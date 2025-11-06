-- config.lua
-- Put this file in your resource and add it as a shared script (see fxmanifest note below).

Config = {}

-- Key & general behavior
Config.Keybind = 100                 -- control index for toggle key (default L = 100)
Config.DoubleTapThreshold = 300     -- ms for single/double tap
Config.RotationSmoothFactor = 0.15
Config.TrackMaxDistance = 250.0
Config.TrackAngleDegrees = 90       -- angle cone to find a valid track target (degrees)

-- Draw parameters are plain numbers/tables. Client will convert offset maps to vector3.
-- Flood (forward) lights
Config.Flood = {
  offsets = {
    { x =  0.0, y =  1.5, z = 1.5 },
    { x = -0.8, y =  1.5, z = 1.5 },
    { x =  0.8, y =  1.5, z = 1.5 },
  },
  color = { r = 255, g = 255, b = 255 },
  -- parameters: intensity, distance, radius, falloff, something (kept in same order as DrawSpotLight in your code)
  params = { intensity = 40.0, distance = 40.0, radius = 10.0, falloff = 50.0, unk = 40.0 }
}

-- Alley (side) lights
Config.Alley = {
  offsets = {
    { x =  0.8, y = 0.0, z = 1.5 }, -- right
    { x = -0.8, y = 0.0, z = 1.5 }, -- left
  },
  color = { r = 255, g = 255, b = 255 },
  params = { intensity = 30.0, distance = 20.0, radius = 1.0, falloff = 35.0, unk = 5.0 }
}

-- Track light
Config.Track = {
  offset = { x = 0.8, y = 0.7, z = 1.5 },
  color = { r = 221, g = 221, b = 221 },
  params = { intensity = 50.0, distance = 30.0, radius = 4.3, falloff = 25.0, unk = 28.6 }
}

-- Misc
Config.TrackAngleThreshold = math.cos(math.rad(Config.TrackAngleDegrees))

return Config
