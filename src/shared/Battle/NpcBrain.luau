--!strict
-- NPC opponents: stat picks weighted by the NPC's own stat values (a strength
-- monster leans 力, so its pattern can be read and countered), charge
-- probability rising linearly with rung 0.3 → 0.8.

local Config = require("../Config")
local Rng = require("../Util/Rng")
local Types = require("../Types")

local NpcBrain = {}

function NpcBrain.pickStat(stats: Types.Stats, rand: Rng.Rand): Types.Stat
	return Rng.weightedPick({
		{ item = "li" :: Types.Stat, weight = stats.li },
		{ item = "su" :: Types.Stat, weight = stats.su },
		{ item = "zhi" :: Types.Stat, weight = stats.zhi },
	}, rand)
end

function NpcBrain.chargeProbability(rung: number): number
	local battle = Config.Battle
	local t = (math.clamp(rung, 1, battle.NPC_RUNGS) - 1) / (battle.NPC_RUNGS - 1)
	return battle.NPC_CHARGE_MIN + (battle.NPC_CHARGE_MAX - battle.NPC_CHARGE_MIN) * t
end

function NpcBrain.resolveCharge(rung: number, rand: Rng.Rand): boolean
	return rand() < NpcBrain.chargeProbability(rung)
end

return NpcBrain
