Config = {}

Config.Debug = false

--[[
   _____                           _
  / ____|                         | |
 | |  __  ___ _ __   ___ _ __ __ _| |
 | | |_ |/ _ \ '_ \ / _ \ '__/ _` | |
 | |__| |  __/ | | |  __/ | | (_| | |
  \_____|\___|_| |_|\___|_|  \__,_|_|
]]--

Config.Currency = "$"

-- Admin creator command, restricted to this ace group
Config.AdminCommand = "mechanicadmin"
Config.AdminGroup = "group.admin"

-- Mechanic must be on duty for all job actions (diagnose, repair, tuning, billing...)
Config.RequireDuty = true

-- Last diagnostics report of a vehicle can be reopened without new scan for X minutes (0 = disabled)
Config.DiagnosticsReopen = 10

-- Deposit to workshop account (society account of the FIRST job of the workshop) at the workshop computer.
-- Employees of the workshop can deposit, withdrawals are done in the boss menu.
Config.Deposit = {
    enabled = true,
    max = 1000000,               -- max amount of one deposit
    methods = { "cash", "bank" },
}

-- Inventory images for NUI (%s = item name)
-- ox_inventory: "nui://ox_inventory/web/images/%s.png"
-- qb-inventory: "nui://qb-inventory/html/images/%s.png"
Config.ImagePath = "nui://ox_inventory/web/images/%s.png"

Config.Keys = {
    mechanicMenu = "F6",   -- radial / mechanic menu (only on duty)
    cancel = "X",          -- cancel running workflow / placing
}

-- Default stash of every workshop
Config.Stash = {
    slots = 80,
    weight = 1000000,
}

-- Illegal workshops (DLC pls_mechanic_illegal). They are created in the creator only when the DLC is started,
-- the DLC crew decides who can use them. No jobs, duty, blip or society account, bills are paid in cash.
Config.IllegalResource = "pls_mechanic_illegal"
Config.IllegalShopRadius = 40.0   -- m, a crew member is "in" his illegal workshop within this distance of any of its points

--[[
  ______   _       _
 |  ____| | |     | |
 | |__ ___| |_ ___| |__
 |  __/ _ \ __/ __| '_ \
 | | |  __/ || (__| | | |
 |_|  \___|\__\___|_| |_|
]]--

-- Parts fetching: parts do not have to be carried at the start of a repair / tuning. A step without its parts pauses,
-- the mechanic takes them from the workshop storage and continues via the target on the vehicle.
-- Quick take / stock numbers need an inventory with stash support in BRIDGE (ox_inventory, qb-inventory, qs-inventory
-- only counts), otherwise the mechanic opens the storage and takes the parts himself.
Config.Fetch = {
    enabled = true,          -- false = old behaviour (all parts + tools in the inventory before the start)
    requireStock = true,     -- start refused when a part / tool is neither in the inventory nor in the workshop storage
    timeout = 10,            -- min, waiting for parts is cancelled after this time (0 = no limit)
    maxDistance = 120.0,     -- m, waiting is cancelled when the mechanic gets further from the vehicle
    resumeDistance = 4.0,    -- m, "Continue" target distance
    quickTake = true,        -- storage point action "Take parts for the job" (moves the missing parts of the step)
    carry = "part_box",      -- prop carried after the quick take (Config.Props / Config.Animations.Props key), false = none
    storageBlip = true,      -- route blip to the storage point while waiting
}

-- Blip for new workshops
Config.DefaultBlip = {
    enabled = true,
    sprite = 446,
    color = 5,
    scale = 0.8,
}

-- Default settings of a new workshop (boss can change them in game)
Config.DefaultShopSettings = {
    laborMultiplier = 1.0,   -- multiplier of labor price from configs/parts.lua
    partsMarkup = 20,        -- % added to supplier price of parts on the bill
    tuningMarkup = 0,        -- % added to tuning prices
    commission = 10,         -- % of every paid bill goes to the mechanic
    supplyModes = { instant = true, delayed = true, run = true },
}

--[[
  _____                    _         _
 |  __ \                  (_)       (_)
 | |__) |__ _ __ _ __ ___  _ ___ ___ _  ___  _ __  ___
 |  ___/ _ \ '__| '_ ` _ \| / __/ __| |/ _ \| '_ \/ __|
 | |  |  __/ |  | | | | | | \__ \__ \ | (_) | | | \__ \
 |_|   \___|_|  |_| |_| |_|_|___/___/_|\___/|_| |_|___/
]]--

-- Order = order in the boss settings UI
Config.PermissionList = {
    "duty",
    "diagnose",
    "service",
    "repair_core",
    "repair_body",
    "tuning_performance",
    "tuning_visual",
    "storage",
    "craft",
    "order",
    "supply_run",
    "billing",
    "tow",
    "impound",
    "missions",
    "manage_shop",
    "bossmenu",
}

-- Default permissions for new workshop by job grade.
-- Grade without entry uses the closest lower grade. Highest grade of the job always gets everything.
Config.DefaultPermissions = {
    [0] = { duty = true, diagnose = true, service = true, storage = true, missions = true, tow = true },
    [1] = { duty = true, diagnose = true, service = true, repair_body = true, storage = true, missions = true, tow = true, billing = true, craft = true },
    [2] = { duty = true, diagnose = true, service = true, repair_core = true, repair_body = true, tuning_visual = true, storage = true, craft = true, supply_run = true, billing = true, tow = true, impound = true, missions = true },
    [3] = { duty = true, diagnose = true, service = true, repair_core = true, repair_body = true, tuning_performance = true, tuning_visual = true, storage = true, craft = true, order = true, supply_run = true, billing = true, tow = true, impound = true, missions = true },
}

--[[
  _____      _       _
 |  __ \    (_)     | |
 | |__) |__  _ _ __ | |_ ___
 |  ___/ _ \| | '_ \| __/ __|
 | |  | (_) | | | | | |_\__ \
 |_|   \___/|_|_| |_|\__|___/
]]--

-- Point types of a workshop. Admin places them in the creator.
-- fields = extra settings editable in the creator (type: number / checkbox / select / text / multi-select)
-- kinds = workshop kinds where the point can be placed (missing = { legal = true }), the illegal DLC adds its own types
Config.PointTypes = {
    duty      = { label = "Duty",             icon = "fa-solid fa-clipboard-user", radius = 1.5, multiple = false, kinds = { legal = true } },
    boss      = { label = "Boss menu",        icon = "fa-solid fa-briefcase",      radius = 1.5, multiple = false, kinds = { legal = true } },
    storage   = { label = "Storage",          icon = "fa-solid fa-box-open",       radius = 1.5, multiple = false, kinds = { legal = true, illegal = true } },
    supply    = { label = "Supply delivery",  icon = "fa-solid fa-truck-ramp-box", radius = 2.5, multiple = false, kinds = { legal = true } },
    computer  = { label = "Computer",         icon = "fa-solid fa-computer",       radius = 1.5, multiple = true,  kinds = { legal = true } },
    workbench = { label = "Workbench",        icon = "fa-solid fa-screwdriver-wrench", radius = 1.5, multiple = true, kinds = { legal = true, illegal = true } },
    billing   = { label = "Payment terminal", icon = "fa-solid fa-cash-register",  radius = 1.5, multiple = true,  kinds = { legal = true, illegal = true } },
    garage    = { label = "Service vehicles", icon = "fa-solid fa-truck-pickup",   radius = 2.0, multiple = false, kinds = { legal = true } },
    bay       = { label = "Bay",              icon = "fa-solid fa-car",            radius = 4.0, multiple = true,  kinds = { legal = true, illegal = true },
        fields = {
            { key = "bayType", type = "select", label = "Bay type", default = "both", options = { { value = "repair", label = "Repair" }, { value = "tuning", label = "Tuning" }, { value = "both", label = "Repair + tuning" } } },
        },
    },
    lift      = { label = "Car lift",         icon = "fa-solid fa-arrows-up-to-line", radius = 4.0, multiple = true, kinds = { legal = true, illegal = true },
        fields = {
            { key = "height", type = "number", label = "Lift height (m)", default = 1.8, min = 0.5, max = 2.5 },
        },
    },
    station   = { label = "Repair station",   icon = "fa-solid fa-gas-pump",       radius = 4.0, multiple = true,  kinds = { legal = true },
        fields = {
            { key = "price", type = "number", label = "Price", default = 500, min = 0 },
            { key = "duration", type = "number", label = "Duration (s)", default = 20, min = 1 },
            { key = "repairs", type = "multi-select", label = "Repairs", default = { "engine", "body" }, options = { { value = "engine", label = "Engine" }, { value = "body", label = "Body" }, { value = "service", label = "Service parts" }, { value = "core", label = "Core parts" } } },
            { key = "onlyWithoutMechanic", type = "checkbox", label = "Only when no mechanic on duty", default = true },
            { key = "jobs", type = "text", label = "Allowed jobs (comma separated, empty = everyone)", default = "" },
        },
    },
}

-- Service vehicles spawned at "garage" point
Config.ServiceVehicles = {
    { model = "flatbed", label = "Flatbed" },
    { model = "towtruck", label = "Tow truck" },
    { model = "burrito3", label = "Supply van" },
}

--[[
  _____ _
 |_   _| |
   | | | |_ ___ _ __ ___  ___
   | | | __/ _ \ '_ ` _ \/ __|
  _| |_| ||  __/ | | | | \__ \
 |_____|\__\___|_| |_| |_|___/
]]--

-- Key = name used in script configs, value = item name in your inventory.
-- Rename items here only.
Config.Items = {
    -- service parts
    engine_oil = "mech_engine_oil",
    oil_filter = "mech_oil_filter",
    air_filter = "mech_air_filter",
    fuel_filter = "mech_fuel_filter",
    spark_plugs = "mech_spark_plugs",
    coolant = "mech_coolant",
    brake_fluid = "mech_brake_fluid",
    transmission_fluid = "mech_transmission_fluid",
    brake_pads = "mech_brake_pads",
    tyre = "mech_tyre",
    timing_belt = "mech_timing_belt",
    -- core parts
    engine_parts = "mech_engine_parts",
    transmission_parts = "mech_transmission_parts",
    clutch_kit = "mech_clutch_kit",
    radiator = "mech_radiator",
    alternator = "mech_alternator",
    car_battery = "mech_car_battery",
    fuel_pump = "mech_fuel_pump",
    brake_discs = "mech_brake_discs",
    shock_absorber = "mech_shock_absorber",
    turbocharger = "mech_turbocharger",
    -- electric vehicles
    ev_battery_module = "mech_ev_battery_module",
    ev_motor = "mech_ev_motor",
    ev_coolant = "mech_ev_coolant",
    -- body
    car_door = "mech_car_door",
    car_hood = "mech_car_hood",
    car_trunk = "mech_car_trunk",
    car_bumper = "mech_car_bumper",
    car_glass = "mech_car_glass",
    car_headlight = "mech_car_headlight",
    car_wheel = "mech_car_wheel",
    body_panel = "mech_body_panel",
    -- tools
    obd_scanner = "mech_obd_scanner",
    toolbox = "mech_toolbox",
    impact_wrench = "mech_impact_wrench",
    car_jack = "mech_car_jack",
    jump_starter = "mech_jump_starter",
    slim_jim = "mech_slim_jim",
    tuning_laptop = "mech_tuning_laptop",
    spray_gun = "mech_spray_gun",
    service_book = "mech_service_book",
    -- repair kits
    repair_kit = "mech_repair_kit",
    advanced_repair_kit = "mech_advanced_repair_kit",
    patch_kit = "mech_patch_kit",
    cleaning_kit = "mech_cleaning_kit",
    -- materials
    scrap_metal = "mech_scrap_metal",
    aluminium = "mech_aluminium",
    rubber = "mech_rubber",
    plastic = "mech_plastic",
    electronics = "mech_electronics",
    used_oil = "mech_used_oil",
    -- props
    traffic_cone = "mech_traffic_cone",
    road_barrier = "mech_road_barrier",
    work_sign = "mech_work_sign",
    -- performance tuning
    engine_stage1 = "mech_engine_stage1",
    engine_stage2 = "mech_engine_stage2",
    engine_stage3 = "mech_engine_stage3",
    engine_stage4 = "mech_engine_stage4",
    brakes_stage1 = "mech_brakes_stage1",
    brakes_stage2 = "mech_brakes_stage2",
    brakes_stage3 = "mech_brakes_stage3",
    transmission_stage1 = "mech_transmission_stage1",
    transmission_stage2 = "mech_transmission_stage2",
    transmission_stage3 = "mech_transmission_stage3",
    suspension_stage1 = "mech_suspension_stage1",
    suspension_stage2 = "mech_suspension_stage2",
    suspension_stage3 = "mech_suspension_stage3",
    suspension_stage4 = "mech_suspension_stage4",
    armor_stage1 = "mech_armor_stage1",
    armor_stage2 = "mech_armor_stage2",
    armor_stage3 = "mech_armor_stage3",
    armor_stage4 = "mech_armor_stage4",
    armor_stage5 = "mech_armor_stage5",
    turbo_kit = "mech_turbo_kit",
    -- visual tuning
    paint_can = "mech_paint_can",
    bodykit_parts = "mech_bodykit_parts",
    rims = "mech_rims",
    tyre_smoke_kit = "mech_tyre_smoke_kit",
    xenon_kit = "mech_xenon_kit",
    neon_kit = "mech_neon_kit",
    window_tint = "mech_window_tint",
    vinyl = "mech_vinyl",
    interior_parts = "mech_interior_parts",
    horn = "mech_horn",
    plate_kit = "mech_plate_kit",
    -- supply
    supply_crate = "mech_supply_crate",
}

-- Items usable directly from inventory (keys of Config.Items)
Config.UsableItems = {
    "tyre", "car_battery", "car_wheel",
    "obd_scanner", "toolbox", "car_jack", "jump_starter", "slim_jim", "service_book",
    "repair_kit", "advanced_repair_kit", "patch_kit", "cleaning_kit",
    "traffic_cone", "road_barrier", "work_sign",
}

--[[
  _____
 |  __ \
 | |__) | __ ___  _ __  ___
 |  ___/ '__/ _ \| '_ \/ __|
 | |   | | | (_) | |_) \__ \
 |_|   |_|  \___/| .__/|___/
                 | |
                 |_|
]]--

-- Hand props used in animations. Replace models with your own props anytime.
-- bone = ped bone id, pos/rot = attach offset
Config.Props = {
    scanner      = { model = "prop_cs_tablet",      bone = 60309, pos = vec3(0.03, 0.002, -0.0), rot = vec3(10.0, 160.0, 0.0) },
    toolbox      = { model = "prop_tool_box_04",    bone = 57005, pos = vec3(0.42, 0.0, -0.02), rot = vec3(-90.0, 0.0, 90.0) },
    wrench       = { model = "prop_tool_wrench",    bone = 57005, pos = vec3(0.14, 0.02, -0.03), rot = vec3(-100.0, 0.0, 0.0) },
    impact_wrench= { model = "prop_tool_drill",     bone = 57005, pos = vec3(0.14, 0.02, -0.03), rot = vec3(-100.0, 0.0, 0.0) },
    battery      = { model = "prop_car_battery_01", bone = 28422, pos = vec3(0.0, -0.1, -0.2), rot = vec3(0.0, 0.0, 0.0) },
    tyre         = { model = "prop_wheel_tyre",     bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
    oil          = { model = "prop_oilcan_01a",     bone = 57005, pos = vec3(0.12, 0.0, -0.05), rot = vec3(-90.0, 0.0, 0.0) },
    spray_gun    = { model = "prop_paint_spray01a", bone = 57005, pos = vec3(0.12, 0.02, -0.03), rot = vec3(-90.0, 0.0, 0.0) },
    laptop       = { model = "prop_laptop_01a",     bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
    crate        = { model = "prop_cs_cardbox_01",  bone = 28422, pos = vec3(0.0, -0.05, -0.1), rot = vec3(0.0, 0.0, 0.0) },
    engine_part  = nil, -- custom prop coming soon (engine block)
    car_jack     = { model = "prop_carjack" },
    lift         = nil, -- custom car lift prop coming soon, without prop only the vehicle is lifted
}
