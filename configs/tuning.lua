--[[
  _______            _
 |__   __|          (_)
    | |_   _ _ __    _ _ __   __ _
    | | | | | '_ \  | | '_ \ / _` |
    | | |_| | | | | | | | | | (_| |
    |_|\__,_|_| |_| |_|_| |_|\__, |
                              __/ |
                             |___/
 Performance + visual (Benny's style) tuning on workshop bays with bay type "tuning" / "both".
 Items are keys of Config.Items (config.lua).
 Prices are base prices, the workshop "tuningMarkup" (%) is added on top.
 Category labels come from locales (tuning_cat_<key>), set label = "..." in a category to override it.
 Every confirmed tuning is written to the mechanic's work log (billing) with the final price.
]]--

Config.Tuning = {}

Config.Tuning.MaxDistance = 8.0          -- m, mechanic must stay this close to the vehicle
Config.Tuning.RemoveFactor = 0.25        -- returning a part to stock costs base price * factor (labor)
Config.Tuning.Cooldown = 1500            -- ms between two confirmations (anti spam)
Config.Tuning.MaxChanges = 60            -- max modifications confirmed at once
Config.Tuning.DraftMinutes = 15          -- min, unconfirmed cart of a vehicle is restored when tuning is opened again (0 = disabled)
Config.Tuning.MaxModIndex = 300          -- highest mod index accepted (addon vehicles can have a lot of parts)
Config.Tuning.SaveOwnedVehicles = true   -- save properties of owned vehicles to the garage table after every confirmation
Config.Tuning.SessionTimeout = 30        -- min, tuning / catalog session without a heartbeat of its player is closed after this time
                                         -- (unconfirmed preview is always reverted by the next owner of the vehicle)
Config.Tuning.HidePlayer = true          -- hides own mechanic ped for the tuning camera (other players still see him)
Config.Tuning.CameraSpeed = 5.0          -- camera smoothing (higher = faster)

-- Customer catalog: anybody standing at a vehicle in a tuning bay picks the tuning himself (target on the vehicle),
-- with live preview and prices. The order goes to the mechanics, the mechanic gets it as the cart of the vehicle.
-- Changes the mechanic adds on top of the order are sent to the customer as a quote (accept / decline).
Config.Tuning.Catalog = {
    enabled = true,
    performance = true,          -- customers also see performance parts (engine, brakes, turbo...)
    requireMechanic = true,      -- catalog only while a mechanic of the workshop is on duty
    illegal = false,             -- catalog in illegal workshops (DLC) too
    maxDistance = 6.0,           -- m, customer has to stay this close to the vehicle
    orderMinutes = 120,          -- min, order waits for a mechanic this long
    approval = true,             -- changes outside the order need the customer's approval (quote on his screen)
    approvalDistance = 30.0,     -- m, customer has to be this close to approve, otherwise extra changes are refused
    approvalTimeout = 60,        -- s, quote without an answer = declined
}

-- Vehicle classes that can't be tuned: 13 cycles, 14 boats, 15 helicopters, 16 planes, 21 trains
Config.Tuning.BlockedClasses = { [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

-- Animations of the mechanic. prop = Config.Props key
Config.Tuning.Animations = {
    idle   = { dict = "amb@code_human_in_bus_passenger_idles@female@tablet@base", clip = "base", flag = 49, prop = "scanner" },  -- browsing the catalogue
    work   = { dict = "mini@repair", clip = "fixing_a_player", flag = 1, prop = "wrench" },                                     -- body / wheels / interior
    paint  = { dict = "switch@franklin@lamar_tagging_wall", clip = "lamar_tagging_wall_loop_lamar", flag = 1, prop = "spray_gun" },
    laptop = { dict = "amb@code_human_in_bus_passenger_idles@female@tablet@base", clip = "base", flag = 49, prop = "laptop" }, -- engine calibration
    hood   = { dict = "mini@repair", clip = "fixing_a_ped", flag = 1, prop = "wrench" },                                        -- engine bay
    under  = { dict = "amb@world_human_vehicle_mechanic@male@base", clip = "base", flag = 1 },                                  -- under the vehicle
    wheel  = { dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", clip = "machinic_loop_mechandplayer", flag = 1, prop = "impact_wrench" }, -- wheels / brakes / suspension
}
-- Installation time after confirmation (ms per modification, max total) - only when Install.enabled = false
Config.Tuning.WorkTime = { perChange = 2000, max = 12000 }

-- Installation workflow: after confirmation every change is installed step by step
-- (mechanic takes the part, walks to the right spot, installs it with animation, the part appears on the car).
-- Without Config.Fetch all items and tools are checked before it starts. With Config.Fetch.enabled (config.lua) the parts
-- are not needed at the start: a step without its part / tool pauses, the mechanic takes it from the workshop storage
-- and continues with the target "Continue tuning" on the vehicle. X cancels, not installed changes stay in the saved cart.
Config.Tuning.Install = {
    enabled = true,              -- false = instant confirmation inside the menu (old behaviour)
    carry = true,                -- mechanic carries the part / parts crate (Config.Props.crate) to the vehicle
    calibration = 6000,          -- ms, laptop calibration after engine / transmission / turbo
    calibrationTool = "tuning_laptop", -- categories with this tool get the calibration (Config.Items key)
    durations = {                -- ms of work per change by group (returning to stock takes removalFactor of it)
        performance = 12000,
        body = 9000,
        wheels = 8000,
        paint = 10000,
        interior = 7000,
        lights = 6000,
        other = 6000,
        settings = 4000,         -- colors of neon / xenon / tyre smoke
    },
    removalFactor = 0.6,         -- returning to stock / removing takes 60 % of the time
    unbox = 2000,                -- ms, unpacking the parts crate (added to the work time)
    test = 2500,                 -- ms, test after installation (revving, horn, lights, neon, hydraulics)
    resultTime = 4000,           -- ms, result is shown in the overlay before the tuning session ends
    serverCheck = 0.9,           -- server accepts a step only after this share of its work time (duration + calibration)
    leftovers = true,            -- removed parts are put on the ground next to the vehicle until the installation ends
    maxDistance = 14.0,          -- m, installation is cancelled when the mechanic gets further from the vehicle
                                 -- (not while waiting for parts, Config.Fetch.maxDistance applies then)
    spotGap = 0.65,              -- m, distance of the work spots from the vehicle body
    -- order of the steps by group, dependencies (transmission before engine stage 3+, xenon before xenon colour...) are resolved automatically
    groupOrder = { "performance", "body", "wheels", "interior", "lights", "other", "paint" },
}

--[[
  _____           _        _ _       _   _
 |_   _|         | |      | | |     | | (_)
   | |  _ __  ___| |_ __ _| | | __ _| |_ _  ___  _ __
   | | | '_ \/ __| __/ _` | | |/ _` | __| |/ _ \| '_ \
  _| |_| | | \__ \ || (_| | | | (_| | |_| | (_) | | | |
 |_____|_| |_|___/\__\__,_|_|_|\__,_|\__|_|\___/|_| |_|

 Scenes of the installation workflow. Every scene:
   take    = "crate" (parts crate is carried, put down and unpacked) / "carry" (part is carried to the vehicle) / nil
   part    = Install.Props key of the part carried from the crate / to the vehicle (removed part is left on the ground)
   work    = list of work positions { spot, door?, phases = { ... } } done in order
   removal = positions used when returning to stock / removing (default: first position with the default removal phases)
   test    = test after the part appeared on the vehicle: "rev" / "horn" / "lights" / "neon" / "hydraulics"
 spot  = front, rear, left, right, left_front, right_front, left_rear, right_rear, hood, trunk, driver, under, top,
         wheel_lf, wheel_rf, wheel_lr, wheel_rr (wheel spots missing on the model are skipped)
 door  = opened for the work: 0 driver door, 4 hood, 5 trunk
 phase = { label = locale key, share = part of the step duration, anim = Install.Anims / Config.Tuning.Animations key,
           prop = Install.Props / Config.Props / Config.Animations.Props key (false = none, nil = prop of the anim preset),
           prop2 = second hand prop, sound = Install.Sounds key, particle = Install.Particles key }
 Following phases at the same spot with the same anim / prop keep it (no standing up / lying down in between).
 Step duration = Install.durations of the group ("settings" for neon / xenon / tyre smoke colours),
 calibration (laptop) is added for categories with calibrationTool, unpacking and walking are added on top.
]]--

-- Animation presets (Config.Tuning.Animations above are available too: idle, work, paint, laptop, hood, wheel).
-- String = preset of Config.Animations.Anims (configs/animations.lua), e.g. lying under the vehicle with transitions.
Config.Tuning.Install.Anims = {
    under    = "under_work",                                                                   -- lying under the vehicle
    overhead = { dict = "amb@prop_human_movie_bulb@base", clip = "base", flag = 1 },          -- roof, aerials
    lean_in  = { dict = "amb@prop_human_bum_bin@base", clip = "base", flag = 1 },             -- through the open door / trunk
    unbox    = { dict = "amb@medic@standing@tendtodead@base", clip = "base", flag = 1 },      -- kneeling at the parts crate
    tablet   = { dict = "amb@code_human_in_bus_passenger_idles@female@tablet@base", clip = "base", flag = 49 },
    wipe     = { dict = "timetable@maid@cleaning_surface@base", clip = "base", flag = 1 },    -- masking, sanding, wrap
    window   = { dict = "timetable@maid@cleaning_window@base", clip = "base", flag = 1 },     -- window tint film
    weld     = { scenario = "WORLD_HUMAN_WELDING" },                                           -- roll cage (scenario has own torch + sparks)
}

-- Props: string = Config.Props (config.lua) or Config.Animations.Props (configs/animations.lua) key,
-- table = own prop { model, bone, pos, rot }. Carried parts use the box carry pose (bone 60309),
-- adjust pos / rot for your own models. Carried parts are also left on the ground as removed old parts.
Config.Tuning.Install.Props = {
    crate        = "crate",
    screwdriver  = "screwdriver",
    rag          = "rag",
    sponge       = "sponge",
    pliers       = { model = "prop_tool_pliers", bone = 57005, pos = vec3(0.12, 0.02, -0.03), rot = vec3(-100.0, 0.0, 0.0) },
    heat_gun     = { model = "prop_tool_blowtorch", bone = 57005, pos = vec3(0.14, 0.02, -0.03), rot = vec3(-100.0, 0.0, 0.0) },
    tape         = { model = "imp_prop_impexp_tape_01", bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
    caliper      = { model = "imp_prop_impexp_brake_caliper_01a", bone = 18905, pos = vec3(0.12, 0.02, 0.02), rot = vec3(-80.0, 0.0, 0.0) },
    -- carried parts
    engine_part  = "engine_part",
    gearbox      = "gearbox",
    bumper_front = "bumper_front",
    bumper_rear  = "bumper_rear",
    bonnet       = "bonnet",
    panel        = "body_panel",
    armor_plate  = "car_door",
    rim          = "wheel",
    spoiler      = { model = "imp_prop_impexp_spoiler_01a", bone = 60309, pos = vec3(0.10, 0.20, 0.30), rot = vec3(-145.0, 290.0, 0.0) },
    exhaust      = { model = "imp_prop_impexp_exhaust_01", bone = 60309, pos = vec3(0.05, 0.10, 0.30), rot = vec3(-145.0, 290.0, 0.0) },
    seat         = { model = "prop_car_seat", bone = 60309, pos = vec3(0.05, 0.15, 0.30), rot = vec3(-145.0, 290.0, 0.0) },
}

-- Sounds (native name + sound set). onVehicle = played from the vehicle, otherwise from the mechanic,
-- combustion = not played for electric vehicles (Config.ElectricVehicles).
-- String = preset of Config.Animations.Sounds (configs/animations.lua)
Config.Tuning.Install.Sounds = {
    impact     = "impact",                                                                     -- impact wrench bursts
    drill      = "grinder",                                                                    -- longer bursts (drilling holes, cutting)
    rev        = { name = "Engine_Rev", set = "Lowrider_Super_Mod_Garage_Sounds", interval = 2400, onVehicle = true, combustion = true, network = true },
    laptop     = { name = "Click_Link", set = "DLC_H3_Arcade_Laptop_Sounds", interval = 800, frontend = true },
    hydraulics = { name = "Hydraulics_Up", set = "Lowrider_Super_Mod_Garage_Sounds", interval = 1200, onVehicle = true, network = true },
    -- one shot sounds
    installed  = { name = "Lowrider_Upgrade", set = "Lowrider_Super_Mod_Garage_Sounds" },   -- part appeared on the vehicle
    calibrated = { name = "Hack_Success", set = "DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS" },   -- calibration finished
    failed     = { name = "ERROR", set = "HUD_FRONTEND_DEFAULT_SOUNDSET" },
}

-- Particles. onVehicle = on the vehicle at the work point of the spot, otherwise entity = "prop" (hand prop,
-- right hand without prop) / nil (mechanic). looped = false: one shot effect repeated every interval ms
Config.Tuning.Install.Particles = {
    paint  = { asset = "scr_playerlamgraff", name = "scr_lamgraff_paint_spray", entity = "prop", offset = vec3(0.0, 0.1, 0.0), scale = 0.8, looped = true },
    mist   = { asset = "scr_paintnspray", name = "scr_respray_smoke", onVehicle = true, scale = 0.35, looped = false, interval = 2200 },
    sparks = { asset = "core", name = "ent_sht_electrical_box", onVehicle = true, scale = 0.35, looped = false, interval = 1700 },
    water  = { asset = "scr_bike_business", name = "scr_bike_spraybottle_spray", entity = "prop", scale = 1.0, looped = false, interval = 1000 },
}

-- Sound played automatically in phases with this hand prop (when the phase has no own sound)
Config.Tuning.Install.PropSounds = {
    impact_wrench = "impact",
}

-- Default removal phases (scene without own removal)
Config.Tuning.Install.RemovalPhases = {
    { label = "tuning_ph_unscrew", share = 0.5, anim = "work", prop = "screwdriver" },
    { label = "tuning_ph_remove_part", share = 0.5, anim = "work", prop = "wrench" },
}

-- Laptop calibration (categories with calibrationTool), shares of Install.calibration
Config.Tuning.Install.CalibrationPhases = {
    { label = "tuning_ph_laptop_connect", share = 0.3, anim = "laptop", sound = "laptop" },
    { label = "tuning_ph_calibrate", share = 0.7, anim = "laptop", sound = "rev" },   -- engine runs, no revving sound for electric vehicles
}

-- Tests after installation (Install.test ms). spot / door = mechanic goes there for the test
Config.Tuning.Install.Tests = {
    rev        = { label = "tuning_ph_test_rev", anim = "tablet", prop = "scanner", sound = "rev" },
    horn       = { label = "tuning_ph_test_horn", anim = "lean_in", prop = false, spot = "driver", door = 0 },
    lights     = { label = "tuning_ph_test_lights", anim = "tablet", prop = "scanner" },
    neon       = { label = "tuning_ph_test_lights", anim = "tablet", prop = "scanner" },
    hydraulics = { label = "tuning_ph_test_hydraulics", anim = "tablet", prop = "scanner", sound = "hydraulics" },
}

Config.Tuning.Install.Scenes = {
    -- performance
    engine = {
        take = "crate", part = "engine_part", test = "rev",
        work = {
            { spot = "hood", door = 4, phases = {
                { label = "tuning_ph_disconnect", share = 0.25, anim = "hood", prop = "wrench" },
                { label = "tuning_ph_remove_old", share = 0.2, anim = "hood", prop = "impact_wrench" },
                { label = "tuning_ph_fit_engine", share = 0.35, anim = "hood", prop = "impact_wrench" },
                { label = "tuning_ph_connect", share = 0.2, anim = "hood", prop = "pliers", particle = "sparks" },
            } },
        },
        removal = {
            { spot = "hood", door = 4, phases = {
                { label = "tuning_ph_disconnect", share = 0.5, anim = "hood", prop = "wrench" },
                { label = "tuning_ph_remove_part", share = 0.5, anim = "hood", prop = "impact_wrench" },
            } },
        },
    },
    turbo = {
        take = "crate", test = "rev",
        work = {
            { spot = "hood", door = 4, phases = {
                { label = "tuning_ph_intake", share = 0.3, anim = "hood", prop = "wrench" },
                { label = "tuning_ph_fit_turbo", share = 0.4, anim = "hood", prop = "impact_wrench" },
                { label = "tuning_ph_boost_lines", share = 0.3, anim = "hood", prop = "wrench" },
            } },
        },
        removal = {
            { spot = "hood", door = 4, phases = {
                { label = "tuning_ph_boost_lines", share = 0.4, anim = "hood", prop = "wrench" },
                { label = "tuning_ph_remove_part", share = 0.6, anim = "hood", prop = "impact_wrench" },
            } },
        },
    },
    transmission = {
        take = "crate", part = "gearbox",
        work = {
            { spot = "under", phases = {
                { label = "tuning_ph_drain", share = 0.2, anim = "under", prop = "wrench" },
                { label = "tuning_ph_unbolt_gearbox", share = 0.3, anim = "under", prop = "impact_wrench" },
                { label = "tuning_ph_fit_gearbox", share = 0.3, anim = "under", prop = "impact_wrench" },
                { label = "tuning_ph_refill", share = 0.2, anim = "under", prop = "wrench" },
            } },
        },
        removal = {
            { spot = "under", phases = {
                { label = "tuning_ph_drain", share = 0.4, anim = "under", prop = "wrench" },
                { label = "tuning_ph_unbolt_gearbox", share = 0.6, anim = "under", prop = "impact_wrench" },
            } },
        },
    },
    brakes = {
        take = "crate",
        work = {
            { spot = "wheel_lf", phases = {
                { label = "tuning_ph_wheel_off", share = 0.15, anim = "wheel" },
                { label = "tuning_ph_fit_brakes", share = 0.2, anim = "wheel", prop = "wrench", prop2 = "caliper" },
                { label = "tuning_ph_wheel_on", share = 0.15, anim = "wheel" },
            } },
            { spot = "wheel_rf", phases = {
                { label = "tuning_ph_wheel_off", share = 0.15, anim = "wheel" },
                { label = "tuning_ph_fit_brakes", share = 0.2, anim = "wheel", prop = "wrench", prop2 = "caliper" },
                { label = "tuning_ph_wheel_on", share = 0.15, anim = "wheel" },
            } },
        },
    },
    suspension = {
        take = "crate", test = "hydraulics",
        work = {
            { spot = "wheel_lf", phases = {
                { label = "tuning_ph_wheel_off", share = 0.15, anim = "wheel" },
                { label = "tuning_ph_fit_suspension", share = 0.2, anim = "wheel", prop = "wrench" },
                { label = "tuning_ph_wheel_on", share = 0.15, anim = "wheel" },
            } },
            { spot = "wheel_lr", phases = {
                { label = "tuning_ph_wheel_off", share = 0.15, anim = "wheel" },
                { label = "tuning_ph_fit_suspension", share = 0.2, anim = "wheel", prop = "wrench" },
                { label = "tuning_ph_wheel_on", share = 0.15, anim = "wheel" },
            } },
        },
    },
    armor = {
        take = "carry", part = "armor_plate",
        work = {
            { spot = "left", phases = {
                { label = "tuning_ph_fit_armor", share = 0.3, anim = "work", prop = "impact_wrench", sound = "drill" },
                { label = "tuning_ph_screw", share = 0.2, anim = "work", prop = "screwdriver" },
            } },
            { spot = "right", phases = {
                { label = "tuning_ph_fit_armor", share = 0.3, anim = "work", prop = "impact_wrench", sound = "drill" },
                { label = "tuning_ph_screw", share = 0.2, anim = "work", prop = "screwdriver" },
            } },
        },
    },

    -- body
    front_bumper = {
        take = "carry", part = "bumper_front",
        work = { { spot = "front", phases = {
            { label = "tuning_ph_unscrew", share = 0.3, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.35, anim = "work", prop = false },
            { label = "tuning_ph_screw", share = 0.35, anim = "work", prop = "impact_wrench" },
        } } },
    },
    rear_bumper = {
        take = "carry", part = "bumper_rear",
        work = { { spot = "rear", phases = {
            { label = "tuning_ph_unscrew", share = 0.3, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.35, anim = "work", prop = false },
            { label = "tuning_ph_screw", share = 0.35, anim = "work", prop = "impact_wrench" },
        } } },
    },
    spoiler = {
        take = "carry", part = "spoiler",
        work = { { spot = "rear", phases = {
            { label = "tuning_ph_unscrew", share = 0.3, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "work", prop = false },
            { label = "tuning_ph_screw", share = 0.4, anim = "work", prop = "impact_wrench" },
        } } },
    },
    hood_panel = {
        take = "carry", part = "bonnet",
        work = { { spot = "hood", door = 4, phases = {
            { label = "tuning_ph_unscrew", share = 0.3, anim = "hood", prop = "wrench" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "hood", prop = false },
            { label = "tuning_ph_align", share = 0.4, anim = "hood", prop = "wrench" },
        } } },
    },
    body_front = {
        take = "crate",
        work = { { spot = "front", phases = {
            { label = "tuning_ph_unscrew", share = 0.35, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "work", prop = false },
            { label = "tuning_ph_screw", share = 0.35, anim = "work", prop = "screwdriver" },
        } } },
    },
    body_rear = {
        take = "crate",
        work = { { spot = "rear", phases = {
            { label = "tuning_ph_unscrew", share = 0.35, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "work", prop = false },
            { label = "tuning_ph_screw", share = 0.35, anim = "work", prop = "screwdriver" },
        } } },
    },
    exhaust = {
        take = "carry", part = "exhaust",
        work = { { spot = "rear", phases = {
            { label = "tuning_ph_unbolt_exhaust", share = 0.35, anim = "wheel", prop = "impact_wrench", sound = "drill" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "wheel", prop = false },
            { label = "tuning_ph_tighten", share = 0.35, anim = "wheel", prop = "wrench" },
        } } },
    },
    fuel_tank = {
        take = "crate",
        work = { { spot = "under", phases = {
            { label = "tuning_ph_unscrew", share = 0.4, anim = "under", prop = "wrench" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "under", prop = false },
            { label = "tuning_ph_tighten", share = 0.3, anim = "under", prop = "wrench" },
        } } },
    },
    sides = {
        take = "carry", part = "panel",
        work = {
            { spot = "left", phases = {
                { label = "tuning_ph_unscrew", share = 0.2, anim = "wheel", prop = "screwdriver" },
                { label = "tuning_ph_fit_part", share = 0.3, anim = "wheel", prop = "impact_wrench" },
            } },
            { spot = "right", phases = {
                { label = "tuning_ph_unscrew", share = 0.2, anim = "wheel", prop = "screwdriver" },
                { label = "tuning_ph_fit_part", share = 0.3, anim = "wheel", prop = "impact_wrench" },
            } },
        },
    },
    fender_left = {
        take = "carry", part = "panel",
        work = { { spot = "left_front", phases = {
            { label = "tuning_ph_unscrew", share = 0.3, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "work", prop = false },
            { label = "tuning_ph_align", share = 0.4, anim = "work", prop = "impact_wrench" },
        } } },
    },
    fender_right = {
        take = "carry", part = "panel",
        work = { { spot = "right_front", phases = {
            { label = "tuning_ph_unscrew", share = 0.3, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "work", prop = false },
            { label = "tuning_ph_align", share = 0.4, anim = "work", prop = "impact_wrench" },
        } } },
    },
    roof = {
        take = "carry", part = "panel",
        work = { { spot = "top", phases = {
            { label = "tuning_ph_unscrew", share = 0.3, anim = "overhead", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "overhead", prop = false },
            { label = "tuning_ph_screw", share = 0.4, anim = "overhead", prop = "impact_wrench" },
        } } },
    },
    windows = {
        take = "crate",
        work = {
            { spot = "left", phases = {
                { label = "tuning_ph_unscrew", share = 0.25, anim = "work", prop = "screwdriver" },
                { label = "tuning_ph_fit_part", share = 0.25, anim = "window", prop = "rag" },
            } },
            { spot = "right", phases = {
                { label = "tuning_ph_unscrew", share = 0.25, anim = "work", prop = "screwdriver" },
                { label = "tuning_ph_fit_part", share = 0.25, anim = "window", prop = "rag" },
            } },
        },
    },
    frame = {
        take = "carry", part = "panel",
        work = { { spot = "driver", door = 0, phases = {
            { label = "tuning_ph_fit_part", share = 0.3, anim = "lean_in", prop = false },
            { label = "tuning_ph_weld", share = 0.5, anim = "weld", prop = false },
            { label = "tuning_ph_screw", share = 0.2, anim = "lean_in", prop = "wrench" },
        } } },
        removal = { { spot = "driver", door = 0, phases = {
            { label = "tuning_ph_unscrew", share = 0.5, anim = "lean_in", prop = "wrench" },
            { label = "tuning_ph_remove_part", share = 0.5, anim = "lean_in", prop = false },
        } } },
    },

    -- wheels
    rims = {
        take = "carry", part = "rim",
        work = {
            { spot = "wheel_lf", phases = {
                { label = "tuning_ph_wheel_off", share = 0.25, anim = "wheel" },
                { label = "tuning_ph_fit_rim", share = 0.25, anim = "wheel" },
            } },
            { spot = "wheel_rf", phases = {
                { label = "tuning_ph_wheel_off", share = 0.25, anim = "wheel" },
                { label = "tuning_ph_fit_rim", share = 0.25, anim = "wheel" },
            } },
        },
    },
    rims_rear = {
        take = "carry", part = "rim",
        work = { { spot = "wheel_lr", phases = {
            { label = "tuning_ph_wheel_off", share = 0.5, anim = "wheel" },
            { label = "tuning_ph_fit_rim", share = 0.5, anim = "wheel" },
        } } },
    },
    tyres = {
        take = "carry", part = "rim",
        work = {
            { spot = "wheel_lf", phases = {
                { label = "tuning_ph_wheel_off", share = 0.2, anim = "wheel" },
                { label = "tuning_ph_fit_tyre", share = 0.3, anim = "wheel", prop = "wrench" },
            } },
            { spot = "wheel_rf", phases = {
                { label = "tuning_ph_wheel_off", share = 0.2, anim = "wheel" },
                { label = "tuning_ph_fit_tyre", share = 0.3, anim = "wheel", prop = "wrench" },
            } },
        },
    },
    tyre_smoke = {
        take = "crate",
        work = { { spot = "wheel_lr", phases = {
            { label = "tuning_ph_smoke_kit", share = 0.6, anim = "wheel", prop = "wrench" },
            { label = "tuning_ph_connect", share = 0.4, anim = "wheel", prop = "pliers", particle = "sparks" },
        } } },
    },
    hydraulics = {
        take = "crate", test = "hydraulics",
        work = {
            { spot = "trunk", door = 5, phases = {
                { label = "tuning_ph_fit_hydraulics", share = 0.45, anim = "lean_in", prop = "wrench" },
            } },
            { spot = "wheel_lf", phases = {
                { label = "tuning_ph_hoses", share = 0.3, anim = "wheel", prop = "wrench" },
                { label = "tuning_ph_tighten", share = 0.25, anim = "wheel" },
            } },
        },
    },

    -- paint
    paint = {
        work = {
            { spot = "left", phases = {
                { label = "tuning_ph_mask", share = 0.15, anim = "wipe", prop = "tape" },
                { label = "tuning_ph_primer", share = 0.2, anim = "paint", particle = "paint" },
            } },
            { spot = "front", phases = {
                { label = "tuning_ph_base_coat", share = 0.25, anim = "paint", particle = "paint" },
            } },
            { spot = "right", phases = {
                { label = "tuning_ph_base_coat", share = 0.25, anim = "paint", particle = "paint" },
                { label = "tuning_ph_clear_coat", share = 0.15, anim = "paint", particle = "mist" },
            } },
        },
    },
    paint_finish = {
        work = {
            { spot = "left", phases = {
                { label = "tuning_ph_sand", share = 0.3, anim = "wipe", prop = "sponge" },
                { label = "tuning_ph_clear_coat", share = 0.3, anim = "paint", particle = "mist" },
            } },
            { spot = "right", phases = {
                { label = "tuning_ph_clear_coat", share = 0.2, anim = "paint", particle = "mist" },
                { label = "tuning_ph_polish", share = 0.2, anim = "wipe", prop = "rag" },
            } },
        },
    },
    paint_wheels = {
        work = {
            { spot = "wheel_lf", phases = {
                { label = "tuning_ph_mask", share = 0.2, anim = "wheel", prop = "tape" },
                { label = "tuning_ph_base_coat", share = 0.3, anim = "wheel", prop = "spray_gun", particle = "paint" },
            } },
            { spot = "wheel_rf", phases = {
                { label = "tuning_ph_base_coat", share = 0.3, anim = "wheel", prop = "spray_gun", particle = "paint" },
                { label = "tuning_ph_clear_coat", share = 0.2, anim = "wheel", prop = "spray_gun", particle = "mist" },
            } },
        },
    },
    livery = {
        take = "crate",
        work = {
            { spot = "left", phases = {
                { label = "tuning_ph_clean", share = 0.2, anim = "wipe", prop = "sponge" },
                { label = "tuning_ph_wrap", share = 0.3, anim = "wipe", prop = false },
            } },
            { spot = "right", phases = {
                { label = "tuning_ph_wrap", share = 0.3, anim = "wipe", prop = false },
                { label = "tuning_ph_heat", share = 0.2, anim = "work", prop = "heat_gun" },
            } },
        },
        removal = {
            { spot = "left", phases = { { label = "tuning_ph_remove_wrap", share = 0.5, anim = "wipe", prop = "heat_gun" } } },
            { spot = "right", phases = { { label = "tuning_ph_remove_wrap", share = 0.5, anim = "wipe", prop = "heat_gun" } } },
        },
    },

    -- interior
    interior = {
        take = "crate",
        work = { { spot = "driver", door = 0, phases = {
            { label = "tuning_ph_interior_remove", share = 0.35, anim = "lean_in", prop = "screwdriver" },
            { label = "tuning_ph_interior_fit", share = 0.35, anim = "lean_in", prop = false },
            { label = "tuning_ph_screw", share = 0.3, anim = "lean_in", prop = "screwdriver" },
        } } },
        removal = { { spot = "driver", door = 0, phases = {
            { label = "tuning_ph_unscrew", share = 0.5, anim = "lean_in", prop = "screwdriver" },
            { label = "tuning_ph_remove_part", share = 0.5, anim = "lean_in", prop = false },
        } } },
    },
    seats = {
        take = "carry", part = "seat",
        work = { { spot = "driver", door = 0, phases = {
            { label = "tuning_ph_interior_remove", share = 0.35, anim = "lean_in", prop = "wrench" },
            { label = "tuning_ph_interior_fit", share = 0.35, anim = "lean_in", prop = false },
            { label = "tuning_ph_tighten", share = 0.3, anim = "lean_in", prop = "wrench" },
        } } },
        removal = { { spot = "driver", door = 0, phases = {
            { label = "tuning_ph_unscrew", share = 0.5, anim = "lean_in", prop = "wrench" },
            { label = "tuning_ph_remove_part", share = 0.5, anim = "lean_in", prop = false },
        } } },
    },
    trunk_interior = {
        take = "crate",
        work = { { spot = "trunk", door = 5, phases = {
            { label = "tuning_ph_interior_remove", share = 0.3, anim = "lean_in", prop = "screwdriver" },
            { label = "tuning_ph_interior_fit", share = 0.4, anim = "lean_in", prop = false },
            { label = "tuning_ph_connect", share = 0.3, anim = "lean_in", prop = "pliers" },
        } } },
        removal = { { spot = "trunk", door = 5, phases = {
            { label = "tuning_ph_unscrew", share = 0.5, anim = "lean_in", prop = "screwdriver" },
            { label = "tuning_ph_remove_part", share = 0.5, anim = "lean_in", prop = false },
        } } },
    },

    -- lights
    xenon = {
        take = "crate", test = "lights",
        work = { { spot = "hood", door = 4, phases = {
            { label = "tuning_ph_bulbs", share = 0.4, anim = "hood", prop = "screwdriver" },
            { label = "tuning_ph_wiring", share = 0.6, anim = "hood", prop = "pliers", particle = "sparks" },
        } } },
    },
    xenon_color = {
        test = "lights",
        work = { { spot = "front", phases = {
            { label = "tuning_ph_bulbs", share = 1.0, anim = "work", prop = "screwdriver" },
        } } },
    },
    neon = {
        take = "crate", test = "neon",
        work = {
            { spot = "under", phases = {
                { label = "tuning_ph_mount_neon", share = 0.5, anim = "under", prop = "impact_wrench" },
            } },
            { spot = "driver", door = 0, phases = {
                { label = "tuning_ph_wiring", share = 0.5, anim = "lean_in", prop = "pliers", particle = "sparks" },
            } },
        },
        removal = { { spot = "under", phases = {
            { label = "tuning_ph_unscrew", share = 1.0, anim = "under", prop = "impact_wrench" },
        } } },
    },
    program = {
        work = { { spot = "driver", door = 0, phases = {
            { label = "tuning_ph_program", share = 1.0, anim = "tablet", prop = "scanner" },
        } } },
    },
    program_neon = {
        test = "neon",
        work = { { spot = "driver", door = 0, phases = {
            { label = "tuning_ph_program", share = 1.0, anim = "tablet", prop = "scanner" },
        } } },
    },

    -- other
    horn = {
        take = "crate", test = "horn",
        work = { { spot = "hood", door = 4, phases = {
            { label = "tuning_ph_fit_horn", share = 0.6, anim = "hood", prop = "wrench" },
            { label = "tuning_ph_connect", share = 0.4, anim = "hood", prop = "pliers", particle = "sparks" },
        } } },
    },
    window_tint = {
        take = "crate",
        work = {
            { spot = "left", phases = {
                { label = "tuning_ph_clean", share = 0.2, anim = "window", prop = "sponge", particle = "water" },
                { label = "tuning_ph_film", share = 0.15, anim = "window", prop = false },
                { label = "tuning_ph_squeegee", share = 0.15, anim = "window", prop = "rag" },
            } },
            { spot = "right", phases = {
                { label = "tuning_ph_film", share = 0.25, anim = "window", prop = false, particle = "water" },
                { label = "tuning_ph_squeegee", share = 0.25, anim = "window", prop = "rag" },
            } },
        },
        removal = {
            { spot = "left", phases = { { label = "tuning_ph_remove_film", share = 0.5, anim = "window", prop = "heat_gun" } } },
            { spot = "right", phases = { { label = "tuning_ph_remove_film", share = 0.5, anim = "window", prop = "heat_gun" } } },
        },
    },
    plate = {
        take = "crate",
        work = { { spot = "rear", phases = {
            { label = "tuning_ph_unscrew", share = 0.35, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_plate", share = 0.3, anim = "work", prop = false },
            { label = "tuning_ph_screw", share = 0.35, anim = "work", prop = "screwdriver" },
        } } },
    },
    engine_bay = {
        take = "crate", test = "rev",
        work = { { spot = "hood", door = 4, phases = {
            { label = "tuning_ph_disconnect", share = 0.3, anim = "hood", prop = "wrench" },
            { label = "tuning_ph_fit_part", share = 0.4, anim = "hood", prop = "impact_wrench" },
            { label = "tuning_ph_tighten", share = 0.3, anim = "hood", prop = "wrench" },
        } } },
        removal = { { spot = "hood", door = 4, phases = {
            { label = "tuning_ph_unscrew", share = 0.5, anim = "hood", prop = "wrench" },
            { label = "tuning_ph_remove_part", share = 0.5, anim = "hood", prop = false },
        } } },
    },
    generic = {
        take = "crate",
        work = { { spot = "left", phases = {
            { label = "tuning_ph_unscrew", share = 0.35, anim = "work", prop = "screwdriver" },
            { label = "tuning_ph_fit_part", share = 0.3, anim = "work", prop = false },
            { label = "tuning_ph_screw", share = 0.35, anim = "work", prop = "wrench" },
        } } },
    },
}

-- Scene of every category (key of Config.Tuning.Performance / Visual, "wheels" = all rim types).
-- Categories without entry use the scene "generic" at the spot of their camera preset.
Config.Tuning.Install.CategoryScenes = {
    engine = "engine", turbo = "turbo", transmission = "transmission", brakes = "brakes", suspension = "suspension", armor = "armor",
    paint_primary = "paint", paint_secondary = "paint", paint_pearlescent = "paint",
    paint_type_primary = "paint_finish", paint_type_secondary = "paint_finish", paint_wheels = "paint_wheels",
    livery = "livery", livery_classic = "livery",
    spoiler = "spoiler", front_bumper = "front_bumper", rear_bumper = "rear_bumper", side_skirts = "sides", exhaust = "exhaust",
    frame = "frame", grille = "body_front", hood = "hood_panel", fender_left = "fender_left", fender_right = "fender_right",
    roof = "roof", arch_cover = "sides", aerials = "roof", trim_exterior = "sides", fuel_tank = "fuel_tank", windows = "windows",
    plate_holder = "body_rear", vanity_plate = "body_front",
    wheels = "rims", back_wheels = "rims_rear", custom_tyres = "tyres", tyre_smoke = "tyre_smoke", tyre_smoke_color = "program",
    trim_interior = "interior", ornaments = "interior", dashboard = "interior", dials = "interior", door_speakers = "interior",
    seats = "seats", steering_wheel = "interior", shifter = "interior", plaques = "interior", speakers = "trunk_interior", trunk = "trunk_interior",
    xenon = "xenon", xenon_color = "xenon_color", neon_layout = "neon", neon_color = "program_neon",
    horn = "horn", window_tint = "window_tint", plate_style = "plate",
    engine_block = "engine_bay", air_filter = "engine_bay", struts = "engine_bay", hydraulics = "hydraulics",
}

--[[
   _____
  / ____|
 | |     __ _ _ __ ___   ___ _ __ __ _
 | |    / _` | '_ ` _ \ / _ \ '__/ _` |
 | |___| (_| | | | | | |  __/ | | (_| |
  \_____\__,_|_| |_| |_|\___|_|  \__,_|

 Camera orbits around a point of the vehicle.
 target   = point on the vehicle as fraction of half size from the center (x = right, y = front, z = up)
 bone     = use vehicle bone as target instead (falls back to target)
 angle    = degrees around the vehicle (0 = in front, 90 = right side, 180 = behind, 270 = left side)
 distance = m from target (scaled by vehicle size), height = m above target
 door     = door opened while the camera looks there (0 driver door, 4 hood, 5 trunk)
]]--

Config.Tuning.Cameras = {
    default    = { target = vec3(0.0, 0.0, 0.0),    angle = 40.0,  distance = 5.6, height = 1.4, fov = 50.0 },
    front      = { target = vec3(0.0, 1.0, 0.0),    angle = 20.0,  distance = 3.4, height = 0.8, fov = 45.0 },
    hood       = { target = vec3(0.0, 0.65, 0.3),   angle = 0.0,   distance = 2.2, height = 1.6, fov = 50.0, door = 4 },
    rear       = { target = vec3(0.0, -1.0, 0.0),   angle = 200.0, distance = 3.4, height = 0.8, fov = 45.0 },
    trunk      = { target = vec3(0.0, -0.8, 0.3),   angle = 180.0, distance = 2.2, height = 1.4, fov = 50.0, door = 5 },
    side       = { target = vec3(-1.0, 0.0, 0.0),   angle = 270.0, distance = 3.8, height = 0.6, fov = 50.0 },
    side_right = { target = vec3(1.0, 0.0, 0.0),    angle = 90.0,  distance = 3.8, height = 0.6, fov = 50.0 },
    wheel      = { target = vec3(-1.0, 0.6, -0.4),  bone = "wheel_lf", angle = 300.0, distance = 1.9, height = 0.3, fov = 45.0 },
    wheel_rear = { target = vec3(-1.0, -0.6, -0.4), bone = "wheel_lr", angle = 240.0, distance = 1.9, height = 0.3, fov = 45.0 },
    interior   = { target = vec3(-0.25, 0.1, 0.35), angle = 285.0, distance = 1.5, height = 0.45, fov = 55.0, door = 0 },
    top        = { target = vec3(0.0, 0.0, 0.6),    angle = 30.0,  distance = 3.2, height = 3.2, fov = 50.0 },
    under      = { target = vec3(0.0, 0.0, -0.8),   angle = 60.0,  distance = 4.6, height = 0.1, fov = 50.0 },
}

--[[
  _____           __
 |  __ \         / _|
 | |__) |__ _ __| |_ ___  _ __ _ __ ___   __ _ _ __   ___ ___
 |  ___/ _ \ '__|  _/ _ \| '__| '_ ` _ \ / _` | '_ \ / __/ _ \
 | |  |  __/ |  | || (_) | |  | | | | | | (_| | | | | (_|  __/
 |_|   \___|_|  |_| \___/|_|  |_| |_| |_|\__,_|_| |_|\___\___|

 Permission "tuning_performance".
 levels             = stage 1..n (GTA mod index 0..n-1), item consumed when the stage is installed
 removePrice        = price for returning to stock
 tool               = required tool (Config.Items key)
 returnItemOnRemove = removed part (downgrade / upgrade / stock) is returned to the mechanic,
                      only when this workshop system installed it (anti duplication)
 requires           = { stage = X, category = key, minStage = Y } stage X and higher needs category at stage Y or higher
 iceOnly            = not offered for electric vehicles (Config.ElectricVehicles)
 Toggle (turbo): price is charged for installing and removing.
]]--

Config.Tuning.Performance = {
    {
        key = "engine", mod = 11, prop = "modEngine", cam = "hood", tool = "tuning_laptop", returnItemOnRemove = true, removePrice = 800,
        levels = {
            { item = "engine_stage1", price = 4000 },
            { item = "engine_stage2", price = 8000 },
            { item = "engine_stage3", price = 14000 },
            { item = "engine_stage4", price = 22000 },
        },
        requires = {
            { stage = 3, category = "transmission", minStage = 1 },
            { stage = 4, category = "transmission", minStage = 2 },
        },
    },
    {
        key = "brakes", mod = 12, prop = "modBrakes", cam = "wheel", returnItemOnRemove = true, removePrice = 500,
        levels = {
            { item = "brakes_stage1", price = 2500 },
            { item = "brakes_stage2", price = 5000 },
            { item = "brakes_stage3", price = 8500 },
        },
    },
    {
        key = "transmission", mod = 13, prop = "modTransmission", cam = "under", tool = "tuning_laptop", returnItemOnRemove = true, removePrice = 700,
        levels = {
            { item = "transmission_stage1", price = 3500 },
            { item = "transmission_stage2", price = 7000 },
            { item = "transmission_stage3", price = 12000 },
        },
    },
    {
        key = "suspension", mod = 15, prop = "modSuspension", cam = "wheel", returnItemOnRemove = true, removePrice = 400,
        levels = {
            { item = "suspension_stage1", price = 1500 },
            { item = "suspension_stage2", price = 3000 },
            { item = "suspension_stage3", price = 5000 },
            { item = "suspension_stage4", price = 8000 },
        },
    },
    {
        key = "armor", mod = 16, prop = "modArmor", cam = "side", returnItemOnRemove = true, removePrice = 1000,
        levels = {
            { item = "armor_stage1", price = 5000 },
            { item = "armor_stage2", price = 9000 },
            { item = "armor_stage3", price = 14000 },
            { item = "armor_stage4", price = 20000 },
            { item = "armor_stage5", price = 28000 },
        },
    },
    {
        key = "turbo", mod = 18, prop = "modTurbo", toggle = true, cam = "hood", tool = "tuning_laptop", returnItemOnRemove = true, iceOnly = true,
        item = "turbo_kit", price = 15000,
    },
}

--[[
 __      ___                 _
 \ \    / (_)               | |
  \ \  / / _ ___ _   _  __ _| |
   \ \/ / | / __| | | |/ _` | |
    \  /  | \__ \ |_| | (_| | |
     \/   |_|___/\__,_|\__,_|_|

 Permission "tuning_visual".
 type:
   mod          - GTA mod list (mod = mod type, prop = ox_lib vehicle property)
   toggle       - GTA toggle mod (xenon, tyre smoke)
   wheels       - rims, one category per wheel type (Config.Tuning.WheelTypes), front wheels
   back_wheels  - rear rim of motorcycles
   custom_tyres - custom tyres toggle
   color        - GTA color index, palette = "paint" (Config.Tuning.Colors) / "xenon" (Config.Tuning.XenonColors)
   paint_type   - paint finish (Config.Tuning.PaintTypes), target = "primary" / "secondary"
   rgb          - neon / tyre smoke color
   neon_layout  - Config.Tuning.NeonLayouts
   window_tint  - Config.Tuning.WindowTints
   plate        - Config.Tuning.PlateStyles
   livery       - vehicle livery (SetVehicleLivery, liveries without mod kit)
 group    = NUI tab: body / wheels / paint / lights / interior / other
 price    = base price, priceStep = added per variant index (mod lists)
 material = consumed per installed change (not when returning to stock / turning off)
 tool     = required tool (not consumed)
 needs    = category that must be installed (xenon color needs xenon...)
 cam      = Config.Tuning.Cameras key
]]--

local bodykit = { item = "bodykit_parts", count = 1 }
local interior = { item = "interior_parts", count = 1 }
local paint = { item = "paint_can", count = 1 }

Config.Tuning.Visual = {
    -- paint
    { key = "paint_primary",        type = "color",      prop = "color1",           palette = "paint", group = "paint", price = 1200, material = paint, tool = "spray_gun", cam = "default" },
    { key = "paint_type_primary",   type = "paint_type", prop = "paintType1",       target = "primary", group = "paint", price = 400, tool = "spray_gun", cam = "default" },
    { key = "paint_secondary",      type = "color",      prop = "color2",           palette = "paint", group = "paint", price = 900, material = paint, tool = "spray_gun", cam = "default" },
    { key = "paint_type_secondary", type = "paint_type", prop = "paintType2",       target = "secondary", group = "paint", price = 400, tool = "spray_gun", cam = "default" },
    { key = "paint_pearlescent",    type = "color",      prop = "pearlescentColor", palette = "paint", group = "paint", price = 1000, material = paint, tool = "spray_gun", cam = "default" },
    { key = "paint_wheels",         type = "color",      prop = "wheelColor",       palette = "paint", group = "paint", price = 600, material = paint, tool = "spray_gun", cam = "wheel" },
    { key = "livery",               type = "mod",        mod = 48, prop = "modLivery", group = "paint", price = 2500, material = { item = "vinyl", count = 1 }, cam = "side" },
    { key = "livery_classic",       type = "livery",     prop = "livery",           group = "paint", price = 2000, material = { item = "vinyl", count = 1 }, cam = "side" },

    -- body
    { key = "spoiler",        type = "mod", mod = 0,  prop = "modSpoilers",    group = "body", price = 1500, priceStep = 150, material = bodykit, cam = "rear" },
    { key = "front_bumper",   type = "mod", mod = 1,  prop = "modFrontBumper", group = "body", price = 1800, priceStep = 150, material = bodykit, cam = "front" },
    { key = "rear_bumper",    type = "mod", mod = 2,  prop = "modRearBumper",  group = "body", price = 1800, priceStep = 150, material = bodykit, cam = "rear" },
    { key = "side_skirts",    type = "mod", mod = 3,  prop = "modSideSkirt",   group = "body", price = 1400, priceStep = 100, material = bodykit, cam = "side" },
    { key = "exhaust",        type = "mod", mod = 4,  prop = "modExhaust",     group = "body", price = 1000, priceStep = 100, material = bodykit, cam = "rear" },
    { key = "frame",          type = "mod", mod = 5,  prop = "modFrame",       group = "body", price = 2000, priceStep = 150, material = { item = "bodykit_parts", count = 2 }, cam = "interior" },
    { key = "grille",         type = "mod", mod = 6,  prop = "modGrille",      group = "body", price = 900,  priceStep = 80,  material = bodykit, cam = "front" },
    { key = "hood",           type = "mod", mod = 7,  prop = "modHood",        group = "body", price = 1800, priceStep = 150, material = bodykit, cam = "front" },
    { key = "fender_left",    type = "mod", mod = 8,  prop = "modFender",      group = "body", price = 1200, priceStep = 100, material = bodykit, cam = "side" },
    { key = "fender_right",   type = "mod", mod = 9,  prop = "modRightFender", group = "body", price = 1200, priceStep = 100, material = bodykit, cam = "side_right" },
    { key = "roof",           type = "mod", mod = 10, prop = "modRoof",        group = "body", price = 1500, priceStep = 120, material = bodykit, cam = "top" },
    { key = "arch_cover",     type = "mod", mod = 42, prop = "modArchCover",   group = "body", price = 900,  priceStep = 80,  material = bodykit, cam = "side" },
    { key = "aerials",        type = "mod", mod = 43, prop = "modAerials",     group = "body", price = 500,  priceStep = 50,  material = bodykit, cam = "top" },
    { key = "trim_exterior",  type = "mod", mod = 44, prop = "modTrimB",       group = "body", price = 900,  priceStep = 80,  material = bodykit, cam = "side" },
    { key = "fuel_tank",      type = "mod", mod = 45, prop = "modTank",        group = "body", price = 600,  priceStep = 50,  material = bodykit, cam = "rear" },
    { key = "windows",        type = "mod", mod = 46, prop = "modWindows",     group = "body", price = 800,  priceStep = 60,  material = bodykit, cam = "side" },
    { key = "plate_holder",   type = "mod", mod = 25, prop = "modPlateHolder", group = "body", price = 400,  priceStep = 30,  material = bodykit, cam = "rear" },
    { key = "vanity_plate",   type = "mod", mod = 26, prop = "modVanityPlate", group = "body", price = 500,  priceStep = 40,  material = bodykit, cam = "front" },

    -- wheels
    { key = "wheels",         type = "wheels",       prop = "modFrontWheels", group = "wheels", price = 2000, priceStep = 40, material = { item = "rims", count = 1 }, cam = "wheel" },
    { key = "back_wheels",    type = "back_wheels",  prop = "modBackWheels",  group = "wheels", price = 1500, priceStep = 40, material = { item = "rims", count = 1 }, cam = "wheel_rear" },
    { key = "custom_tyres",   type = "custom_tyres", prop = "modCustomTiresF", group = "wheels", price = 800, material = { item = "rims", count = 1 }, cam = "wheel" },
    { key = "tyre_smoke",     type = "toggle", mod = 20, prop = "modSmokeEnabled", group = "wheels", price = 1500, material = { item = "tyre_smoke_kit", count = 1 }, cam = "wheel_rear" },
    { key = "tyre_smoke_color", type = "rgb",  prop = "tyreSmokeColor", group = "wheels", price = 400, needs = "tyre_smoke", cam = "wheel_rear" },

    -- interior (Benny's)
    { key = "trim_interior",  type = "mod", mod = 27, prop = "modTrimA",          group = "interior", price = 900,  priceStep = 80,  material = interior, cam = "interior" },
    { key = "ornaments",      type = "mod", mod = 28, prop = "modOrnaments",      group = "interior", price = 500,  priceStep = 40,  material = interior, cam = "interior" },
    { key = "dashboard",      type = "mod", mod = 29, prop = "modDashboard",      group = "interior", price = 1200, priceStep = 100, material = interior, cam = "interior" },
    { key = "dials",          type = "mod", mod = 30, prop = "modDial",           group = "interior", price = 700,  priceStep = 50,  material = interior, cam = "interior" },
    { key = "door_speakers",  type = "mod", mod = 31, prop = "modDoorSpeaker",    group = "interior", price = 800,  priceStep = 60,  material = interior, cam = "interior" },
    { key = "seats",          type = "mod", mod = 32, prop = "modSeats",          group = "interior", price = 1500, priceStep = 120, material = interior, cam = "interior" },
    { key = "steering_wheel", type = "mod", mod = 33, prop = "modSteeringWheel",  group = "interior", price = 900,  priceStep = 80,  material = interior, cam = "interior" },
    { key = "shifter",        type = "mod", mod = 34, prop = "modShifterLeavers", group = "interior", price = 600,  priceStep = 50,  material = interior, cam = "interior" },
    { key = "plaques",        type = "mod", mod = 35, prop = "modAPlate",         group = "interior", price = 400,  priceStep = 30,  material = interior, cam = "interior" },
    { key = "speakers",       type = "mod", mod = 36, prop = "modSpeakers",       group = "interior", price = 1000, priceStep = 80,  material = interior, cam = "trunk" },
    { key = "trunk",          type = "mod", mod = 37, prop = "modTrunk",          group = "interior", price = 1200, priceStep = 100, material = interior, cam = "trunk" },

    -- lights
    { key = "xenon",          type = "toggle", mod = 22, prop = "modXenon", group = "lights", price = 1500, material = { item = "xenon_kit", count = 1 }, cam = "front" },
    { key = "xenon_color",    type = "color",  prop = "xenonColor", palette = "xenon", group = "lights", price = 500, needs = "xenon", cam = "front" },
    { key = "neon_layout",    type = "neon_layout", prop = "neonEnabled", group = "lights", price = 3000, material = { item = "neon_kit", count = 1 }, cam = "under" },
    { key = "neon_color",     type = "rgb",    prop = "neonColor", group = "lights", price = 600, needs = "neon_layout", cam = "under" },

    -- other
    { key = "horn",           type = "mod", mod = 14, prop = "modHorns", group = "other", price = 600, priceStep = 20, material = { item = "horn", count = 1 }, cam = "front" },
    { key = "window_tint",    type = "window_tint", prop = "windowTint", group = "other", price = 900, material = { item = "window_tint", count = 1 }, cam = "side" },
    { key = "plate_style",    type = "plate",       prop = "plateIndex", group = "other", price = 500, material = { item = "plate_kit", count = 1 }, cam = "rear" },
    { key = "engine_block",   type = "mod", mod = 39, prop = "modEngineBlock", group = "other", price = 1500, priceStep = 120, material = bodykit, cam = "hood" },
    { key = "air_filter",     type = "mod", mod = 40, prop = "modAirFilter",   group = "other", price = 800,  priceStep = 60,  material = bodykit, cam = "hood" },
    { key = "struts",         type = "mod", mod = 41, prop = "modStruts",      group = "other", price = 1000, priceStep = 80,  material = bodykit, cam = "hood" },
    { key = "hydraulics",     type = "mod", mod = 38, prop = "modHydrolic",    group = "other", price = 3500, priceStep = 250, material = { item = "bodykit_parts", count = 2 }, cam = "wheel" },
}

--[[
  _      _     _
 | |    (_)   | |
 | |     _ ___| |_ ___
 | |    | / __| __/ __|
 | |____| \__ \ |_\__ \
 |______|_|___/\__|___/

 Labels of wheel types, paint types, tints, plate styles, neon layouts and xenon colors are in locales.
]]--

-- Wheel types (SetVehicleWheelType). bike = motorcycles only, openWheel = open wheel class only, minBuild = game build
Config.Tuning.WheelTypes = {
    { type = 0,  key = "sport" },
    { type = 1,  key = "muscle" },
    { type = 2,  key = "lowrider" },
    { type = 3,  key = "suv" },
    { type = 4,  key = "offroad" },
    { type = 5,  key = "tuner" },
    { type = 7,  key = "highend" },
    { type = 8,  key = "bennys_original" },
    { type = 9,  key = "bennys_bespoke" },
    { type = 10, key = "open_wheel", openWheel = true, minBuild = 2060 },
    { type = 11, key = "street", minBuild = 2372 },
    { type = 12, key = "track", minBuild = 2372 },
    { type = 6,  key = "bike", bike = true },
}

-- Paint finish (SetVehicleModColor_1 / _2). primaryOnly = not offered for secondary color
Config.Tuning.PaintTypes = {
    { value = 0, key = "classic" },
    { value = 1, key = "metallic" },
    { value = 2, key = "pearl", primaryOnly = true },
    { value = 3, key = "matte" },
    { value = 4, key = "metal" },
    { value = 5, key = "chrome" },
}

-- Window tint (SetVehicleWindowTint), value 0 = no tint (removal)
Config.Tuning.WindowTints = {
    { value = 0, key = "none" },
    { value = 4, key = "stock" },
    { value = 3, key = "light_smoke" },
    { value = 2, key = "dark_smoke" },
    { value = 1, key = "pure_black" },
    { value = 5, key = "limo" },
    { value = 6, key = "green" },
}

-- Plate styles (SetVehicleNumberPlateTextIndex)
Config.Tuning.PlateStyles = {
    { value = 0, key = "blue_white" },
    { value = 3, key = "blue_white_2" },
    { value = 4, key = "blue_white_3" },
    { value = 1, key = "yellow_black" },
    { value = 2, key = "yellow_blue" },
    { value = 5, key = "yankton" },
}

-- Neon layouts, value = bit mask: 1 left, 2 right, 4 front, 8 back. value 0 = no neon (removal)
Config.Tuning.NeonLayouts = {
    { value = 0,  key = "none" },
    { value = 4,  key = "front" },
    { value = 8,  key = "back" },
    { value = 3,  key = "sides" },
    { value = 12, key = "front_back" },
    { value = 7,  key = "front_sides" },
    { value = 11, key = "back_sides" },
    { value = 15, key = "all" },
}

-- Xenon colors (SetVehicleXenonLightsColor), 255 = stock
Config.Tuning.XenonColors = {
    { value = 255, key = "stock",         hex = "#DFE9FF" },
    { value = 0,   key = "white",         hex = "#FFFFFF" },
    { value = 1,   key = "blue",          hex = "#0215FF" },
    { value = 2,   key = "electric_blue", hex = "#0353FF" },
    { value = 3,   key = "mint_green",    hex = "#00FF8C" },
    { value = 4,   key = "lime_green",    hex = "#5EFF01" },
    { value = 5,   key = "yellow",        hex = "#FFFF00" },
    { value = 6,   key = "golden_shower", hex = "#FF9600" },
    { value = 7,   key = "orange",        hex = "#FF3E00" },
    { value = 8,   key = "red",           hex = "#FF0101" },
    { value = 9,   key = "pony_pink",     hex = "#FF3264" },
    { value = 10,  key = "hot_pink",      hex = "#FF05BE" },
    { value = 11,  key = "purple",        hex = "#2301FF" },
    { value = 12,  key = "blacklight",    hex = "#0F03FF" },
}

-- Horn names by mod index (used when the game has no label)
Config.Tuning.HornNames = {
    [0] = "Truck Horn", "Cop Horn", "Clown Horn", "Musical Horn 1", "Musical Horn 2", "Musical Horn 3", "Musical Horn 4",
    "Musical Horn 5", "Sad Trombone", "Classical Horn 1", "Classical Horn 2", "Classical Horn 3", "Classical Horn 4",
    "Classical Horn 5", "Classical Horn 6", "Classical Horn 7", "Scale - Do", "Scale - Re", "Scale - Mi", "Scale - Fa",
    "Scale - Sol", "Scale - La", "Scale - Ti", "Scale - Do (High)", "Jazz Horn 1", "Jazz Horn 2", "Jazz Horn 3",
    "Jazz Horn Loop", "Star Spangled Banner 1", "Star Spangled Banner 2", "Star Spangled Banner 3", "Star Spangled Banner 4",
    "Classical Horn 8 Loop", "Classical Horn 9 Loop", "Classical Horn 10 Loop", "Classical Horn 8", "Classical Horn 9",
    "Classical Horn 10", "Funeral Loop", "Funeral", "Spooky Loop", "Spooky", "San Andreas Loop", "San Andreas",
    "Liberty City Loop", "Liberty City", "Festive 1 Loop", "Festive 1", "Festive 2 Loop", "Festive 2", "Festive 3 Loop", "Festive 3",
}

--[[
   _____      _
  / ____|    | |
 | |     ___ | | ___  _ __ ___
 | |    / _ \| |/ _ \| '__/ __|
 | |___| (_) | | (_) | |  \__ \
  \_____\___/|_|\___/|_|  |___/

 GTA vehicle color indexes (SetVehicleColours / SetVehicleExtraColours). hex = approximation for the UI.
 Remove lines of colors you don't want to offer.
]]--

Config.Tuning.Colors = {
    { value = 0,   label = "Metallic Black",              hex = "#0D1116" },
    { value = 1,   label = "Metallic Graphite Black",     hex = "#1C1D21" },
    { value = 2,   label = "Metallic Black Steel",        hex = "#32383D" },
    { value = 3,   label = "Metallic Dark Silver",        hex = "#454B4F" },
    { value = 4,   label = "Metallic Silver",             hex = "#999DA0" },
    { value = 5,   label = "Metallic Blue Silver",        hex = "#C2C4C6" },
    { value = 6,   label = "Metallic Steel Gray",         hex = "#979A97" },
    { value = 7,   label = "Metallic Shadow Silver",      hex = "#637380" },
    { value = 8,   label = "Metallic Stone Silver",       hex = "#63625C" },
    { value = 9,   label = "Metallic Midnight Silver",    hex = "#3C3F47" },
    { value = 10,  label = "Metallic Gun Metal",          hex = "#444E54" },
    { value = 11,  label = "Metallic Anthracite Grey",    hex = "#1D2129" },
    { value = 12,  label = "Matte Black",                 hex = "#13181F" },
    { value = 13,  label = "Matte Gray",                  hex = "#26282A" },
    { value = 14,  label = "Matte Light Grey",            hex = "#515554" },
    { value = 15,  label = "Util Black",                  hex = "#151921" },
    { value = 16,  label = "Util Black Poly",             hex = "#1E2429" },
    { value = 17,  label = "Util Dark Silver",            hex = "#333A3C" },
    { value = 18,  label = "Util Silver",                 hex = "#8C9095" },
    { value = 19,  label = "Util Gun Metal",              hex = "#39434D" },
    { value = 20,  label = "Util Shadow Silver",          hex = "#506272" },
    { value = 21,  label = "Worn Black",                  hex = "#1E232F" },
    { value = 22,  label = "Worn Graphite",               hex = "#363A3F" },
    { value = 23,  label = "Worn Silver Grey",            hex = "#A0A199" },
    { value = 24,  label = "Worn Silver",                 hex = "#D3D3D3" },
    { value = 25,  label = "Worn Blue Silver",            hex = "#B7BFCA" },
    { value = 26,  label = "Worn Shadow Silver",          hex = "#778794" },
    { value = 27,  label = "Metallic Red",                hex = "#C00E1A" },
    { value = 28,  label = "Metallic Torino Red",         hex = "#DA1918" },
    { value = 29,  label = "Metallic Formula Red",        hex = "#B6111B" },
    { value = 30,  label = "Metallic Blaze Red",          hex = "#A51E23" },
    { value = 31,  label = "Metallic Graceful Red",       hex = "#7B1A22" },
    { value = 32,  label = "Metallic Garnet Red",         hex = "#8E1B1F" },
    { value = 33,  label = "Metallic Desert Red",         hex = "#6F1818" },
    { value = 34,  label = "Metallic Cabernet Red",       hex = "#49111D" },
    { value = 35,  label = "Metallic Candy Red",          hex = "#B60F25" },
    { value = 36,  label = "Metallic Sunrise Orange",     hex = "#D44A17" },
    { value = 37,  label = "Metallic Classic Gold",       hex = "#C2944F" },
    { value = 38,  label = "Metallic Orange",             hex = "#F78616" },
    { value = 39,  label = "Matte Red",                   hex = "#CF1F21" },
    { value = 40,  label = "Matte Dark Red",              hex = "#732021" },
    { value = 41,  label = "Matte Orange",                hex = "#F27D20" },
    { value = 42,  label = "Matte Yellow",                hex = "#FFC91F" },
    { value = 43,  label = "Util Red",                    hex = "#9C1016" },
    { value = 44,  label = "Util Bright Red",             hex = "#DE0F18" },
    { value = 45,  label = "Util Garnet Red",             hex = "#8F1E17" },
    { value = 46,  label = "Worn Red",                    hex = "#A94744" },
    { value = 47,  label = "Worn Golden Red",             hex = "#B16C51" },
    { value = 48,  label = "Worn Dark Red",               hex = "#371C25" },
    { value = 49,  label = "Metallic Dark Green",         hex = "#132428" },
    { value = 50,  label = "Metallic Racing Green",       hex = "#122E2B" },
    { value = 51,  label = "Metallic Sea Green",          hex = "#12383C" },
    { value = 52,  label = "Metallic Olive Green",        hex = "#31423F" },
    { value = 53,  label = "Metallic Green",              hex = "#155C2D" },
    { value = 54,  label = "Metallic Gasoline Blue Green", hex = "#1B6770" },
    { value = 55,  label = "Matte Lime Green",            hex = "#66B81F" },
    { value = 56,  label = "Util Dark Green",             hex = "#22383E" },
    { value = 57,  label = "Util Green",                  hex = "#1D5A3F" },
    { value = 58,  label = "Worn Dark Green",             hex = "#2D423F" },
    { value = 59,  label = "Worn Green",                  hex = "#45594B" },
    { value = 60,  label = "Worn Sea Wash",               hex = "#65867F" },
    { value = 61,  label = "Metallic Midnight Blue",      hex = "#222E46" },
    { value = 62,  label = "Metallic Dark Blue",          hex = "#233155" },
    { value = 63,  label = "Metallic Saxony Blue",        hex = "#304C7E" },
    { value = 64,  label = "Metallic Blue",               hex = "#47578F" },
    { value = 65,  label = "Metallic Mariner Blue",       hex = "#637BA7" },
    { value = 66,  label = "Metallic Harbor Blue",        hex = "#394762" },
    { value = 67,  label = "Metallic Diamond Blue",       hex = "#D6E7F1" },
    { value = 68,  label = "Metallic Surf Blue",          hex = "#76AFBE" },
    { value = 69,  label = "Metallic Nautical Blue",      hex = "#345E72" },
    { value = 70,  label = "Metallic Bright Blue",        hex = "#0B9CF1" },
    { value = 71,  label = "Metallic Purple Blue",        hex = "#2F2D52" },
    { value = 72,  label = "Metallic Spinnaker Blue",     hex = "#282C4D" },
    { value = 73,  label = "Metallic Ultra Blue",         hex = "#2354A1" },
    { value = 74,  label = "Metallic Light Blue",         hex = "#6EA3C6" },
    { value = 75,  label = "Util Dark Blue",              hex = "#112552" },
    { value = 76,  label = "Util Midnight Blue",          hex = "#1B203E" },
    { value = 77,  label = "Util Blue",                   hex = "#275190" },
    { value = 78,  label = "Util Sea Foam Blue",          hex = "#608592" },
    { value = 79,  label = "Util Lightning Blue",         hex = "#2446A8" },
    { value = 80,  label = "Util Maui Blue Poly",         hex = "#4271E1" },
    { value = 81,  label = "Util Bright Blue",            hex = "#3B39E0" },
    { value = 82,  label = "Matte Dark Blue",             hex = "#1F2852" },
    { value = 83,  label = "Matte Blue",                  hex = "#253AA7" },
    { value = 84,  label = "Matte Midnight Blue",         hex = "#1C3551" },
    { value = 85,  label = "Worn Dark Blue",              hex = "#4C5F81" },
    { value = 86,  label = "Worn Blue",                   hex = "#58688E" },
    { value = 87,  label = "Worn Light Blue",             hex = "#74B5D8" },
    { value = 88,  label = "Metallic Taxi Yellow",        hex = "#FFCF20" },
    { value = 89,  label = "Metallic Race Yellow",        hex = "#FBE212" },
    { value = 90,  label = "Metallic Bronze",             hex = "#916532" },
    { value = 91,  label = "Metallic Yellow Bird",        hex = "#E0E13D" },
    { value = 92,  label = "Metallic Lime",               hex = "#98D223" },
    { value = 93,  label = "Metallic Champagne",          hex = "#9B8C78" },
    { value = 94,  label = "Metallic Pueblo Beige",       hex = "#503218" },
    { value = 95,  label = "Metallic Dark Ivory",         hex = "#473F2B" },
    { value = 96,  label = "Metallic Choco Brown",        hex = "#221B19" },
    { value = 97,  label = "Metallic Golden Brown",       hex = "#653F23" },
    { value = 98,  label = "Metallic Light Brown",        hex = "#775C3E" },
    { value = 99,  label = "Metallic Straw Beige",        hex = "#AC9975" },
    { value = 100, label = "Metallic Moss Brown",         hex = "#6C6B4B" },
    { value = 101, label = "Metallic Biston Brown",       hex = "#402E2B" },
    { value = 102, label = "Metallic Beechwood",          hex = "#A4965F" },
    { value = 103, label = "Metallic Dark Beechwood",     hex = "#46231A" },
    { value = 104, label = "Metallic Choco Orange",       hex = "#752B19" },
    { value = 105, label = "Metallic Beach Sand",         hex = "#BFAE7B" },
    { value = 106, label = "Metallic Sun Bleached Sand",  hex = "#DFD5B2" },
    { value = 107, label = "Metallic Cream",              hex = "#F7EDD5" },
    { value = 108, label = "Util Brown",                  hex = "#3A2A1B" },
    { value = 109, label = "Util Medium Brown",           hex = "#785F33" },
    { value = 110, label = "Util Light Brown",            hex = "#B5A079" },
    { value = 111, label = "Metallic White",              hex = "#FFFFF6" },
    { value = 112, label = "Metallic Frost White",        hex = "#EAEAEA" },
    { value = 113, label = "Worn Honey Beige",            hex = "#B0AB94" },
    { value = 114, label = "Worn Brown",                  hex = "#453831" },
    { value = 115, label = "Worn Dark Brown",             hex = "#2A282B" },
    { value = 116, label = "Worn Straw Beige",            hex = "#726C57" },
    { value = 117, label = "Brushed Steel",               hex = "#6A747C" },
    { value = 118, label = "Brushed Black Steel",         hex = "#354158" },
    { value = 119, label = "Brushed Aluminium",           hex = "#9BA0A8" },
    { value = 120, label = "Chrome",                      hex = "#C8CCD0" },
    { value = 121, label = "Worn Off White",              hex = "#EAE6DE" },
    { value = 122, label = "Util Off White",              hex = "#DFDDD0" },
    { value = 123, label = "Worn Orange",                 hex = "#F2AD2E" },
    { value = 124, label = "Worn Light Orange",           hex = "#F9A458" },
    { value = 125, label = "Metallic Securicor Green",    hex = "#83C566" },
    { value = 126, label = "Worn Taxi Yellow",            hex = "#F1CC40" },
    { value = 127, label = "Police Car Blue",             hex = "#4CC3DA" },
    { value = 128, label = "Matte Green",                 hex = "#4E6443" },
    { value = 129, label = "Matte Brown",                 hex = "#BCAC8F" },
    { value = 130, label = "Worn Pale Orange",            hex = "#F8B658" },
    { value = 131, label = "Matte White",                 hex = "#FCF9F1" },
    { value = 132, label = "Worn White",                  hex = "#FFFFFB" },
    { value = 133, label = "Worn Olive Army Green",       hex = "#81844C" },
    { value = 134, label = "Pure White",                  hex = "#FFFFFF" },
    { value = 135, label = "Hot Pink",                    hex = "#F21F99" },
    { value = 136, label = "Salmon Pink",                 hex = "#FDD6CD" },
    { value = 137, label = "Metallic Vermillion Pink",    hex = "#DF5891" },
    { value = 138, label = "Orange",                      hex = "#F6AE20" },
    { value = 139, label = "Green",                       hex = "#B0EE6E" },
    { value = 140, label = "Blue",                        hex = "#08E9FA" },
    { value = 141, label = "Metallic Black Blue",         hex = "#0A0C17" },
    { value = 142, label = "Metallic Black Purple",       hex = "#0C0D18" },
    { value = 143, label = "Metallic Black Red",          hex = "#0E0D14" },
    { value = 144, label = "Hunter Green",                hex = "#9F9E8A" },
    { value = 145, label = "Metallic Purple",             hex = "#621276" },
    { value = 146, label = "Metallic Very Dark Blue",     hex = "#0B1421" },
    { value = 147, label = "Modshop Black",               hex = "#11141A" },
    { value = 148, label = "Matte Purple",                hex = "#6B1F7B" },
    { value = 149, label = "Matte Dark Purple",           hex = "#1E1D22" },
    { value = 150, label = "Metallic Lava Red",           hex = "#BC1917" },
    { value = 151, label = "Matte Forest Green",          hex = "#2D362A" },
    { value = 152, label = "Matte Olive Drab",            hex = "#696748" },
    { value = 153, label = "Matte Desert Brown",          hex = "#7A6C55" },
    { value = 154, label = "Matte Desert Tan",            hex = "#C3B492" },
    { value = 155, label = "Matte Foliage Green",         hex = "#5A6352" },
    { value = 156, label = "Default Alloy",               hex = "#81827F" },
    { value = 157, label = "Epsilon Blue",                hex = "#AFD6E4" },
    { value = 158, label = "Pure Gold",                   hex = "#7A6440" },
    { value = 159, label = "Brushed Gold",                hex = "#7F6A48" },
}
