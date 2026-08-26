--!strict
-- Tunable economy + rules. Learning and reward stay separate systems: coins come
-- from missions, everything here only spends them.

local Config = {
	RESCUE_COST = 5,
	FEED_COST = 2,
	FUSE_COST = 10,
	STARTING_COINS = 20,

	STAT_CAP = 10,
	MAX_PARTS = 6, -- a chimera can be at most six animals deep
	BOUNTY = 3, -- first win against a monster rung

	BATTLE_ROUNDS = 3, -- best-of-3
	SAVE_INTERVAL = 60,
	DATASTORE_NAME = "FusionZoo_v1",
}

-- 速⚡ beats 力💪 · 智🧠 beats 速⚡ · 力💪 beats 智🧠
local BEATS: { [string]: string } = {
	speed = "power",
	smarts = "speed",
	power = "smarts",
}

local STAT_LABELS: { [string]: string } = {
	power = "力💪",
	speed = "速⚡",
	smarts = "智🧠",
}

local STATS: { string } = { "power", "speed", "smarts" }

Config.BEATS = BEATS
Config.STAT_LABELS = STAT_LABELS
Config.STATS = STATS

return Config
