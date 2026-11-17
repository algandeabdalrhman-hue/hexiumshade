#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface HexiumShade : NSObject

+ (NSString *)version;
+ (NSDictionary<NSString *, NSString *> *)parseINI:(NSString *)ini;
+ (NSString *)exportINI:(NSDictionary<NSString *, NSString *> *)settings;
+ (BOOL)setQualityPreset:(NSString *)preset;
+ (NSString *)qualityPreset;
+ (NSDictionary<NSString *, NSNumber *> *)qualitySettings;

/// Runs HexiumShade's standalone Metal color pass on a caller-owned texture.
+ (nullable id<MTLTexture>)processTexture:(id<MTLTexture>)input
                                   device:(id<MTLDevice>)device
                             commandQueue:(id<MTLCommandQueue>)commandQueue
                                    error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
