local Locale = assert(require('client.modules.locale'))
local localeKnown = Locale.init()

local Hud = assert(require('client.modules.hud'))
local Status = assert(require('client.modules.status'))
local Help = assert(require('client.modules.help'))
local Motion = assert(require('client.modules.motion'))
local Voice = assert(require('client.modules.voice'))
local Blocks = assert(require('client.modules.blocks'))
local Custom = assert(require('client.modules.custom'))
local Owners = assert(require('client.modules.owners'))
local Float = assert(require('client.modules.float'))
local Ecg = assert(require('client.modules.ecg'))
local Wave = assert(require('client.modules.wave'))

local RESOURCE = GetCurrentResourceName()

-- Toasts belong to the notify provider; opx_core routes them (Config.providers.notify).
local function notify(message, kind, duration)
	local pending = Open77.exports.call('opx_core', 'Notify', message, kind, duration)
	return pending ~= nil
end

local created = Hud.create()
Hud.onShownChanged(Motion.shown)
Hud.onBlockShown(Motion.blockShown)

-- The player's nui.reducedmotion, as the float measures it: the heartbeat trace and the voice wave go calm.
Float.onReducedChanged(function(reduced)
	local calm = reduced or Config.motion.reduced == true
	Ecg.setCalm(calm)
	Wave.setCalm(calm)
	Hud.set('ecg', Ecg.decorator(Hud.get('health')))
	Voice.redraw()
	Hud.flush()
end)

-- Config.locale 'auto': the game reports its language a moment after the client starts; labels follow then.
if not localeKnown then
	CreateThread(function()
		for _ = 1, 30 do
			Wait(2000)
			if Locale.ready() then
				Locale.init()
				Hud.relabel()
				return
			end
		end
	end)
end

-- Vanilla HUD claims; released automatically when the resource stops.
local function hideVanilla()
	for component, hidden in pairs(Config.vanilla) do
		if hidden then
			local ok, reason = Open77.hud.setVisible(component, false)
			if not ok then Open77.log.warn(('[opx_hud] cannot hide vanilla %s: %s'):format(component, tostring(reason))) end
		end
	end
end

-- Only once the HUD exists: without its documents the vanilla displays stay (README, Install).
if created then
	hideVanilla()
	-- worldReady fires again after world reloads (and not after a hot reload, hence the call above).
	AddEventHandler('open77:worldReady', hideVanilla)
end

-- opx_core player data -------------------------------------------------------

RegisterNetEvent('opx:playerLoaded', function(playerData)
	Status.load(playerData)
end)

RegisterNetEvent('opx:playerUnloaded', function()
	Help.hide()
	Status.unload()
end)

RegisterNetEvent('opx:setPlayerData', function(key, value)
	Status.update(key, value)
end)

-- Menus: hide on the edge, the poll loop catches anything the event misses.
AddEventHandler('open77:menuStateChanged', function()
	if not Config.hideInMenus then return end
	Hud.setState('menu', Status.menuOpen())
end)

-- Drops what owners that are gone left in the HUD; one failing module does not skip the others.
---@param gone fun(resource: string, generation: integer): boolean
local function sweep(gone)
	for _, module in ipairs({ Help, Blocks, Custom }) do
		local ok, err = pcall(module.sweep, gone)
		if not ok then Open77.log.warn('[opx_hud] sweep failed: ' .. tostring(err)) end
	end
end

--- The calling resource and its generation; what an older VM of that resource left goes first.
---@return string name
---@return integer generation
local function caller()
	local name, generation = Owners.caller()
	if Owners.renewed(name, generation) then
		sweep(function(r, g) return r == name and g ~= generation end)
	end
	return name, generation
end

-- Other resources: help lines of a stopped resource, the voice resource, the creator provider.
AddEventHandler('onClientResourceStart', function(name)
	if name == RESOURCE then return end
	Status.resourceChanged()
	Voice.resourceStarted(name)
end)

AddEventHandler('onClientResourceStop', function(name)
	if name == RESOURCE then
		-- give open-voice its own line back
		Voice.release()
		return
	end
	-- generation-based (client/modules/owners.lua): a hot-reloaded resource keeps what its new VM set
	local gone = function(r, g) return Owners.gone(r, g, name) end
	sweep(gone)
	Status.resourceChanged()
	Voice.resourceStopped(name)
end)

-- An owner that vanished without a stop notice: its claims, gauges and help line go within a second.
CreateThread(function()
	while true do
		Wait(1000)
		sweep(Owners.gone)
	end
end)

-- Voice: range confirmed by the server (open-voice), local talking edges and the push-to-talk key.
AddEventHandler('open-voice:modeChanged', function(mode, distance, label)
	Voice.modeChanged(mode, distance, label)
end)

AddEventHandler('open77:voice:talkingChanged', function(playerId)
	Voice.talkingChanged(playerId)
end)

AddEventHandler('open77:voice:pushToTalkKeyChanged', function(key)
	Voice.pushToTalkKeyChanged(key)
end)

-- Exports (contract: docs/ARCHITECTURE.md › opx_hud) ---------------------------
-- hud provider contract: SetVisible, IsVisible; optional ShowHelp, HideHelp. The others are opx_hud extras
-- (a replacement provider may lack them: call them under pcall). Full signatures in types.lua.

exports('ShowHelp', function(text, key)
	local name, generation = caller()
	return Help.show(text, key, name, generation)
end)

exports('HideHelp', function()
	return Help.hide((caller()))
end)

-- One shared flag, the last call wins (README, types.lua); not a per-resource claim.
exports('SetVisible', function(visible)
	Hud.setState('wanted', visible ~= false)
	return true
end)

exports('IsVisible', function()
	return Hud.getState('wanted')
end)

-- True while the HUD is on screen right now (character loaded, not hidden by SetVisible, /hud or a menu).
exports('IsShown', function()
	return Hud.isShown()
end)

-- Hides one block for the caller (minigame, cutscene); the block comes back once no resource hides it.
exports('SetBlockVisible', function(block, visible)
	local name, generation = caller()
	return Blocks.set(name, block, visible, generation)
end)

exports('IsBlockVisible', function(block)
	return Blocks.isVisible(block)
end)

-- A custom gauge in the biomonitor (oxygen, stress...), owned by the caller.
exports('SetCustomStatus', function(id, data)
	local name, generation = caller()
	return Custom.set(name, id, data, generation)
end)

exports('RemoveCustomStatus', function(id)
	local name, generation = caller()
	return Custom.set(name, id, nil, generation)
end)

-- Commands ---------------------------------------------------------------------

if Config.toggleCommand then
	RegisterCommand(Config.toggleCommand, function()
		local show = not Hud.getState('user')
		Hud.setState('user', show)
		notify(show and Locale.t('toggle.shown') or Locale.t('toggle.hidden', Config.toggleCommand), 'info', 2500)
	end, false)
end

if Config.debug then
	-- /hudtest [hide|hit|status|block <name>]: shows (or hides) the help line; hit plays the damage
	-- shake; status adds / removes a sample custom gauge; block toggles one block (SetBlockVisible).
	-- Sample toasts: /notifytest in opx_notification.
	local sample = nil
	RegisterCommand('hudtest', function(_, args)
		local mode = args and args[1]
		if mode == 'hide' then
			Help.hide()
			notify(Locale.t('test.helpHidden'), 'info', 2000)
		elseif mode == 'hit' then
			Float.hit(10)
		elseif mode == 'status' then
			sample = not sample and 25 or nil
			Custom.set(RESOURCE, 'sample', sample and { label = Locale.t('test.status'), value = sample } or nil)
		elseif mode == 'block' then
			local block = args[2]
			local ok = Blocks.set(RESOURCE, block, Blocks.isVisible(block) == false)
			if not ok then notify(Locale.t('test.blocks'), 'warning', 3000) end
		else
			Help.show(Locale.t('test.help'), 'E')
		end
	end, false)
end

Status.start()
Voice.start()

-- A restart while a character is loaded: ask opx_core for the current data.
CreateThread(function()
	local ok, loaded = pcall(Open77.exports.callSync, 'opx_core', 'IsPlayerLoaded')
	if not ok or loaded ~= true or Hud.getState('loaded') then return end
	local okData, data = pcall(Open77.exports.callSync, 'opx_core', 'GetPlayerData')
	if okData and type(data) == 'table' then Status.load(data) end
end)

-- The menu event is an edge and is not raised at start.
if Config.hideInMenus then
	Hud.setState('menu', Status.menuOpen())
end
