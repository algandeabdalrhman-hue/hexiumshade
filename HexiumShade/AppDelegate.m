#import "AppDelegate.h"
#import "HexiumShadeOverlay.h"
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>

typedef struct {
    float exposure, contrast, saturation, bloomIntensity, sharpenAmount, ambientIntensity;
    uint32_t flags;
} HSUniforms;

enum { HSBloom=1u<<0, HSSharpen=1u<<1, HSColor=1u<<2, HSAmbient=1u<<3 };

@interface HexiumShadeRenderer : NSObject <MTKViewDelegate>
@property(nonatomic,strong) id<MTLDevice> device;
@property(nonatomic,strong) id<MTLCommandQueue> queue;
@property(nonatomic,strong) id<MTLRenderPipelineState> scenePipeline;
@property(nonatomic,strong) id<MTLRenderPipelineState> displayPipeline;
@property(nonatomic,strong) id<MTLComputePipelineState> effectPipeline;
@property(nonatomic,strong) id<MTLSamplerState> sampler;
@property(nonatomic,strong) id<MTLTexture> sourceTexture;
@property(nonatomic,strong) id<MTLTexture> outputTexture;
@property(nonatomic,strong) NSDictionary<NSString *,NSNumber *> *options;
@property(nonatomic) CFTimeInterval startTime;
@property(nonatomic) NSUInteger textureWidth;
@property(nonatomic) NSUInteger textureHeight;
- (instancetype)initWithView:(MTKView *)view;
- (void)applyOptions:(NSDictionary<NSString *,NSNumber *> *)options;
@end

@implementation HexiumShadeRenderer
- (instancetype)initWithView:(MTKView *)view {
    if ((self=[super init])) {
        _device=MTLCreateSystemDefaultDevice();
        if (!_device) return nil;
        _queue=[_device newCommandQueue];
        view.device=_device;
        view.delegate=self;
        view.paused=NO;
        view.enableSetNeedsDisplay=NO;
        view.preferredFramesPerSecond=60;
        view.framebufferOnly=NO;
        view.colorPixelFormat=MTLPixelFormatBGRA8Unorm;
        NSError *error=nil;
        id<MTLLibrary> lib=[_device newDefaultLibrary];
        id<MTLFunction> sceneV=[lib newFunctionWithName:@"hexium_sceneVertex"];
        id<MTLFunction> sceneF=[lib newFunctionWithName:@"hexium_sceneFragment"];
        id<MTLFunction> displayV=[lib newFunctionWithName:@"hexium_displayVertex"];
        id<MTLFunction> displayF=[lib newFunctionWithName:@"hexium_displayFragment"];
        id<MTLFunction> effect=[lib newFunctionWithName:@"hexiumshade_applyEffects"];
        MTLRenderPipelineDescriptor *scene=[MTLRenderPipelineDescriptor new];
        scene.vertexFunction=sceneV; scene.fragmentFunction=sceneF;
        scene.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
        _scenePipeline=[_device newRenderPipelineStateWithDescriptor:scene error:&error];
        if (!_scenePipeline) return nil;
        MTLRenderPipelineDescriptor *display=[MTLRenderPipelineDescriptor new];
        display.vertexFunction=displayV; display.fragmentFunction=displayF;
        display.colorAttachments[0].pixelFormat=view.colorPixelFormat;
        _displayPipeline=[_device newRenderPipelineStateWithDescriptor:display error:&error];
        if (!_displayPipeline) return nil;
        _effectPipeline=[_device newComputePipelineStateWithFunction:effect error:&error];
        if (!_effectPipeline) return nil;
        MTLSamplerDescriptor *sd=[MTLSamplerDescriptor new];
        sd.minFilter=MTLSamplerMinMagFilterLinear; sd.magFilter=MTLSamplerMinMagFilterLinear;
        _sampler=[_device newSamplerStateWithDescriptor:sd];
        _options=@{@"Quality":@2,@"Bloom":@1,@"Sharpen":@1,@"ColorCorrection":@1,@"AmbientLight":@1,
                   @"Exposure":@0.08,@"Contrast":@1.08,@"Saturation":@1.08,
                   @"BloomIntensity":@0.32,@"SharpenAmount":@0.28,@"AmbientIntensity":@0.10};
        _startTime=CACurrentMediaTime();
    }
    return self;
}
- (void)applyOptions:(NSDictionary<NSString *,NSNumber *> *)options {
    NSMutableDictionary *merged=[self.options mutableCopy] ?: [NSMutableDictionary dictionary];
    [merged addEntriesFromDictionary:options];
    self.options=[merged copy];
}
- (void)ensureTexturesForView:(MTKView *)view {
    NSUInteger scaleQuality=self.options[@"Quality"] ? self.options[@"Quality"].unsignedIntegerValue : 2;
    CGFloat scale=(scaleQuality==3 ? 1.0 : scaleQuality==2 ? 0.85 : scaleQuality==1 ? 0.68 : 0.50);
    NSUInteger w=MAX(1,(NSUInteger)(view.drawableSize.width*scale));
    NSUInteger h=MAX(1,(NSUInteger)(view.drawableSize.height*scale));
    if (w==self.textureWidth && h==self.textureHeight && self.sourceTexture && self.outputTexture) return;
    self.textureWidth=w; self.textureHeight=h;
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:w height:h mipmapped:NO];
    td.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    td.storageMode=MTLStorageModePrivate;
    self.sourceTexture=[self.device newTextureWithDescriptor:td];
    self.outputTexture=[self.device newTextureWithDescriptor:td];
}
- (void)drawInMTKView:(MTKView *)view {
    if (!view.currentDrawable || !view.currentRenderPassDescriptor) return;
    [self ensureTexturesForView:view];
    if (!self.sourceTexture || !self.outputTexture) return;
    id<MTLCommandBuffer> cb=[self.queue commandBuffer];
    MTLRenderPassDescriptor *scenePass=[MTLRenderPassDescriptor renderPassDescriptor];
    scenePass.colorAttachments[0].texture=self.sourceTexture;
    scenePass.colorAttachments[0].loadAction=MTLLoadActionClear;
    scenePass.colorAttachments[0].storeAction=MTLStoreActionStore;
    scenePass.colorAttachments[0].clearColor=MTLClearColorMake(0.015,0.025,0.055,1);
    id<MTLRenderCommandEncoder> se=[cb renderCommandEncoderWithDescriptor:scenePass];
    [se setRenderPipelineState:self.scenePipeline];
    float time=(float)(CACurrentMediaTime()-self.startTime);
    [se setFragmentBytes:&time length:sizeof(time) atIndex:0];
    [se drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [se endEncoding];

    HSUniforms u={0};
    u.exposure=self.options[@"Exposure"].floatValue;
    u.contrast=self.options[@"Contrast"] ? self.options[@"Contrast"].floatValue : 1.0;
    u.saturation=self.options[@"Saturation"] ? self.options[@"Saturation"].floatValue : 1.0;
    u.bloomIntensity=self.options[@"BloomIntensity"].floatValue;
    u.sharpenAmount=self.options[@"SharpenAmount"].floatValue;
    u.ambientIntensity=self.options[@"AmbientIntensity"].floatValue;
    if (self.options[@"Bloom"].boolValue) u.flags|=HSBloom;
    if (self.options[@"Sharpen"].boolValue) u.flags|=HSSharpen;
    if (self.options[@"ColorCorrection"].boolValue) u.flags|=HSColor;
    if (self.options[@"AmbientLight"].boolValue) u.flags|=HSAmbient;
    id<MTLComputeCommandEncoder> ce=[cb computeCommandEncoder];
    [ce setComputePipelineState:self.effectPipeline];
    [ce setTexture:self.sourceTexture atIndex:0];
    [ce setTexture:self.outputTexture atIndex:1];
    [ce setBytes:&u length:sizeof(u) atIndex:0];
    NSUInteger tw=self.effectPipeline.threadExecutionWidth;
    NSUInteger th=MAX(1,self.effectPipeline.maxTotalThreadsPerThreadgroup/tw);
    [ce dispatchThreads:MTLSizeMake(self.textureWidth,self.textureHeight,1)
  threadsPerThreadgroup:MTLSizeMake(tw,th,1)];
    [ce endEncoding];

    id<MTLRenderCommandEncoder> de=[cb renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    [de setRenderPipelineState:self.displayPipeline];
    [de setFragmentTexture:self.outputTexture atIndex:0];
    [de setFragmentSamplerState:self.sampler atIndex:0];
    [de drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [de endEncoding];
    [cb presentDrawable:view.currentDrawable];
    [cb commit];
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.textureWidth=0; self.textureHeight=0;
}
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root=[UIViewController new];
    root.view.backgroundColor=[UIColor colorWithRed:0.025 green:0.045 blue:0.085 alpha:1];
    MTKView *renderView=[[MTKView alloc] initWithFrame:root.view.bounds];
    renderView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [root.view addSubview:renderView];
    HexiumShadeRenderer *renderer=[[HexiumShadeRenderer alloc] initWithView:renderView];
    if (renderer) {
        [HexiumShadeOverlay setApplyHandler:^(NSDictionary<NSString *,NSNumber *> *options, HexiumShadeApplyCompletion completion) {
            [renderer applyOptions:options];
            if (completion) completion(YES,nil);
        }];
    }
    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(24,48,root.view.bounds.size.width-48,42)];
    title.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    title.text=@"HEXIUM SHADE"; title.textColor=[UIColor colorWithRed:0.62 green:0.79 blue:1 alpha:1];
    title.font=[UIFont systemFontOfSize:25 weight:UIFontWeightBlack]; title.textAlignment=NSTextAlignmentCenter;
    title.shadowColor=[UIColor blackColor]; title.shadowOffset=CGSizeMake(0,1);
    [root.view addSubview:title];
    UILabel *subtitle=[[UILabel alloc] initWithFrame:CGRectMake(28,90,root.view.bounds.size.width-56,30)];
    subtitle.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    subtitle.text=renderer ? @"Live Metal demo renderer • quality presets" : @"Metal is unavailable on this device";
    subtitle.textColor=UIColor.whiteColor; subtitle.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitle.textAlignment=NSTextAlignmentCenter; [root.view addSubview:subtitle];
    self.window.rootViewController=root; [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ [HexiumShadeOverlay showOverlay]; });
    return YES;
}
@end
