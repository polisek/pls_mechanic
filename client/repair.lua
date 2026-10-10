--[[
  _____                  _
 |  __ \                (_)
 | |__) |___ _ __   __ _ _ _ __
 |  _  // _ \ '_ \ / _` | | '__|
 | | \ \  __/ |_) | (_| | | |
 |_|  \_\___| .__/ \__,_|_|_|
            | |
            |_|
 Repair workflow (NUI overlay "workflow"), body repair technique, quick repairs and repair kits.
 Every step: client pre-check -> server "begin" (validation + timer) -> repair scene (Config.Animations.Scenes,
 walking, props, phases) -> server "step" -> natives -> test run -> old parts picked up.
 Parts fetching (Config.Fetch, client/fetch.lua): a step without its parts / tools pauses ("waiting"), the mechanic
 brings them from the workshop storage and continues via the "Continue repair" target on the vehicle.
 Workflow, quick repairs and kits run as one session with the same overlay, cancel key and cancel target.
]]--

Repair = {}

local TANK_DAMAGE = 700.0             -- petrol tank health below = fuel tank damaged
local BODY_DAMAGE = 950.0             -- body health below = bodywork damaged
local DEFORMATION_DAMAGE = 0.05       -- sampled deformation (m) above = bodywork damaged
local DEFORMATION_SAMPLE = 0.02       -- smaller deformation points are not re-applied
local WORK_DISTANCE = 15.0            -- max distance from vehicle during workflow
local REACH_DISTANCE = 2.5            -- work spot farther than this = can't reach it
local FETCH_DURATION = 1500           -- ms, taking a part from the toolbox

local AnimConfig = Config.Animations or {}
local AnimSettings = AnimConfig.Settings or {}
local OVERHEAD_HEIGHT = AnimSettings.overheadHeight or 1.6

local Workflow = nil
local RepairedBody = {}               -- [netId] = { [bodyKey] = true } during workflow
local CancelTarget = nil
local EngineTestVehicle = nil         -- vehicle with engine started for a test run

local DoorBones = { [0] = "door_dside_f", [1] = "door_pside_f", [2] = "door_dside_r", [3] = "door_pside_r", [4] = "bonnet", [5] = "boot" } -- GTA door index: 0 FL, 1 FR, 2 RL, 3 RR
local WindowBones = { [0] = "window_lf", [1] = "window_rf", [2] = "window_lr", [3] = "window_rr", [4] = "window_lm", [5] = "window_rm", [6] = "windscreen", [7] = "windscreen_r" }
local WindowDoor = { [0] = 0, [1] = 1, [2] = 2, [3] = 3 }   -- side window -> door that holds it
local BumperBones = { front = "bumper_f", rear = "bumper_r" }
local HeadlightBones = { left = "headlight_l", right = "headlight_r" }
local SideWheel = { lf = 0, rf = 1, lr = 4, rr = 5 }
local WheelRing = { 0, 2, 4, 5, 3, 1 }  -- wheels in the order around the vehicle
local DoorByName = { hood = 4, trunk = 5, driver = 0 }
local UnderY = { under = 0.0, under_front = 0.45, under_rear = -0.45 }
local AccessAnim = { hood = "hood", trunk = "hood", under = "under", wheel = "kneel" }

local DoorPositions = { [0] = "repair_pos_front_left", [1] = "repair_pos_front_right", [2] = "repair_pos_rear_left", [3] = "repair_pos_rear_right" }
local WindowPositions = {
    [0] = "repair_pos_front_left", [1] = "repair_pos_front_right", [2] = "repair_pos_rear_left", [3] = "repair_pos_rear_right",
    [4] = "repair_pos_middle_left", [5] = "repair_pos_middle_right", [6] = "repair_pos_windscreen", [7] = "repair_pos_rear_windscreen",
}
local WheelPositions = {
    [0] = "repair_pos_front_left", [1] = "repair_pos_front_right", [2] = "repair_pos_middle_left",
    [3] = "repair_pos_middle_right", [4] = "repair_pos_rear_left", [5] = "repair_pos_rear_right",
}
local NamedPositions = { front = "repair_pos_front", rear = "repair_pos_rear", left = "repair_pos_left", right = "repair_pos_right" }

-- Workflow order: fluids and filters first, then parts by access (hood -> under -> wheels), bodywork last
local AccessRank = { hood = 1, trunk = 2, under = 3, wheel = 4 }
local ServiceOrder = { oil = 1, coolant = 2, brake_fluid = 3, ev_coolant = 4, transmission_fluid = 5, air_filter = 6, fuel_filter = 7, spark_plugs = 8, timing_belt = 9, brake_pads = 10, tyres = 11 }
local CoreOrder = { battery = 1, alternator = 2, radiator = 3, turbo = 4, engine = 5, fuel_pump = 6, transmission = 7, clutch = 8, ev_battery = 9, ev_motor = 10, brakes = 11, suspension = 12, alignment = 13 }
local BodyOrder = { door = 1, hood = 2, trunk = 3, window = 4, headlight = 5, wheel = 6, tyre = 7, fuel_tank = 8, bumper = 9 }

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

local function hasBone(vehicle, boneName)
    return boneName ~= nil and GetEntityBoneIndexByName(vehicle, boneName) ~= -1
end

local function permissionReason()
    -- illegal workshops have no duty, the crew only lacks the permission
    local shopId = Core.GetMyShopId()
    if shopId and Core.IsIllegalShop and Core.IsIllegalShop(shopId) then
        return locale("no_permission")
    end
    if Config.RequireDuty and not Core.IsOnDuty() then
        return locale("not_on_duty")
    end
    return locale("no_permission")
end

local function missingItemsText(list)
    local parts = {}
    for _, v in ipairs(list or {}) do
        if v.have < v.count then
            parts[#parts + 1] = ("%dx %s"):format(v.count - v.have, v.label)
        end
    end
    return table.concat(parts, ", ")
end

local function playSound(name, set)
    PlaySoundFrontend(-1, name, set, true)
end

local function getNetId(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then return nil end
    return VehToNet(vehicle)
end

local function isValidBodyKey(bodyKind, index)
    if not bodyKind or not Config.BodyParts[bodyKind] then return false end
    if bodyKind == "door" then
        return math.type(index) == "integer" and index >= 0 and index <= 3
    elseif bodyKind == "window" then
        return math.type(index) == "integer" and index >= 0 and index <= 7
    elseif bodyKind == "tyre" or bodyKind == "wheel" then
        return math.type(index) == "integer" and index >= 0 and index <= 5
    elseif bodyKind == "bumper" then
        return index == "front" or index == "rear"
    elseif bodyKind == "headlight" then
        return index == "left" or index == "right"
    end
    return index == nil
end

-- Where the mechanic stands for body part
local function getBodyAccess(bodyKind, index)
    if bodyKind == "door" then
        return index % 2 == 0 and "left" or "right"   -- 0 FL, 2 RL = left / 1 FR, 3 RR = right
    elseif bodyKind == "window" then
        if index == 6 then return "hood" end
        if index == 7 then return "trunk" end
        return index % 2 == 0 and "left" or "right"
    elseif bodyKind == "hood" or bodyKind == "headlight" then
        return "hood"
    elseif bodyKind == "trunk" then
        return "trunk"
    elseif bodyKind == "bumper" then
        return index == "front" and "hood" or "trunk"
    elseif bodyKind == "tyre" or bodyKind == "wheel" then
        return "wheel"
    elseif bodyKind == "fuel_tank" then
        return "under"
    end
    return "left"
end

-- Wheel array index (CFX wheel natives, 0..count-1) for tyre index (tyre natives / bones, 0..5)
local function getWheelArrayIndex(vehicle, tyreIndex)
    local count = GetVehicleNumberOfWheels(vehicle)
    if count == 2 then
        return ({ [0] = 0, [4] = 1 })[tyreIndex]
    elseif count == 4 then
        return ({ [0] = 0, [1] = 1, [4] = 2, [5] = 3 })[tyreIndex]
    end
    if tyreIndex < count then return tyreIndex end
    return nil
end

local function isWheelMissing(vehicle, tyreIndex)
    if not IsVehicleWheelBrokenOff then return false end
    local arrayIndex = getWheelArrayIndex(vehicle, tyreIndex)
    return arrayIndex ~= nil and IsVehicleWheelBrokenOff(vehicle, arrayIndex) and true or false
end

-- Another module keeps the player busy (tuning / diagnostics / running animation phase / scene of the illegal DLC)
local function isPlayerBusy()
    if Tuning and ((Tuning.IsInstalling and Tuning.IsInstalling()) or (Tuning.IsOpen and Tuning.IsOpen())) then
        return true, locale("tuning_busy")
    end
    if (Diagnostics and Diagnostics.IsBusy and Diagnostics.IsBusy()) or Anim.IsBusy() or Core.IsExternalBusy() then
        return true, locale("repair_busy")
    end
    return false
end

-- Parts fetching (client/fetch.lua) loaded and enabled, the resource works without it
local function fetchEnabled()
    return Fetch ~= nil and Fetch.Enabled ~= nil and Fetch.Enabled() == true
end

-- Shop whose storage the parts come from: shop of the bay / lift the vehicle stands in (when the player may use it),
-- else duty / own shop (current illegal workshop of the crew)
local function getFetchShopId(vehicle)
    local duty = Core.GetDutyShopId()
    local current = Core.GetMyShopId()
    if vehicle and DoesEntityExist(vehicle) then
        local coords = GetEntityCoords(vehicle)
        local _, shop = Core.GetLiftAt(coords)
        if not shop then _, shop = Core.GetBayAt(coords) end
        if shop and shop.id == current then
            return shop.id
        end
        if shop and shop.kind ~= "illegal" and Core.IsMember(shop.id) and (not Config.RequireDuty or shop.id == duty) then
            return shop.id
        end
    end
    return duty or current
end

--[[
  _____        __                            _   _
 |  __ \      / _|                          | | (_)
 | |  | | ___| |_ ___  _ __ _ __ ___   __ _| |_ _  ___  _ __
 | |  | |/ _ \  _/ _ \| '__| '_ ` _ \ / _` | __| |/ _ \| '_ \
 | |__| |  __/ || (_) | |  | | | | | | (_| | |_| | (_) | | | |
 |_____/ \___|_| \___/|_|  |_| |_| |_|\__,_|\__|_|\___/|_| |_|
]]--

-- Grid of offsets around the model used to sample deformation
local function getDeformationOffsets(vehicle)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local x = (max.x - min.x) * 0.5
    local y = (max.y - min.y) * 0.5
    local z = (max.z - min.z) * 0.5
    local offsets = {}
    for _, fy in ipairs({ 1.0, 0.5, 0.0, -0.5, -1.0 }) do
        for _, fx in ipairs({ -1.0, 0.0, 1.0 }) do
            for _, fz in ipairs({ 0.0, 1.0 }) do
                -- centre points at mid height are inside the cabin
                if not (fx == 0.0 and fz == 0.0 and fy > -1.0 and fy < 1.0) then
                    offsets[#offsets + 1] = vector3(x * fx, y * fy, z * fz)
                end
            end
        end
    end
    return offsets
end

local function sampleDeformation(vehicle)
    local points = {}
    for _, offset in ipairs(getDeformationOffsets(vehicle)) do
        local value = #GetVehicleDeformationAtPos(vehicle, offset.x, offset.y, offset.z)
        if value > DEFORMATION_SAMPLE then
            points[#points + 1] = { offset = offset, value = value }
        end
    end
    return points
end

local function getMaxDeformation(vehicle)
    local maxValue = 0.0
    for _, point in ipairs(sampleDeformation(vehicle)) do
        if point.value > maxValue then maxValue = point.value end
    end
    return maxValue
end

-- Re-applies sampled deformation. Approximation: GTA has no setter for deformation, damage is applied
-- until every sampled point is deformed at least as much as before (max 5 iterations).
local function applyDeformation(vehicle, points)
    if #points == 0 then return end
    local handlingMult = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fDeformationDamageMult")
    local damageMult = 20.0
    if handlingMult <= 0.55 then
        damageMult = 1000.0
    elseif handlingMult <= 0.65 then
        damageMult = 400.0
    elseif handlingMult <= 0.75 then
        damageMult = 200.0
    end
    for _ = 1, 5 do
        local applied = false
        for _, point in ipairs(points) do
            local o = point.offset
            if #GetVehicleDeformationAtPos(vehicle, o.x, o.y, o.z) < point.value then
                SetVehicleDamage(vehicle, o.x * 2.0, o.y * 2.0, o.z * 2.0, point.value * handlingMult * damageMult, 1000.0, true)
                applied = true
            end
        end
        if not applied then break end
        Wait(100)
    end
end

--[[
  ____            _               _
 |  _ \          | |             | |
 | |_) | ___   __| |_   _    __ _| | ___
 |  _ < / _ \ / _` | | | |  / _` | |/ _ \
 | |_) | (_) | (_| | |_| | | (_| | |  __/
 |____/ \___/ \__,_|\__, |  \__,_|_|\___|
                     __/ |
                    |___/
]]--

-- Body part exists on this model (bones / electric vehicles without fuel tank)
local function bodyPartExists(vehicle, bodyKind, index)
    if bodyKind == "door" then return hasBone(vehicle, DoorBones[index]) end
    if bodyKind == "hood" then return hasBone(vehicle, DoorBones[4]) end
    if bodyKind == "trunk" then return hasBone(vehicle, DoorBones[5]) end
    if bodyKind == "window" then
        if not hasBone(vehicle, WindowBones[index]) then return false end
        -- rear windscreen is part of a lowered convertible roof
        if index == 7 and IsVehicleAConvertible(vehicle, false) and GetConvertibleRoofState(vehicle) ~= 0 then return false end
        return true
    end
    if bodyKind == "bumper" then return hasBone(vehicle, BumperBones[index]) end
    if bodyKind == "headlight" then return hasBone(vehicle, HeadlightBones[index]) end
    if bodyKind == "tyre" or bodyKind == "wheel" then return hasBone(vehicle, Utils.WheelBones[index]) end
    if bodyKind == "fuel_tank" then return not Utils.IsElectricModel(GetEntityModel(vehicle)) end
    return true
end

-- Body part is currently damaged (client natives)
function Repair.IsBodyDamaged(vehicle, key)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    local bodyKind, index = Utils.SplitBodyKey(key)
    if bodyKind == "door" then
        return IsVehicleDoorDamaged(vehicle, index)
    elseif bodyKind == "hood" then
        return IsVehicleDoorDamaged(vehicle, 4)
    elseif bodyKind == "trunk" then
        return IsVehicleDoorDamaged(vehicle, 5)
    elseif bodyKind == "window" then
        return not IsVehicleWindowIntact(vehicle, index)
    elseif bodyKind == "bumper" then
        local front = index == "front"
        return IsVehicleBumperBrokenOff(vehicle, front) or IsVehicleBumperBouncing(vehicle, front)
    elseif bodyKind == "headlight" then
        if index == "left" then return GetIsLeftVehicleHeadlightDamaged(vehicle) end
        return GetIsRightVehicleHeadlightDamaged(vehicle)
    elseif bodyKind == "tyre" then
        return IsVehicleTyreBurst(vehicle, index, false) and not isWheelMissing(vehicle, index)
    elseif bodyKind == "wheel" then
        return isWheelMissing(vehicle, index)
    elseif bodyKind == "fuel_tank" then
        return GetVehiclePetrolTankHealth(vehicle) < TANK_DAMAGE
    elseif bodyKind == "deformation" then
        return GetVehicleBodyHealth(vehicle) < BODY_DAMAGE or getMaxDeformation(vehicle) > DEFORMATION_DAMAGE
    end
    -- custom body kinds from config can't be detected, they are always offered
    return true
end

-- Returns list of damaged body keys ("door:0", "hood", "tyre:4", ...)
function Repair.GetBodyDamage(vehicle)
    local result = {}
    if not vehicle or not DoesEntityExist(vehicle) then return result end
    local candidates = {}
    for i = 0, 3 do candidates[#candidates + 1] = "door:"..i end
    candidates[#candidates + 1] = "hood"
    candidates[#candidates + 1] = "trunk"
    for i = 0, 7 do candidates[#candidates + 1] = "window:"..i end
    candidates[#candidates + 1] = "headlight:left"
    candidates[#candidates + 1] = "headlight:right"
    candidates[#candidates + 1] = "bumper:front"
    candidates[#candidates + 1] = "bumper:rear"
    for i = 0, 5 do candidates[#candidates + 1] = "wheel:"..i end
    for i = 0, 5 do candidates[#candidates + 1] = "tyre:"..i end
    candidates[#candidates + 1] = "fuel_tank"
    candidates[#candidates + 1] = "deformation"

    local brokenDoors = {}
    for _, key in ipairs(candidates) do
        local bodyKind, index = Utils.SplitBodyKey(key)
        if Config.BodyParts[bodyKind] and bodyPartExists(vehicle, bodyKind, index) then
            local skip = bodyKind == "window" and WindowDoor[index] ~= nil and brokenDoors[WindowDoor[index]]
            if not skip and Repair.IsBodyDamaged(vehicle, key) then
                result[#result + 1] = key
                if bodyKind == "door" then brokenDoors[index] = true end
            end
        end
    end
    return result
end

-- body_panel count for bodywork by body health (Config.BodyParts.deformation.severity)
function Repair.GetDeformationCount(bodyHealth)
    local count = 1
    local part = Config.BodyParts.deformation
    for _, severity in ipairs(part and part.severity or {}) do
        if bodyHealth <= severity.maxBodyHealth and severity.count > count then
            count = severity.count
        end
    end
    return count
end

function Repair.GetStepLabel(kind, key)
    if kind == "service" then
        local part = Config.ServiceParts[key]
        return part and part.label or tostring(key)
    elseif kind == "core" then
        local part = Config.CoreParts[key]
        return part and part.label or tostring(key)
    elseif kind == "kit" then
        return Core.GetItemLabel(Utils.Item(key))
    end
    local bodyKind, index = Utils.SplitBodyKey(key)
    local part = Config.BodyParts[bodyKind]
    if not part then return tostring(key) end
    local position = nil
    if bodyKind == "door" then
        position = DoorPositions[index]
    elseif bodyKind == "window" then
        position = WindowPositions[index]
    elseif bodyKind == "tyre" or bodyKind == "wheel" then
        position = WheelPositions[index]
    elseif bodyKind == "bumper" or bodyKind == "headlight" then
        position = NamedPositions[index]
    end
    if position then
        return ("%s (%s)"):format(part.label, locale(position))
    end
    return part.label
end

-- Step definition for kind ("service" / "core" / "body" / "kit") and key. nil when invalid.
function Repair.ResolveStep(kind, key)
    if type(key) ~= "string" then return nil end
    if kind == "service" or kind == "core" then
        local part = (kind == "service" and Config.ServiceParts or Config.CoreParts)[key]
        if not part then return nil end
        return {
            kind = kind, key = key, part = part, label = part.label,
            perm = part.perm, location = part.location or "anywhere", access = part.access or "hood",
            duration = part.duration or 10000,
        }
    elseif kind == "body" then
        local bodyKind, index = Utils.SplitBodyKey(key)
        if not isValidBodyKey(bodyKind, index) then return nil end
        local part = Config.BodyParts[bodyKind]
        return {
            kind = kind, key = key, part = part, label = Repair.GetStepLabel(kind, key),
            perm = Config.BodyRepairPermission, location = part.location or "anywhere", access = getBodyAccess(bodyKind, index),
            duration = part.duration or 10000,
            bodyKind = bodyKind, index = index, wheel = (bodyKind == "tyre" or bodyKind == "wheel") and index or nil,
        }
    elseif kind == "kit" then
        local kit = Config.RepairKits[key]
        if not kit then return nil end
        return {
            kind = kind, key = key, part = kit, label = Repair.GetStepLabel(kind, key),
            location = "anywhere", access = "hood", duration = kit.duration or 10000,
        }
    end
    return nil
end

local function getStepRank(step)
    if step.kind == "body" then
        if step.bodyKind == "deformation" then return 90000 end
        local indexRank = type(step.index) == "number" and step.index or ((step.index == "front" or step.index == "left") and 0 or 1)
        return 50000 + (BodyOrder[step.bodyKind] or 50) * 10 + indexRank
    end
    local order = step.kind == "service" and ServiceOrder or CoreOrder
    return (AccessRank[step.access] or 5) * 1000 + (step.kind == "core" and 100 or 0) + (order[step.key] or 99)
end

--[[
  _   _       _   _
 | \ | |     | | (_)
 |  \| | __ _| |_ ___   _____  ___
 | . ` |/ _` | __| \ \ / / _ \/ __|
 | |\  | (_| | |_| |\ V /  __/\__ \
 |_| \_|\__,_|\__|_| \_/ \___||___/
]]--

local function getRepairedSet(vehicle)
    local netId = getNetId(vehicle)
    if Workflow and netId and Workflow.netId == netId then
        RepairedBody[netId] = RepairedBody[netId] or {}
        return RepairedBody[netId]
    end
    return {}
end

-- Snapshot of all native damage of vehicle
local function snapshotDamage(vehicle)
    local snap = {
        engine = GetVehicleEngineHealth(vehicle),
        body = GetVehicleBodyHealth(vehicle),
        tank = GetVehiclePetrolTankHealth(vehicle),
        dirt = GetVehicleDirtLevel(vehicle),
        fuel = GetVehicleFuelLevel(vehicle),
        doors = {}, open = {}, windows = {}, tyres = {}, wheels = {}, headlights = {},
        deformation = sampleDeformation(vehicle),
    }
    for i = 0, 5 do
        if hasBone(vehicle, DoorBones[i]) then
            if IsVehicleDoorDamaged(vehicle, i) then
                snap.doors[i] = true
            elseif GetVehicleDoorAngleRatio(vehicle, i) > 0.1 then
                snap.open[i] = true
            end
        end
    end
    for i = 0, 7 do
        if bodyPartExists(vehicle, "window", i) and not IsVehicleWindowIntact(vehicle, i) then
            snap.windows[i] = true
        end
    end
    for i = 0, 5 do
        if hasBone(vehicle, Utils.WheelBones[i]) then
            if isWheelMissing(vehicle, i) then
                snap.wheels[i] = getWheelArrayIndex(vehicle, i)
            elseif IsVehicleTyreBurst(vehicle, i, false) then
                snap.tyres[i] = IsVehicleTyreBurst(vehicle, i, true)
            end
        end
    end
    for side, bone in pairs(HeadlightBones) do
        if hasBone(vehicle, bone) and Repair.IsBodyDamaged(vehicle, "headlight:"..side) then
            snap.headlights[side] = true
        end
    end
    return snap
end

-- Headlights have no "break" native: small local damage at the lamp until it breaks (max 3 tries)
local function breakHeadlight(vehicle, side)
    local bone = GetEntityBoneIndexByName(vehicle, HeadlightBones[side])
    if bone == -1 then return end
    local world = GetWorldPositionOfEntityBone(vehicle, bone)
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
    for i = 1, 3 do
        if Repair.IsBodyDamaged(vehicle, "headlight:"..side) then return end
        SetVehicleDamage(vehicle, offset.x, offset.y, offset.z, 40.0 * i, 0.15, true)
        Wait(50)
    end
end

-- Re-applies damage from snapshot except parts in repaired set.
-- Limitations: bumpers can't be broken off by natives -> they get restored by any full body repair and are
-- effectively repaired together with the bodywork. Headlights are re-broken by small local damage (best effort).
local function restoreDamage(vehicle, snap, repaired)
    SetVehicleEngineHealth(vehicle, snap.engine + 0.0)
    if not repaired.fuel_tank then
        SetVehiclePetrolTankHealth(vehicle, snap.tank + 0.0)
    end
    if not repaired.deformation then
        applyDeformation(vehicle, snap.deformation)
        SetVehicleBodyHealth(vehicle, snap.body + 0.0)
    end
    for i in pairs(snap.doors) do
        local key = i == 4 and "hood" or i == 5 and "trunk" or "door:"..i
        if not repaired[key] then
            SetVehicleDoorBroken(vehicle, i, true)
        end
    end
    for i in pairs(snap.windows) do
        local door = WindowDoor[i]
        local doorGone = door ~= nil and snap.doors[door] and not repaired["door:"..door]
        if not repaired["window:"..i] and not doorGone then
            SmashVehicleWindow(vehicle, i)
        end
    end
    for i, onRim in pairs(snap.tyres) do
        if not repaired["tyre:"..i] then
            SetVehicleTyreBurst(vehicle, i, onRim, 1000.0)
        end
    end
    for i, arrayIndex in pairs(snap.wheels) do
        if not repaired["wheel:"..i] and BreakOffVehicleWheel then
            BreakOffVehicleWheel(vehicle, arrayIndex, false, true, true, false)
        end
    end
    for side in pairs(snap.headlights) do
        if not repaired["headlight:"..side] then
            breakHeadlight(vehicle, side)
        end
    end
    for i in pairs(snap.open) do
        SetVehicleDoorOpen(vehicle, i, false, true)
    end
    SetVehicleDirtLevel(vehicle, snap.dirt + 0.0)
    SetVehicleFuelLevel(vehicle, snap.fuel + 0.0)
end

-- GTA can't repair a single part: snapshot damage, SetVehicleFixed, re-apply everything not repaired yet.
-- Caller must have network control.
local function fullBodyRepair(vehicle, key, repaired)
    repaired[key] = true
    local snap = snapshotDamage(vehicle)
    -- SetVehicleFixed doesn't work on vehicle with broken engine
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleFixed(vehicle)
    if repaired.deformation then
        SetVehicleDeformationFixed(vehicle)
    end
    Wait(0)
    restoreDamage(vehicle, snap, repaired)
end

-- Applies natives after successful server step
local function applyStepNatives(vehicle, step)
    if step.kind == "core" then
        if step.key == "engine" or step.key == "ev_motor" then
            SetVehicleEngineHealth(vehicle, 1000.0)
            SetVehicleUndriveable(vehicle, false)
        end
        return
    end
    local repaired = getRepairedSet(vehicle)
    if step.kind == "service" then
        if step.key == "tyres" then
            for i = 0, 5 do
                if hasBone(vehicle, Utils.WheelBones[i]) and not isWheelMissing(vehicle, i) then
                    SetVehicleTyreFixed(vehicle, i)
                    repaired["tyre:"..i] = true
                end
            end
        end
        return
    end
    if step.bodyKind == "tyre" then
        SetVehicleTyreFixed(vehicle, step.index)
        repaired[step.key] = true
    elseif step.bodyKind == "fuel_tank" then
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        repaired[step.key] = true
    elseif step.bodyKind == "window" then
        repaired[step.key] = true
        FixVehicleWindow(vehicle, step.index)
        Wait(0)
        if not IsVehicleWindowIntact(vehicle, step.index) then
            fullBodyRepair(vehicle, step.key, repaired)
        end
    else
        fullBodyRepair(vehicle, step.key, repaired)
    end
end

-- "repair" (engine / body / core parts), "patch" (failed parts to critical), "clean"
local function getKitType(kit)
    if kit.failedToCritical then return "patch" end
    if kit.engineHealth or kit.bodyHealth or kit.corePartsMin then return "repair" end
    return "clean"
end

local function applyKitNatives(vehicle, kit)
    local kitType = getKitType(kit)
    if kitType == "clean" then
        SetVehicleDirtLevel(vehicle, 0.0)
        WashDecalsFromVehicle(vehicle, 1.0)
        return
    end
    if kitType == "patch" then
        local minimum = (Config.PartStates.critical + 1) * 10.0
        if GetVehicleEngineHealth(vehicle) < minimum then
            SetVehicleEngineHealth(vehicle, minimum)
        end
        SetVehicleUndriveable(vehicle, false)
        return
    end
    if kit.bodyHealth and kit.bodyHealth >= 1000 then
        local dirt, fuel = GetVehicleDirtLevel(vehicle), GetVehicleFuelLevel(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleDirtLevel(vehicle, dirt)
        SetVehicleFuelLevel(vehicle, fuel)
    elseif kit.bodyHealth and GetVehicleBodyHealth(vehicle) < kit.bodyHealth then
        SetVehicleBodyHealth(vehicle, kit.bodyHealth + 0.0)
    end
    if kit.engineHealth and GetVehicleEngineHealth(vehicle) < kit.engineHealth then
        SetVehicleEngineHealth(vehicle, kit.engineHealth + 0.0)
    end
    SetVehicleUndriveable(vehicle, false)
end

--[[
                                    _
     /\                            | |
    /  \   ___ ___ ___  ___ ___    | |
   / /\ \ / __/ __/ _ \/ __/ __|   | |
  / ____ \ (_| (_|  __/\__ \__ \   |_|
 /_/    \_\___\___\___||___/___/   (_)
]]--

-- Wheel used for service / core parts with "wheel" access: jacked wheel or closest one
local function getWorkWheel(vehicle)
    local jack = Core.GetJack(vehicle)
    if jack and SideWheel[jack.wheel] then return SideWheel[jack.wheel] end
    local pedCoords = GetEntityCoords(cache.ped)
    local best, bestDistance = 0, nil
    for i = 0, 5 do
        local bone = GetEntityBoneIndexByName(vehicle, Utils.WheelBones[i])
        if bone ~= -1 then
            local distance = #(pedCoords - GetWorldPositionOfEntityBone(vehicle, bone))
            if not bestDistance or distance < bestDistance then
                best, bestDistance = i, distance
            end
        end
    end
    return best
end

local function isOverhead(vehicle)
    return Core.IsVehicleOnLift(vehicle) and GetEntityHeightAboveGround(vehicle) > OVERHEAD_HEIGHT
end

local function facingHeading(vehicle, side)
    return GetEntityHeading(vehicle) + (side < 0 and -90.0 or 90.0)
end

-- Position at the side of the repaired door / window (or its default access)
local function getSidePosition(vehicle, step)
    local access = step.access
    if access ~= "left" and access ~= "right" then
        return Core.GetAccessPosition(vehicle, access)
    end
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local y = 0.0
    local boneName = step.bodyKind == "door" and DoorBones[step.index] or step.bodyKind == "window" and WindowBones[step.index] or nil
    local bone = boneName and GetEntityBoneIndexByName(vehicle, boneName) or -1
    if bone ~= -1 then
        local world = GetWorldPositionOfEntityBone(vehicle, bone)
        y = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z).y
    end
    local side = access == "left" and -1 or 1
    local x = side < 0 and (min.x - 0.6) or (max.x + 0.6)
    return GetOffsetFromEntityInWorldCoords(vehicle, x, y, 0.0), facingHeading(vehicle, side)
end

-- Work spot of a scene action. Returns coords, heading
local function getSpot(ctx, at)
    local vehicle, step = ctx.vehicle, ctx.step
    at = at or "access"
    if at == "access" then
        at = step.access
        if at == "left" or at == "right" then at = "side" end
    end
    if at == "hood" or at == "trunk" then
        return Core.GetAccessPosition(vehicle, at)
    end
    if at == "wheel" then
        return Core.GetAccessPosition(vehicle, "wheel", ctx.wheel or getWorkWheel(vehicle))
    end
    if at == "side" then
        return getSidePosition(vehicle, step)
    end
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    if at == "left" or at == "right" then
        local side = at == "left" and -1 or 1
        local x = side < 0 and (min.x - 0.6) or (max.x + 0.6)
        return GetOffsetFromEntityInWorldCoords(vehicle, x, 0.0, 0.0), facingHeading(vehicle, side)
    end
    local underY = UnderY[at]
    if underY then
        local y = underY >= 0 and max.y * underY or -min.y * underY
        if ctx.overhead then
            -- vehicle is high on the lift, mechanic stands under it
            local pos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, y, 0.0)
            return vector3(pos.x, pos.y, GetEntityCoords(cache.ped).z), GetEntityHeading(vehicle)
        end
        if not ctx.underSide then
            local pedCoords = GetEntityCoords(cache.ped)
            local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, pedCoords.x, pedCoords.y, pedCoords.z)
            ctx.underSide = offset.x < 0 and -1 or 1
        end
        local lie = AnimSettings.lie or {}
        local distance = lie.distance or 0.35
        local x = ctx.underSide < 0 and (min.x - distance) or (max.x + distance)
        return GetOffsetFromEntityInWorldCoords(vehicle, x, y, 0.0), facingHeading(vehicle, ctx.underSide) + (lie.heading or 180.0)
    end
    return Core.GetAccessPosition(vehicle, step.access or "hood", ctx.wheel)
end

--[[
   _____
  / ____|
 | (___   ___ ___ _ __   ___  ___
  \___ \ / __/ _ \ '_ \ / _ \/ __|
  ____) | (_|  __/ | | |  __/\__ \
 |_____/ \___\___|_| |_|\___||___/
 ctx = { workflow, vehicle, step, duration, overhead, wheel, underSide, phaseIndex, phaseCount, cancel }
]]--

local function markCancelled(workflow)
    if not workflow.cancelled then
        workflow.cancelled = true
        workflow.cancelledAt = GetGameTimer()
    end
end

-- Session is cancelled (key / target) or can't continue (vehicle gone, player dead or too far).
-- While waiting for parts the mechanic walks to the storage, Fetch checks the vehicle and its own distance limit.
local function isCancelled(workflow)
    if workflow.cancelled then return true end
    local vehicle = workflow.vehicle
    local lost = IsEntityDead(cache.ped)
    if not lost and not workflow.waiting then
        lost = not DoesEntityExist(vehicle) or #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > WORK_DISTANCE
    end
    if lost then
        markCancelled(workflow)
        workflow.fast = true
        return true
    end
    return false
end

local function getScene(step)
    local scenes = AnimConfig.Scenes or {}
    local scene = scenes[step.kind..":"..step.key]
    if not scene and step.bodyKind then
        scene = scenes["body:"..step.bodyKind]
    end
    if not scene then
        local access = (step.access == "left" or step.access == "right") and "side" or step.access
        scene = scenes["default:"..tostring(access)] or scenes["default:hood"]
    end
    return scene or {}
end

local function getSceneWheels(ctx, mode)
    local vehicle = ctx.vehicle
    if mode == "step" then return { ctx.step.wheel or getWorkWheel(vehicle) } end
    if mode == "work" then return { getWorkWheel(vehicle) } end
    local jack = not Core.IsVehicleOnLift(vehicle) and Core.GetJack(vehicle) or nil
    local jacked = jack and SideWheel[jack.wheel] or nil
    if mode == "axle" then
        if jacked then return { jacked } end
        local list = {}
        for _, i in ipairs({ 0, 1 }) do
            if hasBone(vehicle, Utils.WheelBones[i]) and not isWheelMissing(vehicle, i) then list[#list + 1] = i end
        end
        return #list > 0 and list or { getWorkWheel(vehicle) }
    end
    if mode == "all" then
        -- around the vehicle, starting at the closest wheel
        local list = {}
        for _, i in ipairs(WheelRing) do
            if hasBone(vehicle, Utils.WheelBones[i]) and not isWheelMissing(vehicle, i) then list[#list + 1] = i end
        end
        local first = getWorkWheel(vehicle)
        for position, i in ipairs(list) do
            if i == first then
                local ordered = {}
                for n = 0, #list - 1 do ordered[#ordered + 1] = list[(position - 1 + n) % #list + 1] end
                return ordered
            end
        end
        return #list > 0 and list or { getWorkWheel(vehicle) }
    end
    return { false }
end

-- Anim key of a phase after the overhead replacement
local function getPhaseAnim(ctx, action)
    local key = action.anim
    if ctx.overhead and type(key) == "string" and AnimConfig.Overhead and AnimConfig.Overhead[key] then
        return AnimConfig.Overhead[key]
    end
    return key
end

local function getAnimPose(key)
    local anim = type(key) == "string" and AnimConfig.Anims and AnimConfig.Anims[key] or nil
    return anim and anim.pose or nil
end

-- Expands the scene into action lists and splits the step duration between weighted phases
local function buildPlan(ctx)
    local scene = getScene(ctx.step)
    local wheels = getSceneWheels(ctx, scene.wheels)
    local pre, post = {}, {}
    for _, wheel in ipairs(wheels) do
        for _, action in ipairs(scene.actions or {}) do
            if type(action) == "table" then
                pre[#pre + 1] = { action = action, wheel = wheel or nil }
            end
        end
    end
    for _, action in ipairs(scene.after or {}) do
        if type(action) == "table" and (not action.engine or AnimSettings.engineTest ~= false) then
            post[#post + 1] = { action = action, wheel = wheels[#wheels] or nil }
        end
    end

    local total = 0
    for _, entry in ipairs(pre) do
        if entry.action[1] == "phase" and not entry.action.duration then
            total = total + (tonumber(entry.action.weight) or 1)
        end
    end
    if total == 0 then
        pre[#pre + 1] = {
            action = { "phase", label = "repair_phase_install", weight = 1, at = "access", anim = AccessAnim[ctx.step.access] or "side", prop = "wrench" },
            wheel = ctx.step.wheel,
        }
        total = 1
    end
    local count = 0
    for _, list in ipairs({ pre, post }) do
        for _, entry in ipairs(list) do
            local kind, action = entry.action[1], entry.action
            if kind == "phase" then
                if action.duration then
                    entry.duration = action.duration
                else
                    entry.duration = math.ceil(ctx.duration * (tonumber(action.weight) or 1) / total)
                end
                count = count + 1
            elseif kind == "fetch" and ctx.workflow.toolbox then
                count = count + 1
            end
        end
    end
    ctx.phaseCount = count
    return pre, post
end

local function setPhase(ctx, label, duration)
    ctx.phaseIndex = ctx.phaseIndex + 1
    local workflow = ctx.workflow
    workflow.phase = { label = label, index = ctx.phaseIndex, count = math.max(ctx.phaseCount, ctx.phaseIndex), duration = duration }
    if Workflow == workflow then
        Core.Nui.Update("workflow", Repair.GetOverlayData())
    end
end

-- Walks to the spot. Returns ok, reason locale key
local function goTo(ctx, at)
    local coords, heading = getSpot(ctx, at)
    if not coords then return true end
    Anim.WalkAround(ctx.vehicle, coords, heading, AnimSettings.walkTimeout, ctx.cancel)
    if ctx.cancel() then return false end
    if #(GetEntityCoords(cache.ped).xy - coords.xy) > REACH_DISTANCE then
        return false, "repair_cannot_reach"
    end
    return true
end

-- Old part / drain pan spot on the ground next to the mechanic, out of the way
local function getDropSpot(ctx)
    local vehicle = ctx.vehicle
    local pos = GetEntityCoords(cache.ped)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, pos.x, pos.y, pos.z)
    local cx = math.max(min.x, math.min(max.x, offset.x))
    local cy = math.max(min.y, math.min(max.y, offset.y))
    local dx, dy = offset.x - cx, offset.y - cy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.05 then
        -- under a lifted vehicle: next to it on the closer side
        local x = offset.x < 0 and (min.x - 0.9) or (max.x + 0.9)
        return GetOffsetFromEntityInWorldCoords(vehicle, x, offset.y, 0.0)
    end
    dx, dy = dx / length, dy / length
    return GetOffsetFromEntityInWorldCoords(vehicle, offset.x + dx * 0.7 + dy * 0.35, offset.y + dy * 0.7 - dx * 0.35, 0.0)
end

local function trackGround(ctx, object, wheel)
    if object then
        ctx.workflow.ground[#ctx.workflow.ground + 1] = { object = object, wheel = wheel, step = ctx.step }
    end
end

-- Picks up props of the step left on the ground (wheel = only props of that wheel)
local function collectGround(ctx, wheel, animate)
    local ground = ctx.workflow.ground
    for i = #ground, 1, -1 do
        local entry = ground[i]
        if entry.step == ctx.step and (wheel == nil or entry.wheel == wheel) then
            table.remove(ground, i)
            if animate and not ctx.cancel() then
                Anim.PickUp(entry.object)
            else
                Anim.DeleteProp(entry.object)
            end
        end
    end
end

-- Test run: engine started by the mechanic (not when somebody sits in the driver seat). Returns true when started.
local function startEngineTest(vehicle)
    if not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= 0 or GetIsVehicleEngineRunning(vehicle) then return false end
    if not Core.RequestControl(vehicle, 1000) then return false end
    SetVehicleEngineOn(vehicle, true, false, false)
    EngineTestVehicle = vehicle
    return true
end

local function stopEngineTest(vehicle, started)
    if EngineTestVehicle == vehicle then EngineTestVehicle = nil end
    if not started or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= 0 then return end
    if Core.RequestControl(vehicle, 1000) then
        SetVehicleEngineOn(vehicle, false, false, false)
    end
end

--[[ Scene actions: function(ctx, entry, nextEntry) -> ok, reason ]]--

local Actions = {}

function Actions.open(ctx, entry)
    local vehicle, door = ctx.vehicle, DoorByName[entry.action.door]
    if not door or not hasBone(vehicle, DoorBones[door]) or IsVehicleDoorDamaged(vehicle, door) then return true end
    if GetVehicleDoorAngleRatio(vehicle, door) > 0.1 then return true end
    if not ctx.overhead then
        local ok, reason = goTo(ctx, door == 4 and "hood" or door == 5 and "trunk" or "side")
        if not ok then return false, reason end
    end
    if Anim.OpenDoor(vehicle, door) then
        ctx.workflow.opened[door] = true
    end
    return true
end

function Actions.walk(ctx, entry)
    return goTo(ctx, entry.action.at)
end

function Actions.phase(ctx, entry, nextEntry)
    local action = entry.action
    if not entry.continued then
        local ok, reason = goTo(ctx, action.at)
        if not ok then return false, reason end
    end
    local anim = getPhaseAnim(ctx, action)
    -- following phase at the same spot with the same anim / pose / prop: keep them (no stand up / flicker)
    local keepAnim, keepProp = false, false
    if nextEntry and nextEntry.action[1] == "phase" and (nextEntry.action.at or "access") == (action.at or "access") and nextEntry.wheel == entry.wheel then
        local nextAnim = getPhaseAnim(ctx, nextEntry.action)
        local pose = getAnimPose(anim)
        keepAnim = anim ~= nil and (anim == nextAnim or (pose ~= nil and pose == getAnimPose(nextAnim)))
        keepProp = action.prop ~= nil and action.prop == nextEntry.action.prop
        nextEntry.continued = keepAnim
    end
    local vehicle = ctx.vehicle
    local label = locale(action.label or "repair_phase_install")
    local engineState = nil
    local done = Anim.Phase({
        label = label,
        duration = entry.duration,
        anim = anim,
        prop = action.prop,
        prop2 = action.prop2,
        sound = action.sound,
        particle = action.particle,
        vehicle = vehicle,
        noCollision = vehicle,
        keepAnim = keepAnim,
        keepProp = keepProp,
        cancel = ctx.cancel,
        onStart = function()
            setPhase(ctx, label, entry.duration)
            if action.engine then engineState = startEngineTest(vehicle) end
        end,
        onEnd = function()
            if action.engine then stopEngineTest(vehicle, engineState) end
        end,
    })
    if not done then
        -- progress cancelled by its own key counts as cancel of the session
        markCancelled(ctx.workflow)
        return false
    end
    return true
end

function Actions.remove(ctx, entry)
    local at = entry.action.at
    local ok, reason = goTo(ctx, at)
    if not ok then return false, reason end
    -- parts low at the wheel / under the vehicle are lifted from the ground first
    local spot = (at == nil or at == "access") and ctx.step.access or at
    if (spot == "wheel" or UnderY[spot]) and not ctx.overhead and not Anim.Play("pickup") then return false end
    if not Anim.Carry(entry.action.prop) then return true end
    local drop = getDropSpot(ctx)
    local object = Anim.PutDown(nil, drop, math.random(0, 359) + 0.0)
    trackGround(ctx, object, entry.wheel)
    return not ctx.cancel()
end

function Actions.fetch(ctx, entry)
    local toolbox = ctx.workflow.toolbox
    if toolbox and DoesEntityExist(toolbox) then
        local vehicle = ctx.vehicle
        local target = GetEntityCoords(toolbox)
        local center = GetEntityCoords(vehicle)
        local dir = target.xy - center.xy
        dir = #dir > 0.01 and dir / #dir or vector2(1.0, 0.0)
        local stand = vector3(target.x + dir.x * 0.7, target.y + dir.y * 0.7, GetEntityCoords(cache.ped).z)
        local heading = GetHeadingFromVector_2d(target.x - stand.x, target.y - stand.y)
        Anim.WalkAround(vehicle, stand, heading, AnimSettings.walkTimeout, ctx.cancel)
        if ctx.cancel() then return false end
        local label = locale("repair_phase_fetch")
        local done = Anim.Phase({
            label = label,
            duration = FETCH_DURATION,
            anim = "kneel_low",
            cancel = ctx.cancel,
            onStart = function() setPhase(ctx, label, FETCH_DURATION) end,
        })
        if not done then
            markCancelled(ctx.workflow)
            return false
        end
    elseif entry.action.prop then
        -- part from the inventory, picked up where he stands
        if not Anim.Play("pickup") then return false end
    end
    if entry.action.prop then
        Anim.Carry(entry.action.prop)
    end
    return not ctx.cancel()
end

function Actions.place(ctx, entry)
    local action = entry.action
    local ok, reason = goTo(ctx, action.at)
    if not ok then return false, reason end
    local vehicle = ctx.vehicle
    local coords, heading = getSpot(ctx, action.at)
    local target
    if UnderY[action.at or ""] and not ctx.overhead then
        -- slid under the vehicle from the side
        local min, max = GetModelDimensions(GetEntityModel(vehicle))
        local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, coords.x, coords.y, coords.z)
        target = GetOffsetFromEntityInWorldCoords(vehicle, offset.x < 0 and min.x * 0.4 or max.x * 0.4, offset.y, 0.0)
    else
        local rad = math.rad(heading or GetEntityHeading(cache.ped))
        target = coords + vector3(-math.sin(rad) * 0.6, math.cos(rad) * 0.6, 0.0)
    end
    local object = Anim.PutDown(action.prop, target, GetEntityHeading(vehicle))
    trackGround(ctx, object, entry.wheel)
    return not ctx.cancel()
end

function Actions.collect(ctx, entry)
    collectGround(ctx, entry.wheel, true)
    return not ctx.cancel()
end

local function runActions(ctx, list)
    for i, entry in ipairs(list) do
        if ctx.cancel() then return false end
        ctx.wheel = entry.wheel
        local handler = Actions[entry.action[1]]
        if handler then
            local ok, reason = handler(ctx, entry, list[i + 1])
            if not ok then return false, reason end
        end
    end
    return true
end

--[[
   _____ _
  / ____| |
 | (___ | |_ ___ _ __
  \___ \| __/ _ \ '_ \
  ____) | ||  __/ |_) |
 |_____/ \__\___| .__/
                | |
                |_|
 Returns status ("done" / "failed" / "skipped" / "cancelled"), message
]]--

local FetchReasons = { cancelled = "cancelled", no_vehicle = "no_vehicle", error = "repair_failed" }   -- other results: "fetch_<result>"

local function updateStepOverlay(workflow)
    if Workflow == workflow then
        Core.Nui.Update("workflow", Repair.GetOverlayData())
    end
end

-- Client pre-check. Returns ready, reason, status (nil = "failed"), parts
-- parts = { items (multiplied), tools, itemsOk } when only parts / tools are missing in the inventory (can be fetched)
local function checkStep(workflow, step)
    local vehicle = workflow.vehicle
    if step.kind == "kit" then
        -- the kit item itself is used, it is never waited for
        if Core.CountTool(step.key) < 1 then
            return false, locale("missing_items", Core.GetItemLabel(Utils.Item(step.key)))
        end
        return true
    end
    if step.kind == "body" and not Repair.IsBodyDamaged(vehicle, step.key) then return false, locale("repair_not_damaged"), "skipped" end
    if not Core.HasPermission(step.perm) then return false, permissionReason() end
    local location = step.location
    local quick = step.quick and Config.QuickRepairs[step.quick]
    if quick and quick.requireJack == false then location = "anywhere" end
    local locationOk, reason = Core.CheckLocation(vehicle, location, step.wheel)
    if not locationOk then return false, locale(reason or "location_bay") end
    local multiplier = step.bodyKind == "deformation" and Repair.GetDeformationCount(GetVehicleBodyHealth(vehicle)) or 1
    local hasTools, missingTool = Core.HasTools(step.part.tools)
    local hasItems, list = Core.CheckItems(step.part.items, multiplier)
    if hasTools and hasItems then return true end
    local items = {}
    for _, v in ipairs(step.part.items or {}) do
        items[#items + 1] = { item = v.item, count = v.count * multiplier }
    end
    local parts = { items = items, tools = step.part.tools or {}, itemsOk = hasItems }
    if not hasTools then return false, locale("missing_tool", Core.GetItemLabel(Utils.Item(missingTool))), nil, parts end
    return false, locale("missing_items", missingItemsText(list)), nil, parts
end

-- Missing parts / tools can be fetched (Config.Fetch). Quick repair uses its own item, it only waits for tools.
local function canFetch(workflow, parts)
    if not parts or not fetchEnabled() then return false end
    if workflow.mode == "quick" and not parts.itemsOk then return false end
    return #Fetch.Missing(parts.items, parts.tools) > 0
end

-- Pauses the step until its parts / tools are in the inventory and the mechanic used "Continue repair" on the vehicle.
-- Returns "ready" or why the workflow can't continue ("cancelled" / "timeout" / "too_far" / "no_vehicle" / "error")
local function waitForParts(workflow, step, parts)
    step.status = "waiting"
    updateStepOverlay(workflow)
    workflow.waiting = true
    local ok, result = pcall(Fetch.Wait, {
        owner = "repair",
        vehicle = workflow.vehicle,
        netId = workflow.netId,
        shopId = getFetchShopId(workflow.vehicle),
        label = step.label,
        items = parts.items,
        tools = parts.tools,
        isCancelled = function() return isCancelled(workflow) end,
        onUpdate = function() updateStepOverlay(workflow) end,
    })
    workflow.waiting = false
    if not ok then
        print("[pls_mechanic] repair fetch error: "..tostring(result))
        result = "error"
    end
    if result == "ready" then
        step.status = "active"
        updateStepOverlay(workflow)
    end
    return result
end

local function performStep(workflow, step)
    local vehicle, netId, kind, key = workflow.vehicle, workflow.netId, step.kind, step.key
    if not DoesEntityExist(vehicle) then return "failed", locale("no_vehicle") end
    if #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > WORK_DISTANCE then return "failed", locale("too_far") end

    -- client pre-check (server validates again), missing parts / tools pause the step until they are brought
    while true do
        local ready, reason, status, parts = checkStep(workflow, step)
        if ready then break end
        if not canFetch(workflow, parts) then return status or "failed", reason end
        local result = waitForParts(workflow, step, parts)
        if result ~= "ready" then
            -- the whole session ends, remaining steps are skipped
            markCancelled(workflow)
            local message = locale(FetchReasons[result] or ("fetch_"..tostring(result)))
            if result ~= "cancelled" then
                -- far from the vehicle / vehicle gone: toolbox is removed without walking back
                if result == "too_far" or result == "no_vehicle" then workflow.fast = true end
                Core.Notify(message, "error")
            end
            return "cancelled", message
        end
        -- back at the vehicle ("Continue repair" target), the scene walks to its work spot. Checked again (loop).
        if not DoesEntityExist(vehicle) then return "failed", locale("no_vehicle") end
        if #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > WORK_DISTANCE then return "failed", locale("too_far") end
    end

    local begin = lib.callback.await("pls_mechanic:server:repair:begin", false, netId, kind, key, step.quick)
    if not begin or not begin.ok then return "failed", begin and begin.message or locale("repair_failed") end

    local ctx = {
        workflow = workflow, vehicle = vehicle, step = step, duration = step.duration,
        overhead = isOverhead(vehicle), phaseIndex = 0, phaseCount = 0,
        cancel = function() return isCancelled(workflow) end,
    }
    local pre, post = buildPlan(ctx)
    local ok, failReason = runActions(ctx, pre)
    Anim.StopCarry()
    if not ok then
        collectGround(ctx, nil, false)
        if ctx.cancel() then return "cancelled", locale("cancelled") end
        return "failed", locale(failReason or "repair_failed")
    end

    -- natives need control, take it before items are consumed
    local needsNatives = kind == "body" or kind == "kit" or (kind == "core" and (key == "engine" or key == "ev_motor")) or (kind == "service" and key == "tyres")
    if needsNatives and not Core.RequestControl(vehicle, 3000) then
        collectGround(ctx, nil, false)
        return "failed", locale("no_control")
    end

    local result
    if kind == "kit" then
        result = lib.callback.await("pls_mechanic:server:repair:kit", false, netId, key)
    else
        result = lib.callback.await("pls_mechanic:server:repair:step", false, netId, kind, key, step.quick)
    end
    if not result or not result.ok then
        collectGround(ctx, nil, not isCancelled(workflow))
        return "failed", result and result.message or locale("repair_failed")
    end
    if needsNatives and DoesEntityExist(vehicle) then
        if kind == "kit" then
            applyKitNatives(vehicle, step.part)
        else
            applyStepNatives(vehicle, step)
        end
    end

    -- test run, old parts back to the toolbox (the step is done even when this part is cancelled)
    workflow.phase = nil
    runActions(ctx, post)
    Anim.StopCarry()
    collectGround(ctx, nil, not isCancelled(workflow))
    return "done", result.message
end

--[[
 __          __        _     __ _
 \ \        / /       | |   / _| |
  \ \  /\  / /__  _ __| | _| |_| | _____      __
   \ \/  \/ / _ \| '__| |/ /  _| |/ _ \ \ /\ / /
    \  /\  / (_) | |  |   <| | | | (_) \ V  V /
     \/  \/ \___/|_|  |_|\_\_| |_|\___/ \_/\_/
]]--

local CancelKeybind = lib.addKeybind({
    name = "pls_mechanic_cancel_workflow",
    description = locale("repair_keybind_cancel"),
    defaultKey = Config.Keys.cancel,
    disabled = true,
    onPressed = function()
        Repair.Cancel()
    end,
})

local function getCancelKey()
    local ok, key = pcall(function() return CancelKeybind:getCurrentKey() end)
    if ok and type(key) == "string" and key ~= "" then return key end
    return Config.Keys.cancel
end

-- Overlay data (NUI view "workflow"), phase only for the active step, waiting = parts to fetch (nil = not waiting)
function Repair.GetOverlayData()
    local workflow = Workflow
    if not workflow then return nil end
    local steps = {}
    for i, step in ipairs(workflow.steps) do
        steps[i] = {
            id = i, kind = step.kind, key = step.key, label = step.label, status = step.status, message = step.message,
            phase = (i == workflow.current and step.status == "active") and workflow.phase or nil,
        }
    end
    return {
        mode = "repair",
        plate = workflow.plate,
        cancelKey = getCancelKey(),
        cancelHint = locale("repair_cancel_hint"),
        current = workflow.current,
        steps = steps,
        waiting = fetchEnabled() and Fetch.IsWaiting("repair") and Fetch.GetOverlay() or nil,
    }
end

local function updateOverlay()
    if Workflow then
        Core.Nui.Update("workflow", Repair.GetOverlayData())
    end
end

-- Validates, deduplicates and orders steps from diagnostics
local function normalizeSteps(steps)
    local result, seen = {}, {}
    local serviceTyres = false
    for _, s in ipairs(steps or {}) do
        if type(s) == "table" and s.kind == "service" and s.key == "tyres" then serviceTyres = true end
    end
    for _, s in ipairs(steps or {}) do
        if type(s) == "table" and s.kind ~= "kit" then
            local step = Repair.ResolveStep(s.kind, s.key)
            local id = step and (step.kind..":"..step.key)
            -- new set of tyres replaces burst tyres too
            local covered = step and serviceTyres and step.bodyKind == "tyre"
            if step and not seen[id] and not covered then
                seen[id] = true
                step.rank = getStepRank(step)
                step.status = "pending"
                result[#result + 1] = step
            end
        end
    end
    table.sort(result, function(a, b) return a.rank < b.rank end)
    return result
end

local function closeOpened(vehicle, opened)
    if not opened or not DoesEntityExist(vehicle) then return end
    for door in pairs(opened) do
        Anim.CloseDoor(vehicle, door)
    end
end

local function finishWorkflow(workflow)
    workflow.current = nil
    workflow.phase = nil
    Anim.StopCarry()
    -- props of the workflow still on the ground
    for _, entry in ipairs(workflow.ground) do
        Anim.DeleteProp(entry.object)
    end
    workflow.ground = {}
    if workflow.toolbox then
        if workflow.fast or IsEntityDead(cache.ped) then
            Anim.DeleteProp(workflow.toolbox)
        else
            Anim.RemoveToolbox(workflow.toolbox)
        end
        workflow.toolbox = nil
    end
    CancelKeybind:disable(true)
    closeOpened(workflow.vehicle, workflow.opened)
    updateOverlay()

    local done = 0
    for _, step in ipairs(workflow.steps) do
        if step.status == "done" then done = done + 1 end
    end
    if workflow.mode ~= "workflow" then
        local step = workflow.steps[1]
        if step and step.status == "done" then
            Core.Notify(step.message or locale("repair_step_done", step.label), "success")
        elseif workflow.cancelled then
            Core.Notify(locale("cancelled"), "error")
        end
    elseif workflow.cancelled then
        Core.Notify(locale("repair_workflow_cancelled"), "error")
    else
        Core.Notify(locale("repair_workflow_done", done, #workflow.steps), done == #workflow.steps and "success" or "inform")
    end
    Wait(workflow.cancelled and 1500 or (workflow.mode == "workflow" and 4000 or 2500))
    if Workflow == workflow then
        Core.Nui.Close("workflow")
        RepairedBody[workflow.netId] = nil
        Workflow = nil
    end
end

local function runWorkflow(workflow)
    -- rolled down windows read as broken, roll them up before any body repair
    if Core.RequestControl(workflow.vehicle, 1500) then
        for i = 0, 7 do RollUpWindow(workflow.vehicle, i) end
    end
    if workflow.mode == "workflow" and AnimSettings.toolbox ~= false and (not AnimSettings.toolboxNeedsItem or Core.CountTool("toolbox") > 0) then
        workflow.toolbox = Anim.PlaceToolbox(workflow.vehicle, function() return isCancelled(workflow) end)
    end
    for i, step in ipairs(workflow.steps) do
        if isCancelled(workflow) then
            step.status = "skipped"
        else
            workflow.current = i
            workflow.phase = nil
            step.status = "active"
            updateOverlay()
            local ok, status, message = pcall(performStep, workflow, step)
            if not ok then
                print("[pls_mechanic] repair step error: "..tostring(status))
                status, message = "failed", locale("repair_failed")
                Anim.Cleanup()
            end
            workflow.phase = nil
            if status == "cancelled" then
                markCancelled(workflow)
                step.status = "skipped"
                step.message = message
            else
                step.status = status
                step.message = message
                if status == "done" then
                    playSound("PICK_UP", "HUD_FRONTEND_DEFAULT_SOUNDSET")
                elseif status == "failed" then
                    playSound("ERROR", "HUD_FRONTEND_DEFAULT_SOUNDSET")
                    Core.Notify(message, "error")
                end
                if status ~= "done" and i < #workflow.steps then
                    -- let the mechanic read the result before the next step starts
                    updateOverlay()
                    Wait(750)
                end
            end
        end
        updateOverlay()
    end
    finishWorkflow(workflow)
end

-- Starts a session (workflow / quick / kit) with resolved steps
local function startSession(vehicle, mode, steps)
    if Workflow then
        Core.Notify(locale("repair_busy"), "error")
        return false
    end
    if cache.vehicle then
        Core.Notify(locale("repair_leave_vehicle"), "error")
        return false
    end
    local busy, busyMessage = isPlayerBusy()
    if busy then
        Core.Notify(busyMessage, "error")
        return false
    end
    local netId = getNetId(vehicle)
    if not netId then
        Core.Notify(locale("no_vehicle"), "error")
        return false
    end
    if #steps == 0 then
        Core.Notify(locale("repair_no_steps"), "error")
        return false
    end
    local data = Core.GetVehicleData(vehicle)
    local workflow = {
        mode = mode,
        vehicle = vehicle,
        netId = netId,
        plate = data and data.plate or Utils.TrimPlate(GetVehicleNumberPlateText(vehicle)),
        steps = steps,
        current = nil,
        phase = nil,
        cancelled = false,
        fast = false,
        opened = {},
        ground = {},
        toolbox = nil,
    }
    Workflow = workflow
    RepairedBody[netId] = {}
    CancelKeybind:disable(false)
    Core.Nui.Open("workflow", Repair.GetOverlayData(), false)
    CreateThread(function()
        local ok, err = pcall(runWorkflow, workflow)
        if not ok then
            print("[pls_mechanic] repair workflow error: "..tostring(err))
            Anim.Cleanup(true)
            CancelKeybind:disable(true)
            if Workflow == workflow then
                Core.Nui.Close("workflow")
                RepairedBody[workflow.netId] = nil
                Workflow = nil
            end
        end
    end)
    return true
end

-- steps = { { kind = "service" | "core" | "body", key = string } }
function Repair.StartWorkflow(vehicle, steps)
    return startSession(vehicle, "workflow", normalizeSteps(steps))
end

-- Cancels running session: stops the current phase at once, remaining steps are skipped.
-- Another cancel while cleaning up skips the cleanup animations (toolbox is removed at once).
function Repair.Cancel()
    local workflow = Workflow
    if not workflow then return end
    if workflow.cancelled then
        if GetGameTimer() - (workflow.cancelledAt or 0) < 500 then return end
        workflow.fast = true
    end
    markCancelled(workflow)
    if fetchEnabled() and Fetch.IsWaiting("repair") then
        Fetch.Cancel()
    end
    Anim.Cleanup()
end

function Repair.IsBusy()
    return Workflow ~= nil
end

-- Workflow paused until the mechanic brings the parts of the current step
function Repair.IsWaiting()
    local workflow = Workflow
    return workflow ~= nil and workflow.waiting == true
end

-- Checks the whole workflow before it starts: items summed over all steps, tools, location, permission.
-- With parts fetching (Config.Fetch) items / tools don't block, only parts missing in the workshop storage do.
-- Returns ok, message with all problems (workflow is not started instead of failing step by step),
-- info (parts to fetch from the storage, caller notifies "inform" after the start)
function Repair.Preflight(vehicle, steps)
    local list = normalizeSteps(steps)
    if #list == 0 then return false, locale("repair_no_steps") end
    local problems, seenProblem = {}, {}
    local function addProblem(text)
        if not seenProblem[text] then
            seenProblem[text] = true
            problems[#problems + 1] = text
        end
    end
    local needed, order = {}, {}
    local tools, missingTools, seenTool = {}, {}, {}
    for _, step in ipairs(list) do
        if step.kind ~= "body" or Repair.IsBodyDamaged(vehicle, step.key) then
            if not Core.HasPermission(step.perm) then
                addProblem(locale("repair_preflight_step", step.label, permissionReason()))
            else
                local locationOk, reason = Core.CheckLocation(vehicle, step.location, step.wheel)
                if not locationOk then
                    addProblem(locale("repair_preflight_step", step.label, locale(reason or "location_bay")))
                end
            end
            for _, key in ipairs(step.part.tools or {}) do
                if not seenTool[key] then
                    seenTool[key] = true
                    tools[#tools + 1] = key
                    if Core.CountTool(key) < 1 then
                        missingTools[#missingTools + 1] = Core.GetItemLabel(Utils.Item(key))
                    end
                end
            end
            local multiplier = step.bodyKind == "deformation" and Repair.GetDeformationCount(GetVehicleBodyHealth(vehicle)) or 1
            for _, v in ipairs(step.part.items or {}) do
                if not needed[v.item] then order[#order + 1] = v.item end
                needed[v.item] = (needed[v.item] or 0) + v.count * multiplier
            end
        end
    end
    local info = nil
    if fetchEnabled() then
        -- parts are brought step by step, the start is refused only when the storage doesn't have them
        if #order > 0 or #tools > 0 then
            local ok, ready, problem, fetchInfo = pcall(Fetch.CheckStart, getFetchShopId(vehicle), needed, tools)
            if not ok then
                print("[pls_mechanic] repair fetch preflight error: "..tostring(ready))
            elseif ready == false then
                table.insert(problems, 1, problem or locale("repair_failed"))
            else
                info = fetchInfo
            end
        end
    else
        local missingItems = {}
        for _, key in ipairs(order) do
            local have = Core.CountItem(key)
            if have < needed[key] then
                missingItems[#missingItems + 1] = ("%dx %s"):format(needed[key] - have, Core.GetItemLabel(Utils.Item(key)))
            end
        end
        if #missingItems > 0 then
            table.insert(problems, 1, locale("missing_items", table.concat(missingItems, ", ")))
        end
        if #missingTools > 0 then
            table.insert(problems, 1, locale("missing_tool", table.concat(missingTools, ", ")))
        end
    end
    if #problems > 0 then
        return false, table.concat(problems, " • ")
    end
    return true, nil, info
end

--[[
   ____        _      _                                _
  / __ \      (_)    | |                              (_)
 | |  | |_   _ _  ___| | __  _ __ ___ _ __   __ _ _ __ _ ___
 | |  | | | | | |/ __| |/ / | '__/ _ \ '_ \ / _` | '__| / __|
 | |__| | |_| | | (__|   <  | | |  __/ |_) | (_| | |  | \__ \
  \___\_\\__,_|_|\___|_|\_\ |_|  \___| .__/ \__,_|_|  |_|___/
                                     | |
                                     |_|
]]--

-- Closest body key of bodyKind ("tyre" / "wheel") that is damaged
local function findClosestDamagedWheel(vehicle, bodyKind)
    local pedCoords = GetEntityCoords(cache.ped)
    local best, bestDistance = nil, nil
    for i = 0, 5 do
        local bone = GetEntityBoneIndexByName(vehicle, Utils.WheelBones[i])
        if bone ~= -1 and Repair.IsBodyDamaged(vehicle, bodyKind..":"..i) then
            local distance = #(pedCoords - GetWorldPositionOfEntityBone(vehicle, bone))
            if not bestDistance or distance < bestDistance then
                best, bestDistance = i, distance
            end
        end
    end
    return best
end

local function getTargetVehicle()
    if cache.vehicle then
        Core.Notify(locale("repair_leave_vehicle"), "error")
        return nil
    end
    local vehicle = Core.GetClosestVehicle(4.0)
    if not vehicle or not getNetId(vehicle) then
        Core.Notify(locale("no_vehicle"), "error")
        return nil
    end
    return vehicle
end

-- Quick repair item -> step on the closest damaged part. Returns kind, key or nil + locale key
local QuickRepairSteps = {
    tyre = function(vehicle)
        local index = findClosestDamagedWheel(vehicle, "tyre")
        if not index then return nil, nil, "repair_no_burst_tyre" end
        return "body", "tyre:"..index
    end,
    car_wheel = function(vehicle)
        local index = findClosestDamagedWheel(vehicle, "wheel")
        if not index then return nil, nil, "repair_no_missing_wheel" end
        return "body", "wheel:"..index
    end,
    car_battery = function()
        return "core", "battery"
    end,
}

local function quickRepair(itemKey)
    if Workflow then
        Core.Notify(locale("repair_busy"), "error")
        return
    end
    local vehicle = getTargetVehicle()
    if not vehicle then return end
    local kind, key, errorKey = QuickRepairSteps[itemKey](vehicle)
    if not kind then
        Core.Notify(locale(errorKey), "error")
        return
    end
    local step = Repair.ResolveStep(kind, key)
    if not step then return end
    step.quick = itemKey
    step.status = "pending"
    startSession(vehicle, "quick", { step })
end

for itemKey in pairs(QuickRepairSteps) do
    if Config.QuickRepairs[itemKey] then
        Items.Register(itemKey, function()
            CreateThread(function()
                quickRepair(itemKey)
            end)
        end)
    end
end

--[[
  _  ___ _
 | |/ (_) |
 | ' / _| |_ ___
 |  < | | __/ __|
 | . \| | |_\__ \
 |_|\_\_|\__|___/
]]--

local function canUseMechanicKit(kit)
    if Core.IsOnDuty() or (not Config.RequireDuty and Core.IsMechanic()) then return true end
    -- crew member inside his illegal workshop
    if Core.GetMyShopId() ~= nil then return true end
    local job = BRIDGE.GetPlayerJob()
    for _, name in ipairs(kit.jobs or {}) do
        if name == job then return true end
    end
    return false
end

local function useKit(kitKey)
    local kit = Config.RepairKits[kitKey]
    if not kit then return end
    if Workflow then
        Core.Notify(locale("repair_busy"), "error")
        return
    end
    local vehicle = getTargetVehicle()
    if not vehicle then return end
    if kit.mechanicOnly and not canUseMechanicKit(kit) then
        Core.Notify(locale("kit_mechanic_only"), "error")
        return
    end
    local step = Repair.ResolveStep("kit", kitKey)
    if not step then return end
    step.status = "pending"
    startSession(vehicle, "kit", { step })
end

for kitKey in pairs(Config.RepairKits) do
    Items.Register(kitKey, function()
        CreateThread(function()
            useKit(kitKey)
        end)
    end)
end

--[[
  _______                   _
 |__   __|                 | |
    | | __ _ _ __ __ _  ___| |_
    | |/ _` | '__/ _` |/ _ \ __|
    | | (_| | | | (_| |  __/ |_
    |_|\__,_|_|  \__, |\___|\__|
                  __/ |
                 |___/
]]--

CreateThread(function()
    CancelTarget = BRIDGE.AddGlobalVehicleTarget({
        {
            name = "pls_mechanic_repair_cancel",
            label = locale("repair_cancel_target"),
            icon = "fa-solid fa-ban",
            distance = 3.0,
            canInteract = function(entity)
                local workflow = Workflow
                if not workflow or workflow.cancelled or not entity or entity == 0 then return false end
                if not NetworkGetEntityIsNetworked(entity) then return false end
                return NetworkGetNetworkIdFromEntity(entity) == workflow.netId
            end,
            onSelect = function()
                Repair.Cancel()
            end,
        },
    })
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
    if CancelTarget then
        BRIDGE.RemoveGlobalVehicleTarget(CancelTarget)
    end
    local vehicle = EngineTestVehicle
    if vehicle and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == 0 and NetworkHasControlOfEntity(vehicle) then
        SetVehicleEngineOn(vehicle, false, true, false)
    end
end)
