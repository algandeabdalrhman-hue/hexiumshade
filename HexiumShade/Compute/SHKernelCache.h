#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/// Thread-safe cache for compute pipeline states created from SHADES-owned Metal functions.
@interface SHKernelCache : NSObject
- (nullable id<MTLComputePipelineState>)pipelineForFunctionNamed:(NSString *)functionName
                                                         library:(nullable id<MTLLibrary>)library
                                                           device:(id<MTLDevice>)device
                                                            error:(NSError * _Nullable * _Nullable)error;
- (void)removeAllPipelinesForDevice:(id<MTLDevice>)device;
@end

NS_ASSUME_NONNULL_END
