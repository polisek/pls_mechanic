--[[
  _______            _
 |__   __|          (_)
    | |_   _ _ __    _ _ __   __ _
    | | | | | '_ \  | | '_ \ / _` |
    | | |_| | | | | | | | | | (_| |
    |_|\__,_|_| |_| |_|_| |_|\__, |
                              __/ |
                             |___/
 Server authority of tuning:
 - session per mechanic (vehicle, shop, tuning state reported when the menu opened)
 - every confirmation validates permission, duty, distance, tuning bay, values, dependencies, tools and items
 - items are removed, price goes to the work log (billing), history + garage properties are saved
 - performance parts installed here are recorded per plate, only those are returned on removal (anti duplication)
 - installation workflow (Config.Tuning.Install.enabled): one change per confirmation, each announced by "begin",
   accepted only after the configured work time of the change
 - parts are consumed by the rules of the workshop (server/items.lua), a performance part installed from a stolen item
   is returned with the same metadata on removal (no laundering of stolen parts)
 - fake plates: records, history and garage properties belong to the real plate (Vehicles.ResolvePlate), the plate of
   the vehicle is its trusted plate (Vehicles.GetEntityPlate), a spoofed plate text never reaches another plate's records
 - customer orders (server/catalog.lua): the order is the cart of the vehicle, changes outside the order need the
   customer's approval (quote), installed changes are removed from the order
 - a session that ended without the client's revert (lost control, crash, drop, no heartbeat) leaves the statebag
   pls_mechanic_revert on the vehicle, the client with network control applies it and reports it (tuning:reverted)
]]--

TuningServer = {}

local Sessions = {}     -- [src] = { netId, plate (real), visiblePlate, rawPlate, shopId, state, owned, activity, orderId (server/catalog.lua) }
local Records = {}      -- [plate] = { engine = 3, turbo = 1 } stages of performance parts installed by workshops
local RecordMeta = {}   -- [plate] = { [category key] = item metadata } performance parts installed from stolen items
local LastAction = {}   -- [src] = { open = ms, confirm = ms }
local Busy = {}
local Reverting = {}    -- [netId] = true while the revert statebag of the vehicle is prepared (stored garage properties)
local RevertCounter = 0
local ItemLabels = nil

local Categories = {}
local PerformanceList = {}
local TuningKeys = {}

local NEON_BITS = { 1, 2, 4, 8 }
local BLOCKED_TYPES = { boat = true, heli = true, plane = true, submarine = true, train = true, trailer = true }

-- ox_lib vehicle properties saved to garage table
local PROP_KEYS = {
    "model", "plate", "plateIndex", "lockState", "bodyHealth", "engineHealth", "tankHealth", "fuelLevel", "oilLevel", "dirtLevel",
    "paintType1", "paintType2", "color1", "color2", "pearlescentColor", "interiorColor", "dashboardColor", "wheelColor",
    "wheelWidth", "wheelSize", "wheels", "windowTint", "xenonColor", "neonEnabled", "neonColor", "extras", "tyreSmokeColor",
    "modSpoilers", "modFrontBumper", "modRearBumper", "modSideSkirt", "modExhaust", "modFrame", "modGrille", "modHood",
    "modFender", "modRightFender", "modRoof", "modEngine", "modBrakes", "modTransmission", "modHorns", "modSuspension",
    "modArmor", "modNitrous", "modTurbo", "modSubwoofer", "modSmokeEnabled", "modHydraulics", "modXenon", "modFrontWheels",
    "modBackWheels", "modCustomTiresF", "modCustomTiresR", "modPlateHolder", "modVanityPlate", "modTrimA", "modOrnaments",
    "modDashboard", "modDial", "modDoorSpeaker", "modSeats", "modSteeringWheel", "modShifterLeavers", "modAPlate",
    "modSpeakers", "modTrunk", "modHydrolic", "modEngineBlock", "modAirFilter", "modStruts", "modArchCover", "modAerials",
    "modTrimB", "modTank", "modWindows", "modDoorR", "modLivery", "modRoofLivery", "modLightbar", "livery",
    "windows", "doors", "tyres", "bulletProofTyres", "driftTyres",
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
    Categories[entry.key] = entry
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
    PerformanceList[#PerformanceList + 1] = entry
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

local PaletteSets = { paint = {}, xenon = {} }
local PaintLabels, XenonKeys, PaintTypes, TintKeys, PlateKeys, NeonKeys = {}, {}, {}, {}, {}, {}
for _, color in ipairs(Config.Tuning.Colors) do
    PaletteSets.paint[color.value] = true
    PaintLabels[color.value] = color.label
end
for _, color in ipairs(Config.Tuning.XenonColors) do
    PaletteSets.xenon[color.value] = true
    XenonKeys[color.value] = color.key
end
for _, paintType in ipairs(Config.Tuning.PaintTypes) do PaintTypes[paintType.value] = paintType end
for _, tint in ipairs(Config.Tuning.WindowTints) do TintKeys[tint.value] = tint.key end
for _, style in ipairs(Config.Tuning.PlateStyles) do PlateKeys[style.value] = style.key end
for _, layout in ipairs(Config.Tuning.NeonLayouts) do NeonKeys[layout.value] = layout.key end

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

 Same rules as client/tuning.lua (values <-> ox_lib vehicle properties).
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

local function installEnabled()
    return Config.Tuning.Install ~= nil and Config.Tuning.Install.enabled == true
end

-- Minimal time (ms) of one installation step, same as client/tuning.lua: work time of the group
-- ("settings" for neon / xenon / tyre smoke colours), removal factor, laptop calibration, server tolerance
local function installMinTime(entry, value)
    local install = Config.Tuning.Install
    local durations = install.durations or {}
    local key = (entry.type == "rgb" or entry.palette == "xenon") and "settings" or entry.group
    local time = tonumber(durations[key]) or tonumber(durations.other) or 5000
    if isRemoval(entry, value) then
        time = time * (install.removalFactor or 1.0)
    elseif entry.tool and entry.tool == install.calibrationTool then
        time = time + (install.calibration or 0)
    end
    return math.floor(math.floor(time) * (install.serverCheck or 0.9))
end

-- Performance stage (0 = stock)
local function stageOf(entry, value)
    if entry.type == "performance_toggle" then
        return value == true and 1 or 0
    end
    return (tonumber(value) or -1) + 1
end

-- Value sent by client -> validated value or nil
local function normalize(entry, raw)
    local kind = entry.type
    if kind == "performance_toggle" or kind == "toggle" or kind == "custom_tyres" then
        if type(raw) ~= "boolean" then return nil end
        return raw
    elseif kind == "rgb" then
        if type(raw) ~= "table" then return nil end
        local r, g, b = toInt(raw.r), toInt(raw.g), toInt(raw.b)
        if not r or not g or not b or r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 then return nil end
        return { r = r, g = g, b = b }
    end
    local value = toInt(raw)
    if not value then return nil end
    if kind == "performance" then
        if value < -1 or value >= #entry.levels then return nil end
    elseif kind == "mod" or kind == "wheels" or kind == "back_wheels" then
        if value < -1 or value > Config.Tuning.MaxModIndex then return nil end
    elseif kind == "livery" then
        if value < 0 or value > Config.Tuning.MaxModIndex then return nil end
    elseif kind == "color" then
        if not PaletteSets[entry.palette] or not PaletteSets[entry.palette][value] then return nil end
    elseif kind == "paint_type" then
        local paintType = PaintTypes[value]
        if not paintType or (entry.target == "secondary" and paintType.primaryOnly) then return nil end
    elseif kind == "neon_layout" then
        if not NeonKeys[value] then return nil end
    elseif kind == "window_tint" then
        if not TintKeys[value] then return nil end
    elseif kind == "plate" then
        if not PlateKeys[value] then return nil end
    else
        return nil
    end
    return value
end

-- Readable value for history / bill
local function valueLabel(entry, value)
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
        return locale("tuning_paint_"..PaintTypes[value].key)
    elseif kind == "neon_layout" then
        return locale("tuning_neon_"..NeonKeys[value])
    elseif kind == "window_tint" then
        return locale("tuning_tint_"..TintKeys[value])
    elseif kind == "plate" then
        return locale("tuning_plate_"..PlateKeys[value])
    elseif kind == "livery" then
        return locale("tuning_livery_n", value + 1)
    end
    return value < 0 and locale("tuning_stock") or locale("tuning_level", value + 1)
end

--[[
  _    _      _
 | |  | |    | |
 | |__| | ___| |_ __   ___ _ __ ___
 |  __  |/ _ \ | '_ \ / _ \ '__/ __|
 | |  | |  __/ | |_) |  __/ |  \__ \
 |_|  |_|\___|_| .__/ \___|_|  |___/
               | |
               |_|
]]--

local function fail(key, ...)
    return { ok = false, message = locale(key, ...) }
end

local function rateLimited(src, action, ms)
    local now = GetGameTimer()
    LastAction[src] = LastAction[src] or {}
    local last = LastAction[src][action]
    if last and now - last < ms then return true end
    LastAction[src][action] = now
    return false
end

local function itemLabel(name)
    if not ItemLabels then
        ItemLabels = {}
        local ok, items = pcall(BRIDGE.GetItems)
        if ok and type(items) == "table" then
            for itemName, data in pairs(items) do
                if type(data) == "table" then
                    ItemLabels[itemName] = data.label or itemName
                end
            end
        end
    end
    return ItemLabels[name] or name
end

-- {{item = key, count}} -> "2x Label, 1x Label"
local function itemsText(list)
    local parts = {}
    for _, v in ipairs(list) do
        parts[#parts + 1] = v.count.."x "..itemLabel(Utils.Item(v.item))
    end
    return table.concat(parts, ", ")
end

local function getPlayerName(src)
    local ok, name = pcall(BRIDGE.GetPlayerFullName, src)
    if ok and type(name) == "string" and name ~= "" then return name end
    return GetPlayerName(src) or tostring(src)
end

-- Plate -> real plate (fake plate alias resolved)
local function resolvePlate(plate)
    if Vehicles and Vehicles.ResolvePlate then
        return Vehicles.ResolvePlate(plate)
    end
    return Utils.TrimPlate(plate)
end

local function getMileage(plate)
    if Vehicles and Vehicles.GetByPlate then
        local ok, data = pcall(Vehicles.GetByPlate, plate)
        if ok and type(data) == "table" then
            return tonumber(data.mileage) or 0
        end
    end
    return 0
end

-- Model hashes can be signed or unsigned depending on side
local function sameModel(a, b)
    a, b = toInt(a), toInt(b)
    if not a or not b then return false end
    return a % 4294967296 == b % 4294967296
end

local function isElectric(model)
    for _, name in ipairs(Config.ElectricVehicles) do
        if sameModel(joaat(name), model) then
            return true
        end
    end
    return false
end

-- Copy of client data limited to plain values (depth 2, 64 entries per table)
local function sanitizeValue(value, depth)
    local valueType = type(value)
    if valueType == "number" or valueType == "boolean" then return value end
    if valueType == "string" then return #value <= 64 and value or nil end
    if valueType ~= "table" or (depth or 0) >= 2 then return nil end
    local copy, count = {}, 0
    for k, v in pairs(value) do
        count = count + 1
        if count > 64 then return nil end
        local keyType = type(k)
        if keyType ~= "number" and keyType ~= "string" then return nil end
        local clean = sanitizeValue(v, (depth or 0) + 1)
        if clean ~= nil then copy[k] = clean end
    end
    return copy
end

local function sanitizeState(state)
    local result = {}
    for key in pairs(TuningKeys) do
        local value = sanitizeValue(state[key])
        if value ~= nil and type(value) ~= "string" then
            result[key] = value
        end
    end
    return result
end

local function sanitizeProps(props)
    if type(props) ~= "table" then return nil end
    local result = {}
    for _, key in ipairs(PROP_KEYS) do
        local value = sanitizeValue(props[key])
        if value ~= nil then result[key] = value end
    end
    return result
end

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

-- Duty shop + tuning permissions of player. Returns access or nil, locale key
local function getAccess(src)
    local shopId = Shops.GetPlayerShopId(src)
    local shop = shopId and Shops.Get(shopId)
    if not shop then return nil, "not_on_duty" end
    local visual = Shops.HasPermission(src, "tuning_visual", shopId)
    local performance = Shops.HasPermission(src, "tuning_performance", shopId)
    if not visual and not performance then
        -- illegal workshops have no duty
        if Config.RequireDuty and shop.kind ~= "illegal" and Player(src).state.pls_mechanic_duty ~= shopId then
            return nil, "not_on_duty"
        end
        return nil, "no_permission"
    end
    return { shopId = shopId, shop = shop, visual = visual == true, performance = performance == true }
end

-- Vehicle exists, is tunable, mechanic is near and vehicle stands in tuning bay of his shop
local function checkVehicle(src, shop, netId)
    local entity = Shops.GetEntity(netId)
    if not entity or GetEntityType(entity) ~= 2 then return nil, "no_vehicle" end
    local vehicleType = GetVehicleType(entity)
    if vehicleType and BLOCKED_TYPES[vehicleType] then return nil, "tuning_vehicle_not_supported" end
    if not Shops.IsNearEntity(src, entity, Config.Tuning.MaxDistance) then return nil, "too_far" end
    if not findTuningBay(shop, GetEntityCoords(entity)) then return nil, "tuning_not_in_bay" end
    return entity
end

local function isVehicleInUse(netId, src)
    local now = os.time()
    for other, session in pairs(Sessions) do
        if other ~= src and session.netId == netId and GetPlayerName(other)
            and now - session.activity <= Config.Tuning.SessionTimeout * 60 then
            return true
        end
    end
    return false
end

--[[
  _____                            _
 |  __ \                          | |
 | |__) |___  ___ ___  _ __ __| |___
 |  _  // _ \/ __/ _ \| '__/ _` / __|
 | | \ \  __/ (_| (_) | | | (_| \__ \
 |_|  \_\___|\___\___/|_|  \__,_|___/

 Performance parts installed by this system (resource KVP for owned vehicles, memory for others).
]]--

local function recordKey(plate)
    return "tuning_"..(plate:gsub("[^%w]", "_"))
end

local function getRecord(plate)
    if not Records[plate] then
        local record = {}
        local raw = GetResourceKvpString(recordKey(plate))
        if raw then
            local ok, data = pcall(json.decode, raw)
            if ok and type(data) == "table" then record = data end
        end
        Records[plate] = record
    end
    return Records[plate]
end

-- Metadata of stolen performance parts installed on the plate { [category key] = metadata }
local function getRecordMeta(plate)
    if not RecordMeta[plate] then
        local meta = {}
        local raw = GetResourceKvpString(recordKey(plate).."_meta")
        if raw then
            local ok, data = pcall(json.decode, raw)
            if ok and type(data) == "table" then meta = data end
        end
        RecordMeta[plate] = meta
    end
    return RecordMeta[plate]
end

local function saveRecord(plate, owned)
    if not owned then return end
    local record = Records[plate]
    if record and next(record) then
        SetResourceKvp(recordKey(plate), json.encode(record))
    else
        DeleteResourceKvp(recordKey(plate))
    end
    local meta = RecordMeta[plate]
    if meta and next(meta) then
        SetResourceKvp(recordKey(plate).."_meta", json.encode(meta))
    else
        DeleteResourceKvp(recordKey(plate).."_meta")
    end
end

--[[
  _    _           _       _   _
 | |  | |         | |     | | (_)
 | |  | |_ __   __| | __ _| |_ _ _ __   __ _
 | |  | | '_ \ / _` |/ _` | __| | '_ \ / _` |
 | |__| | |_) | (_| | (_| | |_| | | | | (_| |
  \____/| .__/ \__,_|\__,_|\__|_|_| |_|\__, |
        | |                             __/ |
        |_|                            |___/
]]--

local function isEnabled(entry, state)
    local value = readValue(entry, state)
    if type(value) == "boolean" then return value end
    return type(value) == "number" and value > 0
end

-- Dependencies on the final state (only rules touched by this confirmation)
local function checkRequirements(applied, final)
    local touched = {}
    for _, change in ipairs(applied) do
        touched[change.entry.key] = true
    end
    for _, entry in ipairs(PerformanceList) do
        for _, rule in ipairs(entry.requires or {}) do
            local required = Categories[rule.category]
            if required and (touched[entry.key] or touched[rule.category]) then
                local stage = stageOf(entry, readValue(entry, final))
                if stage >= rule.stage and stageOf(required, readValue(required, final)) < rule.minStage then
                    return false, locale("tuning_requires", catLabel(entry), rule.stage, catLabel(required), rule.minStage)
                end
            end
        end
    end
    for _, change in ipairs(applied) do
        local needed = change.entry.needs and Categories[change.entry.needs]
        local neutral = change.entry.palette == "xenon" and change.value == 255
        if needed and not neutral and not isEnabled(needed, final) then
            return false, locale("tuning_requires_enabled", catLabel(change.entry), catLabel(needed))
        end
    end
    return true
end

local function deepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not deepEqual(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function saveOwnedProps(session, entity, props)
    local clean = sanitizeProps(props)
    if not clean or Utils.TrimPlate(clean.plate) ~= session.visiblePlate or not sameModel(clean.model, GetEntityModel(entity)) then
        Utils.Debug("tuning: vehicle properties of", session.plate, "rejected, not saved")
        return
    end
    -- Stored garage properties are the base: client can report fake mods at menu open,
    -- so only keys changed by validated confirmations of this session are written over them.
    local okStored, stored = pcall(BRIDGE.GetVehicleProperties, session.rawPlate)
    if okStored and type(stored) == "table" then
        local merged = Utils.DeepCopy(stored)
        for key in pairs(TuningKeys) do
            if session.state[key] ~= nil and not deepEqual(session.state[key], session.openState and session.openState[key]) then
                merged[key] = Utils.DeepCopy(session.state[key])
            end
        end
        clean = merged
    else
        -- no stored properties (not supported by framework) - tuning keys from server state
        for key in pairs(TuningKeys) do
            if session.state[key] ~= nil then
                clean[key] = Utils.DeepCopy(session.state[key])
            end
        end
        -- fake plate on the vehicle: the garage keeps the real one
        if session.visiblePlate ~= session.plate then
            clean.plate = session.rawPlate
        end
    end
    local ok, err = pcall(BRIDGE.SaveVehicleProperties, session.rawPlate, clean)
    if not ok then
        print("[pls_mechanic] tuning SaveVehicleProperties failed: "..tostring(err))
    end
end

-- Unconfirmed preview of a session (mechanic or customer catalog) that ended without the client's revert:
-- statebag pls_mechanic_revert = { id, state, plate } stays on the vehicle until the client with network control
-- applies it (tuning:reverted). The state is the server state of the session (confirmed changes stay).
-- Owned vehicles (Config.Tuning.SaveOwnedVehicles): tuning keys of the stored garage properties win over the state
-- reported by the client at open, only keys confirmed in this session stay (a forged state never adds foreign mods)
local function setRevert(session)
    local netId = session.netId
    if not Shops.GetEntity(netId) then return end
    Reverting[netId] = true
    CreateThread(function()
        local state = Utils.DeepCopy(session.state)
        if Config.Tuning.SaveOwnedVehicles and session.owned ~= false and session.rawPlate then
            local ok, stored = pcall(BRIDGE.GetVehicleProperties, session.rawPlate)
            if ok and type(stored) == "table" then
                for key, value in pairs(sanitizeState(stored)) do
                    if not session.openState or deepEqual(session.state[key], session.openState[key]) then
                        state[key] = value
                    end
                end
            end
        end
        Reverting[netId] = nil
        local entity = Shops.GetEntity(netId)
        if not entity or Utils.TrimPlate(GetVehicleNumberPlateText(entity)) ~= session.visiblePlate then return end
        RevertCounter = RevertCounter + 1
        Entity(entity).state:set("pls_mechanic_revert", {
            id = ("%d_%d"):format(os.time(), RevertCounter),
            state = state,
            plate = session.visiblePlate,
        }, true)
    end)
end

-- Revert of an ended session waits for the client with network control, a new session waits for it too.
-- A revert of another plate (the plate was changed since) can't be applied any more, the new session replaces it
local function revertPending(netId, entity)
    if Reverting[netId] then return true end
    local pending = Entity(entity).state.pls_mechanic_revert
    if type(pending) ~= "table" then return false end
    if pending.plate ~= Utils.TrimPlate(GetVehicleNumberPlateText(entity)) then
        Entity(entity).state:set("pls_mechanic_revert", nil, true)
        return false
    end
    return true
end

local function processConfirm(src, netId, changes, props)
    local session = Sessions[src]
    if not session or session.netId ~= netId then return fail("tuning_session_expired") end

    local access, reason = getAccess(src)
    if not access then return fail(reason) end
    if access.shopId ~= session.shopId then return fail("tuning_session_expired") end
    local entity, vehicleReason = checkVehicle(src, access.shop, netId)
    if not entity then return fail(vehicleReason) end
    -- plate changed during the session (trusted plate = records / refunds of the session)
    local realPlate, _, visiblePlate = Vehicles.GetEntityPlate(entity)
    if realPlate ~= session.plate or (visiblePlate or realPlate) ~= session.visiblePlate then return fail("tuning_session_expired") end

    if type(changes) ~= "table" or #changes == 0 then return fail("tuning_nothing_to_confirm") end
    if #changes > Config.Tuning.MaxChanges then return fail("tuning_too_many", Config.Tuning.MaxChanges) end

    -- installation workflow: exactly the change announced by "begin", after its work time
    if installEnabled() then
        local pending = session.pending
        session.pending = nil
        local change = changes[1]
        if #changes ~= 1 or not pending or type(change) ~= "table" or change.key ~= pending.key then
            return fail("tuning_install_invalid")
        end
        local value = normalize(Categories[pending.key], change.value)
        if value == nil or not sameValue(value, pending.value) then
            return fail("tuning_install_invalid")
        end
        if GetGameTimer() - pending.started < pending.min then
            return fail("tuning_install_too_fast")
        end
    end

    -- validate values + permission, last value of key wins
    local isEv = isElectric(GetEntityModel(entity))
    local byKey, order = {}, {}
    for _, change in ipairs(changes) do
        local entry = type(change) == "table" and type(change.key) == "string" and Categories[change.key] or nil
        if not entry then
            return fail("tuning_invalid", type(change) == "table" and tostring(change.key):sub(1, 32) or "?")
        end
        local value = normalize(entry, change.value)
        if value == nil then return fail("tuning_invalid", catLabel(entry)) end
        if (entry.performance and not access.performance) or (not entry.performance and not access.visual) then
            return fail("no_permission")
        end
        if entry.iceOnly and isEv and not isRemoval(entry, value) then
            return fail("tuning_vehicle_not_supported")
        end
        if not byKey[entry.key] then
            order[#order + 1] = entry.key
        end
        byKey[entry.key] = { entry = entry, value = value }
    end

    -- one rim set only (last one), skip values that equal current state
    local lastWheel = nil
    for _, key in ipairs(order) do
        if byKey[key].entry.type == "wheels" then lastWheel = key end
    end
    local state = session.state
    local applied = {}
    for _, key in ipairs(order) do
        local change = byKey[key]
        if change.entry.type ~= "wheels" or key == lastWheel then
            local before = readValue(change.entry, state)
            if not sameValue(before, change.value) then
                change.before = before
                applied[#applied + 1] = change
            end
        end
    end
    if #applied == 0 then return fail("tuning_nothing_to_confirm") end

    local final = Utils.DeepCopy(state)
    for _, change in ipairs(applied) do
        writeValue(change.entry, final, change.value)
    end
    local requirementsOk, requirementMessage = checkRequirements(applied, final)
    if not requirementsOk then
        return { ok = false, message = requirementMessage }
    end
    -- customer order: changes outside the order only after the customer's approval (quote)
    if CatalogServer then
        local approvedOk, approvalKey = CatalogServer.CheckApproved(session, applied)
        if not approvedOk then
            return fail(approvalKey or "tuning_quote_required")
        end
    end

    -- price, items, tools, returned parts
    local markup = tonumber(access.shop.settings and access.shop.settings.tuningMarkup) or 0
    local record = getRecord(session.plate)
    local recordMeta = getRecordMeta(session.plate)
    local total = 0
    local itemCounts, tools, refunds, recordChanges, installs = {}, {}, {}, {}, {}
    for _, change in ipairs(applied) do
        local entry, value = change.entry, change.value
        change.price = withMarkup(basePrice(entry, value), markup)
        total = total + change.price
        if entry.tool then
            tools[entry.tool] = true
        end
        if entry.performance then
            local newStage, oldStage = stageOf(entry, value), stageOf(entry, change.before)
            local isToggle = entry.type == "performance_toggle"
            if newStage > 0 then
                local item = isToggle and entry.item or entry.levels[newStage].item
                itemCounts[item] = (itemCounts[item] or 0) + 1
                installs[#installs + 1] = { key = entry.key, item = item }
            end
            if entry.returnItemOnRemove and oldStage > 0 and record[entry.key] == oldStage then
                local item = isToggle and entry.item or (entry.levels[oldStage] and entry.levels[oldStage].item)
                if item then
                    -- part installed from a stolen item comes back stolen
                    refunds[#refunds + 1] = { item = item, count = 1, metadata = recordMeta[entry.key] }
                end
            end
            recordChanges[entry.key] = newStage > 0 and newStage or false
        elseif entry.material and not isRemoval(entry, value) then
            itemCounts[entry.material.item] = (itemCounts[entry.material.item] or 0) + entry.material.count
        end
    end

    local toolList = {}
    for key in pairs(tools) do
        toolList[#toolList + 1] = key
    end
    -- parts by the rules of the workshop (illegal: stolen first, legal: clean only)
    local hasTools, missingTool = Shops.HasTools(src, toolList, access.shopId)
    if not hasTools then
        return fail("missing_tool", itemLabel(Utils.Item(missingTool)))
    end
    local items = {}
    for key, count in pairs(itemCounts) do
        items[#items + 1] = { item = key, count = count }
    end
    local hasItems, missing = Shops.HasItems(src, items, 1, access.shopId)
    if not hasItems then
        return fail("missing_items", itemsText(missing))
    end

    -- commit
    local consumed, removed = Shops.RemoveItems(src, items, 1, access.shopId)
    if not removed then
        -- inventory changed after the check: what was taken goes back
        Shops.AddItems(src, consumed, access.shopId)
        return fail("missing_items", itemsText(items))
    end
    if #refunds > 0 then
        Shops.AddItems(src, refunds, access.shopId)
    end
    session.state = final
    session.activity = os.time()
    -- metadata of stolen performance parts (returned the same way on removal)
    local units = {}
    for _, entry in ipairs(consumed) do
        units[entry.item] = units[entry.item] or {}
        for _ = 1, entry.count do
            table.insert(units[entry.item], entry.stolen and entry.metadata or false)
        end
    end
    for key, stage in pairs(recordChanges) do
        record[key] = stage or nil
        recordMeta[key] = nil
    end
    for _, install in ipairs(installs) do
        local metadata = units[install.item] and table.remove(units[install.item], 1)
        recordMeta[install.key] = metadata or nil
    end
    saveRecord(session.plate, session.owned)

    local names, historyItems, logChanges, appliedKeys = {}, {}, {}, {}
    for i, change in ipairs(applied) do
        local label = catLabel(change.entry)
        names[i] = label
        historyItems[i] = { label = label..": "..valueLabel(change.entry, change.value), count = 1 }
        logChanges[i] = { key = change.entry.key, value = change.value, price = change.price }
        appliedKeys[i] = change.entry.key
    end

    if total > 0 then
        local label = locale("tuning_worklog", table.concat(names, ", "))
        if #label > 120 then
            label = locale("tuning_worklog_count", #applied)
        end
        WorkLog.Add(src, session.plate, { label = label, price = total })
    end

    local mechanic = getPlayerName(src)
    History.Add(session.plate, {
        shopId = access.shopId,
        mechanic = mechanic,
        type = "tuning",
        label = locale("tuning_history", #applied),
        items = historyItems,
        mileage = getMileage(session.plate),
    })

    if Config.Tuning.SaveOwnedVehicles and session.owned then
        saveOwnedProps(session, entity, props)
    end

    OpenServer.Log(src, "tuning", locale("tuning_log", mechanic, session.plate, Config.Currency..total), {
        plate = session.plate,
        shopId = access.shopId,
        total = total,
        changes = logChanges,
        refunds = refunds,
    })

    if #refunds > 0 then
        Shops.Notify(src, locale("tuning_refund", itemsText(refunds)), "inform")
    end

    -- installed changes leave the customer order (empty order = done)
    if CatalogServer then
        CatalogServer.OnConfirmed(session, applied)
    end

    return { ok = true, total = total, applied = appliedKeys }
end

--[[
   _____      _ _ _                _
  / ____|    | | | |              | |
 | |     __ _| | | |__   __ _  ___| | _____
 | |    / _` | | | '_ \ / _` |/ __| |/ / __|
 | |___| (_| | | | |_) | (_| | (__|   <\__ \
  \_____\__,_|_|_|_.__/ \__,_|\___|_|\_\___/
]]--

-- Menu opened: stores tuning state of the vehicle (tuning subset of lib.getVehicleProperties)
lib.callback.register("pls_mechanic:server:tuning:open", function(src, netId, state)
    if rateLimited(src, "open", 1000) then return fail("tuning_wait") end
    netId = toInt(netId)
    if not netId or type(state) ~= "table" then return fail("no_vehicle") end

    local access, reason = getAccess(src)
    if not access then return fail(reason) end
    local entity, vehicleReason = checkVehicle(src, access.shop, netId)
    if not entity then return fail(vehicleReason) end
    if isVehicleInUse(netId, src) then return fail("tuning_in_use") end
    if CatalogServer and CatalogServer.IsVehicleInCatalog(netId, src) then return fail("tuning_in_use_customer") end

    -- fake plate: records / history / garage belong to the real plate. The trusted plate of the entity is used,
    -- a plate text changed by the owner client (another player's plate) never reaches his records / refunds
    local plate, _, visiblePlate = Vehicles.GetEntityPlate(entity)
    if not plate then return fail("no_vehicle") end
    visiblePlate = visiblePlate or plate
    local rawPlate = plate ~= visiblePlate and plate or GetVehicleNumberPlateText(entity)
    local ok, owned = pcall(BRIDGE.IsVehicleOwned, rawPlate)
    -- the query yields: another menu / the catalog may have been opened meanwhile, a revert of an ended session
    -- is applied by the opener first (statebag pls_mechanic_revert)
    if isVehicleInUse(netId, src) then return fail("tuning_in_use") end
    if CatalogServer and CatalogServer.IsVehicleInCatalog(netId, src) then return fail("tuning_in_use_customer") end
    if not DoesEntityExist(entity) then return fail("no_vehicle") end
    if revertPending(netId, entity) then return fail("tuning_wait") end
    local openState = sanitizeState(state)
    local session = {
        netId = netId,
        plate = plate,
        visiblePlate = visiblePlate,
        rawPlate = rawPlate,
        shopId = access.shopId,
        state = openState,
        openState = Utils.DeepCopy(openState),
        owned = ok and owned == true,
        activity = os.time(),
    }
    -- pending customer order of the vehicle = cart of the mechanic, bound to the session (before the session exists,
    -- an order in work doesn't expire)
    local order = CatalogServer and CatalogServer.BindOrder(session) or nil
    Sessions[src] = session
    return { ok = true, order = order }
end)

-- Installation workflow: one step starts (key, value of the change), its work time is measured from now
lib.callback.register("pls_mechanic:server:tuning:begin", function(src, netId, key, value)
    if not installEnabled() then return fail("tuning_failed") end
    if rateLimited(src, "begin", 500) then return fail("tuning_wait") end
    local session = Sessions[src]
    if not session or session.netId ~= toInt(netId) then return fail("tuning_session_expired") end
    local entry = type(key) == "string" and Categories[key] or nil
    if not entry then return fail("tuning_invalid", tostring(key):sub(1, 32)) end
    local normalized = normalize(entry, value)
    if normalized == nil then return fail("tuning_invalid", catLabel(entry)) end
    session.pending = {
        key = entry.key,
        value = normalized,
        started = GetGameTimer(),
        min = installMinTime(entry, normalized),
    }
    session.activity = os.time()
    return { ok = true }
end)

-- changes = { { key, value } }, props = lib.getVehicleProperties after applying changes
lib.callback.register("pls_mechanic:server:tuning:confirm", function(src, netId, changes, props)
    if Busy[src] or rateLimited(src, "confirm", Config.Tuning.Cooldown) then return fail("tuning_wait") end
    Busy[src] = true
    local ok, result = pcall(processConfirm, src, toInt(netId), changes, props)
    Busy[src] = nil
    if not ok then
        print("[pls_mechanic] tuning confirm error: "..tostring(result))
        return fail("tuning_failed")
    end
    return result
end)

-- reverted = the client reverted the unconfirmed preview with network control, otherwise the revert statebag does it
RegisterNetEvent("pls_mechanic:server:tuning:close", function(reverted)
    local src = source
    if not CanTrustPlayer(src) then return end
    local session = Sessions[src]
    Sessions[src] = nil
    if not session then return end
    -- his quote waiting for the customer closes
    if CatalogServer then
        CatalogServer.OnSessionClosed(src)
    end
    if reverted ~= true then
        setRevert(session)
    end
end)

-- Menu / catalog / installation still open (client every 60 s): a session is stale only without it
RegisterNetEvent("pls_mechanic:server:tuning:heartbeat", function()
    local src = source
    if not CanTrustPlayer(src) then return end
    local session = Sessions[src]
    if session then
        session.activity = os.time()
    end
    if CatalogServer then
        CatalogServer.OnHeartbeat(src, session)
    end
end)

-- Client with network control applied the revert statebag (id = the applied revert, also one from before a restart)
RegisterNetEvent("pls_mechanic:server:tuning:reverted", function(netId, id)
    local src = source
    if not CanTrustPlayer(src) then return end
    local entity = Shops.GetEntity(toInt(netId))
    if not entity or type(id) ~= "string" or NetworkGetEntityOwner(entity) ~= src then return end
    local pending = Entity(entity).state.pls_mechanic_revert
    if type(pending) == "table" and pending.id == id then
        Entity(entity).state:set("pls_mechanic_revert", nil, true)
    end
end)

-- Mechanic left during tuning: the revert statebag reverts the unconfirmed preview
AddEventHandler("playerDropped", function()
    local src = source
    local session = Sessions[src]
    Sessions[src], LastAction[src], Busy[src] = nil, nil, nil
    if not session then return end
    -- stale session (no heartbeat): only when nobody else works on the vehicle meanwhile
    if os.time() - session.activity > Config.Tuning.SessionTimeout * 60 and TuningServer.IsVehicleInTuning(session.netId) then return end
    setRevert(session)
end)

-- Stale sessions (no heartbeat for Config.Tuning.SessionTimeout): the vehicle is free again, the unconfirmed preview
-- is reverted unless somebody else works on the vehicle meanwhile
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for src, session in pairs(Sessions) do
            if now - session.activity > Config.Tuning.SessionTimeout * 60 then
                Sessions[src] = nil
                if CatalogServer then
                    CatalogServer.OnSessionClosed(src)
                end
                if not TuningServer.IsVehicleInTuning(session.netId) then
                    setRevert(session)
                end
            end
        end
    end
end)

--[[
  _____       _     _ _
 |  __ \     | |   | (_)
 | |__) |   _| |__ | |_  ___
 |  ___/ | | | '_ \| | |/ __|
 | |   | |_| | |_) | | | (__
 |_|    \__,_|_.__/|_|_|\___|
]]--

-- Somebody has the tuning menu (or the customer catalog) open on this vehicle
function TuningServer.IsVehicleInTuning(netId)
    return isVehicleInUse(netId, nil) or (CatalogServer ~= nil and CatalogServer.IsVehicleInCatalog(netId))
end

-- Stages of performance parts installed by workshops: { engine = 3, turbo = 1, ... }
function TuningServer.GetInstalledParts(plate)
    plate = resolvePlate(plate)
    if not plate then return {} end
    return Utils.DeepCopy(getRecord(plate))
end

-- Locals shared with server/catalog.lua (same rules for the customer catalog, not for other resources)
TuningServer.Internal = {
    Sessions = Sessions,
    Categories = Categories,
    BLOCKED_TYPES = BLOCKED_TYPES,
    toInt = toInt,
    readValue = readValue,
    writeValue = writeValue,
    sameValue = sameValue,
    isRemoval = isRemoval,
    basePrice = basePrice,
    withMarkup = withMarkup,
    normalize = normalize,
    catLabel = catLabel,
    valueLabel = valueLabel,
    fail = fail,
    rateLimited = rateLimited,
    getPlayerName = getPlayerName,
    isElectric = isElectric,
    sanitizeState = sanitizeState,
    findTuningBay = findTuningBay,
    checkRequirements = checkRequirements,
    isVehicleInUse = isVehicleInUse,
    setRevert = setRevert,
    revertPending = revertPending,
}
