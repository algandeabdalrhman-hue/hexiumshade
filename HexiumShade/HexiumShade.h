#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface HexiumShade : NSObject

+ (NSString *)version;

+ (NSDictionary<NSString *, NSString *> *)parseINI:(NSString *)ini;

+ (NSString *)exportINI:(NSDictionary<NSString *, NSString *> *)settings;

/**
 Processes an RGBA Metal texture into a separate output texture.
 The caller owns texture creation, frame acquisition, and presentation.
 Required texture usage: source = MTLTextureUsageShaderRead,
 destination = MTLTextureUsageShaderWrite.
 Supported option keys:
 Bloom, Sharpen, ColorCorrection, AmbientLight (booleans);
 Exposure (-2...2), Contrast (0...2), Saturation (0...2),
 BloomIntensity (0...2), SharpenAmount (0...2),
 AmbientIntensity (0...0.5).
 */
+ (BOOL)processTexture:(id<MTLTexture>)source
         outputTexture:(id<MTLTexture>)destination
               options:(NSDictionary<NSString *, NSNumber *> *)options
                 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
