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

/// Validates the color, depth, normal, and motion-vector textures supplied by a host renderer.
+ (BOOL)validateFrameColorTexture:(id<MTLTexture>)colorTexture
                     depthTexture:(nullable id<MTLTexture>)depthTexture
                    normalTexture:(nullable id<MTLTexture>)normalTexture
              motionVectorTexture:(nullable id<MTLTexture>)motionVectorTexture
                           device:(id<MTLDevice>)device
                            error:(NSError * _Nullable * _Nullable)error;

/// Processes the color input after validating the optional auxiliary frame textures.
+ (nullable id<MTLTexture>)processFrameColorTexture:(id<MTLTexture>)colorTexture
                                      depthTexture:(nullable id<MTLTexture>)depthTexture
                                     normalTexture:(nullable id<MTLTexture>)normalTexture
                               motionVectorTexture:(nullable id<MTLTexture>)motionVectorTexture
                                            device:(id<MTLDevice>)device
                                      commandQueue:(id<MTLCommandQueue>)commandQueue
                                             error:(NSError * _Nullable * _Nullable)error;

/// Runs HexiumShade's standalone Metal color pass on a caller-owned texture.
+ (nullable id<MTLTexture>)processTexture:(id<MTLTexture>)input
                                   device:(id<MTLDevice>)device
                             commandQueue:(id<MTLCommandQueue>)commandQueue
                                    error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
