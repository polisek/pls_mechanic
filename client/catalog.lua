--[[
   _____      _        _
  / ____|    | |      | |
 | |     __ _| |_ __ _| | ___   __ _
 | |    / _` | __/ _` | |/ _ \ / _` |
 | |___| (_| | || (_| | | (_) | (_| |
  \_____\__,_|\__\__,_|_|\___/ \__, |
                                __/ |
                               |___/
 Customer tuning catalog (Config.Tuning.Catalog).
 Target "Tuning catalog" on a vehicle in a tuning bay opens the tuning menu in customer mode (Tuning.OpenCatalog):
 live preview with prices, the cart is sent to the mechanics of the workshop as an order.
 Quote: the mechanic wants changes outside the order, the customer accepts / declines them (NUI "quote").
]]--

local Cfg = Config.Tuning.Catalog or {}
local TargetId = nil
local BayCache = { entity = nil, time = 0, result = false }
local Quote = nil            -- pending quote { promise, done, dialog }

local DIALOG_ANSWERS = { confirm = "accept", cancel = "decline" }

--[[
  _______                   _
 |__   __|                 | |
    | | __ _ _ __ __ _  ___| |_
    | |/ _` | '__/ _` |/ _ \ __|
    | | (_| | | | (_| |  __/ |_
    |_|\__,_|_|  \__, |\___|\__|
                  __/ |
                 |___/
]]--

-- Tuning bay of a workshop with the catalog (legal, illegal with Catalog.illegal) at coords
local function findCatalogBay(coords)
    for _, shop in pairs(Core.Shops) do
        if shop.kind ~= "illegal" or Cfg.illegal then
            for _, point in pairs(shop.points or {}) do
                if point.type == "bay" and Utils.BayAccepts(point, "tuning")
                    and #(coords - Utils.Vec3(point.coords)) <= (point.radius or Config.PointTypes.bay.radius) then
                    return point
                end
            end
        end
    end
    return nil
end

-- Vehicle stands in a catalog bay (short cache, canInteract runs often)
local function inCatalogBay(entity)
    local now = GetGameTimer()
    if BayCache.entity == entity and BayCache.time > now then
        return BayCache.result
    end
    -- an entity being removed / not streamed yet throws in model natives (GetVehicleClass)
    local okClass, class = pcall(GetVehicleClass, entity)
    local result = okClass and not Config.Tuning.BlockedClasses[class] and NetworkGetEntityIsNetworked(entity)
        and findCatalogBay(GetEntityCoords(entity)) ~= nil
    BayCache.entity, BayCache.time, BayCache.result = entity, now + 750, result and true or false
    return BayCache.result
end

if Cfg.enabled then
    TargetId = BRIDGE.AddGlobalVehicleTarget({
        {
            name = "pls_mechanic_tuning_catalog",
            label = locale("tuning_catalog_target"),
            icon = "fa-solid fa-book-open",
            distance = math.min(Cfg.maxDistance or 4.0, 4.0),
            canInteract = function(entity)
                -- on foot, no own tuning / catalog session (the server checks the rest)
                if cache.vehicle or not entity or entity == 0 or Tuning.IsOpen() then return false end
                return inCatalogBay(entity) and IsVehicleSeatFree(entity, -1)
            end,
            onSelect = function(data)
                local entity = type(data) == "table" and data.entity or data
                Tuning.OpenCatalog(entity)
            end,
        },
    })
end

--[[
   ____              _
  / __ \            | |
 | |  | |_   _  ___ | |_ ___
 | |  | | | | |/ _ \| __/ _ \
 | |__| | |_| | (_) | ||  __/
  \___\_\\__,_|\___/ \__\___|

 Server (tuning:approve) asks the customer: quote = { shop, mechanic, plate, items = { { label, value, price, ordered } },
 extraTotal, total, timeout (s) }. Answer true = accepted, false = declined, nil = no answer (timeout / closed).
]]--

local function formatMoney(value)
    return Config.Currency..Utils.FormatMoney(tonumber(value) or 0)
end

-- Plain text of the quote (dialog when another window is open)
local function quoteText(data, timeout)
    local lines = { locale("tuning_quote_info", tostring(data.shop or "-"), tostring(data.mechanic or "-"), tostring(data.plate or "-")), "" }
    for _, item in ipairs(data.items) do
        if type(item) == "table" then
            local key = item.ordered and "tuning_quote_item_ordered" or "tuning_quote_item_extra"
            lines[#lines + 1] = locale(key, tostring(item.label or "-"), tostring(item.value or "-"), formatMoney(item.price))
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = locale("tuning_quote_totals", formatMoney(data.extraTotal), formatMoney(data.total))
    lines[#lines + 1] = locale("tuning_quote_question", timeout)
    return table.concat(lines, "  \n")
end

-- answer = "accept" / "decline" / "none" (timeout, closed), first answer wins
local function finishQuote(quote, answer)
    if quote.done then return end
    quote.done = true
    if Quote == quote then
        Quote = nil
    end
    quote.promise:resolve(answer or "none")
end

lib.callback.register("pls_mechanic:client:tuning:quote", function(data)
    if type(data) ~= "table" or type(data.items) ~= "table" then return nil end
    -- one quote at a time, the other mechanic gets no answer
    if Quote then return nil end
    local timeout = math.max(5, math.floor(tonumber(data.timeout) or Cfg.approvalTimeout or 60))
    local quote = { promise = promise.new(), done = false, dialog = false }
    Quote = quote

    if Core.Nui.IsOpen() or IsNuiFocused() then
        -- another window is open (catalog, bill...): plain text dialog, the window stays
        quote.dialog = true
        CreateThread(function()
            local ok, answer = pcall(lib.alertDialog, {
                header = locale("tuning_quote_title"),
                content = quoteText(data, timeout),
                centered = true,
                cancel = true,
                labels = { confirm = locale("tuning_quote_button_accept"), cancel = locale("tuning_quote_button_decline") },
            })
            quote.dialog = false
            finishQuote(quote, ok and DIALOG_ANSWERS[answer] or nil)
        end)
    else
        Core.Nui.Open("quote", data)
    end

    SetTimeout(timeout * 1000, function()
        finishQuote(quote, nil)
    end)

    local answer = Citizen.Await(quote.promise)
    -- the window / dialog closes after any answer
    if quote.dialog then
        quote.dialog = false
        pcall(lib.closeAlertDialog)
    elseif Core.Nui.IsOpen("quote") then
        Core.Nui.Close("quote")
    end
    if answer == "accept" then return true end
    if answer == "decline" then return false end
    return nil
end)

RegisterNUICallback("quote:accept", function(_, cb)
    local quote = Quote
    cb({ ok = quote ~= nil })
    if quote then
        finishQuote(quote, "accept")
    end
end)

RegisterNUICallback("quote:decline", function(_, cb)
    local quote = Quote
    cb({ ok = quote ~= nil })
    if quote then
        finishQuote(quote, "decline")
    end
end)

-- ESC / close button = declined
Core.Nui.OnClose("quote", function()
    local quote = Quote
    if quote and not quote.dialog then
        finishQuote(quote, "decline")
    end
end)

-- Server settled the quote without an answer (the mechanic closed the menu / left, the order was cancelled):
-- the window / dialog closes, the callback answers nil
RegisterNetEvent("pls_mechanic:client:tuning:quoteClose", function()
    local quote = Quote
    if quote and not quote.done then
        finishQuote(quote, nil)
        Core.Notify(locale("tuning_quote_closed"), "inform")
    end
end)

--[[
   _____ _
  / ____| |
 | (___ | |_ ___  _ __
  \___ \| __/ _ \| '_ \
  ____) | || (_) | |_) |
 |_____/ \__\___/| .__/
                 | |
                 |_|
]]--

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if TargetId then
        BRIDGE.RemoveGlobalVehicleTarget(TargetId)
        TargetId = nil
    end
    -- the dialog belongs to ox_lib, it would stay open
    if Quote and Quote.dialog then
        pcall(lib.closeAlertDialog)
    end
end)
