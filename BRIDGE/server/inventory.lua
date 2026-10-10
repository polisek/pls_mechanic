--[[
   _____      _                 _                      _                   
  / ____|    | |               (_)                    | |                  
 | (___   ___| |_ _   _ _ __    _ _ ____   _____ _ __ | |_ ___  _ __ _   _ 
  \___ \ / _ \ __| | | | '_ \  | | '_ \ \ / / _ \ '_ \| __/ _ \| '__| | | |
  ____) |  __/ |_| |_| | |_) | | | | | \ V /  __/ | | | || (_) | |  | |_| |
 |_____/ \___|\__|\__,_| .__/  |_|_| |_|\_/ \___|_| |_|\__\___/|_|   \__, |
                       | |                                            __/ |
                       |_|                                           |___/ 
]]--

local Inventory = nil

local Stashes = {}
local Drops = {}

if BRIDGE.Inventory  == "ox_inventory" then
    Inventory = exports.ox_inventory
end

if BRIDGE.Inventory == "qb_inventory" then
    Inventory = exports['qs-inventory']
end

if BRIDGE.Inventory == "quasar_inventory" then
    Inventory = exports['qs-inventory']
end

if BRIDGE.Inventory == "codem" then
    Inventory = exports['codem-inventory']
end

--[[
   _____      _     _____ _                     
  / ____|    | |   |_   _| |                    
 | |  __  ___| |_    | | | |_ ___ _ __ ___  ___ 
 | | |_ |/ _ \ __|   | | | __/ _ \ '_ ` _ \/ __|
 | |__| |  __/ |_   _| |_| ||  __/ | | | | \__ \
  \_____|\___|\__| |_____|\__\___|_| |_| |_|___/
                                                
                                                
]]--

BRIDGE.GetItems = function()
    local items = nil
    if BRIDGE.Inventory == "ox_inventory" then
        items = Inventory:Items()
    elseif BRIDGE.Inventory == "qb_inventory" then
        items = Framework.Shared.Items
    elseif BRIDGE.Inventory == "quasar_inventory" then
        items = Inventory:GetItemList()
    elseif BRIDGE.Inventory == "codem" then
        items = Inventory:GetItemList()
    end
    return items
end

--[[
   _____      _     _____ _                    _____                  _   
  / ____|    | |   |_   _| |                  / ____|                | |  
 | |  __  ___| |_    | | | |_ ___ _ __ ___   | |     ___  _   _ _ __ | |_ 
 | | |_ |/ _ \ __|   | | | __/ _ \ '_ ` _ \  | |    / _ \| | | | '_ \| __|
 | |__| |  __/ |_   _| |_| ||  __/ | | | | | | |___| (_) | |_| | | | | |_ 
  \_____|\___|\__| |_____|\__\___|_| |_| |_|  \_____\___/ \__,_|_| |_|\__|
                                                                                                                                          
]]--

BRIDGE.GetItemCount = function(playerId, itemName)
    local count = nil
    if BRIDGE.Inventory == "ox_inventory" then
        count = Inventory:Search(playerId, 'count', itemName)
    elseif BRIDGE.Inventory == "qb_inventory" then
        local xPlayer = Framework.Functions.GetPlayer(playerId)
        local item = xPlayer.Functions.GetItemByName(itemName)
        if item ~= nil then 
            count = item.amount 
        else
           count = 0
        end
        if itemName == "money" then
           count = xPlayer.PlayerData.money["cash"]
        end
    elseif BRIDGE.Inventory == "quasar_inventory" then
        local xPlayer = Framework.Functions.GetPlayer(playerId)
        local item = Inventory:GetItemTotalAmount(playerId, itemName)
        if item ~= nil then 
            count = item
        else
           count = 0
        end
        if itemName == "money" then
           count = xPlayer.PlayerData.money["cash"]
        end
    elseif BRIDGE.Inventory == "codem" then
        if itemName == "money" then
            itemName = "cash"
        end
        local item = Inventory:GetItemsTotalAmount(playerId, itemName)
        if item ~= nil then 
            count = item
        else
           count = 0
        end
    end
    return count
end

if BRIDGE.Inventory == "codem" then
    lib.callback.register('codemGetItemCountClient', function(source, itemName)
        if itemName == "money" then
            itemName = "cash"
        end
        local itemCount = Inventory:GetItemsTotalAmount(source, itemName)
        return itemCount
    end)
end

--[[ 
           _____  _____ _____ _______ ______ __  __ 
     /\   |  __ \|  __ \_   _|__   __|  ____|  \/  |
    /  \  | |  | | |  | || |    | |  | |__  | \  / |
   / /\ \ | |  | | |  | || |    | |  |  __| | |\/| |
  / ____ \| |__| | |__| || |_   | |  | |____| |  | |
 /_/    \_\_____/|_____/_____|  |_|  |______|_|  |_|
                                                    
                                                    
]]--

BRIDGE.AddItem = function(playerId, itemName, count, metadata)
    local returns = false
    if BRIDGE.Inventory == "ox_inventory" then
        returns = Inventory:AddItem(playerId, itemName, count, metadata)
    elseif BRIDGE.Inventory == "qb_inventory" then
        local QBPlayer = Framework.Functions.GetPlayer(playerId)
        if itemName == "money" then
            returns = QBPlayer.Functions.AddMoney('cash', count)
        else
            -- metadata = item info (e.g. stolen parts)
            returns = QBPlayer.Functions.AddItem(itemName, count,  false, metadata or {})
        end
    elseif BRIDGE.Inventory == "quasar_inventory" then
        local QBPlayer = Framework.Functions.GetPlayer(playerId)
        if itemName == "money" then
            returns = QBPlayer.Functions.AddMoney('cash', count)
        else
            -- AddItem(source, item, amount, slot, metadata)
            returns = Inventory:AddItem(playerId, itemName, count, nil, metadata)
        end
    elseif BRIDGE.Inventory == "codem" then
        if itemName == "money" then
            itemName = "cash"
        end
        returns = Inventory:AddItem(playerId, itemName, count, metadata)
    end
    return returns
end

--[[ 
  _____  ______ __  __  ______      ________ _____ _______ ______ __  __ 
 |  __ \|  ____|  \/  |/ __ \ \    / /  ____|_   _|__   __|  ____|  \/  |
 | |__) | |__  | \  / | |  | \ \  / /| |__    | |    | |  | |__  | \  / |
 |  _  /|  __| | |\/| | |  | |\ \/ / |  __|   | |    | |  |  __| | |\/| |
 | | \ \| |____| |  | | |__| | \  /  | |____ _| |_   | |  | |____| |  | |
 |_|  \_\______|_|  |_|\____/   \/   |______|_____|  |_|  |______|_|  |_|
                                                                                                                                                                                                
]]--

BRIDGE.RemoveItem = function(playerId, itemName, count)
    local returns = false
    if BRIDGE.Inventory == "ox_inventory" then
        returns = Inventory:RemoveItem(playerId, itemName, count)
    elseif BRIDGE.Inventory == "qb_inventory" then
        local QBPlayer = Framework.Functions.GetPlayer(playerId)
        if itemName == "money" then
            returns = QBPlayer.Functions.RemoveMoney('cash', count)
        else
            returns = QBPlayer.Functions.RemoveItem(itemName, count)
        end
    elseif BRIDGE.Inventory == "quasar_inventory" then
        local QBPlayer = Framework.Functions.GetPlayer(playerId)
        if itemName == "money" then
            returns = QBPlayer.Functions.RemoveMoney('cash', count)
        else
            returns = Inventory:RemoveItem(playerId, itemName, count)
        end

    elseif BRIDGE.Inventory == "codem" then
        if itemName == "money" then
            itemName = "cash"
        end
        returns = Inventory:RemoveItem(playerId, itemName, count)
    end
    return returns
end

--[[

 _____           _                   ______                 
/  __ \         | |                  |  _  \                
| /  \/_   _ ___| |_ ___  _ __ ___   | | | |_ __ ___  _ __  
| |   | | | / __| __/ _ \| '_ ` _ \  | | | | '__/ _ \| '_ \ 
| \__/\ |_| \__ \ || (_) | | | | | | | |/ /| | | (_) | |_) |
 \____/\__,_|___/\__\___/|_| |_| |_| |___/ |_|  \___/| .__/ 
                                                     | |    
                                                     |_|    
                                                     
]]--

-- Server side event only (BRIDGE/server/framework.lua), a client can't trigger it for another player
AddEventHandler(GetCurrentResourceName()..':playerLoaded',function(playerId)
    if BRIDGE.IsSpoofedPlayerLoaded and BRIDGE.IsSpoofedPlayerLoaded(playerId) then return end
    TriggerClientEvent(GetCurrentResourceName().."send_data", playerId, Drops)
end)


local function CreateCustomDrop(prop, itemName,itemCount, coords)
    local identifier = "CUSTOM_DROP_"..math.random(1, 99999)
    local dropData = {
        identifier = identifier,
        prop = prop,
        itemName = itemName,
        itemCount = itemCount,
        coords = coords,
    }
    table.insert(Drops, dropData)
    TriggerClientEvent(GetCurrentResourceName().."drops_create", -1, dropData)
end

local function TakeDrop(playerId, dropName)
    for i,v in pairs(Drops) do
        if v.identifier == dropName then
            local ped = GetPlayerPed(playerId)
            local playerCoords = GetEntityCoords(ped)
            if #(v.coords - playerCoords) < 5.0 then
                BRIDGE.AddItem(playerId, v.itemName, v.itemCount)
                table.remove(Drops, i)
                TriggerClientEvent(GetCurrentResourceName().."remove_drop", -1, dropName)
                return true 
            end
        end
    end
    return false
end

RegisterNetEvent(GetCurrentResourceName().."take_drop")
AddEventHandler(GetCurrentResourceName().."take_drop", function(dropName)
    local src = source
    TakeDrop(src, dropName)
end)


BRIDGE.CreateCustomDrop = function(prop, itemName, itemCount, coords)
    CreateCustomDrop(prop,itemName,itemCount, coords)
end

--[[
 _____ _            _                               _                 
/  ___| |          | |                             | |                
\ `--.| |_ __ _ ___| |__   ___  ___   ___ _   _ ___| |_ ___ _ __ ___  
 `--. \ __/ _` / __| '_ \ / _ \/ __| / __| | | / __| __/ _ \ '_ ` _ \ 
/\__/ / || (_| \__ \ | | |  __/\__ \ \__ \ |_| \__ \ ||  __/ | | | | |
\____/ \__\__,_|___/_| |_|\___||___/ |___/\__, |___/\__\___|_| |_| |_|
                                           __/ |                      
                                          |___/                                                                 
]]--



local StashGroups = {} -- [stashName] = { [job] = minGrade } for PLS stashes, nil = everyone
local StashAccessCheck = nil -- function(playerId, stashName) -> true / false (decides) or nil (job groups decide)

local function CreateStash(name, groups)
    if not Stashes[name] then
        Stashes[name] = {}
    end
    StashGroups[name] = groups
end

-- Custom access rule of the script for PLS stashes (e.g. stashes without job groups).
-- fn(playerId, stashName) returns true / false to decide, nil to use the job groups
BRIDGE.SetStashAccessCheck = function(fn)
    StashAccessCheck = type(fn) == "function" and fn or nil
end

-- Job + grade check of PLS stash (clients send the stash name, never trust it)
local function canAccessStash(playerId, stashName)
    if StashAccessCheck then
        local ok, allowed = pcall(StashAccessCheck, playerId, stashName)
        if ok and type(allowed) == "boolean" then return allowed end
    end
    local groups = StashGroups[stashName]
    if not groups or next(groups) == nil then return true end
    local ok, job = pcall(BRIDGE.GetPlayerJob, playerId)
    local minGrade = ok and job and groups[job]
    if not minGrade then return false end
    local okGrade, grade = pcall(BRIDGE.GetPlayerGrade, playerId)
    return okGrade and (tonumber(grade) or 0) >= minGrade
end

local function AddItemToStash(stashName, itemName, count)
    if Stashes[stashName] then
        local itemData = {
            itemName = itemName,
            count = count
        }
        table.insert(Stashes[stashName], itemData)
    else
        -- print("Stash doesnt exist! "..stashName)
    end
end

local function GetItemsInStash(stashName)
    if Stashes[stashName] then
        return Stashes[stashName]
    end
    return false
end

local function TakeItemFromStash(stashName, playerId, position)
    if Stashes[stashName] then
        if Stashes[stashName][position] then
            local itemData = Stashes[stashName][position]
            BRIDGE.AddItem(playerId, itemData.itemName, itemData.count)
            table.remove(Stashes[stashName], position)
        end
    else
        -- print("Stash doesnt exist! "..stashName)
    end
end
local function clearStash(stashName)
    if Stashes[stashName] then
        Stashes[stashName] = {}
    else
        -- print("Stash doesnt exist! "..stashName)
    end
end

if BRIDGE.QBStashesReplaceByPLS then
    lib.callback.register(GetCurrentResourceName()..'_open_stash', function(source, stashName)
        if not canAccessStash(source, stashName) then return false end
        local items = GetItemsInStash(stashName)
        return items
    end)
end


RegisterNetEvent(GetCurrentResourceName().."takeItemFromStash")
AddEventHandler(GetCurrentResourceName().."takeItemFromStash", function(stashName, position)
    local src = source
    if not canAccessStash(src, stashName) then return end
    TakeItemFromStash(stashName, src, position)
end)



-- groups (optional, ox_inventory + PLS stashes) = { ['mechanic'] = 0 } - job and minimal grade which can open stash
-- coords (optional, ox_inventory) = vector3 or list of vector3 - the stash opens only near them
BRIDGE.RegisterStash = function(stashName, stashLabel, stashSlots, stashWeight, groups, coords)
    if BRIDGE.Inventory == "ox_inventory" then
        -- RegisterStash(id, label, slots, maxWeight, owner, groups, coords)
        returns = Inventory:RegisterStash(stashName, stashLabel, stashSlots, stashWeight, nil, groups, coords)
    elseif BRIDGE.Inventory == "qb_inventory" then
        returns = CreateStash(stashName, groups)
    elseif BRIDGE.Inventory == "quasar_inventory" then
        -- qs-inventory stashes have no job groups (groups are dropped) and open from a client event with any name.
        -- Nothing to enforce here: BRIDGE.StashServerProtected() is false, the script warns about it.
        returns = Inventory:RegisterStash(stashName, stashSlots, stashWeight) 
    end
end


BRIDGE.ClearStash = function (stashName)
    if BRIDGE.Inventory == "ox_inventory" then
        returns = Inventory:ClearInventory(stashName)
    elseif BRIDGE.Inventory == "qb_inventory" then
        returns = clearStash(stashName)
    elseif BRIDGE.Inventory == "quasar_inventory" then
        returns = Inventory:ClearInventory(stashName, {})
    end
end



-- Real qb-inventory stashes (BRIDGE.QBStashesReplaceByPLS = false). nil when qb-inventory is not started
-- Exports (qb-inventory 2.x): GetInventory(identifier), AddItem / RemoveItem(identifier, item, amount, slot, ...)
local function qbStashInventory()
    if BRIDGE.QBStashesReplaceByPLS or GetResourceState("qb-inventory") ~= "started" then return nil end
    return exports["qb-inventory"]
end

-- Returns false only when inventory explicitly refused the item (e.g. stash full)
BRIDGE.AddStashItem = function(stashName, itemName, itemCount, metadata)
    local returns = nil
    if BRIDGE.Inventory == "ox_inventory" then
        returns = Inventory:AddItem(stashName, itemName, itemCount, metadata)
    elseif BRIDGE.Inventory == "qb_inventory" then
        local qb = qbStashInventory()
        local ok, added = false, false
        if qb then
            ok, added = pcall(function() return qb:AddItem(stashName, itemName, itemCount, false, metadata or false, GetCurrentResourceName()) end)
        end
        -- old qb-inventory / stash without capacity -> PLS stash as before
        if not ok or added ~= true then
            returns = AddItemToStash(stashName, itemName, itemCount)
        end
    elseif BRIDGE.Inventory == "quasar_inventory" then
        returns = Inventory:AddItemIntoStash(stashName, itemName, itemCount)
    end
    return returns ~= false
end

--[[
   _____ _            _
  / ____| |          | |
 | (___ | |_ __ _ ___| |__     ___  _ __   ___ _ __
  \___ \| __/ _` / __| '_ \   / _ \| '_ \ / _ \ '_ \
  ____) | || (_| \__ \ | | | | (_) | |_) |  __/ | | |
 |_____/ \__\__,_|___/_| |_|  \___/| .__/ \___|_| |_|
                                   | |
                                   |_|

 Opens a stash for the player from the server (the script checks the access first).
 Returns true when the inventory handled the open, false = no server side open (the script opens it from the client, BRIDGE.OpenStash).
 ox_inventory     - forceOpenInventory(playerId, 'stash', id) (skips the groups / coords check)
 qb_inventory     - qb-inventory 2.x OpenInventory(playerId, id, { label, maxweight, slots }),
                    PLS stashes = false (their client menu asks the server, which checks the access on every open / take)
 quasar / codem / core - false
]]--

-- qb-inventory 2.x opens stashes only from the server, old versions from the client event inventory:server:OpenInventory.
-- OpenInventoryById is a 2.x export (the old OpenInventory export has other parameters: name, id, other, origin)
local function qbServerOpen()
    local qb = qbStashInventory()
    if not qb then return false end
    local ok = pcall(function() return qb.OpenInventoryById end)
    return ok
end

BRIDGE.OpenStashServer = function(playerId, stashName, label, slots, weight)
    playerId = tonumber(playerId)
    if not playerId or type(stashName) ~= "string" then return false end
    if BRIDGE.Inventory == "ox_inventory" then
        local ok = pcall(function() Inventory:forceOpenInventory(playerId, 'stash', stashName) end)
        return ok
    elseif BRIDGE.Inventory == "qb_inventory" then
        if not qbServerOpen() then return false end
        local ok = pcall(function() exports["qb-inventory"]:OpenInventory(playerId, stashName, { label = label, maxweight = weight, slots = slots }) end)
        return ok
    end
    return false
end

-- true when a client can't open a stash of the script by its name: ox_inventory (groups / coords),
-- PLS qb stashes (the server checks every open / take), qb-inventory 2.x (stashes open only from the server).
-- false = quasar, codem, core_inventory and old qb-inventory, any client can open any stash by its name.
BRIDGE.StashServerProtected = function()
    if BRIDGE.Inventory == "ox_inventory" then return true end
    if BRIDGE.Inventory == "qb_inventory" then
        return BRIDGE.QBStashesReplaceByPLS == true or qbServerOpen()
    end
    return false
end

--[[
  _____ _            _        _ _
 / ____| |          | |      (_) |
| (___ | |_ __ _ ___| |__     _| |_ ___ _ __ ___  ___
 \___ \| __/ _` / __| '_ \   | | __/ _ \ '_ ` _ \/ __|
 ____) | || (_| \__ \ | | |  | | ||  __/ | | | | \__ \
|_____/ \__\__,_|___/_| |_|  |_|\__\___|_| |_| |_|___/

 Count / remove items of a stash from server scripts (e.g. taking parts from a workshop storage).
 nil = not supported by the inventory, the script falls back to opening the stash.
 ox_inventory     - GetItemCount(inv, item) / RemoveItem(inv, item, count)
 qb_inventory     - PLS stashes (BRIDGE.QBStashesReplaceByPLS) or qb-inventory 2.x GetInventory / RemoveItem per slot
 quasar_inventory - GetStashItems(stashId) for counting, removing is not supported (return value not documented)
 codem / core     - not supported
]]--

local function plsStashCount(stashName, itemName)
    local count = 0
    for _, entry in pairs(Stashes[stashName] or {}) do
        if entry.itemName == itemName then
            count = count + (tonumber(entry.count) or 0)
        end
    end
    return count
end

local function plsStashRemove(stashName, itemName, count)
    local stash = Stashes[stashName]
    if not stash or plsStashCount(stashName, itemName) < count then return false end
    local left = count
    for i = #stash, 1, -1 do
        local entry = stash[i]
        if left <= 0 then break end
        if entry.itemName == itemName then
            local take = math.min(left, tonumber(entry.count) or 0)
            entry.count = (tonumber(entry.count) or 0) - take
            left = left - take
            if entry.count <= 0 then
                table.remove(stash, i)
            end
        end
    end
    return true
end

-- Slots of item in real qb-inventory stash { { slot, amount } }, nil = not supported (old qb-inventory without exports)
local function qbStashSlots(stashName, itemName)
    local qb = qbStashInventory()
    if not qb then return nil end
    local ok, inventory = pcall(function() return qb:GetInventory(stashName) end)
    -- stash not loaded yet (qb-inventory loads it on first open) = unknown, not empty
    if not ok or type(inventory) ~= "table" then return nil end
    local slots = {}
    if type(inventory) == "table" and type(inventory.items) == "table" then
        for _, item in pairs(inventory.items) do
            local amount = type(item) == "table" and math.floor(tonumber(item.amount) or 0) or 0
            if amount > 0 and type(item.name) == "string" and item.name:lower() == itemName:lower() then
                slots[#slots + 1] = { slot = item.slot, amount = amount }
            end
        end
    end
    return slots
end

local function qsStashCount(stashName, itemName)
    local ok, items = pcall(function() return Inventory:GetStashItems(stashName) end)
    if not ok then return nil end
    local count = 0
    for _, item in pairs(type(items) == "table" and items or {}) do
        if type(item) == "table" and item.name == itemName then
            count = count + (tonumber(item.amount) or 0)
        end
    end
    return count
end

-- Count of item in stash. nil = not supported by the inventory (feature falls back to opening the stash)
BRIDGE.GetStashItemCount = function(stashName, itemName)
    if BRIDGE.Inventory == "ox_inventory" then
        local ok, count = pcall(function() return Inventory:GetItemCount(stashName, itemName) end)
        if not ok then return nil end
        return math.floor(tonumber(count) or 0)
    elseif BRIDGE.Inventory == "qb_inventory" then
        if BRIDGE.QBStashesReplaceByPLS then
            return plsStashCount(stashName, itemName)
        end
        local slots = qbStashSlots(stashName, itemName)
        if not slots then return nil end
        local count = 0
        for _, entry in pairs(slots) do
            count = count + entry.amount
        end
        return count
    elseif BRIDGE.Inventory == "quasar_inventory" then
        local count = qsStashCount(stashName, itemName)
        return count and math.floor(count) or nil
    end
    return nil
end

-- Removes count of item from stash. Returns true when removed, false when not (not enough items),
-- nil = not supported by the inventory
BRIDGE.RemoveStashItem = function(stashName, itemName, count)
    count = math.floor(tonumber(count) or 0)
    if count < 1 then return false end
    if BRIDGE.Inventory == "ox_inventory" then
        local ok, success = pcall(function() return Inventory:RemoveItem(stashName, itemName, count) end)
        return ok and success == true
    elseif BRIDGE.Inventory == "qb_inventory" then
        if BRIDGE.QBStashesReplaceByPLS then
            return plsStashRemove(stashName, itemName, count)
        end
        local slots = qbStashSlots(stashName, itemName)
        if not slots then return nil end
        local total = 0
        for _, entry in pairs(slots) do
            total = total + entry.amount
        end
        if total < count then return false end
        -- qb-inventory removes from one slot per call
        local qb = qbStashInventory()
        local left = count
        for _, entry in ipairs(slots) do
            if left <= 0 then break end
            local take = math.min(left, entry.amount)
            local ok, removed = pcall(function() return qb:RemoveItem(stashName, itemName, take, entry.slot, GetCurrentResourceName()) end)
            if ok and removed == true then
                left = left - take
            end
        end
        if left > 0 then
            -- put back what was already removed, the caller gets false
            if count - left > 0 then
                BRIDGE.AddStashItem(stashName, itemName, count - left)
            end
            return false
        end
        return true
    end
    return nil
end

--[[
  _____ _                     _       _
 |_   _| |                   | |     | |
   | | | |_ ___ _ __ ___  ___| | ___ | |_ ___
   | | | __/ _ \ '_ ` _ \/ __| |/ _ \| __/ __|
  _| |_| ||  __/ | | | | \__ \ | (_) | |_\__ \
 |_____|\__\___|_| |_| |_|___/_|\___/ \__|___/

 Item slots with metadata (e.g. stolen parts { stolen = true, quality = 80 }) of a player or a stash.
 Slot list = { { slot = number, count = number, metadata = table } }, nil = inventory without metadata support
 (the script then treats every item as a plain one and uses the count functions above).
 ox_inventory     - Search(inv, 'slots', item) / RemoveItem(inv, item, count, nil, slot)
 qb_inventory     - Player.PlayerData.items[slot].info / Player.Functions.RemoveItem(item, count, slot)
                    stashes: qb-inventory 2.x GetInventory(id).items / RemoveItem(id, item, count, slot), PLS stashes = nil
 quasar_inventory - GetInventory(source)[slot].info / RemoveItem(source, item, count, slot), stashes not supported
 codem / core     - not supported
]]--

local function copyMetadata(value)
    if type(value) ~= "table" then return {} end
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = type(entry) == "table" and copyMetadata(entry) or entry
    end
    return copy
end

local function sortSlots(slots)
    table.sort(slots, function(a, b) return a.slot < b.slot end)
    return slots
end

-- Slots from an items table in qb / qs format (name, amount, info, slot)
local function slotsFromItems(items, itemName)
    local slots = {}
    local lower = itemName:lower()
    for key, item in pairs(type(items) == "table" and items or {}) do
        if type(item) == "table" and type(item.name) == "string" and item.name:lower() == lower then
            local count = math.floor(tonumber(item.amount or item.count) or 0)
            local slot = tonumber(item.slot) or tonumber(key)
            if count > 0 and slot then
                slots[#slots + 1] = { slot = math.floor(slot), count = count, metadata = copyMetadata(item.info or item.metadata) }
            end
        end
    end
    return sortSlots(slots)
end

-- ox_inventory Search 'slots' (player source or stash id). nil = export failed
local function oxSlots(inv, itemName)
    local ok, result = pcall(function() return Inventory:Search(inv, 'slots', itemName) end)
    if not ok then return nil end
    local slots = {}
    for _, item in pairs(type(result) == "table" and result or {}) do
        if type(item) == "table" and tonumber(item.slot) then
            local count = math.floor(tonumber(item.count) or 0)
            if count > 0 then
                slots[#slots + 1] = { slot = math.floor(tonumber(item.slot)), count = count, metadata = copyMetadata(item.metadata) }
            end
        end
    end
    return sortSlots(slots)
end

local function qbPlayer(playerId)
    local ok, player = pcall(function() return Framework.Functions.GetPlayer(playerId) end)
    return ok and player or nil
end

-- Amount in one qs-inventory slot of the player (nil = unknown)
local function qsSlotAmount(playerId, itemName, slot)
    local ok, items = pcall(function() return Inventory:GetInventory(playerId) end)
    if not ok or type(items) ~= "table" then return nil end
    for _, entry in ipairs(slotsFromItems(items, itemName)) do
        if entry.slot == slot then return entry.count end
    end
    return 0
end

-- Slots of item in player's inventory { { slot, count, metadata } }, nil = no metadata support
BRIDGE.GetItemSlots = function(playerId, itemName)
    if type(itemName) ~= "string" then return nil end
    if BRIDGE.Inventory == "ox_inventory" then
        return oxSlots(playerId, itemName)
    elseif BRIDGE.Inventory == "qb_inventory" then
        if itemName == "money" then return nil end
        local player = qbPlayer(playerId)
        if not player or type(player.PlayerData) ~= "table" then return {} end
        return slotsFromItems(player.PlayerData.items, itemName)
    elseif BRIDGE.Inventory == "quasar_inventory" then
        if itemName == "money" then return nil end
        local ok, items = pcall(function() return Inventory:GetInventory(playerId) end)
        if not ok then return nil end
        return slotsFromItems(items, itemName)
    end
    return nil
end

-- Removes count of item from one slot of player's inventory. Returns true when removed, nil = not supported
BRIDGE.RemoveItemSlot = function(playerId, itemName, count, slot)
    count = math.floor(tonumber(count) or 0)
    slot = tonumber(slot)
    if count < 1 or not slot then return false end
    if BRIDGE.Inventory == "ox_inventory" then
        local ok, success = pcall(function() return Inventory:RemoveItem(playerId, itemName, count, nil, slot) end)
        return ok and success == true
    elseif BRIDGE.Inventory == "qb_inventory" then
        local player = qbPlayer(playerId)
        if not player then return false end
        local ok, removed = pcall(function() return player.Functions.RemoveItem(itemName, count, slot) end)
        return ok and removed == true
    elseif BRIDGE.Inventory == "quasar_inventory" then
        -- return value of RemoveItem is not documented, the slot is read again
        local before = qsSlotAmount(playerId, itemName, slot)
        if not before or before < count then return false end
        local ok, removed = pcall(function() return Inventory:RemoveItem(playerId, itemName, count, slot) end)
        if not ok or removed == false then return false end
        local after = qsSlotAmount(playerId, itemName, slot)
        return after ~= nil and after <= before - count
    end
    return nil
end

-- Slots of item in stash { { slot, count, metadata } }, nil = no metadata support
BRIDGE.GetStashItemSlots = function(stashName, itemName)
    if type(itemName) ~= "string" then return nil end
    if BRIDGE.Inventory == "ox_inventory" then
        return oxSlots(stashName, itemName)
    elseif BRIDGE.Inventory == "qb_inventory" then
        -- PLS stashes keep no metadata
        if BRIDGE.QBStashesReplaceByPLS then return nil end
        local qb = qbStashInventory()
        if not qb then return nil end
        local ok, inventory = pcall(function() return qb:GetInventory(stashName) end)
        -- stash not loaded yet (qb-inventory loads it on first open) = unknown
        if not ok or type(inventory) ~= "table" then return nil end
        return slotsFromItems(inventory.items, itemName)
    end
    return nil
end

-- Removes count of item from one stash slot. Returns true when removed, nil = not supported
BRIDGE.RemoveStashItemSlot = function(stashName, itemName, count, slot)
    count = math.floor(tonumber(count) or 0)
    slot = tonumber(slot)
    if count < 1 or not slot then return false end
    if BRIDGE.Inventory == "ox_inventory" then
        local ok, success = pcall(function() return Inventory:RemoveItem(stashName, itemName, count, nil, slot) end)
        return ok and success == true
    elseif BRIDGE.Inventory == "qb_inventory" then
        if BRIDGE.QBStashesReplaceByPLS then return nil end
        local qb = qbStashInventory()
        if not qb then return nil end
        local ok, removed = pcall(function() return qb:RemoveItem(stashName, itemName, count, slot, GetCurrentResourceName()) end)
        return ok and removed == true
    end
    return nil
end

