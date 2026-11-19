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
    if (!commandBuffer) {
        SHComputeDispatcherSetError(error, 2, @"Could not create a Metal command buffer.");
        return nil;
    }
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (!encoder) {
        SHComputeDispatcherSetError(error, 3, @"Could not create a Metal compute encoder.");
        return nil;
    }

    [encoder setComputePipelineState:pipeline];
    if (![bindings encodeToComputeEncoder:encoder device:self.device error:error]) {
        [encoder endEncoding];
        return nil;
    }

    // Pick a legal group shape that follows the logical grid dimensions and
    // never exceeds the pipeline's maximum total threads per group.
    NSUInteger maxThreads = MAX((NSUInteger)1, pipeline.maxTotalThreadsPerThreadgroup);
    NSUInteger executionWidth = MAX((NSUInteger)1, pipeline.threadExecutionWidth);
    NSUInteger tx = MIN(gridSize.width, MIN(executionWidth, maxThreads));
    NSUInteger remainingAfterX = MAX((NSUInteger)1, maxThreads / tx);
    NSUInteger ty = MIN(gridSize.height, remainingAfterX);
    NSUInteger remainingAfterY = MAX((NSUInteger)1, remainingAfterX / ty);
    NSUInteger tz = MIN(gridSize.depth, remainingAfterY);
    MTLSize threadsPerGroup = MTLSizeMake(MAX((NSUInteger)1, tx),
                                          MAX((NSUInteger)1, ty),
                                          MAX((NSUInteger)1, tz));

    MTLSize threadgroups = MTLSizeMake(
        (gridSize.width / threadsPerGroup.width) + ((gridSize.width % threadsPerGroup.width) != 0),
        (gridSize.height / threadsPerGroup.height) + ((gridSize.height % threadsPerGroup.height) != 0),
        (gridSize.depth / threadsPerGroup.depth) + ((gridSize.depth % threadsPerGroup.depth) != 0)
    );

    [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerGroup];
    [encoder endEncoding];
    [commandBuffer commit];
    return commandBuffer;
}

@end
