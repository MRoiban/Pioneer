//
//  Utils.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "Utils.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netdb.h>

@implementation Utils
NSString *const deviceName = @"roth";

+ (NSData*) randomBytes:(NSInteger)length {
    char* bytes = malloc(length);
    arc4random_buf(bytes, length);
    NSData* randomData = [NSData dataWithBytes:bytes length:length];
    free(bytes);
    return randomData;
}

+ (NSData*) hexToBytes:(NSString*) hex {
    unsigned long len = [hex length];
    NSMutableData* data = [NSMutableData dataWithCapacity:len / 2];
    char byteChars[3] = {'\0','\0','\0'};
    unsigned long wholeByte;
    
    const char *chars = [hex UTF8String];
    int i = 0;
    while (i < len) {
        byteChars[0] = chars[i++];
        byteChars[1] = chars[i++];
        wholeByte = strtoul(byteChars, NULL, 16);
        [data appendBytes:&wholeByte length:1];
    }
    
    return data;
}

+ (NSString*) bytesToHex:(NSData*)data {
    const unsigned char* bytes = [data bytes];
    NSMutableString *hex = [[NSMutableString alloc] init];
    for (int i = 0; i < [data length]; i++) {
        [hex appendFormat:@"%02X" , bytes[i]];
    }
    return hex;
}

+ (NSString*)hostFromAddressString:(NSString*)address {
    NSString* trimmedAddress = [address trim];
    if ([trimmedAddress hasPrefix:@"["]) {
        NSRange closingBracket = [trimmedAddress rangeOfString:@"]"];
        if (closingBracket.location != NSNotFound && closingBracket.location > 1) {
            return [trimmedAddress substringWithRange:NSMakeRange(1, closingBracket.location - 1)];
        }
        return trimmedAddress;
    }

    NSUInteger colonCount = 0;
    for (NSUInteger i = 0; i < trimmedAddress.length; i++) {
        if ([trimmedAddress characterAtIndex:i] == ':') {
            colonCount++;
        }
    }

    if (colonCount == 1) {
        NSRange portSeparator = [trimmedAddress rangeOfString:@":" options:NSBackwardsSearch];
        NSString* host = [trimmedAddress substringToIndex:portSeparator.location];
        NSString* port = [trimmedAddress substringFromIndex:portSeparator.location + 1];
        if (host.length != 0 && [Utils isValidPortString:port]) {
            return host;
        }
    }

    return trimmedAddress;
}

+ (NSString*)portFromAddressString:(NSString*)address {
    NSString* trimmedAddress = [address trim];
    if ([trimmedAddress hasPrefix:@"["]) {
        NSRange closingBracket = [trimmedAddress rangeOfString:@"]"];
        if (closingBracket.location != NSNotFound && closingBracket.location + 2 < trimmedAddress.length &&
            [trimmedAddress characterAtIndex:closingBracket.location + 1] == ':') {
            NSString* port = [trimmedAddress substringFromIndex:closingBracket.location + 2];
            return [Utils isValidPortString:port] ? port : nil;
        }
        return nil;
    }

    NSUInteger colonCount = 0;
    for (NSUInteger i = 0; i < trimmedAddress.length; i++) {
        if ([trimmedAddress characterAtIndex:i] == ':') {
            colonCount++;
        }
    }

    if (colonCount == 1) {
        NSRange portSeparator = [trimmedAddress rangeOfString:@":" options:NSBackwardsSearch];
        NSString* port = [trimmedAddress substringFromIndex:portSeparator.location + 1];
        return [Utils isValidPortString:port] ? port : nil;
    }

    return nil;
}

+ (NSString*)urlSafeHostFromAddressString:(NSString*)address {
    NSString* host = [Utils hostFromAddressString:address];
    if ([host containsString:@":"]) {
        return [NSString stringWithFormat:@"[%@]", host];
    }
    return host;
}

+ (BOOL)addressStringHasExplicitPort:(NSString*)address {
    return [Utils portFromAddressString:address] != nil;
}

+ (BOOL)isValidPortString:(NSString*)port {
    if (port.length == 0) {
        return NO;
    }

    NSCharacterSet* nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([port rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return NO;
    }

    NSInteger portValue = [port integerValue];
    return portValue > 0 && portValue <= 65535;
}

+ (BOOL)isActiveNetworkVPN {
    NSDictionary *dict = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    NSArray *keys = [dict[@"__SCOPED__"] allKeys];
    for (NSString *key in keys) {
        if ([key containsString:@"tap"] ||
            [key containsString:@"tun"] ||
            [key containsString:@"ppp"] ||
            [key containsString:@"ipsec"]) {
            return YES;
        }
    }
    return NO;
}

#if TARGET_OS_IPHONE
+ (void) addHelpOptionToDialog:(UIAlertController*)dialog {
#if !TARGET_OS_TV
    // tvOS doesn't have a browser
    [dialog addAction:[UIAlertAction actionWithTitle:@"Help" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"]];
    }]];
#endif
}
#endif

@end

@implementation NSString (NSStringWithTrim)

- (NSString *)trim {
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
