--[[
   _____ _        _   _
  / ____| |      | | (_)
 | (___ | |_ __ _| |_ _  ___  _ __  ___
  \___ \| __/ _` | __| |/ _ \| '_ \/ __|
  ____) | || (_| | |_| | (_) | | | \__ \
 |_____/ \__\__,_|\__|_|\___/|_| |_|___/

 Public repair station: validation, payment (cash first then bank) to the workshop society,
 service / core parts via Vehicles (new clean parts = origin "unknown" is cleared), engine / body applied by the
 client after success.
]]--

StationsServer = {}

local Busy = {}     -- [src] = GetGameTimer() until next repair is allowed

local function PlayerName(src)
    local name = BRIDGE.GetPlayerFullName(src)
    if not name or name == "" then
        name = GetPlayerName(src) or tostring(src)
    end
    return name
end

local function ParseJobs(text)
    local jobs = {}
    for job in tostring(text or ""):gmatch("[^,%s]+") do
        jobs[job] = true
    end
    return jobs
end

-- Pays by Config.Stations.paymentMethods order. Returns method or nil
local function Pay(src, amount)
    for _, method in ipairs(Config.Stations.paymentMethods or { "cash", "bank" }) do
        if method == "cash" and (BRIDGE.GetItemCount(src, "money") or 0) >= amount then
            BRIDGE.RemoveItem(src, "money", amount)
            return "cash"
        elseif method == "bank" and (BRIDGE.GetPlayerBankMoney(src) or 0) >= amount and BRIDGE.RemovePlayerBankMoney(src, amount) then
            return "bank"
        end
    end
    return nil
end

local function Fail(message)
    return { ok = false, message = message }
end

lib.callback.register("pls_mechanic:server:stations:repair", function(src, shopId, pointId, netId)
    local now = GetGameTimer()
    if Busy[src] and Busy[src] > now then return Fail("station_busy") end
    Busy[src] = now + 3000

    local shop = Shops.Get(shopId)
    local point = shop and Utils.GetShopPoint(shop, pointId)
    if not point or point.type ~= "station" then return Fail("station_invalid") end

    local ped = GetPlayerPed(src)
    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or GetVehiclePedIsIn(ped, false) ~= entity or GetPedInVehicleSeat(entity, -1) ~= ped then
        return Fail("station_driver")
    end
    local radius = point.radius or Config.PointTypes.station.radius
    if #(GetEntityCoords(entity) - Utils.Vec3(point.coords)) > radius + 1.5 then
        return Fail("station_not_inside")
    end

    local data = point.data or {}
    local jobs = ParseJobs(data.jobs)
    if next(jobs) ~= nil and not jobs[BRIDGE.GetPlayerJob(src) or ""] then
        return Fail("station_job")
    end
    if data.onlyWithoutMechanic and Shops.CountOnDuty(shop.id) > 0 then
        return Fail("station_mechanic_available")
    end

    local repairs = {}
    for _, key in pairs(data.repairs or {}) do
        repairs[key] = true
    end
    local vehicleData = nil
    if (repairs.service or repairs.core) and Vehicles and Vehicles.GetByEntity and Vehicles.SetPart then
        vehicleData = Vehicles.GetByEntity(entity)
    end
    if not repairs.engine and not repairs.body and not vehicleData then
        return Fail(next(repairs) and "vehicle_excluded" or "station_nothing")
    end

    local price = math.max(0, math.floor(tonumber(data.price) or 0))
    local method = nil
    if price > 0 then
        method = Pay(src, price)
        if not method then return Fail("not_enough_money") end
        local job = Config.Stations.societyPayment and Shops.GetSocietyJob(shop.id)
        if job then
            BRIDGE.AddSocietyMoney(job, price)
        end
    end

    local done = {}
    if repairs.engine then table.insert(done, "engine") end
    if repairs.body then table.insert(done, "body") end
    if vehicleData then
        if repairs.service then
            for key in pairs(vehicleData.service or {}) do
                Vehicles.SetPart(vehicleData.plate, "service", key, 100)
                if Vehicles.SetPartOrigin then Vehicles.SetPartOrigin(vehicleData.plate, key, nil) end
            end
            table.insert(done, "service")
        end
        if repairs.core then
            for key in pairs(vehicleData.core or {}) do
                Vehicles.SetPart(vehicleData.plate, "core", key, 100)
                if Vehicles.SetPartOrigin then Vehicles.SetPartOrigin(vehicleData.plate, key, nil) end
            end
            table.insert(done, "core")
        end
    end

    local labels = {}
    for _, key in ipairs(done) do
        table.insert(labels, locale("station_repair_"..key))
    end
    -- real plate (trusted plate of the vehicle, fake plate alias resolved)
    local plate = vehicleData and vehicleData.plate or nil
    if not plate then
        plate = Vehicles and Vehicles.GetEntityPlate and Vehicles.GetEntityPlate(entity) or Utils.TrimPlate(GetVehicleNumberPlateText(entity))
    end
    if plate and plate ~= "" then
        History.Add(plate, {
            shopId = shop.id,
            mechanic = locale("station_history_mechanic"),
            type = "station",
            label = locale("station_history_label", table.concat(labels, ", ")),
            items = {},
            mileage = vehicleData and vehicleData.mileage or 0,
        })
    end
    OpenServer.Log(src, "station_repair", ("%s used repair station of %s (%s) for %s, paid %d (%s)"):format(PlayerName(src), shop.name, table.concat(done, ", "), plate or "-", price, method or "free"), {
        shopId = shop.id,
        pointId = point.id,
        plate = plate,
        price = price,
        method = method,
        repairs = done,
    })

    local duration = math.max(1, math.floor(tonumber(data.duration) or 20))
    Busy[src] = now + duration * 1000
    return {
        ok = true,
        repairs = { engine = repairs.engine == true, body = repairs.body == true },
        duration = duration,
        price = price,
        method = method,
    }
end)

AddEventHandler("playerDropped", function()
    Busy[source] = nil
end)
