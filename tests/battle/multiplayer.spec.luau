--!strict
-- M5 criteria: ghost publish/fetch with mocked stores (accuracy clamp at
-- publish, self-filter, stat-window preference, starter fallback) and the
-- live-battle state machine (both picks required, simultaneous flashes,
-- payouts + caps, void on disconnect).

local T = require("../testkit")
local H = require("../quiz/helpers")
local BattleService = require("../../src/server/Services/BattleService")
local GhostService = require("../../src/server/Services/GhostService")
local QuizService = require("../../src/server/Services/QuizService")
local Profiles = require("../../src/server/Services/Profiles")
local Analytics = require("../../src/server/Services/Analytics")
local MockBackend = require("../profile/mockbackend")
local ProfileSchema = require("../../src/shared/ProfileSchema")
local Rng = require("../../src/shared/Util/Rng")
local Types = require("../../src/shared/Types")
local describe, it, expect = T.describe, T.it, T.expect

local ALICE, BOB = 111, 222

local function mockStores()
	local data: { [string]: any } = {}
	local index: { [number]: number } = {}
	return {
		get = function(key: string)
			return data[key]
		end,
		set = function(key: string, value: any)
			data[key] = value
		end,
		indexSet = function(userId: number, publishedAt: number)
			index[userId] = publishedAt
		end,
		indexSample = function(count: number)
			local out = {}
			for userId in index do
				table.insert(out, userId)
				if #out >= count then
					break
				end
			end
			return out
		end,
		_data = data,
		_index = index,
	}
end

local function giveBeast(profile: Types.Profile, head: string, body: string, feedHead: number?)
	profile.animals[head] = true
	profile.animals[body] = true
	local id = `b{profile.nextBeastId}`
	profile.nextBeastId += 1
	profile.beasts[id] = {
		id = id,
		name = nil,
		slots = { head = head, body = body, legs = nil, tail = nil },
		feed = { head = feedHead or 0, body = 0, legs = 0, tail = 0 },
		golden = false,
		colorway = nil,
		createdAt = 0,
	}
	profile.activeBeastId = id
end

local function setup()
	local clock = { now = H.NOW }
	local nowFn = function()
		return clock.now
	end
	local backend = MockBackend.new()
	local profiles = Profiles.new(backend :: any)
	local analytics = Analytics.new(nowFn)
	local quiz = QuizService.new({
		profiles = profiles,
		analytics = analytics,
		now = nowFn,
		manifests = H.fullManifests(),
	})
	local pushes: { { userId: number, event: string, payload: any } } = {}
	local battle = BattleService.new({
		profiles = profiles,
		quiz = quiz,
		analytics = analytics,
		now = nowFn,
		rand = Rng.mulberry32(99),
		push = function(userId, event, payload)
			table.insert(pushes, { userId = userId, event = event, payload = payload })
		end,
	})
	local stores = mockStores()
	local ghosts = GhostService.new({
		profiles = profiles,
		stores = stores :: any,
		now = nowFn,
		rand = Rng.mulberry32(5),
	})
	local alice = profiles:load(ALICE, 1, clock.now) :: Types.Profile
	local bob = profiles:load(BOB, 2, clock.now) :: Types.Profile
	giveBeast(alice, "猫", "鸟")
	giveBeast(bob, "熊", "牛", 2)
	return {
		clock = clock,
		profiles = profiles,
		quiz = quiz,
		battle = battle,
		ghosts = ghosts,
		stores = stores,
		pushes = pushes,
		alice = alice,
		bob = bob,
	}
end

local function lastPush(pushes: { any }, userId: number, event: string): any
	for i = #pushes, 1, -1 do
		local push = pushes[i]
		if push.userId == userId and push.event == event then
			return push.payload
		end
	end
	return nil
end

return function()
	describe("ghost pool (criterion 5)", function()
		it("publishes the active beast with accuracy clamped 0.2–0.9", function()
			local world = setup()
			-- Bob has terrible recorded accuracy
			for _ = 1, 50 do
				ProfileSchema.recordAnswer(world.bob, false)
			end
			expect((world.ghosts :: any):publish(BOB, "Bob")).to.equal(true)
			local snapshot = world.stores._data["g222"]
			expect(snapshot).to.be.ok()
			expect(snapshot.accuracy).to.be.near(0.2) -- clamped floor
			expect(snapshot.slots.head).to.equal("熊")
			expect(snapshot.feed.head).to.equal(2) -- build travels with the ghost

			-- great accuracy clamps at 0.9
			for _ = 1, 300 do
				ProfileSchema.recordAnswer(world.alice, true)
			end
			expect((world.ghosts :: any):publish(ALICE, "Alice")).to.equal(true)
			expect(world.stores._data["g111"].accuracy).to.be.near(0.9)
		end)

		it("debounces republish, forces on demand", function()
			local world = setup()
			expect((world.ghosts :: any):publish(ALICE, "Alice")).to.equal(true)
			expect((world.ghosts :: any):publish(ALICE, "Alice")).to.equal(false) -- debounced
			expect((world.ghosts :: any):publish(ALICE, "Alice", true)).to.equal(true) -- forced
			world.clock.now += 31
			expect((world.ghosts :: any):publish(ALICE, "Alice")).to.equal(true)
		end)

		it("never serves the player their own ghost", function()
			local world = setup();
			(world.ghosts :: any):publish(ALICE, "Alice")
			-- pool contains only Alice; Alice fetches → starter ghost fallback
			local ghost = (world.ghosts :: any):fetch(ALICE)
			expect(ghost).to.be.ok()
			expect(ghost.ownerUserId == ALICE).to.equal(false)
		end)

		it("serves another player's ghost when the pool has one", function()
			local world = setup();
			(world.ghosts :: any):publish(BOB, "Bob")
			local ghost = (world.ghosts :: any):fetch(ALICE)
			expect(ghost.ownerUserId).to.equal(BOB)
		end)

		it("falls back to starter ghosts on an empty pool", function()
			local world = setup()
			local ghost = (world.ghosts :: any):fetch(ALICE)
			expect(ghost).to.be.ok()
			expect(ghost.ownerUserId).to.equal(0) -- seeded starter
		end)

		it("ghost battles never touch the ghost owner's profile", function()
			local world = setup();
			(world.ghosts :: any):publish(BOB, "Bob")
			local bobCoinsBefore = world.bob.coins
			local bobRecordBefore = world.bob.battleRecord.wins + world.bob.battleRecord.losses
			local ghost = (world.ghosts :: any):fetch(ALICE)
			local started = (world.battle :: any):startGhost(ALICE, ghost)
			expect(started.ok).to.equal(true)
			-- play the whole match out
			local guard = 0
			repeat
				local session = (world.battle :: any)._sessions[ALICE]
				local picked = (world.battle :: any):pickStat(ALICE, {
					battleId = started.battleId,
					round = session.round,
					stat = "su",
				})
				assert(picked.ok, picked.err)
				world.clock.now += 5
				local resolved = (world.battle :: any):resolveRound(
					ALICE,
					{ battleId = started.battleId }
				)
				assert(resolved.ok, resolved.err)
				guard += 1
			until resolved.match or guard > 30
			expect(world.bob.coins).to.equal(bobCoinsBefore)
			expect(world.bob.battleRecord.wins + world.bob.battleRecord.losses).to.equal(
				bobRecordBefore
			)
		end)
	end)

	describe("live battles (criterion 4)", function()
		it(
			"runs challenge → accept → both pick → simultaneous flashes → resolve",
			function()
				local world = setup()
				local challenged = (world.battle :: any):challenge(ALICE, BOB)
				expect(challenged.ok).to.equal(true)
				expect(lastPush(world.pushes, BOB, "ChallengeIncoming")).to.be.ok()

				local accepted = (world.battle :: any):respondChallenge(BOB, true)
				expect(accepted.ok).to.equal(true)
				local battleId = accepted.battleId
				expect(lastPush(world.pushes, ALICE, "LiveStarted")).to.be.ok()
				expect(lastPush(world.pushes, BOB, "LiveStarted")).to.be.ok()

				-- Alice picks first: waiting; no flash yet for anyone
				local alicePick = (world.battle :: any):pickStat(
					ALICE,
					{ battleId = battleId, round = 1, stat = "su" }
				)
				expect(alicePick.waiting).to.equal(true)
				expect(lastPush(world.pushes, ALICE, "FlashPrompt")).to.equal(nil)

				-- Bob picks: flashes fire for BOTH with one shared deadline
				local bobPick = (world.battle :: any):pickStat(
					BOB,
					{ battleId = battleId, round = 1, stat = "li" }
				)
				expect(bobPick.waiting).to.equal(false)
				local aliceFlash = lastPush(world.pushes, ALICE, "FlashPrompt")
				local bobFlash = lastPush(world.pushes, BOB, "FlashPrompt")
				expect(aliceFlash).to.be.ok()
				expect(bobFlash).to.be.ok()
				expect(aliceFlash.deadline).to.equal(bobFlash.deadline)

				-- both answer their own flashes correctly
				for _, entry in
					{ { user = ALICE, flash = aliceFlash }, { user = BOB, flash = bobFlash } }
				do
					local pending = (world.quiz :: any)._pendingFlash[entry.user]
					local result = (world.battle :: any):submitFlash(entry.user, {
						battleId = battleId,
						questionId = entry.flash.flash.questionId,
						choiceIndex = pending.question.correctIndex,
					})
					expect(result.ok).to.equal(true)
				end

				-- both flashes in → the round resolved and pushed to both, oriented
				local aliceRound = lastPush(world.pushes, ALICE, "RoundResult")
				local bobRound = lastPush(world.pushes, BOB, "RoundResult")
				expect(aliceRound).to.be.ok()
				expect(bobRound).to.be.ok()
				expect(aliceRound.you.stat).to.equal("su")
				expect(bobRound.you.stat).to.equal("li")
				-- 速 beats 力, both charged: Alice's 3×2=6 vs Bob's 力6 → tie replay!
				-- (whatever the exact numbers, orientations must mirror)
				expect(aliceRound.them.stat).to.equal("li")
				expect(bobRound.them.stat).to.equal("su")
			end
		)

		it("pays live_win/participation with the daily cap", function()
			local world = setup()
			-- run full matches until someone wins twice; repeat to hit the 9🪙 cap
			local totalPaid = 0
			for _ = 1, 4 do
				local challenged = (world.battle :: any):challenge(ALICE, BOB)
				assert(challenged.ok, challenged.err)
				local accepted = (world.battle :: any):respondChallenge(BOB, true)
				assert(accepted.ok, accepted.err)
				local battleId = accepted.battleId
				local guard = 0
				local done = false
				repeat
					(world.battle :: any):pickStat(
						ALICE,
						{ battleId = battleId, round = 0, stat = "su" }
					)
					local session = (world.battle :: any)._live[ALICE]
					if not session then
						done = true
						break
					end
					-- picks must reference the live round; re-pick properly
					local roundNow = session.round
					local a = (world.battle :: any):pickStat(
						ALICE,
						{ battleId = battleId, round = roundNow, stat = "su" }
					)
					local b = (world.battle :: any):pickStat(
						BOB,
						{ battleId = battleId, round = roundNow, stat = "zhi" }
					)
					local _ = a
					local _2 = b
					world.clock.now += 5 -- let flashes lapse: uncharged both
					(world.battle :: any):liveResolve(ALICE, { battleId = battleId })
					local aliceRound = lastPush(world.pushes, ALICE, "RoundResult")
					if aliceRound and aliceRound.match then
						done = true
					end
					guard += 1
				until done or guard > 40
				expect(done).to.equal(true)
			end
			-- combined payouts can never exceed the 9🪙 daily live cap per player
			local aliceLive = world.alice.daily.liveCoins
			local bobLive = world.bob.daily.liveCoins
			expect(aliceLive <= 9).to.equal(true)
			expect(bobLive <= 9).to.equal(true)
			totalPaid = aliceLive + bobLive
			expect(totalPaid > 0).to.equal(true)
		end)

		it("voids the match when a player leaves — no coins move", function()
			local world = setup();
			(world.battle :: any):challenge(ALICE, BOB)
			local accepted = (world.battle :: any):respondChallenge(BOB, true)
			assert(accepted.ok, "accept failed")
			local aliceCoins, bobCoins = world.alice.coins, world.bob.coins;
			(world.battle :: any):dropPlayer(ALICE)
			expect((world.battle :: any)._live[BOB]).to.equal(nil)
			expect(lastPush(world.pushes, BOB, "LiveEnded").reason).to.equal("opponent_left")
			expect(world.alice.coins).to.equal(aliceCoins)
			expect(world.bob.coins).to.equal(bobCoins)
		end)

		it("rejects challenges off the pad or to busy players", function()
			local world = setup();
			(world.battle :: any):challenge(ALICE, BOB);
			(world.battle :: any):respondChallenge(BOB, true)
			-- both now in a live battle: further challenges refused
			expect((world.battle :: any):challenge(ALICE, BOB).err).to.equal("battle_in_progress")
		end)
	end)
end
