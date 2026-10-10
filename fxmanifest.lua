fx_version 'cerulean'
game 'gta5'
lua54 "yes"

description 'Polisek scripts - Mechanic'
version "1.0.0"

dependencies {'ox_lib', 'oxmysql'}

shared_scripts {
    '@ox_lib/init.lua',
    -- BRIDGE
    "BRIDGE/config.lua",
    -- CONFIG
    "secure.lua",
    'config.lua',
    'configs/parts.lua',
    'configs/effects.lua',
    'configs/tuning.lua',
    'configs/supplier.lua',
    'configs/crafting.lua',
    'configs/missions.lua',
    'configs/extras.lua',
    'configs/animations.lua',
    'shared/utils.lua',
}

client_scripts {
    -- BRIDGE
    "BRIDGE/client/framework.lua",
    "BRIDGE/client/inventory.lua",
    "BRIDGE/client/target.lua",
    -- CONFIG
    'configs/client.lua',
    -- CORE
    'client/main.lua',
    'client/inventory.lua',
    'client/items.lua',
    'client/animations.lua',
    'client/fetch.lua',
    -- MODULES
    'client/shops.lua',
    'client/creator.lua',
    'client/settings.lua',
    'client/vehicle.lua',
    'client/diagnostics.lua',
    'client/repair.lua',
    'client/lift.lua',
    'client/history.lua',
    'client/tuning.lua',
    'client/catalog.lua',
    'client/supply.lua',
    'client/crafting.lua',
    'client/billing.lua',
    'client/menu.lua',
    'client/missions.lua',
    'client/props.lua',
    'client/stations.lua',
    -- EXPORTS
    'client/api.lua',
}

server_scripts {
    -- SQL
    '@oxmysql/lib/MySQL.lua',
    -- BRIDGE
    "BRIDGE/server/framework.lua",
    "BRIDGE/server/inventory.lua",
    -- CORE
    'server/open.lua',
    'server/core.lua',
    'server/items.lua',
    -- MODULES
    'server/shops.lua',
    'server/fetch.lua',
    'server/vehicles.lua',
    'server/repair.lua',
    'server/lift.lua',
    'server/tuning.lua',
    'server/catalog.lua',
    'server/supply.lua',
    'server/crafting.lua',
    'server/billing.lua',
    'server/menu.lua',
    'server/missions.lua',
    'server/props.lua',
    'server/stations.lua',
    -- EXPORTS
    'server/api.lua',
    'server/api_vehicles.lua',
}

ui_page 'web/dist/index.html'

files {
    'locales/*.json',
    'web/dist/index.html',
    'web/dist/assets/*',
}

escrow_ignore {
    "BRIDGE/config.lua",
    "BRIDGE/client/framework.lua",
    "BRIDGE/client/inventory.lua",
    "BRIDGE/client/target.lua",
    "BRIDGE/server/framework.lua",
    "BRIDGE/server/inventory.lua",
    "config.lua",
    "configs/*.lua",
    "secure.lua",
    "server/open.lua",
    "INSTALL/*.lua",
}
