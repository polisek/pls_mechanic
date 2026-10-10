--[[
  ______      _
 |  ____|    | |
 | |__  __  _| |_ _ __ __ _ ___
 |  __| \ \/ / __| '__/ _` / __|
 | |____ >  <| |_| | | (_| \__ \
 |______/_/\_\\__|_|  \__,_|___/

 Mechanic menu, vehicle actions, flatbed towing, placeable props,
 jump starter and public repair stations.

 Scene phases (played by the Anim library, client/animations.lua):
   label    = locale key
   share    = part of the action duration (shares of one action sum to 1.0), duration = fixed ms instead
   anim     = { dict, clip, flag } | { scenario } | Config.Animations.Anims key
   prop     = Config.Props key | Config.Animations.Props key | { model, bone, pos, rot }
   sound    = { name, set, bank?, interval?, length?, entity? } | Config.Animations.Sounds key
              (bank = script audio bank loaded for the sound, entity = "vehicle" plays it from the vehicle)
   particle = { asset, name, entity?, bone?, offset?, scale?, looped?, interval?, length? } | Config.Animations.Particles key
]]--

-- Presets of this file
local Kneel = { dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", clip = "machinic_loop_mechandplayer", flag = 1 }
local Lever = { dict = "missbigscoreprepd", clip = "pull_level_michael", flag = 1 }
local HoodWork = { dict = "mini@repair", clip = "fixing_a_ped", flag = 1 }
local HoodCheck = { dict = "mini@repair", clip = "fixing_a_player", flag = 1 }
local HydraulicsUp = { name = "Hydraulics_Up", set = "Lowrider_Super_Mod_Garage_Sounds", entity = "vehicle" }
local HydraulicsDown = { name = "Hydraulics_Down", set = "Lowrider_Super_Mod_Garage_Sounds", entity = "vehicle" }
-- box carry placement (bone 60309 = left hand, used by anim@heists@box_carry@)
local CarryBone, CarryPos, CarryRot = 60309, vec3(0.025, 0.08, 0.255), vec3(-145.0, 290.0, 0.0)

--[[
  __  __
 |  \/  |
 | \  / | ___ _ __  _   _
 | |\/| |/ _ \ '_ \| | | |
 | |  | |  __/ | | | |_| |
 |_|  |_|\___|_| |_|\__,_|
]]--

-- Mechanic menu (ox_lib context). Opened by keybind Config.Keys.mechanicMenu or from radial menu while on duty.
-- Every action is shown only when the player has its permission in the workshop.
Config.MechanicMenu = {
    radial = true,              -- add "Mechanic menu" into ox_lib radial menu while on duty
    keybind = true,             -- open with Config.Keys.mechanicMenu
    vehicleDistance = 5.0,      -- closest vehicle used by actions
    actions = {
        diagnose = true,        -- perm diagnose (repair module)
        bill = true,            -- perm billing (economy module)
        missions = true,        -- perm missions
        push = true,            -- perm tow
        flip = true,            -- perm tow
        unlock = true,          -- perm tow + slim jim item
        impound = true,         -- perm impound
        tow = true,             -- perm tow (flatbed attach / detach)
        servicebook = true,     -- perm diagnose (repair module)
    },
}

-- Pushing vehicle without driver. [W] push, [A]/[D] steer, Config.Keys.cancel stop.
Config.Push = {
    speed = 1.2,                -- m/s while pushing
    maxSpeed = 5.0,             -- player lets go when the vehicle rolls faster (m/s)
    gap = 0.35,                 -- distance between player and bumper
    height = 1.0,               -- player height above the bottom of the vehicle
    anim = { dict = "missfinale_c2ig_11", clip = "pushcar_offcliff_m" },
    -- player walks to the bumper and braces against it before pushing (one-shot anim, time = ms)
    brace = { dict = "missheistpaletoscore1", clip = "push_car_intro_a_player", flag = 0, time = 900 },
    -- classes that can't be pushed (10 industrial, 14 boats, 15 helicopters, 16 planes, 19 military, 20 commercial, 21 trains)
    blacklistClasses = { [10] = true, [14] = true, [15] = true, [16] = true, [19] = true, [20] = true, [21] = true },
}

-- Putting flipped vehicle back on wheels: player pushes from the roof side, rocks the vehicle and rolls it over
Config.Flip = {
    duration = 9000,            -- total time of all phases
    rockAngle = 7.0,            -- max rocking of the vehicle (degrees) while pushing
    rollLift = 0.35,            -- m the vehicle is lifted while it rolls over (no clipping into the ground)
    phases = {
        { label = "menu_flip_phase_brace", share = 0.15, anim = { dict = "missheistpaletoscore1", clip = "push_car_intro_a_player", flag = 2 } },
        { label = "menu_flip_phase_rock", share = 0.25, rock = 0.5, anim = { dict = "missheistpaletoscore1", clip = "push_car_loop_player", flag = 1 } },
        { label = "menu_flip_phase_rock_hard", share = 0.25, rock = 1.0, anim = { dict = "missheistpaletoscore1", clip = "push_car_loop_player", flag = 1 } },
        { label = "menu_flip_phase_roll", share = 0.35, roll = true, anim = { dict = "missfinale_c2ig_11", clip = "pushcar_offcliff_m", flag = 1 } },
    },
}

-- Unlocking locked vehicle with slim jim (item "slim_jim", perm tow)
local SlimJim = { model = "bkr_prop_fakeid_ruler_01a", bone = 57005, pos = vec3(0.12, 0.02, -0.03), rot = vec3(-80.0, 0.0, 0.0) }

Config.Unlock = {
    duration = 10000,           -- total time of all phases (server accepts the result after 90 %)
    successChance = 70,         -- %
    breakChance = 25,           -- % that slim jim breaks after failed attempt
    alarm = true,               -- failed attempt starts the car alarm
    giveKeys = true,            -- calls Config.GiveKeys (configs/client.lua) after successful unlock
    openDoor = true,            -- driver door swings open after a successful unlock
    successSound = { name = "Remote_Control_Open", set = "PI_Menu_Sounds" }, -- lock pops up (played from the vehicle)
    breakSound = { name = "Drill_Pin_Break", set = "DLC_HEIST_FLEECA_SOUNDSET", bank = "DLC_MPHEIST\\HEIST_FLEECA_DRILL" },
    phases = {
        { label = "menu_unlock_phase_check", share = 0.12, anim = { dict = "veh@break_in@0h@p_m_one@", clip = "std_locked_ds", flag = 2 } },
        { label = "menu_unlock_phase_insert", share = 0.18, prop = SlimJim, anim = { dict = "missheistfbisetup1", clip = "unlock_enter_janitor", flag = 2 } },
        { label = "menu_unlock_phase_search", share = 0.30, prop = SlimJim, anim = { dict = "missheistfbisetup1", clip = "unlock_loop_janitor", flag = 1 } },
        { label = "menu_unlock_phase_hook", share = 0.25, prop = SlimJim, anim = { dict = "missheistfbisetup1", clip = "unlock_loop_janitor", flag = 1 } },
        { label = "menu_unlock_phase_pull", share = 0.15, prop = SlimJim, anim = { dict = "veh@break_in@0h@p_m_one@", clip = "low_force_entry_ds", flag = 2 } },
    },
}

-- Impound (perm impound): photos of the vehicle from two corners, then the impound report.
-- Vehicle is handed to OpenServer.ImpoundVehicle (server/open.lua)
local Camera = { model = "prop_pap_camera_01", bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) }
local PhotoAnim = { dict = "amb@world_human_paparazzi@male@base", clip = "base", flag = 1 }
local Flash = { asset = "core", name = "ent_anim_paparazzi_flash", entity = "prop", looped = false, interval = 1500 }
local Shutter = { name = "Camera_Shoot", set = "Phone_Soundset_Franklin", interval = 1500 }

Config.Impound = {
    duration = 12000,           -- total time of all phases (server accepts the result after 90 %)
    phases = {
        { label = "menu_impound_phase_photo_front", share = 0.25, spot = "front", prop = Camera, anim = PhotoAnim, particle = Flash, sound = Shutter },
        { label = "menu_impound_phase_photo_rear", share = 0.25, spot = "rear", prop = Camera, anim = PhotoAnim, particle = Flash, sound = Shutter },
        { label = "menu_impound_phase_report", share = 0.50, spot = "side", anim = { scenario = "WORLD_HUMAN_CLIPBOARD" } },
    },
}

--[[
  ______ _       _   _              _
 |  ____| |     | | | |            | |
 | |__  | | __ _| |_| |__   ___  __| |___
 |  __| | |/ _` | __| '_ \ / _ \/ _` / __|
 | |    | | (_| | |_| |_) |  __/ (_| \__ \
 |_|    |_|\__,_|\__|_.__/ \___|\__,_|___/
]]--

-- Loading on foot: operator lowers the bed at the controls, hooks the winch cable on the vehicle,
-- winches it up (the vehicle slides onto the bed) and straps the wheels. Unloading: straps off, bed released at the
-- controls, then the vehicle stands on the ground behind the truck at once (no sliding through the bed).
-- From the driver seat the bed is operated remotely (phases without walking).
Config.Towing = {
    maxDistance = 12.0,         -- player to flatbed
    cable = true,               -- visible steel winch cable between the bed and the vehicle while winching
    phases = {
        lower   = { label = "menu_tow_phase_lower",   duration = 2500, anim = Lever, sound = HydraulicsDown },
        hook    = { label = "menu_tow_phase_hook",    duration = 3000, anim = Kneel },
        winch   = { label = "menu_tow_phase_winch",   duration = 5500, anim = Lever, sound = HydraulicsUp },
        strap   = { label = "menu_tow_phase_strap",   duration = 2500, anim = Kneel },
        unstrap = { label = "menu_tow_phase_unstrap", duration = 2500, anim = Kneel },
        release = { label = "menu_tow_phase_release", duration = 5500, anim = Lever, sound = HydraulicsDown },
    },
    -- classes that can't be loaded (14 boats, 15 helicopters, 16 planes, 20 commercial, 21 trains)
    blacklistClasses = { [14] = true, [15] = true, [16] = true, [20] = true, [21] = true },
}

-- Supported flatbed models.
-- bone     = flatbed bone the vehicle is attached to
-- offset   = attach offset from the bone, z = height of the bed surface (bottom of the loaded vehicle is placed on it)
-- rotation = attach rotation
-- search   = offset from the flatbed where the vehicle to load must stand (behind the truck)
-- radius   = search radius around "search"
-- detach   = offset from the flatbed where the vehicle is unloaded (placed on the ground), y is moved further back
--            automatically when the vehicle would touch the rear edge of the truck
-- controls = operator position (x < 0 driver side, x > 0 passenger side, y along the truck), player faces the truck
-- winch    = offset of the winch (cable start) on the bed
Config.Flatbeds = {
    flatbed = {
        bone = "bodyshell",
        offset = vec3(0.0, -2.35, 0.45),
        rotation = vec3(0.0, 0.0, 0.0),
        search = vec3(0.0, -9.0, 0.0),
        radius = 4.5,
        detach = vec3(0.0, -9.0, 0.0),
        controls = vec3(-1.0, -1.2, 0.0),
        winch = vec3(0.0, 0.2, 1.0),
    },
}

--[[
  _____  _                     _     _
 |  __ \| |                   | |   | |
 | |__) | | __ _  ___ ___  __ _| |__ | | ___  ___
 |  ___/| |/ _` |/ __/ _ \/ _` | '_ \| |/ _ \/ __|
 | |    | | (_| | (_|  __/ (_| | |_) | |  __/\__ \
 |_|    |_|\__,_|\___\___|\__,_|_.__/|_|\___||___/
]]--

-- Items placed on the ground (keys of Config.Items). Anyone can pick them up again.
-- The player walks to the chosen spot with the item and puts it down ("hand" = attach while carrying and putting down,
-- Config.Props key or { bone, pos, rot } with the item model, carry = box carry pose while walking).
Config.Placeables = {
    maxPerPlayer = 20,          -- placed props per character
    placeDistance = 6.0,        -- max distance of placed prop from player
    pickupDistance = 3.0,
    rotateStep = 5.0,           -- degrees per scroll / arrow press
    anim = {
        place = { dict = "pickup_object", clip = "putdown_low", flag = 0 },
        pickup = { dict = "pickup_object", clip = "pickup_low", flag = 0 },
    },
    placeDuration = 1300,       -- ms of the put down animation
    pickupDuration = 1200,      -- ms of the pick up animation
    items = {
        traffic_cone = { model = "prop_roadcone02a", carry = true, hand = { bone = CarryBone, pos = vec3(0.1, 0.1, 0.2), rot = CarryRot } },
        road_barrier = { model = "prop_barrier_work05", carry = true, hand = { bone = CarryBone, pos = vec3(0.1, 0.1, 0.25), rot = CarryRot } },
        work_sign    = { model = "prop_snow_sign_road_06g", carry = true, hand = { bone = CarryBone, pos = vec3(0.1, 0.1, 0.25), rot = CarryRot } },
        toolbox      = { model = "prop_tool_box_04", carry = false, hand = "toolbox" },
    },
}

--[[
      _                         _____ _             _
     | |                       / ____| |           | |
     | |_   _ _ __ ___  _ __  | (___ | |_ __ _ _ __| |_ ___ _ __
 _   | | | | | '_ ` _ \| '_ \  \___ \| __/ _` | '__| __/ _ \ '__|
| |__| | |_| | | | | | | |_) | ____) | || (_| | |  | ||  __/ |
 \____/ \__,_|_| |_| |_| .__/ |_____/ \__\__,_|_|   \__\___|_|
                       | |
                       |_|
 Item "jump_starter" - anyone can use it on a vehicle with critical / failed battery (core part "battery").
 Scene: carry the booster to the hood, put it down, open the hood, connect the clamps, charge,
 start attempt, disconnect, close the hood and pick the booster up.
]]--

Config.JumpStart = {
    duration = 15000,           -- time of the timed phases (server accepts the result after 90 %)
    batteryValue = ((Config.PartStates and Config.PartStates.critical) or 15) + 5, -- battery health after jump start
    -- booster carried to the hood and put down (nil = none)
    booster = { model = "prop_car_battery_01", bone = CarryBone, pos = CarryPos, rot = CarryRot },
    cables = true,              -- visible jumper cables between the booster and the engine bay
    startEngine = true,         -- engine starts after successful jump start
    sparks = { asset = "core", name = "ent_brk_sparking_wires", scale = 0.6 }, -- when a clamp is connected (nil = off)
    phases = {
        { label = "menu_jump_phase_red", share = 0.20, clamp = true, anim = HoodWork },
        { label = "menu_jump_phase_black", share = 0.20, clamp = true, anim = HoodWork },
        { label = "menu_jump_phase_charge", share = 0.45, anim = { dict = "amb@medic@standing@kneel@base", clip = "base", flag = 1 },
            sound = { name = "CONFIRM_BEEP", set = "HUD_MINI_GAME_SOUNDSET", interval = 3000 } },
        -- weak first start attempt (the starter cranks, the engine doesn't catch yet)
        { label = "menu_jump_phase_crank", share = 0.15, anim = HoodCheck,
            sound = { name = "IGNITION_FAIL", set = "BARRY_03_SOUNDSET", bank = "BARRY3C_IGNITION_FAIL", entity = "vehicle" } },
    },
    -- after the server accepted the jump start
    start = { label = "menu_jump_phase_start", duration = 2500, anim = HoodCheck },
    disconnect = { label = "menu_jump_phase_disconnect", duration = 2500, anim = HoodWork },
}

--[[
   _____ _        _   _
  / ____| |      | | (_)
 | (___ | |_ __ _| |_ _  ___  _ __  ___
  \___ \| __/ _` | __| |/ _ \| '_ \/ __|
  ____) | || (_| | |_| | (_) | | | \__ \
 |_____/ \__\__,_|\__|_|\___/|_| |_|___/

 Public repair stations are placed in the creator (point type "station" in config.lua).
 Price, duration, repairs, allowed jobs and "only without mechanic" are set per point.
 Service scene: the driver waits in the vehicle (engine off, hood open), cinematic camera around the vehicle,
 phases share the station duration (already paid, the service can't be cancelled).
]]--

-- short bursts of sparks at the engine bone
local StationSparks = { asset = "core", name = "ent_brk_sparking_wires", entity = "vehicle", bone = "engine", offset = vec3(0.0, 0.0, 0.3), scale = 0.8, interval = 2400, length = 700 }

Config.Stations = {
    paymentMethods = { "cash", "bank" }, -- tried in this order
    societyPayment = true,               -- money goes to the society of the workshop
    drivePrompt = true,                  -- [E] prompt for driver standing in the station (target mode only, markers have own prompt)
    promptKey = 38,                      -- E
    camera = true,                       -- cinematic camera slowly orbiting the vehicle during the service
    cameraDistance = 2.8,                -- m from the vehicle edge
    cameraHeight = 1.3,                  -- m above the vehicle center
    cameraSpeed = 9.0,                   -- degrees per second
    phases = {
        { label = "station_phase_checkin", share = 0.15, sound = { name = "CONFIRM_BEEP", set = "HUD_MINI_GAME_SOUNDSET", entity = "vehicle" } },
        { label = "station_phase_diagnostics", share = 0.25, sound = { name = "CONFIRM_BEEP", set = "HUD_MINI_GAME_SOUNDSET", entity = "vehicle", interval = 1400 } },
        { label = "station_phase_repair", share = 0.45, particle = StationSparks,
            sound = { name = "Drill", set = "DLC_HEIST_FLEECA_SOUNDSET", bank = "DLC_MPHEIST\\HEIST_FLEECA_DRILL", entity = "vehicle", interval = 2600, length = 1200 } },
        { label = "station_phase_check", share = 0.15, sound = { name = "TIMER_STOP", set = "HUD_MINI_GAME_SOUNDSET", entity = "vehicle" } },
    },
}
