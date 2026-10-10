--[[
           _____ _____  __      __  _     _      _
     /\   |  __ \_   _| \ \    / / | |   (_)    | |
    /  \  | |__) || |    \ \  / /__| |__  _  ___| | ___  ___
   / /\ \ |  ___/ | |     \ \/ / _ \ '_ \| |/ __| |/ _ \/ __|
  / ____ \| |    _| |_     \  /  __/ | | | | (__| |  __/\__ \
 /_/    \_\_|   |_____|     \/ \___|_| |_|_|\___|_|\___||___/

 Vehicle exports for other resources (pls_mechanic_illegal and 3rd party scripts), mechanic-illegal-dev-spec.md section 2.
 Plain data only: returned tables are copies, never live VehicleData. Plates are trimmed strings, aliases are resolved.

 exports.pls_mechanic:GetVehicleData(entityOrPlate)            -> copy | nil
 exports.pls_mechanic:SetVehiclePart(plate, kind, key, value)  -> bool     kind = "service" / "core"
 exports.pls_mechanic:SetPartOrigin(plate, key, origin)        -> bool     origin = "unknown" / nil (clean)
 exports.pls_mechanic:SetVehicleModifiers(plate, source, mods) -> bool     mods = { handling = {}, wear = {} } / nil
 exports.pls_mechanic:SetPlateAlias(aliasPlate, realPlate)     -> bool
 exports.pls_mechanic:ClearPlateAlias(aliasPlate)              -> bool
 exports.pls_mechanic:GetRealPlate(plate)                      -> plate
 exports.pls_mechanic:GetEntityPlate(entity)                   -> realPlate, spoofed, visiblePlate
 exports.pls_mechanic:SetTrustedPlate(entity, plate)           -> bool     plate of a vehicle spawned by the caller's server
 exports.pls_mechanic:GetInstalledTuning(plate)                -> { [category key] = stage } performance parts installed by workshops

 Never read the real plate of an entity from its plate text (the owner client can change it to another player's plate),
 use GetEntityPlate: the plate BASE trusts for the entity (first sight, then only server side changes / plate aliases).
]]--

local function isEntity(value)
    return type(value) == "number" and value > 0 and DoesEntityExist(value) and GetEntityType(value) == 2
end

-- VehicleData -> plain copy { plate, model, class, mileage, ev, owned, service, core, origin, ext }
local function copyData(data)
    if type(data) ~= "table" then return nil end
    return {
        plate = data.plate,
        model = data.model,
        class = data.class,
        mileage = data.mileage,
        ev = data.ev == true,
        owned = data.owned == true,
        service = Utils.DeepCopy(data.service or {}),
        core = Utils.DeepCopy(data.core or {}),
        origin = Utils.DeepCopy(data.origin or {}),
        ext = Utils.DeepCopy(data.ext or {}),
    }
end

-- Entity creates the data like the first drive (not owned = random used condition), plate reads cache / database only
exports("GetVehicleData", function(entityOrPlate)
    if isEntity(entityOrPlate) then
        return copyData(Vehicles.GetByEntity(entityOrPlate))
    end
    if type(entityOrPlate) ~= "string" then return nil end
    return copyData(Vehicles.GetByPlate(entityOrPlate))
end)

exports("SetVehiclePart", function(plate, kind, key, value)
    if type(plate) ~= "string" then return false end
    return Vehicles.SetPart(plate, kind, key, value) == true
end)

exports("SetPartOrigin", function(plate, key, origin)
    if type(plate) ~= "string" then return false end
    return Vehicles.SetPartOrigin(plate, key, origin) == true
end)

exports("SetVehicleModifiers", function(plate, source, mods)
    if type(plate) ~= "string" then return false end
    return Vehicles.SetModifiers(plate, source, mods) == true
end)

exports("SetPlateAlias", function(aliasPlate, realPlate)
    return Vehicles.SetPlateAlias(aliasPlate, realPlate) == true
end)

exports("ClearPlateAlias", function(aliasPlate)
    return Vehicles.ClearPlateAlias(aliasPlate) == true
end)

exports("GetRealPlate", function(plate)
    return Vehicles.GetRealPlate(plate)
end)

-- realPlate = trusted plate of the entity resolved to the real plate, spoofed = the plate text (alias resolved) is
-- another plate, visiblePlate = plate text. A vehicle seen for the first time is recorded now (spoofed = false).
exports("GetEntityPlate", function(entity)
    if not isEntity(entity) then return nil, false, nil end
    local real, spoofed, visible = Vehicles.GetEntityPlate(entity)
    return real, spoofed == true, visible
end)

-- Vehicle spawned by the server of another resource: its plate (set by the server or applied by the owner client later)
-- becomes the trusted plate right away, the settling of new vehicles is skipped
exports("SetTrustedPlate", function(entity, plate)
    if not isEntity(entity) or type(plate) ~= "string" then return false end
    return Vehicles.SetTrustedPlate(entity, plate) == true
end)

-- Stages of performance parts installed by workshops on the plate { engine = 3, turbo = 1 }, {} when none
exports("GetInstalledTuning", function(plate)
    if type(plate) ~= "string" or not TuningServer or not TuningServer.GetInstalledParts then return {} end
    local ok, parts = pcall(TuningServer.GetInstalledParts, plate)
    if not ok or type(parts) ~= "table" then return {} end
    return parts
end)
