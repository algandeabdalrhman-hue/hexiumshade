# SHADES / HexiumShade

SHADES is an iOS ARM64 Metal post-processing library with an optional UIKit control panel.

## Build artifact

The GitHub Actions workflow produces two separate artifacts:

- `SHADES-Dylib-iOS-arm64` — `SHADES.dylib`, the library.
- `SHADES-App-iOS-arm64` — the standalone sample app.

The dylib is built for the iOS device SDK and ARM64. The workflow currently disables code signing; the host application is responsible for signing its own final app bundle.

## Host integration contract

The library is not an app injector or a universal overlay. iOS does not load a dylib merely because it is copied into a directory. A host application that it owns or is authorized to modify must link/embed the library, satisfy its dependencies, and explicitly call its public API.

To present the control panel from an app-owned host, import `HexiumShadeOverlay.h` and call the exported function after the host has created its foreground UI window:

```objc
#import "HexiumShadeOverlay.h"

// Call from the host app's normal UI lifecycle, on the main thread.
SHADESPresentOverlay();
```

The function dispatches presentation to the main queue and searches for the active scene's key window. If no foreground window is available, it logs a diagnostic and returns.

## Metal frame processing

SHADES does not capture another app's screen or obtain a game's private render buffers. The host renderer must explicitly provide textures it owns and is permitted to share, plus matching camera/depth metadata where an effect requires it.

Public APIs are declared in `HexiumShade/HexiumShade.h`. The library exposes:
- Color grading through `processTexture:device:commandQueue:error:`.
- MXAO through `applyMXAOToColorTexture:depthTexture:normalTexture:...`.
- Depth haze through `applyDepthHazeToColorTexture:depthTexture:...`.
- Depth of field through `applyADOFToColorTexture:depthTexture:...`.
- Validation helpers for frame textures and camera metadata.

The host is responsible for supplying valid Metal textures, encoding conventions, near/far planes, and command queues. The current pipeline obtains shader functions from the host's default Metal library via `newDefaultLibrary`; therefore the host must compile `HexiumShade.metal` into its app target (or otherwise make the matching functions available in that default library). The standalone dylib artifact contains only `SHADES.dylib`, not a separate `default.metallib`. Returned textures are separate outputs; callers retain ownership of their inputs.

### Host frame example

```objc
HSFrameInfo frameInfo = {
    .projectionMatrix = projectionMatrix,
    .inverseProjectionMatrix = inverseProjectionMatrix,
    .viewMatrix = viewMatrix,
    .nearPlane = cameraNear,
    .farPlane = cameraFar,
    .deltaTime = frameDelta,
    .depthEncoding = HSDepthEncodingDeviceZ,
    .normalEncoding = HSNormalEncodingViewSpace
};

NSError *renderError = nil;
id<MTLTexture> processed = [HexiumShade
    processFrameColorTexture:colorTexture
    depthTexture:depthTexture
    normalTexture:normalTexture
    motionVectorTexture:nil
    frameInfo:frameInfo
    device:metalDevice
    commandQueue:commandQueue
    error:&renderError];

if (!processed) {
    NSLog(@"SHADES frame failed: %@", renderError);
}
```

Call this from the host renderer with textures created for the same Metal device. The returned texture is the final color result; the host renderer remains responsible for presenting it in its own render path.

## Metal effect graph status

The frame-processing API now executes an ordered chain: color grading, optional MXAO, optional depth haze, then optional ADOF. The chain reads the effect switches saved by the UIKit panel. The metadata-aware overload accepts `HSFrameInfo` so the host can specify depth encoding, normal encoding, and camera near/far planes. The compatibility overload uses conventional Metal device-Z depth with near=0.1 and far=1000; hosts with different depth conventions should use the metadata-aware overload.

MXAO requires both depth and normal textures. Depth haze and ADOF require depth. Missing required inputs return a descriptive error instead of silently pretending an effect ran. SSR remains disabled in the UI because a Metal SSR kernel has not been implemented. Motion vectors are validated for the host frame contract but are not consumed by the current effects.

The effect graph allocates a distinct output texture per enabled pass and encodes the entire ordered chain into one Metal command buffer, followed by one completion wait. This avoids a CPU/GPU synchronization after every effect. Texture-pool reuse and a non-blocking completion-handler API remain performance improvements for a later iteration. The host must still call the frame-processing API from its own supported render loop; the UIKit switches do not independently acquire frames.

## Build

Open `HexiumShade.xcodeproj` in Xcode, or run the GitHub Actions workflow `.github/workflows/build-ios-dylib.yml`. The workflow builds the ARM64 dylib and standalone app as separate artifacts.
