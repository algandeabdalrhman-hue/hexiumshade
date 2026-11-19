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

The host is responsible for supplying valid Metal textures, encoding conventions, near/far planes, and command queues. Returned textures are separate outputs; callers retain ownership of their inputs.

## Current UI / renderer status

The UIKit panel supports preset import/export, quality selection, effect switches, and editable INI values. At this stage, the switches and Apply action persist/configure UI preset state; they do **not** automatically insert MXAO, DepthHaze, ADOF, or SSR into a host's render loop. A host integration must call the corresponding Metal processing APIs with its own frame textures. SSR is currently a UI/configuration option only; no SSR Metal pass is exposed yet.

## Build

Open `HexiumShade.xcodeproj` in Xcode, or run the GitHub Actions workflow `.github/workflows/build-ios-dylib.yml`. The workflow builds the ARM64 dylib and standalone app as separate artifacts.
