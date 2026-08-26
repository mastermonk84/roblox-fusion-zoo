--!strict
-- Ghost opponents: snapshots of real players' beasts. Picks lean lightly
-- toward the owner's real pick pattern; charge probability IS the owner's
-- recorded quiz accuracy, clamped 0.2–0.9 — studying makes your beast
-- stronger, even while you sleep.

local Config = require("../Config")
local Rng = require("../Util/Rng")
local Types = require("../Types")

local GhostBrain = {}

function GhostBrain.pickStat(snapshot: Types.GhostSnapshot, rand: Rng.Rand): Types.Stat
	local histogram = snapshot.pickHistogram
	local total = math.max(1, histogram.li + histogram.su + histogram.zhi)
	return Rng.weightedPick({
		{ item = "li" :: Types.Stat, weight = 1 + 0.5 * (histogram.li / total) * 3 },
		{ item = "su" :: Types.Stat, weight = 1 + 0.5 * (histogram.su / total) * 3 },
		{ item = "zhi" :: Types.Stat, weight = 1 + 0.5 * (histogram.zhi / total) * 3 },
	}, rand)
end

function GhostBrain.chargeProbability(snapshot: Types.GhostSnapshot): number
	return math.clamp(
		snapshot.accuracy,
		Config.Battle.GHOST_CHARGE_MIN,
		Config.Battle.GHOST_CHARGE_MAX
	)
end

function GhostBrain.resolveCharge(snapshot: Types.GhostSnapshot, rand: Rng.Rand): boolean
	return rand() < GhostBrain.chargeProbability(snapshot)
end

return GhostBrain
