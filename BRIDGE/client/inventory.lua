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
local Drops = {}
if BRIDGE.Inventory  == "ox_inventory" then
    Inventory = exports.ox_inventory
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

local function qb_get_item_count(items, itemName)

    local count = 0
    for _, v in pairs(items) do 
        if v.name == itemName then
            count = count+v.amount
        end
    end
    return count
end

BRIDGE.GetItemCount = function(itemName)
    local count = nil
    if BRIDGE.Inventory == "ox_inventory" then
        count = Inventory:Search('count', itemName)
    elseif BRIDGE.Inventory == "qb_inventory" then
        local QBPlayer = Framework.Functions.GetPlayerData()
        local item = qb_get_item_count(QBPlayer.items, itemName)
        if item ~= nil then 
            count = item
        else
           count = 0
        end
        if itemName == "money" then
            count = QBPlayer.money["cash"]
        end
    elseif BRIDGE.Inventory == "quasar_inventory" then
        local QBPlayer = Framework.Functions.GetPlayerData()
        local item = Inventory:Search(itemName)
        if item ~= nil then 
            count = item
        else
           count = 0
        end
        if itemName == "money" then
            count = QBPlayer.money["cash"]
        end
    elseif BRIDGE.Inventory == "codem" then
        local itemCount = lib.callback.await("codemGetItemCountClient",100,itemName)
        if itemCount then
            count = itemCount
        else
            count = 0
        end
    end
    return count
end

--[[
  _____ _                     _       _
 |_   _| |                   | |     | |
   | | | |_ ___ _ __ ___  ___| | ___ | |_ ___
   | | | __/ _ \ '_ ` _ \/ __| |/ _ \| __/ __|
  _| |_| ||  __/ | | | | \__ \ | (_) | |_\__ \
 |_____|\__\___|_| |_| |_|___/_|\___/ \__|___/

 Slots of item in own inventory with metadata { { slot, count, metadata } }, nil = no metadata support.
 ox_inventory - Search('slots', item), qb_inventory - PlayerData.items[slot].info, others not supported
]]--

local function copyMetadata(value)
    if type(value) ~= "table" then return {} end
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = type(entry) == "table" and copyMetadata(entry) or entry
    end
    return copy
end

BRIDGE.GetItemSlots = function(itemName)
    if type(itemName) ~= "string" then return nil end
    local slots = {}
    if BRIDGE.Inventory == "ox_inventory" then
        local ok, result = pcall(function() return Inventory:Search('slots', itemName) end)
        if not ok then return nil end
        for _, item in pairs(type(result) == "table" and result or {}) do
            local count = type(item) == "table" and math.floor(tonumber(item.count) or 0) or 0
            if count > 0 and tonumber(item.slot) then
                slots[#slots + 1] = { slot = math.floor(tonumber(item.slot)), count = count, metadata = copyMetadata(item.metadata) }
            end
        end
    elseif BRIDGE.Inventory == "qb_inventory" then
        if itemName == "money" then return nil end
        local ok, data = pcall(function() return Framework.Functions.GetPlayerData() end)
        if not ok or type(data) ~= "table" then return nil end
        local lower = itemName:lower()
        for key, item in pairs(type(data.items) == "table" and data.items or {}) do
            if type(item) == "table" and type(item.name) == "string" and item.name:lower() == lower then
                local count = math.floor(tonumber(item.amount) or 0)
                local slot = tonumber(item.slot) or tonumber(key)
                if count > 0 and slot then
                    slots[#slots + 1] = { slot = math.floor(slot), count = count, metadata = copyMetadata(item.info) }
                end
            end
        end
    else
        return nil
    end
    table.sort(slots, function(a, b) return a.slot < b.slot end)
    return slots
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

local function openStash(stashName)
    local stashData = lib.callback.await(GetCurrentResourceName()..'_open_stash',100,stashName)
    if stashData then
        local newOptions = {}
        for i,itemData in pairs(stashData) do
            local option = {
                title = itemData.itemName.." - "..itemData.count,
                icon = "cirle",
                onSelect = function()
                   TriggerServerEvent(GetCurrentResourceName().."takeItemFromStash",stashName, i)
                end
            }
            table.insert(newOptions, option)
        end
        lib.registerContext({
            id = GetCurrentResourceName()..'dynamic_stash_menu',
            title = 'Stash',
            options = newOptions
          })
        lib.showContext(GetCurrentResourceName()..'dynamic_stash_menu')
    end
end

BRIDGE.OpenStash = function(stashName, max_weight, slots)
    if BRIDGE.Inventory == "ox_inventory" then
        local stashData = {id=stashName}
        Inventory:openInventory("stash",stashData)
    elseif BRIDGE.Inventory == "qb_inventory" then
        if BRIDGE.QBStashesReplaceByPLS then
            openStash(stashName)
        else
            TriggerServerEvent("inventory:server:OpenInventory", "stash", stashName, {maxweight = max_weight, slots =  slots})
            TriggerEvent("inventory:client:SetCurrentStash",stashName)
        end
    elseif BRIDGE.Inventory == "quasar_inventory" then
        local other = {}
        other.maxweight = 20000
        other.slots = 10
        TriggerServerEvent("inventory:server:OpenInventory", "stash", stashName, {})
        TriggerEvent("inventory:client:SetCurrentStash",stashName)
    elseif BRIDGE.Inventory == "core" then
        TriggerServerEvent('core_inventory:server:openInventory', stashName, "stash")
    end
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

RegisterNetEvent(GetCurrentResourceName().."send_data")
AddEventHandler(GetCurrentResourceName().."send_data", function(dropData)
    Drops = dropData
end)

RegisterNetEvent(GetCurrentResourceName().."drops_create")
AddEventHandler(GetCurrentResourceName().."drops_create", function(dropData)
    table.insert(Drops, dropData)
end)


RegisterNetEvent(GetCurrentResourceName().."remove_drop")
AddEventHandler(GetCurrentResourceName().."remove_drop", function(dropName)
    for i, drop in pairs(Drops) do
        if drop.identifier == dropName then
            if drop.object then
                DeleteObject(drop.object)
                drop.object = nil
                if drop.target then
                    BRIDGE.RemoveSphereTarget(drop.target)
                    drop.target = nil
                end
            end
            table.remove(Drops, i)
        end
    end
end)


CreateThread(function()
    while true do
        Wait(8000)
        local coords = GetEntityCoords(PlayerPedId())
        for _, drop in pairs(Drops) do
            if #(drop.coords - coords) < 50.0 then
                if not drop.object then
                    drop.object = CreateObject(joaat(drop.prop), drop.coords.x,drop.coords.y,drop.coords.z-1, false, false)
                    FreezeEntityPosition(drop.object,true) 
                    drop.target = BRIDGE.AddSphereTarget({ 
                        coords = vector3(drop.coords.x,drop.coords.y,drop.coords.z-1), 
                        radius = 2,  
                        options = {  
                            {
                                name = 'sphere',
                                icon = 'fa-solid fa-user',
                                label = "Take",
                                onSelect = function(data) 
                                    TriggerServerEvent(GetCurrentResourceName().."take_drop", drop.identifier)
                                end,
                            }
                        },
                    })
                end
            else
                if drop.object then
                    DeleteObject(drop.object)
                    drop.object = nil
                    if drop.target then
                        BRIDGE.RemoveSphereTarget(drop.target)
                        drop.target = nil
                    end
                end
            end
        end
    end
end)