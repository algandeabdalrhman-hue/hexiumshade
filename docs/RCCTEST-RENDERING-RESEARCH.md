# RCCTEST rendering research

## What the repository actually does

Reference: https://github.com/devponte/RCCTEST

The project description says its goal is to render modern Roblox avatars with a 2020 RCCService. Its PHP entry point (render.php) fetches a user's avatar description, downloads selected avatar assets and dependencies, stages them in the RCC content directory, submits a SOAP job to a local RCCService endpoint, calls ThumbnailGenerator:Click, and writes the returned PNG.

This is an offline/server-side avatar thumbnail workflow. It is not a Roblox Player graphics plug-in and it does not provide a way for a separate iOS app to alter the live frame output of Roblox experiences.

## What is useful as a rendering reference

The repository includes a RCCService/shaders directory containing compiled shader packs for:

- Direct3D 9
- Direct3D 10 / 10.1
- Direct3D 11
- GLSL / GLSL 3
- Vulkan

The pack files are binary assets, not readable Metal shader source. There is no Metal shader pack in that directory. The RCC bundle also includes a Windows executable (RCCService.exe) and Windows DLL dependencies, so it is not a native iOS/arm64 renderer that can be linked into HexiumShade.

The useful reference is therefore the historical rendering environment and its visual output—not a drop-in binary or source-level Metal implementation.

## HexiumShade implementation decision

1. Keep HexiumShade's renderer native to Metal and independent of the RCC executable.
2. Use original Metal shader code for image-space grading and later effects that can be tested with textures supplied by a host app.
3. Use RCCTEST's rendered PNGs as visual references only when the user supplies or is authorized to use those images.
4. Do not copy the compiled shader packs into the iOS target or claim they can run on Metal.
5. Keep the global Roblox integration question separate: iOS app sandboxing does not expose another app's live Metal textures or command queue to HexiumShade. A normal standalone app cannot apply a post-process pass to Roblox merely by launching alongside it.

## Current renderer limitations to track

- The Metal pass is a post-process for a texture that the host explicitly supplies.
- It does not capture the screen or read another app's framebuffer.
- Preset values currently adjust brightness, contrast, and saturation only.
- The synchronous processing method waits for GPU completion; a future host app should use an asynchronous API to avoid blocking its UI thread.
- The supported input formats are intentionally limited to common uncompressed 2D color textures.

This document records the boundary between the 2020 RCC thumbnail renderer and the independent iOS Metal work so future changes do not conflate them.
