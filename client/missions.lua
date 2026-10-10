--[[
  _   _ _____   _____   __  __ _         _
 | \ | |  __ \ / ____| |  \/  (_)       (_)
 |  \| | |__) | |      | \  / |_ ___ ___ _  ___  _ __  ___
 | . ` |  ___/| |      | |\/| | / __/ __| |/ _ \| '_ \/ __|
 | |\  | |    | |____  | |  | | \__ \__ \ | (_) | | | \__ \
 |_| \_|_|     \_____| |_|  |_|_|___/___/_|\___/|_| |_|___/

 Mission menu, blips, vehicle setup (owner applies native damage), NPC owner (greets, watches, pays),
 mission action scenes (tyre change, refuel, scrapping) and completion checks.
]]--

Missions = {}

local MENU_ID = "pls_mechanic_missions"
local SETUP_DISTANCE = 90.0     -- owner applies damage / spawns NPC when collision is surely loaded
local TYPE_ORDER = { "tow", "jumpstart", "tyre", "refuel", "scrap" }

local Active = nil      -- current mission (see server ClientData)
local Blip = nil
local DropBlip = nil
local Npc = nil
local NpcState = {}     -- { greeted, watching, waiting, acting }
local Busy = false
local TargetId = nil
local Scene = nil       -- running action scene { cancelled, objects, onCleanup }

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

local function TypeLabel(missionType)
    return locale("mission_type_"..missionType)
end

local function CreateBlip(coords, settings, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, settings.sprite)
    SetBlipColour(blip, settings.color)
    SetBlipScale(blip, settings.scale)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, settings.route == true)
    SetBlipRouteColour(blip, settings.color)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function ClearBlips()
    if Blip and DoesBlipExist(Blip) then RemoveBlip(Blip) end
    if DropBlip and DoesBlipExist(DropBlip) then RemoveBlip(DropBlip) end
    Blip, DropBlip = nil, nil
end

local function DeleteNpc(ped)
    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end
end

-- Mission vehicle entity when it exists on this client
local function GetMissionVehicle()
    if not Active or not Active.netId or not NetworkDoesEntityExistWithNetworkId(Active.netId) then return nil end
    local vehicle = NetworkGetEntityFromNetworkId(Active.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

local function IsMissionVehicle(entity, missionType)
    if not Active or not Active.ready or Busy then return false end
    local state = Entity(entity).state.pls_mission
    return state ~= nil and state.id == Active.id and state.owner == cache.serverId and (not missionType or state.type == missionType)
end

-- Position next to a vehicle bone facing the vehicle
local function PositionAtBone(vehicle, boneName)
    local bone = GetEntityBoneIndexByName(vehicle, boneName)
    if bone == -1 then return nil end
    local world = GetWorldPositionOfEntityBone(vehicle, bone)
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
    local side = offset.x < 0 and -1 or 1
    local pos = GetOffsetFromEntityInWorldCoords(vehicle, offset.x + side * 0.8, offset.y, 0.0)
    return pos, GetEntityHeading(vehicle) + (side < 0 and -90.0 or 90.0)
end

local function PlayPedAnim(ped, anim, flag)
    if not anim or not DoesEntityExist(ped) then return end
    lib.requestAnimDict(anim.dict)
    TaskPlayAnim(ped, anim.dict, anim.clip, 4.0, -4.0, anim.time or 3000, flag or 48, 0, false, false, false)
    RemoveAnimDict(anim.dict)
end

--[[
   _____
  / ____|
 | (___   ___ ___ _ __   ___
  \___ \ / __/ _ \ '_ \ / _ \
  ____) | (_|  __/ | | |  __/
 |_____/ \___\___|_| |_|\___|

 Action scene: Config.Keys.cancel (shared cancel key of the mechanic menu) or the progress cancel stops it.
 scene.objects = props left on the ground { [object] = "pickup" | "delete" }, "pickup" ones are picked up
 with an animation when the action succeeded, everything else is deleted.
]]--

local function IsCancelled()
    return Scene == nil or Scene.cancelled == true
end

local function BeginScene()
    Scene = { cancelled = false, objects = {} }
    local scene = Scene
    if Menu and Menu.SetCancelHandler then
        Menu.SetCancelHandler(function()
            scene.cancelled = true
        end)
    end
    return scene
end

local function EndScene()
    local scene = Scene
    if not scene then return end
    Scene = nil
    if Menu and Menu.SetCancelHandler then
        Menu.SetCancelHandler(nil)
    end
    if scene.cancelled then
        Anim.Cleanup()
    end
    if scene.onCleanup then
        local ok, err = pcall(scene.onCleanup, scene.cancelled)
        if not ok then print("[pls_mechanic] mission scene cleanup error: "..tostring(err)) end
    end
    for object, mode in pairs(scene.objects) do
        if mode == "pickup" and not scene.cancelled then
            Anim.PickUp(object)
        else
            Anim.DeleteProp(object)
        end
    end
    scene.objects = {}
end

local function Track(scene, object, mode)
    if object then scene.objects[object] = mode or "delete" end
    return object
end

local function PickUpTracked(scene, object)
    if not object then return end
    scene.objects[object] = nil
    Anim.PickUp(object)
end

local function PhaseDuration(phase, total)
    if phase.duration then return phase.duration end
    return math.max(500, math.floor((total or 0) * (phase.share or 0)))
end

-- One config phase with Anim.Phase (vehicle = "vehicle" entity of sounds / particles). extra overrides options.
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
        opts[key] = value
    end
    return Anim.Phase(opts) == true and not IsCancelled()
end

-- Smoothly raises (height > 0) or lowers (height = 0) the frozen vehicle standing on the jack
local function LiftVehicle(scene, vehicle, height, duration)
    scene.liftToken = (scene.liftToken or 0) + 1
    local token = scene.liftToken
    CreateThread(function()
        local from = scene.lifted or 0.0
        local start = GetGameTimer()
        while scene.liftToken == token and scene.basePos and DoesEntityExist(vehicle) do
            local t = math.min(1.0, (GetGameTimer() - start) / math.max(duration, 1))
            local z = from + (height - from) * t
            SetEntityCoordsNoOffset(vehicle, scene.basePos.x, scene.basePos.y, scene.basePos.z + z, false, false, false)
            scene.lifted = z
            if t >= 1.0 then break end
            Wait(0)
        end
    end)
end

local function ReleaseLift(scene, vehicle)
    scene.liftToken = (scene.liftToken or 0) + 1
    if scene.basePos and DoesEntityExist(vehicle) then
        SetEntityCoordsNoOffset(vehicle, scene.basePos.x, scene.basePos.y, scene.basePos.z, false, false, false)
        FreezeEntityPosition(vehicle, false)
        SetVehicleOnGroundProperly(vehicle)
    end
    scene.basePos, scene.lifted = nil, nil
end

--[[
  _   _ _____   _____
 | \ | |  __ \ / ____|
 |  \| | |__) | |
 | . ` |  ___/| |
 | |\  | |    | |____
 |_| \_|_|     \_____|
 Owner of the car (local ped, only for the mission mechanic): waits, greets the mechanic,
 watches him work, walks to him and pays after the job.
]]--

local function SpawnNpc(vehicle)
    if not Active.npc or Npc then return end
    local model = joaat(Active.npc.model)
    if not IsModelValid(model) then return end
    lib.requestModel(model)
    local _, max = GetModelDimensions(GetEntityModel(vehicle))
    local pos = GetOffsetFromEntityInWorldCoords(vehicle, max.x + 1.3, 0.8, 0.0)
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 2.0, false)
    local vehCoords = GetEntityCoords(vehicle)
    local heading = GetHeadingFromVector_2d(vehCoords.x - pos.x, vehCoords.y - pos.y)
    Npc = CreatePed(4, model, pos.x, pos.y, found and groundZ or pos.z, heading, false, false)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(Npc) then
        Npc = nil
        return
    end
    NpcState = {}
    SetEntityAsMissionEntity(Npc, true, true)
    SetBlockingOfNonTemporaryEvents(Npc, true)
    SetPedFleeAttributes(Npc, 0, false)
    SetPedCanRagdollFromPlayerImpact(Npc, false)
    SetEntityInvincible(Npc, true)
    if Active.npc.scenario then
        TaskStartScenarioInPlace(Npc, Active.npc.scenario, 0, true)
    end
end

-- Owner turns to the arriving mechanic, waves and goes back to waiting
local function NpcGreet(ped)
    local cfg = Config.Missions.npc
    NpcState.acting = true
    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(ped, cache.ped, 1200)
    Wait(1200)
    if cfg.greet and DoesEntityExist(ped) then
        PlayPedAnim(ped, cfg.greet)
        Wait(cfg.greet.time or 2500)
    end
    if Npc == ped and DoesEntityExist(ped) then
        local scenario = (Busy and cfg.waiting) or (Active and Active.npc and Active.npc.scenario)
        if scenario then
            TaskStartScenarioInPlace(ped, scenario, 0, true)
        end
        NpcState.waiting = Busy and cfg.waiting ~= nil
    end
    NpcState.acting = false
    NpcState.watching = nil
end

-- Called every second of the mission loop
local function UpdateNpc()
    local ped = Npc
    if not ped or not DoesEntityExist(ped) or NpcState.acting then return end
    local cfg = Config.Missions.npc
    local distance = #(GetEntityCoords(cache.ped) - GetEntityCoords(ped))
    if not NpcState.greeted and distance <= (cfg.greetDistance or 15.0) and not cache.vehicle then
        NpcState.greeted = true
        CreateThread(function() NpcGreet(ped) end)
        return
    end
    local watch = distance <= (cfg.watchDistance or 25.0)
    if watch ~= NpcState.watching then
        NpcState.watching = watch
        if watch then
            TaskLookAtEntity(ped, cache.ped, -1, 2048, 3)
        else
            TaskClearLookAt(ped)
        end
    end
    -- impatient while the mechanic works, back to the own scenario afterwards
    local working = Busy or (Menu and Menu.IsBusy and Menu.IsBusy()) or false
    if cfg.waiting and working ~= (NpcState.waiting == true) then
        NpcState.waiting = working
        local scenario = working and cfg.waiting or (Active and Active.npc and Active.npc.scenario)
        ClearPedTasks(ped)
        if scenario then
            TaskStartScenarioInPlace(ped, scenario, 0, true)
        end
        NpcState.watching = nil
    end
end

-- Mechanic takes the money from the owner (only when free and on foot)
local function TakePayment(ped)
    local take = Config.Missions.npc.take
    if not take or cache.vehicle or Busy or (Menu and Menu.IsBusy and Menu.IsBusy()) or Anim.IsBusy() then return false end
    if #(GetEntityCoords(cache.ped) - GetEntityCoords(ped)) > 2.5 then return false end
    Anim.Face(ped)
    Anim.Play(take)
    return true
end

local function NpcThanks(ped)
    if not ped or not DoesEntityExist(ped) then return end
    CreateThread(function()
        local cfg = Config.Missions.npc
        ClearPedTasks(ped)
        TaskLookAtEntity(ped, cache.ped, 10000, 2048, 3)
        -- walk to the mechanic when he is around
        if not cache.vehicle and #(GetEntityCoords(ped) - GetEntityCoords(cache.ped)) < 20.0 then
            TaskGoToEntity(ped, cache.ped, 6000, 1.3, 1.0, 1073741824, 0)
            local timeout = GetGameTimer() + 6000
            while DoesEntityExist(ped) and #(GetEntityCoords(ped) - GetEntityCoords(cache.ped)) > 1.6 and GetGameTimer() < timeout do
                Wait(200)
            end
        end
        if not DoesEntityExist(ped) then return end
        TaskTurnPedToFaceEntity(ped, cache.ped, 1000)
        Wait(1000)
        -- hands over the money
        local pay = cfg.pay
        if pay and DoesEntityExist(ped) and #(GetEntityCoords(ped) - GetEntityCoords(cache.ped)) < 2.5 then
            local cash = nil
            local model = pay.prop and joaat(pay.prop.model)
            if model and IsModelValid(model) then
                lib.requestModel(model)
                local coords = GetEntityCoords(ped)
                cash = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
                SetModelAsNoLongerNeeded(model)
                local pos, rot = pay.prop.pos, pay.prop.rot
                AttachEntityToEntity(cash, ped, GetPedBoneIndex(ped, pay.prop.bone or 28422), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
            end
            PlayPedAnim(ped, pay)
            if not TakePayment(ped) then
                Wait(pay.time or 1800)
            end
            if cash and DoesEntityExist(cash) then
                DeleteEntity(cash)
            end
        end
        if cfg.thanks and DoesEntityExist(ped) then
            PlayPedAnim(ped, { dict = cfg.thanks.dict, clip = cfg.thanks.clip, time = 3000 })
            Wait(3000)
        end
        if not DoesEntityExist(ped) then return end
        TaskClearLookAt(ped)
        SetEntityInvincible(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
        TaskWanderStandard(ped, 10.0, 10)
        Wait(20000)
        DeleteNpc(ped)
    end)
end

--[[
  __      __  _     _      _
  \ \    / / | |   (_)    | |
   \ \  / /__| |__  _  ___| | ___
    \ \/ / _ \ '_ \| |/ __| |/ _ \
     \  /  __/ | | | | (__| |  __/
      \/ \___|_| |_|_|\___|_|\___|
]]--

-- Nearest road side from mission location. Returns coords, heading
local function ResolveSpawn(anchor)
    local base = vector3(anchor.x, anchor.y, anchor.z)
    if not Config.Missions.snapToRoad then
        return base, anchor.w
    end
    local found, node, nodeHeading = GetClosestVehicleNodeWithHeading(base.x, base.y, base.z, 1, 3.0, 0)
    if not found or #(node - base) > Config.Missions.snapRadius then
        return base, anchor.w
    end
    local ok, side = GetRoadBoundaryUsingHeading(node.x, node.y, node.z, nodeHeading)
    if ok and side then
        local distance = #(side.xy - node.xy)
        if distance > 1.5 and distance < 20.0 then
            local dir = (side.xy - node.xy) / distance
            local pos = side.xy - dir * 1.4
            return vector3(pos.x, pos.y, node.z), nodeHeading
        end
    end
    return node, nodeHeading
end

local function RequestSpawn()
    local mission = Active
    mission.spawning = true
    local coords, heading = ResolveSpawn(mission.anchor)
    local ok, result = lib.callback.await("pls_mechanic:server:missions:spawn", false, mission.id, { x = coords.x, y = coords.y, z = coords.z }, heading)
    if Active ~= mission then return end
    mission.spawning = false
    if ok then
        mission.netId = result
        return
    end
    mission.spawnFails = (mission.spawnFails or 0) + 1
    if mission.spawnFails >= 3 then
        Notify(result or "mission_spawn_failed", "error")
        lib.callback.await("pls_mechanic:server:missions:cancel", false)
    end
end

local function SetHazards(vehicle, toggle)
    SetVehicleIndicatorLights(vehicle, 0, toggle)
    SetVehicleIndicatorLights(vehicle, 1, toggle)
end

local function ApplyWreck(vehicle, setup)
    SetVehicleDirtLevel(vehicle, 15.0)
    SetVehicleBodyHealth(vehicle, 250.0)
    SetVehicleEngineHealth(vehicle, 150.0)
    for window = 0, 3 do
        SmashVehicleWindow(vehicle, window)
    end
    SetVehicleDoorBroken(vehicle, setup.door or 0, true)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    for _ = 1, 6 do
        local x = min.x + math.random() * (max.x - min.x)
        local y = min.y + math.random() * (max.y - min.y)
        SetVehicleDamage(vehicle, x, y, 0.2, 250.0, 150.0, true)
    end
    local wheels = { 0, 1, 4, 5 }
    for i = 1, math.min(setup.tyres or 1, #wheels) do
        SetVehicleTyreBurst(vehicle, wheels[i], true, 1000.0)
    end
    Config.SetFuel(vehicle, 0.0)
end

-- Owner applies native state of the mission (damage is synced by the entity owner)
local function SetupVehicle(vehicle)
    local mission = Active
    if mission.settingUp then return end
    mission.settingUp = true
    if not Core.RequestControl(vehicle, 3000) then
        mission.settingUp = false
        return
    end
    local setup = mission.setup or {}
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, mission.plate)
    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleEngineOn(vehicle, false, true, true)

    if mission.type == "tow" then
        SetVehicleEngineHealth(vehicle, (setup.engineHealth or 100.0) + 0.0)
        SetVehicleUndriveable(vehicle, true)
        SetVehicleDoorOpen(vehicle, 4, false, false)
        SetHazards(vehicle, true)
    elseif mission.type == "tyre" then
        SetVehicleTyreBurst(vehicle, setup.tyre or 0, true, 1000.0)
        SetHazards(vehicle, true)
    elseif mission.type == "refuel" then
        Config.SetFuel(vehicle, 0.0)
        SetHazards(vehicle, true)
    elseif mission.type == "scrap" then
        ApplyWreck(vehicle, setup)
        SetVehicleUndriveable(vehicle, true)
    elseif mission.type == "jumpstart" then
        SetVehicleDoorOpen(vehicle, 4, false, false)
    end

    SpawnNpc(vehicle)
    mission.ready = true
    TriggerSecureEvent("pls_mechanic:server:missions:ready", mission.id)
    Notify("mission_hint_"..mission.type, "inform")
end

local function Complete(mission)
    mission.completing = true
    local ok, err = lib.callback.await("pls_mechanic:server:missions:complete", false, mission.id)
    if Active ~= mission then return end
    if not ok then
        if err ~= mission.lastError then
            Notify(err or "mission_not_done", "error")
            mission.lastError = err
        end
        SetTimeout(3000, function()
            mission.completing = false
        end)
    end
end

-- Tow: route to drop-off while loaded, finish when unloaded there
local function MonitorTow(vehicle)
    local mission = Active
    local attached = IsEntityAttached(vehicle)
    if attached and not DropBlip and mission.dropOff then
        if Blip and DoesBlipExist(Blip) then SetBlipRoute(Blip, false) end
        DropBlip = CreateBlip(mission.dropOff, Config.Missions.dropOffBlip, locale("mission_blip_dropoff"))
        Notify("mission_tow_dropoff", "inform")
    end
    if not attached and not mission.completing and mission.dropOff then
        if #(GetEntityCoords(vehicle) - vector3(mission.dropOff.x, mission.dropOff.y, mission.dropOff.z)) <= (mission.dropRadius or 15.0) and GetEntitySpeed(vehicle) < 1.0 then
            Complete(mission)
        end
    end
end

-- Tyre: the controlling client reports fixed tyre (repair module quick repair or mission action)
local function MonitorTyre(vehicle)
    local mission = Active
    if mission.completing or NetworkGetEntityOwner(vehicle) ~= cache.playerId then return end
    if not IsVehicleTyreBurst(vehicle, mission.setup.tyre or 0, false) then
        Complete(mission)
    end
end

local function MissionLoop(missionId)
    while Active and Active.id == missionId do
        local mission = Active
        if not mission.netId then
            if not mission.spawning then
                local anchor = vector3(mission.anchor.x, mission.anchor.y, mission.anchor.z)
                if #(GetEntityCoords(cache.ped) - anchor) <= Config.Missions.spawnDistance then
                    RequestSpawn()
                end
            end
        else
            local vehicle = GetMissionVehicle()
            if vehicle then
                if Blip and DoesBlipExist(Blip) then
                    local coords = GetEntityCoords(vehicle)
                    SetBlipCoords(Blip, coords.x, coords.y, coords.z)
                end
                if not mission.ready then
                    if #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) <= SETUP_DISTANCE then
                        SetupVehicle(vehicle)
                    end
                elseif mission.type == "tow" then
                    MonitorTow(vehicle)
                elseif mission.type == "tyre" then
                    MonitorTyre(vehicle)
                end
            end
            UpdateNpc()
        end
        Wait(1000)
    end
end

--[[
   _____
  / ____|
 | (___   ___ ___ _ __   ___  ___
  \___ \ / __/ _ \ '_ \ / _ \/ __|
  ____) | (_|  __/ | | |  __/\__ \
 |_____/ \___\___|_| |_|\___||___/
 Every scene returns true when all phases are done (false = cancelled / vehicle lost).
]]--

-- Jack / spare tyre / old tyre spots on the ground next to the wheel (tyre index 0, 1, 4, 5)
local function WheelSpots(vehicle, tyre)
    local bone = GetEntityBoneIndexByName(vehicle, Utils.WheelBones[tyre] or "wheel_lf")
    local world = bone ~= -1 and GetWorldPositionOfEntityBone(vehicle, bone) or GetEntityCoords(vehicle)
    local wheel = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
    local side = wheel.x < 0 and -1 or 1
    local along = wheel.y > 0 and -1 or 1      -- towards the middle of the vehicle
    return {
        jack = GetOffsetFromEntityInWorldCoords(vehicle, wheel.x + side * 0.1, wheel.y + along * 0.7, 0.0),
        spare = GetOffsetFromEntityInWorldCoords(vehicle, wheel.x + side * 1.35, wheel.y - along * 0.9, 0.0),
        old = GetOffsetFromEntityInWorldCoords(vehicle, wheel.x + side * 1.5, wheel.y + along * 1.1, 0.0),
    }
end

local function TyreScene(vehicle, mission, cfg)
    local scene = BeginScene()
    local tyre = mission.setup.tyre or 0
    local phases, total = cfg.phases, cfg.duration
    local pos, heading = Core.GetAccessPosition(vehicle, "wheel", tyre)
    local spots = WheelSpots(vehicle, tyre)
    scene.onCleanup = function()
        ReleaseLift(scene, vehicle)
    end

    -- bring the new tyre and the jack to the wheel
    Anim.Carry(cfg.tyreProp)
    Anim.WalkAround(vehicle, pos, heading, 10000, IsCancelled)
    if IsCancelled() then return false end
    local spare = Track(scene, Anim.PutDown(nil, spots.spare, heading))
    if cfg.jack and not IsCancelled() then
        Track(scene, Anim.PutDown(cfg.jack, spots.jack, GetEntityHeading(vehicle) + 90.0), "pickup")
    end
    Anim.WalkTo(pos, heading, 4000, IsCancelled)
    if IsCancelled() or not DoesEntityExist(vehicle) then return false end

    -- jack up, unbolt, take the old tyre off
    if (cfg.jackLift or 0) > 0 and Core.RequestControl(vehicle, 2000) then
        FreezeEntityPosition(vehicle, true)
        scene.basePos = GetEntityCoords(vehicle)
    end
    local jackDuration = PhaseDuration(phases.jack, total)
    if not RunPhase(phases.jack, total, vehicle, {
        keepAnim = true,
        onStart = function()
            if scene.basePos then LiftVehicle(scene, vehicle, cfg.jackLift, math.floor(jackDuration * 0.8)) end
        end,
    }) then return false end
    if not RunPhase(phases.loosen, total, vehicle, { keepAnim = true }) then return false end
    if not RunPhase(phases.remove, total, vehicle) then return false end

    -- old tyre aside, new tyre on
    Anim.Carry(cfg.tyreProp)
    Track(scene, Anim.PutDown(nil, spots.old, heading), "pickup")
    if IsCancelled() then return false end
    PickUpTracked(scene, spare)
    Anim.Carry(cfg.tyreProp)
    Anim.WalkTo(pos, heading, 5000, IsCancelled)
    if IsCancelled() or not DoesEntityExist(vehicle) then return false end
    if not RunPhase(phases.mount, total, vehicle, { keepAnim = true }) then return false end
    if not RunPhase(phases.tighten, total, vehicle, { keepAnim = true }) then return false end

    -- lower the vehicle
    local lowerDuration = PhaseDuration(phases.lower, total)
    if not RunPhase(phases.lower, total, vehicle, {
        onStart = function()
            if scene.basePos then LiftVehicle(scene, vehicle, 0.0, math.floor(lowerDuration * 0.8)) end
        end,
    }) then return false end
    ReleaseLift(scene, vehicle)
    return true
end

local function RefuelScene(vehicle, cfg)
    local scene = BeginScene()
    local phases, total = cfg.phases, cfg.duration
    local pos, heading = PositionAtBone(vehicle, "petrolcap")
    if not pos then
        pos, heading = Core.GetAccessPosition(vehicle, "wheel", 4)
    end

    -- jerry can in one hand to the filler, put it down
    Anim.Carry(cfg.can, false)
    Anim.WalkAround(vehicle, pos, heading, 10000, IsCancelled)
    if IsCancelled() then return false end
    local can = Track(scene, Anim.PutDown(nil, GetOffsetFromEntityInWorldCoords(cache.ped, -0.5, 0.3, 0.0), heading))
    Anim.WalkTo(pos, heading, 3000, IsCancelled)
    if IsCancelled() or not DoesEntityExist(vehicle) then return false end

    -- cap off, pour, cap on
    if not RunPhase(phases.open, total, vehicle) then return false end
    PickUpTracked(scene, can)
    Anim.WalkTo(pos, heading, 3000, IsCancelled)
    if not RunPhase(phases.pour, total, vehicle) then return false end
    return RunPhase(phases.close, total, vehicle)
end

-- Work spot of a scrap step. Returns coords, heading
local function ScrapSpot(vehicle, spot)
    if spot.access == "door" then
        local pos, heading = PositionAtBone(vehicle, "door_dside_f")
        if pos then return pos, heading end
    elseif spot.access == "wheel" then
        return Core.GetAccessPosition(vehicle, "wheel", spot.wheel == 1 and 1 or spot.wheel == 2 and 4 or spot.wheel == 3 and 5 or 0)
    end
    return Core.GetAccessPosition(vehicle, spot.access == "trunk" and "trunk" or "hood")
end

-- Takes the part off the wreck. Returns true when there was something to take off.
local function DetachPart(vehicle, spot)
    if not DoesEntityExist(vehicle) or not Core.RequestControl(vehicle, 1000) then return false end
    if spot.door then
        if not GetIsDoorValid(vehicle, spot.door) or IsVehicleDoorDamaged(vehicle, spot.door) then return false end
        SetVehicleDoorBroken(vehicle, spot.door, true)
        return true
    end
    if spot.wheel then
        if spot.wheel >= GetVehicleNumberOfWheels(vehicle) then return false end
        BreakOffVehicleWheel(vehicle, spot.wheel, false, true, false, false)
        return true
    end
    return false
end

local function ScrapScene(vehicle, cfg)
    local scene = BeginScene()
    local steps = math.max(1, cfg.steps or 1)
    local stepDuration = math.floor((cfg.duration or 30000) / steps)
    local spots = cfg.spots or {}
    if #spots == 0 then return false end
    local pile = cfg.pile or vec3(-2.6, 0.0, 0.0)

    for i = 1, steps do
        if not DoesEntityExist(vehicle) then return false end
        local spot = spots[((i - 1) % #spots) + 1]
        local pos, heading = ScrapSpot(vehicle, spot)
        Anim.WalkAround(vehicle, pos, heading, 10000, IsCancelled)
        if IsCancelled() then return false end
        for j, phase in ipairs(spot.phases) do
            local nextPhase = spot.phases[j + 1]
            local keep = nextPhase ~= nil and phase.anim == nextPhase.anim
            if not RunPhase(phase, stepDuration, vehicle, { label = locale(phase.label, i, steps), keepAnim = keep }) then
                return false
            end
        end
        -- the part comes off, carry it to the scrap pile
        if DetachPart(vehicle, spot) and spot.part then
            Anim.Carry(spot.part)
            local spotPos = GetOffsetFromEntityInWorldCoords(vehicle, pile.x + ((i % 2) * 0.6), pile.y + (i - 2) * 0.5, 0.0)
            Track(scene, Anim.PutDown(nil, spotPos, GetEntityHeading(vehicle) + i * 35.0))
            if IsCancelled() then return false end
        end
    end
    return true
end

--[[
                _   _
     /\        | | (_)
    /  \   ___| |_ _  ___  _ __  ___
   / /\ \ / __| __| |/ _ \| '_ \/ __|
  / ____ \ (__| |_| | (_) | | | \__ \
 /_/    \_\___|\__|_|\___/|_| |_|___/
]]--

local function CheckRequirements(cfg)
    if cfg.items then
        local ok, list = Core.CheckItems(cfg.items)
        if not ok then
            local missing = {}
            for _, v in pairs(list) do
                if v.have < v.count then
                    table.insert(missing, (v.count - v.have).."x "..v.label)
                end
            end
            Notify("missing_items", "error", table.concat(missing, ", "))
            return false
        end
    end
    if cfg.tools then
        local ok, key = Core.HasTools(cfg.tools)
        if not ok then
            Notify("missing_tool", "error", Core.GetItemLabel(Utils.Item(key)))
            return false
        end
    end
    return true
end

local function RunScene(action, vehicle, mission, cfg)
    if action == "tyre" then
        return TyreScene(vehicle, mission, cfg)
    elseif action == "refuel" then
        return RefuelScene(vehicle, cfg)
    elseif action == "scrap" then
        return ScrapScene(vehicle, cfg)
    end
    return false
end

-- Another scene of the shared animation library is running (mechanic menu action, repair, tuning installation, DLC scene)
local function OtherWorkRunning()
    if (Menu and Menu.IsBusy and Menu.IsBusy()) or (Tuning and Tuning.IsInstalling and Tuning.IsInstalling())
        or (Repair and Repair.IsBusy and Repair.IsBusy()) or Anim.IsBusy() or Core.IsExternalBusy() then
        Notify("repair_busy", "error")
        return true
    end
    return false
end

local function DoAction(action, vehicle)
    if Busy or not Active or not Active.ready or cache.vehicle then return end
    if OtherWorkRunning() then return end
    local mission = Active
    local cfg = Config.Missions.types[action]
    if not CheckRequirements(cfg) then return end
    Busy = true

    local ok, err = lib.callback.await("pls_mechanic:server:missions:actionStart", false, mission.id, action)
    if not ok then
        Busy = false
        return Notify(err or "mission_invalid", "error")
    end

    local done = RunScene(action, vehicle, mission, cfg)
    if not done or not DoesEntityExist(vehicle) then
        if Scene then Scene.cancelled = true end
        EndScene()
        Busy = false
        return Notify("cancelled", "error")
    end

    -- control first, the server finishes the mission right away
    if action ~= "scrap" and not Core.RequestControl(vehicle, 3000) then
        if Scene then Scene.cancelled = true end
        EndScene()
        Busy = false
        return Notify("no_control", "error")
    end
    ok, err = lib.callback.await("pls_mechanic:server:missions:action", false, mission.id, action)
    if ok and DoesEntityExist(vehicle) then
        if action == "tyre" then
            SetVehicleTyreFixed(vehicle, mission.setup.tyre or 0)
            SetHazards(vehicle, false)
        elseif action == "refuel" then
            Config.SetFuel(vehicle, cfg.fuel or 35.0)
            SetHazards(vehicle, false)
        end
    end
    if not ok and Scene then
        Scene.cancelled = true
    end
    -- packs up (old tyre, jack) or removes the scrap pile
    EndScene()
    Busy = false
    if not ok then
        Notify(err or "mission_invalid", "error")
    end
end

--[[
  __  __
 |  \/  |
 | \  / | ___ _ __  _   _
 | |\/| |/ _ \ '_ \| | | |
 | |  | |  __/ | | | |_| |
 |_|  |_|\___|_| |_|\__,_|
]]--

function Missions.GetActive()
    return Active
end

local function StartMission(missionType)
    if Active then
        return Notify("mission_already", "error")
    end
    local ok, result, extra = lib.callback.await("pls_mechanic:server:missions:start", false, missionType)
    if not ok then
        if result == "mission_cooldown" then
            return Notify("mission_cooldown", "error", math.ceil((extra or 0) / 60))
        end
        return Notify(result or "mission_invalid", "error")
    end
    Active = result
    Active.expiresAt = GetGameTimer() + (result.expiresIn or 0) * 1000
    Blip = CreateBlip(Active.anchor, Config.Missions.blip, TypeLabel(Active.type))
    Notify("mission_started", "success", TypeLabel(Active.type))
    CreateThread(function()
        MissionLoop(result.id)
    end)
end

local function CancelMission()
    local confirm = lib.alertDialog({
        header = locale("mission_cancel"),
        content = locale("mission_cancel_confirm"),
        centered = true,
        cancel = true,
    })
    if confirm ~= "confirm" then return end
    local ok, err = lib.callback.await("pls_mechanic:server:missions:cancel", false)
    if not ok then
        Notify(err or "mission_none", "error")
    end
end

local function RewardText(reward)
    if not reward or not reward.money then return "" end
    return locale("mission_reward_range", Config.Currency, reward.money.min or 0, reward.money.max or 0)
end

function Missions.OpenMenu()
    if not Config.Missions.enabled then return end
    if not Core.HasPermission("missions") then
        return Notify("no_permission", "error")
    end
    local options = {}
    if Active then
        local vehicle = GetMissionVehicle()
        local minutes = math.max(0, math.ceil((Active.expiresAt - GetGameTimer()) / 60000))
        table.insert(options, {
            title = locale("mission_current", TypeLabel(Active.type)),
            description = locale("mission_desc_"..Active.type).." "..locale("mission_time_left", minutes),
            icon = Config.Missions.types[Active.type].icon,
            onSelect = function()
                local coords = vehicle and GetEntityCoords(vehicle) or Active.anchor
                SetNewWaypoint(coords.x, coords.y)
            end,
        })
        table.insert(options, {
            title = locale("mission_cancel"),
            icon = "fa-solid fa-xmark",
            iconColor = "#e03131",
            onSelect = function()
                CreateThread(CancelMission)
            end,
        })
    else
        local listed = {}
        local function add(key)
            local cfg = Config.Missions.types[key]
            if not cfg or not cfg.enabled or listed[key] then return end
            listed[key] = true
            table.insert(options, {
                title = TypeLabel(key),
                description = locale("mission_desc_"..key).." "..RewardText(cfg.reward),
                icon = cfg.icon,
                onSelect = function()
                    CreateThread(function() StartMission(key) end)
                end,
            })
        end
        for _, key in ipairs(TYPE_ORDER) do add(key) end
        for key in pairs(Config.Missions.types) do add(key) end
    end
    if #options == 0 then
        return Notify("mission_disabled", "error")
    end
    lib.registerContext({
        id = MENU_ID,
        title = locale("mission_title"),
        options = options,
    })
    lib.showContext(MENU_ID)
end

--[[
  ______               _
 |  ____|             | |
 | |____   _____ _ __ | |_ ___
 |  __\ \ / / _ \ '_ \| __/ __|
 | |___\ V /  __/ | | | |_\__ \
 |______\_/ \___|_| |_|\__|___/
]]--

RegisterNetEvent("pls_mechanic:client:missions:ended", function(missionId, reason, reward)
    if not Active or Active.id ~= missionId then return end
    local ped = Npc
    Npc = nil
    NpcState = {}
    Active = nil
    ClearBlips()
    if reason == "completed" then
        NpcThanks(ped)
        local parts = {}
        for _, v in pairs(reward and reward.items or {}) do
            table.insert(parts, v.count.."x "..Core.GetItemLabel(v.item))
        end
        Notify("mission_completed", "success", Config.Currency, Utils.FormatMoney(reward and reward.money or 0))
        if #parts > 0 then
            Notify("mission_reward_items", "success", table.concat(parts, ", "))
        end
    else
        DeleteNpc(ped)
        Notify("mission_"..tostring(reason), "error")
    end
end)

TargetId = BRIDGE.AddGlobalVehicleTarget({
    {
        name = "pls_mechanic_mission_jumpstart",
        label = locale("mission_action_jumpstart"),
        icon = "fa-solid fa-car-battery",
        distance = 3.0,
        canInteract = function(entity)
            return IsMissionVehicle(entity, "jumpstart") and Core.CountTool("jump_starter") > 0
        end,
        onSelect = function(data)
            local entity = type(data) == "table" and data.entity or data
            if Menu and Menu.JumpStart then
                CreateThread(function() Menu.JumpStart(entity) end)
            end
        end,
    },
    {
        name = "pls_mechanic_mission_tyre",
        label = locale("mission_action_tyre"),
        icon = "fa-solid fa-circle-dot",
        distance = 3.0,
        canInteract = function(entity)
            return IsMissionVehicle(entity, "tyre")
        end,
        onSelect = function(data)
            local entity = type(data) == "table" and data.entity or data
            CreateThread(function() DoAction("tyre", entity) end)
        end,
    },
    {
        name = "pls_mechanic_mission_refuel",
        label = locale("mission_action_refuel"),
        icon = "fa-solid fa-gas-pump",
        distance = 3.0,
        canInteract = function(entity)
            return IsMissionVehicle(entity, "refuel")
        end,
        onSelect = function(data)
            local entity = type(data) == "table" and data.entity or data
            CreateThread(function() DoAction("refuel", entity) end)
        end,
    },
    {
        name = "pls_mechanic_mission_scrap",
        label = locale("mission_action_scrap"),
        icon = "fa-solid fa-recycle",
        distance = 3.0,
        canInteract = function(entity)
            return IsMissionVehicle(entity, "scrap")
        end,
        onSelect = function(data)
            local entity = type(data) == "table" and data.entity or data
            CreateThread(function() DoAction("scrap", entity) end)
        end,
    },
})

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Scene then
        Scene.cancelled = true
        EndScene()
    end
    ClearBlips()
    DeleteNpc(Npc)
    Npc = nil
    if TargetId then
        BRIDGE.RemoveGlobalVehicleTarget(TargetId)
    end
end)
