fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Mazus / MZ Core'
description 'MZ Doors - sistema de portas persistentes com ACE e banco'
version '0.2.0'

shared_scripts {
    'shared/config.lua',
    'shared/v2_logic.lua'
}

client_scripts {
    'client/main.lua',
    'client/v2.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/database_v2.lua',
    'server/access_v2.lua',
    'server/main.lua',
    'server/v2.lua'
}

dependencies {
    'oxmysql',
    'mz_core',
    'mz_org'
}
