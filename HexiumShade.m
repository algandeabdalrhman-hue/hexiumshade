#import "HexiumShade.h"
#import <Foundation/Foundation.h>

@implementation HexiumShade

+ (NSString *)version {
    return @"1.0.0";
}

+ (NSDictionary<NSString *, NSString *> *)parseINI:(NSString *)ini {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];

    for (NSString *line in [ini componentsSeparatedByCharactersInSet:
                            NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceCharacterSet];

        if (trimmed.length == 0 ||
            [trimmed hasPrefix:@";"] ||
            [trimmed hasPrefix:@"#"] ||
            [trimmed hasPrefix:@"["]) {
            continue;
        }

        NSRange separator = [trimmed rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;

        NSString *key = [[trimmed substringToIndex:separator.location]
                         stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceCharacterSet];

        NSString *value = [[trimmed substringFromIndex:separator.location + 1]
                           stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceCharacterSet];

        if (key.length > 0) {
            settings[key] = value;
        }
    }

    return settings;
}

+ (NSString *)exportINI:(NSDictionary<NSString *, NSString *> *)settings {
    NSMutableString *output = [NSMutableString string];

    for (NSString *key in [[settings allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [output appendFormat:@"%@=%@\n", key, settings[key]];
    }

    return output;
}

@end
