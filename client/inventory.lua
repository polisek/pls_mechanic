--[[
  _____                      _
 |_   _|                    | |
   | |  _ ____   _____ _ __ | |_ ___  _ __ _   _
   | | | '_ \ \ / / _ \ '_ \| __/ _ \| '__| | | |
  _| |_| | | \ V /  __/ | | | || (_) | |  | |_| |
 |_____|_| |_|\_/ \___|_| |_|\__\___/|_|   \__, |
                                            __/ |
                                           |___/
 Client side of the consumption rules of server/items.lua (UI and pre-checks only, the server checks again):
 - legal workshop (and no workshop): clean items only (Config.StolenParts.legalAccepts = stolen ones too)
 - illegal workshop: clean + stolen items
 - tools: any metadata, crates of a courier mission (metadata.courier) never count
 - inventory without metadata support (BRIDGE.GetItemSlots = nil): everything counts as clean
 Redefines the item functions of client/main.lua (this file is loaded right after it).
 shopId is always the last optional argument, nil = current shop (Core.GetMyShopId).
]]--

local function isStolen(metadata)
    return type(metadata) == "table" and metadata.stolen == true
end

local function isReserved(metadata)
    return type(metadata) == "table" and metadata.courier ~= nil
end

local function acceptsStolen(shopId)
    shopId = shopId or Core.GetMyShopId()
    local shop = shopId and Core.GetShop(shopId)
    if shop and shop.kind == "illegal" then return true end
    return Config.StolenParts ~= nil and Config.StolenParts.legalAccepts == true
end

-- Usable count from the slots, nil = inventory without metadata support
local function countSlots(itemName, stolenOk)
    local ok, slots = pcall(BRIDGE.GetItemSlots, itemName)
    if not ok or type(slots) ~= "table" then return nil end
    local count = 0
    for _, entry in ipairs(slots) do
        if type(entry) == "table" and not isReserved(entry.metadata) and (stolenOk or not isStolen(entry.metadata)) then
            count = count + math.floor(tonumber(entry.count) or 0)
        end
    end
    return count
end

-- Usable count of item by Config.Items key for the workshop
function Core.CountItem(key, shopId)
    local itemName = Utils.Item(key)
    local count = countSlots(itemName, acceptsStolen(shopId))
    if count == nil then
        return BRIDGE.GetItemCount(itemName) or 0
    end
    return count
end

-- Count of a tool (any metadata)
function Core.CountTool(key)
    return BRIDGE.GetItemCount(Utils.Item(key)) or 0
end

-- Checks items {{item = key, count = n}}. Returns ok, list of { item, label, count, have }
function Core.CheckItems(items, multiplier, shopId)
    local ok = true
    local list = {}
    for _, v in pairs(items or {}) do
        local name = Utils.Item(v.item)
        local need = v.count * (multiplier or 1)
        local have = Core.CountItem(v.item, shopId)
        if have < need then ok = false end
        table.insert(list, { item = name, label = Core.GetItemLabel(name), count = need, have = have })
    end
    return ok, list
end

-- Checks tools (list of keys), any metadata. shopId is accepted for the common signature only
function Core.HasTools(tools, shopId)
    for _, key in pairs(tools or {}) do
        if Core.CountTool(key) < 1 then
            return false, key
        end
    end
    return true
end
