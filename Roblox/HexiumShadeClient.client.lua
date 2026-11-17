-- HexiumShade Roblox client integration
-- Place this LocalScript in StarterPlayer > StarterPlayerScripts.
-- Change the LocalPlayer attribute "HexiumShadeQuality" to Ultra, High, Medium, or Low.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local PREFIX = "HexiumShade_"

local PRESETS = {
    Ultra = {
        brightness = 0.03,
        contrast = 0.16,
        saturation = 0.14,
        bloomIntensity = 0.28,
        bloomSize = 32,
        bloomThreshold = 1.05,
        sunRaysIntensity = 0.08,
        sunRaysSpread = 0.82,
        dofEnabled = true,
        dofFarIntensity = 0.08,
        dofFocusDistance = 48,
        dofInFocusRadius = 36,
        dofNearIntensity = 0.04,
    },
    High = {
        brightness = 0.02,
        contrast = 0.12,
        saturation = 0.10,
        bloomIntensity = 0.20,
        bloomSize = 24,
        bloomThreshold = 1.1,
        sunRaysIntensity = 0.05,
        sunRaysSpread = 0.8,
        dofEnabled = false,
        dofFarIntensity = 0,
        dofFocusDistance = 50,
        dofInFocusRadius = 40,
        dofNearIntensity = 0,
    },
    Medium = {
        brightness = 0.01,
        contrast = 0.07,
        saturation = 0.05,
        bloomIntensity = 0.10,
        bloomSize = 18,
        bloomThreshold = 1.2,
        sunRaysIntensity = 0,
        sunRaysSpread = 0.8,
        dofEnabled = false,
        dofFarIntensity = 0,
        dofFocusDistance = 50,
        dofInFocusRadius = 40,
        dofNearIntensity = 0,
    },
    Low = {
        brightness = 0,
        contrast = 0,
        saturation = 0,
        bloomIntensity = 0,
        bloomSize = 0,
        bloomThreshold = 2,
        sunRaysIntensity = 0,
        sunRaysSpread = 0,
        dofEnabled = false,
        dofFarIntensity = 0,
        dofFocusDistance = 50,
        dofInFocusRadius = 40,
        dofNearIntensity = 0,
    },
}

local function getOrCreate(className, name)
    local existing = Lighting:FindFirstChild(name)
    if existing and existing.ClassName == className then
        return existing
    end

    if existing then
        existing:Destroy()
    end

    local effect = Instance.new(className)
    effect.Name = name
    effect.Parent = Lighting
    return effect
end

local color = getOrCreate("ColorCorrectionEffect", PREFIX .. "Color")
local bloom = getOrCreate("BloomEffect", PREFIX .. "Bloom")
local rays = getOrCreate("SunRaysEffect", PREFIX .. "SunRays")
local depth = getOrCreate("DepthOfFieldEffect", PREFIX .. "DepthOfField")

local function applyPreset(name)
    local preset = PRESETS[name]
    if not preset then
        warn("[HexiumShade] Unknown quality preset:", name, "— using High")
        name = "High"
        preset = PRESETS.High
    end

    color.Enabled = true
    color.Brightness = preset.brightness
    color.Contrast = preset.contrast
    color.Saturation = preset.saturation

    bloom.Enabled = preset.bloomIntensity > 0
    bloom.Intensity = preset.bloomIntensity
    bloom.Size = preset.bloomSize
    bloom.Threshold = preset.bloomThreshold

    rays.Enabled = preset.sunRaysIntensity > 0
    rays.Intensity = preset.sunRaysIntensity
    rays.Spread = preset.sunRaysSpread

    depth.Enabled = preset.dofEnabled
    depth.FarIntensity = preset.dofFarIntensity
    depth.FocusDistance = preset.dofFocusDistance
    depth.InFocusRadius = preset.dofInFocusRadius
    depth.NearIntensity = preset.dofNearIntensity

    player:SetAttribute("HexiumShadeAppliedQuality", name)
    print("[HexiumShade] Applied", name, "quality")
end

local function readQuality()
    local requested = player:GetAttribute("HexiumShadeQuality")
    if typeof(requested) ~= "string" then
        requested = "High"
    end
    applyPreset(requested)
end

readQuality()
player:GetAttributeChangedSignal("HexiumShadeQuality"):Connect(readQuality)

print("[HexiumShade] Automatic Roblox client rendering is active")
