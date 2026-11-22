--- Turns a config position ({ anchor = 'bottom-left', x, y }) into RCSS rules and the resting projection
--- of its document (the block's base tilt, hinged on its outer edge).
local Layout = {}

-- Reference screen height in dp (1 dp = 1 px at 1080p): projection origins are fractions of the screen.
local SCREEN_DP = 1080

--- A configured offset as whole dp: "44.5" or 44.5 gives 44, anything that is not a number gives 0.
--- The rules below are written with %d, which raises on a number with a fraction (the whole HUD would
--- stop at start), so the value is always an integer within a sane range.
---@param value any
---@return integer
local function whole(value)
	value = tonumber(value)
	if not value or value ~= value then return 0 end
	return math.floor(math.max(-100000, math.min(100000, value)))
end

---@param position table?
---@return 'top'|'bottom' vertical
---@return 'left'|'center'|'right' horizontal
---@return integer x
---@return integer y
function Layout.parse(position)
	position = type(position) == 'table' and position or {}
	local vertical, horizontal = tostring(position.anchor or ''):match('^(%a+)%-(%a+)$')
	if vertical ~= 'top' and vertical ~= 'bottom' then vertical = 'bottom' end
	if horizontal ~= 'left' and horizontal ~= 'center' and horizontal ~= 'right' then horizontal = 'left' end
	return vertical, horizontal, whole(position.x), whole(position.y)
end

--- Anchor elements are absolute flex columns; a centered one spans the width and centers its block.
---@param selector string
---@param position table?
---@return string
function Layout.rule(selector, position)
	local vertical, horizontal, x, y = Layout.parse(position)
	local rules = { ('%s: %ddp;'):format(vertical, y) }
	if horizontal == 'center' then
		rules[#rules + 1] = ('left: %ddp; right: %ddp; align-items: center;'):format(x, -x)
	else
		rules[#rules + 1] = ('%s: %ddp;'):format(horizontal, x)
		rules[#rules + 1] = ('align-items: %s;'):format(horizontal == 'left' and 'flex-start' or 'flex-end')
	end
	return ('%s { %s }'):format(selector, table.concat(rules, ' '))
end

--- How a block turns toward the screen centre (rotateY): +1 on the left (its right edge goes away),
--- -1 on the right, 0 for a centered block (it does not turn).
---@param position table?
---@return integer
function Layout.hingeSign(position)
	local _, horizontal = Layout.parse(position)
	if horizontal == 'left' then return 1 end
	if horizontal == 'right' then return -1 end
	return 0
end

--- How a block lies back (rotateX): +1 at the bottom (its top edge goes away), -1 at the top.
---@param position table?
---@return integer
function Layout.pitchSign(position)
	local vertical = Layout.parse(position)
	return vertical == 'top' and -1 or 1
end

--- The resting projection of a block's document. The pivot (and the eye, the vanishing point follows
--- it) sits on the block's outer edge: the screen side it is anchored to for a turned block, its edge
--- nearest to the screen border for a block lying back. `height` is an estimate of the block in dp
--- (only the vertical pivot of a turned block depends on it, i.e. the small float tilts).
---@param position table?
---@param kind 'yaw'|'pitch'|'flat'
---@param angle number degrees (Config.motion.tilt)
---@param height number dp
---@return table spec { rotateX, rotateY, origin = { x, y } }
function Layout.base(position, kind, angle, height)
	local vertical, horizontal, x, y = Layout.parse(position)
	-- a centered block's x shift, as a fraction of a 16:9 screen width
	local ox = horizontal == 'left' and 0 or (horizontal == 'right' and 1 or 0.5 + x / (SCREEN_DP * 16 / 9))
	local spec = { rotateX = 0, rotateY = 0 }
	local edge
	if kind == 'pitch' then
		spec.rotateX = Layout.pitchSign(position) * angle
		edge = y -- the edge nearest to the screen border
	else
		spec.rotateY = kind == 'yaw' and Layout.hingeSign(position) * angle or 0
		edge = y + height / 2 -- the block's middle
	end
	local fy = edge / SCREEN_DP
	if vertical == 'bottom' then fy = 1 - fy end
	spec.origin = { ox, math.floor(math.max(0, math.min(1, fy)) * 1000 + 0.5) / 1000 }
	return spec
end

return Layout
