--[[
  _      _  __ _
 | |    (_)/ _| |
 | |     _| |_| |_
 | |    | |  _| __|
 | |____| | | | |_
 |______|_|_|  \__|

 Lift:  Entity(veh).state.pls_lift = { shopId, pointId, base? }
        GlobalState["pls_mech_lift_<shopId>_<pointId>"] = { height, netId, base? = {x, y, z, h} }
        GlobalState reaches every client: illegal workshops keep base (their location) only in the vehicle
        statebag (clients near the vehicle only), legal workshops have it in GlobalState.
 Jack:  Entity(veh).state.pls_jack = { wheel = "lf"/"rf"/"lr"/"rr", by = src }
        the jack item is taken while placed and returned when removed.
]]--

LiftServer = {}

local LIFT_SPEED = 0.35          -- m/s, same as client/lift.lua
local JACK_DISTANCE = 5.0
local BlockedTypes = { boat = true, heli = true, plane = true, submarine = true, train = true, blimp = true }
local JackSides = { lf = true, rf = true, lr = true, rr = true }

local Lifts = {}                 -- [stateKey] = { shopId, pointId, netId, base, busyUntil }
local Jacks = {}                 -- [entity] = { netId, by }
local Cooldowns = {}             -- [src] = time

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

local function stateKey(shopId, pointId)
    return ("pls_mech_lift_%s_%s"):format(shopId, pointId)
end

local function checkCooldown(src, ms)
    local now = GetGameTimer()
    if Cooldowns[src] and now - Cooldowns[src] < ms then return false end
    Cooldowns[src] = now
    return true
end

local function permissionReason(src)
    if Config.RequireDuty and not Player(src).state.pls_mechanic_duty and not Shops.IsIllegal(Shops.GetPlayerShopId(src)) then
        return "not_on_duty"
    end
    return "no_permission"
end

local ItemLabels = nil
local function itemLabel(itemName)
    if not ItemLabels then
        ItemLabels = {}
        for name, data in pairs(BRIDGE.GetItems() or {}) do
            if type(data) == "table" then
                ItemLabels[name] = data.label or name
            end
        end
    end
    return ItemLabels[itemName] or itemName
end

local function isPlayerOnline(src)
    return src ~= nil and GetPlayerName(src) ~= nil
end

local function getLiftPoint(shopId, pointId)
    local shop = Shops.Get(shopId)
    local point = shop and Utils.GetShopPoint(shop, pointId)
    if not point or point.type ~= "lift" or not point.coords then return nil, nil end
    return shop, point
end

local function isNearCoords(src, coords, maxDistance)
    return #(GetEntityCoords(GetPlayerPed(src)) - coords) <= maxDistance
end

local function getDuration(height)
    return math.ceil((height or 0) / LIFT_SPEED * 1000)
end

function LiftServer.GetStateKey(shopId, pointId)
    return stateKey(shopId, pointId)
end

-- Vehicle entity currently on lift of shop point (or nil)
function LiftServer.GetVehicle(shopId, pointId)
    local lift = Lifts[stateKey(shopId, pointId)]
    return lift and Shops.GetEntity(lift.netId) or nil
end

-- Server records for location checks (statebags can be written by the entity owner client)
function LiftServer.IsOnLift(entity)
    for _, lift in pairs(Lifts) do
        if lift.entity == entity or (lift.netId and Shops.GetEntity(lift.netId) == entity) then
            return true
        end
    end
    return false
end

function LiftServer.GetJackWheel(entity)
    local jack = Jacks[entity]
    return jack and jack.wheel or nil
end

-- Base position of the vehicle in the vehicle statebag (illegal workshops, not in GlobalState)
local function entityBase(entity)
    local liftState = entity and Entity(entity).state.pls_lift
    return type(liftState) == "table" and type(liftState.base) == "table" and liftState.base or nil
end

-- Clears lift state. drop = put vehicle back to its ground position (vehicle would stay in the air)
local function releaseLift(key, drop)
    local lift = Lifts[key]
    local state = GlobalState[key]
    local netId = (lift and lift.netId) or (state and state.netId)
    local entity = netId and Shops.GetEntity(netId)
    local base = (lift and lift.base) or (state and state.base) or entityBase(entity)
    if entity then
        Entity(entity).state:set("pls_lift", nil, true)
        if drop and base then
            SetEntityCoords(entity, base.x + 0.0, base.y + 0.0, base.z + 0.0, false, false, false, false)
        end
        FreezeEntityPosition(entity, false)
    end
    Lifts[key] = nil
    GlobalState:set(key, nil, true)
end

-- Clears jack state. giveTo = player who gets the jack item back
local function clearJack(entity, giveTo)
    local jack = Jacks[entity]
    Jacks[entity] = nil
    if DoesEntityExist(entity) then
        Entity(entity).state:set("pls_jack", nil, true)
        FreezeEntityPosition(entity, false)
    end
    if isPlayerOnline(giveTo) then
        BRIDGE.AddItem(giveTo, Utils.Item("car_jack"), 1)
    end
    return jack
end

--[[
  _      _  __ _
 | |    (_)/ _| |
 | |     _| |_| |_
 | |    | |  _| __|
 | |____| | | | |_
 |______|_|_|  \__|
]]--

RegisterNetEvent("pls_mechanic:server:lift:raise", function(shopId, pointId, netId)
    local src = source
    if not CanTrustPlayer(src) then return end
    if not checkCooldown(src, 1500) then return end
    local shop, point = getLiftPoint(shopId, pointId)
    if not point then return end
    local allowed = Shops.HasPermission(src, "service", shop.id)
    if not allowed then
        Shops.Notify(src, locale(permissionReason(src)), "error")
        return
    end
    local pointCoords = Utils.Vec3(point.coords)
    local radius = point.radius or Config.PointTypes.lift.radius
    if not isNearCoords(src, pointCoords, radius + 5.0) then
        Shops.Notify(src, locale("too_far"), "error")
        return
    end
    local key = stateKey(shop.id, point.id)
    local state = GlobalState[key]
    local lift = Lifts[key]
    if (state and ((state.height or 0) > 0 or state.netId)) or (lift and lift.busyUntil > GetGameTimer()) then
        Shops.Notify(src, locale("lift_busy"), "error")
        return
    end
    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or GetEntityType(entity) ~= 2 or BlockedTypes[GetVehicleType(entity)] then
        Shops.Notify(src, locale("lift_no_vehicle"), "error")
        return
    end
    local coords = GetEntityCoords(entity)
    if #(coords.xy - pointCoords.xy) > radius then
        Shops.Notify(src, locale("lift_no_vehicle"), "error")
        return
    end
    local entityState = Entity(entity).state
    if entityState.pls_lift then
        Shops.Notify(src, locale("lift_busy"), "error")
        return
    end
    if entityState.pls_jack then
        Shops.Notify(src, locale("lift_remove_jack"), "error")
        return
    end
    if GetPedInVehicleSeat(entity, -1) ~= 0 then
        Shops.Notify(src, locale("lift_vehicle_occupied"), "error")
        return
    end

    local height = Utils.Clamp(tonumber(point.data and point.data.height) or 1.8, 0.5, 2.5)
    local base = { x = Utils.Round(coords.x, 3), y = Utils.Round(coords.y, 3), z = Utils.Round(coords.z, 3), h = Utils.Round(GetEntityHeading(entity), 2) }
    -- GlobalState goes to every client: coords of an illegal workshop only in the vehicle statebag
    local illegal = Shops.IsIllegal(shop)
    FreezeEntityPosition(entity, true)
    entityState:set("pls_lift", { shopId = shop.id, pointId = point.id, base = illegal and base or nil }, true)
    GlobalState:set(key, { height = height, netId = tonumber(netId), base = not illegal and base or nil }, true)
    Lifts[key] = { shopId = shop.id, pointId = point.id, netId = tonumber(netId), entity = entity, base = base, busyUntil = GetGameTimer() + getDuration(height) }
    Shops.Notify(src, locale("lift_raising"), "inform")
    local plate = Vehicles and Vehicles.GetEntityPlate and Vehicles.GetEntityPlate(entity) or Utils.TrimPlate(GetVehicleNumberPlateText(entity))
    OpenServer.Log(src, "lift_raise", ("%s - %s"):format(shop.name, plate or "-"), { shopId = shop.id, pointId = point.id })
end)

RegisterNetEvent("pls_mechanic:server:lift:lower", function(shopId, pointId)
    local src = source
    if not CanTrustPlayer(src) then return end
    if not checkCooldown(src, 1500) then return end
    local shop, point = getLiftPoint(shopId, pointId)
    if not point then return end
    local allowed = Shops.HasPermission(src, "service", shop.id)
    if not allowed then
        Shops.Notify(src, locale(permissionReason(src)), "error")
        return
    end
    local radius = point.radius or Config.PointTypes.lift.radius
    if not isNearCoords(src, Utils.Vec3(point.coords), radius + 5.0) then
        Shops.Notify(src, locale("too_far"), "error")
        return
    end
    local key = stateKey(shop.id, point.id)
    local state = GlobalState[key]
    local lift = Lifts[key]
    if not state or (state.height or 0) <= 0 then
        Shops.Notify(src, locale("lift_not_raised"), "error")
        return
    end
    if lift and lift.busyUntil > GetGameTimer() then
        Shops.Notify(src, locale("lift_busy"), "error")
        return
    end
    local netId = state.netId
    local duration = getDuration(state.height)
    GlobalState:set(key, { height = 0, netId = netId, base = state.base }, true)
    if lift then
        lift.busyUntil = GetGameTimer() + duration
    end
    Shops.Notify(src, locale("lift_lowering"), "inform")
    OpenServer.Log(src, "lift_lower", shop.name, { shopId = shop.id, pointId = point.id })

    -- vehicle is down, lift is free again
    SetTimeout(duration + 750, function()
        local current = GlobalState[key]
        if not current or (current.height or 0) > 0 or current.netId ~= netId then return end
        local entity = netId and Shops.GetEntity(netId)
        if entity then
            Entity(entity).state:set("pls_lift", nil, true)
            FreezeEntityPosition(entity, false)
        end
        Lifts[key] = nil
        GlobalState:set(key, { height = 0 }, true)
    end)
end)

--[[
      _            _
     | |          | |
     | | __ _  ___| | __
 _   | |/ _` |/ __| |/ /
| |__| | (_| | (__|   <
 \____/ \__,_|\___|_|\_\
]]--

lib.callback.register("pls_mechanic:server:lift:jack", function(src, netId, side)
    if not checkCooldown(src, 1500) then return { ok = false, message = locale("repair_too_fast") } end
    if not JackSides[side] then return { ok = false, message = locale("jack_no_wheel") } end
    if not Shops.HasPermission(src, "service") then return { ok = false, message = locale(permissionReason(src)) } end
    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or GetEntityType(entity) ~= 2 then return { ok = false, message = locale("no_vehicle") } end
    if GetVehicleType(entity) ~= "automobile" then return { ok = false, message = locale("jack_not_supported") } end
    if not Shops.IsNearEntity(src, entity, JACK_DISTANCE) then return { ok = false, message = locale("too_far") } end
    local entityState = Entity(entity).state
    if entityState.pls_lift then return { ok = false, message = locale("jack_on_lift") } end
    if entityState.pls_jack or Jacks[entity] then return { ok = false, message = locale("jack_already") } end
    if GetPedInVehicleSeat(entity, -1) ~= 0 then return { ok = false, message = locale("jack_vehicle_occupied") } end
    local itemName = Utils.Item("car_jack")
    if (BRIDGE.GetItemCount(src, itemName) or 0) < 1 then return { ok = false, message = locale("missing_tool", itemLabel(itemName)) } end

    BRIDGE.RemoveItem(src, itemName, 1)
    entityState:set("pls_jack", { wheel = side, by = src }, true)
    Jacks[entity] = { netId = tonumber(netId), by = src, wheel = side }
    OpenServer.Log(src, "jack_place", Utils.TrimPlate(GetVehicleNumberPlateText(entity)), { wheel = side })
    return { ok = true }
end)

lib.callback.register("pls_mechanic:server:lift:removeJack", function(src, netId)
    if not checkCooldown(src, 1500) then return { ok = false, message = locale("repair_too_fast") } end
    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or GetEntityType(entity) ~= 2 then return { ok = false, message = locale("no_vehicle") } end
    if not Shops.IsNearEntity(src, entity, JACK_DISTANCE) then return { ok = false, message = locale("too_far") } end
    -- server record only, the statebag can be written by the owning client (jack item would be duplicated)
    local jack = Jacks[entity]
    if not jack then return { ok = false, message = locale("jack_none") } end
    if jack.by ~= src and not Shops.HasPermission(src, "service") then
        return { ok = false, message = locale(permissionReason(src)) }
    end
    clearJack(entity, src)
    OpenServer.Log(src, "jack_remove", Utils.TrimPlate(GetVehicleNumberPlateText(entity)), { wheel = jack.wheel })
    return { ok = true }
end)

--[[
   _____ _
  / ____| |
 | |    | | ___  __ _ _ __  _   _ _ __
 | |    | |/ _ \/ _` | '_ \| | | | '_ \
 | |____| |  __/ (_| | | | | |_| | |_) |
  \_____|_|\___|\__,_|_| |_|\__,_| .__/
                                 | |
                                 |_|
]]--

-- Lifts of deleted points / vehicles are released
local function validateLifts()
    for key, lift in pairs(Lifts) do
        local _, point = getLiftPoint(lift.shopId, lift.pointId)
        if not point then
            releaseLift(key, true)
        elseif not Shops.GetEntity(lift.netId) then
            releaseLift(key, false)
        end
    end
    for entity, jack in pairs(Jacks) do
        if not DoesEntityExist(entity) then
            Jacks[entity] = nil
            if isPlayerOnline(jack.by) then
                BRIDGE.AddItem(jack.by, Utils.Item("car_jack"), 1)
            end
        end
    end
end

-- Adopts lift / jack states that survived (restart after crash), clears stale ones
local function adoptStates()
    for _, entity in ipairs(GetAllVehicles()) do
        local entityState = Entity(entity).state
        local netId = NetworkGetNetworkIdFromEntity(entity)
        if entityState.pls_jack then
            Jacks[entity] = { netId = netId, by = entityState.pls_jack.by, wheel = entityState.pls_jack.wheel }
        end
        local liftState = entityState.pls_lift
        if liftState then
            local key = stateKey(liftState.shopId, liftState.pointId)
            local global = GlobalState[key]
            -- illegal workshops: base is in the vehicle statebag only
            local base = (global and global.base) or (type(liftState.base) == "table" and liftState.base or nil)
            if global and global.netId == netId and getLiftPoint(liftState.shopId, liftState.pointId) then
                Lifts[key] = { shopId = liftState.shopId, pointId = liftState.pointId, netId = netId, entity = entity, base = base, busyUntil = 0 }
            else
                entityState:set("pls_lift", nil, true)
                if base then
                    SetEntityCoords(entity, base.x + 0.0, base.y + 0.0, base.z + 0.0, false, false, false, false)
                end
                FreezeEntityPosition(entity, false)
            end
        end
    end
    -- GlobalState of lift points without vehicle
    for _, shop in pairs(Shops.GetAll()) do
        for _, point in pairs(shop.points or {}) do
            if point.type == "lift" then
                local key = stateKey(shop.id, point.id)
                local global = GlobalState[key]
                if global and not Lifts[key] and (global.netId or (global.height or 0) > 0) then
                    GlobalState:set(key, { height = 0 }, true)
                end
            end
        end
    end
end

AddEventHandler("pls_mechanic:server:shopsLoaded", function()
    adoptStates()
end)

AddEventHandler("pls_mechanic:server:shopsChanged", function()
    validateLifts()
end)

AddEventHandler("entityRemoved", function(entity)
    local jack = Jacks[entity]
    if jack then
        Jacks[entity] = nil
        if isPlayerOnline(jack.by) then
            BRIDGE.AddItem(jack.by, Utils.Item("car_jack"), 1)
        end
    end
    for key, lift in pairs(Lifts) do
        if lift.entity == entity then
            Lifts[key] = nil
            GlobalState:set(key, nil, true)
        end
    end
end)

CreateThread(function()
    if Shops.IsLoaded() then
        adoptStates()
    end
    while true do
        Wait(5000)
        validateLifts()
    end
end)

AddEventHandler("playerDropped", function()
    Cooldowns[source] = nil
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for key in pairs(Lifts) do
        releaseLift(key, true)
    end
    for entity, jack in pairs(Jacks) do
        clearJack(entity, jack.by)
    end
end)
