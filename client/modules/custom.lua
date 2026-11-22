--- Custom status gauges another resource adds to the biomonitor, next to hunger and thirst (oxygen, stress,
--- battery...). Each gauge belongs to the resource that set it (ids are per resource) and goes away when
--- that resource's VM is gone (client/modules/owners.lua). At most Config.status.customMax gauges at once
--- for ALL resources together, in the order they were added.
local Hud = require('client.modules.hud')
local Format = require('client.modules.format')

local Custom = {}

local gauges = {} -- key (resource .. '/' .. id) -> { key, owner, generation, seq, label, value, lowAt, highAt }
local count, seq = 0, 0

local function max()
	return math.max(0, math.floor(tonumber(Config.status.customMax) or 2))
end

--- Sends the list when what it draws changed. The fills glide on their own (ui/hud.rcss, .gfill transition).
local function push()
	local list = {}
	for _, g in pairs(gauges) do list[#list + 1] = g end
	table.sort(list, function(a, b) return a.seq < b.seq end)
	local rows, signature = {}, {}
	for i, g in ipairs(list) do
		local low = (type(g.lowAt) == 'number' and g.value <= g.lowAt) or (type(g.highAt) == 'number' and g.value >= g.highAt)
		rows[i] = { label = g.label, value = g.value, low = low }
		signature[i] = ('%s=%d%s'):format(g.label, g.value, low and '!' or '')
	end
	local key = table.concat(signature, '|')
	if Hud.get('customKey') ~= key then
		Hud.set('customKey', key)
		Hud.set('custom', rows)
	end
	Hud.set('customOn', #rows > 0)
	Hud.flush()
end

---@param value any
---@return integer?
local function percent(value)
	value = tonumber(value)
	if not value or value ~= value then return nil end
	return math.floor(Format.clamp(value, 0, 100) + 0.5)
end

---@param value any
---@param default number|false|nil
---@return number|false|nil
local function threshold(value, default)
	if value == false then return false end
	if value == nil then return default end
	return tonumber(value) or default
end

--- Adds, updates or removes one gauge.
---@param caller string resource that asked
---@param id any ^[%w_.:-]{1,32}$
---@param data any nil/false removes it; a number updates the value of an existing gauge; a table
---  { label = string, value = 0..100, lowAt? = number|false, highAt? = number } adds or replaces it
---@param generation integer? generation of the caller's VM (0 / nil = unknown)
---@return boolean ok
---@return string? reason invalid_id | invalid_value | invalid_label | unknown_id | too_many
function Custom.set(caller, id, data, generation)
	if type(id) ~= 'string' or not id:match('^[%w_%.:%-]+$') or #id > 32 then return false, 'invalid_id' end
	local key = caller .. '/' .. id
	local gauge = gauges[key]

	if data == nil or data == false then
		if gauge then
			gauges[key], count = nil, count - 1
			push()
		end
		return true
	end

	if type(data) ~= 'table' then
		if not gauge then return false, 'unknown_id' end
		local value = percent(data)
		if not value then return false, 'invalid_value' end
		gauge.value, gauge.generation = value, generation or 0
		push()
		return true
	end

	local value = percent(data.value)
	if not value then return false, 'invalid_value' end
	local label = data.label ~= nil and Format.upper(Format.clean(data.label, 16)) or (gauge and gauge.label or '')
	if label == '' then return false, 'invalid_label' end
	if not gauge then
		if count >= max() then return false, 'too_many' end
		seq = seq + 1
		gauge = { key = key, owner = caller, seq = seq }
		gauges[key], count = gauge, count + 1
	end
	-- the same resource sending the table again replaces its own gauge (and its generation)
	gauge.label, gauge.value, gauge.generation = label, value, generation or 0
	gauge.lowAt = threshold(data.lowAt, Config.status.lowAt)
	gauge.highAt = threshold(data.highAt, nil) or nil
	push()
	return true
end

--- Removes the gauges whose owner is gone. `gone(resource, generation)` decides (Owners.gone, or "an older
--- generation of this caller" when a reloaded resource calls again).
---@param gone fun(resource: string, generation: integer): boolean
function Custom.sweep(gone)
	local changed = false
	for key, g in pairs(gauges) do
		if gone(g.owner, g.generation) then
			gauges[key], count, changed = nil, count - 1, true
		end
	end
	if changed then push() end
end

return Custom
