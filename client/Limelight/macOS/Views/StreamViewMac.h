//
//  StreamViewMac.h
//  Moonlight for macOS
//
//  Created by Michael Kenny on 27/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "StreamViewController.h"

@interface StreamViewMac : NSView
@property (nonatomic, strong) NSString *statusText;
@property (nonatomic, strong) NSString *appName;
@property (nonatomic, weak) id<KeyboardNotifiableDelegate> keyboardNotifiable;

- (void)updateHostCursorImage:(NSImage *)image hotspot:(NSPoint)hotspot visible:(BOOL)visible;
- (void)moveHostCursorToPoint:(NSPoint)point;
- (void)setHostCursorVisible:(BOOL)visible;
- (void)showDebugMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)toggleStatsOverlay:(NSString *)message;

@end
