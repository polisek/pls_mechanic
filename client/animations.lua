--[[
             _                 _   _
     /\     (_)               | | (_)
    /  \   _ __  _ _ __ ___   __ _| |_ _  ___  _ __  ___
   / /\ \ | '_ \| | '_ ` _ \ / _` | __| |/ _ \| '_ \/ __|
  / ____ \| | | | | | | | | | (_| | |_| | (_) | | | \__ \
 /_/    \_\_| |_|_|_| |_| |_|\__,_|\__|_|\___/|_| |_|___/

 Global "Anim": work phases with ox_lib progress circle, hand / carried / ground props, sounds, particles,
 walking around vehicles, doors and toolbox. Presets in configs/animations.lua (Config.Animations).
 Everything started here is tracked and stopped by Anim.Cleanup() / on resource stop.

 Anim.Phase(opts) -> bool                    opts = { label, duration, anim, prop, prop2, sound, particle, cancel,
                                                      disable, onStart, onEnd, vehicle?, noCollision?, keepAnim?,
                                                      keepProp?, keepProp2?, keepCarry?, canCancel? }
 Anim.Sequence(phases, cancelFn) -> bool
 Anim.Carry(prop, anim?) -> handle           anim = false: no carry pose (toolbox in one hand)
 Anim.StopCarry(handle?)
 Anim.WalkTo(coords, heading?, timeout?, cancelFn?, radius?) -> bool
 Anim.WalkAround(vehicle, coords, heading?, timeout?, cancelFn?) -> bool   walks around the vehicle, not through it
 Anim.Face(entityOrCoords)
 Anim.PutDown(prop?, coords?, heading?, anim?) -> object      prop nil = the carried prop
 Anim.PickUp(object, anim?)
 Anim.SpawnProp(prop, coords, heading) -> object
 Anim.DeleteProp(object)
 Anim.PlaceToolbox(vehicle, cancelFn?) -> object
 Anim.RemoveToolbox(object)
 Anim.OpenDoor(vehicle, door) -> bool / Anim.CloseDoor(vehicle, door)
 Anim.Play(anim)                              blocking one-shot anim (transitions)
 Anim.IsBusy() -> bool
 Anim.Cleanup(all?)                           all = also props left on the ground
]]--

Anim = {}

local Presets = Config.Animations or {}
local Settings = Presets.Settings or {}

local RIGHT_HAND = 57005
local LEFT_HAND = 18905
local NO_HEADING = 40000.0
local DoorBones = { [0] = "door_dside_f", [1] = "door_pside_f", [2] = "door_dside_r", [3] = "door_pside_r", [4] = "bonnet", [5] = "boot" } -- GTA door index: 0 FL, 1 FR, 2 RL, 3 RR
local DefaultDisable = { move = true, car = true, combat = true, mouse = false, sprint = true }

local State = {
    token = 0,          -- increased by Cleanup, running loops stop when it changes
    phase = nil,        -- running phase { token, cancelled }
    anim = nil,         -- looped anim / scenario played by the library (kept between phases)
    hand = {},          -- [slot] = { object, sig }
    carry = nil,        -- { object, def, anim }
    objects = {},       -- every object created by the library
    ground = {},        -- objects left on the ground
    particles = {},     -- looped particle handles
    sounds = {},        -- sound ids
    banks = {},         -- loaded script audio banks
    assets = {},        -- requested particle assets
    frozen = false,
    walking = false,
    oneShot = false,
}

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

local function toVec3(value)
    local t = type(value)
    if t == "vector3" then return value end
    if t == "vector4" then return vector3(value.x, value.y, value.z) end
    if t == "table" then
        if value.x then return vector3(value.x + 0.0, value.y + 0.0, (value.z or 0.0) + 0.0) end
        if value[1] then return vector3(value[1] + 0.0, value[2] + 0.0, (value[3] or 0.0) + 0.0) end
    end
    return nil
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then print("[pls_mechanic] Anim callback error: "..tostring(err)) end
end

local function headingDiff(a, b)
    return math.abs((a - b + 180.0) % 360.0 - 180.0)
end

local function isActive(token)
    return State.token == token
end

-- Anim preset key | { dict, clip, flag } | { scenario } -> table or nil
local function resolveAnim(anim)
    if anim == nil or anim == false then return nil end
    if type(anim) == "string" then
        anim = Presets.Anims and Presets.Anims[anim]
    end
    if type(anim) ~= "table" then return nil end
    if type(anim.scenario) == "string" then return anim end
    if type(anim.dict) == "string" and type(anim.clip) == "string" then return anim end
    if type(anim[1]) == "string" and type(anim[2]) == "string" then
        return { dict = anim[1], clip = anim[2], flag = anim[3] or 1 }
    end
    return nil
end

local function sameAnim(a, b)
    if not a or not b then return false end
    if a.scenario or b.scenario then return a.scenario == b.scenario end
    return a.dict == b.dict and a.clip == b.clip
end

-- Anims of the same body pose (e.g. "lying") switch without exit / enter transitions
local function samePose(a, b)
    return a ~= nil and b ~= nil and a.pose ~= nil and a.pose == b.pose
end

-- Config.Props key | Config.Animations.Props key | { model, bone, pos, rot } -> def or nil
local function resolveProp(prop)
    if prop == nil or prop == false then return nil end
    if type(prop) == "string" then
        prop = (Config.Props and Config.Props[prop]) or (Presets.Props and Presets.Props[prop])
    end
    if type(prop) ~= "table" then return nil end
    local model = prop.model or prop[1]
    if type(model) == "string" then model = joaat(model) end
    if type(model) ~= "number" then return nil end
    return {
        model = model,
        bone = prop.bone,
        pos = toVec3(prop.pos) or vector3(0.0, 0.0, 0.0),
        rot = toVec3(prop.rot) or vector3(0.0, 0.0, 0.0),
        ground = type(prop.ground) == "table" and prop.ground or nil,
    }
end

local function propSignature(def)
    if not def then return nil end
    return ("%s|%s|%s|%s"):format(tostring(def.model), tostring(def.bone), tostring(def.pos), tostring(def.rot))
end

local function resolveSound(sound)
    if type(sound) == "string" then sound = Presets.Sounds and Presets.Sounds[sound] end
    if type(sound) ~= "table" then return nil end
    local name = sound.name or sound[1]
    if type(name) ~= "string" then return nil end
    return {
        name = name, set = sound.set or sound[2], interval = sound.interval, length = sound.length,
        entity = sound.entity, bank = sound.bank, frontend = sound.frontend == true, network = sound.network == true,
    }
end

local function resolveParticle(particle)
    if type(particle) == "string" then particle = Presets.Particles and Presets.Particles[particle] end
    if type(particle) ~= "table" then return nil end
    local asset, name = particle.asset or particle[1], particle.name or particle[2]
    if type(asset) ~= "string" or type(name) ~= "string" then return nil end
    return {
        asset = asset, name = name, entity = particle.entity, bone = particle.bone,
        offset = toVec3(particle.offset) or vector3(0.0, 0.0, 0.0), rot = toVec3(particle.rot) or vector3(0.0, 0.0, 0.0),
        scale = (tonumber(particle.scale) or 1.0) + 0.0, looped = particle.looped ~= false,
        interval = particle.interval, length = particle.length, network = particle.network,
    }
end

-- Single entry or list of entries (list of tables / list of preset keys)
local function asList(value, presets)
    if value == nil or value == false then return {} end
    if type(value) ~= "table" then return { value } end
    if type(value[1]) == "table" then return value end
    if type(value[1]) == "string" and presets and presets[value[1]] then return value end
    return { value }
end

--[[
     _          _
    / \   _ __ (_)_ __ ___  ___
   / _ \ | '_ \| | '_ ` _ \/ __|
  / ___ \| | | | | | | | | \__ \
 /_/   \_\_| |_|_|_| |_| |_|___/
]]--

local function loadDict(dict)
    return pcall(lib.requestAnimDict, dict, 3000)
end

-- Starts looped anim / scenario without transitions
local function startAnim(anim)
    local ped = cache.ped
    if anim.scenario then
        TaskStartScenarioInPlace(ped, anim.scenario, 0, true)
        return true
    end
    if not loadDict(anim.dict) then return false end
    TaskPlayAnim(ped, anim.dict, anim.clip, (anim.blendIn or 3.0) + 0.0, (anim.blendOut or 3.0) + 0.0, anim.duration or -1, anim.flag or 1, 0.0, false, false, false)
    RemoveAnimDict(anim.dict)
    return true
end

local function isAnimPlaying(anim)
    if anim.scenario then return IsPedUsingScenario(cache.ped, anim.scenario) end
    return IsEntityPlayingAnim(cache.ped, anim.dict, anim.clip, 3)
end

-- One-shot anim, blocks for its length. onRelease is called at anim.release (0..1) of the length.
local function playTimed(anim, token, onRelease)
    if not anim or anim.scenario or not loadDict(anim.dict) then
        State.oneShot = false
        if onRelease then onRelease() end
        return
    end
    local total = anim.time or math.floor(GetAnimDuration(anim.dict, anim.clip) * 1000)
    if not total or total <= 0 then total = 1200 end
    State.oneShot = true
    TaskPlayAnim(cache.ped, anim.dict, anim.clip, (anim.blendIn or 4.0) + 0.0, (anim.blendOut or 4.0) + 0.0, total, anim.flag or 0, 0.0, false, false, false)
    RemoveAnimDict(anim.dict)
    local startTime = GetGameTimer()
    local releaseAt = startTime + math.floor(total * (anim.release or 0.5))
    local released = onRelease == nil
    while GetGameTimer() < startTime + total and isActive(token) do
        if not released and GetGameTimer() >= releaseAt then
            released = true
            onRelease()
        end
        Wait(0)
    end
    if isActive(token) then State.oneShot = false end
    if not released then onRelease() end
end

-- Looped anim with its enter transition
local function playAnim(anim, token)
    if anim.enter then
        playTimed(resolveAnim(anim.enter), token)
        if not isActive(token) then return false end
    end
    if not startAnim(anim) then return false end
    State.anim = anim
    if anim.freeze then
        FreezeEntityPosition(cache.ped, true)
        State.frozen = true
    end
    return true
end

-- Stops the library anim. graceful = play its exit transition
local function stopAnim(token, graceful)
    local anim = State.anim
    if not anim then return end
    State.anim = nil
    local ped = cache.ped
    if State.frozen then
        FreezeEntityPosition(ped, false)
        State.frozen = false
    end
    if anim.scenario then
        ClearPedTasks(ped)
        return
    end
    local exit = graceful and resolveAnim(anim.exit) or nil
    if exit then
        playTimed(exit, token)
        return
    end
    StopAnimTask(ped, anim.dict, anim.clip, (anim.blendOut or 2.0) + 0.0)
end

-- A looped anim kept from the last phase ends before walking / putting down (gets up from lying first)
local function releaseAnim(token)
    if State.anim and not State.phase then
        stopAnim(token, true)
    end
end

--[[
  ____
 |  _ \ _ __ ___  _ __  ___
 | |_) | '__/ _ \| '_ \/ __|
 |  __/| | | (_) | |_) \__ \
 |_|   |_|  \___/| .__/|___/
                 |_|
]]--

local function createObject(def, coords)
    if not IsModelValid(def.model) or not pcall(lib.requestModel, def.model, 5000) then return nil end
    local networked = Settings.networkProps ~= false
    local object = CreateObject(def.model, coords.x, coords.y, coords.z, networked, true, false)
    if (not object or object == 0) and networked then
        -- servers with entity lockdown don't allow client networked objects: local prop instead
        networked = false
        object = CreateObject(def.model, coords.x, coords.y, coords.z, false, true, false)
    end
    SetModelAsNoLongerNeeded(def.model)
    if not object or object == 0 then return nil end
    if networked and NetworkGetEntityIsNetworked(object) then
        SetNetworkIdCanMigrate(ObjToNet(object), false)
    end
    State.objects[object] = true
    return object
end

local function deleteObject(object)
    if not object then return end
    State.objects[object] = nil
    State.ground[object] = nil
    if not DoesEntityExist(object) then return end
    if IsEntityAttached(object) then
        DetachEntity(object, true, false)
    end
    SetEntityAsMissionEntity(object, true, true)
    DeleteEntity(object)
end

local function attachProp(def, defaultBone)
    local ped = cache.ped
    local object = createObject(def, GetEntityCoords(ped))
    if not object then return nil end
    SetEntityCollision(object, false, false)
    local pos, rot = def.pos, def.rot
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, def.bone or defaultBone), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    return object
end

-- Hand prop slot 1 (right hand) / 2 (left hand). Same prop stays attached (no flicker between phases).
local function setHandProp(slot, prop)
    local def = resolveProp(prop)
    local current = State.hand[slot]
    local sig = propSignature(def)
    if current and sig and current.sig == sig and DoesEntityExist(current.object) then
        return current.object
    end
    if current then
        deleteObject(current.object)
        State.hand[slot] = nil
    end
    if not def then return nil end
    local object = attachProp(def, slot == 2 and LEFT_HAND or RIGHT_HAND)
    if object then
        State.hand[slot] = { object = object, sig = sig }
    end
    return object
end

-- Ground height at coords (ground under the ped when close, props go under vehicles too)
local function getGroundZ(coords)
    local ped = cache.ped
    local pedCoords = GetEntityCoords(ped)
    if #(pedCoords.xy - coords.xy) < 5.0 and not IsPedFalling(ped) then
        return pedCoords.z - GetEntityHeightAboveGround(ped)
    end
    local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    if found then return z end
    return coords.z
end

local function spawnGround(def, coords, heading)
    local groundZ = getGroundZ(coords)
    local object = createObject(def, vector3(coords.x, coords.y, groundZ + 0.5))
    if not object then return nil end
    local ground = def.ground or {}
    local rot = toVec3(ground.rot)
    local min = GetModelDimensions(def.model)
    local z = groundZ + (tonumber(ground.z) or 0.0)
    if rot then
        SetEntityRotation(object, rot.x, rot.y, (heading or 0.0) + rot.z, 2, true)
    else
        SetEntityHeading(object, (heading or 0.0) + 0.0)
        z = z - min.z
    end
    SetEntityCoordsNoOffset(object, coords.x, coords.y, z, false, false, false)
    FreezeEntityPosition(object, true)
    if not Settings.groundCollision then
        SetEntityCollision(object, false, false)
    end
    State.ground[object] = true
    return object
end

--[[
  ______  __  __           _
 |  ____|/ _|/ _|         | |
 | |__  | |_| |_ ___  ___| |_ ___
 |  __| |  _|  _/ _ \/ __| __/ __|
 | |____| | | ||  __/ (__| |_\__ \
 |______|_| |_| \___|\___|\__|___/
]]--

local function stopParticle(handle)
    State.particles[handle] = nil
    StopParticleFxLooped(handle, false)
    RemoveParticleFx(handle, false)
end

local function stopSound(id)
    State.sounds[id] = nil
    StopSound(id)
    ReleaseSoundId(id)
end

local function releaseBank(name)
    if State.banks[name] then
        State.banks[name] = nil
        ReleaseNamedScriptAudioBank(name)
    end
end

local function requestAsset(asset)
    if HasNamedPtfxAssetLoaded(asset) then return true end
    local ok = pcall(lib.requestNamedPtfxAsset, asset, 3000)
    if ok then State.assets[asset] = true end
    return ok
end

local function loadBanks(bank, fx)
    local list = type(bank) == "table" and bank or { bank }
    for _, name in ipairs(list) do
        if type(name) == "string" and not State.banks[name] then
            local timeout = GetGameTimer() + 3000
            while not RequestScriptAudioBank(name, false) do
                if GetGameTimer() > timeout or not fx.active then return false end
                Wait(50)
            end
            State.banks[name] = true
            fx.banks[name] = true
        end
    end
    return fx.active
end

-- Entity for "ped" / "prop" / "prop2" / "vehicle" / handle. Returns entity, bone override
local function resolveEntity(value, ctx)
    local ped = cache.ped
    if type(value) == "number" then
        return DoesEntityExist(value) and value or nil
    end
    if value == "vehicle" then
        return ctx.vehicle and DoesEntityExist(ctx.vehicle) and ctx.vehicle or nil
    end
    if value == "prop" or value == "prop2" then
        local slot = State.hand[value == "prop" and 1 or 2]
        if slot and DoesEntityExist(slot.object) then return slot.object end
        return ped, value == "prop" and RIGHT_HAND or LEFT_HAND
    end
    return ped
end

local function startParticle(p, entity, boneOverride)
    local networked = p.network ~= false and Settings.networkParticles ~= false
    local bone = boneOverride or p.bone
    local boneIndex = nil
    if bone then
        if type(bone) == "number" then
            boneIndex = IsEntityAPed(entity) and GetPedBoneIndex(entity, bone) or bone
        else
            boneIndex = GetEntityBoneIndexByName(entity, bone)
            if boneIndex == -1 then boneIndex = nil end
        end
    end
    local o, r = p.offset, p.rot
    if not p.looped then
        UseParticleFxAssetNextCall(p.asset)
        if networked then
            StartNetworkedParticleFxNonLoopedOnEntity(p.name, entity, o.x, o.y, o.z, r.x, r.y, r.z, p.scale, false, false, false)
        else
            StartParticleFxNonLoopedOnEntity(p.name, entity, o.x, o.y, o.z, r.x, r.y, r.z, p.scale, false, false, false)
        end
        return nil
    end
    local function start(net)
        UseParticleFxAssetNextCall(p.asset)
        if boneIndex then
            if net then
                return StartNetworkedParticleFxLoopedOnEntityBone(p.name, entity, o.x, o.y, o.z, r.x, r.y, r.z, boneIndex, p.scale, false, false, false)
            end
            return StartParticleFxLoopedOnEntityBone(p.name, entity, o.x, o.y, o.z, r.x, r.y, r.z, boneIndex, p.scale, false, false, false)
        end
        if net then
            return StartNetworkedParticleFxLoopedOnEntity(p.name, entity, o.x, o.y, o.z, r.x, r.y, r.z, p.scale, false, false, false)
        end
        return StartParticleFxLoopedOnEntity(p.name, entity, o.x, o.y, o.z, r.x, r.y, r.z, p.scale, false, false, false)
    end
    local handle = start(networked)
    if (not handle or handle == 0) and networked then
        handle = start(false)
    end
    if handle and handle ~= 0 then
        State.particles[handle] = true
        return handle
    end
    return nil
end

local function runParticle(p, fx, ctx)
    CreateThread(function()
        if not requestAsset(p.asset) then return end
        while fx.active do
            local entity, bone = resolveEntity(p.entity, ctx)
            local handle = entity and startParticle(p, entity, bone) or nil
            if handle then fx.particles[handle] = true end
            if not p.interval and not p.length then return end
            local now = GetGameTimer()
            local stopAt = p.length and now + p.length or nil
            local nextAt = p.interval and now + p.interval or nil
            while fx.active do
                now = GetGameTimer()
                if handle and stopAt and now >= stopAt then
                    stopParticle(handle)
                    fx.particles[handle] = nil
                    handle = nil
                end
                if (nextAt and now >= nextAt) or (not nextAt and not handle) then break end
                Wait(50)
            end
            if handle and State.particles[handle] then
                stopParticle(handle)
                fx.particles[handle] = nil
            end
            if not nextAt then return end
        end
    end)
end

local function runSound(s, fx, ctx)
    CreateThread(function()
        if s.bank and not loadBanks(s.bank, fx) then return end
        while fx.active do
            local id = -1
            if s.length then
                id = GetSoundId()
                State.sounds[id] = true
                fx.sounds[id] = GetGameTimer() + s.length
            end
            if s.frontend then
                PlaySoundFrontend(id, s.name, s.set, true)
            else
                local entity = resolveEntity(s.entity, ctx) or cache.ped
                PlaySoundFromEntity(id, s.name, entity, s.set, s.network, 0)
            end
            local nextAt = s.interval and GetGameTimer() + s.interval or nil
            while fx.active do
                local now = GetGameTimer()
                for soundId, stopAt in pairs(fx.sounds) do
                    if now >= stopAt then
                        fx.sounds[soundId] = nil
                        stopSound(soundId)
                    end
                end
                if nextAt then
                    if now >= nextAt then break end
                elseif next(fx.sounds) == nil then
                    return
                end
                Wait(50)
            end
            if not nextAt then return end
        end
    end)
end

local function startEffects(opts, ctx)
    local fx = { active = true, particles = {}, sounds = {}, banks = {} }
    for _, value in ipairs(asList(opts.particle, Presets.Particles)) do
        local p = resolveParticle(value)
        if p then runParticle(p, fx, ctx) end
    end
    for _, value in ipairs(asList(opts.sound, Presets.Sounds)) do
        local s = resolveSound(value)
        if s then runSound(s, fx, ctx) end
    end
    return fx
end

local function stopEffects(fx)
    fx.active = false
    for handle in pairs(fx.particles) do
        if State.particles[handle] then stopParticle(handle) end
    end
    for id in pairs(fx.sounds) do
        if State.sounds[id] then stopSound(id) end
    end
    for name in pairs(fx.banks) do
        releaseBank(name)
    end
    fx.particles, fx.sounds, fx.banks = {}, {}, {}
end

--[[
  _____  _
 |  __ \| |
 | |__) | |__   __ _ ___  ___
 |  ___/| '_ \ / _` / __|/ _ \
 | |    | | | | (_| \__ \  __/
 |_|    |_| |_|\__,_|___/\___|
]]--

local function disableFlags(custom)
    local flags = {}
    for key, value in pairs(DefaultDisable) do flags[key] = value end
    if type(custom) == "table" then
        for key, value in pairs(custom) do flags[key] = value end
    end
    return flags
end

local function isCancelled(opts, phase)
    if not isActive(phase.token) or phase.cancelled then return true end
    if opts.cancel then
        local ok, result = pcall(opts.cancel)
        if ok and result then return true end
    end
    return false
end

-- Releases what the phase started (not when Cleanup already did it)
local function finishPhase(opts, phase, completed)
    if not isActive(phase.token) then return end
    if not (completed and opts.keepProp) then setHandProp(1, nil) end
    if not (completed and opts.keepProp2) then setHandProp(2, nil) end
    if State.anim and not (completed and opts.keepAnim) then
        stopAnim(phase.token, true)
    end
end

local function runPhase(opts, phase)
    local token = phase.token
    if isCancelled(opts, phase) then
        finishPhase(opts, phase, false)
        return false
    end
    if State.carry and not opts.keepCarry then
        Anim.StopCarry(State.carry)
    end

    local anim = resolveAnim(opts.anim)
    local switched = false
    if State.anim and not sameAnim(State.anim, anim) then
        if samePose(State.anim, anim) then
            switched = startAnim(anim)
            State.anim = switched and anim or State.anim
        end
        if not switched then
            stopAnim(token, true)
        end
    end
    if anim and not switched and not (State.anim and isAnimPlaying(anim)) then
        State.anim = nil
        playAnim(anim, token)
    end
    if not isActive(token) or isCancelled(opts, phase) then
        finishPhase(opts, phase, false)
        return false
    end

    setHandProp(1, opts.prop)
    setHandProp(2, opts.prop2)
    local ctx = { vehicle = opts.vehicle }
    local fx = startEffects(opts, ctx)
    safeCall(opts.onStart)

    local watching = true
    -- looped anims interrupted by the game (bump, ragdoll) are started again, one-shot anims play once
    local looped = anim and not anim.scenario and ((anim.flag or 1) & 1) == 1
    CreateThread(function()
        local ped = cache.ped
        local nextCheck = GetGameTimer() + 1000
        while watching do
            if phase.cancelled or isCancelled(opts, phase) then
                phase.cancelled = true
                -- progress may start a frame later, keep waiting for it
                if lib.progressActive() then
                    lib.cancelProgress()
                    return
                end
            else
                if opts.noCollision and DoesEntityExist(opts.noCollision) then
                    SetEntityNoCollisionEntity(ped, opts.noCollision, true)
                end
                local now = GetGameTimer()
                if looped and now > nextCheck then
                    nextCheck = now + 1000
                    if not IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) and not IsPedRagdoll(ped) then
                        startAnim(anim)
                    end
                end
            end
            Wait(0)
        end
    end)

    local completed = false
    if not phase.cancelled then
        completed = lib.progressCircle({
            label = opts.label,
            duration = math.max(math.floor(tonumber(opts.duration) or 1000), 100),
            position = Settings.progressPosition or "bottom",
            useWhileDead = false,
            canCancel = opts.canCancel ~= false,
            disable = disableFlags(opts.disable),
        })
    end
    watching = false
    completed = completed == true and not phase.cancelled and isActive(token)
    stopEffects(fx)
    finishPhase(opts, phase, completed)
    safeCall(opts.onEnd, completed)
    return completed
end

-- One work phase. Returns true when completed (false = cancelled / failed)
function Anim.Phase(opts)
    if type(opts) ~= "table" or State.phase then return false end
    local phase = { token = State.token, cancelled = false }
    State.phase = phase
    local ok, result = pcall(runPhase, opts, phase)
    if State.phase == phase then State.phase = nil end
    if not ok then
        print("[pls_mechanic] Anim.Phase error: "..tostring(result))
        if isActive(phase.token) then
            setHandProp(1, nil)
            setHandProp(2, nil)
            stopAnim(phase.token, false)
        end
        return false
    end
    return result == true
end

-- Runs phases one by one (anim / props shared by following phases stay on). Stops at the first not completed.
function Anim.Sequence(phases, cancelFn)
    if type(phases) ~= "table" then return false end
    local token = State.token
    for i, entry in ipairs(phases) do
        local opts = {}
        for key, value in pairs(entry) do opts[key] = value end
        if cancelFn then
            local own = entry.cancel
            opts.cancel = own and function() return cancelFn() or own() end or cancelFn
        end
        local nextEntry = phases[i + 1]
        if nextEntry then
            local animA, animB = resolveAnim(entry.anim), resolveAnim(nextEntry.anim)
            opts.keepAnim = entry.keepAnim or sameAnim(animA, animB) or samePose(animA, animB)
            opts.keepProp = entry.keepProp or (entry.prop ~= nil and propSignature(resolveProp(entry.prop)) == propSignature(resolveProp(nextEntry.prop)))
            opts.keepProp2 = entry.keepProp2 or (entry.prop2 ~= nil and propSignature(resolveProp(entry.prop2)) == propSignature(resolveProp(nextEntry.prop2)))
        end
        if not Anim.Phase(opts) then
            if isActive(token) and not State.phase then
                setHandProp(1, nil)
                setHandProp(2, nil)
                stopAnim(token, true)
            end
            return false
        end
    end
    return true
end

function Anim.IsBusy()
    return State.phase ~= nil
end

-- Blocking one-shot anim (transition). Returns false when interrupted by Cleanup.
function Anim.Play(anim)
    local token = State.token
    releaseAnim(token)
    playTimed(resolveAnim(anim), token)
    return isActive(token)
end

--[[
  _____
 / ____|
| |     __ _ _ __ _ __ _   _
| |    / _` | '__| '__| | | |
| |___| (_| | |  | |  | |_| |
 \_____\__,_|_|  |_|   \__, |
                        __/ |
                       |___/
]]--

-- Carry pose + prop, the player can walk. anim = false: prop only (toolbox in one hand)
function Anim.Carry(prop, anim)
    local def = resolveProp(prop)
    if not def then return nil end
    if State.carry then Anim.StopCarry(State.carry) end
    local object = attachProp(def, RIGHT_HAND)
    if not object then return nil end
    local carryAnim = anim ~= false and resolveAnim(anim or "carry") or nil
    local handle = { object = object, def = def, anim = carryAnim }
    State.carry = handle
    if carryAnim then startAnim(carryAnim) end
    CreateThread(function()
        local nextCheck = 0
        while State.carry == handle do
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 23, true)   -- enter vehicle
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 140, true)  -- melee
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            local now = GetGameTimer()
            if carryAnim and now > nextCheck then
                nextCheck = now + 500
                local ped = cache.ped
                if not State.phase and not State.oneShot and not IsPedRagdoll(ped) and not isAnimPlaying(carryAnim) then
                    startAnim(carryAnim)
                end
            end
            Wait(0)
        end
    end)
    return handle
end

function Anim.StopCarry(handle)
    handle = handle or State.carry
    if not handle then return end
    if State.carry == handle then State.carry = nil end
    deleteObject(handle.object)
    if handle.anim and not handle.anim.scenario then
        StopAnimTask(cache.ped, handle.anim.dict, handle.anim.clip, 2.0)
    end
end

--[[
 __          __   _ _
 \ \        / /  | | |
  \ \  /\  / /_ _| | | __
   \ \/  \/ / _` | | |/ /
    \  /\  / (_| | |   <
     \/  \/ \__,_|_|_|\_\
]]--

local function turnTo(heading)
    local ped = cache.ped
    heading = heading + 0.0
    if headingDiff(GetEntityHeading(ped), heading) > 15.0 then
        TaskAchieveHeading(ped, heading, 1000)
        local endTime = GetGameTimer() + 1000
        while GetGameTimer() < endTime and headingDiff(GetEntityHeading(ped), heading) > 12.0 do
            Wait(50)
        end
    end
    SetEntityHeading(ped, heading)
end

function Anim.Face(target)
    local coords
    if type(target) == "number" then
        if not DoesEntityExist(target) then return end
        coords = GetEntityCoords(target)
    else
        coords = toVec3(target)
    end
    if not coords then return end
    local pos = GetEntityCoords(cache.ped)
    if #(pos.xy - coords.xy) < 0.05 then return end
    turnTo(GetHeadingFromVector_2d(coords.x - pos.x, coords.y - pos.y))
end

-- Walks to coords (straight, navmesh when stuck). True when reached (<= Settings.reachDistance).
function Anim.WalkTo(coords, heading, timeout, cancel, radius)
    coords = toVec3(coords)
    if not coords then return false end
    local ped = cache.ped
    local token = State.token
    radius = radius or 0.35
    timeout = timeout or Settings.walkTimeout or 8000
    local speed = (Settings.walkSpeed or 1.0) + 0.0
    local function distance() return #(GetEntityCoords(ped).xy - coords.xy) end

    if distance() > radius then
        releaseAnim(token)
        if not isActive(token) then return false end
        State.walking = true
        TaskGoStraightToCoord(ped, coords.x, coords.y, coords.z, speed, timeout, heading and (heading + 0.0) or NO_HEADING, 0.1)
        local endTime = GetGameTimer() + timeout
        local lastPos, lastMove = GetEntityCoords(ped), GetGameTimer()
        local usedNavmesh = false
        while distance() > radius do
            if not isActive(token) then return false end
            if cancel and cancel() then
                State.walking = false
                ClearPedTasks(ped)
                return false
            end
            local now = GetGameTimer()
            if now > endTime then break end
            local pos = GetEntityCoords(ped)
            if #(pos - lastPos) > 0.15 then
                lastPos, lastMove = pos, now
            elseif now - lastMove > 1500 then
                if usedNavmesh then break end
                usedNavmesh = true
                lastMove = now
                TaskFollowNavMeshToCoord(ped, coords.x, coords.y, coords.z, speed, math.max(endTime - now, 1000), radius, 0, heading and (heading + 0.0) or NO_HEADING)
            end
            Wait(100)
        end
        State.walking = false
    end
    local reached = distance() <= (Settings.reachDistance or 1.2)
    if reached and heading then
        turnTo(heading)
    end
    return reached
end

-- Liang-Barsky: segment a-b hits box
local function segmentHitsBox(ax, ay, bx, by, minX, minY, maxX, maxY)
    local dx, dy = bx - ax, by - ay
    local t0, t1 = 0.0, 1.0
    local p = { -dx, dx, -dy, dy }
    local q = { ax - minX, maxX - ax, ay - minY, maxY - ay }
    for i = 1, 4 do
        if p[i] == 0 then
            if q[i] < 0 then return false end
        else
            local t = q[i] / p[i]
            if p[i] < 0 then
                if t > t1 then return false end
                if t > t0 then t0 = t end
            else
                if t < t0 then return false end
                if t < t1 then t1 = t end
            end
        end
    end
    return true
end

-- Waypoints (world) around the vehicle footprint from -> to. Empty = direct way.
local function buildRoute(vehicle, from, to)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local a = GetOffsetFromEntityGivenWorldCoords(vehicle, from.x, from.y, from.z)
    local b = GetOffsetFromEntityGivenWorldCoords(vehicle, to.x, to.y, to.z)
    -- vehicle high above the ped (lift): free way under it
    if a.z < min.z - 0.9 then return {} end
    local pad, out = 0.3, 0.85
    local x0, y0, x1, y1 = min.x - pad, min.y - pad, max.x + pad, max.y + pad
    local function inside(p) return p.x > x0 and p.x < x1 and p.y > y0 and p.y < y1 end
    if inside(a) or inside(b) or not segmentHitsBox(a.x, a.y, b.x, b.y, x0, y0, x1, y1) then return {} end

    local corners = {
        { min.x - out, max.y + out }, { max.x + out, max.y + out },
        { max.x + out, min.y - out }, { min.x - out, min.y - out },
    }
    local A, B = { a.x, a.y }, { b.x, b.y }
    local function clear(p, q) return not segmentHitsBox(p[1], p[2], q[1], q[2], x0, y0, x1, y1) end
    local function dist(p, q) return math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2) end
    local best, bestLength = nil, math.huge
    for i = 1, 4 do
        local c = corners[i]
        if clear(A, c) then
            if clear(c, B) then
                local length = dist(A, c) + dist(c, B)
                if length < bestLength then best, bestLength = { c }, length end
            end
            for _, j in ipairs({ i % 4 + 1, (i + 2) % 4 + 1 }) do
                local d = corners[j]
                if clear(d, B) then
                    local length = dist(A, c) + dist(c, d) + dist(d, B)
                    if length < bestLength then best, bestLength = { c, d }, length end
                end
            end
        end
    end
    local route = {}
    for _, c in ipairs(best or {}) do
        local world = GetOffsetFromEntityInWorldCoords(vehicle, c[1], c[2], 0.0)
        route[#route + 1] = vector3(world.x, world.y, from.z)
    end
    return route
end

-- Walks to coords around the vehicle (never through it)
function Anim.WalkAround(vehicle, coords, heading, timeout, cancel)
    coords = toVec3(coords)
    if not coords then return false end
    timeout = timeout or Settings.walkTimeout or 8000
    if not vehicle or not DoesEntityExist(vehicle) then
        return Anim.WalkTo(coords, heading, timeout, cancel)
    end
    local ped = cache.ped
    local token = State.token
    local route = buildRoute(vehicle, GetEntityCoords(ped), coords)
    local endTime = GetGameTimer() + timeout
    if #route > 0 then
        State.walking = true
        TaskFlushRoute()
        for _, point in ipairs(route) do
            TaskExtendRoute(point.x, point.y, point.z)
        end
        TaskExtendRoute(coords.x, coords.y, coords.z)
        TaskFollowPointRoute(ped, (Settings.walkSpeed or 1.0) + 0.0, 0)
        local lastPos, lastMove = GetEntityCoords(ped), GetGameTimer()
        while #(GetEntityCoords(ped).xy - coords.xy) > 0.8 do
            if not isActive(token) then return false end
            if cancel and cancel() then
                State.walking = false
                ClearPedTasks(ped)
                return false
            end
            local now = GetGameTimer()
            local pos = GetEntityCoords(ped)
            if #(pos - lastPos) > 0.15 then
                lastPos, lastMove = pos, now
            elseif now - lastMove > 1500 or now > endTime then
                break
            end
            Wait(100)
        end
        State.walking = false
    end
    return Anim.WalkTo(coords, heading, math.max(endTime - GetGameTimer(), 3000), cancel)
end

--[[
   _____                           _   _____
  / ____|                         | | |  __ \
 | |  __ _ __ ___  _   _ _ __   __| | | |__) | __ ___  _ __  ___
 | | |_ | '__/ _ \| | | | '_ \ / _` | |  ___/ '__/ _ \| '_ \/ __|
 | |__| | | | (_) | |_| | | | | (_| | | |   | | | (_) | |_) \__ \
  \_____|_|  \___/ \__,_|_| |_|\__,_| |_|   |_|  \___/| .__/|___/
                                                      | |
                                                      |_|
]]--

function Anim.SpawnProp(prop, coords, heading)
    local def = resolveProp(prop)
    coords = toVec3(coords)
    if not def or not coords then return nil end
    return spawnGround(def, coords, heading or 0.0)
end

function Anim.DeleteProp(object)
    deleteObject(object)
end

-- Short put-down anim, the prop stays on the ground. prop nil = the carried prop.
function Anim.PutDown(prop, coords, heading, anim)
    local token = State.token
    local carry = State.carry
    local def = resolveProp(prop) or (carry and carry.def) or nil
    if not def then return nil end
    local ped = cache.ped
    releaseAnim(token)
    coords = toVec3(coords)
    if coords then
        local pos = GetEntityCoords(ped)
        local dir = pos.xy - coords.xy
        local length = #dir
        if length > 1.6 then
            dir = dir / length
            Anim.WalkTo(vector3(coords.x + dir.x * 0.7, coords.y + dir.y * 0.7, pos.z), nil, 5000)
            if not isActive(token) then return nil end
        end
        Anim.Face(coords)
    else
        coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.6, 0.0)
    end
    heading = heading or GetEntityHeading(ped)
    if carry and carry.anim and not carry.anim.scenario then
        -- hands free for the put-down anim, the carried prop stays in the hands until it is released
        State.oneShot = true
        StopAnimTask(ped, carry.anim.dict, carry.anim.clip, 4.0)
    end
    local object = nil
    local released = false
    local function release()
        if released then return end
        released = true
        if carry then Anim.StopCarry(carry) end
        if isActive(token) then
            object = spawnGround(def, coords, heading)
        end
    end
    playTimed(resolveAnim(anim or "putdown"), token, release)
    release()
    return object
end

-- Crouch / pick-up anim, deletes the object
function Anim.PickUp(object, anim)
    if not object or not DoesEntityExist(object) then
        deleteObject(object)
        return
    end
    local token = State.token
    local ped = cache.ped
    releaseAnim(token)
    local target = GetEntityCoords(object)
    local pos = GetEntityCoords(ped)
    local length = #(pos.xy - target.xy)
    if length > 15.0 then
        deleteObject(object)
        return
    end
    if length > 1.3 then
        local dir = (pos.xy - target.xy) / length
        Anim.WalkTo(vector3(target.x + dir.x * 0.7, target.y + dir.y * 0.7, pos.z), nil, 5000)
    end
    if not isActive(token) then
        deleteObject(object)
        return
    end
    Anim.Face(target)
    playTimed(resolveAnim(anim or "pickup"), token, function()
        deleteObject(object)
    end)
    deleteObject(object)
end

-- Toolbox spot beside the vehicle (corner closest to the ped). Returns ground coords, stand coords, heading
local function getToolboxSpot(vehicle)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local pedCoords = GetEntityCoords(cache.ped)
    local vehHeading = GetEntityHeading(vehicle)
    local best = nil
    for _, side in ipairs({ -1, 1 }) do
        for _, y in ipairs({ max.y * 0.55, min.y * 0.55 }) do
            local x = side < 0 and (min.x - 0.75) or (max.x + 0.75)
            local spot = GetOffsetFromEntityInWorldCoords(vehicle, x, y, 0.0)
            local stand = GetOffsetFromEntityInWorldCoords(vehicle, x + side * 0.65, y, 0.0)
            local distance = #(pedCoords - stand)
            if not best or distance < best.distance then
                best = { spot = spot, stand = stand, distance = distance, heading = vehHeading + (side < 0 and -90.0 or 90.0) }
            end
        end
    end
    return best.spot, best.stand, best.heading
end

-- Carries the toolbox (Config.Props.toolbox) beside the vehicle and puts it on the ground
function Anim.PlaceToolbox(vehicle, cancel)
    if not vehicle or not DoesEntityExist(vehicle) or not resolveProp("toolbox") then return nil end
    local token = State.token
    local spot, stand, heading = getToolboxSpot(vehicle)
    local handle = Anim.Carry("toolbox", false)
    Anim.WalkAround(vehicle, stand, heading, nil, cancel)
    if not isActive(token) or (cancel and cancel()) then
        if handle then Anim.StopCarry(handle) end
        return nil
    end
    return Anim.PutDown(not handle and "toolbox" or nil, spot, GetEntityHeading(vehicle), "putdown_case")
end

function Anim.RemoveToolbox(object)
    Anim.PickUp(object, "pickup")
end

--[[
  _____
 |  __ \
 | |  | | ___   ___  _ __ ___
 | |  | |/ _ \ / _ \| '__/ __|
 | |__| | (_) | (_) | |  \__ \
 |_____/ \___/ \___/|_|  |___/
]]--

local function isDoorUsable(vehicle, door)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    local bone = DoorBones[door]
    if not bone or GetEntityBoneIndexByName(vehicle, bone) == -1 then return false end
    return not IsVehicleDoorDamaged(vehicle, door)
end

-- Opens hood (4) / trunk (5) / door (0-3). True when this call opened it.
function Anim.OpenDoor(vehicle, door)
    if not isDoorUsable(vehicle, door) then return false end
    if GetVehicleDoorAngleRatio(vehicle, door) > 0.1 then return false end
    if not Core.RequestControl(vehicle, 1500) then return false end
    SetVehicleDoorOpen(vehicle, door, false, false)
    Wait(500)
    return true
end

function Anim.CloseDoor(vehicle, door)
    if not isDoorUsable(vehicle, door) then return end
    if GetVehicleDoorAngleRatio(vehicle, door) <= 0.0 then return end
    if not Core.RequestControl(vehicle, 1500) then return end
    SetVehicleDoorShut(vehicle, door, false)
end

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

-- Stops everything the library started for the local player. all = also props left on the ground.
function Anim.Cleanup(all)
    State.token = State.token + 1
    local ped = cache.ped
    if State.phase then
        State.phase.cancelled = true
        if lib.progressActive() then lib.cancelProgress() end
    end
    for handle in pairs(State.particles) do stopParticle(handle) end
    for id in pairs(State.sounds) do stopSound(id) end
    for name in pairs(State.banks) do releaseBank(name) end
    for slot in pairs(State.hand) do setHandProp(slot, nil) end
    if State.carry then Anim.StopCarry(State.carry) end
    if State.frozen then
        FreezeEntityPosition(ped, false)
        State.frozen = false
    end
    if State.anim or State.walking or State.oneShot then
        ClearPedTasks(ped)
    end
    State.anim, State.walking, State.oneShot = nil, false, false
    if all then
        for object in pairs(State.ground) do deleteObject(object) end
    end
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Anim.Cleanup(true)
    for object in pairs(State.objects) do deleteObject(object) end
    for asset in pairs(State.assets) do
        if asset ~= "core" then RemoveNamedPtfxAsset(asset) end
    end
end)
