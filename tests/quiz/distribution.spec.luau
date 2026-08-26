--!strict
-- Acceptance criterion 1 (quiz): mode mix per level within ±5% over 1000
-- draws; numbers under-sampled 4x; homophone rule never violated across
-- 10,000 generated listen questions. Criterion 9: manifest degradation.

local T = require("../testkit")
local H = require("./helpers")
local Deck = require("../../src/shared/Quiz/Deck")
local Generator = require("../../src/shared/Quiz/Generator")
local Sampler = require("../../src/shared/Quiz/Sampler")
local Rng = require("../../src/shared/Util/Rng")
local describe, it, expect = T.describe, T.it, T.expect

local function makeView(level: number, pinyinOn: boolean, manifests: any, unlocked: number)
	local deck = Deck.ordered(H.items, 424242)
	return {
		allItems = H.items,
		workingSet = Deck.workingSet(deck, unlocked),
		states = {},
		level = level,
		pinyinOn = pinyinOn,
		manifests = manifests,
	},
		deck
end

local function drawModes(view: any, n: number, seed: number): { [string]: number }
	local rand = Rng.mulberry32(seed)
	local counts: { [string]: number } = {}
	for _ = 1, n do
		local q = Generator.generate(view, {}, rand)
		assert(q, "generator returned nil with full manifests")
		counts[q.mode] = (counts[q.mode] or 0) + 1
	end
	return counts
end

local function share(counts: { [string]: number }, mode: string, n: number): number
	return (counts[mode] or 0) / n
end

return function()
	describe("mode mix (±5% over 1000 draws, full manifests)", function()
		it("level 1 is 100% listen", function()
			local view = makeView(1, false, H.fullManifests(), 50)
			local counts = drawModes(view, 1000, 1)
			expect(share(counts, "listen-char", 1000)).to.equal(1)
		end)

		it("level 2 is 60/40 listen/char→picture", function()
			local view = makeView(2, false, H.fullManifests(), 50)
			local counts = drawModes(view, 1000, 2)
			expect(math.abs(share(counts, "listen-char", 1000) - 0.6) < 0.05).to.equal(true)
			expect(math.abs(share(counts, "char-picture", 1000) - 0.4) < 0.05).to.equal(true)
		end)

		it("level 3+ is 50/20/30", function()
			for _, level in { 3, 4, 5 } do
				local view = makeView(level, false, H.fullManifests(), 80)
				local counts = drawModes(view, 1000, 100 + level)
				expect(math.abs(share(counts, "listen-char", 1000) - 0.5) < 0.05).to.equal(true)
				expect(math.abs(share(counts, "char-picture", 1000) - 0.2) < 0.05).to.equal(true)
				expect(math.abs(share(counts, "picture-char", 1000) - 0.3) < 0.05).to.equal(true)
			end
		end)

		it("pinyin-on at level 4 shifts to 5/2/3/3 thirteenths", function()
			local view = makeView(4, true, H.fullManifests(), 80)
			local counts = drawModes(view, 1300, 7)
			expect(math.abs(share(counts, "listen-char", 1300) - 5 / 13) < 0.05).to.equal(true)
			expect(math.abs(share(counts, "char-pinyin", 1300) - 3 / 13) < 0.05).to.equal(true)
		end)

		it("pinyin stays off below level 4 even when toggled on", function()
			local view = makeView(3, true, H.fullManifests(), 80)
			local counts = drawModes(view, 1000, 8)
			expect(counts["char-pinyin"]).to.equal(nil)
		end)
	end)

	describe("number under-sampling (4x)", function()
		it("samples number items at ~0.25 relative weight", function()
			local deck = Deck.ordered(H.items, 424242)
			local workingSet = Deck.workingSet(deck, 50) -- band 1: all ten numbers present
			local manifests = H.fullManifests()
			local pool = Sampler.pool(workingSet, "listen-char", manifests, false)

			local expectedTotal = 0
			for _, item in pool do
				expectedTotal += if item.category == "number" then 0.25 else 1
			end
			local expectedNumberShare = 0
			for _, item in pool do
				if item.category == "number" then
					expectedNumberShare += 0.25 / expectedTotal
				end
			end
			assert(expectedNumberShare > 0, "band 1 must contain numbers")

			local rand = Rng.mulberry32(99)
			local hits = 0
			local draws = 20000
			for _ = 1, draws do
				local target = Sampler.pickTarget(pool, {}, {}, rand)
				assert(target, "pickTarget nil")
				if target.category == "number" then
					hits += 1
				end
			end
			local observed = hits / draws
			expect(math.abs(observed - expectedNumberShare) < 0.02).to.equal(true)
		end)
	end)

	describe("homophone hard rule (10,000 listen questions)", function()
		it("never offers a distractor sharing the target's exact pinyin", function()
			local view = makeView(1, false, H.fullManifests(), 700)
			local rand = Rng.mulberry32(1234)
			for _ = 1, 10000 do
				local q = Generator.generate(view, {}, rand)
				assert(q, "generator returned nil")
				expect(q.mode).to.equal("listen-char")
				for index, choice in q.choices do
					if index ~= q.correctIndex then
						expect(choice.pinyin == q.item.pinyin).to.equal(false)
					end
				end
			end
		end)
	end)

	describe("criterion 9: manifest degradation", function()
		it("empty audio manifest → zero listen questions, zero errors", function()
			local manifests = H.emptyManifests()
			-- icons only: picture modes carry the game
			for _, item in H.items do
				if item.needs_visual then
					manifests.icons[item.text] = `rbxassetid://2{item.seq}`
				end
			end
			local view = makeView(1, false, manifests, 100)
			local rand = Rng.mulberry32(5)
			for _ = 1, 500 do
				local q = Generator.generate(view, {}, rand)
				assert(q, "should degrade to picture modes, not nil")
				expect(q.mode == "listen-char").to.equal(false)
			end
		end)

		it("partial manifest → listen questions only for covered items", function()
			local manifests = H.partialManifests(2) -- audio for bands 1-2 only
			local view = makeView(3, false, manifests, 700)
			local rand = Rng.mulberry32(6)
			for _ = 1, 2000 do
				local q = Generator.generate(view, {}, rand)
				assert(q, "generator returned nil")
				if q.mode == "listen-char" then
					expect(q.item.band <= 2).to.equal(true)
				end
			end
		end)

		it("nothing eligible at all → nil, never an error", function()
			local view = makeView(1, false, H.emptyManifests(), 50)
			local rand = Rng.mulberry32(7)
			expect(Generator.generate(view, {}, rand)).to.equal(nil)
		end)
	end)

	describe("choice hygiene", function()
		it("always three choices with unique display keys and one correct", function()
			local view = makeView(3, true, H.fullManifests(), 300)
			local rand = Rng.mulberry32(31337)
			local Distractors = require("../../src/shared/Quiz/Distractors")
			for _ = 1, 2000 do
				local q = Generator.generate(view, {}, rand)
				assert(q, "generator returned nil")
				expect(#q.choices).to.equal(3)
				expect(q.choices[q.correctIndex].text).to.equal(q.item.text)
				local keys: { [string]: boolean } = {}
				for _, choice in q.choices do
					local key = Distractors.displayKey(choice, q.mode, view.manifests)
					expect(keys[key]).to.equal(nil)
					keys[key] = true
				end
			end
		end)

		it("respects the repeat-avoidance ring", function()
			local view = makeView(1, false, H.fullManifests(), 50)
			local rand = Rng.mulberry32(55)
			local recent: { string } = {}
			for _ = 1, 300 do
				local q = Generator.generate(view, recent, rand)
				assert(q, "generator returned nil")
				-- the ring guarantees the target isn't among the last few asked
				for i = math.max(1, #recent - 3), #recent do
					expect(q.item.text == recent[i]).to.equal(false)
				end
				table.insert(recent, q.item.text)
				if #recent > 12 then
					table.remove(recent, 1)
				end
			end
		end)
	end)
end
