--[[
  _      _  __ _
 | |    (_)/ _| |
 | |     _| |_| |_
 | |    | |  _| __|
 | |____| | | | |_
 |______|_|_|  \__|

 Lift:  GlobalState "pls_mech_lift_<shopId>_<pointId>" = { height, netId, base? = {x, y, z, h} }
        all clients animate the lift prop, the network owner of the vehicle moves it.
        Illegal workshops: base is not in GlobalState (it reaches every client), it's in the vehicle statebag
        pls_lift = { shopId, pointId, base } (clients near the vehicle only).
 Jack:  Entity(veh).state.pls_jack = { wheel = "lf"/"rf"/"lr"/"rr", by = serverId }
        all clients render the jack prop, the network owner freezes and tilts the vehicle
        (frozen jacked vehicle = already tilted by previous owner).
]]--

Lift = {}

local LIFT_SPEED = 0.35             -- m/s, same as server/lift.lua
local PROP_DISTANCE = 80.0
local JACK_RAISE = 0.16             -- m, jacked corner goes up by this
local JACK_WHEEL_DISTANCE = 1.8

local Busy = false
local Lifts = {}                    -- [stateKey] = { key, shopId, pointId, coords, heading, current, target, netId, base, object }
local JackStates = {}               -- [vehicle] = { side, object }
local JackTilts = {}                -- [vehicle] = { coords, rot } when we tilted it
local TiltSigns = nil               -- { pitch, roll } found on first tilt
local RemoveJackTarget = nil

local SideWheel = { lf = 0, rf = 1, lr = 4, rr = 5 }

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

local function permissionReason()
    if Config.RequireDuty and not Core.IsOnDuty() and not Core.GetIllegalShopId() then
        return locale("not_on_duty")
    end
    return locale("no_permission")
end

-- Repair / tuning / another animation / scene of the illegal DLC keeps the player busy. Notifies the reason.
local function isPlayerBusy()
    if Tuning and ((Tuning.IsInstalling and Tuning.IsInstalling()) or (Tuning.IsOpen and Tuning.IsOpen())) then
        Core.Notify(locale("tuning_busy"), "error")
        return true
    end
    if (Repair and Repair.IsBusy and Repair.IsBusy()) or Anim.IsBusy() or Core.IsExternalBusy() then
        Core.Notify(locale("repair_busy"), "error")
        return true
    end
    return false
end

local function isOwner(entity)
    return NetworkGetEntityOwner(entity) == cache.playerId
end

function Lift.GetStateKey(shopId, pointId)
    return ("pls_mech_lift_%s_%s"):format(shopId, pointId)
end

-- { height, netId, base } or nil
function Lift.GetState(shopId, pointId)
    return GlobalState[Lift.GetStateKey(shopId, pointId)]
end

-- Lift is up or moving with a vehicle
function Lift.IsInUse(shopId, pointId)
    local state = Lift.GetState(shopId, pointId)
    return state ~= nil and ((state.height or 0) > 0 or state.netId ~= nil)
end

--[[
  _      _  __ _
 | |    (_)/ _| |
 | |     _| |_| |_
 | |    | |  _| __|
 | |____| | | | |_
 |______|_|_|  \__|
]]--

local function deleteLiftProp(lift)
    if lift.object and DoesEntityExist(lift.object) then
        DeleteEntity(lift.object)
    end
    lift.object = nil
end

local function getLiftPropPosition(lift)
    local prop = Config.Props.lift
    local offset = prop.pos or vec3(0.0, 0.0, 0.0)
    local heading = math.rad(lift.heading)
    local x = lift.coords.x + offset.x * math.cos(heading) - offset.y * math.sin(heading)
    local y = lift.coords.y + offset.x * math.sin(heading) + offset.y * math.cos(heading)
    return vector3(x, y, lift.coords.z + offset.z + (lift.current or 0.0))
end

local function ensureLiftProp(lift)
    local prop = Config.Props.lift
    if lift.object or not prop or not prop.model then return end
    local model = joaat(prop.model)
    if not IsModelValid(model) then return end
    lib.requestModel(model)
    local pos = getLiftPropPosition(lift)
    lift.object = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(lift.object, lift.heading + (prop.rot and prop.rot.z or 0.0))
    FreezeEntityPosition(lift.object, true)
    SetModelAsNoLongerNeeded(model)
end

local function updateLiftProp(lift)
    if not lift.object or not DoesEntityExist(lift.object) then return end
    local pos = getLiftPropPosition(lift)
    SetEntityCoordsNoOffset(lift.object, pos.x, pos.y, pos.z, false, false, false)
end

local function getLiftVehicle(lift)
    if not lift.netId or not NetworkDoesEntityExistWithNetworkId(lift.netId) then return nil end
    local vehicle = NetToVeh(lift.netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

-- Base position from the vehicle statebag (illegal workshops, GlobalState has none)
local function getVehicleBase(vehicle)
    if not vehicle then return nil end
    local liftState = Entity(vehicle).state.pls_lift
    return type(liftState) == "table" and type(liftState.base) == "table" and liftState.base or nil
end

-- Puts vehicle down to base position (forced release: point deleted / state cleared)
local function dropVehicle(vehicle, base)
    if not vehicle or not DoesEntityExist(vehicle) or not isOwner(vehicle) then return end
    if base then
        SetEntityCoordsNoOffset(vehicle, base.x, base.y, base.z, false, false, false)
    end
    FreezeEntityPosition(vehicle, false)
    SetVehicleOnGroundProperly(vehicle)
end

-- Owner keeps the vehicle on the lift platform
local function updateLiftVehicle(lift, moving)
    local vehicle = getLiftVehicle(lift)
    if vehicle and not lift.base then
        -- illegal workshop: the vehicle statebag can arrive after GlobalState / when the vehicle streams in
        lift.base = getVehicleBase(vehicle)
    end
    if not vehicle or not lift.base or not isOwner(vehicle) then return end
    local base = lift.base
    if lift.target <= 0.0 and lift.current <= 0.0 then
        if lift.releasedNet ~= lift.netId then
            lift.releasedNet = lift.netId
            dropVehicle(vehicle, base)
        end
        return
    end
    lift.releasedNet = nil
    local z = base.z + lift.current
    if moving or not IsEntityPositionFrozen(vehicle) or math.abs(GetEntityCoords(vehicle).z - z) > 0.03 then
        FreezeEntityPosition(vehicle, true)
        SetEntityCoordsNoOffset(vehicle, base.x, base.y, z, false, false, false)
        SetEntityRotation(vehicle, 0.0, 0.0, base.h or GetEntityHeading(vehicle), 2, true)
    end
end

local function applyLiftState(lift, state)
    local oldNet, oldBase = lift.netId, lift.base
    lift.target = state and tonumber(state.height) or 0.0
    lift.netId = state and state.netId or nil
    lift.base = state and state.base or nil
    if not lift.base and lift.netId then
        -- illegal workshop: base from the vehicle statebag (same vehicle keeps the known one)
        lift.base = getVehicleBase(getLiftVehicle(lift)) or (lift.netId == oldNet and oldBase or nil)
    end
    if lift.current == nil then
        lift.current = lift.target
    end
    -- state cleared while vehicle was still in the air (point deleted, vehicle released by server)
    if oldNet and not lift.netId then
        local vehicle = NetworkDoesEntityExistWithNetworkId(oldNet) and NetToVeh(oldNet) or 0
        if vehicle ~= 0 and IsEntityPositionFrozen(vehicle) and not Entity(vehicle).state.pls_lift then
            dropVehicle(vehicle, oldBase)
        end
    end
end

local function syncLifts(shops)
    local seen = {}
    for _, shop in pairs(shops or {}) do
        for _, point in pairs(shop.points or {}) do
            if point.type == "lift" and point.coords then
                local key = Lift.GetStateKey(shop.id, point.id)
                local coords = Utils.Vec3(point.coords)
                local heading = (point.heading or 0.0) + 0.0
                local lift = Lifts[key]
                seen[key] = true
                if not lift then
                    lift = { key = key }
                    Lifts[key] = lift
                elseif #(lift.coords - coords) > 0.01 or lift.heading ~= heading then
                    deleteLiftProp(lift)
                end
                lift.shopId, lift.pointId, lift.coords, lift.heading = shop.id, point.id, coords, heading
                applyLiftState(lift, GlobalState[key])
            end
        end
    end
    for key, lift in pairs(Lifts) do
        if not seen[key] then
            deleteLiftProp(lift)
            local vehicle = getLiftVehicle(lift)
            if vehicle then dropVehicle(vehicle, lift.base) end
            Lifts[key] = nil
        end
    end
end

Core.OnShopsUpdated(syncLifts)

AddStateBagChangeHandler(nil, "global", function(_, key, value)
    if type(key) ~= "string" or key:sub(1, 14) ~= "pls_mech_lift_" then return end
    local lift = Lifts[key]
    if lift then
        applyLiftState(lift, value)
    end
end)

-- Lift animation (Wait(0) only while a nearby lift is moving)
CreateThread(function()
    local last = GetGameTimer()
    while true do
        local now = GetGameTimer()
        local delta = math.min((now - last) / 1000.0, 0.1)
        last = now
        local sleep = 1000
        local pedCoords = GetEntityCoords(cache.ped)
        for _, lift in pairs(Lifts) do
            local distance = #(pedCoords - lift.coords)
            if distance < PROP_DISTANCE then
                ensureLiftProp(lift)
            elseif lift.object and distance > PROP_DISTANCE + 20.0 then
                deleteLiftProp(lift)
            end
            local moving = lift.current ~= lift.target
            if moving then
                local diff = lift.target - lift.current
                local stepSize = LIFT_SPEED * delta
                if math.abs(diff) <= stepSize or distance > 250.0 then
                    lift.current = lift.target
                else
                    lift.current = lift.current + (diff > 0 and stepSize or -stepSize)
                    sleep = 0
                end
                updateLiftProp(lift)
            end
            updateLiftVehicle(lift, moving)
        end
        Wait(sleep)
    end
end)

local function findLiftVehicle(point)
    local coords = Utils.Vec3(point.coords)
    local radius = point.radius or Config.PointTypes.lift.radius
    local vehicle = lib.getClosestVehicle(coords, radius, true)
    return vehicle
end

function Lift.Raise(shop, point)
    CreateThread(function()
        if Busy or isPlayerBusy() then return end
        local vehicle = findLiftVehicle(point)
        if not vehicle or not NetworkGetEntityIsNetworked(vehicle) then
            Core.Notify(locale("lift_no_vehicle"), "error")
            return
        end
        if GetPedInVehicleSeat(vehicle, -1) ~= 0 then
            Core.Notify(locale("lift_vehicle_occupied"), "error")
            return
        end
        if Core.GetJack(vehicle) then
            Core.Notify(locale("lift_remove_jack"), "error")
            return
        end
        Busy = true
        if Anim.Phase({ label = locale("lift_progress_raise"), duration = 2000, anim = "button", sound = "button" }) then
            -- operator becomes network owner, so the movement runs on his client
            Core.RequestControl(vehicle, 1500)
            TriggerSecureEvent("pls_mechanic:server:lift:raise", shop.id, point.id, VehToNet(vehicle))
        end
        Busy = false
    end)
end

function Lift.Lower(shop, point)
    CreateThread(function()
        if Busy or isPlayerBusy() then return end
        Busy = true
        if Anim.Phase({ label = locale("lift_progress_lower"), duration = 2000, anim = "button", sound = "button" }) then
            local lift = Lifts[Lift.GetStateKey(shop.id, point.id)]
            local vehicle = lift and getLiftVehicle(lift)
            if vehicle then
                Core.RequestControl(vehicle, 1500)
            end
            TriggerSecureEvent("pls_mechanic:server:lift:lower", shop.id, point.id)
        end
        Busy = false
    end)
end

ShopPoints.RegisterAction("lift", {
    label = locale("lift_raise"),
    icon = "fa-solid fa-arrow-up",
    perm = "service",
    canInteract = function(shop, point)
        return not Busy and not Lift.IsInUse(shop.id, point.id)
    end,
    onSelect = function(shop, point)
        Lift.Raise(shop, point)
    end,
})

ShopPoints.RegisterAction("lift", {
    label = locale("lift_lower"),
    icon = "fa-solid fa-arrow-down",
    perm = "service",
    canInteract = function(shop, point)
        local state = Lift.GetState(shop.id, point.id)
        return not Busy and state ~= nil and (state.height or 0) > 0
    end,
    onSelect = function(shop, point)
        Lift.Lower(shop, point)
    end,
})

--[[
      _            _
     | |          | |
     | | __ _  ___| | __
 _   | |/ _` |/ __| |/ /
| |__| | (_| | (__|   <
 \____/ \__,_|\___|_|\_\
]]--

-- Local offset of wheel for jack side
local function getWheelOffset(vehicle, side)
    local bone = GetEntityBoneIndexByName(vehicle, Utils.WheelBones[SideWheel[side] or 0])
    if bone == -1 then return nil end
    local world = GetWorldPositionOfEntityBone(vehicle, bone)
    return GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
end

local function deleteJackProp(vehicle)
    local jack = JackStates[vehicle]
    if jack and jack.object and DoesEntityExist(jack.object) then
        DeleteEntity(jack.object)
    end
end

-- Jack prop on the ground at the jacking point next to the wheel
local function createJackProp(vehicle, side)
    local prop = Config.Props.car_jack
    if not prop or not prop.model then return nil end
    local model = joaat(prop.model)
    if not IsModelValid(model) then return nil end
    local offset = getWheelOffset(vehicle, side)
    if not offset then return nil end
    lib.requestModel(model)
    local towardsCenter = offset.y > 0 and -0.55 or 0.55
    local pos = GetOffsetFromEntityInWorldCoords(vehicle, offset.x * 0.85, offset.y + towardsCenter, offset.z)
    local object = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(object, GetEntityHeading(vehicle) + (offset.x < 0 and 90.0 or -90.0))
    PlaceObjectOnGroundProperly(object)
    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(model)
    return object
end

-- Owner tilts the vehicle: jacked corner rises by JACK_RAISE, diagonal corner stays on the ground
local function applyJackTilt(vehicle, side)
    local offset = getWheelOffset(vehicle, side)
    if not offset then return end
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local length, width = math.max(max.y - min.y, 1.0), math.max(max.x - min.x, 1.0)
    local pitch = math.deg(math.asin(Utils.Clamp(JACK_RAISE / (2.0 * length), 0.0, 1.0)))
    local roll = math.deg(math.asin(Utils.Clamp(JACK_RAISE / (2.0 * width), 0.0, 1.0)))
    local front = side == "lf" or side == "rf"
    local left = side == "lf" or side == "lr"
    local coords = GetEntityCoords(vehicle)
    local rot = GetEntityRotation(vehicle, 2)
    local wheelZ = GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z).z

    local function apply(signs)
        SetEntityCoordsNoOffset(vehicle, coords.x, coords.y, coords.z + JACK_RAISE * 0.5, false, false, false)
        SetEntityRotation(vehicle, rot.x + (front and pitch or -pitch) * signs[1], rot.y + (left and roll or -roll) * signs[2], rot.z, 2, true)
        return GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z).z - wheelZ
    end

    FreezeEntityPosition(vehicle, true)
    if TiltSigns then
        apply(TiltSigns)
    else
        -- rotation sign convention is verified once by measuring the jacked wheel
        local best, bestRise = nil, nil
        for _, signs in ipairs({ { 1.0, 1.0 }, { 1.0, -1.0 }, { -1.0, 1.0 }, { -1.0, -1.0 } }) do
            local rise = apply(signs)
            if not bestRise or rise > bestRise then best, bestRise = signs, rise end
        end
        TiltSigns = best
        apply(best)
    end
    JackTilts[vehicle] = { coords = coords, rot = rot }
end

local function lowerJackedVehicle(vehicle)
    if not DoesEntityExist(vehicle) or not isOwner(vehicle) then
        JackTilts[vehicle] = nil
        return
    end
    local tilt = JackTilts[vehicle]
    if tilt and tilt.coords then
        SetEntityCoordsNoOffset(vehicle, tilt.coords.x, tilt.coords.y, tilt.coords.z, false, false, false)
        SetEntityRotation(vehicle, tilt.rot.x, tilt.rot.y, tilt.rot.z, 2, true)
    end
    if not Entity(vehicle).state.pls_lift then
        FreezeEntityPosition(vehicle, false)
        SetVehicleOnGroundProperly(vehicle)
    end
    JackTilts[vehicle] = nil
end

-- Reacts to jack state of vehicle (statebag handler + periodic scan)
local function handleJack(vehicle, jack)
    local current = JackStates[vehicle]
    if jack and jack.wheel and SideWheel[jack.wheel] then
        if not current or current.side ~= jack.wheel then
            if current then deleteJackProp(vehicle) end
            local entry = { side = jack.wheel }
            JackStates[vehicle] = entry
            local object = createJackProp(vehicle, jack.wheel)
            if JackStates[vehicle] == entry then
                entry.object = object
            elseif object then
                DeleteEntity(object)
            end
        end
        -- owner (also after ownership migration) keeps it frozen and tilted
        if isOwner(vehicle) and not JackTilts[vehicle] then
            if IsEntityPositionFrozen(vehicle) then
                JackTilts[vehicle] = { coords = nil }
            else
                applyJackTilt(vehicle, jack.wheel)
            end
        end
    elseif current then
        deleteJackProp(vehicle)
        JackStates[vehicle] = nil
        lowerJackedVehicle(vehicle)
    end
end

AddStateBagChangeHandler("pls_jack", nil, function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    CreateThread(function()
        handleJack(entity, value)
    end)
end)

-- Streams jack props of nearby vehicles, cleans up deleted ones
CreateThread(function()
    while true do
        local pedCoords = GetEntityCoords(cache.ped)
        local seen = {}
        for _, vehicle in ipairs(GetGamePool("CVehicle")) do
            if #(pedCoords - GetEntityCoords(vehicle)) < PROP_DISTANCE then
                local jack = Entity(vehicle).state.pls_jack
                if jack or JackStates[vehicle] then
                    seen[vehicle] = true
                    handleJack(vehicle, jack)
                end
            end
        end
        for vehicle in pairs(JackStates) do
            if not seen[vehicle] then
                deleteJackProp(vehicle)
                JackStates[vehicle] = nil
                if not DoesEntityExist(vehicle) then JackTilts[vehicle] = nil end
            end
        end
        Wait(1000)
    end
end)

local function findJackWheel(vehicle)
    local pedCoords = GetEntityCoords(cache.ped)
    local best, bestDistance = nil, nil
    for side, index in pairs(SideWheel) do
        local bone = GetEntityBoneIndexByName(vehicle, Utils.WheelBones[index])
        if bone ~= -1 then
            local distance = #(pedCoords.xy - GetWorldPositionOfEntityBone(vehicle, bone).xy)
            if distance <= JACK_WHEEL_DISTANCE and (not bestDistance or distance < bestDistance) then
                best, bestDistance = side, distance
            end
        end
    end
    return best
end

function Lift.PlaceJack()
    if Busy or isPlayerBusy() then return end
    if cache.vehicle then
        Core.Notify(locale("jack_leave_vehicle"), "error")
        return
    end
    if not Core.HasPermission("service") then
        Core.Notify(permissionReason(), "error")
        return
    end
    local vehicle = Core.GetClosestVehicle(4.0)
    if not vehicle or not NetworkGetEntityIsNetworked(vehicle) then
        Core.Notify(locale("no_vehicle"), "error")
        return
    end
    if GetVehicleNumberOfWheels(vehicle) < 4 or GetVehicleClass(vehicle) == 8 or Config.ExcludedClasses[GetVehicleClass(vehicle)] then
        Core.Notify(locale("jack_not_supported"), "error")
        return
    end
    if Core.IsVehicleOnLift(vehicle) then
        Core.Notify(locale("jack_on_lift"), "error")
        return
    end
    if Core.GetJack(vehicle) then
        Core.Notify(locale("jack_already"), "error")
        return
    end
    if GetPedInVehicleSeat(vehicle, -1) ~= 0 then
        Core.Notify(locale("jack_vehicle_occupied"), "error")
        return
    end
    local side = findJackWheel(vehicle)
    if not side then
        Core.Notify(locale("jack_no_wheel"), "error")
        return
    end
    Busy = true
    -- carry the jack to the wheel, slide it under the jacking point, pump the vehicle up
    local coords, heading = Core.GetAccessPosition(vehicle, "wheel", SideWheel[side])
    local cancel = function() return not DoesEntityExist(vehicle) end
    local carry = Anim.Carry("jack_hand", false)
    Anim.WalkAround(vehicle, coords, heading, 6000, cancel)
    local positioned = Anim.Phase({ label = locale("jack_phase_position"), duration = 2500, anim = "kneel_low", keepCarry = true, vehicle = vehicle, cancel = cancel })
    Anim.StopCarry(carry)
    if positioned then
        -- the owner tilts the vehicle, take control so it happens right away
        Core.RequestControl(vehicle, 2000)
        local result = lib.callback.await("pls_mechanic:server:lift:jack", false, VehToNet(vehicle), side)
        if result and result.ok then
            Anim.Phase({ label = locale("jack_phase_pump"), duration = 3500, anim = "kneel", prop = "wrench", vehicle = vehicle, cancel = cancel })
            Core.Notify(locale("jack_placed"), "success")
        else
            Core.Notify(result and result.message or locale("jack_failed"), "error")
        end
    else
        Core.Notify(locale("cancelled"), "error")
    end
    Busy = false
end

function Lift.RemoveJack(vehicle)
    if Busy or not vehicle or not DoesEntityExist(vehicle) or isPlayerBusy() then return end
    local jack = Core.GetJack(vehicle)
    if not jack then return end
    Busy = true
    local coords, heading = Core.GetAccessPosition(vehicle, "wheel", SideWheel[jack.wheel] or 0)
    local cancel = function() return not DoesEntityExist(vehicle) end
    Anim.WalkAround(vehicle, coords, heading, 6000, cancel)
    if Anim.Phase({ label = locale("jack_phase_lower"), duration = 2500, anim = "kneel", prop = "wrench", vehicle = vehicle, cancel = cancel }) then
        Core.RequestControl(vehicle, 2000)
        local result = lib.callback.await("pls_mechanic:server:lift:removeJack", false, VehToNet(vehicle))
        if result and result.ok then
            -- jack pulled out from under the vehicle
            Anim.Play("pickup")
            Core.Notify(locale("jack_removed"), "success")
        else
            Core.Notify(result and result.message or locale("jack_failed"), "error")
        end
    else
        Core.Notify(locale("cancelled"), "error")
    end
    Busy = false
end

Items.Register("car_jack", function()
    CreateThread(function()
        local ok, err = pcall(Lift.PlaceJack)
        if not ok then
            Busy = false
            Anim.Cleanup()
            print("[pls_mechanic] jack error: "..tostring(err))
        end
    end)
end)

CreateThread(function()
    RemoveJackTarget = BRIDGE.AddGlobalVehicleTarget({
        {
            name = "pls_mechanic_remove_jack",
            label = locale("jack_target_remove"),
            icon = "fa-solid fa-car-burst",
            distance = 2.5,
            canInteract = function(entity)
                if Busy or cache.vehicle or not entity or entity == 0 then return false end
                local jack = Core.GetJack(entity)
                if not jack then return false end
                return jack.by == cache.serverId or Core.HasPermission("service")
            end,
            onSelect = function(data)
                local entity = type(data) == "table" and data.entity or data
                CreateThread(function()
                    local ok, err = pcall(Lift.RemoveJack, entity)
                    if not ok then
                        Busy = false
                        Anim.Cleanup()
                        print("[pls_mechanic] jack error: "..tostring(err))
                    end
                end)
            end,
        },
    })
end)

--[[
  _____       _
 |  __ \     (_)
 | |  | |_ __ ___   _____
 | |  | | '__| \ \ / / _ \
 | |__| | |  | |\ V /  __/
 |_____/|_|  |_| \_/ \___|
 Nobody drives a vehicle that is on a lift or a jack.
]]--

CreateThread(function()
    local warned = nil
    while true do
        local sleep = 1000
        local vehicle = cache.vehicle
        if vehicle and cache.seat == -1 then
            sleep = 500
            local state = Entity(vehicle).state
            if state.pls_lift or state.pls_jack then
                if warned ~= vehicle then
                    warned = vehicle
                    Core.Notify(locale("lift_cannot_drive"), "error")
                end
                -- controls are disabled per frame, state is re-checked every 500 ms
                local untilTime = GetGameTimer() + 500
                while cache.vehicle == vehicle and GetGameTimer() < untilTime do
                    DisableControlAction(0, 71, true)  -- accelerate
                    DisableControlAction(0, 72, true)  -- brake / reverse
                    DisableControlAction(0, 59, true)  -- steer
                    DisableControlAction(0, 76, true)  -- handbrake
                    Wait(0)
                end
                sleep = 0
            else
                warned = nil
            end
        else
            warned = nil
        end
        Wait(sleep)
    end
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

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, lift in pairs(Lifts) do
        deleteLiftProp(lift)
        local vehicle = getLiftVehicle(lift)
        if vehicle then dropVehicle(vehicle, lift.base) end
    end
    for vehicle in pairs(JackStates) do
        deleteJackProp(vehicle)
        if DoesEntityExist(vehicle) and isOwner(vehicle) then
            FreezeEntityPosition(vehicle, false)
            SetVehicleOnGroundProperly(vehicle)
        end
    end
    if RemoveJackTarget then
        BRIDGE.RemoveGlobalVehicleTarget(RemoveJackTarget)
    end
end)
