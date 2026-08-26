--!strict
-- Distractor selection, ported from the web engine: ring expansion
-- same-category -> same-band -> anything, drawn from the FULL item list (a
-- level-1 kid can meet a band-14 char as a wrong answer — deliberate), with:
--   listen mode      exact tone-sensitive pinyin exclusion (spec hard rule)
--   picture modes    picture-eligible only + hand-curated confusable pairs
--   all modes        display-key uniqueness so no two visible buttons match

local Config = require("../Config")
local Conflicts = require("../Data/Conflicts")
local Item = require("./Item")
local Rng = require("../Util/Rng")
local Types = require("../Types")

type QuizItem = Types.QuizItem

local Distractors = {}

local conflictsMap: { [string]: { string } } = Conflicts

local function conflicts(a: string, b: string): boolean
	local listA = conflictsMap[a]
	if listA and table.find(listA, b) then
		return true
	end
	local listB = conflictsMap[b]
	return listB ~= nil and table.find(listB, a) ~= nil
end

-- What the player will actually see on the button for this item in this mode.
function Distractors.displayKey(item: QuizItem, mode: string, manifests: Item.Manifests): string
	if mode == "char-pinyin" then
		return item.pinyin
	elseif mode == "char-picture" then
		-- picture answers: the icon (repeated for counting numbers)
		local icon = manifests.icons[item.text] or ""
		return `{icon}x{item.value or 1}`
	end
	return item.text
end

local function valid(
	target: QuizItem,
	candidate: QuizItem,
	mode: string,
	manifests: Item.Manifests
): boolean
	if candidate.text == target.text then
		return false
	end
	local needsPicture = mode == "char-picture" or mode == "picture-char"
	if needsPicture then
		if not Item.pictureEligible(candidate, manifests) then
			return false
		end
		if conflicts(target.text, candidate.text) then
			return false
		end
	end
	if mode == "listen-char" and candidate.pinyin == target.pinyin then
		return false -- homophone rule: never share exact pinyin incl. tone
	end
	return true
end

function Distractors.choose(
	allItems: { QuizItem },
	target: QuizItem,
	mode: string,
	manifests: Item.Manifests,
	rand: Rng.Rand
): { QuizItem }
	local rings: { (QuizItem) -> boolean } = {
		function(c)
			return c.category == target.category
		end,
		function(c)
			return c.band == target.band
		end,
		function()
			return true
		end,
	}

	local chosen: { QuizItem } = { target }
	local usedKeys: { [string]: boolean } =
		{ [Distractors.displayKey(target, mode, manifests)] = true }
	local usedTexts: { [string]: boolean } = { [target.text] = true }

	for _, ringFilter in rings do
		if #chosen >= Config.Quiz.CHOICES then
			break
		end
		local ring: { QuizItem } = {}
		for _, candidate in allItems do
			if valid(target, candidate, mode, manifests) and ringFilter(candidate) then
				table.insert(ring, candidate)
			end
		end
		for _, candidate in Rng.seededShuffle(ring, rand) do
			if #chosen >= Config.Quiz.CHOICES then
				break
			end
			local key = Distractors.displayKey(candidate, mode, manifests)
			if not usedKeys[key] and not usedTexts[candidate.text] then
				usedKeys[key] = true
				usedTexts[candidate.text] = true
				table.insert(chosen, candidate)
			end
		end
	end

	return chosen
end

return Distractors
