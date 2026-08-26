--!strict
-- Slot-stat fusion (replaces the web's additive fuseStat):
--   BODY → 力 li     LEGS → 速 su     HEAD → 智 zhi
--   TAIL → splash of 1 + floor(feed/3) onto the tail animal's naturally
--          highest innate stat (tie-break 力 > 速 > 智)
-- slot stat = occupant's innate contribution + the BEAST's feed level for that
-- slot, capped at 10. A 2-part beast (BODY+HEAD) runs LEGS on the body animal
-- with no legs feed until the slot is bought.

local Config = require("../Config")
local Types = require("../Types")

type Stats = Types.Stats
type AnimalDef = Types.AnimalDef
type Beast = Types.Beast

local SlotStats = {}

export type AnimalIndex = { [string]: AnimalDef }

function SlotStats.index(animals: { AnimalDef }): AnimalIndex
	local map: AnimalIndex = {}
	for _, animal in animals do
		map[animal.char] = animal
	end
	return map
end

-- The stat an animal is naturally best at (tie-break 力 > 速 > 智).
function SlotStats.naturalBest(animal: AnimalDef): Types.Stat
	local best: Types.Stat = "li"
	local bestValue = animal.li
	if animal.su > bestValue then
		best = "su"
		bestValue = animal.su
	end
	if animal.zhi > bestValue then
		best = "zhi"
	end
	return best
end

function SlotStats.tailSplash(feedTail: number): number
	return Config.Fusion.TAIL_SPLASH_BASE + math.floor(feedTail / Config.Fusion.TAIL_FEED_PER_EXTRA)
end

-- Effective battle stats for a build. Missing LEGS falls back to the body
-- animal (feed contributes only once the slot is unlocked and fed, which the
-- service enforces by keeping feed.legs at 0 until purchase).
function SlotStats.resolve(beast: Beast, animals: AnimalIndex): Stats
	local body = animals[beast.slots.body]
	local head = animals[beast.slots.head]
	assert(body, `unknown body animal {beast.slots.body}`)
	assert(head, `unknown head animal {beast.slots.head}`)
	local legsChar = beast.slots.legs or beast.slots.body
	local legs = animals[legsChar]
	assert(legs, `unknown legs animal {legsChar}`)

	local cap = Config.Fusion.STAT_CAP
	local stats: Stats = {
		li = math.min(cap, body.li + beast.feed.body),
		su = math.min(cap, legs.su + beast.feed.legs),
		zhi = math.min(cap, head.zhi + beast.feed.head),
	}

	local tailChar = beast.slots.tail
	if tailChar then
		local tail = animals[tailChar]
		assert(tail, `unknown tail animal {tailChar}`)
		local target = SlotStats.naturalBest(tail)
		local statsAny = stats :: any
		statsAny[target] = math.min(cap, statsAny[target] + SlotStats.tailSplash(beast.feed.tail))
	end

	return stats
end

-- Per-slot stat totals (for visual scaling and the feed menu): what each slot
-- currently contributes on its own axis.
function SlotStats.slotTotals(beast: Beast, animals: AnimalIndex): { [string]: number }
	local cap = Config.Fusion.STAT_CAP
	local body = animals[beast.slots.body]
	local head = animals[beast.slots.head]
	local legs = animals[beast.slots.legs or beast.slots.body]
	local totals: { [string]: number } = {
		body = math.min(cap, body.li + beast.feed.body),
		head = math.min(cap, head.zhi + beast.feed.head),
		legs = math.min(cap, legs.su + beast.feed.legs),
	}
	if beast.slots.tail then
		totals.tail =
			math.min(cap, SlotStats.tailSplash(beast.feed.tail) * Config.Fusion.TAIL_FEED_PER_EXTRA)
	end
	return totals
end

return SlotStats
