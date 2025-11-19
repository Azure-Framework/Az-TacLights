local Config = Config or require('config')
if type(Config) == "table" and Config.Config then Config = Config.Config end

-- ---------- defaults ----------
Config.Keybind = Config.Keybind or 47 -- G
Config.HoldThreshold = Config.HoldThreshold or 400
Config.TrackMaxDistance = Config.TrackMaxDistance or 60.0
Config.TrackAngleThreshold = Config.TrackAngleThreshold or 0.6
Config.RotationSmoothFactor = Config.RotationSmoothFactor or 0.12

Config.Flood = Config.Flood or {}
Config.Flood.offsets = Config.Flood.offsets or { { x = 0.0, y = 1.0, z = 0.5 } }
Config.Flood.color = Config.Flood.color or { r = 255, g = 255, b = 255 }
Config.Flood.params = Config.Flood.params or { intensity = 25.0, distance = 40.0, radius = 2.0, falloff = 1.0, unk = 0.0 }

Config.Alley = Config.Alley or {}
Config.Alley.offsets = Config.Alley.offsets or { { x = 0.8, y = 0.0, z = 1.5 }, { x = -0.8, y = 0.0, z = 1.5 } }
Config.Alley.color = Config.Alley.color or { r = 255, g = 220, b = 120 }
Config.Alley.params = Config.Alley.params or { intensity = 20.0, distance = 30.0, radius = 1.8, falloff = 1.0, unk = 0.0 }

Config.Track = Config.Track or {}
Config.Track.offset = Config.Track.offset or { x = 0.0, y = 1.2, z = 0.4 }
Config.Track.color = Config.Track.color or { r = 255, g = 255, b = 255 }
Config.Track.params = Config.Track.params or { intensity = 40.0, distance = 80.0, radius = 3.0, falloff = 1.0, unk = 0.0 }

-- ---------- vehicle restriction (config-driven) ----------
-- If RestrictToEmergency is not true, we behave exactly like the original script.
Config.RestrictToEmergency = (Config.RestrictToEmergency == true)

local allowedVehicleClasses = {}
if type(Config.AllowedVehicleClasses) == "table" then
  for _, classId in ipairs(Config.AllowedVehicleClasses) do
    classId = tonumber(classId)
    if classId then
      allowedVehicleClasses[classId] = true
    end
  end
end

local allowedVehicleModels = {}
if type(Config.AllowedModels) == "table" then
  for _, model in ipairs(Config.AllowedModels) do
    if type(model) == "string" then
      allowedVehicleModels[GetHashKey(model)] = true
    elseif type(model) == "number" then
      allowedVehicleModels[model] = true
    end
  end
end

local function isVehicleAllowed(veh)
  -- If restriction is disabled, allow everything (original behavior)
  if not Config.RestrictToEmergency then
    return true
  end

  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return false
  end

  local model = GetEntityModel(veh)
  if allowedVehicleModels[model] then
    return true
  end

  local classId = GetVehicleClass(veh)
  if allowedVehicleClasses[classId] then
    return true
  end

  return false
end

-- ---------- state ----------
local lastVehicle       = nil
local floodlightsOn     = false
local alleyLightsOn     = false
local trackMode         = false
local trackedVehicle    = nil
local uiVisible         = false
local uiFocused         = false
local remoteStates      = {}
local currentTrackDir   = vector3(1.0, 0.0, 0.0)
local isOutOfVehicle    = true

-- ---------- input helpers ----------
local keyDownStart  = 0
local holdTriggered = false
local holdThreshold = Config.HoldThreshold or 400

local CTRLS = {
  up    = 172, -- arrow up
  down  = 173, -- arrow down
  left  = 174, -- arrow left
  right = 175, -- arrow right
  shift = 21,  -- LSHIFT
  ctrl  = 36,  -- LCTRL
}

-- Sensitivities (slower / fine control)
local MOVE_DELTA   = 0.008
local Z_DELTA      = 0.008
local PITCH_DELTA  = 0.025
local AIM_DELTA    = 0.035

local FLOOD_LIMITS = {
  x = { min = -2.0, max = 2.0 },
  y = { min = -3.0, max = 5.0 },
  z = { min = -1.0, max = 2.5 }
}

local ALLEY_META_LIMITS = {
  radius = { min = 0.3, max = 2.0 },
  pitch  = { min = -0.9, max = 0.9 },
  z      = { min = -1.0, max = 2.5 },
}

local ALLEY_OFF_LIMITS = {
  x = { min = -2.0, max = 2.0 },
  y = { min = -3.0, max = 5.0 },
  z = { min = -1.0, max = 2.5 }
}

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function pressedAny(group, id)
  if IsControlPressed(group, id) or IsDisabledControlPressed(group, id) then return true end
  local n = GetControlNormal(group, id) or 0.0
  if type(n) == 'number' and n > 0.15 then return true end
  local dn = GetDisabledControlNormal(group, id) or 0.0
  if type(dn) == 'number' and dn > 0.15 then return true end
  return false
end

local function justPressedAny(group, id)
  if IsControlJustPressed(group, id) or IsDisabledControlJustPressed(group, id) then return true end
  local n = GetControlNormal(group, id) or 0.0
  if type(n) == 'number' and n > 0.6 then return true end
  local dn = GetDisabledControlNormal(group, id) or 0.0
  if type(dn) == 'number' and dn > 0.6 then return true end
  return false
end

local function arrowUpPressed()    return pressedAny(0, CTRLS.up) end
local function arrowDownPressed()  return pressedAny(0, CTRLS.down) end
local function arrowLeftPressed()  return pressedAny(0, CTRLS.left) end
local function arrowRightPressed() return pressedAny(0, CTRLS.right) end

-- ---------- ensure numeric offsets ----------
local function ensureOffsets(tbl)
  for _, off in ipairs(tbl) do
    off.x = tonumber(off.x) or 0.0
    off.y = tonumber(off.y) or 0.0
    off.z = tonumber(off.z) or 0.0
  end
end

ensureOffsets(Config.Flood.offsets)
ensureOffsets(Config.Alley.offsets)

Config.Track.offset.x = tonumber(Config.Track.offset.x) or 0.0
Config.Track.offset.y = tonumber(Config.Track.offset.y) or 0.0
Config.Track.offset.z = tonumber(Config.Track.offset.z) or 0.0

-- Save ORIGINAL alley offsets for proper reset
local function copyOffsets(src)
  local out = {}
  for i, off in ipairs(src) do
    out[i] = { x = off.x, y = off.y, z = off.z }
  end
  return out
end

local originalAlleyOffsets = copyOffsets(Config.Alley.offsets)

-- ---------- alley meta ----------
local alleyMeta = {}

local function recomputeAlleyOffsets()
  for i, m in ipairs(alleyMeta) do
    m.radius = clamp(m.radius, ALLEY_META_LIMITS.radius.min, ALLEY_META_LIMITS.radius.max)
    m.pitch  = clamp(m.pitch,  ALLEY_META_LIMITS.pitch.min,  ALLEY_META_LIMITS.pitch.max)
    m.z      = clamp(m.z,      ALLEY_META_LIMITS.z.min,      ALLEY_META_LIMITS.z.max)

    if m.theta > math.pi then m.theta = m.theta - 2 * math.pi end
    if m.theta < -math.pi then m.theta = m.theta + 2 * math.pi end

    Config.Alley.offsets[i].x = math.cos(m.theta) * m.radius
    Config.Alley.offsets[i].y = math.sin(m.theta) * m.radius
    Config.Alley.offsets[i].z = m.z

    m.aim = clamp(m.aim or 0.0, -math.pi/2, math.pi/2)
  end
end

local function initAlleyMetaFromOffsets()
  alleyMeta = {}
  for i, off in ipairs(Config.Alley.offsets) do
    local x = off.x or 0.0
    local y = off.y or 0.0
    local z = off.z or 0.0
    local radius = math.sqrt(x*x + y*y)
    local theta = math.atan2(y, x)
    alleyMeta[i] = {
      theta = theta,
      radius = clamp(radius, ALLEY_META_LIMITS.radius.min, ALLEY_META_LIMITS.radius.max),
      pitch = clamp(-0.1, ALLEY_META_LIMITS.pitch.min, ALLEY_META_LIMITS.pitch.max),
      z     = clamp(z, ALLEY_META_LIMITS.z.min, ALLEY_META_LIMITS.z.max),
      aim   = 0.0,
    }
  end
  recomputeAlleyOffsets()
end

local function updateMetaFromOffsets()
  for i, off in ipairs(Config.Alley.offsets) do
    local x, y, z = off.x or 0.0, off.y or 0.0, off.z or 0.0
    local r = math.sqrt(x*x + y*y)
    local th = math.atan2(y, x)
    if not alleyMeta[i] then alleyMeta[i] = {} end
    alleyMeta[i].theta  = th
    alleyMeta[i].radius = clamp(r, ALLEY_META_LIMITS.radius.min, ALLEY_META_LIMITS.radius.max)
    alleyMeta[i].z      = clamp(z, ALLEY_META_LIMITS.z.min, ALLEY_META_LIMITS.z.max)
    alleyMeta[i].pitch  = alleyMeta[i].pitch or -0.1
    alleyMeta[i].aim    = alleyMeta[i].aim or 0.0
  end
end

initAlleyMetaFromOffsets()

-- ---------- helpers ----------
local function moveAlleyOffsetsLocal(dx, dy, dz)
  for _, off in ipairs(Config.Alley.offsets) do
    off.x = clamp(off.x + dx, ALLEY_OFF_LIMITS.x.min, ALLEY_OFF_LIMITS.x.max)
    off.y = clamp(off.y + dy, ALLEY_OFF_LIMITS.y.min, ALLEY_OFF_LIMITS.y.max)
    off.z = clamp(off.z + dz, ALLEY_OFF_LIMITS.z.min, ALLEY_OFF_LIMITS.z.max)
  end
  ensureOffsets(Config.Alley.offsets)
  updateMetaFromOffsets()
  recomputeAlleyOffsets()
  if uiVisible then
    SendNUIMessage({
      action = 'offsetsUpdate',
      flood  = Config.Flood.offsets,
      alley  = Config.Alley.offsets,
      alleyMeta = alleyMeta
    })
  end
end

local function changeAlleyPitch(dP)
  for _, m in ipairs(alleyMeta) do
    m.pitch = clamp((m.pitch or -0.1) + dP, ALLEY_META_LIMITS.pitch.min, ALLEY_META_LIMITS.pitch.max)
  end
  if uiVisible then
    SendNUIMessage({
      action = 'offsetsUpdate',
      flood  = Config.Flood.offsets,
      alley  = Config.Alley.offsets,
      alleyMeta = alleyMeta
    })
  end
end

local function changeAlleyMountZ(dz)
  for i, m in ipairs(alleyMeta) do
    m.z = clamp((m.z or Config.Alley.offsets[i].z or 0.0) + dz,
      ALLEY_META_LIMITS.z.min, ALLEY_META_LIMITS.z.max)
  end
  recomputeAlleyOffsets()
  updateMetaFromOffsets()
  if uiVisible then
    SendNUIMessage({
      action = 'offsetsUpdate',
      flood  = Config.Flood.offsets,
      alley  = Config.Alley.offsets,
      alleyMeta = alleyMeta
    })
  end
end

local function drawSpotForParams(origin, direction, color, params)
  DrawSpotLight(
    origin.x, origin.y, origin.z,
    direction.x, direction.y, direction.z,
    color.r, color.g, color.b,
    params.intensity, params.distance, params.radius, params.falloff, params.unk
  )
end

-- ---------- networking ----------
local function sendMyState()
  if lastVehicle and DoesEntityExist(lastVehicle) and isVehicleAllowed(lastVehicle) then
    TriggerServerEvent('spotlights:updateState', VehToNet(lastVehicle), floodlightsOn, alleyLightsOn, trackMode)
  end
end

local function AcquireTarget()
  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  local forward = GetEntityForwardVector(ped)
  local start = pos + forward * 1.0
  local finish = pos + forward * Config.TrackMaxDistance
  local ray = StartShapeTestRay(start.x, start.y, start.z, finish.x, finish.y, finish.z, 10, ped, 0)
  local _, _, _, _, entity = GetShapeTestResult(ray)
  if entity and IsEntityAVehicle(entity) then
    local tpos = GetEntityCoords(entity)
    local dir = tpos - pos
    local dist = #(dir)
    if dist <= Config.TrackMaxDistance then
      local dirNorm = dir / dist
      local dot = forward.x * dirNorm.x + forward.y * dirNorm.y + forward.z * dirNorm.z
      if dot >= Config.TrackAngleThreshold then
        return entity
      end
    end
  end
  return nil
end

-- ---------- UI helpers ----------
local function openSpotlightUI()
  uiVisible = true
  uiFocused = true
  SetNuiFocus(true, true)
  if SetNuiFocusKeepInput then
    SetNuiFocusKeepInput(false)
  end

  SendNUIMessage({
    action      = 'open',
    flood       = floodlightsOn,
    alley       = alleyLightsOn,
    track       = trackMode,
    alleyMeta   = alleyMeta,
    alleyOffsets= Config.Alley.offsets
  })
  SendNUIMessage({ action = 'focus', focus = true })
end

local function closeSpotlightUI()
  uiVisible = false
  uiFocused = false
  SetNuiFocus(false, false)
  if SetNuiFocusKeepInput then
    SetNuiFocusKeepInput(false)
  end
  SendNUIMessage({ action = 'focus', focus = false })
  SendNUIMessage({ action = 'close' })
end

local function unfocusSpotlightUI()
  uiFocused = false
  SetNuiFocus(false, false)
  if SetNuiFocusKeepInput then
    SetNuiFocusKeepInput(false)
  end
  -- UI stays visible, just loses focus
  SendNUIMessage({ action = 'focus', focus = false })
end

-- ---------- commands ----------
RegisterCommand('spotlightui', function()
  openSpotlightUI()
end, false)

-- Reset Alley to ORIGINAL positions from config
RegisterCommand('snapalley', function()
  Config.Alley.offsets = copyOffsets(originalAlleyOffsets)
  ensureOffsets(Config.Alley.offsets)
  initAlleyMetaFromOffsets()
  if uiVisible then
    SendNUIMessage({
      action    = 'offsetsUpdate',
      flood     = Config.Flood.offsets,
      alley     = Config.Alley.offsets,
      alleyMeta = alleyMeta
    })
  end
end, false)

-- ---------- NUI callbacks ----------
RegisterNUICallback('snapAlley', function(_, cb)
  Config.Alley.offsets = copyOffsets(originalAlleyOffsets)
  ensureOffsets(Config.Alley.offsets)
  initAlleyMetaFromOffsets()
  if uiVisible then
    SendNUIMessage({
      action    = 'offsetsUpdate',
      flood     = Config.Flood.offsets,
      alley     = Config.Alley.offsets,
      alleyMeta = alleyMeta
    })
  end
  cb('ok')
end)

RegisterNUICallback('toggleFlood', function(_, cb)
  floodlightsOn = not floodlightsOn
  alleyLightsOn, trackMode, trackedVehicle = false, false, nil
  SendNUIMessage({
    action = 'update',
    flood  = floodlightsOn,
    alley  = alleyLightsOn,
    track  = trackMode
  })
  sendMyState()
  cb('ok')
end)

RegisterNUICallback('toggleAlley', function(_, cb)
  alleyLightsOn = not alleyLightsOn
  floodlightsOn, trackMode, trackedVehicle = false, false, nil
  SendNUIMessage({
    action      = 'update',
    flood       = floodlightsOn,
    alley       = alleyLightsOn,
    track       = trackMode,
    alleyMeta   = alleyMeta,
    alleyOffsets= Config.Alley.offsets
  })
  sendMyState()
  cb('ok')
end)

RegisterNUICallback('toggleTrack', function(_, cb)
  trackMode = not trackMode
  floodlightsOn, alleyLightsOn = trackMode, false
  trackedVehicle = nil
  SendNUIMessage({
    action = 'update',
    flood  = floodlightsOn,
    alley  = alleyLightsOn,
    track  = trackMode
  })
  sendMyState()
  cb('ok')
end)

RegisterNUICallback('toggleAll', function(_, cb)
  local anyOn = floodlightsOn or alleyLightsOn or trackMode
  floodlightsOn = not anyOn
  alleyLightsOn = not anyOn
  trackMode     = not anyOn
  trackedVehicle = nil
  SendNUIMessage({
    action      = 'update',
    flood       = floodlightsOn,
    alley       = alleyLightsOn,
    track       = trackMode,
    alleyMeta   = alleyMeta,
    alleyOffsets= Config.Alley.offsets
  })
  sendMyState()
  cb('ok')
end)

-- Close UI (hide + remove focus)
RegisterNUICallback('hideUI', function(_, cb)
  closeSpotlightUI()
  cb('ok')
end)

RegisterNUICallback('closeUI', function(_, cb)
  closeSpotlightUI()
  cb('ok')
end)

-- Unfocus: keep UI visible, just drop mouse/focus
RegisterNUICallback('escape', function(_, cb)
  unfocusSpotlightUI()
  cb('ok')
end)

-- ---------- keybind logic ----------
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)

    if IsControlJustPressed(0, Config.Keybind) or IsDisabledControlJustPressed(0, Config.Keybind) then
      keyDownStart = GetGameTimer()
      holdTriggered = false
    end

    if IsControlPressed(0, Config.Keybind) or IsDisabledControlPressed(0, Config.Keybind) then
      if not holdTriggered and keyDownStart > 0 then
        local held = GetGameTimer() - keyDownStart
        if held >= holdThreshold then
          trackMode = not trackMode
          if trackMode then
            floodlightsOn = true
            alleyLightsOn = false
            trackedVehicle = nil
          else
            floodlightsOn = false
            alleyLightsOn = false
            trackedVehicle = nil
          end
          holdTriggered = true
          keyDownStart  = 0
          sendMyState()
          if uiVisible then
            SendNUIMessage({
              action      = 'update',
              flood       = floodlightsOn,
              alley       = alleyLightsOn,
              track       = trackMode,
              alleyMeta   = alleyMeta,
              alleyOffsets= Config.Alley.offsets
            })
          end
        end
      end
    end

    if IsControlJustReleased(0, Config.Keybind) or IsDisabledControlJustReleased(0, Config.Keybind) then
      if not holdTriggered then
        if not floodlightsOn and not alleyLightsOn and not trackMode then
          floodlightsOn = true; alleyLightsOn = false; trackMode = false
        elseif floodlightsOn and not alleyLightsOn then
          floodlightsOn = false; alleyLightsOn = true; trackMode = false
        elseif alleyLightsOn then
          floodlightsOn = false; alleyLightsOn = false; trackMode = false
        else
          floodlightsOn = true; alleyLightsOn = false; trackMode = false
        end

        trackedVehicle = nil
        sendMyState()

        if uiVisible then
          SendNUIMessage({
            action      = 'update',
            flood       = floodlightsOn,
            alley       = alleyLightsOn,
            track       = trackMode,
            alleyMeta   = alleyMeta,
            alleyOffsets= Config.Alley.offsets
          })
        end
      end
      keyDownStart  = 0
      holdTriggered = false
    end
  end
end)

-- ---------- movement helpers ----------
local function moveFloodOffsets(dx, dy, dz)
  for _, off in ipairs(Config.Flood.offsets) do
    off.x = clamp(off.x + dx, FLOOD_LIMITS.x.min, FLOOD_LIMITS.x.max)
    off.y = clamp(off.y + dy, FLOOD_LIMITS.y.min, FLOOD_LIMITS.y.max)
    off.z = clamp(off.z + dz, FLOOD_LIMITS.z.min, FLOOD_LIMITS.z.max)
  end
end

local function rotateAlley(dTheta)
  for _, m in ipairs(alleyMeta) do
    m.theta = m.theta + dTheta
    if m.theta > math.pi then m.theta = m.theta - 2 * math.pi end
    if m.theta < -math.pi then m.theta = m.theta + 2 * math.pi end
  end
  recomputeAlleyOffsets()
end

-- ---------- main loop (input + rendering) ----------
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
      isOutOfVehicle = false
      lastVehicle = GetVehiclePedIsIn(ped, false)
    else
      isOutOfVehicle = true
    end

    local veh = (not isOutOfVehicle and GetVehiclePedIsIn(ped, false)) or lastVehicle

    -- Rendering
    if veh and DoesEntityExist(veh) and isVehicleAllowed(veh) then
      if (not isOutOfVehicle) or (isOutOfVehicle and (floodlightsOn or alleyLightsOn or trackMode)) then

        if floodlightsOn then
          local fwd = GetEntityForwardVector(veh)
          for _, off in ipairs(Config.Flood.offsets) do
            local pos = GetOffsetFromEntityInWorldCoords(veh, off.x, off.y, off.z)
            local dir = vector3(fwd.x, fwd.y, 0.0)
            drawSpotForParams(pos, dir, Config.Flood.color, Config.Flood.params)
          end
        end

        if alleyLightsOn then
          local fwd = GetEntityForwardVector(veh)
          local fwdXY = vector3(fwd.x, fwd.y, 0.0)
          local mag = math.sqrt(fwdXY.x*fwdXY.x + fwdXY.y*fwdXY.y) or 1.0
          fwdXY = fwdXY / mag

          -- right pod
          local offR  = Config.Alley.offsets[1] or { x = 0.8,  y = 0.0, z = 1.5 }
          local metaR = alleyMeta[1]           or { pitch = -0.1, aim = 0.0 }
          local posR  = GetOffsetFromEntityInWorldCoords(veh, offR.x, offR.y, offR.z)
          local latR  = vector3(fwdXY.y, -fwdXY.x, 0.0)
          local axR   = math.cos(metaR.aim or 0.0)
          local bxR   = math.sin(metaR.aim or 0.0)
          local dirR  = vector3(
            latR.x * axR + fwdXY.x * bxR,
            latR.y * axR + fwdXY.y * bxR,
            metaR.pitch or -0.1
          )
          local mR = math.sqrt(dirR.x*dirR.x + dirR.y*dirR.y + dirR.z*dirR.z) or 1.0
          dirR = vector3(dirR.x / mR, dirR.y / mR, dirR.z / mR)

          -- left pod
          local offL  = Config.Alley.offsets[2] or { x = -0.8, y = 0.0, z = 1.5 }
          local metaL = alleyMeta[2]           or { pitch = -0.1, aim = 0.0 }
          local posL  = GetOffsetFromEntityInWorldCoords(veh, offL.x, offL.y, offL.z)
          local latL  = vector3(-fwdXY.y, fwdXY.x, 0.0)
          local axL   = math.cos(metaL.aim or 0.0)
          local bxL   = math.sin(metaL.aim or 0.0)
          local dirL  = vector3(
            latL.x * axL + fwdXY.x * bxL,
            latL.y * axL + fwdXY.y * bxL,
            metaL.pitch or -0.1
          )
          local mL = math.sqrt(dirL.x*dirL.x + dirL.y*dirL.y + dirL.z*dirL.z) or 1.0
          dirL = vector3(dirL.x / mL, dirL.y / mL, dirL.z / mL)

          drawSpotForParams(posR, dirR, Config.Alley.color, Config.Alley.params)
          drawSpotForParams(posL, dirL, Config.Alley.color, Config.Alley.params)
        end

        if trackMode then
          if not trackedVehicle then
            trackedVehicle = AcquireTarget()
          end
          local off = Config.Track.offset
          local pos = GetOffsetFromEntityInWorldCoords(veh, off.x, off.y, off.z)
          local desired
          if trackedVehicle and DoesEntityExist(trackedVehicle) then
            desired = GetEntityCoords(trackedVehicle) - pos
          else
            desired = GetEntityForwardVector(veh)
          end
          desired = vector3(desired.x, desired.y, 0.0)
          local mag = math.sqrt(desired.x*desired.x + desired.y*desired.y) or 1.0
          desired = desired / mag
          currentTrackDir = currentTrackDir + (desired - currentTrackDir) * Config.RotationSmoothFactor
          drawSpotForParams(pos, vector3(currentTrackDir.x, currentTrackDir.y, 0.0), Config.Track.color, Config.Track.params)
        end
      end
    end
  end
end)

-- ---------- sync handlers ----------
RegisterNetEvent('spotlights:syncStates')
AddEventHandler('spotlights:syncStates', function(vehNetId, flood, alley, track)
  if lastVehicle and vehNetId == VehToNet(lastVehicle) then return end
  if not flood and not alley and not track then
    remoteStates[vehNetId] = nil
  else
    remoteStates[vehNetId] = { flood = flood, alley = alley, track = track }
  end
end)

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    for netId, state in pairs(remoteStates) do
      if NetworkDoesNetworkIdExist(netId) then
        local veh = NetToVeh(netId)
        if DoesEntityExist(veh) and isVehicleAllowed(veh) then
          if state.flood then
            local fwd = GetEntityForwardVector(veh)
            for _, off in ipairs(Config.Flood.offsets) do
              local wp = GetOffsetFromEntityInWorldCoords(veh, off.x, off.y, off.z)
              drawSpotForParams(wp, vector3(fwd.x, fwd.y, 0.0), Config.Flood.color, Config.Flood.params)
            end
          end
          if state.alley then
            local offR = Config.Alley.offsets[1]
            local offL = Config.Alley.offsets[2]
            local posR = GetOffsetFromEntityInWorldCoords(veh, offR.x, offR.y, offR.z)
            local posL = GetOffsetFromEntityInWorldCoords(veh, offL.x, offL.y, offL.z)
            local fwd  = GetEntityForwardVector(veh)
            local fwdXY = vector3(fwd.x, fwd.y, 0.0)
            local mag = math.sqrt(fwdXY.x*fwdXY.x + fwdXY.y*fwdXY.y) or 1.0
            fwdXY = fwdXY / mag
            local right = vector3(fwdXY.y, -fwdXY.x, -0.1)
            local left  = vector3(-fwdXY.y, fwdXY.x, -0.1)
            drawSpotForParams(posR, right, Config.Alley.color, Config.Alley.params)
            drawSpotForParams(posL, left,  Config.Alley.color, Config.Alley.params)
          end
          if state.track then
            local off = Config.Track.offset
            local pos = GetOffsetFromEntityInWorldCoords(veh, off.x, off.y, off.z)
            local dir = GetEntityForwardVector(veh)
            dir = vector3(dir.x, dir.y, 0.0)
            local mag = math.sqrt(dir.x*dir.x + dir.y*dir.y) or 1.0
            dir = dir / mag
            drawSpotForParams(pos, dir, Config.Track.color, Config.Track.params)
          end
        else
          remoteStates[netId] = nil
        end
      else
        remoteStates[netId] = nil
      end
    end
  end
end)

AddEventHandler('playerSpawned', function()
  TriggerServerEvent('spotlights:requestSync')
end)

RegisterNetEvent('timechanger:setTime', function(hour, minute)
  NetworkOverrideClockTime(hour, minute, 0)
end)
