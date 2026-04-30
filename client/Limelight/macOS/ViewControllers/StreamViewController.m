//
//  StreamViewController.m
//  Moonlight for macOS
//
//  Created by Michael Kenny on 25/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import "StreamViewController.h"
#import "StreamViewMac.h"
#import "AppsViewController.h"
#import "NSWindow+Moonlight.h"
#import "AlertPresenter.h"

#import "Connection.h"
#import "StreamConfiguration.h"
#import "DataManager.h"
#import "ControllerSupport.h"
#import "StreamManager.h"
#import "VideoDecoderRenderer.h"
#import "HIDSupport.h"
#import "AWDLDisabler.h"

#import "Moonlight-Swift.h"

#include "Limelight.h"

@import VideoToolbox;
@import CoreVideo;

#import <IOKit/pwr_mgt/IOPMLib.h>
#import <Carbon/Carbon.h>

@interface StreamViewController () <ConnectionCallbacks, KeyboardNotifiableDelegate, InputPresenceDelegate>

@property (nonatomic, strong) ControllerSupport *controllerSupport;
@property (nonatomic, strong) HIDSupport *hidSupport;
@property (nonatomic) BOOL useSystemControllerDriver;
@property (nonatomic, strong) StreamManager *streamMan;
@property (nonatomic, readonly) StreamViewMac *streamView;
@property (nonatomic, strong) id windowDidExitFullScreenNotification;
@property (nonatomic, strong) id windowDidEnterFullScreenNotification;
@property (nonatomic, strong) id windowDidResignKeyNotification;
@property (nonatomic, strong) id windowDidBecomeKeyNotification;
@property (nonatomic, strong) id windowWillCloseNotification;
@property (nonatomic) int cursorHiddenCounter;
@property (nonatomic) BOOL awdlDisablerStarted;
@property (nonatomic) BOOL parsecMouseMode;
@property (nonatomic) BOOL parsecRelativeMouseMode;
@property (nonatomic) BOOL parsecManualMouseOverride;
@property (nonatomic) NSInteger parsecMouseShortcutKeyCode;
@property (nonatomic) NSUInteger parsecMouseShortcutModifierFlags;
@property (nonatomic) BOOL parsecCursorFeedbackReceived;
@property (nonatomic) BOOL parsecCursorImageReceived;
@property (nonatomic) CFAbsoluteTime parsecLastLocalMoveTime;
@property (nonatomic) NSPoint parsecLastLocalCursorPoint;
@property (nonatomic) CVDisplayLinkRef parsecCursorDisplayLink;
@property (nonatomic) dispatch_queue_t parsecPositionQueue;
@property (nonatomic) dispatch_source_t parsecPositionTimer;
@property (atomic) CGFloat parsecViewScreenOriginX;
@property (atomic) CGFloat parsecViewScreenOriginY;
@property (atomic) CGFloat parsecViewWidth;
@property (atomic) CGFloat parsecViewHeight;
@property (atomic) short parsecLastSentX;
@property (atomic) short parsecLastSentY;

@property (nonatomic) IOPMAssertionID powerAssertionID;

@end

@implementation StreamViewController

#pragma mark - Lifecycle

- (BOOL)useSystemControllerDriver {
    return [SettingsClass controllerDriverFor:self.app.host.uuid] == 1;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.cursorHiddenCounter = 0;
    
    [self prepareForStreaming];
    
    __weak typeof(self) weakSelf = self;

    self.windowDidExitFullScreenNotification = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidExitFullScreenNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if ([weakSelf isOurWindowTheWindowInNotiifcation:note]) {
            if ([weakSelf.view.window isKeyWindow]) {
                [weakSelf uncaptureMouse];
                [weakSelf captureMouse];
            }
        }
    }];

    self.windowDidEnterFullScreenNotification = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidEnterFullScreenNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if ([weakSelf isOurWindowTheWindowInNotiifcation:note]) {
            if ([weakSelf isWindowInCurrentSpace]) {
                if ([weakSelf isWindowFullscreen]) {
                    if ([weakSelf.view.window isKeyWindow]) {
                        [weakSelf uncaptureMouse];
                        [weakSelf captureMouse];
                    }
                }
            }
        }
    }];
    
    self.windowDidResignKeyNotification = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidResignKeyNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if ([weakSelf isOurWindowTheWindowInNotiifcation:note]) {
            weakSelf.parsecManualMouseOverride = NO;
            if (![weakSelf isWindowInCurrentSpace] || ![weakSelf isWindowFullscreen]) {
                [weakSelf uncaptureMouse];
            }
        }
    }];
    self.windowDidBecomeKeyNotification = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if ([weakSelf isOurWindowTheWindowInNotiifcation:note]) {
            if ([weakSelf isWindowInCurrentSpace]) {
                if ([weakSelf isWindowFullscreen]) {
                    if ([weakSelf.view.window isKeyWindow]) {
                        [weakSelf uncaptureMouse];
                        [weakSelf captureMouse];
                    }
                }
            }
        } else {
            [weakSelf uncaptureMouse];
        }
    }];
    
    self.windowWillCloseNotification = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if ([weakSelf isOurWindowTheWindowInNotiifcation:note]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (weakSelf.useSystemControllerDriver) {
                    [weakSelf.controllerSupport cleanup];
                }
                [weakSelf stopAWDLDisablerIfNeeded];
                [weakSelf.streamMan stopStream];
            });
        }
    }];
    
}

- (void)viewDidAppear {
    [super viewDidAppear];
    
    self.streamView.keyboardNotifiable = self;
    self.streamView.appName = self.app.name;
    self.streamView.statusText = @"Starting";
    self.view.window.tabbingMode = NSWindowTabbingModeDisallowed;
    [self.view.window makeFirstResponder:self];
    
    self.view.window.contentAspectRatio = NSMakeSize([self.class getResolution].width, [self.class getResolution].height);
    self.view.window.frameAutosaveName = @"Stream Window";
    [self.view.window moonlight_centerWindowOnFirstRunWithSize:CGSizeMake(1008, 595)];
    
    self.view.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.windowDidExitFullScreenNotification];
    [[NSNotificationCenter defaultCenter] removeObserver:self.windowDidEnterFullScreenNotification];
    [[NSNotificationCenter defaultCenter] removeObserver:self.windowDidResignKeyNotification];
    [[NSNotificationCenter defaultCenter] removeObserver:self.windowDidBecomeKeyNotification];
    [[NSNotificationCenter defaultCenter] removeObserver:self.windowWillCloseNotification];

    [self stopParsecCursorDisplayLink];
    [self stopParsecPositionSender];
    [self stopAWDLDisablerIfNeeded];
    [self.hidSupport tearDownHidManager];
    self.hidSupport = nil;
}

static CVReturn parsecCursorDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                                const CVTimeStamp *now,
                                                const CVTimeStamp *outputTime,
                                                CVOptionFlags flagsIn,
                                                CVOptionFlags *flagsOut,
                                                void *context) {
    StreamViewController *vc = (__bridge StreamViewController *)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc tickParsecCursorOverlay];
    });
    return kCVReturnSuccess;
}

- (void)startParsecCursorDisplayLink {
    if (self.parsecCursorDisplayLink != NULL) {
        return;
    }
    CVDisplayLinkRef link = NULL;
    if (CVDisplayLinkCreateWithActiveCGDisplays(&link) != kCVReturnSuccess || link == NULL) {
        return;
    }
    CVDisplayLinkSetOutputCallback(link, parsecCursorDisplayLinkCallback, (__bridge void *)self);
    CVDisplayLinkStart(link);
    self.parsecCursorDisplayLink = link;
}

- (void)stopParsecCursorDisplayLink {
    if (self.parsecCursorDisplayLink == NULL) {
        return;
    }
    CVDisplayLinkStop(self.parsecCursorDisplayLink);
    CVDisplayLinkRelease(self.parsecCursorDisplayLink);
    self.parsecCursorDisplayLink = NULL;
}

- (void)tickParsecCursorOverlay {
    if (!self.parsecMouseMode || self.parsecRelativeMouseMode || !self.hidSupport.shouldSendInputEvents) {
        return;
    }
    NSWindow *window = self.view.window;
    if (window == nil) {
        return;
    }

    NSRect viewInWindow = [self.view convertRect:self.view.bounds toView:nil];
    NSRect viewInScreen = [window convertRectToScreen:viewInWindow];
    self.parsecViewScreenOriginX = NSMinX(viewInScreen);
    self.parsecViewScreenOriginY = NSMinY(viewInScreen);
    self.parsecViewWidth = MAX(1, self.view.bounds.size.width);
    self.parsecViewHeight = MAX(1, self.view.bounds.size.height);

    NSPoint windowPoint = window.mouseLocationOutsideOfEventStream;
    NSPoint viewPoint = [self.view convertPoint:windowPoint fromView:nil];
    if (!NSPointInRect(viewPoint, self.view.bounds)) {
        return;
    }
    CGFloat clampedX = MAX(0, MIN(self.parsecViewWidth, viewPoint.x));
    CGFloat clampedY = MAX(0, MIN(self.parsecViewHeight, viewPoint.y));
    NSPoint overlayPoint = NSMakePoint(clampedX, clampedY);
    if (NSEqualPoints(overlayPoint, self.parsecLastLocalCursorPoint)) {
        return;
    }
    self.parsecLastLocalCursorPoint = overlayPoint;
    self.parsecLastLocalMoveTime = CFAbsoluteTimeGetCurrent();
    [self.streamView moveHostCursorToPoint:overlayPoint];
}

- (void)startParsecPositionSender {
    if (self.parsecPositionTimer != nil) {
        return;
    }
    if (self.parsecPositionQueue == nil) {
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                              QOS_CLASS_USER_INTERACTIVE, 0);
        self.parsecPositionQueue = dispatch_queue_create("com.moonlight-stream.parsecPositionQueue", attr);
    }
    self.parsecPositionTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.parsecPositionQueue);
    uint64_t intervalNs = 2 * NSEC_PER_MSEC; // ~500Hz
    dispatch_source_set_timer(self.parsecPositionTimer,
                              dispatch_time(DISPATCH_TIME_NOW, intervalNs),
                              intervalNs,
                              NSEC_PER_MSEC / 4);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.parsecPositionTimer, ^{
        [weakSelf sendParsecPositionTick];
    });
    dispatch_resume(self.parsecPositionTimer);
}

- (void)stopParsecPositionSender {
    if (self.parsecPositionTimer != nil) {
        dispatch_source_cancel(self.parsecPositionTimer);
        self.parsecPositionTimer = nil;
    }
    self.parsecLastSentX = -1;
    self.parsecLastSentY = -1;
}

- (void)sendParsecPositionTick {
    if (!self.hidSupport.shouldSendInputEvents) {
        return;
    }
    CGFloat width = self.parsecViewWidth;
    CGFloat height = self.parsecViewHeight;
    if (width <= 0 || height <= 0) {
        return;
    }
    CGFloat originX = self.parsecViewScreenOriginX;
    CGFloat originY = self.parsecViewScreenOriginY;
    CGPoint mouse = [NSEvent mouseLocation];
    CGFloat localX = mouse.x - originX;
    CGFloat localY = (originY + height) - mouse.y;
    if (localX < 0 || localY < 0 || localX > width || localY > height) {
        return;
    }
    short referenceWidth = (short)MAX(1, MIN(INT16_MAX, lround(width)));
    short referenceHeight = (short)MAX(1, MIN(INT16_MAX, lround(height)));
    short x = (short)MAX(0, MIN(referenceWidth, lround(localX)));
    short y = (short)MAX(0, MIN(referenceHeight, lround(localY)));
    if (x == self.parsecLastSentX && y == self.parsecLastSentY) {
        return;
    }
    self.parsecLastSentX = x;
    self.parsecLastSentY = y;
    LiSendMousePositionEvent(x, y, referenceWidth, referenceHeight);
}

- (void)flagsChanged:(NSEvent *)event {
    [self.hidSupport flagsChanged:event];
    
    if (event.modifierFlags == 786721) {
        [self.hidSupport releaseAllModifierKeys];
        [self uncaptureMouse];
    }
}

- (void)keyDown:(NSEvent *)event {
    if ([self handleParsecMouseOverrideHotkey:event]) {
        return;
    }
    if ([self handleStatsOverlayHotkey:event]) {
        return;
    }

    [self.hidSupport keyDown:event];
}

- (void)keyUp:(NSEvent *)event {
    [self.hidSupport keyUp:event];
}


- (void)mouseDown:(NSEvent *)event {
    [self.hidSupport mouseDown:event withButton:BUTTON_LEFT];
    [self captureMouse];
}

- (void)mouseUp:(NSEvent *)event {
    [self.hidSupport mouseUp:event withButton:BUTTON_LEFT];
}

- (void)rightMouseDown:(NSEvent *)event {
    [self.hidSupport mouseDown:event withButton:BUTTON_RIGHT];
}

- (void)rightMouseUp:(NSEvent *)event {
    [self.hidSupport mouseUp:event withButton:BUTTON_RIGHT];
}

- (void)otherMouseDown:(NSEvent *)event {
    int button = [self getMouseButtonFromEvent:event];
    if (button == 0) {
        return;
    }
    [self.hidSupport mouseDown:event withButton:button];
}

- (void)otherMouseUp:(NSEvent *)event {
    int button = [self getMouseButtonFromEvent:event];
    if (button == 0) {
        return;
    }
    [self.hidSupport mouseUp:event withButton:button];
}

- (void)mouseMoved:(NSEvent *)event {
    if ([self sendDesktopMousePositionIfNeeded:event]) {
        return;
    }
    [self.hidSupport mouseMoved:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if ([self sendDesktopMousePositionIfNeeded:event]) {
        return;
    }
    [self.hidSupport mouseMoved:event];
}

- (void)rightMouseDragged:(NSEvent *)event {
    if ([self sendDesktopMousePositionIfNeeded:event]) {
        return;
    }
    [self.hidSupport mouseMoved:event];
}

- (void)otherMouseDragged:(NSEvent *)event {
    if ([self sendDesktopMousePositionIfNeeded:event]) {
        return;
    }
    [self.hidSupport mouseMoved:event];
}

- (void)scrollWheel:(NSEvent *)event {
    [self.hidSupport scrollWheel:event];
}

- (int)getMouseButtonFromEvent:(NSEvent *)event {
    int button;
    switch (event.buttonNumber) {
        case 2:
            button = BUTTON_MIDDLE;
            break;
        case 3:
            button = BUTTON_X1;
            break;
        case 4:
            button = BUTTON_X2;
            break;
        default:
            return 0;
            break;
    }
    
    return button;
}


#pragma mark - KeyboardNotifiable

- (BOOL)onKeyboardEquivalent:(NSEvent *)event {
    const NSEventModifierFlags modifierFlags = NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagFunction;
    const NSEventModifierFlags eventModifierFlags = event.modifierFlags & modifierFlags;

    if ([self handleParsecMouseOverrideHotkey:event]) {
        return YES;
    }
    if ([self handleStatsOverlayHotkey:event]) {
        return YES;
    }

    if (event.keyCode == kVK_ANSI_1 && eventModifierFlags == NSEventModifierFlagCommand) {
        [self.hidSupport releaseAllModifierKeys];
        return NO;
    }
    
    if ((event.keyCode == kVK_ANSI_Grave && eventModifierFlags == NSEventModifierFlagCommand)
        || (event.keyCode == kVK_ANSI_H && eventModifierFlags == NSEventModifierFlagCommand)
        ) {
        if (![self isWindowFullscreen]) {
            [self.hidSupport releaseAllModifierKeys];
            return NO;
        }
    }
    
    if ((event.keyCode == kVK_ANSI_F && eventModifierFlags == (NSEventModifierFlagControl | NSEventModifierFlagCommand))
        || (event.keyCode == kVK_ANSI_F && eventModifierFlags == NSEventModifierFlagFunction)
        || (event.keyCode == kVK_ANSI_W && eventModifierFlags == (NSEventModifierFlagOption | NSEventModifierFlagControl))
        || (event.keyCode == kVK_ANSI_W && eventModifierFlags == (NSEventModifierFlagShift | NSEventModifierFlagControl))
        || (event.keyCode == kVK_ANSI_W && eventModifierFlags == NSEventModifierFlagCommand)
        ) {
        [self.hidSupport releaseAllModifierKeys];
        return NO;
    }
    
    [self.hidSupport keyDown:event];
    [self.hidSupport keyUp:event];
    
    return YES;
}


#pragma mark - Actions


- (IBAction)performClose:(id)sender {
    [self uncaptureMouse];
    
    NSAlert *alert = [[NSAlert alloc] init];
    
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Disconnect from Stream, or Close and Quit App?";

    [alert addButtonWithTitle:@"Disconnect from Stream"];
    [alert addButtonWithTitle:@"Close and Quit App"];
    [alert addButtonWithTitle:@"Cancel"];

    NSModalResponse response = [alert runModal];
    switch (response) {
        case NSAlertFirstButtonReturn:
            [self doCommandBySelector:@selector(performCloseStreamWindow:)];
            break;
            
        case NSAlertSecondButtonReturn:
            [self doCommandBySelector:@selector(performCloseAndQuitApp:)];
            break;

        default:
            break;
    }
}

- (IBAction)performCloseStreamWindow:(id)sender {
    [self.hidSupport releaseAllModifierKeys];
    [self.nextResponder doCommandBySelector:@selector(performClose:)];
}

- (IBAction)performCloseAndQuitApp:(id)sender {
    [self.delegate quitApp:self.app completion:nil];
}

- (IBAction)resizeWindowToActualResulution:(id)sender {
    CGFloat screenScale = [NSScreen mainScreen].backingScaleFactor;
    CGFloat width = (CGFloat)[self.class getResolution].width / screenScale;
    CGFloat height = (CGFloat)[self.class getResolution].height / screenScale;
    [self.view.window setContentSize:NSMakeSize(width, height)];
}


#pragma mark - Helpers

- (void)enableMenuItems:(BOOL)enable {
    NSMenu *appMenu = [[NSApplication sharedApplication].mainMenu itemWithTag:1000].submenu;
    appMenu.autoenablesItems = enable;
    [self itemWithMenu:appMenu andAction:@selector(terminate:)].enabled = enable;
}

- (void)captureMouse {
    if (self.parsecMouseMode && !self.parsecRelativeMouseMode) {
        [self captureDesktopMouse];
        return;
    }

    [self captureRelativeMouse];
}

- (void)captureRelativeMouse {
    [self stopParsecCursorDisplayLink];
    [self stopParsecPositionSender];
    [self.streamView setHostCursorVisible:NO];
    CGAssociateMouseAndMouseCursorPosition(NO);
    if (self.cursorHiddenCounter == 0) {
        [NSCursor hide];
        self.cursorHiddenCounter ++;
    }
    
    CGRect rectInWindow = [self.view convertRect:self.view.bounds toView:nil];
    CGRect rectInScreen = [self.view.window convertRectToScreen:rectInWindow];
    CGFloat screenHeight = self.view.window.screen.frame.size.height;
    CGPoint cursorPoint = CGPointMake(CGRectGetMidX(rectInScreen), screenHeight - CGRectGetMidY(rectInScreen));
    CGWarpMouseCursorPosition(cursorPoint);
    
    [self enableMenuItems:NO];
    
    [self disallowDisplaySleep];
    
    self.hidSupport.shouldSendInputEvents = YES;
    self.controllerSupport.shouldSendInputEvents = YES;
    self.view.window.acceptsMouseMovedEvents = YES;
}

- (void)captureDesktopMouse {
    CGAssociateMouseAndMouseCursorPosition(YES);
    if (self.cursorHiddenCounter != 0) {
        [NSCursor unhide];
        self.cursorHiddenCounter --;
    }
    [self.streamView setHostCursorVisible:YES];

    [self enableMenuItems:NO];
    [self disallowDisplaySleep];

    self.hidSupport.shouldSendInputEvents = YES;
    self.controllerSupport.shouldSendInputEvents = YES;
    self.view.window.acceptsMouseMovedEvents = YES;
    [self startParsecCursorDisplayLink];
    [self startParsecPositionSender];
}

- (void)uncaptureMouse {
    CGAssociateMouseAndMouseCursorPosition(YES);
    if (self.cursorHiddenCounter != 0) {
        [NSCursor unhide];
        self.cursorHiddenCounter --;
    }

    [self enableMenuItems:YES];

    [self allowDisplaySleep];

    self.hidSupport.shouldSendInputEvents = NO;
    self.controllerSupport.shouldSendInputEvents = NO;
    self.view.window.acceptsMouseMovedEvents = NO;
    [self.streamView setHostCursorVisible:NO];
    [self stopParsecCursorDisplayLink];
    [self stopParsecPositionSender];
}

- (BOOL)sendDesktopMousePositionIfNeeded:(NSEvent *)event {
    if (!self.parsecMouseMode || self.parsecRelativeMouseMode || !self.hidSupport.shouldSendInputEvents) {
        return NO;
    }
    return YES;
}

- (void)setParsecRelativeMouseMode:(BOOL)relativeMode {
    if (_parsecRelativeMouseMode == relativeMode) {
        return;
    }

    _parsecRelativeMouseMode = relativeMode;
    if (self.hidSupport.shouldSendInputEvents) {
        [self captureMouse];
    }
}

- (BOOL)handleParsecMouseOverrideHotkey:(NSEvent *)event {
    if (!self.parsecMouseMode || event.type != NSEventTypeKeyDown) {
        return NO;
    }

    const NSEventModifierFlags modifierFlags = NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagFunction;
    const NSEventModifierFlags eventModifierFlags = event.modifierFlags & modifierFlags;
    if (event.keyCode != self.parsecMouseShortcutKeyCode || eventModifierFlags != self.parsecMouseShortcutModifierFlags) {
        return NO;
    }

    [self.hidSupport releaseAllModifierKeys];
    self.parsecManualMouseOverride = YES;
    [self setParsecRelativeMouseMode:!self.parsecRelativeMouseMode];
    return YES;
}

- (BOOL)handleStatsOverlayHotkey:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return NO;
    }

    const NSEventModifierFlags modifierMask = NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagFunction;
    const NSEventModifierFlags eventModifierFlags = event.modifierFlags & modifierMask;
    const NSEventModifierFlags targetFlags = NSEventModifierFlagFunction | NSEventModifierFlagControl | NSEventModifierFlagOption;

    if (event.keyCode != kVK_ANSI_O || eventModifierFlags != targetFlags) {
        return NO;
    }

    [self.hidSupport releaseAllModifierKeys];

    NSString *message;
    if (!self.parsecMouseMode) {
        message = @"Mouse Mode: OFF";
    } else {
        NSString *mouseType = self.parsecRelativeMouseMode ? @"Relative" : @"Desktop";
        NSString *sunshineStatus = self.parsecCursorFeedbackReceived ? @"Active" : @"Waiting";
        message = [NSString stringWithFormat:@"Mouse Mode: ON  |  %@  |  Sunshine: %@", mouseType, sunshineStatus];
    }

    [self.streamView toggleStatsOverlay:message];
    return YES;
}

- (NSImage *)hostCursorImageWithBGRAData:(const uint8_t *)imageData width:(uint16_t)width height:(uint16_t)height imageByteLength:(uint32_t)imageByteLength {
    if (imageData == NULL || width == 0 || height == 0 || imageByteLength != (uint32_t)width * height * 4) {
        return nil;
    }

    NSData *data = [NSData dataWithBytes:imageData length:imageByteLength];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    if (provider == NULL) {
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL) {
        CGDataProviderRelease(provider);
        return nil;
    }

    CGImageRef cgImage = CGImageCreate(width, height, 8, 32, width * 4, colorSpace,
                                       kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
                                       provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

    if (cgImage == NULL) {
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size:NSMakeSize(width, height)];
    CGImageRelease(cgImage);
    return image;
}

- (NSPoint)localPointForHostCursorX:(int32_t)x y:(int32_t)y clipLeft:(int32_t)clipLeft clipTop:(int32_t)clipTop clipRight:(int32_t)clipRight clipBottom:(int32_t)clipBottom flags:(uint8_t)flags {
    CGFloat normalizedX = 0;
    CGFloat normalizedY = 0;

    if ((flags & LI_CURSOR_FLAG_CLIP_VALID) != 0 && clipRight > clipLeft && clipBottom > clipTop) {
        normalizedX = ((CGFloat)x - clipLeft) / ((CGFloat)clipRight - clipLeft);
        normalizedY = ((CGFloat)y - clipTop) / ((CGFloat)clipBottom - clipTop);
    } else {
        struct Resolution resolution = [self.class getResolution];
        normalizedX = resolution.width > 0 ? (CGFloat)x / resolution.width : 0;
        normalizedY = resolution.height > 0 ? (CGFloat)y / resolution.height : 0;
    }

    normalizedX = MAX(0, MIN(1, normalizedX));
    normalizedY = MAX(0, MIN(1, normalizedY));
    return NSMakePoint(normalizedX * self.view.bounds.size.width, (1 - normalizedY) * self.view.bounds.size.height);
}

- (BOOL)isWindowInCurrentSpace {
    BOOL found = NO;
    CFArrayRef windowsInSpace = CGWindowListCopyWindowInfo(kCGWindowListOptionAll | kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    for (NSDictionary *thisWindow in (__bridge NSArray *)windowsInSpace) {
        NSNumber *thisWindowNumber = (NSNumber *)thisWindow[(__bridge NSString *)kCGWindowNumber];
        if (self.view.window.windowNumber == thisWindowNumber.integerValue) {
            found = YES;
            break;
        }
    }
    if (windowsInSpace != NULL) {
        CFRelease(windowsInSpace);
    }
    return found;
}

- (BOOL)isWindowFullscreen {
    return [self.view.window styleMask] & NSWindowStyleMaskFullScreen;
}

- (BOOL)isOurWindowTheWindowInNotiifcation:(NSNotification *)note {
    return ((NSWindow *)note.object) == self.view.window;
}

- (NSMenuItem *)itemWithMenu:(NSMenu *)menu andAction:(SEL)action {
    return [menu itemAtIndex:[menu indexOfItemWithTarget:nil andAction:action]];
}


- (void)disallowDisplaySleep {
    if (self.powerAssertionID != 0) {
        return;
    }
    
    CFStringRef reasonForActivity= CFSTR("Moonlight streaming");
    
    IOPMAssertionID assertionID;
    IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, kIOPMAssertionLevelOn, reasonForActivity, &assertionID);
    
    if (success == kIOReturnSuccess) {
        self.powerAssertionID = assertionID;
    } else {
        self.powerAssertionID = 0;
    }
}

- (void)allowDisplaySleep {
    if (self.powerAssertionID != 0) {
        IOPMAssertionRelease(self.powerAssertionID);
        self.powerAssertionID = 0;
    }
}

- (void)closeWindowFromMainQueueWithMessage:(NSString *)message {
    [self.hidSupport releaseAllModifierKeys];
    [self stopAWDLDisablerIfNeeded];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self uncaptureMouse];

        [self.delegate appDidQuit:self.app];
        if (message != nil) {
            [AlertPresenter displayAlert:NSAlertStyleWarning title:@"Connection Failed" message:message window:self.view.window completionHandler:^(NSModalResponse returnCode) {
                [self.view.window close];
            }];
        } else {
            [self.view.window close];
        }
    });
}

- (StreamViewMac *)streamView {
    return (StreamViewMac *)self.view;
}


#pragma mark - Streaming Operations

- (void)startAWDLDisablerIfNeeded {
    if (self.awdlDisablerStarted) {
        return;
    }

    if (![SettingsClass disableAWDLDuringStreamFor:self.app.host.uuid]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.streamView.statusText = @"Waiting for network permission...";
    });

    if ([AWDLDisabler startMonitoring]) {
        self.awdlDisablerStarted = YES;
    } else {
        Log(LOG_W, @"AWDL disabler is enabled but did not start");
    }
}

- (void)stopAWDLDisablerIfNeeded {
    if (!self.awdlDisablerStarted) {
        return;
    }

    [AWDLDisabler stopMonitoring];
    self.awdlDisablerStarted = NO;
}

- (void)prepareForStreaming {
    StreamConfiguration *streamConfig = [[StreamConfiguration alloc] init];
    
    streamConfig.host = self.app.host.activeAddress;
    streamConfig.appID = self.app.id;
    streamConfig.appName = self.app.name;
    streamConfig.serverCert = self.app.host.serverCert;
    
    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* streamSettings = [dataMan getSettings];
    
    streamConfig.width = [self.class getResolution].width;
    streamConfig.height = [self.class getResolution].height;

    streamConfig.frameRate = [streamSettings.framerate intValue];
    streamConfig.bitRate = [streamSettings.bitrate intValue];
    streamConfig.framePacing = [SettingsClass framePacingFor:self.app.host.uuid];
    streamConfig.optimizeGameSettings = streamSettings.optimizeGames;
    streamConfig.playAudioOnPC = streamSettings.playAudioOnPC;
    streamConfig.allowHevc = streamSettings.useHevc;
    streamConfig.cursorFeedback = [SettingsClass parsecMouseModeFor:self.app.host.uuid];
    streamConfig.enableHdr = streamSettings.useHevc && VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) ? streamSettings.enableHdr : NO;

    streamConfig.multiController = streamSettings.multiController;
    streamConfig.gamepadMask = self.useSystemControllerDriver ? [ControllerSupport getConnectedGamepadMask:streamConfig] : 1;
    
    streamConfig.audioConfiguration = AUDIO_CONFIGURATION_STEREO;

    if (self.useSystemControllerDriver) {
        if (@available(iOS 13, tvOS 13, macOS 10.15, *)) {
            self.controllerSupport = [[ControllerSupport alloc] initWithConfig:streamConfig presenceDelegate:self];
        }
    }
    self.hidSupport = [[HIDSupport alloc] init:self.app.host];
    self.parsecMouseMode = streamConfig.cursorFeedback;
    self.parsecRelativeMouseMode = !self.parsecMouseMode;
    self.parsecManualMouseOverride = NO;
    self.parsecCursorFeedbackReceived = NO;
    self.parsecCursorImageReceived = NO;
    self.parsecMouseShortcutKeyCode = [SettingsClass parsecMouseShortcutKeyCodeFor:self.app.host.uuid];
    self.parsecMouseShortcutModifierFlags = [SettingsClass parsecMouseShortcutModifierFlagsFor:self.app.host.uuid];
    Log(LOG_I, @"Parsec Mouse Mode %@ for host %@. Shortcut keyCode=%ld modifiers=0x%lx",
        self.parsecMouseMode ? @"enabled" : @"disabled",
        self.app.host.name,
        (long)self.parsecMouseShortcutKeyCode,
        (unsigned long)self.parsecMouseShortcutModifierFlags);
    [self startAWDLDisablerIfNeeded];
    
    self.streamMan = [[StreamManager alloc] initWithConfig:streamConfig renderView:self.view connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:self.streamMan];
}


#pragma mark - Resolution

+ (struct Resolution)getResolution {
    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* streamSettings = [dataMan getSettings];

    struct Resolution resolution;
    
    resolution.width = [streamSettings.width intValue];
    resolution.height = [streamSettings.height intValue];

    return resolution;
}


#pragma mark - ConnectionCallbacks

- (void)stageStarting:(const char *)stageName {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString *titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        self.streamView.statusText = titleCase;
    });
}

- (void)stageComplete:(const char *)stageName {
}

- (void)connectionStarted {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.streamView.statusText = nil;
        [self.streamView showDebugMessage:(self.parsecMouseMode ? @"Parsec Mouse Mode is enabled" : @"Parsec Mouse Mode is disabled") duration:4];
        
        if ([SettingsClass autoFullscreenFor:self.app.host.uuid]) {
            if (!(self.view.window.styleMask & NSWindowStyleMaskFullScreen)) {
                [self.view.window toggleFullScreen:self];
            }
        } else {
            [self captureMouse];
        }

        if (self.parsecMouseMode) {
            [self.streamView showDebugMessage:@"Parsec Mouse: waiting for Sunshine feedback" duration:4];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!self.parsecCursorFeedbackReceived) {
                    Log(LOG_W, @"Parsec Mouse Mode is enabled, but no Sunshine cursor feedback packets were received. Confirm the Windows Sunshine fork is running and the host was restarted after building it.");
                    [self.streamView showDebugMessage:@"No Sunshine cursor feedback received" duration:6];
                }
            });
        }
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %ld", errorCode);
    [self closeWindowFromMainQueueWithMessage:nil];
}

- (void)stageFailed:(const char *)stageName withError:(int)errorCode {
    Log(LOG_I, @"Stage %s failed: %ld", stageName, errorCode);
    [self closeWindowFromMainQueueWithMessage:[NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode]];
}

- (void)launchFailed:(NSString *)message {
    [self closeWindowFromMainQueueWithMessage:message];
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    if ([SettingsClass rumbleFor:self.app.host.uuid]) {
        if (self.hidSupport.shouldSendInputEvents) {
            if (self.controllerSupport != nil) {
                [self.controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
            } else {
                [self.hidSupport rumbleLowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
            }
        }
    }
}

- (void)connectionStatusUpdate:(int)status {
}

- (void)cursorStateWithVersion:(uint8_t)version flags:(uint8_t)flags sequence:(uint32_t)sequence x:(int32_t)x y:(int32_t)y clipLeft:(int32_t)clipLeft clipTop:(int32_t)clipTop clipRight:(int32_t)clipRight clipBottom:(int32_t)clipBottom width:(uint16_t)width height:(uint16_t)height hotspotX:(uint16_t)hotspotX hotspotY:(uint16_t)hotspotY cursorHash:(uint32_t)cursorHash imageData:(const uint8_t *)imageData imageByteLength:(uint32_t)imageByteLength {
    if (!self.parsecMouseMode || version != 1) {
        return;
    }

    BOOL relativeMode = (flags & LI_CURSOR_FLAG_RELATIVE_MODE) != 0;
    BOOL visible = (flags & LI_CURSOR_FLAG_VISIBLE) != 0;
    BOOL imageIncluded = (flags & LI_CURSOR_FLAG_IMAGE_INCLUDED) != 0;
    if (!self.parsecCursorFeedbackReceived) {
        self.parsecCursorFeedbackReceived = YES;
        Log(LOG_I, @"Received first Sunshine cursor feedback packet. flags=0x%02x relative=%d visible=%d", flags, relativeMode, visible);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.streamView showDebugMessage:@"Sunshine cursor feedback active" duration:3];
        });
    }
    if (imageIncluded && !self.parsecCursorImageReceived) {
        self.parsecCursorImageReceived = YES;
        Log(LOG_I, @"Received first Sunshine cursor image. %ux%u bytes=%u hash=%u", width, height, imageByteLength, cursorHash);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.streamView showDebugMessage:@"Host cursor image received" duration:3];
        });
    }
    NSImage *cursorImage = imageIncluded ? [self hostCursorImageWithBGRAData:imageData width:width height:height imageByteLength:imageByteLength] : nil;
    NSPoint hostCursorPoint = [self localPointForHostCursorX:x y:y clipLeft:clipLeft clipTop:clipTop clipRight:clipRight clipBottom:clipBottom flags:flags];

    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat scale = self.view.window.backingScaleFactor ?: 1.0;
        if (cursorImage != nil) {
            cursorImage.size = NSMakeSize(width / scale, height / scale);
        }
        NSPoint hotspot = NSMakePoint(hotspotX / scale, hotspotY / scale);

        if (!self.parsecManualMouseOverride) {
            [self setParsecRelativeMouseMode:relativeMode];
        }
        BOOL displayedRelativeMode = self.parsecManualMouseOverride ? self.parsecRelativeMouseMode : relativeMode;
        if (cursorImage != nil) {
            [self.streamView updateHostCursorImage:cursorImage hotspot:hotspot visible:visible && !displayedRelativeMode];
            if (visible && !displayedRelativeMode && self.cursorHiddenCounter == 0) {
                [NSCursor hide];
                self.cursorHiddenCounter ++;
            }
        }
        CFAbsoluteTime nowTime = CFAbsoluteTimeGetCurrent();
        BOOL recentLocalMove = (nowTime - self.parsecLastLocalMoveTime) < 0.1;
        if (!recentLocalMove || displayedRelativeMode) {
            [self.streamView moveHostCursorToPoint:hostCursorPoint];
        }
        [self.streamView setHostCursorVisible:visible && !displayedRelativeMode];
    });
}


#pragma mark - InputPresenceDelegate

- (void)gamepadPresenceChanged {
}

- (void)mousePresenceChanged {
}

@end
