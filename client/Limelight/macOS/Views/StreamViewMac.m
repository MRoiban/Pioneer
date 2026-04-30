//
//  StreamViewMac.m
//  Moonlight for macOS
//
//  Created by Michael Kenny on 27/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import "StreamViewMac.h"

@interface StreamViewMac ()
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSImageView *hostCursorImageView;
@property (nonatomic, strong) NSTextField *debugLabel;
@property (nonatomic, strong) NSWindow *debugOverlayWindow;
@property (nonatomic, strong) NSTextField *debugOverlayLabel;
@property (nonatomic, strong) NSWindow *statsOverlayWindow;
@property (nonatomic, strong) NSTextField *statsOverlayLabel;
@property (nonatomic) NSPoint hostCursorHotspot;
@property (nonatomic) NSPoint hostCursorPoint;

@end

@implementation StreamViewMac

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        self.spinner = [[NSProgressIndicator alloc] init];
        self.spinner.style = NSProgressIndicatorStyleSpinning;
        [self.spinner startAnimation:self];
        [self addSubview:self.spinner];
        self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
        [self.spinner.widthAnchor constraintEqualToConstant:32].active = YES;
        [self.spinner.heightAnchor constraintEqualToConstant:32].active = YES;

        self.hostCursorImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        self.hostCursorImageView.imageScaling = NSImageScaleNone;
        self.hostCursorImageView.hidden = YES;
        [self addSubview:self.hostCursorImageView positioned:NSWindowAbove relativeTo:nil];

        self.debugLabel = [NSTextField labelWithString:@""];
        self.debugLabel.hidden = YES;
        self.debugLabel.textColor = NSColor.whiteColor;
        self.debugLabel.backgroundColor = [NSColor colorWithWhite:0 alpha:0.7];
        self.debugLabel.drawsBackground = YES;
        self.debugLabel.wantsLayer = YES;
        self.debugLabel.layer.cornerRadius = 4;
        self.debugLabel.layer.masksToBounds = YES;
        self.debugLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:self.debugLabel positioned:NSWindowAbove relativeTo:nil];
        self.debugLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.debugLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12].active = YES;
        [self.debugLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12].active = YES;
        [self.debugLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor constant:-24].active = YES;
    }
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window == nil) {
        if (self.debugOverlayWindow != nil) {
            [self.debugOverlayWindow close];
            self.debugOverlayWindow = nil;
            self.debugOverlayLabel = nil;
        }
        if (self.statsOverlayWindow != nil) {
            [self.statsOverlayWindow close];
            self.statsOverlayWindow = nil;
            self.statsOverlayLabel = nil;
        }
    }
}

- (void)setStatusText:(NSString *)statusText {
    if (statusText == nil) {
        [self.spinner stopAnimation:self];
        self.spinner.hidden = YES;
        self.window.title = self.appName;
    } else {
        self.window.title = [[self.appName stringByAppendingString:@" - "] stringByAppendingString:statusText];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    [[NSColor blackColor] setFill];
    NSRectFill(dirtyRect);
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    return [self.keyboardNotifiable onKeyboardEquivalent:event];
}

- (void)updateHostCursorImage:(NSImage *)image hotspot:(NSPoint)hotspot visible:(BOOL)visible {
    self.hostCursorImageView.image = image;
    self.hostCursorHotspot = hotspot;
    self.hostCursorImageView.hidden = !visible || image == nil;
    [self moveHostCursorToPoint:self.hostCursorPoint];
}

- (void)moveHostCursorToPoint:(NSPoint)point {
    self.hostCursorPoint = point;

    NSImage *image = self.hostCursorImageView.image;
    if (image == nil) {
        return;
    }

    CGFloat x = point.x - self.hostCursorHotspot.x;
    CGFloat y = point.y - (image.size.height - self.hostCursorHotspot.y);
    self.hostCursorImageView.frame = NSMakeRect(x, y, image.size.width, image.size.height);
}

- (void)setHostCursorVisible:(BOOL)visible {
    self.hostCursorImageView.hidden = !visible || self.hostCursorImageView.image == nil;
}

- (void)showDebugMessage:(NSString *)message duration:(NSTimeInterval)duration {
    self.debugLabel.stringValue = [NSString stringWithFormat:@"  %@  ", message];
    self.debugLabel.hidden = NO;
    [self addSubview:self.debugLabel positioned:NSWindowAbove relativeTo:nil];
    [self showDebugOverlayWindowMessage:message];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.debugLabel.stringValue containsString:message]) {
            self.debugLabel.hidden = YES;
        }
        if ([self.debugOverlayLabel.stringValue containsString:message]) {
            [self.debugOverlayWindow orderOut:nil];
        }
    });
}

- (void)showDebugOverlayWindowMessage:(NSString *)message {
    if (self.window == nil) {
        return;
    }

    if (self.debugOverlayWindow == nil) {
        NSRect frame = NSMakeRect(0, 0, 420, 32);
        self.debugOverlayWindow = [[NSWindow alloc] initWithContentRect:frame
                                                              styleMask:NSWindowStyleMaskBorderless
                                                                backing:NSBackingStoreBuffered
                                                                  defer:NO];
        self.debugOverlayWindow.opaque = NO;
        self.debugOverlayWindow.backgroundColor = NSColor.clearColor;
        self.debugOverlayWindow.ignoresMouseEvents = YES;
        self.debugOverlayWindow.releasedWhenClosed = NO;
        self.debugOverlayWindow.level = NSStatusWindowLevel;

        self.debugOverlayLabel = [NSTextField labelWithString:@""];
        self.debugOverlayLabel.textColor = NSColor.whiteColor;
        self.debugOverlayLabel.backgroundColor = [NSColor colorWithWhite:0 alpha:0.82];
        self.debugOverlayLabel.drawsBackground = YES;
        self.debugOverlayLabel.wantsLayer = YES;
        self.debugOverlayLabel.layer.cornerRadius = 5;
        self.debugOverlayLabel.layer.masksToBounds = YES;
        self.debugOverlayLabel.alignment = NSTextAlignmentCenter;
        self.debugOverlayLabel.frame = frame;
        self.debugOverlayWindow.contentView = self.debugOverlayLabel;
        [self.window addChildWindow:self.debugOverlayWindow ordered:NSWindowAbove];
    }

    self.debugOverlayLabel.stringValue = [NSString stringWithFormat:@"  %@  ", message];
    [self.debugOverlayLabel sizeToFit];
    CGFloat width = MIN(MAX(self.debugOverlayLabel.frame.size.width + 24, 260), MAX(self.window.frame.size.width - 48, 260));
    NSRect windowFrame = self.window.frame;
    NSRect overlayFrame = NSMakeRect(NSMinX(windowFrame) + 24, NSMaxY(windowFrame) - 56, width, 32);
    [self.debugOverlayWindow setFrame:overlayFrame display:YES];
    self.debugOverlayLabel.frame = NSMakeRect(0, 0, width, 32);
    [self.debugOverlayWindow orderFront:nil];
}

- (void)toggleStatsOverlay:(NSString *)message {
    if (self.statsOverlayWindow != nil && self.statsOverlayWindow.isVisible) {
        [self.statsOverlayWindow orderOut:nil];
        return;
    }

    if (self.window == nil) {
        return;
    }

    if (self.statsOverlayWindow == nil) {
        NSRect frame = NSMakeRect(0, 0, 300, 32);
        self.statsOverlayWindow = [[NSWindow alloc] initWithContentRect:frame
                                                              styleMask:NSWindowStyleMaskBorderless
                                                                backing:NSBackingStoreBuffered
                                                                  defer:NO];
        self.statsOverlayWindow.opaque = NO;
        self.statsOverlayWindow.backgroundColor = NSColor.clearColor;
        self.statsOverlayWindow.ignoresMouseEvents = YES;
        self.statsOverlayWindow.releasedWhenClosed = NO;
        self.statsOverlayWindow.level = NSStatusWindowLevel;

        self.statsOverlayLabel = [NSTextField labelWithString:@""];
        self.statsOverlayLabel.textColor = NSColor.whiteColor;
        self.statsOverlayLabel.backgroundColor = [NSColor colorWithWhite:0 alpha:0.82];
        self.statsOverlayLabel.drawsBackground = YES;
        self.statsOverlayLabel.wantsLayer = YES;
        self.statsOverlayLabel.layer.cornerRadius = 5;
        self.statsOverlayLabel.layer.masksToBounds = YES;
        self.statsOverlayLabel.alignment = NSTextAlignmentCenter;
        self.statsOverlayLabel.frame = frame;
        self.statsOverlayWindow.contentView = self.statsOverlayLabel;
        [self.window addChildWindow:self.statsOverlayWindow ordered:NSWindowAbove];
    }

    self.statsOverlayLabel.stringValue = [NSString stringWithFormat:@"  %@  ", message];
    [self.statsOverlayLabel sizeToFit];
    CGFloat width = MIN(MAX(self.statsOverlayLabel.frame.size.width + 24, 200), MAX(self.window.frame.size.width - 48, 200));
    NSRect windowFrame = self.window.frame;
    NSRect overlayFrame = NSMakeRect(NSMinX(windowFrame) + 24, NSMinY(windowFrame) + 24, width, 32);
    [self.statsOverlayWindow setFrame:overlayFrame display:YES];
    self.statsOverlayLabel.frame = NSMakeRect(0, 0, width, 32);
    [self.statsOverlayWindow orderFront:nil];
}

@end
