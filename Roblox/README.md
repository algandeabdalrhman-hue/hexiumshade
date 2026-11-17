# Roblox Studio integration

The Roblox integration is a client-side Luau quality controller. It uses Roblox-supported Lighting effects; it does not replace Roblox's internal renderer or load the native Metal library.

## Install

1. Open the Roblox experience in Roblox Studio.
2. In Explorer, open StarterPlayer, then StarterPlayerScripts.
3. Insert a LocalScript.
4. Copy the contents of `Roblox/HexiumShadeClient.client.lua` into it.
5. Run the experience.

The script applies the High preset at startup. It creates and manages only effects whose names begin with `HexiumShade_`.

## Change quality at runtime

From another LocalScript, set the local player's attribute:

```lua
local Players = game:GetService("Players")
local player = Players.LocalPlayer

player:SetAttribute("HexiumShadeQuality", "Ultra")
-- Supported: "Ultra", "High", "Medium", "Low"
```

The controller listens for attribute changes and applies the new preset immediately. The active preset is reported in the `HexiumShadeAppliedQuality` player attribute.

## Scope

This controls color correction, bloom, sun rays, and depth of field through Roblox's public experience APIs. It cannot access the game's rendered Metal textures, replace Roblox's renderer, or make the standalone iOS `.dylib` run inside the Roblox app.
