--[[
   _____ _        _   _
  / ____| |      | | (_)
 | (___ | |_ __ _| |_ _  ___  _ __  ___
  \___ \| __/ _` | __| |/ _ \| '_ \/ __|
  ____) | || (_| | |_| | (_) | | | \__ \
 |_____/ \__\__,_|\__|_|\___/|_| |_|___/

 Public repair stations (point type "station" from creator).
 Driver stops in the station and pays. Automatic service scene: engine off, hood open, cinematic camera
 around the vehicle, phases (check-in, diagnostics, repair with sparks / air tools, final check),
 fade out, vehicle repaired.
]]--

Stations = {}

local Busy = false
local PromptPoint = nil
local Sequence = nil    -- { vehicle, frozen, camera } while repairing

local function Notify(key, notifyType, ...)
    Core.Notify(locale(key, ...), notifyType or "inform")
end

local function ParseJobs(text)
    local jobs = {}
    for job in tostring(text or ""):gmatch("[^,%s]+") do
        jobs[job] = true
    end
    return jobs
end

local function JobAllowed(point)
    local jobs = ParseJobs(point.data and point.data.jobs)
    if next(jobs) == nil then return true end
    return jobs[BRIDGE.GetPlayerJob() or ""] == true
end

local function PointRadius(point)
    return point.radius or Config.PointTypes.station.radius
end

local function InStation(point, vehicle)
    return #(GetEntityCoords(vehicle) - Utils.Vec3(point.coords)) <= PointRadius(point)
end

local function PriceText(point)
    local price = math.floor(tonumber(point.data and point.data.price) or 0)
    if price <= 0 then return locale("station_free") end
    return Config.Currency..Utils.FormatMoney(price)
end

local function RepairLabels(repairs)
    local list = {}
    for _, key in pairs(repairs or {}) do
        table.insert(list, locale("station_repair_"..key))
    end
    return table.concat(list, ", ")
end

-- Returns ok, reason (locale key)
function Stations.CanUse(point)
    if Busy then return false end
    local vehicle = cache.vehicle
    if not vehicle or cache.seat ~= -1 then return false, "station_driver" end
    if not InStation(point, vehicle) then return false, "station_not_inside" end
    if not JobAllowed(point) then return false, "station_job" end
    return true
end

--[[
   _____
  / ____|
 | (___   ___  __ _ _   _  ___ _ __   ___ ___
  \___ \ / _ \/ _` | | | |/ _ \ '_ \ / __/ _ \
  ____) |  __/ (_| | |_| |  __/ | | | (_|  __/
 |_____/ \___|\__, |\__,_|\___|_| |_|\___\___|
                 | |
                 |_|
]]--

local function ApplyRepairs(vehicle, repairs)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    if repairs.body then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        if not repairs.engine then
            SetVehicleEngineHealth(vehicle, engineHealth)
        end
    end
    if repairs.engine then
        SetVehicleEngineHealth(vehicle, 1000.0)
    end
end

local function FadeOut(ms)
    DoScreenFadeOut(ms)
    local timeout = GetGameTimer() + ms + 1000
    while not IsScreenFadedOut() and GetGameTimer() < timeout do
        Wait(10)
    end
end

-- Cinematic camera slowly orbiting the vehicle
local function StartCamera(vehicle)
    local cfg = Config.Stations
    if not cfg.camera then return nil end
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local radius = math.max(max.y - min.y, max.x - min.x) * 0.5 + (cfg.cameraDistance or 2.8)
    local state = { active = true, cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true) }
    local angle = GetEntityHeading(vehicle) + 35.0
    local function place()
        local center = GetEntityCoords(vehicle)
        local rad = math.rad(angle)
        SetCamCoord(state.cam, center.x - math.sin(rad) * radius, center.y + math.cos(rad) * radius, center.z + (cfg.cameraHeight or 1.3))
    end
    place()
    PointCamAtEntity(state.cam, vehicle, 0.0, 0.0, 0.0, true)
    SetCamFov(state.cam, 50.0)
    RenderScriptCams(true, true, 1200, true, false)
    CreateThread(function()
        local last = GetGameTimer()
        while state.active and DoesEntityExist(vehicle) do
            local now = GetGameTimer()
            angle = angle + (cfg.cameraSpeed or 9.0) * (now - last) / 1000.0
            last = now
            place()
            Wait(0)
        end
    end)
    return state
end

local function StopCamera(state, ease)
    if not state then return end
    state.active = false
    RenderScriptCams(false, ease == true, ease and 800 or 0, true, false)
    DestroyCam(state.cam, false)
end

local function EndSequence()
    if not Sequence then return end
    local vehicle = Sequence.vehicle
    StopCamera(Sequence.camera, false)
    if Sequence.frozen and DoesEntityExist(vehicle) then
        FreezeEntityPosition(vehicle, false)
    end
    Sequence = nil
end

local function PhaseDuration(phase, total)
    if phase.duration then return phase.duration end
    return math.max(500, math.floor(total * (phase.share or 0)))
end

-- Service phases (already paid, can't be cancelled). Every phase keeps its time even when the library is busy.
local function RunService(vehicle, total)
    for _, phase in ipairs(Config.Stations.phases or {}) do
        if not DoesEntityExist(vehicle) or cache.vehicle ~= vehicle then return end
        local duration = PhaseDuration(phase, total)
        local started = GetGameTimer()
        Anim.Phase({
            label = locale(phase.label),
            duration = duration,
            sound = phase.sound,
            particle = phase.particle,
            vehicle = vehicle,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
        })
        local left = duration - (GetGameTimer() - started)
        if left > 0 then
            Wait(left)
        end
    end
end

local function RunSequence(vehicle, result)
    Sequence = { vehicle = vehicle, frozen = false }
    if Core.RequestControl(vehicle, 2000) then
        SetVehicleEngineOn(vehicle, false, true, true)
        FreezeEntityPosition(vehicle, true)
        SetVehicleDoorOpen(vehicle, 4, false, false)
        Sequence.frozen = true
    end
    Sequence.camera = StartCamera(vehicle)

    RunService(vehicle, result.duration * 1000)

    FadeOut(600)
    if Sequence then
        StopCamera(Sequence.camera, false)
        Sequence.camera = nil
    end
    if DoesEntityExist(vehicle) and Core.RequestControl(vehicle, 2000) then
        ApplyRepairs(vehicle, result.repairs or {})
        SetVehicleDoorShut(vehicle, 4, true)
    end
    EndSequence()
    Wait(400)
    DoScreenFadeIn(600)
    PlaySoundFrontend(-1, "PURCHASE", "HUD_LIQUOR_STORE_SOUNDSET", true)
    if result.price and result.price > 0 then
        Notify("station_done_paid", "success", Config.Currency..Utils.FormatMoney(result.price), locale("station_method_"..tostring(result.method)))
    else
        Notify("station_done", "success")
    end
end

function Stations.Open(shop, point)
    local ok, reason = Stations.CanUse(point)
    if not ok then
        if reason then Notify(reason, "error") end
        return
    end
    if Anim.IsBusy() or Core.IsExternalBusy() then
        return Notify("repair_busy", "error")
    end
    local repairs = point.data and point.data.repairs or {}
    if #repairs == 0 then
        return Notify("station_nothing", "error")
    end
    local confirm = lib.alertDialog({
        header = locale("station_title"),
        content = locale("station_confirm", RepairLabels(repairs), PriceText(point)),
        centered = true,
        cancel = true,
    })
    if confirm ~= "confirm" then return end

    local vehicle = cache.vehicle
    if Busy or not vehicle or cache.seat ~= -1 or not NetworkGetEntityIsNetworked(vehicle) then return end
    Busy = true
    local result = lib.callback.await("pls_mechanic:server:stations:repair", false, shop.id, point.id, NetworkGetNetworkIdFromEntity(vehicle))
    if not result or not result.ok then
        Busy = false
        return Notify(result and result.message or "station_failed", "error")
    end
    RunSequence(vehicle, result)
    Busy = false
end

--[[
  _____       _       _
 |  __ \     (_)     | |
 | |__) |__ _ _ _ __ | |_
 |  ___/ _ \| | '_ \| __|
 | |  | (_) | | | | | |_
 |_|   \___/|_|_| |_|\__|
]]--

ShopPoints.RegisterAction("station", {
    label = locale("station_use"),
    icon = "fa-solid fa-screwdriver-wrench",
    perm = nil,
    canInteract = function(_, point)
        return Stations.CanUse(point) == true
    end,
    onSelect = function(shop, point)
        CreateThread(function()
            Stations.Open(shop, point)
        end)
    end,
})

-- Station where the vehicle stands. Returns shop, point, distance to the closest station
local function FindStation(coords)
    local closest = nil
    for _, shop in pairs(Core.Shops) do
        for _, point in pairs(shop.points or {}) do
            if point.type == "station" then
                local distance = #(coords - Utils.Vec3(point.coords))
                if distance <= PointRadius(point) and JobAllowed(point) then
                    return shop, point, distance
                end
                if not closest or distance < closest then
                    closest = distance
                end
            end
        end
    end
    return nil, nil, closest
end

local function HidePrompt()
    if PromptPoint then
        lib.hideTextUI()
        PromptPoint = nil
    end
end

-- Drive-in prompt (targets usually don't work from a vehicle, markers mode has own prompt)
if Config.Stations.drivePrompt and not BRIDGE.UseMarkers then
    CreateThread(function()
        while true do
            local sleep = 1500
            local vehicle = cache.vehicle
            if vehicle and cache.seat == -1 and not Busy then
                local shop, point, distance = FindStation(GetEntityCoords(vehicle))
                if point then
                    sleep = 0
                    if PromptPoint ~= point.id then
                        lib.showTextUI(locale("station_prompt", PriceText(point)))
                        PromptPoint = point.id
                    end
                    if IsControlJustReleased(0, Config.Stations.promptKey) then
                        HidePrompt()
                        Stations.Open(shop, point)
                    end
                else
                    HidePrompt()
                    if distance and distance < 40.0 then
                        sleep = 500
                    end
                end
            else
                HidePrompt()
            end
            Wait(sleep)
        end
    end)
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    HidePrompt()
    if Sequence then
        EndSequence()
        DoScreenFadeIn(0)
    end
end)
