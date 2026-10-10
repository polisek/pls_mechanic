--[[
   _____                 _            _                 _
  / ____|               (_)          | |               | |
 | (___   ___ _ ____   ___  ___ ___  | |__   ___   ___ | | __
  \___ \ / _ \ '__\ \ / / |/ __/ _ \ | '_ \ / _ \ / _ \| |/ /
  ____) |  __/ |   \ V /| | (_|  __/ | |_) | (_) | (_) |   <
 |_____/ \___|_|    \_/ |_|\___\___| |_.__/ \___/ \___/|_|\_\
 Service history of a vehicle in NUI "history".
]]--

ServiceBook = {}

local Busy = false
local Reading = false

local function getModelLabel(vehicle)
    local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(name)
    if not label or label == "NULL" then return name end
    return label
end

-- Opens service book of plate. vehicle (optional) adds model name.
function ServiceBook.Open(plate, vehicle)
    CreateThread(function()
        plate = Utils.TrimPlate(plate)
        if Busy or not plate or plate == "" then return end
        Busy = true
        local result = lib.callback.await("pls_mechanic:server:repair:history", false, plate)
        Busy = false
        if not result or not result.ok then
            Core.Notify(result and result.message or locale("book_failed"), "error")
            return
        end
        local data = result.data
        if vehicle and DoesEntityExist(vehicle) then
            data.model = getModelLabel(vehicle)
        end
        if not cache.vehicle and not IsPedUsingAnyScenario(cache.ped) then
            TaskStartScenarioInPlace(cache.ped, "WORLD_HUMAN_CLIPBOARD", 0, true)
            Reading = true
        end
        Core.Nui.Open("history", data)
    end)
end

Core.Nui.OnClose("history", function()
    if Reading then
        Reading = false
        ClearPedTasks(cache.ped)
    end
end)

Items.Register("service_book", function()
    CreateThread(function()
        local vehicle = cache.vehicle or Core.GetClosestVehicle(5.0)
        if not vehicle then
            Core.Notify(locale("no_vehicle"), "error")
            return
        end
        ServiceBook.Open(GetVehicleNumberPlateText(vehicle), vehicle)
    end)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() and Reading then
        ClearPedTasks(cache.ped)
    end
end)
