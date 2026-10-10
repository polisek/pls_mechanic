--[[
  _____  _                     _     _
 |  __ \| |                   | |   | |
 | |__) | | __ _  ___ ___  __ _| |__ | | ___  ___
 |  ___/| |/ _` |/ __/ _ \/ _` | '_ \| |/ _ \/ __|
 | |    | | (_| | (_|  __/ (_| | |_) | |  __/\__ \
 |_|    |_|\__,_|\___\___|\__,_|_.__/|_|\___||___/

 Cones, barriers, signs and toolbox placed from inventory.
 Local ghost preview -> the player carries the item to the spot and puts it down ->
 server creates networked frozen object (state pls_prop).
 Anyone can pick the prop up again (target on models, crouch + pick up animation).
]]--

Props = {}

local Placing = false
local Ghost = nil

-- weapon wheel, attack, aim, cover, melee
local PlaceControls = { 14, 15, 16, 17, 24, 25, 37, 44, 140, 141, 142, 257, 263 }
local KEY_PLACE = 38        -- E
local KEY_CANCEL = 194      -- Backspace
local KEY_LEFT = 174        -- arrow left
local KEY_RIGHT = 175       -- arrow right
local KEY_SCROLL_UP = 15
local KEY_SCROLL_DOWN = 14

-- Hand prop of each item: Config.Props key or { model, bone, pos, rot }
local HandProps = {}
for key, data in pairs(Config.Placeables.items) do
    if type(data.hand) == "string" then
        HandProps[key] = data.hand
    else
        local hand = data.hand or {}
        HandProps[key] = { model = data.model, bone = hand.bone or 28422, pos = hand.pos or vec3(0.0, 0.0, 0.0), rot = hand.rot or vec3(0.0, 0.0, 0.0) }
    end
end

local function Notify(key, notifyType, ...)
    Core.Notify(locale(key, ...), notifyType or "inform")
end

-- Another scene of the shared animation library is running (mechanic menu action, repair, tuning installation, DLC scene)
local function OtherWorkRunning()
    if (Menu and Menu.IsBusy and Menu.IsBusy()) or (Tuning and Tuning.IsInstalling and Tuning.IsInstalling())
        or (Repair and Repair.IsBusy and Repair.IsBusy()) or Anim.IsBusy() or Core.IsExternalBusy() then
        Notify("repair_busy", "error")
        return true
    end
    return false
end

local function SetCancel(fn)
    if Menu and Menu.SetCancelHandler then
        Menu.SetCancelHandler(fn)
    end
end

-- Standing spot 0.7 m in front of the target (on the player's side) and the heading towards the target
local function StandSpot(target)
    local pos = GetEntityCoords(cache.ped)
    local dir = pos.xy - target.xy
    local length = #dir
    if length < 0.8 then
        return vector3(pos.x, pos.y, pos.z), GetHeadingFromVector_2d(target.x - pos.x, target.y - pos.y)
    end
    dir = dir / length
    local stand = vector3(target.x + dir.x * 0.7, target.y + dir.y * 0.7, pos.z)
    return stand, GetHeadingFromVector_2d(target.x - stand.x, target.y - stand.y)
end

local function RotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

-- World (1) + objects (16) raycast from gameplay camera. Returns hit, coords
local function RaycastFromCamera(distance)
    local camCoords = GetFinalRenderedCamCoord()
    local dest = camCoords + RotationToDirection(GetFinalRenderedCamRot(2)) * distance
    local handle = StartExpensiveSynchronousShapeTestLosProbe(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, 17, cache.ped, 4)
    local _, hit, coords = GetShapeTestResult(handle)
    return hit == 1 or hit == true, coords
end

local function DeleteGhost()
    if Ghost and DoesEntityExist(Ghost) then
        SetEntityDrawOutline(Ghost, false)
        DeleteEntity(Ghost)
        SetEntityDrawOutlineShader(0)
    end
    Ghost = nil
end

local function CreateGhost(model)
    local coords = GetEntityCoords(cache.ped)
    Ghost = CreateObject(model, coords.x, coords.y, coords.z - 10.0, false, false, false)
    SetEntityAlpha(Ghost, 170, false)
    SetEntityCollision(Ghost, false, false)
    FreezeEntityPosition(Ghost, true)
    SetEntityDrawOutline(Ghost, true)
    SetEntityDrawOutlineShader(1)
end

-- Placement preview. Returns coords, heading or nil when cancelled
local function PlacementLoop(model)
    local minDim = GetModelDimensions(model)
    local heading = GetEntityHeading(cache.ped)
    local step = Config.Placeables.rotateStep or 5.0
    local cancelled = false
    local lastValid = nil

    SetCancel(function() cancelled = true end)
    lib.showTextUI(locale("props_place_help"))

    while not cancelled do
        for i = 1, #PlaceControls do
            DisableControlAction(0, PlaceControls[i], true)
        end
        if cache.vehicle or IsPedDeadOrDying(cache.ped, true) then break end

        if IsDisabledControlJustPressed(0, KEY_SCROLL_UP) then heading = heading + step end
        if IsDisabledControlJustPressed(0, KEY_SCROLL_DOWN) then heading = heading - step end
        if IsControlPressed(0, KEY_LEFT) then heading = heading + step * 0.3 end
        if IsControlPressed(0, KEY_RIGHT) then heading = heading - step * 0.3 end

        local hit, coords = RaycastFromCamera(Config.Placeables.placeDistance + 8.0)
        local valid = false
        if hit then
            SetEntityCoordsNoOffset(Ghost, coords.x, coords.y, coords.z - minDim.z, false, false, false)
            valid = #(GetEntityCoords(Ghost) - GetEntityCoords(cache.ped)) <= Config.Placeables.placeDistance
        end
        SetEntityHeading(Ghost, heading)
        if valid then
            SetEntityDrawOutlineColor(80, 220, 120, 255)
            lastValid = GetEntityCoords(Ghost)
        else
            SetEntityDrawOutlineColor(230, 70, 70, 255)
            lastValid = nil
        end

        if IsControlJustPressed(0, KEY_PLACE) then
            if lastValid then
                lib.hideTextUI()
                SetCancel(nil)
                return lastValid, heading % 360.0
            end
            Notify("props_too_far", "error")
        end
        if IsControlJustPressed(0, KEY_CANCEL) then break end
        Wait(0)
    end

    lib.hideTextUI()
    SetCancel(nil)
    return nil
end

-- Carries the item to the chosen spot and puts it down. Returns true when put down.
local function PutDownScene(key, coords)
    local data = Config.Placeables.items[key]
    local hand = HandProps[key]
    local cancelled = false
    local isCancelled = function() return cancelled end
    SetCancel(function() cancelled = true end)

    -- box carry pose, or only in one hand (toolbox)
    local carryAnim = nil
    if data.carry == false then
        carryAnim = false
    end
    local carry = Anim.Carry(hand, carryAnim)
    local stand, heading = StandSpot(coords)
    Anim.WalkTo(stand, heading, 6000, isCancelled)
    local done = false
    if not cancelled then
        Anim.Face(coords)
        done = Anim.Phase({
            label = locale("props_placing"),
            duration = Config.Placeables.placeDuration or 1300,
            anim = Config.Placeables.anim.place,
            prop = hand,
            cancel = isCancelled,
        })
    end
    if carry then
        Anim.StopCarry(carry)
    end
    SetCancel(nil)
    return done and not cancelled
end

function Props.StartPlacement(key)
    if Placing then return end
    local data = Config.Placeables.items[key]
    if not data then return end
    if cache.vehicle then
        return Notify("menu_on_foot", "error")
    end
    if OtherWorkRunning() then return end
    if Core.CountItem(key) < 1 then
        return Notify("missing_items", "error", Core.GetItemLabel(Utils.Item(key)))
    end
    local model = joaat(data.model)
    if not IsModelValid(model) then return end

    Placing = true
    lib.requestModel(model)
    CreateGhost(model)
    SetModelAsNoLongerNeeded(model)
    local coords, heading = PlacementLoop(model)
    DeleteGhost()
    if not coords then
        Placing = false
        return Notify("cancelled", "error")
    end

    if not PutDownScene(key, coords) then
        Placing = false
        return Notify("cancelled", "error")
    end
    TriggerSecureEvent("pls_mechanic:server:props:place", key, Utils.Coords(coords), heading)
    Placing = false
end

function Props.IsPlacing()
    return Placing
end

--[[
  _____ _      _
 |  __ (_)    | |
 | |__) |  ___| | __  _   _ _ __
 |  ___/ |/ __| |/ / | | | | '_ \
 | |   | | (__|   <  | |_| | |_) |
 |_|   |_|\___|_|\_\  \__,_| .__/
                           | |
                           |_|
]]--

local function PickUp(entity)
    if Placing or not entity or not DoesEntityExist(entity) then return end
    local state = Entity(entity).state.pls_prop
    if not state or not NetworkGetEntityIsNetworked(entity) then return end
    if OtherWorkRunning() then return end
    Placing = true
    local netId = NetworkGetNetworkIdFromEntity(entity)
    local cancelled = false
    local isCancelled = function() return cancelled end
    SetCancel(function() cancelled = true end)

    local coords = GetEntityCoords(entity)
    local stand, heading = StandSpot(coords)
    Anim.WalkTo(stand, heading, 4000, isCancelled)
    local picked = false
    if not cancelled then
        Anim.Face(coords)
        local duration = Config.Placeables.pickupDuration or 1200
        local active = true
        -- the item leaves the ground at the lowest point of the crouch
        local function release()
            if picked then return end
            picked = true
            TriggerSecureEvent("pls_mechanic:server:props:pickup", netId)
        end
        local done = Anim.Phase({
            label = locale("props_picking"),
            duration = duration,
            anim = Config.Placeables.anim.pickup,
            cancel = isCancelled,
            onStart = function()
                CreateThread(function()
                    Wait(math.floor(duration * 0.5))
                    if active and not cancelled then release() end
                end)
            end,
        })
        active = false
        if done and not cancelled then
            release()
        end
    end
    SetCancel(nil)
    if not picked then
        Notify("cancelled", "error")
    end
    Placing = false
end

local Models = {}
for _, data in pairs(Config.Placeables.items) do
    table.insert(Models, data.model)
end

if #Models > 0 then
    BRIDGE.AddModelTarget(Models, {
        {
            name = "pls_mechanic_prop_pickup",
            label = locale("props_pickup"),
            icon = "fa-solid fa-hand",
            distance = Config.Placeables.pickupDistance,
            canInteract = function(entity)
                return not Placing and not cache.vehicle and Entity(entity).state.pls_prop ~= nil
            end,
            onSelect = function(data)
                local entity = type(data) == "table" and data.entity or data
                CreateThread(function() PickUp(entity) end)
            end,
        },
    })
end

for key in pairs(Config.Placeables.items) do
    Items.Register(key, function()
        -- own thread: placement loop must not block the item use (ox_inventory export)
        CreateThread(function()
            Props.StartPlacement(key)
        end)
    end)
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Ghost then
        DeleteGhost()
        lib.hideTextUI()
    end
end)
