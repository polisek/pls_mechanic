--[[
  _   _ _____   _____   __  __ _         _
 | \ | |  __ \ / ____| |  \/  (_)       (_)
 |  \| | |__) | |      | \  / |_ ___ ___ _  ___  _ __  ___
 | . ` |  ___/| |      | |\/| | / __/ __| |/ _ \| '_ \/ __|
 | |\  | |    | |____  | |  | | \__ \__ \ | (_) | | | \__ \
 |_| \_|_|     \_____| |_|  |_|_|___/___/_|\___/|_| |_|___/

 One active mission per player. Vehicle is created server side (CreateVehicleServerSetter)
 when the mechanic gets close, the owner client applies native damage (statebag pls_mission).
 Completion is always validated here, rewards: money + materials (+ society share).
]]--

MissionsServer = {}

local Active = {}       -- [src] = mission
local Cooldowns = {}    -- [charid] = os.time() of next allowed mission
local Despawns = {}     -- [entity] = true (finished mission vehicles waiting for removal)
local RateLimits = {}   -- [src][key] = GetGameTimer()
local NextId = 0

local ACTIONS = { refuel = true, tyre = true, scrap = true }
local WHEELS = { 0, 1, 4, 5 }

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

local function RateLimited(src, key, ms)
    local now = GetGameTimer()
    RateLimits[src] = RateLimits[src] or {}
    if RateLimits[src][key] and now - RateLimits[src][key] < ms then
        return true
    end
    RateLimits[src][key] = now
    return false
end

local function RandomFrom(list)
    if not list or #list == 0 then return nil end
    return list[math.random(#list)]
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

local function GeneratePlate()
    local letters = "ABCDEFGHJKLMNPRSTUVWXYZ"
    local chars = {}
    for i = 1, 3 do
        local index = math.random(#letters)
        chars[i] = letters:sub(index, index)
    end
    return ("%02d%s%03d"):format(math.random(0, 99), table.concat(chars), math.random(0, 999))
end

local function TypeConfig(missionType)
    return Config.Missions.types[missionType]
end

-- Model entry "name" or { model = "name", type = "bike" }
local function PickModel(cfg)
    local entry = RandomFrom(cfg.vehicles or Config.Missions.vehicles)
    if type(entry) == "table" then
        return entry.model, entry.type or "automobile"
    end
    return entry, "automobile"
end

local function PickLocation(cfg)
    local candidates = {}
    for _, area in pairs(cfg.areas or { "city", "county" }) do
        for _, location in pairs(Config.Missions.locations[area] or {}) do
            local free = true
            for _, mission in pairs(Active) do
                if #(mission.anchor.xyz - location.xyz) < 60.0 then
                    free = false
                    break
                end
            end
            if free then
                table.insert(candidates, location)
            end
        end
    end
    return RandomFrom(candidates)
end

-- Tow drop-off: bay / lift / garage point of the workshop, otherwise closest config drop-off
local function GetDropOff(shopId, cfg, anchor)
    local shop = shopId and Shops.Get(shopId)
    if shop then
        for _, pointType in ipairs({ "bay", "lift", "garage" }) do
            for _, point in pairs(shop.points or {}) do
                if point.type == pointType then
                    return Utils.Vec3(point.coords)
                end
            end
        end
    end
    local best, bestDistance = nil, nil
    for _, coords in pairs(cfg.dropOffs or {}) do
        local distance = #(coords - anchor.xyz)
        if not bestDistance or distance < bestDistance then
            best, bestDistance = coords, distance
        end
    end
    return best
end

local function BuildSetup(missionType, cfg)
    if missionType == "tow" then
        return { engineHealth = cfg.engineHealth or 100.0 }
    elseif missionType == "tyre" then
        return { tyre = RandomFrom(WHEELS) }
    elseif missionType == "scrap" then
        return { door = math.random(0, 3), tyres = math.random(1, 3) }
    end
    return {}
end

-- Data sent to the mission client
local function ClientData(mission)
    local cfg = TypeConfig(mission.type)
    return {
        id = mission.id,
        type = mission.type,
        plate = mission.plate,
        anchor = { x = mission.anchor.x, y = mission.anchor.y, z = mission.anchor.z, w = mission.anchor.w },
        dropOff = mission.dropOff and Utils.Coords(mission.dropOff) or nil,
        dropRadius = cfg.dropRadius,
        npc = mission.npc,
        setup = mission.setup,
        netId = mission.netId,
        expiresIn = mission.expiresAt - os.time(),
    }
end

local function GetMission(src, missionId)
    local mission = Active[src]
    if not mission or mission.id ~= missionId then return nil end
    return mission
end

local function MissionEntity(mission)
    if not mission.entity or not DoesEntityExist(mission.entity) then return nil end
    return mission.entity
end

local function RemoveVehicle(entity)
    if not entity or not DoesEntityExist(entity) then return end
    if MenuServer and MenuServer.ReleaseTowed then
        MenuServer.ReleaseTowed(entity)
    end
    DeleteEntity(entity)
end

-- Removes finished mission vehicle after delay, waits while somebody drives it
local function ScheduleDespawn(entity)
    if not entity or not DoesEntityExist(entity) then return end
    Entity(entity).state:set("pls_mission", nil, true)
    Despawns[entity] = true
    CreateThread(function()
        Wait(Config.Missions.despawnDelay * 1000)
        for _ = 1, 40 do
            if not DoesEntityExist(entity) then break end
            local driver = GetPedInVehicleSeat(entity, -1)
            if not driver or driver == 0 then
                RemoveVehicle(entity)
                break
            end
            Wait(15000)
        end
        Despawns[entity] = nil
    end)
end

--[[
  ______           _
 |  ____|         | |
 | |__   _ __   __| |
 |  __| | '_ \ / _` |
 | |____| | | | (_| |
 |______|_| |_|\__,_|
]]--

local function GiveReward(mission)
    local src = mission.src
    local reward = TypeConfig(mission.type).reward or {}
    local result = { money = 0, items = {} }

    if reward.money then
        result.money = math.random(reward.money.min or 0, math.max(reward.money.min or 0, reward.money.max or 0))
        if result.money > 0 then
            BRIDGE.AddItem(src, "money", result.money)
        end
    end
    for _, v in pairs(reward.items or {}) do
        if math.random(100) <= (v.chance or 100) then
            local count = math.random(v.min or 1, math.max(v.min or 1, v.max or v.min or 1))
            if count > 0 then
                BRIDGE.AddItem(src, Utils.Item(v.item), count)
                table.insert(result.items, { item = Utils.Item(v.item), count = count })
            end
        end
    end

    local share = Config.Missions.societyShare or 0
    local job = mission.shopId and Shops.GetSocietyJob(mission.shopId)
    if share > 0 and job and result.money > 0 then
        local amount = math.floor(result.money * share / 100)
        if amount > 0 then
            BRIDGE.AddSocietyMoney(job, amount)
            result.society = amount
        end
    end
    return result
end

local function Complete(mission, deleteVehicle)
    if Active[mission.src] ~= mission then return end
    Active[mission.src] = nil
    Cooldowns[mission.charid] = os.time() + Config.Missions.cooldown

    local reward = GiveReward(mission)
    local entity = MissionEntity(mission)
    if deleteVehicle then
        RemoveVehicle(entity)
    else
        ScheduleDespawn(entity)
    end
    TriggerClientEvent("pls_mechanic:client:missions:ended", mission.src, mission.id, "completed", reward)
    OpenServer.Log(mission.src, "mission_complete", ("%s completed %s mission (%s, $%d)"):format(PlayerName(mission.src), mission.type, mission.plate, reward.money), {
        type = mission.type,
        plate = mission.plate,
        reward = reward,
    })
end

-- reason = "cancelled" / "timeout" / "failed" / nil (player dropped)
local function Finish(mission, reason)
    if Active[mission.src] ~= mission then return end
    Active[mission.src] = nil
    Cooldowns[mission.charid] = os.time() + Config.Missions.cooldown
    RemoveVehicle(MissionEntity(mission))
    if reason then
        TriggerClientEvent("pls_mechanic:client:missions:ended", mission.src, mission.id, reason)
        OpenServer.Log(mission.src, "mission_"..reason, ("%s mission %s: %s"):format(PlayerName(mission.src), mission.type, reason), {
            type = mission.type,
            plate = mission.plate,
        })
    end
end

-- Called by server/menu.lua after successful jump start
function MissionsServer.OnJumpStart(src, entity)
    for _, mission in pairs(Active) do
        if mission.entity == entity and mission.type == "jumpstart" and mission.ready then
            local data = Vehicles and Vehicles.GetByEntity and Vehicles.GetByEntity(entity)
            local battery = data and data.core and data.core.battery
            if battery and battery > Config.PartStates.critical then
                if mission.src ~= src then
                    Shops.Notify(mission.src, locale("mission_helped", PlayerName(src)), "inform")
                end
                Complete(mission)
            end
            return
        end
    end
end

-- Mission of vehicle entity or nil
function MissionsServer.GetByEntity(entity)
    for _, mission in pairs(Active) do
        if mission.entity == entity then
            return mission
        end
    end
    return nil
end

--[[
   _____ _             _
  / ____| |           | |
 | (___ | |_ __ _ _ __| |_
  \___ \| __/ _` | '__| __|
  ____) | || (_| | |  | |_
 |_____/ \__\__,_|_|   \__|
]]--

lib.callback.register("pls_mechanic:server:missions:start", function(src, missionType)
    if not Config.Missions.enabled then return false, "mission_disabled" end
    local cfg = TypeConfig(missionType)
    if not cfg or not cfg.enabled then return false, "mission_invalid" end
    local ok, shopId = Shops.HasPermission(src, "missions")
    if not ok then return false, shopId and "no_permission" or "not_on_duty" end
    if Active[src] then return false, "mission_already" end
    if RateLimited(src, "start", 2000) then return false, "menu_rate_limit" end

    local charid = GetCharId(src)
    local cooldown = Cooldowns[charid]
    if cooldown and cooldown > os.time() then
        return false, "mission_cooldown", cooldown - os.time()
    end
    local anchor = PickLocation(cfg)
    if not anchor then return false, "mission_no_location" end
    local model, vehicleType = PickModel(cfg)
    if not model then return false, "mission_no_location" end

    NextId = NextId + 1
    local npc = nil
    local npcConfig = Config.Missions.npc
    if cfg.npc ~= false and npcConfig and math.random(100) <= (npcConfig.chance or 0) then
        npc = { model = RandomFrom(npcConfig.models), scenario = RandomFrom(npcConfig.scenarios) }
        if not npc.model then npc = nil end
    end

    local mission = {
        id = NextId,
        src = src,
        charid = charid,
        shopId = shopId,
        type = missionType,
        anchor = anchor,
        model = model,
        vehicleType = vehicleType,
        plate = GeneratePlate(),
        npc = npc,
        setup = BuildSetup(missionType, cfg),
        expiresAt = os.time() + Config.Missions.timeout * 60,
    }
    if missionType == "tow" then
        mission.dropOff = GetDropOff(shopId, cfg, anchor)
        if not mission.dropOff then return false, "mission_no_location" end
    end
    Active[src] = mission
    OpenServer.Log(src, "mission_start", ("%s started %s mission"):format(PlayerName(src), missionType), { type = missionType, plate = mission.plate })
    return true, ClientData(mission)
end)

-- Client resolved road side position near the location
lib.callback.register("pls_mechanic:server:missions:spawn", function(src, missionId, coords, heading)
    local mission = GetMission(src, missionId)
    if not mission then return false, "mission_invalid" end
    if MissionEntity(mission) then return true, mission.netId end
    if mission.spawning then return false, "menu_rate_limit" end

    local pos = mission.anchor.xyz
    heading = tonumber(heading) or mission.anchor.w
    if type(coords) == "table" and tonumber(coords.x) and tonumber(coords.y) and tonumber(coords.z) then
        local requested = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
        if #(requested - pos) <= Config.Missions.snapRadius + 5.0 then
            pos = requested
        else
            heading = mission.anchor.w
        end
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - pos) > Config.Missions.spawnDistance + 150.0 then
        return false, "too_far"
    end

    mission.spawning = true
    local entity = CreateVehicleServerSetter(joaat(mission.model), mission.vehicleType, pos.x, pos.y, pos.z + 0.3, heading + 0.0)
    local timeout = GetGameTimer() + 3000
    while (not entity or entity == 0 or not DoesEntityExist(entity)) and GetGameTimer() < timeout do
        Wait(50)
    end
    mission.spawning = false
    if Active[src] ~= mission then
        if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
        return false, "mission_invalid"
    end
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false, "mission_spawn_failed"
    end

    if SetEntityOrphanMode then
        SetEntityOrphanMode(entity, 2)
    end
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    mission.entity = entity
    mission.netId = NetworkGetNetworkIdFromEntity(entity)
    -- the owner client applies the plate later, the mission plate is the trusted plate of the vehicle right away
    if Vehicles and Vehicles.SetTrustedPlate then
        Vehicles.SetTrustedPlate(entity, mission.plate)
    end
    Entity(entity).state:set("pls_mission", {
        id = mission.id,
        type = mission.type,
        owner = src,
        plate = mission.plate,
        setup = mission.setup,
    }, true)
    return true, mission.netId
end)

-- Owner client applied native damage -> part states (vehicle module)
RegisterNetEvent("pls_mechanic:server:missions:ready", function(missionId)
    local src = source
    if not CanTrustPlayer(src) then return end
    local mission = GetMission(src, missionId)
    if not mission or mission.ready then return end
    local entity = MissionEntity(mission)
    if not entity or not Shops.IsNearEntity(src, entity, Config.Missions.spawnDistance + 100.0) then return end
    mission.ready = true
    mission.readyAt = os.time()

    if not Vehicles or not Vehicles.GetByEntity or not Vehicles.SetPart then return end
    -- wait until the plate set by the owner is synced, vehicle state is stored by plate
    for _ = 1, 50 do
        if not DoesEntityExist(entity) then return end
        if Utils.TrimPlate(GetVehicleNumberPlateText(entity)) == mission.plate then break end
        Wait(100)
    end
    local data = Vehicles.GetByEntity(entity)
    if not data then return end
    if mission.type == "jumpstart" and data.core and data.core.battery ~= nil then
        Vehicles.SetPart(data.plate, "core", "battery", 0)
    elseif mission.type == "tow" then
        for key, value in pairs(TypeConfig("tow").coreDamage or {}) do
            if data.core and data.core[key] ~= nil then
                Vehicles.SetPart(data.plate, "core", key, value)
            end
        end
    end
end)

--[[
                _   _
     /\        | | (_)
    /  \   ___| |_ _  ___  _ __  ___
   / /\ \ / __| __| |/ _ \| '_ \/ __|
  / ____ \ (__| |_| | (_) | | | \__ \
 /_/    \_\___|\__|_|\___/|_| |_|___/
]]--

local function CheckAction(src, missionId, action)
    local mission = GetMission(src, missionId)
    if not mission or mission.type ~= action or not ACTIONS[action] then return nil, "mission_invalid" end
    if not mission.ready then return nil, "mission_not_ready" end
    local entity = MissionEntity(mission)
    if not entity then return nil, "no_vehicle" end
    if not Shops.IsNearEntity(src, entity, 7.0) then return nil, "too_far" end
    local cfg = TypeConfig(action)
    if cfg.items then
        local ok = Shops.HasItems(src, cfg.items)
        if not ok then return nil, "mission_missing_items" end
    end
    if cfg.tools then
        local ok = Shops.HasTools(src, cfg.tools)
        if not ok then return nil, "mission_missing_items" end
    end
    return mission, entity
end

lib.callback.register("pls_mechanic:server:missions:actionStart", function(src, missionId, action)
    if RateLimited(src, "action", 1000) then return false, "menu_rate_limit" end
    local mission, err = CheckAction(src, missionId, action)
    if not mission then return false, err end
    mission.actionStart = GetGameTimer()
    return true
end)

lib.callback.register("pls_mechanic:server:missions:action", function(src, missionId, action)
    local mission, err = CheckAction(src, missionId, action)
    if not mission then return false, err end
    local cfg = TypeConfig(action)
    if not mission.actionStart or GetGameTimer() - mission.actionStart < (cfg.duration or 0) * 0.8 then
        return false, "mission_too_fast"
    end
    mission.actionStart = nil
    if cfg.items then
        Shops.RemoveItems(src, cfg.items)
    end
    Complete(mission, action == "scrap")
    return true
end)

-- Tow: vehicle unloaded at drop-off / tyre: controlling client reports fixed tyre
lib.callback.register("pls_mechanic:server:missions:complete", function(src, missionId)
    if RateLimited(src, "complete", 2000) then return false, "menu_rate_limit" end
    local mission = GetMission(src, missionId)
    if not mission or not mission.ready then return false, "mission_invalid" end
    local entity = MissionEntity(mission)
    if not entity then return false, "no_vehicle" end

    if mission.type == "tow" then
        if GetEntityAttachedTo(entity) ~= 0 or (MenuServer and MenuServer.IsTowed and MenuServer.IsTowed(entity)) then
            return false, "mission_tow_unload"
        end
        if #(GetEntityCoords(entity) - mission.dropOff) > (TypeConfig("tow").dropRadius or 15.0) + 2.0 then
            return false, "mission_tow_not_there"
        end
        if not Shops.IsNearEntity(src, entity, 50.0) then return false, "too_far" end
    elseif mission.type == "tyre" then
        if not Shops.IsNearEntity(src, entity, 15.0) then return false, "too_far" end
        if NetworkGetEntityOwner(entity) ~= src or os.time() - (mission.readyAt or os.time()) < 5 then
            return false, "mission_not_done"
        end
        if IsVehicleTyreBurst(entity, mission.setup.tyre, false) then
            return false, "mission_not_done"
        end
    else
        return false, "mission_invalid"
    end
    Complete(mission)
    return true
end)

lib.callback.register("pls_mechanic:server:missions:cancel", function(src)
    local mission = Active[src]
    if not mission then return false, "mission_none" end
    Finish(mission, "cancelled")
    return true
end)

--[[
   _____ _
  / ____| |
 | |    | | ___  __ _ _ __  _   _ _ __
 | |    | |/ _ \/ _` | '_ \| | | | '_ \
 | |____| |  __/ (_| | | | | |_| | |_) |
  \_____|_|\___|\__,_|_| |_|\__,_| .__/
                                 | |
                                 |_|
]]--

CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for _, mission in pairs(Active) do
            if now > mission.expiresAt then
                Finish(mission, "timeout")
            elseif mission.netId and not mission.spawning and not MissionEntity(mission) then
                Finish(mission, "failed")
            end
        end
    end
end)

AddEventHandler("pls_mechanic:server:dutyChanged", function(src, shopId)
    if not shopId and Active[src] then
        Finish(Active[src], "cancelled")
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    RateLimits[src] = nil
    if Active[src] then
        Finish(Active[src], nil)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, mission in pairs(Active) do
        local entity = MissionEntity(mission)
        if entity then DeleteEntity(entity) end
    end
    for entity in pairs(Despawns) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end)
