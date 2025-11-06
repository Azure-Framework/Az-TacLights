-- server.lua
local lightStates = {}  -- [vehNetId] = { flood=bool, alley=bool, track=bool }

RegisterNetEvent('spotlights:updateState')
AddEventHandler('spotlights:updateState', function(vehNetId, flood, alley, track)
    local src = source
    -- normalize nil -> false
    flood  = not not flood
    alley  = not not alley
    track  = not not track

    local existing = lightStates[vehNetId]
    local newState = nil
    if not flood and not alley and not track then
        newState = nil
    else
        newState = { flood = flood, alley = alley, track = track }
    end

    -- If no change, ignore
    local changed = false
    if existing == nil and newState ~= nil then
        changed = true
    elseif existing ~= nil and newState == nil then
        changed = true
    elseif existing ~= nil and newState ~= nil then
        if existing.flood ~= newState.flood or existing.alley ~= newState.alley or existing.track ~= newState.track then
            changed = true
        end
    end

    if changed then
        lightStates[vehNetId] = newState
        -- broadcast this change to everyone (including source) so clients can render remote lights
        TriggerClientEvent('spotlights:syncStates', -1, vehNetId, flood, alley, track)
    end
end)

RegisterNetEvent('spotlights:requestSync')
AddEventHandler('spotlights:requestSync', function()
    local src = source
    for vehNetId, st in pairs(lightStates) do
        if st then
            TriggerClientEvent('spotlights:syncStates', src, vehNetId, st.flood, st.alley, st.track)
        end
    end
end)

-- Optional: clean up when a player disconnects (not strictly needed but avoids stuck states if nets get orphaned)
AddEventHandler('playerDropped', function()
    -- you might want to clean up entries here if you track who created them.
    -- We don't have owner info in this simple implementation.
end)



-- Register the /time command. The 'false' at the end means it can be used by ANY player.
RegisterCommand('time', function(source, args, rawCommand)
    -- Check if the command was run by a player (source > 0) or the console (source = 0)
    local playerName = GetPlayerName(source)

    -- Basic check for arguments
    if #args == 0 then
        TriggerClientEvent('chat:addMessage', source, {
            color = { 255, 100, 100 },
            args = { '[Time Changer]', 'Usage: /time [day|night]' }
        })
        return
    end

    local command = string.lower(args[1])
    local hour = -1
    local action = ""

    if command == 'day' then
        hour = 12 -- Noon
        action = "set to Day (12:00)"
    elseif command == 'night' then
        hour = 0 -- Midnight
        action = "set to Night (00:00)"
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = { 255, 100, 100 },
            args = { '[Time Changer]', 'Invalid argument. Use "day" or "night".' }
        })
        return
    end

    if hour ~= -1 then
        -- Trigger event to all clients (-1) to synchronize the time change
        TriggerClientEvent('timechanger:setTime', -1, hour, 0)

        -- Send confirmation message back to the player who executed the command
        TriggerClientEvent('chat:addMessage', source, {
            color = { 100, 255, 100 },
            args = { '[Time Changer]', 'Game time successfully ' .. action .. '.' }
        })
        
        -- Log the action to the server console
        print(string.format('[Time Changer] %s set time to %s (%d:00).', playerName or 'Console', command, hour))
    end
end, false)