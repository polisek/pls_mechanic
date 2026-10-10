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
Framework = nil
if BRIDGE.Framework == "ESX" then
   if BRIDGE.ESXOld then
      TriggerEvent('esx:getSharedObject', function(obj) Framework = obj end)
   else 
      Framework = exports["es_extended"]:getSharedObject()
   end
elseif BRIDGE.Framework == "QB" then
   Framework = exports['qb-core']:GetCoreObject()
end

-- QB: fresh core object. The export event is read directly: exports['qb-core'] keeps the function of the first call
-- until a resource named qb-core stops, qbx_core only provides qb-core (after its restart the function points to the stopped resource).
local function fetchCoreObject()
   local getCore = nil
   TriggerEvent('__cfx_export_qb-core_GetCoreObject', function(exportData) getCore = exportData end)
   local ok, core = pcall(function()
      if getCore then return getCore() end
      return exports['qb-core']:GetCoreObject()
   end)
   return ok and type(core) == "table" and core or nil
end

-- QB: jobs / items changed at runtime (AddJob, UpdateJob...) - the core object is only a copy, get it again (qb-core docs).
-- More updates in a row (server start) refresh it once.
local CoreRefreshPending = false
local function refreshCoreObject()
   if BRIDGE.Framework ~= "QB" or CoreRefreshPending then return end
   CoreRefreshPending = true
   SetTimeout(1000, function()
      CoreRefreshPending = false
      local core = fetchCoreObject()
      if core then
         Framework = core
      end
   end)
end

AddEventHandler('QBCore:Server:UpdateObject', function()
   local src = tonumber(source)
   if src and src > 0 then return end
   refreshCoreObject()
end)

-- qb-core / qbx_core restarted: the old copy is dead (its functions point to the stopped resource).
-- qbx_core never fires QBCore:Server:UpdateObject on its start.
AddEventHandler('onResourceStart', function(resourceName)
   local src = tonumber(source)
   if (src and src > 0) or (resourceName ~= 'qb-core' and resourceName ~= 'qbx_core') then return end
   refreshCoreObject()
end)

-- Call of a client (net event) for another player's id: a cheater would reload / flush the data of his victim.
-- Handlers of <resource>:playerLoaded can use BRIDGE.IsSpoofedPlayerLoaded(playerId) too.
local function isSpoofedPlayerLoaded(playerId)
    local src = tonumber(source)
    return src ~= nil and src > 0 and src ~= tonumber(playerId)
end
BRIDGE.IsSpoofedPlayerLoaded = isSpoofedPlayerLoaded

RegisterNetEvent('esx:playerLoaded')
RegisterNetEvent('esx:playerLoaded', function(player, xPlayer, isNew)
    if isSpoofedPlayerLoaded(player) then return end
    TriggerEvent(GetCurrentResourceName()..':playerLoaded', player, xPlayer, isNew)
end)

RegisterNetEvent(GetCurrentResourceName()..':server:configPlayerLoaded', function()
    local playerId = source
    TriggerEvent(GetCurrentResourceName()..':playerLoaded',playerId)
end)

AddEventHandler('ox:playerLoaded', function(source, userid, charid)
    TriggerEvent(GetCurrentResourceName()..':playerLoaded', source, userid, charid)
end)


-- Server side event only (not a net event): clients use :server:configPlayerLoaded, which takes their own source.
-- The check stays in case another script registers the event for the network.
AddEventHandler(GetCurrentResourceName()..':playerLoaded',function(playerId, value1, value2)
    if isSpoofedPlayerLoaded(playerId) then return end
end)


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

-- Functions which OX (or unknown framework) doesn't support - printed once per function
local WarnedUnsupported = {}
local function notSupported(functionName)
   if WarnedUnsupported[functionName] then return end
   WarnedUnsupported[functionName] = true
   print(("[PLS_BRIDGE] %s is not supported for %s, please change to your system. BRIDGE/server/framework.lua - %s"):format(functionName, tostring(BRIDGE.Framework), functionName))
end

-- OX player, nil when ox_core lib (@ox_core/lib/init.lua) is not loaded
local function oxPlayer(playerId)
   if type(Ox) ~= "table" or not Ox.GetPlayer then return nil end
   local ok, player = pcall(Ox.GetPlayer, playerId)
   return ok and player or nil
end

-- OX "inService" group (OX is not supported, the old branches only must not crash)
local function oxInService(playerId)
   local player = oxPlayer(playerId)
   if not player then return nil end
   local ok, value = pcall(function() return player.get("inService") end)
   if ok and type(value) == "table" then return value end
   return nil
end

-- Grade as integer (ESX numbers, QB string keys "0", Qbox integer keys), nil when invalid
local function toGrade(value)
   local number = tonumber(value)
   if not number or number ~= number or number < 0 or number > 1000 or number % 1 ~= 0 then return nil end
   return math.floor(number)
end

local function trim(value)
   return (tostring(value):gsub("^%s*(.-)%s*$", "%1"))
end

-- Cuts text to length characters (UTF-8 safe - Czech labels)
local function cutText(text, length)
   local count = utf8.len(text)
   if not count then return text:sub(1, length) end
   if count <= length then return text end
   return text:sub(1, utf8.offset(text, length + 1) - 1)
end

-- "Firstname Lastname", nil when both are empty
local function fullName(firstname, lastname)
   local name = trim(("%s %s"):format(firstname or "", lastname or ""))
   return name ~= "" and name or nil
end

-- QB / Qbox players.charinfo (JSON string or table) -> full name
local function charinfoName(charinfo)
   if type(charinfo) == "string" then
      local ok, decoded = pcall(json.decode, charinfo)
      charinfo = ok and decoded or nil
   end
   if type(charinfo) ~= "table" then return nil end
   return fullName(charinfo.firstname, charinfo.lastname)
end

-- oxmysql query which never throws (needs '@oxmysql/lib/MySQL.lua'), nil = no MySQL or error
local function sql(method, query, params)
   if not MySQL then return nil end
   local ok, result = pcall(function() return MySQL[method].await(query, params) end)
   if not ok then
      print(("^1[PLS_BRIDGE] SQL error: %s^0"):format(tostring(result)))
      return nil
   end
   return result
end

-- ESX
local function getESXPlayer(playerId)
   local ok, xPlayer = pcall(function() return Framework.GetPlayerFromId(playerId) end)
   return ok and type(xPlayer) == "table" and xPlayer or nil
end

-- ESX job { name, label, grades = { ["0"] = { grade, name, label, salary } } } (ESX.GetJobs, old ESX = database)
local function getEsxJob(jobName)
   local ok, jobs = pcall(function() return Framework.GetJobs() end)
   if ok and type(jobs) == "table" then return jobs[jobName] end
   local job = sql("single", 'SELECT name, label FROM jobs WHERE name = ? LIMIT 1', { jobName })
   if not job then return nil end
   job.grades = {}
   for _, row in ipairs(sql("query", 'SELECT grade, name, label, salary FROM job_grades WHERE job_name = ?', { jobName }) or {}) do
      job.grades[tostring(row.grade)] = row
   end
   return job
end

local function esxJobExists(jobName, grade)
   local ok, exists = pcall(function() return Framework.DoesJobExist(jobName, grade) end)
   if ok and type(exists) == "boolean" then return exists end
   local job = getEsxJob(jobName)
   return job ~= nil and type(job.grades) == "table" and job.grades[tostring(grade)] ~= nil
end

-- Online ESX players (xPlayers) with the job
local function getEsxJobPlayers(jobName)
   local ok, players = pcall(function() return Framework.GetExtendedPlayers('job', jobName) end)
   if ok and type(players) == "table" then return players end
   local list = {}
   for _, playerId in ipairs(GetPlayers()) do
      local xPlayer = getESXPlayer(tonumber(playerId))
      if xPlayer and xPlayer.job and xPlayer.job.name == jobName then
         list[#list + 1] = xPlayer
      end
   end
   return list
end

-- false = users table without firstname / lastname (ESX without esx_identity)
local EsxNameColumns = nil
local function esxHasNameColumns()
   if EsxNameColumns == nil then
      local count = sql("scalar", "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME IN ('firstname', 'lastname')")
      EsxNameColumns = (tonumber(count) or 0) >= 2
   end
   return EsxNameColumns
end

-- QB / Qbox
local function getQBPlayer(playerId)
   local ok, player = pcall(function()
      if BRIDGE.IsQbox then return exports.qbx_core:GetPlayer(playerId) end
      return Framework.Functions.GetPlayer(playerId)
   end)
   return ok and type(player) == "table" and type(player.PlayerData) == "table" and player or nil
end

local function getQBPlayerByCitizenId(citizenid)
   local ok, player = pcall(function()
      if BRIDGE.IsQbox then return exports.qbx_core:GetPlayerByCitizenId(citizenid) end
      return Framework.Functions.GetPlayerByCitizenId(citizenid)
   end)
   return ok and type(player) == "table" and type(player.PlayerData) == "table" and player or nil
end

-- Server ids of online QB players with the job (GetPlayersByJob matches the job type too, the caller checks the name)
local function getQBJobPlayerIds(jobName)
   local ok, players = pcall(function() return Framework.Functions.GetPlayersByJob(jobName) end)
   if ok and type(players) == "table" then return players end
   local list = {}
   for _, playerId in ipairs(GetPlayers()) do
      list[#list + 1] = tonumber(playerId)
   end
   return list
end

-- qb-core 1.3+ (May 2026) has GetShared export, older one only the core object copy (refreshed on QBCore:Server:UpdateObject)
local QBHasGetShared = nil

-- All QB jobs, fresh (Qbox GetJobs, qb-core GetShared, else core object)
local function getQBJobs()
   if BRIDGE.IsQbox then
      local ok, jobs = pcall(function() return exports.qbx_core:GetJobs() end)
      return ok and type(jobs) == "table" and jobs or {}
   end
   if QBHasGetShared ~= false then
      local ok, jobs = pcall(function() return exports['qb-core']:GetShared('Jobs') end)
      QBHasGetShared = ok
      if ok and type(jobs) == "table" then return jobs end
   end
   return Framework and Framework.Shared and Framework.Shared.Jobs or {}
end

-- QB job { label, defaultDuty, type, grades = { ["0"] (QB) / [0] (Qbox) = { name, payment, isboss } } } or nil
local function getQBJob(jobName)
   if type(jobName) ~= "string" then return nil end
   if BRIDGE.IsQbox then
      local ok, job = pcall(function() return exports.qbx_core:GetJob(jobName) end)
      return ok and type(job) == "table" and job or nil
   end
   if QBHasGetShared ~= false then
      local ok, job = pcall(function() return exports['qb-core']:GetShared('Jobs', jobName) end)
      QBHasGetShared = ok
      -- GetShared returns the whole namespace for an unknown job
      if ok then
         return type(job) == "table" and type(job.grades) == "table" and job or nil
      end
   end
   local jobs = Framework and Framework.Shared and Framework.Shared.Jobs
   return jobs and jobs[jobName] or nil
end

-- Grade data of QB job (string keys) or Qbox job (integer keys)
local function getQBGrade(job, grade)
   if type(job) ~= "table" or type(job.grades) ~= "table" or grade == nil then return nil end
   return job.grades[grade] or job.grades[tostring(grade)]
end


--[[
  _____  _                       _____        _        
 |  __ \| |                     |  __ \      | |       
 | |__) | | __ _ _   _  ___ _ __| |  | | __ _| |_ __ _ 
 |  ___/| |/ _` | | | |/ _ \ '__| |  | |/ _` | __/ _` |
 | |    | | (_| | |_| |  __/ |  | |__| | (_| | || (_| |
 |_|    |_|\__,_|\__, |\___|_|  |_____/ \__,_|\__\__,_|
                  __/ |                                
                 |___/                                                                                                                                                                                              
]]--

BRIDGE.GetPlayerData = function(playerId)
   local playerData = nil
   if BRIDGE.Framework == "ESX" then
      playerData = Framework.GetPlayerFromId(playerId)
   elseif BRIDGE.Framework == "QB" then
      playerData = Framework.Functions.GetPlayer(playerId)
   elseif BRIDGE.Framework == "OX" then
      playerData = oxPlayer(playerId)
   end
   return playerData
end 

BRIDGE.GetPlayerFullName = function(playerId)
   local playerData = nil
   local name = ""
   if BRIDGE.Framework == "ESX" then
      playerData = Framework.GetPlayerFromId(playerId)
      name = playerData.name
   elseif BRIDGE.Framework == "QB" then
      playerData = Framework.Functions.GetPlayer(playerId)
      name = playerData.PlayerData.charinfo.firstname.." "..playerData.PlayerData.charinfo.lastname
   end
   return name
end 


BRIDGE.GetPlayerBankMoney = function(playerId)
   local bankMoney = 0
   local player = nil
   if BRIDGE.Framework == "ESX" then
      player = Framework.GetPlayerFromId(playerId)
      bankMoney = player.getAccount("bank").money
   elseif BRIDGE.Framework == "QB" then
      local xPlayer = Framework.Functions.GetPlayer(playerId)
      bankMoney = xPlayer.PlayerData.money.bank
   end
   return bankMoney
end 

-- Returns true when the money was added
BRIDGE.AddPlayerBankMoney = function(playerId, count)
   local playerData = nil
   if BRIDGE.Framework == "ESX" then
      playerData = Framework.GetPlayerFromId(playerId)
      if not playerData then return false end
      playerData.addAccountMoney('bank', count)
      return true
   elseif BRIDGE.Framework == "QB" then
      playerData = Framework.Functions.GetPlayer(playerId)
      if not playerData then return false end
      return playerData.Functions.AddMoney('bank', count, 'Company payment') ~= false
   end
   return false
end 

-- Returns true when the money was removed (never below 0 – QB allows a negative bank by default)
BRIDGE.RemovePlayerBankMoney = function(playerId, count)
   local playerData = nil
   if BRIDGE.Framework == "ESX" then
      playerData = Framework.GetPlayerFromId(playerId)
      if not playerData then return false end
      local account = playerData.getAccount('bank')
      if not account or account.money < count then return false end
      playerData.removeAccountMoney('bank', count)
      return true
   elseif BRIDGE.Framework == "QB" then
      playerData = Framework.Functions.GetPlayer(playerId)
      if not playerData then return false end
      if (playerData.PlayerData.money['bank'] or 0) < count then return false end
      return playerData.Functions.RemoveMoney('bank', count, 'Buy vehicle') ~= false
   end
   return false
end 

--[[
   _____      _       _       _     
  / ____|    | |     | |     | |    
 | |  __  ___| |_    | | ___ | |__  
 | | |_ |/ _ \ __|   | |/ _ \| '_ \ 
 | |__| |  __/ || |__| | (_) | |_) |
  \_____|\___|\__\____/ \___/|_.__/                                                                                                                                                                     
]]--

BRIDGE.GetPlayerJob = function (playerId)
   local JobName = nil
   if BRIDGE.Framework == "ESX" then
       local PlayerData = Framework.GetPlayerFromId(playerId)
       JobName = PlayerData.job.name
   elseif BRIDGE.Framework == "QB" then
       local Player = Framework.Functions.GetPlayer(playerId)
       JobName = Player.PlayerData.job.name
   elseif BRIDGE.Framework == "OX" then
      local Job = oxInService(playerId)
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

BRIDGE.GetPlayerGrade = function (playerId)
   local JobGrade = nil
   if BRIDGE.Framework == "ESX" then
       local PlayerData = Framework.GetPlayerFromId(playerId)
       JobGrade = PlayerData.job.grade
   elseif BRIDGE.Framework == "QB" then
       local Player = Framework.Functions.GetPlayer(playerId)
       JobGrade = Player.PlayerData.job.grade.level
   elseif BRIDGE.Framework == "OX" then
      local Job = oxInService(playerId)
      JobGrade = Job and Job.grade
   end
   return JobGrade
end




--[[
   _____            _      _                                            
  / ____|          (_)    | |                                           
 | (___   ___   ___ _  ___| |_ _   _   _ __ ___   ___  _ __   ___ _   _ 
  \___ \ / _ \ / __| |/ _ \ __| | | | | '_ ` _ \ / _ \| '_ \ / _ \ | | |
  ____) | (_) | (__| |  __/ |_| |_| | | | | | | | (_) | | | |  __/ |_| |
 |_____/ \___/ \___|_|\___|\__|\__, | |_| |_| |_|\___/|_| |_|\___|\__, |
                                __/ |                              __/ |
                               |___/                              |___/                                      
                                                                                                                                                                                                            
]]--

-- ESX society account (esx_society + esx_addonaccount), callbacks run synchronously
local function getEsxSocietyAccount(jobName)
   local societyAccount = nil
   TriggerEvent('esx_society:getSociety', jobName, function (society)
      if society ~= nil then
         TriggerEvent('esx_addonaccount:getSharedAccount', society.account, function (account)
            societyAccount = account
         end)
      end
   end)
   if not societyAccount then
      TriggerEvent('esx_addonaccount:getSharedAccount', 'society_'..jobName, function (account)
         societyAccount = account
      end)
   end
   if not societyAccount and GetResourceState('esx_addonaccount') == 'started' then
      local ok, account = pcall(function() return exports['esx_addonaccount']:GetSharedAccount('society_'..jobName) end)
      if ok then societyAccount = account end
   end
   return societyAccount
end

-- QB: new qb-banking, Renewed-Banking (Qbox) or old qb-management
local function useQBBanking()
   return GetResourceState('qb-banking') == 'started'
end

-- Renewed-Banking provides the qb-management exports too, its own exports are used: they report a missing account
-- (false), and exports['qb-management'] keeps a dead function after a restart of Renewed-Banking (provide only)
local function useRenewedBanking()
   return not useQBBanking() and GetResourceState('Renewed-Banking') == 'started'
end

-- Name of the society account (ESX addon account = society_<job>, QB = job name)
BRIDGE.GetSocietyAccountName = function (jobName)
   if BRIDGE.Framework == "ESX" then
      return 'society_'..tostring(jobName)
   end
   return tostring(jobName)
end

local WarnedSocieties = {}
local function warnMissingSociety(jobName)
   if WarnedSocieties[jobName] then return end
   WarnedSocieties[jobName] = true
   if BRIDGE.Framework == "ESX" then
      print(("^1[PLS_BRIDGE] Society account '%s' not found. esx_addonaccount: %s, esx_society: %s. The account must be in addon_account table (shared = 1) and esx_addonaccount must be started before this resource.^0"):format(
         BRIDGE.GetSocietyAccountName(jobName), GetResourceState('esx_addonaccount'), GetResourceState('esx_society')))
   else
      print(("^1[PLS_BRIDGE] Society account of job '%s' not found. qb-banking: %s, Renewed-Banking: %s, qb-management: %s.^0"):format(
         jobName, GetResourceState('qb-banking'), GetResourceState('Renewed-Banking'), GetResourceState('qb-management')))
   end
end

-- true when society account of the job exists (money can be added / removed)
BRIDGE.HasSocietyAccount = function (jobName)
   if not jobName then return false end
   local exists = false
   if BRIDGE.Framework == "ESX" then
      exists = getEsxSocietyAccount(jobName) ~= nil
   elseif BRIDGE.Framework == "QB" then
      if useQBBanking() then
         local ok, account = pcall(function() return exports['qb-banking']:GetAccount(jobName) end)
         -- older qb-banking without GetAccount export: can't check, expect it exists
         exists = not ok or account ~= nil
      elseif useRenewedBanking() then
         -- getAccountMoney = balance of the job account, false when it doesn't exist
         local ok, money = pcall(function() return exports['Renewed-Banking']:getAccountMoney(jobName) end)
         exists = ok and tonumber(money) ~= nil
      else
         exists = GetResourceState('qb-management') == 'started'
      end
   end
   if not exists then warnMissingSociety(jobName) end
   return exists
end

-- Returns true when money was added
BRIDGE.AddSocietyMoney = function (jobName, money)
   if BRIDGE.Framework == "ESX" then
      local account = getEsxSocietyAccount(jobName)
      if account then
         account.addMoney(money)
         return true
      end
      warnMissingSociety(jobName)
   elseif BRIDGE.Framework == "QB" then
      local ok, result = pcall(function()
         if useQBBanking() then
            return exports['qb-banking']:AddMoney(jobName, money, 'Society payment')
         elseif useRenewedBanking() then
            return exports['Renewed-Banking']:addAccountMoney(jobName, money)
         end
         exports['qb-management']:AddMoney(jobName, money)
         return true
      end)
      if ok and result ~= false then return true end
      warnMissingSociety(jobName)
   elseif BRIDGE.Framework == "OX" then
      print("[PLS_BRIDGE] SOCIETY MONEY OX not support for now please change to your system. BRIDGE/server/framework.lua - AddSocietyMoney")
   end
   return false
end

BRIDGE.GetSocietyMoney = function (jobName)
   local money = 0
   if BRIDGE.Framework == "ESX" then
      local account = getEsxSocietyAccount(jobName)
      if account then
         money = account.money
      end
   elseif BRIDGE.Framework == "QB" then
      local ok, result = pcall(function()
         if useQBBanking() then
            return exports['qb-banking']:GetAccountBalance(jobName)
         elseif useRenewedBanking() then
            return exports['Renewed-Banking']:getAccountMoney(jobName)
         end
         return exports['qb-management']:GetAccount(jobName)
      end)
      if ok and result then
         money = tonumber(result) or 0
      end
   elseif BRIDGE.Framework == "OX" then
      print("[PLS_BRIDGE] SOCIETY MONEY OX not support for now please change to your system. BRIDGE/server/framework.lua - GetSocietyMoney")
   end
   return money
end

BRIDGE.RemoveSocietyMoney = function (jobName, money)
   if BRIDGE.GetSocietyMoney(jobName) < money then
      return false
   end
   if BRIDGE.Framework == "ESX" then
      local account = getEsxSocietyAccount(jobName)
      if account then
         account.removeMoney(money)
         return true
      end
   elseif BRIDGE.Framework == "QB" then
      -- result of the export, not only of the pcall (failed removal must never count as paid)
      local ok, result = pcall(function()
         if useQBBanking() then
            return exports['qb-banking']:RemoveMoney(jobName, money, 'Society payment')
         elseif useRenewedBanking() then
            return exports['Renewed-Banking']:removeAccountMoney(jobName, money)
         end
         return exports['qb-management']:RemoveMoney(jobName, money)
      end)
      return ok and result ~= false
   elseif BRIDGE.Framework == "OX" then
      print("[PLS_BRIDGE] SOCIETY MONEY OX not support for now please change to your system. BRIDGE/server/framework.lua - RemoveSocietyMoney")
   end
   return false
end


--[[
    Job grades - returns list {grade = number, label = string} sorted by grade + job label
]]--

BRIDGE.GetJobGrades = function (jobName)
   local grades = {}
   local jobLabel = jobName
   if BRIDGE.Framework == "ESX" then
      local jobs = Framework.GetJobs and Framework.GetJobs() or nil
      if jobs and jobs[jobName] then
         jobLabel = jobs[jobName].label or jobName
         for gradeKey, v in pairs(jobs[jobName].grades or {}) do
            table.insert(grades, { grade = tonumber(v.grade or gradeKey), label = v.label or v.name or tostring(gradeKey) })
         end
      elseif MySQL then
         local rows = MySQL.query.await('SELECT grade, label FROM job_grades WHERE job_name = ?', { jobName }) or {}
         for _, v in pairs(rows) do
            table.insert(grades, { grade = tonumber(v.grade), label = v.label })
         end
      end
   elseif BRIDGE.Framework == "QB" then
      local job = getQBJob(jobName)
      if job then
         jobLabel = job.label or jobName
         for gradeKey, v in pairs(job.grades or {}) do
            table.insert(grades, { grade = tonumber(gradeKey), label = v.name or tostring(gradeKey) })
         end
      end
   elseif BRIDGE.Framework == "OX" then
      local ok, group = pcall(function() return exports.ox_core:GetGroup(jobName) end)
      if ok and group then
         jobLabel = group.label or jobName
         for i, label in ipairs(group.grades or {}) do
            table.insert(grades, { grade = i, label = type(label) == "table" and (label.label or tostring(i)) or label })
         end
      end
   end
   table.sort(grades, function(a, b) return a.grade < b.grade end)
   return grades, jobLabel
end


--[[
    Owned vehicles - needs '@oxmysql/lib/MySQL.lua' before BRIDGE in server_scripts
]]--

local OwnedVehiclesTables = {
   ESX = { table = "owned_vehicles", props = "vehicle" },
   QB = { table = "player_vehicles", props = "mods" },
   OX = { table = "vehicles", props = nil },
}

local function trimPlate(plate)
   return (tostring(plate):gsub("^%s*(.-)%s*$", "%1"))
end

BRIDGE.IsVehicleOwned = function (plate)
   local data = OwnedVehiclesTables[BRIDGE.Framework]
   if not MySQL or not data or not plate then return false end
   local result = MySQL.scalar.await(('SELECT 1 FROM `%s` WHERE `plate` = ? OR `plate` = ? LIMIT 1'):format(data.table), { plate, trimPlate(plate) })
   return result ~= nil
end

-- Stored vehicle properties from garage table (table or nil)
BRIDGE.GetVehicleProperties = function (plate)
   local data = OwnedVehiclesTables[BRIDGE.Framework]
   if not MySQL or not data or not data.props or not plate then return nil end
   local stored = MySQL.scalar.await(('SELECT `%s` FROM `%s` WHERE `plate` = ? OR `plate` = ? LIMIT 1'):format(data.props, data.table), { plate, trimPlate(plate) })
   if type(stored) ~= "string" or stored == "" then return nil end
   local ok, props = pcall(json.decode, stored)
   return ok and type(props) == "table" and props or nil
end

BRIDGE.SaveVehicleProperties = function (plate, props)
   local data = OwnedVehiclesTables[BRIDGE.Framework]
   if not MySQL or not data or not plate then return false end
   if not data.props then
      print("[PLS_BRIDGE] SaveVehicleProperties is not supported for "..BRIDGE.Framework.." please change to your system. BRIDGE/server/framework.lua - SaveVehicleProperties")
      return false
   end
   local affected = MySQL.update.await(('UPDATE `%s` SET `%s` = ? WHERE `plate` = ? OR `plate` = ?'):format(data.table, data.props), { json.encode(props), plate, trimPlate(plate) })
   return affected and affected > 0
end




---- CHARID
BRIDGE.GetPlayerCharId = function (playerId)
   local identifier = nil
   if BRIDGE.Framework == "ESX" then
       local PlayerData = Framework.GetPlayerFromId(playerId)
       identifier = PlayerData.getIdentifier()
   elseif BRIDGE.Framework == "QB" then
       local Player = BRIDGE.GetPlayerData(playerId)
       identifier = Player.PlayerData.citizenid
   elseif BRIDGE.Framework == "OX" then
      local player = oxPlayer(playerId)
      identifier = player and player.charId
   end
   return identifier
end


--[[
   _____                _         _    _           _     _        _____ _                 
  / ____|              | |       | |  | |         | |   | |      |_   _| |                
 | |     _ __ ___  __ _| |_ ___  | |  | |___  __ _| |__ | | ___    | | | |_ ___ _ __ ___  
 | |    | '__/ _ \/ _` | __/ _ \ | |  | / __|/ _` | '_ \| |/ _ \   | | | __/ _ \ '_ ` _ \ 
 | |____| | |  __/ (_| | ||  __/ | |__| \__ \ (_| | |_) | |  __/  _| |_| ||  __/ | | | | |
  \_____|_|  \___|\__,_|\__\___|  \____/|___/\__,_|_.__/|_|\___| |_____|\__\___|_| |_| |_|
                                                                                          
                                                                                          
]]--


-- action = function(playerId) or client event name (string) - event gets {item = item}
local function useItem(action, playerId, item)
   if type(action) == "string" then
      TriggerClientEvent(action, playerId, {item = item})
   else
      action(playerId)
   end
end

BRIDGE.RegisterUsableItem = function(itemName, action)
   if BRIDGE.Framework == "ESX" then
      Framework.RegisterUsableItem(itemName, function(playerId, item)
         useItem(action, playerId, item)
      end)
   elseif BRIDGE.Framework == "QB" then
      Framework.Functions.CreateUseableItem(itemName, function(source, item)
         local Player = Framework.Functions.GetPlayer(source)
         if not Player.Functions.GetItemByName(item.name) then return end
         useItem(action, source, item)
      end)
   end
end


--[[
       _       _           _       _
      | |     | |         | |     | |
      | | ___ | |__     __| | __ _| |_ __ _
  _   | |/ _ \| '_ \   / _` |/ _` | __/ _` |
 | |__| | (_) | |_) | | (_| | (_| | || (_| |
  \____/ \___/|_.__/   \__,_|\__,_|\__\__,_|

 Job functions for boss menus (ESX 1.10+, QB old + 1.3 class based, Qbox). OX is not supported (nil / false).
 Grades are integers everywhere (ESX 0 based, QB string keys "0", Qbox integer keys).
 charId = BRIDGE.GetPlayerCharId format (ESX identifier, QB / Qbox citizenid).
 SQL functions need '@oxmysql/lib/MySQL.lua' before BRIDGE in server_scripts (nil without it).
]]--

-- { name, label, grade, gradeLabel, isBoss, onDuty } of the player's (primary) job, nil when not loaded.
-- onDuty = nil when the framework has no duty (ESX older than 1.11)
BRIDGE.GetPlayerJobData = function (playerId)
   if BRIDGE.Framework == "ESX" then
      local xPlayer = getESXPlayer(playerId)
      local job = xPlayer and xPlayer.job
      if type(job) ~= "table" or not job.name then return nil end
      local onDuty = nil
      if type(job.onDuty) == "boolean" then
         onDuty = job.onDuty
      end
      local grade = toGrade(job.grade) or 0
      return { name = job.name, label = job.label or job.name, grade = grade, gradeLabel = job.grade_label or tostring(grade), isBoss = job.grade_name == "boss", onDuty = onDuty }
   elseif BRIDGE.Framework == "QB" then
      local player = getQBPlayer(playerId)
      local job = player and player.PlayerData.job
      if type(job) ~= "table" or not job.name then return nil end
      local gradeData = type(job.grade) == "table" and job.grade or {}
      local grade = toGrade(gradeData.level) or 0
      local data = { name = job.name, label = job.label or job.name, grade = grade, gradeLabel = gradeData.name or tostring(grade), isBoss = job.isboss == true or gradeData.isboss == true, onDuty = job.onduty == true }
      -- the player keeps a copy of the grade, the shared job has grade edits made at runtime
      local shared = getQBGrade(getQBJob(job.name), grade)
      if type(shared) == "table" then
         data.gradeLabel = shared.name or data.gradeLabel
         data.isBoss = shared.isboss == true
      end
      return data
   end
   notSupported("GetPlayerJobData")
   return nil
end

-- Server id of the online character, nil when offline
BRIDGE.GetPlayerByCharId = function (charId)
   if charId == nil or charId == "" then return nil end
   if BRIDGE.Framework == "ESX" then
      -- ESX 1.11+ GetPlayerIdFromIdentifier, older GetPlayerFromIdentifier
      local ok, playerId = pcall(function() return Framework.GetPlayerIdFromIdentifier(charId) end)
      if ok then return tonumber(playerId) end
      local okPlayer, xPlayer = pcall(function() return Framework.GetPlayerFromIdentifier(charId) end)
      return okPlayer and type(xPlayer) == "table" and tonumber(xPlayer.source) or nil
   elseif BRIDGE.Framework == "QB" then
      local player = getQBPlayerByCitizenId(charId)
      return player and tonumber(player.PlayerData.source) or nil
   end
   notSupported("GetPlayerByCharId")
   return nil
end

-- Full name of the character (online player or database: ESX users.firstname / lastname, QB / Qbox players.charinfo), nil = unknown
BRIDGE.GetCharName = function (charId)
   if charId == nil or charId == "" then return nil end
   if BRIDGE.Framework ~= "ESX" and BRIDGE.Framework ~= "QB" then
      notSupported("GetCharName")
      return nil
   end
   local playerId = BRIDGE.GetPlayerByCharId(charId)
   if playerId then
      local ok, name = pcall(BRIDGE.GetPlayerFullName, playerId)
      if ok and type(name) == "string" and trim(name) ~= "" then return trim(name) end
   end
   if not MySQL then return nil end
   if BRIDGE.Framework == "ESX" then
      if not esxHasNameColumns() then return nil end
      local row = sql("single", 'SELECT firstname, lastname FROM users WHERE identifier = ? LIMIT 1', { charId })
      return row and fullName(row.firstname, row.lastname) or nil
   end
   return charinfoName(sql("scalar", 'SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { charId }))
end

-- All jobs of the framework { { name, label } } sorted by name
BRIDGE.GetAllJobs = function ()
   local jobs = nil
   if BRIDGE.Framework == "ESX" then
      local ok, result = pcall(function() return Framework.GetJobs() end)
      jobs = ok and type(result) == "table" and result or nil
      if not jobs then
         jobs = {}
         for _, row in ipairs(sql("query", 'SELECT name, label FROM jobs') or {}) do
            jobs[row.name] = row
         end
      end
   elseif BRIDGE.Framework == "QB" then
      jobs = getQBJobs()
   else
      notSupported("GetAllJobs")
      return {}
   end
   local list = {}
   for name, job in pairs(jobs) do
      if type(job) == "table" then
         list[#list + 1] = { name = tostring(name), label = job.label or tostring(name) }
      end
   end
   table.sort(list, function(a, b) return a.name < b.name end)
   return list
end

-- Names of all jobs of the framework { "mechanic", "police", ... } sorted
BRIDGE.GetJobList = function ()
   local names = {}
   for _, job in ipairs(BRIDGE.GetAllJobs()) do
      names[#names + 1] = job.name
   end
   return names
end

-- Normalized job { name, label, grades = { [grade] = { grade, label, salary, isBoss } } }
local function toJobInfo(jobName, job)
   if type(job) ~= "table" then return nil end
   local info = { name = jobName, label = job.label or jobName, grades = {} }
   for key, data in pairs(type(job.grades) == "table" and job.grades or {}) do
      local grade = type(data) == "table" and toGrade(data.grade or key) or nil
      if grade then
         if BRIDGE.Framework == "ESX" then
            -- ESX boss grade = job_grades.name 'boss' (esx_society)
            info.grades[grade] = { grade = grade, label = data.label or data.name or tostring(grade), salary = math.floor(tonumber(data.salary) or 0), isBoss = data.name == "boss" }
         else
            info.grades[grade] = { grade = grade, label = data.name or tostring(grade), salary = math.floor(tonumber(data.payment) or 0), isBoss = data.isboss == true }
         end
      end
   end
   return info
end

-- Job with grades (ESX jobs / job_grades, QB Shared.Jobs, Qbox GetJob), nil = job doesn't exist
BRIDGE.GetJobInfo = function (jobName)
   if type(jobName) ~= "string" or jobName == "" then return nil end
   if BRIDGE.Framework == "ESX" then
      return toJobInfo(jobName, getEsxJob(jobName))
   elseif BRIDGE.Framework == "QB" then
      return toJobInfo(jobName, getQBJob(jobName))
   end
   notSupported("GetJobInfo")
   return nil
end

-- Unemployed job of the framework (firing)
BRIDGE.GetUnemployedJob = function ()
   return "unemployed", 0
end


--[[
  __  __                _
 |  \/  |              | |
 | \  / | ___ _ __ ___ | |__   ___ _ __ ___
 | |\/| |/ _ \ '_ ` _ \| '_ \ / _ \ '__/ __|
 | |  | |  __/ | | | | | |_) |  __/ |  \__ \
 |_|  |_|\___|_| |_| |_|_.__/ \___|_|  |___/

 Members of a job incl. offline { { charId, name, grade } }, nil = not supported / database error.
 ESX     - online players + users WHERE job = ?
 QB      - online players + players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ? (online data is newer than the database)
 Qbox    - player_groups JOIN players, primary job only (players.job, qbx_core saves it at once - secondary jobs of multi job are not members)
]]--

BRIDGE.GetJobMembers = function (jobName)
   if type(jobName) ~= "string" or jobName == "" then return nil end
   if BRIDGE.Framework ~= "ESX" and BRIDGE.Framework ~= "QB" then
      notSupported("GetJobMembers")
      return nil
   end
   if not MySQL then return nil end
   local members, seen = {}, {}
   local function add(charId, name, grade)
      if charId == nil or seen[charId] then return end
      seen[charId] = true
      members[#members + 1] = { charId = charId, name = name or tostring(charId), grade = grade or 0 }
   end
   if BRIDGE.Framework == "ESX" then
      -- online players first, the job in memory is newer than the database
      for _, xPlayer in pairs(getEsxJobPlayers(jobName)) do
         if type(xPlayer) == "table" and xPlayer.job and xPlayer.job.name == jobName then
            add(xPlayer.identifier, xPlayer.name, toGrade(xPlayer.job.grade))
         end
      end
      local rows = nil
      if esxHasNameColumns() then
         rows = sql("query", 'SELECT identifier, firstname, lastname, job_grade FROM users WHERE job = ?', { jobName })
      else
         rows = sql("query", 'SELECT identifier, job_grade FROM users WHERE job = ?', { jobName })
      end
      if not rows then return nil end
      for _, row in ipairs(rows) do
         -- online with another job = the database row is old
         if not seen[row.identifier] and not BRIDGE.GetPlayerByCharId(row.identifier) then
            add(row.identifier, fullName(row.firstname, row.lastname), toGrade(row.job_grade))
         end
      end
   elseif BRIDGE.IsQbox then
      -- a secondary job of multi job is not a membership (the rest of the script uses the primary job only)
      local rows = sql("query", "SELECT pg.citizenid, pg.grade, p.charinfo FROM player_groups pg JOIN players p ON p.citizenid = pg.citizenid WHERE pg.`group` = ? AND pg.type = 'job' AND JSON_UNQUOTE(JSON_EXTRACT(p.job, '$.name')) = ?", { jobName, jobName })
      if not rows then return nil end
      for _, row in ipairs(rows) do
         add(row.citizenid, charinfoName(row.charinfo), toGrade(row.grade))
      end
   else
      for _, playerId in ipairs(getQBJobPlayerIds(jobName)) do
         local player = getQBPlayer(playerId)
         local data = player and player.PlayerData
         if data and type(data.job) == "table" and data.job.name == jobName then
            add(data.citizenid, charinfoName(data.charinfo), toGrade(type(data.job.grade) == "table" and data.job.grade.level))
         end
      end
      local rows = sql("query", "SELECT citizenid, charinfo, JSON_UNQUOTE(JSON_EXTRACT(job, '$.grade.level')) AS grade FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?", { jobName })
      if not rows then return nil end
      for _, row in ipairs(rows) do
         if not seen[row.citizenid] and not getQBPlayerByCitizenId(row.citizenid) then
            add(row.citizenid, charinfoName(row.charinfo), toGrade(row.grade))
         end
      end
   end
   return members
end


--[[
   _____      _       _       _
  / ____|    | |     (_)     | |
 | (___   ___| |_     _  ___ | |__
  \___ \ / _ \ __|   | |/ _ \| '_ \
  ____) |  __/ |_    | | (_) | |_) |
 |_____/ \___|\__|   | |\___/|_.__/
                    _/ |
                   |__/

 Returns ok, err (err = invalid_job / invalid_grade / player_not_found / not_found / job_changed / no_database / not_supported / failed).
 Job and grade are checked first: QB SetJob saves an invalid grade as "No Grades", ESX setJob only prints a warning.
 Firing = BRIDGE.GetUnemployedJob() ("unemployed", 0).
]]--

-- Qbox error result { code, message } -> string
local function qbxError(ok, result, errorResult)
   if not ok then return tostring(result) end
   if type(errorResult) == "table" then return errorResult.code or errorResult.message or "failed" end
   return "failed"
end

-- Qbox: true when the character has the job (primary or membership in player_groups), nil = character not found
local function qbxHasJob(citizenid, jobName)
   local player = getQBPlayerByCitizenId(citizenid)
   if not player then
      local ok, offline = pcall(function() return exports.qbx_core:GetOfflinePlayer(citizenid) end)
      player = ok and type(offline) == "table" and type(offline.PlayerData) == "table" and offline or nil
   end
   if not player then return nil end
   local data = player.PlayerData
   if type(data.job) == "table" and data.job.name == jobName then return true end
   return type(data.jobs) == "table" and data.jobs[jobName] ~= nil
end

-- Qbox: primary job + membership in player_groups (online and offline, citizenid)
-- playerData = PlayerData of the online or offline player, fromJob = job to fire from / change the grade in (optional)
local function qbxSetJob(playerData, jobName, grade, fromJob)
   local citizenid = playerData.citizenid
   local current = type(playerData.job) == "table" and playerData.job or {}
   local jobs = type(playerData.jobs) == "table" and playerData.jobs or {}
   local ok, success, errorResult
   if jobName == "unemployed" then
      local oldJob = fromJob or current.name
      -- primary job -> unemployed (fires the job events of online players)
      if current.name and current.name ~= "unemployed" and current.name == oldJob then
         ok, success, errorResult = pcall(function() return exports.qbx_core:SetJob(citizenid, "unemployed", 0) end)
         if not ok or not success then return false, qbxError(ok, success, errorResult) end
      end
      -- membership (SetJob keeps it with qbx:setjob_replaces false or for a secondary job)
      if oldJob and oldJob ~= "unemployed" then
         ok, success, errorResult = pcall(function() return exports.qbx_core:RemovePlayerFromJob(citizenid, oldJob) end)
         -- SetJob can remove the membership already (qbx:setjob_replaces): fired = the character doesn't have the job any more
         if (not ok or not success) and qbxHasJob(citizenid, oldJob) ~= false then
            return false, qbxError(ok, success, errorResult)
         end
      end
      return true
   end
   local sameJob = current.name == jobName
   if sameJob or (fromJob == jobName and jobs[jobName] ~= nil) then
      -- grade change of a held job, the primary job stays
      ok, success, errorResult = pcall(function() return exports.qbx_core:AddPlayerToJob(citizenid, jobName, grade) end)
   else
      ok, success, errorResult = pcall(function() return exports.qbx_core:SetJob(citizenid, jobName, grade) end)
   end
   if not ok or not success then return false, qbxError(ok, success, errorResult) end
   -- grade change keeps the duty state (qbx_core sets defaultDuty of the job)
   local oldGrade = type(current.grade) == "table" and toGrade(current.grade.level) or nil
   if playerData.source and sameJob and oldGrade ~= grade and type(current.onduty) == "boolean" then
      pcall(function() exports.qbx_core:SetJobDuty(playerData.source, current.onduty) end)
   end
   return true
end

-- Sets job of an online player
BRIDGE.SetPlayerJob = function (playerId, jobName, grade)
   grade = toGrade(grade)
   if type(jobName) ~= "string" or jobName == "" then return false, "invalid_job" end
   if not grade then return false, "invalid_grade" end
   if BRIDGE.Framework == "ESX" then
      if not esxJobExists(jobName, grade) then
         return false, getEsxJob(jobName) and "invalid_grade" or "invalid_job"
      end
      local xPlayer = getESXPlayer(playerId)
      if not xPlayer or type(xPlayer.job) ~= "table" then return false, "player_not_found" end
      -- grade change keeps the duty state (ESX 1.11+), a new job gets the default duty of ESX
      local onDuty = nil
      if xPlayer.job.name == jobName and type(xPlayer.job.onDuty) == "boolean" then
         onDuty = xPlayer.job.onDuty
      end
      local ok = pcall(function() xPlayer.setJob(jobName, grade, onDuty) end)
      if not ok then return false, "failed" end
   elseif BRIDGE.Framework == "QB" then
      local job = getQBJob(jobName)
      if not job then return false, "invalid_job" end
      if not getQBGrade(job, grade) then return false, "invalid_grade" end
      local player = getQBPlayer(playerId)
      if not player then return false, "player_not_found" end
      if BRIDGE.IsQbox then
         return qbxSetJob(player.PlayerData, jobName, grade, nil)
      end
      local current = type(player.PlayerData.job) == "table" and player.PlayerData.job or {}
      local ok, result = pcall(function() return player.Functions.SetJob(jobName, grade) end)
      if not ok or result == false then return false, "failed" end
      -- grade change keeps the duty state (SetJob sets defaultDuty of the job)
      if current.name == jobName and (current.onduty == true) ~= (job.defaultDuty == true) then
         pcall(function() player.Functions.SetJobDuty(current.onduty == true) end)
      end
   else
      notSupported("SetPlayerJob")
      return false, "not_supported"
   end
   -- read it again, the set functions don't report every failure
   local data = BRIDGE.GetPlayerJobData(playerId)
   if not data or data.name ~= jobName or data.grade ~= grade then return false, "failed" end
   return true
end

-- Online player with fromJob guard
local function setOnlineJob(playerId, jobName, grade, fromJob)
   if fromJob then
      local data = BRIDGE.GetPlayerJobData(playerId)
      if not data or data.name ~= fromJob then return false, "job_changed" end
   end
   return BRIDGE.SetPlayerJob(playerId, jobName, grade)
end

-- Sets job of a character, online or offline (online = SetPlayerJob).
-- fromJob (optional) = changes only when the character has this job now (fire / grade change of a member).
BRIDGE.SetOfflineJob = function (charId, jobName, grade, fromJob)
   grade = toGrade(grade)
   if charId == nil or charId == "" then return false, "not_found" end
   if type(jobName) ~= "string" or jobName == "" then return false, "invalid_job" end
   if not grade then return false, "invalid_grade" end
   if fromJob ~= nil and type(fromJob) ~= "string" then return false, "invalid_job" end
   if BRIDGE.Framework == "ESX" then
      local playerId = BRIDGE.GetPlayerByCharId(charId)
      if playerId then return setOnlineJob(playerId, jobName, grade, fromJob) end
      if not MySQL then return false, "no_database" end
      if not esxJobExists(jobName, grade) then
         return false, getEsxJob(jobName) and "invalid_grade" or "invalid_job"
      end
      local row = sql("single", 'SELECT job, job_grade FROM users WHERE identifier = ? LIMIT 1', { charId })
      if not row then return false, "not_found" end
      if fromJob and row.job ~= fromJob then return false, "job_changed" end
      if row.job == jobName and tonumber(row.job_grade) == grade then return true end
      -- AND job = ?: the row didn't change since it was read
      local affected = nil
      if row.job == nil then
         affected = sql("update", 'UPDATE users SET job = ?, job_grade = ? WHERE identifier = ? AND job IS NULL', { jobName, grade, charId })
      else
         affected = sql("update", 'UPDATE users SET job = ?, job_grade = ? WHERE identifier = ? AND job = ?', { jobName, grade, charId, row.job })
      end
      if not affected or affected < 1 then return false, "job_changed" end
   elseif BRIDGE.IsQbox then
      local job = getQBJob(jobName)
      if not job then return false, "invalid_job" end
      if not getQBGrade(job, grade) then return false, "invalid_grade" end
      local player = getQBPlayerByCitizenId(charId)
      if not player then
         local ok, offline = pcall(function() return exports.qbx_core:GetOfflinePlayer(charId) end)
         player = ok and type(offline) == "table" and type(offline.PlayerData) == "table" and offline or nil
      end
      if not player then return false, "not_found" end
      local data = player.PlayerData
      -- multi job: fromJob can be a secondary job
      if fromJob and (type(data.job) ~= "table" or data.job.name ~= fromJob) and (type(data.jobs) ~= "table" or data.jobs[fromJob] == nil) then
         return false, "job_changed"
      end
      return qbxSetJob(data, jobName, grade, fromJob)
   elseif BRIDGE.Framework == "QB" then
      local playerId = BRIDGE.GetPlayerByCharId(charId)
      if playerId then return setOnlineJob(playerId, jobName, grade, fromJob) end
      if not MySQL then return false, "no_database" end
      local job = getQBJob(jobName)
      if not job then return false, "invalid_job" end
      local gradeData = getQBGrade(job, grade)
      if not gradeData then return false, "invalid_grade" end
      -- only players.job: Save() of an offline player (qb-core 1.3) writes inventory = '[]' because it doesn't load items
      local raw = sql("scalar", 'SELECT job FROM players WHERE citizenid = ? LIMIT 1', { charId })
      if raw == nil then return false, "not_found" end
      local okJson, current = pcall(json.decode, raw)
      current = okJson and type(current) == "table" and current or {}
      local currentGrade = type(current.grade) == "table" and toGrade(current.grade.level) or nil
      if fromJob and current.name ~= fromJob then return false, "job_changed" end
      if current.name == jobName and currentGrade == grade then return true end
      -- same structure as Player.Functions.SetJob (qb-core validates it again on login)
      local onDuty = job.defaultDuty
      if current.name == jobName then
         onDuty = current.onduty
      end
      local newJob = {
         name = jobName,
         label = job.label or jobName,
         onduty = onDuty,
         type = job.type or 'none',
         isboss = gradeData.isboss or false,
         grade = { name = gradeData.name, level = grade, payment = gradeData.payment, isboss = gradeData.isboss or false },
      }
      -- job = ?: the row didn't change since it was read
      local affected = sql("update", 'UPDATE players SET job = ? WHERE citizenid = ? AND job = ?', { json.encode(newJob), charId, raw })
      if not affected or affected < 1 then return false, "job_changed" end
   else
      notSupported("SetOfflineJob")
      return false, "not_supported"
   end
   -- logged in meanwhile: the framework could load the old job
   local playerId = BRIDGE.GetPlayerByCharId(charId)
   if playerId then return BRIDGE.SetPlayerJob(playerId, jobName, grade) end
   return true
end


--[[
   _____               _
  / ____|             | |
 | |  __ _ __ __ _  __| | ___  ___
 | | |_ | '__/ _` |/ _` |/ _ \/ __|
 | |__| | | | (_| | (_| |  __/\__ \
  \_____|_|  \__,_|\__,_|\___||___/

 Grade edits. Returns ok, persisted, err
 ESX  - job_grades table + ESX.RefreshJob (1.15+) or ESX.RefreshJobs + setJob of online members, persisted = true
 QB   - exports['qb-core']:UpdateJob = runtime only, persisted = false (the script saves it and applies it again on start)
 Qbox - exports.qbx_core:UpsertJobGrade / RemoveJobGrade, persisted = BRIDGE.QboxSaveJobsToFile (see BRIDGE/config.lua)
]]--

-- ESX: job changed in the database -> ESX.Jobs + online members
local function refreshEsxJob(jobName)
   -- ESX 1.15+ refreshes online members too
   local ok = pcall(function() return Framework.RefreshJob(jobName) end)
   if ok then return end
   pcall(function() Framework.RefreshJobs() end)
   -- older ESX: online members keep the old grade data until setJob
   for _, xPlayer in pairs(getEsxJobPlayers(jobName)) do
      local job = type(xPlayer) == "table" and xPlayer.job or nil
      if job and esxJobExists(job.name, job.grade) then
         pcall(function() xPlayer.setJob(job.name, job.grade, job.onDuty) end)
      end
   end
end

-- ESX grade name (job_grades.name) from label: "Senior Mechanic" -> "senior_mechanic", 'boss' only for boss grades
local function esxGradeName(label, grade)
   local name = tostring(label or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
   if name == "" or name == "boss" then
      name = "grade_"..grade
   end
   return name:sub(1, 50)
end

-- QB: whole job back to qb-core, Qbox: UpsertJobGrade / RemoveJobGrade. data = nil removes the grade
local function saveQBGrade(jobName, job, grade, data)
   if BRIDGE.IsQbox then
      local commit = BRIDGE.QboxSaveJobsToFile == true
      local ok = pcall(function()
         if data then
            exports.qbx_core:UpsertJobGrade(jobName, grade, data, commit)
         else
            exports.qbx_core:RemoveJobGrade(jobName, grade, commit)
         end
      end)
      -- the exports return nothing, read the job again
      local saved = getQBGrade(getQBJob(jobName), grade)
      if not ok or (data ~= nil) ~= (saved ~= nil) then return false, false, "failed" end
      return true, commit
   end
   local updated = {}
   for key, value in pairs(job) do
      updated[key] = value
   end
   updated.grades = {}
   for key, value in pairs(type(job.grades) == "table" and job.grades or {}) do
      updated.grades[tostring(key)] = value
   end
   updated.grades[tostring(grade)] = data
   local ok, result = pcall(function() return exports['qb-core']:UpdateJob(jobName, updated) end)
   if not ok or result == false then return false, false, "failed" end
   -- old qb-core: own copy at once (QBCore:Server:UpdateObject refreshes it later)
   if Framework and Framework.Shared and type(Framework.Shared.Jobs) == "table" then
      Framework.Shared.Jobs[jobName] = updated
   end
   return true, false
end

-- changes = { label?, salary?, isBoss? }, create = true adds a missing grade
local function editGrade(jobName, grade, changes, create)
   grade = toGrade(grade)
   if type(jobName) ~= "string" or jobName == "" then return false, false, "invalid_job" end
   if not grade then return false, false, "invalid_grade" end
   if changes.salary ~= nil then
      local salary = tonumber(changes.salary)
      if not salary or salary ~= salary or salary < 0 or salary > 2147483647 then return false, false, "invalid_salary" end
      changes.salary = math.floor(salary)
   end
   if changes.label ~= nil then
      local label = type(changes.label) == "string" and cutText(trim(changes.label), 50) or ""
      if label == "" then return false, false, "invalid_label" end
      changes.label = label
   end
   if BRIDGE.Framework == "ESX" then
      if not MySQL then return false, false, "no_database" end
      if not sql("scalar", 'SELECT 1 FROM jobs WHERE name = ? LIMIT 1', { jobName }) then return false, false, "invalid_job" end
      local row = sql("single", 'SELECT id, name, label, salary FROM job_grades WHERE job_name = ? AND grade = ? LIMIT 1', { jobName, grade })
      if not row and not create then return false, false, "invalid_grade" end
      local label = changes.label or (row and row.label) or ("Grade "..grade)
      local salary = changes.salary or (row and math.floor(tonumber(row.salary) or 0)) or 0
      local name = row and row.name or esxGradeName(label, grade)
      if changes.isBoss == true then
         name = "boss"
      elseif changes.isBoss == false and name == "boss" then
         name = esxGradeName(label, grade)
      end
      local result = nil
      if row then
         result = sql("update", 'UPDATE job_grades SET name = ?, label = ?, salary = ? WHERE id = ?', { name, label, salary, row.id })
      else
         result = sql("insert", "INSERT INTO job_grades (job_name, grade, name, label, salary, skin_male, skin_female) VALUES (?, ?, ?, ?, ?, '{}', '{}')", { jobName, grade, name, label, salary })
      end
      if result == nil then return false, false, "failed" end
      refreshEsxJob(jobName)
      return true, true
   elseif BRIDGE.Framework == "QB" then
      local job = getQBJob(jobName)
      if not job then return false, false, "invalid_job" end
      local current = getQBGrade(job, grade)
      if not current and not create then return false, false, "invalid_grade" end
      -- copy keeps other fields of the grade (bankAuth...)
      local data = {}
      for key, value in pairs(type(current) == "table" and current or {}) do
         data[key] = value
      end
      data.name = changes.label or data.name or ("Grade "..grade)
      data.payment = changes.salary or math.floor(tonumber(data.payment) or 0)
      if changes.isBoss ~= nil then
         data.isboss = changes.isBoss == true or nil
      end
      return saveQBGrade(jobName, job, grade, data)
   end
   notSupported("Job grades")
   return false, false, "not_supported"
end

BRIDGE.SetGradeSalary = function (jobName, grade, salary)
   if salary == nil then return false, false, "invalid_salary" end
   return editGrade(jobName, grade, { salary = salary }, false)
end

BRIDGE.SetGradeLabel = function (jobName, grade, label)
   if label == nil then return false, false, "invalid_label" end
   return editGrade(jobName, grade, { label = label }, false)
end

-- data = { label?, salary?, isBoss? } - adds the grade or changes the given values
BRIDGE.UpsertJobGrade = function (jobName, grade, data)
   data = type(data) == "table" and data or {}
   return editGrade(jobName, grade, { label = data.label, salary = data.salary, isBoss = data.isBoss }, true)
end

-- Removes the grade (never the last one, the job would stop to exist). Move its members first.
BRIDGE.RemoveJobGrade = function (jobName, grade)
   grade = toGrade(grade)
   if type(jobName) ~= "string" or jobName == "" then return false, false, "invalid_job" end
   if not grade then return false, false, "invalid_grade" end
   if BRIDGE.Framework == "ESX" then
      if not MySQL then return false, false, "no_database" end
      local row = sql("single", 'SELECT id FROM job_grades WHERE job_name = ? AND grade = ? LIMIT 1', { jobName, grade })
      if not row then return false, false, "invalid_grade" end
      local count = tonumber(sql("scalar", 'SELECT COUNT(*) FROM job_grades WHERE job_name = ?', { jobName })) or 0
      if count <= 1 then return false, false, "last_grade" end
      if sql("update", 'DELETE FROM job_grades WHERE id = ?', { row.id }) == nil then return false, false, "failed" end
      refreshEsxJob(jobName)
      return true, true
   elseif BRIDGE.Framework == "QB" then
      local job = getQBJob(jobName)
      if not job then return false, false, "invalid_job" end
      if not getQBGrade(job, grade) then return false, false, "invalid_grade" end
      local count = 0
      for _ in pairs(job.grades) do
         count = count + 1
      end
      if count <= 1 then return false, false, "last_grade" end
      return saveQBGrade(jobName, job, grade, nil)
   end
   notSupported("RemoveJobGrade")
   return false, false, "not_supported"
end


--[[
  _____        _
 |  __ \      | |
 | |  | |_   _| |_ _   _
 | |  | | | | | __| | | |
 | |__| | |_| | |_| |_| |
 |_____/ \__,_|\__|\__, |
                    __/ |
                   |___/

 Duty of the framework. ESX 1.11+ (job.onDuty), QB SetJobDuty, Qbox exports.qbx_core:SetJobDuty
]]--

-- true / false, nil = not supported (ESX older than 1.11, OX)
BRIDGE.GetPlayerDuty = function (playerId)
   local data = BRIDGE.GetPlayerJobData(playerId)
   if not data then return nil end
   return data.onDuty
end

-- true when the duty is set, false = failed (no player, ESX keeps unemployed off duty), nil = not supported
BRIDGE.SetPlayerDuty = function (playerId, state)
   state = state == true
   if BRIDGE.Framework == "ESX" then
      local xPlayer = getESXPlayer(playerId)
      local job = xPlayer and xPlayer.job
      if type(job) ~= "table" then return false end
      if type(job.onDuty) ~= "boolean" then return nil end
      if job.onDuty == state then return true end
      if not pcall(function() xPlayer.setJob(job.name, job.grade, state) end) then return false end
   elseif BRIDGE.Framework == "QB" then
      local player = getQBPlayer(playerId)
      if not player or type(player.PlayerData.job) ~= "table" then return false end
      if (player.PlayerData.job.onduty == true) == state then return true end
      local ok = pcall(function()
         if BRIDGE.IsQbox then
            exports.qbx_core:SetJobDuty(playerId, state)
         else
            player.Functions.SetJobDuty(state)
         end
      end)
      if not ok then return false end
   else
      notSupported("SetPlayerDuty")
      return nil
   end
   return BRIDGE.GetPlayerDuty(playerId) == state
end


--[[
       _       _                            _
      | |     | |                          | |
      | | ___ | |__     _____   _____ _ __ | |_
  _   | |/ _ \| '_ \   / _ \ \ / / _ \ '_ \| __|
 | |__| | (_) | |_) | |  __/\ V /  __/ | | | |_
  \____/ \___/|_.__/   \___| \_/ \___|_| |_|\__|

 Local server event <resource>:jobChanged (playerId, job, grade, charId) after a real job / grade change of an online player
 (bossmenu, admin commands, other scripts). Sources: esx:setJob, QBCore:Server:OnJobUpdate, qbx_core:server:onGroupUpdate.
 Never a net event: only AddEventHandler, the job is read again from the framework (event data is not trusted)
 and compared with the last known one (duty changes don't fire it).
 Handlers: AddEventHandler(GetCurrentResourceName()..":jobChanged", function(playerId, job, grade, charId) ... end)
]]--

local LastJobs = {} -- [playerId] = "charId|job|grade"

-- lastJob (ESX only) = job before the change, a player seen for the first time with the same job doesn't fire it
local function checkJobChange(playerId, lastJob)
   -- a client can't trigger it (not registered for the network), the check stays for other scripts which register it
   local src = tonumber(source)
   if src and src > 0 then return end
   playerId = tonumber(playerId)
   if not playerId or playerId <= 0 then return end
   local ok, data = pcall(BRIDGE.GetPlayerJobData, playerId)
   if not ok or not data then return end
   local okId, charId = pcall(BRIDGE.GetPlayerCharId, playerId)
   charId = okId and charId or nil
   -- charId in the key: other character of the same player (multicharacter)
   local key = ("%s|%s|%s"):format(tostring(charId), data.name, data.grade)
   if LastJobs[playerId] == key then return end
   local firstSeen = LastJobs[playerId] == nil
   LastJobs[playerId] = key
   if firstSeen and type(lastJob) == "table" and lastJob.name == data.name and toGrade(lastJob.grade) == data.grade then return end
   TriggerEvent(GetCurrentResourceName()..":jobChanged", playerId, data.name, data.grade, charId)
end

if BRIDGE.Framework == "ESX" then
   AddEventHandler('esx:setJob', function(playerId, job, lastJob)
      checkJobChange(playerId, lastJob)
   end)
elseif BRIDGE.Framework == "QB" then
   -- old and new qb-core, Qbox fires it from SetPlayerPrimaryJob
   AddEventHandler('QBCore:Server:OnJobUpdate', function(playerId)
      checkJobChange(playerId)
   end)
   if BRIDGE.IsQbox then
      -- Qbox fires only this one when a player is removed from a job (grade = nil, fire).
      -- Added / changed grade of the primary job fires QBCore:Server:OnJobUpdate right after it.
      AddEventHandler('qbx_core:server:onGroupUpdate', function(playerId, groupName, grade)
         if grade ~= nil then return end
         checkJobChange(playerId)
      end)
   end
end

AddEventHandler('playerDropped', function()
   local src = tonumber(source)
   if src then
      LastJobs[src] = nil
   end
end)


--[[
  _                             _
 | |                           | |
 | |     ___   __ _  ___  _   _| |_
 | |    / _ \ / _` |/ _ \| | | | __|
 | |___| (_) | (_| | (_) | |_| | |_
 |______\___/ \__, |\___/ \__,_|\__|
               __/ |
              |___/

 Local server event <resource>:playerUnloaded (playerId) when the player logs out to the character select (still connected).
 Sources: esx:playerLogout (ESX), QBCore:Server:OnPlayerUnload (QB, not on drop), qbx_core:server:playerLoggedOut (Qbox).
 Never a net event: only AddEventHandler. ESX / QB fire it before the character is removed, the framework can still return
 the old character in the handler - treat the player as logged out until <resource>:playerLoaded of the next character.
 Handlers: AddEventHandler(GetCurrentResourceName()..":playerUnloaded", function(playerId) ... end)
]]--

local function playerUnloaded(playerId)
   -- a client can't trigger it (not registered for the network), the check stays for other scripts which register it
   if isSpoofedPlayerLoaded(playerId) then return end
   playerId = tonumber(playerId)
   if not playerId or playerId <= 0 then return end
   -- the next character (or the same one again) is compared from scratch
   LastJobs[playerId] = nil
   TriggerEvent(GetCurrentResourceName()..":playerUnloaded", playerId)
end

if BRIDGE.Framework == "ESX" then
   AddEventHandler('esx:playerLogout', function(playerId)
      playerUnloaded(playerId)
   end)
elseif BRIDGE.IsQbox then
   -- Qbox fires QBCore:Server:OnPlayerUnload too (same logout), only this one is used
   AddEventHandler('qbx_core:server:playerLoggedOut', function(playerId)
      playerUnloaded(playerId)
   end)
elseif BRIDGE.Framework == "QB" then
   -- qb-core fires OnPlayerUnload on drop too, right after QBCore:Server:PlayerDropped (a drop is not a logout)
   local Dropping = nil
   AddEventHandler('QBCore:Server:PlayerDropped', function(player)
      local src = tonumber(source)
      if src and src > 0 then return end
      Dropping = type(player) == "table" and type(player.PlayerData) == "table" and tonumber(player.PlayerData.source) or tonumber(player)
   end)
   AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerId)
      local dropping = Dropping ~= nil and Dropping == tonumber(playerId)
      Dropping = nil
      if dropping then return end
      playerUnloaded(playerId)
   end)
end

