--!strict
-- Criterion 1 (fusion): slot-stat math (innate + feed, cap), tail splash,
-- feed persistence across slot swaps, real-word detection anywhere in the
-- build (both orders), feed cost curve.

local T = require("../testkit")
local SlotStats = require("../../src/shared/Fusion/SlotStats")
local RealWords = require("../../src/shared/Fusion/RealWords")
local FeedCurve = require("../../src/shared/Fusion/FeedCurve")
local Animals = require("../../src/shared/Data/Animals")
local Types = require("../../src/shared/Types")
local describe, it, expect = T.describe, T.it, T.expect

local INDEX = SlotStats.index(Animals :: { Types.AnimalDef })

local function beast(slots: any, feed: any?): Types.Beast
	return {
		id = "b1",
		name = nil,
		slots = slots,
		feed = feed or { head = 0, body = 0, legs = 0, tail = 0 },
		golden = false,
		colorway = nil,
		createdAt = 0,
	}
end

-- innate references (from animals.json): 马 2/4/1 · 蛙 1/3/1 · 熊 4/1/2 ·
-- 猫 1/3/2 · 龙 3/3/3 · 兔 1/4/1

return function()
	describe("slot-stat resolution", function()
		it("BODY→力, HEAD→智, LEGS defaults to the body animal's 速", function()
			-- 马-head on 蛙-body: li = 蛙.li 1, su = 蛙.su 3 (legs default), zhi = 马.zhi 1
			local stats = SlotStats.resolve(beast({ head = "马", body = "蛙" }), INDEX)
			expect(stats.li).to.equal(1)
			expect(stats.su).to.equal(3)
			expect(stats.zhi).to.equal(1)
		end)

		it("order matters: 马-head/蛙-body ≠ 蛙-head/马-body", function()
			local a = SlotStats.resolve(beast({ head = "马", body = "蛙" }), INDEX)
			local b = SlotStats.resolve(beast({ head = "蛙", body = "马" }), INDEX)
			-- b: li = 马.li 2, su = 马.su 4, zhi = 蛙.zhi 1
			expect(b.li).to.equal(2)
			expect(b.su).to.equal(4)
			expect(T.deepEqual(a, b)).to.equal(false)
		end)

		it("adds slot feed to the occupant's innate contribution, capped at 10", function()
			local stats = SlotStats.resolve(
				beast({ head = "马", body = "熊" }, { head = 3, body = 8, legs = 0, tail = 0 }),
				INDEX
			)
			expect(stats.li).to.equal(10) -- 熊.li 4 + 8 = 12 → cap 10
			expect(stats.zhi).to.equal(4) -- 马.zhi 1 + 3
		end)

		it("a dedicated LEGS occupant overrides the body default", function()
			local stats = SlotStats.resolve(
				beast(
					{ head = "熊", body = "熊", legs = "兔" },
					{ head = 0, body = 0, legs = 2, tail = 0 }
				),
				INDEX
			)
			expect(stats.su).to.equal(6) -- 兔.su 4 + feed 2 (vs 熊.su 1)
		end)
	end)

	describe("tail splash", function()
		it("adds +1 to the tail animal's naturally-highest stat at feed 0", function()
			-- tail 兔: natural best is su (4). Base su from 蛙 legs-default = 3.
			local stats =
				SlotStats.resolve(beast({ head = "马", body = "蛙", tail = "兔" }), INDEX)
			expect(stats.su).to.equal(4) -- 3 + splash 1
		end)

		it("grows with tail feed: 1 + floor(feed/3)", function()
			expect(SlotStats.tailSplash(0)).to.equal(1)
			expect(SlotStats.tailSplash(2)).to.equal(1)
			expect(SlotStats.tailSplash(3)).to.equal(2)
			expect(SlotStats.tailSplash(9)).to.equal(4)
			local stats = SlotStats.resolve(
				beast(
					{ head = "马", body = "蛙", tail = "兔" },
					{ head = 0, body = 0, legs = 0, tail = 9 }
				),
				INDEX
			)
			expect(stats.su).to.equal(7) -- 3 + splash 4
		end)

		it("tie-breaks 力 > 速 > 智 for the natural best", function()
			-- 龙 3/3/3 → best is li by tie-break
			expect(SlotStats.naturalBest(INDEX["龙"])).to.equal("li")
			local stats =
				SlotStats.resolve(beast({ head = "马", body = "蛙", tail = "龙" }), INDEX)
			expect(stats.li).to.equal(2) -- 蛙.li 1 + splash 1
		end)
	end)

	describe("feed persistence across swaps (the no-punish rule)", function()
		it("keeps slot feed when the occupant changes", function()
			local b = beast(
				{ head = "马", body = "蛙" },
				{ head = 5, body = 2, legs = 0, tail = 0 }
			)
			local before = SlotStats.resolve(b, INDEX)
			expect(before.zhi).to.equal(6) -- 马.zhi 1 + 5

			b.slots.head = "猫" -- re-fuse: swap the head, feed stays on the SLOT
			local after = SlotStats.resolve(b, INDEX)
			expect(after.zhi).to.equal(7) -- 猫.zhi 2 + the same 5 feed
			expect(b.feed.head).to.equal(5)
		end)
	end)

	describe("real words anywhere in the build", function()
		it("detects 熊+猫 in any two slots, either arrangement", function()
			for _, slots in
				{
					{ head = "熊", body = "猫" },
					{ head = "猫", body = "熊" },
					{ head = "马", body = "熊", legs = "猫" },
					{ head = "猫", body = "蛙", tail = "熊" },
				}
			do
				local matches = RealWords.matches(beast(slots))
				local hasPanda = false
				for _, word in matches do
					if word.word == "熊猫" then
						hasPanda = true
					end
				end
				expect(hasPanda).to.equal(true)
			end
		end)

		it("finds nothing in a wordless build", function()
			expect(#RealWords.matches(beast({ head = "马", body = "蛙" }))).to.equal(0)
		end)

		it("can hold multiple words in a 4-slot build", function()
			-- 龙+虾 (龙虾) and 熊+猫 (熊猫) in one chimera
			local matches =
				RealWords.matches(beast({ head = "龙", body = "虾", legs = "熊", tail = "猫" }))
			expect(#matches >= 2).to.equal(true)
		end)
	end)

	describe("feed cost curve", function()
		it("costs n to reach level n; 0→10 totals 55", function()
			expect(FeedCurve.costToNext(0)).to.equal(1)
			expect(FeedCurve.costToNext(5)).to.equal(6)
			expect(FeedCurve.costToNext(9)).to.equal(10)
			expect(FeedCurve.costToNext(10)).to.equal(nil) -- maxed
			expect(FeedCurve.cumulative(10)).to.equal(55)
			expect(FeedCurve.cumulative(10) * 4).to.equal(220) -- 4-slot lifetime sink
		end)
	end)
end
