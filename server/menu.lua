--[[
  __  __           _                 _        __  __
 |  \/  |         | |               (_)      |  \/  |
 | \  / | ___  ___| |__   __ _ _ __  _  ___  | \  / | ___ _ __  _   _
 | |\/| |/ _ \/ __| '_ \ / _` | '_ \| |/ __| | |\/| |/ _ \ '_ \| | | |
 | |  | |  __/ (__| | | | (_| | | | | | (__  | |  | |  __/ | | | |_| |
 |_|  |_|\___|\___|_| |_|\__,_|_| |_|_|\___| |_|  |_|\___|_| |_|\__,_|

 Validation of mechanic menu actions: push, flip, unlock, impound,
 flatbed towing (Entity(flatbed).state.pls_towed = netId) and jump starter.
]]--

MenuServer = {}

local RateLimits = {}   -- [src][key] = GetGameTimer()
local Towing = {}       -- [flatbed entity] = towed entity

local function HashKey(hash)
    return math.floor(hash or 0) & 0xFFFFFFFF
end

local FlatbedModels = {}
for model in pairs(Config.Flatbeds or {}) do
    FlatbedModels[HashKey(joaat(model))] = true
end

--[[
  _    _      _
 | |  | |    | |
 | |__| | ___| |_ __   ___ _ __ ___
 |  __  |/ _ \ | '_ \ / _ \ '__/ __|
 | |  | |  __/ | |_) |  __/ |  \__ \
 |_|  |_|\___|_| .__/ \___|_|  |___/
               | |
               |_|
]]--

local function RateLimited(src, key, ms)
    local now = GetGameTimer()
    RateLimits[src] = RateLimits[src] or {}
    local last = RateLimits[src][key]
    if last and now - last < ms then
        return true
    end
    RateLimits[src][key] = now
    return false
end

local function GetVehicle(netId)
    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

-- Plate text shown on the vehicle (logs)
local function GetPlate(entity)
    return Utils.TrimPlate(GetVehicleNumberPlateText(entity)) or ""
end

-- Trusted real plate of the vehicle (fake plate resolved, a plate text changed by the owner client is ignored)
local function GetRealPlate(entity)
    if Vehicles and Vehicles.GetEntityPlate then
        local plate = Vehicles.GetEntityPlate(entity)
        if plate then return plate end
    end
    return GetPlate(entity)
end

-- BASE NPC mission vehicle (server record, the statebag pls_mission only adds to it)
local function GetMission(entity)
    local mission = MissionsServer and MissionsServer.GetByEntity and MissionsServer.GetByEntity(entity)
    return mission or Entity(entity).state.pls_mission
end

local function PlayerName(src)
    local name = BRIDGE.GetPlayerFullName(src)
    if not name or name == "" then
        name = GetPlayerName(src) or tostring(src)
    end
    return name
end

-- Permission on duty. Returns ok, shopId or false, localeKey
local function CheckPermission(src, perm)
    local ok, shopId = Shops.HasPermission(src, perm)
    if ok then return true, shopId end
    return false, shopId and "no_permission" or "not_on_duty"
end

-- Permission + vehicle + distance. Returns entity, shopId or nil, localeKey
local function CheckVehicleAction(src, perm, netId, distance)
    local ok, result = CheckPermission(src, perm)
    if not ok then return nil, result end
    local entity = GetVehicle(netId)
    if not entity then return nil, "no_vehicle" end
    if not Shops.IsNearEntity(src, entity, distance) then return nil, "too_far" end
    return entity, result
end

local function HasDriver(entity)
    local driver = GetPedInVehicleSeat(entity, -1)
    return driver ~= nil and driver ~= 0
end

--[[
  ______ _       _   _              _
 |  ____| |     | | | |            | |
 | |__  | | __ _| |_| |__   ___  __| |
 |  __| | |/ _` | __| '_ \ / _ \/ _` |
 | |    | | (_| | |_| |_) |  __/ (_| |
 |_|    |_|\__,_|\__|_.__/ \___|\__,_|
]]--

-- Flatbed entity carrying this vehicle or nil
function MenuServer.GetTowingFlatbed(entity)
    for flatbed, towed in pairs(Towing) do
        if towed == entity then
            return flatbed
        end
    end
    return nil
end

function MenuServer.IsTowed(entity)
    return MenuServer.GetTowingFlatbed(entity) ~= nil
end

-- Flatbed carries a vehicle (server record, the statebag pls_towed can be written by the owner client)
function MenuServer.IsTowing(entity)
    return entity ~= nil and Towing[entity] ~= nil
end

-- Clears towing state of flatbed / towed vehicle (vehicle removed, impounded...)
function MenuServer.ReleaseTowed(entity)
    for flatbed, towed in pairs(Towing) do
        if flatbed == entity or towed == entity then
            Towing[flatbed] = nil
            if DoesEntityExist(flatbed) then
                Entity(flatbed).state:set("pls_towed", nil, true)
            end
        end
    end
end

lib.callback.register("pls_mechanic:server:menu:towAttach", function(src, flatNet, targetNet)
    if RateLimited(src, "tow", 2000) then return false, "menu_rate_limit" end
    local ok, err = CheckPermission(src, "tow")
    if not ok then return false, err end
    local flatbed, target = GetVehicle(flatNet), GetVehicle(targetNet)
    if not flatbed or not target or flatbed == target then return false, "no_vehicle" end
    if not FlatbedModels[HashKey(GetEntityModel(flatbed))] then return false, "menu_tow_no_flatbed" end
    if FlatbedModels[HashKey(GetEntityModel(target))] then return false, "menu_tow_no_target" end
    if not Shops.IsNearEntity(src, flatbed, Config.Towing.maxDistance + 3.0) then return false, "too_far" end
    if #(GetEntityCoords(flatbed) - GetEntityCoords(target)) > 20.0 then return false, "menu_tow_no_target" end
    if Towing[flatbed] or Entity(flatbed).state.pls_towed then return false, "menu_tow_busy" end
    if MenuServer.IsTowed(target) or GetEntityAttachedTo(target) ~= 0 then return false, "menu_vehicle_attached" end
    if HasDriver(target) then return false, "menu_vehicle_occupied" end

    Towing[flatbed] = target
    Entity(flatbed).state:set("pls_towed", tonumber(targetNet), true)
    OpenServer.Log(src, "tow_attach", ("%s loaded vehicle %s onto flatbed %s"):format(PlayerName(src), GetPlate(target), GetPlate(flatbed)), {
        plate = GetPlate(target),
        flatbed = GetPlate(flatbed),
    })
    return true
end)

lib.callback.register("pls_mechanic:server:menu:towDetach", function(src, flatNet)
    if RateLimited(src, "tow", 2000) then return false, "menu_rate_limit" end
    local flatbed, err = CheckVehicleAction(src, "tow", flatNet, Config.Towing.maxDistance + 3.0)
    if not flatbed then return false, err end
    local towedNet = Entity(flatbed).state.pls_towed
    if not towedNet then return false, "menu_tow_empty" end

    local towed = Towing[flatbed]
    Towing[flatbed] = nil
    Entity(flatbed).state:set("pls_towed", nil, true)
    OpenServer.Log(src, "tow_detach", ("%s unloaded vehicle %s from flatbed %s"):format(PlayerName(src), towed and DoesEntityExist(towed) and GetPlate(towed) or "-", GetPlate(flatbed)), {
        flatbed = GetPlate(flatbed),
    })
    return true, towedNet
end)

-- Rebuild towing after restart + cleanup of removed vehicles
CreateThread(function()
    for _, vehicle in pairs(GetAllVehicles()) do
        local towedNet = Entity(vehicle).state.pls_towed
        if towedNet then
            local towed = NetworkGetEntityFromNetworkId(towedNet)
            if towed and towed ~= 0 and DoesEntityExist(towed) then
                Towing[vehicle] = towed
            else
                Entity(vehicle).state:set("pls_towed", nil, true)
            end
        end
    end
    while true do
        Wait(10000)
        for flatbed, towed in pairs(Towing) do
            if not DoesEntityExist(flatbed) then
                Towing[flatbed] = nil
            elseif not DoesEntityExist(towed) then
                Towing[flatbed] = nil
                Entity(flatbed).state:set("pls_towed", nil, true)
            end
        end
    end
end)

--[[
                _   _
     /\        | | (_)
    /  \   ___| |_ _  ___  _ __  ___
   / /\ \ / __| __| |/ _ \| '_ \/ __|
  / ____ \ (__| |_| | (_) | | | \__ \
 /_/    \_\___|\__|_|\___/|_| |_|___/
]]--

-- Push / flip: permission check before the client takes control
lib.callback.register("pls_mechanic:server:menu:action", function(src, action, netId)
    if action ~= "push" and action ~= "flip" then return false, "no_permission" end
    if RateLimited(src, "action", 1500) then return false, "menu_rate_limit" end
    local entity, err = CheckVehicleAction(src, "tow", netId, 6.0)
    if not entity then return false, err end
    if HasDriver(entity) then return false, "menu_vehicle_occupied" end
    if MenuServer.IsTowed(entity) then return false, "menu_vehicle_attached" end
    OpenServer.Log(src, action, ("%s used %s on vehicle %s"):format(PlayerName(src), action, GetPlate(entity)), { plate = GetPlate(entity) })
    return true
end)

-- Timed actions: client starts the timer before the progress bar, finish is accepted after 90 % of the duration
local ActionTimers = {}  -- [src] = { action, netId, time }
local TimedActions = {
    unlock = function() return Config.Unlock.duration end,
    impound = function() return Config.Impound.duration end,
    jumpStart = function() return Config.JumpStart.duration end,
}

lib.callback.register("pls_mechanic:server:menu:begin", function(src, action, netId)
    if not TimedActions[action] then return false end
    if RateLimited(src, "begin", 500) then return false end
    ActionTimers[src] = { action = action, netId = tonumber(netId), time = GetGameTimer() }
    return true
end)

local function FinishTimer(src, action, netId)
    local timer = ActionTimers[src]
    ActionTimers[src] = nil
    if not timer or timer.action ~= action or timer.netId ~= tonumber(netId) then return false end
    return GetGameTimer() - timer.time >= TimedActions[action]() * 0.9
end

lib.callback.register("pls_mechanic:server:menu:unlock", function(src, netId)
    if RateLimited(src, "unlock", math.max(2000, Config.Unlock.duration - 2000)) then
        return { ok = false, message = "menu_rate_limit" }
    end
    if not FinishTimer(src, "unlock", netId) then
        return { ok = false, message = "menu_rate_limit" }
    end
    local entity, err = CheckVehicleAction(src, "tow", netId, 5.0)
    if not entity then return { ok = false, message = err } end
    if (BRIDGE.GetItemCount(src, Utils.Item("slim_jim")) or 0) < 1 then
        return { ok = false, message = "menu_need_slim_jim" }
    end
    if GetVehicleDoorLockStatus(entity) < 2 then
        return { ok = false, message = "menu_unlock_not_locked" }
    end

    local success = math.random(100) <= Config.Unlock.successChance
    local broken = false
    if success then
        SetVehicleDoorsLocked(entity, 1)
    elseif math.random(100) <= Config.Unlock.breakChance then
        BRIDGE.RemoveItem(src, Utils.Item("slim_jim"), 1)
        broken = true
    end
    OpenServer.Log(src, "unlock", ("%s %s vehicle %s with slim jim%s"):format(PlayerName(src), success and "unlocked" or "failed to unlock", GetPlate(entity), broken and " (slim jim broke)" or ""), {
        plate = GetPlate(entity),
        success = success,
        broken = broken,
    })
    return { ok = true, success = success, broken = broken }
end)

lib.callback.register("pls_mechanic:server:menu:impound", function(src, netId)
    if RateLimited(src, "impound", 3000) then return false, "menu_rate_limit" end
    if not FinishTimer(src, "impound", netId) then return false, "menu_rate_limit" end
    local entity, err = CheckVehicleAction(src, "impound", netId, 8.0)
    if not entity then return false, err end
    if HasDriver(entity) then return false, "menu_vehicle_occupied" end
    if GetMission(entity) then return false, "menu_impound_mission" end
    if GetEntityAttachedTo(entity) ~= 0 then return false, "menu_vehicle_attached" end

    -- garage systems know the real plate (fake plate of the illegal DLC / plate text changed by the owner client)
    local plate = GetRealPlate(entity)
    local shown = GetPlate(entity)
    MenuServer.ReleaseTowed(entity)
    local ok = OpenServer.ImpoundVehicle(src, entity, plate)
    if not ok then return false, "menu_impound_failed" end
    OpenServer.Log(src, "impound", ("%s impounded vehicle %s%s"):format(PlayerName(src), plate, shown ~= plate and (" (shown plate "..shown..")") or ""), {
        plate = plate,
        shownPlate = shown ~= plate and shown or nil,
    })
    return true
end)

--[[
      _                         _____ _             _
     | |                       / ____| |           | |
     | |_   _ _ __ ___  _ __  | (___ | |_ __ _ _ __| |_
 _   | | | | | '_ ` _ \| '_ \  \___ \| __/ _` | '__| __|
| |__| | |_| | | | | | | |_) | ____) | || (_| | |  | |_
 \____/ \__,_|_| |_| |_| .__/ |_____/ \__\__,_|_|   \__|
                       | |
                       |_|
 Anyone with the item can use it (no mechanic permission)
]]--

lib.callback.register("pls_mechanic:server:menu:jumpStart", function(src, netId)
    if RateLimited(src, "jumpstart", math.max(2000, Config.JumpStart.duration - 3000)) then return false, "menu_rate_limit" end
    if not FinishTimer(src, "jumpStart", netId) then return false, "menu_rate_limit" end
    local entity = GetVehicle(netId)
    if not entity then return false, "no_vehicle" end
    if not Shops.IsNearEntity(src, entity, 6.0) then return false, "too_far" end
    if not Shops.HasTools(src, { "jump_starter" }) then return false, "menu_need_jump_starter" end
    if not Vehicles or not Vehicles.GetByEntity or not Vehicles.SetPart then return false, "vehicle_excluded" end

    local data = Vehicles.GetByEntity(entity)
    local battery = data and data.core and data.core.battery
    if battery == nil then return false, "vehicle_excluded" end
    -- server record of the mission (the statebag can be written by the owner client)
    local mission = MissionsServer and MissionsServer.GetByEntity and MissionsServer.GetByEntity(entity)
    local state = Utils.GetPartState(battery)
    if state ~= "critical" and state ~= "failed" and not (mission and mission.type == "jumpstart") then
        return false, "menu_jump_not_needed"
    end

    if battery < Config.JumpStart.batteryValue then
        Vehicles.SetPart(data.plate, "core", "battery", Config.JumpStart.batteryValue)
    end
    OpenServer.Log(src, "jumpstart", ("%s jump started vehicle %s (battery %.0f%%)"):format(PlayerName(src), data.plate, battery), {
        plate = data.plate,
        battery = battery,
    })
    if MissionsServer and MissionsServer.OnJumpStart then
        MissionsServer.OnJumpStart(src, entity)
    end
    return true
end)

AddEventHandler("playerDropped", function()
    RateLimits[source] = nil
    ActionTimers[source] = nil
end)
