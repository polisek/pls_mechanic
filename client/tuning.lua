--[[
  _______            _
 |__   __|          (_)
    | |_   _ _ __    _ _ __   __ _
    | | | | | '_ \  | | '_ \ / _` |
    | | |_| | | | | | | | | | (_| |
    |_|\__,_|_| |_| |_|_| |_|\__, |
                              __/ |
                             |___/
 Performance + visual tuning on workshop bays (bay type "tuning" / "both").
 Preview is applied locally on the vehicle (we own it), server validates and bills every confirmation.
 Closing the menu reverts everything that was not confirmed.
 With Config.Tuning.Install.enabled the confirmed cart is installed step by step (workflow overlay),
 every step is an animated scene and is confirmed by the server on its own.
 Customer catalog (client/catalog.lua): the same session with mode "customer" (no permissions, items or tools),
 the cart is sent to the mechanics as an order. Changes outside the order need the customer's approval (quote).
]]--

Tuning = {}

local Session = nil
local Opening = false
local SessionCounter = 0
local BayCache = {}
local Install = nil          -- running installation (Session stays alive, menu is closed)
local IgnoreDrafts = {}      -- [plate] = true, NUI drafts ignored while the installation owns the draft
local CatalogCfg = Config.Tuning.Catalog or {}

local Categories = {}     -- key -> category entry (config + computed fields)
local CategoryOrder = {}  -- entries in UI order (wheels expanded per wheel type)
local TuningKeys = {}     -- ox_lib vehicle property keys handled by tuning

local PAINT_KEYS = { paintType1 = true, paintType2 = true, color1 = true, color2 = true, pearlescentColor = true, wheelColor = true }
local NEON_BITS = { 1, 2, 4, 8 } -- neon index 0..3 (left, right, front, back) -> bit of layout mask
local KINDS = {
    performance = "list", performance_toggle = "toggle", mod = "list", toggle = "toggle", wheels = "list",
    back_wheels = "list", custom_tyres = "toggle", color = "color", paint_type = "list", rgb = "rgb",
    neon_layout = "list", window_tint = "list", plate = "list", livery = "list",
}
local PROP_GROUPS = {
    wheels = { "wheels", "modFrontWheels", "modCustomTiresF" },
    back_wheels = { "modBackWheels", "modCustomTiresR" },
}

--[[
   _____      _                        _
  / ____|    | |                      (_)
 | |     __ _| |_ ___  __ _  ___  _ __ _  ___  ___
 | |    / _` | __/ _ \/ _` |/ _ \| '__| |/ _ \/ __|
 | |___| (_| | ||  __/ (_| | (_) | |  | |  __/\__ \
  \_____\__,_|\__\___|\__, |\___/|_|  |_|\___||___/
                       __/ |
                      |___/
]]--

local function registerCategory(entry)
    entry.order = #CategoryOrder + 1
    Categories[entry.key] = entry
    CategoryOrder[#CategoryOrder + 1] = entry
    if entry.prop then
        TuningKeys[entry.prop] = true
    end
end

for _, cfg in ipairs(Config.Tuning.Performance) do
    local entry = Utils.DeepCopy(cfg)
    entry.type = cfg.toggle and "performance_toggle" or "performance"
    entry.group = "performance"
    entry.performance = true
    registerCategory(entry)
end

for _, cfg in ipairs(Config.Tuning.Visual) do
    if cfg.type == "wheels" then
        for _, wheel in ipairs(Config.Tuning.WheelTypes) do
            local entry = Utils.DeepCopy(cfg)
            entry.key = cfg.key.."_"..wheel.key
            entry.wheel = wheel
            registerCategory(entry)
        end
        TuningKeys.wheels = true
    else
        registerCategory(Utils.DeepCopy(cfg))
    end
end
TuningKeys.modCustomTiresR = true

local PaintPalette, PaintValues, XenonValues = {}, {}, {}
local PaintLabels, XenonKeys, PaintTypeKeys, TintKeys, PlateKeys, NeonKeys = {}, {}, {}, {}, {}, {}
for _, color in ipairs(Config.Tuning.Colors) do
    PaintPalette[#PaintPalette + 1] = { value = color.value, label = color.label, hex = color.hex }
    PaintValues[color.value] = true
    PaintLabels[color.value] = color.label
end
for _, color in ipairs(Config.Tuning.XenonColors) do
    XenonValues[color.value] = true
    XenonKeys[color.value] = color.key
end
for _, paintType in ipairs(Config.Tuning.PaintTypes) do PaintTypeKeys[paintType.value] = paintType.key end
for _, tint in ipairs(Config.Tuning.WindowTints) do TintKeys[tint.value] = tint.key end
for _, style in ipairs(Config.Tuning.PlateStyles) do PlateKeys[style.value] = style.key end
for _, layout in ipairs(Config.Tuning.NeonLayouts) do NeonKeys[layout.value] = layout.key end

-- Performance categories other categories depend on (installed first)
local RequiredCategories = {}
for _, entry in ipairs(CategoryOrder) do
    for _, rule in ipairs(entry.requires or {}) do
        RequiredCategories[rule.category] = true
    end
end

local function catLabel(entry)
    if entry.label then return entry.label end
    if entry.wheel then
        return locale("tuning_cat_wheels", locale("tuning_wheel_"..entry.wheel.key))
    end
    return locale("tuning_cat_"..entry.key)
end

--[[
 __      __   _
 \ \    / /  | |
  \ \  / /_ _| |_   _  ___  ___
   \ \/ / _` | | | | |/ _ \/ __|
    \  / (_| | | |_| |  __/\__ \
     \/ \__,_|_|\__,_|\___||___/

 Values of categories are read from / written to ox_lib vehicle properties (same logic on server).
]]--

local function toInt(value)
    local number = tonumber(value)
    if not number then return nil end
    return math.tointeger(number)
end

local function readValue(entry, props)
    local kind = entry.type
    local value = props[entry.prop]
    if kind == "performance_toggle" or kind == "toggle" or kind == "custom_tyres" then
        return value == true or value == 1
    elseif kind == "wheels" then
        if toInt(props.wheels) ~= entry.wheel.type then return -1 end
        return toInt(value) or -1
    elseif kind == "rgb" then
        if type(value) ~= "table" then return { r = 255, g = 255, b = 255 } end
        return { r = toInt(value[1] or value.r) or 255, g = toInt(value[2] or value.g) or 255, b = toInt(value[3] or value.b) or 255 }
    elseif kind == "neon_layout" then
        local mask = 0
        if type(value) == "table" then
            for i = 1, 4 do
                if value[i] == true then mask = mask | NEON_BITS[i] end
            end
        end
        return mask
    elseif kind == "color" then
        value = toInt(value)
        if entry.palette == "xenon" then
            if not value or value < 0 or value > 12 then return 255 end
            return value
        end
        return value or -1
    elseif kind == "window_tint" then
        value = toInt(value) or 0
        return value < 0 and 0 or value
    elseif kind == "paint_type" or kind == "plate" then
        return toInt(value) or 0
    end
    return toInt(value) or -1
end

local function writeValue(entry, props, value)
    local kind = entry.type
    if kind == "wheels" then
        props.wheels = entry.wheel.type
        props.modFrontWheels = value
    elseif kind == "custom_tyres" then
        props.modCustomTiresF = value
        props.modCustomTiresR = value
    elseif kind == "rgb" then
        props[entry.prop] = { value.r, value.g, value.b }
    elseif kind == "neon_layout" then
        local list = {}
        for i = 1, 4 do
            list[i] = (value & NEON_BITS[i]) ~= 0
        end
        props[entry.prop] = list
    else
        props[entry.prop] = value
    end
end

local function sameValue(a, b)
    if type(a) == "table" and type(b) == "table" then
        return a.r == b.r and a.g == b.g and a.b == b.b
    end
    return a == b
end

-- Returning to stock / turning off (no material, removal price)
local function isRemoval(entry, value)
    local kind = entry.type
    if kind == "performance_toggle" or kind == "toggle" or kind == "custom_tyres" then return value == false end
    if kind == "neon_layout" or kind == "window_tint" then return value == 0 end
    if kind == "performance" or kind == "mod" or kind == "wheels" or kind == "back_wheels" then return value == -1 end
    return false
end

local function basePrice(entry, value)
    local kind = entry.type
    if kind == "performance" then
        if value < 0 then return entry.removePrice or 0 end
        local level = entry.levels[value + 1]
        return level and level.price or 0
    end
    if kind == "mod" or kind == "wheels" or kind == "back_wheels" or kind == "livery" or kind == "neon_layout" or kind == "window_tint" then
        if isRemoval(entry, value) then
            return math.floor((entry.price or 0) * Config.Tuning.RemoveFactor + 0.5)
        end
        if kind == "neon_layout" or kind == "window_tint" then
            return entry.price or 0
        end
        return (entry.price or 0) + math.max(value, 0) * (entry.priceStep or 0)
    end
    return entry.price or 0
end

local function withMarkup(price, markup)
    return math.max(0, math.floor(price * (1 + (markup or 0) / 100) + 0.5))
end

-- Performance stage (0 = stock)
local function stageOf(entry, value)
    if entry.type == "performance_toggle" then
        return value == true and 1 or 0
    end
    return (tonumber(value) or -1) + 1
end

local function isEnabled(entry, state)
    local value = readValue(entry, state)
    if type(value) == "boolean" then return value end
    return type(value) == "number" and value > 0
end

-- Same rules as server checkRequirements: changes = { { entry, value } }, final = props after the changes
local function checkRequirements(changes, final)
    local touched = {}
    for _, change in ipairs(changes) do
        touched[change.entry.key] = true
    end
    for _, entry in ipairs(CategoryOrder) do
        for _, rule in ipairs(entry.performance and entry.requires or {}) do
            local required = Categories[rule.category]
            if required and (touched[entry.key] or touched[rule.category]) then
                local stage = stageOf(entry, readValue(entry, final))
                if stage >= rule.stage and stageOf(required, readValue(required, final)) < rule.minStage then
                    return false, locale("tuning_requires", catLabel(entry), rule.stage, catLabel(required), rule.minStage)
                end
            end
        end
    end
    for _, change in ipairs(changes) do
        local needed = change.entry.needs and Categories[change.entry.needs]
        local neutral = change.entry.palette == "xenon" and change.value == 255
        if needed and not neutral and not isEnabled(needed, final) then
            return false, locale("tuning_requires_enabled", catLabel(change.entry), catLabel(needed))
        end
    end
    return true
end

-- Item consumed by the change (same as server): Config.Items key, count or nil
local function requiredItem(entry, value)
    if entry.performance then
        local stage = stageOf(entry, value)
        if stage <= 0 then return nil end
        if entry.type == "performance_toggle" then return entry.item, 1 end
        local level = entry.levels[stage]
        return level and level.item, 1
    end
    if entry.material and not isRemoval(entry, value) then
        return entry.material.item, entry.material.count
    end
    return nil
end

-- Readable value for the installation steps
local function valueLabel(entry, value, vehicle)
    local kind = entry.type
    if kind == "performance" then
        return value < 0 and locale("tuning_stock") or locale("tuning_stage", value + 1)
    elseif kind == "performance_toggle" or kind == "toggle" or kind == "custom_tyres" then
        return value and locale("tuning_installed") or locale("tuning_removed")
    elseif kind == "rgb" then
        return locale("tuning_rgb", value.r, value.g, value.b)
    elseif kind == "color" then
        if entry.palette == "xenon" then
            return locale("tuning_xenon_"..(XenonKeys[value] or "stock"))
        end
        return PaintLabels[value] or tostring(value)
    elseif kind == "paint_type" then
        return PaintTypeKeys[value] and locale("tuning_paint_"..PaintTypeKeys[value]) or tostring(value)
    elseif kind == "neon_layout" then
        return NeonKeys[value] and locale("tuning_neon_"..NeonKeys[value]) or locale("tuning_neon_custom")
    elseif kind == "window_tint" then
        return TintKeys[value] and locale("tuning_tint_"..TintKeys[value]) or tostring(value)
    elseif kind == "plate" then
        return PlateKeys[value] and locale("tuning_plate_"..PlateKeys[value]) or tostring(value)
    elseif kind == "livery" then
        local name = vehicle and GetLiveryName(vehicle, value)
        local text = name and name ~= "" and name ~= "NULL" and GetLabelText(name) or nil
        return (text and text ~= "" and text ~= "NULL") and text or locale("tuning_livery_n", value + 1)
    end
    if value < 0 then return locale("tuning_stock") end
    if kind == "mod" and vehicle then
        if entry.mod == 14 and Config.Tuning.HornNames[value] then
            return Config.Tuning.HornNames[value]
        end
        local label = GetModTextLabel(vehicle, entry.mod, value)
        local text = label and label ~= "" and label ~= "NULL" and GetLabelText(label) or nil
        if text and text ~= "" and text ~= "NULL" then return text end
    end
    return locale("tuning_level", value + 1)
end

-- NUI value -> validated value or nil
local function normalizeValue(item, raw)
    local kind = KINDS[item.entry.type]
    if kind == "toggle" then
        if type(raw) ~= "boolean" then return nil end
        return raw
    elseif kind == "rgb" then
        if type(raw) ~= "table" then return nil end
        local r, g, b = toInt(raw.r), toInt(raw.g), toInt(raw.b)
        if not r or not g or not b then return nil end
        return { r = Utils.Clamp(r, 0, 255), g = Utils.Clamp(g, 0, 255), b = Utils.Clamp(b, 0, 255) }
    end
    local value = toInt(raw)
    if value == nil or not item.values[value] then return nil end
    return value
end

--[[
 __      __  _     _      _
 \ \    / / | |   (_)    | |
  \ \  / /__| |__  _  ___| | ___
   \ \/ / _ \ '_ \| |/ __| |/ _ \
    \  /  __/ | | | | (__| |  __/
     \/ \___|_| |_|_|\___|_|\___|
]]--

-- Tuning related subset of lib.getVehicleProperties
local function getTuningProps(vehicle)
    local props = lib.getVehicleProperties(vehicle)
    if not props then return nil end
    local result = {}
    for key in pairs(TuningKeys) do
        if props[key] ~= nil then
            result[key] = props[key]
        end
    end
    return result
end

-- Paint layers + finish. paint = props-like table (paintType1/2, color1/2 number or {r,g,b}, pearlescentColor, wheelColor)
local function restorePaint(vehicle, paint)
    local color1, color2 = GetVehicleColours(vehicle)
    local pearl, wheel = GetVehicleExtraColours(vehicle)
    local type1 = GetVehicleModColor_1(vehicle)
    local type2 = GetVehicleModColor_2(vehicle)
    pearl = paint.pearlescentColor or pearl
    wheel = paint.wheelColor or wheel

    SetVehicleModColor_1(vehicle, paint.paintType1 or type1, 0, pearl)
    SetVehicleModColor_2(vehicle, paint.paintType2 or type2, 0)
    SetVehicleColours(vehicle, type(paint.color1) == "number" and paint.color1 or color1, type(paint.color2) == "number" and paint.color2 or color2)

    if type(paint.color1) == "table" then
        SetVehicleCustomPrimaryColour(vehicle, paint.color1[1] or 0, paint.color1[2] or 0, paint.color1[3] or 0)
    elseif paint.color1 then
        ClearVehicleCustomPrimaryColour(vehicle)
    end
    if type(paint.color2) == "table" then
        SetVehicleCustomSecondaryColour(vehicle, paint.color2[1] or 0, paint.color2[2] or 0, paint.color2[3] or 0)
    elseif paint.color2 then
        ClearVehicleCustomSecondaryColour(vehicle)
    end
    SetVehicleExtraColours(vehicle, pearl, wheel)
end

-- lib.setVehicleProperties for tuning keys, paint is handled here (ox_lib doesn't restore paint type of index colors)
local function applyProps(vehicle, props)
    if not DoesEntityExist(vehicle) then return end
    local other, hasPaint = {}, false
    for key, value in pairs(props) do
        if PAINT_KEYS[key] then
            hasPaint = true
        else
            other[key] = value
        end
    end
    if next(other) then
        lib.setVehicleProperties(vehicle, other)
    end
    if hasPaint then
        restorePaint(vehicle, props)
    end
end

-- Preview of one value on the vehicle
local function applyValue(vehicle, entry, value)
    local s = Session
    local kind = entry.type
    if kind == "performance" or kind == "mod" then
        if value < 0 then
            RemoveVehicleMod(vehicle, entry.mod)
        else
            SetVehicleMod(vehicle, entry.mod, value, false)
            if entry.mod == 14 then
                StartVehicleHorn(vehicle, 1500, joaat("HELDDOWN"), false)
            end
        end
    elseif kind == "performance_toggle" or kind == "toggle" then
        ToggleVehicleMod(vehicle, entry.mod, value)
    elseif kind == "wheels" then
        SetVehicleWheelType(vehicle, entry.wheel.type)
        SetVehicleMod(vehicle, 23, value, GetVehicleModVariation(vehicle, 23))
        if s then s.wheelKey = entry.key end
    elseif kind == "back_wheels" then
        SetVehicleMod(vehicle, 24, value, GetVehicleModVariation(vehicle, 24))
    elseif kind == "custom_tyres" then
        SetVehicleMod(vehicle, 23, GetVehicleMod(vehicle, 23), value)
        if s and s.isBike then
            SetVehicleMod(vehicle, 24, GetVehicleMod(vehicle, 24), value)
        end
    elseif kind == "color" then
        if entry.palette == "xenon" then
            SetVehicleXenonLightsColor(vehicle, value)
        elseif s then
            s.paint[entry.prop] = value
            restorePaint(vehicle, s.paint)
        end
    elseif kind == "paint_type" then
        if s then
            s.paint[entry.prop] = value
            restorePaint(vehicle, s.paint)
        end
    elseif kind == "rgb" then
        if entry.prop == "neonColor" then
            SetVehicleNeonLightsColour(vehicle, value.r, value.g, value.b)
        else
            SetVehicleTyreSmokeColor(vehicle, value.r, value.g, value.b)
        end
    elseif kind == "neon_layout" then
        for i = 1, 4 do
            SetVehicleNeonLightEnabled(vehicle, i - 1, (value & NEON_BITS[i]) ~= 0)
        end
    elseif kind == "window_tint" then
        SetVehicleWindowTint(vehicle, value)
    elseif kind == "plate" then
        SetVehicleNumberPlateTextIndex(vehicle, value)
    elseif kind == "livery" then
        SetVehicleLivery(vehicle, value)
    end
end

-- Puts one category back to the last confirmed value
local function revertEntry(entry)
    local s = Session
    if not s or not DoesEntityExist(s.vehicle) then return end
    if PAINT_KEYS[entry.prop] then
        s.paint[entry.prop] = Utils.DeepCopy(s.confirmed[entry.prop])
        restorePaint(s.vehicle, s.paint)
        return
    end
    if entry.type == "custom_tyres" then
        applyValue(s.vehicle, entry, readValue(entry, s.confirmed))
        return
    end
    local subset = {}
    for _, key in ipairs(PROP_GROUPS[entry.type] or { entry.prop }) do
        subset[key] = Utils.DeepCopy(s.confirmed[key])
    end
    applyProps(s.vehicle, subset)
end

--[[
  _   _ _    _ _____        _       _
 | \ | | |  | |_   _|      | |     | |
 |  \| | |  | | | |      __| | __ _| |_ __ _
 | . ` | |  | | | |     / _` |/ _` | __/ _` |
 | |\  | |__| |_| |_   | (_| | (_| | || (_| |
 |_| \_|\____/|_____|   \__,_|\__,_|\__\__,_|
]]--

local function gameLabel(label)
    if not label or label == "" or label == "NULL" then return nil end
    local text = GetLabelText(label)
    if not text or text == "" or text == "NULL" then return nil end
    return text
end

local function itemReq(key, count, counts)
    local name = Utils.Item(key)
    if counts[key] == nil then
        counts[key] = Core.CountItem(key)
    end
    return { item = name, label = Core.GetItemLabel(name), count = count, have = counts[key] }
end

local function modOptionLabel(vehicle, entry, index)
    if entry.mod == 14 and Config.Tuning.HornNames[index] then
        return Config.Tuning.HornNames[index]
    end
    return gameLabel(GetModTextLabel(vehicle, entry.mod, index)) or locale("tuning_level", index + 1)
end

local function wheelTypeAllowed(ctx, wheel)
    if ctx.isBike then
        if not wheel.bike then return false end
    elseif ctx.isOpenWheel then
        if not wheel.openWheel then return false end
    elseif wheel.bike or wheel.openWheel then
        return false
    end
    return not wheel.minBuild or ctx.build >= wheel.minBuild
end

-- Returns NUI category + set of allowed values, nil when category is not available on this vehicle
local function buildCategory(ctx, entry)
    local vehicle = ctx.vehicle
    local kind = entry.type
    local current = readValue(entry, ctx.confirmed)
    local category = { key = entry.key, label = catLabel(entry), group = entry.group, kind = KINDS[kind], current = current }
    local values = {}
    local options = nil

    local function addOption(value, label, item)
        options = options or {}
        options[#options + 1] = {
            value = value,
            label = label,
            price = withMarkup(basePrice(entry, value), ctx.markup),
            item = item,
            installed = sameValue(value, current),
            removal = isRemoval(entry, value) or nil,
        }
        values[value] = true
    end

    if entry.iceOnly and ctx.isEv then return nil end

    if kind == "performance" then
        local count = math.min(GetNumVehicleMods(vehicle, entry.mod), #entry.levels)
        if count <= 0 then return nil end
        addOption(-1, locale("tuning_stock"))
        for i = 0, count - 1 do
            addOption(i, locale("tuning_stage", i + 1), not ctx.customer and itemReq(entry.levels[i + 1].item, 1, ctx.counts) or nil)
        end
    elseif kind == "performance_toggle" or kind == "toggle" then
        if not ctx.hasModKit then return nil end
    elseif kind == "mod" then
        local count = GetNumVehicleMods(vehicle, entry.mod)
        if count <= 0 then return nil end
        addOption(-1, locale("tuning_stock"))
        for i = 0, count - 1 do
            addOption(i, modOptionLabel(vehicle, entry, i))
        end
    elseif kind == "wheels" then
        if not wheelTypeAllowed(ctx, entry.wheel) then return nil end
        SetVehicleWheelType(vehicle, entry.wheel.type)
        local count = GetNumVehicleMods(vehicle, 23)
        if count <= 0 then return nil end
        addOption(-1, locale("tuning_stock"))
        for i = 0, count - 1 do
            addOption(i, gameLabel(GetModTextLabel(vehicle, 23, i)) or locale("tuning_level", i + 1))
        end
    elseif kind == "back_wheels" then
        if not ctx.isBike then return nil end
        local count = GetNumVehicleMods(vehicle, 24)
        if count <= 0 then return nil end
        addOption(-1, locale("tuning_stock"))
        for i = 0, count - 1 do
            addOption(i, gameLabel(GetModTextLabel(vehicle, 24, i)) or locale("tuning_level", i + 1))
        end
    elseif kind == "custom_tyres" then
        if not ctx.hasModKit then return nil end
    elseif kind == "color" then
        if entry.palette == "xenon" then
            local palette = {}
            for _, color in ipairs(Config.Tuning.XenonColors) do
                palette[#palette + 1] = { value = color.value, label = locale("tuning_xenon_"..color.key), hex = color.hex }
            end
            category.palette = palette
            values = XenonValues
        else
            category.palette = PaintPalette
            values = PaintValues
        end
    elseif kind == "paint_type" then
        for _, paintType in ipairs(Config.Tuning.PaintTypes) do
            if entry.target ~= "secondary" or not paintType.primaryOnly then
                addOption(paintType.value, locale("tuning_paint_"..paintType.key))
            end
        end
    elseif kind == "rgb" then
        if entry.prop == "neonColor" and ctx.isBike then return nil end
    elseif kind == "neon_layout" then
        if ctx.isBike then return nil end
        for _, layout in ipairs(Config.Tuning.NeonLayouts) do
            addOption(layout.value, locale("tuning_neon_"..layout.key))
        end
        if not values[current] then
            addOption(current, locale("tuning_neon_custom"))
        end
    elseif kind == "window_tint" then
        if ctx.isBike then return nil end
        for _, tint in ipairs(Config.Tuning.WindowTints) do
            addOption(tint.value, locale("tuning_tint_"..tint.key))
        end
    elseif kind == "plate" then
        for _, style in ipairs(Config.Tuning.PlateStyles) do
            addOption(style.value, locale("tuning_plate_"..style.key))
        end
    elseif kind == "livery" then
        local count = GetVehicleLiveryCount(vehicle)
        if count <= 1 then return nil end
        for i = 0, count - 1 do
            addOption(i, gameLabel(GetLiveryName(vehicle, i)) or locale("tuning_livery_n", i + 1))
        end
    else
        return nil
    end

    category.options = options
    if category.kind ~= "list" then
        category.price = withMarkup(basePrice(entry, true), ctx.markup)
    end
    -- customer catalog: parts and tools are the mechanic's business
    if ctx.customer then
        return category, values
    end
    if kind == "performance_toggle" and entry.item then
        category.item = itemReq(entry.item, 1, ctx.counts)
    elseif entry.material then
        category.item = itemReq(entry.material.item, entry.material.count, ctx.counts)
    end
    if entry.tool then
        category.tool = itemReq(entry.tool, 1, ctx.counts)
    end
    return category, values
end

local function buildData()
    local s = Session
    local vehicle = s.vehicle
    local ctx = {
        vehicle = vehicle,
        confirmed = s.confirmed,
        markup = s.markup,
        counts = {},
        isBike = s.isBike,
        isOpenWheel = s.isOpenWheel,
        isEv = s.isEv,
        hasModKit = GetNumModKits(vehicle) > 0,
        build = GetGameBuildNumber(),
        available = {},
        customer = s.mode == "customer",
    }
    local canPerformance = Core.HasPermission("tuning_performance", s.shopId)
    local canVisual = Core.HasPermission("tuning_visual", s.shopId)
    -- customer catalog: no permissions, performance parts only when the server allows them
    if ctx.customer then
        canPerformance, canVisual = s.performance == true, true
    end

    -- wheel categories switch wheel type to read rims, live state is restored afterwards
    local wheelType = GetVehicleWheelType(vehicle)
    local frontWheel, frontCustom = GetVehicleMod(vehicle, 23), GetVehicleModVariation(vehicle, 23)

    local categories, index = {}, {}
    for _, entry in ipairs(CategoryOrder) do
        local allowed = (entry.performance and canPerformance) or (not entry.performance and canVisual)
        if allowed and (not entry.needs or ctx.available[entry.needs]) then
            local ok, category, values = pcall(buildCategory, ctx, entry)
            if ok and category then
                categories[#categories + 1] = category
                index[entry.key] = { entry = entry, values = values }
                ctx.available[entry.key] = true
            elseif not ok then
                Utils.Debug("tuning category", entry.key, category)
            end
        end
    end

    SetVehicleWheelType(vehicle, wheelType)
    SetVehicleMod(vehicle, 23, frontWheel, frontCustom)

    s.index = index
    return { netId = s.netId, plate = s.plate, model = s.model, categories = categories }
end

local function pushUpdate()
    if Session and DoesEntityExist(Session.vehicle) then
        Core.Nui.Update("tuning", buildData())
    end
end

-- Unconfirmed cart per vehicle (NUI saves it on every change), restored on next open
local Drafts = {}   -- [plate] = { changes = { { key, value } }, time }

local function getDraft(plate)
    local draft = plate and Drafts[plate]
    if not draft then return nil end
    local minutes = Config.Tuning.DraftMinutes or 0
    if minutes <= 0 or GetGameTimer() - draft.time > minutes * 60000 then
        Drafts[plate] = nil
        return nil
    end
    return draft.changes
end

--[[
   _____
  / ____|
 | |     __ _ _ __ ___   ___ _ __ __ _
 | |    / _` | '_ ` _ \ / _ \ '__/ _` |
 | |___| (_| | | | | | |  __/ | | (_| |
  \_____\__,_|_| |_| |_|\___|_|  \__,_|
]]--

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpAngle(a, b, t)
    return a + (((b - a + 180.0) % 360.0) - 180.0) * t
end

local function cameraGoal(name)
    local s = Session
    local preset = Config.Tuning.Cameras[name] or Config.Tuning.Cameras.default
    local target = nil
    if preset.bone then
        local bone = GetEntityBoneIndexByName(s.vehicle, preset.bone)
        if bone ~= -1 then
            local world = GetWorldPositionOfEntityBone(s.vehicle, bone)
            target = GetOffsetFromEntityGivenWorldCoords(s.vehicle, world.x, world.y, world.z)
        end
    end
    if not target then
        local t = preset.target or vec3(0.0, 0.0, 0.0)
        target = vector3(s.center.x + t.x * s.half.x, s.center.y + t.y * s.half.y, s.center.z + t.z * s.half.z)
    end
    local distance = (preset.distance or 4.0) * s.scale
    return {
        name = Config.Tuning.Cameras[name] and name or "default",
        target = target,
        angle = preset.angle or 0.0,
        distance = distance,
        baseDistance = distance,
        height = (preset.height or 1.0) * s.scale,
        fov = preset.fov or 50.0,
        door = preset.door,
    }
end

local function updateCamera(dt)
    local s = Session
    local cam = s.cam
    local goal = cam.goal
    local k = 1.0 - math.exp(-dt * Config.Tuning.CameraSpeed)
    cam.angle = lerpAngle(cam.angle, goal.angle, k)
    cam.distance = lerp(cam.distance, goal.distance, k)
    cam.height = lerp(cam.height, goal.height, k)
    cam.fov = lerp(cam.fov, goal.fov, k)
    cam.target = cam.target + (goal.target - cam.target) * k

    local rad = math.rad(cam.angle)
    local offset = cam.target + vector3(math.sin(rad) * cam.distance, math.cos(rad) * cam.distance, cam.height)
    local position = GetOffsetFromEntityInWorldCoords(s.vehicle, offset.x, offset.y, offset.z)
    local look = GetOffsetFromEntityInWorldCoords(s.vehicle, cam.target.x, cam.target.y, cam.target.z)
    SetCamCoord(cam.handle, position.x, position.y, position.z)
    PointCamAtCoord(cam.handle, look.x, look.y, look.z)
    SetCamFov(cam.handle, cam.fov)
end

local function createCamera()
    local s = Session
    local goal = cameraGoal("default")
    s.cam = {
        goal = goal,
        angle = goal.angle,
        distance = goal.distance,
        height = goal.height,
        fov = goal.fov,
        target = goal.target,
        handle = CreateCam("DEFAULT_SCRIPTED_CAMERA", true),
    }
    updateCamera(0.0)
    SetCamActive(s.cam.handle, true)
    RenderScriptCams(true, true, 800, true, true)
end

local function destroyCamera(cam, ease)
    if not cam or not cam.handle then return end
    RenderScriptCams(false, ease, ease and 600 or 0, true, true)
    if ease then Wait(600) end
    if DoesCamExist(cam.handle) then
        DestroyCam(cam.handle, false)
    end
end

-- Opens door of camera preset (hood / trunk / driver door), closes the previous one
local function setDoor(door)
    local s = Session
    if s.door == door then return end
    if s.door then
        SetVehicleDoorShut(s.vehicle, s.door, false)
        s.door = nil
    end
    if door and GetIsDoorValid(s.vehicle, door) and GetVehicleDoorAngleRatio(s.vehicle, door) < 0.05 then
        SetVehicleDoorOpen(s.vehicle, door, false, false)
        s.door = door
    end
end

-- Headlights + engine on while looking at lights (xenon / neon preview)
local function setLights(on)
    local s = Session
    if s.lights == on then return end
    s.lights = on
    SetVehicleLights(s.vehicle, on and 2 or 0)
    if not s.engineOn then
        SetVehicleEngineOn(s.vehicle, on, true, false)
    end
end

local function focusCamera(entry)
    local s = Session
    s.cam.goal = cameraGoal(entry and entry.cam or "default")
    setDoor(s.cam.goal.door)
    setLights(entry ~= nil and entry.group == "lights")
end

local function cameraAction(action)
    local goal = Session.cam.goal
    if action == "rotateLeft" then
        goal.angle = (goal.angle - 35.0) % 360.0
    elseif action == "rotateRight" then
        goal.angle = (goal.angle + 35.0) % 360.0
    elseif action == "zoomIn" then
        goal.distance = math.max(goal.baseDistance * 0.45, goal.distance * 0.8)
    elseif action == "zoomOut" then
        goal.distance = math.min(goal.baseDistance * 2.2, goal.distance * 1.25)
    elseif action == "reset" then
        Session.cam.goal = cameraGoal(goal.name)
        setDoor(Session.cam.goal.door)
    else
        return false
    end
    return true
end

--[[
  _____          _
 |  __ \        | |
 | |__) |__  ___| |
 |  ___/ _ \/ _ \ |
 | |  |  __/  __/_|
 |_|   \___|\___(_)

 Mechanic animations.
]]--

local function playAnim(anim)
    if not anim then return nil end
    local prop = anim.prop and Core.AttachProp(anim.prop) or nil
    local ok = pcall(Core.PlayAnim, anim.dict, anim.clip, anim.flag or 1, -1)
    if not ok then
        Utils.Debug("tuning animation failed", anim.dict, anim.clip)
    end
    return prop
end

local function stopAnim(prop)
    Core.StopAnim()
    Core.DeleteProp(prop)
end

local function workAnimation(entries)
    local anims = Config.Tuning.Animations
    for _, entry in ipairs(entries) do
        if entry.performance and entry.tool then return anims.laptop end
    end
    for _, entry in ipairs(entries) do
        if entry.group == "paint" and entry.tool then return anims.paint end
    end
    return anims.work
end

-- Installation after confirmation, menu stays open
local function playWork(entries)
    local s = Session
    if not s or #entries == 0 then return end
    local duration = math.min(Config.Tuning.WorkTime.perChange * #entries, Config.Tuning.WorkTime.max)
    stopAnim(s.prop)
    s.prop = playAnim(workAnimation(entries))
    local prop = s.prop
    local endTime = GetGameTimer() + duration
    while Session == s and GetGameTimer() < endTime do
        Wait(100)
    end
    stopAnim(prop)
    if Session == s then
        s.prop = playAnim(Config.Tuning.Animations.idle)
    end
end

--[[
   _____                _
  / ____|              (_)
 | (___   ___  ___ ___ _  ___  _ __
  \___ \ / _ \/ __/ __| |/ _ \| '_ \
  ____) |  __/\__ \__ \ | (_) | | | |
 |_____/ \___||___/___/_|\___/|_| |_|
]]--

local function findTuningBay(shop, coords)
    for _, point in pairs(shop and shop.points or {}) do
        if point.type == "bay" and Utils.BayAccepts(point, "tuning") then
            if #(coords - Utils.Vec3(point.coords)) <= (point.radius or Config.PointTypes.bay.radius) then
                return point
            end
        end
    end
    return nil
end

local function modelLabel(vehicle)
    local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    return gameLabel(name) or name
end

-- Changes outside a customer order need the customer's approval (Config.Tuning.Catalog)
local function approvalEnabled()
    return CatalogCfg.enabled == true and CatalogCfg.approval == true
end

-- instant = resource stop (no waits, no server call)
local function cleanup(revert, instant)
    local s = Session
    if not s then return end
    -- confirmation on the way: wait for the server, a paid change must not be reverted
    while not instant and s.awaiting and Session == s do
        Wait(50)
    end
    if Session ~= s then return end
    Session = nil

    -- reverted = the preview is gone (we had control), otherwise the server leaves a revert on the vehicle (statebag)
    local reverted = false
    local vehicle = s.vehicle
    if DoesEntityExist(vehicle) then
        local control = NetworkHasControlOfEntity(vehicle) or (not instant and Core.RequestControl(vehicle, 1500))
        if control then
            if revert then
                local ok, err = pcall(applyProps, vehicle, s.confirmed)
                if not ok then print("[pls_mechanic] tuning revert failed: "..tostring(err)) end
                reverted = ok
            end
            -- customer catalog: doors back to the lock status before the catalog
            if s.doorLock ~= nil then
                SetVehicleDoorsLocked(vehicle, s.doorLock)
            end
            if s.door then
                SetVehicleDoorShut(vehicle, s.door, false)
            end
            if s.lights then
                SetVehicleLights(vehicle, 0)
                if not s.engineOn then SetVehicleEngineOn(vehicle, false, true, false) end
            end
            if s.frozen and not Core.IsVehicleOnLift(vehicle) and not Core.GetJack(vehicle) then
                FreezeEntityPosition(vehicle, false)
            end
        end
    end

    stopAnim(s.prop)
    if not s.radarHidden then
        DisplayRadar(true)
    end
    destroyCamera(s.cam, not instant)
    if not instant then
        TriggerSecureEvent(s.closeEvent, reverted)
    end
end

local function startThreads(id)
    -- camera + hud (per frame only while the menu is open, ends when the installation starts)
    CreateThread(function()
        local last = GetGameTimer()
        while Session and Session.id == id and not Session.installing do
            local now = GetGameTimer()
            local dt = math.min((now - last) / 1000.0, 0.1)
            last = now
            HideHudAndRadarThisFrame()
            if Config.Tuning.HidePlayer then
                SetEntityLocallyInvisible(cache.ped)
                if Session.prop and DoesEntityExist(Session.prop) then
                    SetEntityLocallyInvisible(Session.prop)
                end
            end
            if Session.cam and DoesEntityExist(Session.vehicle) then
                updateCamera(dt)
            end
            Wait(0)
        end
    end)

    -- watchdog of the menu (the installation has its own)
    CreateThread(function()
        while Session and Session.id == id and not Session.installing do
            local s = Session
            local reason = nil
            if not DoesEntityExist(s.vehicle) then
                reason = "no_vehicle"
            elseif IsEntityDead(cache.ped) then
                reason = "cancelled"
            elseif #(GetEntityCoords(cache.ped) - GetEntityCoords(s.vehicle)) > s.maxDistance + 2.0 then
                reason = "too_far"
            elseif not IsVehicleSeatFree(s.vehicle, -1) then
                reason = "tuning_vehicle_occupied"
            elseif Core.Nui.GetView() ~= "tuning" then
                reason = false -- another view replaced the menu
            end
            if reason ~= nil and not s.installing then
                if reason then Core.Notify(locale(reason), "error") end
                Core.Nui.Close("tuning")
                return
            end
            if not NetworkHasControlOfEntity(s.vehicle) then
                NetworkRequestControlOfEntity(s.vehicle)
            end
            Wait(500)
        end
    end)
end

-- Server session (menu, installation, catalog) stays alive only with a heartbeat (Config.Tuning.SessionTimeout)
local function startHeartbeat(s)
    CreateThread(function()
        while Session == s do
            Wait(60000)
            if Session == s then
                TriggerSecureEvent("pls_mechanic:server:tuning:heartbeat")
            end
        end
    end)
end

-- Revert left on the vehicle by the server (statebag "pls_mechanic_revert" = { id, state, plate }): a session ended
-- without a confirmed revert (no control, disconnect, stale session). The client with network control applies the
-- tuning keys and reports it, the server clears the statebag. True when applied
local function applyRevert(vehicle)
    if not DoesEntityExist(vehicle) or not NetworkHasControlOfEntity(vehicle) then return false end
    -- own menu / installation on this vehicle, its cleanup decides
    if Session and Session.vehicle == vehicle then return false end
    local revert = Entity(vehicle).state.pls_mechanic_revert
    if type(revert) ~= "table" or type(revert.state) ~= "table" then return false end
    if type(revert.plate) ~= "string" or Utils.TrimPlate(revert.plate) ~= Utils.TrimPlate(GetVehicleNumberPlateText(vehicle)) then
        return false
    end
    local subset = {}
    for key in pairs(TuningKeys) do
        if revert.state[key] ~= nil then
            subset[key] = revert.state[key]
        end
    end
    SetVehicleModKit(vehicle, 0)
    local ok, err = pcall(applyProps, vehicle, subset)
    if not ok then print("[pls_mechanic] tuning revert failed: "..tostring(err)) end
    SetVehicleDoorsShut(vehicle, false)
    SetVehicleLights(vehicle, 0)
    if IsEntityPositionFrozen(vehicle) and not Core.IsVehicleOnLift(vehicle) and not Core.GetJack(vehicle)
        and Core.GetBayAt(GetEntityCoords(vehicle), "tuning") then
        FreezeEntityPosition(vehicle, false)
    end
    TriggerSecureEvent("pls_mechanic:server:tuning:reverted", NetworkGetNetworkIdFromEntity(vehicle), revert.id)
    return true
end

-- customer = catalog of the customer (client/catalog.lua): no permissions, the server finds the workshop by its bay
local function openSession(vehicle, shopId, customer)
    if Session then return end
    if Core.Nui.IsOpen() then
        return Core.Notify(locale("tuning_busy"), "error")
    end
    -- scene of the illegal DLC running (its animation library isn't seen by the BASE checks)
    if Core.IsExternalBusy() then
        return Core.Notify(locale("repair_busy"), "error")
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return Core.Notify(locale("no_vehicle"), "error")
    end
    local shop = nil
    if not customer then
        shopId = shopId or Core.GetMyShopId()
        shop = shopId and Core.GetShop(shopId)
        if not shop then
            return Core.Notify(locale("not_on_duty"), "error")
        end
        if not Core.HasPermission("tuning_visual", shopId) and not Core.HasPermission("tuning_performance", shopId) then
            local onDuty = not Config.RequireDuty or Core.GetDutyShopId() == shopId
            return Core.Notify(locale(onDuty and "no_permission" or "not_on_duty"), "error")
        end
    end
    if Config.Tuning.BlockedClasses[GetVehicleClass(vehicle)] or not NetworkGetEntityIsNetworked(vehicle) then
        return Core.Notify(locale("tuning_vehicle_not_supported"), "error")
    end
    if shop and not findTuningBay(shop, GetEntityCoords(vehicle)) then
        return Core.Notify(locale("tuning_not_in_bay"), "error")
    end
    local maxDistance = customer and (CatalogCfg.maxDistance or Config.Tuning.MaxDistance) or Config.Tuning.MaxDistance
    if #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > maxDistance then
        return Core.Notify(locale("too_far"), "error")
    end
    if cache.vehicle or not IsVehicleSeatFree(vehicle, -1) then
        return Core.Notify(locale("tuning_vehicle_occupied"), "error")
    end
    if not Core.RequestControl(vehicle, 3000) then
        return Core.Notify(locale("no_control"), "error")
    end
    -- unfinished revert of a previous session goes first (the server opens only without it)
    applyRevert(vehicle)

    SetVehicleModKit(vehicle, 0)
    local confirmed = getTuningProps(vehicle)
    if not confirmed then
        return Core.Notify(locale("no_vehicle"), "error")
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local closeEvent = customer and "pls_mechanic:server:catalog:close" or "pls_mechanic:server:tuning:close"
    local result = lib.callback.await(customer and "pls_mechanic:server:catalog:open" or "pls_mechanic:server:tuning:open", false, netId, confirmed)
    if type(result) ~= "table" or not result.ok then
        return Core.Notify(type(result) == "table" and result.message or locale("tuning_failed"), "error")
    end
    -- nothing was previewed yet (true = nothing to revert)
    if Session or not DoesEntityExist(vehicle) then
        TriggerSecureEvent(closeEvent, true)
        return
    end

    local model = GetEntityModel(vehicle)
    local min, max = GetModelDimensions(model)
    local half = (max - min) / 2
    local paint = {}
    for key in pairs(PAINT_KEYS) do
        paint[key] = Utils.DeepCopy(confirmed[key])
    end

    SessionCounter = SessionCounter + 1
    Session = {
        id = SessionCounter,
        mode = customer and "customer" or "mechanic",
        closeEvent = closeEvent,
        vehicle = vehicle,
        netId = netId,
        shopId = customer and tonumber(result.shopId) or shopId,
        plate = Utils.TrimPlate(GetVehicleNumberPlateText(vehicle)),
        model = modelLabel(vehicle),
        markup = customer and (tonumber(result.markup) or 0) or tonumber(shop.settings and shop.settings.tuningMarkup) or 0,
        performance = customer and result.performance == true or nil,  -- customer: performance parts allowed
        order = type(result.order) == "table" and result.order or nil,  -- pending customer order of this vehicle
        maxDistance = maxDistance,
        confirmed = confirmed,
        paint = paint,
        isBike = IsThisModelABike(model),
        isOpenWheel = GetVehicleClass(vehicle) == 22,
        isEv = Utils.IsElectricModel(model),
        center = (min + max) / 2,
        half = half,
        scale = Utils.Clamp(math.max(half.x, half.y) / 2.4, 0.45, 2.5),
        engineOn = GetIsVehicleEngineRunning(vehicle),
        lights = false,
        radarHidden = IsRadarHidden(),
    }
    local s = Session

    local data = buildData()
    if #data.categories == 0 then
        Session = nil
        TriggerSecureEvent(closeEvent, true)
        return Core.Notify(locale("tuning_no_categories"), "error")
    end

    if not IsEntityPositionFrozen(vehicle) then
        FreezeEntityPosition(vehicle, true)
        s.frozen = true
    end
    -- customer catalog: nobody gets in while the preview is on the vehicle (lock status restored on cleanup)
    if customer then
        s.doorLock = GetVehicleDoorLockStatus(vehicle)
        SetVehicleDoorsLocked(vehicle, 2)
    end
    TaskTurnPedToFaceEntity(cache.ped, vehicle, 800)
    Wait(800)
    if Session ~= s then return end

    s.prop = playAnim(Config.Tuning.Animations.idle)
    DisplayRadar(false)
    createCamera()
    data.mode = s.mode
    data.shop = shop and shop.name or result.shopName
    -- customer: his pending order is restored, mechanic: the order is the cart (priority over the draft)
    data.order = s.order
    if not customer then
        data.draft = getDraft(s.plate)
        data.approvalEnabled = approvalEnabled()
        data.approvalTimeout = tonumber(CatalogCfg.approvalTimeout) or 60
    end
    Core.Nui.Open("tuning", data)
    startThreads(s.id)
    startHeartbeat(s)
end

-- Removes duplicates, invalid values and not changed values. Returns list { entry, value } or nil, message
local function prepareChanges(list)
    local s = Session
    if type(list) ~= "table" then return nil, locale("tuning_nothing_to_confirm") end
    local byKey, order = {}, {}
    for _, change in ipairs(list) do
        local item = type(change) == "table" and type(change.key) == "string" and s.index[change.key] or nil
        if not item then
            return nil, locale("tuning_invalid", type(change) == "table" and tostring(change.key):sub(1, 32) or "?")
        end
        local value = normalizeValue(item, change.value)
        if value == nil then
            return nil, locale("tuning_invalid", catLabel(item.entry))
        end
        if not byKey[item.entry.key] then
            order[#order + 1] = item.entry.key
        end
        byKey[item.entry.key] = { entry = item.entry, value = value }
    end

    -- only one rim set can be installed, keep the last previewed one
    local wheelKeys = {}
    for _, key in ipairs(order) do
        if byKey[key].entry.type == "wheels" then
            wheelKeys[#wheelKeys + 1] = key
        end
    end
    if #wheelKeys > 1 then
        local keep = byKey[s.wheelKey] and s.wheelKey or wheelKeys[#wheelKeys]
        for _, key in ipairs(wheelKeys) do
            if key ~= keep then byKey[key] = nil end
        end
    end

    local changes = {}
    for _, key in ipairs(order) do
        local change = byKey[key]
        if change and not sameValue(change.value, readValue(change.entry, s.confirmed)) then
            changes[#changes + 1] = change
        end
    end
    return changes
end

-- Applies changes on the vehicle (it must show exactly what is being paid) and sends them to the server.
-- Success: confirmed state updated. Failure: changes reverted.
-- Returns { ok, message?, total?, installed = { entries } }
local function sendConfirm(changes)
    local s = Session
    local vehicle = s.vehicle
    if not DoesEntityExist(vehicle) then
        return { ok = false, message = locale("no_vehicle") }
    end
    if not NetworkHasControlOfEntity(vehicle) and not Core.RequestControl(vehicle, 1500) then
        return { ok = false, message = locale("no_control") }
    end

    for _, change in ipairs(changes) do
        applyValue(vehicle, change.entry, change.value)
    end
    local props = lib.getVehicleProperties(vehicle)
    local payload = {}
    for i, change in ipairs(changes) do
        payload[i] = { key = change.entry.key, value = change.value }
    end

    s.awaiting = true
    local ok, result = pcall(lib.callback.await, "pls_mechanic:server:tuning:confirm", false, s.netId, payload, props)
    s.awaiting = false
    if not ok then result = nil end
    if Session ~= s then
        return { ok = false, message = locale("tuning_session_expired") }
    end
    if type(result) ~= "table" or not result.ok then
        for _, change in ipairs(changes) do
            revertEntry(change.entry)
        end
        return { ok = false, message = type(result) == "table" and result.message or locale("tuning_failed") }
    end

    local applied = {}
    for _, key in ipairs(result.applied or {}) do
        applied[key] = true
    end
    local installed = {}
    for _, change in ipairs(changes) do
        if applied[change.entry.key] then
            writeValue(change.entry, s.confirmed, change.value)
            installed[#installed + 1] = change.entry
        end
    end
    return { ok = true, total = tonumber(result.total) or 0, installed = installed }
end

-- Instant confirmation inside the menu (Config.Tuning.Install.enabled = false)
local function confirmChanges(changes)
    local s = Session
    local result = sendConfirm(changes)
    if Session ~= s then
        return result
    end
    if not result.ok then
        pushUpdate()
        return result
    end

    playWork(result.installed)
    pushUpdate()

    local total = result.total
    local message = total > 0 and locale("tuning_confirmed", Config.Currency..Utils.FormatMoney(total)) or locale("tuning_confirmed_free")
    Core.Notify(message, "success")
    return { ok = true, total = total, message = message }
end

-- Customer order on the vehicle: changes outside of it are approved by the customer first (quote on his screen),
-- the server refuses not approved ones. Without an order the server approves at once. Returns ok, message
local function requestApproval(s, changes)
    if not approvalEnabled() then return true end
    local ordered = {}
    for _, change in ipairs(type(s.order) == "table" and type(s.order.changes) == "table" and s.order.changes or {}) do
        if type(change) == "table" and type(change.key) == "string" then
            ordered[change.key] = change.value
        end
    end
    local payload, waiting = {}, false
    for i, change in ipairs(changes) do
        payload[i] = { key = change.entry.key, value = change.value }
        local value = ordered[change.entry.key]
        if s.order and (value == nil or not sameValue(value, change.value)) then
            waiting = true
        end
    end

    -- extra changes: the menu shows the waiting state until the customer answers (Catalog.approvalTimeout).
    -- The server can ask the customer without an order known here (finished / cancelled order): waiting after a moment
    local pending = true
    if waiting then
        Core.Nui.Update("tuning", { approvalState = "waiting" })
    else
        SetTimeout(750, function()
            if pending and Session == s then
                waiting = true
                Core.Nui.Update("tuning", { approvalState = "waiting" })
            end
        end)
    end
    local started = GetGameTimer()
    local ok, result = pcall(lib.callback.await, "pls_mechanic:server:tuning:approve", false, s.netId, payload)
    pending = false
    if waiting then
        Core.Nui.Update("tuning", { approvalState = false })
    end
    if Session ~= s then
        return false, locale("tuning_session_expired")
    end
    if not ok or type(result) ~= "table" or not result.ok then
        local message = ok and type(result) == "table" and result.message or locale("tuning_failed")
        -- long wait: the NUI request may be timed out already, the mechanic gets the answer as a notification too
        if GetGameTimer() - started > 15000 then
            Core.Notify(message, "error")
        end
        return false, message
    end
    return true
end

--[[
  _____           _        _ _       _   _
 |_   _|         | |      | | |     | | (_)
   | |  _ __  ___| |_ __ _| | | __ _| |_ _  ___  _ __
   | | | '_ \/ __| __/ _` | | |/ _` | __| |/ _ \| '_ \
  _| |_| | | \__ \ || (_| | | | (_| | |_| | (_) | | | |
 |_____|_| |_|___/\__\__,_|_|_|\__,_|\__|_|\___/|_| |_|

 Confirmed cart is installed step by step (NUI overlay "workflow", mode "tuning").
 Step: server "begin" (timer) -> scene (take the part, walk, open, work phases, calibration)
       -> server confirmation of this one change -> part appears on the vehicle -> test -> tidy up.
 Not installed changes stay in the saved cart (Drafts) and are restored when the menu opens again.
 Parts fetching (Config.Fetch, client/fetch.lua): parts don't have to be carried at the start, a step without its
 part / tool waits (Fetch.Wait) until the mechanic brings it from the storage and uses "Continue tuning" on the vehicle.
]]--

local InstallCfg = Config.Tuning.Install or {}
local WheelSpots = { wheel_lf = 0, wheel_rf = 1, wheel_lr = 4, wheel_rr = 5 }
local CamSpots = {
    default = "left", front = "front", hood = "hood", rear = "rear", trunk = "trunk", side = "left", side_right = "right",
    wheel = "wheel_lf", wheel_rear = "wheel_lr", interior = "driver", top = "top", under = "under",
}
local DEFAULT_SCENE = { work = { { spot = "left", phases = { { label = "tuning_ph_fit_part", share = 1.0, anim = "work" } } } } }

local CancelKeybind = lib.addKeybind({
    name = "pls_mechanic_cancel_tuning",
    description = locale("tuning_keybind_cancel"),
    defaultKey = Config.Keys.cancel,
    disabled = true,
    onPressed = function()
        Tuning.CancelInstall()
    end,
})

local function installEnabled()
    return InstallCfg.enabled == true and Anim ~= nil
end

local function getCancelKey()
    local ok, key = pcall(function() return CancelKeybind:getCurrentKey() end)
    if ok and type(key) == "string" and key ~= "" then return key end
    return Config.Keys.cancel
end

local function isCancelled()
    return Install == nil or Install.cancelled
end

-- Parts fetching (client/fetch.lua), the installation works without it (all parts checked at the start)
local function fetchEnabled()
    return Fetch ~= nil and Fetch.Enabled ~= nil and Fetch.Enabled() == true
end

-- Installation waits for parts of the current step (the mechanic is on the way to the storage)
local function fetchWaiting()
    return fetchEnabled() and Fetch.IsWaiting ~= nil and Fetch.IsWaiting("tuning") == true
end

-- reason = locale key shown in the overlay + notify (nil = cancelled by the mechanic)
local function cancelInstall(reason)
    local inst = Install
    if not inst or inst.cancelled or inst.finished then return end
    inst.cancelled = true
    inst.reason = reason or nil
    CancelKeybind:disable(true)
    -- waiting for parts ends at once (blips, carried box)
    if fetchWaiting() and Fetch.Cancel then
        pcall(Fetch.Cancel)
    end
    -- stops the running phase / walk / put down of the animation library at once (props, anim, sounds, particles)
    if Anim and Anim.Cleanup then
        pcall(Anim.Cleanup)
    elseif lib.progressActive() then
        lib.cancelProgress()
    end
end

local function playSoundPreset(key)
    local sound = InstallCfg.Sounds and InstallCfg.Sounds[key]
    if type(sound) == "table" and sound.name then
        PlaySoundFrontend(-1, sound.name, sound.set, true)
    end
end

local function installData()
    local inst = Install
    local steps = {}
    for i, step in ipairs(inst.steps) do
        steps[i] = {
            id = i,
            kind = "tuning",
            key = step.entry.key,
            label = step.label,
            status = step.status,
            message = step.message,
            phase = step.status == "active" and step.phase or nil,
        }
    end
    return {
        mode = "tuning",
        plate = inst.plate,
        cancelKey = getCancelKey(),
        cancelHint = locale("tuning_cancel_hint"),
        current = inst.current,
        steps = steps,
        -- missing parts of the waiting step (whole field every update, nil = not waiting)
        waiting = fetchWaiting() and Fetch.GetOverlay and Fetch.GetOverlay() or nil,
    }
end

local function updateOverlay()
    if Install then
        Core.Nui.Update("workflow", installData())
    end
end

local function permissionReason(shopId)
    if Config.RequireDuty and not Core.IsIllegalShop(shopId) and Core.GetDutyShopId() ~= shopId then
        return locale("not_on_duty")
    end
    return locale("no_permission")
end

--[[ Drafts: the whole cart is saved when the installation starts, installed changes are removed one by one ]]--

local function saveInstallDraft(plate, changes)
    local list = {}
    for i, change in ipairs(changes) do
        list[i] = { key = change.entry.key, value = Utils.DeepCopy(change.value) }
    end
    Drafts[plate] = #list > 0 and { changes = list, time = GetGameTimer() } or nil
end

local function removeFromDraft(plate, key)
    local draft = Drafts[plate]
    if not draft then return end
    for i = #draft.changes, 1, -1 do
        if draft.changes[i].key == key then
            table.remove(draft.changes, i)
        end
    end
    if #draft.changes == 0 then
        Drafts[plate] = nil
    end
end

--[[ Preflight + order ]]--

-- Everything the whole cart needs (same rules as the server). Returns ok, message with all problems,
-- info (Config.Fetch: parts brought from the workshop storage during the installation)
local function preflight(s, changes)
    local problems, seen = {}, {}
    local function addProblem(text)
        if not seen[text] then
            seen[text] = true
            problems[#problems + 1] = text
        end
    end
    if Repair and Repair.IsBusy and Repair.IsBusy() then
        addProblem(locale("tuning_repair_busy"))
    end

    local canPerformance = Core.HasPermission("tuning_performance", s.shopId)
    local canVisual = Core.HasPermission("tuning_visual", s.shopId)
    local needed, itemOrder, tools, toolOrder = {}, {}, {}, {}
    local final = Utils.DeepCopy(s.confirmed)
    for _, change in ipairs(changes) do
        local entry, value = change.entry, change.value
        if (entry.performance and not canPerformance) or (not entry.performance and not canVisual) then
            addProblem(locale("tuning_preflight_step", catLabel(entry), permissionReason(s.shopId)))
        end
        if entry.tool and not tools[entry.tool] then
            tools[entry.tool] = true
            toolOrder[#toolOrder + 1] = entry.tool
        end
        local item, count = requiredItem(entry, value)
        if item then
            if not needed[item] then itemOrder[#itemOrder + 1] = item end
            needed[item] = (needed[item] or 0) + count
        end
        writeValue(entry, final, value)
    end
    local requirementsOk, requirementMessage = checkRequirements(changes, final)
    if not requirementsOk then
        addProblem(requirementMessage)
    end

    -- parts fetching: missing parts / tools don't block, every step waits for its own parts. Blocks only when
    -- Config.Fetch.requireStock and a part / tool is neither in the inventory nor in the workshop storage
    if fetchEnabled() then
        local called, stockOk, problem, info = pcall(Fetch.CheckStart, s.shopId, needed, toolOrder)
        if not called then
            print("[pls_mechanic] tuning parts check error: "..tostring(stockOk))
        elseif stockOk == false then
            table.insert(problems, 1, type(problem) == "string" and problem or locale("tuning_failed"))
        end
        if #problems > 0 then
            return false, table.concat(problems, " • ")
        end
        return true, nil, type(info) == "string" and info or nil
    end

    local missingItems = {}
    for _, key in ipairs(itemOrder) do
        local have = Core.CountItem(key)
        if have < needed[key] then
            missingItems[#missingItems + 1] = ("%dx %s"):format(needed[key] - have, Core.GetItemLabel(Utils.Item(key)))
        end
    end
    local missingTools = {}
    for _, key in ipairs(toolOrder) do
        if Core.CountTool(key) < 1 then
            missingTools[#missingTools + 1] = Core.GetItemLabel(Utils.Item(key))
        end
    end
    if #missingItems > 0 then
        table.insert(problems, 1, locale("missing_items", table.concat(missingItems, ", ")))
    end
    if #missingTools > 0 then
        table.insert(problems, 1, locale("missing_tool", table.concat(missingTools, ", ")))
    end
    if #problems > 0 then
        return false, table.concat(problems, " • ")
    end
    return true
end

local function installRank(entry)
    local groups = InstallCfg.groupOrder or {}
    local groupIndex = #groups + 1
    for i, group in ipairs(groups) do
        if group == entry.group then
            groupIndex = i
            break
        end
    end
    return groupIndex * 100000 + (RequiredCategories[entry.key] and 0 or 10000) + (entry.order or 0)
end

-- Group order, then dependencies: the next step is always the first one the server accepts after the previous steps
-- (transmission before engine stage 3+, engine downgraded before the transmission, xenon before xenon colour...)
local function orderChanges(s, changes)
    local remaining = {}
    for i, change in ipairs(changes) do
        remaining[i] = change
    end
    table.sort(remaining, function(a, b) return installRank(a.entry) < installRank(b.entry) end)
    local state = Utils.DeepCopy(s.confirmed)
    local ordered = {}
    while #remaining > 0 do
        local pick = 1
        for i, change in ipairs(remaining) do
            local test = Utils.DeepCopy(state)
            writeValue(change.entry, test, change.value)
            if checkRequirements({ change }, test) then
                pick = i
                break
            end
        end
        local change = table.remove(remaining, pick)
        writeValue(change.entry, state, change.value)
        ordered[#ordered + 1] = change
    end
    return ordered
end

--[[ Durations (server/tuning.lua computes the same minimum) ]]--

local function workTime(entry, removal)
    local durations = InstallCfg.durations or {}
    local key = (entry.type == "rgb" or entry.palette == "xenon") and "settings" or entry.group
    local time = tonumber(durations[key]) or tonumber(durations.other) or 5000
    if removal then
        time = time * (InstallCfg.removalFactor or 1.0)
    end
    return math.floor(time)
end

local function needsCalibration(entry, removal)
    return not removal and entry.tool ~= nil and entry.tool == InstallCfg.calibrationTool and (InstallCfg.calibration or 0) > 0
end

local function shareSum(phases)
    local sum = 0
    for _, phase in ipairs(phases) do
        sum = sum + (phase.share or 1.0)
    end
    return sum > 0 and sum or 1.0
end

--[[ Scene data ]]--

local function sceneOf(entry)
    local scenes = InstallCfg.Scenes or {}
    local mapping = InstallCfg.CategoryScenes or {}
    local key = mapping[entry.key] or (entry.wheel and mapping.wheels) or nil
    if key and scenes[key] then
        return scenes[key]
    end
    -- generic scene at the spot of the camera preset of the category
    local generic = scenes.generic or DEFAULT_SCENE
    local preset = Config.Tuning.Cameras[entry.cam or "default"] or {}
    local first = generic.work and generic.work[1] or DEFAULT_SCENE.work[1]
    return {
        take = generic.take,
        part = generic.part,
        test = generic.test,
        work = { { spot = CamSpots[entry.cam or "default"] or "left", door = preset.door, phases = first.phases } },
    }
end

-- Prop for Anim: Install.Props entry (string = Config.Props / Config.Animations.Props key, table = own prop)
-- or directly a Config.Props / Config.Animations.Props key. false / nil = none
local function propOf(key)
    if not key then return nil end
    local prop = InstallCfg.Props and InstallCfg.Props[key]
    if prop ~= nil then return prop end
    if Config.Props[key] or (Config.Animations and Config.Animations.Props and Config.Animations.Props[key]) then
        return key
    end
    return nil
end

-- Anim for Anim.Phase + its preset table (prop, lying...). Install.Anims entry (string = Config.Animations.Anims key,
-- table = own anim), falls back to Config.Tuning.Animations
local function animOf(key)
    if not key then return nil, nil end
    local anim = InstallCfg.Anims and InstallCfg.Anims[key]
    if type(anim) == "string" then
        local preset = Config.Animations and Config.Animations.Anims and Config.Animations.Anims[anim]
        if preset then return anim, preset end
        anim = nil
    end
    if anim == nil then anim = Config.Tuning.Animations[key] end
    if type(anim) ~= "table" then return nil, nil end
    if anim.scenario then return { scenario = anim.scenario }, anim end
    local copy = {}
    for field, value in pairs(anim) do
        if field ~= "prop" then copy[field] = value end
    end
    return copy, anim
end

local function sameAnim(a, b)
    local _, first = animOf(a)
    local _, second = animOf(b)
    if not first or not second then return false end
    if first.scenario or second.scenario then return first.scenario == second.scenario end
    return first.dict == second.dict and first.clip == second.clip
end

local function isLying(animKey)
    local _, preset = animOf(animKey)
    return preset ~= nil and preset.lying == true
end

-- Install.Sounds preset (string = Config.Animations.Sounds preset of the animation library)
local function soundPreset(key)
    local preset = key and InstallCfg.Sounds and InstallCfg.Sounds[key]
    if type(preset) == "string" then
        preset = Config.Animations and Config.Animations.Sounds and Config.Animations.Sounds[preset]
    end
    return type(preset) == "table" and preset.name and preset or nil
end

local function soundOf(key, ctx)
    local preset = soundPreset(key)
    if not preset or (preset.combustion and ctx.session.isEv) then return nil end
    local sound = {}
    for field, value in pairs(preset) do
        sound[field] = value
    end
    sound.onVehicle, sound.combustion = nil, nil
    sound.entity = preset.onVehicle and ctx.vehicle or nil
    return sound
end

-- Particle for Anim.Phase. onVehicle = on the vehicle at the work point of the spot,
-- otherwise entity of the preset ("prop" = hand prop, "ped" / nil = mechanic)
local function particleOf(key, ctx, position)
    local preset = key and InstallCfg.Particles and InstallCfg.Particles[key]
    if not preset then return nil end
    local particle = {
        asset = preset.asset,
        name = preset.name,
        entity = preset.entity,
        bone = preset.bone,
        offset = preset.offset,
        rot = preset.rot,
        scale = preset.scale,
        looped = preset.looped,
        interval = preset.interval,
        length = preset.length,
    }
    if preset.onVehicle then
        local work = position and position.work or vector3(0.0, 0.0, 0.0)
        particle.entity = ctx.vehicle
        particle.bone = nil
        particle.offset = preset.offset and (work + preset.offset) or work
    end
    return particle
end

-- World position + heading of a work spot, the point on the vehicle (local offset) where the work happens and the
-- heading facing the vehicle. lying = lying anim: closer to the body with the back to the vehicle (head under it,
-- Config.Animations.Settings.lie). nil when the spot doesn't exist on this model (missing wheel)
local function getSpot(vehicle, spot, lying)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local lie = lying and Config.Animations and Config.Animations.Settings and Config.Animations.Settings.lie or nil
    local gap = lying and (lie and lie.distance or 0.35) or (InstallCfg.spotGap or 0.65)
    local midZ = (min.z + max.z) * 0.5
    local x, y, face, work
    if WheelSpots[spot] then
        local bone = GetEntityBoneIndexByName(vehicle, Utils.WheelBones[WheelSpots[spot]])
        if bone == -1 then return nil end
        local world = GetWorldPositionOfEntityBone(vehicle, bone)
        local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
        local side = offset.x < 0 and -1 or 1
        if lying then
            x = side < 0 and (min.x - gap) or (max.x + gap)
        else
            x = offset.x + side * 0.9
        end
        y, face = offset.y, side < 0 and -90.0 or 90.0
        work = vector3(offset.x, offset.y, offset.z)
    elseif spot == "front" or spot == "hood" then
        x, y, face = 0.0, max.y + gap, 180.0
        work = spot == "hood" and vector3(0.0, max.y - 0.6, max.z * 0.5) or vector3(0.0, max.y - 0.1, midZ)
    elseif spot == "rear" or spot == "trunk" then
        x, y, face = 0.0, min.y - gap, 0.0
        work = vector3(0.0, min.y + 0.1, midZ)
    elseif spot == "left" or spot == "top" or spot == "under" then
        x, y, face = min.x - gap, 0.0, -90.0
        work = vector3(min.x + 0.1, 0.0, spot == "under" and min.z + 0.1 or midZ)
    elseif spot == "right" then
        x, y, face = max.x + gap, 0.0, 90.0
        work = vector3(max.x - 0.1, 0.0, midZ)
    elseif spot == "left_front" or spot == "left_rear" then
        y = spot == "left_front" and max.y * 0.55 or min.y * 0.55
        x, face = min.x - gap, -90.0
        work = vector3(min.x + 0.1, y, midZ)
    elseif spot == "right_front" or spot == "right_rear" then
        y = spot == "right_front" and max.y * 0.55 or min.y * 0.55
        x, face = max.x + gap, 90.0
        work = vector3(max.x - 0.1, y, midZ)
    elseif spot == "driver" then
        y = 0.2
        local bone = GetEntityBoneIndexByName(vehicle, "seat_dside_f")
        if bone ~= -1 then
            local world = GetWorldPositionOfEntityBone(vehicle, bone)
            y = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z).y
        end
        x, face = min.x - (lying and gap or 0.45), -90.0
        work = vector3(min.x + 0.4, y, midZ)
    else
        return nil
    end
    local coords = GetOffsetFromEntityInWorldCoords(vehicle, x, y, 0.0)
    local facing = (GetEntityHeading(vehicle) + face) % 360.0
    local heading = lying and (facing + (lie and lie.heading or 180.0)) % 360.0 or facing
    return coords, heading, work, facing
end

-- Work positions of the step with timed phases
local function resolvePositions(ctx)
    local scene, removal = ctx.scene, ctx.removal
    local source = scene.work or DEFAULT_SCENE.work
    if removal then
        if scene.removal then
            source = scene.removal
        else
            -- default removal phases at the first spot, in the pose of the scene (kneeling at the wheel, lying under...)
            local first = source[1] or DEFAULT_SCENE.work[1]
            local pose = first.phases and first.phases[1] and first.phases[1].anim
            local phases = {}
            for i, phase in ipairs(InstallCfg.RemovalPhases or DEFAULT_SCENE.work[1].phases) do
                phases[i] = { label = phase.label, share = phase.share, anim = pose or phase.anim, prop = phase.prop, prop2 = phase.prop2 }
            end
            source = { { spot = first.spot, door = first.door, phases = phases } }
        end
    end
    local positions, all = {}, {}
    for _, position in ipairs(source) do
        local phaseDefs = position.phases or {}
        local lying = phaseDefs[1] ~= nil and isLying(phaseDefs[1].anim)
        local coords, heading, work, facing = getSpot(ctx.vehicle, position.spot, lying)
        if coords then
            local resolved = { spot = position.spot, door = position.door, coords = coords, heading = heading, facing = facing, work = work, phases = {} }
            for _, phase in ipairs(phaseDefs) do
                all[#all + 1] = phase
                resolved.phases[#resolved.phases + 1] = { def = phase }
            end
            positions[#positions + 1] = resolved
        end
    end
    if #positions == 0 then
        local coords, heading, work, facing = getSpot(ctx.vehicle, "left")
        local phases = {}
        for _, phase in ipairs(DEFAULT_SCENE.work[1].phases) do
            all[#all + 1] = phase
            phases[#phases + 1] = { def = phase }
        end
        positions[1] = { spot = "left", coords = coords, heading = heading, facing = facing, work = work, phases = phases }
    end
    local total, sum = workTime(ctx.entry, removal), shareSum(all)
    for _, position in ipairs(positions) do
        for _, phase in ipairs(position.phases) do
            phase.duration = math.max(500, math.floor(total * (phase.def.share or 1.0) / sum))
        end
    end
    return positions, #all
end

--[[ Scene actions ]]--

local function setEngine(ctx, on)
    local vehicle = ctx.vehicle
    if not DoesEntityExist(vehicle) then return end
    if on then
        ctx.engine = true
        SetVehicleEngineOn(vehicle, true, true, false)
    elseif ctx.engine then
        ctx.engine = false
        if not ctx.session.engineOn then
            SetVehicleEngineOn(vehicle, false, true, false)
        end
    end
end

local function setTestLights(ctx, on)
    local vehicle = ctx.vehicle
    if not DoesEntityExist(vehicle) then return end
    if on then
        ctx.lights = true
        SetVehicleLights(vehicle, 2)
    elseif ctx.lights then
        ctx.lights = false
        SetVehicleLights(vehicle, 0)
    end
end

-- Vehicle back to the state before the scene (engine, lights), no waits (used on resource stop too)
local function restoreVehicle(ctx)
    setTestLights(ctx, false)
    setEngine(ctx, false)
end

-- Overlay shows no work phase while the mechanic walks
local function clearPhase(ctx)
    if ctx.step.phase then
        ctx.step.phase = nil
        updateOverlay()
    end
end

-- Walks around the vehicle (never through it), cancel stops the walk immediately. True when the spot was reached
local function walkTo(ctx, coords, heading)
    if isCancelled() then return false end
    clearPhase(ctx)
    local distance = #(GetEntityCoords(cache.ped) - coords)
    local timeout = math.floor(math.min(15000, 3000 + distance * 1500))
    local ok, reached = pcall(Anim.WalkAround, ctx.vehicle, coords, heading, timeout, isCancelled)
    if not ok then
        print("[pls_mechanic] tuning walk error: "..tostring(reached))
        return false
    end
    if isCancelled() then return false end
    return reached == true or #(GetEntityCoords(cache.ped).xy - coords.xy) <= 2.0
end

local function openDoor(ctx, door)
    if not door or ctx.opened[door] or not DoesEntityExist(ctx.vehicle) then return end
    local ok, opened = pcall(Anim.OpenDoor, ctx.vehicle, door)
    if ok and opened then
        ctx.opened[door] = true
    end
end

local function closeDoors(ctx)
    if DoesEntityExist(ctx.vehicle) then
        for door in pairs(ctx.opened) do
            pcall(Anim.CloseDoor, ctx.vehicle, door)
        end
    end
    ctx.opened = {}
end

local function stopCarry(ctx)
    if ctx.carry then
        pcall(Anim.StopCarry, ctx.carry)
        ctx.carry = nil
    end
end

local function startCarry(ctx, key)
    local prop = propOf(key)
    if not prop or InstallCfg.carry == false then return end
    stopCarry(ctx)
    local ok, handle = pcall(Anim.Carry, prop)
    if ok and handle then
        ctx.carry = handle
    end
end

-- Hand prop of a phase (own prop, or prop of the anim preset)
local function phaseProp(def)
    if not def then return nil end
    if def.prop ~= nil then return def.prop end
    local _, preset = animOf(def.anim)
    return preset and preset.prop or nil
end

-- One work phase (overlay update + Anim.Phase). hooks = { onStart, onEnd }, nextDef = following phase at the
-- same spot (same anim / props stay on, no stand up / lie down between the phases)
local function runPhase(ctx, def, duration, position, hooks, nextDef)
    if isCancelled() then return false end
    local step = ctx.step
    ctx.phaseIndex = ctx.phaseIndex + 1
    local label = locale(def.label)
    step.phase = { label = label, index = math.min(ctx.phaseIndex, ctx.phaseCount), count = ctx.phaseCount, duration = duration }
    updateOverlay()

    local anim = animOf(def.anim)
    local prop = phaseProp(def)
    local sound = def.sound
    if sound == nil and type(prop) == "string" and InstallCfg.PropSounds then
        sound = InstallCfg.PropSounds[prop]
    end

    local ok, completed = pcall(Anim.Phase, {
        label = label,
        duration = duration,
        anim = anim,
        prop = propOf(prop),
        prop2 = propOf(def.prop2),
        sound = soundOf(sound, ctx),
        particle = particleOf(def.particle, ctx, position),
        cancel = isCancelled,
        disable = { move = true, car = true, combat = true },
        vehicle = ctx.vehicle,
        noCollision = ctx.vehicle,
        keepAnim = nextDef ~= nil and def.anim ~= nil and sameAnim(def.anim, nextDef.anim),
        keepProp = nextDef ~= nil and prop ~= nil and prop == phaseProp(nextDef),
        keepProp2 = nextDef ~= nil and def.prop2 ~= nil and def.prop2 == nextDef.prop2,
        onStart = hooks and hooks.onStart or nil,
        onEnd = hooks and hooks.onEnd or nil,
    })
    if not ok then
        print("[pls_mechanic] tuning phase error: "..tostring(completed))
        ctx.error = true
        return false
    end
    return completed == true and not isCancelled()
end

local function runCalibration(ctx, position)
    local phases = InstallCfg.CalibrationPhases or {}
    local total, sum = InstallCfg.calibration or 0, shareSum(phases)
    for i, def in ipairs(phases) do
        local duration = math.max(500, math.floor(total * (def.share or 1.0) / sum))
        local hooks = nil
        if i == #phases then
            -- ECU calibration with the engine running
            hooks = {
                onStart = function() setEngine(ctx, true) end,
                onEnd = function(completed)
                    setEngine(ctx, false)
                    if completed then playSoundPreset("calibrated") end
                end,
            }
        end
        if not runPhase(ctx, def, duration, position, hooks, phases[i + 1]) then return false end
    end
    return true
end

local function testHooks(ctx, kind)
    if kind == "rev" or kind == "neon" then
        return {
            onStart = function() setEngine(ctx, true) end,
            onEnd = function() setEngine(ctx, false) end,
        }
    elseif kind == "lights" then
        return {
            onStart = function()
                setEngine(ctx, true)
                setTestLights(ctx, true)
            end,
            onEnd = function()
                setTestLights(ctx, false)
                setEngine(ctx, false)
            end,
        }
    elseif kind == "horn" then
        return {
            onStart = function()
                if DoesEntityExist(ctx.vehicle) then
                    StartVehicleHorn(ctx.vehicle, math.min(InstallCfg.test or 2500, 2000), joaat("HELDDOWN"), false)
                end
            end,
        }
    end
    return nil
end

local function runTest(ctx, kind)
    local test = InstallCfg.Tests and InstallCfg.Tests[kind]
    if not test or isCancelled() then return end
    local position = ctx.position
    if test.spot then
        local coords, heading, work = getSpot(ctx.vehicle, test.spot, isLying(test.anim))
        if coords then
            if not walkTo(ctx, coords, heading) then return end
            openDoor(ctx, test.door)
            position = { work = work }
        end
    end
    runPhase(ctx, test, InstallCfg.test or 2500, position, testHooks(ctx, kind))
end

-- Old part on the ground next to the vehicle (removed at the end of the installation)
local function putDownLeftover(ctx, key)
    local prop = propOf(key)
    if not prop or InstallCfg.leftovers == false or isCancelled() then return end
    clearPhase(ctx)
    local pedCoords = GetEntityCoords(cache.ped)
    local away = pedCoords - GetEntityCoords(ctx.vehicle)
    away = vector3(away.x, away.y, 0.0)
    local length = #away
    local coords = length > 0.01 and (pedCoords + away / length * 0.9) or nil
    local ok, object = pcall(Anim.PutDown, prop, coords)
    if ok and object and DoesEntityExist(object) then
        ctx.inst.leftovers[#ctx.inst.leftovers + 1] = object
    end
end

-- Parts crate carried beside the first spot, put down and unpacked. False when cancelled / not reachable
local function unpackCrate(ctx, first)
    startCarry(ctx, "crate")
    local rad = math.rad(first.facing)
    local staging = first.coords + vector3(math.cos(rad), math.sin(rad), 0.0) * 0.9
    if not walkTo(ctx, staging, (first.facing + 180.0) % 360.0) then
        return false
    end
    local ok, crate
    if ctx.carry then
        ok, crate = pcall(Anim.PutDown)
        ctx.carry = nil
    else
        ok, crate = pcall(Anim.PutDown, propOf("crate"))
    end
    if ok and crate and DoesEntityExist(crate) then
        ctx.crate = crate
        ctx.staging = staging
        pcall(Anim.Face, crate)
    end
    return true
end

-- Empty parts crate is taken away (back at the crate first, around the vehicle)
local function pickUpCrate(ctx)
    local crate = ctx.crate
    if not crate or not DoesEntityExist(crate) or isCancelled() then return end
    local crateCoords = GetEntityCoords(crate)
    if ctx.staging and #(GetEntityCoords(cache.ped).xy - crateCoords.xy) > 1.3 then
        local heading = GetHeadingFromVector_2d(crateCoords.x - ctx.staging.x, crateCoords.y - ctx.staging.y)
        if not walkTo(ctx, ctx.staging, heading) then return end
    end
    clearPhase(ctx)
    pcall(Anim.PickUp, crate)
    if not DoesEntityExist(crate) then
        ctx.crate = nil
    end
end

-- Scene props, anims, doors, engine and lights of the step are cleaned (always, also after cancel / failure)
local function cleanupScene(ctx)
    stopCarry(ctx)
    if ctx.crate then
        if DoesEntityExist(ctx.crate) then
            pcall(Anim.DeleteProp, ctx.crate)
        end
        ctx.crate = nil
    end
    pcall(Anim.Cleanup)
    restoreVehicle(ctx)
    closeDoors(ctx)
end

--[[ Step ]]--

local function waitCooldown(inst)
    local remaining = inst.lastConfirm + (Config.Tuning.Cooldown or 0) + 150 - GetGameTimer()
    if remaining > 0 then
        Wait(remaining)
    end
end

local function interrupted(ctx)
    if ctx.error then
        return "failed", locale("tuning_failed")
    end
    return "cancelled"
end

-- Fetch.Wait result -> cancel reason (locale key), "cancelled" = cancel key / target (no reason)
local WaitReasons = { timeout = "fetch_timeout", too_far = "fetch_too_far", no_vehicle = "no_vehicle", failed = "tuning_failed" }

-- Config.Fetch: part / tool of the step is not in the inventory -> the installation waits until the mechanic brings it
-- from the workshop storage and uses "Continue tuning" on the vehicle. False = the installation was cancelled
-- (timeout, too far, no vehicle, cancel key / target), remaining steps are skipped and stay in the saved cart
local function waitForParts(ctx)
    if not fetchEnabled() then return true end
    local inst, step = ctx.inst, ctx.step
    local items, tools = {}, {}
    if not step.removal then
        local item, count = requiredItem(step.entry, step.value)
        if item then
            items[1] = { item = item, count = count }
        end
    end
    if step.entry.tool then
        tools[1] = step.entry.tool
    end
    local counted, missing = pcall(Fetch.Missing, items, tools)
    if not counted then
        -- the server checks the items of the step anyway
        print("[pls_mechanic] tuning parts count error: "..tostring(missing))
        return true
    end
    if type(missing) ~= "table" or #missing == 0 then return true end

    step.status = "waiting"
    step.phase = nil
    updateOverlay()
    local ok, result = pcall(Fetch.Wait, {
        owner = "tuning",
        vehicle = ctx.vehicle,
        netId = inst.netId,
        shopId = inst.session.shopId,
        label = step.label,
        items = items,
        tools = tools,
        isCancelled = isCancelled,
        onUpdate = updateOverlay,
    })
    if not ok then
        print("[pls_mechanic] tuning parts wait error: "..tostring(result))
        result = "failed"
    end
    if result ~= "ready" then
        cancelInstall(WaitReasons[result])
        return false
    end
    if isCancelled() then return false end

    step.status = "active"
    updateOverlay()
    -- the mechanic was away: the vehicle may have changed its network owner (freeze is local to the owner)
    local vehicle = ctx.vehicle
    if DoesEntityExist(vehicle) then
        if not NetworkHasControlOfEntity(vehicle) then
            Core.RequestControl(vehicle, 1500)
        end
        if ctx.session.frozen and not IsEntityPositionFrozen(vehicle) and NetworkHasControlOfEntity(vehicle) then
            FreezeEntityPosition(vehicle, true)
        end
    end
    return true
end

-- Returns "done" / "failed" / "cancelled", message
local function performStep(ctx)
    local inst, step, vehicle = ctx.inst, ctx.step, ctx.vehicle
    local entry, value, removal = step.entry, step.value, step.removal
    if not DoesEntityExist(vehicle) then return "failed", locale("no_vehicle") end

    -- parts of the step (Config.Fetch), before "begin": the server work time is measured from the real work
    if not waitForParts(ctx) then return "cancelled" end

    local positions, phaseCount = resolvePositions(ctx)
    local take = not removal and InstallCfg.carry ~= false and ctx.scene.take or nil
    local calibration = needsCalibration(entry, removal)
    local test = not removal and ctx.scene.test and InstallCfg.Tests and InstallCfg.Tests[ctx.scene.test] and ctx.scene.test or nil
    ctx.phaseCount = phaseCount + (take == "crate" and 1 or 0) + (calibration and #(InstallCfg.CalibrationPhases or {}) or 0) + (test and 1 or 0)

    -- server timer of this step (minimal work time)
    local ok, begin = pcall(lib.callback.await, "pls_mechanic:server:tuning:begin", false, inst.netId, entry.key, value)
    if not ok or type(begin) ~= "table" or not begin.ok then
        return "failed", ok and type(begin) == "table" and begin.message or locale("tuning_failed")
    end
    if isCancelled() then return "cancelled" end

    -- take the part: parts crate unpacked beside the first spot / part carried to the vehicle
    local first = positions[1]
    if take == "crate" then
        if not unpackCrate(ctx, first) then
            if isCancelled() then return "cancelled" end
            return "failed", locale("tuning_cannot_reach")
        end
        if not runPhase(ctx, { label = "tuning_ph_unbox", anim = "unbox", prop = false }, InstallCfg.unbox or 2000) then
            return interrupted(ctx)
        end
    end
    if take and ctx.scene.part then
        startCarry(ctx, ctx.scene.part)
    end

    -- work positions
    for _, position in ipairs(positions) do
        ctx.position = position
        if not walkTo(ctx, position.coords, position.heading) then
            if isCancelled() then return "cancelled" end
            return "failed", locale("tuning_cannot_reach")
        end
        stopCarry(ctx)
        openDoor(ctx, position.door)
        for i, phase in ipairs(position.phases) do
            local nextPhase = position.phases[i + 1]
            if not runPhase(ctx, phase.def, phase.duration, position, nil, nextPhase and nextPhase.def) then
                return interrupted(ctx)
            end
        end
    end

    -- laptop calibration (engine, transmission, turbo)
    if calibration and not runCalibration(ctx, ctx.position) then
        return interrupted(ctx)
    end

    -- server confirmation of this change, the part appears on the vehicle
    waitCooldown(inst)
    if isCancelled() then return "cancelled" end
    local result = sendConfirm({ { entry = entry, value = value } })
    inst.lastConfirm = GetGameTimer()
    if not result.ok then
        return "failed", result.message
    end
    inst.total = inst.total + (result.total or 0)
    removeFromDraft(inst.plate, entry.key)
    playSoundPreset("installed")

    -- installed: removed part on the ground / test, tidy up (cancel from here on keeps the step done)
    if removal and ctx.scene.part then
        putDownLeftover(ctx, ctx.scene.part)
    end
    if test then
        runTest(ctx, test)
    end
    restoreVehicle(ctx)
    if not isCancelled() then
        closeDoors(ctx)
        pickUpCrate(ctx)
    end
    local price = result.total or 0
    return "done", price > 0 and Config.Currency..Utils.FormatMoney(price) or nil
end

--[[ Runner ]]--

local function finishInstall()
    local inst = Install
    if not inst then return end
    local s = inst.session
    CancelKeybind:disable(true)
    inst.finished = true
    inst.current = nil

    local done = 0
    for _, step in ipairs(inst.steps) do
        if step.status == "done" then done = done + 1 end
    end
    updateOverlay()

    -- not installed changes stay in the saved cart
    local draft = Drafts[inst.plate]
    if draft then
        draft.time = GetGameTimer()
    end

    if inst.reason then
        Core.Notify(locale(inst.reason), "error")
    end
    if done > 0 then
        local count = #inst.steps
        local message = inst.total > 0
            and locale("tuning_install_done", done, count, Config.Currency..Utils.FormatMoney(inst.total))
            or locale("tuning_install_done_free", done, count)
        Core.Notify(message, done == count and "success" or "inform")
    end
    if inst.cancelled then
        Core.Notify(locale("tuning_install_cancelled"), "error")
    elseif done == 0 then
        Core.Notify(locale("tuning_install_nothing"), "error")
    end

    Wait(inst.cancelled and 1500 or (InstallCfg.resultTime or 4000))
    for _, object in ipairs(inst.leftovers) do
        if DoesEntityExist(object) then
            pcall(Anim.DeleteProp, object)
        end
    end
    inst.leftovers = {}
    if Install == inst then
        Install = nil
        Core.Nui.Close("workflow")
    end
    -- session ends normally: not confirmed state reverted, vehicle unfrozen, server session closed
    if Session == s then
        cleanup(true, false)
    end
    SetTimeout(2000, function()
        if IgnoreDrafts[inst.plate] == inst then
            IgnoreDrafts[inst.plate] = nil
        end
    end)
end

local function runSteps(inst)
    local s = inst.session
    for i, step in ipairs(inst.steps) do
        if inst.cancelled or Session ~= s or not DoesEntityExist(inst.vehicle) then
            step.status = "skipped"
        else
            inst.current = i
            step.status = "active"
            step.phase = nil
            updateOverlay()
            if not NetworkHasControlOfEntity(inst.vehicle) then
                Core.RequestControl(inst.vehicle, 1500)
            end
            local ctx = {
                inst = inst, session = s, step = step, vehicle = inst.vehicle, entry = step.entry, removal = step.removal,
                scene = sceneOf(step.entry), opened = {}, phaseIndex = 0, phaseCount = 1,
            }
            inst.ctx = ctx
            local ok, status, message = pcall(performStep, ctx)
            if not ok then
                print("[pls_mechanic] tuning install step error: "..tostring(status))
                status, message = "failed", locale("tuning_failed")
            end
            cleanupScene(ctx)
            inst.ctx = nil
            step.phase = nil
            if status == "cancelled" then
                inst.cancelled = true
                step.status = "skipped"
                step.message = inst.reason and locale(inst.reason) or locale("cancelled")
            else
                step.status = status
                step.message = message
                if status == "failed" then
                    playSoundPreset("failed")
                    Core.Notify(message or locale("tuning_failed"), "error")
                    -- let the mechanic read the result before the next step starts
                    updateOverlay()
                    Wait(1000)
                end
            end
        end
        updateOverlay()
    end
end

local function startInstallWatchdog(inst)
    CreateThread(function()
        while Install == inst and not inst.finished do
            local vehicle = inst.vehicle
            -- waiting for parts: the mechanic walks to the storage, Fetch has its own distance limit (Config.Fetch.maxDistance)
            local waiting = fetchWaiting()
            local reason = nil
            if not DoesEntityExist(vehicle) then
                reason = "no_vehicle"
            elseif IsEntityDead(cache.ped) then
                reason = false
            elseif not waiting and #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > (InstallCfg.maxDistance or 14.0) then
                reason = "too_far"
            elseif not waiting and not IsVehicleSeatFree(vehicle, -1) then
                reason = "tuning_vehicle_occupied"
            elseif Session ~= inst.session then
                reason = "tuning_session_expired"
            end
            if reason ~= nil then
                cancelInstall(reason or nil)
            elseif not NetworkHasControlOfEntity(vehicle) then
                NetworkRequestControlOfEntity(vehicle)
            end
            Wait(500)
        end
    end)
end

-- Menu closes, camera goes back to the mechanic, vehicle shows the confirmed state, steps run one by one
local function startInstall(s, changes)
    s.installing = true
    s.busy = true
    local ordered = orderChanges(s, changes)
    saveInstallDraft(s.plate, ordered)

    local inst = {
        session = s,
        vehicle = s.vehicle,
        netId = s.netId,
        plate = s.plate,
        steps = {},
        current = nil,
        cancelled = false,
        total = 0,
        lastConfirm = 0,
        leftovers = {},
    }
    for i, change in ipairs(ordered) do
        inst.steps[i] = {
            entry = change.entry,
            value = change.value,
            removal = isRemoval(change.entry, change.value),
            label = catLabel(change.entry)..": "..valueLabel(change.entry, change.value, s.vehicle),
            status = "pending",
        }
    end
    Install = inst
    IgnoreDrafts[s.plate] = inst

    CreateThread(function()
        local ok, err = pcall(function()
            Core.Nui.Close("tuning")
            stopAnim(s.prop)
            s.prop = nil
            Wait(0) -- camera thread ends (installing)
            destroyCamera(s.cam, true)
            s.cam = nil
            if not s.radarHidden then
                DisplayRadar(true)
            end
            if Session ~= s then return end

            -- parts appear one by one: vehicle back to the confirmed state
            if DoesEntityExist(s.vehicle) and (NetworkHasControlOfEntity(s.vehicle) or Core.RequestControl(s.vehicle, 1500)) then
                setDoor(nil)
                setLights(false)
                applyProps(s.vehicle, s.confirmed)
                for key in pairs(PAINT_KEYS) do
                    s.paint[key] = Utils.DeepCopy(s.confirmed[key])
                end
            end

            Core.Nui.Open("workflow", installData(), false)
            CancelKeybind:disable(false)
            startInstallWatchdog(inst)
            runSteps(inst)
        end)
        if not ok then
            print("[pls_mechanic] tuning installation error: "..tostring(err))
            inst.cancelled = true
            if inst.ctx then cleanupScene(inst.ctx) end
        end
        finishInstall()
    end)
end

--[[
  _____       _     _ _
 |  __ \     | |   | (_)
 | |__) |   _| |__ | |_  ___
 |  ___/ | | | '_ \| | |/ __|
 | |   | |_| | |_) | | | (__
 |_|    \__,_|_.__/|_|_|\___|
]]--

local function startSession(vehicle, shopId, customer)
    CreateThread(function()
        if Session or Opening then return end
        Opening = true
        local ok, err = pcall(openSession, vehicle, shopId, customer)
        Opening = false
        if not ok then
            print("[pls_mechanic] tuning open failed: "..tostring(err))
            if Session then
                Core.Nui.Close("tuning")
            end
        end
    end)
end

function Tuning.Open(vehicle, shopId)
    startSession(vehicle, shopId, false)
end

-- Customer catalog (client/catalog.lua): preview with prices, the cart is sent to the mechanics as an order
function Tuning.OpenCatalog(vehicle)
    startSession(vehicle, nil, true)
end

-- Closes the menu, a running installation is cancelled (remaining changes stay in the saved cart)
function Tuning.Close()
    if Install then
        cancelInstall()
    elseif Session then
        Core.Nui.Close("tuning")
    end
end

-- Menu open or installation running
function Tuning.IsOpen()
    return Session ~= nil
end

function Tuning.IsInstalling()
    return Install ~= nil
end

-- Cancel key / vehicle target: stops the running phase / waiting for parts, remaining steps are skipped
function Tuning.CancelInstall()
    cancelInstall()
end

function Tuning.GetVehicle()
    return Session and Session.vehicle or nil
end

--[[
  _   _ _    _ _____             _ _ _                _
 | \ | | |  | |_   _|           | | | |              | |
 |  \| | |  | | | |     ___ __ _| | | |__   __ _  ___| | _____
 | . ` | |  | | | |    / __/ _` | | | '_ \ / _` |/ __| |/ / __|
 | |\  | |__| |_| |_  | (_| (_| | | | |_) | (_| | (__|   <\__ \
 |_| \_|\____/|_____|  \___\__,_|_|_|_.__/ \__,_|\___|_|\_\___/
]]--

Core.Nui.OnClose("tuning", function()
    -- the installation closes the menu itself and keeps the session
    if Session and Session.installing then return end
    cleanup(true, false)
end)

RegisterNUICallback("tuning:preview", function(data, cb)
    local s = Session
    local item = s and type(data) == "table" and type(data.key) == "string" and s.index[data.key] or nil
    if not item then
        return cb({ ok = false })
    end
    local value = normalizeValue(item, data.value)
    if value == nil then
        return cb({ ok = false, message = locale("tuning_invalid", catLabel(item.entry)) })
    end
    if not NetworkHasControlOfEntity(s.vehicle) and not Core.RequestControl(s.vehicle, 1000) then
        return cb({ ok = false, message = locale("no_control") })
    end
    applyValue(s.vehicle, item.entry, value)
    cb({ ok = true })
end)

-- { plate, changes = { { key, value } } } - empty changes removes the draft
RegisterNUICallback("tuning:draft", function(data, cb)
    cb({ ok = true })
    -- customer catalog: the cart is his order, no local draft
    if Session and Session.mode == "customer" then return end
    if (Config.Tuning.DraftMinutes or 0) <= 0 or type(data) ~= "table" or type(data.plate) ~= "string" then return end
    local plate = Utils.TrimPlate(data.plate)
    -- installation owns the draft of this vehicle (not installed steps must stay in it)
    if IgnoreDrafts[plate] then return end
    local changes = {}
    for _, change in ipairs(type(data.changes) == "table" and data.changes or {}) do
        if type(change) == "table" and type(change.key) == "string" and Categories[change.key] and #changes < Config.Tuning.MaxChanges then
            changes[#changes + 1] = { key = change.key, value = change.value }
        end
    end
    Drafts[plate] = #changes > 0 and { changes = changes, time = GetGameTimer() } or nil
end)

RegisterNUICallback("tuning:focus", function(data, cb)
    if not Session then
        return cb({ ok = false })
    end
    local entry = type(data) == "table" and type(data.key) == "string" and Categories[data.key] or nil
    focusCamera(entry)
    cb({ ok = true })
end)

RegisterNUICallback("tuning:camera", function(data, cb)
    if not Session then
        return cb({ ok = false })
    end
    cb({ ok = cameraAction(type(data) == "table" and data.action or nil) })
end)

RegisterNUICallback("tuning:confirm", function(data, cb)
    local s = Session
    if not s then
        return cb({ ok = false, message = locale("tuning_session_expired") })
    end
    -- customer catalog: only "catalog:submit" (order for the mechanics)
    if s.mode == "customer" then
        return cb({ ok = false, message = locale("tuning_catalog_order_only") })
    end
    if s.busy or s.installing then
        return cb({ ok = false, message = locale("tuning_wait") })
    end
    local changes, err = prepareChanges(type(data) == "table" and data.changes or nil)
    if not changes then
        return cb({ ok = false, message = err })
    end
    if #changes == 0 then
        return cb({ ok = false, message = locale("tuning_nothing_to_confirm") })
    end

    -- step by step installation: everything is checked first, the menu stays open with the cart on any problem
    if installEnabled() then
        -- the parts check can ask the server for the storage stock (Config.Fetch), another confirm waits meanwhile
        s.busy = true
        local called, ok, message, info = pcall(preflight, s, changes)
        s.busy = false
        if not called then
            print("[pls_mechanic] tuning preflight failed: "..tostring(ok))
            ok, message = false, locale("tuning_failed")
        end
        if Session ~= s then
            return cb({ ok = false, message = locale("tuning_session_expired") })
        end
        if not ok then
            return cb({ ok = false, message = message })
        end
        -- customer order: changes outside of it are approved by the customer, the cart stays on refusal
        s.busy = true
        local approved, approvalMessage = requestApproval(s, changes)
        s.busy = false
        if not approved then
            return cb({ ok = false, message = approvalMessage })
        end
        cb({ ok = true })
        startInstall(s, changes)
        -- parts brought from the workshop storage during the installation
        if info then
            Core.Notify(info, "inform")
        end
        return
    end

    s.busy = true
    local approved, approvalMessage = requestApproval(s, changes)
    if not approved then
        s.busy = false
        return cb({ ok = false, message = approvalMessage })
    end
    local ok, result = pcall(confirmChanges, changes)
    s.busy = false
    if not ok then
        print("[pls_mechanic] tuning confirm failed: "..tostring(result))
        result = { ok = false, message = locale("tuning_failed") }
    end
    cb(result)
end)

-- Customer catalog: { changes = { { key, value } } } is sent to the mechanics as an order, empty list = cancel the order.
-- Sent: the menu closes and the preview is reverted (the vehicle stays as it was until the mechanic installs it)
RegisterNUICallback("catalog:submit", function(data, cb)
    local s = Session
    if not s or s.mode ~= "customer" then
        return cb({ ok = false, message = locale("tuning_session_expired") })
    end
    if s.busy then
        return cb({ ok = false, message = locale("tuning_wait") })
    end
    local list = type(data) == "table" and data.changes or nil
    local changes, err = prepareChanges(list)
    if not changes then
        return cb({ ok = false, message = err })
    end
    -- the cart holds only current values (an empty cart cancels the order)
    if #changes == 0 and #list > 0 then
        return cb({ ok = false, message = locale("tuning_nothing_to_confirm") })
    end
    local final = Utils.DeepCopy(s.confirmed)
    for _, change in ipairs(changes) do
        writeValue(change.entry, final, change.value)
    end
    local requirementsOk, requirementMessage = checkRequirements(changes, final)
    if not requirementsOk then
        return cb({ ok = false, message = requirementMessage })
    end

    local payload = {}
    for i, change in ipairs(changes) do
        payload[i] = { key = change.entry.key, value = change.value }
    end
    s.busy = true
    local ok, result = pcall(lib.callback.await, "pls_mechanic:server:catalog:submit", false, s.netId, payload)
    s.busy = false
    if not ok or type(result) ~= "table" then
        result = { ok = false, message = locale("tuning_failed") }
    end
    cb({ ok = result.ok == true, total = tonumber(result.total), message = result.message })
    if result.ok then
        if Session == s then
            Core.Nui.Close("tuning")
        end
        if result.message then
            Core.Notify(result.message, "success")
        end
    end
end)

--[[
  ____
 |  _ \
 | |_) | __ _ _   _
 |  _ < / _` | | | |
 | |_) | (_| | |_| |
 |____/ \__,_|\__, |
               __/ |
              |___/
]]--

-- Vehicle standing in bay (short cache, canInteract runs often)
local function getBayVehicle(point, fresh)
    local now = GetGameTimer()
    local cacheKey = point.id or ("%.2f:%.2f"):format(point.coords.x, point.coords.y)
    local cached = BayCache[cacheKey]
    if not fresh and cached and cached.time > now then
        return cached.vehicle
    end
    local radius = point.radius or Config.PointTypes.bay.radius
    local vehicle = lib.getClosestVehicle(Utils.Vec3(point.coords), radius, false)
    if vehicle and not DoesEntityExist(vehicle) then vehicle = nil end
    BayCache[cacheKey] = { vehicle = vehicle, time = now + 750 }
    return vehicle
end

ShopPoints.RegisterAction("bay", {
    label = locale("tuning_target"),
    icon = "fa-solid fa-wand-magic-sparkles",
    perm = nil, -- tuning_visual OR tuning_performance, checked in canInteract
    canInteract = function(shop, point)
        if Session or Opening or not Utils.BayAccepts(point, "tuning") then return false end
        if not Core.HasPermission("tuning_visual", shop.id) and not Core.HasPermission("tuning_performance", shop.id) then
            return false
        end
        return getBayVehicle(point) ~= nil
    end,
    onSelect = function(shop, point)
        local vehicle = getBayVehicle(point, true)
        if not vehicle then
            return Core.Notify(locale("no_vehicle"), "error")
        end
        Tuning.Open(vehicle, shop.id)
    end,
})

--[[
  ______               _
 |  ____|             | |
 | |____   _____ _ __ | |_ ___
 |  __\ \ / / _ \ '_ \| __/ __|
 | |___\ V /  __/ | | | |_\__ \
 |______\_/ \___|_| |_|\__|___/
]]--

-- Server left a revert on the vehicle (applyRevert): vehicles with the statebag are checked about every second while
-- there is any, the client with network control applies it. [netId] = { seen, id, time } (id + time of the last report)
local PendingReverts = {}
local RevertLoop = false

local function checkRevert(netId, pending)
    local now = GetGameTimer()
    local vehicle = NetworkDoesEntityExistWithNetworkId(netId) and NetToVeh(netId) or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        -- not streamed in, forgotten after a while (the statebag comes again with the vehicle)
        if now - pending.seen > 300000 then PendingReverts[netId] = nil end
        return
    end
    pending.seen = now
    local revert = Entity(vehicle).state.pls_mechanic_revert
    if type(revert) ~= "table" then
        PendingReverts[netId] = nil
        return
    end
    -- reported already, the server clears the statebag (reported again when it didn't)
    if pending.time and pending.id == revert.id and now - pending.time < 5000 then return end
    if applyRevert(vehicle) then
        pending.id, pending.time = revert.id, GetGameTimer()
    end
end

local function startRevertLoop()
    if RevertLoop then return end
    RevertLoop = true
    CreateThread(function()
        while next(PendingReverts) do
            Wait(1000)
            local list = {}
            for netId in pairs(PendingReverts) do
                list[#list + 1] = netId
            end
            for _, netId in ipairs(list) do
                local pending = PendingReverts[netId]
                if pending then
                    checkRevert(netId, pending)
                end
            end
        end
        RevertLoop = false
    end)
end

AddStateBagChangeHandler("pls_mechanic_revert", nil, function(bagName, _, value)
    local netId = tonumber(bagName:match("^entity:(%d+)$"))
    if not netId then return end
    if type(value) ~= "table" then
        PendingReverts[netId] = nil
        return
    end
    PendingReverts[netId] = PendingReverts[netId] or { seen = GetGameTimer() }
    startRevertLoop()
end)

-- resource restart: reverts already on streamed vehicles
CreateThread(function()
    for _, vehicle in ipairs(GetGamePool("CVehicle")) do
        if NetworkGetEntityIsNetworked(vehicle) and Entity(vehicle).state.pls_mechanic_revert then
            PendingReverts[NetworkGetNetworkIdFromEntity(vehicle)] = { seen = GetGameTimer() }
        end
    end
    if next(PendingReverts) then
        startRevertLoop()
    end
end)

-- "Cancel installation" on the vehicle the mechanic is installing parts on
local CancelTargetId = BRIDGE.AddGlobalVehicleTarget({
    {
        name = "pls_mechanic_tuning_cancel",
        label = locale("tuning_cancel_target"),
        icon = "fa-solid fa-ban",
        distance = 4.0,
        canInteract = function(entity)
            local inst = Install
            if not inst or inst.cancelled or inst.finished or not entity or entity == 0 then return false end
            if entity == inst.vehicle then return true end
            return NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) == inst.netId
        end,
        onSelect = function()
            Tuning.CancelInstall()
        end,
    },
})

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local inst = Install
    if inst then
        Install = nil
        if Anim and Anim.Cleanup then
            pcall(Anim.Cleanup)
        end
        local ctx = inst.ctx
        if ctx then
            if ctx.crate and DoesEntityExist(ctx.crate) then
                DeleteEntity(ctx.crate)
            end
            if DoesEntityExist(ctx.vehicle) and NetworkHasControlOfEntity(ctx.vehicle) then
                restoreVehicle(ctx)
                for door in pairs(ctx.opened) do
                    SetVehicleDoorShut(ctx.vehicle, door, false)
                end
            end
        end
        for _, object in ipairs(inst.leftovers) do
            if DoesEntityExist(object) then
                DeleteEntity(object)
            end
        end
    end
    if CancelTargetId then
        BRIDGE.RemoveGlobalVehicleTarget(CancelTargetId)
    end
    cleanup(true, true)
end)
