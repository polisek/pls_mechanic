--[[
   _____            __ _   _
  / ____|          / _| | (_)
 | |     _ __ __ _| |_| |_ _ _ __   __ _
 | |    | '__/ _` |  _| __| | '_ \ / _` |
 | |____| | | (_| | | | |_| | | | | (_| |
  \_____|_|  \__,_|_|  \__|_|_| |_|\__, |
                                    __/ |
                                   |___/
 Workbench crafting menu (ox_lib context), recipes from configs/crafting.lua.
 Every piece is a workbench scene (welding / drilling / hammering / assembling by category),
 the product then appears on the bench and the mechanic takes it.
]]--

Crafting = {}

local MENU_ID = "pls_mechanic_crafting"
local CATEGORY_ORDER = { "kits", "parts", "body", "tools", "props", "recycling" }
local CATEGORY_ICONS = {
    kits = "fa-solid fa-kit-medical",
    parts = "fa-solid fa-gears",
    body = "fa-solid fa-car-side",
    tools = "fa-solid fa-toolbox",
    props = "fa-solid fa-road-barrier",
    recycling = "fa-solid fa-recycle",
}
local Busy = false

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

local function notifyResult(result)
    if result and result.message then
        Core.Notify(result.message, result.ok and "success" or "error")
    end
end

local function itemLabel(key)
    return Core.GetItemLabel(Utils.Item(key))
end

-- How many times the recipe can be crafted with items in inventory
local function maxCraftable(recipe)
    local max = Config.Crafting.maxAmount or 10
    for _, v in pairs(recipe.ingredients or {}) do
        max = math.min(max, math.floor(Core.CountItem(v.item) / v.count))
    end
    return max
end

local function categoryIndex(category)
    for i, key in ipairs(CATEGORY_ORDER) do
        if key == category then return i end
    end
    return #CATEGORY_ORDER + 1
end

local function recipeOption(shop, point, index, recipe)
    local hasItems, list = Core.CheckItems(recipe.ingredients)
    local hasTools = Core.HasTools(recipe.tools)
    local metadata, parts = {}, {}
    for _, v in ipairs(list) do
        table.insert(metadata, { label = v.label, value = locale("craft_have_need", v.have, v.count) })
        table.insert(parts, v.count.."x "..v.label)
    end
    if recipe.tools and #recipe.tools > 0 then
        local tools = {}
        for _, key in ipairs(recipe.tools) do
            table.insert(tools, Core.CountTool(key) > 0 and itemLabel(key) or locale("craft_tool_missing", itemLabel(key)))
        end
        table.insert(metadata, { label = locale("craft_tools"), value = table.concat(tools, ", ") })
    end
    table.insert(metadata, { label = locale("craft_duration"), value = locale("craft_seconds", math.floor((recipe.duration or 10000) / 1000)) })
    local resultName = Utils.Item(recipe.result)
    local canCraft = hasItems and hasTools
    return {
        title = ("%dx %s"):format(recipe.count or 1, Core.GetItemLabel(resultName)),
        description = table.concat(parts, ", "),
        icon = canCraft and "fa-solid fa-hammer" or "fa-solid fa-lock",
        iconColor = canCraft and "#4ade80" or "#f87171",
        image = Config.ImagePath:format(resultName),
        metadata = metadata,
        onSelect = function()
            CreateThread(function()
                Crafting.Craft(shop, point, index)
            end)
        end,
    }
end

local function showMenu(shop, point)
    local categories, order = {}, {}
    for index, recipe in ipairs(Config.Crafting.recipes) do
        if Config.Items[recipe.result] then
            local category = recipe.category or "parts"
            if not categories[category] then
                categories[category] = {}
                table.insert(order, category)
            end
            table.insert(categories[category], recipeOption(shop, point, index, recipe))
        end
    end
    if #order == 0 then
        Core.Notify(locale("craft_none"), "error")
        return
    end
    table.sort(order, function(a, b) return categoryIndex(a) < categoryIndex(b) end)

    if #order == 1 then
        lib.registerContext({ id = MENU_ID, title = locale("craft_menu_title"), options = categories[order[1]] })
    else
        local options = {}
        for _, category in ipairs(order) do
            local id = MENU_ID.."_"..category
            local title = locale("craft_category_"..category)
            lib.registerContext({ id = id, title = title, menu = MENU_ID, options = categories[category] })
            table.insert(options, {
                title = title,
                description = locale("craft_recipes_count", #categories[category]),
                icon = CATEGORY_ICONS[category] or "fa-solid fa-screwdriver-wrench",
                menu = id,
                arrow = true,
            })
        end
        lib.registerContext({ id = MENU_ID, title = locale("craft_menu_title"), options = options })
    end
    lib.showContext(MENU_ID)
end

--[[
  _____       _     _ _
 |  __ \     | |   | (_)
 | |__) |   _| |__ | |_  ___
 |  ___/ | | | '_ \| | |/ __|
 | |   | |_| | |_) | | | (__
 |_|    \__,_|_.__/|_|_|\___|
]]--

-- Workbench point: server decides built-in menu or custom crafting (OpenServer.OpenCustomCrafting)
function Crafting.Open(shop, point)
    CreateThread(function()
        if Busy then return end
        local result = lib.callback.await("pls_mechanic:server:crafting:open", false, shop.id, point.id)
        if not result or not result.ok then
            notifyResult(result)
            return
        end
        if result.custom then return end
        showMenu(shop, point)
    end)
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

-- Workbench scene of one piece, phases share the recipe duration. Returns true when completed
local function runScene(recipe, duration, label, piece, amount, isCancelled)
    local scene = Config.Crafting.scenes and Config.Crafting.scenes[recipe.scene or recipe.category or "parts"]
    if not scene or #scene == 0 then
        return Anim.Phase({ label = locale("craft_progress", label, piece, amount), duration = duration, cancel = isCancelled })
    end
    for i, phase in ipairs(scene) do
        local nextPhase = scene[i + 1]
        local done = Anim.Phase({
            label = locale("craft_phase_label", locale(phase.label), label, piece, amount),
            duration = math.max(500, math.floor(duration * (phase.share or (1 / #scene)))),
            anim = phase.anim,
            prop = phase.prop,
            prop2 = phase.prop2,
            sound = phase.sound,
            particle = phase.particle,
            keepAnim = nextPhase ~= nil and nextPhase.anim == phase.anim,
            keepProp = nextPhase ~= nil and phase.prop ~= nil and nextPhase.prop == phase.prop,
            cancel = isCancelled,
        })
        if not done then return false end
    end
    return true
end

-- The product appears on the bench in front of the mechanic, he takes it
local function takeProduct(recipe)
    local model = recipe.prop or (Config.Crafting.products and Config.Crafting.products[recipe.category or "parts"])
    local hash = model and joaat(model)
    if not hash or not IsModelValid(hash) or not pcall(lib.requestModel, hash, 3000) then return end
    local ped = cache.ped
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.55, 0.0)
    local min = GetModelDimensions(hash)
    -- ped root is at about the height of a workbench top, the bottom of the product is placed there
    local z = pos.z - 0.05 - min.z
    local object = CreateObject(hash, pos.x, pos.y, z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not object or object == 0 then return end
    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)
    SetEntityHeading(object, GetEntityHeading(ped) + 90.0)
    SetEntityCoordsNoOffset(object, pos.x, pos.y, z, false, false, false)
    Wait(700)
    local take = Config.Crafting.take
    if take then
        CreateThread(function()
            Wait(math.floor((take.time or 1300) * 0.5))
            if DoesEntityExist(object) then DeleteEntity(object) end
        end)
        Anim.Play(take)
    end
    if DoesEntityExist(object) then
        DeleteEntity(object)
    end
end

-- Crafts recipe (index in Config.Crafting.recipes), asks for amount, one workbench scene per piece
function Crafting.Craft(shop, point, index)
    if Busy then return end
    local recipe = Config.Crafting.recipes[index]
    if not recipe then return end
    local label = itemLabel(recipe.result)

    local hasItems, list = Core.CheckItems(recipe.ingredients)
    if not hasItems then
        local missing = {}
        for _, v in ipairs(list) do
            if v.have < v.count then
                table.insert(missing, (v.count - v.have).."x "..v.label)
            end
        end
        Core.Notify(locale("missing_items", table.concat(missing, ", ")), "error")
        return
    end
    local hasTools, missingTool = Core.HasTools(recipe.tools)
    if not hasTools then
        Core.Notify(locale("missing_tool", itemLabel(missingTool)), "error")
        return
    end
    if otherWorkRunning() then return end

    local amount = 1
    local max = math.max(1, maxCraftable(recipe))
    if max > 1 then
        local input = lib.inputDialog(locale("craft_amount_title", label), {
            { type = "number", label = locale("craft_amount", max), default = 1, min = 1, max = max, required = true },
        })
        if not input or not input[1] then return end
        amount = Utils.Clamp(math.floor(tonumber(input[1]) or 1), 1, max)
    end

    Busy = true
    local cancelled = false
    local isCancelled = function() return cancelled end
    if Menu and Menu.SetCancelHandler then
        Menu.SetCancelHandler(function() cancelled = true end)
    end
    Anim.Face(Utils.Vec3(point.coords))
    local crafted = 0
    for i = 1, amount do
        local start = lib.callback.await("pls_mechanic:server:crafting:start", false, shop.id, point.id, index)
        if not start or not start.ok then
            notifyResult(start)
            break
        end
        if not runScene(recipe, start.duration, label, i, amount, isCancelled) or cancelled then
            Core.Notify(locale("cancelled"), "error")
            break
        end
        local result = lib.callback.await("pls_mechanic:server:crafting:finish", false)
        if not result or not result.ok then
            notifyResult(result)
            break
        end
        crafted = crafted + (result.count or 1)
        takeProduct(recipe)
    end
    if Menu and Menu.SetCancelHandler then
        Menu.SetCancelHandler(nil)
    end
    if cancelled then
        Anim.Cleanup()
    end
    if crafted > 0 then
        Core.Notify(locale("craft_done", crafted, label), "success")
    end
    Busy = false
end

--[[
                 _   _
     /\         | | (_)
    /  \   ___| |_ _  ___  _ __  ___
   / /\ \ / __| __| |/ _ \| '_ \/ __|
  / ____ \ (__| |_| | (_) | | | \__ \
 /_/    \_\___|\__|_|\___/|_| |_|___/
]]--

ShopPoints.RegisterAction("workbench", {
    label = locale("craft_action"),
    icon = "fa-solid fa-hammer",
    perm = "craft",
    onSelect = function(shop, point)
        Crafting.Open(shop, point)
    end,
})
