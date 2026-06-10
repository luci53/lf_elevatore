local SAVE_FILE = 'data/elevators.json'
local resourceName = GetCurrentResourceName()

local elevators = {}        -- runtime data (config + saved merged, full detail incl. PINs)
local clientElevators = {}  -- sanitized copy sent to clients (PINs reduced to booleans)
local savedElevators = {}   -- elevators created in-game, persisted to SAVE_FILE
local sessions = {}         -- active /elevator creation sessions, keyed by source
local lastUse = {}          -- per-player cooldown timestamps

local moveCooldown = Config.ElevatorWaitTime * 1000 + Config.FadeTime * 2

local settings = {
    target = Config.Target,
    useTextUI = Config.UseTextUI,
    interactKey = Config.InteractKey,
    interactDistance = Config.InteractDistance,
    waitTime = Config.ElevatorWaitTime,
    fadeTime = Config.FadeTime,
    debug = Config.Debug,
    sounds = Config.Sounds,
}

local function notify(source, key, notifyType, ...)
    TriggerClientEvent('lf_elevatore:client:notify', source, key, notifyType, ...)
end

local function runtimeFloor(floor)
    return {
        coords = vec3(floor.coords.x, floor.coords.y, floor.coords.z),
        heading = floor.heading,
        level = floor.level,
        label = floor.label,
        size = floor.size and vec3(floor.size.x, floor.size.y, floor.size.z) or nil,
        jobs = floor.jobs,
        gangs = floor.gangs,
        items = floor.items,
        requireAll = floor.requireAll or floor.jobAndItem or nil,
        pin = floor.pin,
        bucket = floor.bucket,
    }
end

local function sanitizeElevators()
    local out = {}
    for name, floors in pairs(elevators) do
        local copy = { label = floors.label, groupTravel = floors.groupTravel }
        for i, floor in ipairs(floors) do
            copy[i] = {
                coords = floor.coords,
                heading = floor.heading,
                level = floor.level,
                label = floor.label,
                size = floor.size,
                jobs = floor.jobs,
                gangs = floor.gangs,
                items = floor.items,
                requireAll = floor.requireAll,
                pin = floor.pin ~= nil or nil,
            }
        end
        out[name] = copy
    end
    return out
end

local function rebuildElevators()
    elevators = {}

    for name, floors in pairs(Config.Elevators) do
        local entry = { label = floors.label, groupTravel = floors.groupTravel }
        for i, floor in ipairs(floors) do
            entry[i] = runtimeFloor(floor)
        end
        elevators[name] = entry
    end

    for name, saved in pairs(savedElevators) do
        if elevators[name] then
            print(('^3[lf_elevatore] Saved elevator "%s" overrides a config elevator with the same name^0'):format(name))
        end
        local entry = { label = saved.label, groupTravel = saved.groupTravel }
        for i, floor in ipairs(saved.floors) do
            entry[i] = runtimeFloor(floor)
        end
        elevators[name] = entry
    end

    clientElevators = sanitizeElevators()
end

local function loadSaved()
    local raw = LoadResourceFile(resourceName, SAVE_FILE)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            savedElevators = data
        else
            print(('^1[lf_elevatore] Could not parse %s - starting with config elevators only^0'):format(SAVE_FILE))
        end
    end
end

local function persistSaved()
    SaveResourceFile(resourceName, SAVE_FILE, json.encode(savedElevators), -1)
end

local function broadcastRefresh()
    TriggerClientEvent('lf_elevatore:client:refresh', -1, clientElevators)
end

loadSaved()
rebuildElevators()

-- Access validation -----------------------------------------------------------

local function hasFloorAccess(source, floor)
    local needsJob = floor.jobs and next(floor.jobs) ~= nil
    local needsGang = floor.gangs and next(floor.gangs) ~= nil
    local needsItem = floor.items and next(floor.items) ~= nil

    if not (needsJob or needsGang or needsItem) then return true end

    local hasJob = false
    if needsJob then
        local job, grade = Bridge.GetJob(source)
        for name, minGrade in pairs(floor.jobs) do
            if job == name and (grade or 0) >= minGrade then
                hasJob = true
                break
            end
        end
    end

    local hasGang = false
    if needsGang then
        local gang, grade = Bridge.GetGang(source)
        for name, minGrade in pairs(floor.gangs) do
            if gang == name and (grade or 0) >= minGrade then
                hasGang = true
                break
            end
        end
    end

    local hasItem = false
    if needsItem then
        for i = 1, #floor.items do
            if Bridge.HasItem(source, floor.items[i]) then
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

lib.callback.register('lf_elevatore:getData', function()
    return settings, clientElevators
end)

lib.callback.register('lf_elevatore:requestMove', function(source, name, fromIndex, toIndex, pin)
    local floors = elevators[name]
    if not floors then return false, 'invalid' end

    local fromFloor = type(fromIndex) == 'number' and floors[fromIndex] or nil
    local toFloor = type(toIndex) == 'number' and floors[toIndex] or nil
    if not fromFloor or not toFloor or fromIndex == toIndex then return false, 'invalid' end

    local now = GetGameTimer()
    if lastUse[source] and now - lastUse[source] < moveCooldown then
        return false, 'too_fast'
    end

    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    if #(coords - fromFloor.coords) > 15.0 then
        return false, 'too_far'
    end

    if toFloor.pin and tostring(pin) ~= tostring(toFloor.pin) then
        return false, 'wrong_pin'
    end

    if not hasFloorAccess(source, toFloor) then
        return false, 'no_access'
    end

    lastUse[source] = now

    -- The requester validated access; players standing next to them ride along.
    local passengers = { source }
    if Config.GroupTravel.enabled and floors.groupTravel ~= false then
        local myBucket = GetPlayerRoutingBucket(source)
        for _, sid in ipairs(GetPlayers()) do
            local id = tonumber(sid)
            if id ~= source and GetPlayerRoutingBucket(id) == myBucket then
                local pedCoords = GetEntityCoords(GetPlayerPed(id))
                if #(pedCoords - coords) <= Config.GroupTravel.radius then
                    passengers[#passengers + 1] = id
                end
            end
        end
    end

    local destination = {
        coords = toFloor.coords,
        heading = toFloor.heading or 0.0,
    }

    for i = 1, #passengers do
        local id = passengers[i]
        if toFloor.bucket then
            -- Switch buckets once the passenger's screen has faded to black
            SetTimeout(Config.FadeTime, function()
                if GetPlayerPed(id) ~= 0 then
                    SetPlayerRoutingBucket(id, toFloor.bucket)
                end
            end)
        end
        TriggerClientEvent('lf_elevatore:client:move', id, destination)
    end

    return true
end)

-- In-game creator --------------------------------------------------------------

local function parseGroups(str)
    if type(str) ~= 'string' or str == '' then return nil end
    local out = {}
    for entry in str:gmatch('[^,]+') do
        local name, grade = entry:match('^%s*([%w_]+)%s*:?%s*(%d*)%s*$')
        if name then
            out[name] = tonumber(grade) or 0
        end
    end
    return next(out) ~= nil and out or nil
end

local function parseItems(str)
    if type(str) ~= 'string' or str == '' then return nil end
    local out = {}
    for entry in str:gmatch('[^,]+') do
        local name = entry:match('^%s*(.-)%s*$')
        if name ~= '' then
            out[#out + 1] = name
        end
    end
    return #out > 0 and out or nil
end

RegisterNetEvent('lf_elevatore:server:addFloor', function(form)
    local source = source
    local session = sessions[source]
    if not session then return notify(source, 'creator_no_session', 'error') end
    if type(form) ~= 'table' or type(form.level) ~= 'string' or form.level == '' then return end

    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)

    session.floors[#session.floors + 1] = {
        coords = { x = math.floor(coords.x * 100) / 100, y = math.floor(coords.y * 100) / 100, z = math.floor(coords.z * 100) / 100 },
        heading = math.floor(GetEntityHeading(ped) * 100) / 100,
        level = form.level,
        label = (type(form.label) == 'string' and form.label ~= '') and form.label or nil,
        pin = (type(form.pin) == 'string' and form.pin ~= '') and form.pin or nil,
        bucket = tonumber(form.bucket),
        jobs = parseGroups(form.jobs),
        gangs = parseGroups(form.gangs),
        items = parseItems(form.items),
    }

    notify(source, 'creator_floor_added', 'success', #session.floors, form.level)
end)

lib.addCommand('elevator', {
    help = 'Manage lf_elevatore elevators',
    restricted = Config.AdminGroup,
    params = {
        { name = 'action', type = 'string', help = 'create | add | save | cancel | delete | list' },
        { name = 'name', type = 'string', help = 'Elevator name (create/delete)', optional = true },
    },
}, function(source, args)
    local action = args.action:lower()

    if action == 'create' then
        if not args.name then return notify(source, 'creator_need_name', 'error') end
        if elevators[args.name] then return notify(source, 'creator_name_taken', 'error', args.name) end
        sessions[source] = { name = args.name, floors = {} }
        notify(source, 'creator_started', 'success', args.name)

    elseif action == 'add' then
        if not sessions[source] then return notify(source, 'creator_no_session', 'error') end
        TriggerClientEvent('lf_elevatore:client:floorDialog', source, #sessions[source].floors + 1)

    elseif action == 'save' then
        local session = sessions[source]
        if not session then return notify(source, 'creator_no_session', 'error') end
        if #session.floors < 2 then return notify(source, 'creator_need_floors', 'error') end
        savedElevators[session.name] = { label = session.name, floors = session.floors }
        persistSaved()
        sessions[source] = nil
        rebuildElevators()
        broadcastRefresh()
        notify(source, 'creator_saved', 'success', session.name, #session.floors)

    elseif action == 'cancel' then
        if not sessions[source] then return notify(source, 'creator_no_session', 'error') end
        sessions[source] = nil
        notify(source, 'creator_cancelled', 'inform')

    elseif action == 'delete' then
        if not args.name then return notify(source, 'creator_need_name', 'error') end
        if not savedElevators[args.name] then return notify(source, 'creator_not_saved', 'error', args.name) end
        savedElevators[args.name] = nil
        persistSaved()
        rebuildElevators()
        broadcastRefresh()
        notify(source, 'creator_deleted', 'success', args.name)

    elseif action == 'list' then
        local names = {}
        for name, floors in pairs(elevators) do
            names[#names + 1] = ('%s (%d)'):format(name, #floors)
        end
        if #names == 0 then return notify(source, 'creator_list_empty', 'inform') end
        notify(source, 'creator_list', 'inform', table.concat(names, ', '))

    else
        notify(source, 'creator_usage', 'error')
    end
end)

AddEventHandler('playerDropped', function()
    lastUse[source] = nil
    sessions[source] = nil
end)
