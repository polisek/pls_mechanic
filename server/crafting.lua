--[[
   _____            __ _   _
  / ____|          / _| | (_)
 | |     _ __ __ _| |_| |_ _ _ __   __ _
 | |    | '__/ _` |  _| __| | '_ \ / _` |
 | |____| | | (_| | | | |_| | | | | (_| |
  \_____|_|  \__,_|_|  \__|_|_| |_|\__, |
                                    __/ |
                                   |___/
 Workbench crafting. Client asks "start" (validated, time stored), plays progress, then "finish"
 (validated again incl. elapsed time) -> ingredients removed, result added.
]]--

CraftingServer = {}

local Recipes = Config.Crafting.recipes
local Pending = {}        -- [src] = { index, shopId, pointId, started, duration }
local ItemLabels = nil

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

local function fail(message)
    return { ok = false, message = message }
end

local function getItemLabel(itemName)
    if not ItemLabels then
        local labels = {}
        local ok, items = pcall(BRIDGE.GetItems)
        if ok and type(items) == "table" then
            for name, data in pairs(items) do
                if type(data) == "table" and data.label then
                    labels[name] = data.label
                end
            end
        end
        if next(labels) then
            ItemLabels = labels
        end
        return labels[itemName] or itemName
    end
    return ItemLabels[itemName] or itemName
end

local function missingText(missing)
    local parts = {}
    for _, v in pairs(missing or {}) do
        table.insert(parts, math.floor(v.count).."x "..getItemLabel(Utils.Item(v.item)))
    end
    return table.concat(parts, ", ")
end

local function isValidRecipe(recipe)
    if type(recipe) ~= "table" or not Config.Items[recipe.result] then return false end
    for _, v in pairs(recipe.ingredients or {}) do
        if not Config.Items[v.item] or (tonumber(v.count) or 0) < 1 then return false end
    end
    for _, key in pairs(recipe.tools or {}) do
        if not Config.Items[key] then return false end
    end
    return true
end

-- Permission (craft + duty) and distance to workbench point of the workshop
local function checkAccess(src, shopId, pointId)
    if not shopId or not Shops.HasPermission(src, "craft", shopId) then
        return false, locale("no_permission")
    end
    local point = Utils.GetShopPoint(Shops.Get(shopId), pointId)
    if not point or point.type ~= "workbench" then
        return false, locale("too_far")
    end
    local ped = GetPlayerPed(src)
    local radius = point.radius or Config.PointTypes.workbench.radius
    if not ped or ped == 0 or #(GetEntityCoords(ped) - Utils.Vec3(point.coords)) > radius + 2.5 then
        return false, locale("too_far")
    end
    return true
end

local function log(src, action, message, data)
    local ok, err = pcall(OpenServer.Log, src, action, message, data)
    if not ok then
        print("[pls_mechanic] OpenServer.Log error: "..tostring(err))
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

-- Full check of one craft (built-in crafting enabled, access, ingredients, tools). Returns ok, message
function CraftingServer.CanCraft(src, shopId, pointId, index)
    if not Config.Crafting.enabled then return false, locale("craft_disabled") end
    local recipe = Recipes[index]
    if not isValidRecipe(recipe) then return false, locale("craft_invalid") end
    local ok, err = checkAccess(src, shopId, pointId)
    if not ok then return false, err end
    -- ingredients by the rules of the workshop (illegal: stolen first, legal: clean only)
    local hasItems, missing = Shops.HasItems(src, recipe.ingredients, 1, shopId)
    if not hasItems then return false, locale("missing_items", missingText(missing)) end
    local hasTools, missingTool = Shops.HasTools(src, recipe.tools, shopId)
    if not hasTools then return false, locale("missing_tool", getItemLabel(Utils.Item(missingTool))) end
    return true
end

--[[
   _____      _ _ _                _
  / ____|    | | | |              | |
 | |     __ _| | | |__   __ _  ___| | _____
 | |    / _` | | | '_ \ / _` |/ __| |/ / __|
 | |___| (_| | | | |_) | (_| | (__|   <\__ \
  \_____\__,_|_|_|_.__/ \__,_|\___|_|\_\___/
]]--

-- Workbench opened. custom = OpenServer.OpenCustomCrafting took over (client shows nothing)
lib.callback.register("pls_mechanic:server:crafting:open", function(src, shopId, pointId)
    shopId = tonumber(shopId)
    local ok, err = checkAccess(src, shopId, pointId)
    if not ok then return fail(err) end
    local success, custom = pcall(OpenServer.OpenCustomCrafting, src, shopId)
    if not success then
        print("[pls_mechanic] OpenServer.OpenCustomCrafting error: "..tostring(custom))
    elseif custom == true then
        return { ok = true, custom = true }
    end
    if not Config.Crafting.enabled then return fail(locale("craft_disabled")) end
    return { ok = true }
end)

lib.callback.register("pls_mechanic:server:crafting:start", function(src, shopId, pointId, index)
    shopId = tonumber(shopId)
    index = tonumber(index)
    Pending[src] = nil
    local ok, err = CraftingServer.CanCraft(src, shopId, pointId, index)
    if not ok then return fail(err) end
    local duration = math.max(1000, math.floor(tonumber(Recipes[index].duration) or 10000))
    Pending[src] = { index = index, shopId = shopId, pointId = pointId, started = GetGameTimer(), duration = duration }
    return { ok = true, duration = duration }
end)

lib.callback.register("pls_mechanic:server:crafting:finish", function(src)
    local pending = Pending[src]
    Pending[src] = nil
    if not pending then return fail(locale("craft_invalid")) end
    if GetGameTimer() - pending.started < pending.duration * 0.85 then
        return fail(locale("craft_too_fast"))
    end
    local ok, err = CraftingServer.CanCraft(src, pending.shopId, pending.pointId, pending.index)
    if not ok then return fail(err) end

    local recipe = Recipes[pending.index]
    local count = math.max(1, math.floor(tonumber(recipe.count) or 1))
    local consumed, removed = Shops.RemoveItems(src, recipe.ingredients, 1, pending.shopId)
    if not removed then
        Shops.AddItems(src, consumed, pending.shopId)
        return fail(locale("missing_items", missingText(recipe.ingredients)))
    end
    -- a result made of stolen parts stays stolen (a workbench can't launder parts)
    local quality, stolen = ItemRules.GetConsumedQuality(consumed)
    local metadata = nil
    if stolen then
        local origin = nil
        for _, entry in ipairs(consumed or {}) do
            if entry.stolen and entry.origin then origin = entry.origin break end
        end
        metadata = { stolen = true, quality = quality, origin = origin, description = locale("item_stolen_desc", quality) }
    end
    if not BRIDGE.AddItem(src, Utils.Item(recipe.result), count, metadata) then
        -- the consumed items go back with their metadata
        Shops.AddItems(src, consumed, pending.shopId)
        return fail(locale("craft_no_space"))
    end
    log(src, "craft", ("Crafted %dx %s at workshop %s"):format(count, recipe.result, pending.shopId), { recipe = pending.index, shopId = pending.shopId })
    return { ok = true, count = count }
end)

AddEventHandler("playerDropped", function()
    Pending[source] = nil
end)
