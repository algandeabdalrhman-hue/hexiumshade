#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HexiumShade : NSObject

+ (NSString *)version;

+ (NSDictionary<NSString *, NSString *> *)parseINI:(NSString *)ini;

+ (NSString *)exportINI:(NSDictionary<NSString *, NSString *> *)settings;

@end

NS_ASSUME_NONNULL_END
