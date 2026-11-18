#import "SHComputeDispatcher.h"

static NSString * const SHComputeDispatcherErrorDomain = @"com.hexiumshade.compute";
static void SHComputeDispatcherSetError(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SHComputeDispatcherErrorDomain code:code
                                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface SHComputeDispatcher ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) SHKernelCache *kernelCache;
@end

@implementation SHComputeDispatcher

- (instancetype)initWithDevice:(id<MTLDevice>)device commandQueue:(id<MTLCommandQueue>)commandQueue kernelCache:(SHKernelCache *)kernelCache {
    NSParameterAssert(device != nil);
    NSParameterAssert(commandQueue != nil);
    NSParameterAssert(kernelCache != nil);
    NSParameterAssert(commandQueue.device == device);
    self = [super init];
    if (self) {
        _device = device;
        _commandQueue = commandQueue;
        _kernelCache = kernelCache;
    }
    return self;
}

- (id<MTLCommandBuffer>)dispatchFunctionNamed:(NSString *)functionName
                                      library:(id<MTLLibrary>)library
                                     gridSize:(MTLSize)gridSize
                                     bindings:(SHBindingTable *)bindings
                                        error:(NSError **)error {
    if (functionName.length == 0 || !bindings ||
        gridSize.width == 0 || gridSize.height == 0 || gridSize.depth == 0) {
        SHComputeDispatcherSetError(error, 1, @"A function name, binding table, and non-zero 3D grid are required.");
        return nil;
    }

    id<MTLComputePipelineState> pipeline =
        [self.kernelCache pipelineForFunctionNamed:functionName library:library device:self.device error:error];
    if (!pipeline) return nil;

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (!commandBuffer || !encoder) {
        SHComputeDispatcherSetError(error, 2, @"Could not create a command buffer or compute encoder.");
        return nil;
    }

    [encoder setComputePipelineState:pipeline];
    if (![bindings encodeToComputeEncoder:encoder device:self.device error:error]) {
        [encoder endEncoding];
        return nil;
    }

    NSUInteger maxThreads = MAX((NSUInteger)1, pipeline.maxTotalThreadsPerThreadgroup);
    NSUInteger threadWidth = MAX((NSUInteger)1, pipeline.threadExecutionWidth);
    NSUInteger tx = MIN(threadWidth, maxThreads);
    NSUInteger remaining = MAX((NSUInteger)1, maxThreads / tx);
    NSUInteger ty = MIN((NSUInteger)4, remaining);
    NSUInteger tz = MAX((NSUInteger)1, remaining / ty);
    MTLSize threadsPerGroup = MTLSizeMake(tx, ty, tz);

    MTLSize threadgroups = MTLSizeMake(
        (gridSize.width + tx - 1) / tx,
        (gridSize.height + ty - 1) / ty,
        (gridSize.depth + tz - 1) / tz
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerGroup];
    [encoder endEncoding];
    [commandBuffer commit];
    return commandBuffer;
}

@end
