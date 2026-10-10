--[[
  _____  _                             _   _
 |  __ \(_)                           | | (_)
 | |  | |_  __ _  __ _ _ __   ___  ___| |_ _  ___ ___
 | |  | | |/ _` |/ _` | '_ \ / _ \/ __| __| |/ __/ __|
 | |__| | | (_| | (_| | | | | (_) \__ \ |_| | (__\__ \
 |_____/|_|\__,_|\__, |_| |_|\___/|___/\__|_|\___|___/
                  __/ |
                 |___/
 OBD scanner: walk to the driver door, plug the OBD connector, read the control unit with the tablet
 -> NUI "diagnostics" report -> repair workflow.
 Parts of unknown origin (stolen parts installed) get a badge, findings of pls_mechanic_illegal (server) are
 added to the fault codes.
]]--

Diagnostics = {}

local SCAN_DURATION = 7000     -- ms, plugging the connector + reading
local PLUG_DURATION = 2000
local Busy = false
local Current = nil            -- { vehicle, netId, keys = { ["service:oil"] = true } }
local TargetId = nil
local ScannerCount = { count = 0, time = 0 }
local LastReports = {}         -- [netId] = { plate, time } - report can be reopened without new scan (Config.DiagnosticsReopen)

local TuningMods = {
    { mod = 11, label = "diag_tuning_engine" },
    { mod = 12, label = "diag_tuning_brakes" },
    { mod = 13, label = "diag_tuning_transmission" },
    { mod = 15, label = "diag_tuning_suspension" },
    { mod = 16, label = "diag_tuning_armor" },
}

--[[
  _    _      _
 | |  | |    | |
 | |__| | ___| |_ __   ___ _ __ ___
 |  __  |/ _ \ | '_ \ / _ \ '__/ __|
 | |  | |  __/ | |_) |  __/ |  \__ \
 |_|  |_|\___|_| .__/ \___|_|  |___/
               | |
               |_|
]]--

local function permissionReason()
    -- illegal workshops have no duty, the crew only lacks the permission
    local shopId = Core.GetMyShopId()
    if shopId and Core.IsIllegalShop and Core.IsIllegalShop(shopId) then
        return locale("no_permission")
    end
    if Config.RequireDuty and not Core.IsOnDuty() then
        return locale("not_on_duty")
    end
    return locale("no_permission")
end

-- Scanner count is cached, target canInteract runs very often
local function hasScanner()
    local now = GetGameTimer()
    if now - ScannerCount.time > 2000 then
        ScannerCount.count = Core.CountTool("obd_scanner")
        ScannerCount.time = now
    end
    return ScannerCount.count > 0
end

local function toolRequirements(tools)
    local list = {}
    for _, key in ipairs(tools or {}) do
        local name = Utils.Item(key)
        list[#list + 1] = { item = name, label = Core.GetItemLabel(name), count = 1, have = Core.CountTool(key) }
    end
    return list
end

local function itemRequirements(items, multiplier)
    local _, list = Core.CheckItems(items, multiplier)
    return list
end

local function setRepairAccess(entry, perm)
    entry.canRepair = Core.HasPermission(perm) == true
    if not entry.canRepair then
        entry.reason = permissionReason()
    end
end

function Diagnostics.GetModelLabel(vehicle)
    local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(name)
    if not label or label == "NULL" then return name end
    return label
end

local function getClassLabel(class)
    local label = GetLabelText(("VEH_CLASS_%d"):format(class))
    if not label or label == "NULL" then return tostring(class) end
    return label
end

local function getTuning(vehicle)
    if GetVehicleModKit(vehicle) ~= 0 then
        SetVehicleModKit(vehicle, 0)
    end
    local list = {}
    for _, v in ipairs(TuningMods) do
        local level = GetVehicleMod(vehicle, v.mod)
        local value = locale("diag_tuning_stock")
        if level >= 0 then
            value = locale("diag_tuning_level", level + 1, math.max(GetNumVehicleMods(vehicle, v.mod), level + 1))
        end
        list[#list + 1] = { label = locale(v.label), value = value }
    end
    list[#list + 1] = { label = locale("diag_tuning_turbo"), value = IsToggleModOn(vehicle, 18) and locale("diag_tuning_installed") or locale("diag_tuning_none") }
    return list
end

local function addFault(faults, seen, code, partLabel)
    if not code or seen[code] then return end
    seen[code] = true
    faults[#faults + 1] = { code = code, description = Config.OBDCodes[code] or "", part = partLabel }
end

-- OBD codes of other resources (server validated) { code, label, severity } -> fault without part
local function addFindings(faults, seen, findings)
    for _, finding in ipairs(type(findings) == "table" and findings or {}) do
        if type(finding) == "table" and type(finding.code) == "string" and not seen[finding.code] then
            seen[finding.code] = true
            faults[#faults + 1] = {
                code = finding.code,
                description = type(finding.label) == "string" and finding.label or (Config.OBDCodes[finding.code] or ""),
                part = "",
                severity = finding.severity == "critical" and "critical" or "warning",
            }
        end
    end
end

-- Full NUI payload (spec: diagnostics view). keys = allowed steps for "diagnostics:start"
-- findings = OBD codes of pls_mechanic_illegal from the server
local function buildReport(vehicle, netId, data, findings)
    local class = GetVehicleClass(vehicle)
    local classWear = Config.ClassWear[class] or 1.0
    local isEv = data.ev == true
    local origin = type(data.origin) == "table" and data.origin or {}
    local keys = {}
    local faults, seenFaults = {}, {}
    local service, core, body = {}, {}, {}

    for key, part in pairs(Config.ServiceParts) do
        local life = data.service and data.service[key]
        if life and Utils.PartFitsVehicle(part, isEv) then
            life = Utils.Clamp(life + 0.0, 0.0, 100.0)
            local state = Utils.GetPartState(life)
            local entry = {
                key = key,
                label = part.label,
                life = Utils.Round(life, 1),
                state = state,
                nextServiceKm = math.max(0, math.floor(life / 100 * (part.interval or 0) / classWear)),
                items = itemRequirements(part.items),
                tools = toolRequirements(part.tools),
                location = part.location or "anywhere",
                unknownOrigin = origin[key] == "unknown" or nil,
            }
            if state ~= "optimal" and part.obd then
                entry.obd = part.obd
                addFault(faults, seenFaults, part.obd, part.label)
            end
            setRepairAccess(entry, part.perm)
            service[#service + 1] = entry
            keys["service:"..key] = true
        end
    end
    table.sort(service, function(a, b) return a.life < b.life end)

    local hasTurbo = IsToggleModOn(vehicle, 18)
    for key, part in pairs(Config.CoreParts) do
        local health = data.core and data.core[key]
        if health and Utils.PartFitsVehicle(part, isEv) and (not part.requiresTurbo or hasTurbo) then
            health = Utils.Clamp(health + 0.0, 0.0, 100.0)
            local state = Utils.GetPartState(health)
            local entry = {
                key = key,
                label = part.label,
                health = Utils.Round(health, 1),
                state = state,
                items = itemRequirements(part.items),
                tools = toolRequirements(part.tools),
                location = part.location or "anywhere",
                unknownOrigin = origin[key] == "unknown" or nil,
            }
            if state ~= "optimal" and part.obd then
                entry.obd = part.obd
                addFault(faults, seenFaults, part.obd, part.label)
            end
            setRepairAccess(entry, part.perm)
            core[#core + 1] = entry
            keys["core:"..key] = true
        end
    end
    table.sort(core, function(a, b) return a.health < b.health end)

    local bodyHealth = GetVehicleBodyHealth(vehicle)
    for _, key in ipairs(Repair.GetBodyDamage(vehicle)) do
        local bodyKind = Utils.SplitBodyKey(key)
        local part = Config.BodyParts[bodyKind]
        local multiplier = bodyKind == "deformation" and Repair.GetDeformationCount(bodyHealth) or 1
        local entry = {
            key = key,
            label = Repair.GetStepLabel("body", key),
            items = itemRequirements(part.items, multiplier),
            tools = toolRequirements(part.tools),
            location = part.location or "anywhere",
        }
        setRepairAccess(entry, Config.BodyRepairPermission)
        body[#body + 1] = entry
        keys["body:"..key] = true
    end
    addFindings(faults, seenFaults, findings)

    local report = {
        netId = netId,
        plate = data.plate or Utils.TrimPlate(GetVehicleNumberPlateText(vehicle)),
        model = Diagnostics.GetModelLabel(vehicle),
        vehicleClass = getClassLabel(class),
        mileage = Utils.Round(data.mileage or 0, 1),
        ev = isEv,
        health = {
            engine = math.floor(Utils.Clamp(GetVehicleEngineHealth(vehicle), 0.0, 1000.0)),
            body = math.floor(Utils.Clamp(bodyHealth, 0.0, 1000.0)),
            tank = math.floor(Utils.Clamp(GetVehiclePetrolTankHealth(vehicle), 0.0, 1000.0)),
        },
        service = service,
        core = core,
        body = body,
        tuning = getTuning(vehicle),
        faultCodes = faults,
    }
    return report, keys
end

-- Rolls windows up (a rolled down window reads as broken)
local function prepareVehicle(vehicle)
    if not Core.RequestControl(vehicle, 1500) then return end
    for i = 0, 7 do RollUpWindow(vehicle, i) end
end

-- Crouch spot at the driver door, the OBD port is under the dashboard. Returns coords, heading
local function getObdPosition(vehicle)
    local min = GetModelDimensions(GetEntityModel(vehicle))
    local y = 0.0
    local bone = GetEntityBoneIndexByName(vehicle, "door_dside_f")
    if bone ~= -1 then
        local world = GetWorldPositionOfEntityBone(vehicle, bone)
        -- door bone is the hinge, the door opening is behind it
        y = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z).y - 0.8
    end
    return GetOffsetFromEntityInWorldCoords(vehicle, min.x - 0.55, y, 0.0), GetEntityHeading(vehicle) - 90.0
end

--[[
   _____ _             _
  / ____| |           | |
 | (___ | |_ __ _ _ __| |_
  \___ \| __/ _` | '__| __|
  ____) | || (_| | |  | |_
 |_____/ \__\__,_|_|   \__|
]]--

local function runDiagnostics(vehicle)
    local netId = VehToNet(vehicle)
    local inside = cache.vehicle == vehicle
    local cancel = function() return not DoesEntityExist(vehicle) end
    local openedDoor = false
    local scanDuration = SCAN_DURATION
    prepareVehicle(vehicle)
    if not inside then
        local coords, heading = getObdPosition(vehicle)
        Anim.WalkAround(vehicle, coords, heading, 8000, cancel)
        if not DoesEntityExist(vehicle) or #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > 8.0 then
            Core.Notify(locale("too_far"), "error")
            return
        end
        openedDoor = Anim.OpenDoor(vehicle, 0)
        local plugged = Anim.Phase({ label = locale("diag_phase_plug"), duration = PLUG_DURATION, anim = "kneel", vehicle = vehicle, cancel = cancel })
        if not plugged then
            if openedDoor then Anim.CloseDoor(vehicle, 0) end
            Core.Notify(locale("cancelled"), "error")
            return
        end
        scanDuration = SCAN_DURATION - PLUG_DURATION
    end
    local scanned = Anim.Phase({
        label = locale("diag_progress"),
        duration = scanDuration,
        anim = "tablet",
        prop = "scanner",
        sound = { "connect", "scanner" },
        vehicle = vehicle,
        cancel = cancel,
    })
    if openedDoor then Anim.CloseDoor(vehicle, 0) end
    if not scanned then
        Core.Notify(locale("cancelled"), "error")
        return
    end
    local result = lib.callback.await("pls_mechanic:server:repair:diagnose", false, netId, GetVehicleClass(vehicle))
    if not result or not result.ok or not DoesEntityExist(vehicle) then
        Core.Notify(result and result.message or locale("diag_failed"), "error")
        return
    end
    PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
    local report, keys = buildReport(vehicle, netId, result.data, result.findings)
    Current = { vehicle = vehicle, netId = netId, keys = keys }
    LastReports[netId] = { plate = GetVehicleNumberPlateText(vehicle), time = GetGameTimer() }
    Core.Nui.Open("diagnostics", report)
end

-- Common checks before diagnostics / reopening report (notifies the reason)
local function canDiagnose(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then
        Core.Notify(locale("no_vehicle"), "error")
        return false
    end
    if cache.vehicle and cache.vehicle ~= vehicle then
        Core.Notify(locale("diag_leave_vehicle"), "error")
        return false
    end
    if Config.ExcludedClasses[GetVehicleClass(vehicle)] then
        Core.Notify(locale("vehicle_excluded"), "error")
        return false
    end
    if not Core.HasPermission("diagnose") then
        Core.Notify(permissionReason(), "error")
        return false
    end
    if Core.CountTool("obd_scanner") < 1 then
        Core.Notify(locale("missing_tool", Core.GetItemLabel(Utils.Item("obd_scanner"))), "error")
        return false
    end
    if (Repair and Repair.IsBusy and Repair.IsBusy()) or Anim.IsBusy() or Core.IsExternalBusy() then
        Core.Notify(locale("repair_busy"), "error")
        return false
    end
    if Tuning and ((Tuning.IsInstalling and Tuning.IsInstalling()) or (Tuning.IsOpen and Tuning.IsOpen())) then
        Core.Notify(locale("tuning_busy"), "error")
        return false
    end
    return true
end

-- Full diagnostics flow. Safe to call from anywhere (runs in own thread).
function Diagnostics.Start(vehicle)
    CreateThread(function()
        if Busy then return end
        if not canDiagnose(vehicle) then return end
        Busy = true
        local ok, err = pcall(runDiagnostics, vehicle)
        if not ok then
            print("[pls_mechanic] diagnostics error: "..tostring(err))
            Anim.Cleanup()
        end
        Busy = false
    end)
end

function Diagnostics.IsBusy()
    return Busy
end

-- Last report of this vehicle is still valid (same plate, within Config.DiagnosticsReopen minutes)
function Diagnostics.CanReopen(vehicle)
    local minutes = Config.DiagnosticsReopen or 0
    if minutes <= 0 or not vehicle or not DoesEntityExist(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then return false end
    local last = LastReports[VehToNet(vehicle)]
    if not last or GetGameTimer() - last.time > minutes * 60000 then return false end
    return last.plate == GetVehicleNumberPlateText(vehicle)
end

-- Opens last report again with fresh data (part states, items) without walking and scanning
function Diagnostics.Reopen(vehicle)
    CreateThread(function()
        if Busy then return end
        if not Diagnostics.CanReopen(vehicle) then
            Core.Notify(locale("diag_reopen_expired"), "error")
            return
        end
        if not canDiagnose(vehicle) then return end
        if cache.vehicle ~= vehicle and #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > 8.0 then
            Core.Notify(locale("too_far"), "error")
            return
        end
        Busy = true
        local ok, err = pcall(function()
            local netId = VehToNet(vehicle)
            local result = lib.callback.await("pls_mechanic:server:repair:diagnose", false, netId, GetVehicleClass(vehicle))
            if not result or not result.ok or not DoesEntityExist(vehicle) then
                Core.Notify(result and result.message or locale("diag_failed"), "error")
                return
            end
            local report, keys = buildReport(vehicle, netId, result.data, result.findings)
            Current = { vehicle = vehicle, netId = netId, keys = keys }
            Core.Nui.Open("diagnostics", report)
        end)
        if not ok then
            print("[pls_mechanic] diagnostics reopen error: "..tostring(err))
        end
        Busy = false
    end)
end

--[[
  _   _ _    _ _____
 | \ | | |  | |_   _|
 |  \| | |  | | | |
 | . ` | |  | | | |
 | |\  | |__| |_| |_
 |_| \_|\____/|_____|
]]--

-- { netId, steps = { { kind, key } } } -> Result. Client closes the report and runs the workflow.
RegisterNUICallback("diagnostics:start", function(data, cb)
    local current = Current
    if not current or type(data) ~= "table" or tonumber(data.netId) ~= current.netId then
        cb({ ok = false, message = locale("diag_expired") })
        return
    end
    if not DoesEntityExist(current.vehicle) then
        cb({ ok = false, message = locale("no_vehicle") })
        return
    end
    local steps = {}
    for _, step in ipairs(type(data.steps) == "table" and data.steps or {}) do
        if type(step) == "table" and type(step.kind) == "string" and type(step.key) == "string" and current.keys[step.kind..":"..step.key] then
            steps[#steps + 1] = { kind = step.kind, key = step.key }
        end
    end
    if #steps == 0 then
        cb({ ok = false, message = locale("repair_no_steps") })
        return
    end
    if not Repair or not Repair.StartWorkflow then
        cb({ ok = false, message = locale("diag_failed") })
        return
    end
    if Repair.IsBusy() then
        cb({ ok = false, message = locale("repair_busy") })
        return
    end
    if cache.vehicle then
        cb({ ok = false, message = locale("repair_leave_vehicle") })
        return
    end
    -- everything is checked before start, report stays open with the reason
    local info = nil
    if Repair.Preflight then
        local ready, message, preflightInfo = Repair.Preflight(current.vehicle, steps)
        if not ready then
            cb({ ok = false, message = message })
            return
        end
        info = preflightInfo
    end
    cb({ ok = true })
    Current = nil
    Core.Nui.Close("diagnostics")
    -- parts to fetch from the workshop storage during the workflow (Config.Fetch)
    if Repair.StartWorkflow(current.vehicle, steps) and info then
        Core.Notify(info, "inform")
    end
end)

Core.Nui.OnClose("diagnostics", function()
    Current = nil
end)

--[[
  _______                   _
 |__   __|                 | |
    | | __ _ _ __ __ _  ___| |_
    | |/ _` | '__/ _` |/ _ \ __|
    | | (_| | | | (_| |  __/ |_
    |_|\__,_|_|  \__, |\___|\__|
                  __/ |
                 |___/
]]--

CreateThread(function()
    TargetId = BRIDGE.AddGlobalVehicleTarget({
        {
            name = "pls_mechanic_diagnose",
            label = locale("diag_target"),
            icon = "fa-solid fa-laptop-code",
            bones = { "bonnet", "engine", "door_dside_f" },
            distance = 2.0,
            canInteract = function(entity)
                if Busy or cache.vehicle or not entity or entity == 0 then return false end
                return Core.HasPermission("diagnose") and hasScanner()
            end,
            onSelect = function(data)
                local entity = type(data) == "table" and data.entity or data
                Diagnostics.Start(entity)
            end,
        },
        {
            name = "pls_mechanic_diagnose_reopen",
            label = locale("diag_reopen_target"),
            icon = "fa-solid fa-clipboard-list",
            distance = 2.5,
            canInteract = function(entity)
                if Busy or cache.vehicle or not entity or entity == 0 then return false end
                return Core.HasPermission("diagnose") and hasScanner() and Diagnostics.CanReopen(entity)
            end,
            onSelect = function(data)
                local entity = type(data) == "table" and data.entity or data
                Diagnostics.Reopen(entity)
            end,
        },
    })
end)

Items.Register("obd_scanner", function()
    CreateThread(function()
        local vehicle = cache.vehicle or Core.GetClosestVehicle(4.0)
        if not vehicle then
            Core.Notify(locale("no_vehicle"), "error")
            return
        end
        if not Diagnostics.CanReopen(vehicle) then
            Diagnostics.Start(vehicle)
            return
        end
        -- valid last report: choose new scan or reopen
        lib.registerContext({
            id = "pls_mechanic_scanner",
            title = locale("diag_target"),
            options = {
                { title = locale("diag_new_scan"), icon = "fa-solid fa-laptop-code", onSelect = function() Diagnostics.Start(vehicle) end },
                { title = locale("diag_reopen_target"), icon = "fa-solid fa-clipboard-list", onSelect = function() Diagnostics.Reopen(vehicle) end },
            },
        })
        lib.showContext("pls_mechanic_scanner")
    end)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if TargetId then
        BRIDGE.RemoveGlobalVehicleTarget(TargetId)
    end
end)
