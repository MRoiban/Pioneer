//
//  AWDLDisabler.h
//  Moonlight
//

#import <Foundation/Foundation.h>

@interface AWDLDisabler : NSObject

+ (BOOL)startMonitoring;
+ (void)stopMonitoring;

@end
