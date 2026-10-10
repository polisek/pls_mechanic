--[[
   _____                   _
  / ____|                 | |
 | (___  _   _ _ __  _ __ | |_   _
  \___ \| | | | '_ \| '_ \| | | | |
  ____) | |_| | |_) | |_) | | |_| |
 |_____/ \__,_| .__/| .__/|_|\__, |
              | |   | |       __/ |
              |_|   |_|      |___/
 Supplier window (NUI "supplier"), supply runs with a van, orders log in workshop settings.
 Crates are carried by hand: from the supplier's pile to the rear of the van (rear doors open),
 from the van to the workshop supply point (stacked there). A crate taken out of any van is carried too.
]]--

Supply = {}

local RunCfg = Config.Supplier.run
local KEY_ACTION = 38         -- E
local DoorBones = { [0] = "door_dside_f", [1] = "door_pside_f", [2] = "door_dside_r", [3] = "door_pside_r", [4] = "bonnet", [5] = "boot" }

local CurrentShopId = nil     -- workshop of opened supplier window
local ActiveRun = nil         -- { id, shopId, netId, plate, crates, loaded, stage = "pickup"|"deliver", pickup = {x,y,z,w}, pickupLabel, timeLimit }
local RunBlip = nil
local RunTarget = nil
local RunPile = nil
local VanBlip = nil            -- blip on the van of the active run (so the runner uses the right one)
local VehicleTarget = nil
local AwaitingCounts = GlobalState.pls_mechanic_supply or {}
local Busy = false
local CrateCarry = nil         -- { handle } crate carried after taking it out of a van
local Stack = {}               -- crates put down at the workshop supply point (visual)
local StackToken = 0
local Hint = nil               -- text UI of the carry session

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

local function notifyResult(result, successType)
    if result and result.message then
        Core.Notify(result.message, result.ok and (successType or "success") or "error")
    end
end

-- Workshop of opened settings window (shops module), payload shopId as fallback
local function getSettingsShopId(data)
    local shopId = Settings and Settings.GetShopId and Settings.GetShopId()
    return tonumber(shopId) or (type(data) == "table" and tonumber(data.shopId)) or nil
end

local function getSupplyPoint(shopId)
    local shop = Core.GetShop(shopId)
    for _, point in pairs(shop and shop.points or {}) do
        if point.type == "supply" then
            return point
        end
    end
    return nil
end

local function removeBlip()
    if RunBlip and DoesBlipExist(RunBlip) then
        RemoveBlip(RunBlip)
    end
    RunBlip = nil
end

local function setRouteBlip(coords, labelKey)
    removeBlip()
    RunBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(RunBlip, RunCfg.blip.sprite)
    SetBlipColour(RunBlip, RunCfg.blip.color)
    SetBlipScale(RunBlip, RunCfg.blip.scale)
    SetBlipRoute(RunBlip, true)
    SetBlipRouteColour(RunBlip, RunCfg.blip.color)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(locale(labelKey))
    EndTextCommandSetBlipName(RunBlip)
    SetNewWaypoint(coords.x, coords.y)
end

local function removePickup()
    if RunTarget then
        BRIDGE.RemoveSphereTarget(RunTarget)
        RunTarget = nil
    end
    if RunPile and DoesEntityExist(RunPile) then
        DeleteEntity(RunPile)
    end
    RunPile = nil
end

local function clearRun()
    removePickup()
    removeBlip()
    if VanBlip and DoesBlipExist(VanBlip) then
        RemoveBlip(VanBlip)
    end
    VanBlip = nil
    ActiveRun = nil
end

local function getRunVehicle()
    if not ActiveRun or not ActiveRun.netId then return nil end
    if not NetworkDoesEntityExistWithNetworkId(ActiveRun.netId) then return nil end
    local vehicle = NetToVeh(ActiveRun.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

local function spawnPile(coords, heading)
    if not RunCfg.pileProp then return end
    local model = joaat(RunCfg.pileProp)
    if not IsModelValid(model) then return end
    lib.requestModel(model)
    RunPile = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(RunPile, heading + 0.0)
    PlaceObjectOnGroundProperly(RunPile)
    FreezeEntityPosition(RunPile, true)
    SetModelAsNoLongerNeeded(model)
end

-- Supply van of workshop with crates near coords
local function findCargoVan(shopId, coords)
    local closest, closestDistance = nil, RunCfg.vanDistance
    for _, vehicle in pairs(GetGamePool("CVehicle")) do
        local distance = #(GetEntityCoords(vehicle) - coords)
        if distance <= closestDistance then
            local state = Entity(vehicle).state.pls_supply
            if state and state.shopId == shopId and (state.crates or 0) > 0 then
                closest, closestDistance = vehicle, distance
            end
        end
    end
    return closest
end

-- Mechanic menu action, repair workflow, tuning installation, another library phase or a DLC scene is running
local function otherWorkRunning()
    if (Menu and Menu.IsBusy and Menu.IsBusy()) or (Tuning and Tuning.IsInstalling and Tuning.IsInstalling())
        or (Repair and Repair.IsBusy and Repair.IsBusy()) or Anim.IsBusy() or Core.IsExternalBusy() then
        Core.Notify(locale("repair_busy"), "error")
        return true
    end
    return false
end

local function setCancel(fn)
    if Menu and Menu.SetCancelHandler then
        Menu.SetCancelHandler(fn)
    end
end

-- Text UI of the carry session, shown again only when the text changes
local function showHint(text)
    if text == Hint then return end
    Hint = text
    if text then
        lib.showTextUI(text)
    else
        lib.hideTextUI()
    end
end

--[[
   _____
  / ____|
 | |     _ __ __ _| |_ ___  ___
 | |    | '__/ _` | __/ _ \/ __|
 | |____| | | (_| | ||  __/\__ \
  \_____|_|  \__,_|\__\___||___/
]]--

-- Loading spot behind the rear doors of the van, heading towards the van
local function vanRear(vehicle)
    local min = GetModelDimensions(GetEntityModel(vehicle))
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, min.y - 0.7, 0.0), GetEntityHeading(vehicle)
end

-- Opens the doors at the rear end of the van. Returns the opened doors
local function openVanDoors(vehicle)
    local opened = {}
    local min = GetModelDimensions(GetEntityModel(vehicle))
    for _, door in ipairs(RunCfg.vanDoors or { 2, 3, 5 }) do
        local bone = DoorBones[door] and GetEntityBoneIndexByName(vehicle, DoorBones[door]) or -1
        if bone ~= -1 then
            local world = GetWorldPositionOfEntityBone(vehicle, bone)
            local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
            if offset.y < min.y * 0.5 and Anim.OpenDoor(vehicle, door) then
                table.insert(opened, door)
            end
        end
    end
    return opened
end

local function closeVanDoors(vehicle, doors)
    if not DoesEntityExist(vehicle) then return end
    for _, door in ipairs(doors or {}) do
        Anim.CloseDoor(vehicle, door)
    end
end

-- Stack slot next to the supply point (3 x 2 grid)
local function stackSlot(point, index)
    local slot = (index - 1) % math.max(1, RunCfg.stackSize or 6)
    local column, row = slot % 3, math.floor(slot / 3)
    local heading = math.rad(point.heading or 0.0)
    local x, y = (column - 1) * 0.55, row * 0.55
    local base = Utils.Vec3(point.coords)
    -- rotate the grid by the point heading
    local worldX = base.x + x * math.cos(heading) - y * math.sin(heading)
    local worldY = base.y + x * math.sin(heading) + y * math.cos(heading)
    return vector3(worldX, worldY, base.z)
end

local function clearStack()
    StackToken = StackToken + 1
    for _, object in ipairs(Stack) do
        Anim.DeleteProp(object)
    end
    Stack = {}
end

-- Crate put down at the supply point: oldest one goes when the stack is full, all go after stackTime
local function addToStack(object)
    if not object then return end
    table.insert(Stack, object)
    while #Stack > math.max(1, RunCfg.stackSize or 6) do
        Anim.DeleteProp(table.remove(Stack, 1))
    end
    StackToken = StackToken + 1
    local token = StackToken
    SetTimeout((RunCfg.stackTime or 60) * 1000, function()
        if StackToken == token then clearStack() end
    end)
end

local function stopCrateCarry()
    if not CrateCarry then return end
    local carry = CrateCarry
    CrateCarry = nil
    Anim.StopCarry(carry.handle)
    showHint(nil)
end

-- Crate taken out of a van stays in the hands until it is put away (E), the player gets into a vehicle,
-- falls or the crate item is gone (it is in the inventory already)
local function startCrateCarry()
    stopCrateCarry()
    local handle = Anim.Carry(RunCfg.crate)
    if not handle then return end
    local carry = { handle = handle }
    CrateCarry = carry
    CreateThread(function()
        local nextCheck = 0
        while CrateCarry == carry do
            showHint(locale("supply_hint_stow"))
            if IsControlJustPressed(0, KEY_ACTION) or cache.vehicle or IsPedRagdoll(cache.ped) or IsPedDeadOrDying(cache.ped, true) then
                break
            end
            local now = GetGameTimer()
            if now > nextCheck then
                nextCheck = now + 1000
                -- crate gone from the inventory or the carry was replaced by another animation
                if Core.CountItem("supply_crate") < 1 or not DoesEntityExist(handle.object) then break end
            end
            Wait(0)
        end
        if CrateCarry == carry then
            stopCrateCarry()
        end
    end)
end

--[[
  _____
 |  __ \
 | |__) |   _ _ __
 |  _  / | | | '_ \
 | | \ \ |_| | | | |
 |_|  \_\__,_|_| |_|
]]--

local function showDelivery()
    removePickup()
    local point = ActiveRun and getSupplyPoint(ActiveRun.shopId)
    if point then
        setRouteBlip(Utils.Vec3(point.coords), "supply_blip_delivery")
    else
        removeBlip()
    end
end

local function showPickup()
    removePickup()
    local pickup = ActiveRun.pickup
    local coords = vector3(pickup.x, pickup.y, pickup.z)
    setRouteBlip(coords, "supply_blip_pickup")
    RunTarget = BRIDGE.AddSphereTarget({
        coords = coords,
        radius = 2.0,
        options = {
            {
                name = "pls_mechanic_supply_load",
                icon = "fa-solid fa-boxes-stacked",
                label = locale("supply_target_load"),
                distance = 3.0,
                canInteract = function()
                    return ActiveRun ~= nil and ActiveRun.stage == "pickup" and not Busy and not cache.vehicle
                end,
                onSelect = function()
                    CreateThread(Supply.LoadCrates)
                end,
            },
        },
    })
    -- crate pile is spawned only when player comes close (collision must be loaded)
    local runId = ActiveRun.id
    CreateThread(function()
        while ActiveRun and ActiveRun.id == runId and ActiveRun.stage == "pickup" do
            if not RunPile and #(GetEntityCoords(cache.ped) - coords) < 80.0 then
                spawnPile(coords, pickup.w or 0.0)
            end
            Wait(1000)
        end
    end)
end

local function setupRun(run)
    clearRun()
    ActiveRun = run
    CreateThread(function()
        local deadline = GetGameTimer() + 10000
        while not NetworkDoesEntityExistWithNetworkId(run.netId) and GetGameTimer() < deadline do
            Wait(100)
        end
        local vehicle = getRunVehicle()
        if not vehicle then return end
        if ActiveRun == run and not VanBlip then
            VanBlip = AddBlipForEntity(vehicle)
            SetBlipSprite(VanBlip, 67)
            SetBlipColour(VanBlip, 5)
            SetBlipScale(VanBlip, 0.85)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(locale("supply_van_blip", run.plate or ""))
            EndTextCommandSetBlipName(VanBlip)
        end
        if Core.RequestControl(vehicle, 2000) then
            SetVehicleNumberPlateText(vehicle, run.plate)
        end
        local ok, err = pcall(Config.SetFuel, vehicle, 100.0)
        if not ok then print("[pls_mechanic] Config.SetFuel error: "..tostring(err)) end
        ok, err = pcall(Config.GiveKeys, vehicle, run.plate)
        if not ok then print("[pls_mechanic] Config.GiveKeys error: "..tostring(err)) end
    end)
    if run.stage == "deliver" then
        showDelivery()
    else
        showPickup()
    end
end

--[[
  _____       _     _ _
 |  __ \     | |   | (_)
 | |__) |   _| |__ | |_  ___
 |  ___/ | | | '_ \| | |/ __|
 | |   | |_| | |_) | | | (__
 |_|    \__,_|_.__/|_|_|\___|
]]--

-- Opens supplier window of workshop (default = duty workshop)
function Supply.OpenCatalog(shopId)
    CreateThread(function()
        shopId = shopId or Core.GetMyShopId()
        if not shopId then
            Core.Notify(locale("not_on_duty"), "error")
            return
        end
        if not Core.HasPermission("order", shopId) then
            Core.Notify(locale("no_permission"), "error")
            return
        end
        local result = lib.callback.await("pls_mechanic:server:supply:get", false, shopId)
        if not result or not result.ok then
            notifyResult(result)
            return
        end
        CurrentShopId = shopId
        Core.Nui.Open("supplier", result.data)
    end)
end

function Supply.GetAwaitingCount(shopId)
    return tonumber(AwaitingCounts[tostring(shopId)]) or 0
end

-- Active supply run of this player (read only) or nil
function Supply.GetActiveRun()
    return ActiveRun
end

function Supply.StartRun(shop, point)
    if Busy then return end
    if ActiveRun then
        Core.Notify(locale("supply_run_active"), "error")
        return
    end
    Busy = true
    local result = lib.callback.await("pls_mechanic:server:supply:startRun", false, shop.id, point.id)
    Busy = false
    if not result or not result.ok then
        notifyResult(result)
        return
    end
    setupRun(result.run)
    Core.Notify(result.message, "success")
end

function Supply.CancelRun()
    if not ActiveRun or Busy then return end
    local answer = lib.alertDialog({
        header = locale("supply_cancel_confirm_title"),
        content = locale("supply_cancel_confirm"),
        centered = true,
        cancel = true,
    })
    if answer ~= "confirm" then return end
    local result = lib.callback.await("pls_mechanic:server:supply:cancelRun", false)
    if result and result.ok then
        clearRun()
    end
    notifyResult(result, "inform")
end

-- Pickup: crates carried one by one from the supplier's pile into the van (van must be parked nearby)
function Supply.LoadCrates()
    if Busy or not ActiveRun or ActiveRun.stage ~= "pickup" then return end
    local pickup = vector3(ActiveRun.pickup.x, ActiveRun.pickup.y, ActiveRun.pickup.z)
    local vehicle = getRunVehicle()
    if not vehicle then
        -- another vehicle (e.g. service van from garage) is not the van of this run
        Core.Notify(locale("supply_van_not_here", ActiveRun.plate or "?"), "error")
        return
    end
    if #(GetEntityCoords(vehicle) - pickup) > RunCfg.vanDistance then
        Core.Notify(locale("supply_van_too_far", ActiveRun.plate or "?", math.floor(RunCfg.vanDistance)), "error")
        return
    end
    if otherWorkRunning() then return end
    stopCrateCarry()
    Busy = true
    local cancelled = false
    local isCancelled = function() return cancelled end
    setCancel(function() cancelled = true end)
    local doors = openVanDoors(vehicle)
    local takeDuration = math.floor(RunCfg.loadDuration * 0.4)
    local putDuration = RunCfg.loadDuration - takeDuration
    local cancelKey = Config.Keys.cancel
    local carry = nil

    while not cancelled and ActiveRun and ActiveRun.stage == "pickup" do
        if cache.vehicle or IsPedDeadOrDying(cache.ped, true) or not DoesEntityExist(vehicle) then break end
        local coords = GetEntityCoords(cache.ped)
        if #(coords - pickup) > 35.0 then break end
        local rear, rearHeading = vanRear(vehicle)
        local run = ActiveRun
        if carry then
            if #(coords.xy - rear.xy) <= RunCfg.carryDistance then
                showHint(locale("supply_hint_put_van", cancelKey))
                if IsControlJustPressed(0, KEY_ACTION) then
                    showHint(nil)
                    Anim.WalkTo(rear, rearHeading, 2000, isCancelled)
                    local done = Anim.Phase({
                        label = locale("supply_loading", run.loaded + 1, run.crates),
                        duration = putDuration,
                        anim = RunCfg.anims.load,
                        prop = RunCfg.crate,
                        cancel = isCancelled,
                    })
                    carry = nil
                    if not done then break end
                    local result = lib.callback.await("pls_mechanic:server:supply:load", false)
                    if not result or not result.ok then
                        notifyResult(result)
                        break
                    end
                    if not ActiveRun then break end
                    ActiveRun.loaded = result.loaded
                    if result.done then
                        ActiveRun.stage = "deliver"
                        Core.Notify(locale("supply_loaded_all"), "success")
                        showDelivery()
                    end
                end
            else
                showHint(locale("supply_hint_carry_van", cancelKey))
            end
        elseif #(coords.xy - pickup.xy) <= RunCfg.carryDistance + 1.0 then
            showHint(locale("supply_hint_take_pile", run.loaded, run.crates, cancelKey))
            if IsControlJustPressed(0, KEY_ACTION) then
                showHint(nil)
                Anim.Face(pickup)
                local done = Anim.Phase({
                    label = locale("supply_taking_pile"),
                    duration = takeDuration,
                    anim = RunCfg.anims.lift,
                    prop = RunCfg.crate,
                    cancel = isCancelled,
                })
                if not done then break end
                carry = Anim.Carry(RunCfg.crate)
            end
        else
            showHint(locale("supply_hint_back_pile", run.loaded, run.crates, cancelKey))
        end
        Wait(0)
    end

    showHint(nil)
    if carry then
        Anim.StopCarry(carry)
    end
    setCancel(nil)
    closeVanDoors(vehicle, doors)
    if cancelled then
        Core.Notify(locale("supply_loading_paused"), "inform")
    end
    Busy = false
end

-- Unloading at the workshop: crates carried from the rear of the van to the supply point.
-- Returns unloaded crates, completed, stopped
local function unloadVan(shop, point, vehicle)
    local coords = Utils.Vec3(point.coords)
    local cancelled = false
    local isCancelled = function() return cancelled end
    setCancel(function() cancelled = true end)
    local doors = openVanDoors(vehicle)
    local takeDuration = math.floor(RunCfg.unloadDuration * 0.8)
    local cancelKey = Config.Keys.cancel
    local carry = nil
    local unloaded, completed, stopped = 0, false, false
    local lastResult = nil

    while not cancelled do
        if cache.vehicle or IsPedDeadOrDying(cache.ped, true) or not DoesEntityExist(vehicle) then
            stopped = true
            break
        end
        local state = Entity(vehicle).state.pls_supply
        local remaining = state and state.crates or 0
        if remaining < 1 and not carry then break end
        local pos = GetEntityCoords(cache.ped)
        if #(pos - coords) > 30.0 then
            stopped = true
            break
        end
        local rear, rearHeading = vanRear(vehicle)
        if carry then
            if #(pos.xy - coords.xy) <= RunCfg.carryDistance + 1.0 then
                showHint(locale("supply_hint_put_point", cancelKey))
                if IsControlJustPressed(0, KEY_ACTION) then
                    showHint(nil)
                    local slot = stackSlot(point, #Stack + 1)
                    addToStack(Anim.PutDown(nil, slot, (point.heading or 0.0) + math.random(-12, 12)))
                    carry = nil
                    if cancelled then break end
                    local result = lib.callback.await("pls_mechanic:server:supply:unload", false, shop.id, point.id, VehToNet(vehicle))
                    if not result or not result.ok then
                        notifyResult(result)
                        stopped = true
                        break
                    end
                    unloaded = unloaded + 1
                    lastResult = result
                    if result.completed then
                        completed = true
                        break
                    end
                end
            else
                showHint(locale("supply_hint_carry_point", cancelKey))
            end
        elseif #(pos.xy - rear.xy) <= RunCfg.carryDistance then
            showHint(locale("supply_hint_take_van", remaining, cancelKey))
            if IsControlJustPressed(0, KEY_ACTION) then
                showHint(nil)
                Anim.WalkTo(rear, rearHeading, 2000, isCancelled)
                local done = Anim.Phase({
                    label = locale("supply_unloading", remaining),
                    duration = takeDuration,
                    anim = RunCfg.anims.lift,
                    prop = RunCfg.crate,
                    cancel = isCancelled,
                })
                if not done then break end
                carry = Anim.Carry(RunCfg.crate)
            end
        else
            showHint(locale("supply_hint_back_van", remaining, cancelKey))
        end
        Wait(0)
    end

    showHint(nil)
    if carry then
        Anim.StopCarry(carry)
    end
    setCancel(nil)
    closeVanDoors(vehicle, doors)
    if cancelled then
        stopped = true
        Core.Notify(locale("cancelled"), "error")
    end
    if unloaded > 0 and not completed and lastResult then
        Core.Notify(locale("supply_unloaded_progress", unloaded, lastResult.delivered, lastResult.crates), "inform")
    end
    return unloaded, completed, stopped
end

-- Workshop supply point: unload crates from nearby supply van, then hand over carried crate items
function Supply.Deliver(shop, point)
    if Busy then return end
    if otherWorkRunning() then return end
    Busy = true
    local coords = Utils.Vec3(point.coords)
    local handled, stopped, completed = false, false, false

    local vehicle = findCargoVan(shop.id, coords)
    if vehicle and not CrateCarry then
        local unloaded
        unloaded, completed, stopped = unloadVan(shop, point, vehicle)
        handled = unloaded > 0 or stopped
    end

    -- crate items in the inventory (taken out of a van / recovered after theft) are put down at the point
    if not stopped and not completed and Core.CountItem("supply_crate") > 0 then
        local carried = CrateCarry ~= nil
        if carried then
            CrateCarry = nil
            showHint(nil)
        end
        local slot = stackSlot(point, #Stack + 1)
        local object = Anim.PutDown(not carried and RunCfg.crate or nil, slot, point.heading or 0.0)
        if object then
            addToStack(object)
            local result = lib.callback.await("pls_mechanic:server:supply:deliverItems", false, shop.id, point.id)
            if not (result and result.ok and result.completed) then
                notifyResult(result)
            end
        else
            Core.Notify(locale("cancelled"), "error")
        end
        handled = true
    end

    if not handled then
        Core.Notify(locale("supply_nothing_to_deliver"), "error")
    end
    Busy = false
end

-- Takes one crate out of a supply van (manual carry / theft), the crate stays in the hands
function Supply.TakeCrate(vehicle)
    if Busy or not vehicle or not DoesEntityExist(vehicle) then return end
    if otherWorkRunning() then return end
    Busy = true
    stopCrateCarry()
    local cancelled = false
    local isCancelled = function() return cancelled end
    setCancel(function() cancelled = true end)
    local rear, heading = vanRear(vehicle)
    Anim.WalkTo(rear, heading, 3000, isCancelled)
    local doors = not cancelled and openVanDoors(vehicle) or {}
    local done = not cancelled and Anim.Phase({
        label = locale("supply_taking_crate"),
        duration = RunCfg.takeDuration,
        anim = RunCfg.anims.lift,
        prop = RunCfg.crate,
        cancel = isCancelled,
    })
    setCancel(nil)
    local took = false
    if done then
        local result = lib.callback.await("pls_mechanic:server:supply:takeCrate", false, VehToNet(vehicle))
        notifyResult(result)
        took = result and result.ok
    else
        Core.Notify(locale("cancelled"), "error")
    end
    closeVanDoors(vehicle, doors)
    if took then
        startCrateCarry()
    end
    Busy = false
end

--[[
  _   _ _    _ _____
 | \ | | |  | |_   _|
 |  \| | |  | | | |
 | . ` | |  | | | |
 | |\  | |__| |_| |_
 |_| \_|\____/|_____|
]]--

RegisterNUICallback("supplier:order", function(data, cb)
    if not CurrentShopId or type(data) ~= "table" then
        cb({ ok = false, message = locale("no_permission") })
        return
    end
    local result = lib.callback.await("pls_mechanic:server:supply:order", false, CurrentShopId, data.mode, data.items)
    cb(result or { ok = false, message = locale("supply_invalid_order") })
end)

RegisterNUICallback("supplier:refresh", function(_, cb)
    if not CurrentShopId then
        cb({})
        return
    end
    local result = lib.callback.await("pls_mechanic:server:supply:get", false, CurrentShopId)
    cb(result and result.ok and result.data or {})
end)

RegisterNUICallback("settings:orders", function(data, cb)
    local shopId = getSettingsShopId(data)
    local result = shopId and lib.callback.await("pls_mechanic:server:supply:orders", false, shopId, type(data) == "table" and data.page or 1)
    cb(result or { orders = {}, pages = 1 })
end)

Core.Nui.OnClose("supplier", function()
    CurrentShopId = nil
end)

--[[
                 _   _
     /\         | | (_)
    /  \   ___| |_ _  ___  _ __  ___
   / /\ \ / __| __| |/ _ \| '_ \/ __|
  / ____ \ (__| |_| | (_) | | | \__ \
 /_/    \_\___|\__|_|\___/|_| |_|___/
]]--

ShopPoints.RegisterAction("computer", {
    label = locale("supply_action_catalog"),
    icon = "fa-solid fa-truck-fast",
    perm = "order",
    onSelect = function(shop)
        Supply.OpenCatalog(shop.id)
    end,
})

ShopPoints.RegisterAction("computer", {
    label = locale("supply_action_start_run"),
    icon = "fa-solid fa-truck-ramp-box",
    perm = "supply_run",
    canInteract = function(shop)
        return ActiveRun == nil and Supply.GetAwaitingCount(shop.id) > 0
    end,
    onSelect = function(shop, point)
        Supply.StartRun(shop, point)
    end,
})

ShopPoints.RegisterAction("computer", {
    label = locale("supply_action_cancel_run"),
    icon = "fa-solid fa-ban",
    perm = "supply_run",
    canInteract = function(shop)
        return ActiveRun ~= nil and ActiveRun.shopId == shop.id
    end,
    onSelect = function()
        Supply.CancelRun()
    end,
})

ShopPoints.RegisterAction("supply", {
    label = locale("supply_action_deliver"),
    icon = "fa-solid fa-dolly",
    perm = "supply_run",
    onSelect = function(shop, point)
        Supply.Deliver(shop, point)
    end,
})

--[[
  ______               _
 |  ____|             | |
 | |____   _____ _ __ | |_ ___
 |  __\ \ / / _ \ '_ \| __/ __|
 | |___\ V /  __/ | | | |_\__ \
 |______\_/ \___|_| |_|\__|___/
]]--

AddStateBagChangeHandler("pls_mechanic_supply", "global", function(_, _, value)
    AwaitingCounts = value or {}
end)

RegisterNetEvent("pls_mechanic:client:supply:runEnded", function(runId)
    if ActiveRun and ActiveRun.id == runId then
        clearRun()
    end
end)

-- Crates can be taken out of any unlocked supply van
CreateThread(function()
    VehicleTarget = BRIDGE.AddGlobalVehicleTarget({
        {
            name = "pls_mechanic_supply_take",
            icon = "fa-solid fa-box",
            label = locale("supply_target_take_crate"),
            distance = 2.5,
            canInteract = function(entity)
                if Busy or CrateCarry or cache.vehicle or not entity or entity == 0 then return false end
                local state = Entity(entity).state.pls_supply
                return state ~= nil and (state.crates or 0) > 0 and GetVehicleDoorLockStatus(entity) <= 1
            end,
            onSelect = function(data)
                local entity = type(data) == "table" and data.entity or data
                CreateThread(function()
                    Supply.TakeCrate(entity)
                end)
            end,
        },
    })
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearRun()
    stopCrateCarry()
    clearStack()
    if Hint then
        lib.hideTextUI()
    end
    if VehicleTarget then
        BRIDGE.RemoveGlobalVehicleTarget(VehicleTarget)
        VehicleTarget = nil
    end
end)
