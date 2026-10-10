--[[
   _____                   _ _
  / ____|                 | (_)
 | (___  _   _ _ __  _ __ | |_  ___ _ __
  \___ \| | | | '_ \| '_ \| | |/ _ \ '__|
  ____) | |_| | |_) | |_) | | |  __/ |
 |_____/ \__,_| .__/| .__/|_|_|\___|_|
              | |   | |
              |_|   |_|
 Items are keys of Config.Items (config.lua).
 price    = price of one piece in the "instant" mode (other modes use multiplier)
 category = service / core / ev / body / tools / kits / props / performance / visual
 limit    = optional max pieces per workshop per day (all modes together)
 minGrade = optional minimal job grade that can see and order the item
]]--

Config.Supplier = {
    payFrom = "society",      -- "society" (workshop account) / "player" (player who orders)
    playerAccount = "bank",   -- "bank" / "cash" - used when payFrom = "player"
    orderCooldown = 3,        -- s between two orders of one player
    maxCount = 999,           -- max pieces of one item in one order
    historySize = 20,         -- last orders shown in the supplier window

    -- Delivery modes. Workshop owner can disable them in workshop settings.
    modes = {
        instant = { enabled = true, multiplier = 1.0 },                 -- straight to the workshop storage
        delayed = { enabled = true, multiplier = 0.85, minutes = 15 },  -- to the storage after X minutes (survives restart)
        run     = { enabled = true, multiplier = 0.65 },                -- mechanic picks the goods up with a supply van
    },

    -- Supply run: van spawns at the workshop "garage" point, crates are loaded at a random pickup
    -- and unloaded at the workshop "supply" point. Anyone can steal crates from an unlocked van (mech_supply_crate).
    -- Every crate is carried by hand: pile -> rear of the van (pickup), rear of the van -> supply point (workshop).
    run = {
        vehicle = "burrito3",       -- model from Config.ServiceVehicles
        vehicleType = "automobile", -- CreateVehicleServerSetter type (automobile / bike / boat / heli / plane / trailer)
        platePrefix = "SUPP",       -- plate = prefix + 4 random digits (max 8 chars)
        itemsPerCrate = 10,         -- item pieces in one crate
        maxCrates = 12,             -- van capacity, bigger "run" orders are refused
        timeLimit = 30,             -- min to finish the run, then orders return to "awaiting pickup"
        vanDistance = 15.0,         -- m, van must be parked this close to pickup / supply point
        loadDuration = 4000,        -- ms per crate at pickup (take it from the pile 40 % + put it into the van 60 %)
        unloadDuration = 3500,      -- ms per crate at the workshop (take it out of the van 80 % + put it down)
        takeDuration = 3000,        -- ms to take one crate out of a van (theft / manual carry)
        vanDespawn = 20,            -- s after completed run before the van is returned (when nobody drives it)
        pileProp = "prop_boxpile_07d", -- crate pile at pickup (nil = no prop)
        -- carried crate (box carry placement, bone 60309 = left hand)
        crate = { model = "prop_cs_cardbox_01", bone = 60309, pos = vec3(0.025, 0.08, 0.255), rot = vec3(-145.0, 290.0, 0.0) },
        vanDoors = { 2, 3, 5 },     -- doors opened while loading / unloading, only doors at the rear end of the van are used
        carryDistance = 2.0,        -- m from the van rear / pile / supply point where a crate is taken / put down
        stackSize = 6,              -- crates stacked at the workshop supply point while unloading (visual only)
        stackTime = 60,             -- s the stacked crates stay after the last one was put down
        anims = {
            lift = { dict = "anim@heists@load_box", clip = "lift_box", flag = 0 },    -- take a crate from the pile / van
            load = { dict = "anim@heists@load_box", clip = "load_box_1", flag = 0 },  -- put a crate into the van
        },
        blip = { sprite = 478, color = 5, scale = 0.9 },
        locations = {
            { label = "Port of Los Santos - Pier 400", coords = vector4(272.4, -3015.3, 5.7, 90.0) },
            { label = "Elysian Island - Pacific Bait", coords = vector4(51.5, -2568.5, 6.0, 0.0) },
            { label = "Terminal - Container Yard",    coords = vector4(1209.0, -3108.0, 5.8, 0.0) },
        },
    },

    catalog = {
        -- service
        { item = "engine_oil",         price = 60,    category = "service" },
        { item = "oil_filter",         price = 25,    category = "service" },
        { item = "air_filter",         price = 35,    category = "service" },
        { item = "fuel_filter",        price = 40,    category = "service" },
        { item = "spark_plugs",        price = 45,    category = "service" },
        { item = "coolant",            price = 30,    category = "service" },
        { item = "brake_fluid",        price = 25,    category = "service" },
        { item = "transmission_fluid", price = 55,    category = "service" },
        { item = "brake_pads",         price = 120,   category = "service" },
        { item = "tyre",               price = 180,   category = "service" },
        { item = "timing_belt",        price = 220,   category = "service" },
        -- core parts
        { item = "engine_parts",       price = 4500,  category = "core", limit = 15 },
        { item = "transmission_parts", price = 3500,  category = "core", limit = 15 },
        { item = "clutch_kit",         price = 900,   category = "core" },
        { item = "radiator",           price = 450,   category = "core" },
        { item = "alternator",         price = 380,   category = "core" },
        { item = "car_battery",        price = 220,   category = "core" },
        { item = "fuel_pump",          price = 320,   category = "core" },
        { item = "brake_discs",        price = 260,   category = "core" },
        { item = "shock_absorber",     price = 180,   category = "core" },
        { item = "turbocharger",       price = 2800,  category = "core", limit = 10 },
        -- electric vehicles
        { item = "ev_battery_module",  price = 6000,  category = "ev", limit = 20 },
        { item = "ev_motor",           price = 7500,  category = "ev", limit = 10 },
        { item = "ev_coolant",         price = 70,    category = "ev" },
        -- body
        { item = "car_door",           price = 450,   category = "body" },
        { item = "car_hood",           price = 400,   category = "body" },
        { item = "car_trunk",          price = 350,   category = "body" },
        { item = "car_bumper",         price = 300,   category = "body" },
        { item = "car_glass",          price = 250,   category = "body" },
        { item = "car_headlight",      price = 180,   category = "body" },
        { item = "car_wheel",          price = 350,   category = "body" },
        { item = "body_panel",         price = 150,   category = "body" },
        -- tools
        { item = "obd_scanner",        price = 1200,  category = "tools", limit = 5 },
        { item = "toolbox",            price = 650,   category = "tools", limit = 10 },
        { item = "impact_wrench",      price = 480,   category = "tools", limit = 10 },
        { item = "car_jack",           price = 350,   category = "tools", limit = 10 },
        { item = "jump_starter",       price = 280,   category = "tools", limit = 10 },
        { item = "slim_jim",           price = 150,   category = "tools", limit = 10 },
        { item = "tuning_laptop",      price = 3500,  category = "tools", limit = 3 },
        { item = "spray_gun",          price = 450,   category = "tools", limit = 5 },
        { item = "service_book",       price = 20,    category = "tools" },
        -- repair kits
        { item = "repair_kit",         price = 350,   category = "kits" },
        { item = "advanced_repair_kit",price = 1200,  category = "kits", limit = 20 },
        { item = "patch_kit",          price = 180,   category = "kits" },
        { item = "cleaning_kit",       price = 60,    category = "kits" },
        -- road equipment
        { item = "traffic_cone",       price = 25,    category = "props" },
        { item = "road_barrier",       price = 90,    category = "props" },
        { item = "work_sign",          price = 60,    category = "props" },
        -- performance tuning
        { item = "engine_stage1",      price = 5000,  category = "performance" },
        { item = "engine_stage2",      price = 9000,  category = "performance" },
        { item = "engine_stage3",      price = 15000, category = "performance", limit = 5 },
        { item = "engine_stage4",      price = 25000, category = "performance", limit = 3, minGrade = 3 },
        { item = "brakes_stage1",      price = 2000,  category = "performance" },
        { item = "brakes_stage2",      price = 4000,  category = "performance" },
        { item = "brakes_stage3",      price = 7000,  category = "performance", limit = 5 },
        { item = "transmission_stage1",price = 3000,  category = "performance" },
        { item = "transmission_stage2",price = 6000,  category = "performance" },
        { item = "transmission_stage3",price = 10000, category = "performance", limit = 5 },
        { item = "suspension_stage1",  price = 1500,  category = "performance" },
        { item = "suspension_stage2",  price = 3000,  category = "performance" },
        { item = "suspension_stage3",  price = 5000,  category = "performance" },
        { item = "suspension_stage4",  price = 8000,  category = "performance", limit = 5 },
        { item = "armor_stage1",       price = 5000,  category = "performance" },
        { item = "armor_stage2",       price = 8500,  category = "performance" },
        { item = "armor_stage3",       price = 12500, category = "performance", limit = 5 },
        { item = "armor_stage4",       price = 17500, category = "performance", limit = 3 },
        { item = "armor_stage5",       price = 25000, category = "performance", limit = 2, minGrade = 3 },
        { item = "turbo_kit",          price = 12000, category = "performance", limit = 5 },
        -- visual tuning
        { item = "paint_can",          price = 150,   category = "visual" },
        { item = "bodykit_parts",      price = 800,   category = "visual" },
        { item = "rims",               price = 1200,  category = "visual" },
        { item = "tyre_smoke_kit",     price = 450,   category = "visual" },
        { item = "xenon_kit",          price = 600,   category = "visual" },
        { item = "neon_kit",           price = 900,   category = "visual" },
        { item = "window_tint",        price = 200,   category = "visual" },
        { item = "vinyl",              price = 350,   category = "visual" },
        { item = "interior_parts",     price = 700,   category = "visual" },
        { item = "horn",               price = 150,   category = "visual" },
        { item = "plate_kit",          price = 120,   category = "visual" },
    },
}

--[[
  ____  _ _ _ _
 |  _ \(_) | (_)
 | |_) |_| | |_ _ __   __ _
 |  _ <| | | | | '_ \ / _` |
 | |_) | | | | | | | | (_| |
 |____/|_|_|_|_|_| |_|\__, |
                       __/ |
                      |___/
 Bill lines are prefilled from the work done on the vehicle:
 labor * workshop laborMultiplier + supplier price of used parts * (1 + workshop partsMarkup %)
]]--

Config.Billing = {
    command = "mechbills",      -- customers reopen their unpaid bills (empty = no command)
    distance = 6.0,             -- m, customer must be this close to the mechanic
    maxLines = 25,              -- max lines of one bill
    maxLinePrice = 100000,      -- max price of one line (per piece)
    maxTotal = 500000,          -- max total of one bill
    maxNoteLength = 200,        -- characters
    maxPending = 5,             -- max unpaid bills of one customer at once
    expireMinutes = 30,         -- unpaid bill expires after X minutes (0 = never)
    methods = { "cash", "bank" }, -- payment methods for customers
    commissionPayout = "bank",  -- "bank" / "cash" - how the mechanic receives commission (workshop setting %)
    sendCooldown = 5,           -- s between two bills of one mechanic
}
