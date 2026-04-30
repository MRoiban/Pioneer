//
//  StreamConfiguration.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MLFramePacingMode) {
    MLFramePacingModeLowestLatency = 0,
    MLFramePacingModeSmoothest = 1,
    MLFramePacingModeAuto = 2,
    MLFramePacingModeBalanced = 3,
};

@interface StreamConfiguration : NSObject

@property NSString* host;
@property NSString* appVersion;
@property NSString* gfeVersion;
@property NSString* rtspSessionUrl;
@property NSString* appID;
@property NSString* appName;
@property int width;
@property int height;
@property int frameRate;
@property int bitRate;
@property int riKeyId;
@property BOOL streamingRemotely;
@property NSData* riKey;
@property int gamepadMask;
@property BOOL optimizeGameSettings;
@property BOOL playAudioOnPC;
@property int audioConfiguration;
@property BOOL enableHdr;
@property BOOL multiController;
@property BOOL allowHevc;
@property BOOL cursorFeedback;
@property NSData* serverCert;
@property int framePacing;

@end
