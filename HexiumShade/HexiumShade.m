#import "HexiumShade.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <stdint.h>

static NSString * const HexiumShadeErrorDomain = @"com.hexiumshade.renderer";

typedef struct {
    float exposure;
    float contrast;
    float saturation;
    float bloomIntensity;
    float sharpenAmount;
    float ambientIntensity;
    uint32_t flags;
} HexiumShadeUniforms;

enum {
    HexiumEffectBloom = 1u << 0,
    HexiumEffectSharpen = 1u << 1,
    HexiumEffectColorCorrection = 1u << 2,
    HexiumEffectAmbientLight = 1u << 3
};

static float HexiumOption(NSDictionary<NSString *, NSNumber *> *options,
                          NSString *key,
                          float fallback) {
    NSNumber *value = options[key];
    return value ? value.floatValue : fallback;
}

static BOOL HexiumEnabled(NSDictionary<NSString *, NSNumber *> *options,
                          NSString *key) {
    return options[key] ? options[key].boolValue : NO;
}

@implementation HexiumShade

+ (NSString *)version {
    return @"1.1.0";
}

+ (NSDictionary<NSString *, NSString *> *)parseINI:(NSString *)ini {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];

    for (NSString *line in [ini componentsSeparatedByCharactersInSet:
                            NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceCharacterSet];

        if (trimmed.length == 0 ||
            [trimmed hasPrefix:@";"] ||
            [trimmed hasPrefix:@"#"] ||
            [trimmed hasPrefix:@"["]) {
            continue;
        }

        NSRange separator = [trimmed rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;

        NSString *key = [[trimmed substringToIndex:separator.location]
                         stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceCharacterSet];

        NSString *value = [[trimmed substringFromIndex:separator.location + 1]
                           stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceCharacterSet];

        if (key.length > 0) {
            settings[key] = value;
        }
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

+ (BOOL)processTexture:(id<MTLTexture>)source
         outputTexture:(id<MTLTexture>)destination
               options:(NSDictionary<NSString *, NSNumber *> *)options
                 error:(NSError **)error {
    if (!source || !destination ||
        source.width == 0 || source.height == 0 ||
        source.width != destination.width ||
        source.height != destination.height ||
        source.pixelFormat != destination.pixelFormat ||
        source.device != destination.device) {
        if (error) {
            *error = [NSError errorWithDomain:HexiumShadeErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Input and output must be matching, non-empty Metal textures on the same device."}];
        }
        return NO;
    }

    static id<MTLComputePipelineState> pipeline = nil;
    static id<MTLDevice> pipelineDevice = nil;
    static dispatch_once_t onceToken;
    static NSError *pipelineError = nil;

    dispatch_once(&onceToken, ^{
        pipelineDevice = MTLCreateSystemDefaultDevice();
        id<MTLLibrary> library = [pipelineDevice newDefaultLibrary];
        id<MTLFunction> function =
            [library newFunctionWithName:@"hexiumshade_applyEffects"];

        if (!pipelineDevice || !library || !function) {
            pipelineError = [NSError errorWithDomain:HexiumShadeErrorDomain
                                                 code:2
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            @"Could not load the compiled HexiumShade Metal shader library."}];
            return;
        }

        pipeline = [pipelineDevice newComputePipelineStateWithFunction:function
                                                                  error:&pipelineError];
    });

    if (!pipeline || source.device != pipelineDevice) {
        if (error) {
            *error = pipelineError ?: [NSError errorWithDomain:HexiumShadeErrorDomain
                                                           code:3
                                                       userInfo:@{NSLocalizedDescriptionKey:
                                                                      @"The texture device does not match the renderer's Metal device."}];
        }
        return NO;
    }

    HexiumShadeUniforms uniforms = {0};
    uniforms.exposure = HexiumOption(options, @"Exposure", 0.0f);
    uniforms.contrast = HexiumOption(options, @"Contrast", 1.0f);
    uniforms.saturation = HexiumOption(options, @"Saturation", 1.0f);
    uniforms.bloomIntensity = HexiumOption(options, @"BloomIntensity", 0.35f);
    uniforms.sharpenAmount = HexiumOption(options, @"SharpenAmount", 0.35f);
    uniforms.ambientIntensity = HexiumOption(options, @"AmbientIntensity", 0.12f);

    if (HexiumEnabled(options, @"Bloom")) uniforms.flags |= HexiumEffectBloom;
    if (HexiumEnabled(options, @"Sharpen")) uniforms.flags |= HexiumEffectSharpen;
    if (HexiumEnabled(options, @"ColorCorrection")) uniforms.flags |= HexiumEffectColorCorrection;
    if (HexiumEnabled(options, @"AmbientLight")) uniforms.flags |= HexiumEffectAmbientLight;

    id<MTLCommandQueue> queue = [pipelineDevice newCommandQueue];
    id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

    if (!queue || !commandBuffer || !encoder) {
        if (error) {
            *error = [NSError errorWithDomain:HexiumShadeErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Could not create a Metal command encoder."}];
        }
        return NO;
    }

    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:source atIndex:0];
    [encoder setTexture:destination atIndex:1];
    [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];

    NSUInteger width = pipeline.threadExecutionWidth;
    NSUInteger height = MAX(1, pipeline.maxTotalThreadsPerThreadgroup / width);
    MTLSize threadsPerGroup = MTLSizeMake(width, height, 1);
    MTLSize threadgroups = MTLSizeMake((source.width + width - 1) / width,
                                       (source.height + height - 1) / height,
                                       1);

    [encoder dispatchThreadgroups:threadgroups
            threadsPerThreadgroup:threadsPerGroup];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    if (commandBuffer.status == MTLCommandBufferStatusError) {
        if (error) *error = commandBuffer.error ?: [NSError errorWithDomain:HexiumShadeErrorDomain
                                                                        code:5
                                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                                                   @"The Metal processing command failed."}];
        return NO;
    }

    return YES;
}

@end
