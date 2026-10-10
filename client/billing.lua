--[[
  ____  _ _ _ _
 |  _ \(_) | (_)
 | |_) |_| | |_ _ __   __ _
 |  _ <| | | | | '_ \ / _` |
 | |_) | | | | | | | | (_| |
 |____/|_|_|_|_|_| |_|\__, |
                       __/ |
                      |___/
 Mechanic: NUI "billCreate" (Billing.OpenCreate - called from mechanic menu)
 Customer: NUI "bill" (received bill, command, payment terminal point)
 Workshop settings: bills log
 Illegal workshop bills come with cashOnly = true (only cash, whole amount to the mechanic)
]]--

Billing = {}

local Cfg = Config.Billing
local Queue = {}          -- bill ids received while another window was open
local QueueRunning = false

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

local function formatMoney(value)
    return Config.Currency..Utils.FormatMoney(value)
end

-- Workshop of opened settings window (shops module), payload shopId as fallback
local function getSettingsShopId(data)
    local shopId = Settings and Settings.GetShopId and Settings.GetShopId()
    return tonumber(shopId) or (type(data) == "table" and tonumber(data.shopId)) or nil
end

-- Another window, pause menu, progress or context menu is active
local function isBusy()
    return Core.Nui.IsOpen() or IsNuiFocused() or IsPauseMenuActive() or lib.progressActive() or lib.getOpenContextMenu() ~= nil
end

local function openBill(bill)
    Core.Nui.Open("bill", bill)
end

local function removeFromQueue(id)
    for i = #Queue, 1, -1 do
        if Queue[i] == id then
            table.remove(Queue, i)
        end
    end
end

-- Opens queued bills one by one when player is free (bill is fetched again = fresh balances, skips paid / expired)
local function processQueue()
    if QueueRunning then return end
    QueueRunning = true
    CreateThread(function()
        while #Queue > 0 do
            Wait(1000)
            if not isBusy() then
                local id = table.remove(Queue, 1)
                local result = lib.callback.await("pls_mechanic:server:billing:get", false, id)
                if result and result.ok then
                    openBill(result.bill)
                end
            end
        end
        QueueRunning = false
    end)
end

--[[
  _____       _     _ _
 |  __ \     | |   | (_)
 | |__) |   _| |__ | |_  ___
 |  ___/ | | | '_ \| | |/ __|
 | |   | |_| | |_) | | | (__
 |_|    \__,_|_.__/|_|_|\___|
]]--

-- Mechanic creates bill. plate = vehicle (default closest vehicle), lines are prefilled from work done on it.
function Billing.OpenCreate(plate)
    CreateThread(function()
        if not Core.HasPermission("billing") then
            Core.Notify(locale(Core.GetMyShopId() and "no_permission" or "not_on_duty"), "error")
            return
        end
        if not plate then
            local vehicle = Core.GetClosestVehicle(6.0)
            if vehicle then
                plate = Utils.TrimPlate(GetVehicleNumberPlateText(vehicle))
            end
        end
        local nearby = {}
        for _, v in pairs(Core.GetNearbyPlayers(Cfg.distance)) do
            table.insert(nearby, v.serverId)
        end
        if #nearby == 0 then
            Core.Notify(locale("bill_no_customers"), "error")
            return
        end
        local result = lib.callback.await("pls_mechanic:server:billing:prepare", false, plate, nearby)
        if not result or not result.ok then
            notifyResult(result)
            return
        end
        if #result.data.customers == 0 then
            Core.Notify(locale("bill_no_customers"), "error")
            return
        end
        Core.Nui.Open("billCreate", result.data)
    end)
end

-- Customer: list of my unpaid bills (shopId = only bills of that workshop)
function Billing.OpenPending(shopId)
    CreateThread(function()
        if Core.Nui.IsOpen() then return end
        local bills = lib.callback.await("pls_mechanic:server:billing:pending", false, shopId)
        if type(bills) ~= "table" or #bills == 0 then
            Core.Notify(locale("bill_no_pending"), "inform")
            return
        end
        if #bills == 1 then
            openBill(bills[1])
            return
        end
        local options = {}
        for _, bill in ipairs(bills) do
            local description = locale("bill_pending_description", bill.mechanicName, bill.plate or locale("bill_no_plate"))
            if bill.cashOnly then
                description = description.." | "..locale("bill_cash_only_short")
            end
            table.insert(options, {
                title = locale("bill_pending_option", bill.shopName, formatMoney(bill.total)),
                description = description,
                icon = "fa-solid fa-file-invoice-dollar",
                onSelect = function()
                    openBill(bill)
                end,
            })
        end
        lib.registerContext({ id = "pls_mechanic_bills", title = locale("bill_pending_title"), options = options })
        lib.showContext("pls_mechanic_bills")
    end)
end

--[[
  _   _ _    _ _____
 | \ | | |  | |_   _|
 |  \| | |  | | | |
 | . ` | |  | | | |
 | |\  | |__| |_| |_
 |_| \_|\____/|_____|
]]--

RegisterNUICallback("billCreate:send", function(data, cb)
    local result = lib.callback.await("pls_mechanic:server:billing:send", false, data)
    result = result or { ok = false, message = locale("bill_invalid") }
    cb(result)
    if result.ok then
        Core.Nui.Close("billCreate")
        Core.Notify(result.message, "success")
    end
end)

RegisterNUICallback("bill:pay", function(data, cb)
    local id = type(data) == "table" and tonumber(data.id) or nil
    local result = id and lib.callback.await("pls_mechanic:server:billing:pay", false, id, data.method)
    result = result or { ok = false, message = locale("bill_invalid") }
    cb(result)
    if result.ok then
        removeFromQueue(id)
        Core.Nui.Close("bill")
        Core.Notify(result.message, "success")
    end
end)

RegisterNUICallback("bill:decline", function(data, cb)
    local id = type(data) == "table" and tonumber(data.id) or nil
    local result = id and lib.callback.await("pls_mechanic:server:billing:decline", false, id)
    result = result or { ok = false, message = locale("bill_invalid") }
    cb(result)
    if result.ok then
        removeFromQueue(id)
        Core.Nui.Close("bill")
        Core.Notify(result.message, "inform")
    end
end)

RegisterNUICallback("settings:bills", function(data, cb)
    local shopId = getSettingsShopId(data)
    local result = shopId and lib.callback.await("pls_mechanic:server:billing:list", false, shopId, type(data) == "table" and data.page or 1)
    cb(result or { bills = {}, pages = 1 })
end)

--[[
  ______               _
 |  ____|             | |
 | |____   _____ _ __ | |_ ___
 |  __\ \ / / _ \ '_ \| __/ __|
 | |___\ V /  __/ | | | |_\__ \
 |______\_/ \___|_| |_|\__|___/
]]--

RegisterNetEvent("pls_mechanic:client:billing:received", function(bill)
    if type(bill) ~= "table" or not bill.id then return end
    if isBusy() then
        removeFromQueue(bill.id)
        table.insert(Queue, bill.id)
        Core.Notify(locale("bill_received_pending", bill.mechanicName or "-", formatMoney(bill.total), Cfg.command or ""), "inform")
        processQueue()
        return
    end
    -- illegal workshop bill (bill.cashOnly): cash straight to the mechanic
    Core.Notify(locale(bill.cashOnly and "bill_received_cash" or "bill_received", bill.mechanicName or "-", formatMoney(bill.total)), "inform")
    openBill(bill)
end)

ShopPoints.RegisterAction("billing", {
    label = locale("bill_action_pay"),
    icon = "fa-solid fa-cash-register",
    onSelect = function(shop)
        Billing.OpenPending(shop.id)
    end,
})

if Cfg.command and Cfg.command ~= "" then
    RegisterCommand(Cfg.command, function()
        Billing.OpenPending()
    end, false)
    TriggerEvent("chat:addSuggestion", "/"..Cfg.command, locale("bill_command_help"))
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Cfg.command and Cfg.command ~= "" then
        TriggerEvent("chat:removeSuggestion", "/"..Cfg.command)
    end
end)
