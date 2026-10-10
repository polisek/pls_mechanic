--[[
   _____ _ _            _                          __ _
  / ____| (_)          | |                        / _(_)
 | |    | |_  ___ _ __ | |_    ___ ___  _ __  ___| |_ _  __ _
 | |    | | |/ _ \ '_ \| __|  / __/ _ \| '_ \/ __|  _| |/ _` |
 | |____| | |  __/ | | | |_  | (_| (_) | | | \__ \ | | | (_| |
  \_____|_|_|\___|_| |_|\__|  \___\___/|_| |_|___/_| |_|\__, |
                                                         __/ |
                                                        |___/
 Client side hooks. Change them to your systems.
]]--

-- Boss menu point in workshop (permission "bossmenu")
Config.OpenBossMenu = function(shopId, job)
    if GetResourceState("pls_bossmenu") ~= "started" then
        return BRIDGE.Notify({ title = locale("script_title"), description = locale("bossmenu_unavailable"), type = "error" })
    end
    exports['pls_bossmenu']:OpenBossMenu(job)
end

-- Fuel system (NPC mission refuel, service vehicles)
Config.SetFuel = function(vehicle, fuel)
    Entity(vehicle).state:set("fuel", fuel, true)
    SetVehicleFuelLevel(vehicle, fuel + 0.0)
    if GetResourceState("LegacyFuel") == "started" then
        exports["LegacyFuel"]:SetFuel(vehicle, fuel)
    elseif GetResourceState("ox_fuel") == "started" then
        Entity(vehicle).state:set("fuel", fuel, true)
    end
end

-- Vehicle keys (service vehicles, unlocked vehicles)
Config.GiveKeys = function(vehicle, plate)
    -- exports["qb-vehiclekeys"]:... / TriggerEvent("vehiclekeys:client:SetOwner", plate)
end

-- Police dispatch when mechanic unlocks vehicle with slim jim (nil = disabled)
Config.UnlockDispatch = nil
-- Config.UnlockDispatch = function(vehicle, coords)
--     exports["ps-dispatch"]:VehicleTheft(vehicle)
-- end

-- Show mileage while driving (small text above minimap)
Config.ShowMileage = true
Config.MileageUnit = "km" -- "km" / "mi"
