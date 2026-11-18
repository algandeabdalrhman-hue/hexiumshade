#import "SHKernelCache.h"

static NSString * const SHKernelCacheErrorDomain = @"com.hexiumshade.compute";
static void SHKernelCacheSetError(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SHKernelCacheErrorDomain code:code
                                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface SHKernelCache ()
@property (nonatomic, strong) NSMapTable<id<MTLDevice>, NSMutableDictionary<NSString *, id<MTLComputePipelineState>> *> *deviceCaches;
@end

@implementation SHKernelCache

- (instancetype)init {
    self = [super init];
    if (self) _deviceCaches = [NSMapTable weakToStrongObjectsMapTable];
    return self;
}

- (id<MTLComputePipelineState>)pipelineForFunctionNamed:(NSString *)functionName
                                                library:(id<MTLLibrary>)library
                                                  device:(id<MTLDevice>)device
                                                   error:(NSError **)error {
    if (functionName.length == 0 || !device) {
        SHKernelCacheSetError(error, 1, @"A function name and Metal device are required.");
        return nil;
    }

    id<MTLLibrary> resolvedLibrary = library ?: [device newDefaultLibrary];
    if (!resolvedLibrary || resolvedLibrary.device != device) {
        SHKernelCacheSetError(error, 2, @"The Metal library must belong to the supplied device.");
        return nil;
    }

    // Include library identity so identically named functions in different libraries never collide.
    NSString *key = [NSString stringWithFormat:@"%p:%@", (__bridge void *)resolvedLibrary, functionName];
    @synchronized (self.deviceCaches) {
        NSMutableDictionary *cache = [self.deviceCaches objectForKey:device];
        if (!cache) {
            cache = [NSMutableDictionary dictionary];
            [self.deviceCaches setObject:cache forKey:device];
        }
        id<MTLComputePipelineState> cached = cache[key];
        if (cached) return cached;

        id<MTLFunction> function = [resolvedLibrary newFunctionWithName:functionName];
        if (!function) {
            SHKernelCacheSetError(error, 3, [NSString stringWithFormat:@"Metal function '%@' was not found.", functionName]);
            return nil;
        }

        NSError *pipelineError = nil;
        id<MTLComputePipelineState> pipeline =
            [device newComputePipelineStateWithFunction:function error:&pipelineError];
        if (!pipeline) {
            if (error) *error = pipelineError ?: [NSError errorWithDomain:SHKernelCacheErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey: @"Could not create the compute pipeline state."}];
            return nil;
        }
        cache[key] = pipeline;
        return pipeline;
    }
}

- (void)removeAllPipelinesForDevice:(id<MTLDevice>)device {
    if (!device) return;
    @synchronized (self.deviceCaches) {
        [self.deviceCaches removeObjectForKey:device];
    }
}

@end
