--[[
   _____      _                 _                       _   
  / ____|    | |               | |                     | |  
 | (___   ___| |_ _   _ _ __   | |_ __ _ _ __ __ _  ___| |_ 
  \___ \ / _ \ __| | | | '_ \  | __/ _` | '__/ _` |/ _ \ __|
  ____) |  __/ |_| |_| | |_) | | || (_| | | | (_| |  __/ |_ 
 |_____/ \___|\__|\__,_| .__/   \__\__,_|_|  \__, |\___|\__|
                       | |                    __/ |         
                       |_|                   |___/          
]]--


local Target = nil
local ActionsModels = {}
local Actions = {}
local Entities = {}

if BRIDGE.Target  == "ox_target" then
    Target = exports.ox_target
end

if BRIDGE.Target == "qb_target" then
    Target = exports['qb-target']
end

local function DrawText3D(x, y, z, text)
	SetTextScale(0.35, 0.35)
	SetTextFont(4)
	SetTextProportional(1)
	SetTextColour(255, 255, 255, 215)
	SetTextEntry("STRING")
	SetTextCentre(true)
	AddTextComponentString(text)
	SetDrawOrigin(x,y,z, 0)
	DrawText(0.0, 0.0)
	local factor = (string.len(text)) / 370
	DrawRect(0.0, 0.0+0.0125, 0.017+ factor, 0.03, 0, 0, 0, 75)
	ClearDrawOrigin()
end

local function AddAction(data)
    data.id = math.random(1,99999)
    table.insert(Actions, data)
    return data.id
end
local function RemoveAction(id)
    for i, action in pairs(Actions) do
        if action.id == id then
            table.remove(Actions, i)
            return true
        end
    end
    return false
end

local function AddEntity(entity, data)
    local values = {
        id = math.random(1,99999),
        entity = entity,
        options = data,
    }
    table.insert(Entities, values)
    return values.id
end
local function RemoveEntity(id)
    for i, action in pairs(Entities) do
        if action.id == id then
            table.remove(Entities, i)
            return true
        end
    end
    return false
end
--[[
              _     _  _____ _                   ______                
     /\      | |   | |/ ____| |                 |___  /                
    /  \   __| | __| | (___ | |__   ___ _ __ ___   / / ___  _ __   ___ 
   / /\ \ / _` |/ _` |\___ \| '_ \ / _ \ '__/ _ \ / / / _ \| '_ \ / _ \
  / ____ \ (_| | (_| |____) | | | |  __/ | |  __// /_| (_) | | | |  __/
 /_/    \_\__,_|\__,_|_____/|_| |_|\___|_|  \___/_____\___/|_| |_|\___|
                                                                       
                                                                                                                
]]--

local function ox_to_qb_target_convert(targetData)
    local new_options = {}
    for i, v in pairs(targetData) do 
        if v then
            local option = {}
            if not v.distance then v.distance = 5 end
            option = {
                num = i,
                type="client",
                label = v.label,
                targeticon = v.icon,
                action = v.onSelect,
                canInteract = v.canInteract,
                job = v.groups,
                drawDistance = v.distance

            }
            table.insert(new_options, option)
        end
    end
    return new_options
end

BRIDGE.AddSphereTarget = function(data)
    local targetID = nil
    if BRIDGE.UseMarkers then
        targetID = AddAction(data)
    else
        if BRIDGE.Target == "ox_target" then
            targetID = Target:addSphereZone(data)
        elseif BRIDGE.Target == "qb_target" then
            targetID = "pls_target"..math.random(1,99).."_"..math.random(1,999)
            if not data.radius then data.radius = 1.5 end
            Target:AddCircleZone(targetID,data.coords, data.radius, {
            name = targetID,
            debugPoly = false, 
            }, {
            options = ox_to_qb_target_convert(data.options),
            distance = 2.5, 
            })
        end
    end
    return targetID
end

--[[
  _____                                _____       _                   ______                
 |  __ \                              / ____|     | |                 |___  /                
 | |__) |___ _ __ ___   _____   _____| (___  _ __ | |__   ___ _ __ ___   / / ___  _ __   ___ 
 |  _  // _ \ '_ ` _ \ / _ \ \ / / _ \\___ \| '_ \| '_ \ / _ \ '__/ _ \ / / / _ \| '_ \ / _ \
 | | \ \  __/ | | | | | (_) \ V /  __/____) | |_) | | | |  __/ | |  __// /_| (_) | | | |  __/
 |_|  \_\___|_| |_| |_|\___/ \_/ \___|_____/| .__/|_| |_|\___|_|  \___/_____\___/|_| |_|\___|
                                            | |                                              
                                            |_|                                                                                                                                                                                 
]]--

BRIDGE.RemoveSphereTarget = function(id)
    if BRIDGE.UseMarkers then
        RemoveAction(id)
    else
        if BRIDGE.Target == "ox_target" then
            Target:removeZone(id)
            return true
        elseif BRIDGE.Target == "qb_target" then
            Target:RemoveZone(id)
            return true
        end
    end
    return false
end

--[[
              _     _ __  __           _      _ 
     /\      | |   | |  \/  |         | |    | |
    /  \   __| | __| | \  / | ___   __| | ___| |
   / /\ \ / _` |/ _` | |\/| |/ _ \ / _` |/ _ \ |
  / ____ \ (_| | (_| | |  | | (_) | (_| |  __/ |
 /_/    \_\__,_|\__,_|_|  |_|\___/ \__,_|\___|_|
                                                
                                                
]]--

BRIDGE.AddModelTarget = function(models, targetData)
    local targetID = nil
    if BRIDGE.UseMarkers then
        for _, v in pairs(models) do 
            local newTData = {
                model = v,
                data = targetData
            }
            table.insert(ActionsModels, newTData) 
        end
    else
        if BRIDGE.Target == "ox_target" then
            targetID = Target:addModel(models, targetData)
        elseif BRIDGE.Target == "qb_target" then
            targetID = Target:AddTargetModel(models, {
                options = ox_to_qb_target_convert(targetData),
                distance = 2.5, 
            })
        end
    end
    return targetID
end

--[[
    Add Global Vehicle - target on all vehicles
    Options use ox_target format (label, icon, bones, canInteract, onSelect).
    ox_target: bones works per option
    qb_target: options with bones use AddTargetBone, others AddGlobalVehicle
    UseMarkers: keypress (BRIDGE.VehicleInteractKey) opens menu for closest vehicle
    Returns id for RemoveGlobalVehicleTarget
]]--

local VehicleActions = {}
local VehicleKeybind = nil

local function openVehicleActionsMenu()
    local coords = GetEntityCoords(cache.ped)
    local vehicle = lib.getClosestVehicle(coords, 3.5, false)
    if not vehicle then return end
    local distance = #(coords - GetEntityCoords(vehicle))
    local newOptions = {}
    for _, group in pairs(VehicleActions) do
        for _, v in pairs(group.options) do
            local allowInteract = true
            if v.canInteract then
                allowInteract = v.canInteract(vehicle, distance, coords, v.name)
            end
            if allowInteract then
                table.insert(newOptions, {
                    title = v.label,
                    icon = v.icon,
                    onSelect = function()
                        if BRIDGE.Target == "ox_target" then
                            v.onSelect({entity = vehicle})
                        else
                            v.onSelect(vehicle)
                        end
                    end
                })
            end
        end
    end
    if #newOptions == 0 then return end
    lib.registerContext({
        id = 'dynamic_menu_target_vehicle',
        title = 'Vehicle',
        options = newOptions
    })
    lib.showContext('dynamic_menu_target_vehicle')
end

BRIDGE.AddGlobalVehicleTarget = function(targetData)
    local targetID = {}
    if BRIDGE.UseMarkers then
        targetID = "pls_vehicle_"..math.random(1,99999)
        VehicleActions[targetID] = { options = targetData }
        if not VehicleKeybind then
            VehicleKeybind = lib.addKeybind({
                name = GetCurrentResourceName()..'_vehicle_interact',
                description = 'Vehicle interaction',
                defaultKey = BRIDGE.VehicleInteractKey or 'G',
                onPressed = openVehicleActionsMenu,
            })
        end
        return targetID
    end
    if BRIDGE.Target == "ox_target" then
        for _, v in pairs(targetData) do
            if not v.name then v.name = "pls_target"..math.random(1,99).."_"..math.random(1,99999) end
            table.insert(targetID, v.name)
        end
        Target:addGlobalVehicle(targetData)
    elseif BRIDGE.Target == "qb_target" then
        local withoutBones = {}
        for _, v in pairs(targetData) do
            if v.bones then
                local bones = type(v.bones) == "table" and v.bones or { v.bones }
                Target:AddTargetBone(bones, {
                    options = ox_to_qb_target_convert({ v }),
                    distance = 2.5,
                })
                table.insert(targetID, { bones = bones, label = v.label })
            else
                table.insert(withoutBones, v)
                table.insert(targetID, v.label)
            end
        end
        if #withoutBones > 0 then
            Target:AddGlobalVehicle({
                options = ox_to_qb_target_convert(withoutBones),
                distance = 2.5,
            })
        end
    end
    return targetID
end

BRIDGE.RemoveGlobalVehicleTarget = function(id)
    if BRIDGE.UseMarkers then
        VehicleActions[id] = nil
        return true
    end
    if BRIDGE.Target == "ox_target" then
        Target:removeGlobalVehicle(id)
        return true
    elseif BRIDGE.Target == "qb_target" then
        local labels = {}
        for _, v in pairs(id) do
            if type(v) == "table" then
                Target:RemoveTargetBone(v.bones, v.label)
            else
                table.insert(labels, v)
            end
        end
        if #labels > 0 then
            Target:RemoveGlobalVehicle(labels)
        end
        return true
    end
    return false
end



local function generateMenuByOptions(options)
    local newOptions = {}
    for _, v in pairs(options) do
        local new_option = {
            title = v.label,
            icon = v.icon,
            onSelect = function()
                local allowInteract = true
                if allowInteract then
                    v.onSelect()
                end
            end
        }
        table.insert(newOptions, new_option)
    end
    lib.registerContext({
        id = 'dynamic_menu_target',
        title = 'Action',
        options = newOptions
      })
    lib.showContext('dynamic_menu_target')
end


CreateThread(function()
    if BRIDGE.UseMarkers then
        while true do
            local coords = GetEntityCoords(PlayerPedId())
            local waitConfig = 5000
            local isClose = false
            local lastDistance = 100.0
            local lastCoords = vector3(0,0,0)
            local options = {}
            for _, v in pairs(Actions) do 
                if #(coords - v.coords)  < 50.0 then
                    isClose = true
                    if #(coords - v.coords) < lastDistance then
                        lastDistance = #(coords - v.coords)
                        lastCoords = v.coords
                        options = v.options
                    end
                end
                if isClose then waitConfig = 0 else  waitConfig = 5000 end
            end
            if #(coords - lastCoords) < 10.0 then
                DrawMarker(25, lastCoords.x, lastCoords.y, lastCoords.z-1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 1, 18, 43, 90, false, false, 2, nil, nil, false)
                if BRIDGE.UseDrawText then
                    DrawText3D(lastCoords.x, lastCoords.y, lastCoords.z+0.5, BRIDGE.DrawText)
                end
                if IsControlJustPressed(1, 38) then -- E
                    if #(coords - lastCoords) < 2.5 then
                        generateMenuByOptions(options)
                    end
                end
            end 
            Wait(waitConfig)
        end
    end
end)

local function generateMenuByOptionsForModel(entity, options)
    local newOptions = {}
    for _, v in pairs(options) do
        local new_option = {
            title = v.label,
            icon = v.icon,
            onSelect = function()
                local allowInteract = true
                if allowInteract then
                    local respon = nil
                    if BRIDGE.Target == "ox_target" then
                        respon = {entity = tonumber(entity)}
                    else
                        respon = tonumber(entity)
                    end
                    v.onSelect(respon)
                end
            end
        }
        table.insert(newOptions, new_option)
    end
    lib.registerContext({
        id = 'dynamic_menu_target_model',
        title = 'Action',
        options = newOptions
      })
    lib.showContext('dynamic_menu_target_model')
end


CreateThread(function()
    if BRIDGE.AllowModelTargetToKeypress then
        while true do
            local coords = GetEntityCoords(PlayerPedId())
            local waitConfig = 5000
            local isClose = false
            local lastDistance = 100.0
            local lastCoords = vector3(0,0,0)
            local options = {}
            local searched_model_entity = nil
            for _, v in pairs(ActionsModels) do 
                local searched_model = GetClosestObjectOfType(
                coords.x, 
                coords.y, 
                coords.z, 
                20.0, 
                joaat(v.model), 
                false, 
                true, 
                false
                )
                if searched_model ~= 0 then
                    local entityCoords = GetEntityCoords(searched_model)
                    if #(coords - entityCoords)  < 50.0 then
                        isClose = true
                        if #(coords - entityCoords) < lastDistance then
                            lastDistance = #(coords - entityCoords)
                            lastCoords = entityCoords
                            options = v.data
                            searched_model_entity = searched_model
                        end
                    end
                    if isClose then waitConfig = 0 else  waitConfig = 5000 end
                end
            end
            if #(coords - lastCoords) < 3.0 then
                DrawMarker(25, lastCoords.x, lastCoords.y, lastCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 1, 18, 43, 90, false, false, 2, nil, nil, false)
                if BRIDGE.UseDrawText then
                    DrawText3D(lastCoords.x, lastCoords.y, lastCoords.z+0.5, BRIDGE.DrawText)
                end
                if IsControlJustPressed(1, 38) then -- E
                    if #(coords - lastCoords) < 2.5 then
                        generateMenuByOptionsForModel(searched_model_entity, options)
                    end
                end
            end 
            Wait(waitConfig)
        end
    end
end)

--[[
  ___      _     _   _____      _   _ _         
 / _ \    | |   | | |  ___|    | | (_) |        
/ /_\ \ __| | __| | | |__ _ __ | |_ _| |_ _   _ 
|  _  |/ _` |/ _` | |  __| '_ \| __| | __| | | |
| | | | (_| | (_| | | |__| | | | |_| | |_| |_| |
\_| |_/\__,_|\__,_| \____/_| |_|\__|_|\__|\__, |
                                           __/ |
                                          |___/ 
]]--


BRIDGE.AddEntityTarget = function(entity, targetData)
    local targetID = nil
    if BRIDGE.UseMarkers then
       AddEntity(entity, targetData)
    else
        if BRIDGE.Target == "ox_target" then
            targetID = Target:addLocalEntity(entity, targetData)
        elseif BRIDGE.Target == "qb_target" then
            targetID = Target:AddTargetEntity(entity, {
                options = ox_to_qb_target_convert(targetData),
                distance = 2.5, 
            })
        end
    end
    return targetID
end


CreateThread(function()
    if BRIDGE.UseMarkers then
        while true do
            local coords = GetEntityCoords(cache.ped)
            local waitConfig = 5000
            local isClose = false
            local lastDistance = 100.0
            local lastCoords = vector3(0,0,0)
            local options = {}
            for _, entity in pairs(Entities) do 
                local entityCoords = GetEntityCoords(entity.entity)
                    if #(coords - entityCoords)  < 50.0 then
                        isClose = true
                        if #(coords - entityCoords) < lastDistance then
                            lastDistance = #(coords - entityCoords)
                            lastCoords = entityCoords
                            options = entity.options
                            searched_model_entity = entity.entity
                        end
                    end
                    if isClose then waitConfig = 0 else  waitConfig = 5000 end
            end
            if #(coords - lastCoords) < 3.0 then
                DrawMarker(25, lastCoords.x, lastCoords.y, lastCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 1, 18, 43, 90, false, false, 2, nil, nil, false)
                if BRIDGE.UseDrawText then
                    DrawText3D(lastCoords.x, lastCoords.y, lastCoords.z+0.5, BRIDGE.DrawText)
                end
                if IsControlJustPressed(1, 38) then -- E
                    if #(coords - lastCoords) < 2.5 then
                        print("Done")
                        generateMenuByOptions(options)
                    end
                end
            end 
            Wait(waitConfig)
        end
    end
end)