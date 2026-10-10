Utils = {}

local IS_SERVER = IsDuplicityVersion()

-- GTA wheel index -> bone name
Utils.WheelBones = {
    [0] = "wheel_lf",
    [1] = "wheel_rf",
    [2] = "wheel_lm1",
    [3] = "wheel_rm1",
    [4] = "wheel_lr",
    [5] = "wheel_rr",
}

-- Wheel index -> side used by jack ("lf", "rf", "lr", "rr")
Utils.WheelSides = {
    [0] = "lf",
    [1] = "rf",
    [2] = "lr",
    [3] = "rr",
    [4] = "lr",
    [5] = "rr",
}

function Utils.Debug(...)
    if Config.Debug then
        print("[pls_mechanic]", ...)
    end
end

-- Item name from Config.Items key (returns key when not found = already item name)
function Utils.Item(key)
    return Config.Items[key] or key
end

-- Config.Items key from item name
function Utils.ItemKey(itemName)
    for key, name in pairs(Config.Items) do
        if name == itemName then
            return key
        end
    end
    return nil
end

function Utils.TrimPlate(plate)
    if not plate then return nil end
    return (tostring(plate):gsub("^%s*(.-)%s*$", "%1"))
end

function Utils.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

function Utils.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utils.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = Utils.DeepCopy(v)
    end
    return copy
end

-- {x, y, z} table -> vector3
function Utils.Vec3(coords)
    if not coords then return nil end
    return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

-- vector3 -> {x, y, z} table (safe for json / statebags)
function Utils.Coords(vec)
    if not vec then return nil end
    return { x = Utils.Round(vec.x, 3), y = Utils.Round(vec.y, 3), z = Utils.Round(vec.z, 3) }
end

-- "optimal" / "worn" / "critical" / "failed"
function Utils.GetPartState(value)
    value = value or 100
    if value > Config.PartStates.optimal then return "optimal" end
    if value > Config.PartStates.worn then return "worn" end
    if value > Config.PartStates.critical then return "critical" end
    return "failed"
end

function Utils.IsElectricModel(model)
    for _, name in pairs(Config.ElectricVehicles) do
        if joaat(name) == model then
            return true
        end
    end
    return false
end

-- Is part used on this vehicle? part = Config.ServiceParts[key] / Config.CoreParts[key]
function Utils.PartFitsVehicle(part, isEv)
    if part.type == "all" then return true end
    if part.type == "ev" then return isEv == true end
    return isEv ~= true
end

-- Split body key "door:0" -> "door", 0
function Utils.SplitBodyKey(key)
    local kind, index = key:match("^([%w_]+):?([%w]*)$")
    if index == "" then index = nil end
    return kind, tonumber(index) or index
end

-- Items list {{item = key, count = n}} -> readable text "2x Brake pads"
function Utils.ItemsToText(items, labels)
    local parts = {}
    for _, v in pairs(items or {}) do
        local name = Utils.Item(v.item)
        local label = labels and labels[name] or name
        table.insert(parts, v.count.."x "..label)
    end
    return table.concat(parts, ", ")
end

-- Job name is in list of workshop jobs
function Utils.ShopHasJob(shop, jobName)
    if not shop or not jobName then return false end
    for _, job in pairs(shop.jobs or {}) do
        if job == jobName then
            return true
        end
    end
    return false
end

-- Permissions table for job + grade from shop (grade keys are strings)
function Utils.GetShopPermissions(shop, jobName, grade)
    if not Utils.ShopHasJob(shop, jobName) then return {} end
    local jobPerms = shop.permissions and shop.permissions[jobName]
    if not jobPerms then return {} end
    return jobPerms[tostring(grade)] or {}
end

-- Finds point of workshop by id
function Utils.GetShopPoint(shop, pointId)
    if not shop then return nil end
    for _, point in pairs(shop.points or {}) do
        if point.id == pointId then
            return point
        end
    end
    return nil
end

-- Bay point types accepted for location "bay"
function Utils.BayAccepts(point, purpose)
    local bayType = point.data and point.data.bayType or "both"
    if bayType == "both" then return true end
    return bayType == purpose
end

if not IS_SERVER then
    -- Format number with thousands separator
    function Utils.FormatMoney(value)
        local formatted = tostring(math.floor(value or 0))
        local k
        repeat
            formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
        until k == 0
        return formatted
    end
end
