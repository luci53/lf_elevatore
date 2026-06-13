Bridge = {}

local framework = Config.Framework
if framework == 'auto' then
    if GetResourceState('qbx_core') == 'started' then
        framework = 'qbox'
    elseif GetResourceState('ox_core') == 'started' then
        framework = 'oxcore'
    elseif GetResourceState('qb-core') == 'started' then
        framework = 'qbcore'
    elseif GetResourceState('es_extended') == 'started' then
        framework = 'esx'
    else
        framework = nil
        print('^1[lf_elevatore] No supported framework found (qbx_core / ox_core / qb-core / es_extended)^0')
    end
end

Bridge.Framework = framework

local QBCore, ESX
if framework == 'qbcore' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif framework == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

local function getPlayerData(source)
    if framework == 'qbox' then
        local player = exports.qbx_core:GetPlayer(source)
        return player and player.PlayerData
    elseif framework == 'qbcore' then
        local player = QBCore.Functions.GetPlayer(source)
        return player and player.PlayerData
    end
end

---Return the player's grade in a named group (job or gang), or nil if not a member.
---Unifies the job/gang concept so the same config works on every framework.
---@param source number
---@param groupName string
---@return number?
function Bridge.GetGroupGrade(source, groupName)
    if framework == 'oxcore' then
        local player = exports.ox_core:GetPlayer(source)
        if not player then return end
        local grade = player:getGroup(groupName)
        return grade
    elseif framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return end
        if xPlayer.job and xPlayer.job.name == groupName then
            return xPlayer.job.grade
        end
        return
    else -- qbox / qbcore
        local data = getPlayerData(source)
        if not data then return end
        if data.job and data.job.name == groupName then
            return data.job.grade and data.job.grade.level or 0
        end
        if data.gang and data.gang.name == groupName then
            return data.gang.grade and data.gang.grade.level or 0
        end
        return
    end
end

---Stable identifiers for owner-only floors (citizenid / stateId / license ...).
---@param source number
---@return table<string, boolean>
function Bridge.GetIdentifiers(source)
    local set = {}

    if framework == 'qbox' or framework == 'qbcore' then
        local data = getPlayerData(source)
        if data and data.citizenid then set[data.citizenid] = true end
    elseif framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer and xPlayer.identifier then set[xPlayer.identifier] = true end
    elseif framework == 'oxcore' then
        local player = exports.ox_core:GetPlayer(source)
        if player then
            if player.stateId then set[player.stateId] = true end
            if player.charId then set[tostring(player.charId)] = true end
        end
    end

    -- Always include raw identifiers so configs can use license:/discord: etc.
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        set[GetPlayerIdentifier(source, i)] = true
    end

    return set
end

---@param source number
---@param item string
---@return boolean
function Bridge.HasItem(source, item)
    if GetResourceState('ox_inventory') == 'started' then
        local count = exports.ox_inventory:Search(source, 'count', item)
        return (count or 0) > 0
    end

    if framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        local invItem = xPlayer.getInventoryItem(item)
        return invItem ~= nil and (invItem.count or 0) > 0
    elseif framework == 'qbox' or framework == 'qbcore' then
        local data = getPlayerData(source)
        if not data then return false end
        for _, slot in pairs(data.items or {}) do
            if slot and slot.name == item and (slot.amount or slot.count or 0) > 0 then
                return true
            end
        end
    end

    return false
end

---Remove `count` of an item (for consumable floor access). Returns success.
---@param source number
---@param item string
---@param count? number
---@return boolean
function Bridge.RemoveItem(source, item, count)
    count = count or 1

    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:RemoveItem(source, item, count) == true
    end

    if framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        xPlayer.removeInventoryItem(item, count)
        return true
    elseif framework == 'qbox' then
        return exports.qbx_core:RemoveItem(source, item, count) ~= false
    elseif framework == 'qbcore' then
        local player = QBCore.Functions.GetPlayer(source)
        if not player then return false end
        return player.Functions.RemoveItem(item, count) ~= false
    end

    return false
end
