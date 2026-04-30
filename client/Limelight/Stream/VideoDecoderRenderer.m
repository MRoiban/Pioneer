//
//  VideoDecoderRenderer.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "VideoDecoderRenderer.h"
#import "RendererLayerContainer.h"

#include "Limelight.h"

@import CoreVideo;
@import Metal;
@import QuartzCore;
@import VideoToolbox;

#define FRAME_START_PREFIX_SIZE 4
#define NALU_START_PREFIX_SIZE 3
#define NAL_LENGTH_PREFIX_SIZE 4

// TODO: Refactor this
int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit);

@interface MetalVideoFrame : NSObject
@property (nonatomic, readonly) CVPixelBufferRef pixelBuffer;
@property (nonatomic, readonly) CFTimeInterval queuedAt;
- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer;
@end

@implementation MetalVideoFrame
- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    self = [super init];
    if (self != nil) {
        _pixelBuffer = CVPixelBufferRetain(pixelBuffer);
        _queuedAt = CACurrentMediaTime();
    }
    return self;
}

- (void)dealloc
{
    if (_pixelBuffer != NULL) {
        CVPixelBufferRelease(_pixelBuffer);
    }
}
@end

@interface VideoDecoderRenderer ()
@property (nonatomic) int frameRate;
- (CMSampleBufferRef)createSampleBufferWithData:(unsigned char *)data length:(int)length frameType:(int)frameType CF_RETURNS_RETAINED;
@end

@implementation VideoDecoderRenderer {
    OSView *_view;
    OSView *_layerContainer;

    AVSampleBufferDisplayLayer *_displayLayer;
    CAMetalLayer *_metalLayer;

    Boolean _waitingForSps, _waitingForPps, _waitingForVps;
    int _videoFormat;

    NSData *_spsData, *_ppsData, *_vpsData;
    CMVideoFormatDescriptionRef _formatDesc;

    CVDisplayLinkRef _displayLink;
    BOOL _wantsDisplayLink;

    BOOL _useMetalRenderer;
    id<MTLDevice> _metalDevice;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    CVMetalTextureCacheRef _textureCache;
    VTDecompressionSessionRef _decompressionSession;
    NSMutableArray<MetalVideoFrame *> *_metalFrameQueue;
    int _configuredFramePacingMode;
    int _effectiveFramePacingMode;
    NSUInteger _decodedFrameCount;
    NSUInteger _presentedFrameCount;
    NSUInteger _droppedFrameCount;
    CFTimeInterval _lastMetricsLogTime;
}

static CGDirectDisplayID getDisplayID(NSScreen* screen)
{
    NSNumber *screenNumber = [screen deviceDescription][@"NSScreenNumber"];
    return [screenNumber unsignedIntValue];
}

static void dispatchSyncOnMain(dispatch_block_t block)
{
    if ([NSThread isMainThread]) {
        block();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static NSString *metalShaderSource(void)
{
    return @"#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VertexOut { float4 position [[position]]; float2 texCoord; };\n"
    "vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {\n"
    "    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };\n"
    "    float2 texCoords[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };\n"
    "    VertexOut out;\n"
    "    out.position = float4(positions[vertexID], 0.0, 1.0);\n"
    "    out.texCoord = texCoords[vertexID];\n"
    "    return out;\n"
    "}\n"
    "fragment float4 fragment_main(VertexOut in [[stage_in]],\n"
    "                              texture2d<float, access::sample> yTexture [[texture(0)]],\n"
    "                              texture2d<float, access::sample> cbcrTexture [[texture(1)]]) {\n"
    "    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);\n"
    "    float y = yTexture.sample(textureSampler, in.texCoord).r;\n"
    "    float2 cbcr = cbcrTexture.sample(textureSampler, in.texCoord).rg;\n"
    "    float yVideo = max((y - (16.0 / 255.0)) * (255.0 / 219.0), 0.0);\n"
    "    float cb = cbcr.x - 0.5;\n"
    "    float cr = cbcr.y - 0.5;\n"
    "    float3 rgb;\n"
    "    rgb.r = yVideo + 1.5748 * cr;\n"
    "    rgb.g = yVideo - 0.1873 * cb - 0.4681 * cr;\n"
    "    rgb.b = yVideo + 1.8556 * cb;\n"
    "    return float4(saturate(rgb), 1.0);\n"
    "}\n";
}

- (id)initWithView:(OSView *)view
{
    self = [super init];

    _view = view;
    _metalFrameQueue = [[NSMutableArray alloc] init];
    _configuredFramePacingMode = MLFramePacingModeAuto;
    _effectiveFramePacingMode = MLFramePacingModeAuto;

    return self;
}

- (void)dealloc
{
    [self stop];
    [self tearDownMetalDecoder];

    if (_formatDesc != nil) {
        CFRelease(_formatDesc);
        _formatDesc = nil;
    }
}

- (void)setFramePacingMode:(int)framePacingMode
{
    _configuredFramePacingMode = framePacingMode;
}

- (double)currentDisplayRefreshRate
{
    if (_displayLink != NULL) {
        double period = CVDisplayLinkGetActualOutputVideoRefreshPeriod(_displayLink);
        if (period > 0) {
            return 1 / period;
        }
    }

    NSScreen *screen = _view.window.screen ?: NSScreen.mainScreen;
    if (@available(macOS 10.15, *)) {
        if (screen.maximumFramesPerSecond > 0) {
            return screen.maximumFramesPerSecond;
        }
    }

    return 60;
}

- (int)effectiveFramePacingModeForRefreshRate:(double)displayRefreshRate
{
    if (_configuredFramePacingMode != MLFramePacingModeAuto) {
        return _configuredFramePacingMode;
    }

    if (self.frameRate <= 30) {
        return MLFramePacingModeLowestLatency;
    }

    if (self.frameRate > displayRefreshRate * 1.05) {
        return MLFramePacingModeLowestLatency;
    }

    return MLFramePacingModeBalanced;
}

- (NSString *)framePacingModeName:(int)framePacingMode
{
    switch (framePacingMode) {
        case MLFramePacingModeLowestLatency:
            return @"Lowest Latency";
        case MLFramePacingModeSmoothest:
            return @"Smoothest";
        case MLFramePacingModeAuto:
            return @"Auto";
        case MLFramePacingModeBalanced:
            return @"Balanced";
        default:
            return @"Auto";
    }
}

- (void)setupWithVideoFormat:(int)videoFormat frameRate:(int)frameRate
{
    _videoFormat = videoFormat;
    self.frameRate = frameRate;

    [self resetCodecState];
    [self tearDownMetalDecoder];
    @synchronized (self) {
        _decodedFrameCount = 0;
        _presentedFrameCount = 0;
        _droppedFrameCount = 0;
        _lastMetricsLogTime = 0;
    }

    _useMetalRenderer = [self shouldUseMetalRendererForVideoFormat:videoFormat];

    if (_useMetalRenderer) {
        if (![self initializeMetalRenderer]) {
            Log(LOG_E, @"Falling back to VideoToolbox AVSampleBufferDisplayLayer renderer");
            _useMetalRenderer = NO;
        }
    }

    if (_useMetalRenderer) {
        Log(LOG_I, @"Using VideoToolbox Metal renderer");
        dispatchSyncOnMain(^{
            [self reinitializeMetalLayer];
        });
    }
    else {
        Log(LOG_I, @"Using VideoToolbox AVSampleBufferDisplayLayer renderer");
        dispatchSyncOnMain(^{
            [self reinitializeDisplayLayer];
        });
    }
}

- (BOOL)shouldUseMetalRendererForVideoFormat:(int)videoFormat
{
#if TARGET_OS_IPHONE
    return NO;
#else
    if (videoFormat & VIDEO_FORMAT_MASK_10BIT) {
        return NO;
    }

    if (!(videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265))) {
        return NO;
    }

    return MTLCreateSystemDefaultDevice() != nil;
#endif
}

- (BOOL)initializeMetalRenderer
{
    _metalDevice = MTLCreateSystemDefaultDevice();
    if (_metalDevice == nil) {
        Log(LOG_E, @"Failed to create Metal device");
        return NO;
    }

    _commandQueue = [_metalDevice newCommandQueue];
    if (_commandQueue == nil) {
        Log(LOG_E, @"Failed to create Metal command queue");
        return NO;
    }

    NSError *libraryError = nil;
    id<MTLLibrary> library = [_metalDevice newLibraryWithSource:metalShaderSource() options:nil error:&libraryError];
    if (library == nil) {
        Log(LOG_E, @"Failed to compile Metal library: %@", libraryError);
        return NO;
    }

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
    if (vertexFunction == nil || fragmentFunction == nil) {
        Log(LOG_E, @"Failed to load Metal shader functions");
        return NO;
    }

    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    NSError *pipelineError = nil;
    _pipelineState = [_metalDevice newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&pipelineError];
    if (_pipelineState == nil) {
        Log(LOG_E, @"Failed to create Metal pipeline: %@", pipelineError);
        return NO;
    }

    CVReturn status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, _metalDevice, nil, &_textureCache);
    if (status != kCVReturnSuccess) {
        Log(LOG_E, @"Failed to create CVMetalTextureCache: %d", status);
        return NO;
    }

    return YES;
}

- (void)resetCodecState
{
    _waitingForSps = true;
    _spsData = nil;
    _waitingForPps = true;
    _ppsData = nil;
    _waitingForVps = true;
    _vpsData = nil;

    if (_formatDesc != nil) {
        CFRelease(_formatDesc);
        _formatDesc = nil;
    }
}

- (void)removeLayerContainer
{
    [_layerContainer removeFromSuperview];
    _layerContainer = nil;
    _displayLayer = nil;
    _metalLayer = nil;
}

- (void)reinitializeDisplayLayer
{
    [self removeLayerContainer];

    RendererLayerContainer *container = [[RendererLayerContainer alloc] init];
    container.frame = _view.bounds;
    container.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [_view addSubview:container];

    _layerContainer = container;
    _displayLayer = (AVSampleBufferDisplayLayer *)container.layer;
    _displayLayer.backgroundColor = [OSColor blackColor].CGColor;
}

- (void)reinitializeMetalLayer
{
    [self removeLayerContainer];

    OSView *container = [[OSView alloc] initWithFrame:_view.bounds];
    container.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [container setWantsLayer:YES];

    CAMetalLayer *metalLayer = [CAMetalLayer layer];
    metalLayer.device = _metalDevice;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.framebufferOnly = YES;
    metalLayer.backgroundColor = [OSColor blackColor].CGColor;
    metalLayer.contentsGravity = kCAGravityResizeAspect;
    container.layer = metalLayer;

    [_view addSubview:container];

    _layerContainer = container;
    _metalLayer = metalLayer;
    [self updateMetalDrawableSize];
}

- (void)updateMetalDrawableSize
{
    if (_metalLayer == nil) {
        return;
    }

    NSScreen *screen = _view.window.screen ?: NSScreen.mainScreen;
    CGFloat scale = screen.backingScaleFactor ?: 1.0;
    CGSize boundsSize = _layerContainer.bounds.size;
    _metalLayer.drawableSize = CGSizeMake(boundsSize.width * scale, boundsSize.height * scale);
}

- (void)start
{
    if (_wantsDisplayLink || _displayLink != NULL) {
        return;
    }

    _wantsDisplayLink = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_wantsDisplayLink || self->_displayLink != NULL) {
            return;
        }

        CGDirectDisplayID displayId = getDisplayID(self->_view.window.screen);
        CVReturn status = CVDisplayLinkCreateWithCGDisplay(displayId, &self->_displayLink);
        if (status != kCVReturnSuccess) {
            Log(LOG_E, @"Failed to create CVDisplayLink: %d", status);
            self->_displayLink = NULL;
            self->_wantsDisplayLink = NO;
            return;
        }

        status = CVDisplayLinkSetOutputCallback(self->_displayLink, displayLinkCallback, (__bridge void * _Nullable)(self));
        if (status != kCVReturnSuccess) {
            Log(LOG_E, @"CVDisplayLinkSetOutputCallback() failed: %d", status);
            CVDisplayLinkRelease(self->_displayLink);
            self->_displayLink = NULL;
            self->_wantsDisplayLink = NO;
            return;
        }

        if (!self->_wantsDisplayLink) {
            CVDisplayLinkRelease(self->_displayLink);
            self->_displayLink = NULL;
            return;
        }

        status = CVDisplayLinkStart(self->_displayLink);
        if (status != kCVReturnSuccess) {
            Log(LOG_E, @"CVDisplayLinkStart() failed: %d", status);
            CVDisplayLinkRelease(self->_displayLink);
            self->_displayLink = NULL;
            self->_wantsDisplayLink = NO;
            return;
        }

        double displayRefreshRate = [self currentDisplayRefreshRate];
        self->_effectiveFramePacingMode = [self effectiveFramePacingModeForRefreshRate:displayRefreshRate];
        if (self->_configuredFramePacingMode == MLFramePacingModeAuto) {
            Log(LOG_I, @"Frame pacing: Auto -> %@ (%d FPS stream, %.0f Hz display)",
                [self framePacingModeName:self->_effectiveFramePacingMode],
                self.frameRate,
                displayRefreshRate);
        }
        else {
            Log(LOG_I, @"Frame pacing: %@ (%d FPS stream, %.0f Hz display)",
                [self framePacingModeName:self->_effectiveFramePacingMode],
                self.frameRate,
                displayRefreshRate);
        }
    });
}

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp *inNow,
                                    const CVTimeStamp *inOutputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags *flagsOut,
                                    void *displayLinkContext)
{
    @autoreleasepool {
        VideoDecoderRenderer *self = (__bridge VideoDecoderRenderer *)displayLinkContext;

        VIDEO_FRAME_HANDLE handle;
        PDECODE_UNIT du;
        double displayRefreshRate = [self currentDisplayRefreshRate];
        int pacingMode = [self effectiveFramePacingModeForRefreshRate:displayRefreshRate];
        self->_effectiveFramePacingMode = pacingMode;

        while (LiPollNextVideoFrame(&handle, &du)) {
            LiCompleteVideoFrame(handle, DrSubmitDecodeUnit(du));

            if (pacingMode == MLFramePacingModeSmoothest) {
                if (LiGetPendingVideoFrames() <= 2) {
                    break;
                }
            }
            else if (pacingMode == MLFramePacingModeBalanced) {
                if (displayRefreshRate >= self.frameRate * 0.9f && LiGetPendingVideoFrames() == 1) {
                    break;
                }
            }
        }

        if (self->_useMetalRenderer) {
            [self renderNextMetalFrameForPacingMode:pacingMode];
        }

        [self logPacingMetricsIfNeeded];
    }

    return kCVReturnSuccess;
}

- (void)stop
{
    _wantsDisplayLink = NO;

    if (_displayLink != NULL) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }

    [self tearDownMetalDecoder];
}

- (void)tearDownMetalDecoder
{
    if (_decompressionSession != NULL) {
        VTDecompressionSessionWaitForAsynchronousFrames(_decompressionSession);
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = NULL;
    }

    @synchronized (self) {
        [_metalFrameQueue removeAllObjects];
    }

    if (_textureCache != NULL) {
        CVMetalTextureCacheFlush(_textureCache, 0);
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
}

- (void)logPacingMetricsIfNeeded
{
    CFTimeInterval now = CACurrentMediaTime();
    if (_lastMetricsLogTime != 0 && now - _lastMetricsLogTime < 5) {
        return;
    }

    _lastMetricsLogTime = now;

    @synchronized (self) {
        CFTimeInterval queueLatencyMs = 0;
        if (_metalFrameQueue.count > 0) {
            queueLatencyMs = (now - _metalFrameQueue.firstObject.queuedAt) * 1000;
        }

        Log(LOG_I, @"Frame pacing metrics: mode=%@ decoded=%lu presented=%lu dropped=%lu queue=%lu latency=%.1f ms",
            [self framePacingModeName:_effectiveFramePacingMode],
            (unsigned long)_decodedFrameCount,
            (unsigned long)_presentedFrameCount,
            (unsigned long)_droppedFrameCount,
            (unsigned long)_metalFrameQueue.count,
            queueLatencyMs);
    }
}

- (void)switchToLegacyRendererWithReason:(NSString *)reason
{
    Log(LOG_E, @"Metal renderer failed (%@). Falling back to VideoToolbox AVSampleBufferDisplayLayer renderer", reason);

    _useMetalRenderer = NO;
    [self tearDownMetalDecoder];

    dispatchSyncOnMain(^{
        [self reinitializeDisplayLayer];
    });

    [self resetCodecState];
}

- (Boolean)readyForPictureData
{
    if (_videoFormat & VIDEO_FORMAT_MASK_H264) {
        return !_waitingForSps && !_waitingForPps;
    }
    else {
        return !_waitingForVps && !_waitingForSps && !_waitingForPps;
    }
}

- (OSStatus)createFormatDescriptionIfReady
{
    if (![self readyForPictureData]) {
        return noErr;
    }

    if (_formatDesc != nil) {
        CFRelease(_formatDesc);
        _formatDesc = nil;
    }

    OSStatus status;
    if (_videoFormat & VIDEO_FORMAT_MASK_H264) {
        const uint8_t* const parameterSetPointers[] = { [_spsData bytes], [_ppsData bytes] };
        const size_t parameterSetSizes[] = { [_spsData length], [_ppsData length] };

        Log(LOG_I, @"Constructing new H264 format description");
        status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                     2,
                                                                     parameterSetPointers,
                                                                     parameterSetSizes,
                                                                     NAL_LENGTH_PREFIX_SIZE,
                                                                     &_formatDesc);
    }
    else {
        const uint8_t* const parameterSetPointers[] = { [_vpsData bytes], [_spsData bytes], [_ppsData bytes] };
        const size_t parameterSetSizes[] = { [_vpsData length], [_spsData length], [_ppsData length] };

        Log(LOG_I, @"Constructing new HEVC format description");
        status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                     3,
                                                                     parameterSetPointers,
                                                                     parameterSetSizes,
                                                                     NAL_LENGTH_PREFIX_SIZE,
                                                                     nil,
                                                                     &_formatDesc);
    }

    if (status != noErr) {
        Log(LOG_E, @"Failed to create video format description: %d", (int)status);
        _formatDesc = NULL;
    }
    else if (_decompressionSession != NULL) {
        VTDecompressionSessionWaitForAsynchronousFrames(_decompressionSession);
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = NULL;
    }

    return status;
}

- (void)updateBufferForRange:(CMBlockBufferRef)frameBuffer dataBlock:(CMBlockBufferRef)dataBuffer offset:(int)offset length:(int)nalLength
{
    OSStatus status;
    size_t oldOffset = CMBlockBufferGetDataLength(frameBuffer);

    status = CMBlockBufferAppendMemoryBlock(frameBuffer, NULL,
                                            NAL_LENGTH_PREFIX_SIZE,
                                            kCFAllocatorDefault, NULL, 0,
                                            NAL_LENGTH_PREFIX_SIZE, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendMemoryBlock failed: %d", (int)status);
        return;
    }

    const int dataLength = nalLength - NALU_START_PREFIX_SIZE;
    const uint8_t lengthBytes[] = {(uint8_t)(dataLength >> 24), (uint8_t)(dataLength >> 16),
        (uint8_t)(dataLength >> 8), (uint8_t)dataLength};
    status = CMBlockBufferReplaceDataBytes(lengthBytes, frameBuffer,
                                           oldOffset, NAL_LENGTH_PREFIX_SIZE);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferReplaceDataBytes failed: %d", (int)status);
        return;
    }

    status = CMBlockBufferAppendBufferReference(frameBuffer, dataBuffer, offset + NALU_START_PREFIX_SIZE, dataLength, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
        return;
    }
}

- (CMSampleBufferRef)createSampleBufferWithData:(unsigned char *)data length:(int)length frameType:(int)frameType
{
    OSStatus status;
    CMBlockBufferRef frameBlockBuffer;
    CMBlockBufferRef dataBlockBuffer;

    status = CMBlockBufferCreateWithMemoryBlock(NULL, data, length, kCFAllocatorDefault, NULL, 0, length, 0, &dataBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateWithMemoryBlock failed: %d", (int)status);
        free(data);
        return NULL;
    }

    status = CMBlockBufferCreateEmpty(NULL, 0, 0, &frameBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateEmpty failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        return NULL;
    }

    int lastOffset = -1;
    for (int i = 0; i < length - FRAME_START_PREFIX_SIZE; i++) {
        if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
            if (lastOffset != -1) {
                [self updateBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:i - lastOffset];
            }

            lastOffset = i;
        }
    }

    if (lastOffset != -1) {
        [self updateBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:length - lastOffset];
    }

    CMSampleBufferRef sampleBuffer;
    status = CMSampleBufferCreate(kCFAllocatorDefault,
                                  frameBlockBuffer,
                                  true, NULL,
                                  NULL, _formatDesc, 1, 0,
                                  NULL, 0, NULL,
                                  &sampleBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMSampleBufferCreate failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        CFRelease(frameBlockBuffer);
        return NULL;
    }

    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);

    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_IsDependedOnByOthers, kCFBooleanTrue);

    if (frameType == FRAME_TYPE_PFRAME) {
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanTrue);
    }
    else {
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanFalse);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanFalse);
    }

    CFRelease(dataBlockBuffer);
    CFRelease(frameBlockBuffer);
    return sampleBuffer;
}

static void decompressionOutputCallback(void *decompressionOutputRefCon,
                                        void *sourceFrameRefCon,
                                        OSStatus status,
                                        VTDecodeInfoFlags infoFlags,
                                        CVImageBufferRef imageBuffer,
                                        CMTime presentationTimeStamp,
                                        CMTime presentationDuration)
{
    VideoDecoderRenderer *self = (__bridge VideoDecoderRenderer *)decompressionOutputRefCon;

    if (status != noErr || imageBuffer == NULL) {
        Log(LOG_E, @"VTDecompressionSession output failed: %d", (int)status);
        return;
    }

    @synchronized (self) {
        self->_decodedFrameCount++;

        MetalVideoFrame *frame = [[MetalVideoFrame alloc] initWithPixelBuffer:(CVPixelBufferRef)imageBuffer];
        int pacingMode = self->_effectiveFramePacingMode;
        NSUInteger queueLimit = pacingMode == MLFramePacingModeSmoothest ? 3 : (pacingMode == MLFramePacingModeBalanced ? 2 : 1);

        [self->_metalFrameQueue addObject:frame];

        while (self->_metalFrameQueue.count > queueLimit) {
            [self->_metalFrameQueue removeObjectAtIndex:0];
            self->_droppedFrameCount++;
        }
    }
}

- (BOOL)ensureDecompressionSession
{
    if (_decompressionSession != NULL) {
        return YES;
    }

    NSDictionary *pixelBufferAttributes = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
    };

    VTDecompressionOutputCallbackRecord callbackRecord;
    callbackRecord.decompressionOutputCallback = decompressionOutputCallback;
    callbackRecord.decompressionOutputRefCon = (__bridge void *)self;

    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                   _formatDesc,
                                                   NULL,
                                                   (__bridge CFDictionaryRef)pixelBufferAttributes,
                                                   &callbackRecord,
                                                   &_decompressionSession);
    if (status != noErr) {
        Log(LOG_E, @"VTDecompressionSessionCreate failed: %d", (int)status);
        return NO;
    }

    VTSessionSetProperty(_decompressionSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(_decompressionSession, kVTDecompressionPropertyKey_MaximizePowerEfficiency, kCFBooleanFalse);
    if (@available(macOS 11.3, *)) {
        VTSessionSetProperty(_decompressionSession,
                             kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder,
                             kCFBooleanTrue);
    }
    return YES;
}

- (int)submitMetalDecodeBuffer:(unsigned char *)data length:(int)length frameType:(int)frameType
{
    if (![self ensureDecompressionSession]) {
        [self switchToLegacyRendererWithReason:@"decompression session creation failed"];
        free(data);
        return DR_NEED_IDR;
    }

    CMSampleBufferRef sampleBuffer = [self createSampleBufferWithData:data length:length frameType:frameType];
    if (sampleBuffer == NULL) {
        return DR_NEED_IDR;
    }

    VTDecodeFrameFlags decodeFlags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags infoFlags = 0;
    OSStatus status = VTDecompressionSessionDecodeFrame(_decompressionSession,
                                                        sampleBuffer,
                                                        decodeFlags,
                                                        NULL,
                                                        &infoFlags);
    CFRelease(sampleBuffer);

    if (status != noErr) {
        Log(LOG_E, @"VTDecompressionSessionDecodeFrame failed: %d", (int)status);
        [self switchToLegacyRendererWithReason:@"decompression failed"];
        return DR_NEED_IDR;
    }

    return DR_OK;
}

- (void)renderNextMetalFrameForPacingMode:(int)pacingMode
{
    MetalVideoFrame *frame = nil;
    @synchronized (self) {
        if (_metalFrameQueue.count > 0) {
            if (pacingMode == MLFramePacingModeLowestLatency) {
                while (_metalFrameQueue.count > 1) {
                    [_metalFrameQueue removeObjectAtIndex:0];
                    _droppedFrameCount++;
                }
            }

            frame = _metalFrameQueue.firstObject;
            [_metalFrameQueue removeObjectAtIndex:0];
        }
    }

    if (frame == nil) {
        return;
    }

    CVPixelBufferRef pixelBuffer = frame.pixelBuffer;

    dispatchSyncOnMain(^{
        [self updateMetalDrawableSize];
    });

    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);

    CVMetalTextureRef yTextureRef = NULL;
    CVMetalTextureRef cbcrTextureRef = NULL;

    CVReturn status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                _textureCache,
                                                                pixelBuffer,
                                                                nil,
                                                                MTLPixelFormatR8Unorm,
                                                                width,
                                                                height,
                                                                0,
                                                                &yTextureRef);
    if (status != kCVReturnSuccess) {
        Log(LOG_E, @"Failed to create Metal Y texture: %d", status);
        [self switchToLegacyRendererWithReason:@"Y texture creation failed"];
        return;
    }

    status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _textureCache,
                                                       pixelBuffer,
                                                       nil,
                                                       MTLPixelFormatRG8Unorm,
                                                       width / 2,
                                                       height / 2,
                                                       1,
                                                       &cbcrTextureRef);
    if (status != kCVReturnSuccess) {
        Log(LOG_E, @"Failed to create Metal CbCr texture: %d", status);
        CFRelease(yTextureRef);
        [self switchToLegacyRendererWithReason:@"CbCr texture creation failed"];
        return;
    }

    id<MTLTexture> yTexture = CVMetalTextureGetTexture(yTextureRef);
    id<MTLTexture> cbcrTexture = CVMetalTextureGetTexture(cbcrTextureRef);
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];

    if (yTexture == nil || cbcrTexture == nil || drawable == nil) {
        Log(LOG_E, @"Failed to prepare Metal draw");
        CFRelease(cbcrTextureRef);
        CFRelease(yTextureRef);
        [self switchToLegacyRendererWithReason:@"draw preparation failed"];
        return;
    }

    MTLRenderPassDescriptor *passDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    passDescriptor.colorAttachments[0].texture = drawable.texture;
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    if (commandBuffer == nil || encoder == nil) {
        Log(LOG_E, @"Failed to create Metal command encoder");
        CFRelease(cbcrTextureRef);
        CFRelease(yTextureRef);
        [self switchToLegacyRendererWithReason:@"command encoding failed"];
        return;
    }

    [encoder setRenderPipelineState:_pipelineState];
    [encoder setFragmentTexture:yTexture atIndex:0];
    [encoder setFragmentTexture:cbcrTexture atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];

    CFRelease(cbcrTextureRef);
    CFRelease(yTextureRef);
    @synchronized (self) {
        _presentedFrameCount++;
    }
}

- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType frameType:(int)frameType pts:(unsigned int)pts
{
    if (bufferType != BUFFER_TYPE_PICDATA) {
        if (bufferType == BUFFER_TYPE_VPS) {
            Log(LOG_I, @"Got VPS");
            _vpsData = [NSData dataWithBytes:&data[FRAME_START_PREFIX_SIZE] length:length - FRAME_START_PREFIX_SIZE];
            _waitingForVps = false;
            _waitingForSps = true;
        }
        else if (bufferType == BUFFER_TYPE_SPS) {
            Log(LOG_I, @"Got SPS");
            _spsData = [NSData dataWithBytes:&data[FRAME_START_PREFIX_SIZE] length:length - FRAME_START_PREFIX_SIZE];
            _waitingForSps = false;
            _waitingForPps = true;
        }
        else if (bufferType == BUFFER_TYPE_PPS) {
            Log(LOG_I, @"Got PPS");
            _ppsData = [NSData dataWithBytes:&data[FRAME_START_PREFIX_SIZE] length:length - FRAME_START_PREFIX_SIZE];
            _waitingForPps = false;
        }

        return [self createFormatDescriptionIfReady] == noErr ? DR_OK : DR_NEED_IDR;
    }

    if (_formatDesc == NULL) {
        free(data);
        return DR_NEED_IDR;
    }

    if (_useMetalRenderer) {
        return [self submitMetalDecodeBuffer:data length:length frameType:frameType];
    }

    if (_displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        Log(LOG_E, @"Display layer rendering failed: %@", _displayLayer.error);

        dispatchSyncOnMain(^{
            [self reinitializeDisplayLayer];
        });

        free(data);
        return DR_NEED_IDR;
    }

    CMSampleBufferRef sampleBuffer = [self createSampleBufferWithData:data length:length frameType:frameType];
    if (sampleBuffer == NULL) {
        return DR_NEED_IDR;
    }

    if (_effectiveFramePacingMode == MLFramePacingModeLowestLatency) {
        [_displayLayer flush];
        @synchronized (self) {
            _droppedFrameCount++;
        }
    }

    [_displayLayer enqueueSampleBuffer:sampleBuffer];
    CFRelease(sampleBuffer);
    @synchronized (self) {
        _decodedFrameCount++;
        _presentedFrameCount++;
    }

    return DR_OK;
}

@end
