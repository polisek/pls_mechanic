--[[
  _____  _                     _     _
 |  __ \| |                   | |   | |
 | |__) | | __ _  ___ ___  __ _| |__ | | ___  ___
 |  ___/| |/ _` |/ __/ _ \/ _` | '_ \| |/ _ \/ __|
 | |    | | (_| | (_|  __/ (_| | |_) | |  __/\__ \
 |_|    |_|\__,_|\___\___|\__,_|_.__/|_|\___||___/

 Networked frozen props created server side, Entity(obj).state.pls_prop = { owner = charid, item = key }.
 Limit per character, removed on resource stop.
]]--

PropsServer = {}

local Placed = {}       -- [entity] = { owner = charid, item = key }
local Counts = {}       -- [charid] = placed props
local RateLimits = {}   -- [src] = GetGameTimer()

local function RateLimited(src, ms)
    local now = GetGameTimer()
    if RateLimits[src] and now - RateLimits[src] < ms then
        return true
    end
    RateLimits[src] = now
    return false
end

local function PlayerName(src)
    local name = BRIDGE.GetPlayerFullName(src)
    if not name or name == "" then
        name = GetPlayerName(src) or tostring(src)
    end
    return name
end

local function GetCharId(src)
    return tostring(BRIDGE.GetPlayerCharId(src) or ("src:"..src))
end

local function Track(entity, info)
    Placed[entity] = info
    Counts[info.owner] = (Counts[info.owner] or 0) + 1
end

local function Untrack(entity)
    local info = Placed[entity]
    if not info then return end
    Placed[entity] = nil
    Counts[info.owner] = math.max(0, (Counts[info.owner] or 1) - 1)
end

function PropsServer.CountPlaced(charid)
    return Counts[tostring(charid)] or 0
end

-- Removes prop (returns item info or nil)
function PropsServer.Remove(entity)
    if not entity or not DoesEntityExist(entity) then return nil end
    local info = Placed[entity]
    if not info then return nil end
    Untrack(entity)
    Entity(entity).state:set("pls_prop", nil, true)
    DeleteEntity(entity)
    return info
end

RegisterNetEvent("pls_mechanic:server:props:place", function(key, coords, heading)
    local src = source
    if not CanTrustPlayer(src) then return end
    if RateLimited(src, 1000) then return end
    local data = Config.Placeables.items[key]
    if not data or type(coords) ~= "table" then return end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end
    local pos = vector3(x + 0.0, y + 0.0, z + 0.0)

    if #(GetEntityCoords(GetPlayerPed(src)) - pos) > Config.Placeables.placeDistance + 2.0 then
        return Shops.Notify(src, locale("props_too_far"), "error")
    end
    local charid = GetCharId(src)
    if (Counts[charid] or 0) >= Config.Placeables.maxPerPlayer then
        return Shops.Notify(src, locale("props_limit", Config.Placeables.maxPerPlayer), "error")
    end
    local item = Utils.Item(key)
    if (BRIDGE.GetItemCount(src, item) or 0) < 1 then
        return Shops.Notify(src, locale("props_no_item"), "error")
    end
    BRIDGE.RemoveItem(src, item, 1)

    local object = CreateObjectNoOffset(joaat(data.model), pos.x, pos.y, pos.z, true, true, false)
    local timeout = GetGameTimer() + 2000
    while (not object or object == 0 or not DoesEntityExist(object)) and GetGameTimer() < timeout do
        Wait(50)
    end
    if not object or object == 0 or not DoesEntityExist(object) then
        BRIDGE.AddItem(src, item, 1)
        return Shops.Notify(src, locale("props_failed"), "error")
    end

    if SetEntityOrphanMode then
        SetEntityOrphanMode(object, 2)
    end
    SetEntityRoutingBucket(object, GetPlayerRoutingBucket(src))
    SetEntityHeading(object, (tonumber(heading) or 0.0) + 0.0)
    FreezeEntityPosition(object, true)
    local info = { owner = charid, item = key }
    Entity(object).state:set("pls_prop", info, true)
    Track(object, info)
    OpenServer.Log(src, "prop_place", ("%s placed %s"):format(PlayerName(src), item), { item = item, coords = Utils.Coords(pos) })
end)

RegisterNetEvent("pls_mechanic:server:props:pickup", function(netId)
    local src = source
    if not CanTrustPlayer(src) then return end
    if RateLimited(src, 1000) then return end
    local object = Shops.GetEntity(tonumber(netId))
    if not object then return end
    -- only props created by the server (entity statebags can be written by the owning client)
    local info = Placed[object]
    if not info or not Config.Placeables.items[info.item] then return end
    if not Shops.IsNearEntity(src, object, Config.Placeables.pickupDistance + 1.5) then
        return Shops.Notify(src, locale("too_far"), "error")
    end
    if not PropsServer.Remove(object) then return end
    local item = Utils.Item(info.item)
    BRIDGE.AddItem(src, item, 1)
    OpenServer.Log(src, "prop_pickup", ("%s picked up %s"):format(PlayerName(src), item), { item = item, owner = info.owner })
end)

-- Adopt props left from previous run (crash without resource stop)
CreateThread(function()
    for _, object in pairs(GetAllObjects()) do
        local info = Entity(object).state.pls_prop
        if info and info.owner and info.item and not Placed[object] then
            Track(object, info)
        end
    end
end)

AddEventHandler("playerDropped", function()
    RateLimits[source] = nil
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for object in pairs(Placed) do
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end
    Placed = {}
end)
