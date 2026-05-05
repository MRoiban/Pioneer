//
//  Connection.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Connection.h"
#import "Utils.h"

#import "Moonlight-Swift.h"

#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

#define SDL_MAIN_HANDLED
#import <SDL2/SDL.h>

#include <stdatomic.h>

#include "Limelight.h"
#include "opus_multistream.h"

@implementation Connection {
    SERVER_INFORMATION _serverInfo;
    STREAM_CONFIGURATION _streamConfig;
    CONNECTION_LISTENER_CALLBACKS _clCallbacks;
    DECODER_RENDERER_CALLBACKS _drCallbacks;
    AUDIO_RENDERER_CALLBACKS _arCallbacks;
    char _hostString[256];
    char _appVersionString[32];
    char _gfeVersionString[32];
    char _rtspSessionUrlString[256];
}

static NSLock* initLock;
static OpusMSDecoder* opusDecoder;
static id<ConnectionCallbacks> _callbacks;

#define OUTPUT_BUS 0

static int channelCount;
static float audioVolumeMultiplier = 1.0f;
static NSString *hostAddress;
static BOOL audioDiagnosticsEnabled;
static FILE* decodedPcmDumpFile;
static unsigned long long decodedPcmDumpFramesRemaining;

#define DECODED_PCM_DUMP_SECONDS 30
#define SDL_AUDIO_THROTTLE_FRAMES 20
#define AUDIO_BACKLOG_DROP_THRESHOLD_MS 100

static SDL_AudioDeviceID audioDevice;
static OPUS_MULTISTREAM_CONFIGURATION audioConfig;
static void* audioBuffer;
static int audioFrameSize;
static VideoDecoderRenderer* renderer;

static atomic_ullong audioDecodedPackets;
static atomic_ullong audioDecodeErrors;
static atomic_ullong audioRingDrops;
static atomic_ullong audioOutputUnderruns;
static atomic_ullong audioInvalidFrameCounts;
static atomic_ullong audioClippedSamples;
static atomic_ullong audioThrottleSleeps;
static atomic_int audioMaxQueuedFrames;
static atomic_int audioMaxPendingMs;

void ArCleanup(void);

static int AudioQueuedBuffers(void)
{
    if (audioDevice == 0 || audioFrameSize == 0) {
        return 0;
    }

    return (int)(SDL_GetQueuedAudioSize(audioDevice) / audioFrameSize);
}

static void UpdateAtomicMaxInt(atomic_int* target, int value)
{
    int current = atomic_load_explicit(target, memory_order_relaxed);
    while (value > current &&
           !atomic_compare_exchange_weak_explicit(target, &current, value, memory_order_relaxed, memory_order_relaxed)) {
    }
}

static void LogAudioDiagnosticsIfNeeded(void)
{
    if (!audioDiagnosticsEnabled) {
        return;
    }

    static CFAbsoluteTime lastLogTime;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    if (now - lastLogTime < 5.0) {
        return;
    }
    lastLogTime = now;

    unsigned long long decoded = atomic_exchange_explicit(&audioDecodedPackets, 0, memory_order_relaxed);
    unsigned long long decodeErrors = atomic_exchange_explicit(&audioDecodeErrors, 0, memory_order_relaxed);
    unsigned long long ringDrops = atomic_exchange_explicit(&audioRingDrops, 0, memory_order_relaxed);
    unsigned long long outputUnderruns = atomic_exchange_explicit(&audioOutputUnderruns, 0, memory_order_relaxed);
    unsigned long long invalidFrames = atomic_exchange_explicit(&audioInvalidFrameCounts, 0, memory_order_relaxed);
    unsigned long long clipped = atomic_exchange_explicit(&audioClippedSamples, 0, memory_order_relaxed);
    unsigned long long throttleSleeps = atomic_exchange_explicit(&audioThrottleSleeps, 0, memory_order_relaxed);
    int maxQueued = atomic_exchange_explicit(&audioMaxQueuedFrames, 0, memory_order_relaxed);
    int maxPending = atomic_exchange_explicit(&audioMaxPendingMs, 0, memory_order_relaxed);
    int queued = AudioQueuedBuffers();

    Log(LOG_I, @"Audio client diagnostics: decoded=%llu decodeErrors=%llu backlogDrops=%llu outputUnderruns=%llu invalidFrames=%llu clipped=%llu queued=%d pendingMs=%d maxQueued=%d maxPendingMs=%d throttleSleeps=%llu volume=%.2f",
        decoded,
        decodeErrors,
        ringDrops,
        outputUnderruns,
        invalidFrames,
        clipped,
        queued,
        LiGetPendingAudioDuration(),
        maxQueued,
        maxPending,
        throttleSleeps,
        audioVolumeMultiplier);

    FILE *file = fopen("/tmp/moonlight_audio_diagnostics.log", "a");
    if (file != NULL) {
        fprintf(file,
                "%.3f Audio client diagnostics: decoded=%llu decodeErrors=%llu backlogDrops=%llu outputUnderruns=%llu invalidFrames=%llu clipped=%llu queued=%d pendingMs=%d maxQueued=%d maxPendingMs=%d throttleSleeps=%llu volume=%.2f\n",
                [[NSDate date] timeIntervalSince1970],
                decoded,
                decodeErrors,
                ringDrops,
                outputUnderruns,
                invalidFrames,
                clipped,
                queued,
                LiGetPendingAudioDuration(),
                maxQueued,
                maxPending,
                throttleSleeps,
                audioVolumeMultiplier);
        fclose(file);
    }
}

static short ClampAudioSample(float sample)
{
    if (sample > 32767.0f) {
        atomic_fetch_add_explicit(&audioClippedSamples, 1, memory_order_relaxed);
        return 32767;
    }
    else if (sample < -32768.0f) {
        atomic_fetch_add_explicit(&audioClippedSamples, 1, memory_order_relaxed);
        return -32768;
    }

    return (short)sample;
}

static void CloseDecodedPcmDump(void)
{
    if (decodedPcmDumpFile != NULL) {
        fclose(decodedPcmDumpFile);
        decodedPcmDumpFile = NULL;
    }
}

static void UpdateAudioDiagnosticsEnabled(void)
{
    audioDiagnosticsEnabled = NO;
    if (hostAddress != nil) {
        NSString *uuid = [SettingsClass getHostUUIDFrom:hostAddress];
        if (uuid != nil) {
            audioDiagnosticsEnabled = [SettingsClass audioDiagnosticsEnabledFor:uuid];
        }
    }
    LiSetAudioDiagnosticsEnabled(audioDiagnosticsEnabled);
}

int DrDecoderSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags)
{
    [renderer setupWithVideoFormat:videoFormat frameRate:redrawRate];
    return 0;
}

void DrStart(void)
{
    [renderer start];
}

void DrStop(void)
{
    [renderer stop];

    _callbacks = nil;
    renderer = nil;
}

int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit)
{
    int offset = 0;
    int ret;
    unsigned char* data = (unsigned char*) malloc(decodeUnit->fullLength);
    if (data == NULL) {
        // A frame was lost due to OOM condition
        return DR_NEED_IDR;
    }

    PLENTRY entry = decodeUnit->bufferList;
    while (entry != NULL) {
        // Submit parameter set NALUs directly since no copy is required by the decoder
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            ret = [renderer submitDecodeBuffer:(unsigned char*)entry->data
                                        length:entry->length
                                    bufferType:entry->bufferType
                                     frameType:decodeUnit->frameType
                                           pts:decodeUnit->presentationTimeMs];
            if (ret != DR_OK) {
                free(data);
                return ret;
            }
        }
        else {
            memcpy(&data[offset], entry->data, entry->length);
            offset += entry->length;
        }

        entry = entry->next;
    }

    // This function will take our picture data buffer
    return [renderer submitDecodeBuffer:data
                                 length:offset
                             bufferType:BUFFER_TYPE_PICDATA
                              frameType:decodeUnit->frameType
                                    pts:decodeUnit->presentationTimeMs];
}

int ArInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION originalOpusConfig, void* context, int flags)
{
    int err;
    OPUS_MULTISTREAM_CONFIGURATION opusConfig = *originalOpusConfig;

    if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) {
        Log(LOG_E, @"Failed to initialize SDL audio subsystem: %s\n", SDL_GetError());
        return -1;
    }
    
    channelCount = opusConfig.channelCount;
    CloseDecodedPcmDump();
    decodedPcmDumpFramesRemaining = (unsigned long long)opusConfig.sampleRate * DECODED_PCM_DUMP_SECONDS;

    if (audioDiagnosticsEnabled) {
        decodedPcmDumpFile = fopen("/tmp/moonlight_decoded_audio.pcm", "wb");
        FILE *metadataFile = fopen("/tmp/moonlight_decoded_audio.txt", "w");
        if (metadataFile != NULL) {
            fprintf(metadataFile,
                    "format=s16le\nsampleRate=%d\nchannels=%d\nseconds=%d\nsource=decoded PCM before SDL queue\n",
                    opusConfig.sampleRate,
                    opusConfig.channelCount,
                    DECODED_PCM_DUMP_SECONDS);
            fclose(metadataFile);
        }
        if (decodedPcmDumpFile == NULL) {
            Log(LOG_W, @"Unable to open decoded PCM dump at /tmp/moonlight_decoded_audio.pcm");
        }
        else {
            Log(LOG_I, @"Audio diagnostics enabled. Writing client logs to /tmp/moonlight_audio_diagnostics.log and decoded PCM to /tmp/moonlight_decoded_audio.pcm");
        }
    }
    
    SDL_AudioSpec want, have;
    SDL_zero(want);
    want.freq = opusConfig.sampleRate;
    want.format = AUDIO_S16SYS;
    want.channels = opusConfig.channelCount;
    want.samples = 2048; // ~42ms at 48kHz; old AudioQueue used 80ms — keep enough margin for jitter

    audioDevice = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
    if (audioDevice == 0) {
        Log(LOG_E, @"Failed to open SDL audio device: %s\n", SDL_GetError());
        ArCleanup();
        return -1;
    }

    audioConfig = opusConfig;
    audioFrameSize = opusConfig.samplesPerFrame * sizeof(short) * opusConfig.channelCount;
    audioBuffer = SDL_malloc(audioFrameSize);
    if (audioBuffer == NULL) {
        Log(LOG_E, @"Failed to allocate SDL audio frame buffer");
        ArCleanup();
        return -1;
    }
    
    opusDecoder = opus_multistream_decoder_create(opusConfig.sampleRate,
                                                  opusConfig.channelCount,
                                                  opusConfig.streams,
                                                  opusConfig.coupledStreams,
                                                  opusConfig.mapping,
                                                  &err);
    if (opusDecoder == NULL) {
        Log(LOG_E, @"Failed to create Opus decoder");
        ArCleanup();
        return -1;
    }

    SDL_PauseAudioDevice(audioDevice, 0);
    return 0;
}

void ArCleanup(void)
{
    if (opusDecoder != NULL) {
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
    }
    CloseDecodedPcmDump();

    if (audioDevice != 0) {
        SDL_CloseAudioDevice(audioDevice);
        audioDevice = 0;
    }

    if (audioBuffer != NULL) {
        SDL_free(audioBuffer);
        audioBuffer = NULL;
    }

    audioFrameSize = 0;
    LiSetAudioDiagnosticsEnabled(false);
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
}

void ArDecodeAndPlaySample(char* sampleData, int sampleLength)
{
    int decodeLen;
    
    int pendingMs = LiGetPendingAudioDuration();
    UpdateAtomicMaxInt(&audioMaxPendingMs, pendingMs);

    // Drop only when the decoder queue is far enough behind that preserving every packet would
    // turn a short scheduling stall into sustained audio latency.
    if (pendingMs > AUDIO_BACKLOG_DROP_THRESHOLD_MS) {
        atomic_fetch_add_explicit(&audioRingDrops, 1, memory_order_relaxed);
        LogAudioDiagnosticsIfNeeded();
        return;
    }
    
    decodeLen = opus_multistream_decode(opusDecoder, (unsigned char *)sampleData, sampleLength,
                                        (short*)audioBuffer, audioConfig.samplesPerFrame, 0);
    if (decodeLen > 0) {
        // Apply volume adjustment to each audio sample
        short* buffer = (short*)audioBuffer;
        for (int i = 0; i < decodeLen * channelCount; i++) {
            buffer[i] = ClampAudioSample(buffer[i] * audioVolumeMultiplier);
        }

        if (decodedPcmDumpFile != NULL && decodedPcmDumpFramesRemaining > 0) {
            int framesToWrite = decodeLen;
            if ((unsigned long long)framesToWrite > decodedPcmDumpFramesRemaining) {
                framesToWrite = (int)decodedPcmDumpFramesRemaining;
            }

            fwrite(buffer, channelCount * sizeof(short), framesToWrite, decodedPcmDumpFile);
            decodedPcmDumpFramesRemaining -= framesToWrite;
            if (decodedPcmDumpFramesRemaining == 0) {
                CloseDecodedPcmDump();
                Log(LOG_I, @"Finished decoded PCM dump at /tmp/moonlight_decoded_audio.pcm");
            }
        }
        atomic_fetch_add_explicit(&audioDecodedPackets, 1, memory_order_relaxed);

        int queuedFrames = (audioFrameSize != 0) ? (int)(SDL_GetQueuedAudioSize(audioDevice) / audioFrameSize) : 0;
        UpdateAtomicMaxInt(&audioMaxQueuedFrames, queuedFrames);
        if (queuedFrames > SDL_AUDIO_THROTTLE_FRAMES) {
            atomic_fetch_add_explicit(&audioRingDrops, 1, memory_order_relaxed);
            LogAudioDiagnosticsIfNeeded();
            return;
        }

        if (SDL_QueueAudio(audioDevice, audioBuffer, sizeof(short) * decodeLen * channelCount) < 0) {
            atomic_fetch_add_explicit(&audioOutputUnderruns, 1, memory_order_relaxed);
            Log(LOG_E, @"Failed to queue SDL audio sample: %s\n", SDL_GetError());
        }
    }
    else {
        atomic_fetch_add_explicit(&audioDecodeErrors, 1, memory_order_relaxed);
    }

    LogAudioDiagnosticsIfNeeded();
}

- (void)updateVolume {
    if (hostAddress != nil) {
        NSString *uuid = [SettingsClass getHostUUIDFrom:hostAddress];
        audioVolumeMultiplier = [SettingsClass volumeLevelFor:uuid];
    }
}

void ClStageStarting(int stage)
{
    [_callbacks stageStarting:LiGetStageName(stage)];
}

void ClStageComplete(int stage)
{
    [_callbacks stageComplete:LiGetStageName(stage)];
}

void ClStageFailed(int stage, int errorCode)
{
    [_callbacks stageFailed:LiGetStageName(stage) withError:errorCode];
}

void ClConnectionStarted(void)
{
    [_callbacks connectionStarted];
}

void ClConnectionTerminated(int errorCode)
{
    [_callbacks connectionTerminated: errorCode];
}

void ClLogMessage(const char* format, ...)
{
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    va_end(va);
}

void ClRumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor)
{
    [_callbacks rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

void ClConnectionStatusUpdate(int status)
{
    [_callbacks connectionStatusUpdate:status];
}

void ClCursorState(uint8_t version, uint8_t flags, uint32_t sequence,
                   int32_t x, int32_t y, int32_t clipLeft, int32_t clipTop, int32_t clipRight, int32_t clipBottom,
                   uint16_t width, uint16_t height, uint16_t hotspotX, uint16_t hotspotY,
                   uint32_t cursorHash, const uint8_t* imageData, uint32_t imageByteLength)
{
    [_callbacks cursorStateWithVersion:version flags:flags sequence:sequence x:x y:y
                              clipLeft:clipLeft clipTop:clipTop clipRight:clipRight clipBottom:clipBottom
                                 width:width height:height hotspotX:hotspotX hotspotY:hotspotY
                            cursorHash:cursorHash imageData:imageData imageByteLength:imageByteLength];
}

-(void) terminate
{
    // Interrupt any action blocking LiStartConnection(). This is
    // thread-safe and done outside initLock on purpose, since we
    // won't be able to acquire it if LiStartConnection is in
    // progress.
    LiInterruptConnection();
    
    // We dispatch this async to get out because this can be invoked
    // on a thread inside common and we don't want to deadlock. It also avoids
    // blocking on the caller's thread waiting to acquire initLock.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [initLock lock];
        LiStopConnection();
        [initLock unlock];
    });
}

-(id) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks
{
    self = [super init];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateVolume) name:@"volumeSettingChanged" object:nil];
    
    // Use a lock to ensure that only one thread is initializing
    // or deinitializing a connection at a time.
    if (initLock == nil) {
        initLock = [[NSLock alloc] init];
    }
    
    hostAddress = config.host;
    [self updateVolume];
    UpdateAudioDiagnosticsEnabled();
    
    NSString* connectionHost = [Utils hostFromAddressString:config.host];
    strncpy(_hostString,
            [connectionHost cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_hostString));
    strncpy(_appVersionString,
            [config.appVersion cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_appVersionString));
    if (config.gfeVersion != nil) {
        strncpy(_gfeVersionString,
                [config.gfeVersion cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_gfeVersionString));
    }
    if (config.rtspSessionUrl != nil) {
        strncpy(_rtspSessionUrlString,
                [config.rtspSessionUrl cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_rtspSessionUrlString));
    }

    LiInitializeServerInformation(&_serverInfo);
    _serverInfo.address = _hostString;
    _serverInfo.serverInfoAppVersion = _appVersionString;
    if (config.gfeVersion != nil) {
        _serverInfo.serverInfoGfeVersion = _gfeVersionString;
    }
    if (config.rtspSessionUrl != nil) {
        _serverInfo.rtspSessionUrl = _rtspSessionUrlString;
    }

    renderer = myRenderer;
    [renderer setFramePacingMode:config.framePacing];
    _callbacks = callbacks;

    LiInitializeStreamConfiguration(&_streamConfig);
    _streamConfig.width = config.width;
    _streamConfig.height = config.height;
    _streamConfig.fps = config.frameRate;
    _streamConfig.bitrate = config.bitRate;
    _streamConfig.enableHdr = config.enableHdr;
    _streamConfig.cursorFeedback = config.cursorFeedback;
    _streamConfig.audioConfiguration = config.audioConfiguration;
    _streamConfig.colorSpace = COLORSPACE_REC_709;
    
    // Use some of the HEVC encoding efficiency improvements to
    // reduce bandwidth usage while still gaining some image
    // quality improvement.
    _streamConfig.hevcBitratePercentageMultiplier = 75;
    
    if ([Utils isActiveNetworkVPN]) {
        // Force remote streaming mode when a VPN is connected
        _streamConfig.streamingRemotely = STREAM_CFG_REMOTE;
        _streamConfig.packetSize = 1024;
    }
    else {
        // Detect remote streaming automatically based on the IP address of the target
        _streamConfig.streamingRemotely = STREAM_CFG_AUTO;
        _streamConfig.packetSize = 1392;
    }
    
    // HDR implies HEVC allowed
    if (config.enableHdr) {
        config.allowHevc = YES;
    }

    // On iOS 11, we can use HEVC if the server supports encoding it
    // and this device has hardware decode for it (A9 and later).
    // Additionally, iPhone X had a bug which would cause video
    // to freeze after a few minutes with HEVC prior to iOS 11.3.
    // As a result, we will only use HEVC on iOS 11.3 or later.
    if (@available(iOS 11.3, tvOS 11.3, macOS 10.14, *)) {
        _streamConfig.supportsHevc = config.allowHevc && VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
    }
    
    // HEVC must be supported when HDR is enabled
    assert(!_streamConfig.enableHdr || _streamConfig.supportsHevc);

    memcpy(_streamConfig.remoteInputAesKey, [config.riKey bytes], [config.riKey length]);
    memset(_streamConfig.remoteInputAesIv, 0, 16);
    int riKeyId = htonl(config.riKeyId);
    memcpy(_streamConfig.remoteInputAesIv, &riKeyId, sizeof(riKeyId));

    LiInitializeVideoCallbacks(&_drCallbacks);
    _drCallbacks.setup = DrDecoderSetup;
    _drCallbacks.start = DrStart;
    _drCallbacks.stop = DrStop;

//#if TARGET_OS_IPHONE
    // RFI doesn't work properly with HEVC on iOS 11 with an iPhone SE (at least)
    // It doesnt work on macOS either, tested with Network Link Conditioner.
    _drCallbacks.capabilities = CAPABILITY_PULL_RENDERER | CAPABILITY_SLICES_PER_FRAME(4);
//#endif

    LiInitializeAudioCallbacks(&_arCallbacks);
    _arCallbacks.init = ArInit;
    _arCallbacks.cleanup = ArCleanup;
    _arCallbacks.decodeAndPlaySample = ArDecodeAndPlaySample;
    _arCallbacks.capabilities = CAPABILITY_DIRECT_SUBMIT | CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;

    LiInitializeConnectionCallbacks(&_clCallbacks);
    _clCallbacks.stageStarting = ClStageStarting;
    _clCallbacks.stageComplete = ClStageComplete;
    _clCallbacks.stageFailed = ClStageFailed;
    _clCallbacks.connectionStarted = ClConnectionStarted;
    _clCallbacks.connectionTerminated = ClConnectionTerminated;
    _clCallbacks.logMessage = ClLogMessage;
    _clCallbacks.rumble = ClRumble;
    _clCallbacks.connectionStatusUpdate = ClConnectionStatusUpdate;
    _clCallbacks.cursorState = ClCursorState;

    return self;
}

-(void) main
{
    [initLock lock];
    LiStartConnection(&_serverInfo,
                      &_streamConfig,
                      &_clCallbacks,
                      &_drCallbacks,
                      &_arCallbacks,
                      NULL, 0,
                      NULL, 0);
    [initLock unlock];
}

@end
