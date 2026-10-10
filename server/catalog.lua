--[[
   _____      _        _
  / ____|    | |      | |
 | |     __ _| |_ __ _| | ___   __ _
 | |    / _` | __/ _` | |/ _ \ / _` |
 | |___| (_| | || (_| | | (_) | (_| |
  \_____\__,_|\__\__,_|_|\___/ \__, |
                                __/ |
                               |___/
 Customer tuning catalog (Config.Tuning.Catalog):
 - anybody at a vehicle in a tuning bay picks the tuning himself (session per customer, the preview is his client only)
 - "Send order" stores the order of the real plate (one per plate, a new one replaces it), prices with the markup of
   the workshop are computed here, the mechanics of the workshop are notified
 - the mechanic gets the order as the cart of the vehicle (tuning:open binds it to his session), changes outside the
   order go to the customer as a quote (tuning:approve), server/tuning.lua refuses changes that are neither ordered
   nor approved
 - a done / cancelled order stays ORDER_GRACE for its plate and workshop, every change then needs the customer's approval
 - orders and sessions live in memory, the customer is the character who sent the order (also after a reconnect)
]]--

CatalogServer = {}

local Internal = TuningServer.Internal
local Catalog = Config.Tuning.Catalog or {}

local Orders = {}           -- [plate (real)] = { id, plate, visiblePlate, shopId, netId, customer = { src, charId, name }, changes = { { key, value, price, label } }, total, created, touched, status = "open" / "done" / "cancelled", quotes, quoteCooldown }
local CatalogSessions = {}  -- [src] = { netId, plate (real), visiblePlate, rawPlate, shopId, state, activity, submitted }
local Quotes = {}           -- [customer src] = settle function of the quote waiting for his answer
local Approving = {}        -- [mechanic src] = { customer = src, order, settle } while his quote waits for the customer
local Notified = {}         -- [plate (real)] = os.time() the mechanics were notified about an order of the plate
local OrderCounter = 0

local ORDER_GRACE = 15 * 60     -- s, a done / cancelled order stays this long (changes of the plate need the approval)
local QUOTE_COOLDOWN = 30       -- s, after a declined / unanswered quote the mechanic waits this long
local QUOTE_LIMIT = 5           -- quotes per order
local NOTIFY_INTERVAL = 30      -- s, mechanics are notified about the orders of one plate at most this often
local ORDER_LIMIT = 3           -- open orders per customer (character)
local SUBMIT_CLOSE = 30         -- s, a catalog session after "Send order" waits this long for catalog:close

local TUNING_PERMS = { "tuning_visual", "tuning_performance" }

local Categories = Internal.Categories
local fail, toInt, sameValue = Internal.fail, Internal.toInt, Internal.sameValue
local readValue, writeValue, isRemoval = Internal.readValue, Internal.writeValue, Internal.isRemoval
local basePrice, withMarkup = Internal.basePrice, Internal.withMarkup
local catLabel, valueLabel = Internal.catLabel, Internal.valueLabel

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

local function money(value)
    return Config.Currency..value
end

local function getCharId(src)
    local ok, charId = pcall(BRIDGE.GetPlayerCharId, src)
    if ok and charId then
        return tostring(charId)
    end
    return nil
end

-- Online player id of the customer: the same character, also after a reconnect (new player id). nil = offline
local function getCustomerSrc(customer)
    if customer.src and GetPlayerName(customer.src) and (not customer.charId or getCharId(customer.src) == customer.charId) then
        return customer.src
    end
    if not customer.charId then return nil end
    for _, playerId in pairs(GetPlayers()) do
        local src = tonumber(playerId)
        if getCharId(src) == customer.charId then
            customer.src = src
            return src
        end
    end
    return nil
end

-- Player is the customer of the order (the same character)
local function isCustomer(order, src)
    if order.customer.charId then
        return getCharId(src) == order.customer.charId
    end
    return order.customer.src == src
end

local function markupOf(shop)
    return tonumber(shop.settings and shop.settings.tuningMarkup) or 0
end

-- Catalog in legal workshops, illegal ones only with Catalog.illegal
local function shopAllowed(shop)
    return shop.kind ~= "illegal" or Catalog.illegal == true
end

-- Workshop whose tuning bay the coords are in
local function findShopAt(coords)
    for _, shop in pairs(Shops.GetAll()) do
        if shopAllowed(shop) and Internal.findTuningBay(shop, coords) then
            return shop
        end
    end
    return nil
end

-- Online mechanics of the workshop who can install tuning (legal: on duty when Config.RequireDuty, illegal: the crew).
-- limit = stop after this many
local function getMechanics(shop, limit)
    local list = {}
    for _, playerId in pairs(GetPlayers()) do
        local src = tonumber(playerId)
        if shop.kind == "illegal" or not Config.RequireDuty or Player(src).state.pls_mechanic_duty == shop.id then
            for _, perm in ipairs(TUNING_PERMS) do
                local ok, allowed = pcall(Shops.HasPermission, src, perm, shop.id)
                if ok and allowed then
                    list[#list + 1] = src
                    break
                end
            end
            if limit and #list >= limit then break end
        end
    end
    return list
end

-- A mechanic tuning session (server/tuning.lua) works on the plate right now
local function mechanicOnPlate(plate)
    local now = os.time()
    for src, session in pairs(Internal.Sessions) do
        if session.plate == plate and GetPlayerName(src) and now - session.activity <= Config.Tuning.SessionTimeout * 60 then
            return true
        end
    end
    return false
end

-- Open order untouched longer than Catalog.orderMinutes (touched = submit, handover to the mechanic, confirm,
-- heartbeat), done / cancelled one longer than ORDER_GRACE. An order the mechanic works on doesn't expire
local function isExpired(order)
    local limit = order.status == "open" and (tonumber(Catalog.orderMinutes) or 120) * 60 or ORDER_GRACE
    return os.time() - order.touched > limit and not mechanicOnPlate(order.plate)
end

-- Order of the plate (also done / cancelled within ORDER_GRACE), shopId = only an order for that workshop
local function getOrder(plate, shopId)
    local order = plate and Orders[plate]
    if not order or isExpired(order) then return nil end
    if shopId and order.shopId ~= shopId then return nil end
    return order
end

-- Pending order of the plate (waits for a mechanic)
local function getOpenOrder(plate, shopId)
    local order = getOrder(plate, shopId)
    if order and order.status == "open" then
        return order
    end
    return nil
end

-- { { key, value } } of the order for the NUI
local function orderChanges(order)
    local list = {}
    for i, change in ipairs(order.changes) do
        list[i] = { key = change.key, value = Utils.DeepCopy(change.value) }
    end
    return list
end

local function minutesAgo(order)
    return math.floor((os.time() - order.created) / 60)
end

-- Done / cancelled order: nothing is ordered any more
local function inOrder(order, key, value)
    if order.status ~= "open" then return false end
    for _, change in ipairs(order.changes) do
        if change.key == key and sameValue(change.value, value) then
            return true
        end
    end
    return false
end

-- Open order has exactly these items { { key, value } }
local function sameItems(order, items)
    if order.status ~= "open" or #order.changes ~= #items then return false end
    for _, item in ipairs(items) do
        if not inOrder(order, item.key, item.value) then
            return false
        end
    end
    return true
end

-- Changes { { key, value } } -> validated list { entry, value } (same rules as processConfirm in server/tuning.lua):
-- last value of key wins, one rim set (last one), values equal to the state are skipped.
-- customer = { isEv } adds the catalog rules (performance parts only with Catalog.performance, ICE only parts).
-- Returns list or nil, fail result
local function collectChanges(changes, state, customer)
    local byKey, order = {}, {}
    for _, change in ipairs(changes) do
        local entry = type(change) == "table" and type(change.key) == "string" and Categories[change.key] or nil
        if not entry then
            return nil, fail("tuning_invalid", type(change) == "table" and tostring(change.key):sub(1, 32) or "?")
        end
        local value = Internal.normalize(entry, change.value)
        if value == nil then return nil, fail("tuning_invalid", catLabel(entry)) end
        if customer then
            if entry.performance and not Catalog.performance then
                return nil, fail("tuning_invalid", catLabel(entry))
            end
            if entry.iceOnly and customer.isEv and not isRemoval(entry, value) then
                return nil, fail("tuning_vehicle_not_supported")
            end
        end
        if not byKey[entry.key] then
            order[#order + 1] = entry.key
        end
        byKey[entry.key] = { entry = entry, value = value }
    end

    local lastWheel = nil
    for _, key in ipairs(order) do
        if byKey[key].entry.type == "wheels" then lastWheel = key end
    end
    local list = {}
    for _, key in ipairs(order) do
        local change = byKey[key]
        if (change.entry.type ~= "wheels" or key == lastWheel) and not sameValue(readValue(change.entry, state), change.value) then
            list[#list + 1] = change
        end
    end
    return list
end

-- Quote on the customer's screen: true = accepted, false = declined, nil = no answer. Never waits longer than the
-- quote timeout + 5 s (the client callback itself can hang when the customer crashes), other confirms don't wait for it.
-- pending = Approving entry of the mechanic (gets the settle function, closeQuote ends the quote early)
local function requestQuote(customerSrc, quote, pending)
    local p = promise.new()
    local settled = false
    local function settle(answer)
        if settled then return end
        settled = true
        if Quotes[customerSrc] == settle then
            Quotes[customerSrc] = nil
        end
        p:resolve(answer)
    end
    Quotes[customerSrc] = settle
    pending.settle = settle
    CreateThread(function()
        local ok, answer = pcall(lib.callback.await, "pls_mechanic:client:tuning:quote", customerSrc, quote)
        if ok then
            settle(answer)
        else
            settle(nil)
        end
    end)
    SetTimeout(math.floor((quote.timeout + 5) * 1000), function()
        settle(nil)
    end)
    return Citizen.Await(p)
end

-- Quote of the mechanic waiting for the customer ends without an answer (menu closed, mechanic left, order cancelled),
-- the window / dialog on the customer's screen closes (the client tells the customer itself)
local function closeQuote(mechanicSrc)
    local pending = Approving[mechanicSrc]
    if pending and pending.settle and Quotes[pending.customer] == pending.settle then
        pending.settle(nil)
        TriggerClientEvent("pls_mechanic:client:tuning:quoteClose", pending.customer)
    end
end

--[[
   ____          _
  / __ \        | |
 | |  | |_ __ __| | ___ _ __ ___
 | |  | | '__/ _` |/ _ \ '__/ __|
 | |__| | | | (_| |  __/ |  \__ \
  \____/|_|  \__,_|\___|_|  |___/
]]--

-- Installed changes (applied keys, another rim set replaces ordered rims) and values already on the vehicle leave the
-- open order, nothing left = done (customer notified, the order stays ORDER_GRACE)
local function purgeOrder(order, state, appliedKeys, wheels)
    local total = 0
    for i = #order.changes, 1, -1 do
        local change = order.changes[i]
        local entry = Categories[change.key]
        if not entry or (appliedKeys and appliedKeys[change.key]) or (wheels and entry.type == "wheels")
            or sameValue(readValue(entry, state), change.value) then
            table.remove(order.changes, i)
        else
            total = total + change.price
        end
    end
    order.total = total
    if #order.changes > 0 then return end

    order.status, order.touched = "done", os.time()
    local customerSrc = getCustomerSrc(order.customer)
    if customerSrc then
        Shops.Notify(customerSrc, locale("tuning_order_done", order.visiblePlate), "success")
    end
end

-- Customer cancelled his order: mechanic sessions working on it refuse further changes, their quotes close
local function cancelOrder(order)
    order.status, order.touched = "cancelled", os.time()
    for mechanic, session in pairs(Internal.Sessions) do
        if session.orderId == order.id then
            session.approved, session.approvedOrderId, session.orderCancelled = nil, nil, true
            closeQuote(mechanic)
            Shops.Notify(mechanic, locale("tuning_order_cancelled_by_customer"), "error")
        end
    end
end

-- Order of the customer (src) for the vehicle of his catalog session (the session stays until catalog:close, a failed
-- revert of the preview is handled there). Returns result
local function submitOrder(src, session, shop, entity, changes)
    local plate = session.plate

    -- empty order = cancel (only the customer who sent it, anybody when it expired), also while a mechanic works on it
    if #changes == 0 then
        local current = Orders[plate]
        if not current or current.status ~= "open" then return fail("tuning_nothing_to_confirm") end
        if isExpired(current) then
            Orders[plate] = nil
        elseif isCustomer(current, src) then
            cancelOrder(current)
        else
            return fail("tuning_order_not_yours")
        end
        return { ok = true, total = 0, message = locale("tuning_order_cancelled", session.visiblePlate) }
    end
    if #changes > Config.Tuning.MaxChanges then return fail("tuning_too_many", Config.Tuning.MaxChanges) end

    -- an order of another customer stays (only he can replace or cancel it), a done / cancelled one too until
    -- ORDER_GRACE ends (otherwise the mechanic would replace it with his own order, approved by himself)
    local previous = Orders[plate]
    if previous and not isExpired(previous) and not isCustomer(previous, src) then
        return fail("tuning_order_not_yours")
    end
    -- open orders of the customer on other vehicles
    local count = 0
    for otherPlate, other in pairs(Orders) do
        if otherPlate ~= plate and other.status == "open" and not isExpired(other) and isCustomer(other, src) then
            count = count + 1
        end
    end
    if count >= ORDER_LIMIT then return fail("tuning_order_limit", ORDER_LIMIT) end

    local list, err = collectChanges(changes, session.state, { isEv = Internal.isElectric(GetEntityModel(entity)) })
    if not list then return err end
    if #list == 0 then return fail("tuning_nothing_to_confirm") end
    local final = Utils.DeepCopy(session.state)
    for _, change in ipairs(list) do
        writeValue(change.entry, final, change.value)
    end
    local requirementsOk, requirementMessage = Internal.checkRequirements(list, final)
    if not requirementsOk then
        return { ok = false, message = requirementMessage }
    end

    -- prices with the markup of the workshop (same as processConfirm)
    local markup = markupOf(shop)
    local items, total = {}, 0
    for i, change in ipairs(list) do
        local price = withMarkup(basePrice(change.entry, change.value), markup)
        total = total + price
        items[i] = {
            key = change.entry.key,
            value = change.value,
            price = price,
            label = catLabel(change.entry)..": "..valueLabel(change.entry, change.value),
        }
    end

    -- mechanics are notified only about a new / changed order, at most once per NOTIFY_INTERVAL per plate
    local changed = not previous or isExpired(previous) or previous.shopId ~= shop.id or not sameItems(previous, items)
    local name = Internal.getPlayerName(src)
    local now = os.time()
    OrderCounter = OrderCounter + 1
    Orders[plate] = {
        id = OrderCounter,
        plate = plate,
        visiblePlate = session.visiblePlate,
        shopId = shop.id,
        netId = session.netId,
        customer = { src = src, charId = getCharId(src), name = name },
        changes = items,
        total = total,
        created = now,
        touched = now,
        status = "open",
    }

    if changed and now - (Notified[plate] or 0) >= NOTIFY_INTERVAL then
        Notified[plate] = now
        local text = locale("tuning_order_new", session.visiblePlate, #items, money(total))
        for _, mechanic in ipairs(getMechanics(shop)) do
            if mechanic ~= src then
                Shops.Notify(mechanic, text, "inform")
            end
        end
    end

    OpenServer.Log(src, "tuning_order", locale("tuning_order_log", name, session.visiblePlate, money(total)), {
        plate = plate,
        shopId = shop.id,
        total = total,
        changes = items,
    })
    return { ok = true, total = total, message = locale("tuning_order_sent", money(total)) }
end

--[[
   _____      _ _ _                _
  / ____|    | | | |              | |
 | |     __ _| | | |__   __ _  ___| | _____
 | |    / _` | | | '_ \ / _` |/ __| |/ / __|
 | |___| (_| | | | |_) | (_| | (__|   <\__ \
  \_____\__,_|_|_|_.__/ \__,_|\___|_|\_\___/
]]--

-- Customer opens the catalog: stores tuning state of the vehicle (tuning subset of lib.getVehicleProperties)
lib.callback.register("pls_mechanic:server:catalog:open", function(src, netId, state)
    if not Catalog.enabled then return fail("tuning_catalog_disabled") end
    if Internal.rateLimited(src, "catalog_open", 1000) then return fail("tuning_wait") end
    netId = toInt(netId)
    if not netId or type(state) ~= "table" then return fail("no_vehicle") end

    local entity = Shops.GetEntity(netId)
    if not entity or GetEntityType(entity) ~= 2 then return fail("no_vehicle") end
    local vehicleType = GetVehicleType(entity)
    if vehicleType and Internal.BLOCKED_TYPES[vehicleType] then return fail("tuning_vehicle_not_supported") end
    if not Shops.IsNearEntity(src, entity, Catalog.maxDistance or 6.0) then return fail("too_far") end
    local shop = findShopAt(GetEntityCoords(entity))
    if not shop then return fail("tuning_catalog_not_in_bay") end
    if Catalog.requireMechanic and #getMechanics(shop, 1) == 0 then return fail("tuning_catalog_no_mechanic") end
    -- repair, lift, jack, towing, mission, service vehicle (same rules as the IsVehicleBusy export, tuning below)
    if Vehicles.GetBusyReason(entity, true) then return fail("tuning_vehicle_busy") end

    -- trusted plate of the entity (fake plate = order of the real plate), same as tuning:open
    local plate, _, visiblePlate = Vehicles.GetEntityPlate(entity)
    if not plate then return fail("no_vehicle") end
    visiblePlate = visiblePlate or plate
    -- locks right before the session (nothing may yield in between): mechanic menu, another catalog, a revert of an
    -- ended session (the opener applies it first)
    if Internal.isVehicleInUse(netId, src) then return fail("tuning_in_use") end
    if CatalogServer.IsVehicleInCatalog(netId, src) then return fail("tuning_in_use_customer") end
    if Internal.revertPending(netId, entity) then return fail("tuning_wait") end
    CatalogSessions[src] = {
        netId = netId,
        plate = plate,
        visiblePlate = visiblePlate,
        rawPlate = plate ~= visiblePlate and plate or GetVehicleNumberPlateText(entity),
        shopId = shop.id,
        state = Internal.sanitizeState(state),
        activity = os.time(),
    }
    -- only his own pending order (another customer's order isn't shown, he can't replace it)
    local order = getOpenOrder(plate)
    if order and not isCustomer(order, src) then
        order = nil
    end
    return {
        ok = true,
        shopId = shop.id,
        shopName = shop.name,
        markup = markupOf(shop),
        performance = Catalog.performance == true,
        order = order and { changes = orderChanges(order), total = order.total, minutes = minutesAgo(order) } or nil,
    }
end)

-- changes = { { key, value } }, empty = cancel the order of the vehicle
lib.callback.register("pls_mechanic:server:catalog:submit", function(src, netId, changes)
    if Internal.rateLimited(src, "catalog_submit", 2000) then return fail("tuning_wait") end
    local session = CatalogSessions[src]
    if not session or session.netId ~= toInt(netId) then return fail("tuning_session_expired") end
    if not Catalog.enabled then return fail("tuning_catalog_disabled") end

    local shop = Shops.Get(session.shopId)
    local entity = Shops.GetEntity(session.netId)
    if not shop or not shopAllowed(shop) or not entity or GetEntityType(entity) ~= 2 then return fail("tuning_session_expired") end
    if not Shops.IsNearEntity(src, entity, Catalog.maxDistance or 6.0) then return fail("too_far") end
    if not Internal.findTuningBay(shop, GetEntityCoords(entity)) then return fail("tuning_catalog_not_in_bay") end
    local plate, _, visiblePlate = Vehicles.GetEntityPlate(entity)
    if plate ~= session.plate or (visiblePlate or plate) ~= session.visiblePlate then return fail("tuning_session_expired") end
    if type(changes) ~= "table" then return fail("tuning_nothing_to_confirm") end
    -- the customer can always cancel, a new order waits until the mechanic is done with the vehicle
    if #changes > 0 and mechanicOnPlate(plate) then return fail("tuning_in_use") end

    local ok, result = pcall(submitOrder, src, session, shop, entity, changes)
    if not ok then
        print("[pls_mechanic] catalog submit error: "..tostring(result))
        return fail("tuning_failed")
    end
    -- the client closes the catalog now (catalog:close), without it the session ends after SUBMIT_CLOSE
    if result.ok then
        session.submitted = os.time()
    end
    return result
end)

-- Mechanic confirms changes on a vehicle with a customer order: ordered changes pass, other changes go to the customer
-- as a quote. Approved changes are stored in the session (processConfirm refuses the rest)
lib.callback.register("pls_mechanic:server:tuning:approve", function(src, netId, changes)
    if Approving[src] or Internal.rateLimited(src, "approve", 1000) then return fail("tuning_wait") end
    local session = Internal.Sessions[src]
    if not session or session.netId ~= toInt(netId) then return fail("tuning_session_expired") end
    -- a new approval replaces the previous one (also a refused one)
    session.approved, session.approvedOrderId = nil, nil
    local order = Catalog.enabled and Catalog.approval and getOrder(session.plate, session.shopId) or nil
    if not order then return { ok = true } end
    if session.orderCancelled and session.orderId == order.id then return fail("tuning_order_cancelled_by_customer") end

    if type(changes) ~= "table" or #changes == 0 then return fail("tuning_nothing_to_confirm") end
    if #changes > Config.Tuning.MaxChanges then return fail("tuning_too_many", Config.Tuning.MaxChanges) end
    local list, err = collectChanges(changes, session.state)
    if not list then return err end

    local approved, extras = {}, 0
    for _, change in ipairs(list) do
        approved[change.entry.key] = change.value
        if not inOrder(order, change.entry.key, change.value) then
            extras = extras + 1
        end
    end
    local customerSrc = getCustomerSrc(order.customer)
    -- only ordered changes / the mechanic's own order
    if extras == 0 or customerSrc == src then
        session.approved, session.approvedOrderId = approved, order.id
        return { ok = true }
    end

    local shop = Shops.Get(session.shopId)
    local entity = Shops.GetEntity(session.netId)
    if not shop or not entity then return fail("tuning_session_expired") end
    if not customerSrc or not Shops.IsNearEntity(customerSrc, entity, Catalog.approvalDistance or 30.0) then
        return fail("tuning_quote_customer_away")
    end
    -- the customer answers another quote right now
    if Quotes[customerSrc] then return fail("tuning_wait") end
    -- after a declined / unanswered quote the next one waits QUOTE_COOLDOWN, at most QUOTE_LIMIT quotes per order
    local wait = (order.quoteCooldown or 0) - os.time()
    if wait > 0 then return fail("tuning_quote_cooldown", wait) end
    if (order.quotes or 0) >= QUOTE_LIMIT then return fail("tuning_quote_limit") end

    local markup = markupOf(shop)
    local items, total, extraTotal = {}, 0, 0
    for i, change in ipairs(list) do
        local price = withMarkup(basePrice(change.entry, change.value), markup)
        local ordered = inOrder(order, change.entry.key, change.value)
        items[i] = { label = catLabel(change.entry), value = valueLabel(change.entry, change.value), price = price, ordered = ordered }
        total = total + price
        if not ordered then
            extraTotal = extraTotal + price
        end
    end
    local quote = {
        shop = shop.name,
        mechanic = Internal.getPlayerName(src),
        plate = session.visiblePlate,
        items = items,
        extraTotal = extraTotal,
        total = total,
        timeout = tonumber(Catalog.approvalTimeout) or 60,
    }

    local pending = { customer = customerSrc, order = order }
    Approving[src] = pending
    order.quotes = (order.quotes or 0) + 1
    local answer = requestQuote(customerSrc, quote, pending)
    if Approving[src] == pending then
        Approving[src] = nil
    end
    -- the mechanic closed the menu meanwhile
    if Internal.Sessions[src] ~= session then return fail("tuning_session_expired") end
    -- the customer cancelled the order meanwhile
    if session.orderCancelled and session.orderId == order.id then return fail("tuning_order_cancelled_by_customer") end
    if answer == true then
        session.approved, session.approvedOrderId = approved, order.id
        session.activity = os.time()
        return { ok = true }
    end
    order.quoteCooldown = os.time() + QUOTE_COOLDOWN
    return fail(answer == false and "tuning_quote_declined" or "tuning_quote_expired")
end)

-- reverted = the client reverted the preview with network control, otherwise the revert statebag does it
RegisterNetEvent("pls_mechanic:server:catalog:close", function(reverted)
    local src = source
    if not CanTrustPlayer(src) then return end
    local session = CatalogSessions[src]
    CatalogSessions[src] = nil
    if session and reverted ~= true then
        Internal.setRevert(session)
    end
end)

--[[
  ______               _
 |  ____|             | |
 | |____   _____ _ __ | |_ ___
 |  __\ \ / / _ \ '_ \| __/ __|
 | |___\ V /  __/ | | | |_\__ \
 |______\_/ \___|_| |_|\__|___/
]]--

-- Customer left during the catalog: the revert statebag reverts the preview, his quote ends without an answer.
-- Mechanic left while his quote waits: the quote closes on the customer's screen
AddEventHandler("playerDropped", function()
    local src = source
    local session = CatalogSessions[src]
    CatalogSessions[src] = nil
    closeQuote(src)
    Approving[src] = nil
    if Quotes[src] then
        Quotes[src](nil)
    end
    if not session then return end
    -- stale session (no heartbeat): only when nobody else works on the vehicle meanwhile
    if os.time() - session.activity > Config.Tuning.SessionTimeout * 60 and TuningServer.IsVehicleInTuning(session.netId) then return end
    Internal.setRevert(session)
end)

-- Expired orders (customer notified, done / cancelled ones just leave) and stale catalog sessions (no heartbeat)
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for plate, order in pairs(Orders) do
            if isExpired(order) then
                Orders[plate] = nil
                local customerSrc = order.status == "open" and getCustomerSrc(order.customer) or nil
                if customerSrc then
                    Shops.Notify(customerSrc, locale("tuning_order_expired", order.visiblePlate), "error")
                end
            end
        end
        for plate, time in pairs(Notified) do
            if now - time >= NOTIFY_INTERVAL then
                Notified[plate] = nil
            end
        end
        for src, session in pairs(CatalogSessions) do
            if not GetPlayerName(src) or now - session.activity > Config.Tuning.SessionTimeout * 60
                or (session.submitted and now - session.submitted > SUBMIT_CLOSE) then
                CatalogSessions[src] = nil
                -- the preview is reverted unless somebody else works on the vehicle meanwhile
                if not TuningServer.IsVehicleInTuning(session.netId) then
                    Internal.setRevert(session)
                end
            end
        end
    end
end)

--[[
  _____       _     _ _
 |  __ \     | |   | (_)
 | |__) |   _| |__ | |_  ___
 |  ___/ | | | '_ \| | |/ __|
 | |   | |_| | |_) | | | (__
 |_|    \__,_|_.__/|_|_|\___|
]]--

-- A customer has the catalog open on this vehicle (exceptSrc = ignore this player)
function CatalogServer.IsVehicleInCatalog(netId, exceptSrc)
    local now = os.time()
    for src, session in pairs(CatalogSessions) do
        if src ~= exceptSrc and session.netId == netId and GetPlayerName(src)
            and now - session.activity <= Config.Tuning.SessionTimeout * 60 then
            return true
        end
    end
    return false
end

-- Mechanic opens tuning (tuning:open, before his session exists): the order of the plate for his workshop is bound to
-- the session, ordered values already on the vehicle leave it (nothing left = done). A done / cancelled order
-- (ORDER_GRACE) binds too, nothing is ordered then. Returns { customer, changes = { { key, value } }, total, minutes } or nil
function CatalogServer.BindOrder(session)
    local order = Catalog.enabled and getOrder(session.plate, session.shopId) or nil
    if not order then return nil end
    session.orderId = order.id
    order.touched = os.time()
    if order.status == "open" then
        purgeOrder(order, session.state)
    end
    local open = order.status == "open"
    return {
        customer = order.customer.name,
        changes = open and orderChanges(order) or {},
        total = open and order.total or 0,
        minutes = minutesAgo(order),
    }
end

-- Heartbeat of the client (tuning:heartbeat): the catalog session isn't stale, the order the mechanic works on
-- doesn't expire. session = mechanic session of the player or nil
function CatalogServer.OnHeartbeat(src, session)
    local catalogSession = CatalogSessions[src]
    if catalogSession then
        catalogSession.activity = os.time()
    end
    local order = session and session.orderId and Orders[session.plate]
    if order and order.id == session.orderId then
        order.touched = os.time()
    end
end

-- Mechanic session ended (menu closed, stale): his quote waiting for the customer closes
function CatalogServer.OnSessionClosed(src)
    closeQuote(src)
end

-- processConfirm: every applied change is in the order or approved by the customer (quote of this order) with the same
-- value. The customer cancelled the order during the session = nothing more. Returns ok, locale key
function CatalogServer.CheckApproved(session, applied)
    if not Catalog.enabled or not Catalog.approval then return true end
    local order = getOrder(session.plate, session.shopId)
    if not order then return true end
    if session.orderCancelled and session.orderId == order.id then return false, "tuning_order_cancelled_by_customer" end
    local approvedList = session.approvedOrderId == order.id and session.approved or nil
    for _, change in ipairs(applied) do
        local key = change.entry.key
        local approved = approvedList and approvedList[key]
        if not inOrder(order, key, change.value) and (approved == nil or not sameValue(approved, change.value)) then
            return false, "tuning_quote_required"
        end
    end
    return true
end

-- processConfirm succeeded: applied keys (and changes already on the vehicle) leave the order, empty order = done
function CatalogServer.OnConfirmed(session, applied)
    local order = getOrder(session.plate, session.shopId)
    if not order then return end
    order.touched = os.time()
    if order.status ~= "open" then return end
    local appliedKeys, wheels = {}, false
    for _, change in ipairs(applied) do
        appliedKeys[change.entry.key] = true
        -- one rim set: another wheel type replaces the ordered one
        if change.entry.type == "wheels" then wheels = true end
    end
    purgeOrder(order, session.state, appliedKeys, wheels)
end
