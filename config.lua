Config = {}

-- Language: 'auto' follows the game's language, or a file in locales/ ('en', 'fr'). Missing keys fall back to English.
Config.locale = 'auto'

-- Registers /hudtest (help line, fake damage, a sample custom gauge, block toggles). Keep it off on a live server.
Config.debug = false

-- Command a player uses to hide or show their own HUD. false disables it.
Config.toggleCommand = 'hud'

-- Blocks drawn on the HUD.
Config.blocks = {
	status = true,  -- biomonitor: health trace, armor segments, stamina ring
	needs = true,   -- hunger and thirst gauges in the biomonitor, read from character metadata
	money = true,   -- cash and bank in the top strip
	job = true,     -- job label, grade and duty in the top strip
	vehicle = true, -- speed and vehicle condition while seated
	voice = true,   -- voice block (range, talking, keys); replaces open-voice's own line. false keeps theirs
}

-- Where each block sits. anchor: top|bottom + left|center|right. x / y: offset in dp from that edge.
-- A block anchored left or right turns toward the screen centre, hinged on its outer edge.
Config.positions = {
	status = { anchor = 'bottom-left', x = 40, y = 44 },   -- biomonitor
	info = { anchor = 'top-right', x = 40, y = 36 },       -- money / job strip
	vehicle = { anchor = 'bottom-center', x = 0, y = 34 }, -- dashboard
	help = { anchor = 'bottom-center', x = 0, y = 176 },   -- help line, above the dashboard
	voice = { anchor = 'bottom-right', x = 40, y = 44 },   -- voice block, mirror of the biomonitor
}

-- Voice block. Range modes come from the voice resource (server-owned), talking from Open77.voice.status().
-- Every part is skipped while that resource is not running (block hidden).
Config.voice = {
	resource = 'open-voice',       -- range-mode resource: exports getState / getModes / setHudVisible
	pttResource = 'open77_voice',  -- push-to-talk owner: export getPushToTalkKey (key shown on the talk cap)
	pttKey = 'V',                  -- talk cap shown when pttResource does not answer
	cycleKey = 'F11',              -- range cap shown until the voice resource answers with its own key
	talkInterval = 80,             -- ms between level reads while talking (only then)
	stateInterval = 1500,          -- ms between range re-reads while drawn (recovery for a missed event)
	peak = 0.85,                   -- input level (0..1) drawn red as a talking peak
}

-- Thresholds in percent: at or below lowAt a value turns red with a short pulse; at or below critAt it keeps pulsing.
Config.status = {
	lowAt = 33,             -- health, hunger, thirst, vehicle condition turn red
	critAt = 15,            -- health keeps pulsing and its trace goes flat and irregular
	hideFullStamina = true, -- the stamina ring only shows while stamina is not full
	armorMax = 100,         -- armor points drawn as all segments lit
	armorSegments = 6,      -- number of armor segments (hidden at 0 armor)
	customMax = 2,          -- custom gauges other resources may add (SetCustomStatus); each row holds two
}

-- Heartbeat trace of the biomonitor (GPU effect, Lua only changes its parameters with health).
Config.ecg = {
	rateFull = 0.9,  -- beats per second at full health (the trace scrolls at this pace)
	rateLow = 2.2,   -- beats per second at lowAt and below: faster as health drops
	rateCrit = 0.7,  -- beats per second at critAt and below: slow, irregular, missing beats
	amplitude = 0.8, -- spike height, 0..1 of the trace box
	ampCrit = 0.3,   -- spike height at critAt and below (flat-ish); a flat line at 0 health
}

-- Needs: metadata keys (0..max) shown as gauges. Set a key to false to hide that gauge.
Config.needs = {
	hunger = 'hunger',
	thirst = 'thirst',
	max = 100,
}

-- Money display.
Config.money = {
	symbol = '€$',       -- currency symbol (eddies), printed before the cash amount
	symbolAfter = false, -- true prints "500 €$" instead of "€$ 500"
	separator = ' ',     -- thousands separator
	cash = 'money',      -- PlayerData.accounts key shown as cash
	bank = 'bank',       -- PlayerData.accounts key shown as bank; false hides it
}

-- Vehicle block.
Config.vehicle = {
	unit = 'kmh',     -- 'kmh' or 'mph'
	passenger = true, -- also show it to passengers, not only the driver
	maxSpeed = 220,   -- speed (in unit) that lights every segment of the speed bars
	segments = 7,     -- segments on each side of the speed
}

-- Motion. NativeUI animations already follow each player's `nui.reducedmotion`.
Config.motion = {
	reduced = false,    -- true = calm for everyone: blocks land in place, no float, no typing
	perspective = 1100, -- dp from the eye to the tilted blocks; smaller is stronger
	tilt = {
		status = 11,    -- degrees the biomonitor turns toward the screen centre (0 = flat)
		info = 9,       -- degrees the money / job strip turns toward the screen centre
		vehicle = 26,   -- degrees the dashboard lies back
		voice = 11,     -- degrees the voice block turns toward the screen centre
	},
}

-- Camera float: each block is its own document and trails the camera (one projection per frame, sent only
-- when it moved). Off with Config.motion.reduced, and for a player whose nui.reducedmotion is on.
--   stiffness  how fast it catches up with the camera      trail / trailMax  dp per degree/s of turn, cap
--   turn / turnMax  degrees of yaw per degree/s, cap        pitch  degrees of tilt per degree/s of look up/down
--   breath  { cycles per 6 s, dp } slow idle drift         shake  hit shake on a health drop (0 = none)
--   kick  weapon-fire kick (0 = none)                       lean  degrees per km/h/s of acceleration (0 = none)
Config.float = {
	enabled = true,
	biomonitor = { stiffness = 7, trail = 0.10, trailMax = 26, turn = 0.025, turnMax = 3.5, pitch = 0.02,
		breath = { 0.9, 2.2 }, shake = 1.0, kick = 1.0, lean = 0 },     -- lively, takes the hits
	info = { stiffness = 6, trail = 0.07, trailMax = 18, turn = 0.02, turnMax = 2.5, pitch = 0.015,
		breath = { 0.7, 1.4 }, shake = 0.4, kick = 0.5, lean = 0 },     -- calmer, small text stays legible
	vehicle = { stiffness = 3.2, trail = 0.18, trailMax = 40, turn = 0.05, turnMax = 6, pitch = 0.03,
		breath = { 1.35, 3.0 }, shake = 0, kick = 0.55, lean = 0.08 },  -- heavy and slow, leans with the car
	voice = { stiffness = 7, trail = 0.10, trailMax = 26, turn = 0.025, turnMax = 3.5, pitch = 0.02,
		breath = { 0.9, 2.0 }, shake = 0.6, kick = 0.8, lean = 0 },     -- mirror of the biomonitor
	help = { stiffness = 5, trail = 0.06, trailMax = 14, turn = 0.015, turnMax = 1.5, pitch = 0.01,
		breath = { 0.8, 1.0 }, shake = 0, kick = 0.3, lean = 0 },       -- barely moves: it must stay readable
}

-- Milliseconds between reads on foot and in a vehicle. The UI only receives values that changed.
Config.updateInterval = 250
Config.vehicleInterval = 100

-- Hide the HUD while a menu owns the screen (pause menu, map, photo mode, chat input...).
Config.hideInMenus = true

-- Resources whose cursor does not count as a menu: the HUD stays on screen while they hold it.
Config.keepVisibleFor = {
	opx_target = true,
	opx_chat = true,   -- typing in the chat keeps the HUD on screen
}

-- Hide the HUD while the character creator is open (the opx_core `creator` provider's client export IsOpen).
Config.hideInCreator = true

-- Vanilla HUD components hidden while this resource runs (Open77.hud). true = hidden.
Config.vanilla = {
	minimap = true,
	compass = true,
	clock = true,
	health = true,
	stamina = true,
	weapon = true,
	speedometer = true,
	questTracker = true,
	phone = true,
	vanillaNotifications = true,
	crosshair = true,
	-- These two also switch a game feature off, not only a display: hidden scanner = no scanning,
	-- hidden hubMenu = no inventory/map hub. Set true only if your server replaces them.
	scanner = false,
	hubMenu = false,
}
