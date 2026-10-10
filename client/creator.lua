--[[
   _____                _
  / ____|              | |
 | |     _ __ ___  __ _| |_ ___  _ __
 | |    | '__/ _ \/ _` | __/ _ \| '__|
 | |____| | |  __/ (_| | || (_) | |
  \_____|_|  \___|\__,_|\__\___/|_|

 In-game workshop creator for admins (Config.AdminCommand).
 Every change is kept in a local draft until it's saved, server validates everything again.
 Illegal workshops (kind "illegal") are offered only while the DLC (Config.IllegalResource) is started:
 no jobs, blip or permission matrix, the owner (online player) is handed to the DLC crew.
]]--

Creator = {}

local Session = false       -- creator is open, world preview thread runs
local SessionId = 0         -- one preview thread per session
local Draft = nil           -- edited shop (local copy)
local Dirty = false         -- draft has unsaved changes
local Placing = false
local CurrentType = nil     -- point type submenu
local CurrentPoint = nil    -- edited point (highlighted in world)
local Menus = {}            -- context builders by id

local MENU_MAIN = "pls_mechanic_creator_main"
local MENU_SHOP = "pls_mechanic_creator_shop"
local MENU_BLIP = "pls_mechanic_creator_blip"
local MENU_POINTS = "pls_mechanic_creator_points"
local MENU_TYPE = "pls_mechanic_creator_type"
local MENU_POINT = "pls_mechanic_creator_point"

local PLACE_DISTANCE = 30.0
local DRAW_DISTANCE = 75.0
local TEXT_DISTANCE = 25.0
local RAY_FLAGS = 17        -- world + objects

-- Order of point types in the menu (other types from config follow alphabetically)
local TYPE_ORDER = { "duty", "boss", "storage", "computer", "workbench", "billing", "supply", "garage", "bay", "lift", "station" }

local TYPE_COLORS = {
    duty = { 52, 152, 219 },
    boss = { 155, 89, 182 },
    storage = { 230, 126, 34 },
    computer = { 26, 188, 156 },
    workbench = { 211, 84, 0 },
    billing = { 46, 204, 113 },
    supply = { 241, 196, 15 },
    garage = { 149, 165, 166 },
    bay = { 0, 168, 255 },
    lift = { 255, 99, 72 },
    station = { 236, 240, 241 },
}

-- Point types where a vehicle stands, footprint shows which way it faces
local VEHICLE_POINTS = { bay = true, lift = true, station = true, garage = true }

-- mouse wheel, weapon wheel, attack / aim / melee, E, arrows, backspace, pause
local PLACE_CONTROLS = { 14, 15, 16, 17, 24, 25, 37, 38, 51, 140, 141, 142, 172, 173, 174, 175, 194, 199, 200, 257, 263 }

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

local function trim(text)
    return (tostring(text or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function round(value, decimals)
    return Utils.Round(tonumber(value) or 0, decimals or 2)
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if value == math.floor(value) then
        return tostring(math.floor(value))
    end
    return tostring(round(value, 2))
end

local function normalizeHeading(heading)
    return (tonumber(heading) or 0.0) % 360.0
end

local function splitJobs(text)
    local jobs, seen = {}, {}
    for job in tostring(text or ""):gmatch("[^,;%s]+") do
        if not seen[job] and #jobs < 10 then
            seen[job] = true
            jobs[#jobs + 1] = job
        end
    end
    return jobs
end

local function jobsText(jobs)
    if not jobs or #jobs == 0 then
        return locale("creator_no_jobs")
    end
    return table.concat(jobs, ", ")
end

local function formatCoords(coords)
    return ("%.2f, %.2f, %.2f"):format(coords.x, coords.y, coords.z)
end

local function typeLabel(pointType)
    local data = Config.PointTypes[pointType]
    return data and data.label or tostring(pointType)
end

-- Point types of other resources can bring their own color { r, g, b }
local function typeColor(pointType)
    if TYPE_COLORS[pointType] then return TYPE_COLORS[pointType] end
    local color = Config.PointTypes[pointType] and Config.PointTypes[pointType].color
    if type(color) == "table" and tonumber(color[1]) and tonumber(color[2]) and tonumber(color[3]) then
        return { math.floor(Utils.Clamp(tonumber(color[1]), 0, 255)), math.floor(Utils.Clamp(tonumber(color[2]), 0, 255)), math.floor(Utils.Clamp(tonumber(color[3]), 0, 255)) }
    end
    return { 255, 255, 255 }
end

-- Illegal workshops can be created / edited only while the DLC runs
local function illegalAvailable()
    return GetResourceState(Config.IllegalResource) == "started"
end

local function isIllegal(shop)
    return shop ~= nil and shop.kind == "illegal"
end

local function kindLabel(kind)
    return locale(kind == "illegal" and "creator_kind_illegal" or "creator_kind_legal")
end

local function colorHex(color)
    return ("#%02x%02x%02x"):format(color[1], color[2], color[3])
end

-- Point types allowed for the workshop kind (Config.PointTypes[type].kinds)
local function getPointTypes(kind)
    local list, added, rest = {}, {}, {}
    for _, key in ipairs(TYPE_ORDER) do
        if Config.PointTypes[key] and ShopPoints.TypeAllowed(key, kind) then
            list[#list + 1] = key
            added[key] = true
        end
    end
    for key in pairs(Config.PointTypes) do
        if not added[key] and ShopPoints.TypeAllowed(key, kind) then
            rest[#rest + 1] = key
        end
    end
    table.sort(rest)
    for _, key in ipairs(rest) do
        list[#list + 1] = key
    end
    return list
end

local function getPointsOfType(pointType)
    local list = {}
    for _, point in ipairs(Draft and Draft.points or {}) do
        if point.type == pointType then
            list[#list + 1] = point
        end
    end
    return list
end

-- Order number of point among points of the same type
local function pointIndex(point)
    local index = 0
    for _, other in ipairs(Draft and Draft.points or {}) do
        if other.type == point.type then
            index = index + 1
        end
        if other == point then
            return index
        end
    end
    return index
end

local function pointRadius(point)
    local data = Config.PointTypes[point.type]
    return point.radius or (data and data.radius) or 1.5
end

local function defaultData(pointType)
    local data = {}
    for _, field in ipairs(Config.PointTypes[pointType].fields or {}) do
        data[field.key] = Utils.DeepCopy(field.default)
    end
    return data
end

local function optionLabel(field, value)
    for _, option in ipairs(field.options or {}) do
        if option.value == value then
            return option.label
        end
    end
    return tostring(value)
end

local function fieldsText(point)
    local parts = {}
    for _, field in ipairs(Config.PointTypes[point.type].fields or {}) do
        local value = point.data and point.data[field.key]
        local text
        if field.type == "checkbox" then
            text = value and locale("creator_yes") or locale("creator_no")
        elseif field.type == "select" then
            text = optionLabel(field, value)
        elseif field.type == "multi-select" then
            local labels = {}
            for _, v in ipairs(type(value) == "table" and value or {}) do
                labels[#labels + 1] = optionLabel(field, v)
            end
            text = #labels > 0 and table.concat(labels, ", ") or "-"
        elseif field.type == "number" then
            text = formatNumber(value)
        else
            text = (value and value ~= "") and tostring(value) or "-"
        end
        parts[#parts + 1] = field.label..": "..text
    end
    return table.concat(parts, " | ")
end

local function blipText(blip)
    return locale("creator_blip_summary",
        blip.enabled and locale("creator_on") or locale("creator_off"),
        blip.sprite, blip.color, formatNumber(blip.scale))
end

local function findShop(shops, shopId)
    for _, shop in ipairs(shops or {}) do
        if shop.id == shopId then
            return shop
        end
    end
    return nil
end

local function show(id)
    if not Menus[id] or Menus[id]() == false then return end
    lib.showContext(id)
end

--[[
  _____                     _
 |  __ \                   (_)
 | |  | |_ __ __ ___      ___ _ __   __ _
 | |  | | '__/ _` \ \ /\ / / | '_ \ / _` |
 | |__| | | | (_| |\ V  V /| | | | | (_| |
 |_____/|_|  \__,_| \_/\_/ |_|_| |_|\__, |
                                     __/ |
                                    |___/
]]--

local function drawText3D(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- GTA heading: 0 = north, grows counter clockwise
local function forwardVector(heading)
    local rad = math.rad(heading)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

local function drawLine(a, b, color, alpha)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, color[1], color[2], color[3], alpha or 255)
end

local function drawArrow(center, heading, length, color)
    local forward = forwardVector(heading)
    local right = vector3(forward.y, -forward.x, 0.0)
    local base = center + vector3(0.0, 0.0, 0.06)
    local tip = base + forward * length
    local head = math.min(0.6, length * 0.35)
    drawLine(base, tip, color)
    drawLine(tip, tip - forward * head + right * head * 0.6, color)
    drawLine(tip, tip - forward * head - right * head * 0.6, color)
end

-- Vehicle sized rectangle aligned with heading
local function drawFootprint(center, heading, color)
    local forward = forwardVector(heading)
    local right = vector3(forward.y, -forward.x, 0.0)
    local base = center + vector3(0.0, 0.0, 0.06)
    local length, width = 2.6, 1.15
    local corners = {
        base + forward * length + right * width,
        base + forward * length - right * width,
        base - forward * length - right * width,
        base - forward * length + right * width,
    }
    for i = 1, 4 do
        drawLine(corners[i], corners[i % 4 + 1], color, 210)
    end
end

-- center = vector3 on the ground / surface
local function drawPoint(pointType, center, heading, radius, highlight, label)
    local color = typeColor(pointType)
    local diameter = radius * 2.0
    DrawMarker(1, center.x, center.y, center.z - 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, diameter, diameter, 0.2, color[1], color[2], color[3], highlight and 100 or 45, false, false, 2, false, nil, nil, false)
    DrawMarker(25, center.x, center.y, center.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, diameter, diameter, 1.0, color[1], color[2], color[3], highlight and 255 or 170, false, false, 2, false, nil, nil, false)
    DrawMarker(0, center.x, center.y, center.z + 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, color[1], color[2], color[3], 210, highlight == true, false, 2, false, nil, nil, false)
    if VEHICLE_POINTS[pointType] then
        drawFootprint(center, heading, color)
    end
    drawArrow(center, heading, math.max(0.8, math.min(radius, 3.0)), color)
    if label then
        drawText3D(center + vector3(0.0, 0.0, 1.6), label)
    end
end

-- Draws all points of the edited shop while the creator is open
local function startSession()
    if Session then return end
    Session = true
    SessionId = SessionId + 1
    local id = SessionId
    CreateThread(function()
        while Session and SessionId == id do
            local sleep = 500
            if Draft then
                local pedCoords = GetEntityCoords(cache.ped)
                local counters = {}
                for _, point in ipairs(Draft.points) do
                    counters[point.type] = (counters[point.type] or 0) + 1
                    local center = Utils.Vec3(point.coords)
                    local distance = #(pedCoords - center)
                    if distance < DRAW_DISTANCE then
                        sleep = 0
                        local highlight = point == CurrentPoint
                        local label = nil
                        if highlight or distance < TEXT_DISTANCE then
                            label = locale("creator_world_label", typeLabel(point.type), counters[point.type], formatNumber(pointRadius(point)), formatNumber(round(point.heading, 1)))
                        end
                        drawPoint(point.type, center, point.heading or 0.0, pointRadius(point), highlight, label)
                    end
                end
                local blipCoords = Draft.blip and Draft.blip.coords
                if blipCoords then
                    local center = Utils.Vec3(blipCoords)
                    if #(pedCoords - center) < TEXT_DISTANCE then
                        sleep = 0
                        DrawMarker(0, center.x, center.y, center.z + 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4, 0.4, 255, 255, 255, 200, true, false, 2, false, nil, nil, false)
                        drawText3D(center + vector3(0.0, 0.0, 1.0), locale("creator_world_blip"))
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

--[[
  _____  _                                     _
 |  __ \| |                                   | |
 | |__) | | __ _  ___ ___ _ __ ___   ___ _ __ | |_
 |  ___/| |/ _` |/ __/ _ \ '_ ` _ \ / _ \ '_ \| __|
 | |    | | (_| | (_|  __/ | | | | |  __/ | | | |_
 |_|    |_|\__,_|\___\___|_| |_| |_|\___|_| |_|\__|
]]--

local function rotationToDirection(rotation)
    local x, z = math.rad(rotation.x), math.rad(rotation.z)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

-- Async probe from the rendering camera (works with noclip / scripted cameras too)
local function startProbe()
    local origin = GetFinalRenderedCamCoord()
    local destination = origin + rotationToDirection(GetFinalRenderedCamRot(2)) * PLACE_DISTANCE
    return StartShapeTestLosProbe(origin.x, origin.y, origin.z, destination.x, destination.y, destination.z, RAY_FLAGS, cache.ped, 4)
end

-- Placement mode. current = moved point or nil. Returns { coords, heading, radius } or nil when cancelled.
local function placePoint(pointType, current)
    local typeData = Config.PointTypes[pointType]
    local heading = current and current.heading or normalizeHeading(GetFinalRenderedCamRot(2).z)
    local radius = current and pointRadius(current) or typeData.radius or 1.5
    local target, probe, placed = nil, nil, nil

    Placing = true
    lib.showTextUI(locale("creator_place_help"), { position = "left-center", icon = "fa-solid fa-location-crosshairs" })
    while Placing do
        Wait(0)
        for _, control in ipairs(PLACE_CONTROLS) do
            DisableControlAction(0, control, true)
        end

        if not probe then
            probe = startProbe()
        end
        local status, hit, endCoords = GetShapeTestResult(probe)
        if status ~= 1 then
            probe = nil
            if status == 2 then
                target = (hit == true or hit == 1) and endCoords or nil
            end
        end

        local step = IsControlPressed(0, 21) and 1.0 or 5.0 -- shift = fine rotation
        if IsDisabledControlJustPressed(0, 15) then heading = normalizeHeading(heading + step) end
        if IsDisabledControlJustPressed(0, 14) then heading = normalizeHeading(heading - step) end
        if IsDisabledControlPressed(0, 174) then heading = normalizeHeading(heading + 90.0 * GetFrameTime()) end
        if IsDisabledControlPressed(0, 175) then heading = normalizeHeading(heading - 90.0 * GetFrameTime()) end
        if IsDisabledControlJustPressed(0, 172) then radius = math.min(15.0, radius + 0.25) end
        if IsDisabledControlJustPressed(0, 173) then radius = math.max(0.5, radius - 0.25) end

        if target then
            drawPoint(pointType, target, heading, radius, true, locale("creator_place_label", typeLabel(pointType), formatNumber(radius), formatNumber(round(heading, 1))))
            if IsDisabledControlJustPressed(0, 38) then
                placed = { coords = Utils.Coords(target), heading = round(heading, 1), radius = round(radius, 2) }
                Placing = false
            end
        end

        if IsDisabledControlJustPressed(0, 194) or IsDisabledControlJustPressed(0, 200) then
            Placing = false
        end
    end
    lib.hideTextUI()
    return placed
end

--[[
  _____        _       _
 |  __ \      (_)     | |
 | |__) |__  _ _ __ | |_ ___
 |  ___/ _ \| | '_ \| __/ __|
 | |  | (_) | | | | | |_\__ \
 |_|   \___/|_|_| |_|\__|___/
]]--

local function isInteger(value)
    return value == nil or (tonumber(value) and value == math.floor(value))
end

-- Edits Config.PointTypes[type].fields of point. Returns true when changed.
local function editFields(point)
    local fields = Config.PointTypes[point.type].fields or {}
    if #fields == 0 then return false end
    point.data = point.data or {}
    local rows = {}
    for _, field in ipairs(fields) do
        local value = point.data[field.key]
        if value == nil then
            value = Utils.DeepCopy(field.default)
        end
        if field.type == "number" then
            local decimal = not (isInteger(field.default) and isInteger(field.min) and isInteger(field.max))
            rows[#rows + 1] = { type = "number", label = field.label, default = tonumber(value), min = field.min, max = field.max, step = decimal and 0.1 or 1, precision = decimal and 2 or 0, required = true }
        elseif field.type == "checkbox" then
            rows[#rows + 1] = { type = "checkbox", label = field.label, checked = value == true }
        elseif field.type == "select" then
            rows[#rows + 1] = { type = "select", label = field.label, options = Utils.DeepCopy(field.options or {}), default = value, required = true }
        elseif field.type == "multi-select" then
            rows[#rows + 1] = { type = "multi-select", label = field.label, options = Utils.DeepCopy(field.options or {}), default = type(value) == "table" and value or {} }
        else
            rows[#rows + 1] = { type = "input", label = field.label, default = value ~= nil and tostring(value) or "" }
        end
    end

    local input = lib.inputDialog(locale("creator_point_fields_title", typeLabel(point.type)), rows)
    if not input then return false end

    for index, field in ipairs(fields) do
        local value = input[index]
        if field.type == "number" then
            value = tonumber(value) or field.default
            if field.min then value = math.max(value, field.min) end
            if field.max then value = math.min(value, field.max) end
        elseif field.type == "checkbox" then
            value = value == true
        elseif field.type == "multi-select" then
            value = type(value) == "table" and value or {}
        elseif field.type == "select" then
            if value == nil then value = field.default end
        else
            value = trim(value)
        end
        point.data[field.key] = value
    end
    Dirty = true
    return true
end

local function addPoint()
    local pointType = CurrentType
    local typeData = pointType and Config.PointTypes[pointType]
    if not Draft or not typeData then return end
    if typeData.multiple == false and #getPointsOfType(pointType) > 0 then
        Core.Notify(locale("creator_point_single"), "error")
        return show(MENU_TYPE)
    end
    local placed = placePoint(pointType)
    if not Session or not Draft then return end
    if not placed then
        return show(MENU_TYPE)
    end
    local point = {
        type = pointType,
        coords = placed.coords,
        heading = placed.heading,
        radius = placed.radius,
        data = defaultData(pointType),
    }
    table.insert(Draft.points, point)
    Dirty = true
    CurrentPoint = point
    editFields(point)
    Core.Notify(locale("creator_point_added", typeLabel(pointType)), "success")
    show(MENU_POINT)
end

local function movePoint(point)
    local placed = placePoint(point.type, point)
    if not Session or not Draft then return end
    if placed then
        point.coords = placed.coords
        point.heading = placed.heading
        point.radius = placed.radius
        Dirty = true
        Core.Notify(locale("creator_point_moved"), "success")
    end
    show(MENU_POINT)
end

local function editRadius(point)
    local input = lib.inputDialog(locale("creator_point_radius"), {
        { type = "number", label = locale("creator_radius"), default = pointRadius(point), min = 0.5, max = 15.0, step = 0.25, precision = 2, required = true },
        { type = "number", label = locale("creator_heading"), default = round(point.heading, 1), min = 0, max = 360, step = 1, precision = 1, required = true },
    })
    if input then
        point.radius = round(Utils.Clamp(tonumber(input[1]) or pointRadius(point), 0.5, 15.0), 2)
        point.heading = round(normalizeHeading(tonumber(input[2]) or point.heading), 1)
        Dirty = true
    end
    show(MENU_POINT)
end

local function deletePoint(point)
    local answer = lib.alertDialog({
        header = locale("creator_point_delete"),
        content = locale("creator_point_delete_confirm", typeLabel(point.type), pointIndex(point)),
        centered = true,
        cancel = true,
    })
    if answer ~= "confirm" then
        return show(MENU_POINT)
    end
    for index, other in ipairs(Draft.points) do
        if other == point then
            table.remove(Draft.points, index)
            break
        end
    end
    CurrentPoint = nil
    Dirty = true
    show(MENU_TYPE)
end

local function teleportTo(point)
    local coords = point.coords
    RequestCollisionAtCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    SetPedCoordsKeepVehicle(cache.ped, coords.x + 0.0, coords.y + 0.0, coords.z + 1.0)
    local endTime = GetGameTimer() + 2000
    while not HasCollisionLoadedAroundEntity(cache.ped) and GetGameTimer() < endTime do
        Wait(0)
    end
end

--[[
   _____ _
  / ____| |
 | (___ | |__   ___  _ __
  \___ \| '_ \ / _ \| '_ \
  ____) | | | | (_) | |_) |
 |_____/|_| |_|\___/| .__/
                    | |
                    |_|
]]--

local function leaveDraft(nextStep)
    if Draft and Dirty then
        local answer = lib.alertDialog({
            header = locale("creator_discard_title"),
            content = locale("creator_discard_text"),
            centered = true,
            cancel = true,
            labels = { confirm = locale("creator_discard_confirm") },
        })
        if answer ~= "confirm" then
            return show(MENU_SHOP)
        end
    end
    Draft, Dirty, CurrentType, CurrentPoint = nil, false, nil, nil
    nextStep()
end

-- ESC in any creator menu. Deferred: ox_lib hides the context after onExit returns.
local function onMenuExit()
    CreateThread(function()
        Wait(0)
        leaveDraft(Creator.Close)
    end)
end

-- Owner of illegal workshop (server id of an online player), nil = keep / none
local function ownerRow(default)
    return { type = "number", label = locale("creator_owner"), description = locale("creator_owner_desc"), default = default, min = 1, precision = 0 }
end

-- kind = "legal" / "illegal"
local function createShop(kind)
    local illegal = kind == "illegal"
    if illegal and not illegalAvailable() then
        Core.Notify(locale("creator_illegal_unavailable", Config.IllegalResource), "error")
        return show(MENU_MAIN)
    end
    local rows = { { type = "input", label = locale("creator_name"), required = true, min = 1, max = 100 } }
    if illegal then
        rows[2] = ownerRow()
    else
        rows[2] = { type = "input", label = locale("creator_jobs"), description = locale("creator_jobs_desc"), placeholder = locale("creator_jobs_placeholder") }
    end
    local input = lib.inputDialog(locale(illegal and "creator_create_illegal" or "creator_create"), rows)
    if not input then
        return show(MENU_MAIN)
    end
    startSession()
    local blip = Utils.DeepCopy(Config.DefaultBlip)
    if illegal then blip.enabled = false end
    Draft = {
        name = trim(input[1]),
        kind = illegal and "illegal" or "legal",
        jobs = illegal and {} or splitJobs(input[2]),
        owner = illegal and tonumber(input[2]) or nil,
        blip = blip,
        points = {},
    }
    Dirty = true
    show(MENU_SHOP)
end

local function editShop(shop)
    startSession()
    Draft = Utils.DeepCopy(shop)
    Draft.kind = Draft.kind == "illegal" and "illegal" or "legal"
    Draft.points = Draft.points or {}
    Draft.jobs = Draft.jobs or {}
    Draft.blip = Draft.blip or Utils.DeepCopy(Config.DefaultBlip)
    Dirty = false
    show(MENU_SHOP)
end

-- Changes kind of the draft, points not allowed for the new kind are removed (after confirmation)
local function editKind()
    if not illegalAvailable() then
        Core.Notify(locale("creator_illegal_unavailable", Config.IllegalResource), "error")
        return show(MENU_SHOP)
    end
    local input = lib.inputDialog(locale("creator_kind"), {
        { type = "select", label = locale("creator_kind"), default = Draft.kind, required = true, options = {
            { value = "legal", label = locale("creator_kind_legal") },
            { value = "illegal", label = locale("creator_kind_illegal") },
        } },
    })
    local kind = input and input[1]
    if kind ~= "legal" and kind ~= "illegal" or kind == Draft.kind then
        return show(MENU_SHOP)
    end
    local removed = 0
    for _, point in ipairs(Draft.points) do
        if not ShopPoints.TypeAllowed(point.type, kind) then
            removed = removed + 1
        end
    end
    local answer = lib.alertDialog({
        header = locale("creator_kind"),
        content = locale(kind == "illegal" and "creator_kind_to_illegal" or "creator_kind_to_legal", removed),
        centered = true,
        cancel = true,
    })
    if answer ~= "confirm" then
        return show(MENU_SHOP)
    end
    for i = #Draft.points, 1, -1 do
        if not ShopPoints.TypeAllowed(Draft.points[i].type, kind) then
            table.remove(Draft.points, i)
        end
    end
    Draft.kind = kind
    if kind == "illegal" then
        Draft.jobs = {}
        Draft.blip.enabled = false
    else
        Draft.owner = nil
    end
    CurrentType, CurrentPoint = nil, nil
    Dirty = true
    Core.Notify(locale("creator_kind_changed", kindLabel(kind)), "success")
    show(MENU_SHOP)
end

-- New / unsaved workshop: owner is sent with the save. Saved workshop: owner is set right away (DLC SetShopOwner).
local function editOwner()
    local input = lib.inputDialog(locale("creator_owner_set"), { ownerRow(Draft.owner) })
    local owner = input and tonumber(input[1])
    if not owner then
        return show(MENU_SHOP)
    end
    if not Draft.id or Dirty then
        Draft.owner = owner
        Dirty = true
        return show(MENU_SHOP)
    end
    local response = lib.callback.await("pls_mechanic:server:creator:setOwner", false, Draft.id, owner)
    Core.Notify(response and response.message or locale("creator_owner_failed"), response and response.ok and "success" or "error")
    show(MENU_SHOP)
end

local function editName()
    local input = lib.inputDialog(locale("creator_name"), {
        { type = "input", label = locale("creator_name"), default = Draft.name, required = true, min = 1, max = 100 },
    })
    if input then
        local name = trim(input[1])
        if name ~= "" and name ~= Draft.name then
            Draft.name = name
            Dirty = true
        end
    end
    show(MENU_SHOP)
end

local function editJobs()
    local input = lib.inputDialog(locale("creator_jobs"), {
        { type = "input", label = locale("creator_jobs"), description = locale("creator_jobs_desc"), placeholder = locale("creator_jobs_placeholder"), default = table.concat(Draft.jobs, ", ") },
    })
    if input then
        local jobs = splitJobs(input[1])
        if table.concat(jobs, ",") ~= table.concat(Draft.jobs, ",") then
            Draft.jobs = jobs
            Dirty = true
        end
    end
    show(MENU_SHOP)
end

local function editBlip()
    local blip = Draft.blip
    local input = lib.inputDialog(locale("creator_blip_edit"), {
        { type = "checkbox", label = locale("creator_blip_enabled"), checked = blip.enabled == true },
        { type = "number", label = locale("creator_blip_sprite"), description = locale("creator_blip_sprite_desc"), default = blip.sprite, min = 1, max = 999, precision = 0, required = true },
        { type = "number", label = locale("creator_blip_color"), default = blip.color, min = 0, max = 85, precision = 0, required = true },
        { type = "number", label = locale("creator_blip_scale"), default = blip.scale, min = 0.1, max = 3.0, step = 0.1, precision = 2, required = true },
    })
    if input then
        blip.enabled = input[1] == true
        blip.sprite = math.floor(Utils.Clamp(tonumber(input[2]) or blip.sprite, 1, 999))
        blip.color = math.floor(Utils.Clamp(tonumber(input[3]) or blip.color, 0, 85))
        blip.scale = round(Utils.Clamp(tonumber(input[4]) or blip.scale, 0.1, 3.0), 2)
        Dirty = true
    end
    show(MENU_BLIP)
end

local function saveDraft()
    if trim(Draft.name) == "" then
        Core.Notify(locale("creator_invalid_name"), "error")
        return show(MENU_SHOP)
    end
    local payload = {
        id = Draft.id,
        name = Draft.name,
        kind = Draft.kind,
        owner = isIllegal(Draft) and Draft.owner or nil,
        jobs = Draft.jobs,
        blip = Draft.blip,
        points = Draft.points,
    }
    local response = lib.callback.await("pls_mechanic:server:creator:save", false, payload)
    if not response or not response.ok then
        Core.Notify(response and response.message or locale("creator_save_failed"), "error")
        return show(MENU_SHOP)
    end
    Core.Notify(response.message or locale("creator_saved"), "success")
    -- reload saved version (server generated point ids, sanitized values)
    local shops = lib.callback.await("pls_mechanic:server:creator:getShops", false)
    local saved = findShop(shops, response.id)
    if saved then
        Draft = Utils.DeepCopy(saved)
        Draft.kind = Draft.kind == "illegal" and "illegal" or "legal"
        Draft.points = Draft.points or {}
        Draft.jobs = Draft.jobs or {}
        Draft.blip = Draft.blip or Utils.DeepCopy(Config.DefaultBlip)
    else
        Draft.id = response.id
        Draft.owner = nil
    end
    Dirty = false
    CurrentPoint = nil
    show(MENU_SHOP)
end

local function deleteShop()
    local answer = lib.alertDialog({
        header = locale("creator_delete"),
        content = locale("creator_delete_confirm", Draft.name),
        centered = true,
        cancel = true,
    })
    if answer ~= "confirm" then
        return show(MENU_SHOP)
    end
    local response = lib.callback.await("pls_mechanic:server:creator:delete", false, Draft.id)
    if not response or not response.ok then
        Core.Notify(response and response.message or locale("creator_save_failed"), "error")
        return show(MENU_SHOP)
    end
    Core.Notify(response.message, "success")
    Draft, Dirty, CurrentType, CurrentPoint = nil, false, nil, nil
    show(MENU_MAIN)
end

local function resetPermissions()
    local answer = lib.alertDialog({
        header = locale("creator_reset_permissions"),
        content = locale("creator_reset_permissions_confirm"),
        centered = true,
        cancel = true,
    })
    if answer == "confirm" then
        local response = lib.callback.await("pls_mechanic:server:creator:resetPermissions", false, Draft.id)
        Core.Notify(response and response.message or locale("creator_save_failed"), response and response.ok and "success" or "error")
    end
    show(MENU_SHOP)
end

-- Boss settings NUI of the edited shop, creator menu comes back when it's closed
local function openSettings()
    if not (Settings and Settings.Open) then
        return show(MENU_SHOP)
    end
    local shopId = Draft.id
    Settings.Open(shopId)
    if not Core.Nui.IsOpen("settings") then
        return show(MENU_SHOP)
    end
    CreateThread(function()
        while Core.Nui.IsOpen("settings") do
            Wait(250)
        end
        if Session and Draft and Draft.id == shopId and not Placing then
            show(MENU_SHOP)
        end
    end)
end

--[[
  __  __
 |  \/  |
 | \  / | ___ _ __  _   _ ___
 | |\/| |/ _ \ '_ \| | | / __|
 | |  | |  __/ | | | |_| \__ \
 |_|  |_|\___|_| |_|\__,_|___/
]]--

Menus[MENU_MAIN] = function()
    local shops = lib.callback.await("pls_mechanic:server:creator:getShops", false)
    if not shops then
        Core.Notify(locale("no_permission"), "error")
        Creator.Close()
        return false
    end
    Draft, Dirty, CurrentType, CurrentPoint = nil, false, nil, nil
    startSession()

    local options = {
        {
            title = locale("creator_create"),
            description = locale("creator_create_desc"),
            icon = "fa-solid fa-plus",
            onSelect = function()
                createShop("legal")
            end,
        },
    }
    if illegalAvailable() then
        options[#options + 1] = {
            title = locale("creator_create_illegal"),
            description = locale("creator_create_illegal_desc"),
            icon = "fa-solid fa-user-secret",
            onSelect = function()
                createShop("illegal")
            end,
        }
    end
    for _, shop in ipairs(shops) do
        local description = locale("creator_shop_desc", jobsText(shop.jobs), #(shop.points or {}))
        if isIllegal(shop) then
            description = locale("creator_illegal_shop_desc", #(shop.points or {}))
        end
        options[#options + 1] = {
            title = ("#%s %s"):format(shop.id, shop.name),
            description = description,
            icon = isIllegal(shop) and "fa-solid fa-user-secret" or "fa-solid fa-warehouse",
            arrow = true,
            onSelect = function()
                editShop(shop)
            end,
        }
    end
    if #shops == 0 then
        options[#options + 1] = {
            title = locale("creator_no_shops"),
            icon = "fa-solid fa-circle-info",
            disabled = true,
        }
    end
    lib.registerContext({
        id = MENU_MAIN,
        title = locale("creator_title"),
        options = options,
        onExit = function()
            Creator.Close()
        end,
    })
end

Menus[MENU_SHOP] = function()
    if not Draft then
        show(MENU_MAIN)
        return false
    end
    local isNew = Draft.id == nil
    local illegal = isIllegal(Draft)
    local options = {
        {
            title = locale("creator_name"),
            description = Draft.name ~= "" and Draft.name or "-",
            icon = "fa-solid fa-signature",
            onSelect = editName,
        },
    }
    -- kind is offered only while the DLC runs, an illegal workshop shows it always
    if illegal or illegalAvailable() then
        options[#options + 1] = {
            title = locale("creator_kind"),
            description = illegalAvailable() and kindLabel(Draft.kind) or locale("creator_illegal_unavailable", Config.IllegalResource),
            icon = illegal and "fa-solid fa-user-secret" or "fa-solid fa-scale-balanced",
            disabled = not illegalAvailable(),
            onSelect = editKind,
        }
    end
    if illegal then
        options[#options + 1] = {
            title = locale("creator_owner_set"),
            description = Draft.owner and locale("creator_owner_pending", Draft.owner) or locale("creator_owner_set_desc"),
            icon = "fa-solid fa-user-lock",
            disabled = not illegalAvailable(),
            onSelect = editOwner,
        }
    else
        options[#options + 1] = {
            title = locale("creator_jobs"),
            description = jobsText(Draft.jobs),
            icon = "fa-solid fa-user-tie",
            onSelect = editJobs,
        }
        options[#options + 1] = {
            title = locale("creator_blip"),
            description = blipText(Draft.blip),
            icon = "fa-solid fa-location-dot",
            arrow = true,
            onSelect = function()
                show(MENU_BLIP)
            end,
        }
    end
    options[#options + 1] = {
        title = locale("creator_points"),
        description = locale("creator_points_desc", #Draft.points),
        icon = "fa-solid fa-map-pin",
        arrow = true,
        onSelect = function()
            show(MENU_POINTS)
        end,
    }
    -- illegal workshops: no permission matrix / prices (the crew decides)
    if not isNew and not illegal then
        options[#options + 1] = {
            title = locale("creator_settings"),
            description = Dirty and locale("creator_save_first") or locale("creator_settings_desc"),
            icon = "fa-solid fa-sliders",
            disabled = Dirty,
            onSelect = openSettings,
        }
        options[#options + 1] = {
            title = locale("creator_reset_permissions"),
            description = Dirty and locale("creator_save_first") or locale("creator_reset_permissions_desc"),
            icon = "fa-solid fa-user-shield",
            disabled = Dirty,
            onSelect = resetPermissions,
        }
    end
    options[#options + 1] = {
        title = locale("creator_save"),
        description = Dirty and locale("creator_unsaved") or locale("creator_no_changes"),
        icon = "fa-solid fa-floppy-disk",
        iconColor = Dirty and "#2ecc71" or nil,
        onSelect = saveDraft,
    }
    if not isNew then
        options[#options + 1] = {
            title = locale("creator_delete"),
            description = locale("creator_delete_desc"),
            icon = "fa-solid fa-trash",
            iconColor = "#e74c3c",
            onSelect = deleteShop,
        }
    end
    options[#options + 1] = {
        title = locale("creator_back"),
        description = locale("creator_back_desc"),
        icon = "fa-solid fa-arrow-left",
        onSelect = function()
            leaveDraft(function()
                show(MENU_MAIN)
            end)
        end,
    }

    local title = Draft.name ~= "" and Draft.name or locale("creator_new_shop")
    if Draft.id then title = ("#%s %s"):format(Draft.id, title) end
    if Dirty then title = title.." *" end
    lib.registerContext({
        id = MENU_SHOP,
        title = title,
        options = options,
        onExit = onMenuExit,
    })
end

Menus[MENU_BLIP] = function()
    local blip = Draft.blip
    lib.registerContext({
        id = MENU_BLIP,
        title = locale("creator_blip"),
        menu = MENU_SHOP,
        onBack = function() Menus[MENU_SHOP]() end,
        onExit = onMenuExit,
        options = {
            {
                title = locale("creator_blip_edit"),
                description = blipText(blip),
                icon = "fa-solid fa-pen",
                onSelect = editBlip,
            },
            {
                title = locale("creator_blip_here"),
                description = blip.coords and formatCoords(blip.coords) or locale("creator_blip_auto"),
                icon = "fa-solid fa-crosshairs",
                onSelect = function()
                    blip.coords = Utils.Coords(GetEntityCoords(cache.ped))
                    Dirty = true
                    Core.Notify(locale("creator_blip_set"), "success")
                    show(MENU_BLIP)
                end,
            },
            {
                title = locale("creator_blip_reset"),
                description = locale("creator_blip_reset_desc"),
                icon = "fa-solid fa-rotate-left",
                disabled = blip.coords == nil,
                onSelect = function()
                    blip.coords = nil
                    Dirty = true
                    show(MENU_BLIP)
                end,
            },
        },
    })
end

Menus[MENU_POINTS] = function()
    local options = {}
    for _, pointType in ipairs(getPointTypes(Draft and Draft.kind)) do
        local typeData = Config.PointTypes[pointType]
        local count = #getPointsOfType(pointType)
        local description
        if count == 0 then
            description = locale("creator_type_empty")
        elseif typeData.multiple == false then
            description = locale("creator_type_placed")
        else
            description = locale("creator_type_count", count)
        end
        options[#options + 1] = {
            title = typeData.label,
            description = description,
            icon = typeData.icon,
            iconColor = colorHex(typeColor(pointType)),
            arrow = true,
            onSelect = function()
                CurrentType = pointType
                show(MENU_TYPE)
            end,
        }
    end
    lib.registerContext({
        id = MENU_POINTS,
        title = locale("creator_points"),
        menu = MENU_SHOP,
        onBack = function() Menus[MENU_SHOP]() end,
        onExit = onMenuExit,
        options = options,
    })
end

Menus[MENU_TYPE] = function()
    local typeData = CurrentType and Config.PointTypes[CurrentType]
    if not Draft or not typeData then
        show(MENU_POINTS)
        return false
    end
    CurrentPoint = nil
    local points = getPointsOfType(CurrentType)
    local canAdd = typeData.multiple ~= false or #points == 0
    local pedCoords = GetEntityCoords(cache.ped)
    local color = colorHex(typeColor(CurrentType))
    local options = {
        {
            title = locale("creator_point_add"),
            description = canAdd and locale("creator_point_add_desc") or locale("creator_point_single"),
            icon = "fa-solid fa-plus",
            disabled = not canAdd,
            onSelect = addPoint,
        },
    }
    for index, point in ipairs(points) do
        options[#options + 1] = {
            title = locale("creator_point_title", typeData.label, index),
            description = locale("creator_point_desc", formatNumber(round(#(pedCoords - Utils.Vec3(point.coords)), 1)), formatNumber(pointRadius(point)), formatNumber(round(point.heading, 1))),
            icon = typeData.icon,
            iconColor = color,
            arrow = true,
            onSelect = function()
                CurrentPoint = point
                show(MENU_POINT)
            end,
        }
    end
    lib.registerContext({
        id = MENU_TYPE,
        title = typeData.label,
        menu = MENU_POINTS,
        onBack = function() Menus[MENU_POINTS]() end,
        onExit = onMenuExit,
        options = options,
    })
end

Menus[MENU_POINT] = function()
    local point = CurrentPoint
    if not Draft or not point then
        show(MENU_TYPE)
        return false
    end
    local typeData = Config.PointTypes[point.type]
    local options = {
        {
            title = locale("creator_point_teleport"),
            description = formatCoords(point.coords),
            icon = "fa-solid fa-person-walking-arrow-right",
            onSelect = function()
                teleportTo(point)
                show(MENU_POINT)
            end,
        },
        {
            title = locale("creator_point_move"),
            description = locale("creator_point_move_desc"),
            icon = "fa-solid fa-up-down-left-right",
            onSelect = function()
                movePoint(point)
            end,
        },
        {
            title = locale("creator_point_radius"),
            description = locale("creator_point_radius_desc", formatNumber(pointRadius(point)), formatNumber(round(point.heading, 1))),
            icon = "fa-solid fa-circle-dot",
            onSelect = function()
                editRadius(point)
            end,
        },
    }
    if typeData.fields and #typeData.fields > 0 then
        options[#options + 1] = {
            title = locale("creator_point_fields"),
            description = fieldsText(point),
            icon = "fa-solid fa-sliders",
            onSelect = function()
                editFields(point)
                show(MENU_POINT)
            end,
        }
    end
    options[#options + 1] = {
        title = locale("creator_point_delete"),
        icon = "fa-solid fa-trash",
        iconColor = "#e74c3c",
        onSelect = function()
            deletePoint(point)
        end,
    }
    lib.registerContext({
        id = MENU_POINT,
        title = locale("creator_point_title", typeData.label, pointIndex(point)),
        menu = MENU_TYPE,
        onBack = function() Menus[MENU_TYPE]() end,
        onExit = onMenuExit,
        options = options,
    })
end

--[[
                 _____ _____
     /\         |  __ \_   _|
    /  \   _ __ | |__) || |
   / /\ \ | '_ \|  ___/ | |
  / ____ \| |_) | |    _| |_
 /_/    \_\ .__/|_|   |_____|
          | |
          |_|
]]--

-- Opens creator (resumes the edited shop when there is one)
function Creator.Open()
    if Placing then return end
    if Session and Draft then
        show(MENU_SHOP)
        return
    end
    show(MENU_MAIN)
end

-- Closes creator and drops unsaved draft
function Creator.Close()
    Session = false
    Placing = false
    Draft, Dirty, CurrentType, CurrentPoint = nil, false, nil, nil
end

function Creator.IsOpen()
    return Session
end

RegisterNetEvent("pls_mechanic:client:creator:open", function()
    Creator.Open()
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Placing then
        lib.hideTextUI()
    end
    local openMenu = lib.getOpenContextMenu and lib.getOpenContextMenu()
    if openMenu and openMenu:find("pls_mechanic_creator", 1, true) then
        lib.hideContext(false)
    end
    Session = false
    Placing = false
end)
