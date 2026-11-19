#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "SHBindingTable.h"
#import "SHKernelCache.h"

NS_ASSUME_NONNULL_BEGIN

/// Owns the device, command queue, pipeline cache, and fixed resource bindings
/// for SHADES-owned compute work. Each dispatch creates a fresh encoder, so
/// all current bindings are replayed onto that encoder before dispatch.
@interface SHComputeContext : NSObject

@property (nonatomic, strong, readonly) id<MTLDevice> device;
@property (nonatomic, strong, readonly) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong, readonly) SHKernelCache *kernelCache;
@property (nonatomic, strong, readonly) SHBindingTable *bindings;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                                  error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)setBuffer:(nullable id<MTLBuffer>)buffer
           offset:(NSUInteger)offset
          atIndex:(NSUInteger)index
            error:(NSError * _Nullable * _Nullable)error;

- (BOOL)setBytes:(const void *)bytes
          length:(NSUInteger)length
         atIndex:(NSUInteger)index
           error:(NSError * _Nullable * _Nullable)error;

- (BOOL)setTexture:(nullable id<MTLTexture>)texture
           atIndex:(NSUInteger)index
             error:(NSError * _Nullable * _Nullable)error;

/// Encodes and commits a dispatch without blocking the calling thread.
/// The returned command buffer can be observed or waited on by the caller.
- (nullable id<MTLCommandBuffer>)dispatchFunctionNamed:(NSString *)functionName
                                               library:(nullable id<MTLLibrary>)library
                                              gridSize:(MTLSize)gridSize
                                                 error:(NSError * _Nullable * _Nullable)error;

- (void)clearBindings;

@end

NS_ASSUME_NONNULL_END
