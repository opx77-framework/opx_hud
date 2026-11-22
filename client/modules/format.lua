local Format = {}

---@param value number
---@param min number
---@param max number
---@return number
function Format.clamp(value, min, max)
	if value < min then return min end
	if value > max then return max end
	return value
end

--- 0..1 fraction to a rounded 0..100 percent. Non-numbers give nil.
---@param fraction any
---@return integer?
function Format.percent(fraction)
	fraction = tonumber(fraction)
	if not fraction or fraction ~= fraction then return nil end
	return math.floor(Format.clamp(fraction, 0, 1) * 100 + 0.5)
end

---@param digits string
---@param separator string
---@return string
local function group(digits, separator)
	local head = #digits % 3
	local parts = {}
	if head > 0 then parts[1] = digits:sub(1, head) end
	for i = head + 1, #digits, 3 do
		parts[#parts + 1] = digits:sub(i, i + 2)
	end
	return table.concat(parts, separator)
end

--- "12 500" (or "-12 500") with the configured thousands separator, no symbol.
---@param amount any
---@return string
function Format.amount(amount)
	amount = tonumber(amount) or 0
	local text = group(tostring(math.floor(math.abs(amount) + 0.5)), Config.money.separator or ' ')
	if amount < 0 then text = '-' .. text end
	return text
end

--- "€$ 12 500" with the configured symbol, side and separator.
---@param amount any
---@return string
function Format.money(amount)
	local settings = Config.money
	local text = Format.amount(amount)
	if settings.symbolAfter then return text .. ' ' .. settings.symbol end
	return settings.symbol .. ' ' .. text
end

--- Characters the client fonts lack, swapped for ones they draw (text of other resources and of players:
--- a help line pasted from a word processor, a job label, an amount formatted by opx_core). The no-break
--- spaces become plain spaces: nothing wraps in the HUD, so they draw the same without needing the glyph.
---@param value string
---@return string
local function swapGlyphs(value)
	return (value
		:gsub('\226\128\166', '...')        -- U+2026 horizontal ellipsis
		:gsub('\226\128[\152\153]', "'")    -- U+2018 / U+2019 curly apostrophes
		:gsub('\226\128\162', '\194\183')   -- U+2022 bullet -> middle dot
		:gsub('\226\128[\147\148]', '-')    -- U+2013 / U+2014 dashes
		:gsub('\226\128[\175\137]', ' ')    -- U+202F narrow no-break space, U+2009 thin space
		:gsub('\194\160', ' '))             -- U+00A0 no-break space
end

--- Trims, drops control characters, swaps the glyphs the fonts lack and caps the length (bytes) of caller text.
---@param value any
---@param maxLength integer
---@return string
function Format.clean(value, maxLength)
	if type(value) == 'number' then value = tostring(value) end
	if type(value) ~= 'string' then return '' end
	-- bound the work below before any pattern runs over it (a trim is quadratic on a long run of spaces)
	local bound = maxLength * 4 + 64
	if #value > bound then value = value:sub(1, bound):gsub('[\192-\255][\128-\191]*$', '') end
	value = swapGlyphs(value:gsub('%c', ' ')):gsub('^%s+', ''):gsub('%s+$', '')
	if #value > maxLength then
		-- drop the last multi-byte character so a cut never leaves half a UTF-8 sequence
		value = value:sub(1, maxLength):gsub('[\192-\255][\128-\191]*$', '')
	end
	return value
end

--- Upper case, accents included (Latin-1 range: é -> É). RCSS text-transform and string.upper
--- only handle ASCII, so labels built from data are upper-cased here.
---@param value string
---@return string
function Format.upper(value)
	value = value:upper()
	return (value:gsub('\195([\160-\190])', function(byte)
		if byte == '\183' then return nil end -- ÷ has no upper case
		return '\195' .. string.char(byte:byte() - 32)
	end))
end

return Format
