#import "HexiumShade.h"
#import <Foundation/Foundation.h>
#import <simd/simd.h>
#include <math.h>

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


static id<MTLComputePipelineState> HexiumShadeMXAOPipelineForDevice(id<MTLDevice> device, NSError **error) {
    static NSMapTable<id<MTLDevice>, id<MTLComputePipelineState>> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMapTable weakToStrongObjectsMapTable]; });
    @synchronized (cache) {
        id<MTLComputePipelineState> cached = [cache objectForKey:device];
        if (cached) return cached;
        id<MTLLibrary> library = [device newDefaultLibrary];
        id<MTLFunction> function = [library newFunctionWithName:@"hexiumshade_mxao"];
        if (!function) {
            HexiumShadeAssignError(error, 40, @"Metal function hexiumshade_mxao was not found in the default library.");
            return nil;
        }
        NSError *pipelineError = nil;
        id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&pipelineError];
        if (!pipeline) {
            if (error) *error = pipelineError ?: [NSError errorWithDomain:HexiumShadeErrorDomain code:41 userInfo:@{NSLocalizedDescriptionKey: @"Could not create the MXAO compute pipeline."}];
            return nil;
        }
        [cache setObject:pipeline forKey:device];
        return pipeline;
    }
}

typedef struct {
    vector_float4 parameters; // radius pixels, intensity, normal bias, depth encoding
    vector_float4 camera;     // near plane, far plane, normal encoding, unused
} HSMXAOControls;


static id<MTLComputePipelineState> HexiumShadeDepthHazePipelineForDevice(id<MTLDevice> device, NSError **error) {
    static NSMapTable<id<MTLDevice>, id<MTLComputePipelineState>> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMapTable weakToStrongObjectsMapTable]; });
    @synchronized (cache) {
        id<MTLComputePipelineState> cached = [cache objectForKey:device];
        if (cached) return cached;
        id<MTLLibrary> library = [device newDefaultLibrary];
        id<MTLFunction> function = [library newFunctionWithName:@"hexiumshade_depth_haze"];
        if (!function) {
            HexiumShadeAssignError(error, 50, @"Metal function hexiumshade_depth_haze was not found in the default library.");
            return nil;
        }
        NSError *pipelineError = nil;
        id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&pipelineError];
        if (!pipeline) {
            if (error) *error = pipelineError ?: [NSError errorWithDomain:HexiumShadeErrorDomain code:51 userInfo:@{NSLocalizedDescriptionKey: @"Could not create the depth haze compute pipeline."}];
            return nil;
        }
        [cache setObject:pipeline forKey:device];
        return pipeline;
    }
}

typedef struct {
    vector_float4 fogColorStart; // RGB fog color, normalized fog start
    vector_float4 depthControls; // fog factor, near, far, depth encoding
} HSDepthHazeControls;


typedef struct {
    vector_float4 focus;  // normalized focus distance, focus range, blur radius, depth encoding
    vector_float4 camera; // near plane, far plane, unused, unused
} HSADOFControls;

static id<MTLComputePipelineState> HexiumShadeADOFPipelineForDevice(id<MTLDevice> device, NSError **error) {
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
            HexiumShadeAssignError(error, 68, @"The default Metal library is unavailable for ADOF.");
            return nil;
        }

        id<MTLFunction> function = [library newFunctionWithName:@"hexiumshade_adof"];
        if (!function) {
            HexiumShadeAssignError(error, 69, @"Metal function hexiumshade_adof was not found in the default library.");
            return nil;
        }

        NSError *pipelineError = nil;
        id<MTLComputePipelineState> pipeline =
            [device newComputePipelineStateWithFunction:function error:&pipelineError];
        if (!pipeline) {
            if (error) *error = pipelineError ?: [NSError errorWithDomain:HexiumShadeErrorDomain
                                                                       code:70
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"Could not create the ADOF compute pipeline."}];
            return nil;
        }

        [cache setObject:pipeline forKey:device];
        return pipeline;
    }
}

@implementation HexiumShade

+ (BOOL)validateFrameInfo:(HSFrameInfo)frameInfo error:(NSError **)error {
    if (!isfinite(frameInfo.nearPlane) || !isfinite(frameInfo.farPlane) ||
        frameInfo.nearPlane <= 0.0f || frameInfo.farPlane <= frameInfo.nearPlane) {
        HexiumShadeAssignError(error, 30, @"Camera near/far planes must be finite, positive, and far must exceed near.");
        return NO;
    }
    if (!isfinite(frameInfo.deltaTime) || frameInfo.deltaTime < 0.0f) {
        HexiumShadeAssignError(error, 31, @"Frame delta time must be finite and non-negative.");
        return NO;
    }
    if (frameInfo.depthEncoding < HSDepthEncodingDeviceZ ||
        frameInfo.depthEncoding > HSDepthEncodingLinearViewDistance ||
        frameInfo.normalEncoding < HSNormalEncodingWorldSpace ||
        frameInfo.normalEncoding > HSNormalEncodingEncoded01) {
        HexiumShadeAssignError(error, 32, @"Unknown depth or normal encoding.");
        return NO;
    }
    for (NSUInteger column = 0; column < 4; column++) {
        for (NSUInteger row = 0; row < 4; row++) {
            if (!isfinite(frameInfo.projectionMatrix.columns[column][row]) ||
                !isfinite(frameInfo.inverseProjectionMatrix.columns[column][row]) ||
                !isfinite(frameInfo.viewMatrix.columns[column][row])) {
                HexiumShadeAssignError(error, 33, @"Camera matrices must contain only finite values.");
                return NO;
            }
        }
    }
    return YES;
}

+ (id<MTLTexture>)newIntermediateTextureWithWidth:(NSUInteger)width
                                           height:(NSUInteger)height
                                      pixelFormat:(MTLPixelFormat)pixelFormat
                                           device:(id<MTLDevice>)device
                                            error:(NSError **)error {
    if (!device || width == 0 || height == 0) {
        HexiumShadeAssignError(error, 34, @"A Metal device and non-zero texture dimensions are required.");
        return nil;
    }
    switch (pixelFormat) {
        case MTLPixelFormatRGBA8Unorm:
        case MTLPixelFormatBGRA8Unorm:
        case MTLPixelFormatRGBA16Float:
        case MTLPixelFormatR16Float:
        case MTLPixelFormatR32Float:
        case MTLPixelFormatRG16Float:
            break;
        default:
            HexiumShadeAssignError(error, 35, @"Unsupported intermediate texture pixel format.");
            return nil;
    }
    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (!texture) {
        HexiumShadeAssignError(error, 36, @"Metal could not allocate the requested intermediate texture.");
        return nil;    }
    return texture;
}


+ (BOOL)validateFrameColorTexture:(id<MTLTexture>)colorTexture
                     depthTexture:(id<MTLTexture>)depthTexture
                    normalTexture:(id<MTLTexture>)normalTexture
              motionVectorTexture:(id<MTLTexture>)motionVectorTexture
                           device:(id<MTLDevice>)device
                            error:(NSError **)error {
    if (!colorTexture || !device) {
        HexiumShadeAssignError(error, 20, @"A color texture and Metal device are required.");
        return NO;
    }
    if (colorTexture.device != device || colorTexture.textureType != MTLTextureType2D ||
        colorTexture.width == 0 || colorTexture.height == 0) {
        HexiumShadeAssignError(error, 21, @"The color texture must be a non-empty 2D texture from the supplied Metal device.");
        return NO;
    }
    if (colorTexture.usage != MTLTextureUsageUnknown && !(colorTexture.usage & MTLTextureUsageShaderRead)) {
        HexiumShadeAssignError(error, 22, @"The color texture must allow shader reads.");
        return NO;
    }

    NSArray *auxiliary = @[
        depthTexture ?: (id)[NSNull null],
        normalTexture ?: (id)[NSNull null],
        motionVectorTexture ?: (id)[NSNull null]
    ];
    for (id candidate in auxiliary) {
        if (candidate == [NSNull null]) continue;
        id<MTLTexture> texture = candidate;
        if (texture.device != device || texture.textureType != MTLTextureType2D ||
            texture.width != colorTexture.width || texture.height != colorTexture.height) {
            HexiumShadeAssignError(error, 23, @"All frame textures must be 2D, use the same Metal device, and match the color texture dimensions.");
            return NO;
        }
        if (texture.usage != MTLTextureUsageUnknown && !(texture.usage & MTLTextureUsageShaderRead)) {
            HexiumShadeAssignError(error, 24, @"Every supplied auxiliary texture must allow shader reads.");
            return NO;
        }
    }

    if (depthTexture && depthTexture.pixelFormat != MTLPixelFormatDepth32Float &&
        depthTexture.pixelFormat != MTLPixelFormatR32Float) {
        HexiumShadeAssignError(error, 25, @"Depth input must use Depth32Float or R32Float.");
        return NO;
    }
    if (normalTexture && normalTexture.pixelFormat != MTLPixelFormatRGBA8Unorm &&
        normalTexture.pixelFormat != MTLPixelFormatRGBA16Float) {
        HexiumShadeAssignError(error, 26, @"Normal input must use RGBA8Unorm or RGBA16Float.");
        return NO;
    }
    if (motionVectorTexture && motionVectorTexture.pixelFormat != MTLPixelFormatRG16Float &&
        motionVectorTexture.pixelFormat != MTLPixelFormatRG32Float &&
        motionVectorTexture.pixelFormat != MTLPixelFormatRGBA16Float) {
        HexiumShadeAssignError(error, 27, @"Motion vectors must use RG16Float, RG32Float, or RGBA16Float.");
        return NO;
    }
    return YES;
}

+ (id<MTLTexture>)processFrameColorTexture:(id<MTLTexture>)colorTexture
                              depthTexture:(id<MTLTexture>)depthTexture
                             normalTexture:(id<MTLTexture>)normalTexture
                       motionVectorTexture:(id<MTLTexture>)motionVectorTexture
                                    device:(id<MTLDevice>)device
                              commandQueue:(id<MTLCommandQueue>)commandQueue
                                     error:(NSError **)error {
    HSFrameInfo frameInfo = {
        .projectionMatrix = matrix_identity_float4x4,
        .inverseProjectionMatrix = matrix_identity_float4x4,
        .viewMatrix = matrix_identity_float4x4,
        .nearPlane = 0.1f,
        .farPlane = 1000.0f,
        .deltaTime = 0.0f,
        .depthEncoding = HSDepthEncodingDeviceZ,
        .normalEncoding = HSNormalEncodingWorldSpace
    };
    return [self processFrameColorTexture:colorTexture
                             depthTexture:depthTexture
                            normalTexture:normalTexture
                      motionVectorTexture:motionVectorTexture
                                frameInfo:frameInfo
                                   device:device
                             commandQueue:commandQueue
                                    error:error];
}

+ (id<MTLTexture>)processFrameColorTexture:(id<MTLTexture>)colorTexture
                              depthTexture:(id<MTLTexture>)depthTexture
                             normalTexture:(id<MTLTexture>)normalTexture
                       motionVectorTexture:(id<MTLTexture>)motionVectorTexture
                                 frameInfo:(HSFrameInfo)frameInfo
                                    device:(id<MTLDevice>)device
                              commandQueue:(id<MTLCommandQueue>)commandQueue
                                     error:(NSError **)error {
    if (![self validateFrameColorTexture:colorTexture depthTexture:depthTexture normalTexture:normalTexture motionVectorTexture:motionVectorTexture device:device error:error]) return nil;
    if (!commandQueue || commandQueue.device != device) {
        HexiumShadeAssignError(error, 28, @"The command queue must belong to the supplied Metal device.");
        return nil;
    }
    if (![self validateFrameInfo:frameInfo error:error]) return nil;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary<NSString *, NSNumber *> *states =
        [defaults dictionaryForKey:@"HexiumShade.effectStates"] ?: @{};
    NSString *ini = [defaults stringForKey:@"HexiumShade.importedPresetINI"] ?: @"";
    NSDictionary<NSString *, NSString *> *preset = [self parseINI:ini];

    id<MTLTexture> current = [self processTexture:colorTexture
                                           device:device
                                     commandQueue:commandQueue
                                            error:error];
    if (!current) return nil;

    BOOL mxaoEnabled = [states[@"MXAO"] boolValue];
    BOOL hazeEnabled = [states[@"DepthHaze"] boolValue];
    BOOL adofEnabled = [states[@"ADOF"] boolValue];
    BOOL ssrEnabled = [states[@"SSR"] boolValue];

    if (mxaoEnabled) {
        if (!depthTexture || !normalTexture) {
            HexiumShadeAssignError(error, 80, @"MXAO is enabled but the host did not supply both depth and normal textures.");
            return nil;
        }
        current = [self applyMXAOToColorTexture:current
                                   depthTexture:depthTexture
                                  normalTexture:normalTexture
                                  depthEncoding:frameInfo.depthEncoding
                                 normalEncoding:frameInfo.normalEncoding
                                      nearPlane:frameInfo.nearPlane
                                       farPlane:frameInfo.farPlane
                                         radius:MIN(MAX([preset[@"MXAO_RADIUS"] floatValue] ?: 6.0f, 1.0f), 32.0f)
                                      intensity:MIN(MAX([preset[@"MXAO_INTENSITY"] floatValue] ?: 1.15f, 0.0f), 8.0f)
                                    normalBias:MIN(MAX([preset[@"MXAO_BIAS"] floatValue] ?: 0.025f, 0.0f), 1.0f)
                                          device:device
                                    commandQueue:commandQueue
                                           error:error];
        if (!current) return nil;
    }

    if (hazeEnabled) {
        if (!depthTexture) {
            HexiumShadeAssignError(error, 81, @"DepthHaze is enabled but the host did not supply a depth texture.");
            return nil;
        }
        vector_float3 fogColor = (vector_float3){0.56f, 0.67f, 0.82f};
        current = [self applyDepthHazeToColorTexture:current
                                       depthTexture:depthTexture
                                      depthEncoding:frameInfo.depthEncoding
                                          nearPlane:frameInfo.nearPlane
                                           fogStart:MIN(MAX([preset[@"DEPTHHAZE_START"] floatValue] ?: 0.55f, 0.0f), 1.0f)
                                          fogFactor:MIN(MAX([preset[@"DEPTHHAZE_FACTOR"] floatValue] ?: 0.35f, 0.001f), 1.0f)
                                           fogColor:fogColor
                                             device:device
                                       commandQueue:commandQueue
                                              error:error];
        if (!current) return nil;
    }

    if (adofEnabled) {
        if (!depthTexture) {
            HexiumShadeAssignError(error, 82, @"ADOF is enabled but the host did not supply a depth texture.");
            return nil;
        }
        current = [self applyADOFToColorTexture:current
                                    depthTexture:depthTexture
                                   depthEncoding:frameInfo.depthEncoding
                                       nearPlane:frameInfo.nearPlane
                                        farPlane:frameInfo.farPlane
                                   focusDistance:MIN(MAX([preset[@"ADOF_FOCUS"] floatValue] ?: 0.5f, 0.0f), 1.0f)
                                      focusRange:MIN(MAX([preset[@"ADOF_RANGE"] floatValue] ?: 0.12f, 0.0f), 0.99f)
                                      blurRadius:MIN(MAX([preset[@"ADOF_RADIUS"] floatValue] ?: 6.0f, 0.0f), 12.0f)
                                           device:device
                                     commandQueue:commandQueue
                                            error:error];
        if (!current) return nil;
    }

    if (ssrEnabled) {
        HexiumShadeAssignError(error, 83, @"SSR is selected in the preset, but no Metal SSR kernel is implemented yet.");
        return nil;
    }

    return current;
}


+ (id<MTLTexture>)applyMXAOToColorTexture:(id<MTLTexture>)colorTexture
                             depthTexture:(id<MTLTexture>)depthTexture
                            normalTexture:(id<MTLTexture>)normalTexture
                            depthEncoding:(HSDepthEncoding)depthEncoding
                           normalEncoding:(HSNormalEncoding)normalEncoding
                                nearPlane:(float)nearPlane
                                 farPlane:(float)farPlane
                                   radius:(float)radius
                                 intensity:(float)intensity
                               normalBias:(float)normalBias
                                   device:(id<MTLDevice>)device
                             commandQueue:(id<MTLCommandQueue>)commandQueue
                                    error:(NSError **)error {
    if (![self validateFrameColorTexture:colorTexture depthTexture:depthTexture normalTexture:normalTexture motionVectorTexture:nil device:device error:error]) return nil;
    if (!depthTexture || !normalTexture) {
        HexiumShadeAssignError(error, 42, @"MXAO requires both depth and normal textures from the host renderer.");
        return nil;
    }
    if (!commandQueue || commandQueue.device != device) {
        HexiumShadeAssignError(error, 43, @"The command queue must belong to the supplied Metal device.");
        return nil;
    }
    if (depthEncoding < HSDepthEncodingDeviceZ || depthEncoding > HSDepthEncodingLinearViewDistance ||
        normalEncoding < HSNormalEncodingWorldSpace || normalEncoding > HSNormalEncodingEncoded01 ||
        !isfinite(nearPlane) || !isfinite(farPlane) || nearPlane <= 0.0f || farPlane <= nearPlane ||
        !isfinite(radius) || radius <= 0.0f || !isfinite(intensity) || intensity < 0.0f ||
        !isfinite(normalBias) || normalBias < 0.0f) {
        HexiumShadeAssignError(error, 44, @"MXAO camera metadata and controls are outside their valid ranges.");
        return nil;
    }
    id<MTLComputePipelineState> pipeline = HexiumShadeMXAOPipelineForDevice(device, error);
    if (!pipeline) return nil;
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:colorTexture.pixelFormat
                                                                                         width:colorTexture.width
                                                                                        height:colorTexture.height
                                                                                     mipmapped:NO];
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output = [device newTextureWithDescriptor:descriptor];
    if (!output) {
        HexiumShadeAssignError(error, 45, @"Could not allocate the MXAO output texture.");
        return nil;
    }
    HSMXAOControls controls = {
        .parameters = { fminf(radius, 32.0f), fminf(intensity, 8.0f), fminf(normalBias, 1.0f), (float)depthEncoding },
        .camera = { nearPlane, farPlane, (float)normalEncoding, 0.0f }
    };
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (!commandBuffer || !encoder) {
        HexiumShadeAssignError(error, 46, @"Could not create the MXAO command buffer or compute encoder.");
        return nil;
    }
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:colorTexture atIndex:0];
    [encoder setTexture:depthTexture atIndex:1];
    [encoder setTexture:normalTexture atIndex:2];
    [encoder setTexture:output atIndex:3];
    [encoder setBytes:&controls length:sizeof(controls) atIndex:0];
    NSUInteger tw = pipeline.threadExecutionWidth;
    NSUInteger th = MAX(1, pipeline.maxTotalThreadsPerThreadgroup / tw);
    [encoder dispatchThreads:MTLSizeMake(colorTexture.width, colorTexture.height, 1)
       threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    if (commandBuffer.status == MTLCommandBufferStatusError) {
        if (error) *error = commandBuffer.error ?: [NSError errorWithDomain:HexiumShadeErrorDomain code:47 userInfo:@{NSLocalizedDescriptionKey: @"MXAO processing failed."}];
        return nil;
    }
    return output;
}



+ (id<MTLTexture>)applyADOFToColorTexture:(id<MTLTexture>)colorTexture
                            depthTexture:(id<MTLTexture>)depthTexture
                           depthEncoding:(HSDepthEncoding)depthEncoding
                               nearPlane:(float)nearPlane
                                farPlane:(float)farPlane
                            focusDistance:(float)focusDistance
                                focusRange:(float)focusRange
                                blurRadius:(float)blurRadius
                                    device:(id<MTLDevice>)device
                              commandQueue:(id<MTLCommandQueue>)commandQueue
                                     error:(NSError **)error {
    if (![self validateFrameColorTexture:colorTexture depthTexture:depthTexture normalTexture:nil motionVectorTexture:nil device:device error:error]) return nil;
    if (!depthTexture) {
        HexiumShadeAssignError(error, 62, @"ADOF requires a readable depth texture supplied by the host renderer.");
        return nil;
    }
    if (!commandQueue || commandQueue.device != device) {
        HexiumShadeAssignError(error, 63, @"The command queue must belong to the supplied Metal device.");
        return nil;
    }
    if (depthEncoding < HSDepthEncodingDeviceZ || depthEncoding > HSDepthEncodingLinearViewDistance ||
        !isfinite(nearPlane) || !isfinite(farPlane) || nearPlane <= 0.0f || farPlane <= nearPlane ||
        !isfinite(focusDistance) || focusDistance < 0.0f || focusDistance > 1.0f ||
        !isfinite(focusRange) || focusRange < 0.0f || focusRange >= 1.0f ||
        !isfinite(blurRadius) || blurRadius < 0.0f || blurRadius > 12.0f) {
        HexiumShadeAssignError(error, 64, @"ADOF camera metadata and controls are outside their valid ranges.");
        return nil;
    }
    id<MTLComputePipelineState> pipeline = HexiumShadeADOFPipelineForDevice(device, error);
    if (!pipeline) return nil;
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:colorTexture.pixelFormat
                                                                                         width:colorTexture.width
                                                                                        height:colorTexture.height
                                                                                     mipmapped:NO];
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output = [device newTextureWithDescriptor:descriptor];
    if (!output) {
        HexiumShadeAssignError(error, 65, @"Could not allocate the ADOF output texture.");
        return nil;
    }
    HSADOFControls controls = {
        .focus = { focusDistance, focusRange, blurRadius, (float)depthEncoding },
        .camera = { nearPlane, farPlane, 0.0f, 0.0f }
    };
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (!commandBuffer || !encoder) {
        HexiumShadeAssignError(error, 66, @"Could not create the ADOF command buffer or compute encoder.");
        return nil;
    }
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:colorTexture atIndex:0];
    [encoder setTexture:depthTexture atIndex:1];
    [encoder setTexture:output atIndex:2];
    [encoder setBytes:&controls length:sizeof(controls) atIndex:0];
    NSUInteger tw = pipeline.threadExecutionWidth;
    NSUInteger th = MAX(1, pipeline.maxTotalThreadsPerThreadgroup / tw);
    [encoder dispatchThreads:MTLSizeMake(colorTexture.width, colorTexture.height, 1)
       threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    if (commandBuffer.status == MTLCommandBufferStatusError) {        if (error) *error = commandBuffer.error ?: [NSError errorWithDomain:HexiumShadeErrorDomain code:67 userInfo:@{NSLocalizedDescriptionKey: @"ADOF processing failed."}];
        return nil;
    }
    return output;
}

+ (id<MTLTexture>)applyDepthHazeToColorTexture:(id<MTLTexture>)colorTexture
                                  depthTexture:(id<MTLTexture>)depthTexture
                                 depthEncoding:(HSDepthEncoding)depthEncoding
                                     nearPlane:(float)nearPlane
                                      farPlane:(float)farPlane
                                      fogStart:(float)fogStart
                                     fogFactor:(float)fogFactor
                                      fogColor:(vector_float3)fogColor
                                        device:(id<MTLDevice>)device
                                  commandQueue:(id<MTLCommandQueue>)commandQueue
                                         error:(NSError **)error {
    if (![self validateFrameColorTexture:colorTexture depthTexture:depthTexture normalTexture:nil motionVectorTexture:nil device:device error:error]) return nil;
    if (!depthTexture) {
        HexiumShadeAssignError(error, 52, @"Depth haze requires a readable depth texture supplied by the host renderer.");
        return nil;
    }
    if (!commandQueue || commandQueue.device != device) {
        HexiumShadeAssignError(error, 53, @"The command queue must belong to the supplied Metal device.");
        return nil;
    }
    if (depthEncoding < HSDepthEncodingDeviceZ || depthEncoding > HSDepthEncodingLinearViewDistance ||
        !isfinite(nearPlane) || !isfinite(farPlane) || nearPlane <= 0.0f || farPlane <= nearPlane ||
        !isfinite(fogStart) || fogStart < 0.0f || fogStart > 1.0f ||
        !isfinite(fogFactor) || fogFactor <= 0.0f || fogFactor > 1.0f ||
        !isfinite(fogColor.x) || !isfinite(fogColor.y) || !isfinite(fogColor.z)) {
        HexiumShadeAssignError(error, 54, @"Depth haze settings or camera metadata are outside their valid ranges.");
        return nil;
    }
    id<MTLComputePipelineState> pipeline = HexiumShadeDepthHazePipelineForDevice(device, error);
    if (!pipeline) return nil;
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:colorTexture.pixelFormat
                                                                                         width:colorTexture.width
                                                                                        height:colorTexture.height
                                                                                     mipmapped:NO];
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> output = [device newTextureWithDescriptor:descriptor];
    if (!output) {
        HexiumShadeAssignError(error, 55, @"Could not allocate the depth haze output texture.");
        return nil;
    }
    HSDepthHazeControls controls = {
        .fogColorStart = { fogColor.x, fogColor.y, fogColor.z, fogStart },
        .depthControls = { fogFactor, nearPlane, farPlane, (float)depthEncoding }
    };
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (!commandBuffer) {
        HexiumShadeAssignError(error, 56, @"Could not create the depth haze command buffer.");
        return nil;
    }
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (!encoder) {
        HexiumShadeAssignError(error, 57, @"Could not create the depth haze compute encoder.");
        return nil;
    }
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:colorTexture atIndex:0];
    [encoder setTexture:depthTexture atIndex:1];
    [encoder setTexture:output atIndex:2];
    [encoder setBytes:&controls length:sizeof(controls) atIndex:0];
    NSUInteger tw = pipeline.threadExecutionWidth;
    NSUInteger th = MAX(1, pipeline.maxTotalThreadsPerThreadgroup / tw);
    [encoder dispatchThreads:MTLSizeMake(colorTexture.width, colorTexture.height, 1)
       threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    if (commandBuffer.status == MTLCommandBufferStatusError) {
        if (error) *error = commandBuffer.error ?: [NSError errorWithDomain:HexiumShadeErrorDomain code:58 userInfo:@{NSLocalizedDescriptionKey: @"Depth haze processing failed."}];
        return nil;
    }
    return output;
}

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