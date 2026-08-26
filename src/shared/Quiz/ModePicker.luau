--!strict
-- The web mode mix, made asset-aware (criterion 9). Build the level's weight
-- table, delete any mode with zero eligible targets in the working set,
-- renormalize by weighted pick over what's left. Never errors: with an empty
-- audio manifest there are simply no listen questions; with nothing eligible
-- at all it returns nil and the caller shows a friendly "content coming" state.

local Config = require("../Config")
local Item = require("./Item")
local Rng = require("../Util/Rng")
local Types = require("../Types")

type QuizItem = Types.QuizItem

local ModePicker = {}

export type PoolCounts = { [string]: number }

-- How many working-set items each mode could serve right now.
function ModePicker.poolCounts(
	workingSet: { QuizItem },
	manifests: Item.Manifests,
	pinyinOn: boolean
): PoolCounts
	local counts: PoolCounts = {}
	for _, item in workingSet do
		for mode in Item.eligibleModes(item, manifests, pinyinOn) do
			counts[mode] = (counts[mode] or 0) + 1
		end
	end
	return counts
end

function ModePicker.pick(
	level: number,
	pinyinOn: boolean,
	counts: PoolCounts,
	rand: Rng.Rand
): string?
	local clamped = math.min(level, Config.Quiz.MAX_LEVEL)
	local tableLevel = math.min(clamped, 3)
	local base = Config.ModeMix.byLevel[tableLevel]

	local weighted: Rng.Weighted<string> = {}
	for mode, weight in base do
		if (counts[mode] or 0) > 0 then
			table.insert(weighted, { item = mode, weight = weight })
		end
	end
	if
		pinyinOn
		and clamped >= Config.ModeMix.PINYIN_MIN_LEVEL
		and (counts["char-pinyin"] or 0) > 0
	then
		table.insert(weighted, { item = "char-pinyin", weight = Config.ModeMix.PINYIN_WEIGHT })
	end

	if #weighted == 0 then
		-- Nothing from the mix table is servable. Fall back to ANY eligible mode
		-- (e.g. pinyin-on with no assets at L1) rather than dead-ending.
		for mode, count in counts do
			if count > 0 then
				table.insert(weighted, { item = mode, weight = 1 })
			end
		end
	end
	if #weighted == 0 then
		return nil
	end
	return Rng.weightedPick(weighted, rand)
end

return ModePicker
