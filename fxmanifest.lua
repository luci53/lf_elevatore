fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'lucifer'
description 'Framework-agnostic elevator script for QBox, QBCore and ESX, powered by ox_lib'
version '3.0.0'

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/bridge.lua',
    'client/client.lua',
}

server_scripts {
    'config.lua',
    'server/bridge.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
}
