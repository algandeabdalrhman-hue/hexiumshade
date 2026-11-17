#import "HexiumShade.h"
#import <Foundation/Foundation.h>
#import <simd/simd.h>

static NSString * const HexiumShadeErrorDomain = @"com.hexiumshade.renderer";

static void HexiumShadeAssignError(NSError **error, NSInteger code, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:HexiumShadeErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

static id<MTLComputePipelineState> HexiumShadePipelineForDevice(id<MTLDevice> device, NSError **error) {
    static NSMapTable<id<MTLDevice>, id<MTLComputePipelineState>> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMapTable weakToStrongObjectsMapTable];
    });

    @synchronized (cache) {
        id<MTLComputePipelineState> cached = [cache objectForKey:device];
        if (cached) return cached;

        id<MTLLibrary> library = [device newDefaultLibrary];
        if (!library) {
            HexiumShadeAssignError(error, 2, @"The default Metal library is unavailable. Make sure HexiumShade.metal is included in the target.");
            return nil;
        }

        id<MTLFunction> function = [library newFunctionWithName:@"hexiumshade_color_grade"];
        if (!function) {
            HexiumShadeAssignError(error, 3, @"Metal function hexiumshade_color_grade was not found in the default library.");
            return nil;
        }

        NSError *pipelineError = nil;
        id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&pipelineError];
        if (!pipeline) {
            if (error) *error = pipelineError ?: [NSError errorWithDomain:HexiumShadeErrorDomain
                                                                       code:4
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"Could not create the Metal compute pipeline."}];
            return nil;
        }

        [cache setObject:pipeline forKey:device];
        return pipeline;
    }
}

@implementation HexiumShade
+ (NSString *)version { return @"1.2.0"; }

+ (NSDictionary<NSString *, NSString *> *)parseINI:(NSString *)ini {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *line in [ini componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0 || [trimmed hasPrefix:@";"] || [trimmed hasPrefix:@"#"] || [trimmed hasPrefix:@"["]) continue;
        NSRange separator = [trimmed rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        NSString *key = [[trimmed substringToIndex:separator.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = [[trimmed substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (key.length) settings[key] = value;
    }
    return settings;
}

+ (NSString *)exportINI:(NSDictionary<NSString *, NSString *> *)settings {
    NSMutableString *output = [NSMutableString string];
    for (NSString *key in [[settings allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [output appendFormat:@"%@=%@\n", key, settings[key]];
    }
    return output;
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)presets {
    return @{
        @"Ultra":  @{@"brightness": @0.02, @"contrast": @1.12, @"saturation": @1.12},
        @"High":   @{@"brightness": @0.01, @"contrast": @1.08, @"saturation": @1.08},
        @"Medium": @{@"brightness": @0.00, @"contrast": @1.04, @"saturation": @1.04},
        @"Low":    @{@"brightness": @0.00, @"contrast": @1.00, @"saturation": @1.00}
    };
}

+ (BOOL)setQualityPreset:(NSString *)preset {
    NSDictionary *settings = self.presets[preset];
    if (!settings) return NO;
    [NSUserDefaults.standardUserDefaults setObject:preset forKey:@"HexiumShade.qualityPreset"];
    [NSUserDefaults.standardUserDefaults setObject:settings forKey:@"HexiumShade.qualitySettings"];
    return YES;
}

+ (NSString *)qualityPreset {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"HexiumShade.qualityPreset"];
    return self.presets[saved] ? saved : @"High";
}

+ (NSDictionary<NSString *, NSNumber *> *)qualitySettings {
    return [NSUserDefaults.standardUserDefaults dictionaryForKey:@"HexiumShade.qualitySettings"] ?: self.presets[@"High"];
}

+ (id<MTLTexture>)processTexture:(id<MTLTexture>)input device:(id<MTLDevice>)device commandQueue:(id<MTLCommandQueue>)commandQueue error:(NSError **)error {
    if (!input || !device || !commandQueue) {
        HexiumShadeAssignError(error, 1, @"Input texture, Metal device, and command queue are required.");
        return nil;
    }
    if (input.device != device || commandQueue.device != device) {
        HexiumShadeAssignError(error, 5, @"The input texture, command queue, and device must belong to the same Metal device.");
        return nil;
    }
    if (input.textureType != MTLTextureType2D || input.width == 0 || input.height == 0) {
        HexiumShadeAssignError(error, 6, @"Only non-empty 2D textures are supported.");
        return nil;
    }
    if (input.usage != MTLTextureUsageUnknown && !(input.usage & MTLTextureUsageShaderRead)) {
        HexiumShadeAssignError(error, 7, @"The input texture must allow shader reads.");
        return nil;
    }

    switch (input.pixelFormat) {
        case MTLPixelFormatRGBA8Unorm:
        case MTLPixelFormatBGRA8Unorm:
        case MTLPixelFormatRGBA16Float:
            break;
        default:
            HexiumShadeAssignError(error, 8, @"Unsupported pixel format. Use RGBA8Unorm, BGRA8Unorm, or RGBA16Float.");
            return nil;
    }

    id<MTLComputePipelineState> pipeline = HexiumShadePipelineForDevice(device, error);
    if (!pipeline) return nil;

    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:input.pixelFormat
                                                                                         width:input.width
                                                                                        height:input.height
                                                                                     mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    descriptor.storageMode = MTLStorageModePrivate;
    id<MTLTexture> output = [device newTextureWithDescriptor:descriptor];
    if (!output) {
        HexiumShadeAssignError(error, 9, @"Could not allocate the output texture for this pixel format and device.");
        return nil;
    }

    NSDictionary *settings = self.qualitySettings;
    vector_float4 controls = {
        [(NSNumber *)(settings[@"brightness"] ?: @0.0) floatValue],
        [(NSNumber *)(settings[@"contrast"] ?: @1.0) floatValue],
        [(NSNumber *)(settings[@"saturation"] ?: @1.0) floatValue],
        0.0f
    };

    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (!commandBuffer) {
        HexiumShadeAssignError(error, 10, @"Could not create a Metal command buffer.");
        return nil;
    }
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (!encoder) {
        HexiumShadeAssignError(error, 11, @"Could not create a Metal compute encoder.");
        return nil;
    }

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input atIndex:0];
    [encoder setTexture:output atIndex:1];
    [encoder setBytes:&controls length:sizeof(controls) atIndex:0];

    NSUInteger width = pipeline.threadExecutionWidth;
    NSUInteger height = MAX(1, pipeline.maxTotalThreadsPerThreadgroup / width);
    [encoder dispatchThreads:MTLSizeMake(input.width, input.height, 1)
       threadsPerThreadgroup:MTLSizeMake(width, height, 1)];
    [encoder endEncoding];

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    if (commandBuffer.status == MTLCommandBufferStatusError) {
        if (error) *error = commandBuffer.error ?: [NSError errorWithDomain:HexiumShadeErrorDomain
                                                                          code:12
                                                                      userInfo:@{NSLocalizedDescriptionKey: @"Metal texture processing failed."}];
        return nil;
    }
    return output;
}
@end
