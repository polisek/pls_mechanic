--[[
  ____  _ _ _ _
 |  _ \(_) | (_)
 | |_) |_| | |_ _ __   __ _
 |  _ <| | | | | '_ \ / _` |
 | |_) | | | | | | | | (_| |
 |____/|_|_|_|_|_| |_|\__, |
                       __/ |
                      |___/
 Mechanic creates itemized bill (prefilled from WorkLog), customer pays by cash / bank or declines.
 Paid bill: workshop society gets total - commission, mechanic gets commission (society keeps it when mechanic is offline).
 Illegal workshop: no society, the customer pays cash and it goes directly to the mechanic (who must be online).
 Bill status: pending / paid / declined / expired. Bills are bound to character ids (survive reconnect).
]]--

BillingServer = {}

local Cfg = Config.Billing
local PAGE_SIZE = 20
local Prices = {}         -- [item key] = supplier price
local Cooldowns = {}      -- [src][action] = GetGameTimer()

for _, entry in ipairs(Config.Supplier.catalog) do
    Prices[entry.item] = entry.price
end

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

local function formatMoney(value)
    local formatted = tostring(math.floor(value or 0))
    local k
    repeat
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
    until k == 0
    return Config.Currency..formatted
end

local function fail(message)
    return { ok = false, message = message }
end

local function checkRate(src, action, ms)
    Cooldowns[src] = Cooldowns[src] or {}
    local now = GetGameTimer()
    local last = Cooldowns[src][action]
    if last and now - last < ms then
        return false
    end
    Cooldowns[src][action] = now
    return true
end

local function getPlayerName(src)
    local ok, name = pcall(BRIDGE.GetPlayerFullName, src)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return GetPlayerName(src) or ("ID "..tostring(src))
end

local function getCharId(src)
    local ok, charId = pcall(BRIDGE.GetPlayerCharId, src)
    if ok and charId then
        return tostring(charId)
    end
    return nil
end

local function getPlayerByCharId(charId)
    if not charId then return nil end
    for _, playerId in pairs(GetPlayers()) do
        local src = tonumber(playerId)
        if getCharId(src) == charId then
            return src
        end
    end
    return nil
end

local function log(src, action, message, data)
    local ok, err = pcall(OpenServer.Log, src, action, message, data)
    if not ok then
        print("[pls_mechanic] OpenServer.Log error: "..tostring(err))
    end
end

-- Single line text, trimmed, max characters (UTF-8 safe)
local function cutText(value, maxChars)
    if type(value) ~= "string" and type(value) ~= "number" then return "" end
    local text = tostring(value):gsub("%c", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local length = utf8.len(text)
    if not length then
        text = text:gsub("[\128-\255]", "")
        length = #text
    end
    if length > maxChars then
        text = text:sub(1, utf8.offset(text, maxChars + 1) - 1)
    end
    return text
end

local function isPlayerNear(src, target, maxDistance)
    if not target or target == src or not GetPlayerName(target) then return false end
    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(target)
    if not ped or ped == 0 or not targetPed or targetPed == 0 then return false end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then return false end
    return #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) <= maxDistance
end

-- Bill of illegal workshop: cash only, straight to the mechanic
local function isCashOnly(shopId)
    return Shops.IsIllegal(shopId)
end

local function isMethodAllowed(method, shopId)
    if method ~= "cash" and method ~= "bank" then return false end
    if isCashOnly(shopId) then return method == "cash" end
    for _, v in pairs(Cfg.methods) do
        if v == method then return true end
    end
    return false
end

local function getBalance(src, method)
    if method == "cash" then
        return BRIDGE.GetItemCount(src, "money") or 0
    end
    return BRIDGE.GetPlayerBankMoney(src) or 0
end

local function isExpired(row)
    return (Cfg.expireMinutes or 0) > 0 and os.time() - (row.created_at or 0) > Cfg.expireMinutes * 60
end

local function decodeLines(value)
    local ok, lines = pcall(json.decode, value or "[]")
    if ok and type(lines) == "table" then
        return lines
    end
    return {}
end

-- NUI "bill" data for customer
local function buildPayload(src, row)
    local shop = Shops.Get(row.shop_id)
    local cashOnly = isCashOnly(row.shop_id)
    local methods, balances = {}, { cash = 0, bank = 0 }
    for _, method in ipairs(cashOnly and { "cash" } or Cfg.methods) do
        if isMethodAllowed(method, row.shop_id) then
            table.insert(methods, method)
            balances[method] = math.floor(getBalance(src, method))
        end
    end
    return {
        id = row.id,
        shopName = shop and shop.name or "-",
        mechanicName = row.mechanic_name or "-",
        plate = row.plate,
        lines = decodeLines(row.lines),
        total = row.total,
        note = (row.note and row.note ~= "") and row.note or nil,
        methods = methods,
        balances = balances,
        cashOnly = cashOnly,
    }
end

-- WorkLog entry price: final price (tuning) or labor * laborMultiplier + supplier price of parts * (1 + partsMarkup %)
local function entryPrice(entry, shop)
    local price = tonumber(entry.price)
    if not price then
        local settings = shop and shop.settings or {}
        local markup = 1 + (tonumber(settings.partsMarkup) or 0) / 100
        price = (tonumber(entry.labor) or 0) * (tonumber(settings.laborMultiplier) or 1.0)
        for _, v in pairs(entry.items or {}) do
            price = price + (Prices[v.item] or 0) * (tonumber(v.count) or 0) * markup
        end
    end
    return math.floor(Utils.Clamp(price, 0, Cfg.maxLinePrice) + 0.5)
end

-- Bill lines from work done by mechanic on vehicle (WorkLog), same label + price are merged
local function buildLines(src, shop, plate)
    local lines, index = {}, {}
    for _, entry in ipairs(WorkLog.Get(src, plate)) do
        local price = entryPrice(entry, shop)
        local label = cutText(entry.label or "-", 60)
        local key = label.."|"..price
        if index[key] then
            index[key].qty = math.min(99, index[key].qty + 1)
        elseif #lines < Cfg.maxLines then
            local line = { label = label, qty = 1, price = price }
            table.insert(lines, line)
            index[key] = line
        end
    end
    return lines
end

-- Validates lines from NUI. Returns lines, total or nil, message
local function parseLines(input)
    if type(input) ~= "table" or #input == 0 then return nil, locale("bill_total_zero") end
    if #input > Cfg.maxLines then return nil, locale("bill_too_many_lines", Cfg.maxLines) end
    local lines, total = {}, 0
    for i = 1, #input do
        local line = input[i]
        if type(line) ~= "table" then return nil, locale("bill_invalid_lines") end
        local label = cutText(line.label, 60)
        local qty = tonumber(line.qty)
        local price = tonumber(line.price)
        if label == "" or not qty or not price or qty ~= math.floor(qty) or price ~= math.floor(price) then
            return nil, locale("bill_invalid_lines")
        end
        if qty < 1 or qty > 99 or price < 0 or price > Cfg.maxLinePrice then
            return nil, locale("bill_invalid_lines")
        end
        qty, price = math.floor(qty), math.floor(price)
        total = total + qty * price
        table.insert(lines, { label = label, qty = qty, price = price })
    end
    if total <= 0 then return nil, locale("bill_total_zero") end
    if total > Cfg.maxTotal then return nil, locale("bill_total_too_high", formatMoney(Cfg.maxTotal)) end
    return lines, total
end

-- Pending bill of this customer. Returns row or nil, message
local function getCustomerBill(src, id)
    id = tonumber(id)
    if not id then return nil, locale("bill_invalid") end
    local row = MySQL.single.await("SELECT * FROM `pls_mechanic_bills` WHERE `id` = ?", { id })
    if not row or row.customer ~= getCharId(src) then return nil, locale("bill_invalid") end
    if row.status ~= "pending" then return nil, locale("bill_already_handled") end
    if isExpired(row) then
        MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'expired' WHERE `id` = ? AND `status` = 'pending'", { row.id })
        return nil, locale("bill_expired")
    end
    return row
end

local function expireBills()
    if (Cfg.expireMinutes or 0) <= 0 then return end
    MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'expired' WHERE `status` = 'pending' AND `created_at` < ?", { os.time() - Cfg.expireMinutes * 60 })
end

--[[
  _____       _     _ _
 |  __ \     | |   | (_)
 | |__) |   _| |__ | |_  ___
 |  ___/ | | | '_ \| | |/ __|
 | |   | |_| | |_) | | | (__
 |_|    \__,_|_.__/|_|_|\___|
]]--

-- Price of one WorkLog entry as it appears on the bill of the workshop
function BillingServer.GetEntryPrice(entry, shopId)
    return entryPrice(entry or {}, Shops.Get(shopId))
end

--[[
   _____      _ _ _                _
  / ____|    | | | |              | |
 | |     __ _| | | |__   __ _  ___| | _____
 | |    / _` | | | '_ \ / _` |/ __| |/ / __|
 | |___| (_| | | | |_) | (_| | (__|   <\__ \
  \_____\__,_|_|_|_.__/ \__,_|\___|_|\_\___/
]]--

-- Mechanic opens bill creation. nearby = server ids seen by client, filtered by server distance.
lib.callback.register("pls_mechanic:server:billing:prepare", function(src, plate, nearby)
    local allowed, shopId = Shops.HasPermission(src, "billing")
    if not allowed then return fail(locale(shopId and "no_permission" or "not_on_duty")) end
    local shop = Shops.Get(shopId)
    plate = cutText(Utils.TrimPlate(type(plate) == "string" and plate or nil) or "", 12)
    if plate == "" then plate = nil end

    local customers = {}
    for _, id in pairs(type(nearby) == "table" and nearby or {}) do
        id = tonumber(id)
        if id and isPlayerNear(src, id, Cfg.distance + 2.0) then
            table.insert(customers, { serverId = id, name = getPlayerName(id) })
        end
        if #customers >= 20 then break end
    end

    -- illegal workshop: the whole cash payment goes to the mechanic
    local cashOnly = isCashOnly(shop.id)
    return {
        ok = true,
        data = {
            shopId = shop.id,
            shopName = shop.name,
            plate = plate,
            customers = customers,
            lines = plate and buildLines(src, shop, plate) or {},
            commission = cashOnly and 100 or math.floor(tonumber(shop.settings.commission) or 0),
            cashOnly = cashOnly,
            maxLines = Cfg.maxLines,
            maxLinePrice = Cfg.maxLinePrice,
            maxTotal = Cfg.maxTotal,
            maxNoteLength = Cfg.maxNoteLength,
        },
    }
end)

-- NUI "billCreate:send" { target, plate?, lines, note }
lib.callback.register("pls_mechanic:server:billing:send", function(src, data)
    if type(data) ~= "table" then return fail(locale("bill_invalid")) end
    local allowed, shopId = Shops.HasPermission(src, "billing")
    if not allowed then return fail(locale(shopId and "no_permission" or "not_on_duty")) end
    if not checkRate(src, "send", (Cfg.sendCooldown or 5) * 1000) then return fail(locale("bill_cooldown")) end

    local target = tonumber(data.target)
    if not target or not isPlayerNear(src, target, Cfg.distance + 2.0) then return fail(locale("bill_no_target")) end
    local lines, totalOrError = parseLines(data.lines)
    if not lines then return fail(totalOrError) end
    local total = totalOrError

    local mechanicId, customerId = getCharId(src), getCharId(target)
    if not mechanicId or not customerId then return fail(locale("bill_no_target")) end
    local pending = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `pls_mechanic_bills` WHERE `customer` = ? AND `status` = 'pending'", { customerId })) or 0
    if pending >= Cfg.maxPending then return fail(locale("bill_too_many_pending")) end

    local shop = Shops.Get(shopId)
    local plate = type(data.plate) == "string" and cutText(Utils.TrimPlate(data.plate), 12) or ""
    -- the bill keeps the real plate: the work log is cleared on payment even when the fake plate is gone by then
    if plate ~= "" and Vehicles and Vehicles.ResolvePlate then
        plate = cutText(Vehicles.ResolvePlate(plate) or plate, 12)
    end
    local note = cutText(data.note, Cfg.maxNoteLength or 200)
    local mechanicName, customerName = getPlayerName(src), getPlayerName(target)
    local now = os.time()
    local encodedLines = json.encode(lines)
    local id = MySQL.insert.await("INSERT INTO `pls_mechanic_bills` (`shop_id`, `mechanic`, `mechanic_name`, `customer`, `customer_name`, `plate`, `lines`, `note`, `total`, `status`, `created_at`) VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, ''), ?, 'pending', ?)", {
        shop.id, mechanicId, mechanicName, customerId, customerName, plate, encodedLines, note, total, now,
    })
    if not id then return fail(locale("bill_invalid")) end

    local row = {
        id = id, shop_id = shop.id, mechanic_name = mechanicName, plate = plate ~= "" and plate or nil,
        lines = encodedLines, note = note, total = total, created_at = now,
    }
    TriggerClientEvent("pls_mechanic:client:billing:received", target, buildPayload(target, row))
    log(src, "bill_create", ("Bill #%s for %s to %s (%s)"):format(id, formatMoney(total), customerName, shop.name), { id = id, shopId = shop.id, customer = customerId, plate = row.plate, lines = lines, total = total })
    return { ok = true, message = locale("bill_sent", formatMoney(total), customerName) }
end)

-- Fresh "bill" data of a pending bill (queued bills, balances)
lib.callback.register("pls_mechanic:server:billing:get", function(src, id)
    local row, err = getCustomerBill(src, id)
    if not row then return fail(err) end
    return { ok = true, bill = buildPayload(src, row) }
end)

-- Pending bills of customer, optionally only of one workshop (payment terminal)
lib.callback.register("pls_mechanic:server:billing:pending", function(src, shopId)
    if not checkRate(src, "pending", 1000) then return {} end
    local charId = getCharId(src)
    if not charId then return {} end
    expireBills()
    shopId = tonumber(shopId)
    local rows
    if shopId then
        rows = MySQL.query.await("SELECT * FROM `pls_mechanic_bills` WHERE `customer` = ? AND `status` = 'pending' AND `shop_id` = ? ORDER BY `id` ASC LIMIT 20", { charId, shopId })
    else
        rows = MySQL.query.await("SELECT * FROM `pls_mechanic_bills` WHERE `customer` = ? AND `status` = 'pending' ORDER BY `id` ASC LIMIT 20", { charId })
    end
    local bills = {}
    for _, row in ipairs(rows or {}) do
        table.insert(bills, buildPayload(src, row))
    end
    return bills
end)

-- Illegal workshop bill: cash from the customer straight to the online mechanic, no society, no commission split
local function payCash(src, row)
    local total = math.floor(row.total or 0)
    if getBalance(src, "cash") < total then return fail(locale("not_enough_money")) end
    local mechanicSrc = getPlayerByCharId(row.mechanic)
    if not mechanicSrc then return fail(locale("bill_mechanic_offline")) end

    local now = os.time()
    local affected = MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'paid', `paid_at` = ? WHERE `id` = ? AND `status` = 'pending'", { now, row.id })
    if not affected or affected < 1 then return fail(locale("bill_already_handled")) end
    if getBalance(src, "cash") < total or BRIDGE.RemoveItem(src, "money", total) == false then
        MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'pending', `paid_at` = NULL WHERE `id` = ?", { row.id })
        return fail(locale("not_enough_money"))
    end
    if not GetPlayerName(mechanicSrc) or BRIDGE.AddItem(mechanicSrc, "money", total) == false then
        -- mechanic left / can't carry it, the customer gets the cash back
        BRIDGE.AddItem(src, "money", total)
        MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'pending', `paid_at` = NULL WHERE `id` = ?", { row.id })
        return fail(locale("bill_mechanic_offline"))
    end

    local customerName = row.customer_name or getPlayerName(src)
    if row.plate then
        WorkLog.Clear(mechanicSrc, row.plate)
    end
    Shops.Notify(mechanicSrc, locale("bill_paid_mechanic_cash", customerName, formatMoney(total)), "success")

    local bill = {
        id = row.id,
        shopId = row.shop_id,
        illegal = true,
        mechanic = row.mechanic,
        mechanicName = row.mechanic_name,
        customer = row.customer,
        customerName = customerName,
        plate = row.plate,
        lines = decodeLines(row.lines),
        note = row.note,
        total = total,
        commission = total,
        method = "cash",
        paidAt = now,
    }
    local ok, hookErr = pcall(OpenServer.OnBillPaid, bill)
    if not ok then
        print("[pls_mechanic] OpenServer.OnBillPaid error: "..tostring(hookErr))
    end
    log(src, "bill_paid", ("Bill #%s of illegal workshop #%s paid in cash (%s) to the mechanic"):format(row.id, row.shop_id, formatMoney(total)), bill)
    return { ok = true, message = locale("bill_paid_customer_cash", formatMoney(total)) }
end

-- NUI "bill:pay" { id, method }
lib.callback.register("pls_mechanic:server:billing:pay", function(src, id, method)
    if not checkRate(src, "pay", 1500) then return fail(locale("bill_cooldown")) end
    if method ~= "cash" and method ~= "bank" then return fail(locale("bill_method_invalid")) end
    local row, err = getCustomerBill(src, id)
    if not row then return fail(err) end
    if isCashOnly(row.shop_id) then
        if method ~= "cash" then return fail(locale("bill_cash_only")) end
        return payCash(src, row)
    end
    if not isMethodAllowed(method, row.shop_id) then return fail(locale("bill_method_invalid")) end
    local total = math.floor(row.total or 0)
    if getBalance(src, method) < total then return fail(locale("not_enough_money")) end
    -- money would be lost without society account of the workshop
    local societyJob = Shops.GetSocietyJob(row.shop_id)
    if societyJob and not BRIDGE.HasSocietyAccount(societyJob) then
        return fail(locale("bill_no_society"))
    end

    -- claim the bill first (double click / two tabs), then take money
    local now = os.time()
    local affected = MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'paid', `paid_at` = ? WHERE `id` = ? AND `status` = 'pending'", { now, row.id })
    if not affected or affected < 1 then return fail(locale("bill_already_handled")) end
    if getBalance(src, method) < total then
        MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'pending', `paid_at` = NULL WHERE `id` = ?", { row.id })
        return fail(locale("not_enough_money"))
    end
    local paid
    if method == "cash" then
        paid = BRIDGE.RemoveItem(src, "money", total) ~= false
    else
        paid = BRIDGE.RemovePlayerBankMoney(src, total)
    end
    if not paid then
        MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'pending', `paid_at` = NULL WHERE `id` = ?", { row.id })
        return fail(locale("not_enough_money"))
    end

    -- payout: society gets total - commission, online mechanic gets commission
    local shop = Shops.Get(row.shop_id)
    local percent = Utils.Clamp(tonumber(shop and shop.settings.commission) or 0, 0, 100)
    local mechanicSrc = getPlayerByCharId(row.mechanic)
    local commission = mechanicSrc and math.floor(total * percent / 100) or 0
    if not societyJob and mechanicSrc then
        commission = total
    end
    if societyJob and total - commission > 0 then
        if not BRIDGE.AddSocietyMoney(societyJob, total - commission) then
            OpenServer.Log(src, "bill_society_failed", ("Bill #%s: %d could not be added to society of %s"):format(row.id, total - commission, societyJob), { billId = row.id })
        end
    end
    if mechanicSrc and commission > 0 then
        if Cfg.commissionPayout == "cash" then
            BRIDGE.AddItem(mechanicSrc, "money", commission)
        else
            BRIDGE.AddPlayerBankMoney(mechanicSrc, commission)
        end
    end

    local customerName = row.customer_name or getPlayerName(src)
    if mechanicSrc then
        if row.plate then
            WorkLog.Clear(mechanicSrc, row.plate)
        end
        Shops.Notify(mechanicSrc, locale("bill_paid_mechanic", customerName, formatMoney(total), formatMoney(commission)), "success")
    end

    local bill = {
        id = row.id,
        shopId = row.shop_id,
        mechanic = row.mechanic,
        mechanicName = row.mechanic_name,
        customer = row.customer,
        customerName = customerName,
        plate = row.plate,
        lines = decodeLines(row.lines),
        note = row.note,
        total = total,
        commission = commission,
        method = method,
        paidAt = now,
    }
    local ok, hookErr = pcall(OpenServer.OnBillPaid, bill)
    if not ok then
        print("[pls_mechanic] OpenServer.OnBillPaid error: "..tostring(hookErr))
    end
    log(src, "bill_paid", ("Bill #%s paid (%s, %s), commission %s"):format(row.id, formatMoney(total), method, formatMoney(commission)), bill)
    return { ok = true, message = locale("bill_paid_customer", formatMoney(total)) }
end)

-- NUI "bill:decline" { id }
lib.callback.register("pls_mechanic:server:billing:decline", function(src, id)
    if not checkRate(src, "decline", 1500) then return fail(locale("bill_cooldown")) end
    local row, err = getCustomerBill(src, id)
    if not row then return fail(err) end
    local affected = MySQL.update.await("UPDATE `pls_mechanic_bills` SET `status` = 'declined' WHERE `id` = ? AND `status` = 'pending'", { row.id })
    if not affected or affected < 1 then return fail(locale("bill_already_handled")) end
    local mechanicSrc = getPlayerByCharId(row.mechanic)
    if mechanicSrc then
        Shops.Notify(mechanicSrc, locale("bill_declined_mechanic", row.customer_name or getPlayerName(src), formatMoney(row.total)), "error")
    end
    log(src, "bill_declined", ("Bill #%s declined (%s)"):format(row.id, formatMoney(row.total)), { id = row.id, shopId = row.shop_id })
    return { ok = true, message = locale("bill_declined_customer") }
end)

-- Bills log for workshop settings (manage_shop or admin), 20 per page
lib.callback.register("pls_mechanic:server:billing:list", function(src, shopId, page)
    shopId = tonumber(shopId)
    local empty = { bills = {}, pages = 1 }
    if not shopId or not Shops.Get(shopId) then return empty end
    if not Shops.IsAdmin(src) and not Shops.HasPermission(src, "manage_shop", shopId) then return empty end
    local count = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `pls_mechanic_bills` WHERE `shop_id` = ?", { shopId })) or 0
    local pages = math.max(1, math.ceil(count / PAGE_SIZE))
    page = Utils.Clamp(math.floor(tonumber(page) or 1), 1, pages)
    local rows = MySQL.query.await("SELECT `id`, `created_at`, `mechanic`, `mechanic_name`, `customer`, `customer_name`, `plate`, `total`, `status` FROM `pls_mechanic_bills` WHERE `shop_id` = ? ORDER BY `id` DESC LIMIT ? OFFSET ?", { shopId, PAGE_SIZE, (page - 1) * PAGE_SIZE }) or {}
    local bills = {}
    for _, row in ipairs(rows) do
        table.insert(bills, {
            id = row.id,
            date = row.created_at,
            mechanic = row.mechanic_name or row.mechanic,
            customer = row.customer_name or row.customer or "-",
            plate = row.plate,
            total = row.total,
            status = row.status,
        })
    end
    return { bills = bills, pages = pages }
end)

--[[
  _______ _                        _
 |__   __| |                      | |
    | |  | |__  _ __ ___  __ _  __| |___
    | |  | '_ \| '__/ _ \/ _` |/ _` / __|
    | |  | | | | | |  __/ (_| | (_| \__ \
    |_|  |_| |_|_|  \___|\__,_|\__,_|___/
]]--

CreateThread(function()
    while not Shops.IsLoaded() do
        Wait(500)
    end
    while true do
        local ok, err = pcall(expireBills)
        if not ok then
            print("[pls_mechanic] bill expiry error: "..tostring(err))
        end
        Wait(60000)
    end
end)

AddEventHandler("playerDropped", function()
    Cooldowns[source] = nil
end)
