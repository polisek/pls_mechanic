--[[
  ______  __  __          _
 |  ____|/ _|/ _|        | |
 | |__  | |_| |_ ___  ___| |_ ___
 |  __| |  _|  _/ _ \/ __| __/ __|
 | |____| | | ||  __/ (__| |_\__ \
 |______|_| |_| \___|\___|\__|___/

 Malfunction effects of worn / damaged parts. Applied only by the driver of the vehicle.
 Part states come from Config.PartStates (configs/parts.lua).
]]--

Config.Effects = {}

-- false = parts still wear and break, but the driver doesn't feel any effect
Config.Effects.Enabled = true

-- Notifications for the driver (state = "worn" / "critical" / "failed")
Config.Effects.Notify = {
    onEnter = true,             -- dashboard warnings when the driver gets in
    enterCore = "critical",     -- core parts in this state or worse are reported on enter
    enterService = "failed",    -- service parts in this state or worse are reported on enter
    changeCore = "worn",        -- core part got worse to this state or worse while driving
    changeService = "critical", -- service part got worse to this state or worse while driving
}

-- How often (ms) random effects are rolled
Config.Effects.Intervals = {
    stall = 5000,     -- engine stall chance
    stutter = 400,    -- power cuts / misfires
    lights = 120,     -- light flicker
    burst = 10000,    -- tyre blowout chance
    turbo = 2000,     -- check of installed turbo (tuning can change it while sitting inside)
}

-- Collision detection (client)
Config.Effects.Collision = {
    window = 200,     -- ms after the impact when the speed change is measured
    cooldown = 750,   -- ms between two reported impacts
}

-- Steering pull (alignment) and wobble (suspension) apply only when the driver doesn't steer
Config.Effects.Steering = {
    minSpeed = 25.0,         -- km/h
    wobbleFrequency = 1.3,   -- Hz
}

-- Engine temperature simulation (combustion engines only). Units: °C and °C per second.
Config.Effects.Temperature = {
    enabled = true,
    ambient = 20.0,
    normal = 90.0,            -- thermostat temperature
    max = 140.0,
    heatIdle = 0.5,           -- heat produced at idle
    heatLoad = 3.0,           -- extra heat at full rpm and full throttle
    coolBase = 2.2,           -- heat removed by healthy cooling while standing
    coolAirflow = 1.8,        -- extra heat removed at 80 km/h and more
    coolOff = 0.015,          -- engine off: part of the difference to ambient lost per second
    warn = 110.0,             -- warning notification
    overheat = 120.0,         -- steam from the engine bay + power cut
    overheatPower = 0.55,     -- power multiplier while overheated
    shutdown = 130.0,         -- engine shuts down and can't be started...
    restart = 105.0,          -- ...until it cools down to this temperature
    engineDamagePerMinute = 2.0, -- % of engine health lost per minute of overheating (server)
}

-- Looped particles on the engine bone (asset / name from the "core" dictionary can be replaced)
Config.Effects.Particles = {
    networked = true,         -- other players see the smoke / steam too
    smoke = { asset = "core", name = "ent_amb_generator_smoke", scale = 0.5, offset = vec3(0.0, 0.0, 0.25) },
    steam = { asset = "core", name = "ent_amb_steam_vent_open_lgt", scale = 0.6, offset = vec3(0.0, 0.0, 0.3) },
}

-- Extra wear calculated by the server for every driven km (% per km)
Config.Effects.Wear = {
    -- natural aging of core parts (multiplied by Config.ClassWear)
    coreAging = { clutch = 0.002, suspension = 0.0015, battery = 0.004, ev_battery = 0.001 },
    -- engine damage while the radiator is in this state
    radiatorEngine = { critical = 0.01, failed = 0.03 },
    -- battery drained by a bad alternator (the battery is not charged)
    alternatorBattery = { worn = 0.01, critical = 0.04, failed = 0.12 },
}

--[[
 Effects per part and state. Keys = Config.ServiceParts / Config.CoreParts keys.
 States: worn / critical / failed, "empty" = value is exactly 0 (replaces "failed", doesn't merge with it).
 Turbo effects apply only when the turbo mod is installed.

 power    = engine power multiplier (1.0 = normal)
 topSpeed = max speed in km/h (limp mode)
 brake    = brake force multiplier
 grip     = tyre grip multiplier
 shift    = gear shift speed multiplier
 pull     = steering pull to one side (0.0 - 0.2)
 wobble   = steering wobble amplitude (0.0 - 0.2)
 cooling  = engine cooling capacity multiplier (temperature simulation)
 stall    = { chance = 0-1 per check, maxSpeed = km/h (nil = any speed) }
 stutter  = { rpm = 0-1, chance = 0-1 per check, duration = ms, power = multiplier during the cut }
 slip     = { throttle = 0-1, power = multiplier }   clutch slips when throttle is above the value
 crank    = { delay = ms, failChance = 0-1 }         slow start, start can fail
 noStart  = locale key, engine can't be started
 noDrive  = locale key, engine runs but the vehicle can't drive
 lights   = { dim = light multiplier, flicker = 0-1 chance per lights tick }
 smoke    = true, smoke from the engine bay while the engine runs
 burst    = { speed = km/h, chance = 0-1 per check }  tyre blowout
 evDrain  = extra battery charge (fuel %) used per km, electric vehicles only
]]--

Config.Effects.Parts = {
    ------------------------------------------------------------------ core
    engine = {
        worn     = { power = 0.9 },
        critical = { power = 0.7, smoke = true, stall = { chance = 0.06, maxSpeed = 30 }, stutter = { rpm = 0.0, chance = 0.05, duration = 350, power = 0.3 } },
        failed   = { noStart = "veh_nostart_engine", smoke = true },
    },
    transmission = {
        worn     = { shift = 0.7, power = 0.95 },
        critical = { shift = 0.45, power = 0.85, topSpeed = 70 },
        failed   = { noDrive = "veh_nodrive_transmission" },
    },
    clutch = {
        worn     = { slip = { throttle = 0.9, power = 0.85 } },
        critical = { slip = { throttle = 0.6, power = 0.6 }, shift = 0.75 },
        failed   = { noDrive = "veh_nodrive_clutch" },
    },
    radiator = {
        worn     = { cooling = 0.8 },
        critical = { cooling = 0.55 },
        failed   = { cooling = 0.3 },
    },
    alternator = {
        worn     = { lights = { dim = 0.9, flicker = 0.02 } },
        critical = { lights = { dim = 0.7, flicker = 0.08 } },
        failed   = { lights = { dim = 0.45, flicker = 0.2 } },
    },
    battery = {
        worn     = { crank = { delay = 800, failChance = 0.0 } },
        critical = { crank = { delay = 2000, failChance = 0.35 }, lights = { dim = 0.8 } },
        failed   = { noStart = "veh_nostart_battery", lights = { dim = 0.3 } },
    },
    fuel_pump = {
        worn     = { stutter = { rpm = 0.9, chance = 0.05, duration = 250, power = 0.4 } },
        critical = { stutter = { rpm = 0.75, chance = 0.15, duration = 400, power = 0.2 }, stall = { chance = 0.03 } },
        failed   = { noStart = "veh_nostart_fuel_pump" },
    },
    brakes = {
        worn     = { brake = 0.85 },
        critical = { brake = 0.6 },
        failed   = { brake = 0.3 },
    },
    suspension = {
        worn     = { wobble = 0.02 },
        critical = { wobble = 0.05, grip = 0.95 },
        failed   = { wobble = 0.09, grip = 0.88, topSpeed = 110 },
    },
    alignment = {
        worn     = { pull = 0.015 },
        critical = { pull = 0.04 },
        failed   = { pull = 0.08, grip = 0.95 },
    },
    turbo = {
        worn     = { power = 0.95 },
        critical = { power = 0.85, stutter = { rpm = 0.8, chance = 0.08, duration = 300, power = 0.6 } },
        failed   = { power = 0.78 },
    },
    ev_battery = {
        worn     = { power = 0.95, evDrain = 0.1 },
        critical = { power = 0.8, evDrain = 0.3, topSpeed = 100 },
        failed   = { noStart = "veh_nostart_ev_battery" },
    },
    ev_motor = {
        worn     = { power = 0.9 },
        critical = { power = 0.7, stutter = { rpm = 0.0, chance = 0.06, duration = 500, power = 0.2 } },
        failed   = { noStart = "veh_nostart_ev_motor" },
    },

    ------------------------------------------------------------------ service
    oil = {
        failed   = { power = 0.97 },
        empty    = { power = 0.9, stutter = { rpm = 0.8, chance = 0.05, duration = 300, power = 0.5 } },
    },
    air_filter = {
        critical = { power = 0.96 },
        failed   = { power = 0.9 },
    },
    fuel_filter = {
        failed   = { stutter = { rpm = 0.85, chance = 0.08, duration = 300, power = 0.4 } },
    },
    spark_plugs = {
        critical = { stutter = { rpm = 0.0, chance = 0.03, duration = 200, power = 0.5 } },
        failed   = { power = 0.92, stutter = { rpm = 0.0, chance = 0.08, duration = 250, power = 0.3 } },
    },
    coolant = {
        critical = { cooling = 0.85 },
        failed   = { cooling = 0.65 },
        empty    = { cooling = 0.4 },
    },
    brake_fluid = {
        critical = { brake = 0.9 },
        failed   = { brake = 0.75 },
    },
    transmission_fluid = {
        failed   = { shift = 0.8 },
    },
    brake_pads = {
        critical = { brake = 0.9 },
        failed   = { brake = 0.7 },
    },
    tyres = {
        worn     = { grip = 0.97 },
        critical = { grip = 0.9 },
        failed   = { grip = 0.82 },
        empty    = { grip = 0.75, burst = { speed = 120, chance = 0.04 } },
    },
    timing_belt = {
        empty    = { noStart = "veh_nostart_timing_belt" },
    },
    ev_coolant = {
        failed   = { power = 0.95 },
        empty    = { power = 0.85 },
    },
}
