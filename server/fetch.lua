--[[
  ______   _       _
 |  ____| | |     | |
 | |__ ___| |_ ___| |__
 |  __/ _ \ __/ __| '_ \
 | | |  __/ || (__| | | |
 |_|  \___|\__\___|_| |_|

 Parts fetching during repair / tuning (client/fetch.lua):
 - stock of the workshop storage for the waiting overlay and the start check
 - quick take of the missing parts of a step at the storage point (permission "storage" + duty + distance)
 Stash access goes through BRIDGE.GetStashItemCount / BRIDGE.RemoveStashItem (nil = inventory not supported).
 With metadata support (BRIDGE.GetStashItemSlots) stock and quick take follow the rules of the workshop
 (server/items.lua: legal = clean parts only, illegal = stolen first) and items are moved slot by slot with their metadata.
]]--

FetchServer = {}

local Cooldowns = {}         -- [src][action] = GetGameTimer()

local MAX_STOCK_KEYS = 40
local MAX_TAKE_ENTRIES = 20
local MAX_TAKE_COUNT = 50
local POINT_MARGIN = 3.0     -- extra distance to storage point radius
local STOCK_COOLDOWN = 300   -- ms, client caches stock for ~2 s
local TAKE_COOLDOWN = 1500

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

local function toId(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return math.tointeger(number)
end

-- true when action is allowed (and stores the time), false when player is too fast
local function checkRate(src, action, ms)
    Cooldowns[src] = Cooldowns[src] or {}
    local now = GetGameTimer()
    local last = Cooldowns[src][action]
    if last and now - last < ms then
        return false
    end
    Cooldowns[src][action] = now
    return true
end

local function fail(message, extra)
    local response = extra or {}
    response.ok = false
    response.message = message
    return response
end

local function log(src, action, message, data)
    local ok, err = pcall(OpenServer.Log, src, action, message, data)
    if not ok then
        print("[pls_mechanic] OpenServer.Log error: "..tostring(err))
    end
end

-- Player works in the workshop: job of a legal workshop / crew member of an illegal one
local function belongsToShop(src, shop)
    local ok, member = pcall(Shops.IsMember, src, shop.id)
    return ok and member == true
end

-- Player stands at a storage point of the workshop (radius + margin)
local function isAtStorage(src, shop)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    for _, point in pairs(shop.points or {}) do
        if point.type == "storage" and point.coords then
            local pointType = Config.PointTypes[point.type]
            local radius = point.radius or (pointType and pointType.radius) or 2.0
            if #(coords - Utils.Vec3(point.coords)) <= radius + POINT_MARGIN then
                return true
            end
        end
    end
    return false
end

-- Usable slots of item in the storage in consumption order of the workshop kind, nil = no metadata support
local function stashSlots(stashId, itemName, kind)
    local ok, slots = pcall(BRIDGE.GetStashItemSlots, stashId, itemName)
    if not ok then
        print("[pls_mechanic] BRIDGE.GetStashItemSlots error: "..tostring(slots))
        return nil
    end
    if type(slots) ~= "table" then return nil end
    return ItemRules.OrderSlots(slots, kind)
end

-- Usable count of item in the storage. kind = workshop kind ("legal" / "illegal"), nil = unknown stock
local function stashCount(stashId, key, kind)
    local slots = stashSlots(stashId, Utils.Item(key), kind)
    if slots then
        local count = 0
        for _, entry in ipairs(slots) do
            count = count + math.floor(tonumber(entry.count) or 0)
        end
        return count
    end
    local ok, count = pcall(BRIDGE.GetStashItemCount, stashId, Utils.Item(key))
    if not ok then
        print("[pls_mechanic] BRIDGE.GetStashItemCount error: "..tostring(count))
        return nil
    end
    if count == nil then return nil end
    return math.max(0, math.floor(tonumber(count) or 0))
end

-- Stock keys from client: unique Config.Items keys, max MAX_STOCK_KEYS
local function sanitizeKeys(keys)
    if type(keys) ~= "table" then return nil end
    local list, seen = {}, {}
    for i, key in ipairs(keys) do
        if i > MAX_STOCK_KEYS then break end
        if type(key) == "string" and Config.Items[key] and not seen[key] then
            seen[key] = true
            list[#list + 1] = key
        end
    end
    return list
end

-- Take list from client { { item = key, count = n } } -> merged list or nil when anything is invalid
local function sanitizeTakeList(list)
    if type(list) ~= "table" then return nil end
    local entries, index = {}, {}
    local size = 0
    for _, entry in ipairs(list) do
        size = size + 1
        if size > MAX_TAKE_ENTRIES or type(entry) ~= "table" then return nil end
        local key, count = entry.item, toId(entry.count)
        if type(key) ~= "string" or not Config.Items[key] then return nil end
        if not count or count < 1 or count > MAX_TAKE_COUNT then return nil end
        if index[key] then
            index[key].count = math.min(index[key].count + count, MAX_TAKE_COUNT)
        else
            index[key] = { item = key, count = count }
            entries[#entries + 1] = index[key]
        end
    end
    if #entries == 0 then return nil end
    return entries
end

local function listToText(list)
    local parts = {}
    for _, v in ipairs(list) do
        parts[#parts + 1] = v.count.."x "..Utils.Item(v.item)
    end
    return table.concat(parts, ", ")
end

--[[
   _____ _             _
  / ____| |           | |
 | (___ | |_ ___   ___| | __
  \___ \| __/ _ \ / __| |/ /
  ____) | || (_) | (__|   <
 |_____/ \__\___/ \___|_|\_\
]]--

-- Count of Config.Items keys in workshop storage. Returns supported, { [key] = count }
function FetchServer.GetStock(shopId, keys)
    local stashId = Shops.GetStashId(shopId)
    local kind = ItemRules.GetShopKind(shopId)
    local stock = {}
    for _, key in ipairs(keys or {}) do
        local count = stashCount(stashId, key, kind)
        if count == nil then
            return false, {}
        end
        stock[key] = count
    end
    return true, stock
end

-- { supported = bool, stock = { [key] = count } }, nil when the player asks too often (client keeps its cache)
lib.callback.register("pls_mechanic:server:fetch:stock", function(src, shopId, keys)
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    local list = sanitizeKeys(keys)
    if not shop or not list or not belongsToShop(src, shop) then
        return { supported = false, stock = {} }
    end
    if not checkRate(src, "stock", STOCK_COOLDOWN) then return nil end
    local supported, stock = FetchServer.GetStock(shopId, list)
    return { supported = supported, stock = stock }
end)

--[[
  _______    _
 |__   __|  | |
    | | __ _| | _____
    | |/ _` | |/ / _ \
    | | (_| |   <  __/
    |_|\__,_|_|\_\___|
]]--

-- Parts go back to the storage (player can't carry them), metadata stays
local function putBack(stashId, itemName, count, metadata)
    local ok, added = pcall(BRIDGE.AddStashItem, stashId, itemName, count, metadata)
    if not ok or not added then
        print(("[pls_mechanic] Fetch: %sx %s couldn't be returned to storage %s (%s)"):format(count, itemName, stashId, tostring(added)))
    end
end

-- Moves up to count items slot by slot (usable slots in consumption order), each slot keeps its metadata.
-- Returns taken, notCarried (put back to the storage)
local function takeSlots(src, stashId, itemName, count, slots)
    local taken, full = 0, 0
    for _, slot in ipairs(slots) do
        local left = count - taken
        if left <= 0 then break end
        local take = math.min(left, math.floor(tonumber(slot.count) or 0))
        if take > 0 then
            local ok, removed = pcall(BRIDGE.RemoveStashItemSlot, stashId, itemName, take, slot.slot)
            if not ok then
                print("[pls_mechanic] BRIDGE.RemoveStashItemSlot error: "..tostring(removed))
            elseif removed == true then
                local metadata = type(slot.metadata) == "table" and next(slot.metadata) ~= nil and slot.metadata or nil
                local okAdd, added = pcall(BRIDGE.AddItem, src, itemName, take, metadata)
                if okAdd and added then
                    taken = taken + take
                else
                    -- weight / slots of the player, the rest isn't tried
                    putBack(stashId, itemName, take, metadata)
                    full = take
                    break
                end
            end
        end
    end
    return taken, full
end

-- Moves items (validated list) from the workshop storage to the player. No permission / distance checks here.
-- Returns { ok = true, taken, missing, full } | { ok = false, message, unsupported = true }
function FetchServer.Take(src, shopId, entries)
    local stashId = Shops.GetStashId(shopId)
    local kind = ItemRules.GetShopKind(shopId)
    local taken, missing, full = {}, {}, {}
    for _, entry in ipairs(entries) do
        local itemName = Utils.Item(entry.item)
        local slots = stashSlots(stashId, itemName, kind)
        local stock = nil
        if slots then
            stock = 0
            for _, slot in ipairs(slots) do
                stock = stock + math.floor(tonumber(slot.count) or 0)
            end
        else
            stock = stashCount(stashId, entry.item, kind)
        end
        -- inventory without stash support (nothing moved yet) -> the mechanic opens the storage himself
        if stock == nil and #taken == 0 and #full == 0 then
            return fail(locale("fetch_take_unsupported"), { unsupported = true })
        end
        local take = math.min(entry.count, stock or 0)
        local lacking = entry.count - take
        if slots then
            -- metadata support: slot by slot by the rules of the workshop
            local moved, notCarried = takeSlots(src, stashId, itemName, take, slots)
            if moved > 0 then taken[#taken + 1] = { item = entry.item, count = moved } end
            if notCarried > 0 then
                -- the rest stays in the storage, the player can't carry more
                full[#full + 1] = { item = entry.item, count = take - moved }
            else
                -- slots changed meanwhile (somebody else took them)
                lacking = lacking + (take - moved)
            end
        elseif take > 0 then
            local ok, removed = pcall(BRIDGE.RemoveStashItem, stashId, itemName, take)
            if not ok then
                print("[pls_mechanic] BRIDGE.RemoveStashItem error: "..tostring(removed))
                removed = false
            end
            if removed == nil and #taken == 0 and #full == 0 then
                return fail(locale("fetch_take_unsupported"), { unsupported = true })
            end
            if removed == true then
                local okAdd, added = pcall(BRIDGE.AddItem, src, itemName, take)
                if okAdd and added then
                    taken[#taken + 1] = { item = entry.item, count = take }
                else
                    -- weight / slots of the player
                    putBack(stashId, itemName, take)
                    full[#full + 1] = { item = entry.item, count = take }
                end
            else
                -- taken by somebody else in the meantime
                lacking = lacking + take
            end
        end
        if lacking > 0 then
            missing[#missing + 1] = { item = entry.item, count = lacking }
        end
    end
    return { ok = true, taken = taken, missing = missing, full = full }
end

lib.callback.register("pls_mechanic:server:fetch:take", function(src, shopId, list)
    shopId = toId(shopId)
    local shop = shopId and Shops.Get(shopId)
    if not shop then return fail(locale("fetch_take_failed")) end
    if not checkRate(src, "take", TAKE_COOLDOWN) then return fail(locale("shops_slow_down")) end
    if not Shops.HasPermission(src, "storage", shopId) then
        local perms = Shops.GetPermissions(src, shopId)
        -- illegal workshops have no duty
        return fail(locale(perms.storage and shop.kind ~= "illegal" and "not_on_duty" or "no_permission"))
    end
    if not isAtStorage(src, shop) then return fail(locale("too_far")) end
    local entries = sanitizeTakeList(list)
    if not entries then return fail(locale("fetch_take_failed")) end

    local response = FetchServer.Take(src, shopId, entries)
    if response.ok and (#response.taken > 0 or #response.full > 0) then
        local text = ("Took %s from storage of workshop #%s \"%s\""):format(#response.taken > 0 and listToText(response.taken) or "nothing", shopId, shop.name)
        if #response.full > 0 then
            text = text..(" (couldn't carry %s, returned)"):format(listToText(response.full))
        end
        log(src, "fetch", text, { shopId = shopId, taken = response.taken, missing = response.missing, full = response.full })
    end
    return response
end)

--[[
   _____ _
  / ____| |
 | |    | | ___  __ _ _ __  _   _ _ __
 | |    | |/ _ \/ _` | '_ \| | | | '_ \
 | |____| |  __/ (_| | | | | |_| | |_) |
  \_____|_|\___|\__,_|_| |_|\__,_| .__/
                                 | |
                                 |_|
]]--

AddEventHandler("playerDropped", function()
    Cooldowns[source] = nil
end)
