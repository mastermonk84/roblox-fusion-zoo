--!strict
-- Per-player save. DataStores are wrapped in pcall so a Studio session with no
-- API access still plays — it just starts fresh every time.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[FusionZoo] DataStore unavailable, running in memory only: {result}`)
	end
end

local cache: { [Player]: Types.Save } = {}

local module = {}

local function blank(): Types.Save
	return {
		coins = Config.STARTING_COINS,
		beasts = {},
		defeated = {},
		nextId = 1,
	}
end

function module.load(player: Player): Types.Save
	local save = blank()

	if store then
		local ok, result = pcall(function()
			return store:GetAsync(`player_{player.UserId}`)
		end)
		if ok and typeof(result) == "table" then
			save = result :: Types.Save
		elseif not ok then
			warn(`[FusionZoo] load failed for {player.Name}: {result}`)
		end
	end

	cache[player] = save
	return save
end

function module.get(player: Player): Types.Save?
	return cache[player]
end

function module.save(player: Player)
	local data = cache[player]
	if not data or not store then
		return
	end

	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(`player_{player.UserId}`, data)
	end)
	if not ok then
		warn(`[FusionZoo] save failed for {player.Name}: {err}`)
	end
end

function module.release(player: Player)
	module.save(player)
	cache[player] = nil
end

function module.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.SAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				module.save(player)
			end
		end
	end)
end

return module
