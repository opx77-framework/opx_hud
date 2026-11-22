--- Each block document's projection: its resting tilt toward the centre (hinged on its outer edge) plus
--- the camera float of the official freeroam HUD (guide native-ui-3d, "A HUD that floats with the
--- camera"): a trail against the camera's yaw / pitch velocity, a small turn with it, a slow breath, a
--- shake on a health drop, a kick on each shot and, for the dashboard, a lean from the car's acceleration.
---
--- Cost: one thread, alive only while the HUD is drawn (it exits on hide); per frame one camera read,
--- one shot-counter read and, per document, ONE projection, sent only when its rounded values changed.
--- No float with Config.motion.reduced or Config.float.enabled = false, nor for a player whose
--- `nui.reducedmotion` is on (detected: the entrance spring then lands at once): blocks rest at their tilt.
local Hud = require('client.modules.hud')
local Layout = require('client.modules.layout')

local Float = {}

local M, F = Config.motion, Config.float or {}

local LEAN_MAX = 7          -- degrees of lean of the dashboard at most
local SETTLE_TIMEOUT = 1800 -- ms: a block whose entrance never reported settles anyway
local FAST_LAND = 150       -- ms: an entrance spring that lands faster than this means nui.reducedmotion

-- Estimated block heights in dp (only the vertical pivot of the small float tilts depends on them).
local HEIGHT = { bio = 150, info = 56, vehicle = 100, voice = 120, help = 40 }

-- The blocks: document name, Config.float preset, resting projection, entrance start offset.
local blocks = {}
do
	local p, tilt = Config.positions, M.tilt or {}
	local function block(name, preset, position, kind, angle)
		local base = Layout.base(position, kind, angle or 0, HEIGHT[name])
		local sign = Layout.hingeSign(position)
		local pitch = Layout.pitchSign(position)
		blocks[#blocks + 1] = {
			name = name,
			cfg = type(F[preset]) == 'table' and F[preset] or nil,
			base = base,
			-- the entrance starts flat, slid in from the block's own edge
			fromX = kind == 'yaw' and sign ~= 0 and -36 * sign or 0,
			fromY = (kind == 'pitch' and 28 * pitch) or (sign == 0 and 10 * pitch) or 0,
			gen = 0, settled = false, enteredAt = 0,
			sx = 0, sy = 0, rx = 0, ry = 0, blend = 0, sent = nil,
			phase = math.random() * 6.2832,
		}
	end
	block('bio', 'biomonitor', p.status, 'yaw', tilt.status)
	block('info', 'info', p.info, 'yaw', tilt.info)
	block('vehicle', 'vehicle', p.vehicle, 'pitch', tilt.vehicle)
	block('voice', 'voice', p.voice, 'yaw', tilt.voice)
	block('help', 'help', p.help, 'flat', 0)
end

local byName = {}
for _, b in ipairs(blocks) do byName[b.name] = b end

-- Inputs of the float, fed by the status poll and decaying on the float clock.
local motion = { shake = 0, kick = 0, lean = 0, speed = nil, speedAt = 0 }
local nuiReduced = false -- the player's nui.reducedmotion, as measured by the last entrance
local loopGen = 0
local reducedWatchers = {}

local function calm() return M.reduced == true end
local function floating() return F.enabled ~= false and not calm() and not nuiReduced end

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function round(v, scale) return math.floor(v * scale + 0.5) / scale end

---@param b table
---@param extra table?
---@return table
local function restSpec(b, extra)
	local spec = {
		rotateX = b.base.rotateX, rotateY = b.base.rotateY, rotateZ = 0,
		offset = { 0, 0, 0 }, perspective = M.perspective or 1100, origin = b.base.origin,
	}
	if extra then for k, v in pairs(extra) do spec[k] = v end end
	return spec
end

--- Camera yaw / pitch in degrees, nil while the camera is unavailable.
local function cameraAngles()
	if type(Open77.camera) ~= 'table' or type(Open77.camera.view) ~= 'function' then return nil end
	local ok, view = pcall(Open77.camera.view)
	local f = ok and type(view) == 'table' and view.forward
	if type(f) ~= 'table' or (math.abs(f.x or 0) + math.abs(f.y or 0)) < 1e-4 then return nil end
	return math.deg(math.atan(-f.x, f.y)), math.deg(math.asin(clamp(f.z or 0, -1, 1)))
end

local readShots = type(Open77.weapons) == 'table' and type(Open77.weapons.shotCounters) == 'function'
	and Open77.weapons.shotCounters or nil
local anyKick = false
for _, b in ipairs(blocks) do
	if b.cfg and (tonumber(b.cfg.kick) or 0) > 0 then anyKick = true end
end

--- One block's projection for this frame; sent only when its rounded values changed.
local function step(b, doc, dt, at, yawVel, pitchVel)
	local cfg = b.cfg
	local k = 1 - math.exp(-dt * (cfg.stiffness or 7))
	local trail, trailMax = cfg.trail or 0, cfg.trailMax or 0
	local turnMax = cfg.turnMax or 0
	-- it trails the turn (offset against it) and turns a little with it
	b.sx = b.sx + (clamp(yawVel * trail, -trailMax, trailMax) - b.sx) * k
	b.sy = b.sy + (clamp(-pitchVel * trail * 0.7, -trailMax * 0.7, trailMax * 0.7) - b.sy) * k
	b.ry = b.ry + (clamp(-yawVel * (cfg.turn or 0), -turnMax, turnMax) - b.ry) * k
	local lean = (cfg.lean or 0) > 0 and motion.lean * cfg.lean or 0
	b.rx = b.rx + (clamp(pitchVel * (cfg.pitch or 0), -turnMax * 0.7, turnMax * 0.7) + clamp(lean, -LEAN_MAX, LEAN_MAX) - b.rx) * k
	-- the float fades in after the entrance instead of jumping
	b.blend = math.min(1, b.blend + dt * 2)
	local w = b.blend

	local jx, jy = 0, 0
	local shake = motion.shake * (cfg.shake or 0)
	if shake > 0.05 then
		jx = (math.random() * 2 - 1) * shake
		jy = (math.random() * 2 - 1) * shake * 0.6
	end
	local kick = motion.kick * (cfg.kick or 0)
	local roll = 0
	if kick > 0.01 then
		jx = jx + (math.random() * 2 - 1) * kick * 2.2
		jy = jy + kick * 5 + (math.random() * 2 - 1) * kick * 1.2
		roll = (math.random() * 2 - 1) * kick * 0.35
	else
		kick = 0
	end
	local breath = type(cfg.breath) == 'table' and cfg.breath or { 0, 0 }
	local fy = math.sin(at / 1000 * (breath[1] or 0) * 6.2832 / 6 + b.phase) * (breath[2] or 0)

	local rotateX = round(b.base.rotateX + (b.rx + kick * 1.6) * w, 100)
	local rotateY = round(b.base.rotateY + b.ry * w, 100)
	local rotateZ = round((jx * 0.05 + roll) * w, 100)
	local ox = round((b.sx + jx) * w, 10)
	local oy = round((b.sy + jy + fy) * w, 10)
	local oz = round(-kick * 38 * w, 10)
	local key = ('%.2f %.2f %.2f %.1f %.1f %.1f'):format(rotateX, rotateY, rotateZ, ox, oy, oz)
	if key == b.sent then return end
	b.sent = key
	doc:projection(restSpec(b, { rotateX = rotateX, rotateY = rotateY, rotateZ = rotateZ, offset = { ox, oy, oz } }))
end

--- True while at least one floating block is on screen (a SetBlockVisible claim can hide them all).
local function anyOn()
	for _, b in ipairs(blocks) do
		if b.cfg and Hud.blockOn(b.name) then return true end
	end
	return false
end

local function startLoop()
	loopGen = loopGen + 1
	local gen = loopGen
	CreateThread(function()
		local at0 = GetGameTimer()
		local yaw0, pitch0 = nil, nil
		local shots, generation = nil, nil
		local wasFloating = true
		while gen == loopGen and Hud.isShown() do
			-- nui.reducedmotion measured on, or nothing to float: idle slowly until that changes
			local active = floating() and anyOn()
			Wait(active and 0 or 250)
			if gen ~= loopGen or not Hud.isShown() then break end
			local at = GetGameTimer()
			local dt = math.max(0.001, math.min(0.1, (at - at0) / 1000))
			at0 = at
			motion.shake = motion.shake * math.exp(-dt * 7)
			motion.kick = motion.kick * math.exp(-dt * 14)

			if floating() and not active then
				-- every block hidden: forget the camera so the next frame does not see a jump
				yaw0, shots = nil, nil
			elseif floating() then
				-- a shot is a new count on the shot counters (both hands); a new incarnation resets them
				if readShots and anyKick then
					local ok, c = pcall(readShots)
					if ok and type(c) == 'table' and tonumber(c.total) then
						local total = tonumber(c.total)
						if shots and generation == c.generation and total > shots then
							-- rapid fire stacks up to a ceiling, like recoil
							motion.kick = math.min(1.8, motion.kick + 0.75 * math.min(3, total - shots))
						end
						shots, generation = total, c.generation
					end
				end

				wasFloating = true
				local yaw, pitch = cameraAngles()
				local yawVel, pitchVel = 0, 0
				if yaw and yaw0 then
					yawVel = ((yaw - yaw0 + 540) % 360 - 180) / dt
					pitchVel = (pitch - pitch0) / dt
				end
				yaw0, pitch0 = yaw, pitch
				for _, b in ipairs(blocks) do
					local doc = Hud.doc(b.name)
					if doc and b.cfg and Hud.blockOn(b.name) then
						if not b.settled and at - b.enteredAt > SETTLE_TIMEOUT then b.settled = true end
						if b.settled then step(b, doc, dt, at, yawVel, pitchVel) end
					end
				end
			else
				yaw0, shots = nil, nil
				if wasFloating then
					-- calm from now on: every settled block back to its resting tilt, once
					wasFloating = false
					for _, b in ipairs(blocks) do
						local doc = Hud.doc(b.name)
						if doc and b.settled and b.sent then
							b.sent, b.blend = nil, 0
							doc:projection(restSpec(b))
						end
					end
				end
			end
		end
	end)
end

--- A block enters: from flat, slid in from its edge, it springs to its resting tilt. The float takes
--- over once it settled. With calm motion it is placed at once.
---@param name string
---@param delay number? seconds
function Float.enter(name, delay)
	local b = byName[name]
	local doc = b and Hud.doc(name)
	if not doc then return end
	b.gen = b.gen + 1
	local gen = b.gen
	b.settled, b.sent, b.blend = false, nil, 0
	b.sx, b.sy, b.rx, b.ry = 0, 0, 0, 0
	if calm() then
		doc:projection(restSpec(b, { reset = true }))
		b.settled = true
		return
	end
	doc:projection(restSpec(b, { reset = true, rotateX = 0, rotateY = 0, offset = { b.fromX, b.fromY, 0 } }))
	local at = GetGameTimer()
	b.enteredAt = at
	delay = delay or 0
	doc:projection(restSpec(b, { spring = { duration = 0.6, bounce = 0.15 }, delay = delay }), function()
		if b.gen ~= gen then return end
		b.settled = true
		-- the spring takes ~0.6 s; landing at once means the player's nui.reducedmotion is on
		local reduced = GetGameTimer() - at < delay * 1000 + FAST_LAND
		if reduced == nuiReduced then return end
		nuiReduced = reduced
		for i = 1, #reducedWatchers do reducedWatchers[i](reduced) end
	end)
end

--- `fn(reduced)` runs when the measured nui.reducedmotion flips (client/main.lua: heartbeat trace, voice wave).
---@param fn fun(reduced: boolean)
function Float.onReducedChanged(fn)
	reducedWatchers[#reducedWatchers + 1] = fn
end

--- Puts a block at its resting tilt at once (no entrance), e.g. a help line typed in place.
---@param name string
function Float.place(name)
	local b = byName[name]
	local doc = b and Hud.doc(name)
	if not doc then return end
	b.gen = b.gen + 1
	b.sent, b.blend = nil, 0
	b.sx, b.sy, b.rx, b.ry = 0, 0, 0, 0
	doc:projection(restSpec(b, { reset = true }))
	b.settled, b.enteredAt = true, GetGameTimer()
end

--- Health dropped by `drop` percent: the blocks with a `shake` shake, then settle.
---@param drop number
function Float.hit(drop)
	if not Hud.isShown() or calm() then return end
	motion.shake = math.min(16, motion.shake + 4 + (tonumber(drop) or 0) * 0.4)
end

--- The car's speed (km/h) at each vehicle read, nil on foot: its acceleration leans the dashboard,
--- back when it pulls, forward when it brakes.
---@param kph number?
function Float.speed(kph)
	local now = GetGameTimer()
	if kph and motion.speed and now > motion.speedAt then
		local accel = (kph - motion.speed) / ((now - motion.speedAt) / 1000)
		motion.lean = clamp(accel, -LEAN_MAX * 20, LEAN_MAX * 20)
	elseif not kph then
		motion.lean = 0
	end
	motion.speed, motion.speedAt = kph, now
end

--- Hud.onShownChanged watcher: the blocks enter on show and the loop starts; it stops on hide.
---@param now boolean
function Float.shown(now)
	if not now then
		loopGen = loopGen + 1
		motion.shake, motion.kick = 0, 0
		return
	end
	local delays = { bio = 0, info = 0.06, vehicle = 0.12, voice = 0.06 }
	for _, b in ipairs(blocks) do
		if b.name == 'help' then Float.place('help') else Float.enter(b.name, delays[b.name]) end
	end
	if F.enabled ~= false and not calm() then startLoop() end
end

return Float
