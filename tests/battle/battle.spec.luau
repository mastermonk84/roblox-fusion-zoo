--!strict
-- Criterion 1 (battle): charge × triangle truth table, tie replay + stall
-- breaker, NPC charge curve; criterion 3: rung gating, no client-computed
-- results, flash forgeries; plus the scripted sim proving rung 1 is beatable
-- by a starter 2-part beast.

local T = require("../testkit")
local H = require("../quiz/helpers")
local Resolver = require("../../src/shared/Battle/Resolver")
local NpcBrain = require("../../src/shared/Battle/NpcBrain")
local GhostBrain = require("../../src/shared/Battle/GhostBrain")
local BattleService = require("../../src/server/Services/BattleService")
local QuizService = require("../../src/server/Services/QuizService")
local Profiles = require("../../src/server/Services/Profiles")
local Analytics = require("../../src/server/Services/Analytics")
local MockBackend = require("../profile/mockbackend")
local Rng = require("../../src/shared/Util/Rng")
local describe, it, expect = T.describe, T.it, T.expect

local USER = 888

local function setup(seed: number?)
	local clock = { now = H.NOW }
	local backend = MockBackend.new()
	local profiles = Profiles.new(backend :: any)
	local analytics = Analytics.new(function()
		return clock.now
	end)
	local nowFn = function()
		return clock.now
	end
	local quiz = QuizService.new({
		profiles = profiles,
		analytics = analytics,
		now = nowFn,
		manifests = H.fullManifests(),
	})
	local battle = BattleService.new({
		profiles = profiles,
		quiz = quiz,
		analytics = analytics,
		now = nowFn,
		rand = Rng.mulberry32(seed or 7),
	})
	local profile = profiles:load(USER, 42, clock.now)
	assert(profile, "no profile")
	-- give the player a starter 2-part beast: 猫-head on 鸟-body (tutorial pair)
	profile.animals["猫"] = true
	profile.animals["鸟"] = true
	profile.beasts["b1"] = {
		id = "b1",
		name = nil,
		slots = { head = "猫", body = "鸟", legs = nil, tail = nil },
		feed = { head = 0, body = 0, legs = 0, tail = 0 },
		golden = false,
		colorway = nil,
		createdAt = clock.now,
	}
	profile.activeBeastId = "b1"
	return battle, quiz, profile, clock
end

-- Drive one round: pick, answer the flash correctly with probability
-- `accuracy`, resolve. Returns the resolve response.
local function playRound(
	battle: any,
	quiz: any,
	clock: any,
	stat: string,
	answerCorrectly: boolean,
	battleId: string,
	round: number
): any
	local picked = battle:pickStat(USER, { battleId = battleId, round = round, stat = stat })
	assert(picked.ok, `pick failed: {picked.err}`)
	if picked.flash and answerCorrectly then
		local pending = (quiz :: any)._pendingFlash[USER]
		local flashResult = battle:submitFlash(USER, {
			battleId = battleId,
			questionId = picked.flash.questionId,
			choiceIndex = pending.question.correctIndex,
		})
		assert(flashResult.ok, "flash submit failed")
	else
		clock.now += 5 -- let the deadline lapse: uncharged
	end
	local resolved = battle:resolveRound(USER, { battleId = battleId })
	assert(resolved.ok, `resolve failed: {resolved.err}`)
	return resolved
end

return function()
	describe("resolver truth table (charge × triangle)", function()
		it("doubles only when advantaged AND charged", function()
			-- 速 beats 力
			local both = Resolver.resolveRound(
				{ stat = "su", value = 4, charged = true },
				{ stat = "li", value = 6, charged = true }
			)
			expect(both.a.doubled).to.equal(true)
			expect(both.a.eff).to.equal(8)
			expect(both.a.mathString).to.equal("速 4 ×2 = 8")
			expect(both.winner).to.equal("a")

			-- advantaged but UNCHARGED: never doubles
			local uncharged = Resolver.resolveRound(
				{ stat = "su", value = 4, charged = false },
				{ stat = "li", value = 6, charged = true }
			)
			expect(uncharged.a.doubled).to.equal(false)
			expect(uncharged.a.eff).to.equal(4)
			expect(uncharged.winner).to.equal("b")

			-- charged but NOT advantaged: never doubles
			local unadvantaged = Resolver.resolveRound(
				{ stat = "li", value = 4, charged = true },
				{ stat = "su", value = 3, charged = false }
			)
			expect(unadvantaged.a.doubled).to.equal(false)
			-- b is advantaged (su beats li) but uncharged: 3 vs 4 → a wins
			expect(unadvantaged.winner).to.equal("a")
		end)

		it("same stat on both sides never doubles either", function()
			local result = Resolver.resolveRound(
				{ stat = "li", value = 5, charged = true },
				{ stat = "li", value = 5, charged = true }
			)
			expect(result.a.doubled).to.equal(false)
			expect(result.b.doubled).to.equal(false)
			expect(result.winner).to.equal("tie")
		end)

		it("mutual advantage is impossible on the 3-cycle", function()
			for _, pair in { { "li", "zhi" }, { "zhi", "su" }, { "su", "li" } } do
				local result = Resolver.resolveRound(
					{ stat = pair[1] :: any, value = 5, charged = true },
					{ stat = pair[2] :: any, value = 5, charged = true }
				)
				expect(result.a.doubled and result.b.doubled).to.equal(false)
				expect(result.a.doubled or result.b.doubled).to.equal(true)
			end
		end)
	end)

	describe("NPC brain", function()
		it("charge probability rises 0.3 → 0.8 across the 12 rungs", function()
			expect(NpcBrain.chargeProbability(1)).to.be.near(0.3)
			expect(NpcBrain.chargeProbability(12)).to.be.near(0.8)
			local last = 0
			for rung = 1, 12 do
				local p = NpcBrain.chargeProbability(rung)
				expect(p >= last).to.equal(true)
				last = p
			end
		end)
	end)

	describe("ghost brain", function()
		it("clamps charge to the owner's accuracy in 0.2–0.9", function()
			local function snap(accuracy: number): any
				return {
					ownerUserId = 1,
					ownerDisplayName = "x",
					slots = { head = "猫", body = "鸟" },
					feed = { head = 0, body = 0, legs = 0, tail = 0 },
					golden = false,
					stats = { li = 1, su = 3, zhi = 2 },
					pickHistogram = { li = 1, su = 1, zhi = 1 },
					accuracy = accuracy,
					publishedAt = 0,
				}
			end
			expect(GhostBrain.chargeProbability(snap(0.05))).to.be.near(0.2)
			expect(GhostBrain.chargeProbability(snap(0.99))).to.be.near(0.9)
			expect(GhostBrain.chargeProbability(snap(0.66))).to.be.near(0.66)
		end)
	end)

	describe("battle service (criterion 3)", function()
		it("locks rungs beyond ladder+1", function()
			local battle = setup()
			expect((battle :: any):startNpc(USER, 3).err).to.equal("rung_locked")
			expect((battle :: any):startNpc(USER, 1).ok).to.equal(true)
		end)

		it("rejects picks in the wrong phase and forged battle ids", function()
			local battle = setup()
			local started = (battle :: any):startNpc(USER, 1)
			expect(
				(battle :: any):pickStat(USER, { battleId = "bt999", round = 1, stat = "li" }).err
			).to.equal("no_battle")
			expect((battle :: any):resolveRound(USER, { battleId = started.battleId }).err).to.equal(
				"wrong_phase"
			)
			expect(
				(battle :: any):pickStat(
					USER,
					{ battleId = started.battleId, round = 1, stat = "nope" }
				).err
			).to.equal("bad_request")
		end)

		it("refuses to resolve before the flash deadline while unanswered", function()
			local battle, _quiz, _profile, _clock = setup()
			local started = (battle :: any):startNpc(USER, 1)
			local picked = (battle :: any):pickStat(
				USER,
				{ battleId = started.battleId, round = 1, stat = "su" }
			)
			expect(picked.ok).to.equal(true)
			local early = (battle :: any):resolveRound(USER, { battleId = started.battleId })
			expect(early.err).to.equal("flash_pending")
		end)

		it("pays the first-clear bounty exactly once and advances the rung", function()
			local battle, quiz, profile, clock = setup(3)
			profile.coins = 0
			local wonOnce = false
			for _attempt = 1, 30 do
				local started = (battle :: any):startNpc(USER, 1)
				assert(started.ok, started.err)
				local finished: any = nil
				local guard = 0
				repeat
					local session = (battle :: any)._sessions[USER]
					local response =
						playRound(battle, quiz, clock, "su", true, started.battleId, session.round)
					finished = response.match
					guard += 1
				until finished or guard > 30
				assert(finished, "match never ended")
				if finished.playerWon then
					wonOnce = true
					expect(finished.rungAdvanced).to.equal(true)
					expect(profile.ladderRung).to.equal(1)
					expect(profile.coins).to.equal(3) -- flat bounty
					break
				end
			end
			expect(wonOnce).to.equal(true)

			-- replaying the beaten rung never pays again
			local coinsAfter = profile.coins
			local started = (battle :: any):startNpc(USER, 1)
			local finished: any = nil
			local guard = 0
			repeat
				local session = (battle :: any)._sessions[USER]
				local response =
					playRound(battle, quiz, clock, "su", true, started.battleId, session.round)
				finished = response.match
				guard += 1
			until finished or guard > 30
			if finished.playerWon then
				expect(finished.rungAdvanced).to.equal(false)
				expect(profile.coins).to.equal(coinsAfter)
			end
		end)

		it("an unanswered flash means uncharged — never a coin penalty", function()
			local battle, quiz, profile, clock = setup(11)
			profile.coins = 5
			local started = (battle :: any):startNpc(USER, 1)
			local response = playRound(battle, quiz, clock, "li", false, started.battleId, 1)
			expect(response.you.charged).to.equal(false)
			expect(response.you.doubled).to.equal(false)
			expect(profile.coins).to.equal(5)
		end)
	end)

	describe("rung 1 beatable by a starter beast (M4 acceptance)", function()
		it("a tutorial 2-part beast with good flashes wins most matches", function()
			local battle, quiz, profile, clock = setup(1234)
			local wins = 0
			local matches = 40
			for _ = 1, matches do
				profile.ladderRung = 0 -- keep fighting rung 1
				local started = (battle :: any):startNpc(USER, 1)
				assert(started.ok, started.err)
				local finished: any = nil
				local guard = 0
				repeat
					local session = (battle :: any)._sessions[USER]
					-- kid strategy: always play the beast's best stat (猫头鸟身 → 速3)
					local response =
						playRound(battle, quiz, clock, "su", true, started.battleId, session.round)
					finished = response.match
					guard += 1
				until finished or guard > 30
				if finished and finished.playerWon then
					wins += 1
				end
			end
			-- 石头怪 is 2/1/1 vs starter 1/3/2: with charged flashes this should
			-- be a strong favorite, not a coin flip
			expect(wins / matches > 0.7).to.equal(true)
		end)
	end)
end
