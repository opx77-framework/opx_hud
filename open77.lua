resource "opx_hud"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

dependency "opx_core"

permissions {
    "network.events",     -- opx:playerLoaded / opx:playerUnloaded / opx:setPlayerData
    "players.stats.read", -- Open77.stats.get (health, armor, stamina)
    "vehicles.read",      -- Open77.vehicles.getPlayerSeat / get (speed, vehicle health)
    "session.menus",      -- Open77.session.menuState / isMenuOpen (hide under menus)
    "session.locale",     -- Open77.session.locale (Config.locale = 'auto': the game's language)
    "ui.vanilla.hud",     -- Open77.hud.setVisible (vanilla HUD claims)
    "voice.client",       -- Open77.voice.status (talking state and level of the voice block, read only)
    "player.weapons.read", -- Open77.weapons.shotCounters (shot kick of the camera float)
}

client_scripts {
    "config.lua",
    "client/main.lua",
}

files {
    "client/modules/*.lua",
    "ui/*.rml",
    "ui/*.rcss",
    "locales/*.json",
}
