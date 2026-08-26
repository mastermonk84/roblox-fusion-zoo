--!strict
-- Acceptance criterion 2: content integrity of the generated data modules
-- (build-data validates the JSON sources; this validates what the game will
-- actually require at runtime).

local T = require("../testkit")
local Curriculum = require("../../src/shared/Data/Curriculum")
local Animals = require("../../src/shared/Data/Animals")
local Opponents = require("../../src/shared/Data/Opponents")
local Words = require("../../src/shared/Data/Words")
local HomophoneIndex = require("../../src/shared/Data/HomophoneIndex")
local Conflicts = require("../../src/shared/Data/Conflicts")
local describe, it, expect = T.describe, T.it, T.expect

return function()
	describe("curriculum", function()
		it("has exactly 700 unique curriculum items plus flagged bonus items", function()
			local core, bonus = 0, 0
			local seen: { [string]: boolean } = {}
			for _, item in Curriculum do
				expect(seen[item.text]).to.equal(nil)
				seen[item.text] = true
				if item.bonus then
					bonus += 1
				else
					core += 1
				end
			end
			expect(core).to.equal(700)
			expect(bonus >= 5).to.equal(true)
		end)

		it("gives every item pinyin, band 1-14, english, and a category", function()
			for _, item in Curriculum do
				expect(#item.pinyin > 0).to.equal(true)
				expect(#item.english > 0).to.equal(true)
				expect(item.band >= 1 and item.band <= 14).to.equal(true)
				expect(#item.category > 0).to.equal(true)
				expect(#item.components >= 1).to.equal(true)
			end
		end)

		it("keeps bands at exactly 50 curriculum items each", function()
			local counts: { [number]: number } = {}
			for _, item in Curriculum do
				if not item.bonus then
					counts[item.band] = (counts[item.band] or 0) + 1
				end
			end
			for band = 1, 14 do
				expect(counts[band]).to.equal(50)
			end
		end)

		it("orders curriculum items by 识字表 sequence", function()
			local lastSeq = 0
			for _, item in Curriculum do
				expect(item.seq).to.equal(lastSeq + 1)
				lastSeq = item.seq
			end
		end)

		it("never marks a grammar word as needs_visual", function()
			for _, item in Curriculum do
				if item.grammar then
					expect(item.needs_visual).to.equal(false)
				end
			end
		end)

		it("gives every number 一..十 a counting value", function()
			local expected: { [string]: number } = {
				["一"] = 1,
				["二"] = 2,
				["三"] = 3,
				["四"] = 4,
				["五"] = 5,
				["六"] = 6,
				["七"] = 7,
				["八"] = 8,
				["九"] = 9,
				["十"] = 10,
			}
			local found = 0
			for _, item in Curriculum do
				if expected[item.text] then
					expect(item.value).to.equal(expected[item.text])
					found += 1
				end
			end
			expect(found).to.equal(10)
		end)
	end)

	describe("homophone index", function()
		it("indexes every item under its exact pinyin", function()
			local total = 0
			for _, texts in HomophoneIndex do
				total += #texts
			end
			expect(total).to.equal(#Curriculum)
		end)

		it("leaves >= 2 distinct-pinyin distractors for every non-grammar item", function()
			for _, item in Curriculum do
				if not item.grammar then
					local same = #HomophoneIndex[item.pinyin]
					expect(#Curriculum - same >= 2).to.equal(true)
				end
			end
		end)
	end)

	describe("animals", function()
		it("has 18 launch animals, all with masterable quiz items", function()
			expect(#Animals).to.equal(18)
			local byText: { [string]: boolean } = {}
			for _, item in Curriculum do
				byText[item.text] = true
			end
			for _, animal in Animals do
				expect(byText[animal.char]).to.equal(true)
			end
		end)
	end)

	describe("opponents", function()
		it("has 12 rungs with non-decreasing total stats", function()
			expect(#Opponents).to.equal(12)
			local last = 0
			for _, opp in Opponents do
				local total = opp.li + opp.su + opp.zhi
				expect(total >= last).to.equal(true)
				last = total
			end
		end)
	end)

	describe("real words", function()
		it("spells every word from two animal chars", function()
			local animalChars: { [string]: boolean } = {}
			for _, animal in Animals do
				animalChars[animal.char] = true
			end
			for _, word in Words do
				expect(#word.pair).to.equal(2)
				expect(animalChars[word.pair[1]]).to.equal(true)
				expect(animalChars[word.pair[2]]).to.equal(true)
				expect(word.pair[1] .. word.pair[2]).to.equal(word.word)
			end
		end)
	end)

	describe("conflicts map", function()
		it("only references characters that exist as items", function()
			local byText: { [string]: boolean } = {}
			for _, item in Curriculum do
				byText[item.text] = true
			end
			for key, others in Conflicts do
				expect(byText[key]).to.equal(true)
				for _, other in others do
					expect(byText[other]).to.equal(true)
				end
			end
		end)
	end)
end
