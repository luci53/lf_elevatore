local resourceName = GetCurrentResourceName()
local SAVE_FILE = 'data/elevators.json'    -- saved elevators (map name -> {label,floors})
local SETTINGS_FILE = 'data/settings.json' -- { overrides = {...}, hidden = { name = true } }

local elevators = {}        -- runtime data (config + saved + api merged, full detail incl. PINs)
local clientElevators = {}  -- sanitized copy sent to clients (PINs/owners reduced to booleans)
local sourceOf = {}         -- name -> 'config' | 'saved' | 'api'
local savedElevators = {}   -- elevators created/edited in-game, persisted to SAVE_FILE
local apiElevators = {}      -- elevators registered at runtime via exports (not persisted)
local hidden = {}           -- config elevator names suppressed in-game
local locked = {}           -- maintenance lock state, keyed by elevator name
local overrides = {}        -- persisted runtime setting overrides
local sessions = {}         -- legacy /elevator command sessions, keyed by source
local lastUse = {}          -- per-player cooldown timestamps

-- Effective settings ---------------------------------------------------------
-- Settings the admin panel is allowed to tweak live; everything else stays in
-- config.lua. S is recomputed whenever overrides change.
local S

local function effective()
    local o = overrides
    local function pick(key, default)
        if o[key] ~= nil then return o[key] end
        return default
    end
    return {
        target = Config.Target,
        useTextUI = pick('useTextUI', Config.UseTextUI),
        interactKey = Config.InteractKey,
        interactDistance = pick('interactDistance', Config.InteractDistance),
        waitTime = pick('waitTime', Config.ElevatorWaitTime),
        fadeTime = pick('fadeTime', Config.FadeTime),
        debug = pick('debug', Config.Debug),
        shake = pick('shake', Config.ArrivalShake),
        sounds = Config.Sounds,
        groupTravelEnabled = pick('groupTravelEnabled', Config.GroupTravel.enabled),
        groupTravelRadius = pick('groupTravelRadius', Config.GroupTravel.radius),
        loggingEnabled = pick('loggingEnabled', Config.Logging and Config.Logging.enabled or false),
        logAllMoves = pick('logAllMoves', Config.Logging and Config.Logging.logAllMoves or false),
        useOxLib = Config.Logging and Config.Logging.useOxLib or false,
        webhook = pick('webhook', Config.Logging and Config.Logging.webhook or ''),
    }
end
S = effective()

-- Client only needs the presentation-related settings.
local function clientSettings()
    return {
        target = S.target,
        useTextUI = S.useTextUI,
        interactKey = S.interactKey,
        interactDistance = S.interactDistance,
        waitTime = S.waitTime,
        fadeTime = S.fadeTime,
        debug = S.debug,
        sounds = S.sounds,
        shake = S.shake,
    }
end

local function moveCooldown()
    return S.waitTime * 1000 + S.fadeTime * 2
end

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

local function addSource(name, src, kind)
    local entry = { label = src.label, groupTravel = src.groupTravel }
    for i, floor in ipairs(src.floors) do
        entry[i] = runtimeFloor(floor)
    end
    elevators[name] = entry
    sourceOf[name] = kind
end

local function rebuildElevators()
    elevators = {}
    sourceOf = {}

    for name, floors in pairs(Config.Elevators) do
        if not hidden[name] and not savedElevators[name] then
            addSource(name, { label = floors.label, groupTravel = floors.groupTravel, floors = floors }, 'config')
        end
    end
    for name, saved in pairs(savedElevators) do
        addSource(name, saved, 'saved')
    end
    for name, api in pairs(apiElevators) do
        addSource(name, api, 'api')
    end

    clientElevators = sanitizeElevators()
end

local function loadStore()
    local raw = LoadResourceFile(resourceName, SAVE_FILE)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then savedElevators = data end
    end

    local sraw = LoadResourceFile(resourceName, SETTINGS_FILE)
    if sraw and sraw ~= '' then
        local ok, data = pcall(json.decode, sraw)
        if ok and type(data) == 'table' then
            overrides = type(data.overrides) == 'table' and data.overrides or {}
            hidden = type(data.hidden) == 'table' and data.hidden or {}
        end
    end
    S = effective()
end

local function persistSaved()
    SaveResourceFile(resourceName, SAVE_FILE, json.encode(savedElevators), -1)
end

local function persistSettings()
    SaveResourceFile(resourceName, SETTINGS_FILE, json.encode({ overrides = overrides, hidden = hidden }), -1)
end

local function broadcastRefresh()
    TriggerClientEvent('lf_elevatore:client:refresh', -1, clientElevators)
end

local function broadcastSettings()
    TriggerClientEvent('lf_elevatore:client:settings', -1, clientSettings())
end

loadStore()
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
    return h >= hours.open or h < hours.close
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
    if not S.loggingEnabled then return end

    local restricted = toFloor.pin or toFloor.jobs or toFloor.gangs or toFloor.items or toFloor.owners
    if not S.logAllMoves and not restricted then return end

    local pName = GetPlayerName(source) or 'unknown'
    local msg = ('%s [%s] used elevator "%s" -> %s%s'):format(
        pName, source, elevatorName, toFloor.level, restricted and ' (restricted)' or '')

    if S.useOxLib then
        lib.logger(source, 'elevator', msg, ('elevator:%s'):format(elevatorName), ('floor:%s'):format(toFloor.level))
    end

    if S.webhook and S.webhook ~= '' then
        PerformHttpRequest(S.webhook, function() end, 'POST', json.encode({
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
    return clientSettings(), clientElevators
end)

lib.callback.register('lf_elevatore:requestMove', function(source, name, fromIndex, toIndex, pin)
    local floors = elevators[name]
    if not floors then return false, 'invalid' end
    if locked[name] then return false, 'locked' end

    local fromFloor = type(fromIndex) == 'number' and floors[fromIndex] or nil
    local toFloor = type(toIndex) == 'number' and floors[toIndex] or nil
    if not fromFloor or not toFloor or fromIndex == toIndex then return false, 'invalid' end

    local now = GetGameTimer()
    if lastUse[source] and now - lastUse[source] < moveCooldown() then
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

    if toFloor.consumeItem and toFloor.items and next(toFloor.items) then
        local item = firstOwnedItem(source, toFloor.items)
        if item and not Bridge.RemoveItem(source, item, 1) then
            return false, 'no_access'
        end
    end

    lastUse[source] = now

    local passengers = { source }
    if S.groupTravelEnabled and floors.groupTravel ~= false then
        local myBucket = GetPlayerRoutingBucket(source)
        for _, sid in ipairs(GetPlayers()) do
            local id = tonumber(sid)
            if id ~= source and GetPlayerRoutingBucket(id) == myBucket then
                local pedCoords = GetEntityCoords(GetPlayerPed(id))
                if #(pedCoords - coords) <= S.groupTravelRadius then
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
            SetTimeout(S.fadeTime, function()
                if GetPlayerPed(id) ~= 0 then
                    SetPlayerRoutingBucket(id, toFloor.bucket)
                end
            end)
        end
        TriggerClientEvent('lf_elevatore:client:move', id, destination)
    end

    logUsage(source, name, toFloor)
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

-- Admin layer ----------------------------------------------------------------

local function isAdmin(source)
    return source == 0 or IsPlayerAceAllowed(source, 'command.elevator')
end

local function nonEmpty(s)
    return (type(s) == 'string' and s ~= '') and s or nil
end

local function normalizeGroups(t)
    if type(t) ~= 'table' then return nil end
    local out = {}
    for k, v in pairs(t) do
        if type(k) == 'string' and k ~= '' then out[k] = tonumber(v) or 0 end
    end
    return next(out) ~= nil and out or nil
end

local function normalizeList(t)
    if type(t) ~= 'table' then return nil end
    local out = {}
    for _, v in ipairs(t) do
        local s = nonEmpty(type(v) == 'string' and (v:gsub('^%s*(.-)%s*$', '%1')) or nil)
        if s then out[#out + 1] = s end
    end
    return #out > 0 and out or nil
end

local function normalizeFloor(f)
    if type(f) ~= 'table' or type(f.coords) ~= 'table' then return nil end
    local c = f.coords
    if not (tonumber(c.x) and tonumber(c.y) and tonumber(c.z)) then return nil end

    local hours
    if f.hours and tonumber(f.hours.open) and tonumber(f.hours.close) then
        hours = { open = math.floor(tonumber(f.hours.open)), close = math.floor(tonumber(f.hours.close)) }
    end

    local size
    if f.size and tonumber(f.size.x) and tonumber(f.size.y) and tonumber(f.size.z) then
        size = { x = tonumber(f.size.x), y = tonumber(f.size.y), z = tonumber(f.size.z) }
    end

    return {
        coords = { x = tonumber(c.x), y = tonumber(c.y), z = tonumber(c.z) },
        heading = tonumber(f.heading) or 0.0,
        level = nonEmpty(f.level) or 'Floor',
        label = nonEmpty(f.label),
        pin = nonEmpty(f.pin),
        bucket = tonumber(f.bucket),
        jobs = normalizeGroups(f.jobs),
        gangs = normalizeGroups(f.gangs),
        items = normalizeList(f.items),
        owners = normalizeList(f.owners),
        consumeItem = (f.consumeItem == true) or nil,
        requireAll = (f.requireAll == true) or nil,
        hours = hours,
        size = size,
    }
end

-- Full (unsanitized) snapshot for the admin panel only.
lib.callback.register('lf_elevatore:admin:getAll', function(source)
    if not isAdmin(source) then return false end

    local out = {}
    for name, floors in pairs(elevators) do
        local fl = {}
        for i, floor in ipairs(floors) do fl[i] = floor end
        out[name] = {
            label = floors.label,
            groupTravel = floors.groupTravel,
            source = sourceOf[name],
            locked = locked[name] or false,
            floors = fl,
        }
    end

    return {
        elevators = out,
        settings = S,
        framework = Bridge.Framework or 'none',
    }
end)

lib.callback.register('lf_elevatore:admin:saveElevator', function(source, payload)
    if not isAdmin(source) then return false, 'no_perm' end
    if type(payload) ~= 'table' or not nonEmpty(payload.name) then return false, 'invalid' end

    if sourceOf[payload.name] == 'api' then return false, 'api_readonly' end

    local floors = {}
    if type(payload.floors) == 'table' then
        for _, f in ipairs(payload.floors) do
            local nf = normalizeFloor(f)
            if nf then floors[#floors + 1] = nf end
        end
    end
    if #floors < 2 then return false, 'need_floors' end

    savedElevators[payload.name] = {
        label = nonEmpty(payload.label) or payload.name,
        groupTravel = payload.groupTravel == false and false or nil,
        floors = floors,
    }
    hidden[payload.name] = nil -- un-hide if it was a deleted config elevator
    persistSaved()
    persistSettings()
    rebuildElevators()
    broadcastRefresh()
    return true
end)

lib.callback.register('lf_elevatore:admin:deleteElevator', function(source, name)
    if not isAdmin(source) then return false, 'no_perm' end
    if not elevators[name] then return false, 'invalid' end

    local kind = sourceOf[name]
    if kind == 'api' then return false, 'api_readonly' end

    savedElevators[name] = nil
    if kind == 'config' or hidden[name] ~= nil then
        hidden[name] = true -- suppress the config-defined one
    end
    locked[name] = nil
    persistSaved()
    persistSettings()
    rebuildElevators()
    broadcastRefresh()
    return true
end)

lib.callback.register('lf_elevatore:admin:setLocked', function(source, name, state)
    if not isAdmin(source) then return false, 'no_perm' end
    if not setLocked(name, state) then return false, 'invalid' end
    return true
end)

lib.callback.register('lf_elevatore:admin:saveSettings', function(source, newOverrides)
    if not isAdmin(source) then return false, 'no_perm' end
    if type(newOverrides) ~= 'table' then return false, 'invalid' end

    local allowed = {
        useTextUI = 'boolean', interactDistance = 'number', waitTime = 'number',
        fadeTime = 'number', debug = 'boolean', shake = 'boolean',
        groupTravelEnabled = 'boolean', groupTravelRadius = 'number',
        loggingEnabled = 'boolean', logAllMoves = 'boolean', webhook = 'string',
    }
    for key, expected in pairs(allowed) do
        local v = newOverrides[key]
        if v ~= nil and type(v) == expected then
            overrides[key] = v
        end
    end

    persistSettings()
    S = effective()
    broadcastSettings()
    return true, S
end)

RegisterNetEvent('lf_elevatore:admin:teleport', function(name, index)
    local src = source
    if not isAdmin(src) then return end
    local floors = elevators[name]
    local floor = floors and floors[tonumber(index)]
    if not floor then return end
    TriggerClientEvent('lf_elevatore:client:teleport', src, floor.coords, floor.heading or 0.0)
end)

-- Legacy /elevator command (still works) + opens the admin panel with no args --

local function parseGroups(str)
    if type(str) ~= 'string' or str == '' then return nil end
    local out = {}
    for entry in str:gmatch('[^,]+') do
        local name, grade = entry:match('^%s*([%w_]+)%s*:?%s*(%d*)%s*$')
        if name then out[name] = tonumber(grade) or 0 end
    end
    return next(out) ~= nil and out or nil
end

local function parseStringList(str)
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
        label = nonEmpty(form.label),
        pin = nonEmpty(form.pin),
        bucket = tonumber(form.bucket),
        jobs = parseGroups(form.jobs),
        gangs = parseGroups(form.gangs),
        items = parseStringList(form.items),
        owners = parseStringList(form.owners),
        consumeItem = form.consumeItem == true or nil,
        hours = hours,
    }

    notify(src, 'creator_floor_added', 'success', #session.floors, form.level)
end)

lib.addCommand('elevator', {
    help = 'Open the elevator admin panel (or manage via subcommands)',
    restricted = Config.AdminGroup,
    params = {
        { name = 'action', type = 'string', help = 'leave empty to open the panel; or create|save|cancel|delete|lock|unlock|list', optional = true },
        { name = 'name', type = 'string', help = 'Elevator name', optional = true },
    },
}, function(source, args)
    local action = args.action and args.action:lower() or nil

    if not action then
        TriggerClientEvent('lf_elevatore:client:openAdmin', source)
        return
    end

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
        hidden[session.name] = nil
        persistSaved()
        persistSettings()
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
        if not elevators[args.name] then return notify(source, 'creator_not_found', 'error', args.name) end
        savedElevators[args.name] = nil
        if sourceOf[args.name] == 'config' then hidden[args.name] = true end
        locked[args.name] = nil
        persistSaved()
        persistSettings()
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
