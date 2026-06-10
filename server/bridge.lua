Bridge = {}

local framework = Config.Framework
if framework == 'auto' then
    if GetResourceState('qbx_core') == 'started' then
        framework = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then
        framework = 'qbcore'
    elseif GetResourceState('es_extended') == 'started' then
        framework = 'esx'
    else
        framework = nil
        print('^1[lf_elevatore] No supported framework found (qbx_core / qb-core / es_extended)^0')
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

---@param source number
---@return string? jobName, number? grade
function Bridge.GetJob(source)
    if framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return end
        return xPlayer.job.name, xPlayer.job.grade
    end

    local data = getPlayerData(source)
    if not data or not data.job then return end
    return data.job.name, data.job.grade.level
end

---@param source number
---@return string? gangName, number? grade
function Bridge.GetGang(source)
    if framework == 'esx' then return end
    local data = getPlayerData(source)
    if not data or not data.gang then return end
    return data.gang.name, data.gang.grade.level
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
    elseif framework == 'qbcore' then
        local player = QBCore.Functions.GetPlayer(source)
        if not player then return false end
        local invItem = player.Functions.GetItemByName(item)
        return invItem ~= nil and (invItem.amount or invItem.count or 0) > 0
    end

    return false
end
