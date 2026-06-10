-- Client-side framework bridge. Only used for menu UX (graying out locked
-- floors) - real access checks happen on the server.
Bridge = {}

local framework
if GetResourceState('qbx_core') == 'started' then
    framework = 'qbox'
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

---@return string? jobName, number? grade
function Bridge.GetJob()
    local data = getPlayerData()
    if not data or not data.job then return end
    if framework == 'esx' then
        return data.job.name, data.job.grade
    end
    return data.job.name, data.job.grade.level
end

---@return string? gangName, number? grade
function Bridge.GetGang()
    if framework == 'esx' then return end
    local data = getPlayerData()
    if not data or not data.gang then return end
    return data.gang.name, data.gang.grade.level
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
