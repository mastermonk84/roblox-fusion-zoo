--!strict
-- The leveling state machine: {3,4,6,8,8} ramp, retry resets the streak, four
-- misses drop a level (never below 1), +8 unlocked per level-up.

local T = require("../testkit")
local Leveling = require("../../src/shared/Quiz/Leveling")
local ProfileSchema = require("../../src/shared/ProfileSchema")
local describe, it, expect = T.describe, T.it, T.expect

local NOW = 1787748347
local DECK = 705

local function fresh()
	return ProfileSchema.template(1, NOW)
end

return function()
	describe("level up", function()
		it("takes 3 clean solves at level 1 (accelerated placement)", function()
			local p = fresh()
			Leveling.apply(p, "clean", DECK)
			Leveling.apply(p, "clean", DECK)
			expect(p.level).to.equal(1)
			local events = Leveling.apply(p, "clean", DECK)
			expect(events.levelUp).to.equal(true)
			expect(p.level).to.equal(2)
			expect(p.cleanStreak).to.equal(0)
			expect(p.unlocked).to.equal(8 + 8)
		end)

		it("takes 4 at level 2, 6 at level 3, 8 at level 4", function()
			local p = fresh()
			local needed = { 3, 4, 6, 8 }
			for level = 1, 4 do
				expect(p.level).to.equal(level)
				for _ = 1, needed[level] do
					Leveling.apply(p, "clean", DECK)
				end
				expect(p.level).to.equal(level + 1)
			end
		end)

		it("caps at level 5 and wraps the streak there", function()
			local p = fresh()
			p.level = 5
			for _ = 1, 8 do
				Leveling.apply(p, "clean", DECK)
			end
			expect(p.level).to.equal(5)
			expect(p.cleanStreak).to.equal(0) -- wrapped at the threshold
		end)
	end)

	describe("retry", function()
		it("resets the clean streak without dropping the level", function()
			local p = fresh()
			Leveling.apply(p, "clean", DECK)
			Leveling.apply(p, "clean", DECK)
			expect(p.cleanStreak).to.equal(2)
			Leveling.apply(p, "retry", DECK)
			expect(p.cleanStreak).to.equal(0)
			expect(p.level).to.equal(1)
			expect(p.missStreak).to.equal(0)
		end)
	end)

	describe("level down", function()
		it("drops after 4 misses, never below level 1", function()
			local p = fresh()
			p.level = 3
			for _ = 1, 3 do
				Leveling.apply(p, "miss", DECK)
			end
			expect(p.level).to.equal(3)
			local events = Leveling.apply(p, "miss", DECK)
			expect(events.levelDown).to.equal(true)
			expect(p.level).to.equal(2)
			expect(p.missStreak).to.equal(0) -- counter resets on the drop

			p.level = 1
			for _ = 1, 12 do
				Leveling.apply(p, "miss", DECK)
			end
			expect(p.level).to.equal(1)
		end)

		it("clean answers break the miss streak", function()
			local p = fresh()
			p.level = 2
			Leveling.apply(p, "miss", DECK)
			Leveling.apply(p, "miss", DECK)
			Leveling.apply(p, "miss", DECK)
			Leveling.apply(p, "clean", DECK)
			expect(p.missStreak).to.equal(0)
			Leveling.apply(p, "miss", DECK)
			expect(p.level).to.equal(2) -- streak restarted, no drop
		end)
	end)

	describe("unlocked growth", function()
		it("caps unlocked at the deck size", function()
			local p = fresh()
			p.level = 4
			p.unlocked = DECK - 2
			for _ = 1, 8 do
				Leveling.apply(p, "clean", DECK)
			end
			expect(p.unlocked).to.equal(DECK)
		end)
	end)
end
