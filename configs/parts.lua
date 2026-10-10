--[[
  _____           _
 |  __ \         | |
 | |__) |_ _ _ __| |_ ___
 |  ___/ _` | '__| __/ __|
 | |  | (_| | |  | |_\__ \
 |_|   \__,_|_|   \__|___/

 Items are keys of Config.Items (config.lua).
 type      = "ice" (combustion only) / "ev" (electric only) / "all"
 location  = "anywhere" / "bay" (repair bay or lift) / "lift" / "lift_or_jack"
 access    = where the mechanic stands: "hood" / "trunk" / "under" / "wheel"
 labor     = base labor price on the bill (multiplied by workshop laborMultiplier)
 duration  = ms of the repair animation
 perm      = permission needed (see Config.PermissionList)
]]--

-- Part health states (%) : > optimal = Optimal, > worn = Worn, > critical = Critical, else Failed
Config.PartStates = {
    optimal = 70,
    worn = 40,
    critical = 15,
}

Config.Mileage = {
    syncInterval = 60,       -- s, driver sends mileage to server at least this often
    syncDistance = 1.0,      -- km, send sooner when reached
    maxSpeed = 450,          -- km/h, server anti-cheat for mileage
    saveInterval = 5,        -- min, batch save of owned vehicles to database
    npcMileage = { min = 20000, max = 250000 }, -- random mileage for not owned vehicles (first time driven)
    npcWear = { min = 10, max = 90 },            -- random wear % of service parts for not owned vehicles
    npcCoreWear = { min = 0, max = 35 },         -- random damage % of core parts for not owned vehicles
    npcMinCore = 45,         -- core parts of not owned vehicles never start below this % (45 = at worst "Worn", never critical)
    npcMinService = 15,      -- service parts of not owned vehicles never start below this life %
    -- New purchase detection: vehicle registered as owned within this time after it was first driven
    -- and with less km driven = bought in a shop -> brand new condition (stolen + later registered keeps its state).
    -- Vehicle shops can also call exports.pls_mechanic:SetVehicleNew(plate)
    newVehicleWindow = 300,  -- s
    newVehicleMaxKm = 5.0,
    newOwnedMileage = { min = 5, max = 60 },     -- owned vehicle seen for the first time = brand new
    npcCacheHours = 6,       -- not owned vehicles are forgotten after this time without driving
}

-- Vehicle classes without parts system: 13 cycles, 14 boats, 15 helicopters, 16 planes, 21 trains
Config.ExcludedClasses = { [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

-- Wear multiplier by vehicle class
Config.ClassWear = {
    [0] = 1.0,  -- Compacts
    [1] = 1.0,  -- Sedans
    [2] = 1.1,  -- SUVs
    [3] = 1.0,  -- Coupes
    [4] = 1.2,  -- Muscle
    [5] = 1.1,  -- Sports Classics
    [6] = 1.3,  -- Sports
    [7] = 1.5,  -- Super
    [8] = 1.2,  -- Motorcycles
    [9] = 1.3,  -- Off-road
    [10] = 0.8, -- Industrial
    [11] = 0.8, -- Utility
    [12] = 0.9, -- Vans
    [17] = 0.9, -- Service
    [18] = 1.0, -- Emergency
    [19] = 1.2, -- Military
    [20] = 0.8, -- Commercial
    [22] = 1.6, -- Open Wheel
}

-- Extra wear from performance tuning (GTA mod level, -1 = stock). Multiplies wear of listed service parts.
Config.TuningWear = {
    engine = { mod = 11, perLevel = 0.15, parts = { "oil", "spark_plugs", "air_filter", "timing_belt" } },
    transmission = { mod = 13, perLevel = 0.15, parts = { "transmission_fluid" } },
    brakes = { mod = 12, perLevel = -0.1, parts = { "brake_pads" } },   -- better brakes wear slower
    turbo = { mod = 18, toggle = true, value = 0.25, parts = { "oil" } },
}

-- Stolen parts (pls_mechanic_illegal): normal part items with metadata { stolen = true, quality = 5..100, origin = "<vehicle>" }.
-- Illegal workshops use stolen parts first (lowest quality first), legal workshops only clean ones.
-- An installed stolen part gets the quality as its condition and the origin "unknown" (legal diagnostics shows it).
-- Inventories without metadata support (codem / core, PLS stashes) treat every part as clean.
Config.StolenParts = {
    legalAccepts = false,      -- legal shops never use stolen parts
    wearMultiplier = 1.5,      -- wear of parts with origin "unknown"
}

-- Electric vehicles (models)
Config.ElectricVehicles = {
    "voltic", "raiden", "cyclone", "cyclone2", "tezeract", "imorgon", "neon", "khamelion",
    "dilettante", "dilettante2", "surge", "iwagen", "omnisegt", "virtue", "buffalo5",
    "powersurge", "caddy", "caddy2", "caddy3", "airtug",
}

--[[
   _____                 _                                _
  / ____|               (_)                              | |
 | (___   ___ _ ____   ___  ___ ___   _ __   __ _ _ __| |_ ___
  \___ \ / _ \ '__\ \ / / |/ __/ _ \ | '_ \ / _` | '__| __/ __|
  ____) |  __/ |   \ V /| | (_|  __/ | |_) | (_| | |  | |_\__ \
 |_____/ \___|_|    \_/ |_|\___\___| | .__/ \__,_|_|   \__|___/
                                     | |
                                     |_|
 Service parts wear by driven km. Value = life in % (100 = new).
 interval = km of full life
 damages  = core parts damaged per km driven after life reached 0 (% per km)
 snap     = when life reaches 0 the linked core part fails immediately
]]--

Config.ServiceParts = {
    oil = {
        label = "Engine oil & filter", type = "ice", interval = 800,
        items = { { item = "engine_oil", count = 1 }, { item = "oil_filter", count = 1 } },
        tools = { "toolbox" },
        damages = { engine = 0.05, turbo = 0.05 },
        salvage = { { item = "used_oil", count = 1 } },
        location = "anywhere", access = "hood", duration = 20000, labor = 150, perm = "service", obd = "P0520",
    },
    air_filter = {
        label = "Air filter", type = "ice", interval = 1500,
        items = { { item = "air_filter", count = 1 } },
        tools = {},
        damages = { engine = 0.02 },
        salvage = { { item = "plastic", count = 1 } },
        location = "anywhere", access = "hood", duration = 8000, labor = 50, perm = "service", obd = "P0101",
    },
    fuel_filter = {
        label = "Fuel filter", type = "ice", interval = 2000,
        items = { { item = "fuel_filter", count = 1 } },
        tools = { "toolbox" },
        damages = { fuel_pump = 0.05 },
        salvage = { { item = "plastic", count = 1 } },
        location = "anywhere", access = "hood", duration = 12000, labor = 80, perm = "service", obd = "P0171",
    },
    spark_plugs = {
        label = "Spark plugs", type = "ice", interval = 2500,
        items = { { item = "spark_plugs", count = 1 } },
        tools = { "toolbox" },
        damages = { engine = 0.03 },
        salvage = { { item = "scrap_metal", count = 1 } },
        location = "anywhere", access = "hood", duration = 15000, labor = 100, perm = "service", obd = "P0301",
    },
    coolant = {
        label = "Coolant", type = "ice", interval = 3000,
        items = { { item = "coolant", count = 1 } },
        tools = {},
        damages = { radiator = 0.05, engine = 0.02 },
        salvage = {},
        location = "anywhere", access = "hood", duration = 10000, labor = 60, perm = "service", obd = "P0128",
    },
    brake_fluid = {
        label = "Brake fluid", type = "all", interval = 3000,
        items = { { item = "brake_fluid", count = 1 } },
        tools = {},
        damages = { brakes = 0.04 },
        salvage = {},
        location = "anywhere", access = "hood", duration = 12000, labor = 60, perm = "service", obd = nil,
    },
    transmission_fluid = {
        label = "Transmission fluid", type = "ice", interval = 4000,
        items = { { item = "transmission_fluid", count = 1 } },
        tools = { "toolbox" },
        damages = { transmission = 0.04, clutch = 0.04 },
        salvage = {},
        location = "bay", access = "under", duration = 20000, labor = 120, perm = "service", obd = "P0711",
    },
    brake_pads = {
        label = "Brake pads", type = "all", interval = 1500,
        items = { { item = "brake_pads", count = 2 } },
        tools = { "toolbox", "impact_wrench" },
        damages = { brakes = 0.08 },
        salvage = { { item = "scrap_metal", count = 1 } },
        location = "lift_or_jack", access = "wheel", duration = 25000, labor = 150, perm = "service", obd = nil,
    },
    tyres = {
        label = "Tyres", type = "all", interval = 2000,
        items = { { item = "tyre", count = 4 } },
        tools = { "impact_wrench" },
        damages = { alignment = 0.02 },
        salvage = { { item = "rubber", count = 4 } },
        location = "lift_or_jack", access = "wheel", duration = 30000, labor = 120, perm = "service", obd = nil,
    },
    timing_belt = {
        label = "Timing belt", type = "ice", interval = 6000,
        items = { { item = "timing_belt", count = 1 } },
        tools = { "toolbox" },
        damages = {},
        snap = "engine",
        salvage = { { item = "rubber", count = 1 } },
        location = "bay", access = "hood", duration = 45000, labor = 300, perm = "service", obd = "P0016",
    },
    ev_coolant = {
        label = "Battery coolant", type = "ev", interval = 4000,
        items = { { item = "ev_coolant", count = 1 } },
        tools = {},
        damages = { ev_battery = 0.04 },
        salvage = {},
        location = "anywhere", access = "hood", duration = 15000, labor = 80, perm = "service", obd = "P0C73",
    },
}

--[[
   _____                                  _
  / ____|                                | |
 | |     ___  _ __ ___   _ __   __ _ _ __| |_ ___
 | |    / _ \| '__/ _ \ | '_ \ / _` | '__| __/ __|
 | |___| (_) | | |  __/ | |_) | (_| | |  | |_\__ \
  \_____\___/|_|  \___| | .__/ \__,_|_|   \__|___/
                        | |
                        |_|
 Core parts are damaged by collisions and neglected service. Value = health in % (100 = new).
 requiresTurbo = only on vehicles with turbo mod installed
]]--

Config.CoreParts = {
    engine = {
        label = "Engine", type = "ice",
        items = { { item = "engine_parts", count = 1 } },
        tools = { "toolbox", "impact_wrench" },
        salvage = { { item = "scrap_metal", count = 3 }, { item = "aluminium", count = 2 } },
        location = "bay", access = "hood", duration = 90000, labor = 1500, perm = "repair_core", obd = "P0300",
    },
    transmission = {
        label = "Transmission", type = "ice",
        items = { { item = "transmission_parts", count = 1 } },
        tools = { "toolbox", "impact_wrench" },
        salvage = { { item = "scrap_metal", count = 3 }, { item = "aluminium", count = 1 } },
        location = "lift", access = "under", duration = 80000, labor = 1200, perm = "repair_core", obd = "P0700",
    },
    clutch = {
        label = "Clutch", type = "ice",
        items = { { item = "clutch_kit", count = 1 } },
        tools = { "toolbox", "impact_wrench" },
        salvage = { { item = "scrap_metal", count = 2 } },
        location = "lift", access = "under", duration = 60000, labor = 800, perm = "repair_core", obd = "P0806",
    },
    radiator = {
        label = "Radiator", type = "ice",
        items = { { item = "radiator", count = 1 } },
        tools = { "toolbox" },
        salvage = { { item = "aluminium", count = 2 } },
        location = "bay", access = "hood", duration = 35000, labor = 400, perm = "repair_core", obd = "P0217",
    },
    alternator = {
        label = "Alternator", type = "ice",
        items = { { item = "alternator", count = 1 } },
        tools = { "toolbox" },
        salvage = { { item = "electronics", count = 1 }, { item = "scrap_metal", count = 1 } },
        location = "bay", access = "hood", duration = 30000, labor = 350, perm = "repair_core", obd = "P0562",
    },
    battery = {
        label = "Battery", type = "all",
        items = { { item = "car_battery", count = 1 } },
        tools = {},
        salvage = { { item = "scrap_metal", count = 1 }, { item = "plastic", count = 1 } },
        location = "anywhere", access = "hood", duration = 12000, labor = 80, perm = "service", obd = "P0560",
    },
    fuel_pump = {
        label = "Fuel pump", type = "ice",
        items = { { item = "fuel_pump", count = 1 } },
        tools = { "toolbox" },
        salvage = { { item = "electronics", count = 1 } },
        location = "lift", access = "under", duration = 40000, labor = 450, perm = "repair_core", obd = "P0087",
    },
    brakes = {
        label = "Brake discs", type = "all",
        items = { { item = "brake_discs", count = 2 } },
        tools = { "toolbox", "impact_wrench" },
        salvage = { { item = "scrap_metal", count = 2 } },
        location = "lift_or_jack", access = "wheel", duration = 40000, labor = 400, perm = "repair_core", obd = "C0035",
    },
    suspension = {
        label = "Suspension", type = "all",
        items = { { item = "shock_absorber", count = 4 } },
        tools = { "toolbox", "impact_wrench" },
        salvage = { { item = "scrap_metal", count = 2 } },
        location = "lift", access = "wheel", duration = 60000, labor = 600, perm = "repair_core", obd = nil,
    },
    alignment = {
        label = "Wheel alignment", type = "all",
        items = {},
        tools = { "toolbox" },
        salvage = {},
        location = "bay", access = "wheel", duration = 25000, labor = 250, perm = "repair_core", obd = nil,
    },
    turbo = {
        label = "Turbocharger", type = "ice", requiresTurbo = true,
        items = { { item = "turbocharger", count = 1 } },
        tools = { "toolbox" },
        salvage = { { item = "scrap_metal", count = 2 }, { item = "aluminium", count = 1 } },
        location = "bay", access = "hood", duration = 45000, labor = 700, perm = "repair_core", obd = "P0299",
    },
    ev_battery = {
        label = "Traction battery", type = "ev",
        items = { { item = "ev_battery_module", count = 2 } },
        tools = { "toolbox" },
        salvage = { { item = "electronics", count = 3 } },
        location = "lift", access = "under", duration = 90000, labor = 1500, perm = "repair_core", obd = "P0A80",
    },
    ev_motor = {
        label = "Electric motor", type = "ev",
        items = { { item = "ev_motor", count = 1 } },
        tools = { "toolbox", "impact_wrench" },
        salvage = { { item = "electronics", count = 2 }, { item = "scrap_metal", count = 2 } },
        location = "lift", access = "under", duration = 80000, labor = 1300, perm = "repair_core", obd = nil,
    },
}

-- OBD code descriptions shown in diagnostics
Config.OBDCodes = {
    P0016 = "Crankshaft / camshaft position correlation",
    P0087 = "Fuel rail / system pressure too low",
    P0101 = "Mass air flow circuit range / performance",
    P0128 = "Coolant temperature below thermostat regulating temperature",
    P0171 = "System too lean",
    P0217 = "Engine overheat condition",
    P0299 = "Turbocharger underboost",
    P0300 = "Random / multiple cylinder misfire detected",
    P0301 = "Cylinder 1 misfire detected",
    P0520 = "Engine oil pressure sensor circuit",
    P0560 = "System voltage malfunction",
    P0562 = "System voltage low",
    P0700 = "Transmission control system malfunction",
    P0711 = "Transmission fluid temperature sensor range / performance",
    P0806 = "Clutch position sensor circuit range / performance",
    P0A80 = "Replace hybrid / EV battery pack",
    P0C73 = "Motor electronics coolant pump",
    C0035 = "Left front wheel speed sensor circuit",
}

--[[
  _____      _ _ _     _
 / ____|    | | (_)   (_)
| |     ___ | | |_ ___ _  ___  _ __  ___
| |    / _ \| | | / __| |/ _ \| '_ \/ __|
| |___| (_) | | | \__ \ | (_) | | | \__ \
 \_____\___/|_|_|_|___/_|\___/|_| |_|___/

 Driver reports impact severity (speed loss in km/h) and zone.
 Core damage (%) = severity * zone factor * multiplier * 0.5
]]--

Config.CollisionDamage = {
    minSeverity = 8,        -- smaller impacts are ignored
    multiplier = 1.0,
    zones = {
        front = { engine = 0.6, radiator = 1.0, alternator = 0.7, battery = 0.3, alignment = 0.4, suspension = 0.3, ev_motor = 0.4, ev_battery = 0.2 },
        rear  = { fuel_pump = 0.8, suspension = 0.4, transmission = 0.2, ev_battery = 0.4 },
        left  = { suspension = 0.8, alignment = 0.8, brakes = 0.3 },
        right = { suspension = 0.8, alignment = 0.8, brakes = 0.3 },
    },
    heavySeverity = 60,     -- extra damage above this severity
    heavy = { transmission = 0.5, clutch = 0.3, engine = 0.3, ev_motor = 0.3 },
}

--[[
  ____            _
 |  _ \          | |
 | |_) | ___   __| |_   _
 |  _ < / _ \ / _` | | | |
 | |_) | (_) | (_| | |_| |
 |____/ \___/ \__,_|\__, |
                     __/ |
                    |___/
 Native GTA damage. Keys in workflow: "door:0".."door:3", "hood", "trunk", "window:0".."window:7",
 "bumper:front", "bumper:rear", "headlight:left", "headlight:right", "tyre:<wheel>", "wheel:<wheel>",
 "fuel_tank", "deformation"
]]--

Config.BodyParts = {
    door        = { label = "Door",        items = { { item = "car_door", count = 1 } },      tools = { "toolbox" },       location = "anywhere",     duration = 20000, labor = 200 },
    hood        = { label = "Hood",        items = { { item = "car_hood", count = 1 } },      tools = { "toolbox" },       location = "anywhere",     duration = 20000, labor = 200 },
    trunk       = { label = "Trunk lid",   items = { { item = "car_trunk", count = 1 } },     tools = { "toolbox" },       location = "anywhere",     duration = 20000, labor = 200 },
    window      = { label = "Window",      items = { { item = "car_glass", count = 1 } },     tools = { "toolbox" },       location = "anywhere",     duration = 15000, labor = 150 },
    bumper      = { label = "Bumper",      items = { { item = "car_bumper", count = 1 } },    tools = { "toolbox" },       location = "anywhere",     duration = 15000, labor = 150 },
    headlight   = { label = "Headlight",   items = { { item = "car_headlight", count = 1 } }, tools = { "toolbox" },       location = "anywhere",     duration = 8000,  labor = 80 },
    tyre        = { label = "Tyre",        items = { { item = "tyre", count = 1 } },          tools = { "impact_wrench" }, location = "lift_or_jack", duration = 12000, labor = 60 },
    wheel       = { label = "Wheel",       items = { { item = "car_wheel", count = 1 } },     tools = { "impact_wrench" }, location = "lift_or_jack", duration = 15000, labor = 80 },
    fuel_tank   = { label = "Fuel tank",   items = { { item = "body_panel", count = 1 } },    tools = { "toolbox" },       location = "bay",          duration = 25000, labor = 250 },
    -- deformation: body_panel count by severity (body health < 900 / 700 / 400)
    deformation = { label = "Bodywork",    items = { { item = "body_panel", count = 1 } },    tools = { "toolbox" },       location = "bay",          duration = 40000, labor = 400,
        severity = { { maxBodyHealth = 900, count = 1 }, { maxBodyHealth = 700, count = 2 }, { maxBodyHealth = 400, count = 3 } } },
}
Config.BodyRepairPermission = "repair_body"

--[[
  _  ___ _
 | |/ (_) |
 | ' / _| |_ ___
 |  < | | __/ __|
 | . \| | |_\__ \
 |_|\_\_|\__|___/
]]--

Config.RepairKits = {
    repair_kit = {
        mechanicOnly = false,
        duration = 15000,
        engineHealth = 650,       -- native engine health set to at least this
        bodyHealth = nil,         -- nil = body not repaired
        corePartsMin = nil,       -- core parts not repaired
    },
    advanced_repair_kit = {
        mechanicOnly = true,
        jobs = { "police", "ambulance" }, -- other jobs allowed to use it
        duration = 25000,
        engineHealth = 1000,
        bodyHealth = 1000,        -- full SetVehicleFixed
        corePartsMin = 60,        -- core parts below this are raised to this value
    },
    patch_kit = {
        mechanicOnly = false,
        duration = 20000,
        failedToCritical = true,  -- failed core parts are raised to critical threshold + 1
    },
    cleaning_kit = {
        mechanicOnly = false,
        duration = 10000,
    },
}

-- Quick repairs with item directly on the vehicle (without diagnostics workflow)
Config.QuickRepairs = {
    tyre = { requireJack = true },      -- change one burst tyre
    car_wheel = { requireJack = true }, -- replace missing wheel
    car_battery = { },                  -- replace battery (core part "battery")
}
