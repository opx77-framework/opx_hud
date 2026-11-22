---@meta

-- opx_hud client exports. It is the `hud` provider of opx_core: other client resources find it with
-- Open77.exports.callSync('opx_core', 'GetProvider', 'hud') (nil when none runs) and call it with
-- Open77.exports.callSync(provider, name, ...) or Open77.exports.call(...):await(); for the whole-HUD toggle
-- prefer opx_core SetHudVisible / OPX.SetHudVisible.
-- Provider contract (docs/ARCHITECTURE.md › Replacing a resource): SetVisible, IsVisible; optional ShowHelp,
-- HideHelp. IsShown, SetBlockVisible, IsBlockVisible, SetCustomStatus and RemoveCustomStatus are opx_hud
-- extras: a replacement provider may not have them, so call them under pcall.

---@alias OpxHudBlock 'status' | 'info' | 'vehicle' | 'voice' | 'help' Config.positions keys: biomonitor, money/job strip, dashboard, voice block, help line.

---@class OpxHudCustomStatus A custom gauge of the biomonitor (SetCustomStatus).
---@field label string Up to 16 characters, upper-cased (accents too). Required when the gauge is created.
---@field value number 0..100, rounded; drawn as a gauge and a number.
---@field lowAt? number|false Red with a pulse at or below this value. Default Config.status.lowAt (33); false = never.
---@field highAt? number Red with a pulse at or above this value (a stress-like gauge). Default none.

---@alias OpxHudAnchor 'top-left' | 'top-center' | 'top-right' | 'bottom-left' | 'bottom-center' | 'bottom-right'

---@class OpxHudPosition
---@field anchor OpxHudAnchor
---@field x number Offset in dp from the anchored side (ignored horizontally for center, used as a shift).
---@field y number Offset in dp from the anchored top or bottom edge.

---@class OpxHudExports
local opx_hud = {}

--- Shows one help line, e.g. ShowHelp('Open the door', 'E'). Replaces the current line (the last caller
--- owns it). Drawn only while the HUD itself is drawn (kept and shown once it comes back).
---@param text string Up to 160 characters (control characters dropped, trimmed).
---@param key? string Key cap label, up to 16 characters, upper-cased; omitted = no key cap.
---@return boolean shown false when `text` is empty or not a string/number
function opx_hud.ShowHelp(text, key) end

--- Hides the help line. A resource can only hide a line it showed itself; the line of a resource that
--- stops is dropped.
---@return boolean hidden false when the current line belongs to another resource
function opx_hud.HideHelp() end

--- Script-level visibility of the whole HUD (opx_character turns it off during selection, through opx_core
--- SetHudVisible). One shared flag, not per caller: the last call wins. nil counts as true.
---@param visible boolean
---@return true
function opx_hud.SetVisible(visible) end

--- The last SetVisible value (default true), not whether the HUD is currently drawn:
--- the HUD also hides without a character, under menus and with the player's /hud toggle.
---@return boolean
function opx_hud.IsVisible() end

--- True while the HUD is on screen right now: a character is loaded, SetVisible is not false, the player has
--- not hidden it with /hud, no menu owns the screen and the creator is not open. Blocks hidden by
--- SetBlockVisible do not change it.
---@return boolean
function opx_hud.IsShown() end

--- Hides one block for the calling resource (a minigame hiding the dashboard, a cutscene hiding the voice
--- block), or gives it back. A block stays hidden while at least one resource hides it; the claims of a
--- resource that stops are dropped. Independent of SetVisible and of the player's /hud.
--- `SetBlockVisible('vehicle', false)` ... `SetBlockVisible('vehicle', true)`.
---@param block OpxHudBlock
---@param visible boolean false hides; anything else gives it back
---@return boolean ok
---@return 'invalid_block'? reason
function opx_hud.SetBlockVisible(block, visible) end

--- False while a resource hides that block with SetBlockVisible (nil for an unknown block name).
---@param block OpxHudBlock
---@return boolean?
function opx_hud.IsBlockVisible(block) end

--- Adds, updates or removes a custom gauge in the biomonitor, after hunger and thirst (oxygen, stress...).
--- Ids are per calling resource; its gauges go away when it stops. At most Config.status.customMax (2) at
--- once, in the order they were added.
---   SetCustomStatus('oxygen', { label = 'O2', value = 100 })  -- add (or replace)
---   SetCustomStatus('oxygen', 42)                             -- update the value only
---   SetCustomStatus('oxygen', nil)                            -- remove (same as RemoveCustomStatus)
--- Nothing is sent to the UI when the drawn value did not change, so calling it on every tick is cheap.
---@param id string 1..32 characters of [A-Za-z0-9_.:-]
---@param data OpxHudCustomStatus|number|nil|false
---@return boolean ok
---@return ('invalid_id'|'invalid_value'|'invalid_label'|'unknown_id'|'too_many')? reason
function opx_hud.SetCustomStatus(id, data) end

--- Removes one of the caller's custom gauges. True even when it did not exist.
---@param id string
---@return boolean ok
---@return 'invalid_id'? reason
function opx_hud.RemoveCustomStatus(id) end

-- Behaviour:
--   * The HUD is drawn only when a character is loaded, SetVisible is not false, the player has not used /hud,
--     no menu owns the screen (Config.hideInMenus; overlays of Config.keepVisibleFor do not count) and the
--     creator provider's IsOpen is false (Config.hideInCreator). The help line follows the same rule.
--   * Claims (help line, SetBlockVisible, custom gauges) are dropped when their resource stops, compared by
--     VM generation: a hot-reloaded resource keeps what its new VM set.
--   * Voice block: hides open-voice's own line (setHudVisible(false)) while opx_hud runs and gives it back on
--     stop; Config.blocks.voice = false keeps open-voice's line.
--   * Without NativeUI (no document can be created) the HUD disables itself and the vanilla HUD stays.
-- Events consumed: opx:playerLoaded (playerData), opx:playerUnloaded (), opx:setPlayerData (key, value)
--   for accounts / job / metadata; open77:menuStateChanged, open77:worldReady (re-applies vanilla claims),
--   onClientResourceStart / onClientResourceStop; open-voice:modeChanged (mode, distance, label, color),
--   open77:voice:talkingChanged (playerId, talking, level), open77:voice:pushToTalkKeyChanged (key).
--   After its own restart it asks opx_core IsPlayerLoaded / GetPlayerData.

-- Data read from opx_core (client net events opx:playerLoaded / opx:setPlayerData).

---@class OpxHudJob
---@field name string
---@field label string
---@field grade integer
---@field gradeName string
---@field gradeLabel string
---@field onDuty boolean

---@class OpxHudPlayerData
---@field accounts table<string, number> { money = 500, bank = 5000 }
---@field job OpxHudJob
---@field metadata table<string, any> hunger / thirst are 0..Config.needs.max

-- Config shapes (config.lua).

---@class OpxHudFloatPreset One block's camera float (Config.float.<block>).
---@field stiffness number How fast it catches up with the camera (1/s).
---@field trail number dp of offset per degree/second of camera turn, against the turn.
---@field trailMax number Cap of that offset, dp.
---@field turn number Degrees of yaw per degree/second of camera turn, with the turn.
---@field turnMax number Cap of that yaw, degrees.
---@field pitch number Degrees of tilt per degree/second of looking up or down.
---@field breath number[] { cycles per 6 s, dp }: slow idle drift.
---@field shake number Hit shake on a health drop (0 = none).
---@field kick number Weapon-fire kick, from Open77.weapons.shotCounters (0 = none).
---@field lean number Degrees of lean per km/h/s of the car's acceleration (0 = none).

---@class OpxHudFloatConfig
---@field enabled boolean
---@field biomonitor OpxHudFloatPreset
---@field info OpxHudFloatPreset
---@field vehicle OpxHudFloatPreset
---@field voice OpxHudFloatPreset
---@field help OpxHudFloatPreset

---@class OpxHudVoiceConfig
---@field resource string Range-mode resource (open-voice): exports getState, getModes, setHudVisible; event open-voice:modeChanged.
---@field pttResource string Push-to-talk owner (open77_voice): export getPushToTalkKey; event open77:voice:pushToTalkKeyChanged.
---@field pttKey string Talk cap shown when pttResource does not answer.
---@field cycleKey string Range cap shown until the voice resource answers.
---@field talkInterval integer ms between level reads while talking.
---@field stateInterval integer ms between range re-reads while drawn.
---@field peak number Input level (0..1) drawn as a red talking peak.
