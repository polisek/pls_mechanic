--[[
 __      __  _     _      _
 \ \    / / | |   (_)    | |
  \ \  / /__| |__  _  ___| | ___  ___
   \ \/ / _ \ '_ \| |/ __| |/ _ \/ __|
    \  /  __/ | | | | (__| |  __/\__ \
     \/ \___|_| |_|_|\___|_|\___||___/

 Realistic vehicle condition: mileage, service parts, core parts, collisions.
 Cache plate -> VehicleData, statebag "pls_mech" on the vehicle entity, owned vehicles saved to database.
 VehicleData.origin = { [partKey] = "unknown" }   installed stolen parts (wear faster, legal diagnostics shows them)
 VehicleData.ext = { [source] = { handling = { [field] = mult }, wear = { [partKey] = mult } } }   modifiers of other
   resources (pls_mechanic_illegal), handling is applied by the driver client, wear here
 Plate aliases (fake plates): alias plate -> real plate, data is always kept under the real plate.
 The statebag carries the visible plate of the entity, never the real one.
 Trusted plates: the owner client can change the plate text of its vehicle (SetVehicleNumberPlateText) to the plate of
 another player. Every entity keeps the plate seen first (a new vehicle settles PLATE_SETTLE_MS after it got an owner,
 garage scripts set the plate after the spawn), later only server side changes count (SetTrustedPlate, plate aliases).
]]--

Vehicles = {}

local STATE_KEY = "pls_mech"
local ADOPT_STATE_SECONDS = 600                                      -- existing statebags are adopted only this long after resource start
local ResourceStartTime = os.time()
local SAVE_QUERY = "INSERT INTO `pls_mechanic_vehicles` (`plate`, `mileage`, `data`, `updated_at`) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `mileage` = VALUES(`mileage`), `data` = VALUES(`data`), `updated_at` = VALUES(`updated_at`)"

local MIN_REPORT_MS = 2000                                          -- min time between two mileage reports of one vehicle
local MAX_ELAPSED_MS = (Config.Mileage.syncInterval * 2 + 10) * 1000 -- idle time doesn't allow bigger reports
local LEFT_WINDOW_MS = (Config.Mileage.syncInterval * 2 + 30) * 1000 -- last driver can flush km after leaving
local COLLISION_COOLDOWN_MS = 750
local INIT_THROTTLE_MS = 500
local OWNED_RECHECK_MS = 10 * 60000
local LOADING_TIMEOUT_MS = 10000

-- Server side vehicle types without parts system
local EXCLUDED_TYPES = { boat = true, heli = true, plane = true, submarine = true, train = true, trailer = true }
-- Classes a vehicle of type "automobile" can't have (anti cheat for class sent by client)
local AUTOMOBILE_FORBIDDEN = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

local Cache = {}          -- [plate] = VehicleData
local Meta = {}           -- [plate] = runtime info (entity, dirty, timers...)
local EntityPlates = {}   -- [entity] = plate
local Loading = {}        -- [plate] = true while loading / creating
local InitThrottle = {}   -- [src] = time of last init of not cached vehicle
local FreshNpc = {}       -- [plate] = { createdAt, mileage } not owned data created recently (new purchase detection)
local PendingNew = {}     -- [plate] = time, marked new by SetVehicleNew before first init
local Aliases = {}        -- [alias plate] = real plate (fake plates, memory only - the owner resource sets them again)
local TrustedPlates = {}  -- [entity] = plate the server trusts for the entity (aliases resolved when read)
local Settling = {}       -- [entity] = { ownedAt } new vehicles, their plate text is trusted until they settle
local SpoofLogged = {}    -- [entity] = visible plate of the last logged spoof attempt
local Declared = {}       -- [entity] = GetGameTimer() when the server set the trusted plate (SetTrustedPlate)

local MAX_MOD_FIELDS = 32  -- handling / wear entries per modifier source
local MAX_MOD_SOURCES = 16
local PLATE_SETTLE_MS = 10000 -- a new vehicle takes its plate text this long after it got an owner client

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

local function round(value)
    return Utils.Round(value, 2)
end

local function randomFloat(min, max)
    return min + math.random() * (max - min)
end

local function validNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

-- Model hash as signed int32 (same as client GetEntityModel)
local function toSignedHash(hash)
    hash = tonumber(hash) or 0
    if hash > 2147483647 then hash = hash - 4294967296 end
    return math.tointeger(hash) or hash
end

local function isElectric(model)
    local signed = toSignedHash(model)
    local unsigned = signed < 0 and signed + 4294967296 or signed
    return Utils.IsElectricModel(signed) or Utils.IsElectricModel(unsigned)
end

-- Plate shown on the entity (can be an alias)
local function getVisiblePlate(entity)
    local plate = GetVehicleNumberPlateText(entity)
    if not plate then return nil end
    plate = Utils.TrimPlate(plate)
    if plate == "" then return nil end
    return plate
end

-- Trusted real plate of the entity. Returns realPlate, spoofed, visiblePlate.
-- First sight records the plate, a new vehicle follows its plate text while it settles.
-- spoofed = the plate text (alias resolved) isn't the trusted plate, the trusted one is used.
local function entityPlate(entity)
    local visible = getVisiblePlate(entity)
    local current = visible and (Aliases[visible] or visible) or nil
    local trusted = TrustedPlates[entity]
    if not trusted or Settling[entity] then
        if current then
            TrustedPlates[entity] = current
        end
        return current, false, visible
    end
    -- alias registered after the plate was recorded (restart of this resource with fake plates on the vehicles)
    local real = Aliases[trusted] or trusted
    if current == real then
        return real, false, visible
    end
    if SpoofLogged[entity] ~= visible then
        SpoofLogged[entity] = visible
        Utils.Debug(("plate spoofing: vehicle %s (net %s, owner %s) shows plate %s, trusted plate %s is used"):format(
            entity, NetworkGetNetworkIdFromEntity(entity), NetworkGetEntityOwner(entity), tostring(visible), real))
    end
    return real, true, visible
end

-- Real plate of the entity (trusted plate, alias resolved) = key of VehicleData
local function getPlate(entity)
    return (entityPlate(entity))
end

-- { handling = { [field] = multiplier }, wear = { [partKey] = multiplier } } -> clean copy, nil when nothing is left
local function sanitizeModifiers(mods)
    if type(mods) ~= "table" then return nil end
    local result = { handling = {}, wear = {} }
    local empty = true
    local count = 0
    for field, mult in pairs(type(mods.handling) == "table" and mods.handling or {}) do
        mult = validNumber(mult)
        -- float fields of CHandlingData only (fBrakeForce, fInitialDriveForce...)
        if count < MAX_MOD_FIELDS and type(field) == "string" and #field <= 48 and field:match("^f%u%w*$") and mult and mult > 0 then
            result.handling[field] = Utils.Round(Utils.Clamp(mult, 0.1, 5.0), 3)
            count = count + 1
            empty = false
        end
    end
    count = 0
    for key, mult in pairs(type(mods.wear) == "table" and mods.wear or {}) do
        mult = validNumber(mult)
        if count < MAX_MOD_FIELDS and type(key) == "string" and (Config.ServiceParts[key] or Config.CoreParts[key]) and mult and mult >= 0 then
            result.wear[key] = Utils.Round(Utils.Clamp(mult, 0.1, 10.0), 3)
            count = count + 1
            empty = false
        end
    end
    if empty then return nil end
    return result
end

local function getMeta(plate)
    local meta = Meta[plate]
    if not meta then
        meta = {
            entity = nil,
            dirty = false,
            version = 0,
            lastActive = os.time(),
            lastReport = nil,
            lastCollision = 0,
            lastDriver = nil,
            lastDriverAt = 0,
            ownedCheckAt = GetGameTimer(),
        }
        Meta[plate] = meta
    end
    return meta
end

local function markChanged(plate)
    local meta = getMeta(plate)
    meta.version = meta.version + 1
    meta.dirty = true
    meta.lastActive = os.time()
end

local function isDriver(src, entity)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetPedInVehicleSeat(entity, -1) == ped
end

local function waitForLoading(plate)
    local timeout = GetGameTimer() + LOADING_TIMEOUT_MS
    while Loading[plate] and GetGameTimer() < timeout do
        Wait(50)
    end
end

-- Class from client validated against server side vehicle type. nil = unknown
local function validateClass(vehicleClass, vehicleType)
    vehicleClass = validNumber(vehicleClass)
    if not vehicleClass or vehicleClass ~= math.floor(vehicleClass) or vehicleClass < 0 or vehicleClass > 22 then
        return nil
    end
    vehicleClass = math.floor(vehicleClass)
    if vehicleType == "bike" then
        return (vehicleClass == 8 or vehicleClass == 13) and vehicleClass or nil
    end
    if vehicleType == "automobile" and AUTOMOBILE_FORBIDDEN[vehicleClass] then
        return nil
    end
    return vehicleClass
end

local function isExcludedClass(vehicleClass)
    return vehicleClass ~= nil and Config.ExcludedClasses[vehicleClass] == true
end

--[[
  _____        _
 |  __ \      | |
 | |  | | __ _| |_ __ _
 | |  | |/ _` | __/ _` |
 | |__| | (_| | || (_| |
 |_____/ \__,_|\__\__,_|
]]--

-- Removes parts that don't fit the vehicle, adds missing ones. fill(kind, key) = value of new part (default 100)
local function normalizeParts(data, fill)
    data.service = type(data.service) == "table" and data.service or {}
    data.core = type(data.core) == "table" and data.core or {}
    local lists = { service = Config.ServiceParts, core = Config.CoreParts }
    for kind, list in pairs(lists) do
        local parts = data[kind]
        for key, value in pairs(parts) do
            local part = list[key]
            local number = validNumber(value)
            if not part or not number or not Utils.PartFitsVehicle(part, data.ev) then
                parts[key] = nil
            else
                parts[key] = round(Utils.Clamp(number, 0.0, 100.0))
            end
        end
        for key, part in pairs(list) do
            if parts[key] == nil and Utils.PartFitsVehicle(part, data.ev) then
                local value = fill and fill(kind, key) or 100.0
                parts[key] = round(Utils.Clamp(value, 0.0, 100.0))
            end
        end
    end
    -- origin only for fitted parts, modifiers of other resources sanitized
    local origin = {}
    for key, value in pairs(type(data.origin) == "table" and data.origin or {}) do
        if value == "unknown" and (data.service[key] ~= nil or data.core[key] ~= nil) then
            origin[key] = "unknown"
        end
    end
    data.origin = origin
    local ext, sources = {}, 0
    for source, mods in pairs(type(data.ext) == "table" and data.ext or {}) do
        local clean = type(source) == "string" and #source <= 32 and sanitizeModifiers(mods) or nil
        if clean and sources < MAX_MOD_SOURCES then
            ext[source] = clean
            sources = sources + 1
        end
    end
    data.ext = ext
    return data
end

-- Owned vehicle seen for the first time = brand new, not owned = random used vehicle
local function createData(plate, model, isEv, owned)
    local data = {
        plate = plate,
        model = model,
        class = nil,
        mileage = 0.0,
        ev = isEv,
        owned = owned,
        service = {},
        core = {},
        origin = {},
        ext = {},
    }

    if owned then
        local range = Config.Mileage.newOwnedMileage
        data.mileage = round(randomFloat(range.min, range.max))
        return normalizeParts(data)
    end

    local range = Config.Mileage.npcMileage
    local wear = Config.Mileage.npcWear
    local coreWear = Config.Mileage.npcCoreWear
    data.mileage = round(randomFloat(range.min, range.max))
    -- 0 = lowest random mileage, 1 = highest -> older vehicles are in worse condition
    local age = Utils.Clamp((data.mileage - range.min) / math.max(1, range.max - range.min), 0.0, 1.0)

    normalizeParts(data, function(kind, key)
        if kind == "service" then
            -- some previous owners did the service recently
            if math.random() < 0.35 - age * 0.25 then
                return randomFloat(75.0, 100.0)
            end
            local t = Utils.Clamp(age * 0.5 + math.random() * 0.6, 0.0, 1.0)
            return 100.0 - (wear.min + (wear.max - wear.min) * t)
        end
        local t = Utils.Clamp(age * 0.45 + math.random() ^ 2 * 0.65, 0.0, 1.0)
        return 100.0 - (coreWear.min + (coreWear.max - coreWear.min) * t)
    end)

    -- neglected service already left marks on linked core parts
    for key, life in pairs(data.service) do
        local part = Config.ServiceParts[key]
        if life < 25.0 then
            for coreKey in pairs(part.damages or {}) do
                if data.core[coreKey] then
                    data.core[coreKey] = round(Utils.Clamp(data.core[coreKey] - randomFloat(0.0, 10.0), 0.0, 100.0))
                end
            end
        end
    end

    -- used vehicle (NPC / stolen), but never critical right away
    for key, value in pairs(data.core) do
        data.core[key] = math.max(value, Config.Mileage.npcMinCore or 0)
    end
    for key, value in pairs(data.service) do
        data.service[key] = math.max(value, Config.Mileage.npcMinService or 0)
    end
    FreshNpc[plate] = { createdAt = os.time(), mileage = data.mileage }

    return data
end

local function serialize(data)
    return json.encode({
        service = data.service,
        core = data.core,
        ev = data.ev,
        class = data.class,
        model = data.model,
        origin = next(data.origin or {}) and data.origin or nil,
        ext = next(data.ext or {}) and data.ext or nil,
    })
end

local function saveParams(data)
    return { data.plate, data.mileage, serialize(data), os.time() }
end

local function loadFromDatabase(plate)
    local row = MySQL.single.await("SELECT `mileage`, `data` FROM `pls_mechanic_vehicles` WHERE `plate` = ? LIMIT 1", { plate })
    if not row then return nil end
    local stored = json.decode(row.data or "{}") or {}
    local data = {
        plate = plate,
        model = stored.model and toSignedHash(stored.model) or nil,
        class = validNumber(stored.class),
        mileage = round(validNumber(row.mileage) or 0.0),
        ev = stored.ev == true,
        owned = true,
        service = stored.service,
        core = stored.core,
        origin = stored.origin,
        ext = stored.ext,
    }
    return normalizeParts(data)
end

-- Database row -> existing statebag (resource restart) -> new data. Returns data, needsInsert
local function loadOrCreate(plate, entity)
    local model = toSignedHash(GetEntityModel(entity))
    local isEv = isElectric(model)

    -- marked as new purchase by vehicle shop (SetVehicleNew) before anybody drove it
    local pending = PendingNew[plate]
    if pending then
        PendingNew[plate] = nil
        if os.time() - pending <= 3600 then
            return createData(plate, model, isEv, true), true
        end
    end

    local data = loadFromDatabase(plate)
    if data then
        if data.model ~= model then
            -- plate moved to another model: keep history, refit parts
            data.model = model
            data.ev = isEv
            data.class = nil
            normalizeParts(data)
        end
        return data, false
    end

    local owned = BRIDGE.IsVehicleOwned(plate) == true
    -- statebag can be written by the entity owner client, adopt it only shortly after resource (re)start
    local state = (os.time() - ResourceStartTime) <= ADOPT_STATE_SECONDS and Entity(entity).state[STATE_KEY] or nil
    -- statebag carries the visible plate (alias of a fake plate)
    local statePlate = type(state) == "table" and type(state.plate) == "string" and state.plate or nil
    if statePlate and (statePlate == plate or Aliases[statePlate] == plate) and type(state.service) == "table" and type(state.core) == "table" then
        -- modifiers (ext) are never adopted from the client writable statebag, their owner sets them again
        data = normalizeParts({
            plate = plate,
            model = model,
            class = validNumber(state.class),
            mileage = round(math.max(0.0, validNumber(state.mileage) or 0.0)),
            ev = isEv,
            owned = owned,
            service = state.service,
            core = state.core,
            origin = state.origin,
        })
        return data, owned
    end

    return createData(plate, model, isEv, owned), owned
end

--[[
  _   _                                     _
 | \ | |                                   | |
 |  \| | _____      __  _ __   _   _  _ __ | |__   __ _ ___  ___
 | . ` |/ _ \ \ /\ / / | '_ \ | | | || '__|| '_ \ / _` / __|/ _ \
 | |\  |  __/\ V  V /  | |_) || |_| || |   | | | | (_| \__ \  __/
 |_| \_|\___| \_/\_/   | .__/  \__,_||_|   |_| |_|\__,_|___/\___|
                       | |
                       |_|
 Vehicle shop spawns the car first and writes the owner a moment later, so the first
 init can see it as not owned (used NPC condition). Fresh vehicles are checked often
 and a quick registration with almost no km = new purchase -> brand new condition.
]]--

local FRESH_CHECKS = { 2, 5, 10, 20, 40, 60, 120, 180, 300 } -- s after first init

local function resetToNew(plate, data)
    local range = Config.Mileage.newOwnedMileage
    data.mileage = round(randomFloat(range.min, range.max))
    for key in pairs(data.service) do
        data.service[key] = 100.0
    end
    for key in pairs(data.core) do
        data.core[key] = 100.0
    end
    data.origin = {}
    data.owned = true
    FreshNpc[plate] = nil
    markChanged(plate)
    Vehicles.Save(plate)
    Vehicles.Push(plate)
end

-- Not owned vehicle became owned: fresh one = bought in a shop, others keep their state (stolen + registered)
local function becameOwned(plate, data)
    local fresh = FreshNpc[plate]
    FreshNpc[plate] = nil
    if fresh and os.time() - fresh.createdAt <= (Config.Mileage.newVehicleWindow or 0) and (data.mileage - fresh.mileage) <= (Config.Mileage.newVehicleMaxKm or 0) then
        resetToNew(plate, data)
        return
    end
    data.owned = true
    markChanged(plate)
    Vehicles.Save(plate)
    Vehicles.Push(plate)
end

local function watchFreshVehicle(plate, data)
    CreateThread(function()
        local startedAt = os.time()
        local window = Config.Mileage.newVehicleWindow or 0
        for _, at in ipairs(FRESH_CHECKS) do
            if at > window then break end
            local waitMs = (startedAt + at - os.time()) * 1000
            if waitMs > 0 then Wait(waitMs) end
            if Cache[plate] ~= data or data.owned or not FreshNpc[plate] then return end
            if BRIDGE.IsVehicleOwned(plate) == true then
                if Cache[plate] == data and not data.owned then
                    becameOwned(plate, data)
                end
                return
            end
        end
        if Cache[plate] == data and FreshNpc[plate] and os.time() - FreshNpc[plate].createdAt > window then
            FreshNpc[plate] = nil
        end
    end)
end

--[[
   _____
  / ____|
 | (___  _   _ _ __   ___
  \___ \| | | | '_ \ / __|
  ____) | |_| | | | | (__
 |_____/ \__, |_| |_|\___|
          __/ |
         |___/
]]--

local function attachEntity(plate, entity)
    local meta = getMeta(plate)
    if meta.entity and meta.entity ~= entity and EntityPlates[meta.entity] == plate then
        EntityPlates[meta.entity] = nil
    end
    meta.entity = entity
    EntityPlates[entity] = plate
end

-- Data for clients: fake plate = the plate they see, never the real one
local function clientPayload(data, entity)
    local visible = entity and getVisiblePlate(entity) or nil
    if not visible or visible == data.plate then return data end
    local payload = {}
    for key, value in pairs(data) do
        payload[key] = value
    end
    payload.plate = visible
    return payload
end

local function pushToEntity(plate, entity)
    local data = Cache[plate]
    if not data or not entity or not DoesEntityExist(entity) then return false end
    -- entity handle could be reused or plate changed
    if getPlate(entity) ~= plate then return false end
    Entity(entity).state:set(STATE_KEY, clientPayload(data, entity), true)
    local meta = getMeta(plate)
    meta.pushedEntity = entity
    meta.pushedVersion = meta.version
    return true
end

-- Re-sends statebag to the last known entity of plate
function Vehicles.Push(plate)
    plate = Vehicles.ResolvePlate(plate)
    local meta = plate and Meta[plate]
    if not meta or not meta.entity then return false end
    if pushToEntity(plate, meta.entity) then return true end
    if EntityPlates[meta.entity] == plate then
        EntityPlates[meta.entity] = nil
    end
    meta.entity = nil
    return false
end

--[[
           _____ _____
     /\   |  __ \_   _|
    /  \  | |__) || |
   / /\ \ |  ___/ | |
  / ____ \| |    _| |_
 /_/    \_\_|   |_____|
]]--

-- Plate string from anywhere (client, other resources) -> real plate (trimmed, fake plate alias resolved)
function Vehicles.ResolvePlate(plate)
    if type(plate) ~= "string" and type(plate) ~= "number" then return nil end
    plate = Utils.TrimPlate(plate)
    return Aliases[plate] or plate
end

-- Trusted plate of a vehicle entity: realPlate, spoofed, visiblePlate (nil when the entity isn't a vehicle).
-- Everything keyed by the plate of an entity uses realPlate, never the plate text (the owner client can change it).
function Vehicles.GetEntityPlate(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil, false, nil end
    return entityPlate(entity)
end

-- Plate set by the server on a vehicle it spawned (the owner client may apply the text later). Returns bool
function Vehicles.SetTrustedPlate(entity, plate)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false end
    plate = type(plate) == "string" and Utils.TrimPlate(plate) or nil
    if not plate or plate == "" or #plate > 12 then return false end
    TrustedPlates[entity] = Aliases[plate] or plate
    Settling[entity] = nil
    SpoofLogged[entity] = nil
    Declared[entity] = GetGameTimer()
    return true
end

-- VehicleData of entity (loads / creates, pushes statebag). vehicleClass is optional (sent by client).
-- Returns nil for excluded vehicles.
function Vehicles.GetByEntity(entity, vehicleClass)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    local vehicleType = GetVehicleType(entity)
    if not vehicleType or EXCLUDED_TYPES[vehicleType] then return nil end
    -- spoofed plate text (another player's plate) never redirects the data, the trusted plate is used
    local plate, _, visible = entityPlate(entity)
    if not plate then return nil end

    vehicleClass = validateClass(vehicleClass, vehicleType)
    if isExcludedClass(vehicleClass) then return nil end

    waitForLoading(plate)
    local data = Cache[plate]
    if not data then
        Loading[plate] = true
        local ok, result, needsInsert = pcall(loadOrCreate, plate, entity)
        Loading[plate] = nil
        if not ok then
            print("[pls_mechanic] vehicle load error ("..plate.."): "..tostring(result))
            return nil
        end
        if not result then return nil end
        data = result
        Cache[plate] = data
        local meta = getMeta(plate)
        meta.ownedCheckAt = GetGameTimer()
        if needsInsert then
            meta.dirty = true
            Vehicles.Save(plate)
        end
        if not data.owned and FreshNpc[plate] then
            watchFreshVehicle(plate, data)
        end
    end

    local meta = getMeta(plate)
    if vehicleClass and data.class == nil then
        data.class = vehicleClass
        markChanged(plate)
    end
    if isExcludedClass(data.class) then return nil end

    attachEntity(plate, entity)
    meta.lastActive = os.time()
    -- statebag pushed before the new plate text was synced (fake plate) still carries the old plate
    local state = Entity(entity).state[STATE_KEY]
    local statePlate = type(state) == "table" and state.plate or nil
    if not (meta.pushedEntity == entity and meta.pushedVersion == meta.version and statePlate == (visible or data.plate)) then
        pushToEntity(plate, entity)
    end
    return data
end

-- VehicleData from cache or database (owned vehicles only). Doesn't create new data. Alias plates are resolved.
function Vehicles.GetByPlate(plate)
    plate = Vehicles.ResolvePlate(plate)
    if not plate or plate == "" then return nil end
    waitForLoading(plate)
    if Cache[plate] then return Cache[plate] end

    Loading[plate] = true
    local ok, data = pcall(loadFromDatabase, plate)
    Loading[plate] = nil
    if not ok then
        print("[pls_mechanic] vehicle load error ("..plate.."): "..tostring(data))
        return nil
    end
    if not data then return nil end
    Cache[plate] = data
    getMeta(plate)
    return data
end

-- kind = "service" / "core". Value is clamped 0-100. Returns true when part exists on the vehicle.
function Vehicles.SetPart(plate, kind, key, value)
    if kind ~= "service" and kind ~= "core" then return false end
    local data = Vehicles.GetByPlate(plate)
    if not data or data[kind][key] == nil then return false end
    value = validNumber(value)
    if not value then return false end
    data[kind][key] = round(Utils.Clamp(value, 0.0, 100.0))
    markChanged(data.plate)
    Vehicles.Push(data.plate)
    return true
end

function Vehicles.ModifyPart(plate, kind, key, delta)
    if kind ~= "service" and kind ~= "core" then return false end
    local data = Vehicles.GetByPlate(plate)
    if not data or data[kind][key] == nil then return false end
    delta = validNumber(delta)
    if not delta then return false end
    return Vehicles.SetPart(data.plate, kind, key, data[kind][key] + delta)
end

--[[
   ____       _       _
  / __ \     (_)     (_)
 | |  | |_ __ _  __ _ _ _ __
 | |  | | '__| |/ _` | | '_ \
 | |__| | |  | | (_| | | | | |
  \____/|_|  |_|\__, |_|_| |_|
                 __/ |
                |___/
 Origin of installed parts, modifiers of other resources, plate aliases
]]--

-- origin = "unknown" (stolen part installed) or nil (clean part). Service + core parts. Returns true when the part exists
function Vehicles.SetPartOrigin(plate, key, origin)
    if origin ~= nil and origin ~= "unknown" then return false end
    local data = Vehicles.GetByPlate(plate)
    if not data or type(key) ~= "string" or (data.service[key] == nil and data.core[key] == nil) then return false end
    data.origin = data.origin or {}
    if data.origin[key] == origin then return true end
    data.origin[key] = origin
    markChanged(data.plate)
    Vehicles.Push(data.plate)
    return true
end

-- mods = { handling = { [field] = multiplier }, wear = { [partKey] = multiplier } }, nil removes the source.
-- Handling is applied by the driver client, wear by applyWear. Returns false when the vehicle has no data.
function Vehicles.SetModifiers(plate, source, mods)
    if type(source) ~= "string" or source == "" or #source > 32 then return false end
    local data = Vehicles.GetByPlate(plate)
    if not data then return false end
    data.ext = data.ext or {}
    local clean = sanitizeModifiers(mods)
    if clean and not data.ext[source] then
        local sources = 0
        for _ in pairs(data.ext) do sources = sources + 1 end
        if sources >= MAX_MOD_SOURCES then return false end
    end
    if clean == nil and data.ext[source] == nil then return true end
    data.ext[source] = clean
    markChanged(data.plate)
    Vehicles.Push(data.plate)
    return true
end

-- Re-sends the statebag to the entity of plate (visible plate changed), otherwise on the next GetByEntity
local function repush(plate)
    local meta = Meta[plate]
    if not meta then return end
    meta.pushedEntity = nil
    if meta.entity and DoesEntityExist(meta.entity) and getPlate(meta.entity) == plate then
        pushToEntity(plate, meta.entity)
    end
end

-- Fake plate: data of aliasPlate is the data of realPlate. Returns false when the alias can't be used.
function Vehicles.SetPlateAlias(aliasPlate, realPlate)
    local alias = type(aliasPlate) == "string" and Utils.TrimPlate(aliasPlate) or nil
    local real = Vehicles.ResolvePlate(realPlate)
    if not alias or alias == "" or #alias > 12 or not real or real == "" or alias == real then return false end
    if Aliases[alias] == real then return true end
    -- alias of an existing registered vehicle / chains are refused
    if (Cache[alias] and Cache[alias].owned) or Aliases[real] then return false end
    for _, target in pairs(Aliases) do
        if target == alias then return false end
    end
    -- plate of another player's vehicle would redirect his vehicle data (pcall: the query needs a thread)
    local okOwned, owned = pcall(BRIDGE.IsVehicleOwned, alias)
    if okOwned and owned == true then return false end
    -- another registration during the query
    if Aliases[alias] and Aliases[alias] ~= real then return false end
    Aliases[alias] = real
    -- vehicles recorded with the fake plate text before the alias was known (restart) belong to the real plate,
    -- their trusted plate stays right after the alias is cleared again
    for trustedEntity, trusted in pairs(TrustedPlates) do
        if trusted == alias then
            TrustedPlates[trustedEntity] = real
        end
    end

    -- data created meanwhile for the new plate (random used vehicle) is dropped, the entity belongs to the real plate
    local meta = Meta[alias]
    local entity = meta and meta.entity
    if Cache[alias] and not Cache[alias].owned then
        Cache[alias] = nil
        Meta[alias] = nil
        FreshNpc[alias] = nil
    end
    if entity and EntityPlates[entity] == alias then
        EntityPlates[entity] = nil
    end
    if entity and DoesEntityExist(entity) and getPlate(entity) == real then
        CreateThread(function()
            Vehicles.GetByEntity(entity)
        end)
    end
    repush(real)
    return true
end

function Vehicles.ClearPlateAlias(aliasPlate)
    local alias = type(aliasPlate) == "string" and Utils.TrimPlate(aliasPlate) or nil
    local real = alias and Aliases[alias]
    if not real then return false end
    Aliases[alias] = nil
    repush(real)
    return true
end

-- Real plate of a plate (the plate itself when it isn't an alias)
function Vehicles.GetRealPlate(plate)
    return Vehicles.ResolvePlate(plate)
end

--[[
 __          __
 \ \        / /
  \ \  /\  / /__  __ _ _ __
   \ \/  \/ / _ \/ _` | '__|
    \  /\  /  __/ (_| | |
     \/  \/ \___|\__,_|_|
]]--

local TurboKey = nil
for key, cfg in pairs(Config.TuningWear) do
    if cfg.toggle and cfg.mod == 18 then
        TurboKey = key
    end
end

-- Mods reported by driver -> { [TuningWear key] = level (-1 stock) | bool }
local function sanitizeMods(mods)
    local result = {}
    for key, cfg in pairs(Config.TuningWear) do
        local value = type(mods) == "table" and mods[key] or nil
        if cfg.toggle then
            result[key] = value == true or value == 1
        else
            local level = validNumber(value) or -1
            result[key] = math.floor(Utils.Clamp(level, -1, 10))
        end
    end
    return result
end

local function tuningFactor(partKey, mods)
    local factor = 1.0
    for key, cfg in pairs(Config.TuningWear) do
        for _, part in pairs(cfg.parts or {}) do
            if part == partKey then
                if cfg.toggle then
                    if mods[key] then
                        factor = factor * (1.0 + (cfg.value or 0.0))
                    end
                else
                    local level = (mods[key] or -1) + 1
                    if level > 0 then
                        factor = factor * (1.0 + (cfg.perLevel or 0.0) * level)
                    end
                end
                break
            end
        end
    end
    return Utils.Clamp(factor, 0.2, 5.0)
end

-- Wear multiplier of one part: origin "unknown" (stolen part, Config.StolenParts.wearMultiplier) x ext wear modifiers
local function partWearFactor(data, key)
    local factor = 1.0
    if data.origin and data.origin[key] == "unknown" then
        factor = factor * (validNumber(Config.StolenParts and Config.StolenParts.wearMultiplier) or 1.0)
    end
    for _, mods in pairs(data.ext or {}) do
        local mult = type(mods.wear) == "table" and validNumber(mods.wear[key]) or nil
        if mult then
            factor = factor * mult
        end
    end
    return Utils.Clamp(factor, 0.1, 10.0)
end

-- Applies wear of driven km to data. extra = { overheat = seconds overheated }
local function applyWear(data, km, mods, extra)
    local wearConfig = Config.Effects and Config.Effects.Wear or {}
    local classWear = Config.ClassWear[data.class] or 1.0
    local turboOn = TurboKey ~= nil and mods[TurboKey] == true
    local damage = {}
    local snapped = {}
    local partFactors = {}

    local function partFactor(key)
        if not partFactors[key] then
            partFactors[key] = partWearFactor(data, key)
        end
        return partFactors[key]
    end

    local function addDamage(key, amount)
        if not amount or amount <= 0 or data.core[key] == nil then return end
        local part = Config.CoreParts[key]
        if part and part.requiresTurbo and not turboOn then return end
        damage[key] = (damage[key] or 0.0) + amount * partFactor(key)
    end

    -- service parts: life lost by km, overdue km damage linked core parts
    for key, life in pairs(data.service) do
        local part = Config.ServiceParts[key]
        local factor = classWear * tuningFactor(key, mods) * partFactor(key)
        local loss = km * factor / math.max(1, part.interval or 1) * 100.0
        local newLife = life - loss
        if newLife < 0 then
            local overdueKm = (life > 0 and loss > 0) and (km * (-newLife) / loss) or km
            for coreKey, perKm in pairs(part.damages or {}) do
                addDamage(coreKey, perKm * overdueKm)
            end
        end
        if part.snap and life > 0 and newLife <= 0 and data.core[part.snap] ~= nil then
            snapped[part.snap] = true
        end
        data.service[key] = round(math.max(0.0, newLife))
    end

    -- natural aging of core parts
    for key, perKm in pairs(wearConfig.coreAging or {}) do
        addDamage(key, perKm * km * classWear)
    end

    -- bad radiator cooks the engine
    if data.core.radiator and wearConfig.radiatorEngine then
        local perKm = wearConfig.radiatorEngine[Utils.GetPartState(data.core.radiator)]
        if perKm then addDamage("engine", perKm * km) end
    end

    -- bad alternator doesn't charge the battery
    if data.core.alternator and wearConfig.alternatorBattery then
        local perKm = wearConfig.alternatorBattery[Utils.GetPartState(data.core.alternator)]
        if perKm then addDamage("battery", perKm * km) end
    end

    -- overheating reported by driver (temperature simulation)
    local overheat = extra and extra.overheat or 0
    local temperature = Config.Effects and Config.Effects.Temperature
    if overheat > 0 and temperature and temperature.engineDamagePerMinute then
        addDamage("engine", overheat / 60.0 * temperature.engineDamagePerMinute)
    end

    for key, amount in pairs(damage) do
        data.core[key] = round(Utils.Clamp(data.core[key] - amount, 0.0, 100.0))
    end
    for key in pairs(snapped) do
        data.core[key] = 0.0
    end
end

-- Adds km with wear. mods = { engine = level, transmission = level, brakes = level, turbo = bool } (optional)
function Vehicles.AddMileage(plate, km, mods, extra)
    local data = Vehicles.GetByPlate(plate)
    if not data then return false end
    km = validNumber(km)
    if not km or km <= 0 then return false end
    applyWear(data, km, sanitizeMods(mods), extra)
    data.mileage = round(data.mileage + km)
    markChanged(data.plate)
    Vehicles.Push(data.plate)
    return true
end

-- Not owned vehicle could be bought / registered meanwhile
local function recheckOwnership(plate)
    local data = Cache[plate]
    local meta = Meta[plate]
    if not data or data.owned or not meta then return end
    if GetGameTimer() - (meta.ownedCheckAt or 0) < OWNED_RECHECK_MS then return end
    meta.ownedCheckAt = GetGameTimer()
    CreateThread(function()
        if BRIDGE.IsVehicleOwned(plate) == true and Cache[plate] == data and not data.owned then
            becameOwned(plate, data)
        end
    end)
end

-- Validated mileage from driver. flush = last report after leaving the vehicle
local function reportMileage(src, plate, km, mods, extra, flush)
    local meta = getMeta(plate)
    local now = GetGameTimer()
    if not flush and meta.lastReport and now - meta.lastReport < MIN_REPORT_MS then return end

    km = validNumber(km)
    if not km or km <= 0 then
        if flush then meta.lastReport = now end
        return
    end

    local elapsed = meta.lastReport and math.min(now - meta.lastReport, MAX_ELAPSED_MS) or MAX_ELAPSED_MS
    local allowed = Config.Mileage.maxSpeed * (elapsed / 3600000) * 1.25 + 0.05
    if km > allowed then
        Utils.Debug(("mileage report of %s clamped %.3f -> %.3f km (player %s)"):format(plate, km, allowed, src))
        km = allowed
    end

    local overheat = type(extra) == "table" and validNumber(extra.overheat) or 0
    overheat = Utils.Clamp(overheat, 0, elapsed / 1000)

    meta.lastReport = now
    meta.lastDriver = src
    meta.lastDriverAt = now
    Vehicles.AddMileage(plate, km, mods, { overheat = overheat })
    recheckOwnership(plate)
end

--[[
   _____      _ _ _     _
  / ____|    | | (_)   (_)
 | |     ___ | | |_ ___ _  ___  _ __  ___
 | |    / _ \| | | / __| |/ _ \| '_ \/ __|
 | |___| (_) | | | \__ \ | (_) | | | \__ \
  \_____\___/|_|_|_|___/_|\___/|_| |_|___/
]]--

local function applyCollision(data, severity, zone)
    local cfg = Config.CollisionDamage
    local factors = cfg.zones[zone]
    if not factors then return false end
    local multiplier = (cfg.multiplier or 1.0) * 0.5
    local changed = false

    local function damage(key, factor)
        if data.core[key] == nil or not factor then return end
        local amount = severity * factor * multiplier
        if amount <= 0 then return end
        data.core[key] = round(Utils.Clamp(data.core[key] - amount, 0.0, 100.0))
        changed = true
    end

    for key, factor in pairs(factors) do
        damage(key, factor)
    end
    if cfg.heavySeverity and severity >= cfg.heavySeverity then
        for key, factor in pairs(cfg.heavy or {}) do
            damage(key, factor)
        end
    end
    return changed
end

--[[
   _____
  / ____|
 | (___   __ ___   _____
  \___ \ / _` \ \ / / _ \
  ____) | (_| |\ V /  __/
 |_____/ \__,_| \_/ \___|
]]--

-- Saves one owned vehicle now
function Vehicles.Save(plate)
    local data = Cache[plate]
    if not data or not data.owned then return false end
    local meta = getMeta(plate)
    meta.dirty = false
    MySQL.prepare(SAVE_QUERY, saveParams(data))
    return true
end

-- Batch save of all dirty owned vehicles. noCallback = resource is stopping
function Vehicles.SaveAll(noCallback)
    local queries = {}
    local plates = {}
    for plate, data in pairs(Cache) do
        local meta = Meta[plate]
        if data.owned and meta and meta.dirty then
            meta.dirty = false
            queries[#queries + 1] = { query = SAVE_QUERY, values = saveParams(data) }
            plates[#plates + 1] = plate
        end
    end
    if #queries == 0 then return 0 end
    if noCallback then
        MySQL.transaction(queries)
    else
        MySQL.transaction(queries, function(success)
            if success then return end
            print("[pls_mechanic] saving of "..#plates.." vehicles failed, retrying next interval")
            for _, plate in pairs(plates) do
                if Meta[plate] then Meta[plate].dirty = true end
            end
        end)
    end
    return #queries
end

-- Forgets vehicles which don't exist anymore and weren't active for Config.Mileage.npcCacheHours
local function cleanupCache()
    local now = os.time()
    local limit = (Config.Mileage.npcCacheHours or 6) * 3600
    for plate, data in pairs(Cache) do
        local meta = Meta[plate]
        local alive = meta and meta.entity and DoesEntityExist(meta.entity) and getPlate(meta.entity) == plate
        local inactive = not meta or now - meta.lastActive > limit
        local unsaved = data.owned and meta and meta.dirty
        if not alive and inactive and not unsaved and not Loading[plate] then
            if meta and meta.entity and EntityPlates[meta.entity] == plate then
                EntityPlates[meta.entity] = nil
            end
            Cache[plate] = nil
            Meta[plate] = nil
        end
    end
end

CreateThread(function()
    while true do
        Wait(math.max(1, Config.Mileage.saveInterval or 5) * 60000)
        Vehicles.SaveAll()
        cleanupCache()
    end
end)

--[[
  ______               _
 |  ____|             | |
 | |____   _____ _ __ | |_ ___
 |  __\ \ / / _ \ '_ \| __/ __|
 | |___\ V /  __/ | | | |_\__ \
 |______\_/ \___|_| |_|\__|___/
]]--

-- (netId, vehicleClass?) -> VehicleData or nil, reason
lib.callback.register("pls_mechanic:server:vehicles:init", function(source, netId, vehicleClass)
    local src = source
    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or GetEntityType(entity) ~= 2 then return nil, "no_vehicle" end
    if not Shops.IsNearEntity(src, entity, 15.0) then return nil, "too_far" end
    local plate = getPlate(entity)
    if not plate then return nil, "no_vehicle" end

    if not Cache[plate] then
        local now = GetGameTimer()
        if InitThrottle[src] and now - InitThrottle[src] < INIT_THROTTLE_MS then
            return nil, "busy"
        end
        InitThrottle[src] = now
    end

    local data = Vehicles.GetByEntity(entity, vehicleClass)
    if not data then return nil, "vehicle_excluded" end
    if isDriver(src, entity) then
        local meta = getMeta(plate)
        meta.lastDriver = src
        meta.lastDriverAt = GetGameTimer()
    end
    return clientPayload(data, entity)
end)

-- Driver reports driven km: (netId, km, mods, extra = { overheat = seconds })
RegisterNetEvent("pls_mechanic:server:vehicles:mileage", function(netId, km, mods, extra)
    local src = source
    if not CanTrustPlayer(src) then return end
    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or not isDriver(src, entity) then return end
    local data = Vehicles.GetByEntity(entity)
    if not data then return end
    reportMileage(src, data.plate, km, mods, extra, false)
end)

-- Driver left the vehicle: last km + save. Vehicle may be already deleted (garage), then plate is used.
RegisterNetEvent("pls_mechanic:server:vehicles:left", function(netId, plate, km, mods, extra)
    local src = source
    if not CanTrustPlayer(src) then return end
    local entity = Shops.GetEntity(tonumber(netId))
    if entity and GetEntityType(entity) == 2 then
        plate = getPlate(entity)
    else
        entity = nil
        -- client sends the plate it sees (can be a fake plate)
        plate = type(plate) == "string" and Vehicles.ResolvePlate(plate) or nil
    end
    if not plate or not Cache[plate] then return end

    local meta = getMeta(plate)
    local now = GetGameTimer()
    local allowed = meta.lastDriver == src and now - meta.lastDriverAt <= LEFT_WINDOW_MS
    if entity then
        if not Shops.IsNearEntity(src, entity, 50.0) then return end
        if not allowed then
            -- short drive without any report yet: he must be the last one in the vehicle and nobody drives it now
            local ped = GetPlayerPed(src)
            local driver = GetPedInVehicleSeat(entity, -1)
            allowed = isDriver(src, entity) or (GetVehiclePedIsIn(ped, true) == entity and (driver == 0 or driver == ped))
        end
    end
    if not allowed then return end

    reportMileage(src, plate, km, mods, extra, true)
    if meta.lastDriver == src then
        meta.lastDriver = nil
    end
    if Cache[plate] and Cache[plate].owned and meta.dirty then
        Vehicles.Save(plate)
    end
end)

-- Driver reports impact: (netId, severity = km/h of velocity change, zone = front/rear/left/right)
RegisterNetEvent("pls_mechanic:server:vehicles:collision", function(netId, severity, zone)
    local src = source
    if not CanTrustPlayer(src) then return end
    if type(zone) ~= "string" or not Config.CollisionDamage.zones[zone] then return end
    severity = validNumber(severity)
    if not severity then return end
    severity = Utils.Clamp(severity, 0, math.min(200, Config.Mileage.maxSpeed))
    if severity < Config.CollisionDamage.minSeverity then return end

    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or not isDriver(src, entity) then return end
    local data = Vehicles.GetByEntity(entity)
    if not data then return end

    local meta = getMeta(data.plate)
    local now = GetGameTimer()
    if now - meta.lastCollision < COLLISION_COOLDOWN_MS then return end
    meta.lastCollision = now
    meta.lastDriver = src
    meta.lastDriverAt = now

    if applyCollision(data, severity, zone) then
        Utils.Debug(("collision %s severity %d zone %s"):format(data.plate, math.floor(severity), zone))
        markChanged(data.plate)
        Vehicles.Push(data.plate)
    end
end)

-- New vehicle: its plate text is trusted until it settles (garage scripts set the plate after the spawn).
-- The handle can be a reused one, its old trusted plate is dropped.
AddEventHandler("entityCreated", function(entity)
    if not entity or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return end
    -- spawned by the server which already set its plate (the event can come after SetTrustedPlate)
    if Declared[entity] and GetGameTimer() - Declared[entity] < PLATE_SETTLE_MS then return end
    Declared[entity] = nil
    TrustedPlates[entity] = nil
    SpoofLogged[entity] = nil
    Settling[entity] = { ownedAt = nil }
end)

-- Settling vehicles: only an owner client can change the plate text, the plate settles PLATE_SETTLE_MS after it got one
CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for entity, settle in pairs(Settling) do
            if not DoesEntityExist(entity) then
                Settling[entity] = nil
            elseif NetworkGetEntityOwner(entity) == -1 then
                settle.ownedAt = nil
            elseif not settle.ownedAt then
                settle.ownedAt = now
            elseif now - settle.ownedAt >= PLATE_SETTLE_MS then
                Settling[entity] = nil
                local visible = getVisiblePlate(entity)
                if visible then
                    TrustedPlates[entity] = Aliases[visible] or visible
                end
            end
        end
    end
end)

-- Vehicle deleted (garage, impound, cleanup) -> save immediately
AddEventHandler("entityRemoved", function(entity)
    TrustedPlates[entity] = nil
    Settling[entity] = nil
    SpoofLogged[entity] = nil
    Declared[entity] = nil
    local plate = EntityPlates[entity]
    if not plate then return end
    EntityPlates[entity] = nil
    local meta = Meta[plate]
    if meta and meta.entity == entity then
        meta.entity = nil
    end
    local data = Cache[plate]
    if data and data.owned and meta and meta.dirty then
        Vehicles.Save(plate)
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    InitThrottle[src] = nil
    for plate, meta in pairs(Meta) do
        if meta.lastDriver == src then
            meta.lastDriver = nil
            local data = Cache[plate]
            if data and data.owned and meta.dirty then
                Vehicles.Save(plate)
            end
        end
    end
end)

AddEventHandler("txAdmin:events:serverShuttingDown", function()
    Vehicles.SaveAll(true)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Vehicles.SaveAll(true)
end)

--[[
  ______                       _
 |  ____|                     | |
 | |__  __  ___ __   ___  _ __| |_ ___
 |  __| \ \/ / '_ \ / _ \| '__| __/ __|
 | |____ >  <| |_) | (_) | |  | |_\__ \
 |______/_/\_\ .__/ \___/|_|   \__|___/
             | |
             |_|
]]--

-- GetVehicleData, SetVehiclePart, SetPartOrigin, SetVehicleModifiers and the plate alias exports are in server/api_vehicles.lua

exports("GetVehicleMileage", function(plate)
    local data = Vehicles.GetByPlate(plate)
    return data and data.mileage or nil
end)

exports("AddVehicleMileage", function(plate, km)
    return Vehicles.AddMileage(plate, km)
end)

-- Vehicle shops: call after purchase, vehicle gets brand new condition (works before and after first drive)
function Vehicles.SetNew(plate)
    plate = Vehicles.ResolvePlate(plate)
    if not plate or plate == "" then return false end
    waitForLoading(plate)
    local data = Cache[plate]
    if data then
        resetToNew(plate, data)
    else
        PendingNew[plate] = os.time()
    end
    return true
end

exports("SetVehicleNew", function(plate)
    return Vehicles.SetNew(plate)
end)
-- All service + core parts to 100 % (admin fix). Mileage and ownership stay. False = vehicle without data
function Vehicles.FixAll(plate)
    plate = Vehicles.ResolvePlate(plate)
    local data = plate and Cache[plate]
    if not data then return false end
    for key in pairs(data.service) do
        data.service[key] = 100.0
    end
    for key in pairs(data.core) do
        data.core[key] = 100.0
    end
    markChanged(plate)
    Vehicles.Save(plate)
    Vehicles.Push(plate)
    return true
end

--[[
           _           _
     /\   | |         (_)
    /  \  | |_ __ ___  _ _ __
   / /\ \ / _` | '_ ` _ \| | '_ \
  / ____ \ (_| | | | | | | | | | |
 /_/    \_\__,_|_| |_| |_|_|_| |_|
]]--

local ADMIN_FIX_RADIUS = 6.0

-- Vehicle the admin sits in, otherwise the closest one within ADMIN_FIX_RADIUS
local function getAdminFixVehicle(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 then return vehicle end
    local coords = GetEntityCoords(ped)
    local best, bestDistance = nil, ADMIN_FIX_RADIUS
    for _, entity in ipairs(GetAllVehicles()) do
        local distance = #(coords - GetEntityCoords(entity))
        if distance <= bestDistance then
            best, bestDistance = entity, distance
        end
    end
    return best
end

-- Full repair of the vehicle: mechanic parts on the server, native damage on the admin's client
lib.addCommand("mechanicadminfix", {
    help = "pls_mechanic - fully repair the vehicle you sit in (or the closest one)",
    restricted = Config.AdminGroup,
}, function(src)
    if src == 0 then
        print("[pls_mechanic] mechanicadminfix can be used in game only")
        return
    end
    local entity = getAdminFixVehicle(src)
    if not entity then
        Shops.Notify(src, locale("no_vehicle"), "error")
        return
    end
    local data = Vehicles.GetByEntity(entity)
    if data then
        Vehicles.FixAll(data.plate)
    end
    TriggerClientEvent("pls_mechanic:client:vehicles:adminFix", src, NetworkGetNetworkIdFromEntity(entity))
    local plate = data and data.plate or getPlate(entity) or "-"
    OpenServer.Log(src, "admin_fix", ("%s fully repaired vehicle %s (admin)"):format(GetPlayerName(src) or src, plate), { plate = plate })
end)
