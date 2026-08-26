--!strict
-- Port of the web orderedDeck/unlockedChars: bands ascending, seeded shuffle
-- within each band threading ONE mulberry32 stream (this correlation is part of
-- the deterministic deck identity — do not "fix" it), working set = prefix.

local Config = require("../Config")
local Rng = require("../Util/Rng")
local Types = require("../Types")

type QuizItem = Types.QuizItem

local Deck = {}

-- Deterministic per seed. Rebuild is cheap enough to call per question, but
-- QuizService caches per (seed) since the item list never changes at runtime.
function Deck.ordered(items: { QuizItem }, seed: number): { QuizItem }
	local byBand: { [number]: { QuizItem } } = {}
	local bands: { number } = {}
	for _, item in items do
		local bucket = byBand[item.band]
		if not bucket then
			bucket = {}
			byBand[item.band] = bucket
			table.insert(bands, item.band)
		end
		table.insert(bucket, item)
	end
	table.sort(bands)

	local rand = Rng.mulberry32(seed)
	local deck: { QuizItem } = {}
	for _, band in bands do
		for _, item in Rng.seededShuffle(byBand[band], rand) do
			table.insert(deck, item)
		end
	end
	return deck
end

-- The working set is always a prefix of the ordered deck, never a scattered
-- subset. Floor of 8 matches the web engine.
function Deck.workingSet(deck: { QuizItem }, unlocked: number): { QuizItem }
	local n = math.min(#deck, math.max(Config.Quiz.UNLOCK_START, unlocked))
	local prefix = table.create(n)
	for i = 1, n do
		prefix[i] = deck[i]
	end
	return prefix
end

return Deck
