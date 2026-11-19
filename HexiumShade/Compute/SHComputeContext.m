#import "SHComputeContext.h"
#import "SHComputeDispatcher.h"

static NSString * const SHComputeContextErrorDomain = @"com.hexiumshade.compute.context";

static void SHComputeContextSetError(NSError **error, NSInteger code, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:SHComputeContextErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

@interface SHComputeContext ()
@property (nonatomic, strong, readwrite) id<MTLDevice> device;
@property (nonatomic, strong, readwrite) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong, readwrite) SHKernelCache *kernelCache;
@property (nonatomic, strong, readwrite) SHBindingTable *bindings;
@property (nonatomic, strong) SHComputeDispatcher *dispatcher;
@end

@implementation SHComputeContext

- (instancetype)initWithDevice:(id<MTLDevice>)device error:(NSError **)error {
    if (!device) {
        SHComputeContextSetError(error, 1, @"A Metal device is required.");
        return nil;
    }

    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (!queue) {
        SHComputeContextSetError(error, 2, @"Could not create a Metal command queue.");
        return nil;
    }

    self = [super init];
    if (self) {
        _device = device;
        _commandQueue = queue;
        _kernelCache = [[SHKernelCache alloc] init];
        _bindings = [[SHBindingTable alloc] init];
        _dispatcher = [[SHComputeDispatcher alloc] initWithDevice:device
                                                     commandQueue:queue
                                                      kernelCache:_kernelCache];
    }
    return self;
}

- (BOOL)setBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index error:(NSError **)error {
    if (buffer && buffer.device != self.device) {
        SHComputeContextSetError(error, 3, @"The buffer belongs to a different Metal device.");
        return NO;
    }
    return [self.bindings setBuffer:buffer offset:offset atIndex:index error:error];
}

- (BOOL)setBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index error:(NSError **)error {
    return [self.bindings setBytes:bytes length:length atIndex:index error:error];
}

- (BOOL)setTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index error:(NSError **)error {
    if (texture && texture.device != self.device) {
        SHComputeContextSetError(error, 4, @"The texture belongs to a different Metal device.");
        return NO;
    }
    return [self.bindings setTexture:texture atIndex:index error:error];
}

- (id<MTLCommandBuffer>)dispatchFunctionNamed:(NSString *)functionName
                                     library:(id<MTLLibrary>)library
                                    gridSize:(MTLSize)gridSize
                                       error:(NSError **)error {
    return [self.dispatcher dispatchFunctionNamed:functionName
                                           library:library
                                          gridSize:gridSize
                                          bindings:self.bindings
                                             error:error];
}

- (void)clearBindings {
    [self.bindings clearAllBindings];
}

@end
