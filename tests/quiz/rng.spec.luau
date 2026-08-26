--!strict
local T = require("../testkit")
local Rng = require("../../src/shared/Util/Rng")
local describe, it, expect = T.describe, T.it, T.expect

return function()
	describe("mulberry32", function()
		it("reproduces the exact JS sequence for seed 42", function()
			local r = Rng.mulberry32(42)
			-- Reference values from the JS implementation (verified in CI setup)
			expect(r()).to.be.near(0.6011037519201636, 1e-15)
			expect(r()).to.be.near(0.44829055899754167, 1e-15)
		end)
		it("is deterministic per seed", function()
			local a, b = Rng.mulberry32(123456789), Rng.mulberry32(123456789)
			for _ = 1, 100 do
				expect(a()).to.equal(b())
			end
		end)
		it("stays in [0, 1)", function()
			local r = Rng.mulberry32(999999999)
			for _ = 1, 1000 do
				local v = r()
				expect(v >= 0 and v < 1).to.equal(true)
			end
		end)
	end)

	describe("seededShuffle", function()
		it("is a permutation and deterministic", function()
			local items = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
			local a = Rng.seededShuffle(items, Rng.mulberry32(7))
			local b = Rng.seededShuffle(items, Rng.mulberry32(7))
			expect(T.deepEqual(a, b)).to.equal(true)
			table.sort(a)
			expect(T.deepEqual(a, items)).to.equal(true)
		end)
		it("does not mutate its input", function()
			local items = { "a", "b", "c" }
			Rng.seededShuffle(items, Rng.mulberry32(1))
			expect(T.deepEqual(items, { "a", "b", "c" })).to.equal(true)
		end)
	end)

	describe("weightedPick", function()
		it("respects zero weights", function()
			local r = Rng.mulberry32(5)
			for _ = 1, 200 do
				local picked = Rng.weightedPick({
					{ item = "never", weight = 0 },
					{ item = "always", weight = 1 },
				}, r)
				expect(picked).to.equal("always")
			end
		end)
		it("approximates 4x under-sampling at weight 0.25", function()
			local r = Rng.mulberry32(11)
			local counts = { a = 0, b = 0 }
			for _ = 1, 10000 do
				local picked = Rng.weightedPick({
					{ item = "a", weight = 1 },
					{ item = "b", weight = 0.25 },
				}, r)
				counts[picked] += 1
			end
			local ratio = counts.a / counts.b
			expect(ratio > 3.5 and ratio < 4.6).to.equal(true)
		end)
	end)
end
