--[[
   _____      _   _   _
  / ____|    | | | | (_)
 | (___   ___| |_| |_ _ _ __   __ _ ___
  \___ \ / _ \ __| __| | '_ \ / _` / __|
  ____) |  __/ |_| |_| | | | | (_| \__ \
 |_____/ \___|\__|\__|_|_| |_|\__, |___/
                               __/ |
                              |___/
 Workshop settings for the boss (permission "manage_shop") / admin - NUI view "settings".
 Tabs bills / orders ("settings:bills", "settings:orders") belong to the economy module.
 Not available for illegal workshops.
]]--

Settings = {}

local CurrentShopId = nil

-- Shop id of the open settings view (nil when closed) - used by tabs of other modules
function Settings.GetShopId()
    if Core.Nui.IsOpen("settings") then
        return CurrentShopId
    end
    return nil
end

function Settings.Open(shopId)
    if not shopId then return end
    if Core.Nui.IsOpen() then return end
    -- illegal workshops have no permission matrix (the crew decides), server refuses them too
    if Core.IsIllegalShop(shopId) then
        return Core.Notify(locale("settings_illegal"), "error")
    end
    local data = lib.callback.await("pls_mechanic:server:shops:getSettings", false, shopId)
    if not data then return end
    CurrentShopId = shopId
    Core.Nui.Open("settings", data)
end

RegisterNUICallback("settings:save", function(data, cb)
    local shopId = Settings.GetShopId()
    if not shopId then
        cb({ ok = false, message = locale("settings_not_open") })
        return
    end
    data = type(data) == "table" and data or {}
    local response = lib.callback.await("pls_mechanic:server:shops:saveSettings", false, shopId, {
        permissions = data.permissions,
        settings = data.settings,
    })
    if type(response) ~= "table" then
        response = { ok = false, message = locale("settings_save_failed") }
    end
    cb({ ok = response.ok == true, message = response.message, permissions = response.permissions, settings = response.settings })
    if response.message then
        Core.Notify(response.message, response.ok and "success" or "error")
    end
end)
