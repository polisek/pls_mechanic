--[[
   ____
  / __ \
 | |  | |_ __   ___ _ __
 | |  | | '_ \ / _ \ '_ \
 | |__| | |_) |  __/ | | |
  \____/| .__/ \___|_| |_|
        | |
        |_|
 Server side hooks. Change them to your systems.
]]--

OpenServer = {}

-- Mechanic impounds vehicle (permission "impound"). Return true when done.
OpenServer.ImpoundVehicle = function(src, entity, plate)
    -- Example for your garage system:
    -- exports["your_garage"]:SetVehicleImpounded(plate)
    DeleteEntity(entity)
    return true
end

-- Called after customer paid a bill. bill = { id, shopId, mechanic, customer, plate, lines, total }
OpenServer.OnBillPaid = function(bill)
end

-- Logs of important actions (discord, pls_logs...)
OpenServer.Log = function(src, action, message, data)
    -- TriggerEvent("logs:send", { player = GetPlayerName(src), message = action..": "..message, data = data })
end

-- Mechanic clocked in / out (duty point, mechanic menu, lost permission). shop = workshop (nil when it was removed),
-- job = job name of the player
OpenServer.OnDutyChanged = function(src, onDuty, shop, job)
    -- Duty time in pls_bossmenu (don't place boss menu duty points for mechanic jobs then, the duty is not doubled):
    -- if job and GetResourceState("pls_bossmenu") == "started" then
    --     exports["pls_bossmenu"]:SetDuty(src, job, onDuty, { label = shop and shop.name })
    -- end
end

-- Own crafting system. Return true to block built-in workbench menu and open yours.
OpenServer.OpenCustomCrafting = function(src, shopId)
    return false
end
