local SAVE_FILE = 'data/elevators.json'
local resourceName = GetCurrentResourceName()

local elevators = {}        -- runtime data (config + saved + api merged, full detail incl. PINs)
local clientElevators = {}  -- sanitized copy sent to clients (PINs/owners reduced to booleans)
local savedElevators = {}   -- elevators created in-game, persisted to SAVE_FILE
local apiElevators = {}      -- elevators registered at runtime via exports (not persisted)
local locked = {}           -- maintenance lock state, keyed by elevator name
local sessions = {}         -- active /elevator creation/edit sessions, keyed by source
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
    shake = Config.ArrivalShake,
}

local function notify(source, key, notifyType, ...)
    TriggerClientEvent('lf_elevatore:client:notify', source, key, notifyType, ...)
end

-- Data assembly --------------------------------------------------------------

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
        owners = floor.owners,
        requireAll = floor.requireAll or floor.jobAndItem or nil,
        consumeItem = floor.consumeItem,
        hours = floor.hours,
        pin = floor.pin,
        bucket = floor.bucket,
    }
end

local function sanitizeElevators()
    local out = {}
    for name, floors in pairs(elevators) do
        local copy = { label = floors.label, groupTravel = floors.groupTravel, locked = locked[name] or nil }
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
                hours = floor.hours,
                pin = floor.pin ~= nil or nil,
                ownerOnly = (floor.owners and #floor.owners > 0) or nil,
            }
        end
        out[name] = copy
    end
    return out
end

---Merge a { label, groupTravel, floors = {...} } source into the runtime table.
local function addSource(name, src)
    if elevators[name] then
        print(('^3[lf_elevatore] Elevator "%s" is defined more than once; later definition wins^0'):format(name))
    end
    local entry = { label = src.label, groupTravel = src.groupTravel }
    for i, floor in ipairs(src.floors) do
        entry[i] = runtimeFloor(floor)
    end
    elevators[name] = entry
end

local function rebuildElevators()
    elevators = {}

    -- Config elevators are array-style with optional label/groupTravel keys.
    for name, floors in pairs(Config.Elevators) do
        addSource(name, { label = floors.label, groupTravel = floors.groupTravel, floors = floors })
    end
    for name, saved in pairs(savedElevators) do
        addSource(name, saved)
    end
    for name, api in pairs(apiElevators) do
        addSource(name, api)
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

-- Access validation ----------------------------------------------------------

local function getHour()
    if Config.BusinessHours and type(Config.BusinessHours.getHour) == 'function' then
        return Config.BusinessHours.getHour()
    end
    return tonumber(os.date('%H'))
end

local function withinHours(hours)
    if not hours or not hours.open or not hours.close then return true end
    local h = getHour()
    if hours.open == hours.close then return true end
    if hours.open < hours.close then
        return h >= hours.open and h < hours.close
    end
    return h >= hours.open or h < hours.close -- overnight window
end

local function matchesGroups(source, groupTable)
    for name, minGrade in pairs(groupTable) do
        local grade = Bridge.GetGroupGrade(source, name)
        if grade and grade >= minGrade then return true end
    end
    return false
end

local function matchesOwners(source, owners)
    local ids = Bridge.GetIdentifiers(source)
    for i = 1, #owners do
        if ids[owners[i]] then return true end
    end
    return false
end

local function firstOwnedItem(source, items)
    for i = 1, #items do
        if Bridge.HasItem(source, items[i]) then return items[i] end
    end
    return nil
end

---@return boolean allowed, string? reason
local function hasFloorAccess(source, floor)
    if not withinHours(floor.hours) then return false, 'closed' end

    local needsJob = floor.jobs and next(floor.jobs) ~= nil
    local needsGang = floor.gangs and next(floor.gangs) ~= nil
    local needsItem = floor.items and next(floor.items) ~= nil
    local needsOwner = floor.owners and #floor.owners > 0

    if not (needsJob or needsGang or needsItem or needsOwner) then return true end

    local hasJob = needsJob and matchesGroups(source, floor.jobs) or false
    local hasGang = needsGang and matchesGroups(source, floor.gangs) or false
    local hasItem = needsItem and firstOwnedItem(source, floor.items) ~= nil or false
    local hasOwner = needsOwner and matchesOwners(source, floor.owners) or false

    local ok
    if floor.requireAll then
        ok = (not needsJob or hasJob) and (not needsGang or hasGang)
            and (not needsItem or hasItem) and (not needsOwner or hasOwner)
    else
        ok = (needsJob and hasJob) or (needsGang and hasGang)
            or (needsItem and hasItem) or (needsOwner and hasOwner)
    end

    if not ok then return false, 'no_access' end
    return true
end

-- Logging --------------------------------------------------------------------

local function logUsage(source, elevatorName, toFloor)
    local cfg = Config.Logging
    if not cfg or not cfg.enabled then return end

    local restricted = toFloor.pin or toFloor.jobs or toFloor.gangs or toFloor.items or toFloor.owners
    if not cfg.logAllMoves and not restricted then return end

    local pName = GetPlayerName(source) or 'unknown'
    local msg = ('%s [%s] used elevator "%s" -> %s%s'):format(
        pName, source, elevatorName, toFloor.level, restricted and ' (restricted)' or '')

    if cfg.useOxLib then
        lib.logger(source, 'elevator', msg, ('elevator:%s'):format(elevatorName), ('floor:%s'):format(toFloor.level))
    end

    if cfg.webhook and cfg.webhook ~= '' then
        PerformHttpRequest(cfg.webhook, function() end, 'POST', json.encode({
            username = 'lf_elevatore',
            embeds = { {
                title = 'Elevator used',
                description = msg,
                color = restricted and 15158332 or 3447003,
            } },
        }), { ['Content-Type'] = 'application/json' })
    end
end

-- Movement -------------------------------------------------------------------

lib.callback.register('lf_elevatore:getData', function()
    return settings, clientElevators
end)

lib.callback.register('lf_elevatore:requestMove', function(source, name, fromIndex, toIndex, pin)
    local floors = elevators[name]
    if not floors then return false, 'invalid' end
    if locked[name] then return false, 'locked' end

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

    local allowed, reason = hasFloorAccess(source, toFloor)
    if not allowed then
        return false, reason
    end

    -- Consume an access item if the floor is configured to (only on success).
    if toFloor.consumeItem and toFloor.items and next(toFloor.items) then
        local item = firstOwnedItem(source, toFloor.items)
        if item and not Bridge.RemoveItem(source, item, 1) then
            return false, 'no_access'
        end
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
        elevator = name,
        level = toFloor.level,
    }

    for i = 1, #passengers do
        local id = passengers[i]
        if toFloor.bucket then
            -- Switch buckets once the passenger's screen has faded to black.
            SetTimeout(Config.FadeTime, function()
                if GetPlayerPed(id) ~= 0 then
                    SetPlayerRoutingBucket(id, toFloor.bucket)
                end
            end)
        end
        TriggerClientEvent('lf_elevatore:client:move', id, destination)
    end

    logUsage(source, name, toFloor)
    -- Public server event for other resources (heists, achievements, etc.)
    TriggerEvent('lf_elevatore:playerMoved', source, name, fromIndex, toIndex, passengers)

    return true
end)

-- Developer exports ----------------------------------------------------------

exports('getElevators', function()
    return clientElevators
end)

exports('isLocked', function(name)
    return locked[name] == true
end)

local function setLocked(name, state)
    if not elevators[name] then return false end
    locked[name] = state and true or nil
    clientElevators = sanitizeElevators()
    broadcastRefresh()
    return true
end
exports('setLocked', setLocked)

exports('addElevator', function(name, data, persist)
    if type(name) ~= 'string' or type(data) ~= 'table' then return false end
    local floors = data.floors or data
    if type(floors) ~= 'table' or #floors < 2 then return false end

    local entry = { label = data.label or name, groupTravel = data.groupTravel, floors = floors }
    if persist then
        savedElevators[name] = entry
        persistSaved()
    else
        apiElevators[name] = entry
    end
    rebuildElevators()
    broadcastRefresh()
    return true
end)

exports('removeElevator', function(name)
    local existed = apiElevators[name] or savedElevators[name]
    apiElevators[name] = nil
    if savedElevators[name] then
        savedElevators[name] = nil
        persistSaved()
    end
    if existed then
        rebuildElevators()
        broadcastRefresh()
    end
    return existed ~= nil
end)

-- In-game creator / editor ---------------------------------------------------

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

local function parseList(str)
    if type(str) ~= 'string' or str == '' then return nil end
    local out = {}
    for entry in str:gmatch('[^,]+') do
        local v = entry:match('^%s*(.-)%s*$')
        if v ~= '' then out[#out + 1] = v end
    end
    return #out > 0 and out or nil
end

RegisterNetEvent('lf_elevatore:server:addFloor', function(form)
    local src = source
    local session = sessions[src]
    if not session then return notify(src, 'creator_no_session', 'error') end
    if type(form) ~= 'table' or type(form.level) ~= 'string' or form.level == '' then return end

    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local function round(n) return math.floor(n * 100) / 100 end

    local hours
    if tonumber(form.open) and tonumber(form.close) then
        hours = { open = tonumber(form.open), close = tonumber(form.close) }
    end

    session.floors[#session.floors + 1] = {
        coords = { x = round(coords.x), y = round(coords.y), z = round(coords.z) },
        heading = round(GetEntityHeading(ped)),
        level = form.level,
        label = (type(form.label) == 'string' and form.label ~= '') and form.label or nil,
        pin = (type(form.pin) == 'string' and form.pin ~= '') and form.pin or nil,
        bucket = tonumber(form.bucket),
        jobs = parseGroups(form.jobs),
        gangs = parseGroups(form.gangs),
        items = parseList(form.items),
        owners = parseList(form.owners),
        consumeItem = form.consumeItem == true or form.consumeItem == 'true' or nil,
        hours = hours,
    }

    notify(src, 'creator_floor_added', 'success', #session.floors, form.level)
end)

lib.addCommand('elevator', {
    help = 'Manage lf_elevatore elevators',
    restricted = Config.AdminGroup,
    params = {
        { name = 'action', type = 'string', help = 'create|add|removefloor|save|cancel|edit|delete|lock|unlock|list' },
        { name = 'name', type = 'string', help = 'Elevator name, or floor index for removefloor', optional = true },
    },
}, function(source, args)
    local action = args.action:lower()

    if action == 'create' then
        if not args.name then return notify(source, 'creator_need_name', 'error') end
        if elevators[args.name] then return notify(source, 'creator_name_taken', 'error', args.name) end
        sessions[source] = { name = args.name, floors = {} }
        notify(source, 'creator_started', 'success', args.name)

    elseif action == 'edit' then
        if not args.name then return notify(source, 'creator_need_name', 'error') end
        local target = savedElevators[args.name]
        if not target then return notify(source, 'creator_not_saved', 'error', args.name) end
        local floorsCopy = json.decode(json.encode(target.floors))
        sessions[source] = { name = args.name, label = target.label, floors = floorsCopy, editing = true }
        notify(source, 'creator_editing', 'success', args.name, #floorsCopy)

    elseif action == 'add' then
        if not sessions[source] then return notify(source, 'creator_no_session', 'error') end
        TriggerClientEvent('lf_elevatore:client:floorDialog', source, #sessions[source].floors + 1)

    elseif action == 'removefloor' then
        local session = sessions[source]
        if not session then return notify(source, 'creator_no_session', 'error') end
        local idx = tonumber(args.name)
        if not idx or not session.floors[idx] then return notify(source, 'creator_bad_index', 'error') end
        table.remove(session.floors, idx)
        notify(source, 'creator_floor_removed', 'success', idx, #session.floors)

    elseif action == 'save' then
        local session = sessions[source]
        if not session then return notify(source, 'creator_no_session', 'error') end
        if #session.floors < 2 then return notify(source, 'creator_need_floors', 'error') end
        savedElevators[session.name] = { label = session.label or session.name, floors = session.floors }
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

    elseif action == 'lock' or action == 'unlock' then
        if not args.name then return notify(source, 'creator_need_name', 'error') end
        if not elevators[args.name] then return notify(source, 'creator_not_found', 'error', args.name) end
        setLocked(args.name, action == 'lock')
        notify(source, action == 'lock' and 'creator_locked' or 'creator_unlocked', 'inform', args.name)

    elseif action == 'list' then
        local names = {}
        for name, floors in pairs(elevators) do
            names[#names + 1] = ('%s (%d%s)'):format(name, #floors, locked[name] and ', locked' or '')
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
