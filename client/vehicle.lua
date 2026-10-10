--[[
 __      __  _     _      _
 \ \    / / | |   (_)    | |
  \ \  / /__| |__  _  ___| | ___
   \ \/ / _ \ '_ \| |/ __| |/ _ \
    \  /  __/ | | | | (__| |  __/
     \/ \___|_| |_|_|\___|_|\___|

 Driver side of the vehicle condition model:
 mileage counting, collision detection, malfunction effects of worn parts, odometer.
 Handling multipliers of other resources (statebag data.ext[source].handling, e.g. ECU remap) are applied
 together with the part effects and restored with them.
 Runs only while the player is the driver of a vehicle with parts system.
]]--

VehicleState = {}

local STATE_KEY = "pls_mech"
local KMH = 3.6
local TURBO_MOD = 18
local MIN_SEND_MS = 5000          -- min time between two mileage reports
local AWAIT_TIMEOUT_MS = 5000     -- sent km are shown on odometer until server confirms
local STATE_INDEX = { optimal = 0, worn = 1, critical = 2, failed = 3 }
-- "won't start" reason used when more parts are broken
local START_ORDER = { "engine", "timing_belt", "fuel_pump", "battery", "ev_battery", "ev_motor" }
-- profile multiplier -> per vehicle handling fields
local HANDLING = {
    brake = { "fBrakeForce" },
    grip = { "fTractionCurveMax", "fTractionCurveMin" },
    shift = { "fClutchChangeRateScaleUpShift", "fClutchChangeRateScaleDownShift" },
}

local SetPowerMultiplier = SetVehicleCheatPowerIncrease or SetVehicleEngineTorqueMultiplier

local DriverVehicle = nil   -- vehicle of the running driver loop
local Active = nil          -- current driving session
local ExternalPower = false -- another resource sets the engine power (e.g. nitro boost of the illegal DLC)
local Excluded = {}         -- [vehicle] = GetGameTimer() until the vehicle is skipped
local Temperatures = {}     -- [plate] = { value, time } engine temperature after leaving
local Anchor = { x = 0.0, y = 0.0, refreshAt = 0 }

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

local function notify(text, notifyType)
    Core.Notify(text, notifyType)
end

-- km/h -> value, unit label by Config.MileageUnit
local function speedText(kmh)
    if Config.MileageUnit == "mi" then
        return math.floor(kmh * 0.621371 + 0.5), locale("veh_speed_mph")
    end
    return math.floor(kmh + 0.5), locale("veh_speed_kmh")
end

-- 12345.6 -> "12 345.6"
local function formatDistance(value)
    local whole = math.floor(value)
    local decimal = math.floor((value - whole) * 10 + 0.5)
    if decimal >= 10 then
        whole = whole + 1
        decimal = 0
    end
    local text = tostring(whole)
    local k
    repeat
        text, k = text:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
    until k == 0
    return text.."."..decimal
end

local function readMods(vehicle)
    local mods = {}
    for key, cfg in pairs(Config.TuningWear) do
        if cfg.toggle then
            mods[key] = IsToggleModOn(vehicle, cfg.mod)
        else
            mods[key] = GetVehicleMod(vehicle, cfg.mod)
        end
    end
    return mods
end

local function getEngineBone(vehicle)
    local bone = GetEntityBoneIndexByName(vehicle, "engine")
    if bone == -1 then bone = GetEntityBoneIndexByName(vehicle, "bonnet") end
    if bone == -1 then bone = 0 end
    return bone
end

--[[
  _____            __ _ _
 |  __ \          / _(_) |
 | |__) | __ ___ | |_ _| | ___
 |  ___/ '__/ _ \|  _| | |/ _ \
 | |   | | | (_) | | | | |  __/
 |_|   |_|  \___/|_| |_|_|\___|

 All effects of worn parts merged into one profile, rebuilt when the statebag changes.
]]--

local function newProfile()
    return {
        power = 1.0, brake = 1.0, grip = 1.0, shift = 1.0, cooling = 1.0,
        pull = 0.0, wobble = 0.0, evDrain = 0.0,
        topSpeed = nil, slip = nil, crank = nil, noStart = nil, noDrive = nil,
        lights = nil, burst = nil, smoke = false,
        stall = {}, stutter = {},
        temperature = false,
    }
end

local function partEffects(key, value)
    local cfg = Config.Effects.Parts[key]
    if not cfg then return nil end
    if value <= 0 and cfg.empty then return cfg.empty end
    return cfg[Utils.GetPartState(value)]
end

local function mergeEffects(p, fx, key, noStarts)
    if fx.power then p.power = p.power * fx.power end
    if fx.brake then p.brake = p.brake * fx.brake end
    if fx.grip then p.grip = p.grip * fx.grip end
    if fx.shift then p.shift = p.shift * fx.shift end
    if fx.cooling then p.cooling = p.cooling * fx.cooling end
    if fx.pull then p.pull = p.pull + fx.pull end
    if fx.wobble then p.wobble = math.max(p.wobble, fx.wobble) end
    if fx.evDrain then p.evDrain = p.evDrain + fx.evDrain end
    if fx.topSpeed then p.topSpeed = p.topSpeed and math.min(p.topSpeed, fx.topSpeed) or fx.topSpeed end
    if fx.smoke then p.smoke = true end
    if fx.stall then p.stall[#p.stall + 1] = fx.stall end
    if fx.stutter then p.stutter[#p.stutter + 1] = fx.stutter end
    if fx.slip and (not p.slip or (fx.slip.power or 1.0) < (p.slip.power or 1.0)) then p.slip = fx.slip end
    if fx.crank then
        local crank = p.crank or { delay = 0, failChance = 0.0 }
        p.crank = {
            delay = math.max(crank.delay, fx.crank.delay or 0),
            failChance = 1.0 - (1.0 - crank.failChance) * (1.0 - (fx.crank.failChance or 0.0)),
        }
    end
    if fx.lights then
        local lights = p.lights or { dim = 1.0, flicker = 0.0 }
        p.lights = {
            dim = math.min(lights.dim, fx.lights.dim or 1.0),
            flicker = math.max(lights.flicker, fx.lights.flicker or 0.0),
        }
    end
    if fx.burst and (not p.burst or (fx.burst.chance or 0) > (p.burst.chance or 0)) then p.burst = fx.burst end
    if fx.noStart then noStarts[key] = fx.noStart end
    if fx.noDrive and not p.noDrive then p.noDrive = fx.noDrive end
end

local function buildProfile(s)
    local p = newProfile()
    local data = s.data
    if not Config.Effects.Enabled or type(data) ~= "table" then return p end

    local noStarts = {}
    for _, kind in ipairs({ "core", "service" }) do
        local defs = kind == "core" and Config.CoreParts or Config.ServiceParts
        for key, value in pairs(data[kind] or {}) do
            local def = defs[key]
            if def and not (def.requiresTurbo and not s.hasTurbo) then
                local fx = partEffects(key, value)
                if fx then mergeEffects(p, fx, key, noStarts) end
            end
        end
    end

    for _, key in ipairs(START_ORDER) do
        if noStarts[key] then
            p.noStart = noStarts[key]
            break
        end
    end
    if not p.noStart then
        local _, reason = next(noStarts)
        p.noStart = reason
    end

    p.power = Utils.Clamp(p.power, 0.05, 2.0)
    p.brake = Utils.Clamp(p.brake, 0.1, 2.0)
    p.grip = Utils.Clamp(p.grip, 0.3, 2.0)
    p.shift = Utils.Clamp(p.shift, 0.1, 2.0)
    p.cooling = Utils.Clamp(p.cooling, 0.05, 2.0)
    p.pull = Utils.Clamp(p.pull, 0.0, 0.3)

    local temperature = Config.Effects.Temperature
    local hasCooling = (data.core and data.core.radiator ~= nil) or (data.service and data.service.coolant ~= nil)
    p.temperature = temperature ~= nil and temperature.enabled == true and not data.ev and hasCooling == true
    return p
end

--[[
   _____ _        _
  / ____| |      | |
 | (___ | |_ __ _| |_ ___
  \___ \| __/ _` | __/ _ \
  ____) | || (_| | ||  __/
 |_____/ \__\__,_|\__\___|

 Natives applied once per profile change (restored when the driver leaves)
]]--

-- Handling field -> multiplier: part effects (profile) x modifiers of other resources (data.ext[source].handling)
local function handlingTargets(s)
    local targets = {}
    for key, fields in pairs(HANDLING) do
        local mult = s.profile[key] or 1.0
        for _, field in ipairs(fields) do
            targets[field] = (targets[field] or 1.0) * mult
        end
    end
    local ext = type(s.data) == "table" and s.data.ext or nil
    for _, mods in pairs(type(ext) == "table" and ext or {}) do
        local handling = type(mods) == "table" and mods.handling or nil
        for field, mult in pairs(type(handling) == "table" and handling or {}) do
            mult = tonumber(mult)
            -- float fields only (validated by the server as well)
            if type(field) == "string" and field:match("^f%u%w*$") and mult and mult > 0 then
                targets[field] = (targets[field] or 1.0) * mult
            end
        end
    end
    -- fields changed before and not wanted anymore go back to the original
    for field in pairs(s.handling) do
        if targets[field] == nil then
            targets[field] = 1.0
        end
    end
    return targets
end

local function applyHandling(s)
    local vehicle = s.vehicle
    for field, mult in pairs(handlingTargets(s)) do
        mult = Utils.Clamp(mult, 0.05, 5.0)
        local entry = s.handling[field]
        if mult ~= 1.0 or entry then
            if not entry then
                entry = { original = GetVehicleHandlingFloat(vehicle, "CHandlingData", field) }
                s.handling[field] = entry
            end
            local value = entry.original * mult
            if entry.applied ~= value then
                SetVehicleHandlingFloat(vehicle, "CHandlingData", field, value + 0.0)
                entry.applied = value
            end
        end
    end
end

local function restoreHandling(s)
    for field, entry in pairs(s.handling) do
        if entry.applied and entry.applied ~= entry.original then
            SetVehicleHandlingFloat(s.vehicle, "CHandlingData", field, entry.original + 0.0)
        end
    end
    s.handling = {}
end

local function applyTopSpeed(s)
    local limit = s.profile.topSpeed
    if limit == s.topSpeed then return end
    SetVehicleMaxSpeed(s.vehicle, limit and (limit / KMH) or 0.0)
    s.topSpeed = limit
    if limit then
        notify(locale("veh_limp_mode", speedText(limit)), "error")
    end
end

local function setUndriveable(s, toggle)
    if s.undriveable == toggle then return end
    s.undriveable = toggle
    SetVehicleUndriveable(s.vehicle, toggle)
end

local function startParticle(s, key)
    if s.ptfx[key] then return end
    local particles = Config.Effects.Particles
    local cfg = particles and particles[key]
    if not cfg or not cfg.asset or not cfg.name then return end
    if not HasNamedPtfxAssetLoaded(cfg.asset) then
        RequestNamedPtfxAsset(cfg.asset)
        return
    end
    local offset = cfg.offset or vec3(0.0, 0.0, 0.0)
    local start = particles.networked and StartNetworkedParticleFxLoopedOnEntityBone or StartParticleFxLoopedOnEntityBone
    UseParticleFxAsset(cfg.asset)
    s.ptfx[key] = start(cfg.name, s.vehicle, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, getEngineBone(s.vehicle), (cfg.scale or 1.0) + 0.0, false, false, false)
end

local function stopParticle(s, key)
    local handle = s.ptfx[key]
    if not handle then return end
    StopParticleFxLooped(handle, false)
    s.ptfx[key] = nil
end

--[[
 __          __              _
 \ \        / /             (_)
  \ \  /\  / /_ _ _ __ _ __  _ _ __   __ _ ___
   \ \/  \/ / _` | '__| '_ \| | '_ \ / _` / __|
    \  /\  / (_| | |  | | | | | | | | (_| \__ \
     \/  \/ \__,_|_|  |_| |_|_|_| |_|\__, |___/
                                      __/ |
                                     |___/
]]--

local function collectStates(s)
    local states = {}
    for _, kind in ipairs({ "core", "service" }) do
        local defs = kind == "core" and Config.CoreParts or Config.ServiceParts
        for key, value in pairs(s.data[kind] or {}) do
            local def = defs[key]
            if def and not (def.requiresTurbo and not s.hasTurbo) then
                states[kind..":"..key] = { kind = kind, label = def.label, state = Utils.GetPartState(value) }
            end
        end
    end
    return states
end

-- initial = driver just got in (dashboard summary), otherwise only parts that got worse
local function checkWarnings(s, initial)
    local cfg = Config.Effects.Notify or {}
    local states = collectStates(s)
    local minIndex = {
        core = STATE_INDEX[initial and cfg.enterCore or cfg.changeCore] or 4,
        service = STATE_INDEX[initial and cfg.enterService or cfg.changeService] or 4,
    }
    local lists = { core = {}, service = {} }

    for id, info in pairs(states) do
        local index = STATE_INDEX[info.state]
        local previous = s.states and s.states[id]
        local before = previous and STATE_INDEX[previous.state] or 0
        if index >= minIndex[info.kind] and (initial or index > before) then
            table.insert(lists[info.kind], {
                index = index,
                text = locale("veh_part_state", info.label, locale("state_"..info.state)),
            })
        end
    end
    s.states = states
    if initial and not cfg.onEnter then return end

    local texts = {}
    for kind, list in pairs(lists) do
        table.sort(list, function(a, b) return a.index > b.index end)
        local parts = {}
        for _, v in ipairs(list) do
            parts[#parts + 1] = v.text
        end
        texts[kind] = table.concat(parts, ", ")
    end
    if texts.core ~= "" then
        notify(locale("veh_check_engine", texts.core), "error")
    end
    if texts.service ~= "" then
        notify(locale("veh_service_due", texts.service), "inform")
    end
end

local function refreshProfile(s)
    local initial = not s.initialized
    s.initialized = true
    s.dirty = false
    local old = s.profile
    s.profile = buildProfile(s)
    local p = s.profile
    applyHandling(s)
    applyTopSpeed(s)
    if not initial then
        if p.noStart and old.noStart ~= p.noStart then
            notify(locale(p.noStart), "error")
        end
        if p.noDrive and old.noDrive ~= p.noDrive then
            notify(locale(p.noDrive), "error")
        end
    end
    if not p.smoke then
        stopParticle(s, "smoke")
    end
    if not p.temperature then
        s.overheat = false
        s.overheatLock = false
        stopParticle(s, "steam")
    end
    checkWarnings(s, initial)
end

--[[
  __  __ _ _
 |  \/  (_) |
 | \  / |_| | ___  __ _  __ _  ___
 | |\/| | | |/ _ \/ _` |/ _` |/ _ \
 | |  | | | |  __/ (_| | (_| |  __/
 |_|  |_|_|_|\___|\__,_|\__, |\___|
                         __/ |
                        |___/
]]--

-- flush = driver left the vehicle (server saves it)
local function sendMileage(s, flush)
    local km = s.pendingKm
    if not flush and km < 0.001 then return end
    local now = GetGameTimer()
    local overheat = Utils.Round(s.overheatSeconds, 1)
    s.pendingKm = 0.0
    s.overheatSeconds = 0.0
    s.lastSend = now

    if DoesEntityExist(s.vehicle) then
        s.mods = readMods(s.vehicle)
        -- degraded traction battery = shorter range
        if km > 0 and s.data.ev and s.profile and s.profile.evDrain > 0 and Config.SetFuel then
            local fuel = GetVehicleFuelLevel(s.vehicle)
            Config.SetFuel(s.vehicle, math.max(0.0, fuel - s.profile.evDrain * km))
        end
    end
    if km > 0 then
        s.awaitKm = km
        s.awaitFrom = s.data.mileage
        s.awaitUntil = now + AWAIT_TIMEOUT_MS
    end

    local netId, plate, mods = s.netId, s.plate, s.mods
    local extra = { overheat = overheat }
    CreateThread(function()
        if flush then
            TriggerSecureEvent("pls_mechanic:server:vehicles:left", netId, plate, km, mods, extra)
        else
            TriggerSecureEvent("pls_mechanic:server:vehicles:mileage", netId, km, mods, extra)
        end
    end)
end

local function currentMileage(s, now)
    local km = (s.data.mileage or 0.0) + s.pendingKm
    if s.awaitKm > 0 then
        if s.data.mileage == s.awaitFrom and now < s.awaitUntil then
            km = km + s.awaitKm
        else
            s.awaitKm = 0.0
        end
    end
    return km
end

-- Top left corner of the minimap (default GTA HUD layout)
local function refreshAnchor()
    local safezone = GetSafeZoneSize()
    local resX, resY = GetActiveScreenResolution()
    local xScale, yScale = 1.0 / resX, 1.0 / resY
    local height = yScale * (resY / 5.674)
    local margin = 0.05 * math.abs(safezone - 1.0) * 10
    local left = xScale * (resX * margin)
    local bottom = 1.0 - yScale * (resY * margin)
    Anchor.x = left + 0.0015
    Anchor.y = bottom - height - 0.032
end

local function drawMileage(s, now)
    if IsHudHidden() or IsRadarHidden() or IsPauseMenuActive() then return end
    if now >= Anchor.refreshAt then
        Anchor.refreshAt = now + 5000
        refreshAnchor()
    end
    local km = currentMileage(s, now)
    local value = Config.MileageUnit == "mi" and km * 0.621371 or km
    value = math.floor(value * 10) / 10
    if value ~= s.odoValue then
        s.odoValue = value
        s.odoText = locale("veh_odometer", formatDistance(value), locale(Config.MileageUnit == "mi" and "veh_unit_mi" or "veh_unit_km"))
    end
    SetTextFont(4)
    SetTextScale(0.0, 0.36)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextDropShadow()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(s.odoText)
    EndTextCommandDisplayText(Anchor.x, Anchor.y)
end

--[[
   _____      _ _ _     _
  / ____|    | | (_)   (_)
 | |     ___ | | |_ ___ _  ___  _ __  ___
 | |    / _ \| | | / __| |/ _ \| '_ \/ __|
 | |___| (_) | | | \__ \ | (_) | | | \__ \
  \_____\___/|_|_|_|___/_|\___/|_| |_|___/

 Impact = collision flag or health drop. Velocity change is measured shortly after the impact,
 zone comes from its direction in the vehicle frame before the impact.
]]--

local function sendCollision(s, severity, zone)
    local netId = s.netId
    CreateThread(function()
        TriggerSecureEvent("pls_mechanic:server:vehicles:collision", netId, severity, zone)
    end)
end

local function detectCollision(s, now)
    local c = s.col
    local vehicle = s.vehicle
    local vel = GetEntityVelocity(vehicle)
    local body = GetVehicleBodyHealth(vehicle)
    local engine = GetVehicleEngineHealth(vehicle)

    if c.pending then
        local p = c.pending
        if now >= p.resolveAt then
            c.pending = nil
            c.cooldownUntil = now + Config.Effects.Collision.cooldown
            local fx, fy = p.forward.x, p.forward.y
            local length = math.sqrt(fx * fx + fy * fy)
            if length > 0.01 then
                fx, fy = fx / length, fy / length
                local dvx, dvy = vel.x - p.vel.x, vel.y - p.vel.y
                local forward = dvx * fx + dvy * fy
                local right = dvx * fy - dvy * fx
                local severity = math.sqrt(forward * forward + right * right) * KMH
                local speedLoss = (math.sqrt(p.vel.x ^ 2 + p.vel.y ^ 2) - math.sqrt(vel.x ^ 2 + vel.y ^ 2)) * KMH
                local healthDrop = (p.body - body) + (p.engine - engine)
                local minSeverity = Config.CollisionDamage.minSeverity
                if severity >= minSeverity and (healthDrop > 0.5 or speedLoss >= minSeverity) then
                    local zone
                    if math.abs(forward) >= math.abs(right) then
                        zone = forward < 0 and "front" or "rear"
                    else
                        zone = right < 0 and "right" or "left"
                    end
                    sendCollision(s, math.min(math.floor(severity + 0.5), 200), zone)
                end
            end
        end
    elseif now >= c.cooldownUntil and (HasEntityCollidedWithAnything(vehicle) or body < c.body - 0.5 or engine < c.engine - 0.5) then
        c.pending = { vel = c.vel, forward = c.forward, body = c.body, engine = c.engine, resolveAt = now + Config.Effects.Collision.window }
    end

    c.vel = vel
    c.forward = GetEntityForwardVector(vehicle)
    c.body = body
    c.engine = engine
end

--[[
  ______  __  __          _
 |  ____|/ _|/ _|        | |
 | |__  | |_| |_ ___  ___| |_ ___
 |  __| |  _|  _/ _ \/ __| __/ __|
 | |____| | | ||  __/ (__| |_\__ \
 |______|_| |_| \___|\___|\__|___/
]]--

-- No start (broken part / overheated), slow cranking (weak battery)
local function handleEngineStart(s, now, engineOn)
    local p = s.profile
    local c = s.crank
    local reason = p.noStart or (s.overheatLock and "veh_overheat_locked") or nil

    if reason then
        c.phase = nil
        setUndriveable(s, true)
        if IsControlJustPressed(0, 71) and now >= s.notifyAt.start then
            s.notifyAt.start = now + 5000
            notify(locale(reason), "error")
        end
        return
    end

    if not p.crank then
        c.phase = nil
        setUndriveable(s, false)
        return
    end

    if c.phase == nil then
        if engineOn then
            setUndriveable(s, false)
        else
            -- engine turns over only, start attempt = throttle
            setUndriveable(s, true)
            if IsControlJustPressed(0, 71) then
                c.phase = "cranking"
                c.untilTime = now + math.floor((p.crank.delay or 1000) * (0.75 + math.random() * 0.5))
            end
        end
    elseif c.phase == "cranking" then
        if now >= c.untilTime then
            if math.random() >= (p.crank.failChance or 0.0) then
                c.phase = "starting"
                c.untilTime = now + 2000
                setUndriveable(s, false)
                SetVehicleEngineOn(s.vehicle, true, false, false)
            else
                c.phase = "retry"
                c.untilTime = now + 1500
                notify(locale("veh_crank_failed"), "error")
            end
        end
    elseif now >= c.untilTime or (c.phase == "starting" and engineOn) then
        c.phase = nil
    end
end

local function updateTemperature(s, dt, speed, engineOn)
    local cfg = Config.Effects.Temperature
    if not s.profile.temperature then return end
    local kmh = speed * KMH
    local temp = s.temp

    if engineOn then
        local rpm = GetVehicleCurrentRpm(s.vehicle)
        local throttle = GetControlNormal(0, 71)
        local heat = cfg.heatIdle + cfg.heatLoad * rpm * (0.4 + 0.6 * throttle)
        local cooling = s.profile.cooling * (cfg.coolBase + cfg.coolAirflow * math.min(kmh / 80.0, 1.0))
        if temp < cfg.normal then
            -- warming up with closed thermostat
            temp = temp + heat * dt
            if temp > cfg.normal and cooling >= heat then temp = cfg.normal end
        else
            temp = math.max(cfg.normal, temp + (heat - cooling) * dt)
        end
    else
        local rate = cfg.coolOff * (1.0 + math.min(kmh / 50.0, 1.0))
        temp = temp - (temp - cfg.ambient) * rate * dt
    end
    s.temp = Utils.Clamp(temp, cfg.ambient, cfg.max)

    if engineOn and s.temp >= cfg.overheat then
        s.overheatSeconds = s.overheatSeconds + dt
    end

    if not s.tempWarned and s.temp >= cfg.warn then
        s.tempWarned = true
        notify(locale("veh_temp_high"), "error")
    elseif s.tempWarned and s.temp < cfg.warn - 8.0 then
        s.tempWarned = false
    end

    if not s.overheat and s.temp >= cfg.overheat then
        s.overheat = true
        notify(locale("veh_overheated"), "error")
    elseif s.overheat and s.temp < cfg.overheat - 5.0 then
        s.overheat = false
    end
    if s.overheat then
        startParticle(s, "steam")
    elseif s.ptfx.steam then
        stopParticle(s, "steam")
    end

    if not s.overheatLock and s.temp >= cfg.shutdown then
        s.overheatLock = true
        notify(locale("veh_overheat_shutdown"), "error")
    elseif s.overheatLock and s.temp <= cfg.restart then
        s.overheatLock = false
        notify(locale("veh_cooled"), "success")
    end
end

local function updateLights(s, now)
    local fx = s.profile.lights
    local mult = 1.0
    if fx then
        mult = fx.dim or 1.0
        if now < s.flickerUntil then
            mult = mult * 0.15
        elseif (fx.flicker or 0) > 0 and math.random() < fx.flicker then
            s.flickerUntil = now + math.random(60, 180)
            mult = mult * 0.15
        end
    end
    if s.lightMult ~= mult and (fx or s.lightMult) then
        SetVehicleLightMultiplier(s.vehicle, mult + 0.0)
        s.lightMult = mult
    end
end

local function burstTyre(s)
    local vehicle = s.vehicle
    if not GetVehicleTyresCanBurst(vehicle) then return end
    local wheels = s.wheels == 2 and { 0, 4 } or { 0, 1, 4, 5 }
    local candidates = {}
    for _, index in ipairs(wheels) do
        if not IsVehicleTyreBurst(vehicle, index, false) then
            candidates[#candidates + 1] = index
        end
    end
    if #candidates == 0 then return end
    SetVehicleTyreBurst(vehicle, candidates[math.random(#candidates)], false, 1000.0)
    notify(locale("veh_tyre_burst"), "error")
end

-- Natives that must be called every frame
local function applyFrameEffects(s, now, speed)
    local p = s.profile
    local vehicle = s.vehicle

    if p.noDrive then
        DisableControlAction(0, 71, true)
        if speed < 1.5 then
            DisableControlAction(0, 72, true)
        end
        if IsDisabledControlJustPressed(0, 71) and now >= s.notifyAt.drive then
            s.notifyAt.drive = now + 5000
            notify(locale(p.noDrive), "error")
        end
    else
        local power = p.power
        if s.overheat then
            power = power * Config.Effects.Temperature.overheatPower
        end
        if p.slip and GetControlNormal(0, 71) >= (p.slip.throttle or 0.8) then
            power = power * (p.slip.power or 1.0)
        end
        if now < s.cutUntil then
            power = power * s.cutPower
        end
        if power < 0.999 and not ExternalPower then
            SetPowerMultiplier(vehicle, power + 0.0)
        end
    end

    if (p.pull > 0.0 or p.wobble > 0.0) and speed * KMH >= Config.Effects.Steering.minSpeed and math.abs(GetControlNormal(0, 59)) < 0.05 then
        local wobble = p.wobble * math.sin(now / 1000.0 * Config.Effects.Steering.wobbleFrequency * 2.0 * math.pi + s.wobblePhase)
        SetVehicleSteerBias(vehicle, p.pull * s.pullSign + wobble)
    end
end

-- Random / periodic effects
local function applyTimedEffects(s, now, speed, engineOn)
    local p = s.profile
    local t = s.timers
    local intervals = Config.Effects.Intervals
    local vehicle = s.vehicle
    local kmh = speed * KMH

    if now >= t.turbo then
        t.turbo = now + intervals.turbo
        local turbo = IsToggleModOn(vehicle, TURBO_MOD)
        if turbo ~= s.hasTurbo then
            s.hasTurbo = turbo
            s.dirty = true
        end
    end

    if now >= t.temp then
        local dt = math.min((now - s.tempAt) / 1000.0, 2.0)
        s.tempAt = now
        t.temp = now + 250
        updateTemperature(s, dt, speed, engineOn)
    end

    if not engineOn then
        -- no stall right after restart
        t.stall = now + intervals.stall
    elseif now >= t.stall then
        t.stall = now + intervals.stall
        for _, stall in ipairs(p.stall) do
            if kmh <= (stall.maxSpeed or 10000) and math.random() < (stall.chance or 0.0) then
                SetVehicleEngineOn(vehicle, false, true, false)
                notify(locale("veh_stalled"), "error")
                break
            end
        end
    end

    if now >= t.stutter then
        t.stutter = now + intervals.stutter
        if engineOn and now >= s.cutUntil and #p.stutter > 0 and GetControlNormal(0, 71) > 0.2 then
            local rpm = GetVehicleCurrentRpm(vehicle)
            for _, stutter in ipairs(p.stutter) do
                if rpm >= (stutter.rpm or 0.0) and math.random() < (stutter.chance or 0.0) then
                    s.cutUntil = now + (stutter.duration or 300)
                    s.cutPower = stutter.power or 0.3
                    break
                end
            end
        end
    end

    if now >= t.lights then
        t.lights = now + intervals.lights
        updateLights(s, now)
    end

    if now >= t.burst then
        t.burst = now + intervals.burst
        if p.burst and kmh >= (p.burst.speed or 0) and math.random() < (p.burst.chance or 0.0) then
            burstTyre(s)
        end
    end

    if p.smoke and engineOn then
        startParticle(s, "smoke")
    elseif s.ptfx.smoke then
        stopParticle(s, "smoke")
    end
end

--[[
  _____       _
 |  __ \     (_)
 | |  | |_ __ ___   _____ _ __
 | |  | | '__| \ \ / / _ \ '__|
 | |__| | |  | |\ V /  __/ |
 |_____/|_|  |_| \_/ \___|_|
]]--

local function initialTemperature(plate, vehicle)
    local cfg = Config.Effects.Temperature
    local saved = Temperatures[plate]
    if saved then
        local elapsed = (GetGameTimer() - saved.time) / 1000.0
        return cfg.ambient + (saved.value - cfg.ambient) * math.exp(-cfg.coolOff * elapsed)
    end
    -- running engine = warm engine
    return GetIsVehicleEngineRunning(vehicle) and cfg.normal or cfg.ambient
end

local function startSession(vehicle, data)
    local now = GetGameTimer()
    local intervals = Config.Effects.Intervals
    local plate = Utils.TrimPlate(GetVehicleNumberPlateText(vehicle)) or ""
    return {
        vehicle = vehicle,
        netId = VehToNet(vehicle),
        plate = plate,
        data = data,
        dirty = true,
        initialized = false,
        profile = newProfile(),
        hasTurbo = IsToggleModOn(vehicle, TURBO_MOD),
        wheels = GetVehicleNumberOfWheels(vehicle),
        mods = readMods(vehicle),
        -- mileage
        pendingKm = 0.0,
        lastSend = now,
        lastTick = now,
        awaitKm = 0.0,
        awaitFrom = 0.0,
        awaitUntil = 0,
        odoValue = nil,
        odoText = "",
        -- applied natives
        handling = {},
        topSpeed = nil,
        lightMult = nil,
        undriveable = false,
        ptfx = {},
        -- effects runtime
        flickerUntil = 0,
        cutUntil = 0,
        cutPower = 1.0,
        crank = { phase = nil, untilTime = 0 },
        temp = initialTemperature(plate, vehicle),
        tempAt = now,
        tempWarned = false,
        overheat = false,
        overheatLock = false,
        overheatSeconds = 0.0,
        pullSign = joaat(plate) % 2 == 0 and 1.0 or -1.0,
        wobblePhase = math.random() * math.pi * 2.0,
        timers = { stall = now + intervals.stall, stutter = now, lights = now, burst = now + intervals.burst, turbo = now + intervals.turbo, temp = now },
        notifyAt = { start = 0, drive = 0 },
        states = nil,
        col = {
            vel = GetEntityVelocity(vehicle),
            forward = GetEntityForwardVector(vehicle),
            body = GetVehicleBodyHealth(vehicle),
            engine = GetVehicleEngineHealth(vehicle),
            cooldownUntil = now + 1000,
            pending = nil,
        },
    }
end

-- Restores everything applied on the vehicle
local function restoreVehicle(s)
    for key in pairs(s.ptfx) do
        stopParticle(s, key)
    end
    if not DoesEntityExist(s.vehicle) then return end
    restoreHandling(s)
    if s.topSpeed then
        SetVehicleMaxSpeed(s.vehicle, 0.0)
        s.topSpeed = nil
    end
    if s.lightMult then
        SetVehicleLightMultiplier(s.vehicle, 1.0)
        s.lightMult = nil
    end
    if s.undriveable then
        SetVehicleUndriveable(s.vehicle, false)
        s.undriveable = false
    end
end

local function endSession(s)
    if Active == s then Active = nil end
    local now = GetGameTimer()
    Temperatures[s.plate] = { value = s.temp, time = now }
    for plate, saved in pairs(Temperatures) do
        if now - saved.time > 1800000 then
            Temperatures[plate] = nil
        end
    end
    sendMileage(s, true)
    restoreVehicle(s)
end

local function driveLoop(vehicle)
    local plate = Utils.TrimPlate(GetVehicleNumberPlateText(vehicle))
    local data = Entity(vehicle).state[STATE_KEY]
    if type(data) ~= "table" or data.plate ~= plate then
        local reason
        for _ = 1, 3 do
            data, reason = lib.callback.await("pls_mechanic:server:vehicles:init", false, VehToNet(vehicle), GetVehicleClass(vehicle))
            if data or reason ~= "busy" then break end
            Wait(1000)
        end
        if type(data) ~= "table" then
            Excluded[vehicle] = GetGameTimer() + 60000
            if DriverVehicle == vehicle then DriverVehicle = nil end
            return
        end
    end
    if DriverVehicle ~= vehicle or cache.vehicle ~= vehicle or cache.seat ~= -1 or not DoesEntityExist(vehicle) then
        if DriverVehicle == vehicle then DriverVehicle = nil end
        return
    end

    local s = startSession(vehicle, data)
    Active = s
    local syncMs = Config.Mileage.syncInterval * 1000
    local maxSpeed = Config.Mileage.maxSpeed / KMH

    while DriverVehicle == vehicle and cache.vehicle == vehicle and cache.seat == -1 and DoesEntityExist(vehicle) do
        local now = GetGameTimer()
        local dt = math.min((now - s.lastTick) / 1000.0, 1.0)
        s.lastTick = now
        if s.dirty then
            refreshProfile(s)
        end

        local engineOn = GetIsVehicleEngineRunning(vehicle)
        local speed = GetEntitySpeed(vehicle)

        if engineOn then
            s.pendingKm = s.pendingKm + math.min(speed, maxSpeed) * dt / 1000.0
        end
        if now - s.lastSend >= MIN_SEND_MS and (s.pendingKm >= Config.Mileage.syncDistance or (now - s.lastSend >= syncMs and s.pendingKm >= 0.001)) then
            sendMileage(s, false)
        end

        detectCollision(s, now)
        handleEngineStart(s, now, engineOn)
        applyFrameEffects(s, now, speed)
        applyTimedEffects(s, now, speed, engineOn)
        if Config.ShowMileage then
            drawMileage(s, now)
        end

        local p = s.profile
        local idle = not Config.ShowMileage and not engineOn and speed < 0.5 and not p.noStart and not p.crank and not p.noDrive and not s.overheatLock
        Wait(idle and 200 or 0)
    end

    endSession(s)
    if DriverVehicle == vehicle then DriverVehicle = nil end
end

-- Starts / stops driver loop by cache.vehicle + cache.seat
function VehicleState.CheckDriver()
    local vehicle = cache.vehicle
    if not vehicle or cache.seat ~= -1 then
        DriverVehicle = nil
        return
    end
    if DriverVehicle == vehicle or not DoesEntityExist(vehicle) then return end
    local skipUntil = Excluded[vehicle]
    if skipUntil then
        if skipUntil > GetGameTimer() then return end
        Excluded[vehicle] = nil
    end
    if Config.ExcludedClasses[GetVehicleClass(vehicle)] then return end
    if not NetworkGetEntityIsNetworked(vehicle) then return end
    DriverVehicle = vehicle
    CreateThread(function()
        driveLoop(vehicle)
    end)
end

lib.onCache("vehicle", function()
    SetTimeout(0, VehicleState.CheckDriver)
end)

lib.onCache("seat", function()
    SetTimeout(0, VehicleState.CheckDriver)
end)

CreateThread(function()
    Wait(1000)
    VehicleState.CheckDriver()
end)

-- Server pushed new condition (mileage, wear, repair, collision)
AddStateBagChangeHandler(STATE_KEY, nil, function(bagName, _, value)
    local s = Active
    if not s or type(value) ~= "table" then return end
    if GetEntityFromStateBagName(bagName) ~= s.vehicle then return end
    s.data = value
    s.dirty = true
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Active then
        restoreVehicle(Active)
    end
end)

-- Admin fix (/mechanicadminfix): mechanic parts were reset on the server, native damage is repaired here
RegisterNetEvent("pls_mechanic:client:vehicles:adminFix", function(netId)
    if type(netId) ~= "number" or not NetworkDoesEntityExistWithNetworkId(netId) then
        return notify(locale("no_vehicle"), "error")
    end
    local vehicle = NetToVeh(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not Core.RequestControl(vehicle, 3000) then
        return notify(locale("no_control"), "error")
    end
    local dirt, fuel = GetVehicleDirtLevel(vehicle), GetVehicleFuelLevel(vehicle)
    -- SetVehicleFixed doesn't work on vehicle with broken engine
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    SetVehicleUndriveable(vehicle, false)
    SetVehicleDirtLevel(vehicle, dirt)
    SetVehicleFuelLevel(vehicle, fuel)
    notify(locale("admin_fix_done", Utils.TrimPlate(GetVehicleNumberPlateText(vehicle))), "success")
end)

--[[
           _____ _____
     /\   |  __ \_   _|
    /  \  | |__) || |
   / /\ \ |  ___/ | |
  / ____ \| |    _| |_
 /_/    \_\_|   |_____|
]]--

-- Mileage in km (includes not yet synced km of the current vehicle). nil = no data
function VehicleState.GetMileage(vehicle)
    vehicle = vehicle or cache.vehicle
    if not vehicle or not DoesEntityExist(vehicle) then return nil end
    local s = Active
    if s and s.vehicle == vehicle then
        return Utils.Round(currentMileage(s, GetGameTimer()), 1)
    end
    local data = Entity(vehicle).state[STATE_KEY]
    return type(data) == "table" and data.mileage or nil
end

-- Engine temperature (°C) of the vehicle the player drives, nil when not simulated
function VehicleState.GetTemperature(vehicle)
    local s = Active
    if not s or (vehicle and s.vehicle ~= vehicle) or not s.profile.temperature then return nil end
    return Utils.Round(s.temp, 1)
end

-- Another resource drives the engine power this frame (nitro boost), worn engine power is not applied meanwhile
function VehicleState.SetExternalPower(active)
    ExternalPower = active == true
end

-- Vehicle the player currently drives with active condition model (or nil)
function VehicleState.GetDrivenVehicle()
    return Active and Active.vehicle or nil
end

exports("GetVehicleMileage", function(vehicle)
    return VehicleState.GetMileage(vehicle)
end)
