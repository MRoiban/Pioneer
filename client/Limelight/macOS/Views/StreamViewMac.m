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
    }
    return self;
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

@end
