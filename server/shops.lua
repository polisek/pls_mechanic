--[[
   _____ _
  / ____| |
 | (___ | |__   ___  _ __  ___
  \___ \| '_ \ / _ \| '_ \/ __|
  ____) | | | | (_) | |_) \__ \
 |_____/|_| |_|\___/| .__/|___/
                    | |
                    |_|
 Admin creator, duty, storage, service vehicles and boss settings of workshops.
 Core data API lives in server/core.lua (Shops).
 Illegal workshops: created only while the DLC runs, owner goes to the DLC, no duty / settings.
]]--

ShopsServer = {}

local ServiceVehicles = {}   -- [src] = { netId, shopId, plate, model }
local Spawning = {}          -- [src] = true while service vehicle is being created
local Cooldowns = {}         -- [src][key] = GetGameTimer() of last action

local MAX_POINTS = 150
local MAX_JOBS = 10
local POINT_MARGIN = 3.0     -- extra distance to point radius for server checks
local GARAGE_MARGIN = 10.0
local VEHICLE_TYPES = {
    automobile = true, bike = true, boat = true, heli = true,
    plane = true, submarine = true, trailer = true, train = true,
}

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

local function isFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function toNumber(value, default)
    value = tonumber(value)
    if not isFinite(value) then return default end
    return value
end

-- Integer id from client value (1, 1.0, "1") or nil
local function toId(value)
    local number = tonumber(value)
    if not isFinite(number) then return nil end
    return math.tointeger(number)
end

-- Plain one line text limited to maxChars UTF-8 characters, nil when not a string
local function cleanText(value, maxChars)
    if type(value) ~= "string" then return nil end
    value = value:gsub("%c", " ")
    if not utf8.len(value) then
        value = value:gsub("[\128-\255]", "")
    end
    value = value:match("^%s*(.-)%s*$")
    local cut = utf8.offset(value, maxChars + 1)
    if cut then
        value = value:sub(1, cut - 1):match("^(.-)%s*$")
    end
    return value
end

local function isRateLimited(src, key, ms)
    local now = GetGameTimer()
    Cooldowns[src] = Cooldowns[src] or {}
    local last = Cooldowns[src][key]
    if last and now - last < ms then
        return true
    end
    Cooldowns[src][key] = now
    return false
end

local function result(ok, message, extra)
    local response = extra or {}
    response.ok = ok
    response.message = message
    return response
end

local function getPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function getPointRadius(point)
    local pointType = Config.PointTypes[point.type]
    return point.radius or (pointType and pointType.radius) or 2.0
end

-- First point of type the player stands in (radius + margin). Returns point, typeExists
local function getNearPoint(src, shop, pointType, margin)
    local coords = getPlayerCoords(src)
    local exists = false
    for _, point in pairs(shop and shop.points or {}) do
        if point.type == pointType and point.coords then
            exists = true
            if coords and #(coords - Utils.Vec3(point.coords)) <= getPointRadius(point) + (margin or POINT_MARGIN) then
                return point, true
            end
        end
    end
    return nil, exists
end

local function gradeKey(grade)
    return tostring(math.tointeger(tonumber(grade)) or grade)
end

local function getJobGrades(jobName)
    local ok, grades, jobLabel = pcall(BRIDGE.GetJobGrades, jobName)
    if not ok or type(grades) ~= "table" then
        return {}, jobName
    end
    return grades, jobLabel or jobName
end

-- Client copies (without the stash key) sorted by id
local function sortedShops()
    local list = {}
    for _, shop in pairs(Shops.GetAll()) do
        table.insert(list, Shops.ClientCopy(shop))
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

--[[
   _____             _ _   _
  / ____|           (_) | (_)
 | (___   __ _ _ __  _| |_ _ _______
  \___ \ / _` | '_ \| | __| |_  / _ \
  ____) | (_| | | | | | |_| |/ /  __/
 |_____/ \__,_|_| |_|_|\__|_/___\___|
]]--

local function sanitizeCoords(coords)
    local kind = type(coords)
    if kind ~= "table" and kind ~= "vector3" and kind ~= "vector4" then return nil end
    local x, y, z = toNumber(coords.x), toNumber(coords.y), toNumber(coords.z)
    if not x or not y or not z then return nil end
    if math.abs(x) > 50000 or math.abs(y) > 50000 or math.abs(z) > 5000 then return nil end
    return { x = Utils.Round(x, 3), y = Utils.Round(y, 3), z = Utils.Round(z, 3) }
end

local function optionValues(field)
    local values = {}
    for _, option in pairs(field.options or {}) do
        values[option.value] = true
    end
    return values
end

-- Value of Config.PointTypes[type].fields entry
local function sanitizeFieldValue(field, value)
    if field.type == "number" then
        local number = toNumber(value, toNumber(field.default, 0))
        if field.min then number = math.max(number, field.min) end
        if field.max then number = math.min(number, field.max) end
        return Utils.Round(Utils.Clamp(number, -1000000000, 1000000000), 2)
    elseif field.type == "checkbox" then
        if type(value) ~= "boolean" then
            return field.default == true
        end
        return value
    elseif field.type == "select" then
        if value ~= nil and optionValues(field)[value] then
            return value
        end
        return Utils.DeepCopy(field.default)
    elseif field.type == "multi-select" then
        if type(value) ~= "table" then
            return Utils.DeepCopy(field.default or {})
        end
        local allowed, list, seen = optionValues(field), {}, {}
        for _, v in ipairs(value) do
            if allowed[v] and not seen[v] then
                seen[v] = true
                table.insert(list, v)
            end
        end
        return list
    elseif field.type == "text" then
        return cleanText(value, 200) or Utils.DeepCopy(field.default or "")
    end
    return Utils.DeepCopy(field.default)
end

local function generatePointId(usedIds)
    local id
    repeat
        id = "p_"..os.time().."_"..math.random(1000, 9999)
    until not usedIds[id]
    return id
end

local function sanitizePoint(point, usedIds)
    if type(point) ~= "table" or type(point.type) ~= "string" then return nil end
    local pointType = Config.PointTypes[point.type]
    if not pointType then return nil end
    local coords = sanitizeCoords(point.coords)
    if not coords then return nil end

    local id = point.id
    if type(id) ~= "string" or #id > 64 or not id:match("^[%w_%-]+$") or usedIds[id] then
        id = generatePointId(usedIds)
    end
    usedIds[id] = true

    local data = {}
    local input = type(point.data) == "table" and point.data or {}
    for _, field in pairs(pointType.fields or {}) do
        data[field.key] = sanitizeFieldValue(field, input[field.key])
    end

    local heading = toNumber(point.heading, 0.0) % 360.0
    if not isFinite(heading) then heading = 0.0 end

    return {
        id = id,
        type = point.type,
        coords = coords,
        heading = Utils.Round(heading, 2),
        radius = Utils.Round(Utils.Clamp(toNumber(point.radius, pointType.radius or 2.0), 0.5, 15.0), 2),
        data = data,
    }
end

local function sanitizeJobs(jobs)
    local list, seen = {}, {}
    if type(jobs) == "string" then
        local split = {}
        for job in jobs:gmatch("[^,;%s]+") do
            table.insert(split, job)
        end
        jobs = split
    end
    if type(jobs) ~= "table" then return list end
    for _, job in ipairs(jobs) do
        job = cleanText(job, 50)
        if job and job ~= "" and not job:find("%s") and not seen[job] then
            seen[job] = true
            table.insert(list, job)
            if #list >= MAX_JOBS then break end
        end
    end
    return list
end

local function sanitizeBlip(blip)
    blip = type(blip) == "table" and blip or {}
    local default = Config.DefaultBlip
    local enabled = default.enabled == true
    if type(blip.enabled) == "boolean" then
        enabled = blip.enabled
    end
    return {
        enabled = enabled,
        sprite = math.floor(Utils.Clamp(toNumber(blip.sprite, default.sprite), 1, 999)),
        color = math.floor(Utils.Clamp(toNumber(blip.color, default.color), 0, 85)),
        scale = Utils.Round(Utils.Clamp(toNumber(blip.scale, default.scale), 0.1, 3.0), 2),
        coords = sanitizeCoords(blip.coords),
    }
end

-- Creator payload { name, kind, jobs, blip, points } -> clean data or nil, locale key
-- Only point types allowed for the workshop kind are kept, illegal workshops have no jobs and no blip.
local function sanitizeShop(payload)
    if type(payload) ~= "table" then return nil, "creator_invalid_data" end
    local name = cleanText(payload.name, 100)
    if not name or name == "" then return nil, "creator_invalid_name" end
    local kind = payload.kind == "illegal" and "illegal" or "legal"

    local points, usedIds, singleUsed = {}, {}, {}
    if type(payload.points) == "table" then
        for _, point in ipairs(payload.points) do
            if #points >= MAX_POINTS then break end
            local clean = sanitizePoint(point, usedIds)
            if clean and Shops.PointTypeAllowed(clean.type, kind) then
                local multiple = Config.PointTypes[clean.type].multiple ~= false
                if multiple or not singleUsed[clean.type] then
                    singleUsed[clean.type] = true
                    table.insert(points, clean)
                end
            end
        end
    end

    local blip = sanitizeBlip(payload.blip)
    if kind == "illegal" then
        blip.enabled = false
    end
    return {
        name = name,
        kind = kind,
        jobs = kind == "illegal" and {} or sanitizeJobs(payload.jobs),
        blip = blip,
        points = points,
    }
end

-- Owner of illegal workshop from creator (server id of an online player) or nil
local function sanitizeOwner(value)
    local owner = toId(value)
    if not owner or owner < 1 or not GetPlayerName(owner) then return nil end
    return owner
end

-- Keeps permissions of remaining jobs, removes removed jobs, adds defaults for new jobs
local function syncPermissions(current, jobs)
    local permissions = {}
    for _, job in ipairs(jobs) do
        if current and type(current[job]) == "table" then
            permissions[job] = Utils.DeepCopy(current[job])
        else
            permissions[job] = Shops.BuildDefaultPermissions(job)
        end
    end
    return permissions
end

-- Boss settings matrix: only shop jobs, only existing grades (string keys), only known perms, booleans
local function sanitizePermissions(shop, input)
    input = type(input) == "table" and input or {}
    local permissions = {}
    for _, jobName in ipairs(shop.jobs or {}) do
        local current = shop.permissions and shop.permissions[jobName] or {}
        local incoming = type(input[jobName]) == "table" and input[jobName] or {}
        local grades = getJobGrades(jobName)
        if #grades == 0 then
            -- framework returned no grades, never wipe the matrix because of it
            permissions[jobName] = Utils.DeepCopy(current)
        else
            permissions[jobName] = {}
            for _, grade in ipairs(grades) do
                local key = gradeKey(grade.grade)
                local old = type(current[key]) == "table" and current[key] or {}
                local new = incoming[key]
                if new == nil and tonumber(key) then
                    new = incoming[tonumber(key)]
                end
                local perms = {}
                for _, perm in ipairs(Config.PermissionList) do
                    local value = old[perm] == true
                    if type(new) == "table" and type(new[perm]) == "boolean" then
                        value = new[perm]
                    end
                    if value then
                        perms[perm] = true
                    end
                end
                permissions[jobName][key] = perms
            end
        end
    end
    return permissions
end

local function sanitizeSettings(current, input)
    current = type(current) == "table" and current or {}
    input = type(input) == "table" and input or {}
    local defaults = Config.DefaultShopSettings
    local settings = Utils.DeepCopy(current)

    local function number(key, min, max)
        local value = toNumber(input[key], toNumber(current[key], defaults[key]))
        return Utils.Clamp(value, min, max)
    end

    settings.laborMultiplier = Utils.Round(number("laborMultiplier", 0.1, 5.0), 2)
    settings.partsMarkup = math.floor(number("partsMarkup", 0, 300) + 0.5)
    settings.tuningMarkup = math.floor(number("tuningMarkup", 0, 300) + 0.5)
    settings.commission = math.floor(number("commission", 0, 100) + 0.5)

    local inputModes = type(input.supplyModes) == "table" and input.supplyModes or {}
    local currentModes = type(current.supplyModes) == "table" and current.supplyModes or {}
    settings.supplyModes = {}
    for mode, default in pairs(defaults.supplyModes) do
        if type(inputModes[mode]) == "boolean" then
            settings.supplyModes[mode] = inputModes[mode]
        elseif type(currentModes[mode]) == "boolean" then
            settings.supplyModes[mode] = currentModes[mode]
        else
            settings.supplyModes[mode] = default
        end
    end
    return settings
end

--[[
   _____                _
  / ____|              | |
 | |     _ __ ___  __ _| |_ ___  _ __
 | |    | '__/ _ \/ _` | __/ _ \| '__|
 | |____| | |  __/ (_| | || (_) | |
  \_____|_|  \___|\__,_|\__\___/|_|
]]--

lib.addCommand(Config.AdminCommand, {
    help = locale("creator_command_help"),
    restricted = Config.AdminGroup,
}, function(source)
    if not source or source <= 0 then return end
    TriggerClientEvent("pls_mechanic:client:creator:open", source)
end)

lib.callback.register("pls_mechanic:server:creator:getShops", function(src)
    if not Shops.IsAdmin(src) then return nil end
    return sortedShops()
end)

lib.callback.register("pls_mechanic:server:creator:save", function(src, payload)
    if not Shops.IsAdmin(src) then return result(false, locale("no_permission")) end
    if isRateLimited(src, "creator_save", 1000) then return result(false, locale("shops_slow_down")) end
    if not Shops.IsLoaded() then return result(false, locale("creator_not_loaded")) end

    local data, err = sanitizeShop(payload)
    if not data then return result(false, locale(err)) end

    -- illegal workshops are saved only with the DLC running (its point types would be dropped otherwise)
    if data.kind == "illegal" and not Shops.IllegalStarted() then
        return result(false, locale("creator_illegal_unavailable", Config.IllegalResource))
    end
    local owner = nil
    if data.kind == "illegal" and payload.owner ~= nil and payload.owner ~= "" then
        owner = sanitizeOwner(payload.owner)
        if not owner then return result(false, locale("creator_owner_invalid")) end
    end

    local shopId = toId(payload.id)
    local id = shopId
    if shopId then
        local shop = Shops.Get(shopId)
        if not shop then return result(false, locale("creator_shop_not_found")) end
        data.permissions = syncPermissions(shop.permissions, data.jobs)
        if not Shops.Update(shopId, data) then
            return result(false, locale("creator_save_failed"))
        end
        OpenServer.Log(src, "creator_update", ("Workshop #%s \"%s\" (%s) updated (%s points)"):format(shopId, data.name, data.kind, #data.points), { shopId = shopId, kind = data.kind, jobs = data.jobs })
    else
        data.permissions = syncPermissions(nil, data.jobs)
        data.settings = Utils.DeepCopy(Config.DefaultShopSettings)
        id = Shops.Create(data)
        if not id then return result(false, locale("creator_save_failed")) end
        OpenServer.Log(src, "creator_create", ("Workshop #%s \"%s\" (%s) created (%s points)"):format(id, data.name, data.kind, #data.points), { shopId = id, kind = data.kind, jobs = data.jobs })
    end

    if owner then
        if not Shops.SetIllegalOwner(id, owner) then
            return result(true, locale("creator_saved_owner_failed"), { id = id })
        end
        OpenServer.Log(src, "creator_owner", ("Owner of illegal workshop #%s set to %s (%s)"):format(id, GetPlayerName(owner) or "-", owner), { shopId = id, owner = owner })
    end
    return result(true, locale("creator_saved"), { id = id })
end)

-- Owner of existing illegal workshop (server id of an online player) -> DLC SetShopOwner
lib.callback.register("pls_mechanic:server:creator:setOwner", function(src, shopId, ownerId)
    if not Shops.IsAdmin(src) then return result(false, locale("no_permission")) end
    if isRateLimited(src, "creator_owner", 1000) then return result(false, locale("shops_slow_down")) end
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not shop then return result(false, locale("creator_shop_not_found")) end
    if shop.kind ~= "illegal" or not Shops.IllegalStarted() then
        return result(false, locale("creator_illegal_unavailable", Config.IllegalResource))
    end
    local owner = sanitizeOwner(ownerId)
    if not owner then return result(false, locale("creator_owner_invalid")) end
    if not Shops.SetIllegalOwner(shopId, owner) then return result(false, locale("creator_owner_failed")) end
    local name = GetPlayerName(owner) or tostring(owner)
    OpenServer.Log(src, "creator_owner", ("Owner of illegal workshop #%s \"%s\" set to %s (%s)"):format(shopId, shop.name, name, owner), { shopId = shopId, owner = owner })
    return result(true, locale("creator_owner_saved", name))
end)

lib.callback.register("pls_mechanic:server:creator:delete", function(src, shopId)
    if not Shops.IsAdmin(src) then return result(false, locale("no_permission")) end
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not shop then return result(false, locale("creator_shop_not_found")) end
    local name = shop.name
    if not Shops.Delete(shopId) then return result(false, locale("creator_save_failed")) end
    OpenServer.Log(src, "creator_delete", ("Workshop #%s \"%s\" deleted"):format(shopId, name), { shopId = shopId })
    return result(true, locale("creator_deleted", name))
end)

lib.callback.register("pls_mechanic:server:creator:resetPermissions", function(src, shopId)
    if not Shops.IsAdmin(src) then return result(false, locale("no_permission")) end
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not shop then return result(false, locale("creator_shop_not_found")) end
    if shop.kind == "illegal" then return result(false, locale("settings_illegal")) end
    local permissions = {}
    for _, job in ipairs(shop.jobs or {}) do
        permissions[job] = Shops.BuildDefaultPermissions(job)
    end
    Shops.Update(shopId, { permissions = permissions })
    OpenServer.Log(src, "creator_reset_permissions", ("Permissions of workshop #%s \"%s\" reset to defaults"):format(shopId, shop.name), { shopId = shopId })
    return result(true, locale("creator_permissions_reset"))
end)

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

-- Removes duty when player's job / duty permission doesn't fit the shop anymore
function ShopsServer.CheckDuty(src)
    local shopId = Player(src).state.pls_mechanic_duty
    if not shopId then return end
    local shop = Shops.Get(shopId)
    local valid = false
    if shop then
        local ok, allowed = pcall(function()
            local job = BRIDGE.GetPlayerJob(src)
            return Utils.ShopHasJob(shop, job) and Shops.GetPermissions(src, shopId).duty == true
        end)
        if not ok then return end -- player data not ready, try again later
        valid = allowed
    end
    if not valid then
        Shops.SetDuty(src, false)
        Shops.Notify(src, locale("shops_duty_removed"), "error")
    end
end

RegisterNetEvent("pls_mechanic:server:shops:toggleDuty", function(shopId)
    local src = source
    if not CanTrustPlayer(src) then return end
    if isRateLimited(src, "duty", 2000) then return end
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not shop or shop.kind == "illegal" then return end -- illegal workshops have no duty

    if Player(src).state.pls_mechanic_duty == shopId then
        Shops.SetDuty(src, false)
        Shops.Notify(src, locale("shops_duty_off", shop.name), "inform")
        OpenServer.Log(src, "duty_off", ("Clocked out of workshop #%s \"%s\""):format(shopId, shop.name), { shopId = shopId })
        return
    end

    if not Shops.HasPermission(src, "duty", shopId) then
        Shops.Notify(src, locale("no_permission"), "error")
        return
    end
    local near, hasDutyPoint = getNearPoint(src, shop, "duty")
    if hasDutyPoint and not near then
        Shops.Notify(src, locale("too_far"), "error")
        return
    end

    Shops.SetDuty(src, shopId)
    Shops.Notify(src, locale("shops_duty_on", shop.name), "success")
    OpenServer.Log(src, "duty_on", ("Clocked in at workshop #%s \"%s\""):format(shopId, shop.name), { shopId = shopId })
end)

-- Jobs / permissions of shop changed -> re-check players on duty there right away
AddEventHandler("pls_mechanic:server:shopsChanged", function(shopId, action)
    if action ~= "update" then return end
    for _, playerId in pairs(GetPlayers()) do
        local src = tonumber(playerId)
        if Player(src).state.pls_mechanic_duty == shopId then
            ShopsServer.CheckDuty(src)
        end
    end
end)

--[[
   _____ _
  / ____| |
 | (___ | |_ ___  _ __ __ _  __ _  ___
  \___ \| __/ _ \| '__/ _` |/ _` |/ _ \
  ____) | || (_) | | | (_| | (_| |  __/
 |_____/ \__\___/|_|  \__,_|\__, |\___|
                             __/ |
                            |___/
]]--

lib.callback.register("pls_mechanic:server:shops:openStash", function(src, shopId)
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not shop then return false end
    if not Shops.HasPermission(src, "storage", shopId) then
        local perms = Shops.GetPermissions(src, shopId)
        Shops.Notify(src, locale(perms.storage and "not_on_duty" or "no_permission"), "error")
        return false
    end
    if not getNearPoint(src, shop, "storage") then
        Shops.Notify(src, locale("too_far"), "error")
        return false
    end
    return Shops.GetStashId(shopId)
end)

-- Stash access rule shared by the ox_inventory hook and PLS stashes (server/items.lua).
-- Returns true / false for workshop stashes, nil when stashName isn't a workshop stash.
-- The id must be the current id of the workshop (illegal: with its key), illegal workshops also need the player
-- at one of their storage points.
function ShopsServer.CanOpenStash(src, stashName)
    local shopId = type(stashName) == "string" and tonumber(stashName:match("^pls_mechanic_stash_(%d+)")) or nil
    if not shopId then return nil end
    local shop = Shops.Get(shopId)
    if not shop or stashName ~= Shops.GetStashId(shop.id) then return false end
    if not Shops.HasPermission(src, "storage", shop.id) then return false end
    if shop.kind == "illegal" and not getNearPoint(src, shop, "storage") then return false end
    return true
end

-- ox_inventory: workshop stashes open only for players with the "storage" permission of that workshop
-- (illegal stashes have no job groups). Hook API: registerHook("openInventory", fn(payload), { inventoryFilter })
-- payload = { source, inventoryId, inventoryType }, returning false keeps the inventory closed.
if BRIDGE.Inventory == "ox_inventory" then
    CreateThread(function()
        if GetResourceState("ox_inventory") ~= "started" then
            print("[pls_mechanic] ox_inventory is not started, workshop stash hook was not registered")
            return
        end
        local ok, err = pcall(function()
            exports.ox_inventory:registerHook("openInventory", function(payload)
                if ShopsServer.CanOpenStash(payload.source, tostring(payload.inventoryId)) == false then
                    return false
                end
            end, {
                -- legal "pls_mechanic_stash_<id>", illegal "pls_mechanic_stash_<id>_<key>"
                inventoryFilter = { "^pls_mechanic_stash_%d+" },
            })
        end)
        if not ok then
            print("[pls_mechanic] ox_inventory registerHook error: "..tostring(err))
        end
    end)
end

--[[
   _____                 _                       _     _      _
  / ____|               (_)                     | |   (_)    | |
 | (___   ___ _ ____   ___  ___ ___  __   _____| |__  _  ___| | ___  ___
  \___ \ / _ \ '__\ \ / / |/ __/ _ \ \ \ / / _ \ '_ \| |/ __| |/ _ \/ __|
  ____) |  __/ |   \ V /| | (_|  __/  \ V /  __/ | | | | (__| |  __/\__ \
 |_____/ \___|_|    \_/ |_|\___\___|   \_/ \___|_| |_|_|\___|_|\___||___/
]]--

-- Returns entity, data of player's service vehicle (nil when it doesn't exist anymore).
-- Server record only (net id + entity handle), the statebag pls_mech_service can be written by the owner client.
function ShopsServer.GetServiceVehicle(src)
    local data = ServiceVehicles[src]
    if not data then return nil end
    local entity = NetworkGetEntityFromNetworkId(data.netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) and (not data.entity or entity == data.entity) then
        return entity, data
    end
    ServiceVehicles[src] = nil
    return nil
end

-- Is entity a mechanic service vehicle (server record)? Returns bool, shopId, owner src
function ShopsServer.IsServiceVehicle(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    for src, data in pairs(ServiceVehicles) do
        if data.entity == entity or NetworkGetEntityFromNetworkId(data.netId) == entity then
            return true, data.shopId, src
        end
    end
    return false
end

function ShopsServer.DeleteServiceVehicle(src)
    local entity = ShopsServer.GetServiceVehicle(src)
    if entity then
        DeleteEntity(entity)
    end
    ServiceVehicles[src] = nil
end

local function isAreaOccupied(coords, radius)
    for _, vehicle in pairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - coords) < radius then
            return true
        end
    end
    return false
end

local function generatePlate()
    local used = {}
    for _, data in pairs(ServiceVehicles) do
        used[data.plate] = true
    end
    local plate
    repeat
        plate = "MECH"..math.random(100, 999)
    until not used[plate]
    return plate
end

-- vehicleType = type of model detected by client (server can't read model info), whitelisted
lib.callback.register("pls_mechanic:server:shops:spawnVehicle", function(src, shopId, index, vehicleType)
    shopId, index = toId(shopId), toId(index)
    local shop = shopId and Shops.Get(shopId)
    local vehicleData = index and Config.ServiceVehicles[index]
    if not shop or not vehicleData then return false end
    if isRateLimited(src, "service_vehicle", 3000) then
        Shops.Notify(src, locale("shops_slow_down"), "error")
        return false
    end
    if not Shops.HasPermission(src, "duty", shopId) then
        Shops.Notify(src, locale("no_permission"), "error")
        return false
    end
    if Config.RequireDuty and Player(src).state.pls_mechanic_duty ~= shopId then
        Shops.Notify(src, locale("not_on_duty"), "error")
        return false
    end
    local point = getNearPoint(src, shop, "garage", GARAGE_MARGIN)
    if not point then
        Shops.Notify(src, locale("too_far"), "error")
        return false
    end
    if Spawning[src] or ShopsServer.GetServiceVehicle(src) then
        Shops.Notify(src, locale("shops_vehicle_already"), "error")
        return false
    end
    local spawn = Utils.Vec3(point.coords)
    if isAreaOccupied(spawn, 3.0) then
        Shops.Notify(src, locale("shops_garage_blocked"), "error")
        return false
    end

    if VEHICLE_TYPES[vehicleData.type] then
        vehicleType = vehicleData.type
    elseif not VEHICLE_TYPES[vehicleType] then
        vehicleType = "automobile"
    end

    -- the waits below would let a second request spawn another (never deleted) vehicle
    Spawning[src] = true
    local entity = CreateVehicleServerSetter(joaat(vehicleData.model), vehicleType, spawn.x, spawn.y, spawn.z + 1.0, (point.heading or 0.0) + 0.0)
    local timeout = GetGameTimer() + 5000
    while (not entity or entity == 0 or not DoesEntityExist(entity)) and GetGameTimer() < timeout do
        Wait(50)
    end
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        Spawning[src] = nil
        Shops.Notify(src, locale("shops_vehicle_failed"), "error")
        return false
    end

    -- keep it when the owner walks away, deleted by us on return / drop / stop (native missing on old artifacts)
    if SetEntityOrphanMode then
        SetEntityOrphanMode(entity, 2)
    end

    -- RPC setters need an owner client
    timeout = GetGameTimer() + 3000
    while NetworkGetEntityOwner(entity) == -1 and GetGameTimer() < timeout do
        Wait(50)
    end
    Spawning[src] = nil
    if not DoesEntityExist(entity) then
        Shops.Notify(src, locale("shops_vehicle_failed"), "error")
        return false
    end
    if not GetPlayerName(src) then
        -- player left while waiting, nobody would delete the vehicle
        DeleteEntity(entity)
        return false
    end

    local plate = generatePlate()
    SetVehicleNumberPlateText(entity, plate)
    -- the owner client may apply the plate text later, the server plate is the trusted one right away
    if Vehicles and Vehicles.SetTrustedPlate then
        Vehicles.SetTrustedPlate(entity, plate)
    end
    Entity(entity).state:set("pls_mech_service", { owner = src, shopId = shopId, plate = plate }, true)

    local netId = NetworkGetNetworkIdFromEntity(entity)
    ServiceVehicles[src] = { netId = netId, entity = entity, shopId = shopId, plate = plate, model = vehicleData.model }
    OpenServer.Log(src, "service_vehicle_spawn", ("Service vehicle %s (%s) spawned at workshop #%s"):format(vehicleData.model, plate, shopId), { shopId = shopId, plate = plate })
    return netId, plate
end)

-- true = player has no service vehicle anymore (returned / already gone)
lib.callback.register("pls_mechanic:server:shops:returnVehicle", function(src, shopId)
    if isRateLimited(src, "service_vehicle_return", 1500) then return false end
    local entity, data = ShopsServer.GetServiceVehicle(src)
    if not entity then
        Shops.Notify(src, locale("shops_vehicle_none"), "inform")
        return true
    end
    local near = Shops.IsNearEntity(src, entity, 10.0)
    if not near then
        for _, id in pairs({ toId(shopId), data.shopId }) do
            if getNearPoint(src, Shops.Get(id), "garage", GARAGE_MARGIN) then
                near = true
                break
            end
        end
    end
    if not near then
        Shops.Notify(src, locale("too_far"), "error")
        return false
    end
    DeleteEntity(entity)
    ServiceVehicles[src] = nil
    Shops.Notify(src, locale("shops_vehicle_returned"), "success")
    OpenServer.Log(src, "service_vehicle_return", ("Service vehicle %s returned"):format(data.plate), { shopId = data.shopId, plate = data.plate })
    return true
end)

--[[
   _____      _   _   _
  / ____|    | | | | (_)
 | (___   ___| |_| |_ _ _ __   __ _ ___
  \___ \ / _ \ __| __| | '_ \ / _` / __|
  ____) |  __/ |_| |_| | | | | (_| \__ \
 |_____/ \___|\__|\__|_|_| |_|\__, |___/
                               __/ |
                              |___/
]]--

local function canManageShop(src, shopId)
    if Shops.IsAdmin(src) then return true end
    local ok = Shops.HasPermission(src, "manage_shop", shopId)
    return ok == true
end

local function buildSettingsData(shop)
    local jobs, permissions = {}, {}
    for _, jobName in ipairs(shop.jobs or {}) do
        local grades, jobLabel = getJobGrades(jobName)
        local current = shop.permissions and shop.permissions[jobName] or {}
        local gradeList = {}
        permissions[jobName] = {}
        for _, grade in ipairs(grades) do
            local key = gradeKey(grade.grade)
            local perms = {}
            for _, perm in ipairs(Config.PermissionList) do
                perms[perm] = type(current[key]) == "table" and current[key][perm] == true or false
            end
            permissions[jobName][key] = perms
            table.insert(gradeList, { grade = math.tointeger(tonumber(grade.grade)) or grade.grade, label = grade.label or key })
        end
        table.insert(jobs, { name = jobName, label = jobLabel, grades = gradeList })
    end

    local permissionList = {}
    for _, perm in ipairs(Config.PermissionList) do
        table.insert(permissionList, { key = perm, label = locale("perm_"..perm) })
    end

    local settings = sanitizeSettings(shop.settings, nil)
    return {
        shopId = shop.id,
        shopName = shop.name,
        canEdit = true,
        jobs = jobs,
        permissions = permissions,
        permissionList = permissionList,
        settings = {
            laborMultiplier = settings.laborMultiplier,
            partsMarkup = settings.partsMarkup,
            tuningMarkup = settings.tuningMarkup,
            commission = settings.commission,
            supplyModes = settings.supplyModes,
        },
    }
end

lib.callback.register("pls_mechanic:server:shops:getSettings", function(src, shopId)
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not shop then return nil end
    -- illegal workshops have no permission matrix (the crew decides) and use default prices
    if shop.kind == "illegal" then
        Shops.Notify(src, locale("settings_illegal"), "error")
        return nil
    end
    if not canManageShop(src, shopId) then
        Shops.Notify(src, locale("no_permission"), "error")
        return nil
    end
    return buildSettingsData(shop)
end)

lib.callback.register("pls_mechanic:server:shops:saveSettings", function(src, shopId, payload)
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not shop then return result(false, locale("settings_shop_not_found")) end
    if shop.kind == "illegal" then return result(false, locale("settings_illegal")) end
    if not canManageShop(src, shopId) then return result(false, locale("no_permission")) end
    if isRateLimited(src, "settings_save", 1500) then return result(false, locale("shops_slow_down")) end
    if type(payload) ~= "table" then return result(false, locale("settings_invalid")) end

    local isAdmin = Shops.IsAdmin(src)
    local permissions = sanitizePermissions(shop, payload.permissions)
    if not isAdmin then
        -- boss can't lock himself out of the settings
        local job, grade = Shops.GetPlayerJobInfo(src)
        local own = permissions[job] and permissions[job][gradeKey(grade)]
        if own then
            own.manage_shop = true
        end
    end
    local settings = sanitizeSettings(shop.settings, payload.settings)

    if not Shops.Update(shopId, { permissions = permissions, settings = settings }) then
        return result(false, locale("settings_save_failed"))
    end
    OpenServer.Log(src, "settings_save", ("Settings of workshop #%s \"%s\" saved"):format(shopId, shop.name), { shopId = shopId, settings = settings })
    local saved = buildSettingsData(Shops.Get(shopId))
    return result(true, locale("settings_saved"), { permissions = saved.permissions, settings = saved.settings })
end)

--[[
  __          __   _       _         _
  \ \        / /  | |     | |       | |
   \ \  /\  / /_ _| |_ ___| |__   __| | ___   __ _
    \ \/  \/ / _` | __/ __| '_ \ / _` |/ _ \ / _` |
     \  /\  / (_| | || (__| | | | (_| | (_) | (_| |
      \/  \/ \__,_|\__\___|_| |_|\__,_|\___/ \__, |
                                              __/ |
                                             |___/
]]--

--[[
 Workshop account deposit - society account of the first job (Shops.GetSocietyJob)
]]--

local function canDeposit(src, shop)
    if not Config.Deposit.enabled or not shop then return false end
    if Shops.IsAdmin(src) then return true end
    return Utils.ShopHasJob(shop, BRIDGE.GetPlayerJob(src))
end

local function depositMethodAllowed(method)
    for _, allowed in ipairs(Config.Deposit.methods) do
        if allowed == method then return true end
    end
    return false
end

lib.callback.register("pls_mechanic:server:shops:getAccount", function(src, shopId)
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not canDeposit(src, shop) then return result(false, locale("no_permission")) end
    local job = Shops.GetSocietyJob(shopId)
    if not job then return result(false, locale("shops_deposit_no_account")) end
    if not BRIDGE.HasSocietyAccount(job) then return result(false, locale("shops_deposit_no_society", BRIDGE.GetSocietyAccountName(job))) end
    return result(true, nil, {
        balance = math.floor(BRIDGE.GetSocietyMoney(job) or 0),
        cash = math.floor(BRIDGE.GetItemCount(src, "money") or 0),
        bank = math.floor(BRIDGE.GetPlayerBankMoney(src) or 0),
    })
end)

lib.callback.register("pls_mechanic:server:shops:deposit", function(src, shopId, amount, method)
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not canDeposit(src, shop) then return result(false, locale("no_permission")) end
    if isRateLimited(src, "deposit", 2000) then return result(false, locale("shops_slow_down")) end
    if not getNearPoint(src, shop, "computer") then return result(false, locale("too_far")) end
    local job = Shops.GetSocietyJob(shopId)
    if not job then return result(false, locale("shops_deposit_no_account")) end

    amount = toId(amount)
    if not amount or amount < 1 or amount > Config.Deposit.max or not depositMethodAllowed(method) then
        return result(false, locale("shops_deposit_invalid", Config.Deposit.max))
    end
    -- money is taken only when the account exists
    if not BRIDGE.HasSocietyAccount(job) then
        return result(false, locale("shops_deposit_no_society", BRIDGE.GetSocietyAccountName(job)))
    end
    if method == "bank" then
        if (BRIDGE.GetPlayerBankMoney(src) or 0) < amount then return result(false, locale("not_enough_money")) end
        if not BRIDGE.RemovePlayerBankMoney(src, amount) then return result(false, locale("not_enough_money")) end
    else
        if (BRIDGE.GetItemCount(src, "money") or 0) < amount then return result(false, locale("not_enough_money")) end
        if BRIDGE.RemoveItem(src, "money", amount) == false then return result(false, locale("not_enough_money")) end
    end
    if not BRIDGE.AddSocietyMoney(job, amount) then
        -- refund
        if method == "bank" then
            BRIDGE.AddPlayerBankMoney(src, amount)
        else
            BRIDGE.AddItem(src, "money", amount)
        end
        return result(false, locale("shops_deposit_no_society", BRIDGE.GetSocietyAccountName(job)))
    end
    OpenServer.Log(src, "deposit", ("Deposit %d (%s) to workshop #%s \"%s\""):format(amount, method, shopId, shop.name), { shopId = shopId, amount = amount, method = method })
    return result(true, locale("shops_deposit_done", amount, shop.name))
end)

CreateThread(function()
    while true do
        Wait(60000)
        for _, playerId in pairs(GetPlayers()) do
            ShopsServer.CheckDuty(tonumber(playerId))
        end
        for src in pairs(ServiceVehicles) do
            ShopsServer.GetServiceVehicle(src) -- drops entries of vehicles that don't exist anymore
        end
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    ShopsServer.DeleteServiceVehicle(src)
    Spawning[src] = nil
    Cooldowns[src] = nil
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(ServiceVehicles) do
        ShopsServer.DeleteServiceVehicle(src)
    end
end)
