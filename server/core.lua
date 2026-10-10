lib.locale()

--[[
   _____
  / ____|
 | |     ___  _ __ ___
 | |    / _ \| '__/ _ \
 | |___| (_) | | |  __/
  \_____\___/|_|  \___|

 Shared server API for all modules:
 Shops    - workshops, permissions, duty, locations, illegal workshops of the DLC
 WorkLog  - work done by mechanic on vehicle (prefills bill)
 History  - service history of vehicles (database)
]]--

Shops = {}
WorkLog = {}
History = {}

local ShopList = {}       -- [id] = shop
local ShopsLoaded = false
local WorkLogs = {}       -- [src][plate] = { entries }
local PrivateState = {}   -- [src] = true when the client has illegal workshops from us
local PrivateRequests = {} -- [src] = GetGameTimer() of the last private workshops request
local LoadedResends = {}  -- [src] = GetGameTimer() of the last resend after character load

local PRIVATE_EVENT = "pls_mechanic:client:shops:private"

-- Point types of config.lua, other resources can't replace them
local BuiltInPointTypes = {}
for key in pairs(Config.PointTypes) do
    BuiltInPointTypes[key] = true
end

--[[
  _____        _        _
 |  __ \      | |      | |
 | |  | | __ _| |_ __ _| |__   __ _ ___  ___
 | |  | |/ _` | __/ _` | '_ \ / _` / __|/ _ \
 | |__| | (_| | || (_| | |_) | (_| \__ \  __/
 |_____/ \__,_|\__\__,_|_.__/ \__,_|___/\___|
]]--

local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pls_mechanic_shops` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(100) NOT NULL,
            `data` LONGTEXT NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pls_mechanic_vehicles` (
            `plate` VARCHAR(12) NOT NULL,
            `mileage` DOUBLE NOT NULL DEFAULT 0,
            `data` LONGTEXT NOT NULL,
            `updated_at` INT(11) NOT NULL DEFAULT 0,
            PRIMARY KEY (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pls_mechanic_history` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `plate` VARCHAR(12) NOT NULL,
            `shop_id` INT(11) NULL DEFAULT NULL,
            `mechanic` VARCHAR(100) NULL DEFAULT NULL,
            `type` VARCHAR(20) NOT NULL,
            `label` VARCHAR(255) NOT NULL,
            `data` LONGTEXT NULL DEFAULT NULL,
            `mileage` DOUBLE NOT NULL DEFAULT 0,
            `created_at` INT(11) NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            INDEX `plate` (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pls_mechanic_bills` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `shop_id` INT(11) NOT NULL,
            `mechanic` VARCHAR(100) NOT NULL,
            `mechanic_name` VARCHAR(100) NULL DEFAULT NULL,
            `customer` VARCHAR(100) NULL DEFAULT NULL,
            `customer_name` VARCHAR(100) NULL DEFAULT NULL,
            `plate` VARCHAR(12) NULL DEFAULT NULL,
            `lines` LONGTEXT NOT NULL,
            `note` TEXT NULL DEFAULT NULL,
            `total` INT(11) NOT NULL DEFAULT 0,
            `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
            `created_at` INT(11) NOT NULL DEFAULT 0,
            `paid_at` INT(11) NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            INDEX `shop_id` (`shop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pls_mechanic_orders` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `shop_id` INT(11) NOT NULL,
            `charid` VARCHAR(100) NULL DEFAULT NULL,
            `name` VARCHAR(100) NULL DEFAULT NULL,
            `items` LONGTEXT NOT NULL,
            `total` INT(11) NOT NULL DEFAULT 0,
            `mode` VARCHAR(20) NOT NULL,
            `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
            `deliver_at` INT(11) NULL DEFAULT NULL,
            `created_at` INT(11) NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            INDEX `shop_id` (`shop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

--[[
   _____ _
  / ____| |
 | (___ | |__   ___  _ __  ___
  \___ \| '_ \ / _ \| '_ \/ __|
  ____) | | | | (_) | |_) \__ \
 |_____/|_| |_|\___/| .__/|___/
                    | |
                    |_|
]]--

local STASH_KEY_LENGTH = 16
local STASH_KEY_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"

-- Stash of the workshop storage. Illegal workshops have a random persisted key in the id (inventories that open stashes
-- by a client event can't be opened by a guessed id), legal workshops keep the plain id (existing stash contents).
-- A workshop that was illegal once keeps its key.
function Shops.GetStashId(shopId)
    local shop = ShopList[tonumber(shopId)]
    if shop and type(shop.stashKey) == "string" and shop.stashKey ~= "" then
        return ("pls_mechanic_stash_%s_%s"):format(shop.id, shop.stashKey)
    end
    return "pls_mechanic_stash_"..shopId
end

local function generateStashKey()
    local chars = {}
    for i = 1, STASH_KEY_LENGTH do
        local index = math.random(1, #STASH_KEY_CHARS)
        chars[i] = STASH_KEY_CHARS:sub(index, index)
    end
    return table.concat(chars)
end

-- Coords of the storage points (ox_inventory opens the stash only near them): vector3, list or nil
local function storageCoords(shop)
    local list = {}
    for _, point in ipairs(shop.points or {}) do
        if point.type == "storage" and point.coords then
            list[#list + 1] = Utils.Vec3(point.coords)
        end
    end
    if #list == 0 then return nil end
    return #list == 1 and list[1] or list
end

-- Illegal workshop stash has no job groups, the crew access + distance to a storage point is checked when it's opened
local function registerStash(shop)
    local groups, coords = nil, nil
    if shop.kind ~= "illegal" then
        groups = {}
        for _, job in pairs(shop.jobs or {}) do
            groups[job] = 0
        end
    else
        coords = storageCoords(shop)
    end
    BRIDGE.RegisterStash(Shops.GetStashId(shop.id), shop.name, Config.Stash.slots, Config.Stash.weight, groups, coords)
end

-- Copy of a shop for clients (GlobalState, private sync, creator): without the stash key
function Shops.ClientCopy(shop)
    if not shop then return nil end
    local copy = {}
    for key, value in pairs(shop) do
        if key ~= "stashKey" then
            copy[key] = value
        end
    end
    return copy
end

-- Fills missing values of shop (new settings after update of script). Returns shop, changed (stash key generated)
local function normalizeShop(shop)
    local changed = false
    shop.kind = shop.kind == "illegal" and "illegal" or "legal"
    if type(shop.stashKey) ~= "string" or not shop.stashKey:match("^%w+$") then
        shop.stashKey = nil
    end
    if shop.kind == "illegal" and not shop.stashKey then
        shop.stashKey = generateStashKey()
        changed = true
    end
    shop.jobs = shop.jobs or {}
    shop.points = shop.points or {}
    shop.permissions = shop.permissions or {}
    shop.blip = shop.blip or Utils.DeepCopy(Config.DefaultBlip)
    if shop.kind == "illegal" then
        -- the DLC crew decides access: no jobs, permission matrix or blip
        shop.jobs = {}
        shop.permissions = {}
        shop.blip.enabled = false
    end
    shop.settings = shop.settings or {}
    for key, value in pairs(Config.DefaultShopSettings) do
        if shop.settings[key] == nil then
            shop.settings[key] = Utils.DeepCopy(value)
        end
    end
    for key, value in pairs(Config.DefaultShopSettings.supplyModes) do
        if shop.settings.supplyModes[key] == nil then
            shop.settings.supplyModes[key] = value
        end
    end
    for _, point in pairs(shop.points) do
        point.data = point.data or {}
        local pointType = Config.PointTypes[point.type]
        if pointType and pointType.fields then
            for _, field in pairs(pointType.fields) do
                if point.data[field.key] == nil then
                    point.data[field.key] = Utils.DeepCopy(field.default)
                end
            end
        end
    end
    return shop, changed
end

-- Default permission matrix for job by Config.DefaultPermissions
function Shops.BuildDefaultPermissions(jobName)
    local grades = BRIDGE.GetJobGrades(jobName)
    local result = {}
    local highest = grades[#grades] and grades[#grades].grade or 0
    for _, v in pairs(grades) do
        local perms = {}
        if v.grade == highest then
            for _, perm in pairs(Config.PermissionList) do
                perms[perm] = true
            end
        else
            local closest = nil
            for grade, _ in pairs(Config.DefaultPermissions) do
                if grade <= v.grade and (not closest or grade > closest) then
                    closest = grade
                end
            end
            if closest then
                perms = Utils.DeepCopy(Config.DefaultPermissions[closest])
            end
        end
        result[tostring(v.grade)] = perms
    end
    return result
end

-- GlobalState list for clients (legal workshops only), illegal workshops go privately to their crews
function Shops.Publish()
    local list = {}
    for _, shop in pairs(ShopList) do
        if shop.kind ~= "illegal" then
            table.insert(list, Shops.ClientCopy(shop))
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    GlobalState:set("pls_mechanic_shops", list, true)
    Shops.SyncPrivate()
end

local function serializeShop(shop)
    return json.encode({
        kind = shop.kind,
        jobs = shop.jobs,
        blip = shop.blip,
        points = shop.points,
        permissions = shop.permissions,
        settings = shop.settings,
        stashKey = shop.stashKey,
    })
end

function Shops.Get(shopId)
    return ShopList[tonumber(shopId)]
end

function Shops.GetAll()
    return ShopList
end

function Shops.IsLoaded()
    return ShopsLoaded
end

-- Plain copy of shop for other resources (exports): { id, name, kind, points, settings }
function Shops.PublicCopy(shop)
    if not shop then return nil end
    local points = {}
    for _, point in ipairs(shop.points or {}) do
        points[#points + 1] = {
            id = point.id,
            type = point.type,
            coords = Utils.DeepCopy(point.coords),
            heading = point.heading,
            radius = point.radius,
            data = Utils.DeepCopy(point.data or {}),
        }
    end
    return {
        id = shop.id,
        name = shop.name,
        kind = shop.kind or "legal",
        points = points,
        settings = Utils.DeepCopy(shop.settings or {}),
    }
end

-- data = { name, kind, jobs, blip, points, permissions, settings } - missing permissions are generated
function Shops.Create(data)
    local shop = normalizeShop({
        name = data.name,
        kind = data.kind,
        jobs = data.jobs,
        blip = data.blip,
        points = data.points,
        permissions = data.permissions,
        settings = data.settings,
    })
    for _, job in pairs(shop.jobs) do
        if not shop.permissions[job] then
            shop.permissions[job] = Shops.BuildDefaultPermissions(job)
        end
    end
    local id = MySQL.insert.await("INSERT INTO `pls_mechanic_shops` (`name`, `data`) VALUES (?, ?)", { shop.name, serializeShop(shop) })
    if not id then return nil end
    shop.id = id
    ShopList[id] = shop
    registerStash(shop)
    Shops.Publish()
    TriggerEvent("pls_mechanic:server:shopsChanged", id, "create")
    return id
end

-- Replaces whole shop data (creator / boss settings). Keeps id.
function Shops.Update(shopId, data)
    local shop = Shops.Get(shopId)
    if not shop then return false end
    local wasIllegal = shop.kind == "illegal"
    for key, value in pairs(data) do
        -- the stash key is generated here only, never taken from data
        if key ~= "id" and key ~= "stashKey" then
            shop[key] = value
        end
    end
    normalizeShop(shop)
    if wasIllegal and shop.kind ~= "illegal" then
        -- workshop is legal now, the DLC drops its crew
        Shops.CallIllegal("OnShopDeleted", shop.id)
    end
    for _, job in pairs(shop.jobs) do
        if not shop.permissions[job] then
            shop.permissions[job] = Shops.BuildDefaultPermissions(job)
        end
    end
    MySQL.update.await("UPDATE `pls_mechanic_shops` SET `name` = ?, `data` = ? WHERE `id` = ?", { shop.name, serializeShop(shop), shop.id })
    registerStash(shop)
    Shops.Publish()
    TriggerEvent("pls_mechanic:server:shopsChanged", shop.id, "update")
    return true
end

function Shops.Delete(shopId)
    local shop = Shops.Get(shopId)
    if not shop then return false end
    MySQL.update.await("DELETE FROM `pls_mechanic_shops` WHERE `id` = ?", { shop.id })
    ShopList[shop.id] = nil
    for _, playerId in pairs(GetPlayers()) do
        local src = tonumber(playerId)
        if Player(src).state.pls_mechanic_duty == shop.id then
            Shops.SetDuty(src, false)
        end
    end
    if shop.kind == "illegal" then
        Shops.CallIllegal("OnShopDeleted", shop.id)
    end
    Shops.Publish()
    TriggerEvent("pls_mechanic:server:shopsChanged", shopId, "delete")
    return true
end

--[[
  _____                    _         _
 |  __ \                  (_)       (_)
 | |__) |__ _ __ _ __ ___  _ ___ ___ _  ___  _ __  ___
 |  ___/ _ \ '__| '_ ` _ \| / __/ __| |/ _ \| '_ \/ __|
 | |  |  __/ |  | | | | | | \__ \__ \ | (_) | | | \__ \
 |_|   \___|_|  |_| |_| |_|_|___/___/_|\___/|_| |_|___/
]]--

function Shops.IsAdmin(src)
    return IsPlayerAceAllowed(src, "command."..Config.AdminCommand)
end

function Shops.GetPlayerJobInfo(src)
    return BRIDGE.GetPlayerJob(src), BRIDGE.GetPlayerGrade(src)
end

-- All shops where player job works
function Shops.GetPlayerShops(src)
    local job = BRIDGE.GetPlayerJob(src)
    local result = {}
    for _, shop in pairs(ShopList) do
        if Utils.ShopHasJob(shop, job) then
            table.insert(result, shop)
        end
    end
    return result
end

function Shops.IsMechanic(src)
    return #Shops.GetPlayerShops(src) > 0
end

-- Current shop of player: the illegal workshop he stands in and has crew access to (a legal mechanic in a crew
-- works for the crew there), otherwise the duty shop (or first shop of player's job when duty is not required)
function Shops.GetPlayerShopId(src)
    local illegal = Shops.GetIllegalShopAt(src)
    if illegal then
        return illegal
    end
    local duty = Player(src).state.pls_mechanic_duty
    if duty and ShopList[duty] then
        return duty
    end
    if not Config.RequireDuty then
        local shops = Shops.GetPlayerShops(src)
        table.sort(shops, function(a, b) return a.id < b.id end)
        if shops[1] then
            return shops[1].id
        end
    end
    return nil
end

-- Illegal workshop: perms of the DLC crew, legal workshop: job grade matrix
function Shops.GetPermissions(src, shopId)
    local shop = Shops.Get(shopId)
    if not shop then return {} end
    if shop.kind == "illegal" then
        return Shops.GetIllegalAccess(src, shop.id) or {}
    end
    local job, grade = Shops.GetPlayerJobInfo(src)
    return Utils.GetShopPermissions(shop, job, grade)
end

-- Returns true, shopId when player can do perm. shopId nil = player's current shop (duty / illegal workshop he stands in).
-- Duty is required for everything except "duty", "bossmenu" and "manage_shop" (when Config.RequireDuty).
-- Illegal workshops have no duty, the crew access is enough.
function Shops.HasPermission(src, perm, shopId)
    shopId = shopId or Shops.GetPlayerShopId(src)
    if not shopId then
        -- player is not on duty, allow "duty" / boss permissions on any of his shops is done with explicit shopId
        return false, nil
    end
    local shop = Shops.Get(shopId)
    if not shop then return false, nil end
    local perms = Shops.GetPermissions(src, shop.id)
    if not perms[perm] then
        return false, shop.id
    end
    if shop.kind ~= "illegal" and Config.RequireDuty and perm ~= "duty" and perm ~= "bossmenu" and perm ~= "manage_shop" then
        if Player(src).state.pls_mechanic_duty ~= shop.id then
            return false, shop.id
        end
    end
    return true, shop.id
end

-- Player works in the workshop: job of a legal workshop / crew member of an illegal one (no duty check)
function Shops.IsMember(src, shopId)
    local shop = Shops.Get(shopId)
    if not shop then return false end
    if shop.kind == "illegal" then
        return Shops.GetIllegalAccess(src, shop.id) ~= nil
    end
    local ok, job = pcall(BRIDGE.GetPlayerJob, src)
    return ok and Utils.ShopHasJob(shop, job)
end

--[[
  _____ _ _                  _
 |_   _| | |                | |
   | | | | | ___  __ _  __ _| |
   | | | | |/ _ \/ _` |/ _` | |
  _| |_| | |  __/ (_| | (_| | |
 |_____|_|_|\___|\__, |\__,_|_|
                  __/ |
                 |___/
 Illegal workshops of the DLC (Config.IllegalResource). The BASE only asks the DLC exports
 (GetShopAccess / SetShopOwner / OnShopDeleted), every call is guarded and wrapped in pcall.
]]--

function Shops.IsIllegal(shopOrId)
    local shop = type(shopOrId) == "table" and shopOrId or ShopList[tonumber(shopOrId)]
    return shop ~= nil and shop.kind == "illegal"
end

function Shops.IllegalStarted()
    return GetResourceState(Config.IllegalResource) == "started"
end

-- Calls export of the DLC. Returns ok, result (ok = false when the DLC is not started or the call failed)
function Shops.CallIllegal(name, ...)
    if not Shops.IllegalStarted() then return false, nil end
    -- indexing a missing export throws too
    local ok, result = pcall(function(...)
        return exports[Config.IllegalResource][name](nil, ...)
    end, ...)
    if not ok then
        print(("[pls_mechanic] %s export %s error: %s"):format(Config.IllegalResource, name, tostring(result)))
        return false, nil
    end
    return true, result
end

-- Crew perms of player in illegal workshop { [perm] = true } or nil (not in the crew / DLC stopped)
function Shops.GetIllegalAccess(src, shopId)
    local ok, access = Shops.CallIllegal("GetShopAccess", src, tonumber(shopId))
    if not ok or type(access) ~= "table" then return nil end
    local perms = {}
    for perm, value in pairs(access) do
        if type(perm) == "string" and value == true then
            perms[perm] = true
        end
    end
    return perms
end

-- Distance from coords to the closest point of shop (nil = no points)
local function distanceToShop(shop, coords)
    local closest = nil
    for _, point in pairs(shop.points or {}) do
        if point.coords then
            local distance = #(coords - Utils.Vec3(point.coords))
            if not closest or distance < closest then
                closest = distance
            end
        end
    end
    return closest
end

-- Illegal workshop the player stands in (Config.IllegalShopRadius from any of its points) with crew access.
-- Returns shopId, perms or nil
function Shops.GetIllegalShopAt(src)
    if not Shops.IllegalStarted() then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    local candidates = {}
    for id, shop in pairs(ShopList) do
        if shop.kind == "illegal" then
            local distance = distanceToShop(shop, coords)
            if distance and distance <= Config.IllegalShopRadius then
                candidates[#candidates + 1] = { id = id, distance = distance }
            end
        end
    end
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    for _, candidate in ipairs(candidates) do
        local perms = Shops.GetIllegalAccess(src, candidate.id)
        if perms then
            return candidate.id, perms
        end
    end
    return nil
end

-- Creator: online player becomes the owner of the crew. Returns bool
function Shops.SetIllegalOwner(shopId, ownerSrc)
    local ok, result = Shops.CallIllegal("SetShopOwner", tonumber(shopId), ownerSrc)
    if not ok or result == false then return false end
    Shops.SyncPrivate(ownerSrc)
    return true
end

-- Illegal workshops for one player: crew members get their workshops + perms, admins all of them (creator)
function Shops.BuildPrivate(src)
    local payload = { shops = {}, perms = {} }
    if not Shops.IllegalStarted() then return payload end
    local admin = Shops.IsAdmin(src)
    local list = {}
    for _, shop in pairs(ShopList) do
        if shop.kind == "illegal" then
            list[#list + 1] = shop
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    for _, shop in ipairs(list) do
        local perms = Shops.GetIllegalAccess(src, shop.id)
        if perms or admin then
            -- the stash key never goes to a client (only the storage callback returns the stash id)
            payload.shops[#payload.shops + 1] = Shops.ClientCopy(shop)
            payload.perms[shop.id] = perms
        end
    end
    return payload
end

local function sendPrivate(src)
    if not GetPlayerName(src) then return end
    local payload = Shops.BuildPrivate(src)
    local hasShops = #payload.shops > 0
    -- the client starts without illegal workshops, empty data is sent only to clear old ones
    if not hasShops and not PrivateState[src] then return end
    PrivateState[src] = hasShops or nil
    TriggerClientEvent(PRIVATE_EVENT, src, payload)
end

-- Re-sends illegal workshops + crew perms (nil = everyone). DLC calls it after crew changes (export RefreshShopAccess).
function Shops.SyncPrivate(src)
    if not ShopsLoaded then return end
    if src then
        sendPrivate(tonumber(src))
        return
    end
    for _, playerId in pairs(GetPlayers()) do
        sendPrivate(tonumber(playerId))
    end
end

-- Point type can be placed in workshop kind (Config.PointTypes[type].kinds, missing = legal only)
function Shops.PointTypeAllowed(pointType, kind)
    local data = Config.PointTypes[pointType]
    if not data then return false end
    local kinds = type(data.kinds) == "table" and data.kinds or { legal = true }
    return kinds[kind or "legal"] == true
end

-- Adds point type of another resource (export RegisterPointType). Built-in types can't be replaced.
-- def = { label, icon, radius, multiple, kinds = { illegal = true }, fields?, color? = { r, g, b } }
function Shops.RegisterPointType(key, def)
    if type(key) ~= "string" or #key > 32 or not key:match("^[%w_]+$") then return false end
    if BuiltInPointTypes[key] or type(def) ~= "table" then return false end
    local kinds = {}
    for kind, value in pairs(type(def.kinds) == "table" and def.kinds or {}) do
        if (kind == "legal" or kind == "illegal") and value == true then
            kinds[kind] = true
        end
    end
    if next(kinds) == nil then
        kinds.legal = true
    end
    Config.PointTypes[key] = {
        label = type(def.label) == "string" and def.label or key,
        icon = type(def.icon) == "string" and def.icon or "fa-solid fa-location-dot",
        radius = Utils.Clamp(tonumber(def.radius) or 1.5, 0.5, 15.0),
        multiple = def.multiple ~= false,
        kinds = kinds,
        fields = type(def.fields) == "table" and Utils.DeepCopy(def.fields) or nil,
        color = type(def.color) == "table" and Utils.DeepCopy(def.color) or nil,
    }
    -- points placed before the registration get default values of the fields
    if ShopsLoaded and Config.PointTypes[key].fields then
        for _, shop in pairs(ShopList) do
            normalizeShop(shop)
        end
        Shops.Publish()
    end
    return true
end

--[[
  _____        _
 |  __ \      | |
 | |  | |_   _| |_ _   _
 | |  | | | | | __| | | |
 | |__| | |_| | |_| |_| |
 |_____/ \__,_|\__|\__, |
                    __/ |
                   |___/
]]--

-- shopId = false -> off duty
function Shops.SetDuty(src, shopId)
    local previous = Player(src).state.pls_mechanic_duty or false
    Player(src).state:set("pls_mechanic_duty", shopId or false, true)
    TriggerEvent("pls_mechanic:server:dutyChanged", src, shopId or false)
    -- open hook (duty time in a boss menu...), only on a real change
    if previous ~= (shopId or false) and OpenServer.OnDutyChanged then
        local okJob, job = pcall(BRIDGE.GetPlayerJob, src)
        local ok, err = pcall(OpenServer.OnDutyChanged, src, shopId and true or false, ShopList[shopId or previous], okJob and job or nil)
        if not ok then
            print(("^1[pls_mechanic] OpenServer.OnDutyChanged: %s^0"):format(tostring(err)))
        end
    end
end

function Shops.CountOnDuty(shopId)
    local count = 0
    for _, playerId in pairs(GetPlayers()) do
        local duty = Player(tonumber(playerId)).state.pls_mechanic_duty
        if duty and (not shopId or duty == shopId) then
            count = count + 1
        end
    end
    return count
end

function Shops.GetSocietyJob(shopId)
    local shop = Shops.Get(shopId)
    return shop and shop.jobs[1] or nil
end

--[[
  _                     _   _
 | |                   | | (_)
 | |     ___   ___ __ _| |_ _  ___  _ __
 | |    / _ \ / __/ _` | __| |/ _ \| '_ \
 | |___| (_) | (_| (_| | |_| | (_) | | | |
 |______\___/ \___\__,_|\__|_|\___/|_| |_|
]]--

-- Bay point at coords. purpose = "repair" / "tuning" / nil (any). Returns point, shop
function Shops.GetBayAt(coords, purpose)
    for _, shop in pairs(ShopList) do
        for _, point in pairs(shop.points) do
            if point.type == "bay" and (not purpose or Utils.BayAccepts(point, purpose)) then
                if #(coords - Utils.Vec3(point.coords)) <= (point.radius or Config.PointTypes.bay.radius) then
                    return point, shop
                end
            end
        end
    end
    return nil, nil
end

function Shops.GetLiftAt(coords)
    for _, shop in pairs(ShopList) do
        for _, point in pairs(shop.points) do
            if point.type == "lift" then
                if #(coords - Utils.Vec3(point.coords)) <= (point.radius or Config.PointTypes.lift.radius) then
                    return point, shop
                end
            end
        end
    end
    return nil, nil
end

-- Checks location requirement of repair on vehicle entity.
-- location = "anywhere" / "bay" / "lift" / "lift_or_jack"; wheel = wheel index for per wheel repairs (jack must be on that side)
-- Returns ok, reason (locale key)
function Shops.CheckLocation(entity, location, wheel)
    if not location or location == "anywhere" then return true end
    if not DoesEntityExist(entity) then return false, "no_vehicle" end
    -- server records of lift module, statebags are only fallback (client owner can write them)
    local onLift, jackWheel
    if LiftServer and LiftServer.IsOnLift then
        onLift = LiftServer.IsOnLift(entity)
        jackWheel = LiftServer.GetJackWheel(entity)
    else
        local state = Entity(entity).state
        onLift = state.pls_lift ~= nil and state.pls_lift ~= false
        jackWheel = state.pls_jack and state.pls_jack.wheel or nil
    end
    if location == "lift" then
        return onLift, "location_lift"
    end
    if location == "bay" then
        if onLift then return true end
        local point = Shops.GetBayAt(GetEntityCoords(entity), "repair")
        return point ~= nil, "location_bay"
    end
    if location == "lift_or_jack" then
        if onLift then return true end
        if jackWheel then
            if wheel == nil or jackWheel == Utils.WheelSides[wheel] then
                return true
            end
        end
        return false, "location_lift_or_jack"
    end
    return true
end

--[[
 __          __        _      _
 \ \        / /       | |    | |
  \ \  /\  / /__  _ __| | __ | |     ___   __ _
   \ \/  \/ / _ \| '__| |/ / | |    / _ \ / _` |
    \  /\  / (_) | |  |   <  | |___| (_) | (_| |
     \/  \/ \___/|_|  |_|\_\ |______\___/ \__, |
                                           __/ |
                                          |___/
 entry = { label = string, labor = number?, items = {{item = key, count = n}}?, price = number? }
 price = final price (tuning), otherwise billing computes labor + parts
 Plates are resolved to the real plate (fake plate alias of the illegal DLC, Vehicles.ResolvePlate).
]]--

local function resolvePlate(plate)
    plate = Utils.TrimPlate(plate)
    if plate and Vehicles and Vehicles.ResolvePlate then
        return Vehicles.ResolvePlate(plate) or plate
    end
    return plate
end

function WorkLog.Add(src, plate, entry)
    plate = resolvePlate(plate)
    WorkLogs[src] = WorkLogs[src] or {}
    WorkLogs[src][plate] = WorkLogs[src][plate] or {}
    entry.time = os.time()
    table.insert(WorkLogs[src][plate], entry)
end

function WorkLog.Get(src, plate)
    plate = resolvePlate(plate)
    return WorkLogs[src] and WorkLogs[src][plate] or {}
end

function WorkLog.GetPlates(src)
    local plates = {}
    for plate, entries in pairs(WorkLogs[src] or {}) do
        if #entries > 0 then
            table.insert(plates, plate)
        end
    end
    return plates
end

function WorkLog.Clear(src, plate)
    if WorkLogs[src] then
        WorkLogs[src][resolvePlate(plate)] = nil
    end
end

--[[
  _    _ _     _
 | |  | (_)   | |
 | |__| |_ ___| |_ ___  _ __ _   _
 |  __  | / __| __/ _ \| '__| | | |
 | |  | | \__ \ || (_) | |  | |_| |
 |_|  |_|_|___/\__\___/|_|   \__, |
                              __/ |
                             |___/
 data = { shopId, mechanic (name), type = "service"/"core"/"body"/"tuning"/"kit"/"station", label, items, mileage }
]]--

function History.Add(plate, data)
    -- work in illegal workshops never gets into the service book
    if data.shopId and Shops.IsIllegal(data.shopId) then return end
    plate = resolvePlate(plate)
    MySQL.insert("INSERT INTO `pls_mechanic_history` (`plate`, `shop_id`, `mechanic`, `type`, `label`, `data`, `mileage`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", {
        plate,
        data.shopId,
        data.mechanic,
        data.type or "service",
        data.label or "",
        json.encode(data.items or {}),
        data.mileage or 0,
        os.time(),
    })
end

-- Returns list newest first: { id, plate, shopId, shopName, mechanic, type, label, items, mileage, date (unix) }
function History.Get(plate, limit)
    plate = resolvePlate(plate)
    local rows = MySQL.query.await("SELECT * FROM `pls_mechanic_history` WHERE `plate` = ? ORDER BY `id` DESC LIMIT ?", { plate, limit or 100 }) or {}
    local result = {}
    for _, row in pairs(rows) do
        local shop = row.shop_id and Shops.Get(row.shop_id)
        table.insert(result, {
            id = row.id,
            plate = row.plate,
            shopId = row.shop_id,
            shopName = shop and shop.name or "-",
            mechanic = row.mechanic or "-",
            type = row.type,
            label = row.label,
            items = json.decode(row.data or "[]") or {},
            mileage = row.mileage,
            date = row.created_at,
        })
    end
    return result
end

--[[
  _    _ _   _ _ _ _   _
 | |  | | | (_) (_) | (_)
 | |  | | |_ _| |_| |_ _  ___  ___
 | |  | | __| | | | __| |/ _ \/ __|
 | |__| | |_| | | | |_| |  __/\__ \
  \____/ \__|_|_|_|\__|_|\___||___/
]]--

-- Player is close to entity (anti cheat for all vehicle actions)
function Shops.IsNearEntity(src, entity, maxDistance)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local ped = GetPlayerPed(src)
    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= (maxDistance or 8.0)
end

-- First point of type in the shop the player stands in (point radius + margin, default 3 m). Returns point or nil
function Shops.GetNearPoint(src, shopId, pointType, margin)
    local shop = Shops.Get(shopId)
    local ped = GetPlayerPed(src)
    if not shop or not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    for _, point in ipairs(shop.points or {}) do
        if point.type == pointType and point.coords then
            local typeData = Config.PointTypes[point.type]
            local radius = point.radius or (typeData and typeData.radius) or 2.0
            if #(coords - Utils.Vec3(point.coords)) <= radius + (tonumber(margin) or 3.0) then
                return point
            end
        end
    end
    return nil
end

-- Entity from net id with existence check
function Shops.GetEntity(netId)
    if not netId then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    return entity
end

-- Item functions (Shops.CountItem / HasItems / HasTools / RemoveItems / AddItems) with stolen parts rules: server/items.lua

function Shops.Notify(src, description, notifyType)
    BRIDGE.Notify(src, {
        title = locale("script_title"),
        description = description,
        type = notifyType or "inform",
    })
end

--[[
  _____       _ _
 |_   _|     (_) |
   | |  _ __  _| |_
   | | | '_ \| | __|
  _| |_| | | | | |_
 |_____|_| |_|_|\__|
]]--

AddEventHandler("onResourceStart", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    createTables()
    local rows = MySQL.query.await("SELECT * FROM `pls_mechanic_shops`") or {}
    for _, row in pairs(rows) do
        local data = json.decode(row.data or "{}") or {}
        data.id = row.id
        data.name = row.name
        local shop, changed = normalizeShop(data)
        ShopList[shop.id] = shop
        if changed then
            -- stash key of an illegal workshop created before the keys existed
            MySQL.update.await("UPDATE `pls_mechanic_shops` SET `data` = ? WHERE `id` = ?", { serializeShop(shop), shop.id })
        end
        registerStash(shop)
    end
    ShopsLoaded = true
    Shops.Publish()
    TriggerEvent("pls_mechanic:server:shopsLoaded")

    -- Usable items for ESX / QB inventories (ox_inventory uses client export from items.lua)
    if BRIDGE.Inventory ~= "ox_inventory" then
        for _, key in pairs(Config.UsableItems) do
            BRIDGE.RegisterUsableItem(Utils.Item(key), "pls_mechanic:client:useItem")
        end
    end
end)

-- Client asks for its illegal workshops when it starts (a push during the resource start could come too early)
lib.callback.register("pls_mechanic:server:shops:private", function(src)
    local now = GetGameTimer()
    if PrivateRequests[src] and now - PrivateRequests[src] < 2000 then return nil end
    PrivateRequests[src] = now
    local timeout = now + 15000
    while not ShopsLoaded and GetGameTimer() < timeout do
        Wait(250)
    end
    local payload = Shops.BuildPrivate(src)
    PrivateState[src] = #payload.shops > 0 or nil
    return payload
end)

-- Character loaded (BRIDGE event, crew is bound to the character). Only a rate limited resend.
AddEventHandler(GetCurrentResourceName()..":playerLoaded", function(playerId)
    -- a client calling it for another player's id
    if BRIDGE.IsSpoofedPlayerLoaded and BRIDGE.IsSpoofedPlayerLoaded(playerId) then return end
    local src = tonumber(playerId)
    if not src or not GetPlayerName(src) then return end
    local now = GetGameTimer()
    if LoadedResends[src] and now - LoadedResends[src] < 2000 then return end
    LoadedResends[src] = now
    SetTimeout(1000, function()
        Shops.SyncPrivate(src)
    end)
end)

-- DLC started / stopped (local resource lifecycle events): illegal workshops appear / disappear for the crews
AddEventHandler("onResourceStart", function(resource)
    if resource ~= Config.IllegalResource then return end
    -- the DLC loads its crews after the start
    SetTimeout(2000, function()
        Shops.SyncPrivate()
    end)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= Config.IllegalResource then return end
    Shops.SyncPrivate()
end)

AddEventHandler("playerDropped", function()
    local src = source
    WorkLogs[src] = nil
    PrivateState[src] = nil
    PrivateRequests[src] = nil
    LoadedResends[src] = nil
end)

-- Debug of workshop society accounts (server console): /mechsociety [job]
lib.addCommand("mechsociety", {
    help = "pls_mechanic - debug society account of workshop job",
    params = { { name = "job", type = "string", help = "Job name (default: jobs of all workshops)", optional = true } },
    restricted = Config.AdminGroup,
}, function(src, args)
    local jobs = {}
    if args.job then
        jobs[1] = args.job
    else
        for _, shop in pairs(ShopList) do
            print(("[pls_mechanic] workshop #%s \"%s\" jobs: %s (account uses the first one)"):format(shop.id, shop.name, table.concat(shop.jobs, ", ")))
            if shop.jobs[1] then jobs[#jobs + 1] = shop.jobs[1] end
        end
    end
    print(("[pls_mechanic] framework=%s esx_addonaccount=%s esx_society=%s"):format(BRIDGE.Framework, GetResourceState("esx_addonaccount"), GetResourceState("esx_society")))
    local names = {}
    local shared = GlobalState.SharedAccounts
    if type(shared) == "table" then
        for name in pairs(shared) do names[#names + 1] = tostring(name) end
    end
    print(("[pls_mechanic] esx_addonaccount loaded shared accounts: %s"):format(#names > 0 and table.concat(names, ", ") or "NONE"))
    for _, job in pairs(jobs) do
        local society = nil
        TriggerEvent("esx_society:getSociety", job, function(result) society = result end)
        print(("[pls_mechanic] esx_society:getSociety('%s') -> %s"):format(job, society and ("registered, account = "..tostring(society.account)) or "not registered"))
        local accountName = society and society.account or ("society_"..job)
        local viaEvent = nil
        TriggerEvent("esx_addonaccount:getSharedAccount", accountName, function(account) viaEvent = account end)
        print(("[pls_mechanic] event getSharedAccount('%s') -> %s"):format(accountName, viaEvent and ("found, money = "..tostring(viaEvent.money)) or "nil"))
        local ok, viaExport = pcall(function() return exports["esx_addonaccount"]:GetSharedAccount(accountName) end)
        print(("[pls_mechanic] export GetSharedAccount('%s') -> %s"):format(accountName, not ok and ("error: "..tostring(viaExport)) or (viaExport and ("found, money = "..tostring(viaExport.money)) or "nil")))
        print(("[pls_mechanic] BRIDGE.HasSocietyAccount('%s') -> %s"):format(job, tostring(BRIDGE.HasSocietyAccount(job))))
    end
    if src and src > 0 then
        Shops.Notify(src, "Society debug printed to the server console.", "inform")
    end
end)
