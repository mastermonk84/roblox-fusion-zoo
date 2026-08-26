--!strict
-- Real-word detection: fires when ANY two distinct animals anywhere in the
-- build (head/body/legs/tail) spell a dictionary word — in the word's written
-- order, either arrangement of slots. 熊 anywhere + 猫 anywhere → 熊猫.

local Words = require("../Data/Words")
local Types = require("../Types")

type Beast = Types.Beast

export type WordDef = { word: string, pinyin: string, english: string, pair: { string } }

local RealWords = {}

local WORDS = Words :: { WordDef }

local function occupants(beast: Beast): { [string]: boolean }
	local set: { [string]: boolean } = {}
	set[beast.slots.body] = true
	set[beast.slots.head] = true
	if beast.slots.legs then
		set[beast.slots.legs] = true
	end
	if beast.slots.tail then
		set[beast.slots.tail] = true
	end
	return set
end

-- All real words this build spells (a 4-slot chimera can hold several).
function RealWords.matches(beast: Beast): { WordDef }
	local present = occupants(beast)
	local found: { WordDef } = {}
	for _, word in WORDS do
		local a, b = word.pair[1], word.pair[2]
		if a ~= b and present[a] and present[b] then
			table.insert(found, word)
		end
	end
	return found
end

function RealWords.isGolden(beast: Beast): boolean
	return #RealWords.matches(beast) > 0
end

return RealWords
