--[[
             _____ _____
     /\     |  __ \_   _|
    /  \    | |__) || |
   / /\ \   |  ___/ | |
  / ____ \ _| |    _| |_
 /_/    \_\_|_|   |_____|

 Shop side exports for other resources (illegal DLC). Vehicle exports live in server/api_vehicles.lua.
 Everything returns plain copies, never live BASE tables. shopId is a number.
]]--

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

local function isPlayer(src)
    src = tonumber(src)
    return src ~= nil and src > 0 and GetPlayerName(src) ~= nil
end

local function isVehicle(entity)
    return type(entity) == "number" and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

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

-- { [key] = itemName } copy of Config.Items
exports("GetItems", function()
    return Utils.DeepCopy(Config.Items)
end)

-- { id, name, kind, points = { { id, type, coords, heading, radius, data } }, settings } or nil
exports("GetShop", function(shopId)
    return Shops.PublicCopy(Shops.Get(shopId))
end)

-- List of shop copies sorted by id, kind = "legal" / "illegal" / nil (all)
exports("GetShops", function(kind)
    local list = {}
    for _, shop in pairs(Shops.GetAll()) do
        if kind == nil or shop.kind == kind then
            list[#list + 1] = Shops.PublicCopy(shop)
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)

-- Duty shop / illegal workshop the player stands in (with crew access), nil otherwise
exports("GetCurrentShopId", function(src)
    if not isPlayer(src) then return nil end
    return Shops.GetPlayerShopId(tonumber(src))
end)

-- Returns ok, shopId (same rules as Shops.HasPermission, illegal workshops: DLC crew access, no duty)
exports("HasShopPermission", function(src, perm, shopId)
    if not isPlayer(src) or type(perm) ~= "string" then return false, nil end
    local ok, resolved = Shops.HasPermission(tonumber(src), perm, tonumber(shopId))
    return ok == true, resolved
end)

-- Player stands at a point of type in the shop (point radius + margin, default 3 m). Returns bool, point copy
exports("IsNearShopPoint", function(src, shopId, pointType, margin)
    if not isPlayer(src) or type(pointType) ~= "string" then return false, nil end
    local point = Shops.GetNearPoint(tonumber(src), shopId, pointType, margin)
    if not point then return false, nil end
    return true, Utils.DeepCopy(point)
end)

-- Stash id of the workshop storage (illegal workshops: with a random key, never send it to players), nil = unknown shop
exports("GetStashId", function(shopId)
    local shop = Shops.Get(tonumber(shopId))
    if not shop then return nil end
    return Shops.GetStashId(shop.id)
end)

-- def = { label, icon, radius, multiple, kinds = { illegal = true }, fields?, color? } - call on server and client
exports("RegisterPointType", function(key, def)
    return Shops.RegisterPointType(key, def)
end)

-- Re-sends private illegal workshops + crew perms (nil = everyone), DLC calls it after crew changes
exports("RefreshShopAccess", function(src)
    if src ~= nil then
        if not isPlayer(src) then return false end
        Shops.SyncPrivate(tonumber(src))
        return true
    end
    Shops.SyncPrivate()
    return true
end)

--[[
 __      __  _     _      _
 \ \    / / | |   (_)    | |
  \ \  / /__| |__  _  ___| | ___
   \ \/ / _ \ '_ \| |/ __| |/ _ \
    \  /  __/ | | | | (__| |  __/
     \/ \___|_| |_|_|\___|_|\___|
]]--

-- Reason why a BASE system uses the vehicle entity right now or nil (same rules as the IsVehicleBusy export, the
-- customer catalog uses it too). ignoreTuning = skip "tuning" (the caller checks the menu / catalog itself)
-- Server records decide. Statebags can be written by the owner client, they can only add a reason, never clear one.
function Vehicles.GetBusyReason(entity, ignoreTuning)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not ignoreTuning and netId and netId ~= 0 and TuningServer and TuningServer.IsVehicleInTuning and TuningServer.IsVehicleInTuning(netId) then
        return "tuning"
    end
    if MenuServer and MenuServer.IsTowed and MenuServer.IsTowed(entity) then
        return "towed"
    end
    if MenuServer and MenuServer.IsTowing and MenuServer.IsTowing(entity) then
        return "towing"
    end
    if LiftServer and LiftServer.IsOnLift and LiftServer.IsOnLift(entity) then
        return "lift"
    end
    if LiftServer and LiftServer.GetJackWheel and LiftServer.GetJackWheel(entity) then
        return "jack"
    end
    if RepairServer and RepairServer.IsVehicleInRepair and RepairServer.IsVehicleInRepair(entity) then
        return "repair"
    end
    if MissionsServer and MissionsServer.GetByEntity and MissionsServer.GetByEntity(entity) then
        return "mission"
    end
    if ShopsServer and ShopsServer.IsServiceVehicle and ShopsServer.IsServiceVehicle(entity) then
        return "service"
    end
    -- attached to something (flatbed / tow truck of another script)
    if GetEntityAttachedTo(entity) ~= 0 then
        return "towed"
    end
    -- extra signals only
    local state = Entity(entity).state
    if state.pls_towed then return "towing" end
    if state.pls_lift then return "lift" end
    if state.pls_jack then return "jack" end
    if state.pls_mission then return "mission" end
    if state.pls_mech_service then return "service" end
    return nil
end

-- Vehicle is used by a BASE system right now. Returns bool, reason:
-- "tuning" (menu / installation), "towed" / "towing" (flatbed), "lift", "jack", "repair" (step running),
-- "mission" (BASE NPC mission), "service" (workshop service vehicle)
exports("IsVehicleBusy", function(entity)
    if not isVehicle(entity) then return false, nil end
    local reason = Vehicles.GetBusyReason(entity)
    return reason ~= nil, reason
end)
