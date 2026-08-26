--!strict
-- Engine-side analytics persistence: drains the Analytics buffer every 60s
-- (and on demand at shutdown) into the Analytics_v1 DataStore, keyed
-- {dateKey}/{jobId} with size-guarded appends. Balance review reads these
-- offline; nothing in the game reads them back.

local DataStoreService = game:GetService("DataStoreService")

local Config = require("../../shared/Config")
local Time = require("../../shared/Util/Time")

local FLUSH_SECONDS = 60
local MAX_EVENTS_PER_KEY = 2000 -- stay far under the 4MB value limit

local AnalyticsFlush = {}

function AnalyticsFlush.start(analytics: any)
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.Profile.ANALYTICS_STORE)
	end)
	if not ok then
		warn("[FusionZoo] analytics store unavailable; events stay in memory")
		return
	end

	local function flush()
		local events = analytics:drain()
		if #events == 0 then
			return
		end
		local key = `{Time.dayKey(os.time())}/{game.JobId ~= "" and game.JobId or "studio"}`
		pcall(function()
			store:UpdateAsync(key, function(existing)
				local list = existing or {}
				for _, event in events do
					if #list >= MAX_EVENTS_PER_KEY then
						break
					end
					table.insert(list, event)
				end
				return list
			end)
		end)
	end

	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			flush()
		end
	end)
	game:BindToClose(flush)
end

return AnalyticsFlush
