--[[
  __  __           _                 _        __  __
 |  \/  |         | |               (_)      |  \/  |
 | \  / | ___  ___| |__   __ _ _ __  _  ___  | \  / | ___ _ __  _   _
 | |\/| |/ _ \/ __| '_ \ / _` | '_ \| |/ __| | |\/| |/ _ \ '_ \| | | |
 | |  | |  __/ (__| | | | (_| | | | | | (__  | |  | |  __/ | | | |_| |
 |_|  |_|\___|\___|_| |_|\__,_|_| |_|_|\___| |_|  |_|\___|_| |_|\__,_|

 Mechanic menu (keybind + radial while on duty) and vehicle actions:
 push, flip, unlock (slim jim), impound, flatbed towing, jump starter.
 Every action is a small scene (walk to the spot, phases with anims / props / sounds),
 Config.Keys.cancel or the progress cancel stops it and cleans everything up.
]]--

Menu = {}

local MENU_ID = "pls_mechanic_menu"
local RADIAL_ID = "pls_mechanic_menu"
local UNLOAD_GAP = 0.8              -- m between the rear edge of the flatbed and the unloaded vehicle

local Busy = false
local Pushing = nil          -- vehicle being pushed
local RadialAdded = false
local CancelHandler = nil
local VehicleTargetId = nil
local Scene = nil            -- cleanup state of the running scene

-- flatbed model hash -> config
local FlatbedModels = {}

local function HashKey(hash)
    return math.floor(hash or 0) & 0xFFFFFFFF
end

for model, data in pairs(Config.Flatbeds or {}) do
    FlatbedModels[HashKey(joaat(model))] = data
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

local function Notify(key, notifyType, ...)
    Core.Notify(locale(key, ...), notifyType or "inform")
end

local function GetNetId(entity)
    if not entity or not DoesEntityExist(entity) or not NetworkGetEntityIsNetworked(entity) then return nil end
    return NetworkGetNetworkIdFromEntity(entity)
end

local function GetPlate(vehicle)
    return Utils.TrimPlate(GetVehicleNumberPlateText(vehicle))
end

local function GetFlatbedConfig(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    -- the target checks every entity under the cursor, an entity being removed / not streamed yet throws in GetEntityModel
    local ok, model = pcall(GetEntityModel, vehicle)
    if not ok or not model or model == 0 then return nil end
    return FlatbedModels[HashKey(model)]
end

-- Mechanic menu is available on duty (or for mechanics when duty is not required)
-- and for crew members inside their illegal workshop (no duty there)
local function HasAccess(duty)
    if duty == nil then duty = Core.GetDutyShopId() end
    if duty then return true end
    if not Config.RequireDuty and Core.IsMechanic() then return true end
    return Core.GetIllegalShopId() ~= nil
end

local function CanUseActions()
    if Busy or Pushing then return false end
    if Props and Props.IsPlacing and Props.IsPlacing() then return false end
    if IsPauseMenuActive() or IsPedDeadOrDying(cache.ped, true) or IsPedCuffed(cache.ped) then return false end
    -- scene of the illegal DLC is running
    if Core.IsExternalBusy() then return false end
    return true
end

-- Repair workflow / tuning installation / another phase of the shared animation library / DLC scene is running
local function OtherWorkRunning()
    if (Tuning and Tuning.IsInstalling and Tuning.IsInstalling()) or (Repair and Repair.IsBusy and Repair.IsBusy()) or Anim.IsBusy()
        or Core.IsExternalBusy() then
        Core.Notify(locale("repair_busy"), "error")
        return true
    end
    return false
end

-- Closest vehicle for action. Returns vehicle or nil (+ notify)
local function GetTargetVehicle(vehicle, onFoot)
    if onFoot and cache.vehicle then
        Notify("menu_on_foot", "error")
        return nil
    end
    vehicle = vehicle or Core.GetClosestVehicle(Config.MechanicMenu.vehicleDistance)
    if not vehicle or not DoesEntityExist(vehicle) then
        Notify("no_vehicle", "error")
        return nil
    end
    if not GetNetId(vehicle) then
        Notify("no_control", "error")
        return nil
    end
    return vehicle
end

-- Heading from coords towards entity
local function HeadingTo(from, entity)
    local target = GetEntityCoords(entity)
    return GetHeadingFromVector_2d(target.x - from.x, target.y - from.y)
end

-- Sparks at the engine (networked). cfg = { asset, name, scale }
local function Sparks(vehicle, cfg)
    if not cfg or not DoesEntityExist(vehicle) then return end
    local bone = GetEntityBoneIndexByName(vehicle, "engine")
    local coords = bone ~= -1 and GetWorldPositionOfEntityBone(vehicle, bone) or GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.5, 0.3)
    if not lib.requestNamedPtfxAsset(cfg.asset, 2000) then return end
    UseParticleFxAssetNextCall(cfg.asset)
    StartNetworkedParticleFxNonLoopedAtCoord(cfg.name, coords.x, coords.y, coords.z + 0.2, 0.0, 0.0, 0.0, cfg.scale or 1.0, false, false, false)
    if cfg.asset ~= "core" then
        RemoveNamedPtfxAsset(cfg.asset)
    end
end

-- Cancel key (Config.Keys.cancel) shared by push / placement / scenes
function Menu.SetCancelHandler(fn)
    CancelHandler = fn
end

function Menu.IsBusy()
    return Busy or Pushing ~= nil
end

lib.addKeybind({
    name = "pls_mechanic_extras_cancel",
    description = locale("menu_keybind_cancel"),
    defaultKey = Config.Keys.cancel,
    onPressed = function()
        if CancelHandler then
            local fn = CancelHandler
            CancelHandler = nil
            fn()
        end
    end,
})

--[[
   _____
  / ____|
 | (___   ___ ___ _ __   ___
  \___ \ / __/ _ \ '_ \ / _ \
  ____) | (_|  __/ | | |  __/
 |_____/ \___\___|_| |_|\___|

 Scene = { cancelled, ropes, onCleanup } of the running action.
 Phases come from configs/extras.lua: { label, share | duration, anim, prop, prop2, sound, particle }
]]--

local function IsCancelled()
    return Scene == nil or Scene.cancelled == true
end

local function BeginScene()
    Scene = { cancelled = false, ropes = {} }
    local scene = Scene
    scene.cancelFn = function()
        scene.cancelled = true
    end
    Menu.SetCancelHandler(scene.cancelFn)
    return scene
end

-- One-shot sound outside of a phase (sfx = { name, set, bank? }), bank released a few seconds later
local function PlaySfx(sfx, entity)
    if not sfx or not sfx.name then return end
    CreateThread(function()
        if sfx.bank then
            local timeout = GetGameTimer() + 2000
            while not RequestScriptAudioBank(sfx.bank, false) do
                if GetGameTimer() > timeout then return end
                Wait(0)
            end
        end
        local target = entity and DoesEntityExist(entity) and entity or cache.ped
        PlaySoundFromEntity(-1, sfx.name, target, sfx.set, false, 0)
        if sfx.bank then
            Wait(5000)
            ReleaseNamedScriptAudioBank(sfx.bank)
        end
    end)
end

-- Rope between two entities (jumper / winch cable), removed with the scene. Positions are world coords on the entities.
-- ropeType 0 = thin rope, 1 = steel cable
local function AddCable(scene, ropeType, entity1, pos1, entity2, pos2)
    if not scene or Scene ~= scene then return nil end
    RopeLoadTextures()
    local timeout = GetGameTimer() + 1500
    while not RopeAreTexturesLoaded() and GetGameTimer() < timeout do
        Wait(0)
    end
    if Scene ~= scene or not DoesEntityExist(entity1) or not DoesEntityExist(entity2) then return nil end
    local length = math.max(0.5, #(pos1 - pos2))
    local rope = AddRope(pos1.x, pos1.y, pos1.z, 0.0, 0.0, 0.0, length + 2.0, ropeType, length, 0.3, 1.0, false, false, false, 1.0, false, 0)
    if not rope or not DoesRopeExist(rope) then return nil end
    AttachEntitiesToRope(rope, entity1, entity2, pos1.x, pos1.y, pos1.z, pos2.x, pos2.y, pos2.z, length, false, false, nil, nil)
    table.insert(scene.ropes, rope)
    return rope
end

-- Invisible local point for a cable end that must not pull on the vehicle (removed with the cables).
-- A rope between a frozen prop and a vehicle launches the vehicle into the air on the smallest movement.
local function CableAnchor(scene, coords)
    if not scene or Scene ~= scene then return nil end
    local model = `prop_golf_ball`
    if not IsModelValid(model) then return nil end
    lib.requestModel(model)
    local anchor = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not anchor or anchor == 0 or not DoesEntityExist(anchor) then return nil end
    SetEntityCoordsNoOffset(anchor, coords.x, coords.y, coords.z, false, false, false)
    FreezeEntityPosition(anchor, true)
    SetEntityCollision(anchor, false, false)
    SetEntityVisible(anchor, false, false)
    scene.anchors = scene.anchors or {}
    table.insert(scene.anchors, anchor)
    return anchor
end

local function RemoveCables(scene)
    for _, rope in ipairs(scene.ropes) do
        if DoesRopeExist(rope) then
            DeleteRope(rope)
        end
    end
    scene.ropes = {}
    for _, anchor in ipairs(scene.anchors or {}) do
        if DoesEntityExist(anchor) then
            DeleteEntity(anchor)
        end
    end
    scene.anchors = {}
end

-- Ends the scene: removes cables, runs the scene cleanup, library cleanup when cancelled
local function EndScene()
    local scene = Scene
    if not scene then return end
    Scene = nil
    if CancelHandler == scene.cancelFn then
        CancelHandler = nil
    end
    RemoveCables(scene)
    if scene.cancelled then
        Anim.Cleanup()
    end
    if scene.onCleanup then
        local ok, err = pcall(scene.onCleanup, scene.cancelled)
        if not ok then print("[pls_mechanic] scene cleanup error: "..tostring(err)) end
    end
end

-- Ends the running action (scene cleanup + busy flag) with optional notify.
-- "cancelled" (also a progress cancelled by its own key) cleans up like the cancel key.
local function Finish(key, notifyType, ...)
    if key == "cancelled" and Scene then
        Scene.cancelled = true
    end
    EndScene()
    Busy = false
    if key then Notify(key, notifyType, ...) end
end

-- Ends the scene without touching the busy flag (flatbed, busy is handled by Menu.Tow)
local function Abort(key, notifyType)
    if key == "cancelled" and Scene then
        Scene.cancelled = true
    end
    EndScene()
    Notify(key, notifyType or "error")
end

local function PhaseDuration(phase, total)
    if phase.duration then return phase.duration end
    return math.max(500, math.floor((total or 0) * (phase.share or 0)))
end

-- Same anim / prop in two config entries (kept between phases, no restart)
local function SameEntry(a, b)
    if a == nil or b == nil then return false end
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if a.scenario or b.scenario then return a.scenario == b.scenario end
    if a.dict then return a.dict == b.dict and a.clip == b.clip end
    return a.model ~= nil and a.model == b.model and a.bone == b.bone
end

-- Runs one config phase with Anim.Phase. vehicle = "vehicle" entity of sounds / particles.
-- extra overrides options (false = remove). Returns true when completed and not cancelled.
local function RunPhase(phase, total, vehicle, extra)
    if IsCancelled() then return false end
    local opts = {
        label = locale(phase.label),
        duration = PhaseDuration(phase, total),
        anim = phase.anim,
        prop = phase.prop,
        prop2 = phase.prop2,
        sound = phase.sound,
        particle = phase.particle,
        vehicle = vehicle,
        cancel = IsCancelled,
    }
    for key, value in pairs(extra or {}) do
        if value == false then
            opts[key] = nil
        else
            opts[key] = value
        end
    end
    return Anim.Phase(opts) == true and not IsCancelled()
end

-- Runs phases one after another at one spot (shared anim / prop stays on). hook(phase) -> extra options
local function RunPhases(list, total, vehicle, hook)
    for i, phase in ipairs(list) do
        local extra = hook and hook(phase) or {}
        local nextPhase = list[i + 1]
        if nextPhase then
            extra.keepAnim = SameEntry(phase.anim, nextPhase.anim)
            extra.keepProp = SameEntry(phase.prop, nextPhase.prop)
        end
        if not RunPhase(phase, total, vehicle, extra) then
            return false
        end
    end
    return true
end

--[[
  _____           _
 |  __ \         | |
 | |__) |   _ ___| |__
 |  ___/ | | / __| '_ \
 | |   | |_| \__ \ | | |
 |_|    \__,_|___/_| |_|
]]--

local PushControls = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 37, 44, 140, 141, 142 }

local function StopPush(vehicle)
    local anim = Config.Push.anim
    StopAnimTask(cache.ped, anim.dict, anim.clip, 2.0)
    if DoesEntityExist(vehicle) and IsEntityAttachedToEntity(cache.ped, vehicle) then
        DetachEntity(cache.ped, true, false)
    end
    ClearPedSecondaryTask(cache.ped)
    lib.hideTextUI()
    CancelHandler = nil
    Pushing = nil
end

local function PushLoop(vehicle, front)
    local anim = Config.Push.anim
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local y = front and (max.y + Config.Push.gap) or (min.y - Config.Push.gap)
    local direction = front and -1.0 or 1.0
    local angle = 0.0
    local stop = false

    lib.requestAnimDict(anim.dict)
    AttachEntityToEntity(cache.ped, vehicle, 0, 0.0, y, min.z + Config.Push.height, 0.0, 0.0, front and 180.0 or 0.0, false, false, false, true, 2, true)
    Menu.SetCancelHandler(function() stop = true end)
    lib.showTextUI(locale("menu_push_help", Config.Keys.cancel))

    while not stop do
        if not DoesEntityExist(vehicle) or not IsEntityAttachedToEntity(cache.ped, vehicle) then break end
        if IsPedDeadOrDying(cache.ped, true) or not IsVehicleSeatFree(vehicle, -1) then break end
        if GetEntitySpeed(vehicle) > Config.Push.maxSpeed or IsEntityInWater(vehicle) then break end

        for i = 1, #PushControls do
            DisableControlAction(0, PushControls[i], true)
        end
        if IsDisabledControlJustPressed(0, 23) then break end -- F = let go

        if not NetworkHasControlOfEntity(vehicle) then
            NetworkRequestControlOfEntity(vehicle)
        end

        -- steering (A / D), wheels keep their angle like in a real car
        if IsDisabledControlPressed(0, 34) then
            angle = math.min(angle + 1.5, 40.0)
        elseif IsDisabledControlPressed(0, 35) then
            angle = math.max(angle - 1.5, -40.0)
        end
        SetVehicleSteeringAngle(vehicle, angle * (front and -1.0 or 1.0))

        if IsDisabledControlPressed(0, 32) then
            if not IsEntityPlayingAnim(cache.ped, anim.dict, anim.clip, 3) then
                TaskPlayAnim(cache.ped, anim.dict, anim.clip, 2.0, -8.0, -1, 35, 0, false, false, false)
            end
            SetVehicleForwardSpeed(vehicle, Config.Push.speed * direction)
        elseif IsEntityPlayingAnim(cache.ped, anim.dict, anim.clip, 3) then
            StopAnimTask(cache.ped, anim.dict, anim.clip, 2.0)
        end
        Wait(0)
    end

    StopPush(vehicle)
    RemoveAnimDict(anim.dict)
end

function Menu.Push(vehicle)
    if not CanUseActions() or OtherWorkRunning() then return end
    vehicle = GetTargetVehicle(vehicle, true)
    if not vehicle then return end
    if Config.Push.blacklistClasses[GetVehicleClass(vehicle)] then
        return Notify("menu_push_class", "error")
    end
    if not IsVehicleSeatFree(vehicle, -1) then
        return Notify("menu_vehicle_occupied", "error")
    end
    if IsEntityAttached(vehicle) then
        return Notify("menu_vehicle_attached", "error")
    end
    if IsEntityUpsidedown(vehicle) or not IsVehicleOnAllWheels(vehicle) then
        return Notify("menu_push_flipped", "error")
    end
    Busy = true
    local ok, err = lib.callback.await("pls_mechanic:server:menu:action", false, "push", GetNetId(vehicle))
    if not ok then
        Busy = false
        return Notify(err or "no_permission", "error")
    end
    if not Core.RequestControl(vehicle, 2000) then
        Busy = false
        return Notify("no_control", "error")
    end

    -- walk to the closer bumper and brace against it
    local scene = BeginScene()
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local pedCoords = GetEntityCoords(cache.ped)
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, pedCoords.x, pedCoords.y, pedCoords.z)
    local front = offset.y > 0.0
    local y = front and (max.y + Config.Push.gap + 0.3) or (min.y - Config.Push.gap - 0.3)
    local pos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, y, 0.0)
    Anim.WalkAround(vehicle, pos, GetEntityHeading(vehicle) + (front and 180.0 or 0.0), 6000, IsCancelled)
    if not IsCancelled() and Config.Push.brace then
        Anim.Play(Config.Push.brace)
    end
    if scene.cancelled or not DoesEntityExist(vehicle) or not IsVehicleSeatFree(vehicle, -1) or cache.vehicle then
        return Finish(scene.cancelled and "cancelled" or nil, "error")
    end
    EndScene()
    Busy = false
    Pushing = vehicle
    CreateThread(function()
        PushLoop(vehicle, front)
    end)
end

--[[
  ______ _ _
 |  ____| (_)
 | |__  | |_ _ __
 |  __| | | | '_ \
 | |    | | | |_) |
 |_|    |_|_| .__/
            | |
            |_|
 The vehicle is frozen while the mechanic rocks it and rolls it over (quaternion slerp to upright).
]]--

local function IsFlipped(vehicle)
    return IsEntityUpsidedown(vehicle) or math.abs(GetEntityRoll(vehicle)) > 45.0 or not IsVehicleOnAllWheels(vehicle)
end

local function GetQuat(entity)
    local x, y, z, w = GetEntityQuaternion(entity)
    return { x = x, y = y, z = z, w = w }
end

local function SetQuat(entity, q)
    SetEntityQuaternion(entity, q.x, q.y, q.z, q.w)
end

local function QuatMul(a, b)
    return {
        x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    }
end

local function QuatSlerp(a, b, t)
    local dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
    if dot < 0.0 then
        b = { x = -b.x, y = -b.y, z = -b.z, w = -b.w }
        dot = -dot
    end
    local wa, wb
    if dot > 0.9995 then
        wa, wb = 1.0 - t, t
    else
        local theta = math.acos(dot)
        local sinTheta = math.sin(theta)
        wa = math.sin((1.0 - t) * theta) / sinTheta
        wb = math.sin(t * theta) / sinTheta
    end
    local q = { x = a.x * wa + b.x * wb, y = a.y * wa + b.y * wb, z = a.z * wa + b.z * wb, w = a.w * wa + b.w * wb }
    local length = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if length > 0.0 then
        q.x, q.y, q.z, q.w = q.x / length, q.y / length, q.z / length, q.w / length
    end
    return q
end

-- Upright rotation keeping the direction the vehicle points to. Returns quaternion, heading
local function UprightQuat(vehicle)
    local center = GetEntityCoords(vehicle)
    local forward = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.0, 0.0) - center
    local heading = (math.abs(forward.x) + math.abs(forward.y) > 0.2) and GetHeadingFromVector_2d(forward.x, forward.y) or GetEntityHeading(vehicle)
    local half = math.rad(heading) * 0.5
    return { x = 0.0, y = 0.0, z = math.sin(half), w = math.cos(half) }, heading
end

-- Pushing spot: roof side when the vehicle lies on its side, otherwise the closer side
local function FlipPosition(vehicle)
    local center = GetEntityCoords(vehicle)
    local up = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, 1.0) - center
    local dir
    if math.abs(up.z) < 0.6 then
        dir = vector2(up.x, up.y)
    else
        local right = GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0) - center
        local toPed = GetEntityCoords(cache.ped) - center
        local sign = (toPed.x * right.x + toPed.y * right.y) >= 0.0 and 1.0 or -1.0
        dir = vector2(right.x * sign, right.y * sign)
    end
    local length = #dir
    dir = length > 0.01 and dir / length or vector2(1.0, 0.0)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local distance = math.max(max.x - min.x, max.z - min.z) * 0.5 + 0.7
    local pos = vector3(center.x + dir.x * distance, center.y + dir.y * distance, GetEntityCoords(cache.ped).z)
    return pos, GetHeadingFromVector_2d(center.x - pos.x, center.y - pos.y)
end

local function NextMotion(scene)
    scene.motionId = (scene.motionId or 0) + 1
    scene.motion = scene.motionId
    return scene.motionId
end

-- Rocks the frozen vehicle around its forward axis until another motion starts or scene.motion is cleared
local function RockVehicle(scene, strength)
    local token = NextMotion(scene)
    CreateThread(function()
        local vehicle = scene.vehicle
        local amplitude = math.rad(Config.Flip.rockAngle * strength)
        local start = GetGameTimer()
        while scene.motion == token and DoesEntityExist(vehicle) do
            local half = math.sin((GetGameTimer() - start) / 1000.0 * 5.0) * amplitude * 0.5
            SetQuat(vehicle, QuatMul(scene.baseQuat, { x = 0.0, y = math.sin(half), z = 0.0, w = math.cos(half) }))
            Wait(0)
        end
        if scene.motion == false and DoesEntityExist(vehicle) then
            SetQuat(vehicle, scene.baseQuat)
        end
    end)
end

-- Rolls the vehicle back on its wheels during duration ms (lifted on the way, no clipping into the ground)
local function RollVehicle(scene, duration)
    local token = NextMotion(scene)
    CreateThread(function()
        local vehicle = scene.vehicle
        local target = UprightQuat(vehicle)
        local min, max = GetModelDimensions(GetEntityModel(vehicle))
        local lift = math.max(Config.Flip.rollLift, (max.x - min.x) * 0.5 - (max.z - min.z) * 0.5 + 0.15)
        local start = GetGameTimer()
        while scene.motion == token and DoesEntityExist(vehicle) do
            local t = math.min(1.0, (GetGameTimer() - start) / duration)
            local eased = t * t * (3.0 - 2.0 * t)
            SetQuat(vehicle, QuatSlerp(scene.baseQuat, target, eased))
            SetEntityCoordsNoOffset(vehicle, scene.basePos.x, scene.basePos.y, scene.basePos.z + math.sin(eased * math.pi) * lift, false, false, false)
            if t >= 1.0 then
                scene.rolled = true
                break
            end
            Wait(0)
        end
    end)
end

function Menu.Flip(vehicle)
    if not CanUseActions() or OtherWorkRunning() then return end
    vehicle = GetTargetVehicle(vehicle, true)
    if not vehicle then return end
    if not IsFlipped(vehicle) then
        return Notify("menu_flip_not_needed", "error")
    end
    if not IsVehicleSeatFree(vehicle, -1) then
        return Notify("menu_vehicle_occupied", "error")
    end
    Busy = true
    local ok, err = lib.callback.await("pls_mechanic:server:menu:action", false, "flip", GetNetId(vehicle))
    if not ok then
        Busy = false
        return Notify(err or "no_permission", "error")
    end
    if not Core.RequestControl(vehicle, 2000) then
        Busy = false
        return Notify("no_control", "error")
    end

    local scene = BeginScene()
    scene.vehicle = vehicle
    scene.onCleanup = function(cancelled)
        scene.motion = false
        if not DoesEntityExist(vehicle) then return end
        if cancelled and scene.baseQuat then
            SetQuat(vehicle, scene.baseQuat)
            SetEntityCoordsNoOffset(vehicle, scene.basePos.x, scene.basePos.y, scene.basePos.z, false, false, false)
        end
        FreezeEntityPosition(vehicle, false)
    end

    local pos, heading = FlipPosition(vehicle)
    Anim.WalkAround(vehicle, pos, heading, 8000, IsCancelled)
    if IsCancelled() or not DoesEntityExist(vehicle) then
        return Finish("cancelled", "error")
    end
    Anim.Face(vehicle)

    FreezeEntityPosition(vehicle, true)
    scene.baseQuat = GetQuat(vehicle)
    scene.basePos = GetEntityCoords(vehicle)
    local done = RunPhases(Config.Flip.phases, Config.Flip.duration, vehicle, function(phase)
        local duration = PhaseDuration(phase, Config.Flip.duration)
        return {
            onStart = function()
                if phase.rock then
                    RockVehicle(scene, phase.rock)
                elseif phase.roll then
                    RollVehicle(scene, math.floor(duration * 0.85))
                end
            end,
            onEnd = function()
                if phase.rock then
                    scene.motion = false
                end
            end,
        }
    end)
    if not done then
        return Finish("cancelled", "error")
    end

    -- roll animation may still be finishing on slow frames
    local timeout = GetGameTimer() + 1000
    while not scene.rolled and GetGameTimer() < timeout do
        Wait(0)
    end
    scene.motion = false
    if not DoesEntityExist(vehicle) or not Core.RequestControl(vehicle, 2000) then
        return Finish("no_control", "error")
    end
    local _, yaw = UprightQuat(vehicle)
    SetEntityRotation(vehicle, 0.0, 0.0, yaw, 2, true)
    FreezeEntityPosition(vehicle, false)
    SetVehicleOnGroundProperly(vehicle)
    Finish("menu_flip_done", "success")
end

--[[
  _    _       _            _
 | |  | |     | |          | |
 | |  | |_ __ | | ___   ___| | __
 | |  | | '_ \| |/ _ \ / __| |/ /
 | |__| | | | | | (_) | (__|   <
  \____/|_| |_|_|\___/ \___|_|\_\
]]--

-- Spot at the lock side of the driver door (window gap next to the B-pillar), facing the door
local function DriverDoorPosition(vehicle)
    local bone = GetEntityBoneIndexByName(vehicle, "door_dside_f")
    if bone == -1 then return nil end
    local doorPos = GetWorldPositionOfEntityBone(vehicle, bone)
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, doorPos.x, doorPos.y, doorPos.z)
    local side = offset.x < 0 and -1 or 1
    local pos = GetOffsetFromEntityInWorldCoords(vehicle, offset.x + side * 0.65, offset.y - 0.55, 0.0)
    return pos, GetEntityHeading(vehicle) + (side < 0 and -90.0 or 90.0)
end

function Menu.Unlock(vehicle)
    if not CanUseActions() or OtherWorkRunning() then return end
    if not Core.HasPermission("tow") then
        return Notify("no_permission", "error")
    end
    if Core.CountTool("slim_jim") < 1 then
        return Notify("missing_tool", "error", Core.GetItemLabel(Utils.Item("slim_jim")))
    end
    vehicle = GetTargetVehicle(vehicle, true)
    if not vehicle then return end
    if GetVehicleDoorLockStatus(vehicle) < 2 then
        return Notify("menu_unlock_not_locked", "error")
    end
    Busy = true
    local netId = GetNetId(vehicle)
    local cfg = Config.Unlock
    BeginScene()
    local pos, heading = DriverDoorPosition(vehicle)
    if pos then
        Anim.WalkAround(vehicle, pos, heading, 8000, IsCancelled)
    else
        Anim.Face(vehicle)
    end
    if IsCancelled() or not DoesEntityExist(vehicle) then
        return Finish("cancelled", "error")
    end
    if Config.UnlockDispatch then
        pcall(Config.UnlockDispatch, vehicle, GetEntityCoords(vehicle))
    end

    lib.callback.await("pls_mechanic:server:menu:begin", false, "unlock", netId)
    if not RunPhases(cfg.phases, cfg.duration, vehicle) then
        return Finish("cancelled", "error")
    end

    local result = lib.callback.await("pls_mechanic:server:menu:unlock", false, netId)
    if not result or not result.ok then
        return Finish(result and result.message or "no_permission", "error")
    end
    if result.success then
        PlaySfx(cfg.successSound, vehicle)
        if Core.RequestControl(vehicle, 2000) then
            SetVehicleDoorsLocked(vehicle, 1)
            SetVehicleDoorsLockedForAllPlayers(vehicle, false)
            if cfg.openDoor then
                SetVehicleDoorOpen(vehicle, 0, false, false)
            end
        end
        if cfg.giveKeys and Config.GiveKeys then
            pcall(Config.GiveKeys, vehicle, GetPlate(vehicle))
        end
        Finish("menu_unlock_success", "success")
    else
        if result.broken then
            PlaySfx(cfg.breakSound, cache.ped)
        end
        if cfg.alarm and Core.RequestControl(vehicle, 1000) then
            SetVehicleAlarm(vehicle, true)
            StartVehicleAlarm(vehicle)
        end
        Finish(result.broken and "menu_unlock_broken" or "menu_unlock_failed", "error")
    end
end

--[[
  _____                                       _
 |_   _|                                     | |
   | |  _ __ ___  _ __   ___  _   _ _ __   __| |
   | | | '_ ` _ \| '_ \ / _ \| | | | '_ \ / _` |
  _| |_| | | | | | |_) | (_) | |_| | | | | (_| |
 |_____|_| |_| |_| .__/ \___/ \__,_|_| |_|\__,_|
                 | |
                 |_|
]]--

-- Photo / report spot around the vehicle, facing it
local function ImpoundSpot(vehicle, spot)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local pos
    if spot == "front" then
        pos = GetOffsetFromEntityInWorldCoords(vehicle, min.x - 0.9, max.y + 1.2, 0.0)
    elseif spot == "rear" then
        pos = GetOffsetFromEntityInWorldCoords(vehicle, max.x + 0.9, min.y - 1.2, 0.0)
    else
        pos = GetOffsetFromEntityInWorldCoords(vehicle, min.x - 1.1, 0.0, 0.0)
    end
    return pos, HeadingTo(pos, vehicle)
end

function Menu.Impound(vehicle)
    if not CanUseActions() or OtherWorkRunning() then return end
    if not Core.HasPermission("impound") then
        return Notify("no_permission", "error")
    end
    vehicle = GetTargetVehicle(vehicle, true)
    if not vehicle then return end
    if not IsVehicleSeatFree(vehicle, -1) then
        return Notify("menu_vehicle_occupied", "error")
    end
    local confirm = lib.alertDialog({
        header = locale("menu_impound"),
        content = locale("menu_impound_confirm", GetPlate(vehicle)),
        centered = true,
        cancel = true,
    })
    if confirm ~= "confirm" then return end
    Busy = true
    local netId = GetNetId(vehicle)
    local cfg = Config.Impound
    BeginScene()

    lib.callback.await("pls_mechanic:server:menu:begin", false, "impound", netId)
    for _, phase in ipairs(cfg.phases) do
        if not DoesEntityExist(vehicle) then
            return Finish("no_vehicle", "error")
        end
        local pos, heading = ImpoundSpot(vehicle, phase.spot)
        Anim.WalkAround(vehicle, pos, heading, 8000, IsCancelled)
        if IsCancelled() then
            return Finish("cancelled", "error")
        end
        Anim.Face(vehicle)
        if not RunPhase(phase, cfg.duration, vehicle) then
            return Finish("cancelled", "error")
        end
    end

    local ok, err = lib.callback.await("pls_mechanic:server:menu:impound", false, netId)
    if not ok then
        return Finish(err or "menu_impound_failed", "error")
    end
    Finish("menu_impound_done", "success")
end

--[[
  ______ _       _   _              _
 |  ____| |     | | | |            | |
 | |__  | | __ _| |_| |__   ___  __| |
 |  __| | |/ _` | __| '_ \ / _ \/ _` |
 | |    | | (_| | |_| |_) |  __/ (_| |
 |_|    |_|\__,_|\__|_.__/ \___|\__,_|
]]--

-- Flatbed the player sits in or the closest one. Returns vehicle, config
function Menu.FindFlatbed()
    if cache.vehicle and GetFlatbedConfig(cache.vehicle) then
        return cache.vehicle, GetFlatbedConfig(cache.vehicle)
    end
    local coords = GetEntityCoords(cache.ped)
    local best, bestConfig, bestDistance = nil, nil, nil
    for _, v in pairs(lib.getNearbyVehicles(coords, Config.Towing.maxDistance, true)) do
        local data = GetFlatbedConfig(v.vehicle)
        if data then
            local distance = #(coords - v.coords)
            if not bestDistance or distance < bestDistance then
                best, bestConfig, bestDistance = v.vehicle, data, distance
            end
        end
    end
    return best, bestConfig
end

local function FindTowTarget(flatbed, data)
    local point = GetOffsetFromEntityInWorldCoords(flatbed, data.search.x, data.search.y, data.search.z)
    local best, bestDistance = nil, nil
    for _, v in pairs(lib.getNearbyVehicles(point, data.radius or 4.5, true)) do
        if v.vehicle ~= flatbed and not IsEntityAttached(v.vehicle) and not GetFlatbedConfig(v.vehicle) then
            local distance = #(point - v.coords)
            if not bestDistance or distance < bestDistance then
                best, bestDistance = v.vehicle, distance
            end
        end
    end
    return best
end

local function FlatbedBone(flatbed, data)
    local bone = data.bone and GetEntityBoneIndexByName(flatbed, data.bone) or -1
    return bone == -1 and 0 or bone
end

-- Offset of the attach bone from the flatbed origin
local function BoneOffset(flatbed, bone)
    if bone == 0 then return vector3(0.0, 0.0, 0.0) end
    local pos = GetWorldPositionOfEntityBone(flatbed, bone)
    return GetOffsetFromEntityGivenWorldCoords(flatbed, pos.x, pos.y, pos.z)
end

local function AttachAt(vehicle, flatbed, bone, offset, heading)
    AttachEntityToEntity(vehicle, flatbed, bone, offset.x, offset.y, offset.z, 0.0, 0.0, heading, false, false, false, false, 2, true)
end

local function AttachToFlatbed(flatbed, data, vehicle)
    local min = GetModelDimensions(GetEntityModel(vehicle))
    local rot = data.rotation or vec3(0.0, 0.0, 0.0)
    AttachEntityToEntity(vehicle, flatbed, FlatbedBone(flatbed, data), data.offset.x, data.offset.y, data.offset.z - min.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
end

-- Unload spot behind the truck on the ground: never closer than the rear edge of the flatbed + the vehicle's front,
-- so the vehicle can't end up inside the bed (long vehicles, custom flatbeds). Returns coords, heading
local function UnloadSpot(flatbed, data, vehicle)
    local flatMin = GetModelDimensions(GetEntityModel(flatbed))
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local detach = data.detach or vec3(0.0, -9.0, 0.0)
    local y = math.min(detach.y, flatMin.y - max.y - UNLOAD_GAP)
    local pos = GetOffsetFromEntityInWorldCoords(flatbed, detach.x, y, detach.z)
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 3.0, false)
    return vector3(pos.x, pos.y, (found and groundZ or pos.z) - min.z), GetEntityHeading(flatbed)
end

-- Another vehicle stands on the unload spot
local function UnloadSpotBlocked(spot, vehicle, flatbed)
    local _, max = GetModelDimensions(GetEntityModel(vehicle))
    for _, v in pairs(lib.getNearbyVehicles(spot, math.max(max.x, max.y), true)) do
        if v.vehicle ~= vehicle and v.vehicle ~= flatbed then
            return true
        end
    end
    return false
end

-- Vehicle is put on the ground behind the truck at once (no sliding through the bed)
local function PlaceBehind(vehicle, spot, heading)
    DetachEntity(vehicle, true, true)
    SetEntityCoords(vehicle, spot.x, spot.y, spot.z, false, false, false, false)
    SetEntityHeading(vehicle, heading)
    SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
    SetVehicleOnGroundProperly(vehicle)
end

-- Relative attach offset + heading of the vehicle standing on the ground behind the truck (start of loading)
local function GroundOffset(flatbed, vehicle, bone)
    local boneOffset = BoneOffset(flatbed, bone)
    local world = GetEntityCoords(vehicle)
    local heading = GetEntityHeading(vehicle) - GetEntityHeading(flatbed)
    heading = (heading + 180.0) % 360.0 - 180.0
    local offset = GetOffsetFromEntityGivenWorldCoords(flatbed, world.x, world.y, world.z) - boneOffset
    return offset, heading
end

-- Operator spot at the flatbed controls, facing the truck
local function ControlsPosition(flatbed, data)
    local min, max = GetModelDimensions(GetEntityModel(flatbed))
    local controls = data.controls or vec3(-1.0, -1.2, 0.0)
    local left = controls.x < 0.0
    local pos = GetOffsetFromEntityInWorldCoords(flatbed, left and (min.x - 0.45) or (max.x + 0.45), controls.y, 0.0)
    return pos, GetEntityHeading(flatbed) + (left and -90.0 or 90.0)
end

-- Spot at the bumper of the vehicle that faces the flatbed, facing the vehicle. Returns pos, heading, bumper point
local function BumperPosition(vehicle, flatbed)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local flatCoords = GetEntityCoords(flatbed)
    local toward = GetOffsetFromEntityGivenWorldCoords(vehicle, flatCoords.x, flatCoords.y, flatCoords.z)
    local front = toward.y > 0.0
    local pos = GetOffsetFromEntityInWorldCoords(vehicle, 0.35, front and (max.y + 0.75) or (min.y - 0.75), 0.0)
    local bumper = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, front and max.y or min.y, min.z + 0.35)
    return pos, GetEntityHeading(vehicle) + (front and 180.0 or 0.0), bumper
end

-- Spot next to the bed at the loaded vehicle's rear wheels (straps)
local function StrapPosition(flatbed, data)
    local min, max = GetModelDimensions(GetEntityModel(flatbed))
    local left = not data.controls or data.controls.x < 0.0
    local pos = GetOffsetFromEntityInWorldCoords(flatbed, left and (min.x - 0.35) or (max.x + 0.35), data.offset.y - 1.6, 0.0)
    return pos, GetEntityHeading(flatbed) + (left and -90.0 or 90.0)
end

local function WalkToControls(flatbed, data)
    if cache.vehicle then return end
    local pos, heading = ControlsPosition(flatbed, data)
    Anim.WalkAround(flatbed, pos, heading, 10000, IsCancelled)
end

-- Remote operation from the cab: phases without animation
local function TowPhase(phase, entity, extra)
    extra = extra or {}
    if cache.vehicle then
        extra.anim = false
        extra.prop = false
    end
    return RunPhase(phase, nil, entity, extra)
end

-- Steel winch cable from the bed to the bumper of the vehicle
local function AttachWinchCable(scene, flatbed, data, vehicle, bumper)
    if not Config.Towing.cable then return nil end
    local winch = data.winch or vec3(0.0, 0.0, 1.0)
    local start = GetOffsetFromEntityInWorldCoords(flatbed, winch.x, winch.y, winch.z)
    return AddCable(scene, 1, flatbed, start, vehicle, bumper)
end

-- Vehicle slides from the ground onto the bed while the phase runs (vehicle attached, control needed)
local function WinchSlide(scene, flatbed, data, vehicle, duration)
    local bone = FlatbedBone(flatbed, data)
    local min = GetModelDimensions(GetEntityModel(vehicle))
    local to = vector3(data.offset.x, data.offset.y, data.offset.z - min.z)
    local toHeading = (data.rotation or vec3(0.0, 0.0, 0.0)).z
    local from, fromHeading = GroundOffset(flatbed, vehicle, bone)
    scene.sliding = true
    CreateThread(function()
        local start = GetGameTimer()
        local winch = data.winch or vec3(0.0, 0.0, 1.0)
        while scene.sliding and DoesEntityExist(vehicle) and DoesEntityExist(flatbed) do
            local t = math.min(1.0, (GetGameTimer() - start) / duration)
            local eased = t * t * (3.0 - 2.0 * t)
            AttachAt(vehicle, flatbed, bone, from + (to - from) * eased, fromHeading + (toHeading - fromHeading) * eased)
            if scene.cable and DoesRopeExist(scene.cable) and scene.bumperOffset then
                local winchPos = GetOffsetFromEntityInWorldCoords(flatbed, winch.x, winch.y, winch.z)
                local bumper = GetOffsetFromEntityInWorldCoords(vehicle, scene.bumperOffset.x, scene.bumperOffset.y, scene.bumperOffset.z)
                RopeForceLength(scene.cable, math.max(0.3, #(winchPos - bumper)))
            end
            if t >= 1.0 then break end
            Wait(0)
        end
        scene.sliding = false
    end)
end

local function TowScene()
    local scene = BeginScene()
    scene.onCleanup = function()
        scene.sliding = false
        scene.cable = nil
    end
    return scene
end

local function LoadVehicle(flatbed, data)
    local target = FindTowTarget(flatbed, data)
    if not target then
        return Notify("menu_tow_no_target", "error")
    end
    if not IsVehicleSeatFree(target, -1) then
        return Notify("menu_vehicle_occupied", "error")
    end
    if Config.Towing.blacklistClasses[GetVehicleClass(target)] then
        return Notify("menu_tow_class", "error")
    end
    local targetNet = GetNetId(target)
    if not targetNet then
        return Notify("no_control", "error")
    end

    local phases = Config.Towing.phases
    local scene = TowScene()
    RopeLoadTextures()
    WalkToControls(flatbed, data)
    if not TowPhase(phases.lower, flatbed) then return Abort("cancelled") end

    -- hook the winch cable on the bumper (on foot)
    local pos, heading, bumper = BumperPosition(target, flatbed)
    scene.bumperOffset = GetOffsetFromEntityGivenWorldCoords(target, bumper.x, bumper.y, bumper.z)
    if not cache.vehicle then
        Anim.WalkAround(target, pos, heading, 10000, IsCancelled)
        if IsCancelled() or not TowPhase(phases.hook, target) then return Abort("cancelled") end
    end
    scene.cable = AttachWinchCable(scene, flatbed, data, target, bumper)
    WalkToControls(flatbed, data)
    if IsCancelled() then return Abort("cancelled") end

    if not DoesEntityExist(target) or not Core.RequestControl(target, 3000) then
        return Abort("no_control")
    end
    local ok, err = lib.callback.await("pls_mechanic:server:menu:towAttach", false, GetNetId(flatbed), targetNet)
    if not ok then
        return Abort(err or "no_permission")
    end

    -- winch: the vehicle slides onto the bed (already loaded on the server, cancel only skips the animation)
    local winchDuration = PhaseDuration(phases.winch)
    TowPhase(phases.winch, flatbed, {
        onStart = function()
            WinchSlide(scene, flatbed, data, target, math.floor(winchDuration * 0.9))
        end,
    })
    scene.sliding = false
    if DoesEntityExist(target) then
        AttachToFlatbed(flatbed, data, target)
    end
    RemoveCables(scene)
    scene.cable = nil

    if not cache.vehicle and not IsCancelled() then
        local strapPos, strapHeading = StrapPosition(flatbed, data)
        Anim.WalkAround(flatbed, strapPos, strapHeading, 10000, IsCancelled)
        TowPhase(phases.strap, target)
    end
    Abort("menu_tow_loaded", "success")
end

local function UnloadVehicle(flatbed, data, towedNet)
    local target = NetworkDoesEntityExistWithNetworkId(towedNet) and NetworkGetEntityFromNetworkId(towedNet) or 0
    local exists = target ~= 0 and DoesEntityExist(target)
    local phases = Config.Towing.phases
    BeginScene()

    if exists and not cache.vehicle then
        local strapPos, strapHeading = StrapPosition(flatbed, data)
        Anim.WalkAround(flatbed, strapPos, strapHeading, 10000, IsCancelled)
        if not TowPhase(phases.unstrap, target) then return Abort("cancelled") end
    end
    WalkToControls(flatbed, data)
    if IsCancelled() then return Abort("cancelled") end
    -- bed released at the controls, nothing is unloaded when cancelled here
    if not TowPhase(phases.release, flatbed) then return Abort("cancelled") end

    local spot, heading
    if exists then
        spot, heading = UnloadSpot(flatbed, data, target)
        if UnloadSpotBlocked(spot, target, flatbed) then
            return Abort("menu_tow_no_space")
        end
        if not Core.RequestControl(target, 3000) then
            return Abort("no_control")
        end
    end
    local ok, err = lib.callback.await("pls_mechanic:server:menu:towDetach", false, GetNetId(flatbed))
    if not ok then
        return Abort(err or "no_permission")
    end
    -- vehicle stands on the ground behind the truck at once (no sliding through the bed)
    if exists and DoesEntityExist(target) then
        PlaceBehind(target, spot, heading)
    end
    Abort("menu_tow_unloaded", "success")
end

-- Loads the vehicle behind the flatbed or unloads the loaded one
function Menu.Tow(flatbed)
    if not CanUseActions() or OtherWorkRunning() then return end
    if not Core.HasPermission("tow") then
        return Notify("no_permission", "error")
    end
    local data
    if flatbed then
        data = GetFlatbedConfig(flatbed)
    else
        flatbed, data = Menu.FindFlatbed()
    end
    if not flatbed or not data or not GetNetId(flatbed) then
        return Notify("menu_tow_no_flatbed", "error")
    end
    Busy = true
    local towedNet = Entity(flatbed).state.pls_towed
    if towedNet then
        UnloadVehicle(flatbed, data, towedNet)
    else
        LoadVehicle(flatbed, data)
    end
    Busy = false
end

--[[
      _                         _____ _             _
     | |                       / ____| |           | |
     | |_   _ _ __ ___  _ __  | (___ | |_ __ _ _ __| |_
 _   | | | | | '_ ` _ \| '_ \  \___ \| __/ _` | '__| __|
| |__| | |_| | | | | | | |_) | ____) | || (_| | |  | |_
 \____/ \__,_|_| |_| |_| .__/ |_____/ \__\__,_|_|   \__|
                       | |
                       |_|
]]--

-- Clamp point in the engine bay (world coords), side = -1 / 1 for the two clamps
local function ClampPoint(vehicle, side)
    local bone = GetEntityBoneIndexByName(vehicle, "engine")
    local base = bone ~= -1 and GetWorldPositionOfEntityBone(vehicle, bone) or GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.4, 0.2)
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, base.x, base.y, base.z)
    return GetOffsetFromEntityInWorldCoords(vehicle, offset.x + side * 0.18, offset.y, offset.z + 0.3)
end

-- Clamp connected: sparks + jumper cable from the booster to the engine bay
local function ConnectClamp(scene, vehicle, side)
    CreateThread(function()
        Sparks(vehicle, Config.JumpStart.sparks)
        if not Config.JumpStart.cables or not scene.booster or not DoesEntityExist(scene.booster) or not DoesEntityExist(vehicle) then return end
        local start = GetOffsetFromEntityInWorldCoords(scene.booster, side * 0.08, 0.0, 0.18)
        -- the booster is frozen on the ground: the clamp end is a frozen anchor too, the rope never pulls the vehicle
        local clamp = ClampPoint(vehicle, side)
        local anchor = CableAnchor(scene, clamp)
        if not anchor then return end
        AddCable(scene, 0, scene.booster, start, anchor, clamp)
    end)
end

function Menu.JumpStart(vehicle)
    if not CanUseActions() or OtherWorkRunning() then return end
    vehicle = GetTargetVehicle(vehicle, true)
    if not vehicle then return end
    local netId = GetNetId(vehicle)
    local data = Core.GetVehicleData(vehicle) or lib.callback.await("pls_mechanic:server:vehicles:init", false, netId, GetVehicleClass(vehicle))
    if not data or not data.core or data.core.battery == nil then
        return Notify("vehicle_excluded", "error")
    end
    local mission = Entity(vehicle).state.pls_mission
    local state = Utils.GetPartState(data.core.battery)
    if not (mission and mission.type == "jumpstart") and state ~= "critical" and state ~= "failed" then
        return Notify("menu_jump_not_needed", "error")
    end

    Busy = true
    local cfg = Config.JumpStart
    local scene = BeginScene()
    scene.onCleanup = function(cancelled)
        if scene.carry then
            Anim.StopCarry(scene.carry)
            scene.carry = nil
        end
        if scene.booster and DoesEntityExist(scene.booster) then
            if cancelled then
                Anim.DeleteProp(scene.booster)
            else
                Anim.PickUp(scene.booster)
            end
        end
        if DoesEntityExist(vehicle) and (scene.success or scene.hoodOpened) then
            Anim.CloseDoor(vehicle, 4)
        end
    end
    if cfg.cables then
        RopeLoadTextures()
    end

    -- carry the booster to the hood and put it down next to the bumper
    local pos, heading = Core.GetAccessPosition(vehicle, "hood")
    if cfg.booster then
        scene.carry = Anim.Carry(cfg.booster)
    end
    Anim.WalkAround(vehicle, pos, heading, 8000, IsCancelled)
    if IsCancelled() or not DoesEntityExist(vehicle) then
        return Finish("cancelled", "error")
    end
    if scene.carry then
        scene.booster = Anim.PutDown(nil, GetOffsetFromEntityInWorldCoords(cache.ped, 0.6, 0.3, 0.0), GetEntityHeading(cache.ped) + 90.0)
        scene.carry = nil
        Anim.Face(vehicle)
    end
    scene.hoodOpened = Anim.OpenDoor(vehicle, 4)
    if IsCancelled() then
        return Finish("cancelled", "error")
    end

    -- timed part: clamps, charging, first (weak) start attempt
    lib.callback.await("pls_mechanic:server:menu:begin", false, "jumpStart", netId)
    local clamp = 0
    for _, phase in ipairs(cfg.phases) do
        local done = RunPhase(phase, cfg.duration, vehicle, {
            onEnd = phase.clamp and function(completed)
                if completed then
                    clamp = clamp + 1
                    ConnectClamp(scene, vehicle, clamp == 1 and 1 or -1)
                end
            end or nil,
        })
        if not done then
            return Finish("cancelled", "error")
        end
    end

    local ok, err = lib.callback.await("pls_mechanic:server:menu:jumpStart", false, netId)
    if ok then
        scene.success = true
        local canStart = cfg.startEngine and DoesEntityExist(vehicle) and Core.RequestControl(vehicle, 1500)
        RunPhase(cfg.start, nil, vehicle, {
            onStart = function()
                if canStart and DoesEntityExist(vehicle) then
                    SetVehicleEngineOn(vehicle, true, false, true)
                end
            end,
        })
    end
    RunPhase(cfg.disconnect, nil, vehicle)
    RemoveCables(scene)
    if not ok then
        return Finish(err or "no_permission", "error")
    end
    -- the job is done, a cancel in the last phases only skips them
    scene.cancelled = false
    Finish("menu_jump_done", "success")
end

--[[
  __  __
 |  \/  |
 | \  / | ___ _ __  _   _
 | |\/| |/ _ \ '_ \| | | |
 | |  | |  __/ | | | |_| |
 |_|  |_|\___|_| |_|\__,_|
]]--

local function RunAction(fn, ...)
    local args = { ... }
    CreateThread(function()
        fn(table.unpack(args))
    end)
end

function Menu.Open()
    if not CanUseActions() or Core.Nui.IsOpen() then return end
    if not HasAccess() then
        return Notify("not_on_duty", "error")
    end
    local actions = Config.MechanicMenu.actions
    local vehicle = Core.GetClosestVehicle(Config.MechanicMenu.vehicleDistance)
    local plate = vehicle and GetPlate(vehicle) or nil
    local vehicleDesc = plate and locale("menu_vehicle_desc", plate) or locale("menu_no_vehicle_desc")
    -- ox_lib cache.vehicle is false (not nil) on foot
    local inVehicle = cache.vehicle and true or false
    local footDesc = inVehicle and locale("menu_on_foot") or vehicleDesc
    local options = {}

    if actions.diagnose and Diagnostics and Diagnostics.Start and Core.HasPermission("diagnose") then
        table.insert(options, {
            title = locale("menu_diagnose"),
            description = vehicleDesc,
            icon = "fa-solid fa-stethoscope",
            disabled = vehicle == nil,
            onSelect = function() RunAction(Diagnostics.Start, vehicle) end,
        })
        if vehicle and Diagnostics.CanReopen and Diagnostics.CanReopen(vehicle) then
            table.insert(options, {
                title = locale("diag_reopen_target"),
                description = vehicleDesc,
                icon = "fa-solid fa-clipboard-list",
                onSelect = function() RunAction(Diagnostics.Reopen, vehicle) end,
            })
        end
    end
    if actions.servicebook and ServiceBook and ServiceBook.Open and Core.HasPermission("diagnose") then
        table.insert(options, {
            title = locale("menu_servicebook"),
            description = vehicleDesc,
            icon = "fa-solid fa-book",
            disabled = plate == nil,
            onSelect = function() RunAction(ServiceBook.Open, plate, vehicle) end,
        })
    end
    if actions.bill and Billing and Billing.OpenCreate and Core.HasPermission("billing") then
        table.insert(options, {
            title = locale("menu_bill"),
            description = plate and locale("menu_vehicle_desc", plate) or nil,
            icon = "fa-solid fa-file-invoice-dollar",
            onSelect = function() RunAction(Billing.OpenCreate, plate) end,
        })
    end
    if actions.missions and Config.Missions and Config.Missions.enabled and Missions and Missions.OpenMenu and Core.HasPermission("missions") then
        table.insert(options, {
            title = locale("menu_missions"),
            description = Missions.GetActive and Missions.GetActive() and locale("menu_missions_active") or nil,
            icon = "fa-solid fa-route",
            onSelect = function() RunAction(Missions.OpenMenu) end,
        })
    end
    if Core.HasPermission("tow") then
        if actions.push then
            table.insert(options, {
                title = locale("menu_push"),
                description = footDesc,
                icon = "fa-solid fa-hands",
                disabled = vehicle == nil or inVehicle,
                onSelect = function() RunAction(Menu.Push, vehicle) end,
            })
        end
        if actions.flip then
            table.insert(options, {
                title = locale("menu_flip"),
                description = footDesc,
                icon = "fa-solid fa-rotate",
                disabled = vehicle == nil or inVehicle,
                onSelect = function() RunAction(Menu.Flip, vehicle) end,
            })
        end
        if actions.unlock then
            local count = Core.CountTool("slim_jim")
            table.insert(options, {
                title = locale("menu_unlock"),
                description = locale("menu_unlock_desc", Core.GetItemLabel(Utils.Item("slim_jim")), count),
                icon = "fa-solid fa-unlock",
                disabled = vehicle == nil or inVehicle or count < 1,
                onSelect = function() RunAction(Menu.Unlock, vehicle) end,
            })
        end
        if actions.tow then
            local flatbed = Menu.FindFlatbed()
            local loaded = flatbed and Entity(flatbed).state.pls_towed
            table.insert(options, {
                title = locale(loaded and "menu_tow_unload" or "menu_tow_load"),
                description = not flatbed and locale("menu_tow_no_flatbed") or nil,
                icon = "fa-solid fa-truck-ramp-box",
                disabled = flatbed == nil,
                onSelect = function() RunAction(Menu.Tow, flatbed) end,
            })
        end
    end
    if actions.impound and Core.HasPermission("impound") then
        table.insert(options, {
            title = locale("menu_impound"),
            description = footDesc,
            icon = "fa-solid fa-warehouse",
            disabled = vehicle == nil or inVehicle,
            onSelect = function() RunAction(Menu.Impound, vehicle) end,
        })
    end

    if #options == 0 then
        return Notify("no_permission", "error")
    end
    lib.registerContext({
        id = MENU_ID,
        title = locale("menu_title"),
        options = options,
    })
    lib.showContext(MENU_ID)
end

--[[
  _____        _
 |  __ \      | |
 | |  | |_   _| |_ _   _
 | |  | | | | | __| | | |
 | |__| | |_| | |_| |_| |
 |_____/ \__,_|\__|\__, |
                    __/ |
                   |___/
 Radial item + keybind only while on duty / inside own illegal workshop
]]--

local function RefreshAccess(duty)
    local available = HasAccess(duty)
    if not Config.MechanicMenu.radial then return end
    if available and not RadialAdded then
        lib.addRadialItem({
            id = RADIAL_ID,
            icon = "wrench",
            label = locale("menu_title"),
            onSelect = function() Menu.Open() end,
        })
        RadialAdded = true
    elseif not available and RadialAdded then
        lib.removeRadialItem(RADIAL_ID)
        RadialAdded = false
    end
end

if Config.MechanicMenu.keybind then
    lib.addKeybind({
        name = "pls_mechanic_menu",
        description = locale("menu_keybind"),
        defaultKey = Config.Keys.mechanicMenu,
        onPressed = function()
            if not HasAccess() then
                -- mechanics off duty get a hint, other players nothing
                if Core.IsMechanic() then Notify("not_on_duty", "error") end
                return
            end
            Menu.Open()
        end,
    })
end

AddStateBagChangeHandler("pls_mechanic_duty", ("player:%s"):format(cache.serverId), function(_, _, value)
    RefreshAccess(value or false)
end)

Core.OnShopsUpdated(function()
    RefreshAccess()
end)

-- Access to an illegal workshop depends on the position, checked only for crew members
CreateThread(function()
    while true do
        Wait(1000)
        if Config.MechanicMenu.radial and Core.HasIllegalAccess() then
            RefreshAccess()
        end
    end
end)

--[[
  _______                   _
 |__   __|                 | |
    | | __ _ _ __ __ _  ___| |_
    | |/ _` | '__/ _` |/ _ \ __|
    | | (_| | | | (_| |  __/ |_
    |_|\__,_|_|  \__, |\___|\__|
                  __/ |
                 |___/
 Flatbed load / unload directly on the truck
]]--

VehicleTargetId = BRIDGE.AddGlobalVehicleTarget({
    {
        name = "pls_mechanic_flatbed",
        label = locale("menu_tow_target"),
        icon = "fa-solid fa-truck-ramp-box",
        distance = 4.0,
        canInteract = function(entity)
            return Config.MechanicMenu.actions.tow and GetFlatbedConfig(entity) ~= nil and not Busy and Core.HasPermission("tow")
        end,
        onSelect = function(data)
            local entity = type(data) == "table" and data.entity or data
            RunAction(Menu.Tow, entity)
        end,
    },
})

--[[
  _____ _
 |_   _| |
   | | | |_ ___ _ __ ___  ___
   | | | __/ _ \ '_ ` _ \/ __|
  _| |_| ||  __/ | | | | \__ \
 |_____|\__\___|_| |_| |_|___/
]]--

-- own thread: the item use (ox_inventory export) must not wait for the whole action
Items.Register("slim_jim", function()
    RunAction(Menu.Unlock)
end)

Items.Register("jump_starter", function()
    RunAction(Menu.JumpStart)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Pushing then
        StopPush(Pushing)
    end
    if Scene then
        Scene.cancelled = true
        EndScene()
    end
    if RadialAdded then
        lib.removeRadialItem(RADIAL_ID)
    end
    if VehicleTargetId then
        BRIDGE.RemoveGlobalVehicleTarget(VehicleTargetId)
    end
end)
