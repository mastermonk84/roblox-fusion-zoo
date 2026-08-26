--!strict
-- Every tunable in the game. Balance changes should never require touching
-- logic modules — adjust here (or in data-src/) only.

local Config = {}

-- ── Quiz engine (ported web values — the battle-tested core IP) ─────────────
Config.Quiz = {
	MAX_LEVEL = 5,
	-- Clean solves in a row to level up, by level. Code truth from the web
	-- version (its README's "5" was stale); realizes accelerated placement.
	CLEAN_TO_ADVANCE = { 3, 4, 6, 8, 8 },
	MISSES_TO_DROP = 4,
	UNLOCK_START = 8,
	UNLOCK_PER_LEVEL = 8,
	MIN_FRESH = 16, -- expand working set while fewer unmastered items than this
	WARM_STREAK = 3, -- web mastery streak -> the "warm" tier
	REVIEW_WEIGHT = 0.12, -- warm items keep appearing at this relative weight
	NUMBER_WEIGHT = 0.25, -- 一..十 sampled 4x less
	RECENT_RING = 12, -- session-only repeat avoidance
	CHOICES = 3, -- target + 2 distractors
	FLASH_SECONDS = 4, -- battle charge-flash answer window
}

-- Mode-mix weight tables by level (web modeForLevel). pinyin adds weight 3 at
-- level >= PINYIN_MIN_LEVEL when the per-player toggle is on.
Config.ModeMix = {
	PINYIN_MIN_LEVEL = 4,
	PINYIN_WEIGHT = 3,
	byLevel = {
		[1] = { ["listen-char"] = 10 },
		[2] = { ["listen-char"] = 6, ["char-picture"] = 4 },
		[3] = { ["listen-char"] = 5, ["char-picture"] = 2, ["picture-char"] = 3 },
	}, -- levels above 3 reuse the level-3 table
}

-- ── Mastery credential (two modes x two days; single-mode items: two days) ──
Config.Mastery = {
	MODE_CLASSES_REQUIRED = 2,
	DAYS_REQUIRED = 2,
}

-- ── Economy ─────────────────────────────────────────────────────────────────
Config.Economy = {
	STARTING_COINS = 5,
	CLEAN_SOLVE = 1, -- the only uncapped faucet
	WARMUP_DOUBLE_COUNT = 5, -- first N clean solves each UTC day pay double
	MISS_PENALTY = 1, -- second wrong tap, floored at 0
	LEVEL_UP_BONUS = 5,
	NPC_FIRST_CLEAR = 3, -- flat, once per rung
	GHOST_WIN = 2,
	GHOST_DAILY_CAP = 10, -- coins per UTC day
	GHOST_COOLDOWN_SECONDS = 6 * 3600, -- per-ghost payout cooldown
	LIVE_WIN = 3,
	LIVE_PARTICIPATION = 1,
	LIVE_DAILY_CAP = 9, -- coins per UTC day
	REAL_WORD_BONUS = 5, -- once per combo, on discovery
	RESCUE_TIERS = { 5, 8, 12, 18, 25 },
	FUSE_COST = 10,
	REFUSE_COST = 6, -- swap a slot on an existing beast
	SLOT_UNLOCKS = {
		legs = { cost = 25, rung = 4 },
		tail = { cost = 60, rung = 8 },
	},
	NAME_COST = 3,
	DECORATION_COST_MIN = 2,
	DECORATION_COST_MAX = 5,
	COLORWAY_COST = 5,
}

-- ── Fusion / feeding ────────────────────────────────────────────────────────
Config.Fusion = {
	STAT_CAP = 10,
	FEED_CAP = 10, -- feed level per slot; reaching level n costs n coins
	-- TAIL contributes 1 + floor(feed/3) to the tail animal's naturally highest
	-- innate stat ("+1 splash" at rest, feeding stays meaningful).
	TAIL_SPLASH_BASE = 1,
	TAIL_FEED_PER_EXTRA = 3,
	SLOT_STAT = { body = "li", legs = "su", head = "zhi" } :: { [string]: string },
}

-- ── Battle ──────────────────────────────────────────────────────────────────
Config.Battle = {
	ROUNDS_TO_WIN = 2, -- best-of-3
	MAX_TIE_REPLAYS = 3, -- then higher total build stats, then challenger
	-- 速 beats 力, 智 beats 速, 力 beats 智 (advantaged AND charged -> x2)
	TRIANGLE = { su = "li", zhi = "su", li = "zhi" } :: { [string]: string },
	NPC_CHARGE_MIN = 0.3,
	NPC_CHARGE_MAX = 0.8,
	NPC_RUNGS = 12,
	GHOST_CHARGE_MIN = 0.2,
	GHOST_CHARGE_MAX = 0.9,
	GHOST_STAT_WINDOW = 0.3, -- prefer ghosts within +-30% total stats
	CHALLENGE_TIMEOUT_SECONDS = 30,
}

-- ── Rig scaling (visual growth) ─────────────────────────────────────────────
Config.Rig = {
	SCALE_PER_POINT = 0.06, -- per stat point above baseline
	SCALE_CAP = 1.55, -- hard proportional cap
	SPARKLE_AT = 10,
}

-- ── Persistence / misc ──────────────────────────────────────────────────────
Config.Profile = {
	SCHEMA_VERSION = 1,
	AUTOSAVE_SECONDS = 30,
	ACCURACY_WINDOW = 200, -- halve counters at this total (rolling-ish accuracy)
	DATASTORE_NAME = "PlayerProfiles_v1",
	GHOST_STORE = "GhostPool_v1",
	GHOST_INDEX = "GhostIndex",
	GHOST_TTL_DAYS = 30,
	ANALYTICS_STORE = "Analytics_v1",
	GHOST_PUBLISH_DEBOUNCE = 30,
}

Config.Content = {
	TOTAL_ITEMS = 700,
	BANDS = 14,
	BAND_SIZE = 50,
}

Config.STAT_LABELS = { li = "力", su = "速", zhi = "智" } :: { [string]: string }
Config.STATS = { "li", "su", "zhi" } :: { string }
Config.MODE_CLASS = {
	["listen-char"] = "listen",
	["char-picture"] = "picture",
	["picture-char"] = "picture",
	["char-pinyin"] = "pinyin",
} :: { [string]: string }

return Config
