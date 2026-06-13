-- Client-side framework bridge. Only used for menu UX (graying out locked
-- floors) - real access checks always happen on the server.
Bridge = {}

local framework
if GetResourceState('qbx_core') == 'started' then
    framework = 'qbox'
elseif GetResourceState('ox_core') == 'started' then
    framework = 'oxcore'
elseif GetResourceState('qb-core') == 'started' then
    framework = 'qbcore'
elseif GetResourceState('es_extended') == 'started' then
    framework = 'esx'
end

Bridge.Framework = framework

local QBCore, ESX
if framework == 'qbcore' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif framework == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

local function getPlayerData()
    if framework == 'qbox' then
        return exports.qbx_core:GetPlayerData()
    elseif framework == 'qbcore' then
        return QBCore.Functions.GetPlayerData()
    elseif framework == 'esx' then
        return ESX.GetPlayerData()
    end
end

---@param groupName string
---@return number? grade  nil = unknown/not a member (ox_core defers to server)
function Bridge.GetGroupGrade(groupName)
    if framework == 'oxcore' then
        return nil -- groups not resolved client-side; server is authoritative
    elseif framework == 'esx' then
        local data = getPlayerData()
        if data and data.job and data.job.name == groupName then
            return data.job.grade
        end
        return nil
    else -- qbox / qbcore
        local data = getPlayerData()
        if not data then return nil end
        if data.job and data.job.name == groupName then
            return data.job.grade and data.job.grade.level or 0
        end
        if data.gang and data.gang.name == groupName then
            return data.gang.grade and data.gang.grade.level or 0
        end
        return nil
    end
end

---@return boolean usesServerOnly  true when client cannot resolve access (ox_core)
function Bridge.DefersToServer()
    return framework == 'oxcore' or framework == nil
end

---@param item string
---@return boolean
function Bridge.HasItem(item)
    if GetResourceState('ox_inventory') == 'started' then
        local count = exports.ox_inventory:Search('count', item)
        return (count or 0) > 0
    end

    local data = getPlayerData()
    if not data then return false end

    if framework == 'esx' then
        for _, slot in ipairs(data.inventory or {}) do
            if slot.name == item and (slot.count or 0) > 0 then
                return true
            end
        end
    else
        for _, slot in pairs(data.items or {}) do
            if slot and slot.name == item and (slot.amount or slot.count or 0) > 0 then
                return true
            end
        end
    end

    return false
end
