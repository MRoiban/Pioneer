//
//  HIDSupport.h
//  Moonlight for macOS
//
//  Created by Michael Kenny on 26/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TemporaryHost.h"

@interface HIDSupport : NSObject
@property (atomic) BOOL shouldSendInputEvents;
@property (atomic) BOOL suppressRelativeMouseEvents;
@property (atomic) TemporaryHost *host;
@property (nonatomic, readonly) BOOL rawHIDMouseActive;
@property (nonatomic, readonly) BOOL rawHIDMouseRequested;
@property (nonatomic, readonly) BOOL localMouseDeltaSourceActive;
@property (nonatomic, copy) void (^localMouseDeltaHandler)(double deltaX, double deltaY);

- (instancetype)init:(TemporaryHost *)host;

- (void)flagsChanged:(NSEvent *)event;
- (void)keyDown:(NSEvent *)event;
- (void)keyUp:(NSEvent *)event;

- (void)releaseAllModifierKeys;

- (void)mouseDown:(NSEvent *)event withButton:(int)button;
- (void)mouseUp:(NSEvent *)event withButton:(int)button;
- (void)mouseMoved:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;

- (void)rumbleLowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor;

- (void)tearDownHidManager;

@end
