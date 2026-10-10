local IS_SERVER = IsDuplicityVersion()

if IS_SERVER then
    local SecurePlayers = {}

    RegisterNetEvent("secure:server:eventGen")
    AddEventHandler("secure:server:eventGen", function(randomString, timeStamp)
        local src = source
        SecurePlayers[src] = {randomString = randomString, timeStamp = os.time()}

        -- Automaticky zrušit platnost po jedné minutě
        SetTimeout(60000, function()
            SecurePlayers[src] = nil
        end)
    end)

    function CanTrustPlayer(source)
        if SecurePlayers[source] and SecurePlayers[source].randomString then
            -- Zkontrolujte, zda byla událost spuštěna před méně než sekundou
            if os.time() - SecurePlayers[source].timeStamp <= 1 then
                return true
            end
        end
        return false
    end 
end
if not IS_SERVER then
    function generateRandomString(length)
        local characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        local result = ''
        local charactersLength = string.len(characters)
    
        for i = 1, length do
            result = result .. string.sub(characters, math.random(1, charactersLength), 1)
        end
    
        return result
    end
    
    function TriggerSecureEvent(eventname, ...)
        local randomString = generateRandomString(10)
        TriggerServerEvent("secure:server:eventGen", randomString, timeStamp)
        Wait(50)
        TriggerServerEvent(eventname, ...)
    end
end
