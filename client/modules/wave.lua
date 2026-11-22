--- The voice block's waveform: a custom fx() effect drawn on the GPU, like the heartbeat trace. The wave
--- moves on the render thread; Lua only rebuilds the decorator string when the voice state or the
--- quantized talking level changes (model field `vWave`).
local Wave = {}

local NAME = 'opx_hud_voice'

-- Colours (same values as the THEME block of ui/hud.rcss: holo / alert / text-dim).
local COLOUR = '#4fe3ff'
local COLOUR_PEAK = '#ff3b47'
local COLOUR_MUTED = '#ff3b4799'
local COLOUR_DIM = '#86a9b566'

-- Line half-width, in percent of the box height.
local WIDTH = 3.2

-- Talking level steps: the decorator changes at most this many times across the 0..1 range.
local STEPS = 5

-- fx(opx_hud_voice a b c d colour)
--   a  voice amplitude 0..1 of the half box height (0 = no voice)
--   b  pace of the wave (1 = talking)
--   c  line half-width, percent of the box height
--   d  idle carrier 0..1: a faint shimmer on the flat line (0 = dead flat)
local SOURCE = [==[
// The voice signal at column xs (dp-scaled): three moving partials under a syllable envelope.
float voxSignal(float xs, float t, float pace)
{
    float s = sin(xs * 0.115 + t * 9.0 * pace) * 0.55
            + sin(xs * 0.271 - t * 14.0 * pace) * 0.30
            + sin(xs * 0.613 + t * 23.0 * pace) * 0.15;
    float syll = 0.55 + 0.45 * sin(t * 6.3 * pace + xs * 0.021) * sin(t * 2.7 * pace + 1.3);
    return s * syll;
}

// Height of the trace (pixels from the top of the box) at pixel column x.
float voxTrace(float x, float2 size, float t, float4 prm)
{
    float xs = x * 34.0 / size.y;
    float u = x / size.x;
    float env = pow(saturate(sin(u * 3.14159)), 1.4);
    float voice = voxSignal(xs, t, max(prm.y, 0.2)) * saturate(prm.x);
    float carrier = 0.05 * saturate(prm.w) * sin(xs * 0.35 + t * 4.0);
    return size.y * (0.5 - 0.46 * (voice + carrier) * env);
}

float4 Effect(EffectInput e)
{
    float2 voxSize = max(e.size, float2(1.0, 1.0));
    float voxHalf = max(e.params.z * 0.01 * voxSize.y, 0.6);

    float voxDist = 1000000.0;
    float voxPrevY = voxTrace(e.px.x - 3.0, voxSize, e.time, e.params);
    [unroll] for (int i = -2; i <= 3; i++)
    {
        float x1 = e.px.x + i;
        float y1 = voxTrace(x1, voxSize, e.time, e.params);
        float2 a = float2(x1 - 1.0, voxPrevY);
        float2 ba = float2(x1, y1) - a;
        float2 pa = e.px - a;
        float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.0001));
        voxDist = min(voxDist, length(pa - ba * h));
        voxPrevY = y1;
    }

    float voxCore = 1.0 - smoothstep(voxHalf - 0.5, voxHalf + 0.75, voxDist);
    float voxGlow = exp(-voxDist / (voxHalf * 4.0 + 1.5)) * 0.35;
    float voxFade = smoothstep(0.0, 0.12, e.uv.x) * (1.0 - smoothstep(0.88, 1.0, e.uv.x));
    float voxBase = (1.0 - smoothstep(0.0, 1.0, abs(e.px.y - voxSize.y * 0.5))) * 0.10;
    return e.color * (saturate(voxCore + voxGlow + voxBase) * voxFade);
}
]==]

local available = false

-- Calm motion: a flat line in the colour of the state. Config.motion.reduced, or the player's own
-- nui.reducedmotion as the float measures it (client/main.lua calls Wave.setCalm when the measure changes).
local calm = Config.motion.reduced == true

--- Registers the effect once, before the documents are created. Without it the wave falls back to a
--- still flat line (Wave.decorator).
---@return boolean
function Wave.register()
	if type(Open77.ui.registerEffect) ~= 'function' then return false end
	local ok, reason = Open77.ui.registerEffect(NAME, SOURCE)
	-- same rule as the heartbeat trace (client/modules/ecg.lua): only the documented refusal of the source
	-- switches to the fallback; any other answer (a second registration after a restart) keeps the effect
	available = ok == true or tostring(reason) ~= 'effect_needs_Effect_function'
	if ok ~= true then
		Open77.log.warn(('[opx_hud] voice wave effect: registerEffect answered %s%s'):format(tostring(reason),
			available and ' (kept: it stays registered across a restart)' or ' (flat line instead)'))
	end
	return available
end

--- Calm motion on or off; the caller sets the `vWave` model field again (Wave.decorator).
---@param flag boolean
function Wave.setCalm(flag)
	calm = flag == true
end

---@param value number
---@return string
local function num(value)
	local hundredths = math.floor(math.max(value, 0) * 100 + 0.5)
	return ('%d.%02d'):format(hundredths // 100, hundredths % 100)
end

--- A 0..1 level on STEPS steps (the decorator string only changes on a step).
---@param level number
---@return number
function Wave.quantize(level)
	level = math.max(0, math.min(1, tonumber(level) or 0))
	return math.floor(level * STEPS + 0.5) / STEPS
end

--- The `decorator` value of the wave for a voice state and a quantized level.
---@param state 'idle'|'talking'|'muted'|'offline'
---@param level number 0..1
---@param peak boolean?
---@return string
function Wave.decorator(state, level, peak)
	local amplitude, pace, carrier, colour = 0, 0.5, 0, COLOUR_DIM
	if state == 'talking' then
		amplitude, pace, carrier = 0.35 + 0.65 * level, 1, 0
		colour = peak and COLOUR_PEAK or COLOUR
	elseif state == 'idle' then
		-- a voice-activation signal below the transmit threshold still moves a little
		amplitude, pace, carrier, colour = level * 0.5, 0.6, 1, COLOUR
	elseif state == 'muted' then
		colour = COLOUR_MUTED
	end
	if not available then
		-- a still flat line across the middle, in the colour of the state (#RRGGBB of it, alpha 00, around)
		local clear = colour:sub(1, 7) .. '00'
		return ('linear-gradient(180deg, %s 0%%, %s 48%%, %s 48%%, %s 52%%, %s 52%%, %s 100%%)')
			:format(clear, clear, colour, colour, clear, clear)
	end
	-- calm: no amplitude and no carrier leave a flat, still line; the colour, the state label and the lit
	-- talk cap keep saying what the microphone does
	if calm then amplitude, carrier = 0, 0 end
	return ('fx(%s %s %s %s %s %s)'):format(NAME, num(amplitude), num(pace), num(WIDTH), num(carrier), colour)
end

return Wave
