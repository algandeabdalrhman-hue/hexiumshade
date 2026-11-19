#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/// Explicit, fixed-size resource table for SHADES-owned compute passes.
/// Buffer/byte and texture slots are independent; each table supports 16 slots.
@interface SHBindingTable : NSObject
@property (nonatomic, readonly) NSUInteger slotCount;
- (BOOL)setBuffer:(nullable id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setTexture:(nullable id<MTLTexture>)texture atIndex:(NSUInteger)index error:(NSError * _Nullable * _Nullable)error;
- (void)clearAllBindings;
- (BOOL)encodeToComputeEncoder:(id<MTLComputeCommandEncoder>)encoder device:(id<MTLDevice>)device error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
