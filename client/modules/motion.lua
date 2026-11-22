--- Element motion of the HUD, all on the render thread: Lua only queues an animation on an edge (the HUD
--- shows, a block appears, a value changes). The tilt and the camera float of each block are its
--- document's projection (client/modules/float.lua).
--- ui:animate / ui:keyframes follow each player's `nui.reducedmotion`; Config.motion.reduced forces calm.
local Hud = require('client.modules.hud')
local Float = require('client.modules.float')

local Motion = {}

local M = Config.motion

-- Money flick colours (same values as the THEME block of ui/hud.rcss: holo / alert / text).
local FLICK_UP, FLICK_DOWN, TEXT = '#4fe3ff', '#ff3b47', '#e9fbff'

-- Help line typing: the text is revealed at a constant pace up to this width.
local TYPE_WIDTH, TYPE_SECONDS = 900, 1.6

local function calm() return M.reduced == true end

--- The help line types itself in: the text is unveiled left to right at a constant pace, its right
--- edge lit like a caret, and the key cap pops.
function Motion.typeHelp(text)
	local ui = Hud.doc('help')
	if not ui or not Hud.isShown() or calm() then return end
	local width = math.min(TYPE_WIDTH, #(text or '') * 8.5 + 24)
	local typed = TYPE_SECONDS * width / TYPE_WIDTH
	ui:animate('#help-type', { from = { ['max-width'] = '0dp' }, to = { ['max-width'] = TYPE_WIDTH .. 'dp' },
		duration = TYPE_SECONDS, easing = 'linear' })
	ui:keyframes('#help-type', { channel = 'border-color', duration = typed + 0.3,
		stops = { { offset = 0, value = FLICK_UP }, { offset = 0.85, value = FLICK_UP }, { offset = 1, value = '#4fe3ff00' } } })
	ui:animate('#help-key', { from = { scale = 0.6, opacity = 0 }, to = { scale = 1, opacity = 1 }, preset = 'bouncy' })
	ui:animate('#help', { from = { y = 10, opacity = 0 }, to = { y = 0, opacity = 1 }, preset = 'snappy' })
end

--- The vehicle block appeared while the HUD is drawn.
function Motion.vehicle()
	if Hud.isShown() then Float.enter('vehicle', 0) end
end

--- The voice block appeared while the HUD is drawn (the voice resource started).
function Motion.voice()
	if Hud.isShown() then Float.enter('voice', 0) end
end

--- A new voice range: the label and the distance drop in, the pips pop.
function Motion.voiceRange()
	local ui = Hud.doc('voice')
	if not ui or not Hud.isShown() or calm() then return end
	ui:animate('#vmode, #vdist', { from = { opacity = 0, y = -8 }, to = { opacity = 1, y = 0 },
		spring = { duration = 0.42, bounce = 0.3 }, stagger = 0.05 })
	ui:animate('#vpips', { from = { scale = 1.3 }, to = { scale = 1 }, spring = { duration = 0.4, bounce = 0.45 } })
end

--- A money value changed: it flashes cyan (up) or red (down) and flicks into place.
---@param selector string
---@param up boolean
function Motion.flick(selector, up)
	local ui = Hud.doc('info')
	if not ui or not Hud.isShown() then return end
	ui:keyframes(selector, { channel = 'color', duration = 0.9,
		stops = { { offset = 0, value = up and FLICK_UP or FLICK_DOWN }, { offset = 1, value = TEXT, easing = 'ease-out' } } })
	if not calm() then
		ui:animate(selector, { from = { y = up and -6 or 6 }, to = { y = 0 }, preset = 'snappy' })
	end
end

--- Hud.onShownChanged watcher: entrances on show (brackets draw, blocks spring to their tilt, then
--- float); the float loop stops on hide.
---@param now boolean
function Motion.shown(now)
	for _, entry in ipairs(Hud.DOCS) do
		local ui = Hud.doc(entry.name)
		if ui then
			if now then
				-- the bracket draw replays on every show
				ui:class('#root', 'in', not calm())
				ui:animate('#root', { from = { opacity = 0 }, to = { opacity = 1 }, preset = 'calm' })
			else
				ui:class('#root', 'in', false)
			end
		end
	end
	Float.shown(now)
	if now and Hud.get('helpOn') then Motion.typeHelp(Hud.get('helpText')) end
end

--- Hud.onBlockShown watcher: one block given back by SetBlockVisible while the HUD stays shown enters alone.
---@param name string document name
function Motion.blockShown(name)
	local ui = Hud.doc(name)
	if not ui then return end
	ui:class('#root', 'in', not calm())
	ui:animate('#root', { from = { opacity = 0 }, to = { opacity = 1 }, preset = 'calm' })
	if name == 'help' then
		Float.place('help')
		if Hud.get('helpOn') then Motion.typeHelp(Hud.get('helpText')) end
	else
		Float.enter(name, 0)
	end
end

return Motion
