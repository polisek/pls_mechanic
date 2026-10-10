--[[
   _____            __ _   _
  / ____|          / _| | (_)
 | |     _ __ __ _| |_| |_ _ _ __   __ _
 | |    | '__/ _` |  _| __| | '_ \ / _` |
 | |____| | | (_| | | | |_| | | | | (_| |
  \_____|_|  \__,_|_|  \__|_|_| |_|\__, |
                                    __/ |
                                   |___/
 Workbench recipes. Items are keys of Config.Items (config.lua).
 Materials come from salvage of replaced parts (scrap metal, aluminium, rubber, plastic, electronics, used oil).
 result      = crafted item, count = pieces per craft
 ingredients = removed items, tools = required (not removed) items
 duration    = ms of one craft (the workbench scene phases share it, the server accepts the craft after 85 %)
 category    = kits / parts / body / tools / props / recycling (menu group + workbench scene)
 scene       = optional scene key of Config.Crafting.scenes (default = category)
 prop        = optional model of the product shown on the bench (default Config.Crafting.products[category])
 Own crafting system: server/open.lua OpenServer.OpenCustomCrafting
]]--

-- Workbench poses (anim / prop / sound / particle format as in configs/extras.lua)
local Bench = { dict = "mini@repair", clip = "fixing_a_ped", flag = 1 }                 -- bent over the bench, working with the hands
local Table = { dict = "amb@prop_human_bbq@male@base", clip = "base", flag = 1 }         -- sorting / arranging parts on the bench
local Pour = { dict = "timetable@gardener@filling_can", clip = "gar_ig_5_filling_can", flag = 1 }
local Weld = { scenario = "WORLD_HUMAN_WELDING" }                                         -- own torch, mask and sparks of the game
local Hammer = { scenario = "WORLD_HUMAN_HAMMERING" }                                     -- own hammer of the game
local Grind = { anim = Bench, prop = "grinder", sound = "grinder", particle = "grind_sparks" } -- Config.Animations presets
local Drill = { anim = Bench, prop = "impact_wrench", sound = "impact" }

local function Phase(label, share, preset)
    local phase = { label = label, share = share }
    for key, value in pairs(preset) do phase[key] = value end
    return phase
end

Config.Crafting = {
    enabled = true,
    maxAmount = 10,     -- max crafts in one batch

    -- Workbench scene of each category, phases share the recipe duration
    scenes = {
        kits = {
            Phase("craft_phase_sort", 0.25, { anim = Table }),
            Phase("craft_phase_assemble", 0.50, { anim = Bench, prop = "wrench" }),
            Phase("craft_phase_pack", 0.25, { anim = Table }),
        },
        parts = {
            Phase("craft_phase_weld", 0.35, { anim = Weld }),
            Phase("craft_phase_drill", 0.30, Drill),
            Phase("craft_phase_assemble", 0.35, { anim = Bench, prop = "wrench" }),
        },
        body = {
            Phase("craft_phase_weld", 0.40, { anim = Weld }),
            Phase("craft_phase_hammer", 0.35, { anim = Hammer }),
            Phase("craft_phase_grind", 0.25, Grind),
        },
        tools = {
            Phase("craft_phase_grind", 0.35, Grind),
            Phase("craft_phase_hammer", 0.35, { anim = Hammer }),
            Phase("craft_phase_assemble", 0.30, { anim = Bench, prop = "wrench" }),
        },
        props = {
            Phase("craft_phase_cut", 0.40, Grind),
            Phase("craft_phase_assemble", 0.40, { anim = Bench }),
            Phase("craft_phase_check", 0.20, { anim = Table }),
        },
        recycling = {
            Phase("craft_phase_filter", 0.50, { anim = Pour, prop = "oil" }),
            Phase("craft_phase_fill", 0.50, { anim = Pour, prop = "oil" }),
        },
    },

    -- product shown on the bench after every piece, then taken by the mechanic
    products = {
        kits = "prop_tool_box_04",
        parts = "prop_cs_cardbox_01",
        body = "prop_cs_cardbox_01",
        tools = "prop_tool_box_04",
        props = "prop_roadcone02a",
        recycling = "prop_oilcan_01a",
    },
    take = { dict = "mp_common", clip = "givetake1_b", flag = 0, time = 1300 },  -- taking the product from the bench

    recipes = {
        -- repair kits
        { result = "repair_kit", count = 1, category = "kits", duration = 15000, tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 3 }, { item = "rubber", count = 2 }, { item = "plastic", count = 2 }, { item = "electronics", count = 1 } } },
        { result = "patch_kit", count = 1, category = "kits", duration = 10000, tools = {},
            ingredients = { { item = "rubber", count = 2 }, { item = "plastic", count = 1 }, { item = "scrap_metal", count = 1 } } },
        { result = "cleaning_kit", count = 1, category = "kits", duration = 6000, tools = {},
            ingredients = { { item = "plastic", count = 2 }, { item = "rubber", count = 1 } } },
        { result = "advanced_repair_kit", count = 1, category = "kits", duration = 30000, tools = { "toolbox", "impact_wrench" },
            ingredients = { { item = "repair_kit", count = 1 }, { item = "electronics", count = 2 }, { item = "aluminium", count = 2 }, { item = "scrap_metal", count = 3 } } },

        -- parts
        { result = "brake_pads", count = 1, category = "parts", duration = 12000, tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 2 }, { item = "rubber", count = 1 } } },
        { result = "brake_discs", count = 1, category = "parts", duration = 18000, prop = "imp_prop_impexp_brake_caliper_01a", tools = { "toolbox", "impact_wrench" },
            ingredients = { { item = "scrap_metal", count = 4 } } },
        { result = "spark_plugs", count = 1, category = "parts", duration = 8000, tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 1 }, { item = "electronics", count = 1 } } },
        { result = "timing_belt", count = 1, category = "parts", duration = 10000, tools = {},
            ingredients = { { item = "rubber", count = 3 } } },
        { result = "tyre", count = 1, category = "parts", duration = 15000, prop = "prop_wheel_tyre", tools = { "impact_wrench" },
            ingredients = { { item = "rubber", count = 6 }, { item = "scrap_metal", count = 1 } } },
        { result = "shock_absorber", count = 1, category = "parts", duration = 18000, tools = { "toolbox", "impact_wrench" },
            ingredients = { { item = "scrap_metal", count = 3 }, { item = "used_oil", count = 1 } } },
        { result = "radiator", count = 1, category = "parts", duration = 25000, prop = "imp_prop_impexp_radiator_01", tools = { "toolbox" },
            ingredients = { { item = "aluminium", count = 5 }, { item = "plastic", count = 2 } } },
        { result = "alternator", count = 1, category = "parts", duration = 25000, tools = { "toolbox" },
            ingredients = { { item = "electronics", count = 3 }, { item = "scrap_metal", count = 2 }, { item = "aluminium", count = 1 } } },
        { result = "fuel_pump", count = 1, category = "parts", duration = 20000, tools = { "toolbox" },
            ingredients = { { item = "electronics", count = 2 }, { item = "plastic", count = 2 }, { item = "scrap_metal", count = 1 } } },
        { result = "car_battery", count = 1, category = "parts", duration = 20000, prop = "prop_car_battery_01", tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 3 }, { item = "plastic", count = 2 }, { item = "electronics", count = 1 } } },

        -- body
        { result = "body_panel", count = 1, category = "body", duration = 20000, prop = "imp_prop_impexp_car_panel_01a", tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 5 } } },
        { result = "car_bumper", count = 1, category = "body", duration = 18000, prop = "imp_prop_impexp_front_bumper_01a", tools = { "toolbox" },
            ingredients = { { item = "plastic", count = 6 }, { item = "scrap_metal", count = 1 } } },
        { result = "car_headlight", count = 1, category = "body", duration = 12000, tools = { "toolbox" },
            ingredients = { { item = "plastic", count = 3 }, { item = "electronics", count = 2 } } },
        { result = "car_hood", count = 1, category = "body", duration = 25000, prop = "imp_prop_impexp_bonnet_01a", tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 6 }, { item = "aluminium", count = 2 } } },
        { result = "car_trunk", count = 1, category = "body", duration = 22000, tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 5 }, { item = "aluminium", count = 1 } } },
        { result = "car_door", count = 1, category = "body", duration = 30000, prop = "imp_prop_impexp_car_door_01a", tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 7 }, { item = "plastic", count = 2 }, { item = "electronics", count = 1 } } },

        -- tools
        { result = "slim_jim", count = 1, category = "tools", duration = 6000, prop = "bkr_prop_fakeid_ruler_01a", tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 1 } } },
        { result = "jump_starter", count = 1, category = "tools", duration = 25000, prop = "prop_car_battery_01", tools = { "toolbox" },
            ingredients = { { item = "electronics", count = 4 }, { item = "plastic", count = 2 }, { item = "scrap_metal", count = 1 } } },

        -- road equipment
        { result = "traffic_cone", count = 2, category = "props", duration = 6000, tools = {},
            ingredients = { { item = "plastic", count = 3 } } },
        { result = "work_sign", count = 1, category = "props", duration = 8000, prop = "prop_snow_sign_road_06g", tools = {},
            ingredients = { { item = "scrap_metal", count = 2 }, { item = "plastic", count = 1 } } },
        { result = "road_barrier", count = 1, category = "props", duration = 12000, prop = "prop_barrier_work05", tools = { "toolbox" },
            ingredients = { { item = "scrap_metal", count = 4 }, { item = "plastic", count = 2 } } },

        -- recycling
        { result = "engine_oil", count = 1, category = "recycling", duration = 20000, tools = { "toolbox" },
            ingredients = { { item = "used_oil", count = 4 } } },
    },
}
