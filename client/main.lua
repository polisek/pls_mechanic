lib.locale()

--[[
   _____
  / ____|
 | |     ___  _ __ ___
 | |    / _ \| '__/ _ \
 | |___| (_) | | |  __/
  \_____\___/|_|  \___|

 Shared client API for all modules:
 Core        - shops from GlobalState + private illegal workshops, permissions, helpers
 Core.Nui    - NUI views
 ShopPoints  - registry of point types / actions for workshop points (client/shops.lua builds targets from it)
]]--

Core = {}
Core.Shops = GlobalState.pls_mechanic_shops or {}

local ShopListeners = {}
local LegalShops = Core.Shops   -- GlobalState list
local PrivateShops = {}         -- illegal workshops sent only to their crew (and admins)
local PrivatePerms = {}         -- [shopId] = crew perms { [perm] = true }
local IllegalCache = { time = 0, id = nil }

local ILLEGAL_CACHE_MS = 500

--[[
   _____ _
  / ____| |
 | (___ | |__   ___  _ __  ___
  \___ \| '_ \ / _ \| '_ \/ __|
  ____) | | | | (_) | |_) \__ \
 |_____/|_| |_|\___/| .__/|___/
                    | |
                    |_|
]]--

-- fn(shops) is called now and every time shops change (creator / boss settings / crew access)
function Core.OnShopsUpdated(fn)
    table.insert(ShopListeners, fn)
    CreateThread(function()
        local ok, err = pcall(fn, Core.Shops)
        if not ok then print("[pls_mechanic] OnShopsUpdated error: "..tostring(err)) end
    end)
end

-- Core.Shops = legal workshops (GlobalState) + illegal workshops of my crew
local function updateShops()
    local list = {}
    for _, shop in pairs(LegalShops) do
        list[#list + 1] = shop
    end
    for _, shop in pairs(PrivateShops) do
        list[#list + 1] = shop
    end
    Core.Shops = list
    IllegalCache.time = 0
    for _, fn in pairs(ShopListeners) do
        CreateThread(function()
            local ok, err = pcall(fn, Core.Shops)
            if not ok then print("[pls_mechanic] OnShopsUpdated error: "..tostring(err)) end
        end)
    end
end

AddStateBagChangeHandler("pls_mechanic_shops", "global", function(_, _, value)
    LegalShops = value or {}
    updateShops()
end)

-- payload = { shops = { illegal shops }, perms = { [shopId] = perms } } from the server
local function setPrivate(payload)
    if type(payload) ~= "table" then return end
    PrivateShops, PrivatePerms = {}, {}
    for _, shop in pairs(type(payload.shops) == "table" and payload.shops or {}) do
        if type(shop) == "table" and shop.id then
            PrivateShops[#PrivateShops + 1] = shop
        end
    end
    for shopId, perms in pairs(type(payload.perms) == "table" and payload.perms or {}) do
        if tonumber(shopId) and type(perms) == "table" then
            PrivatePerms[tonumber(shopId)] = perms
        end
    end
    updateShops()
end

RegisterNetEvent("pls_mechanic:client:shops:private", setPrivate)

-- Initial illegal workshops (the server push during the resource start could come before this script)
CreateThread(function()
    setPrivate(lib.callback.await("pls_mechanic:server:shops:private", false))
end)

function Core.GetShop(shopId)
    shopId = tonumber(shopId)
    for _, shop in pairs(Core.Shops) do
        if shop.id == shopId then
            return shop
        end
    end
    return nil
end

function Core.IsIllegalShop(shopId)
    local shop = Core.GetShop(shopId)
    return shop ~= nil and shop.kind == "illegal"
end

-- I have crew access to at least one illegal workshop
function Core.HasIllegalAccess()
    return next(PrivatePerms) ~= nil
end

-- Distance from coords to the closest point of shop (nil = no points)
local function distanceToShop(shop, coords)
    local closest = nil
    for _, point in pairs(shop.points or {}) do
        if point.coords then
            local distance = #(coords - Utils.Vec3(point.coords))
            if not closest or distance < closest then
                closest = distance
            end
        end
    end
    return closest
end

-- Illegal workshop I stand in (Config.IllegalShopRadius from any of its points) and have crew access to, or nil
function Core.GetIllegalShopId()
    if not next(PrivatePerms) then return nil end
    local now = GetGameTimer()
    if now - IllegalCache.time < ILLEGAL_CACHE_MS then
        return IllegalCache.id
    end
    local coords = GetEntityCoords(cache.ped)
    local best, bestDistance = nil, nil
    for _, shop in pairs(PrivateShops) do
        if PrivatePerms[shop.id] then
            local distance = distanceToShop(shop, coords)
            if distance and distance <= Config.IllegalShopRadius and (not bestDistance or distance < bestDistance) then
                best, bestDistance = shop.id, distance
            end
        end
    end
    IllegalCache.time, IllegalCache.id = now, best
    return best
end

function Core.GetJob()
    return BRIDGE.GetPlayerJob(), BRIDGE.GetPlayerGrade()
end

-- Shops of player's job
function Core.GetMyShops()
    local job = BRIDGE.GetPlayerJob()
    local result = {}
    for _, shop in pairs(Core.Shops) do
        if Utils.ShopHasJob(shop, job) then
            table.insert(result, shop)
        end
    end
    return result
end

function Core.IsMechanic()
    return #Core.GetMyShops() > 0
end

function Core.GetDutyShopId()
    return LocalPlayer.state.pls_mechanic_duty or nil
end

function Core.IsOnDuty()
    return Core.GetDutyShopId() ~= nil
end

-- Current shop: the illegal workshop I stand in and have crew access to (a legal mechanic in a crew works for
-- the crew there), otherwise duty shop (or first shop of job when duty is not required). Same rule as server Shops.GetPlayerShopId
function Core.GetMyShopId()
    local illegal = Core.GetIllegalShopId()
    if illegal then return illegal end
    local duty = Core.GetDutyShopId()
    if duty then return duty end
    if not Config.RequireDuty then
        local shops = Core.GetMyShops()
        table.sort(shops, function(a, b) return a.id < b.id end)
        if shops[1] then return shops[1].id end
    end
    return nil
end

-- Scene of the illegal DLC is running (its own animation library / scenes are not visible to the BASE busy checks).
-- Not part of the IsBusy export: the DLC IsBusy export already asks the BASE one.
function Core.IsExternalBusy()
    local resource = Config.IllegalResource
    if not resource or GetResourceState(resource) ~= "started" then return false end
    local ok, busy = pcall(function()
        return exports[resource]:IsBusy()
    end)
    return ok and busy == true
end

-- Illegal workshop: crew perms sent by the server, legal workshop: job grade matrix
function Core.GetPermissions(shopId)
    local shop = Core.GetShop(shopId)
    if not shop then return {} end
    if shop.kind == "illegal" then
        return PrivatePerms[shop.id] or {}
    end
    local job, grade = Core.GetJob()
    return Utils.GetShopPermissions(shop, job, grade)
end

-- UI only, server always checks again. shopId nil = current shop. Illegal workshops have no duty.
function Core.HasPermission(perm, shopId)
    shopId = tonumber(shopId) or Core.GetMyShopId()
    if not shopId then return false end
    local shop = Core.GetShop(shopId)
    if not shop then return false end
    local perms = Core.GetPermissions(shopId)
    if not perms[perm] then return false end
    if shop.kind ~= "illegal" and Config.RequireDuty and perm ~= "duty" and perm ~= "bossmenu" and perm ~= "manage_shop" then
        return Core.GetDutyShopId() == shopId
    end
    return true
end

-- I work in the workshop: job of a legal workshop / crew member of an illegal one (no duty check)
function Core.IsMember(shopId)
    local shop = Core.GetShop(shopId)
    if not shop then return false end
    if shop.kind == "illegal" then
        return PrivatePerms[shop.id] ~= nil
    end
    return Utils.ShopHasJob(shop, BRIDGE.GetPlayerJob())
end

--[[
  _   _ _    _ _____
 | \ | | |  | |_   _|
 |  \| | |  | | | |
 | . ` | |  | | | |
 | |\  | |__| |_| |_
 |_| \_|\____/|_____|

 Client -> NUI: { action = "open" | "update" | "close", view = string, data = table, locales = table, config = table }
 NUI -> client: RegisterNUICallback("<view>:<action>") in modules, "close" is handled here
]]--

Core.Nui = {}
local CurrentView = nil
local CloseHandlers = {}

local function getUiLocales()
    local result = {}
    local ok, all = pcall(function() return lib.getLocales and lib.getLocales() or nil end)
    if ok and all then
        for key, value in pairs(all) do
            if key:sub(1, 3) == "ui_" then
                result[key] = value
            end
        end
    end
    return result
end

local function uiConfig()
    return {
        currency = Config.Currency,
        imagePath = Config.ImagePath,
        mileageUnit = Config.MileageUnit,
        fetchParts = Config.Fetch ~= nil and Config.Fetch.enabled ~= false, -- parts can be fetched from storage during work
    }
end

-- focus = false for overlays (workflow) - overlay doesn't change current view
function Core.Nui.Open(view, data, focus)
    if focus ~= false then
        CurrentView = view
        SetNuiFocus(true, true)
    end
    SendNUIMessage({
        action = "open",
        view = view,
        data = data or {},
        locales = getUiLocales(),
        config = uiConfig(),
    })
end

function Core.Nui.Update(view, data)
    SendNUIMessage({
        action = "update",
        view = view,
        data = data or {},
    })
end

-- Closes view. Calls OnClose handler of the view.
function Core.Nui.Close(view)
    view = view or CurrentView
    if CurrentView == view then
        CurrentView = nil
        SetNuiFocus(false, false)
    end
    SendNUIMessage({ action = "close", view = view })
    if view and CloseHandlers[view] then
        CreateThread(function()
            CloseHandlers[view]()
        end)
    end
end

function Core.Nui.GetView()
    return CurrentView
end

function Core.Nui.IsOpen(view)
    if view then return CurrentView == view end
    return CurrentView ~= nil
end

-- fn() when view is closed (ESC in NUI or Core.Nui.Close)
function Core.Nui.OnClose(view, fn)
    CloseHandlers[view] = fn
end

RegisterNUICallback("close", function(data, cb)
    Core.Nui.Close(data and data.view or nil)
    cb({ ok = true })
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() and CurrentView then
        SetNuiFocus(false, false)
    end
end)

--[[
   _____ _                   _____      _       _
  / ____| |                 |  __ \    (_)     | |
 | (___ | |__   ___  _ __   | |__) |__  _ _ __ | |_ ___
  \___ \| '_ \ / _ \| '_ \  |  ___/ _ \| | '_ \| __/ __|
  ____) | | | | (_) | |_) | | |  | (_) | | | | | |_\__ \
 |_____/|_| |_|\___/| .__/  |_|   \___/|_|_| |_|\__|___/
                    | |
                    |_|
 Modules register actions for point types, client/shops.lua builds targets / markers.
 action = {
    label = string,
    icon = string,
    perm = string | nil,              -- shown only with permission (nil = everyone)
    canInteract = function(shop, point) return bool end | nil,
    onSelect = function(shop, point) end,
    resource = string | nil,          -- other resource (exports), its actions are removed when it stops
 }
]]--

ShopPoints = {}
local PointActions = {}
local PointListeners = {}

-- Point types of config.lua, other resources can't replace them
local BuiltInPointTypes = {}
for key in pairs(Config.PointTypes) do
    BuiltInPointTypes[key] = true
end

local function notifyPointListeners(pointType)
    for _, fn in pairs(PointListeners) do
        fn(pointType)
    end
end

function ShopPoints.RegisterAction(pointType, action)
    PointActions[pointType] = PointActions[pointType] or {}
    table.insert(PointActions[pointType], action)
    notifyPointListeners(pointType)
end

function ShopPoints.GetActions(pointType)
    return PointActions[pointType] or {}
end

-- client/shops.lua rebuilds targets when module registers action / point type later
function ShopPoints.OnActionRegistered(fn)
    table.insert(PointListeners, fn)
end

-- Removes actions registered by another resource (it stopped, it registers them again on start)
function ShopPoints.RemoveActionsOf(resource)
    local removedAny = false
    for pointType, actions in pairs(PointActions) do
        local removed = false
        for i = #actions, 1, -1 do
            if actions[i].resource == resource then
                table.remove(actions, i)
                removed = true
            end
        end
        if removed then
            removedAny = true
            notifyPointListeners(pointType)
        end
    end
    return removedAny
end

-- Point type can be placed in workshop kind (Config.PointTypes[type].kinds, missing = legal only)
function ShopPoints.TypeAllowed(pointType, kind)
    local data = Config.PointTypes[pointType]
    if not data then return false end
    local kinds = type(data.kinds) == "table" and data.kinds or { legal = true }
    return kinds[kind or "legal"] == true
end

-- Adds point type of another resource (export RegisterPointType, same def as on the server). Built-in types can't be replaced.
-- def = { label, icon, radius, multiple, kinds = { illegal = true }, fields?, color? = { r, g, b } }
function ShopPoints.RegisterType(key, def)
    if type(key) ~= "string" or #key > 32 or not key:match("^[%w_]+$") then return false end
    if BuiltInPointTypes[key] or type(def) ~= "table" then return false end
    local kinds = {}
    for kind, value in pairs(type(def.kinds) == "table" and def.kinds or {}) do
        if (kind == "legal" or kind == "illegal") and value == true then
            kinds[kind] = true
        end
    end
    if next(kinds) == nil then
        kinds.legal = true
    end
    Config.PointTypes[key] = {
        label = type(def.label) == "string" and def.label or key,
        icon = type(def.icon) == "string" and def.icon or "fa-solid fa-location-dot",
        radius = Utils.Clamp(tonumber(def.radius) or 1.5, 0.5, 15.0),
        multiple = def.multiple ~= false,
        kinds = kinds,
        fields = type(def.fields) == "table" and Utils.DeepCopy(def.fields) or nil,
        color = type(def.color) == "table" and Utils.DeepCopy(def.color) or nil,
    }
    notifyPointListeners(key)
    return true
end

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

function Core.Notify(description, notifyType)
    BRIDGE.Notify({
        title = locale("script_title"),
        description = description,
        type = notifyType or "inform",
    })
end

function Core.GetClosestVehicle(maxDistance)
    local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), maxDistance or 4.0, true)
    return vehicle
end

-- Requests network control of entity. Returns true when we have it.
function Core.RequestControl(entity, timeout)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    local endTime = GetGameTimer() + (timeout or 2000)
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < endTime do
        Wait(50)
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

-- Plays looped anim until Core.StopAnim / ClearPedTasks
function Core.PlayAnim(dict, clip, flag, duration)
    lib.requestAnimDict(dict)
    TaskPlayAnim(cache.ped, dict, clip, 8.0, -8.0, duration or -1, flag or 1, 0, false, false, false)
    RemoveAnimDict(dict)
end

function Core.StopAnim()
    ClearPedTasks(cache.ped)
end

-- Attaches prop from Config.Props[key] (or table {model, bone, pos, rot}) to player. Returns object or nil.
function Core.AttachProp(prop)
    if type(prop) == "string" then prop = Config.Props[prop] end
    if not prop or not prop.model then return nil end
    local model = joaat(prop.model)
    if not IsModelValid(model) then return nil end
    lib.requestModel(model)
    local coords = GetEntityCoords(cache.ped)
    local object = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    local pos = prop.pos or vec3(0.0, 0.0, 0.0)
    local rot = prop.rot or vec3(0.0, 0.0, 0.0)
    AttachEntityToEntity(object, cache.ped, GetPedBoneIndex(cache.ped, prop.bone or 57005), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    return object
end

function Core.DeleteProp(object)
    if object and DoesEntityExist(object) then
        DetachEntity(object, true, false)
        DeleteEntity(object)
    end
end

-- ox_lib progress with default disables. anim = {dict, clip, flag} / {scenario}, prop = Config.Props key or ox prop table
function Core.Progress(label, duration, anim, prop)
    local oxProp = nil
    if type(prop) == "string" and Config.Props[prop] and Config.Props[prop].model then
        local p = Config.Props[prop]
        oxProp = { model = joaat(p.model), bone = p.bone, pos = p.pos, rot = p.rot }
    elseif type(prop) == "table" then
        oxProp = prop
    end
    return lib.progressCircle({
        label = label,
        duration = duration,
        position = "bottom",
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = anim,
        prop = oxProp,
    })
end

-- Vehicle parts state (statebag set by server)
function Core.GetVehicleData(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end
    return Entity(vehicle).state.pls_mech
end

-- Bay at coords. purpose = "repair" / "tuning" / nil. Returns point, shop
function Core.GetBayAt(coords, purpose)
    for _, shop in pairs(Core.Shops) do
        for _, point in pairs(shop.points or {}) do
            if point.type == "bay" and (not purpose or Utils.BayAccepts(point, purpose)) then
                if #(coords - Utils.Vec3(point.coords)) <= (point.radius or Config.PointTypes.bay.radius) then
                    return point, shop
                end
            end
        end
    end
    return nil, nil
end

function Core.GetLiftAt(coords)
    for _, shop in pairs(Core.Shops) do
        for _, point in pairs(shop.points or {}) do
            if point.type == "lift" then
                if #(coords - Utils.Vec3(point.coords)) <= (point.radius or Config.PointTypes.lift.radius) then
                    return point, shop
                end
            end
        end
    end
    return nil, nil
end

function Core.IsVehicleOnLift(vehicle)
    local lift = Entity(vehicle).state.pls_lift
    return lift ~= nil and lift ~= false
end

-- {wheel = "lf"/"rf"/"lr"/"rr", ...} or nil
function Core.GetJack(vehicle)
    return Entity(vehicle).state.pls_jack
end

-- Same rules as server Shops.CheckLocation. Returns ok, reason locale key
function Core.CheckLocation(vehicle, location, wheel)
    if not location or location == "anywhere" then return true end
    if not DoesEntityExist(vehicle) then return false, "no_vehicle" end
    local onLift = Core.IsVehicleOnLift(vehicle)
    if location == "lift" then
        return onLift, "location_lift"
    end
    if location == "bay" then
        if onLift then return true end
        return Core.GetBayAt(GetEntityCoords(vehicle), "repair") ~= nil, "location_bay"
    end
    if location == "lift_or_jack" then
        if onLift then return true end
        local jack = Core.GetJack(vehicle)
        if jack and (wheel == nil or jack.wheel == Utils.WheelSides[wheel]) then
            return true
        end
        return false, "location_lift_or_jack"
    end
    return true
end

-- Nearby players { serverId, name }
function Core.GetNearbyPlayers(radius, includeSelf)
    local result = {}
    local players = lib.getNearbyPlayers(GetEntityCoords(cache.ped), radius or 5.0, includeSelf == true)
    for _, v in pairs(players) do
        table.insert(result, { serverId = GetPlayerServerId(v.id), name = GetPlayerName(v.id) })
    end
    return result
end

-- Item labels from inventory
local ItemLabels = nil
function Core.GetItemLabel(itemName)
    if not ItemLabels then
        ItemLabels = {}
        local items = BRIDGE.GetItems() or {}
        for name, data in pairs(items) do
            ItemLabels[name] = data.label or name
        end
    end
    return ItemLabels[itemName] or itemName
end

-- Item functions (Core.CountItem / CountTool / CheckItems / HasTools) with stolen parts rules: client/inventory.lua

-- Walks player to coords (used before repair animations)
function Core.GoTo(coords, heading, timeout)
    TaskGoStraightToCoord(cache.ped, coords.x, coords.y, coords.z, 1.0, timeout or 5000, heading or 0.0, 0.1)
    local endTime = GetGameTimer() + (timeout or 5000)
    while #(GetEntityCoords(cache.ped).xy - vector2(coords.x, coords.y)) > 0.6 and GetGameTimer() < endTime do
        Wait(100)
    end
    if heading then
        SetEntityHeading(cache.ped, heading)
    end
end

-- Position next to vehicle for access type: "hood" / "trunk" / "under" / "wheel" (+ wheel index). Returns coords, heading
function Core.GetAccessPosition(vehicle, access, wheel)
    local vehHeading = GetEntityHeading(vehicle)
    if access == "wheel" then
        local bone = GetEntityBoneIndexByName(vehicle, Utils.WheelBones[wheel or 0] or "wheel_lf")
        local wheelPos = bone ~= -1 and GetWorldPositionOfEntityBone(vehicle, bone) or GetEntityCoords(vehicle)
        local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, wheelPos.x, wheelPos.y, wheelPos.z)
        local side = offset.x < 0 and -1 or 1
        local pos = GetOffsetFromEntityInWorldCoords(vehicle, offset.x + side * 0.9, offset.y, 0.0)
        return pos, vehHeading + (side < 0 and -90.0 or 90.0)
    elseif access == "trunk" then
        local min, max = GetModelDimensions(GetEntityModel(vehicle))
        return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, min.y - 0.6, 0.0), vehHeading
    elseif access == "under" then
        local min = GetModelDimensions(GetEntityModel(vehicle))
        return GetOffsetFromEntityInWorldCoords(vehicle, min.x - 0.7, 0.0, 0.0), vehHeading - 90.0
    end
    local _, max = GetModelDimensions(GetEntityModel(vehicle))
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, max.y + 0.6, 0.0), vehHeading + 180.0
end
