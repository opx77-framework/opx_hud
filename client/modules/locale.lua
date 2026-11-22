--- Player-facing text from locales/<lang>.json, English as the fallback.
--- Config.locale 'auto' follows the game's language (Open77.session.locale) once the client reported it:
--- on a fresh join that is a few seconds after the first gameplay frame, long after this resource started.
local Locale = {}

local strings, fallback = {}, {}

---@param code string
---@return table?
local function load(code)
	if type(code) ~= 'string' or not code:match('^[%a_%-]+$') then return nil end
	local text = Open77.resource.readFile(('locales/%s.json'):format(code))
	if not text then return nil end
	local ok, data = pcall(Open77.json.decode, text)
	return ok and type(data) == 'table' and data or nil
end

---@return string code
---@return boolean known false while 'auto' waits for the game language
local function language()
	local wanted = Config.locale or 'en'
	if wanted ~= 'auto' then return tostring(wanted), true end
	if type(Open77.session) ~= 'table' or type(Open77.session.locale) ~= 'function' then return 'en', true end
	local ok, info = pcall(Open77.session.locale)
	local code = ok and type(info) == 'table' and info.code or nil
	if type(code) ~= 'string' or code == '' then return 'en', false end
	return code:sub(1, 2):lower(), true
end

--- Loads the strings. Returns false while the game language is not known yet: English is loaded
--- meanwhile; ask Locale.ready() until it answers true, then call this again and redraw the labels.
---@return boolean known
function Locale.init()
	local code, known = language()
	fallback = load('en') or {}
	strings = (code ~= 'en' and load(code)) or fallback
	return known
end

--- True once the language can be told (a fixed Config.locale, or the game has reported its own). One
--- native read, no file: cheap enough to ask every few seconds for as long as the game stays silent.
---@return boolean
function Locale.ready()
	local _, known = language()
	return known
end

--- Translated string for `key`, formatted with the extra arguments. Unknown keys return the key.
---@param key string
---@return string
function Locale.t(key, ...)
	local text = strings[key] or fallback[key] or tostring(key)
	if select('#', ...) == 0 then return text end
	local ok, formatted = pcall(string.format, text, ...)
	return ok and formatted or text
end

return Locale
