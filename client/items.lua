--[[
  _____ _
 |_   _| |
   | | | |_ ___ _ __ ___  ___
   | | | __/ _ \ '_ ` _ \/ __|
  _| |_| ||  __/ | | | | \__ \
 |_____|\__\___|_| |_| |_|___/

 Usable items dispatcher.
 ox_inventory: client export "pls_mechanic.useItem" (INSTALL/items.lua)
 ESX / QB:     server registers usable items -> client event "pls_mechanic:client:useItem"
 Modules register handlers: Items.Register(key, function(itemName) end)  (key = Config.Items key)
]]--

Items = {}
local Handlers = {}
local Busy = false

function Items.Register(key, fn)
    Handlers[key] = fn
end

local function useItem(itemName)
    if not itemName then return end
    local key = Utils.ItemKey(itemName)
    local handler = key and Handlers[key]
    if not handler then
        Utils.Debug("No handler for item", itemName)
        return
    end
    if Busy then return end
    Busy = true
    local ok, err = pcall(handler, itemName)
    Busy = false
    if not ok then
        print("[pls_mechanic] item "..tostring(itemName).." error: "..tostring(err))
    end
end

-- ox_inventory: (data, slot) - data.name is item name
exports("useItem", function(data, slot)
    useItem(data and data.name)
end)

-- ESX / QB: {item = itemName | itemTable}
RegisterNetEvent("pls_mechanic:client:useItem", function(data)
    local item = data and data.item
    if type(item) == "table" then
        item = item.name
    end
    useItem(item)
end)
