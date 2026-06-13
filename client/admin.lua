-- NUI admin panel bridge. All mutations are re-validated server-side; this file
-- only drives the interface and captures world positions.

local panelOpen = false

local function round(n) return math.floor(n * 100) / 100 end

local function openPanel()
    local data = lib.callback.await('lf_elevatore:admin:getAll', false)
    if not data then
        lib.notify({ description = locale('admin_no_perm'), type = 'error' })
        return
    end
    panelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', payload = data })
end

local function closePanel()
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('lf_elevatore:client:openAdmin', openPanel)

-- World position picker ------------------------------------------------------

local function pickPosition()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })

    local ped = cache.ped
    local result
    lib.showTextUI(locale('picker_hint'), { position = 'bottom-center' })

    while true do
        Wait(0)
        local coords = GetEntityCoords(ped)
        DrawMarker(1, coords.x, coords.y, coords.z - 0.96, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            1.0, 1.0, 0.5, 64, 140, 255, 120, false, false, 2, false, nil, nil, false)

        if IsControlJustReleased(0, 38) then -- E confirm
            result = {
                coords = { x = round(coords.x), y = round(coords.y), z = round(coords.z) },
                heading = round(GetEntityHeading(ped)),
            }
            break
        elseif IsControlJustReleased(0, 177) or IsControlJustReleased(0, 200) then -- Backspace / Esc cancel
            break
        end
    end

    lib.hideTextUI()
    if panelOpen then
        SendNUIMessage({ action = 'show' })
        SetNuiFocus(true, true)
    end
    return result
end

-- NUI callbacks --------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb(true)
end)

RegisterNUICallback('refresh', function(_, cb)
    cb(lib.callback.await('lf_elevatore:admin:getAll', false) or false)
end)

RegisterNUICallback('currentPosition', function(_, cb)
    local coords = GetEntityCoords(cache.ped)
    cb({
        coords = { x = round(coords.x), y = round(coords.y), z = round(coords.z) },
        heading = round(GetEntityHeading(cache.ped)),
    })
end)

RegisterNUICallback('pickPosition', function(_, cb)
    cb(pickPosition() or false)
end)

RegisterNUICallback('saveElevator', function(payload, cb)
    local ok, reason = lib.callback.await('lf_elevatore:admin:saveElevator', false, payload)
    cb({ ok = ok, reason = reason })
end)

RegisterNUICallback('deleteElevator', function(data, cb)
    local ok, reason = lib.callback.await('lf_elevatore:admin:deleteElevator', false, data.name)
    cb({ ok = ok, reason = reason })
end)

RegisterNUICallback('setLocked', function(data, cb)
    local ok, reason = lib.callback.await('lf_elevatore:admin:setLocked', false, data.name, data.state)
    cb({ ok = ok, reason = reason })
end)

RegisterNUICallback('saveSettings', function(data, cb)
    local ok, settings = lib.callback.await('lf_elevatore:admin:saveSettings', false, data)
    cb({ ok = ok, settings = settings })
end)

RegisterNUICallback('teleport', function(data, cb)
    TriggerServerEvent('lf_elevatore:admin:teleport', data.name, data.index)
    closePanel()
    cb(true)
end)
