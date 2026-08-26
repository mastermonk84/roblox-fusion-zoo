--!strict
-- Criterion 1 (mastery): the two-tier model. Warm streak (pacing) ports the
-- web behavior; MASTERED (credential) needs two mode classes on two distinct
-- UTC days — single-class grammar words relax to two days in one class.

local T = require("../testkit")
local H = require("../quiz/helpers")
local Mastery = require("../../src/shared/Quiz/Mastery")
local Deck = require("../../src/shared/Quiz/Deck")
local ProfileSchema = require("../../src/shared/ProfileSchema")
local Types = require("../../src/shared/Types")
local describe, it, expect = T.describe, T.it, T.expect

type QuizItem = Types.QuizItem

local DAY1, DAY2 = "2026-08-25", "2026-08-26"

local function findItem(predicate: (QuizItem) -> boolean): QuizItem
	for _, item in H.items do
		if predicate(item) then
			return item
		end
	end
	error("no item matches")
end

local horse = findItem(function(i)
	return i.text == "马"
end)
local grammarWord = findItem(function(i)
	return i.grammar
end)

return function()
	describe("warm tier (web streak mastery)", function()
		it("goes warm at 3 clean solves and resets on a miss", function()
			local p = ProfileSchema.template(1, H.NOW)
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			expect(p.chars["马"].warm).to.equal(2)
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			expect(p.chars["马"].warm).to.equal(3)
			Mastery.recordMiss(p, horse)
			expect(p.chars["马"].warm).to.equal(0)
		end)

		it("holds the warm streak through a retry", function()
			local p = ProfileSchema.template(1, H.NOW)
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			Mastery.recordRetry(p, horse)
			expect(p.chars["马"].warm).to.equal(2)
			expect(p.chars["马"].asked).to.equal(3)
		end)
	end)

	describe("MASTERED credential", function()
		it("requires two mode classes AND two distinct days", function()
			local p = ProfileSchema.template(1, H.NOW)
			-- same day, two classes: not mastered
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			Mastery.recordClean(p, horse, "char-picture", DAY1)
			expect(Mastery.isMastered(p, "马")).to.equal(false)
			-- second day, but a class already seen: NOW it's two classes x two days
			local newly = Mastery.recordClean(p, horse, "listen-char", DAY2)
			expect(newly).to.equal(true)
			expect(Mastery.isMastered(p, "马")).to.equal(true)
		end)

		it("two days in ONE class is not enough for a multi-class item", function()
			local p = ProfileSchema.template(1, H.NOW)
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			Mastery.recordClean(p, horse, "listen-char", DAY2)
			expect(Mastery.isMastered(p, "马")).to.equal(false)
		end)

		it("both picture directions count as ONE class", function()
			local p = ProfileSchema.template(1, H.NOW)
			Mastery.recordClean(p, horse, "char-picture", DAY1)
			Mastery.recordClean(p, horse, "picture-char", DAY2)
			expect(Mastery.isMastered(p, "马")).to.equal(false)
		end)

		it("grammar words master on two distinct days in pinyin mode", function()
			local p = ProfileSchema.template(1, H.NOW)
			Mastery.recordClean(p, grammarWord, "char-pinyin", DAY1)
			expect(Mastery.isMastered(p, grammarWord.text)).to.equal(false)
			Mastery.recordClean(p, grammarWord, "char-pinyin", DAY2)
			expect(Mastery.isMastered(p, grammarWord.text)).to.equal(true)
		end)

		it("misses never revoke MASTERED", function()
			local p = ProfileSchema.template(1, H.NOW)
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			Mastery.recordClean(p, horse, "char-picture", DAY2)
			expect(Mastery.isMastered(p, "马")).to.equal(true)
			Mastery.recordMiss(p, horse)
			expect(Mastery.isMastered(p, "马")).to.equal(true) -- credential sticks
			expect(p.chars["马"].warm).to.equal(0) -- pacing tier resets
		end)
	end)

	describe("working-set expansion", function()
		it("grows by 8 while fewer than 16 fresh items are in play", function()
			local p = ProfileSchema.template(1, H.NOW)
			local deck = Deck.ordered(H.items, p.seed)
			local manifests = H.fullManifests()
			expect(p.unlocked).to.equal(8)
			Mastery.expandWorkingSet(p, deck, manifests)
			expect(p.unlocked).to.equal(16) -- 8 fresh < 16 → one growth step

			-- warm the first 10: fresh drops to 6, and the loop grows until
			-- fresh >= 16 again (web behavior): 16 -> 24 (fresh 14) -> 32 (fresh 22)
			for i = 1, 10 do
				local item = deck[i]
				for _ = 1, 3 do
					Mastery.recordClean(p, item, "listen-char", DAY1)
				end
			end
			Mastery.expandWorkingSet(p, deck, manifests)
			expect(p.unlocked).to.equal(32)
		end)

		it("does not chase the horizon when everything is deferred", function()
			local p = ProfileSchema.template(1, H.NOW)
			local deck = Deck.ordered(H.items, p.seed)
			Mastery.expandWorkingSet(p, deck, H.emptyManifests())
			expect(p.unlocked).to.equal(8) -- no eligible items -> no growth
		end)
	end)

	describe("progress screen data", function()
		it("counts mastered per band over exactly 700 curriculum items", function()
			local p = ProfileSchema.template(1, H.NOW)
			Mastery.recordClean(p, horse, "listen-char", DAY1)
			Mastery.recordClean(p, horse, "char-picture", DAY2)
			local progress = Mastery.progress(p, H.items)
			expect(progress.of).to.equal(700)
			expect(progress.total).to.equal(1)
			local sum = 0
			for _, band in progress.bands do
				sum += band.of
			end
			expect(sum).to.equal(700) -- bonus items excluded
			expect(progress.deferredByToggle > 0).to.equal(true) -- grammar words wait on the toggle
		end)
	end)
end
