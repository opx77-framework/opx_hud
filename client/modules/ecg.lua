--- The biomonitor's heartbeat trace: a custom fx() effect drawn on the GPU. The trace scrolls on the
--- render thread; Lua only rebuilds the decorator string when the health band changes (model field `ecg`).
local Ecg = {}

local NAME = 'opx_hud_ecg'

-- Colours of the trace (same values as the THEME block of ui/hud.rcss: holo / alert).
local COLOUR = '#4fe3ff'
local COLOUR_LOW = '#ff3b47'

-- Line half-width, in percent of the trace box height.
local WIDTH = 2.6

-- fx(opx_hud_ecg a b c d colour)
--   a  beats per second (scroll pace; 3 beats fit across the box)
--   b  spike amplitude, 0..1 of the box height (0 = flat line)
--   c  line half-width, percent of the box height
--   d  irregularity 0..1: beat-to-beat amplitude, missing beats, timing and baseline drift
local SOURCE = [==[
float ecgBump(float p, float c, float w)
{
    float d = (p - c) / w;
    return exp(-d * d);
}

float ecgHash(float n)
{
    return frac(sin(n * 127.1) * 43758.5453);
}

// One heartbeat over p = 0..1: P wave, QRS complex, T wave.
float ecgBeat(float p)
{
    return 0.10 * ecgBump(p, 0.20, 0.045)
         - 0.14 * ecgBump(p, 0.375, 0.016)
         + 1.00 * ecgBump(p, 0.41, 0.020)
         - 0.30 * ecgBump(p, 0.445, 0.018)
         + 0.24 * ecgBump(p, 0.68, 0.065);
}

// Height of the trace (pixels from the top of the box) at pixel column x.
float ecgTrace(float x, float2 size, float t, float4 prm)
{
    float u = x / size.x * 3.0 + t * prm.x;
    float k = floor(u);
    float jitter = saturate(prm.w);
    float p = frac(u) + (ecgHash(k + 1.0) - 0.5) * 0.22 * jitter;
    float a = saturate(prm.y) * lerp(1.0, 0.25 + 1.1 * ecgHash(k + 7.0), jitter);
    a *= lerp(1.0, step(0.3, ecgHash(k + 3.0)), jitter);
    float drift = jitter * 0.06 * sin(u * 5.3 + t * 2.1);
    return size.y * (0.62 - 0.5 * (ecgBeat(p) * a + drift));
}

float4 Effect(EffectInput e)
{
    float2 ecgSize = max(e.size, float2(1.0, 1.0));
    float ecgHalf = max(e.params.z * 0.01 * ecgSize.y, 0.6);

    // distance to the polyline sampled every pixel around this column (keeps the QRS spike solid)
    float ecgDist = 1000000.0;
    float ecgPrevY = ecgTrace(e.px.x - 3.0, ecgSize, e.time, e.params);
    [unroll] for (int i = -2; i <= 3; i++)
    {
        float x1 = e.px.x + i;
        float y1 = ecgTrace(x1, ecgSize, e.time, e.params);
        float2 a = float2(x1 - 1.0, ecgPrevY);
        float2 ba = float2(x1, y1) - a;
        float2 pa = e.px - a;
        float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.0001));
        ecgDist = min(ecgDist, length(pa - ba * h));
        ecgPrevY = y1;
    }

    float ecgCore = 1.0 - smoothstep(ecgHalf - 0.5, ecgHalf + 0.75, ecgDist);
    float ecgGlow = exp(-ecgDist / (ecgHalf * 4.0 + 1.5)) * 0.35;
    float ecgHead = 0.45 + 0.55 * smoothstep(0.2, 0.92, e.uv.x);
    float ecgFade = smoothstep(0.0, 0.18, e.uv.x) * (1.0 - smoothstep(0.96, 1.0, e.uv.x));
    float ecgBase = (1.0 - smoothstep(0.0, 1.0, abs(e.px.y - ecgSize.y * 0.62))) * 0.10;
    return e.color * (saturate((ecgCore + ecgGlow) * ecgHead + ecgBase) * ecgFade);
}
]==]

local available = false

-- Calm motion: the trace stands still. Config.motion.reduced, or the player's own nui.reducedmotion as
-- the float measures it (client/main.lua calls Ecg.setCalm when the measure changes).
local calm = Config.motion.reduced == true

--- Registers the effect once, before the document is created. Without it the trace falls back to
--- a still flat line (Ecg.decorator).
---@return boolean
function Ecg.register()
	if type(Open77.ui.registerEffect) ~= 'function' then
		Open77.log.warn('[opx_hud] Open77.ui.registerEffect is missing: flat line instead of the heartbeat trace')
		return false
	end
	local ok, reason = Open77.ui.registerEffect(NAME, SOURCE)
	-- The one documented refusal is a source without an Effect function. What a second registration of
	-- the same name answers (this resource restarted, the game did not) is not documented: the effect of
	-- the first one is still there, so any other answer keeps the trace and is only written to the log.
	available = ok == true or tostring(reason) ~= 'effect_needs_Effect_function'
	if ok ~= true then
		Open77.log.warn(('[opx_hud] heartbeat effect: registerEffect answered %s%s'):format(tostring(reason),
			available and ' (kept: it stays registered across a restart)' or ' (flat line instead)'))
	end
	return available
end

--- Calm motion on or off; the caller sets the `ecg` model field again (Ecg.decorator).
---@param flag boolean
function Ecg.setCalm(flag)
	calm = flag == true
end

--- 0.85 -> "0.85", independent of the C locale.
---@param value number
---@return string
local function num(value)
	local hundredths = math.floor(math.max(value, 0) * 100 + 0.5)
	return ('%d.%02d'):format(hundredths // 100, hundredths % 100)
end

--- Rate, amplitude and irregularity for a health percent. Health is read in bands of 10 above lowAt
--- so the trace changes pace a few times, not at every regeneration tick.
---@param health integer 0..100
---@return number rate, number amplitude, number jitter
local function params(health)
	local status, ecg = Config.status, Config.ecg
	if health <= 0 then return 0, 0, 0 end
	if health <= status.critAt then return ecg.rateCrit, ecg.ampCrit, 1 end
	if health <= status.lowAt then return ecg.rateLow, ecg.amplitude, 0.2 end
	local band = math.floor(health / 10) * 10
	local span = math.max(100 - status.lowAt, 1)
	local t = math.max(0, math.min(1, (band - status.lowAt) / span))
	return ecg.rateLow + (ecg.rateFull - ecg.rateLow) * t, ecg.amplitude, 0
end

--- The `decorator` value of the trace for a health percent.
---@param health integer 0..100
---@return string
function Ecg.decorator(health)
	local rate, amplitude, jitter = params(health)
	local colour = health <= Config.status.lowAt and COLOUR_LOW or COLOUR
	if not available then
		-- a still flat line on the trace's baseline, in the colour of the health band
		return ('linear-gradient(180deg, %s00 0%%, %s00 61%%, %s 61%%, %s 63%%, %s00 63%%, %s00 100%%)')
			:format(colour, colour, colour, colour, colour, colour)
	end
	-- calm: pace 0 freezes the trace where it is (its shape and colour still follow the health band);
	-- irregularity 0 because its baseline drift runs on the clock, not on the pace
	if calm then rate, jitter = 0, 0 end
	return ('fx(%s %s %s %s %s %s)'):format(NAME, num(rate), num(amplitude), num(WIDTH), num(jitter), colour)
end

return Ecg
