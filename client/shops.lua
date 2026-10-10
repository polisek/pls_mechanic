--[[
   _____ _
  / ____| |
 | (___ | |__   ___  _ __  ___
  \___ \| '_ \ / _ \| '_ \/ __|
  ____) | | | | (_) | |_) \__ \
 |_____/|_| |_|\___/| .__/|___/
                    | |
                    |_|
 Workshop points from GlobalState -> targets / markers, blips and built-in point actions
 (duty, boss menu, storage, service vehicles, workshop settings).
 Illegal workshops (private, only for their crew) get targets but never a blip.
]]--

Shops = {}

local Targets = {}          -- sphere target ids
local Blips = {}
local RebuildToken = 0
local ServiceVehicle = nil  -- { netId, plate } of my service vehicle

local TARGET_OFFSET = 1.0   -- point coords are on the ground / surface, target center is above it

--[[
  _______                   _
 |__   __|                 | |
    | | __ _ _ __ __ _  ___| |_ ___
    | |/ _` | '__/ _` |/ _ \ __/ __|
    | | (_| | | | (_| |  __/ |_\__ \
    |_|\__,_|_|  \__, |\___|\__|___/
                  __/ |
                 |___/
]]--

-- ok, reason (locale key or nil)
local function canUseAction(shop, point, action)
    if action.perm and not Core.HasPermission(action.perm, shop.id) then
        return false, "no_permission"
    end
    if action.canInteract then
        local ok, allowed = pcall(action.canInteract, shop, point)
        if not ok or not allowed then
            return false, nil
        end
    end
    return true
end

local function buildOptions(shop, point, radius)
    local options = {}
    for index, action in ipairs(ShopPoints.GetActions(point.type)) do
        options[#options + 1] = {
            name = ("pls_mechanic_%s_%s_%s"):format(shop.id, point.id or "point", index),
            label = action.label,
            icon = action.icon,
            distance = math.max(2.5, math.min(radius + 1.0, 7.0)),
            canInteract = function()
                return (canUseAction(shop, point, action))
            end,
            onSelect = function()
                -- marker mode doesn't use canInteract, check again
                local ok, reason = canUseAction(shop, point, action)
                if not ok then
                    Core.Notify(locale(reason or "shops_action_unavailable"), "error")
                    return
                end
                CreateThread(function()
                    action.onSelect(shop, point)
                end)
            end,
        }
    end
    return options
end

local function removeTargets()
    for _, id in pairs(Targets) do
        BRIDGE.RemoveSphereTarget(id)
    end
    Targets = {}
end

local function rebuildTargets()
    removeTargets()
    for _, shop in pairs(Core.Shops or {}) do
        -- admins receive all illegal workshops for the creator, targets only for crew members
        local points = (shop.kind ~= "illegal" or Core.IsMember(shop.id)) and shop.points or {}
        for _, point in pairs(points) do
            local pointType = Config.PointTypes[point.type]
            if pointType and point.coords then
                local radius = point.radius or pointType.radius or 1.5
                local options = buildOptions(shop, point, radius)
                if #options > 0 then
                    local id = BRIDGE.AddSphereTarget({
                        coords = Utils.Vec3(point.coords) + vector3(0.0, 0.0, TARGET_OFFSET),
                        radius = radius,
                        drawSprite = true,
                        options = options,
                    })
                    if id then
                        Targets[#Targets + 1] = id
                    end
                end
            end
        end
    end
end

-- Debounced rebuild (modules register actions one by one)
local function requestRebuild(delay)
    RebuildToken = RebuildToken + 1
    local token = RebuildToken
    SetTimeout(delay or 0, function()
        if token ~= RebuildToken then return end
        rebuildTargets()
    end)
end

--[[
  ____  _ _
 |  _ \| (_)
 | |_) | |_ _ __  ___
 |  _ <| | | '_ \/ __|
 | |_) | | | |_) \__ \
 |____/|_|_| .__/|___/
           | |
           |_|
]]--

local function removeBlips()
    for _, blip in pairs(Blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    Blips = {}
end

local function rebuildBlips(shops)
    removeBlips()
    for _, shop in pairs(shops or {}) do
        local data = shop.kind ~= "illegal" and shop.blip or nil
        if data and data.enabled then
            local coords = data.coords or (shop.points and shop.points[1] and shop.points[1].coords)
            if coords then
                local blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
                SetBlipSprite(blip, data.sprite or Config.DefaultBlip.sprite)
                SetBlipColour(blip, data.color or Config.DefaultBlip.color)
                SetBlipScale(blip, (data.scale or Config.DefaultBlip.scale) + 0.0)
                SetBlipDisplay(blip, 4)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentSubstringPlayerName(shop.name or locale("script_title"))
                EndTextCommandSetBlipName(blip)
                Blips[#Blips + 1] = blip
            end
        end
    end
end

Core.OnShopsUpdated(function(shops)
    rebuildBlips(shops)
    requestRebuild(0)
end)

ShopPoints.OnActionRegistered(function()
    requestRebuild(500)
end)

-- Rebuild targets and blips now (e.g. after job change)
function Shops.Refresh()
    rebuildBlips(Core.Shops)
    requestRebuild(0)
end

--[[
   _____                 _                       _     _      _
  / ____|               (_)                     | |   (_)    | |
 | (___   ___ _ ____   ___  ___ ___  __   _____| |__  _  ___| | ___  ___
  \___ \ / _ \ '__\ \ / / |/ __/ _ \ \ \ / / _ \ '_ \| |/ __| |/ _ \/ __|
  ____) |  __/ |   \ V /| | (_|  __/  \ V /  __/ | | | | (__| |  __/\__ \
 |_____/ \___|_|    \_/ |_|\___\___|   \_/ \___|_| |_|_|\___|_|\___||___/
]]--

-- Returns netId, plate of my service vehicle or nil
function Shops.GetServiceVehicle()
    if not ServiceVehicle then return nil end
    return ServiceVehicle.netId, ServiceVehicle.plate
end

-- CreateVehicleServerSetter needs vehicle type, server can't read model info
local function getVehicleType(model)
    if IsThisModelABike(model) or IsThisModelABicycle(model) then return "bike" end
    if IsThisModelABoat(model) or IsThisModelAJetski(model) then return "boat" end
    if IsThisModelAHeli(model) then return "heli" end
    if IsThisModelAPlane(model) then return "plane" end
    if IsThisModelATrain(model) then return "train" end
    return "automobile"
end

local function waitForVehicle(netId, timeout)
    local endTime = GetGameTimer() + (timeout or 5000)
    while GetGameTimer() < endTime do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local vehicle = NetToVeh(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                return vehicle
            end
        end
        Wait(50)
    end
    return nil
end

local function spawnServiceVehicle(shop, index)
    local data = Config.ServiceVehicles[index]
    if not data then return end
    local model = joaat(data.model)
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        Core.Notify(locale("shops_vehicle_invalid"), "error")
        return
    end

    local netId, plate = lib.callback.await("pls_mechanic:server:shops:spawnVehicle", false, shop.id, index, getVehicleType(model))
    if not netId then return end
    ServiceVehicle = { netId = netId, plate = plate }

    local vehicle = waitForVehicle(netId, 5000)
    if not vehicle then
        Core.Notify(locale("shops_vehicle_failed"), "error")
        return
    end
    if Core.RequestControl(vehicle, 2000) then
        SetVehicleOnGroundProperly(vehicle)
        if plate and Utils.TrimPlate(GetVehicleNumberPlateText(vehicle)) ~= plate then
            SetVehicleNumberPlateText(vehicle, plate)
        end
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleDirtLevel(vehicle, 0.0)
    end
    -- client hooks, a broken fuel / keys resource must not break the spawn
    local ok, err = pcall(Config.SetFuel, vehicle, 100)
    if not ok then print("[pls_mechanic] Config.SetFuel error: "..tostring(err)) end
    ok, err = pcall(Config.GiveKeys, vehicle, plate or Utils.TrimPlate(GetVehicleNumberPlateText(vehicle)))
    if not ok then print("[pls_mechanic] Config.GiveKeys error: "..tostring(err)) end
    TaskWarpPedIntoVehicle(cache.ped, vehicle, -1)
    Core.Notify(locale("shops_vehicle_spawned", data.label), "success")
end

local function returnServiceVehicle(shop)
    local done = lib.callback.await("pls_mechanic:server:shops:returnVehicle", false, shop.id)
    if done then
        ServiceVehicle = nil
    end
end

local function openGarageMenu(shop)
    local options = {}
    for index, vehicle in ipairs(Config.ServiceVehicles) do
        options[#options + 1] = {
            title = vehicle.label,
            description = ServiceVehicle and locale("shops_garage_return_first") or locale("shops_garage_spawn_desc"),
            icon = "fa-solid fa-truck-pickup",
            disabled = ServiceVehicle ~= nil,
            onSelect = function()
                spawnServiceVehicle(shop, index)
            end,
        }
    end
    options[#options + 1] = {
        title = locale("shops_garage_return"),
        description = ServiceVehicle and ServiceVehicle.plate or locale("shops_garage_no_vehicle"),
        icon = "fa-solid fa-square-parking",
        disabled = ServiceVehicle == nil,
        onSelect = function()
            returnServiceVehicle(shop)
        end,
    }
    lib.registerContext({
        id = "pls_mechanic_garage",
        title = locale("shops_garage_title", shop.name),
        options = options,
    })
    lib.showContext("pls_mechanic_garage")
end

--[[
                 _   _
     /\         | | (_)
    /  \   ___| |_ _  ___  _ __  ___
   / /\ \ / __| __| |/ _ \| '_ \/ __|
  / ____ \ (__| |_| | (_) | | | \__ \
 /_/    \_\___|\__|_|\___/|_| |_|___/
]]--

local function toggleDuty(shop)
    TriggerSecureEvent("pls_mechanic:server:shops:toggleDuty", shop.id)
end

ShopPoints.RegisterAction("duty", {
    label = locale("shops_duty_clock_in"),
    icon = "fa-solid fa-right-to-bracket",
    canInteract = function(shop)
        return Core.GetPermissions(shop.id).duty == true and Core.GetDutyShopId() ~= shop.id
    end,
    onSelect = toggleDuty,
})

ShopPoints.RegisterAction("duty", {
    label = locale("shops_duty_clock_out"),
    icon = "fa-solid fa-right-from-bracket",
    canInteract = function(shop)
        return Core.GetDutyShopId() == shop.id
    end,
    onSelect = toggleDuty,
})

ShopPoints.RegisterAction("boss", {
    label = locale("shops_boss_menu"),
    icon = "fa-solid fa-briefcase",
    perm = "bossmenu",
    onSelect = function(shop)
        local ok, err = pcall(Config.OpenBossMenu, shop.id, BRIDGE.GetPlayerJob())
        if not ok then
            print("[pls_mechanic] Config.OpenBossMenu error: "..tostring(err))
            Core.Notify(locale("shops_boss_menu_error"), "error")
        end
    end,
})

ShopPoints.RegisterAction("storage", {
    label = locale("shops_storage_open"),
    icon = "fa-solid fa-box-open",
    perm = "storage",
    onSelect = function(shop)
        local stashId = lib.callback.await("pls_mechanic:server:shops:openStash", false, shop.id)
        if stashId then
            BRIDGE.OpenStash(stashId, Config.Stash.weight, Config.Stash.slots)
        end
    end,
})

ShopPoints.RegisterAction("garage", {
    label = locale("shops_garage_open"),
    icon = "fa-solid fa-truck-pickup",
    perm = "duty",
    canInteract = function(shop)
        return not Config.RequireDuty or Core.GetDutyShopId() == shop.id
    end,
    onSelect = function(shop)
        openGarageMenu(shop)
    end,
})

-- Deposit to workshop account (society of the first job), any employee of the workshop
ShopPoints.RegisterAction("computer", {
    label = locale("shops_deposit_open"),
    icon = "fa-solid fa-piggy-bank",
    canInteract = function(shop)
        return Config.Deposit.enabled and Utils.ShopHasJob(shop, BRIDGE.GetPlayerJob())
    end,
    onSelect = function(shop)
        local account = lib.callback.await("pls_mechanic:server:shops:getAccount", false, shop.id)
        if not account or not account.ok then
            return Core.Notify(account and account.message or locale("no_permission"), "error")
        end
        local methods = {}
        for _, method in ipairs(Config.Deposit.methods) do
            local have = method == "bank" and account.bank or account.cash
            methods[#methods + 1] = { value = method, label = locale("shops_deposit_method_"..method, Config.Currency..Utils.FormatMoney(have)) }
        end
        local input = lib.inputDialog(locale("shops_deposit_title", shop.name), {
            { type = "number", label = locale("shops_deposit_amount"), description = locale("shops_deposit_balance", Config.Currency..Utils.FormatMoney(account.balance)), required = true, min = 1, max = Config.Deposit.max },
            { type = "select", label = locale("shops_deposit_method"), options = methods, default = methods[1] and methods[1].value, required = true },
        })
        if not input then return end
        local response = lib.callback.await("pls_mechanic:server:shops:deposit", false, shop.id, input[1], input[2])
        if response and response.message then
            Core.Notify(response.message, response.ok and "success" or "error")
        end
    end,
})

ShopPoints.RegisterAction("computer", {
    label = locale("shops_settings_open"),
    icon = "fa-solid fa-sliders",
    perm = "manage_shop",
    onSelect = function(shop)
        if Settings and Settings.Open then
            Settings.Open(shop.id)
        end
    end,
})

--[[
   _____ _
  / ____| |
 | (___ | |_ ___  _ __
  \___ \| __/ _ \| '_ \
  ____) | || (_) | |_) |
 |_____/ \__\___/| .__/
                 | |
                 |_|
]]--

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    RebuildToken = RebuildToken + 1
    removeTargets()
    removeBlips()
end)
