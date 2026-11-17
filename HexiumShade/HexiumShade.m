#import "HexiumShade.h"
#import <Foundation/Foundation.h>
#import <simd/simd.h>

static NSString * const HexiumShadeErrorDomain = @"com.hexiumshade.renderer";

@implementation HexiumShade
+ (NSString *)version { return @"1.1.0"; }

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
        if (error) *error = [NSError errorWithDomain:HexiumShadeErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"Input texture, Metal device, and command queue are required."}];
        return nil;
    }
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> function = [library newFunctionWithName:@"hexiumshade_color_grade"];
    if (!function) {
        if (error) *error = [NSError errorWithDomain:HexiumShadeErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:@"Metal function hexiumshade_color_grade was not found."}];
        return nil;
    }
    NSError *pipelineError = nil;
    id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&pipelineError];
    if (!pipeline) { if (error) *error = pipelineError; return nil; }

    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:input.pixelFormat width:input.width height:input.height mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    descriptor.storageMode = MTLStorageModePrivate;
    id<MTLTexture> output = [device newTextureWithDescriptor:descriptor];
    if (!output) {
        if (error) *error = [NSError errorWithDomain:HexiumShadeErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey:@"Could not allocate output texture."}];
        return nil;
    }

    NSDictionary *settings = self.qualitySettings;
    vector_float4 controls = {settings[@"brightness"].floatValue, settings[@"contrast"].floatValue, settings[@"saturation"].floatValue, 0.0f};
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:input atIndex:0];
    [encoder setTexture:output atIndex:1];
    [encoder setBytes:&controls length:sizeof(controls) atIndex:0];
    NSUInteger w = pipeline.threadExecutionWidth;
    NSUInteger h = MAX(1, pipeline.maxTotalThreadsPerThreadgroup / w);
    [encoder dispatchThreads:MTLSizeMake(input.width, input.height, 1) threadsPerThreadgroup:MTLSizeMake(w, h, 1)];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    if (commandBuffer.status == MTLCommandBufferStatusError) {
        if (error) *error = commandBuffer.error ?: [NSError errorWithDomain:HexiumShadeErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey:@"Metal processing failed."}];
        return nil;
    }
    return output;
}
@end
