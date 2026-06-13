-- luacheck configuration for lf_elevatore (FiveM / CfxLua)
std = 'lua54'
max_line_length = false
self = false

-- fxmanifest.lua is the CfxLua manifest DSL (fx_version, game, *_scripts ...),
-- not a normal Lua module — don't lint it.
exclude_files = { 'fxmanifest.lua' }

-- Suppress stylistic / framework-idiomatic noise while keeping the checks that
-- matter (syntax errors, undefined globals 11x, unused locals 211).
-- Entries are Lua patterns matched against warning codes.
ignore = {
    '212',  -- unused argument (event handlers, ox_lib point methods, callbacks)
    '213',  -- unused loop variable
    '231',  -- local set but never accessed (framework-conditional locals)
    '311',  -- value assigned but never accessed
    '4..',  -- redefining / shadowing (idiomatic `local source = source`)
    '5..',  -- control-flow style (empty branches, unreachable guards)
    '6..',  -- whitespace / line-length cosmetics
}

-- Globals provided by the CfxLua runtime + libraries we rely on.
read_globals = {
    -- CfxLua core
    'Citizen', 'CreateThread', 'Wait', 'SetTimeout',
    'RegisterNetEvent', 'AddEventHandler', 'TriggerEvent', 'TriggerServerEvent',
    'TriggerClientEvent', 'RegisterCommand',
    'GetCurrentResourceName', 'GetResourceState', 'GetResourceMetadata',
    'LoadResourceFile', 'SaveResourceFile',
    'GetHashKey', 'GetGameTimer', 'GetConvar', 'GetConvarInt',
    'vector2', 'vector3', 'vector4', 'vec', 'vec2', 'vec3', 'vec4',
    'json', 'msgpack', 'promise', 'Cfx',
    'PerformHttpRequest',

    -- Server natives used
    'GetPlayers', 'GetPlayerPed', 'GetEntityCoords', 'GetEntityHeading',
    'GetPlayerRoutingBucket', 'SetPlayerRoutingBucket', 'GetPlayerName',
    'GetPlayerIdentifierByType', 'GetPlayerIdentifiers',
    'GetNumPlayerIdentifiers', 'GetPlayerIdentifier', 'IsPlayerAceAllowed',
    'source',

    -- Client natives used
    'PlayerPedId', 'PlayerId', 'DoScreenFadeOut', 'DoScreenFadeIn',
    'IsScreenFadedOut', 'FreezeEntityPosition', 'RequestCollisionAtCoord',
    'HasCollisionLoadedAroundEntity', 'SetEntityCoords', 'SetEntityHeading',
    'IsControlJustReleased', 'PlaySoundFrontend', 'ShakeGameplayCam',
    'StopGameplayCamShaking', 'DrawMarker',
    'SetNuiFocus', 'SendNUIMessage', 'RegisterNUICallback',

    -- Libraries / framework
    'lib', 'cache', 'exports', 'GetInvokingResource',
}

-- Files may also assign to these shared globals.
globals = {
    'Config', 'Bridge', 'locale',
}
