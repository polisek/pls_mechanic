--[[
   _____      _               
  / ____|    | |              
 | (___   ___| |_ _   _ _ __  
  \___ \ / _ \ __| | | | '_ \ 
  ____) |  __/ |_| |_| | |_) |
 |_____/ \___|\__|\__,_| .__/ 
                       | |    
                       |_|    
]]--
Framework = {}
if BRIDGE.Framework == "ESX" then
   if BRIDGE.ESXOld then
      TriggerEvent('esx:getSharedObject', function(obj) Framework = obj end)
   else 
      Framework = exports["es_extended"]:getSharedObject()
   end
elseif BRIDGE.Framework == "QB" then
   Framework = exports['qb-core']:GetCoreObject()
end

-- qb-core / qbx_core restarted: the core object copy is dead (its functions point to the stopped resource), get it again.
-- The export event is read directly: exports['qb-core'] keeps the old function until a resource named qb-core stops
-- (qbx_core only provides qb-core).
AddEventHandler('onResourceStart', function(resourceName)
    if BRIDGE.Framework ~= "QB" or (resourceName ~= 'qb-core' and resourceName ~= 'qbx_core') then return end
    SetTimeout(1000, function()
        local getCore = nil
        TriggerEvent('__cfx_export_qb-core_GetCoreObject', function(exportData) getCore = exportData end)
        local ok, core = pcall(function()
            if getCore then return getCore() end
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and type(core) == "table" then
            Framework = core
        end
    end)
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded',function(xPlayer, isNew, skin)
    TriggerEvent(GetCurrentResourceName()..':playerLoaded', xPlayer, isNew, skin)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local PlayerData = {}
    if BRIDGE.Framework == "QB" then
        PlayerData = Framework.Functions.GetPlayerData()
    end
    TriggerEvent(GetCurrentResourceName()..':playerLoaded', PlayerData)
    TriggerServerEvent(GetCurrentResourceName()..":server:configPlayerLoaded")
end)

AddEventHandler('ox:playerLoaded', function(data)
    TriggerEvent(GetCurrentResourceName()..':playerLoaded', data)
end)


RegisterNetEvent(GetCurrentResourceName()..':playerLoaded')
AddEventHandler(GetCurrentResourceName()..':playerLoaded',function(playerData, isNew, skin)
    --print("PLS BRIDGE - Player loaded")
end)

-- OX is not supported, its branches only must not crash ("inService" group, nil without ox_core lib)
local function oxInService()
    local ok, value = pcall(function() return Ox.GetPlayer().get("inService") end)
    if ok and type(value) == "table" then return value end
    return nil
end





--[[
   _____      _       _       _     
  / ____|    | |     | |     | |    
 | |  __  ___| |_    | | ___ | |__  
 | | |_ |/ _ \ __|   | |/ _ \| '_ \ 
 | |__| |  __/ || |__| | (_) | |_) |
  \_____|\___|\__\____/ \___/|_.__/                                                                                                                                                                     
]]--

BRIDGE.GetPlayerJob = function ()
    local JobName = nil
    if BRIDGE.Framework == "ESX" then
        local PlayerData = Framework.GetPlayerData()
        JobName = PlayerData.job.name
    elseif BRIDGE.Framework == "QB" then
        local Player = Framework.Functions.GetPlayerData()
        JobName = Player.job.name
    elseif BRIDGE.Framework == "OX" then
        local Job = oxInService()
        JobName = Job and Job.name
    end
    return JobName
end



--[[
   _____      _    _____               _      
  / ____|    | |  / ____|             | |     
 | |  __  ___| |_| |  __ _ __ __ _  __| | ___ 
 | | |_ |/ _ \ __| | |_ | '__/ _` |/ _` |/ _ \
 | |__| |  __/ |_| |__| | | | (_| | (_| |  __/
  \_____|\___|\__|\_____|_|  \__,_|\__,_|\___|
                                              
                                                                                                                                                                                                            
]]--

BRIDGE.GetPlayerGrade = function ()
    local JobName = nil
    if BRIDGE.Framework == "ESX" then
        local PlayerData = Framework.GetPlayerData()
        JobName = PlayerData.job.grade
    elseif BRIDGE.Framework == "QB" then
        local Player = Framework.Functions.GetPlayerData()
        JobName = Player.job.grade.level
    elseif BRIDGE.Framework == "OX" then
        local Job = oxInService()
        JobName = Job and Job.grade
    end
    return JobName
 end

 ---- CHARID
BRIDGE.GetPlayerCharId = function ()
    local identifier = nil
    if BRIDGE.Framework == "ESX" then
        local PlayerData = Framework.GetPlayerData()
        identifier = PlayerData.identifier
    elseif BRIDGE.Framework == "QB" then
        local Player = Framework.Functions.GetPlayerData()
        identifier = Player.citizenid
    elseif BRIDGE.Framework == "OX" then
       local ok, player = pcall(function() return Ox.GetPlayer() end)
       identifier = ok and type(player) == "table" and player.charId or nil
    end
    return identifier
 end


--[[
       _       _           _       _
      | |     | |         | |     | |
      | | ___ | |__     __| | __ _| |_ __ _
  _   | |/ _ \| '_ \   / _` |/ _` | __/ _` |
 | |__| | (_) | |_) | | (_| | (_| | || (_| |
  \____/ \___/|_.__/   \__,_|\__,_|\__\__,_|

]]--

-- Own job { name, label, grade, gradeLabel, isBoss, onDuty } (same as the server version), nil when not loaded.
-- grade = integer, onDuty = nil when the framework has no duty (ESX older than 1.11). UI only - the server checks again.
BRIDGE.GetPlayerJobData = function ()
    if BRIDGE.Framework == "ESX" then
        local ok, PlayerData = pcall(function() return Framework.GetPlayerData() end)
        local job = ok and type(PlayerData) == "table" and PlayerData.job or nil
        if type(job) ~= "table" or not job.name then return nil end
        local onDuty = nil
        if type(job.onDuty) == "boolean" then
            onDuty = job.onDuty
        end
        local grade = math.floor(tonumber(job.grade) or 0)
        return { name = job.name, label = job.label or job.name, grade = grade, gradeLabel = job.grade_label or tostring(grade), isBoss = job.grade_name == "boss", onDuty = onDuty }
    elseif BRIDGE.Framework == "QB" then
        local ok, PlayerData = pcall(function()
            if BRIDGE.IsQbox then return exports.qbx_core:GetPlayerData() end
            return Framework.Functions.GetPlayerData()
        end)
        local job = ok and type(PlayerData) == "table" and PlayerData.job or nil
        if type(job) ~= "table" or not job.name then return nil end
        local gradeData = type(job.grade) == "table" and job.grade or {}
        local grade = math.floor(tonumber(gradeData.level) or 0)
        return { name = job.name, label = job.label or job.name, grade = grade, gradeLabel = gradeData.name or tostring(grade), isBoss = job.isboss == true or gradeData.isboss == true, onDuty = job.onduty == true }
    end
    return nil
end