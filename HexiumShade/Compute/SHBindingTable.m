#import "SHBindingTable.h"

static NSString * const SHBindingTableErrorDomain = @"com.hexiumshade.compute";
static const NSUInteger SHBindingTableSlotCount = 16;

static void SHBindingTableSetError(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SHBindingTableErrorDomain code:code
                                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface SHBindingTable ()
@property (nonatomic, strong) NSMutableArray *buffers;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *bufferOffsets;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *bufferDirty;
@property (nonatomic, strong) NSMutableArray *byteData;
@property (nonatomic, strong) NSMutableArray *textures;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *textureDirty;
@end

@implementation SHBindingTable

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffers = [NSMutableArray arrayWithCapacity:SHBindingTableSlotCount];
        _bufferOffsets = [NSMutableArray arrayWithCapacity:SHBindingTableSlotCount];
        _bufferDirty = [NSMutableArray arrayWithCapacity:SHBindingTableSlotCount];
        _byteData = [NSMutableArray arrayWithCapacity:SHBindingTableSlotCount];
        _textures = [NSMutableArray arrayWithCapacity:SHBindingTableSlotCount];
        _textureDirty = [NSMutableArray arrayWithCapacity:SHBindingTableSlotCount];
        for (NSUInteger i = 0; i < SHBindingTableSlotCount; i++) {
            [_buffers addObject:[NSNull null]];
            [_bufferOffsets addObject:@0];
            [_bufferDirty addObject:@YES];
            [_byteData addObject:[NSNull null]];
            [_textures addObject:[NSNull null]];
            [_textureDirty addObject:@YES];
        }
    }
    return self;
}

- (NSUInteger)slotCount { return SHBindingTableSlotCount; }

- (BOOL)validIndex:(NSUInteger)index error:(NSError **)error {
    if (index >= SHBindingTableSlotCount) {
        SHBindingTableSetError(error, 1, @"Binding index must be between 0 and 15.");
        return NO;
    }
    return YES;
}

- (BOOL)setBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index error:(NSError **)error {
    if (![self validIndex:index error:error]) return NO;
    if (buffer && offset > buffer.length) {
        SHBindingTableSetError(error, 2, @"Buffer offset exceeds the buffer length.");
        return NO;
    }
    @synchronized (self) {
        self.buffers[index] = buffer ?: (id)[NSNull null];
        self.bufferOffsets[index] = @(offset);
        self.byteData[index] = [NSNull null];
        self.bufferDirty[index] = @YES;
    }
    return YES;
}

- (BOOL)setBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index error:(NSError **)error {
    if (![self validIndex:index error:error]) return NO;
    if (!bytes || length == 0 || length > 4096) {
        SHBindingTableSetError(error, 3, @"Inline buffer data must be non-null and between 1 and 4096 bytes.");
        return NO;
    }
    @synchronized (self) {
        self.buffers[index] = [NSNull null];
        self.bufferOffsets[index] = @0;
        self.byteData[index] = [NSData dataWithBytes:bytes length:length];
        self.bufferDirty[index] = @YES;
    }
    return YES;
}

- (BOOL)setTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index error:(NSError **)error {
    if (![self validIndex:index error:error]) return NO;
    @synchronized (self) {
        self.textures[index] = texture ?: (id)[NSNull null];
        self.textureDirty[index] = @YES;
    }
    return YES;
}

- (void)clearAllBindings {
    @synchronized (self) {
        for (NSUInteger i = 0; i < SHBindingTableSlotCount; i++) {
            self.buffers[i] = [NSNull null];
            self.bufferOffsets[i] = @0;
            self.byteData[i] = [NSNull null];
            self.bufferDirty[i] = @YES;
            self.textures[i] = [NSNull null];
            self.textureDirty[i] = @YES;
        }
    }
}

- (BOOL)encodeToComputeEncoder:(id<MTLComputeCommandEncoder>)encoder device:(id<MTLDevice>)device error:(NSError **)error {
    if (!encoder || !device) {
        SHBindingTableSetError(error, 4, @"A compute encoder and Metal device are required.");
        return NO;
    }

    // Metal argument bindings belong to a command encoder, not to this table.
    // A fresh encoder starts unbound, so replay every slot on every dispatch.
    // Dirty flags track table mutations for diagnostics/future batching only;
    // they must never suppress a bind on a newly-created encoder.
    @synchronized (self) {
        for (NSUInteger i = 0; i < SHBindingTableSlotCount; i++) {
            id bytes = self.byteData[i];
            id buffer = self.buffers[i];
            if (bytes != [NSNull null]) {
                NSData *data = bytes;
                [encoder setBytes:data.bytes length:data.length atIndex:i];
            } else if (buffer != [NSNull null]) {
                id<MTLBuffer> metalBuffer = buffer;
                if (metalBuffer.device != device) {
                    SHBindingTableSetError(error, 5, @"A bound buffer belongs to a different Metal device.");
                    return NO;
                }
                [encoder setBuffer:metalBuffer offset:self.bufferOffsets[i].unsignedIntegerValue atIndex:i];
            } else {
                [encoder setBuffer:nil offset:0 atIndex:i];
            }
            self.bufferDirty[i] = @NO;

            id texture = self.textures[i];
            if (texture != [NSNull null] && ((id<MTLTexture>)texture).device != device) {
                SHBindingTableSetError(error, 6, @"A bound texture belongs to a different Metal device.");
                return NO;
            }
            [encoder setTexture:(texture == [NSNull null] ? nil : texture) atIndex:i];
            self.textureDirty[i] = @NO;
        }
    }
    return YES;
}

@end
