--!strict
-- The cross-server ghost pool. Publishing: the player's active beast snapshots
-- into a durable store plus a recency index (debounced; also on session end).
-- Fetching: a random window from the index, self filtered out, weighted toward
-- beasts within ±30% of the challenger's total stats; a thin pool falls back
-- to seeded starter ghosts. Ghost owners are never touched by a battle.
--
-- Stores are injected:
--   prod  DataStore GhostPool_v1 (snapshots) + MemoryStore SortedMap GhostIndex
--   tests in-memory fakes with the same three functions

local Animals = require("../../shared/Data/Animals")
local Config = require("../../shared/Config")
local StarterGhosts = require("../../shared/Data/StarterGhosts")
local ProfileSchema = require("../../shared/ProfileSchema")
local Rng = require("../../shared/Util/Rng")
local SlotStats = require("../../shared/Fusion/SlotStats")
local Types = require("../../shared/Types")

type Profile = Types.Profile
type GhostSnapshot = Types.GhostSnapshot

local ANIMAL_INDEX = SlotStats.index(Animals :: { Types.AnimalDef })

local GhostService = {}
GhostService.__index = GhostService

export type Stores = {
	-- durable snapshots
	get: (key: string) -> GhostSnapshot?,
	set: (key: string, value: GhostSnapshot) -> (),
	-- recency index: returns up to `count` userIds, freshest-biased
	indexSet: (userId: number, publishedAt: number) -> (),
	indexSample: (count: number) -> { number },
}

export type Deps = {
	profiles: any,
	stores: Stores,
	now: (() -> number)?,
	rand: Rng.Rand?,
}

function GhostService.new(deps: Deps)
	return setmetatable({
		_profiles = deps.profiles,
		_stores = deps.stores,
		_now = deps.now or os.time,
		_rand = deps.rand or Rng.mulberry32(os.clock() * 1e6 % 2 ^ 31),
		_lastPublish = {} :: { [number]: number },
	}, GhostService)
end

function GhostService.snapshotOf(
	profile: Profile,
	userId: number,
	displayName: string,
	now: number
): GhostSnapshot?
	local beastId = profile.activeBeastId
	if not beastId then
		return nil
	end
	local beast = profile.beasts[beastId]
	if not beast then
		return nil
	end
	local battle = Config.Battle
	return {
		ownerUserId = userId,
		ownerDisplayName = displayName,
		slots = beast.slots,
		feed = beast.feed,
		golden = beast.golden,
		stats = SlotStats.resolve(beast, ANIMAL_INDEX),
		pickHistogram = profile.pickHistogram,
		-- the owner's REAL mission accuracy, clamped at publish (spec)
		accuracy = math.clamp(
			ProfileSchema.accuracy(profile),
			battle.GHOST_CHARGE_MIN,
			battle.GHOST_CHARGE_MAX
		),
		publishedAt = now,
	}
end

-- Debounced auto-publish; pass force=true on session end.
function GhostService.publish(
	self: any,
	userId: number,
	displayName: string,
	force: boolean?
): boolean
	local now = self._now()
	local last = self._lastPublish[userId]
	if not force and last and now - last < Config.Profile.GHOST_PUBLISH_DEBOUNCE then
		return false
	end
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return false
	end
	local snapshot = GhostService.snapshotOf(profile, userId, displayName, now)
	if not snapshot then
		return false
	end
	self._lastPublish[userId] = now
	self._stores.set(`g{userId}`, snapshot)
	self._stores.indexSet(userId, now)
	return true
end

-- Write a pre-built snapshot (used on PlayerRemoving: the snapshot is captured
-- synchronously before the profile releases; the store writes may yield).
function GhostService.publishSnapshot(self: any, userId: number, snapshot: GhostSnapshot)
	self._lastPublish[userId] = snapshot.publishedAt
	self._stores.set(`g{userId}`, snapshot)
	self._stores.indexSet(userId, snapshot.publishedAt)
end

-- Pick an opponent ghost for this player. Never the player's own; prefers
-- builds within ±30% total stats; starter ghosts when the pool is thin.
function GhostService.fetch(self: any, userId: number): GhostSnapshot?
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return nil
	end
	local myStats: Types.Stats? = nil
	local beastId = profile.activeBeastId
	if beastId and profile.beasts[beastId] then
		myStats = SlotStats.resolve(profile.beasts[beastId], ANIMAL_INDEX)
	end
	local myTotal = if myStats then myStats.li + myStats.su + myStats.zhi else 6

	local candidates: { GhostSnapshot } = {}
	for _, ghostUserId in self._stores.indexSample(24) do
		if ghostUserId ~= userId then
			local snapshot = self._stores.get(`g{ghostUserId}`)
			if snapshot then
				table.insert(candidates, snapshot)
			end
		end
	end
	if #candidates == 0 then
		local starters = StarterGhosts :: { GhostSnapshot }
		return starters[math.floor(self._rand() * #starters) + 1]
	end

	local window = Config.Battle.GHOST_STAT_WINDOW
	local weighted: Rng.Weighted<GhostSnapshot> = {}
	for _, snapshot in candidates do
		local total = snapshot.stats.li + snapshot.stats.su + snapshot.stats.zhi
		local ratio = total / math.max(1, myTotal)
		local inWindow = ratio >= 1 - window and ratio <= 1 + window
		table.insert(weighted, { item = snapshot, weight = if inWindow then 4 else 1 })
	end
	return Rng.weightedPick(weighted, self._rand)
end

return GhostService
