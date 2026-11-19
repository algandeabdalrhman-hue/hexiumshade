#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "SHKernelCache.h"
#import "SHBindingTable.h"

NS_ASSUME_NONNULL_BEGIN

/// Dispatches SHADES-owned compute kernels using explicit host-provided resources.
@interface SHComputeDispatcher : NSObject
- (instancetype)initWithDevice:(id<MTLDevice>)device
                   commandQueue:(id<MTLCommandQueue>)commandQueue
                    kernelCache:(SHKernelCache *)kernelCache NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// gridSize is the total logical workload. Threadgroup counts use ceil division.
- (nullable id<MTLCommandBuffer>)dispatchFunctionNamed:(NSString *)functionName
                                               library:(nullable id<MTLLibrary>)library
                                              gridSize:(MTLSize)gridSize
                                              bindings:(SHBindingTable *)bindings
                                                 error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
