//
//  Connection.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "VideoDecoderRenderer.h"
#import "StreamConfiguration.h"

@protocol ConnectionCallbacks <NSObject>

- (void) connectionStarted;
- (void) connectionTerminated:(int)errorCode;
- (void) stageStarting:(const char*)stageName;
- (void) stageComplete:(const char*)stageName;
- (void) stageFailed:(const char*)stageName withError:(int)errorCode;
- (void) launchFailed:(NSString*)message;
- (void) rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor;
- (void) connectionStatusUpdate:(int)status;
- (void) cursorStateWithVersion:(uint8_t)version flags:(uint8_t)flags sequence:(uint32_t)sequence x:(int32_t)x y:(int32_t)y clipLeft:(int32_t)clipLeft clipTop:(int32_t)clipTop clipRight:(int32_t)clipRight clipBottom:(int32_t)clipBottom width:(uint16_t)width height:(uint16_t)height hotspotX:(uint16_t)hotspotX hotspotY:(uint16_t)hotspotY cursorHash:(uint32_t)cursorHash imageData:(const uint8_t*)imageData imageByteLength:(uint32_t)imageByteLength;

@end

@interface Connection : NSOperation <NSStreamDelegate>

-(id) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks;
-(void) terminate;
-(void) main;

@end
