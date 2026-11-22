--- Feeds the HUD model: player data from opx_core events, live pools and vehicle from natives.
local Hud = require('client.modules.hud')
local Format = require('client.modules.format')
local Ecg = require('client.modules.ecg')
local Motion = require('client.modules.motion')
local Float = require('client.modules.float')
local Voice = require('client.modules.voice')

local Status = {}

local DRIVER_SEAT = 'seat_front_left'
local MPH = 0.621371

local playerData = {}
local inVehicle = false
local lastHealth = nil            -- previous health read while drawn (damage shake)
local lastCash, lastBank = nil, nil -- previous balances (money flick)

-- Natives this module reads; a client without them simply leaves that block empty.
local canReadStats = type(Open77.stats) == 'table' and type(Open77.stats.get) == 'function'
local canReadVehicles = type(Open77.vehicles) == 'table' and type(Open77.vehicles.getPlayerSeat) == 'function'

--- Percent of a platform pool: its own fraction, else current / maximum. No invented maximum.
---@param pool any
---@return integer?
local function poolPercent(pool)
	if type(pool) ~= 'table' then return nil end
	if pool.fraction then return Format.percent(pool.fraction) end
	local value, maximum = tonumber(pool.value or pool.current), tonumber(pool.maximum or pool.max)
	if not value or not maximum or maximum <= 0 then return nil end
	return Format.percent(value / maximum)
end

local function readStats()
	if not canReadStats or not Config.blocks.status then return end
	local stats = Open77.stats.get()
	if type(stats) ~= 'table' then return end

	local health = poolPercent(stats.health)
	if health then
		local drop = lastHealth and lastHealth - health or 0
		-- a health loss shakes the blocks
		if drop >= 1 then Float.hit(drop) end
		lastHealth = health
		Hud.set('health', health)
		Hud.set('ecg', Ecg.decorator(health))
	end

	local armor = Format.percent((tonumber(stats.armor) or 0) / Config.status.armorMax) or 0
	Hud.set('armor', armor)
	Hud.set('armorOn', armor > 0)

	local stamina = poolPercent(stats.stamina)
	if stamina then
		Hud.set('stamina', stamina)
		Hud.set('staminaOn', not Config.status.hideFullStamina or stamina < 100)
	end
end

local function readVehicle()
	if not canReadVehicles or not Config.blocks.vehicle then return end
	local seat = Open77.vehicles.getPlayerSeat()
	local car = nil
	if seat and (Config.vehicle.passenger or seat.seat == DRIVER_SEAT) then
		car = Open77.vehicles.get(seat.vehicleId)
	end

	local appeared = car ~= nil and not inVehicle
	inVehicle = car ~= nil
	Hud.set('vehicleOn', inVehicle)
	if not car then
		Float.speed(nil)
		return
	end

	local kph = tonumber(car.speedKph) or (tonumber(car.speed) or 0) * 3.6
	Float.speed(math.abs(kph))
	local speed = math.floor(math.abs(Config.vehicle.unit == 'mph' and kph * MPH or kph) + 0.5)
	Hud.set('speed', speed)
	Hud.set('speedPct', math.floor(Format.clamp(speed / math.max(Config.vehicle.maxSpeed or 220, 1), 0, 1) * 100 + 0.5))
	Hud.set('condition', Format.percent(car.health) or 100)
	Hud.set('engineOn', car.engineOn ~= false)
	return appeared
end

local function applyMoney()
	local accounts = type(playerData.accounts) == 'table' and playerData.accounts or {}
	local money = Config.money
	local cashOn = Config.blocks.money and money.cash ~= false
	local bankOn = Config.blocks.money and money.bank ~= false
	Hud.set('cashOn', cashOn)
	Hud.set('bankOn', bankOn)
	local cash = cashOn and (tonumber(accounts[money.cash]) or 0) or nil
	local bank = bankOn and (tonumber(accounts[money.bank]) or 0) or nil
	if cash then Hud.set('cash', Format.money(cash)) end
	if bank then Hud.set('bank', Format.amount(bank)) end
	return cash, bank
end

--- Money from an opx:setPlayerData update: flicks the balance that moved.
local function updateMoney()
	local cash, bank = applyMoney()
	Hud.flush()
	if cash and lastCash and cash ~= lastCash then Motion.flick('#cash', cash > lastCash) end
	if bank and lastBank and bank ~= lastBank then Motion.flick('#bank', bank > lastBank) end
	lastCash, lastBank = cash, bank
end

local function applyJob()
	local job = playerData.job
	local jobOn = Config.blocks.job and type(job) == 'table'
	Hud.set('jobOn', jobOn)
	if not jobOn then return end
	Hud.set('jobLabel', Format.upper(Format.clean(job.label or job.name, 48)))
	Hud.set('gradeLabel', Format.upper(Format.clean(job.gradeLabel or job.gradeName, 48)))
	Hud.set('onDuty', job.onDuty ~= false)
end

---@param key string|false
---@param metadata table
---@return boolean shown
---@return integer value
local function need(key, metadata)
	if not key then return false, 100 end
	local value = tonumber(metadata[key])
	if not value then return false, 100 end
	return true, Format.percent(value / Config.needs.max) or 0
end

local function applyNeeds()
	local metadata = type(playerData.metadata) == 'table' and playerData.metadata or {}
	local enabled = Config.blocks.needs
	local hungerOn, hunger = need(enabled and Config.needs.hunger, metadata)
	local thirstOn, thirst = need(enabled and Config.needs.thirst, metadata)
	Hud.set('hungerOn', hungerOn)
	Hud.set('hunger', hunger)
	Hud.set('thirstOn', thirstOn)
	Hud.set('thirst', thirst)
	Hud.set('needsOn', hungerOn or thirstOn)
end

local function applyAll()
	Hud.set('statusOn', Config.blocks.status == true)
	lastCash, lastBank = applyMoney()
	applyJob()
	applyNeeds()
	Hud.set('infoOn', Hud.getState('loaded') and (Config.blocks.money or Config.blocks.job) or false)
	Hud.flush()
end

--- Full PlayerData from opx:playerLoaded (or opx_core GetPlayerData after a restart).
---@param data table
function Status.load(data)
	playerData = type(data) == 'table' and data or {}
	Hud.setState('loaded', true)
	applyAll()
end

function Status.unload()
	playerData = {}
	Hud.setState('loaded', false)
	inVehicle = false
	Hud.set('vehicleOn', false)
	applyAll()
end

--- One PlayerData key changed (opx:setPlayerData).
---@param key string
---@param value any
function Status.update(key, value)
	if type(key) ~= 'string' then return end
	playerData[key] = value
	if key == 'accounts' then return updateMoney()
	elseif key == 'job' then applyJob()
	elseif key == 'metadata' then applyNeeds()
	else return end
	Hud.flush()
end

---@return boolean
local function menuOpen()
	if not Config.hideInMenus then return false end
	local ok, state = pcall(Open77.session.menuState)
	if not ok or type(state) ~= 'table' then return Open77.session.isMenuOpen() == true end
	if not state.open then return false end
	-- a resource that only borrows the cursor over the world (targeting) does not hide the HUD
	if state.source == 'overlay' and Config.keepVisibleFor[state.overlayResource or ''] then return false end
	return true
end
Status.menuOpen = menuOpen

-- The creator provider (opx_core GetProvider('creator')), cached; re-asked when a resource starts or stops.
local creatorProvider, creatorAsked = nil, false
local creatorAt = 0
local CREATOR_POLL = 400

--- Drops the cached creator provider (a resource started or stopped).
function Status.resourceChanged()
	creatorAsked = false
end

--- True while the character creator is open: the provider's client export IsOpen (opx_creator has one;
--- a provider without it never hides the HUD).
---@return boolean
local function creatorOpen()
	if not Config.hideInCreator then return false end
	if not creatorAsked then
		creatorAsked = true
		local ok, name = pcall(Open77.exports.callSync, 'opx_core', 'GetProvider', 'creator')
		creatorProvider = ok and type(name) == 'string' and name or nil
	end
	if not creatorProvider then return false end
	local ok, open = pcall(Open77.exports.callSync, creatorProvider, 'IsOpen')
	return ok and open == true
end

--- Poll loop: reads pools and vehicle only while the HUD is drawn, and keeps the menu state in sync.
function Status.start()
	applyAll()
	CreateThread(function()
		while true do
			if Hud.isShown() or Hud.getState('menu') then
				Hud.setState('menu', menuOpen())
			end
			-- the creator is asked at most every CREATOR_POLL ms (one export call)
			local now = GetGameTimer()
			if (Hud.isShown() or Hud.getState('creator')) and now - creatorAt >= CREATOR_POLL then
				creatorAt = now
				Hud.setState('creator', creatorOpen())
			end
			if Hud.isShown() then
				readStats()
				local appeared = readVehicle()
				Voice.poll()
				Hud.flush()
				if appeared then Motion.vehicle() end
				Wait(inVehicle and Config.vehicleInterval or Config.updateInterval)
			else
				-- a hit taken while hidden is not replayed on show; the vehicle block re-enters on show
				lastHealth = nil
				Wait(500)
			end
		end
	end)
end

return Status
