--- One help line ("[E] Open the door") drawn by the HUD document. The last caller owns it, with the
--- generation of its VM: the line goes when that VM is gone (client/modules/owners.lua).
local Hud = require('client.modules.hud')
local Format = require('client.modules.format')
local Motion = require('client.modules.motion')

local Help = {}

local owner = nil      -- resource that showed the line; nil for this resource
local ownerGeneration = 0

---@param text any
---@param key any
---@param caller string? resource that asked (GetInvokingResource), nil for this resource
---@param generation integer? generation of the caller's VM
---@return boolean
function Help.show(text, key, caller, generation)
	text = Format.clean(text, 160)
	if text == '' then return false end
	owner, ownerGeneration = caller, generation or 0
	local fresh = not Hud.get('helpOn') or Hud.get('helpText') ~= text
	Hud.set('helpText', text)
	Hud.set('helpKey', Format.upper(Format.clean(key, 16)))
	Hud.set('helpOn', true)
	Hud.flush()
	-- a new line comes in; the same line shown again stays as it is
	if fresh then Motion.typeHelp(text) end
	return true
end

--- Hides the help line. Another resource's call only hides the line it showed itself.
---@param caller string?
---@return boolean
function Help.hide(caller)
	if caller and owner and caller ~= owner then return false end
	owner, ownerGeneration = nil, 0
	Hud.set('helpOn', false)
	Hud.flush()
	return true
end

--- Drops the line when its owner is gone (it stopped, or was reloaded, without hiding it).
---@param gone fun(resource: string, generation: integer): boolean
function Help.sweep(gone)
	if owner and gone(owner, ownerGeneration) then Help.hide() end
end

return Help
