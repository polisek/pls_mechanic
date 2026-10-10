--[[
  _   _ _____   _____   __  __ _         _
 | \ | |  __ \ / ____| |  \/  (_)       (_)
 |  \| | |__) | |      | \  / |_ ___ ___ _  ___  _ __  ___
 | . ` |  ___/| |      | |\/| | / __/ __| |/ _ \| '_ \/ __|
 | |\  | |    | |____  | |  | | \__ \__ \ | (_) | | | \__ \
 |_| \_|_|     \_____| |_|  |_|_|___/___/_|\___/|_| |_|___/

 Mechanic on duty with permission "missions" picks a mission type in the mechanic menu.
 The vehicle is spawned when the mechanic gets close (spawnDistance) and is moved to the nearest road side.
 Items are keys of Config.Items (config.lua). Rewards: money item "money" + materials.

 Mission actions are scenes (Anim library, client/animations.lua). Scene phases: share = part of the action
 duration (the server accepts the action after 80 % of "duration"), anim / prop / sound / particle as in
 configs/extras.lua (tables or Config.Animations preset keys).
]]--

-- Presets of this file
local Kneel = { dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", clip = "machinic_loop_mechandplayer", flag = 1 }
local Twist = { dict = "missheistfbisetup1", clip = "unlock_loop_janitor", flag = 1 }   -- twisting a cap / bolt at waist height
local Pour = { dict = "timetable@gardener@filling_can", clip = "gar_ig_5_filling_can", flag = 1 }
local Weld = { scenario = "WORLD_HUMAN_WELDING" }         -- own torch, mask and sparks of the game
local Hammer = { scenario = "WORLD_HUMAN_HAMMERING" }     -- own hammer of the game
local ImpactWrench = "impact_wrench"                      -- Config.Props key
local ImpactSound = "impact"                              -- Config.Animations.Sounds key (bursts of an air tool)
local JerryCan = { model = "w_am_jerrycan", bone = 57005, pos = vec3(0.18, 0.13, -0.12), rot = vec3(-165.0, -11.0, -5.0) }

Config.Missions = {
    enabled = true,
    cooldown = 120,             -- s between two missions of one character
    timeout = 30,               -- min to finish the mission, then it's cancelled
    spawnDistance = 180.0,      -- vehicle is created when the mechanic gets this close to the location
    snapToRoad = true,          -- move vehicle from location to the nearest road side
    snapRadius = 150.0,         -- max distance of the road side from the location
    despawnDelay = 45,          -- s after the mission before the vehicle is removed
    societyShare = 20,          -- % of money reward paid on top to the society of the workshop (0 = off)

    blip = { sprite = 225, color = 47, scale = 0.9, route = true },          -- mission vehicle
    dropOffBlip = { sprite = 357, color = 5, scale = 0.9, route = true },   -- tow drop-off

    -- Owner of the vehicle waiting next to it
    npc = {
        chance = 75,            -- % of missions with owner
        models = {
            "a_m_y_business_01", "a_f_y_business_01", "a_m_m_farmer_01", "a_m_y_hipster_01",
            "a_f_y_tourist_01", "a_m_m_salton_01", "a_m_y_genstreet_01", "a_f_m_bevhills_01",
        },
        scenarios = { "WORLD_HUMAN_STAND_MOBILE", "WORLD_HUMAN_SMOKING", "WORLD_HUMAN_STAND_IMPATIENT", "WORLD_HUMAN_AA_COFFEE" },
        greetDistance = 15.0,   -- owner waves when the mechanic arrives
        greet = { dict = "friends@frj@ig_1", clip = "wave_a", time = 2500 },
        watchDistance = 25.0,   -- owner watches the mechanic while he is this close
        waiting = "WORLD_HUMAN_STAND_IMPATIENT", -- owner's scenario while the mechanic works on the vehicle (nil = keep)
        -- after the job: the owner walks to the mechanic, pays and gives a thumbs up
        pay = { dict = "mp_common", clip = "givetake1_a", time = 1800, prop = { model = "prop_anim_cash_note", bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) } },
        take = { dict = "mp_common", clip = "givetake1_b", flag = 0, time = 1800 },  -- mechanic takes the money
        thanks = { dict = "anim@mp_player_intselfiethumbs_up", clip = "idle_a" },
    },

    -- Customer vehicles (model or { model, type } - type for CreateVehicleServerSetter, default "automobile")
    vehicles = {
        "asea", "premier", "stanier", "primo", "ingot", "tailgater", "emperor", "fugitive", "washington",
        "intruder", "regina", "stratum", "minivan", "baller", "cavalcade", "granger", "blista", "issi2",
        "panto", "rancherxl", "bison", "sadler", "bobcatxl", "youga", "felon", "oracle", "buffalo", "dominator",
    },

    -- Roadside locations. With snapToRoad the vehicle is placed on the nearest road side,
    -- heading (w) is used only when no road is found.
    locations = {
        city = {
            vector4(-2480.9, -212.0, 17.4, 60.0),      -- Pacific Bluffs
            vector4(-2723.4, 13.2, 15.1, 45.0),        -- Pacific Bluffs
            vector4(-1656.9, -246.2, 54.5, 70.0),      -- Morningwood
            vector4(-1586.7, -647.6, 29.4, 140.0),     -- Del Perro
            vector4(-1036.1, -491.1, 36.2, 120.0),     -- Rockford Hills
            vector4(-1613.9, 18.8, 61.8, 330.0),       -- Richman
            vector4(-521.9, -266.8, 34.9, 290.0),      -- Rockford Hills
            vector4(-366.9, 115.5, 65.6, 90.0),        -- West Vinewood
            vector4(-111.9, 92.0, 71.1, 60.0),         -- West Vinewood
            vector4(75.2, 164.9, 104.7, 160.0),        -- Vinewood
            vector4(327.6, -205.1, 53.1, 160.0),       -- Alta
            vector4(229.3, -365.9, 43.8, 70.0),        -- Alta
            vector4(-85.8, -51.7, 61.1, 70.0),         -- Hawick
            vector4(487.2, -30.8, 88.9, 240.0),        -- Downtown Vinewood
            vector4(27.2, -1030.9, 29.4, 250.0),       -- Pillbox Hill
            vector4(-534.6, -756.7, 31.6, 180.0),      -- Little Seoul
            vector4(-772.2, -1281.8, 4.6, 170.0),      -- La Puerta
            vector4(-556.1, -1794.7, 22.0, 150.0),     -- La Puerta
            vector4(322.4, -1900.5, 25.8, 50.0),       -- Rancho
            vector4(719.1, -767.8, 24.9, 90.0),        -- La Mesa
            vector4(1192.1, -1336.9, 35.1, 175.0),     -- El Burro Heights
            vector4(1181.4, -330.8, 69.3, 100.0),      -- Mirror Park
            vector4(2581.3, 362.0, 108.5, 90.0),       -- Tataviam Mountains
        },
        county = {
            vector4(-3169.6, 976.2, 15.0, 20.0),       -- Chumash
            vector4(-2555.0, 2334.4, 33.1, 95.0),      -- Lago Zancudo
            vector4(49.4, 2778.8, 58.0, 140.0),        -- Route 68
            vector4(263.9, 2606.5, 45.0, 10.0),        -- Harmony
            vector4(1040.0, 2671.1, 39.6, 0.0),        -- Route 68
            vector4(2539.7, 2594.2, 37.9, 290.0),      -- Senora Freeway
            vector4(2679.9, 3263.9, 55.2, 240.0),      -- Senora Freeway
            vector4(1784.3, 3330.6, 41.3, 30.0),       -- Sandy Shores
            vector4(2005.1, 3773.9, 32.4, 210.0),      -- Sandy Shores
            vector4(1687.2, 4929.4, 42.1, 55.0),       -- Grapeseed
            vector4(1701.3, 6416.0, 32.8, 155.0),      -- Great Ocean Highway
            vector4(179.9, 6602.8, 31.9, 220.0),       -- Paleto Bay
            vector4(80.4, 6424.1, 31.7, 45.0),         -- Paleto Bay
            vector4(-94.5, 6419.6, 31.5, 45.0),        -- Paleto Bay
        },
    },

    -- Mission types. areas = keys of locations, reward.items = { item, min, max, chance % }
    types = {
        -- Broken-down vehicle, tow it to the workshop (bay / lift / garage point of duty workshop) or to dropOffs
        tow = {
            enabled = true,
            icon = "fa-solid fa-truck-pickup",
            areas = { "city", "county" },
            engineHealth = 100.0,           -- native engine health of the broken vehicle (smoking, undriveable)
            coreDamage = { engine = 5.0 },  -- core parts set to this health (vehicle module)
            dropRadius = 15.0,
            dropOffs = {                    -- used when workshop has no suitable point
                vector3(-337.4, -136.9, 38.6),
                vector3(731.8, -1088.8, 22.2),
                vector3(-1155.5, -2007.2, 13.2),
                vector3(1175.0, 2640.2, 37.8),
                vector3(111.0, 6626.4, 31.8),
            },
            reward = {
                money = { min = 700, max = 1200 },
                items = {},
            },
        },
        -- Dead battery, use jump starter (item "jump_starter", scene in configs/extras.lua Config.JumpStart)
        jumpstart = {
            enabled = true,
            icon = "fa-solid fa-car-battery",
            areas = { "city", "county" },
            reward = {
                money = { min = 350, max = 600 },
                items = {},
            },
        },
        -- Burst tyre, replace it (tyre item + jack) or with repair module tyre quick repair.
        -- Scene: new tyre + jack next to the wheel, jack up, unbolt, old tyre off, new tyre on, bolt, lower.
        tyre = {
            enabled = true,
            icon = "fa-solid fa-circle-dot",
            areas = { "city", "county" },
            items = { { item = "tyre", count = 1 } },
            tools = { "car_jack" },
            duration = 18000,
            jack = "car_jack",              -- Config.Props key, put under the sill (nil = no prop)
            jackLift = 0.12,                -- m the vehicle is lifted by the jack (0 = no lift)
            tyreProp = "wheel",             -- carried tyre (Config.Props / Config.Animations.Props key)
            phases = {
                jack    = { label = "mission_tyre_phase_jack",    share = 0.14, anim = Kneel },
                loosen  = { label = "mission_tyre_phase_loosen",  share = 0.18, anim = Kneel, prop = ImpactWrench, sound = ImpactSound },
                remove  = { label = "mission_tyre_phase_remove",  share = 0.14, anim = Kneel },
                mount   = { label = "mission_tyre_phase_mount",   share = 0.18, anim = Kneel },
                tighten = { label = "mission_tyre_phase_tighten", share = 0.22, anim = Kneel, prop = ImpactWrench, sound = ImpactSound },
                lower   = { label = "mission_tyre_phase_lower",   share = 0.14, anim = Kneel },
            },
            reward = {
                money = { min = 400, max = 700 },
                items = { { item = "rubber", min = 1, max = 1, chance = 50 } },
            },
        },
        -- Empty tank, refuel with jerry can: can put down next to the filler, cap off, pour, cap on
        refuel = {
            enabled = true,
            icon = "fa-solid fa-gas-pump",
            areas = { "city", "county" },
            fuel = 35.0,                    -- fuel level after refuel
            duration = 12000,
            can = JerryCan,                 -- carried in one hand, put down next to the filler, used for pouring
            phases = {
                open  = { label = "mission_refuel_phase_open",  share = 0.15, anim = Twist },
                pour  = { label = "mission_refuel_phase_pour",  share = 0.70, anim = Pour, prop = JerryCan },
                close = { label = "mission_refuel_phase_close", share = 0.15, anim = Twist },
            },
            reward = {
                money = { min = 250, max = 450 },
                items = {},
            },
        },
        -- Abandoned wreck, scrap it for materials. Every step: work at a spot, the part comes off,
        -- the mechanic carries it to the scrap pile next to the wreck.
        scrap = {
            enabled = true,
            icon = "fa-solid fa-recycle",
            areas = { "county", "city" },
            npc = false,                    -- no owner waits at wreck
            vehicles = { "emperor2", "tornado3", "tornado4", "rebel", "voodoo2", "ratloader", "surfer2" },
            duration = 36000,               -- total, split into steps around the vehicle
            steps = 3,
            tools = { "toolbox" },
            pile = vec3(-2.6, 0.0, 0.0),    -- scrap pile offset from the wreck (x < 0 driver side)
            -- spots (used in this order, repeated when steps > spots): access = hood / trunk / wheel / under,
            -- door = door broken off after the step, wheel = wheel index broken off, part = carried part
            spots = {
                { access = "hood", door = 4, part = "bonnet", phases = {
                    { label = "mission_scrap_phase_cut", share = 0.6, anim = Weld },
                    { label = "mission_scrap_phase_hammer", share = 0.4, anim = Hammer },
                } },
                { access = "wheel", wheel = 0, part = "wheel", phases = {
                    { label = "mission_scrap_phase_unbolt", share = 0.7, anim = Kneel, prop = ImpactWrench, sound = ImpactSound },
                    { label = "mission_scrap_phase_pry", share = 0.3, anim = Kneel },
                } },
                { access = "trunk", door = 5, part = "body_panel", phases = {
                    { label = "mission_scrap_phase_grind", share = 0.7, anim = Kneel, prop = "grinder", sound = "grinder", particle = "grind_sparks" },
                    { label = "mission_scrap_phase_hammer", share = 0.3, anim = Hammer },
                } },
                { access = "wheel", wheel = 1, part = "wheel", phases = {
                    { label = "mission_scrap_phase_unbolt", share = 0.7, anim = Kneel, prop = ImpactWrench, sound = ImpactSound },
                    { label = "mission_scrap_phase_pry", share = 0.3, anim = Kneel },
                } },
                { access = "door", door = 0, part = "car_door", phases = {
                    { label = "mission_scrap_phase_cut", share = 0.6, anim = Weld },
                    { label = "mission_scrap_phase_hammer", share = 0.4, anim = Hammer },
                } },
            },
            reward = {
                money = { min = 150, max = 300 },
                items = {
                    { item = "scrap_metal", min = 3, max = 6, chance = 100 },
                    { item = "aluminium", min = 1, max = 3, chance = 70 },
                    { item = "rubber", min = 1, max = 4, chance = 70 },
                    { item = "plastic", min = 1, max = 3, chance = 60 },
                    { item = "electronics", min = 1, max = 2, chance = 30 },
                },
            },
        },
    },
}
