--!strict
-- Target selection, ported from the web engine: mode-filtered pool from the
-- working set, adaptive repeat-avoidance ring, weightedPick with warm-review
-- (0.12) and number (0.25) factors.

local Config = require("../Config")
local Item = require("./Item")
local Rng = require("../Util/Rng")
local Types = require("../Types")

type QuizItem = Types.QuizItem
type CharState = Types.CharState

local Sampler = {}

local function isWarm(states: { [string]: CharState }, text: string): boolean
	local state = states[text]
	return state ~= nil and state.warm >= Config.Quiz.WARM_STREAK
end

Sampler.isWarm = isWarm

-- Pool for a mode: eligible working-set items that this mode can serve.
function Sampler.pool(
	workingSet: { QuizItem },
	mode: string,
	manifests: Item.Manifests,
	pinyinOn: boolean
): { QuizItem }
	local out: { QuizItem } = {}
	for _, item in workingSet do
		if Item.eligibleModes(item, manifests, pinyinOn)[mode] then
			table.insert(out, item)
		end
	end
	return out
end

-- Adaptive ring: exclude up to the last N recent targets, but never shrink the
-- candidate set below 3 (web behavior, verbatim).
local function withoutRecent(pool: { QuizItem }, recent: { string }): { QuizItem }
	local n = math.max(1, math.min(#recent, #pool - 3))
	if n <= 0 or #recent == 0 then
		return pool
	end
	local excluded: { [string]: boolean } = {}
	for i = #recent - n + 1, #recent do
		excluded[recent[i]] = true
	end
	local out: { QuizItem } = {}
	for _, item in pool do
		if not excluded[item.text] then
			table.insert(out, item)
		end
	end
	if #out == 0 then
		return pool
	end
	return out
end

function Sampler.pickTarget(
	pool: { QuizItem },
	states: { [string]: CharState },
	recent: { string },
	rand: Rng.Rand
): QuizItem?
	if #pool == 0 then
		return nil
	end
	local candidates = withoutRecent(pool, recent)
	local weighted: Rng.Weighted<QuizItem> = {}
	for _, item in candidates do
		local weight = 1.0
		if isWarm(states, item.text) then
			weight *= Config.Quiz.REVIEW_WEIGHT
		end
		if item.category == "number" then
			weight *= Config.Quiz.NUMBER_WEIGHT
		end
		table.insert(weighted, { item = item, weight = weight })
	end
	return Rng.weightedPick(weighted, rand)
end

return Sampler
