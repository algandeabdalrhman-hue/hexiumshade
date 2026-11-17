# HexiumShade host renderer integration

HexiumShade is a renderer component, not a frame-capture system. The host app must own the frame it processes and provide two compatible Metal textures.

This example is for an app and renderer you control. It does not attach to, capture, or modify another app's private rendering pipeline.

## Requirements

- Import `HexiumShade.h` and `HexiumShadeOverlay.h` into the host app.
- The host app must have a Metal device and create both textures from that same device.
- The source texture must be readable by a compute shader.
- The destination texture must be writable by a compute shader.
- Both textures must have matching width, height, and pixel format.
- The host app remains responsible for presenting the destination texture.

## Register the Apply handler

Register this once after the host renderer has been initialized. Replace `currentFrameTexture` and `processedFrameTexture` with properties owned by your renderer:

```objc
#import "HexiumShade.h"
#import "HexiumShadeOverlay.h"

- (void)connectHexiumShade {
    __weak typeof(self) weakSelf = self;

    [HexiumShadeOverlay setApplyHandler:
     ^(NSDictionary<NSString *, NSNumber *> *options,
       HexiumShadeApplyCompletion completion) {

        dispatch_async(weakSelf.rendererQueue, ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                NSError *error = [NSError errorWithDomain:@"com.hexiumshade.host"
                                                     code:1
                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                                @"The host renderer is no longer available."}];
                completion(NO, error);
                return;
            }

            id<MTLTexture> input = strongSelf.currentFrameTexture;
            id<MTLTexture> output = strongSelf.processedFrameTexture;

            if (!input || !output) {
                NSError *error = [NSError errorWithDomain:@"com.hexiumshade.host"
                                                     code:2
                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                                @"The host renderer has no frame textures ready."}];
                completion(NO, error);
                return;
            }

            NSError *error = nil;
            BOOL success = [HexiumShade processTexture:input
                                         outputTexture:output
                                               options:options
                                                 error:&error];

            if (success) {
                // Schedule output for presentation in the host app's normal render loop.
                strongSelf.pendingProcessedTexture = output;
            }

            completion(success, error);
        });
    }];
}
```

The example assumes the host app already has a serial `rendererQueue`, a current frame texture, an output texture, and a normal presentation step. Those names are placeholders for the host app's own renderer properties; they are not created by HexiumShade.

## Create compatible textures

For a host-owned render target, use the host app's Metal device and matching dimensions and pixel format. The source needs `MTLTextureUsageShaderRead`; the destination needs `MTLTextureUsageShaderWrite`. Add any other usage flags required by the host renderer.

For example:

```objc
MTLTextureDescriptor *sourceDescriptor =
    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                       width:width
                                                      height:height
                                                   mipmapped:NO];
sourceDescriptor.usage = MTLTextureUsageShaderRead;

MTLTextureDescriptor *outputDescriptor =
    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                       width:width
                                                      height:height
                                                   mipmapped:NO];
outputDescriptor.usage = MTLTextureUsageShaderWrite;

id<MTLTexture> source = [device newTextureWithDescriptor:sourceDescriptor];
id<MTLTexture> output = [device newTextureWithDescriptor:outputDescriptor];
```

The host app must populate the source texture with its own frame before processing and present the output texture only after the Metal command has completed.

## Show the overlay

Call this from the host app after its UI is ready:

```objc
[HexiumShadeOverlay showOverlay];
```

## Important limitations

- The current processor waits synchronously for its Metal command buffer to finish. Do not call it on the main/UI thread; use the host renderer's own serial queue.
- The current implementation creates a command queue per processing call. A production real-time renderer should reuse its queue and schedule work asynchronously.
- The overlay's Apply button reports whether the registered host callback succeeded. It does not acquire frames or present them itself.
- This integration is not a plug-and-play connection to a third-party game's private renderer. Only pass textures created and managed by your own host app.
