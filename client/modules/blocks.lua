--- Block visibility claims of other resources (SetBlockVisible): a resource hides one block (e.g. the
--- vehicle dashboard during a minigame) while the rest of the HUD stays. A block is hidden while at least
--- one resource holds a hide claim on it. Independent of SetVisible (one shared flag, client/main.lua) and
--- of the player's own /hud. A claim is kept with the generation of the VM that made it and dropped when
--- that VM is gone (client/modules/owners.lua).
local Hud = require('client.modules.hud')

local Blocks = {}

local claims = {} -- block -> { [resource] = generation }

---@param block string
local function apply(block)
	Hud.setBlockHidden(block, next(claims[block] or {}) ~= nil)
end

---@param caller string resource that asked
---@param block any Config.positions key: 'status' | 'info' | 'vehicle' | 'voice' | 'help'
---@param visible any false hides, anything else gives the block back
---@param generation integer? generation of the caller's VM (0 / nil = unknown)
---@return boolean ok
---@return string? reason 'invalid_block'
function Blocks.set(caller, block, visible, generation)
	if not Hud.isBlock(block) then return false, 'invalid_block' end
	claims[block] = claims[block] or {}
	-- the same resource asking again replaces its own claim (and its generation)
	claims[block][caller] = visible == false and (generation or 0) or nil
	apply(block)
	return true
end

--- True unless a claim hides that block (nil for an unknown block name).
---@param block any
---@return boolean?
function Blocks.isVisible(block)
	if not Hud.isBlock(block) then return nil end
	return next(claims[block] or {}) == nil
end

--- Drops the claims whose owner is gone. `gone(resource, generation)` decides (Owners.gone, or "an older
--- generation of this caller" when a reloaded resource calls again).
---@param gone fun(resource: string, generation: integer): boolean
function Blocks.sweep(gone)
	for block, owners in pairs(claims) do
		local changed = false
		for owner, generation in pairs(owners) do
			if gone(owner, generation) then owners[owner], changed = nil, true end
		end
		if changed then apply(block) end
	end
end

return Blocks
