--- The HUD documents: one NativeUI document per block (a projection tilts a whole document, so each block
--- floats on its own), model updates (change-gated, routed to the document that draws the field),
--- layout from config and visibility.
local Locale = require('client.modules.locale')
local Layout = require('client.modules.layout')
local Ecg = require('client.modules.ecg')
local Wave = require('client.modules.wave')

local Hud = {}

-- The documents, in drawing order. `on`: the model field(s) that put the block on screen.
-- `pos`: Config.positions key, also the block name of the SetBlockVisible export.
-- `anchor`: the anchor element the layout stylesheet places.
local DOCS = {
	{ name = 'bio', file = 'ui/bio.rml', pos = 'status', anchor = '#status-anchor', on = { 'statusOn', 'needsOn', 'customOn' } },
	{ name = 'info', file = 'ui/info.rml', pos = 'info', anchor = '#info-anchor', on = { 'infoOn' } },
	{ name = 'vehicle', file = 'ui/vehicle.rml', pos = 'vehicle', anchor = '#vehicle-anchor', on = { 'vehicleOn' } },
	{ name = 'voice', file = 'ui/voice.rml', pos = 'voice', anchor = '#voice-anchor', on = { 'voiceOn' } },
	{ name = 'help', file = 'ui/help.rml', pos = 'help', anchor = '#help-anchor', on = { 'helpOn' } },
}
Hud.DOCS = DOCS

-- Block name (Config.positions key, SetBlockVisible) -> document name, and document name -> its entry.
local BLOCK_DOC, BY_NAME = {}, {}
for _, entry in ipairs(DOCS) do
	BLOCK_DOC[entry.pos] = entry.name
	BY_NAME[entry.name] = entry
end

-- Which document(s) draw a model field. `t` (labels) goes to every document at creation.
local ROUTE = {}
do
	local owners = {
		bio = { 'statusOn', 'health', 'ecg', 'armor', 'armorOn', 'armorSegs', 'stamina', 'staminaOn',
			'needsOn', 'hungerOn', 'hunger', 'thirstOn', 'thirst', 'lowAt', 'critAt', 'customOn', 'custom' },
		info = { 'infoOn', 'cashOn', 'cash', 'bankOn', 'bank', 'jobOn', 'jobLabel', 'gradeLabel', 'dutyOn', 'onDuty' },
		vehicle = { 'vehicleOn', 'speed', 'speedPct', 'segL', 'segR', 'speedUnit', 'condition', 'engineOn', 'lowAt' },
		voice = { 'voiceOn', 'vState', 'vStateLabel', 'vMode', 'vDist', 'vPips', 'vWave', 'vPeak', 'vPtt', 'vCycle' },
		help = { 'helpOn', 'helpText', 'helpKey' },
	}
	for doc, fields in pairs(owners) do
		for _, field in ipairs(fields) do
			ROUTE[field] = ROUTE[field] or {}
			ROUTE[field][#ROUTE[field] + 1] = doc
		end
	end
end

local docs = {}      -- name -> document handle
local sent = {}      -- last value the documents received, per model field
local pending = nil  -- fields changed since the last flush
local shown = false
local watchers = {}
local hiddenDocs = {}   -- document name -> true while a SetBlockVisible claim hides it
local drawn = {}        -- document name -> true while that document is shown
local blockWatchers = {}

-- Every condition must hold for the HUD to be drawn.
local state = {
	loaded = false,  -- a character is loaded (opx_core)
	wanted = true,   -- the last SetVisible value: one shared flag, the last call wins (client/main.lua)
	user = true,     -- the player's own /hud toggle
	menu = false,    -- a menu owns the screen
	creator = false, -- the character creator is open
}

local function labels()
	local t = Locale.t
	return {
		bio = t('bio.title'),
		health = t('status.health'), armor = t('status.armor'), stamina = t('status.stamina'),
		hunger = t('needs.hunger'), thirst = t('needs.thirst'),
		bank = t('money.bank'), onDuty = t('job.onDuty'), offDuty = t('job.offDuty'),
		condition = t('vehicle.condition'), engineOff = t('vehicle.engineOff'),
		voice = t('voice.title'), voiceTalk = t('voice.talk'), voiceRange = t('voice.range'),
	}
end

--- Armor segments: segment i is lit once armor reaches the middle of its slice.
local function armorSegments()
	local count = math.max(1, math.floor(tonumber(Config.status.armorSegments) or 6))
	local list = {}
	for i = 1, count do
		list[i] = { t = (i - 0.5) * 100 / count }
	end
	return list
end

--- Speed bars: heights grow toward the speed; segment i lights at i / count of maxSpeed.
--- The left bar is listed outer to inner, the right one inner to outer.
local function speedSegments()
	local count = math.max(2, math.floor(tonumber(Config.vehicle.segments) or 7))
	local left, right = {}, {}
	for i = 1, count do
		local segment = {
			t = i * 100 / count,
			h = math.floor(5 + 17 * (i - 1) / (count - 1) + 0.5),
			hot = i > count - 2,
		}
		left[i] = segment
		right[count + 1 - i] = segment
	end
	return left, right
end

local function initialModel()
	local status = Config.status
	local left, right = speedSegments()
	return {
		lowAt = status.lowAt, critAt = status.critAt,
		statusOn = false, health = 100, ecg = Ecg.decorator(100),
		armor = 0, armorOn = false, armorSegs = armorSegments(),
		stamina = 100, staminaOn = false,
		needsOn = false, hungerOn = false, hunger = 100, thirstOn = false, thirst = 100,
		customOn = false, custom = {},
		infoOn = false, cashOn = false, cash = '', bankOn = false, bank = '',
		jobOn = false, jobLabel = '', gradeLabel = '', dutyOn = true, onDuty = true,
		vehicleOn = false, speed = 0, speedPct = 0, segL = left, segR = right,
		speedUnit = Locale.t(Config.vehicle.unit == 'mph' and 'vehicle.mph' or 'vehicle.kmh'),
		condition = 100, engineOn = true,
		voiceOn = false, vState = 'offline', vStateLabel = Locale.t('voice.offline'), vMode = '', vDist = '',
		vPips = {}, vWave = Wave.decorator('offline', 0), vPeak = false,
		vPtt = Config.voice.pttKey or 'V', vCycle = Config.voice.cycleKey or 'F11',
		helpOn = false, helpText = '', helpKey = '',
	}
end

--- Shows or hides each document to match the HUD state and the block claims. Returns the documents that
--- came back on screen while the HUD stayed shown (a block un-hidden by SetBlockVisible).
---@return string[]
local function applyDocs()
	local back = {}
	for _, entry in ipairs(DOCS) do
		local doc = docs[entry.name]
		local want = shown and not hiddenDocs[entry.name]
		if doc and (drawn[entry.name] == true) ~= want then
			drawn[entry.name] = want
			if want then doc:show() else doc:hide() end
			if want then back[#back + 1] = entry.name end
		end
	end
	return back
end

local function refresh()
	local now = next(docs) ~= nil and state.loaded and state.wanted and state.user and not state.menu
		and not state.creator
	if now == shown then return end
	shown = now
	applyDocs()
	for i = 1, #watchers do watchers[i](now) end
end

---@return boolean ok
function Hud.create()
	if type(Open77.ui) ~= 'table' or type(Open77.ui.create) ~= 'function' then
		Open77.log.warn('[opx_hud] NativeUI is not available on this client: HUD disabled')
		return false
	end
	Ecg.register()
	Wave.register()
	local model = initialModel()
	for key, value in pairs(model) do sent[key] = value end

	local t = labels()
	for i, entry in ipairs(DOCS) do
		local fields = { t = t }
		for key, value in pairs(model) do
			for _, owner in ipairs(ROUTE[key] or {}) do
				if owner == entry.name then fields[key] = value end
			end
		end
		local doc, reason = Open77.ui.create({
			document = entry.file,
			layer = 'hud',
			zIndex = i,
			visible = false,
			models = { hud = fields },
		})
		if doc then
			docs[entry.name] = doc
			local name = entry.name
			doc:onEvent('error', function(command, detail)
				Open77.log.warn(('[opx_hud] %s %s: %s'):format(name, tostring(command), tostring(detail and detail.message)))
			end)
			doc:stylesheet('layout', Layout.rule(entry.anchor, Config.positions[entry.pos]))
		else
			Open77.log.error(('[opx_hud] cannot create %s: %s'):format(entry.file, tostring(reason)))
		end
	end
	return next(docs) ~= nil
end

--- Block names of the SetBlockVisible export (Config.positions keys).
---@param block any
---@return boolean
function Hud.isBlock(block)
	return type(block) == 'string' and BLOCK_DOC[block] ~= nil
end

--- Hides (or gives back) one block's document while the rest of the HUD stays. `hidden` comes from the
--- SetBlockVisible claims (client/modules/blocks.lua).
---@param block string Config.positions key
---@param hidden boolean
function Hud.setBlockHidden(block, hidden)
	local name = BLOCK_DOC[block]
	if not name or (hiddenDocs[name] == true) == (hidden == true) then return end
	hiddenDocs[name] = hidden == true or nil
	local back = applyDocs()
	for _, doc in ipairs(back) do
		for i = 1, #blockWatchers do blockWatchers[i](doc) end
	end
end

--- `fn(docName)` runs when one document comes back on screen while the HUD stays shown.
---@param fn fun(name: string)
function Hud.onBlockShown(fn)
	blockWatchers[#blockWatchers + 1] = fn
end

--- Sends the labels again (the game language became known after the documents were created).
function Hud.relabel()
	local t = labels()
	for _, doc in pairs(docs) do doc:merge('hud', { t = t }) end
	Hud.set('speedUnit', Locale.t(Config.vehicle.unit == 'mph' and 'vehicle.mph' or 'vehicle.kmh'))
	Hud.flush()
end

--- A document handle by block name ('bio', 'info', 'vehicle', 'voice', 'help'); nil when missing.
---@param name string
function Hud.doc(name)
	return docs[name]
end

--- True when the block of that document has something to draw (and no claim hides it).
---@param name string
---@return boolean
function Hud.blockOn(name)
	local entry = BY_NAME[name]
	if not entry or hiddenDocs[name] then return false end
	local on = entry.on
	for i = 1, #on do
		if sent[on[i]] then return true end
	end
	return false
end

--- Queues one model field; nothing is sent when the value did not change.
---@param key string
---@param value any
function Hud.set(key, value)
	if sent[key] == value then return end
	sent[key] = value
	pending = pending or {}
	pending[key] = value
end

--- The value the documents last received (or will receive at the next flush).
---@param key string
function Hud.get(key)
	return sent[key]
end

--- Sends every queued field: one merge per document that draws one of them.
function Hud.flush()
	if not pending then return end
	local batches = {}
	for key, value in pairs(pending) do
		for _, owner in ipairs(ROUTE[key] or {}) do
			batches[owner] = batches[owner] or {}
			batches[owner][key] = value
		end
	end
	pending = nil
	for name, fields in pairs(batches) do
		local doc = docs[name]
		if doc then doc:merge('hud', fields) end
	end
end

---@param name 'loaded'|'wanted'|'user'|'menu'|'creator'
---@param value boolean
function Hud.setState(name, value)
	state[name] = value == true
	refresh()
end

---@param name 'loaded'|'wanted'|'user'|'menu'|'creator'
---@return boolean
function Hud.getState(name)
	return state[name]
end

--- True while the documents are drawn.
---@return boolean
function Hud.isShown()
	return shown
end

--- `fn(shown)` runs whenever the drawn state flips.
---@param fn fun(shown: boolean)
function Hud.onShownChanged(fn)
	watchers[#watchers + 1] = fn
end

return Hud
