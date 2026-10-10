--[[

  ____       _     _                               __ _       
 |  _ \     (_)   | |                             / _(_)      
 | |_) |_ __ _  __| | __ _  ___    ___ ___  _ __ | |_ _  __ _ 
 |  _ <| '__| |/ _` |/ _` |/ _ \  / __/ _ \| '_ \|  _| |/ _` |
 | |_) | |  | | (_| | (_| |  __/ | (_| (_) | | | | | | | (_| |
 |____/|_|  |_|\__,_|\__, |\___|  \___\___/|_| |_|_| |_|\__, |
                      __/ |                              __/ |
                     |___/                              |___/ 

]]--

local IS_SERVER = IsDuplicityVersion()

lib.locale()

BRIDGE = {}

BRIDGE.Framework = "ESX" -- ESX / QB / OX
-- Automatic detection - overrides line above when framework resource is started
if GetResourceState("es_extended") == "started" then BRIDGE.Framework = "ESX" elseif GetResourceState("qb-core") == "started" or GetResourceState("qbx_core") == "started" then BRIDGE.Framework = "QB" elseif GetResourceState("ox_core") == "started" then BRIDGE.Framework = "OX" end

-- Qbox (qbx_core) provides qb-core, so BRIDGE.Framework stays "QB". Job functions use qbx_core exports where they differ.
BRIDGE.IsQbox = BRIDGE.Framework == "QB" and GetResourceState("qbx_core") == "started"
-- Qbox only: grade edits from scripts (boss menu) are saved by qbx_core into qbx_core/shared/jobs.lua.
-- qbx_core rewrites the whole file and loses the job "type" (police = 'leo', ambulance = 'ems') and comments, keep false.
-- With false the script keeps the edits in its own database and applies them again on every start.
BRIDGE.QboxSaveJobsToFile = false

-- Supports inventory
-- ox_inventory  - https://github.com/overextended/ox_inventory
-- qb_inventory -  https://docs.qbcore.org/qbcore-documentation/
-- quasar_inventory - https://docs.quasar-store.com/assets-and-guides/inventory
-- codem - codem-inventory
-- core - core_inventory (only stashes)

BRIDGE.Inventory = "ox_inventory" -- ox_inventory, qb_inventory, quasar_inventory, codem, core

BRIDGE.ESXOld = false -- Change on true when you use old version of ESX

BRIDGE.Target = "ox_target"  -- ox_target / qb_target
BRIDGE.UseMarkers = false -- This is for some script where u dont want use target! But not all scripts supports this.
BRIDGE.AllowModelTargetToKeypress = false -- This is allow replace target for model with markers. UseMarkers must be true
BRIDGE.UseDrawText = false -- Enables 3D text if you are not using a target.
BRIDGE.DrawText = "[ E ]" -- Guess what
BRIDGE.VehicleInteractKey = "G" -- Key for vehicle interaction menu when UseMarkers = true (vehicle targets)

-- This is created for pls_keycards and pls_hiddenstashes FUCK THIS in other scripts.
BRIDGE.QBStashesReplaceByPLS = true -- This is replace qb-inventory stashes.

--[[ 
  _________                                        .__    .___      
 /   _____/ ______________  __ ___________    _____|__| __| _/____  
 \_____  \_/ __ \_  __ \  \/ // __ \_  __ \  /  ___/  |/ __ |/ __ \ 
 /        \  ___/|  | \/\   /\  ___/|  | \/  \___ \|  / /_/ \  ___/ 
/_______  /\___  >__|    \_/  \___  >__|    /____  >__\____ |\___  >
        \/     \/                 \/             \/        \/    \/ 
]]--

if IS_SERVER then
    BRIDGE.Notify =  function(playerId, notifyData)
        -- notifyData.title = NOTIFY TITLE
        -- notifyData.description = NOTIFY DESCRIPTION
        -- notifyData.type = NOTIFY TYPE  | TYPES: success, inform, error
        lib.notify(playerId, notifyData)
    end
end


--[[
_________ .__  .__               __           .__    .___      
\_   ___ \|  | |__| ____   _____/  |_    _____|__| __| _/____  
/    \  \/|  | |  |/ __ \ /    \   __\  /  ___/  |/ __ |/ __ \ 
\     \___|  |_|  \  ___/|   |  \  |    \___ \|  / /_/ \  ___/ 
 \______  /____/__|\___  >___|  /__|   /____  >__\____ |\___  >
        \/             \/     \/            \/        \/    \/ 
]]--

if not IS_SERVER then
    BRIDGE.Notify = function(notifyData)
        -- notifyData.title = NOTIFY TITLE
        -- notifyData.description = NOTIFY DESCRIPTION
        -- notifyData.type = NOTIFY TYPE  | TYPES: success, inform, error
        lib.notify(notifyData)
    end
end