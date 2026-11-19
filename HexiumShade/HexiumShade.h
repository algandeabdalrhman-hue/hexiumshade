#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSInteger, HSDepthEncoding) {
    HSDepthEncodingDeviceZ = 0,
    HSDepthEncodingLinear01 = 1,
    HSDepthEncodingLinearViewDistance = 2
};

typedef NS_ENUM(NSInteger, HSNormalEncoding) {
    HSNormalEncodingWorldSpace = 0,
    HSNormalEncodingViewSpace = 1,
    HSNormalEncodingEncoded01 = 2
};

/// Per-frame camera/depth metadata. Matrices are column-major Metal SIMD matrices.
typedef struct {
    simd_float4x4 projectionMatrix;
    simd_float4x4 inverseProjectionMatrix;
    simd_float4x4 viewMatrix;
    float nearPlane;
    float farPlane;
    float deltaTime;
    HSDepthEncoding depthEncoding;
    HSNormalEncoding normalEncoding;
} HSFrameInfo;

@interface HexiumShade : NSObject

+ (NSString *)version;
+ (NSDictionary<NSString *, NSString *> *)parseINI:(NSString *)ini;
+ (NSString *)exportINI:(NSDictionary<NSString *, NSString *> *)settings;
+ (BOOL)setQualityPreset:(NSString *)preset;
+ (NSString *)qualityPreset;
+ (NSDictionary<NSString *, NSNumber *> *)qualitySettings;

/// Validates camera metadata required by depth-aware post-processing.
+ (BOOL)validateFrameInfo:(HSFrameInfo)frameInfo error:(NSError * _Nullable * _Nullable)error;

/// Allocates a private intermediate texture with shader read/write access.
+ (nullable id<MTLTexture>)createIntermediateTextureWithWidth:(NSUInteger)width
                                                    height:(NSUInteger)height
                                               pixelFormat:(MTLPixelFormat)pixelFormat
                                                    device:(id<MTLDevice>)device
                                                     error:(NSError * _Nullable * _Nullable)error;

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

/// Processes a host-owned frame through the enabled SHADES effect chain.
/// Effects are read from the state saved by the control panel. Depth effects require
/// matching host-supplied depth/normal textures and accurate HSFrameInfo metadata.
+ (nullable id<MTLTexture>)processFrameColorTexture:(id<MTLTexture>)colorTexture
                                      depthTexture:(nullable id<MTLTexture>)depthTexture
                                     normalTexture:(nullable id<MTLTexture>)normalTexture
                               motionVectorTexture:(nullable id<MTLTexture>)motionVectorTexture
                                         frameInfo:(HSFrameInfo)frameInfo
                                            device:(id<MTLDevice>)device
                                      commandQueue:(id<MTLCommandQueue>)commandQueue
                                             error:(NSError * _Nullable * _Nullable)error;

/// Applies screen-space ambient occlusion using host-supplied linear/device depth and normals.
/// Returns a new color texture; inputs remain owned by the caller.
+ (nullable id<MTLTexture>)applyMXAOToColorTexture:(id<MTLTexture>)colorTexture
                                      depthTexture:(id<MTLTexture>)depthTexture
                                     normalTexture:(id<MTLTexture>)normalTexture
                                      depthEncoding:(HSDepthEncoding)depthEncoding
                                     normalEncoding:(HSNormalEncoding)normalEncoding
                                          nearPlane:(float)nearPlane
                                           farPlane:(float)farPlane
                                             radius:(float)radius
                                           intensity:(float)intensity
                                         normalBias:(float)normalBias
                                             device:(id<MTLDevice>)device
                                       commandQueue:(id<MTLCommandQueue>)commandQueue
                                              error:(NSError * _Nullable * _Nullable)error;


/// Applies distance-based depth haze to a host-supplied color/depth frame.
/// fogStart and fogFactor are normalized [0,1] distance controls; fogColor is linear RGB.
+ (nullable id<MTLTexture>)applyDepthHazeToColorTexture:(id<MTLTexture>)colorTexture
                                          depthTexture:(id<MTLTexture>)depthTexture
                                         depthEncoding:(HSDepthEncoding)depthEncoding
                                             nearPlane:(float)nearPlane
                                              farPlane:(float)farPlane
                                              fogStart:(float)fogStart
                                             fogFactor:(float)fogFactor
                                              fogColor:(vector_float3)fogColor
                                                device:(id<MTLDevice>)device
                                          commandQueue:(id<MTLCommandQueue>)commandQueue
                                                 error:(NSError * _Nullable * _Nullable)error;


/// Applies depth-of-field blur using host-supplied color and depth textures.
/// focusDistance is normalized [0,1] linear view distance; focusRange controls the in-focus band.
+ (nullable id<MTLTexture>)applyADOFToColorTexture:(id<MTLTexture>)colorTexture
                                     depthTexture:(id<MTLTexture>)depthTexture
                                    depthEncoding:(HSDepthEncoding)depthEncoding
                                        nearPlane:(float)nearPlane
                                         farPlane:(float)farPlane
                                     focusDistance:(float)focusDistance
                                         focusRange:(float)focusRange
                                         blurRadius:(float)blurRadius
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
