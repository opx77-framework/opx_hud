--- The voice block: range mode from the voice resource (Config.voice.resource, open-voice: server-owned
--- modes), talking state and level from Open77.voice.status(), push-to-talk key from open77_voice.
--- While our block runs, open-voice's own line is hidden (setHudVisible(false)) and given back when this
--- resource stops. Nothing is read while the voice resource is not running: the block is hidden.
local Hud = require('client.modules.hud')
local Locale = require('client.modules.locale')
local Format = require('client.modules.format')
local Wave = require('client.modules.wave')
local Motion = require('client.modules.motion')

local Voice = {}

local cfg = Config.voice
local enabled = Config.blocks.voice == true and type(cfg) == 'table' and type(cfg.resource) == 'string'

local canReadStatus = type(Open77.voice) == 'table' and type(Open77.voice.status) == 'function'

local running = false   -- the voice resource is running
local modes = {}        -- { { name, label, distance } } from getModes
local current = nil     -- { mode, label, distance } from getState / open-voice:modeChanged
local lastStateRead = 0 -- GetGameTimer() of the last getState
local fastRunning = false
local localId = nil
local pttKey = nil      -- push-to-talk key cap text

---@param resource string
---@param name string
---@return any
local function call(resource, name, ...)
	local ok, result = pcall(Open77.exports.callSync, resource, name, ...)
	if ok then return result end
	return nil
end

---@param name string
---@return boolean
local function isRunning(name)
	return type(name) == 'string' and GetResourceState(name) == 'running'
end

--- "20 m", "2.5 m".
---@param metres any
---@return string
local function distance(metres)
	metres = math.max(0, tonumber(metres) or 0)
	if metres > 0 and metres < 10 and metres ~= math.floor(metres) then
		local tenths = math.floor(metres * 10 + 0.5)
		return ('%d.%d m'):format(tenths // 10, tenths % 10)
	end
	return ('%d m'):format(math.floor(metres + 0.5))
end

--- The mode label: ours from the locales (voice.mode.<name>), else the resource's, upper-cased.
---@param mode string
---@param label any
---@return string
local function modeLabel(mode, label)
	local key = 'voice.mode.' .. tostring(mode)
	local text = Locale.t(key)
	if text ~= key then return text end
	return Format.upper(Format.clean(label or mode, 24))
end

---@param key any
---@return string
local function keyCap(key, fallback)
	local text = Format.clean(key, 12)
	if text == '' then text = Format.clean(fallback, 12) end
	return Format.upper(text)
end

--- Range fields from `current` and `modes`.
local function applyRange()
	if not current then
		Hud.set('vMode', '')
		Hud.set('vDist', '')
		-- a new {} is always "changed" for Hud.set: replaced only when pips were drawn
		if Hud.get('vPipsKey') ~= '' then
			Hud.set('vPipsKey', '')
			Hud.set('vPips', {})
		end
		return false
	end
	local before = Hud.get('vMode')
	Hud.set('vMode', modeLabel(current.mode, current.label))
	Hud.set('vDist', distance(current.distance))
	local pips, signature = {}, {}
	for i, mode in ipairs(modes) do
		if i > 8 then break end
		local on = mode.name == current.mode
		pips[i] = { on = on }
		signature[i] = on and '1' or '0'
	end
	-- the pips list is replaced only when it changed
	local key = table.concat(signature)
	if Hud.get('vPipsKey') ~= key then
		Hud.set('vPipsKey', key)
		Hud.set('vPips', pips)
	end
	return before ~= '' and before ~= Hud.get('vMode')
end

--- Reads the range state (and the mode list, the keys) from the resources.
local function readState()
	lastStateRead = GetGameTimer()
	local state = call(cfg.resource, 'getState')
	if type(state) == 'table' and state.configured ~= false and state.mode then
		current = { mode = tostring(state.mode), label = state.label, distance = state.distance }
		Hud.set('vCycle', keyCap(state.cycleKey, cfg.cycleKey or 'F11'))
	end
	local list = call(cfg.resource, 'getModes')
	if type(list) == 'table' then
		local parsed = {}
		for i, mode in ipairs(list) do
			if type(mode) == 'table' and mode.name then
				parsed[#parsed + 1] = { name = tostring(mode.name), label = mode.label, distance = mode.distance }
			end
			if i >= 8 then break end
		end
		modes = parsed
	end
	if isRunning(cfg.pttResource) then
		pttKey = keyCap(call(cfg.pttResource, 'getPushToTalkKey'), cfg.pttKey or 'V')
	end
	applyRange()
end

--- Talking state from the native snapshot. Returns true while the player talks (or a VAD signal shows).
---@return boolean live
local function readTalk()
	local status = canReadStatus and Open77.voice.status() or nil
	local level = 0
	local state = 'offline'
	local vad = false
	if type(status) == 'table' and status.available == true and current then
		level = tonumber(status.inputLevel or status.microphoneActivity) or 0
		if status.captureEnabled ~= true then
			state = 'muted'
		elseif status.transmitting == true then
			state = 'talking'
		else
			state = 'idle'
		end
		vad = status.voiceActivation == true
	end
	-- voice activation has no key: the talk cap reads VAD then
	Hud.set('vPtt', vad and Locale.t('voice.vad') or pttKey or keyCap(cfg.pttKey, 'V'))
	local q = state == 'muted' and 0 or Wave.quantize(level)
	local peak = state == 'talking' and level >= (cfg.peak or 0.85)
	Hud.set('vState', state)
	Hud.set('vStateLabel', Locale.t('voice.' .. state))
	Hud.set('vPeak', peak)
	Hud.set('vWave', Wave.decorator(state, q, peak))
	return state == 'talking' or (state == 'idle' and level > 0.025)
end

--- While the player talks, the level is read every Config.voice.talkInterval ms (and only then).
local function startFast()
	if fastRunning then return end
	fastRunning = true
	CreateThread(function()
		while running and Hud.isShown() do
			local live = readTalk()
			Hud.flush()
			if not live then break end
			Wait(cfg.talkInterval or 80)
		end
		fastRunning = false
	end)
end

--- open-voice draws its own line; ours replaces it while this resource runs.
---@param visible boolean
local function setOfficialHud(visible)
	if not enabled or not isRunning(cfg.resource) then return end
	call(cfg.resource, 'setHudVisible', visible)
end

--- The voice resource came up (start of this resource, or it (re)started): hide its line and read it.
local function attach()
	running = true
	setOfficialHud(false)
	-- its document and its first server answer arrive a moment later: hide and read again then
	for _, delay in ipairs({ 1000, 4000 }) do
		SetTimeout(delay, function()
			if not running then return end
			setOfficialHud(false)
			readState()
			Hud.flush()
		end)
	end
	readState()
	local appeared = not Hud.get('voiceOn')
	Hud.set('voiceOn', true)
	readTalk()
	Hud.flush()
	if appeared then Motion.voice() end
end

local function detach()
	running = false
	current, modes = nil, {}
	Hud.set('voiceOn', false)
	applyRange()
	Hud.flush()
end

function Voice.start()
	-- without our voice document (no NativeUI), open-voice keeps its own line
	enabled = enabled and Hud.doc('voice') ~= nil
	if not enabled then return end
	if isRunning(cfg.resource) then attach() end
end

--- Status poll (every Config.updateInterval ms, only while the HUD is drawn).
function Voice.poll()
	if not running then return end
	if GetGameTimer() - lastStateRead >= (cfg.stateInterval or 1500) then readState() end
	if readTalk() then startFast() end
end

--- open-voice:modeChanged(mode, distance, label, color): the server confirmed a new range.
function Voice.modeChanged(mode, metres, label)
	if not running or type(mode) ~= 'string' then return end
	current = { mode = mode, label = label, distance = metres }
	local changed = applyRange()
	Hud.flush()
	if changed then Motion.voiceRange() end
end

--- open77:voice:talkingChanged(playerId, talking, level): the local player started or stopped talking.
function Voice.talkingChanged(playerId)
	if not running or not Hud.isShown() then return end
	if localId == nil and type(Open77.players) == 'table' and type(Open77.players.localId) == 'function' then
		localId = Open77.players.localId()
	end
	if localId ~= nil and tonumber(playerId) ~= tonumber(localId) then return end
	if readTalk() then startFast() end
	Hud.flush()
end

--- open77:voice:pushToTalkKeyChanged(key).
function Voice.pushToTalkKeyChanged(key)
	if not running then return end
	pttKey = keyCap(key, cfg.pttKey or 'V')
	readTalk()
	Hud.flush()
end

--- onClientResourceStart(name).
function Voice.resourceStarted(name)
	if not enabled then return end
	if name == cfg.resource then
		attach()
	elseif name == cfg.pttResource and running then
		readState()
		Hud.flush()
	end
end

--- onClientResourceStop(name).
function Voice.resourceStopped(name)
	if enabled and name == cfg.resource then detach() end
end

--- The waveform again after calm motion changed (Wave.setCalm); the caller flushes.
function Voice.redraw()
	if running then readTalk() else Hud.set('vWave', Wave.decorator('offline', 0)) end
end

--- This resource stops: give open-voice its own line back. Whether an export call still runs from this
--- resource's own stop handler is not verified on the client: a refusal is logged, not swallowed.
function Voice.release()
	if not running or not enabled or not isRunning(cfg.resource) then return end
	local ok, result = pcall(Open77.exports.callSync, cfg.resource, 'setHudVisible', true)
	if not ok then
		Open77.log.warn(('[opx_hud] cannot give %s its voice line back: %s'):format(cfg.resource, tostring(result)))
	end
end

return Voice
