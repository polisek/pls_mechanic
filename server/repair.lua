--[[
  _____                  _
 |  __ \                (_)
 | |__) |___ _ __   __ _ _ _ __
 |  _  // _ \ '_ \ / _` | | '__|
 | | \ \  __/ |_) | (_| | | |
 |_|  \_\___| .__/ \__,_|_|_|
            | |
            |_|
 Server authority for diagnostics, repair steps, quick repairs, kits and service book.
 Step flow: "begin" validates everything and starts a timer, "step" / "kit" validates again,
 requires the timer (animation duration) and applies the result.
 Parts are consumed by the rules of the workshop (server/items.lua). An installed service / core part gets the lowest
 quality of the stolen items used (clean = 100) and the origin "unknown" when a stolen item was used.
]]--

RepairServer = {}

local MAX_DISTANCE = 8.0          -- player <-> vehicle centre (long vehicles need more than 6 m at the trunk)
local BOOK_DISTANCE = 10.0
local DURATION_TOLERANCE = 0.9    -- step must take at least 90 % of its duration

local Pending = {}                -- [src] = { netId, kind, key, time, duration }
local Cooldowns = {}              -- [src] = { [action] = time }
local ItemLabels = nil

local SideNames = { front = "repair_pos_front", rear = "repair_pos_rear", left = "repair_pos_left", right = "repair_pos_right" }
local DoorPositions = { [0] = "repair_pos_front_left", [1] = "repair_pos_rear_left", [2] = "repair_pos_front_right", [3] = "repair_pos_rear_right" }
local WindowPositions = {
    [0] = "repair_pos_front_left", [1] = "repair_pos_front_right", [2] = "repair_pos_rear_left", [3] = "repair_pos_rear_right",
    [4] = "repair_pos_middle_left", [5] = "repair_pos_middle_right", [6] = "repair_pos_windscreen", [7] = "repair_pos_rear_windscreen",
}
local WheelPositions = {
    [0] = "repair_pos_front_left", [1] = "repair_pos_front_right", [2] = "repair_pos_middle_left",
    [3] = "repair_pos_middle_right", [4] = "repair_pos_rear_left", [5] = "repair_pos_rear_right",
}

-- Quick repair item -> which steps it may do
local QuickRepairKinds = {
    tyre = function(kind, key) return kind == "body" and key:sub(1, 5) == "tyre:" end,
    car_wheel = function(kind, key) return kind == "body" and key:sub(1, 6) == "wheel:" end,
    car_battery = function(kind, key) return kind == "core" and key == "battery" end,
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

local function checkCooldown(src, action, ms)
    local now = GetGameTimer()
    Cooldowns[src] = Cooldowns[src] or {}
    local last = Cooldowns[src][action]
    if last and now - last < ms then return false end
    Cooldowns[src][action] = now
    return true
end

local function itemLabel(itemName)
    if not ItemLabels then
        ItemLabels = {}
        for name, data in pairs(BRIDGE.GetItems() or {}) do
            if type(data) == "table" then
                ItemLabels[name] = data.label or name
            end
        end
    end
    return ItemLabels[itemName] or itemName
end

local function mechanicName(src)
    local name = BRIDGE.GetPlayerFullName(src)
    if not name or name == "" then
        name = GetPlayerName(src) or tostring(src)
    end
    return name
end

local function permissionReason(src)
    -- illegal workshops have no duty, the crew only lacks the permission
    local shopId = Shops.GetPlayerShopId(src)
    if shopId and Shops.IsIllegal and Shops.IsIllegal(shopId) then
        return "no_permission"
    end
    if Config.RequireDuty and not Player(src).state.pls_mechanic_duty then
        return "not_on_duty"
    end
    return "no_permission"
end

local function scaleItems(items, multiplier)
    local result = {}
    for _, v in ipairs(items or {}) do
        result[#result + 1] = { item = v.item, count = v.count * (multiplier or 1) }
    end
    return result
end

local function missingText(missing)
    local parts = {}
    for _, v in ipairs(missing or {}) do
        parts[#parts + 1] = ("%dx %s"):format(v.count, itemLabel(Utils.Item(v.item)))
    end
    return table.concat(parts, ", ")
end

local function historyItems(items)
    local result = {}
    for _, v in ipairs(items or {}) do
        result[#result + 1] = { label = itemLabel(Utils.Item(v.item)), count = v.count }
    end
    return result
end

local function getVehicleData(entity)
    if not Vehicles or not Vehicles.GetByEntity then return nil end
    return Vehicles.GetByEntity(entity)
end

local function resolvePlate(plate)
    if Vehicles and Vehicles.ResolvePlate then
        return Vehicles.ResolvePlate(plate)
    end
    return Utils.TrimPlate(plate)
end

-- Trusted real plate of a vehicle entity (the owner client can change the plate text to another player's plate)
local function entityPlate(entity)
    if Vehicles and Vehicles.GetEntityPlate then
        return (Vehicles.GetEntityPlate(entity))
    end
    return Utils.TrimPlate(GetVehicleNumberPlateText(entity))
end

-- Findings of pls_mechanic_illegal for the OBD code list { { code, label, severity } }
local function getDiagnosticFindings(plate)
    local resource = Config.IllegalResource or "pls_mechanic_illegal"
    if not plate or GetResourceState(resource) ~= "started" then return {} end
    local ok, findings = pcall(function() return exports[resource]:GetDiagnosticFindings(plate) end)
    if not ok then
        print("[pls_mechanic] GetDiagnosticFindings error: "..tostring(findings))
        return {}
    end
    local list = {}
    for _, finding in ipairs(type(findings) == "table" and findings or {}) do
        if #list >= 10 then break end
        if type(finding) == "table" and type(finding.code) == "string" and finding.code ~= "" and #finding.code <= 16 then
            list[#list + 1] = {
                code = finding.code,
                label = type(finding.label) == "string" and finding.label:sub(1, 160) or "",
                severity = finding.severity == "critical" and "critical" or "warning",
            }
        end
    end
    return list
end

local function getVehicleEntity(src, netId)
    local entity = Shops.GetEntity(tonumber(netId))
    if not entity or GetEntityType(entity) ~= 2 then return nil, "no_vehicle" end
    if not Shops.IsNearEntity(src, entity, MAX_DISTANCE) then return nil, "too_far" end
    return entity
end

local function isValidBodyKey(bodyKind, index)
    if not bodyKind or not Config.BodyParts[bodyKind] then return false end
    if bodyKind == "door" then
        return math.type(index) == "integer" and index >= 0 and index <= 3
    elseif bodyKind == "window" then
        return math.type(index) == "integer" and index >= 0 and index <= 7
    elseif bodyKind == "tyre" or bodyKind == "wheel" then
        return math.type(index) == "integer" and index >= 0 and index <= 5
    elseif bodyKind == "bumper" then
        return index == "front" or index == "rear"
    elseif bodyKind == "headlight" then
        return index == "left" or index == "right"
    end
    return index == nil
end

function RepairServer.GetStepLabel(kind, key)
    if kind == "service" then
        local part = Config.ServiceParts[key]
        return part and part.label or tostring(key)
    elseif kind == "core" then
        local part = Config.CoreParts[key]
        return part and part.label or tostring(key)
    end
    local bodyKind, index = Utils.SplitBodyKey(key)
    local part = Config.BodyParts[bodyKind]
    if not part then return tostring(key) end
    local position = nil
    if bodyKind == "door" then
        position = DoorPositions[index]
    elseif bodyKind == "window" then
        position = WindowPositions[index]
    elseif bodyKind == "tyre" or bodyKind == "wheel" then
        position = WheelPositions[index]
    elseif bodyKind == "bumper" or bodyKind == "headlight" then
        position = SideNames[index]
    end
    if position then
        return ("%s (%s)"):format(part.label, locale(position))
    end
    return part.label
end

-- body_panel count for bodywork by body health (same rule as client)
function RepairServer.GetDeformationCount(bodyHealth)
    local count = 1
    local part = Config.BodyParts.deformation
    for _, severity in ipairs(part and part.severity or {}) do
        if bodyHealth <= severity.maxBodyHealth and severity.count > count then
            count = severity.count
        end
    end
    return count
end

local function resolveStep(kind, key)
    if type(key) ~= "string" or #key > 32 then return nil end
    if kind == "service" or kind == "core" then
        local part = (kind == "service" and Config.ServiceParts or Config.CoreParts)[key]
        if not part then return nil end
        return { kind = kind, key = key, part = part, perm = part.perm, location = part.location or "anywhere", duration = part.duration or 10000, label = part.label }
    elseif kind == "body" then
        local bodyKind, index = Utils.SplitBodyKey(key)
        if not isValidBodyKey(bodyKind, index) then return nil end
        local part = Config.BodyParts[bodyKind]
        return {
            kind = kind, key = key, part = part, perm = Config.BodyRepairPermission, location = part.location or "anywhere",
            duration = part.duration or 10000, label = RepairServer.GetStepLabel(kind, key),
            bodyKind = bodyKind, wheel = (bodyKind == "tyre" or bodyKind == "wheel") and index or nil,
        }
    end
    return nil
end

--[[
   _____ _
  / ____| |
 | (___ | |_ ___ _ __  ___
  \___ \| __/ _ \ '_ \/ __|
  ____) | ||  __/ |_) \__ \
 |_____/ \__\___| .__/|___/
                | |
                |_|
]]--

-- Full validation of repair step. Returns ok, message, ctx
local function validateStep(src, netId, kind, key, quick)
    local step = resolveStep(kind, key)
    if not step then return false, locale("repair_invalid_step") end
    if quick ~= nil then
        local quickConfig = Config.QuickRepairs[quick]
        local matches = QuickRepairKinds[quick]
        if not quickConfig or not matches or not matches(kind, key) then return false, locale("repair_invalid_step") end
        if quickConfig.requireJack == false then step.location = "anywhere" end
    end

    local allowed, shopId = Shops.HasPermission(src, step.perm)
    if not allowed then return false, locale(permissionReason(src)) end

    local entity, entityError = getVehicleEntity(src, netId)
    if not entity then return false, locale(entityError) end

    local data = getVehicleData(entity)
    if kind ~= "body" then
        if not data then return false, locale("vehicle_excluded") end
        local value = data[kind] and data[kind][key]
        if value == nil or not Utils.PartFitsVehicle(step.part, data.ev) then return false, locale("repair_part_not_fitted") end
        if value >= 99.95 then return false, locale("repair_part_ok") end
    end

    local locationOk, reason = Shops.CheckLocation(entity, step.location, step.wheel)
    if not locationOk then return false, locale(reason or "location_bay") end

    local multiplier = 1
    if step.bodyKind == "deformation" then
        multiplier = RepairServer.GetDeformationCount(GetVehicleBodyHealth(entity))
    end
    local items = scaleItems(step.part.items, multiplier)

    -- parts by the rules of the workshop (illegal: stolen first, legal: clean only)
    local hasTools, missingTool = Shops.HasTools(src, step.part.tools, shopId)
    if not hasTools then return false, locale("missing_tool", itemLabel(Utils.Item(missingTool))) end
    local hasItems, missing = Shops.HasItems(src, items, 1, shopId)
    if not hasItems then return false, locale("missing_items", missingText(missing)) end

    return true, nil, {
        step = step,
        entity = entity,
        shopId = shopId,
        data = data,
        plate = data and data.plate or entityPlate(entity),
        items = items,
    }
end

-- Condition + origin of the installed service / core part from the consumed items
local function installPart(ctx, kind, key, consumed)
    if kind == "body" or not Vehicles or not Vehicles.SetPart then return 100, false end
    local quality, stolen = ItemRules.GetConsumedQuality(consumed)
    Vehicles.SetPart(ctx.plate, kind, key, quality)
    if Vehicles.SetPartOrigin then
        Vehicles.SetPartOrigin(ctx.plate, key, stolen and "unknown" or nil)
    end
    return quality, stolen
end

local function completeStep(src, netId, kind, key, quick)
    local pending = Pending[src]
    Pending[src] = nil
    if not pending or pending.netId ~= netId or pending.kind ~= kind or pending.key ~= key then
        return false, locale("repair_not_started")
    end
    if GetGameTimer() - pending.time < pending.duration * DURATION_TOLERANCE then
        return false, locale("repair_too_fast")
    end
    local ok, message, ctx = validateStep(src, netId, kind, key, quick)
    if not ok then return false, message end

    local step = ctx.step
    local consumed, removed = Shops.RemoveItems(src, ctx.items, 1, ctx.shopId)
    if not removed then
        -- inventory changed after the check: what was taken goes back
        Shops.AddItems(src, consumed, ctx.shopId)
        return false, locale("missing_items", missingText(ctx.items))
    end
    if step.part.salvage and #step.part.salvage > 0 then
        Shops.AddItems(src, step.part.salvage, ctx.shopId)
    end
    local quality, stolen = installPart(ctx, kind, key, consumed)
    WorkLog.Add(src, ctx.plate, { label = step.label, labor = step.part.labor, items = ctx.items })
    History.Add(ctx.plate, {
        shopId = ctx.shopId,
        mechanic = mechanicName(src),
        type = kind,
        label = step.label,
        items = historyItems(ctx.items),
        mileage = ctx.data and ctx.data.mileage or 0,
    })
    OpenServer.Log(src, "repair", ("%s - %s%s"):format(ctx.plate, step.label, stolen and (" (stolen parts, quality %d %%)"):format(quality) or ""), {
        kind = kind, key = key, quick = quick, items = ctx.items, shopId = ctx.shopId, stolen = stolen, quality = quality,
    })
    TriggerEvent("pls_mechanic:server:repair:done", src, ctx.plate, kind, key, netId)
    if stolen and kind ~= "body" then
        return true, locale("repair_step_done_stolen", step.label, quality)
    end
    return true, locale("repair_step_done", step.label)
end

--[[
  _  ___ _
 | |/ (_) |
 | ' / _| |_ ___
 |  < | | __/ __|
 | . \| | |_\__ \
 |_|\_\_|\__|___/
]]--

local function getKitType(kit)
    if kit.failedToCritical then return "patch" end
    if kit.engineHealth or kit.bodyHealth or kit.corePartsMin then return "repair" end
    return "clean"
end

-- Mechanic on duty, crew member inside his illegal workshop or one of kit.jobs
local function canUseMechanicKit(src, kit)
    local duty = Player(src).state.pls_mechanic_duty
    if duty and Shops.Get(duty) then return true end
    if not Config.RequireDuty and Shops.IsMechanic(src) then return true end
    if Shops.GetPlayerShopId(src) ~= nil then return true end
    local job = BRIDGE.GetPlayerJob(src)
    for _, name in ipairs(kit.jobs or {}) do
        if name == job then return true end
    end
    return false
end

local function isKitNeeded(entity, data, kit, kitType)
    if kitType == "clean" then
        return GetVehicleDirtLevel(entity) >= 1.0
    end
    if kitType == "patch" then
        if GetVehicleEngineHealth(entity) < (Config.PartStates.critical + 1) * 10.0 then return true end
        for _, value in pairs(data and data.core or {}) do
            if value <= Config.PartStates.critical then return true end
        end
        return false
    end
    if kit.engineHealth and GetVehicleEngineHealth(entity) < kit.engineHealth - 1.0 then return true end
    if kit.bodyHealth and GetVehicleBodyHealth(entity) < kit.bodyHealth - 1.0 then return true end
    if kit.corePartsMin then
        for _, value in pairs(data and data.core or {}) do
            if value < kit.corePartsMin then return true end
        end
    end
    return false
end

local function validateKit(src, netId, kitKey)
    local kit = type(kitKey) == "string" and Config.RepairKits[kitKey]
    if not kit then return false, locale("repair_invalid_step") end
    local itemName = Utils.Item(kitKey)
    if (BRIDGE.GetItemCount(src, itemName) or 0) < 1 then return false, locale("missing_items", itemLabel(itemName)) end
    if kit.mechanicOnly and not canUseMechanicKit(src, kit) then return false, locale("kit_mechanic_only") end
    local entity, entityError = getVehicleEntity(src, netId)
    if not entity then return false, locale(entityError) end
    local data = getVehicleData(entity)
    local kitType = getKitType(kit)
    if not isKitNeeded(entity, data, kit, kitType) then return false, locale("kit_not_needed") end
    return true, nil, {
        kit = kit,
        kitType = kitType,
        entity = entity,
        data = data,
        itemName = itemName,
        plate = data and data.plate or entityPlate(entity),
    }
end

local function completeKit(src, netId, kitKey)
    local pending = Pending[src]
    Pending[src] = nil
    if not pending or pending.netId ~= netId or pending.kind ~= "kit" or pending.key ~= kitKey then
        return false, locale("repair_not_started")
    end
    if GetGameTimer() - pending.time < pending.duration * DURATION_TOLERANCE then
        return false, locale("repair_too_fast")
    end
    local ok, message, ctx = validateKit(src, netId, kitKey)
    if not ok then return false, message end

    local kit, data = ctx.kit, ctx.data
    BRIDGE.RemoveItem(src, ctx.itemName, 1)
    if data and Vehicles and Vehicles.SetPart then
        local changes = {}
        for key, value in pairs(data.core or {}) do
            if ctx.kitType == "repair" and kit.corePartsMin and value < kit.corePartsMin then
                changes[key] = kit.corePartsMin
            elseif ctx.kitType == "patch" and value <= Config.PartStates.critical then
                changes[key] = Config.PartStates.critical + 1
            end
        end
        for key, value in pairs(changes) do
            Vehicles.SetPart(ctx.plate, "core", key, value)
        end
    end
    local label = itemLabel(ctx.itemName)
    if ctx.kitType ~= "clean" and data then
        -- current shop (History.Add skips illegal workshops)
        History.Add(ctx.plate, {
            shopId = Shops.GetPlayerShopId(src),
            mechanic = mechanicName(src),
            type = "kit",
            label = label,
            items = { { label = label, count = 1 } },
            mileage = data.mileage or 0,
        })
    end
    OpenServer.Log(src, "repair_kit", ("%s - %s"):format(ctx.plate, label), { kit = kitKey })
    return true, locale("kit_used", label)
end

--[[
   _____      _ _ _                _
  / ____|    | | | |              | |
 | |     __ _| | | |__   __ _  ___| | _____
 | |    / _` | | | '_ \ / _` |/ __| |/ / __|
 | |___| (_| | | | |_) | (_| | (__|   <\__ \
  \_____\__,_|_|_|_.__/ \__,_|\___|_|\_\___/
]]--

-- netId, vehicleClass (client, validated by Vehicles) -> { ok, data = VehicleData, findings } | { ok = false, message }
-- data.plate = plate shown on the vehicle (fake plate stays), findings = OBD codes of pls_mechanic_illegal
lib.callback.register("pls_mechanic:server:repair:diagnose", function(src, netId, vehicleClass)
    if not checkCooldown(src, "diagnose", 2000) then return { ok = false, message = locale("repair_too_fast") } end
    if not Shops.HasPermission(src, "diagnose") then return { ok = false, message = locale(permissionReason(src)) } end
    local scanner = Utils.Item("obd_scanner")
    if (BRIDGE.GetItemCount(src, scanner) or 0) < 1 then return { ok = false, message = locale("missing_tool", itemLabel(scanner)) } end
    local entity, entityError = getVehicleEntity(src, netId)
    if not entity then return { ok = false, message = locale(entityError) } end
    if not Vehicles or not Vehicles.GetByEntity then return { ok = false, message = locale("diag_failed") } end
    local data = Vehicles.GetByEntity(entity, tonumber(vehicleClass))
    if not data then return { ok = false, message = locale("vehicle_excluded") } end
    local _, _, visiblePlate = Vehicles.GetEntityPlate(entity)
    local report = {
        plate = visiblePlate or data.plate,
        model = data.model,
        class = data.class,
        mileage = data.mileage,
        ev = data.ev,
        service = data.service,
        core = data.core,
        origin = data.origin or {},
    }
    return { ok = true, data = report, findings = getDiagnosticFindings(data.plate) }
end)

-- Validates step (or kit when kind = "kit") and starts its timer
lib.callback.register("pls_mechanic:server:repair:begin", function(src, netId, kind, key, quick)
    if not checkCooldown(src, "begin", 300) then return { ok = false, message = locale("repair_too_fast") } end
    local ok, message, ctx
    if kind == "kit" then
        ok, message, ctx = validateKit(src, netId, key)
    else
        ok, message, ctx = validateStep(src, netId, kind, key, quick)
    end
    if not ok then
        Pending[src] = nil
        return { ok = false, message = message }
    end
    Pending[src] = {
        netId = netId,
        kind = kind,
        key = key,
        time = GetGameTimer(),
        duration = kind == "kit" and (ctx.kit.duration or 10000) or ctx.step.duration,
    }
    return { ok = true }
end)

lib.callback.register("pls_mechanic:server:repair:step", function(src, netId, kind, key, quick)
    local ok, message = completeStep(src, netId, kind, key, quick)
    return { ok = ok, message = message }
end)

lib.callback.register("pls_mechanic:server:repair:kit", function(src, netId, kitKey)
    local ok, message = completeKit(src, netId, kitKey)
    return { ok = ok, message = message }
end)

-- A repair step / kit of somebody is running on the vehicle ("begin" done, finish pending, abandoned ones expire)
function RepairServer.IsVehicleInRepair(entity)
    if not entity or entity == 0 then return false end
    local now = GetGameTimer()
    for _, pending in pairs(Pending) do
        local netId = tonumber(pending.netId)
        if netId and now - pending.time <= (pending.duration or 0) + 60000 and NetworkGetEntityFromNetworkId(netId) == entity then
            return true
        end
    end
    return false
end

-- Vehicle with plate near player (plate = real plate, trusted plates of the vehicles, fake plates resolved)
local function isPlateNear(src, plate, maxDistance)
    local pedCoords = GetEntityCoords(GetPlayerPed(src))
    for _, vehicle in ipairs(GetAllVehicles()) do
        if #(pedCoords - GetEntityCoords(vehicle)) <= maxDistance and entityPlate(vehicle) == plate then
            return true
        end
    end
    return false
end

-- plate -> { ok, data = { plate, mileage, entries } }
-- Mechanic with "diagnose" of a legal workshop can read any plate, others (crew of an illegal workshop too)
-- need the vehicle nearby, without "diagnose" also the service book.
-- The client sends the plate it sees, the book belongs to the real plate (response keeps the requested plate).
lib.callback.register("pls_mechanic:server:repair:history", function(src, plate)
    if not checkCooldown(src, "history", 1500) then return { ok = false, message = locale("repair_too_fast") } end
    local shownPlate = type(plate) == "string" and Utils.TrimPlate(plate) or nil
    if not shownPlate or shownPlate == "" or #shownPlate > 12 then return { ok = false, message = locale("no_vehicle") } end
    plate = resolvePlate(shownPlate)
    local canDiagnose, diagnoseShop = Shops.HasPermission(src, "diagnose")
    if canDiagnose and Shops.IsIllegal(diagnoseShop) then
        -- illegal workshops have no access to the registry, the vehicle has to stand next to the crew member
        if not isPlateNear(src, plate, BOOK_DISTANCE) then return { ok = false, message = locale("book_vehicle_far") } end
    elseif not canDiagnose then
        local book = Utils.Item("service_book")
        if (BRIDGE.GetItemCount(src, book) or 0) < 1 then return { ok = false, message = locale("missing_items", itemLabel(book)) } end
        if not isPlateNear(src, plate, BOOK_DISTANCE) then return { ok = false, message = locale("book_vehicle_far") } end
    end
    local entries = {}
    for _, row in ipairs(History.Get(plate, 100) or {}) do
        entries[#entries + 1] = {
            id = row.id,
            date = row.date,
            mileage = Utils.Round(row.mileage or 0, 1),
            shopName = row.shopName,
            mechanic = row.mechanic,
            type = row.type,
            label = row.label,
            items = row.items or {},
        }
    end
    local mileage = 0
    if Vehicles and Vehicles.GetByPlate then
        local data = Vehicles.GetByPlate(plate)
        mileage = data and data.mileage or 0
    end
    return { ok = true, data = { plate = shownPlate, mileage = Utils.Round(mileage, 1), entries = entries } }
end)

AddEventHandler("playerDropped", function()
    local src = source
    Pending[src] = nil
    Cooldowns[src] = nil
end)
