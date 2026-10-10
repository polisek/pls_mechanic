--[[
  _____ _
 |_   _| |
   | | | |_ ___ _ __ ___  ___
   | | | __/ _ \ '_ ` _ \/ __|
  _| |_| ||  __/ | | | | \__ \
 |_____|\__\___|_| |_| |_|___/

 Parts in the inventory: counting, checking and consuming by the rules of the workshop (Config.StolenParts).
 Stolen parts are normal items with metadata { stolen = true, quality = 5..100, origin = "<vehicle>" } (pls_mechanic_illegal).
 - legal workshop (and no workshop): clean items only, legalAccepts = stolen ones too (clean first)
 - illegal workshop: stolen items first (lowest quality first), then clean ones
 - tools: any metadata
 - crates of a courier mission (metadata.courier) are never counted or consumed
 - inventory without metadata support (BRIDGE.GetItemSlots = nil): everything counts as clean
 Redefines the item functions of server/core.lua (this file is loaded right after it).
 shopId is always the last optional argument, nil = current shop of the player (Shops.GetPlayerShopId).
 Also registers the access rule of PLS stashes of illegal workshops (BRIDGE.SetStashAccessCheck).
]]--

ItemRules = {}

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

local function legalAccepts()
    return Config.StolenParts ~= nil and Config.StolenParts.legalAccepts == true
end

-- Crate of a courier mission, reserved for the mission
local function isReserved(metadata)
    return type(metadata) == "table" and metadata.courier ~= nil
end

local function resolveShopId(src, shopId)
    shopId = tonumber(shopId)
    if shopId then return shopId end
    local ok, current = pcall(Shops.GetPlayerShopId, src)
    return ok and current or nil
end

function ItemRules.IsStolen(metadata)
    return type(metadata) == "table" and metadata.stolen == true
end

-- Quality 5..100 (multiple of 5) of a stolen item, clean items are 100
function ItemRules.GetQuality(metadata)
    if not ItemRules.IsStolen(metadata) then return 100 end
    local quality = Utils.Clamp(tonumber(metadata.quality) or 100, 5, 100)
    return math.floor(quality / 5 + 0.5) * 5
end

-- "illegal" / "legal" (no shop = legal rules)
function ItemRules.GetShopKind(shopId)
    local shop = shopId and Shops.Get(shopId)
    return shop and shop.kind == "illegal" and "illegal" or "legal"
end

-- Slots { { slot, count, metadata } } -> usable slots in consumption order for the shop kind.
-- Adds stolen / quality to every entry.
function ItemRules.OrderSlots(slots, kind)
    local stolen, clean = {}, {}
    for _, entry in ipairs(slots or {}) do
        if type(entry) == "table" and not isReserved(entry.metadata) and (tonumber(entry.count) or 0) > 0 then
            if ItemRules.IsStolen(entry.metadata) then
                entry.stolen = true
                entry.quality = ItemRules.GetQuality(entry.metadata)
                stolen[#stolen + 1] = entry
            else
                entry.stolen = false
                entry.quality = 100
                clean[#clean + 1] = entry
            end
        end
    end
    table.sort(stolen, function(a, b)
        if a.quality ~= b.quality then return a.quality < b.quality end
        return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
    end)
    local result = {}
    local function append(list)
        for _, entry in ipairs(list) do
            result[#result + 1] = entry
        end
    end
    if kind == "illegal" then
        append(stolen)
        append(clean)
    else
        append(clean)
        if legalAccepts() then append(stolen) end
    end
    return result
end

-- Min quality of the stolen items in a consumed list (clean = 100), true when a stolen item was used
function ItemRules.GetConsumedQuality(consumed)
    local quality, stolen = 100, false
    for _, entry in ipairs(consumed or {}) do
        if entry.stolen then
            stolen = true
            quality = math.min(quality, tonumber(entry.quality) or 100)
        end
    end
    return quality, stolen
end

-- Usable slots of item in player's inventory, nil = inventory without metadata support
local function usableSlots(src, itemName, kind)
    local ok, slots = pcall(BRIDGE.GetItemSlots, src, itemName)
    if not ok then
        print("[pls_mechanic] BRIDGE.GetItemSlots error: "..tostring(slots))
        return nil
    end
    if type(slots) ~= "table" then return nil end
    return ItemRules.OrderSlots(slots, kind)
end

local function countFor(src, key, kind)
    local itemName = Utils.Item(key)
    local slots = usableSlots(src, itemName, kind)
    if not slots then
        return BRIDGE.GetItemCount(src, itemName) or 0
    end
    local count = 0
    for _, entry in ipairs(slots) do
        count = count + math.floor(tonumber(entry.count) or 0)
    end
    return count
end

local function addConsumed(consumed, key, count, entry)
    local metadata = entry and entry.metadata or nil
    local stolen = entry ~= nil and entry.stolen == true
    consumed[#consumed + 1] = {
        item = key,
        count = count,
        quality = entry and entry.quality or 100,
        stolen = stolen,
        origin = stolen and type(metadata.origin) == "string" and metadata.origin or nil,
        metadata = type(metadata) == "table" and next(metadata) ~= nil and metadata or nil,
    }
end

-- Removes count of item slot by slot in consumption order. Returns true when everything was removed
local function removeItem(src, key, count, kind, consumed)
    local itemName = Utils.Item(key)
    -- a slot can change meanwhile (other script), the slots are read once more
    for _ = 1, 2 do
        local slots = usableSlots(src, itemName, kind)
        if not slots then
            -- no metadata support: everything is clean
            if BRIDGE.RemoveItem(src, itemName, count) == false then return false end
            addConsumed(consumed, key, count, nil)
            return true
        end
        for _, entry in ipairs(slots) do
            if count <= 0 then break end
            local take = math.min(count, math.floor(tonumber(entry.count) or 0))
            if take > 0 then
                local ok, removed = pcall(BRIDGE.RemoveItemSlot, src, itemName, take, entry.slot)
                if not ok then
                    print("[pls_mechanic] BRIDGE.RemoveItemSlot error: "..tostring(removed))
                elseif removed == true then
                    count = count - take
                    addConsumed(consumed, key, take, entry)
                end
            end
        end
        if count <= 0 then return true end
    end
    return false
end

--[[
  _____ _
 |_   _| |
   | | | |_ ___ _ __ ___  ___
   | | | __/ _ \ '_ ` _ \/ __|
  _| |_| ||  __/ | | | | \__ \
 |_____|\__\___|_| |_| |_|___/
]]--

-- Usable count of item (Config.Items key) for the workshop
function Shops.CountItem(src, key, shopId)
    return countFor(src, key, ItemRules.GetShopKind(resolveShopId(src, shopId)))
end

-- Checks player has all items {{item = key, count = n}} usable in the workshop. Returns ok, missing list
function Shops.HasItems(src, items, multiplier, shopId)
    local kind = ItemRules.GetShopKind(resolveShopId(src, shopId))
    local missing = {}
    for _, v in pairs(items or {}) do
        local need = v.count * (multiplier or 1)
        local have = countFor(src, v.item, kind)
        if have < need then
            table.insert(missing, { item = v.item, count = need - have })
        end
    end
    return #missing == 0, missing
end

-- Checks tools (list of keys), any metadata. shopId is accepted for the common signature only
function Shops.HasTools(src, tools, shopId)
    for _, key in pairs(tools or {}) do
        if (BRIDGE.GetItemCount(src, Utils.Item(key)) or 0) < 1 then
            return false, key
        end
    end
    return true
end

-- Consumes items by the rules of the workshop.
-- Returns consumed list { { item = key, count, quality, stolen, origin, metadata } }, ok (false = something was missing)
function Shops.RemoveItems(src, items, multiplier, shopId)
    local kind = ItemRules.GetShopKind(resolveShopId(src, shopId))
    local consumed, ok = {}, true
    for _, v in pairs(items or {}) do
        local count = math.floor(v.count * (multiplier or 1))
        if count > 0 and not removeItem(src, v.item, count, kind, consumed) then
            ok = false
        end
    end
    return consumed, ok
end

-- Adds items {{item = key, count = n, metadata = table?}}. A consumed list can be given back the same way.
-- Returns false when something didn't fit
function Shops.AddItems(src, items, shopId)
    local ok = true
    for _, v in pairs(items or {}) do
        if BRIDGE.AddItem(src, Utils.Item(v.item), v.count, v.metadata) == false then
            ok = false
        end
    end
    return ok
end

--[[
   _____ _            _
  / ____| |          | |
 | (___ | |_ __ _ ___| |__
  \___ \| __/ _` / __| '_ \
  ____) | || (_| \__ \ | | |
 |_____/ \__\__,_|___/_| |_|

 PLS stashes (qb_inventory + BRIDGE.QBStashesReplaceByPLS) of illegal workshops have no job groups,
 the crew permission "storage" and the distance to a storage point decide (ShopsServer.CanOpenStash).
 Legal workshops keep the job groups of the stash, a wrong id (old / guessed key) is refused.
]]--

if BRIDGE.SetStashAccessCheck then
    BRIDGE.SetStashAccessCheck(function(src, stashName)
        local shopId = type(stashName) == "string" and tonumber(stashName:match("^pls_mechanic_stash_(%d+)")) or nil
        if not shopId then return nil end
        local shop = Shops.Get(shopId)
        if not shop or stashName ~= Shops.GetStashId(shop.id) then return false end
        if shop.kind ~= "illegal" then return nil end
        return ShopsServer.CanOpenStash(src, stashName) == true
    end)
end
