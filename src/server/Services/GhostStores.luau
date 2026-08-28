--!strict
-- Production ghost stores: DataStore for durable snapshots, MemoryStore
-- SortedMap for the recency index (TTL'd, cheap to sample). Every call is
-- pcall-wrapped: a store hiccup degrades to the starter-ghost fallback rather
-- than erroring a battle.

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Config = require("../../shared/Config")

local GhostStores = {}

function GhostStores.new()
	local ok, dataStore = pcall(function()
		return DataStoreService:GetDataStore(Config.Profile.GHOST_STORE)
	end)
	-- MemoryStoreService errors on unpublished places (Studio); acquire it under
	-- pcall like the DataStore above so the recency index degrades to a no-op
	-- instead of aborting server boot.
	local okMap, sortedMap = pcall(function()
		return MemoryStoreService:GetSortedMap(Config.Profile.GHOST_INDEX)
	end)
	local ttl = Config.Profile.GHOST_TTL_DAYS * 86400

	return {
		get = function(key: string)
			if not ok then
				return nil
			end
			local success, value = pcall(function()
				return dataStore:GetAsync(key)
			end)
			return if success then value else nil
		end,
		set = function(key: string, value: any)
			if not ok then
				return
			end
			pcall(function()
				dataStore:SetAsync(key, value)
			end)
		end,
		indexSet = function(userId: number, publishedAt: number)
			if not okMap then
				return
			end
			pcall(function()
				sortedMap:SetAsync(tostring(userId), true, ttl, publishedAt)
			end)
		end,
		indexSample = function(count: number)
			local out: { number } = {}
			if not okMap then
				return out
			end
			pcall(function()
				-- newest-first window keeps the pool fresh
				local items = sortedMap:GetRangeAsync(Enum.SortDirection.Descending, count)
				for _, item in items do
					local userId = tonumber(item.key)
					if userId then
						table.insert(out, userId)
					end
				end
			end)
			return out
		end,
	}
end

return GhostStores
