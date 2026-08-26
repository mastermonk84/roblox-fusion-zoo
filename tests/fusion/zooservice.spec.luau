--!strict
-- ZooService rules headless: rescue gating (criterion 1), fusion without
-- funds/unlock rejected (criterion 3), feed persistence, naming from mastered
-- chars only, real-word payout exactly once.

local T = require("../testkit")
local H = require("../quiz/helpers")
local Profiles = require("../../src/server/Services/Profiles")
local ZooService = require("../../src/server/Services/ZooService")
local Analytics = require("../../src/server/Services/Analytics")
local Mastery = require("../../src/shared/Quiz/Mastery")
local MockBackend = require("../profile/mockbackend")
local Types = require("../../src/shared/Types")
local describe, it, expect = T.describe, T.it, T.expect

local USER = 555

local function findItem(text: string): Types.QuizItem
	for _, item in H.items do
		if item.text == text then
			return item
		end
	end
	error(`no item {text}`)
end

local function master(profile: any, char: string)
	local item = findItem(char)
	Mastery.recordClean(profile, item, "listen-char", "2026-08-25")
	Mastery.recordClean(profile, item, "char-picture", "2026-08-26")
	assert(Mastery.isMastered(profile, char), `failed to master {char}`)
end

local function setup()
	local backend = MockBackend.new()
	local profiles = Profiles.new(backend :: any)
	local zoo = ZooService.new({
		profiles = profiles,
		analytics = Analytics.new(function()
			return H.NOW
		end),
		now = function()
			return H.NOW
		end,
	})
	local profile = profiles:load(USER, 42, H.NOW)
	assert(profile, "no profile")
	return zoo, profile
end

return function()
	describe("rescue gating (criterion 1)", function()
		it("blocks rescue of an unmastered character", function()
			local zoo, profile = setup()
			profile.coins = 100
			local result = (zoo :: any):rescue(USER, "马")
			expect(result.ok).to.equal(false)
			expect(result.err).to.equal("character_not_mastered")
			expect(profile.coins).to.equal(100) -- nothing charged
		end)

		it("allows rescue once MASTERED and funded, at the tier price", function()
			local zoo, profile = setup()
			profile.coins = 100
			master(profile, "马") -- 马 is tier 3 → 12🪙
			local result = (zoo :: any):rescue(USER, "马")
			expect(result.ok).to.equal(true)
			expect(profile.coins).to.equal(88)
			expect(profile.animals["马"]).to.equal(true)
			-- owning it twice is refused
			expect((zoo :: any):rescue(USER, "马").err).to.equal("already_owned")
		end)

		it("refuses a mastered rescue without funds", function()
			local zoo, profile = setup()
			profile.coins = 3
			master(profile, "马")
			local result = (zoo :: any):rescue(USER, "马")
			expect(result.ok).to.equal(false)
			expect(result.err).to.equal("not_enough_coins")
		end)
	end)

	describe("fusion (criteria 3 + 4 groundwork)", function()
		it("fuses two owned animals into a 2-part beast for 10🪙", function()
			local zoo, profile = setup()
			profile.coins = 50
			profile.animals["马"] = true
			profile.animals["蛙"] = true
			local result = (zoo :: any):fuse(USER, { head = "马", body = "蛙" })
			expect(result.ok).to.equal(true)
			expect(profile.coins).to.equal(40)
			expect(result.beast.stats.zhi).to.equal(1) -- 马-head 智
			expect(result.beast.stats.su).to.equal(3) -- 蛙 legs-default 速
			expect(profile.activeBeastId).to.equal(result.beast.id)
		end)

		it("rejects fusion with unowned animals or missing funds", function()
			local zoo, profile = setup()
			profile.coins = 50
			profile.animals["马"] = true
			expect((zoo :: any):fuse(USER, { head = "马", body = "蛙" }).err).to.equal(
				"animal_not_owned"
			)
			profile.animals["蛙"] = true
			profile.coins = 9
			expect((zoo :: any):fuse(USER, { head = "马", body = "蛙" }).err).to.equal(
				"not_enough_coins"
			)
		end)

		it("blocks legs/tail in a re-fuse until the slot is unlocked", function()
			local zoo, profile = setup()
			profile.coins = 100
			for _, char in { "马", "蛙", "兔" } do
				profile.animals[char] = true
			end
			local fused = (zoo :: any):fuse(USER, { head = "马", body = "蛙" })
			local blocked = (zoo :: any):refuse(USER, {
				beastId = fused.beast.id,
				head = "马",
				body = "蛙",
				legs = "兔",
			})
			expect(blocked.err).to.equal("legs_slot_locked")

			-- rung gate on the unlock itself
			expect((zoo :: any):unlockSlot(USER, "legs").err).to.equal("rung_too_low")
			profile.ladderRung = 4
			expect((zoo :: any):unlockSlot(USER, "legs").ok).to.equal(true)
			local allowed = (zoo :: any):refuse(USER, {
				beastId = fused.beast.id,
				head = "马",
				body = "蛙",
				legs = "兔",
			})
			expect(allowed.ok).to.equal(true)
			expect(allowed.beast.stats.su).to.equal(4) -- 兔 legs
		end)

		it("preserves slot feed across a re-fuse swap", function()
			local zoo, profile = setup()
			profile.coins = 200
			for _, char in { "马", "蛙", "猫" } do
				profile.animals[char] = true
			end
			local fused = (zoo :: any):fuse(USER, { head = "马", body = "蛙" })
			for _ = 1, 3 do
				local fed = (zoo :: any):feedSlot(USER, { beastId = fused.beast.id, slot = "head" })
				expect(fed.ok).to.equal(true)
			end
			local swapped = (zoo :: any):refuse(
				USER,
				{ beastId = fused.beast.id, head = "猫", body = "蛙" }
			)
			expect(swapped.ok).to.equal(true)
			expect(swapped.beast.feed.head).to.equal(3) -- feed stays on the SLOT
			expect(swapped.beast.stats.zhi).to.equal(5) -- 猫.zhi 2 + 3
		end)

		it("charges the scaling feed curve and stops at max", function()
			local zoo, profile = setup()
			profile.coins = 1000
			profile.animals["马"] = true
			profile.animals["蛙"] = true
			local fused = (zoo :: any):fuse(USER, { head = "马", body = "蛙" })
			local before = profile.coins
			local total = 0
			for expectedCost = 1, 10 do
				local fed = (zoo :: any):feedSlot(USER, { beastId = fused.beast.id, slot = "head" })
				expect(fed.ok).to.equal(true)
				total += expectedCost
			end
			expect(before - profile.coins).to.equal(55) -- 0→10 cumulative
			expect((zoo :: any):feedSlot(USER, { beastId = fused.beast.id, slot = "head" }).err).to.equal(
				"slot_maxed"
			)
			expect(total).to.equal(55)
		end)
	end)

	describe("real words", function()
		it("pays the 5🪙 discovery once, keeps golden on rebuilds", function()
			local zoo, profile = setup()
			profile.coins = 100
			profile.animals["熊"] = true
			profile.animals["猫"] = true
			local first = (zoo :: any):fuse(USER, { head = "熊", body = "猫" })
			expect(first.beast.golden).to.equal(true)
			expect(#first.realWords).to.equal(1)
			expect(first.realWords[1].word).to.equal("熊猫")
			-- second 熊猫 build: still golden, no second payout
			local second = (zoo :: any):fuse(USER, { head = "猫", body = "熊" })
			expect(second.beast.golden).to.equal(true)
			expect(#second.realWords).to.equal(0)
		end)
	end)

	describe("naming (no free text ever)", function()
		it("only accepts two MASTERED characters", function()
			local zoo, profile = setup()
			profile.coins = 100
			profile.animals["马"] = true
			profile.animals["蛙"] = true
			local fused = (zoo :: any):fuse(USER, { head = "马", body = "蛙" })
			local denied = (zoo :: any):nameBeast(
				USER,
				{ beastId = fused.beast.id, chars = { "马", "蛙" } }
			)
			expect(denied.err).to.equal("character_not_mastered")
			master(profile, "马")
			master(profile, "蛙")
			local named = (zoo :: any):nameBeast(
				USER,
				{ beastId = fused.beast.id, chars = { "马", "蛙" } }
			)
			expect(named.ok).to.equal(true)
			expect(named.name).to.equal("马蛙")
		end)
	end)

	describe("decorations", function()
		it("cannot place more than owned", function()
			local zoo, profile = setup()
			profile.coins = 20
			local bought = (zoo :: any):buyDecoration(USER, "flower_pot")
			expect(bought.ok).to.equal(true)
			expect((zoo :: any):placeDecoration(USER, { itemId = "flower_pot", gridIndex = 1 }).ok).to.equal(
				true
			)
			expect((zoo :: any):placeDecoration(USER, { itemId = "flower_pot", gridIndex = 2 }).err).to.equal(
				"not_owned"
			)
		end)
	end)
end
