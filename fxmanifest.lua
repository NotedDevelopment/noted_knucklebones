fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'noted_knucklebones_phone'
author 'NotedDevelopment'
description 'Knucklebones as an LB Phone app: rooms by code, spectating, and a CPU opponent'
version '0.1.0'

shared_scripts {
    'config.lua',
    'shared/game.lua',
}
server_scripts {
    '@ox_lib/init.lua', -- lib.logger for nickname changes
    'server/match.lua',
    'server/main.lua',
}
client_scripts {
    'client/main.lua',
}

-- The page is also loaded as this resource's own (invisible) NUI; the phone loads its own copy.
ui_page 'ui/index.html'
files {
    'ui/index.html',
    'ui/app.js',
    'ui/style.css',
    'ui/icon.svg',
    'ui/fonts/*.woff2',
    'ui/sounds/*.ogg',
}

dependencies {
    'lb-phone',
}
