--!strict
-- Profile template, migration chain, reconcile, and the small profile-math
-- helpers (daily rollover, rolling accuracy). Pure: the persistence backend
-- (loleris ProfileService in prod, a mock in tests) is injected elsewhere.

local Config = require("./Config")
local Time = require("./Util/Time")
local Types = require("./Types")

type Profile = Types.Profile

local ProfileSchema = {}

ProfileSchema.CURRENT_VERSION = Config.Profile.SCHEMA_VERSION

function ProfileSchema.template(seed: number, now: number): Profile
	return {
		schemaVersion = ProfileSchema.CURRENT_VERSION,
		createdAt = now,
		coins = Config.Economy.STARTING_COINS,
		level = 1,
		cleanStreak = 0,
		missStreak = 0,
		seed = seed,
		unlocked = Config.Quiz.UNLOCK_START,
		pinyinMode = false,
		chars = {},
		accuracy = { clean = 0, total = 0 },
		daily = {
			dayKey = Time.dayKey(now),
			warmupCount = 0,
			ghostCoins = 0,
			liveCoins = 0,
			ghostPayouts = {},
		},
		animals = {},
		beasts = {},
		nextBeastId = 1,
		activeBeastId = nil,
		slotsUnlocked = { legs = false, tail = false },
		ladderRung = 0,
		battleRecord = { wins = 0, losses = 0 },
		realWordsFound = {},
		decorations = {},
		plotPlacements = {},
		colorways = {},
		tutorial = { grantsGiven = false, done = false },
	}
end

-- Migration chain: migrations[n] upgrades a version-(n-1) profile to version n.
-- Version 1 is the launch schema, so the chain is empty today; every future
-- schema change adds one entry and bumps Config.Profile.SCHEMA_VERSION.
ProfileSchema.migrations = {} :: { [number]: (any) -> () }

function ProfileSchema.migrate(profile: any): Profile
	local version = if type(profile.schemaVersion) == "number" then profile.schemaVersion else 0
	while version < ProfileSchema.CURRENT_VERSION do
		version += 1
		local step = ProfileSchema.migrations[version]
		if step then
			step(profile)
		end
		profile.schemaVersion = version
	end
	return profile :: Profile
end

-- Deep-fill missing keys from the template (array tables are taken verbatim).
local function reconcileInto(target: { [string]: any }, source: { [string]: any })
	for key, value in source do
		if target[key] == nil then
			if type(value) == "table" then
				local copy = {}
				reconcileInto(copy, value :: { [string]: any })
				target[key] = copy
			else
				target[key] = value
			end
		elseif
			type(value) == "table"
			and type(target[key]) == "table"
			and #(value :: { any }) == 0
		then
			reconcileInto(target[key] :: { [string]: any }, value :: { [string]: any })
		end
	end
end

function ProfileSchema.reconcile(profile: any, seed: number, now: number): Profile
	reconcileInto(profile, ProfileSchema.template(seed, now) :: any)
	return profile :: Profile
end

-- Lazy UTC-day rollover: call before touching any daily counter.
function ProfileSchema.rollDaily(profile: Profile, now: number)
	local today = Time.dayKey(now)
	if profile.daily.dayKey ~= today then
		profile.daily = {
			dayKey = today,
			warmupCount = 0,
			ghostCoins = 0,
			liveCoins = 0,
			ghostPayouts = {},
		}
	end
end

-- Rolling-ish accuracy: halve both counters at the window cap so recent play
-- dominates without storing a ring buffer. Mission answers only.
function ProfileSchema.recordAnswer(profile: Profile, clean: boolean)
	local acc = profile.accuracy
	acc.total += 1
	if clean then
		acc.clean += 1
	end
	if acc.total >= Config.Profile.ACCURACY_WINDOW then
		acc.total = math.floor(acc.total / 2)
		acc.clean = math.floor(acc.clean / 2)
	end
end

-- 0..1; 0.5 before any evidence (a fresh ghost fights at coin-flip charge).
function ProfileSchema.accuracy(profile: Profile): number
	if profile.accuracy.total == 0 then
		return 0.5
	end
	return profile.accuracy.clean / profile.accuracy.total
end

return ProfileSchema
