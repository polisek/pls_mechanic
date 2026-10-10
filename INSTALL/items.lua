--[[
The local items variable is only because I don't like red lines in my visual studio code. Thanks for understanding.
Only copy things inside the table.

ox_inventory  -> copy "items" into ox_inventory/data/items.lua
qb-inventory  -> copy "qbcore" into qb-core/shared/items.lua
Images        -> INSTALL/images/<item_name>.png

Usable items have consume = 0, the script removes them itself.
]]--
local items = {

    -- SERVICE PARTS
    ['mech_engine_oil'] = { label = 'Engine Oil', weight = 4500, stack = true, close = true, description = '5L of fully synthetic engine oil.' },
    ['mech_oil_filter'] = { label = 'Oil Filter', weight = 400, stack = true, close = true, description = 'Replace together with engine oil.' },
    ['mech_air_filter'] = { label = 'Air Filter', weight = 500, stack = true, close = true, description = 'Clean air for full engine power.' },
    ['mech_fuel_filter'] = { label = 'Fuel Filter', weight = 400, stack = true, close = true, description = 'Protects the fuel pump from dirt.' },
    ['mech_spark_plugs'] = { label = 'Spark Plugs', weight = 300, stack = true, close = true, description = 'Set of spark plugs.' },
    ['mech_coolant'] = { label = 'Coolant', weight = 2000, stack = true, close = true, description = 'Keeps the engine at working temperature.' },
    ['mech_brake_fluid'] = { label = 'Brake Fluid', weight = 1000, stack = true, close = true, description = 'DOT 4 brake fluid.' },
    ['mech_transmission_fluid'] = { label = 'Transmission Fluid', weight = 2000, stack = true, close = true, description = 'Gearbox and clutch lubrication.' },
    ['mech_brake_pads'] = { label = 'Brake Pads', weight = 1500, stack = true, close = true, description = 'Brake pads for one axle.' },
    ['mech_tyre'] = { label = 'Tyre', weight = 9000, stack = true, close = true, consume = 0, description = 'All-season tyre.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_timing_belt'] = { label = 'Timing Belt', weight = 800, stack = true, close = true, description = 'If it snaps, the engine is gone.' },

    -- CORE PARTS
    ['mech_engine_parts'] = { label = 'Engine Rebuild Kit', weight = 25000, stack = true, close = true, description = 'Pistons, rings, gaskets and bearings for an engine rebuild.' },
    ['mech_transmission_parts'] = { label = 'Transmission Rebuild Kit', weight = 18000, stack = true, close = true, description = 'Gears, synchros and seals for a gearbox rebuild.' },
    ['mech_clutch_kit'] = { label = 'Clutch Kit', weight = 7000, stack = true, close = true, description = 'Clutch disc, pressure plate and release bearing.' },
    ['mech_radiator'] = { label = 'Radiator', weight = 6000, stack = true, close = true, description = 'Engine cooling radiator.' },
    ['mech_alternator'] = { label = 'Alternator', weight = 5000, stack = true, close = true, description = 'Charges the battery while driving.' },
    ['mech_car_battery'] = { label = 'Car Battery', weight = 15000, stack = true, close = true, consume = 0, description = '12V 70Ah car battery.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_fuel_pump'] = { label = 'Fuel Pump', weight = 2000, stack = true, close = true, description = 'Electric fuel pump.' },
    ['mech_brake_discs'] = { label = 'Brake Discs', weight = 10000, stack = true, close = true, description = 'Brake discs for one axle.' },
    ['mech_shock_absorber'] = { label = 'Shock Absorber', weight = 3000, stack = true, close = true, description = 'Gas-filled shock absorber.' },
    ['mech_turbocharger'] = { label = 'Turbocharger', weight = 8000, stack = true, close = true, description = 'Replacement turbocharger.' },

    -- ELECTRIC VEHICLES
    ['mech_ev_battery_module'] = { label = 'EV Battery Module', weight = 20000, stack = true, close = true, description = 'Traction battery module for electric vehicles.' },
    ['mech_ev_motor'] = { label = 'Electric Motor', weight = 30000, stack = true, close = true, description = 'Drive motor for electric vehicles.' },
    ['mech_ev_coolant'] = { label = 'EV Battery Coolant', weight = 2000, stack = true, close = true, description = 'Coolant for the traction battery.' },

    -- BODY
    ['mech_car_door'] = { label = 'Car Door', weight = 15000, stack = true, close = true, description = 'Universal car door.' },
    ['mech_car_hood'] = { label = 'Car Hood', weight = 12000, stack = true, close = true, description = 'Universal hood.' },
    ['mech_car_trunk'] = { label = 'Trunk Lid', weight = 10000, stack = true, close = true, description = 'Universal trunk lid.' },
    ['mech_car_bumper'] = { label = 'Bumper', weight = 6000, stack = true, close = true, description = 'Front or rear bumper.' },
    ['mech_car_glass'] = { label = 'Car Glass', weight = 8000, stack = true, close = true, description = 'Windshield or side window.' },
    ['mech_car_headlight'] = { label = 'Headlight', weight = 2000, stack = true, close = true, description = 'Headlight assembly.' },
    ['mech_car_wheel'] = { label = 'Wheel', weight = 15000, stack = true, close = true, consume = 0, description = 'Complete wheel with rim and tyre.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_body_panel'] = { label = 'Body Panel', weight = 10000, stack = true, close = true, description = 'Sheet metal for bodywork repairs.' },

    -- TOOLS
    ['mech_obd_scanner'] = { label = 'OBD Scanner', weight = 800, stack = false, close = true, consume = 0, description = 'Reads fault codes and part condition.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_toolbox'] = { label = 'Toolbox', weight = 6000, stack = false, close = true, consume = 0, description = 'Basic mechanic tools. Can be placed on the ground.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_impact_wrench'] = { label = 'Impact Wrench', weight = 3000, stack = false, close = true, description = 'Needed for wheel and suspension work.' },
    ['mech_car_jack'] = { label = 'Car Jack', weight = 8000, stack = false, close = true, consume = 0, description = 'Lifts one corner of the vehicle.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_jump_starter'] = { label = 'Jump Starter', weight = 4000, stack = false, close = true, consume = 0, description = 'Starts a vehicle with a dead battery.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_slim_jim'] = { label = 'Slim Jim', weight = 200, stack = false, close = true, consume = 0, description = 'Opens locked vehicles.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_tuning_laptop'] = { label = 'Tuning Laptop', weight = 2500, stack = false, close = true, description = 'Calibrates engine, transmission and turbo upgrades.' },
    ['mech_spray_gun'] = { label = 'Spray Gun', weight = 1500, stack = false, close = true, description = 'Needed for painting.' },
    ['mech_service_book'] = { label = 'Service Book', weight = 200, stack = false, close = true, consume = 0, description = 'Service history of the vehicle.', client = { export = 'pls_mechanic.useItem' } },

    -- REPAIR KITS
    ['mech_repair_kit'] = { label = 'Repair Kit', weight = 3000, stack = true, close = true, consume = 0, description = 'Quick fix that gets the engine running again.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_advanced_repair_kit'] = { label = 'Advanced Repair Kit', weight = 5000, stack = true, close = true, consume = 0, description = 'Full engine and body repair. Mechanics only.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_patch_kit'] = { label = 'Emergency Patch Kit', weight = 1500, stack = true, close = true, consume = 0, description = 'Temporary fix of a failed part, enough to reach a workshop.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_cleaning_kit'] = { label = 'Cleaning Kit', weight = 1000, stack = true, close = true, consume = 0, description = 'Washes dirt off the vehicle.', client = { export = 'pls_mechanic.useItem' } },

    -- MATERIALS
    ['mech_scrap_metal'] = { label = 'Scrap Metal', weight = 1000, stack = true, close = true, description = 'Salvaged from old parts.' },
    ['mech_aluminium'] = { label = 'Aluminium', weight = 500, stack = true, close = true, description = 'Salvaged from old parts.' },
    ['mech_rubber'] = { label = 'Rubber', weight = 500, stack = true, close = true, description = 'Salvaged from old tyres and seals.' },
    ['mech_plastic'] = { label = 'Plastic', weight = 300, stack = true, close = true, description = 'Salvaged from old parts.' },
    ['mech_electronics'] = { label = 'Electronics', weight = 200, stack = true, close = true, description = 'Salvaged from electrical parts.' },
    ['mech_used_oil'] = { label = 'Used Oil', weight = 4500, stack = true, close = true, description = 'Must be disposed of properly.' },

    -- PROPS
    ['mech_traffic_cone'] = { label = 'Traffic Cone', weight = 1500, stack = true, close = true, consume = 0, description = 'Place it on the road.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_road_barrier'] = { label = 'Road Barrier', weight = 8000, stack = true, close = true, consume = 0, description = 'Place it on the road.', client = { export = 'pls_mechanic.useItem' } },
    ['mech_work_sign'] = { label = 'Work Sign', weight = 3000, stack = true, close = true, consume = 0, description = 'Place it on the road.', client = { export = 'pls_mechanic.useItem' } },

    -- PERFORMANCE TUNING
    ['mech_engine_stage1'] = { label = 'Engine Upgrade Stage 1', weight = 8000, stack = true, close = true, description = 'EMS upgrade, level 1.' },
    ['mech_engine_stage2'] = { label = 'Engine Upgrade Stage 2', weight = 9000, stack = true, close = true, description = 'EMS upgrade, level 2.' },
    ['mech_engine_stage3'] = { label = 'Engine Upgrade Stage 3', weight = 10000, stack = true, close = true, description = 'EMS upgrade, level 3.' },
    ['mech_engine_stage4'] = { label = 'Engine Upgrade Stage 4', weight = 12000, stack = true, close = true, description = 'EMS upgrade, level 4.' },
    ['mech_brakes_stage1'] = { label = 'Street Brakes', weight = 8000, stack = true, close = true, description = 'Brake upgrade, level 1.' },
    ['mech_brakes_stage2'] = { label = 'Sport Brakes', weight = 9000, stack = true, close = true, description = 'Brake upgrade, level 2.' },
    ['mech_brakes_stage3'] = { label = 'Race Brakes', weight = 10000, stack = true, close = true, description = 'Brake upgrade, level 3.' },
    ['mech_transmission_stage1'] = { label = 'Street Transmission', weight = 15000, stack = true, close = true, description = 'Transmission upgrade, level 1.' },
    ['mech_transmission_stage2'] = { label = 'Sport Transmission', weight = 16000, stack = true, close = true, description = 'Transmission upgrade, level 2.' },
    ['mech_transmission_stage3'] = { label = 'Race Transmission', weight = 17000, stack = true, close = true, description = 'Transmission upgrade, level 3.' },
    ['mech_suspension_stage1'] = { label = 'Lowered Suspension', weight = 10000, stack = true, close = true, description = 'Suspension upgrade, level 1.' },
    ['mech_suspension_stage2'] = { label = 'Street Suspension', weight = 11000, stack = true, close = true, description = 'Suspension upgrade, level 2.' },
    ['mech_suspension_stage3'] = { label = 'Sport Suspension', weight = 12000, stack = true, close = true, description = 'Suspension upgrade, level 3.' },
    ['mech_suspension_stage4'] = { label = 'Competition Suspension', weight = 13000, stack = true, close = true, description = 'Suspension upgrade, level 4.' },
    ['mech_armor_stage1'] = { label = 'Armor Upgrade 20%', weight = 15000, stack = true, close = true, description = 'Armor upgrade, level 1.' },
    ['mech_armor_stage2'] = { label = 'Armor Upgrade 40%', weight = 20000, stack = true, close = true, description = 'Armor upgrade, level 2.' },
    ['mech_armor_stage3'] = { label = 'Armor Upgrade 60%', weight = 25000, stack = true, close = true, description = 'Armor upgrade, level 3.' },
    ['mech_armor_stage4'] = { label = 'Armor Upgrade 80%', weight = 30000, stack = true, close = true, description = 'Armor upgrade, level 4.' },
    ['mech_armor_stage5'] = { label = 'Armor Upgrade 100%', weight = 35000, stack = true, close = true, description = 'Armor upgrade, level 5.' },
    ['mech_turbo_kit'] = { label = 'Turbo Kit', weight = 12000, stack = true, close = true, description = 'Turbo tuning kit.' },

    -- VISUAL TUNING
    ['mech_paint_can'] = { label = 'Car Paint', weight = 2000, stack = true, close = true, description = 'Paint for one layer. Needs a spray gun.' },
    ['mech_bodykit_parts'] = { label = 'Body Kit Parts', weight = 10000, stack = true, close = true, description = 'Spoilers, bumpers, skirts, hoods and more.' },
    ['mech_rims'] = { label = 'Rims', weight = 20000, stack = true, close = true, description = 'Set of custom rims.' },
    ['mech_tyre_smoke_kit'] = { label = 'Tyre Smoke Kit', weight = 1000, stack = true, close = true, description = 'Colored tyre smoke.' },
    ['mech_xenon_kit'] = { label = 'Xenon Kit', weight = 1500, stack = true, close = true, description = 'Xenon headlights.' },
    ['mech_neon_kit'] = { label = 'Neon Kit', weight = 2000, stack = true, close = true, description = 'Underglow neon lights.' },
    ['mech_window_tint'] = { label = 'Window Tint', weight = 500, stack = true, close = true, description = 'Tint film for all windows.' },
    ['mech_vinyl'] = { label = 'Vinyl Wrap', weight = 1000, stack = true, close = true, description = 'Livery wrap.' },
    ['mech_interior_parts'] = { label = 'Interior Parts', weight = 5000, stack = true, close = true, description = 'Seats, steering wheels, dashboards and more.' },
    ['mech_horn'] = { label = 'Horn', weight = 500, stack = true, close = true, description = 'Custom horn.' },
    ['mech_plate_kit'] = { label = 'Plate Kit', weight = 500, stack = true, close = true, description = 'Custom plate style.' },

    -- SUPPLY
    ['mech_supply_crate'] = { label = 'Parts Delivery', weight = 20000, stack = false, close = true, description = 'Deliver it to the workshop supply point.' },
}

local qbcore = {
    -- SERVICE PARTS
    mech_engine_oil = { name = 'mech_engine_oil', label = 'Engine Oil', weight = 4500, type = 'item', image = 'mech_engine_oil.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = '5L of fully synthetic engine oil.' },
    mech_oil_filter = { name = 'mech_oil_filter', label = 'Oil Filter', weight = 400, type = 'item', image = 'mech_oil_filter.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Replace together with engine oil.' },
    mech_air_filter = { name = 'mech_air_filter', label = 'Air Filter', weight = 500, type = 'item', image = 'mech_air_filter.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Clean air for full engine power.' },
    mech_fuel_filter = { name = 'mech_fuel_filter', label = 'Fuel Filter', weight = 400, type = 'item', image = 'mech_fuel_filter.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Protects the fuel pump from dirt.' },
    mech_spark_plugs = { name = 'mech_spark_plugs', label = 'Spark Plugs', weight = 300, type = 'item', image = 'mech_spark_plugs.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Set of spark plugs.' },
    mech_coolant = { name = 'mech_coolant', label = 'Coolant', weight = 2000, type = 'item', image = 'mech_coolant.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Keeps the engine at working temperature.' },
    mech_brake_fluid = { name = 'mech_brake_fluid', label = 'Brake Fluid', weight = 1000, type = 'item', image = 'mech_brake_fluid.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'DOT 4 brake fluid.' },
    mech_transmission_fluid = { name = 'mech_transmission_fluid', label = 'Transmission Fluid', weight = 2000, type = 'item', image = 'mech_transmission_fluid.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Gearbox and clutch lubrication.' },
    mech_brake_pads = { name = 'mech_brake_pads', label = 'Brake Pads', weight = 1500, type = 'item', image = 'mech_brake_pads.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Brake pads for one axle.' },
    mech_tyre = { name = 'mech_tyre', label = 'Tyre', weight = 9000, type = 'item', image = 'mech_tyre.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'All-season tyre.' },
    mech_timing_belt = { name = 'mech_timing_belt', label = 'Timing Belt', weight = 800, type = 'item', image = 'mech_timing_belt.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'If it snaps, the engine is gone.' },

    -- CORE PARTS
    mech_engine_parts = { name = 'mech_engine_parts', label = 'Engine Rebuild Kit', weight = 25000, type = 'item', image = 'mech_engine_parts.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Pistons, rings, gaskets and bearings for an engine rebuild.' },
    mech_transmission_parts = { name = 'mech_transmission_parts', label = 'Transmission Rebuild Kit', weight = 18000, type = 'item', image = 'mech_transmission_parts.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Gears, synchros and seals for a gearbox rebuild.' },
    mech_clutch_kit = { name = 'mech_clutch_kit', label = 'Clutch Kit', weight = 7000, type = 'item', image = 'mech_clutch_kit.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Clutch disc, pressure plate and release bearing.' },
    mech_radiator = { name = 'mech_radiator', label = 'Radiator', weight = 6000, type = 'item', image = 'mech_radiator.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Engine cooling radiator.' },
    mech_alternator = { name = 'mech_alternator', label = 'Alternator', weight = 5000, type = 'item', image = 'mech_alternator.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Charges the battery while driving.' },
    mech_car_battery = { name = 'mech_car_battery', label = 'Car Battery', weight = 15000, type = 'item', image = 'mech_car_battery.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = '12V 70Ah car battery.' },
    mech_fuel_pump = { name = 'mech_fuel_pump', label = 'Fuel Pump', weight = 2000, type = 'item', image = 'mech_fuel_pump.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Electric fuel pump.' },
    mech_brake_discs = { name = 'mech_brake_discs', label = 'Brake Discs', weight = 10000, type = 'item', image = 'mech_brake_discs.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Brake discs for one axle.' },
    mech_shock_absorber = { name = 'mech_shock_absorber', label = 'Shock Absorber', weight = 3000, type = 'item', image = 'mech_shock_absorber.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Gas-filled shock absorber.' },
    mech_turbocharger = { name = 'mech_turbocharger', label = 'Turbocharger', weight = 8000, type = 'item', image = 'mech_turbocharger.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Replacement turbocharger.' },

    -- ELECTRIC VEHICLES
    mech_ev_battery_module = { name = 'mech_ev_battery_module', label = 'EV Battery Module', weight = 20000, type = 'item', image = 'mech_ev_battery_module.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Traction battery module for electric vehicles.' },
    mech_ev_motor = { name = 'mech_ev_motor', label = 'Electric Motor', weight = 30000, type = 'item', image = 'mech_ev_motor.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Drive motor for electric vehicles.' },
    mech_ev_coolant = { name = 'mech_ev_coolant', label = 'EV Battery Coolant', weight = 2000, type = 'item', image = 'mech_ev_coolant.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Coolant for the traction battery.' },

    -- BODY
    mech_car_door = { name = 'mech_car_door', label = 'Car Door', weight = 15000, type = 'item', image = 'mech_car_door.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Universal car door.' },
    mech_car_hood = { name = 'mech_car_hood', label = 'Car Hood', weight = 12000, type = 'item', image = 'mech_car_hood.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Universal hood.' },
    mech_car_trunk = { name = 'mech_car_trunk', label = 'Trunk Lid', weight = 10000, type = 'item', image = 'mech_car_trunk.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Universal trunk lid.' },
    mech_car_bumper = { name = 'mech_car_bumper', label = 'Bumper', weight = 6000, type = 'item', image = 'mech_car_bumper.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Front or rear bumper.' },
    mech_car_glass = { name = 'mech_car_glass', label = 'Car Glass', weight = 8000, type = 'item', image = 'mech_car_glass.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Windshield or side window.' },
    mech_car_headlight = { name = 'mech_car_headlight', label = 'Headlight', weight = 2000, type = 'item', image = 'mech_car_headlight.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Headlight assembly.' },
    mech_car_wheel = { name = 'mech_car_wheel', label = 'Wheel', weight = 15000, type = 'item', image = 'mech_car_wheel.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Complete wheel with rim and tyre.' },
    mech_body_panel = { name = 'mech_body_panel', label = 'Body Panel', weight = 10000, type = 'item', image = 'mech_body_panel.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Sheet metal for bodywork repairs.' },

    -- TOOLS
    mech_obd_scanner = { name = 'mech_obd_scanner', label = 'OBD Scanner', weight = 800, type = 'item', image = 'mech_obd_scanner.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Reads fault codes and part condition.' },
    mech_toolbox = { name = 'mech_toolbox', label = 'Toolbox', weight = 6000, type = 'item', image = 'mech_toolbox.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Basic mechanic tools. Can be placed on the ground.' },
    mech_impact_wrench = { name = 'mech_impact_wrench', label = 'Impact Wrench', weight = 3000, type = 'item', image = 'mech_impact_wrench.png', unique = true, useable = false, shouldClose = true, combinable = nil, description = 'Needed for wheel and suspension work.' },
    mech_car_jack = { name = 'mech_car_jack', label = 'Car Jack', weight = 8000, type = 'item', image = 'mech_car_jack.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Lifts one corner of the vehicle.' },
    mech_jump_starter = { name = 'mech_jump_starter', label = 'Jump Starter', weight = 4000, type = 'item', image = 'mech_jump_starter.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Starts a vehicle with a dead battery.' },
    mech_slim_jim = { name = 'mech_slim_jim', label = 'Slim Jim', weight = 200, type = 'item', image = 'mech_slim_jim.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Opens locked vehicles.' },
    mech_tuning_laptop = { name = 'mech_tuning_laptop', label = 'Tuning Laptop', weight = 2500, type = 'item', image = 'mech_tuning_laptop.png', unique = true, useable = false, shouldClose = true, combinable = nil, description = 'Calibrates engine, transmission and turbo upgrades.' },
    mech_spray_gun = { name = 'mech_spray_gun', label = 'Spray Gun', weight = 1500, type = 'item', image = 'mech_spray_gun.png', unique = true, useable = false, shouldClose = true, combinable = nil, description = 'Needed for painting.' },
    mech_service_book = { name = 'mech_service_book', label = 'Service Book', weight = 200, type = 'item', image = 'mech_service_book.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Service history of the vehicle.' },

    -- REPAIR KITS
    mech_repair_kit = { name = 'mech_repair_kit', label = 'Repair Kit', weight = 3000, type = 'item', image = 'mech_repair_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Quick fix that gets the engine running again.' },
    mech_advanced_repair_kit = { name = 'mech_advanced_repair_kit', label = 'Advanced Repair Kit', weight = 5000, type = 'item', image = 'mech_advanced_repair_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Full engine and body repair. Mechanics only.' },
    mech_patch_kit = { name = 'mech_patch_kit', label = 'Emergency Patch Kit', weight = 1500, type = 'item', image = 'mech_patch_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Temporary fix of a failed part, enough to reach a workshop.' },
    mech_cleaning_kit = { name = 'mech_cleaning_kit', label = 'Cleaning Kit', weight = 1000, type = 'item', image = 'mech_cleaning_kit.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Washes dirt off the vehicle.' },

    -- MATERIALS
    mech_scrap_metal = { name = 'mech_scrap_metal', label = 'Scrap Metal', weight = 1000, type = 'item', image = 'mech_scrap_metal.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Salvaged from old parts.' },
    mech_aluminium = { name = 'mech_aluminium', label = 'Aluminium', weight = 500, type = 'item', image = 'mech_aluminium.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Salvaged from old parts.' },
    mech_rubber = { name = 'mech_rubber', label = 'Rubber', weight = 500, type = 'item', image = 'mech_rubber.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Salvaged from old tyres and seals.' },
    mech_plastic = { name = 'mech_plastic', label = 'Plastic', weight = 300, type = 'item', image = 'mech_plastic.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Salvaged from old parts.' },
    mech_electronics = { name = 'mech_electronics', label = 'Electronics', weight = 200, type = 'item', image = 'mech_electronics.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Salvaged from electrical parts.' },
    mech_used_oil = { name = 'mech_used_oil', label = 'Used Oil', weight = 4500, type = 'item', image = 'mech_used_oil.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Must be disposed of properly.' },

    -- PROPS
    mech_traffic_cone = { name = 'mech_traffic_cone', label = 'Traffic Cone', weight = 1500, type = 'item', image = 'mech_traffic_cone.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Place it on the road.' },
    mech_road_barrier = { name = 'mech_road_barrier', label = 'Road Barrier', weight = 8000, type = 'item', image = 'mech_road_barrier.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Place it on the road.' },
    mech_work_sign = { name = 'mech_work_sign', label = 'Work Sign', weight = 3000, type = 'item', image = 'mech_work_sign.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Place it on the road.' },

    -- PERFORMANCE TUNING
    mech_engine_stage1 = { name = 'mech_engine_stage1', label = 'Engine Upgrade Stage 1', weight = 8000, type = 'item', image = 'mech_engine_stage1.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'EMS upgrade, level 1.' },
    mech_engine_stage2 = { name = 'mech_engine_stage2', label = 'Engine Upgrade Stage 2', weight = 9000, type = 'item', image = 'mech_engine_stage2.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'EMS upgrade, level 2.' },
    mech_engine_stage3 = { name = 'mech_engine_stage3', label = 'Engine Upgrade Stage 3', weight = 10000, type = 'item', image = 'mech_engine_stage3.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'EMS upgrade, level 3.' },
    mech_engine_stage4 = { name = 'mech_engine_stage4', label = 'Engine Upgrade Stage 4', weight = 12000, type = 'item', image = 'mech_engine_stage4.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'EMS upgrade, level 4.' },
    mech_brakes_stage1 = { name = 'mech_brakes_stage1', label = 'Street Brakes', weight = 8000, type = 'item', image = 'mech_brakes_stage1.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Brake upgrade, level 1.' },
    mech_brakes_stage2 = { name = 'mech_brakes_stage2', label = 'Sport Brakes', weight = 9000, type = 'item', image = 'mech_brakes_stage2.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Brake upgrade, level 2.' },
    mech_brakes_stage3 = { name = 'mech_brakes_stage3', label = 'Race Brakes', weight = 10000, type = 'item', image = 'mech_brakes_stage3.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Brake upgrade, level 3.' },
    mech_transmission_stage1 = { name = 'mech_transmission_stage1', label = 'Street Transmission', weight = 15000, type = 'item', image = 'mech_transmission_stage1.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Transmission upgrade, level 1.' },
    mech_transmission_stage2 = { name = 'mech_transmission_stage2', label = 'Sport Transmission', weight = 16000, type = 'item', image = 'mech_transmission_stage2.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Transmission upgrade, level 2.' },
    mech_transmission_stage3 = { name = 'mech_transmission_stage3', label = 'Race Transmission', weight = 17000, type = 'item', image = 'mech_transmission_stage3.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Transmission upgrade, level 3.' },
    mech_suspension_stage1 = { name = 'mech_suspension_stage1', label = 'Lowered Suspension', weight = 10000, type = 'item', image = 'mech_suspension_stage1.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Suspension upgrade, level 1.' },
    mech_suspension_stage2 = { name = 'mech_suspension_stage2', label = 'Street Suspension', weight = 11000, type = 'item', image = 'mech_suspension_stage2.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Suspension upgrade, level 2.' },
    mech_suspension_stage3 = { name = 'mech_suspension_stage3', label = 'Sport Suspension', weight = 12000, type = 'item', image = 'mech_suspension_stage3.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Suspension upgrade, level 3.' },
    mech_suspension_stage4 = { name = 'mech_suspension_stage4', label = 'Competition Suspension', weight = 13000, type = 'item', image = 'mech_suspension_stage4.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Suspension upgrade, level 4.' },
    mech_armor_stage1 = { name = 'mech_armor_stage1', label = 'Armor Upgrade 20%', weight = 15000, type = 'item', image = 'mech_armor_stage1.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Armor upgrade, level 1.' },
    mech_armor_stage2 = { name = 'mech_armor_stage2', label = 'Armor Upgrade 40%', weight = 20000, type = 'item', image = 'mech_armor_stage2.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Armor upgrade, level 2.' },
    mech_armor_stage3 = { name = 'mech_armor_stage3', label = 'Armor Upgrade 60%', weight = 25000, type = 'item', image = 'mech_armor_stage3.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Armor upgrade, level 3.' },
    mech_armor_stage4 = { name = 'mech_armor_stage4', label = 'Armor Upgrade 80%', weight = 30000, type = 'item', image = 'mech_armor_stage4.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Armor upgrade, level 4.' },
    mech_armor_stage5 = { name = 'mech_armor_stage5', label = 'Armor Upgrade 100%', weight = 35000, type = 'item', image = 'mech_armor_stage5.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Armor upgrade, level 5.' },
    mech_turbo_kit = { name = 'mech_turbo_kit', label = 'Turbo Kit', weight = 12000, type = 'item', image = 'mech_turbo_kit.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Turbo tuning kit.' },

    -- VISUAL TUNING
    mech_paint_can = { name = 'mech_paint_can', label = 'Car Paint', weight = 2000, type = 'item', image = 'mech_paint_can.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Paint for one layer. Needs a spray gun.' },
    mech_bodykit_parts = { name = 'mech_bodykit_parts', label = 'Body Kit Parts', weight = 10000, type = 'item', image = 'mech_bodykit_parts.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Spoilers, bumpers, skirts, hoods and more.' },
    mech_rims = { name = 'mech_rims', label = 'Rims', weight = 20000, type = 'item', image = 'mech_rims.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Set of custom rims.' },
    mech_tyre_smoke_kit = { name = 'mech_tyre_smoke_kit', label = 'Tyre Smoke Kit', weight = 1000, type = 'item', image = 'mech_tyre_smoke_kit.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Colored tyre smoke.' },
    mech_xenon_kit = { name = 'mech_xenon_kit', label = 'Xenon Kit', weight = 1500, type = 'item', image = 'mech_xenon_kit.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Xenon headlights.' },
    mech_neon_kit = { name = 'mech_neon_kit', label = 'Neon Kit', weight = 2000, type = 'item', image = 'mech_neon_kit.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Underglow neon lights.' },
    mech_window_tint = { name = 'mech_window_tint', label = 'Window Tint', weight = 500, type = 'item', image = 'mech_window_tint.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Tint film for all windows.' },
    mech_vinyl = { name = 'mech_vinyl', label = 'Vinyl Wrap', weight = 1000, type = 'item', image = 'mech_vinyl.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Livery wrap.' },
    mech_interior_parts = { name = 'mech_interior_parts', label = 'Interior Parts', weight = 5000, type = 'item', image = 'mech_interior_parts.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Seats, steering wheels, dashboards and more.' },
    mech_horn = { name = 'mech_horn', label = 'Horn', weight = 500, type = 'item', image = 'mech_horn.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Custom horn.' },
    mech_plate_kit = { name = 'mech_plate_kit', label = 'Plate Kit', weight = 500, type = 'item', image = 'mech_plate_kit.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Custom plate style.' },

    -- SUPPLY
    mech_supply_crate = { name = 'mech_supply_crate', label = 'Parts Delivery', weight = 20000, type = 'item', image = 'mech_supply_crate.png', unique = true, useable = false, shouldClose = true, combinable = nil, description = 'Deliver it to the workshop supply point.' },
}
