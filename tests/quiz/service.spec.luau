--!strict
-- End-to-end service flow, headless: request → answer with coins/mastery/
-- leveling effects, forged-answer rejection (criterion 3 groundwork), and the
-- flash namespace minting nothing.

local T = require("../testkit")
local H = require("./helpers")
local Profiles = require("../../src/server/Services/Profiles")
local QuizService = require("../../src/server/Services/QuizService")
local Analytics = require("../../src/server/Services/Analytics")
local MockBackend = require("../profile/mockbackend")
local describe, it, expect = T.describe, T.it, T.expect

local USER = 777

local function setup(manifests: any?)
	local clock = { now = H.NOW }
	local backend = MockBackend.new()
	local profiles = Profiles.new(backend :: any)
	local analytics = Analytics.new(function()
		return clock.now
	end)
	local quiz = QuizService.new({
		profiles = profiles,
		analytics = analytics,
		now = function()
			return clock.now
		end,
		manifests = manifests or H.fullManifests(),
	})
	local profile = profiles:load(USER, 42, clock.now)
	assert(profile, "profile load failed")
	return quiz, profile, clock, analytics
end

local function answerUntil(quiz: any, _profile: any, wantCorrect: boolean): any
	-- request then submit either the correct index (found by probing server
	-- state via outcome) — tests know the correct answer by brute force: try
	-- index 1; if retryPending, the correct one is among the others.
	local req = (quiz :: any):requestQuestion(USER)
	assert(req.ok and req.question, "no question")
	local qid = req.question.questionId
	if wantCorrect then
		-- submit each index until "clean"/"retry"; first submit that returns
		-- correct wins. (Server allows 2 taps; brute force stays within them.)
		for index = 1, 3 do
			local result = (quiz :: any):submitAnswer(
				USER,
				{ questionId = qid, choiceIndex = index }
			)
			if result.ok and (result.outcome == "clean" or result.outcome == "retry") then
				return result
			end
			if result.ok and result.outcome == "miss" then
				return result
			end
		end
		error("never answered correctly")
	else
		-- two distinct wrong taps: probe until miss
		local firstWrong: number? = nil
		for index = 1, 3 do
			local result = (quiz :: any):submitAnswer(
				USER,
				{ questionId = qid, choiceIndex = index }
			)
			if not result.ok then
				continue
			end
			if result.outcome == "retryPending" then
				firstWrong = index
			elseif result.outcome == "miss" then
				return result
			elseif result.outcome == "clean" or result.outcome == "retry" then
				return result -- accidentally correct; caller retries
			end
		end
		error(`no miss produced (firstWrong={firstWrong})`)
	end
end

return function()
	describe("mission flow", function()
		it("pays doubled warm-up coins on the first clean solve of the day", function()
			local quiz, profile = setup()
			local result
			repeat
				result = answerUntil(quiz, profile, true)
			until result.outcome == "clean" or result.outcome == "retry"
			if result.outcome == "clean" then
				expect(result.coinDelta).to.equal(2) -- warm-up double
				expect(result.warmupRemaining).to.equal(4)
			else
				expect(result.coinDelta).to.equal(0) -- retry pays nothing
			end
			-- the server's ledger and the live profile always agree
			expect(profile.coins).to.equal(result.newCoins)
		end)

		it("charges 1 coin on a full miss and reveals the answer", function()
			local quiz, profile = setup()
			profile.coins = 5
			local result
			local guard = 0
			repeat
				result = answerUntil(quiz, profile, false)
				guard += 1
			until result.outcome == "miss" or guard > 20
			expect(result.outcome).to.equal("miss")
			expect(result.coinDelta).to.equal(-1)
			expect(result.correctIndex >= 1 and result.correctIndex <= 3).to.equal(true)
			expect(type(result.revealText)).to.equal("string")
		end)

		it("levels up after 3 clean solves with the 5🪙 bonus", function()
			local quiz, profile = setup()
			local cleans = 0
			local sawLevelUp = false
			for _ = 1, 40 do
				local result = answerUntil(quiz, profile, true)
				if result.outcome == "clean" then
					cleans += 1
					if result.levelUp then
						sawLevelUp = true
						expect(result.newLevel).to.equal(2)
						expect(type(result.levelUpMath)).to.equal("string")
						break
					end
				else
					cleans = 0 -- retry resets the streak server-side too
				end
			end
			expect(sawLevelUp).to.equal(true)
			expect(profile.level).to.equal(2)
		end)
	end)

	describe("hostile clients (criterion 3)", function()
		it("rejects a forged questionId", function()
			local quiz = setup()
			local result = (quiz :: any):submitAnswer(
				USER,
				{ questionId = "q999999", choiceIndex = 1 }
			)
			expect(result.ok).to.equal(false)
			expect(result.err).to.equal("no_such_question")
		end)

		it("rejects double-submits of an answered question", function()
			local quiz = setup()
			local req = (quiz :: any):requestQuestion(USER)
			local qid = req.question.questionId
			local answered = false
			for index = 1, 3 do
				local result = (quiz :: any):submitAnswer(
					USER,
					{ questionId = qid, choiceIndex = index }
				)
				if result.ok and result.outcome ~= "retryPending" then
					answered = true
					local again = (quiz :: any):submitAnswer(
						USER,
						{ questionId = qid, choiceIndex = index }
					)
					expect(again.ok).to.equal(false)
					break
				end
			end
			expect(answered).to.equal(true)
		end)

		it("rejects out-of-range and non-integer indices", function()
			local quiz = setup()
			local req = (quiz :: any):requestQuestion(USER)
			local qid = req.question.questionId
			for _, bad in { 0, 4, 1.5, -1 } do
				local result = (quiz :: any):submitAnswer(
					USER,
					{ questionId = qid, choiceIndex = bad }
				)
				expect(result.ok).to.equal(false)
			end
		end)

		it("voids the pending question on re-request (no answer scouting)", function()
			local quiz = setup()
			local first = (quiz :: any):requestQuestion(USER)
			local second = (quiz :: any):requestQuestion(USER)
			local stale = (quiz :: any):submitAnswer(USER, {
				questionId = first.question.questionId,
				choiceIndex = 1,
			})
			expect(stale.ok).to.equal(false)
			expect(second.question.questionId == first.question.questionId).to.equal(false)
		end)
	end)

	describe("charge flashes", function()
		it("reports charged on a correct answer and mints nothing", function()
			local quiz, profile, clock = setup()
			local before = profile.coins
			local payload, pending = (quiz :: any):generateFlash(USER)
			assert(payload and pending, "no flash")
			local result = (quiz :: any):submitFlash(USER, {
				questionId = payload.questionId,
				choiceIndex = pending.question.correctIndex,
			})
			expect(result.charged).to.equal(true)
			expect(profile.coins).to.equal(before) -- flash answers never mint
			expect(profile.cleanStreak).to.equal(0) -- and never touch leveling
			local _ = clock
		end)

		it("treats a late answer as uncharged, never a penalty", function()
			local quiz, profile, clock = setup()
			local payload, pending = (quiz :: any):generateFlash(USER)
			assert(payload and pending, "no flash")
			clock.now += 5 -- past the 4s window
			local result = (quiz :: any):submitFlash(USER, {
				questionId = payload.questionId,
				choiceIndex = pending.question.correctIndex,
			})
			expect(result.charged).to.equal(false)
			expect(result.late).to.equal(true)
			expect(profile.coins >= 0).to.equal(true)
		end)
	end)

	describe("degradation at the service layer", function()
		it("returns a friendly waiting state when everything is deferred", function()
			local quiz = setup(H.emptyManifests())
			local result = (quiz :: any):requestQuestion(USER)
			expect(result.ok).to.equal(true)
			expect(result.waiting).to.equal(true)
		end)
	end)

	describe("progress summary", function()
		it("reports N/700 with per-band rows", function()
			local quiz = setup()
			local result = (quiz :: any):progressSummary(USER)
			expect(result.ok).to.equal(true)
			expect(result.of).to.equal(700)
			expect(#result.bands).to.equal(14)
		end)
	end)
end
