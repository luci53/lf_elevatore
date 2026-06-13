-- luacheck configuration for lf_elevatore (FiveM / CfxLua)
std = 'lua54'
max_line_length = false
self = false

-- Ignore unused-self warnings on ox_lib point methods, and "argument always nil"
ignore = {
    '212', -- unused argument (CreateThread callbacks, event handlers)
    '432', -- shadowing an upvalue argument (source)
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
    'GetPlayerIdentifierByType', 'source',

    -- Client natives used
    'PlayerPedId', 'PlayerId', 'DoScreenFadeOut', 'DoScreenFadeIn',
    'IsScreenFadedOut', 'FreezeEntityPosition', 'RequestCollisionAtCoord',
    'HasCollisionLoadedAroundEntity', 'SetEntityCoords', 'SetEntityHeading',
    'IsControlJustReleased', 'PlaySoundFrontend', 'ShakeGameplayCam',
    'StopGameplayCamShaking',

    -- Libraries / framework
    'lib', 'cache', 'exports', 'GetInvokingResource',
}

-- Files may also assign to these shared globals.
globals = {
    'Config', 'Bridge', 'locale',
}
