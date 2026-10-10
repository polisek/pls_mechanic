--[[
             _____ _____
     /\     |  __ \_   _|
    /  \    | |__) || |
   / /\ \   |  ___/ | |
  / ____ \ _| |    _| |_
 /_/    \_\_|_|   |_____|

 Client exports for other resources (illegal DLC). Everything returns plain copies.
 Functions of other resources (point action callbacks) are called in pcall, their actions are removed
 when the resource stops (it registers them again on start).
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

local ShopCopies = {}   -- [shopId] = public copy for callbacks of other resources (dropped when shops change)

-- { id, name, kind, points = { { id, type, coords, heading, radius, data } }, settings }
local function publicCopy(shop)
    if not shop then return nil end
    local points = {}
    for _, point in ipairs(shop.points or {}) do
        points[#points + 1] = {
            id = point.id,
            type = point.type,
            coords = Utils.DeepCopy(point.coords),
            heading = point.heading,
            radius = point.radius,
            data = Utils.DeepCopy(point.data or {}),
        }
    end
    return {
        id = shop.id,
        name = shop.name,
        kind = shop.kind or "legal",
        points = points,
        settings = Utils.DeepCopy(shop.settings or {}),
    }
end

-- Cached copy (canInteract of targets runs very often), the other resource gets it serialized anyway
local function cachedCopy(shop)
    if not shop then return nil end
    local copy = ShopCopies[shop.id]
    if not copy then
        copy = publicCopy(shop)
        ShopCopies[shop.id] = copy
    end
    return copy
end

local function pointCopy(shop, point)
    local copy = cachedCopy(shop)
    for _, p in ipairs(copy and copy.points or {}) do
        if p.id == point.id then
            return p
        end
    end
    return Utils.DeepCopy(point)
end

Core.OnShopsUpdated(function()
    ShopCopies = {}
end)

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

exports("GetItems", function()
    return Utils.DeepCopy(Config.Items)
end)

-- Same def as the server export: { label, icon, radius, multiple, kinds = { illegal = true }, fields?, color? }
exports("RegisterPointType", function(key, def)
    return ShopPoints.RegisterType(key, def)
end)

-- action = { label, icon, perm?, canInteract = function(shop, point) end, onSelect = function(shop, point) end }
-- shop / point passed to the callbacks are copies (incl. shop.kind). Targets / markers are rebuilt.
exports("RegisterPointAction", function(pointType, action)
    if type(pointType) ~= "string" or type(action) ~= "table" or action.onSelect == nil then return false end
    local resource = GetInvokingResource()
    local canInteract, onSelect = action.canInteract, action.onSelect
    ShopPoints.RegisterAction(pointType, {
        label = tostring(action.label or pointType),
        icon = type(action.icon) == "string" and action.icon or "fa-solid fa-circle",
        perm = type(action.perm) == "string" and action.perm or nil,
        resource = resource,
        canInteract = canInteract and function(shop, point)
            local ok, allowed = pcall(canInteract, cachedCopy(shop), pointCopy(shop, point))
            return ok and allowed ~= nil and allowed ~= false
        end or nil,
        onSelect = function(shop, point)
            local ok, err = pcall(onSelect, cachedCopy(shop), pointCopy(shop, point))
            if not ok then
                print(("[pls_mechanic] point action of %s error: %s"):format(tostring(resource), tostring(err)))
            end
        end,
    })
    return true
end)

exports("GetShop", function(shopId)
    return publicCopy(Core.GetShop(shopId))
end)

-- Duty shop / illegal workshop I stand in (with crew access), nil otherwise
exports("GetCurrentShopId", function()
    return Core.GetMyShopId()
end)

-- UI check only, the server checks again. shopId nil = current shop
exports("HasPermission", function(perm, shopId)
    if type(perm) ~= "string" then return false end
    return Core.HasPermission(perm, shopId) == true
end)

--[[
 __          __        _
 \ \        / /       | |
  \ \  /\  / /__  _ __| | __
   \ \/  \/ / _ \| '__| |/ /
    \  /\  / (_) | |  |   <
     \/  \/ \___/|_|  |_|\_\
]]--

-- BASE repair workflow / diagnostics / tuning menu or installation / Anim phase / menu scene / waiting for parts.
-- Scenes of the DLC (Core.IsExternalBusy) are not included on purpose: the DLC IsBusy export calls this one.
exports("IsBusy", function()
    if Repair and Repair.IsBusy and Repair.IsBusy() then return true end
    if Diagnostics and Diagnostics.IsBusy and Diagnostics.IsBusy() then return true end
    if Tuning and ((Tuning.IsOpen and Tuning.IsOpen()) or (Tuning.IsInstalling and Tuning.IsInstalling())) then return true end
    if Anim and Anim.IsBusy and Anim.IsBusy() then return true end
    if Menu and Menu.IsBusy and Menu.IsBusy() then return true end
    if Fetch and Fetch.IsWaiting and Fetch.IsWaiting() then return true end
    return false
end)

-- Engine power is set by the caller (nitro boost), BASE skips its worn engine power meanwhile
exports("SetExternalPower", function(active)
    VehicleState.SetExternalPower(active)
end)

-- Copy of the vehicle statebag pls_mech (nil when the vehicle has no data yet)
exports("GetVehicleData", function(vehicle)
    if type(vehicle) ~= "number" or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return Utils.DeepCopy(Core.GetVehicleData(vehicle))
end)

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

-- Actions of a stopped resource would call dead function references
AddEventHandler("onClientResourceStop", function(resource)
    if resource == GetCurrentResourceName() then return end
    ShopPoints.RemoveActionsOf(resource)
end)
