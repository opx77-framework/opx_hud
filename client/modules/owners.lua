--- Who owns what other resources leave in the HUD: block claims, whole-HUD claims, custom gauges and the
--- help line. Each one is kept with the NAME of the resource that asked and the GENERATION of its VM
--- (GetInvokingResourceGeneration), and is never dropped on the name alone.
---
--- Why: when a resource is hot-reloaded, its new VM starts (and can register again) BEFORE the other
--- resources hear that the old one stopped. Dropping "everything of that name" in the stop handler would
--- erase what the new VM just registered. Comparing generations keeps the fresh entries and drops the
--- stale ones, whichever notice arrives first:
---   - the owner calls again from a new generation: what its previous VM left goes first (Owners.renewed);
---   - its stop notice arrives: what does not belong to the generation now running goes (Owners.gone);
---   - no notice at all (it vanished): the slow sweep of client/main.lua asks Owners.gone as well.
local Owners = {}

local SELF = GetCurrentResourceName()

local seen = {} -- resource -> generation of its last call

---@param value any
---@return integer generation 0 when unknown
local function whole(value)
	value = tonumber(value)
	return value and math.tointeger(value) or 0
end

--- The resource whose export call is being served and the generation of its VM. Outside an export call
--- (a command or a thread of this resource) the owner is this resource.
---@return string name
---@return integer generation 0 when the client does not report one
function Owners.caller()
	local name = GetInvokingResource()
	if type(name) ~= 'string' or name == '' then return SELF, 0 end
	if type(GetInvokingResourceGeneration) ~= 'function' then return name, 0 end
	return name, whole(GetInvokingResourceGeneration())
end

--- Remembers the generation `name` calls from. True when it differs from its previous call: the resource
--- was reloaded, and what its old VM left here must go before the new call is served.
---@param name string
---@param generation integer
---@return boolean
function Owners.renewed(name, generation)
	local before = seen[name]
	seen[name] = generation
	return before ~= nil and before ~= generation
end

--- True when what `name` left here from `generation` has no owner any more: the resource is not running,
--- or it runs another generation (it was reloaded and did not ask again).
---@param name string
---@param generation integer 0 = unknown: then only the stop notice of that resource drops it
---@param stopped string? the resource whose stop notice is being handled
---@return boolean
function Owners.gone(name, generation, stopped)
	if name == SELF then return false end
	local state = GetResourceState(name)
	-- 'starting': a claim made while the owner's script was still loading counts
	if state ~= 'running' and state ~= 'starting' then
		seen[name] = nil
		return true
	end
	if generation == 0 then return name == stopped end
	local ok, current = pcall(Open77.resource.generation, name)
	-- the generation cannot be read on this client: fall back to the stop notice, as for an unknown one
	if not ok then return name == stopped end
	return whole(current) ~= generation
end

return Owners
