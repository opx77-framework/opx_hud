# opx_hud

The player HUD: health, armor, stamina, hunger and thirst bottom-left, money and job top-right, a speed dashboard in vehicles, a voice block and a help line.
It hides the vanilla HUD and only shows once a character is loaded.

## Install
- Needs: `opx_core`. Load after `opx_core`. Optional: `open-voice` / `open77_voice` for the voice block.
- No database. Client only.
- Needs an Open77 client with NativeUI; on an older client it switches off and the vanilla HUD stays.

## In game
- `/hud`: hide or show your own HUD.
- The HUD hides itself in menus and in the character creator.
- `/hudtest [hide|hit|status|block <name>]` (only with `Config.debug`): test the help line, damage shake, a sample gauge, block toggles.

## Config
`config.lua`: `blocks` (which blocks are drawn), `positions`, `money` (symbol and accounts), `vanilla` (vanilla HUD parts to hide). Everything else is commented in the file. Colours: top of `ui/hud.rcss`.

## For developers
- Provider of the `hud` slot: find it with `Open77.exports.callSync('opx_core', 'GetProvider', 'hud')`. A replacement implements the exports in `types.lua`.
- `SetVisible(visible)` / `IsVisible()` → whole HUD for a scene (prefer opx_core `SetHudVisible`).
- `ShowHelp(text, key?)` / `HideHelp()` → one help line with a key cap, e.g. `ShowHelp('Open the door', 'E')`.
- `SetBlockVisible(block, visible)` → hide `'status'`, `'info'`, `'vehicle'`, `'voice'` or `'help'` for your resource.
- `SetCustomStatus(id, { label, value })` → `true` or `false, reason`: an extra gauge (oxygen, stress), 2 at most.
- Extras beyond `SetVisible` / `IsVisible` / `ShowHelp` / `HideHelp` may be missing in a replacement: call them under `pcall`.
- Full contract: `types.lua`.
