lib.locale()

local Settings, Elevators
local targetResource = false
local zones = {}    -- ox_target ids / qb-target zone names
local points = {}   -- lib.points handles
local moving = false

-- UX-only mirror of the server-side check, used to gray out locked floors.
-- ox_core defers entirely to the server (groups aren't resolved client-side).
local function hasFloorAccess(floor)
    if Bridge.DefersToServer() then return true end

    local needsJob = floor.jobs and next(floor.jobs) ~= nil
    local needsGang = floor.gangs and next(floor.gangs) ~= nil
    local needsItem = floor.items and next(floor.items) ~= nil
    local ownerOnly = floor.ownerOnly

    -- Can't resolve owner identity reliably client-side; let the server decide.
    if ownerOnly and not (needsJob or needsGang or needsItem) then return true end
    if not (needsJob or needsGang or needsItem) then return true end

    local function matches(groupTable)
        for name, minGrade in pairs(groupTable) do
            local grade = Bridge.GetGroupGrade(name)
            if grade and grade >= minGrade then return true end
        end
        return false
    end

    local hasJob = needsJob and matches(floor.jobs) or false
    local hasGang = needsGang and matches(floor.gangs) or false

    local hasItem = false
    if needsItem then
        for i = 1, #floor.items do
            if Bridge.HasItem(floor.items[i]) then
                hasItem = true
                break
            end
        end
    end

    if floor.requireAll then
        return (not needsJob or hasJob) and (not needsGang or hasGang) and (not needsItem or hasItem)
    end

    return (needsJob and hasJob) or (needsGang and hasGang) or (needsItem and hasItem)
end

local function floorHint(floor)
    if floor.hours and floor.hours.open and floor.hours.close then
        return locale('floor_hours', floor.hours.open, floor.hours.close)
    end
    return floor.label
end

local function playSound(sound)
    if not sound then return end
    if sound.type == 'native' then
        PlaySoundFrontend(-1, sound.name, sound.set, true)
    elseif sound.type == 'interact-sound' then
        TriggerEvent('InteractSound_CL:PlayOnOne', sound.name, sound.volume or 0.3)
    end
end

local function requestMove(elevatorName, fromIndex, toIndex, floor)
    if moving then return end

    local pin
    if floor.pin then
        local input = lib.inputDialog(locale('pin_title'), {
            { type = 'input', label = locale('pin_label'), password = true, icon = 'key', required = true },
        })
        if not input then return end
        pin = input[1]
    end

    local ok, reason = lib.callback.await('lf_elevatore:requestMove', false, elevatorName, fromIndex, toIndex, pin)
    if not ok then
        lib.notify({ description = locale(reason or 'invalid'), type = 'error' })
    end
end

local function openFloorMenu(elevatorName, currentIndex)
    if moving then return end
    local floors = Elevators and Elevators[elevatorName]
    if not floors then return end

    if floors.locked then
        lib.notify({ description = locale('locked'), type = 'error' })
        return
    end

    local options = {}
    for index, floor in ipairs(floors) do
        local isHere = index == currentIndex
        local allowed = hasFloorAccess(floor)
        local icon = 'elevator'
        if isHere then
            icon = 'location-dot'
        elseif not allowed then
            icon = 'lock'
        elseif floor.pin then
            icon = 'key'
        elseif floor.ownerOnly then
            icon = 'user-lock'
        end
        options[#options + 1] = {
            title = floor.level,
            description = isHere and locale('you_are_here') or floorHint(floor),
            icon = icon,
            disabled = isHere or not allowed,
            onSelect = function()
                requestMove(elevatorName, currentIndex, index, floor)
            end,
        }
    end

    lib.registerContext({
        id = 'lf_elevator_menu',
        title = floors.label or locale('menu_title', elevatorName),
        options = options,
    })
    lib.showContext('lf_elevator_menu')
end

-- Kept for v1 compatibility (external triggers)
RegisterNetEvent('lf_elevator:showFloors', function(data)
    openFloorMenu(data.elevator, data.level)
end)

-- Public client export: open an elevator's menu from the nearest floor.
exports('openElevator', function(elevatorName)
    local floors = Elevators and Elevators[elevatorName]
    if not floors then return false end
    local coords = GetEntityCoords(cache.ped)
    local nearestIndex, nearestDist = 1, math.huge
    for index, floor in ipairs(floors) do
        local d = #(coords - floor.coords)
        if d < nearestDist then
            nearestDist, nearestIndex = d, index
        end
    end
    openFloorMenu(elevatorName, nearestIndex)
    return true
end)

-- Zone / point construction -----------------------------------------------------

local function teardown()
    for i = 1, #zones do
        if targetResource == 'ox_target' then
            exports.ox_target:removeZone(zones[i], true)
        elseif targetResource == 'qb-target' then
            exports['qb-target']:RemoveZone(zones[i])
        end
    end
    zones = {}

    for i = 1, #points do
        points[i]:remove()
    end
    points = {}

    lib.hideTextUI()
end

local function buildAll()
    for elevatorName, floors in pairs(Elevators) do
        for index, floor in ipairs(floors) do
            local zoneName = ('lf_elevator:%s:%d'):format(elevatorName, index)
            local label = locale('use_elevator', floor.level)
            local size = floor.size or vec3(5.0, 4.0, 3.0)

            if targetResource == 'ox_target' then
                zones[#zones + 1] = exports.ox_target:addBoxZone({
                    coords = floor.coords,
                    size = size,
                    rotation = floor.heading or 0.0,
                    debug = Settings.debug,
                    options = {
                        {
                            name = zoneName,
                            icon = 'fas fa-elevator',
                            label = label,
                            onSelect = function()
                                openFloorMenu(elevatorName, index)
                            end,
                        },
                    },
                })
            elseif targetResource == 'qb-target' then
                exports['qb-target']:AddBoxZone(zoneName, floor.coords, size.x, size.y, {
                    name = zoneName,
                    heading = floor.heading or 0.0,
                    debugPoly = Settings.debug,
                    minZ = floor.coords.z - size.z / 2,
                    maxZ = floor.coords.z + size.z / 2,
                }, {
                    options = {
                        {
                            icon = 'fas fa-elevator',
                            label = label,
                            action = function()
                                openFloorMenu(elevatorName, index)
                            end,
                        },
                    },
                    distance = 2.0,
                })
                zones[#zones + 1] = zoneName
            end

            if Settings.useTextUI then
                local point = lib.points.new({
                    coords = floor.coords,
                    distance = 10.0,
                })
                local shown = false

                function point:nearby()
                    if self.currentDistance <= Settings.interactDistance and not moving then
                        if not shown then
                            lib.showTextUI(locale('textui_prompt', floor.level))
                            shown = true
                        end
                        if IsControlJustReleased(0, Settings.interactKey) then
                            lib.hideTextUI()
                            shown = false
                            openFloorMenu(elevatorName, index)
                        end
                    elseif shown then
                        lib.hideTextUI()
                        shown = false
                    end
                end

                function point:onExit()
                    if shown then
                        lib.hideTextUI()
                        shown = false
                    end
                end

                points[#points + 1] = point
            end
        end
    end
end

-- Server events ------------------------------------------------------------------

RegisterNetEvent('lf_elevatore:client:move', function(destination)
    if moving then return end
    moving = true

    local ped = cache.ped
    DoScreenFadeOut(Settings.fadeTime)
    while not IsScreenFadedOut() do Wait(50) end

    playSound(Settings.sounds and Settings.sounds.travel)
    Wait(Settings.waitTime * 1000)

    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(destination.coords.x, destination.coords.y, destination.coords.z)
    SetEntityCoords(ped, destination.coords.x, destination.coords.y, destination.coords.z, false, false, false, false)
    SetEntityHeading(ped, destination.heading or 0.0)

    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        Wait(50)
    end
    FreezeEntityPosition(ped, false)

    if Settings.shake then
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.12)
        SetTimeout(400, function() StopGameplayCamShaking(true) end)
    end

    playSound(Settings.sounds and Settings.sounds.arrive)
    DoScreenFadeIn(Settings.fadeTime)
    moving = false

    -- Public client event for other resources.
    TriggerEvent('lf_elevatore:arrived', destination.elevator, destination.level, destination.coords)
end)

RegisterNetEvent('lf_elevatore:client:refresh', function(elevators)
    if not Settings then return end -- initial getData still pending
    Elevators = elevators
    teardown()
    buildAll()
end)

RegisterNetEvent('lf_elevatore:client:notify', function(key, notifyType, ...)
    lib.notify({ description = locale(key, ...), type = notifyType or 'inform' })
end)

RegisterNetEvent('lf_elevatore:client:floorDialog', function(floorNumber)
    local input = lib.inputDialog(locale('creator_dialog_title', floorNumber), {
        { type = 'input', label = locale('creator_field_level'), required = true, icon = 'signs-post' },
        { type = 'input', label = locale('creator_field_label'), icon = 'tag' },
        { type = 'input', label = locale('creator_field_pin'), description = locale('creator_field_pin_desc'), icon = 'key' },
        { type = 'number', label = locale('creator_field_bucket'), description = locale('creator_field_bucket_desc'), icon = 'layer-group' },
        { type = 'input', label = locale('creator_field_jobs'), description = 'police:0, ambulance:2', icon = 'briefcase' },
        { type = 'input', label = locale('creator_field_gangs'), description = 'ballas:0', icon = 'people-group' },
        { type = 'input', label = locale('creator_field_items'), description = 'keycard, vip_card', icon = 'box' },
        { type = 'checkbox', label = locale('creator_field_consume') },
        { type = 'input', label = locale('creator_field_owners'), description = locale('creator_field_owners_desc'), icon = 'id-card' },
        { type = 'number', label = locale('creator_field_open'), icon = 'clock', min = 0, max = 23 },
        { type = 'number', label = locale('creator_field_close'), icon = 'clock', min = 0, max = 23 },
    })
    if not input then return end

    TriggerServerEvent('lf_elevatore:server:addFloor', {
        level = input[1],
        label = input[2],
        pin = input[3],
        bucket = input[4],
        jobs = input[5],
        gangs = input[6],
        items = input[7],
        consumeItem = input[8],
        owners = input[9],
        open = input[10],
        close = input[11],
    })
end)

-- Startup -------------------------------------------------------------------------

CreateThread(function()
    local settings, elevators = lib.callback.await('lf_elevatore:getData', false)
    Settings = settings
    Elevators = elevators

    targetResource = Settings.target
    if targetResource == 'auto' then
        if GetResourceState('ox_target') == 'started' then
            targetResource = 'ox_target'
        elseif GetResourceState('qb-target') == 'started' then
            targetResource = 'qb-target'
        else
            targetResource = false
        end
    elseif targetResource and GetResourceState(targetResource) ~= 'started' then
        print(('^3[lf_elevatore] Configured target "%s" is not running^0'):format(targetResource))
        targetResource = false
    end

    if not targetResource and not Settings.useTextUI then
        print('^3[lf_elevatore] Both targeting and TextUI are disabled - elevators cannot be used^0')
    end

    buildAll()
end)
