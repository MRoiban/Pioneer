//
//  AWDLDisabler.m
//  Moonlight
//

#import "AWDLDisabler.h"
#import "Logger.h"

#include <unistd.h>

@implementation AWDLDisabler

static NSInteger activeRequests;

+ (NSString *)sentinelPath
{
    return [NSString stringWithFormat:@"/tmp/moonlight-awdl-killer-%d.enabled", getuid()];
}

+ (NSString *)pidPath
{
    return [NSString stringWithFormat:@"/tmp/moonlight-awdl-killer-%d.pid", getuid()];
}

+ (NSString *)appleScriptStringLiteral:(NSString *)string
{
    NSMutableString *escaped = [string mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

+ (NSString *)shellSingleQuotedString:(NSString *)string
{
    NSMutableString *escaped = [string mutableCopy];
    [escaped replaceOccurrencesOfString:@"'" withString:@"'\\''" options:0 range:NSMakeRange(0, escaped.length)];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

+ (BOOL)startMonitoring
{
    @synchronized (self) {
        if (activeRequests > 0) {
            activeRequests++;
            return YES;
        }

        NSString *sentinelPath = [self sentinelPath];
        NSString *pidPath = [self pidPath];

        if (![@"1\n" writeToFile:sentinelPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
            Log(LOG_E, @"Failed to create AWDL disabler sentinel");
            return NO;
        }

        NSString *shellScript = [NSString stringWithFormat:
                                 @"SENTINEL=%@; "
                                 @"PIDFILE=%@; "
                                 @"PARENTPID=%d; "
                                 @"INTERFACE=awdl0; "
                                 @"if [ -f \"$PIDFILE\" ] && /bin/kill -0 \"$(/bin/cat \"$PIDFILE\")\" 2>/dev/null; then exit 0; fi; "
                                 @"( "
                                 @"echo $$ > \"$PIDFILE\"; "
                                 @"trap '/sbin/ifconfig awdl0 up >/dev/null 2>&1; /bin/rm -f \"$PIDFILE\"' EXIT INT TERM; "
                                 @"while [ -f \"$SENTINEL\" ] && /bin/kill -0 \"$PARENTPID\" 2>/dev/null; do "
                                 @"if /sbin/ifconfig \"$INTERFACE\" 2>/dev/null | /usr/bin/awk 'NR == 1 { exit(index($0, \"UP\") ? 0 : 1) }'; then "
                                 @"/sbin/ifconfig \"$INTERFACE\" down >/dev/null 2>&1; "
                                 @"fi; "
                                 @"/bin/sleep 0.1; "
                                 @"done "
                                 @") >/dev/null 2>&1 &",
                                 [self shellSingleQuotedString:sentinelPath],
                                 [self shellSingleQuotedString:pidPath],
                                 getpid()];

        NSString *appleScript = [NSString stringWithFormat:@"do shell script %@ with administrator privileges",
                                 [self appleScriptStringLiteral:shellScript]];

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/osascript";
        task.arguments = @[@"-e", appleScript];

        @try {
            [task launch];
            [task waitUntilExit];
        }
        @catch (NSException *exception) {
            Log(LOG_E, @"Failed to launch AWDL disabler authorization prompt: %@", exception);
            [[NSFileManager defaultManager] removeItemAtPath:sentinelPath error:nil];
            return NO;
        }

        if (task.terminationStatus != 0) {
            Log(LOG_W, @"AWDL disabler authorization was cancelled or failed");
            [[NSFileManager defaultManager] removeItemAtPath:sentinelPath error:nil];
            return NO;
        }

        activeRequests = 1;
        Log(LOG_I, @"AWDL disabler started");
        return YES;
    }
}

+ (void)stopMonitoring
{
    @synchronized (self) {
        if (activeRequests == 0) {
            return;
        }

        activeRequests--;
        if (activeRequests > 0) {
            return;
        }

        [[NSFileManager defaultManager] removeItemAtPath:[self sentinelPath] error:nil];
        Log(LOG_I, @"AWDL disabler stopped");
    }
}

@end
