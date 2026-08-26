--!strict
-- In-memory persistence backend for tests. Same three-function surface the
-- production loleris wrapper exposes, plus crash/lock simulation so the
-- session-lock recovery criterion is testable headless. Data passes through a
-- DataStore-compatibility check on every save boundary, so a profile that
-- would fail SetAsync (mixed keys, functions, NaN, cycles) fails the test.

local MockBackend = {}
MockBackend.__index = MockBackend

-- Reject anything Roblox DataStores reject.
local function checkStorable(value: any, path: string, seen: { [any]: boolean })
	local t = type(value)
	if t == "number" then
		assert(value == value and value ~= math.huge and value ~= -math.huge, `NaN/inf at {path}`)
	elseif t == "string" or t == "boolean" then
		return
	elseif t == "table" then
		assert(not seen[value], `cycle at {path}`)
		seen[value] = true
		local arrayCount = #(value :: { any })
		local total = 0
		for k, v in value :: { [any]: any } do
			total += 1
			local kt = type(k)
			assert(kt == "string" or kt == "number", `bad key type {kt} at {path}`)
			checkStorable(v, `{path}.{tostring(k)}`, seen)
		end
		-- mixed array/map tables don't survive DataStore JSON
		if arrayCount > 0 then
			assert(arrayCount == total, `mixed array/dictionary table at {path}`)
		end
	elseif t == "nil" then
		return
	else
		error(`unstorable type {t} at {path}`)
	end
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: { [any]: any } do
		copy[k] = deepCopy(v)
	end
	return copy
end

export type MockBackend = {
	load: (key: string) -> any,
	save: (self: MockBackend, key: string) -> (),
	simulateCrash: (self: MockBackend, key: string) -> (),
	storedData: (self: MockBackend, key: string) -> any,
	releaseAll: (self: MockBackend) -> (),
}

function MockBackend.new()
	local self: any = setmetatable({
		_stored = {} :: { [string]: any }, -- durable data, as of last save
		_locks = {} :: { [string]: { stale: boolean, live: any? } },
	}, MockBackend)

	-- Bind load with self captured: backends expose load as a plain function.
	self.load = function(key: string)
		local lock = self._locks[key]
		if lock and not lock.stale then
			return nil -- session-locked by a live "server"
		end
		-- steal a stale lock (crash recovery): durable data survives
		local data = deepCopy(self._stored[key]) or {}
		local releaseListeners: { () -> () } = {}
		local active = true
		local profile: any
		profile = {
			Data = data,
			Release = function(_p)
				if not active then
					return
				end
				active = false
				checkStorable(profile.Data, key, {})
				self._stored[key] = deepCopy(profile.Data)
				self._locks[key] = nil
				for _, fn in releaseListeners do
					fn()
				end
			end,
			ListenToRelease = function(_p, fn: () -> ())
				table.insert(releaseListeners, fn)
			end,
			IsActive = function(_p)
				return active
			end,
		}
		self._locks[key] = { stale = false, live = profile }
		return profile
	end
	return self
end

-- Autosave tick: persist without releasing (checks storability like SetAsync).
function MockBackend.save(self: any, key: string)
	local lock = self._locks[key]
	assert(lock and lock.live, `no live profile for {key}`)
	checkStorable(lock.live.Data, key, {})
	self._stored[key] = deepCopy(lock.live.Data)
end

-- Server dies without releasing: durable data = last save, lock goes stale so
-- the next load (on any server) steals it.
function MockBackend.simulateCrash(self: any, key: string)
	local lock = self._locks[key]
	assert(lock, `no lock to crash for {key}`)
	lock.stale = true
	lock.live = nil
end

function MockBackend.storedData(self: any, key: string): any
	return deepCopy(self._stored[key])
end

function MockBackend.releaseAll(self: any)
	for _, lock in self._locks :: { [string]: any } do
		if lock.live then
			lock.live:Release()
		end
	end
end

return MockBackend
