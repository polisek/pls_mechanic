--[[
             _                 _   _
     /\     (_)               | | (_)
    /  \   _ __  _ _ __ ___   __ _| |_ _  ___  _ __  ___
   / /\ \ | '_ \| | '_ ` _ \ / _` | __| |/ _ \| '_ \/ __|
  / ____ \| | | | | | | | | | (_| | |_| | (_) | | | \__ \
 /_/    \_\_| |_|_|_| |_| |_|\__,_|\__|_|\___/|_| |_|___/

 Animations, props, sounds, particles and repair scenes used by client/animations.lua (global "Anim")
 and client/repair.lua. Every anim dict / clip, scenario, model, particle and sound below exists in the
 base game (DurtyFree GTA V data dumps). Swap anything for your own assets - keys stay the same.

 Anims     : { dict, clip, flag, blendIn?, blendOut?, enter?, exit?, freeze?, pose?, time?, release? } or { scenario }
             enter / exit = anim key played once when the anim starts / ends (not between phases that share it)
             pose = anims with the same pose switch directly (lying -> lying without getting up)
             lying = lying under the vehicle (spot next to the body, Settings.lie), freeze = ped frozen while playing
             time = ms of a one-shot anim, release = part of it (0-1) when a put down / picked up prop changes
 Props     : same format as Config.Props (config.lua): { model, bone, pos, rot } + ground = { z, rot } for
             props left on the ground. String prop keys are looked up in Config.Props first, then here.
 Sounds    : { name, set, bank?, frontend?, interval?, length?, network? }
             bank = script audio bank(s) loaded for the sound, interval = repeat every x ms,
             length = stop the sound after x ms (needed for looping sounds), frontend = 2D sound (only you hear it)
 Particles : { asset, name, entity?, bone?, offset?, rot?, scale?, looped?, interval?, length? }
             entity = "ped" (default) | "prop" (hand prop) | "vehicle" (vehicle you work on)
]]--

Config.Animations = {}

Config.Animations.Settings = {
    progressPosition = "bottom",   -- ox_lib progress circle position ("middle" / "bottom")
    walkSpeed = 1.0,               -- 1.0 walk, 2.0 jog
    walkTimeout = 8000,            -- ms, max time to walk to a spot
    reachDistance = 1.2,           -- m, spot counts as reached within this distance
    networkProps = true,           -- hand / carried / ground props are networked (other players see them)
    networkParticles = true,       -- particles are networked (other players see them)
    groundCollision = false,       -- props left on the ground have collision (false = nobody gets stuck on them)
    toolbox = true,                -- mechanic puts a toolbox next to the vehicle for the whole repair workflow
    toolboxNeedsItem = true,       -- ... only when he has the toolbox item
    engineTest = true,             -- test run of the engine after battery / alternator / spark plugs / engine ... repairs
    -- Lying under the vehicle (anim "under"): ped stands this far outside the vehicle side and turns by
    -- "heading" degrees from facing the vehicle (180 = back to the vehicle, he lies down with the head under it)
    lie = { distance = 0.35, heading = 180.0 },
    -- Vehicle higher than this on a lift = mechanic works standing under it (anims are replaced by Overhead)
    overheadHeight = 1.6,
}

--[[
     _          _
    / \   _ __ (_)_ __ ___  ___
   / _ \ | '_ \| | '_ ` _ \/ __|
  / ___ \| | | | | | | | | \__ \
 /_/   \_\_| |_|_|_| |_| |_|___/
]]--

Config.Animations.Anims = {
    -- work poses
    hood        = { dict = "mini@repair", clip = "fixing_a_ped", flag = 1 },                          -- leaning into the engine bay
    side        = { dict = "mini@repair", clip = "fixing_a_player", flag = 1 },                       -- standing work on the body / door
    under       = { dict = "amb@world_human_vehicle_mechanic@male@base", clip = "base", flag = 1,      -- lying under the vehicle
                    pose = "lying", lying = true, freeze = true, blendIn = 2.0, enter = "kneel_enter", exit = "under_exit" },
    under_work  = { dict = "amb@world_human_vehicle_mechanic@male@idle_a", clip = "idle_a", flag = 1,  -- lying, working with the hands
                    pose = "lying", lying = true, freeze = true, blendIn = 2.0, enter = "kneel_enter", exit = "under_exit" },
    overhead    = { dict = "amb@prop_human_movie_bulb@base", clip = "base", flag = 1 },                -- standing under a lifted vehicle, arms up
    kneel       = { dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", clip = "machinic_loop_mechandplayer", flag = 1 }, -- crouched at the wheel
    kneel_low   = { dict = "amb@medic@standing@tendtodead@idle_a", clip = "idle_a", flag = 1, blendIn = 2.0 }, -- kneeling, hands on the ground
    crouch      = { dict = "anim@amb@inspect@crouch@male_a@base", clip = "base", flag = 1 },           -- crouched, inspecting
    pour        = { dict = "timetable@gardener@filling_can", clip = "gar_ig_5_filling_can", flag = 1 },  -- pouring fluid
    clean       = { dict = "timetable@floyd@clean_kitchen@base", clip = "base", flag = 1 },             -- wiping with sponge / rag
    tablet      = { dict = "amb@code_human_in_bus_passenger_idles@female@tablet@base", clip = "base", flag = 49 },
    button      = { dict = "anim@apt_trans@buzzer", clip = "buzz_reg", flag = 0 },                      -- pressing a panel button
    -- scenarios (own props / sounds / effects of the game)
    weld        = { scenario = "WORLD_HUMAN_WELDING" },
    hammer      = { scenario = "WORLD_HUMAN_HAMMERING" },
    scrub       = { scenario = "WORLD_HUMAN_MAID_CLEAN" },
    -- transitions and short actions
    kneel_enter = { dict = "amb@medic@standing@kneel@enter", clip = "enter", flag = 0, time = 1200 },
    under_exit  = { dict = "amb@world_human_vehicle_mechanic@male@exit", clip = "exit", flag = 0, time = 2600 },
    carry       = { dict = "anim@heists@box_carry@", clip = "idle", flag = 49 },
    putdown     = { dict = "pickup_object", clip = "putdown_low", flag = 0, time = 1300, release = 0.55 },
    pickup      = { dict = "pickup_object", clip = "pickup_low", flag = 0, time = 1300, release = 0.5 },
    putdown_case= { dict = "anim@heists@money_grab@briefcase", clip = "put_down_case", flag = 0, time = 1600, release = 0.6 },
}

-- Anim replacements when the vehicle is high on a lift (mechanic stands under it / at the raised wheel)
Config.Animations.Overhead = {
    hood = "overhead", under = "overhead", under_work = "overhead", kneel = "overhead",
    kneel_low = "overhead", crouch = "overhead", pour = "overhead", side = "overhead",
}

--[[
  ____
 |  _ \ _ __ ___  _ __  ___
 | |_) | '__/ _ \| '_ \/ __|
 |  __/| | | (_) | |_) \__ \
 |_|   |_|  \___/| .__/|___/
                 |_|
 Bones: 57005 right hand, 18905 left hand, 28422 right hand (prop), 60309 left hand (prop, used by box carry)
 Keys used from Config.Props (config.lua): wrench, impact_wrench, oil, scanner, toolbox, battery, tyre, crate
]]--

local CarryBone = 60309
local CarryPos = vec3(0.025, 0.08, 0.255)
local CarryRot = vec3(-145.0, 290.0, 0.0)

Config.Animations.Props = {
    -- hand tools
    screwdriver   = { model = "prop_tool_screwdvr01", bone = 57005, pos = vec3(0.10, 0.03, -0.02), rot = vec3(-90.0, 0.0, 0.0) },
    torque_wrench = { model = "gr_prop_gr_torque_wrench_01a", bone = 57005, pos = vec3(0.10, 0.02, -0.02), rot = vec3(-100.0, 0.0, 0.0) },
    grinder       = { model = "imp_prop_grinder_01a", bone = 57005, pos = vec3(0.12, 0.03, -0.02), rot = vec3(-90.0, 0.0, 0.0) },
    flashlight    = { model = "prop_cs_police_torch", bone = 57005, pos = vec3(0.12, 0.02, -0.02), rot = vec3(-90.0, 0.0, 0.0) },
    rag           = { model = "prop_rag_01", bone = 57005, pos = vec3(0.10, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
    sponge        = { model = "prop_sponge_01", bone = 28422, pos = vec3(0.0, 0.0, -0.01), rot = vec3(90.0, 0.0, 0.0) },
    coolant_can   = { model = "prop_ld_jerrycan_01", bone = 57005, pos = vec3(0.16, 0.0, -0.06), rot = vec3(-90.0, 0.0, 0.0) },
    jack_hand     = { model = "prop_carjack", bone = 57005, pos = vec3(0.30, 0.0, -0.05), rot = vec3(-90.0, 0.0, 90.0) },
    -- carried parts (box carry pose) - also left on the ground as old parts
    part_box      = { model = "prop_cs_cardbox_01", bone = CarryBone, pos = CarryPos, rot = CarryRot },
    wheel         = { model = "prop_wheel_01", bone = CarryBone, pos = vec3(0.05, 0.10, 0.25), rot = vec3(-145.0, 290.0, 0.0) },
    radiator      = { model = "imp_prop_impexp_radiator_01", bone = CarryBone, pos = CarryPos, rot = CarryRot },
    engine_part   = { model = "imp_prop_impexp_engine_part_01a", bone = CarryBone, pos = CarryPos, rot = CarryRot },
    gearbox       = { model = "imp_prop_impexp_gearbox_01", bone = CarryBone, pos = vec3(0.05, 0.10, 0.30), rot = CarryRot },
    brake_caliper = { model = "imp_prop_impexp_brake_caliper_01a", bone = CarryBone, pos = CarryPos, rot = CarryRot },
    ev_module     = { model = "prop_cs_power_cell", bone = CarryBone, pos = CarryPos, rot = CarryRot },
    ev_motor      = { model = "prop_etricmotor_01", bone = CarryBone, pos = vec3(0.05, 0.10, 0.30), rot = CarryRot },
    car_door      = { model = "imp_prop_impexp_car_door_01a", bone = CarryBone, pos = vec3(0.10, 0.20, 0.30), rot = CarryRot },
    bonnet        = { model = "imp_prop_impexp_bonnet_01a", bone = CarryBone, pos = vec3(0.10, 0.25, 0.30), rot = CarryRot },
    bumper_front  = { model = "imp_prop_impexp_front_bumper_01a", bone = CarryBone, pos = vec3(0.10, 0.20, 0.30), rot = CarryRot },
    bumper_rear   = { model = "imp_prop_impexp_rear_bumper_01a", bone = CarryBone, pos = vec3(0.10, 0.20, 0.30), rot = CarryRot },
    body_panel    = { model = "imp_prop_impexp_car_panel_01a", bone = CarryBone, pos = vec3(0.10, 0.20, 0.30), rot = CarryRot },
    glass_scrap   = { model = "prop_cs_glass_scrap", bone = CarryBone, pos = CarryPos, rot = CarryRot },
    -- ground props
    drain_pan     = { model = "prop_cs_bucket_s" },   -- catch container for old oil / fluids (replace with your own drain pan)
}

--[[
  ____                        _
 / ___|  ___  _   _ _ __   __| |___
 \___ \ / _ \| | | | '_ \ / _` / __|
  ___) | (_) | |_| | | | | (_| \__ \
 |____/ \___/ \__,_|_| |_|\__,_|___/
]]--

Config.Animations.Sounds = {
    -- short bursts of the Fleeca drill = pneumatic impact wrench
    impact   = { name = "Drill", set = "DLC_HEIST_FLEECA_SOUNDSET", bank = { "DLC_MPHEIST\\HEIST_FLEECA_DRILL", "DLC_MPHEIST\\HEIST_FLEECA_DRILL_2" }, interval = 2600, length = 1100, network = true },
    grinder  = { name = "Drill", set = "DLC_HEIST_FLEECA_SOUNDSET", bank = { "DLC_MPHEIST\\HEIST_FLEECA_DRILL", "DLC_MPHEIST\\HEIST_FLEECA_DRILL_2" }, interval = 1800, length = 1500, network = true },
    scanner  = { name = "NAV_UP_DOWN", set = "HUD_FRONTEND_DEFAULT_SOUNDSET", frontend = true, interval = 900 },  -- scanner beeps
    connect  = { name = "CONFIRM_BEEP", set = "HUD_MINI_GAME_SOUNDSET", frontend = true },                        -- device connected
    button   = { name = "SELECT", set = "HUD_FRONTEND_DEFAULT_SOUNDSET", frontend = true },
}

--[[
  ____            _   _      _
 |  _ \ __ _ _ __| |_(_) ___| | ___  ___
 | |_) / _` | '__| __| |/ __| |/ _ \/ __|
 |  __/ (_| | |  | |_| | (__| |  __/\__ \
 |_|   \__,_|_|   \__|_|\___|_|\___||___/
]]--

Config.Animations.Particles = {
    oil_drain     = { asset = "core", name = "veh_oil_leak", entity = "vehicle", bone = "engine", offset = vec3(0.0, 0.0, -0.45), scale = 1.6 },
    fluid_drain   = { asset = "core", name = "veh_oil_leak", entity = "vehicle", offset = vec3(0.0, 0.3, -0.35), scale = 1.4 },
    coolant_steam = { asset = "core", name = "ent_amb_steam", entity = "vehicle", bone = "engine", offset = vec3(0.0, 0.35, 0.35), scale = 0.35 },
    battery_spark = { asset = "core", name = "ent_brk_sparking_wires", entity = "prop", scale = 0.35, interval = 2200, length = 450 },
    grind_sparks  = { asset = "scr_reconstructionaccident", name = "scr_sparking_generator", entity = "prop", scale = 0.45, interval = 1800, length = 1500 },
    wash_water    = { asset = "core", name = "ent_amb_waterfall_splash_p", entity = "vehicle", offset = vec3(0.0, 0.0, 0.5), scale = 0.6 },
    wash_drips    = { asset = "core", name = "ent_amb_water_drips_sm", entity = "vehicle", offset = vec3(0.0, 0.0, 0.4), scale = 1.0 },
}

--[[
  ____
 / ___|  ___ ___ _ __   ___  ___
 \___ \ / __/ _ \ '_ \ / _ \/ __|
  ___) | (_|  __/ | | |  __/\__ \
 |____/ \___\___|_| |_|\___||___/

 Repair scenes. Key: "<kind>:<key>" (service:oil, core:battery, kit:repair_kit, body:bumper:front)
 then "body:<bodyKind>" (body:door) and "default:<access>" as fallback.
 wheels  = run the actions for every wheel: "step" (repaired wheel), "work" (jacked / closest wheel),
           "axle" (jacked wheel or both front wheels), "all" (every wheel)
 actions : { "open", door = "hood" | "trunk" | "driver" }                 open for access (closed after the workflow)
           { "walk", at = spot }                                           walk to a spot
           { "phase", label, weight, at, anim, prop, prop2, sound, particle } work phase with progress circle
               the configured part duration is split between phases by weight (total >= part duration = server check)
           { "remove", prop, at }                                          take out the old part and put it on the ground
           { "fetch", prop? }                                              take a new part at the toolbox (carried to the next phase)
           { "place", prop, at }                                           put a prop on the ground at a spot (drain pan)
           { "collect" }                                                   pick up props left on the ground (old parts, drain pan)
 after   : phases after the server confirmed the repair (fixed duration, engine = engine running = test run)
 spots   : access (step default), hood, trunk, wheel, under, under_front, under_rear, left, right, side (repaired door / window)
 Old parts left on the ground are picked up at the end of the step.
]]--

local EngineTest = { "phase", label = "repair_phase_engine_test", duration = 4000, at = "hood", anim = "hood", engine = true }
local WheelOff = { "phase", label = "repair_phase_wheel_off", weight = 2, at = "wheel", anim = "kneel", prop = "impact_wrench", sound = "impact" }
local WheelOn = { "phase", label = "repair_phase_wheel_on", weight = 2, at = "wheel", anim = "kneel", prop = "impact_wrench", sound = "impact" }
local BatteryOff = { "phase", label = "repair_phase_battery_disconnect", weight = 1, at = "hood", anim = "hood", prop = "wrench", particle = "battery_spark" }
local BatteryOn = { "phase", label = "repair_phase_battery_connect", weight = 1, at = "hood", anim = "hood", prop = "wrench", particle = "battery_spark" }
local EvIsolate = { "phase", label = "repair_phase_ev_isolate", weight = 1, at = "left", anim = "tablet", prop = "scanner", sound = "scanner" }
local EvCalibrate = { "phase", label = "repair_phase_ev_calibrate", weight = 1, at = "left", anim = "tablet", prop = "scanner", sound = "scanner" }

Config.Animations.Scenes = {
    --[[ Service parts ]]--
    ["service:oil"] = {
        actions = {
            { "open", door = "hood" },
            { "place", prop = "drain_pan", at = "under_front" },
            { "phase", label = "repair_phase_oil_drain", weight = 3, at = "under_front", anim = "under", prop = "wrench", particle = "oil_drain" },
            { "phase", label = "repair_phase_oil_filter", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_oil_fill", weight = 3, at = "hood", anim = "pour", prop = "oil" },
            { "phase", label = "repair_phase_oil_check", weight = 1, at = "hood", anim = "hood", prop = "rag" },
        },
    },
    ["service:air_filter"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_air_open", weight = 1, at = "hood", anim = "hood", prop = "screwdriver" },
            { "fetch" },
            { "phase", label = "repair_phase_air_replace", weight = 2, at = "hood", anim = "hood" },
            { "phase", label = "repair_phase_air_close", weight = 1, at = "hood", anim = "hood", prop = "screwdriver" },
        },
    },
    ["service:fuel_filter"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_fuel_relieve", weight = 1, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_fuel_filter_remove", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_fuel_filter_fit", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
        },
        after = { EngineTest },
    },
    ["service:spark_plugs"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_plugs_remove", weight = 3, at = "hood", anim = "hood", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_plugs_gap", weight = 1, at = "hood", anim = "hood", prop = "screwdriver" },
            { "phase", label = "repair_phase_plugs_fit", weight = 3, at = "hood", anim = "hood", prop = "torque_wrench" },
        },
        after = { EngineTest },
    },
    ["service:coolant"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_coolant_cap", weight = 1, at = "hood", anim = "hood", prop = "rag", particle = "coolant_steam" },
            { "fetch" },
            { "phase", label = "repair_phase_coolant_fill", weight = 3, at = "hood", anim = "pour", prop = "coolant_can" },
            { "phase", label = "repair_phase_coolant_bleed", weight = 1, at = "hood", anim = "hood" },
        },
    },
    ["service:brake_fluid"] = {
        wheels = "work",
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_brake_fluid_old", weight = 2, at = "hood", anim = "hood" },
            { "fetch" },
            { "phase", label = "repair_phase_brake_fluid_fill", weight = 2, at = "hood", anim = "pour", prop = "oil" },
            { "phase", label = "repair_phase_brake_bleed", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
        },
    },
    ["service:transmission_fluid"] = {
        actions = {
            { "place", prop = "drain_pan", at = "under" },
            { "phase", label = "repair_phase_trans_drain", weight = 3, at = "under", anim = "under", prop = "wrench", particle = "fluid_drain" },
            { "open", door = "hood" },
            { "fetch" },
            { "phase", label = "repair_phase_trans_fill", weight = 2, at = "hood", anim = "pour", prop = "oil" },
            { "phase", label = "repair_phase_trans_check", weight = 1, at = "hood", anim = "hood", prop = "rag" },
        },
    },
    ["service:brake_pads"] = {
        wheels = "axle",
        actions = {
            WheelOff,
            { "phase", label = "repair_phase_caliper_off", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_pads_fit", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
            WheelOn,
        },
    },
    ["service:tyres"] = {
        wheels = "all",
        actions = {
            WheelOff,
            { "remove", prop = "tyre", at = "wheel" },
            { "fetch", prop = "tyre" },
            { "phase", label = "repair_phase_tyre_mount", weight = 1, at = "wheel", anim = "kneel" },
            WheelOn,
            { "collect" },
        },
    },
    ["service:timing_belt"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_belt_covers", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_belt_tension", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_belt_fit", weight = 3, at = "hood", anim = "hood" },
            { "phase", label = "repair_phase_belt_align", weight = 2, at = "hood", anim = "hood", prop = "torque_wrench" },
            { "phase", label = "repair_phase_belt_covers_on", weight = 1, at = "hood", anim = "hood", prop = "wrench" },
        },
        after = { EngineTest },
    },
    ["service:ev_coolant"] = {
        actions = {
            EvIsolate,
            { "open", door = "hood" },
            { "fetch" },
            { "phase", label = "repair_phase_coolant_fill", weight = 3, at = "hood", anim = "pour", prop = "coolant_can" },
            { "phase", label = "repair_phase_coolant_bleed", weight = 1, at = "hood", anim = "hood" },
        },
    },

    --[[ Core parts ]]--
    ["core:engine"] = {
        actions = {
            { "open", door = "hood" },
            { "place", prop = "drain_pan", at = "under_front" },
            { "phase", label = "repair_phase_engine_drain", weight = 2, at = "under_front", anim = "under", prop = "wrench", particle = "oil_drain" },
            { "phase", label = "repair_phase_engine_disassemble", weight = 3, at = "hood", anim = "hood", prop = "wrench" },
            { "remove", prop = "engine_part", at = "hood" },
            { "fetch", prop = "engine_part" },
            { "phase", label = "repair_phase_engine_assemble", weight = 4, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_engine_torque", weight = 2, at = "hood", anim = "hood", prop = "torque_wrench" },
            { "phase", label = "repair_phase_oil_fill", weight = 1, at = "hood", anim = "pour", prop = "oil" },
        },
        after = { EngineTest },
    },
    ["core:transmission"] = {
        actions = {
            { "place", prop = "drain_pan", at = "under" },
            { "phase", label = "repair_phase_trans_drain", weight = 2, at = "under", anim = "under", prop = "wrench", particle = "fluid_drain" },
            { "phase", label = "repair_phase_trans_unbolt", weight = 3, at = "under", anim = "under_work", prop = "impact_wrench", sound = "impact" },
            { "remove", prop = "gearbox", at = "under" },
            { "fetch", prop = "gearbox" },
            { "phase", label = "repair_phase_trans_mount", weight = 3, at = "under", anim = "under_work" },
            { "phase", label = "repair_phase_trans_bolt", weight = 3, at = "under", anim = "under_work", prop = "impact_wrench", sound = "impact" },
            { "phase", label = "repair_phase_trans_refill", weight = 1, at = "under", anim = "under", prop = "oil" },
        },
    },
    ["core:clutch"] = {
        actions = {
            { "phase", label = "repair_phase_clutch_trans_off", weight = 3, at = "under", anim = "under_work", prop = "impact_wrench", sound = "impact" },
            { "phase", label = "repair_phase_clutch_remove", weight = 2, at = "under", anim = "under", prop = "wrench" },
            { "fetch", prop = "part_box" },
            { "phase", label = "repair_phase_clutch_fit", weight = 3, at = "under", anim = "under_work" },
            { "phase", label = "repair_phase_clutch_align", weight = 2, at = "under", anim = "under", prop = "wrench" },
            { "phase", label = "repair_phase_trans_bolt", weight = 3, at = "under", anim = "under_work", prop = "impact_wrench", sound = "impact" },
        },
    },
    ["core:radiator"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_coolant_cap", weight = 1, at = "hood", anim = "hood", prop = "rag", particle = "coolant_steam" },
            { "place", prop = "drain_pan", at = "under_front" },
            { "phase", label = "repair_phase_radiator_drain", weight = 2, at = "under_front", anim = "under", prop = "wrench", particle = "fluid_drain" },
            { "phase", label = "repair_phase_radiator_hoses", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "remove", prop = "radiator", at = "hood" },
            { "fetch", prop = "radiator" },
            { "phase", label = "repair_phase_radiator_fit", weight = 3, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_coolant_fill", weight = 2, at = "hood", anim = "pour", prop = "coolant_can" },
        },
    },
    ["core:alternator"] = {
        actions = {
            { "open", door = "hood" },
            BatteryOff,
            { "phase", label = "repair_phase_alternator_belt", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_alternator_unbolt", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "remove", prop = "engine_part", at = "hood" },
            { "fetch", prop = "engine_part" },
            { "phase", label = "repair_phase_alternator_fit", weight = 3, at = "hood", anim = "hood", prop = "wrench" },
            BatteryOn,
        },
        after = {
            { "phase", label = "repair_phase_charge_test", duration = 4000, at = "hood", anim = "tablet", prop = "scanner", sound = "scanner", engine = true },
        },
    },
    ["core:battery"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_battery_disconnect", weight = 2, at = "hood", anim = "hood", prop = "wrench", particle = "battery_spark" },
            { "remove", prop = "battery", at = "hood" },
            { "fetch", prop = "battery" },
            { "phase", label = "repair_phase_battery_fit", weight = 2, at = "hood", anim = "hood" },
            { "phase", label = "repair_phase_battery_connect", weight = 2, at = "hood", anim = "hood", prop = "wrench", particle = "battery_spark" },
        },
        after = { EngineTest },
    },
    ["core:fuel_pump"] = {
        actions = {
            { "phase", label = "repair_phase_fuel_relieve", weight = 1, at = "under_rear", anim = "under", prop = "wrench" },
            { "phase", label = "repair_phase_fuel_pump_lines", weight = 2, at = "under_rear", anim = "under", prop = "wrench" },
            { "phase", label = "repair_phase_fuel_pump_remove", weight = 2, at = "under_rear", anim = "under_work" },
            { "remove", prop = "engine_part", at = "under_rear" },
            { "fetch", prop = "part_box" },
            { "phase", label = "repair_phase_fuel_pump_fit", weight = 3, at = "under_rear", anim = "under", prop = "wrench" },
        },
        after = { EngineTest },
    },
    ["core:brakes"] = {
        wheels = "axle",
        actions = {
            WheelOff,
            { "phase", label = "repair_phase_caliper_off", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
            { "remove", prop = "brake_caliper", at = "wheel" },
            { "fetch", prop = "brake_caliper" },
            { "phase", label = "repair_phase_disc_fit", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
            { "phase", label = "repair_phase_caliper_on", weight = 1, at = "wheel", anim = "kneel", prop = "torque_wrench" },
            WheelOn,
            { "collect" },
        },
    },
    ["core:suspension"] = {
        wheels = "all",
        actions = {
            { "phase", label = "repair_phase_wheel_off", weight = 1, at = "wheel", anim = "kneel", prop = "impact_wrench", sound = "impact" },
            { "phase", label = "repair_phase_shock_unbolt", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
            { "fetch", prop = "part_box" },
            { "phase", label = "repair_phase_shock_fit", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
            { "phase", label = "repair_phase_wheel_on", weight = 1, at = "wheel", anim = "kneel", prop = "impact_wrench", sound = "impact" },
        },
    },
    ["core:alignment"] = {
        wheels = "all",
        actions = {
            { "phase", label = "repair_phase_alignment_measure", weight = 1, at = "wheel", anim = "tablet", prop = "scanner", sound = "scanner" },
            { "phase", label = "repair_phase_alignment_adjust", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
        },
    },
    ["core:turbo"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_turbo_heat_shield", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_turbo_lines", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
            { "remove", prop = "engine_part", at = "hood" },
            { "fetch", prop = "engine_part" },
            { "phase", label = "repair_phase_turbo_fit", weight = 3, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_turbo_torque", weight = 2, at = "hood", anim = "hood", prop = "torque_wrench" },
        },
        after = { EngineTest },
    },
    ["core:ev_battery"] = {
        actions = {
            EvIsolate,
            { "phase", label = "repair_phase_ev_unbolt", weight = 3, at = "under", anim = "under_work", prop = "impact_wrench", sound = "impact" },
            { "remove", prop = "ev_module", at = "under" },
            { "fetch", prop = "ev_module" },
            { "phase", label = "repair_phase_ev_module_fit", weight = 3, at = "under", anim = "under_work" },
            { "phase", label = "repair_phase_ev_bolt", weight = 3, at = "under", anim = "under_work", prop = "impact_wrench", sound = "impact" },
            EvCalibrate,
        },
    },
    ["core:ev_motor"] = {
        actions = {
            EvIsolate,
            { "phase", label = "repair_phase_ev_motor_unbolt", weight = 3, at = "under_rear", anim = "under_work", prop = "impact_wrench", sound = "impact" },
            { "remove", prop = "ev_motor", at = "under_rear" },
            { "fetch", prop = "ev_motor" },
            { "phase", label = "repair_phase_ev_motor_fit", weight = 3, at = "under_rear", anim = "under_work" },
            { "phase", label = "repair_phase_ev_bolt", weight = 2, at = "under_rear", anim = "under_work", prop = "impact_wrench", sound = "impact" },
            EvCalibrate,
        },
        after = { EngineTest },
    },

    --[[ Body ]]--
    ["body:door"] = {
        actions = {
            { "fetch", prop = "car_door" },
            { "phase", label = "repair_phase_door_hang", weight = 3, at = "side", anim = "side" },
            { "phase", label = "repair_phase_door_hinges", weight = 3, at = "side", anim = "side", prop = "wrench" },
            { "phase", label = "repair_phase_door_adjust", weight = 2, at = "side", anim = "side", prop = "screwdriver" },
        },
    },
    ["body:hood"] = {
        actions = {
            { "fetch", prop = "bonnet" },
            { "phase", label = "repair_phase_hood_fit", weight = 3, at = "hood", anim = "side" },
            { "phase", label = "repair_phase_hood_hinges", weight = 3, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_panel_adjust", weight = 2, at = "hood", anim = "hood", prop = "screwdriver" },
        },
    },
    ["body:trunk"] = {
        actions = {
            { "fetch", prop = "bonnet" },
            { "phase", label = "repair_phase_trunk_fit", weight = 3, at = "trunk", anim = "side" },
            { "phase", label = "repair_phase_hood_hinges", weight = 3, at = "trunk", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_panel_adjust", weight = 2, at = "trunk", anim = "hood", prop = "screwdriver" },
        },
    },
    ["body:window"] = {
        actions = {
            { "phase", label = "repair_phase_glass_clear", weight = 2, at = "side", anim = "clean", prop = "rag" },
            { "remove", prop = "glass_scrap", at = "side" },
            { "fetch" },
            { "phase", label = "repair_phase_glass_fit", weight = 3, at = "side", anim = "side" },
            { "phase", label = "repair_phase_glass_seal", weight = 2, at = "side", anim = "side", prop = "screwdriver" },
        },
    },
    ["body:bumper:front"] = {
        actions = {
            { "phase", label = "repair_phase_bumper_unbolt", weight = 2, at = "hood", anim = "kneel", prop = "wrench" },
            { "remove", prop = "bumper_front", at = "hood" },
            { "fetch", prop = "bumper_front" },
            { "phase", label = "repair_phase_bumper_fit", weight = 2, at = "hood", anim = "kneel" },
            { "phase", label = "repair_phase_bumper_bolt", weight = 2, at = "hood", anim = "kneel", prop = "wrench" },
        },
    },
    ["body:bumper:rear"] = {
        actions = {
            { "phase", label = "repair_phase_bumper_unbolt", weight = 2, at = "trunk", anim = "kneel", prop = "wrench" },
            { "remove", prop = "bumper_rear", at = "trunk" },
            { "fetch", prop = "bumper_rear" },
            { "phase", label = "repair_phase_bumper_fit", weight = 2, at = "trunk", anim = "kneel" },
            { "phase", label = "repair_phase_bumper_bolt", weight = 2, at = "trunk", anim = "kneel", prop = "wrench" },
        },
    },
    ["body:headlight"] = {
        actions = {
            { "phase", label = "repair_phase_headlight_remove", weight = 2, at = "hood", anim = "hood", prop = "screwdriver" },
            { "fetch" },
            { "phase", label = "repair_phase_headlight_fit", weight = 2, at = "hood", anim = "hood", prop = "screwdriver" },
            { "phase", label = "repair_phase_headlight_aim", weight = 1, at = "hood", anim = "hood" },
        },
    },
    ["body:tyre"] = {
        wheels = "step",
        actions = {
            WheelOff,
            { "remove", prop = "tyre", at = "wheel" },
            { "fetch", prop = "tyre" },
            { "phase", label = "repair_phase_tyre_mount", weight = 1, at = "wheel", anim = "kneel" },
            WheelOn,
        },
    },
    ["body:wheel"] = {
        wheels = "step",
        actions = {
            { "phase", label = "repair_phase_hub_clean", weight = 1, at = "wheel", anim = "kneel", prop = "wrench" },
            { "fetch", prop = "wheel" },
            { "phase", label = "repair_phase_wheel_mount", weight = 2, at = "wheel", anim = "kneel" },
            WheelOn,
        },
    },
    ["body:fuel_tank"] = {
        actions = {
            { "place", prop = "drain_pan", at = "under_rear" },
            { "phase", label = "repair_phase_tank_drain", weight = 2, at = "under_rear", anim = "under", prop = "wrench", particle = "fluid_drain" },
            { "phase", label = "repair_phase_tank_straps", weight = 2, at = "under_rear", anim = "under", prop = "wrench" },
            { "phase", label = "repair_phase_tank_seal", weight = 3, at = "under_rear", anim = "under_work" },
            { "phase", label = "repair_phase_tank_mount", weight = 2, at = "under_rear", anim = "under", prop = "wrench" },
        },
    },
    ["body:deformation"] = {
        actions = {
            { "phase", label = "repair_phase_body_inspect", weight = 1, at = "hood", anim = "crouch", prop = "flashlight" },
            { "phase", label = "repair_phase_body_grind", weight = 2, at = "left", anim = "side", prop = "grinder", sound = "grinder", particle = "grind_sparks" },
            { "phase", label = "repair_phase_body_weld", weight = 3, at = "left", anim = "weld" },
            { "phase", label = "repair_phase_body_hammer", weight = 3, at = "right", anim = "hammer" },
            { "fetch", prop = "body_panel" },
            { "phase", label = "repair_phase_body_panel", weight = 2, at = "right", anim = "side", prop = "wrench" },
            { "phase", label = "repair_phase_body_finish", weight = 1, at = "trunk", anim = "clean", prop = "rag" },
        },
    },

    --[[ Kits (duration = Config.RepairKits[kit].duration) ]]--
    ["kit:repair_kit"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_kit_inspect", weight = 1, at = "hood", anim = "hood", prop = "flashlight" },
            { "phase", label = "repair_phase_kit_fix", weight = 3, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_kit_tape", weight = 1, at = "hood", anim = "hood" },
        },
    },
    ["kit:advanced_repair_kit"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_kit_inspect", weight = 1, at = "hood", anim = "hood", prop = "flashlight" },
            { "phase", label = "repair_phase_kit_fix", weight = 3, at = "hood", anim = "hood", prop = "wrench" },
            { "phase", label = "repair_phase_kit_body", weight = 2, at = "left", anim = "side", prop = "wrench" },
            { "phase", label = "repair_phase_kit_test", weight = 1, at = "hood", anim = "tablet", prop = "scanner", sound = "scanner" },
        },
    },
    ["kit:patch_kit"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_patch_find", weight = 1, at = "hood", anim = "hood", prop = "flashlight" },
            { "phase", label = "repair_phase_patch_apply", weight = 3, at = "hood", anim = "hood", prop = "rag" },
            { "phase", label = "repair_phase_patch_secure", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
        },
    },
    ["kit:cleaning_kit"] = {
        actions = {
            { "phase", label = "repair_phase_clean_rinse", weight = 1, at = "left", anim = "clean", prop = "sponge", particle = "wash_water" },
            { "phase", label = "repair_phase_clean_scrub", weight = 2, at = "right", anim = "scrub", particle = "wash_drips" },
            { "phase", label = "repair_phase_clean_wipe", weight = 1, at = "hood", anim = "clean", prop = "rag" },
        },
    },

    --[[ Fallbacks by access (custom parts without own scene) ]]--
    ["default:hood"] = {
        actions = {
            { "open", door = "hood" },
            { "phase", label = "repair_phase_disassemble", weight = 1, at = "hood", anim = "hood", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_install", weight = 2, at = "hood", anim = "hood", prop = "wrench" },
        },
    },
    ["default:trunk"] = {
        actions = {
            { "open", door = "trunk" },
            { "phase", label = "repair_phase_disassemble", weight = 1, at = "trunk", anim = "hood", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_install", weight = 2, at = "trunk", anim = "hood", prop = "wrench" },
        },
    },
    ["default:under"] = {
        actions = {
            { "phase", label = "repair_phase_disassemble", weight = 1, at = "under", anim = "under", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_install", weight = 2, at = "under", anim = "under_work" },
        },
    },
    ["default:wheel"] = {
        wheels = "work",
        actions = {
            WheelOff,
            { "phase", label = "repair_phase_install", weight = 2, at = "wheel", anim = "kneel", prop = "wrench" },
            WheelOn,
        },
    },
    ["default:side"] = {
        actions = {
            { "phase", label = "repair_phase_disassemble", weight = 1, at = "side", anim = "side", prop = "wrench" },
            { "fetch" },
            { "phase", label = "repair_phase_install", weight = 2, at = "side", anim = "side", prop = "wrench" },
        },
    },
}
