--!strict
-- One battle state machine for all three opponent kinds: NPC rungs (M4),
-- ghosts and live players (M5) — a side is a player or a brain; everything
-- downstream is identical. Engine-free: deps injected, clock injected, flash
-- generation delegated to QuizService's flash namespace. Battle results are
-- NEVER accepted from a client — the machine computes them.
--
-- NPC/ghost flow (RF-driven):
--   start → pickStat (response carries the flash payload + deadline)
--   → submitFlash → resolveRound (idempotent; also callable after deadline)
--   → repeat to best-of-3 → match result with bounty/caps applied.

local Config = require("../../shared/Config")
local Animals = require("../../shared/Data/Animals")
local Opponents = require("../../shared/Data/Opponents")
local GhostBrain = require("../../shared/Battle/GhostBrain")
local NpcBrain = require("../../shared/Battle/NpcBrain")
local Resolver = require("../../shared/Battle/Resolver")
local Ledger = require("../../shared/Economy/Ledger")
local ProfileSchema = require("../../shared/ProfileSchema")
local Rng = require("../../shared/Util/Rng")
local SlotStats = require("../../shared/Fusion/SlotStats")
local Types = require("../../shared/Types")

type Profile = Types.Profile
type Stats = Types.Stats

local ANIMAL_INDEX = SlotStats.index(Animals :: { Types.AnimalDef })
local OPPONENTS = Opponents :: { Types.OpponentDef }

local BattleService = {}
BattleService.__index = BattleService

export type BrainSide = {
	kind: "npc" | "ghost",
	stats: Stats,
	name: string,
	rung: number?, -- npc
	snapshot: Types.GhostSnapshot?, -- ghost
}

export type Session = {
	battleId: string,
	userId: number,
	playerStats: Stats,
	brain: BrainSide,
	round: number,
	playerScore: number,
	brainScore: number,
	tieStreak: number,
	phase: "picking" | "flash" | "done",
	playerPick: Types.Stat?,
	playerCharged: boolean?,
	brainPick: Types.Stat?,
	brainCharged: boolean?,
	flashDeadline: number?,
	rounds: { Resolver.RoundResult },
}

export type Deps = {
	profiles: any,
	quiz: any, -- QuizService (flash namespace)
	analytics: any,
	now: (() -> number)?,
	rand: Rng.Rand?,
	push: ((userId: number, event: string, payload: any) -> ())?, -- live-battle RE pushes
	nearPad: ((userIdA: number, userIdB: number) -> boolean)?, -- challenge-pad proximity
	displayName: ((userId: number) -> string)?,
}

local counter = 0

function BattleService.new(deps: Deps)
	counter = 0
	return setmetatable({
		_profiles = deps.profiles,
		_quiz = deps.quiz,
		_analytics = deps.analytics,
		_now = deps.now or os.time,
		_rand = deps.rand or Rng.mulberry32(os.clock() * 1e6 % 2 ^ 31),
		_push = deps.push or function() end,
		_nearPad = deps.nearPad or function()
			return true
		end,
		_displayName = deps.displayName or function(userId: number)
			return `Player{userId}`
		end,
		_sessions = {} :: { [number]: Session }, -- one brain battle per player
		_live = {} :: { [number]: any }, -- userId -> shared LiveSession
		_challenges = {} :: { [number]: { from: number, expiresAt: number } },
	}, BattleService)
end

local function fail(err: string): any
	return { ok = false, err = err }
end

local function activeStats(profile: Profile): Stats?
	local beastId = profile.activeBeastId
	if not beastId then
		return nil
	end
	local beast = profile.beasts[beastId]
	if not beast then
		return nil
	end
	return SlotStats.resolve(beast, ANIMAL_INDEX)
end

function BattleService.dropPlayer(self: any, userId: number)
	self._sessions[userId] = nil
	self._challenges[userId] = nil
	local live = self._live[userId]
	if live then
		-- a vanished player voids the match: no coins move, the opponent is freed
		local other = if live.a.userId == userId then live.b.userId else live.a.userId
		self._live[live.a.userId] = nil
		self._live[live.b.userId] = nil
		self._push(other, "LiveEnded", { reason = "opponent_left" })
	end
end

-- Ladder snapshot for the arena UI.
function BattleService.ladder(self: any, userId: number): any
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return fail("no_profile")
	end
	local rungs = {}
	for index, opponent in OPPONENTS do
		table.insert(rungs, {
			rung = index,
			name = opponent.name,
			pinyin = opponent.pinyin,
			li = opponent.li,
			su = opponent.su,
			zhi = opponent.zhi,
			beaten = index <= profile.ladderRung,
			locked = index > profile.ladderRung + 1,
			chargeRate = NpcBrain.chargeProbability(index),
		})
	end
	return {
		ok = true,
		rungs = rungs,
		ladderRung = profile.ladderRung,
		record = profile.battleRecord,
		hasBeast = activeStats(profile) ~= nil,
	}
end

function BattleService.startNpc(self: any, userId: number, rung: number): any
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return fail("no_profile")
	end
	if self._sessions[userId] then
		return fail("battle_in_progress")
	end
	if rung < 1 or rung > #OPPONENTS or rung > profile.ladderRung + 1 then
		return fail("rung_locked")
	end
	local stats = activeStats(profile)
	if not stats then
		return fail("no_active_beast")
	end
	local opponent = OPPONENTS[rung]

	counter += 1
	local session: Session = {
		battleId = `bt{counter}`,
		userId = userId,
		playerStats = stats :: Stats,
		brain = {
			kind = "npc",
			stats = { li = opponent.li, su = opponent.su, zhi = opponent.zhi },
			name = opponent.name,
			rung = rung,
			snapshot = nil,
		},
		round = 1,
		playerScore = 0,
		brainScore = 0,
		tieStreak = 0,
		phase = "picking",
		playerPick = nil,
		playerCharged = nil,
		brainPick = nil,
		brainCharged = nil,
		flashDeadline = nil,
		rounds = {},
	}
	self._sessions[userId] = session
	return {
		ok = true,
		battleId = session.battleId,
		opponent = {
			name = opponent.name,
			pinyin = opponent.pinyin,
			li = opponent.li,
			su = opponent.su,
			zhi = opponent.zhi,
			rung = rung,
			chargeRate = NpcBrain.chargeProbability(rung),
		},
		yourStats = stats,
	}
end

function BattleService.startGhost(self: any, userId: number, snapshot: Types.GhostSnapshot): any
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return fail("no_profile")
	end
	if self._sessions[userId] then
		return fail("battle_in_progress")
	end
	local stats = activeStats(profile)
	if not stats then
		return fail("no_active_beast")
	end
	counter += 1
	local displayName = snapshot.ownerDisplayName
	local session: Session = {
		battleId = `bt{counter}`,
		userId = userId,
		playerStats = stats :: Stats,
		brain = {
			kind = "ghost",
			stats = snapshot.stats,
			name = `{displayName} 的幽灵兽`,
			rung = nil,
			snapshot = snapshot,
		},
		round = 1,
		playerScore = 0,
		brainScore = 0,
		tieStreak = 0,
		phase = "picking",
		playerPick = nil,
		playerCharged = nil,
		brainPick = nil,
		brainCharged = nil,
		flashDeadline = nil,
		rounds = {},
	}
	self._sessions[userId] = session
	return {
		ok = true,
		battleId = session.battleId,
		ghost = {
			ownerDisplayName = displayName,
			stats = snapshot.stats,
			golden = snapshot.golden,
			chargeRate = GhostBrain.chargeProbability(snapshot),
		},
		yourStats = stats,
	}
end

-- Secret pick; the response carries the charge-flash question for THIS player
-- (served from their own band/mode mix) plus the server deadline.
function BattleService.pickStat(self: any, userId: number, payload: any): any
	if self._live[userId] then
		return BattleService.livePick(self, userId, payload)
	end
	local session = self._sessions[userId] :: Session?
	if not session or session.battleId ~= payload.battleId then
		return fail("no_battle")
	end
	if session.phase ~= "picking" or payload.round ~= session.round then
		return fail("wrong_phase")
	end
	local stat = payload.stat
	if stat ~= "li" and stat ~= "su" and stat ~= "zhi" then
		return fail("bad_request")
	end

	session.playerPick = stat
	do
		local profile = self._profiles:get(userId) :: Profile?
		if profile then
			(profile.pickHistogram :: any)[stat] += 1
		end
	end
	-- brain picks + rolls its charge the moment picks close (server-side only;
	-- nothing about the brain's pick leaves the server before the reveal)
	if session.brain.kind == "npc" then
		session.brainPick = NpcBrain.pickStat(session.brain.stats, self._rand)
		session.brainCharged = NpcBrain.resolveCharge(session.brain.rung :: number, self._rand)
	else
		local snapshot = session.brain.snapshot :: Types.GhostSnapshot
		session.brainPick = GhostBrain.pickStat(snapshot, self._rand)
		session.brainCharged = GhostBrain.resolveCharge(snapshot, self._rand)
	end
	session.phase = "flash"
	session.flashDeadline = self._now() + Config.Quiz.FLASH_SECONDS

	local flashPayload = self._quiz:generateFlash(userId)
	if not flashPayload then
		-- No servable flash content (all deferred): the card simply stays
		-- uncharged — never an error, never a penalty.
		session.playerCharged = false
		return { ok = true, flash = nil, deadline = session.flashDeadline }
	end
	return { ok = true, flash = flashPayload, deadline = session.flashDeadline }
end

function BattleService.submitFlash(self: any, userId: number, payload: any): any
	if self._live[userId] then
		return BattleService.liveFlash(self, userId, payload)
	end
	local session = self._sessions[userId] :: Session?
	if not session or session.battleId ~= payload.battleId then
		return fail("no_battle")
	end
	if session.phase ~= "flash" then
		return fail("wrong_phase")
	end
	local result = self._quiz:submitFlash(userId, payload)
	if not result.ok then
		return result
	end
	session.playerCharged = result.charged == true
	return { ok = true, charged = session.playerCharged }
end

local function applyMatchEnd(self: any, session: Session, profile: Profile): any
	local playerWon = session.playerScore > session.brainScore
	local now = self._now()
	ProfileSchema.rollDaily(profile, now)
	local record = profile.battleRecord
	if playerWon then
		record.wins += 1
	else
		record.losses += 1
	end

	local bounty = nil
	local rungAdvanced = false
	local capNote = nil
	if session.brain.kind == "npc" then
		local rung = session.brain.rung :: number
		if playerWon and rung == profile.ladderRung + 1 then
			profile.ladderRung = rung
			rungAdvanced = true
			local coin = Ledger.faucet(profile, "npc_first_clear", {}, now)
			bounty = coin.mathString
			self._analytics:track(
				session.userId,
				"faucet",
				"npc_first_clear",
				coin.delta,
				{ rung = rung }
			)
		end
	elseif session.brain.kind == "ghost" and playerWon then
		local snapshot = session.brain.snapshot :: Types.GhostSnapshot
		local coin =
			Ledger.faucet(profile, "ghost_win", { ghostKey = `g{snapshot.ownerUserId}` }, now)
		if coin.delta > 0 then
			bounty = coin.mathString
		else
			capNote = "今天的幽灵奖励拿满啦! (ghost coins capped for today)"
		end
		self._analytics:track(session.userId, "faucet", "ghost_win", coin.delta, {})
	end

	self._sessions[session.userId] = nil
	self._analytics:track(
		session.userId,
		"battle",
		session.brain.kind,
		if playerWon then 1 else 0,
		{
			rounds = #session.rounds,
		}
	)
	return {
		playerWon = playerWon,
		bountyMath = bounty,
		rungAdvanced = rungAdvanced,
		capNote = capNote,
		newCoins = profile.coins,
		record = record,
	}
end

-- Resolve the current round. Idempotent within a phase; callable by the client
-- after the flash deadline (an unanswered flash is simply uncharged).
function BattleService.resolveRound(self: any, userId: number, payload: any): any
	if self._live[userId] then
		return BattleService.liveResolve(self, userId, payload)
	end
	local session = self._sessions[userId] :: Session?
	if not session or session.battleId ~= payload.battleId then
		return fail("no_battle")
	end
	if session.phase ~= "flash" then
		return fail("wrong_phase")
	end
	if session.playerCharged == nil then
		if self._now() < (session.flashDeadline :: number) then
			return fail("flash_pending")
		end
		session.playerCharged = false -- deadline passed: uncharged, no penalty
	end

	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return fail("no_profile")
	end

	local playerPick = session.playerPick :: Types.Stat
	local result = Resolver.resolveRound({
		stat = playerPick,
		value = (session.playerStats :: any)[playerPick],
		charged = session.playerCharged :: boolean,
	}, {
		stat = session.brainPick :: Types.Stat,
		value = (session.brain.stats :: any)[session.brainPick],
		charged = session.brainCharged :: boolean,
	})
	table.insert(session.rounds, result)

	local response: any = {
		ok = true,
		round = session.round,
		you = result.a,
		them = result.b,
		winner = result.winner,
	}

	if result.winner == "tie" then
		session.tieStreak += 1
		if session.tieStreak >= Config.Battle.MAX_TIE_REPLAYS then
			-- stall breaker: totals, then challenger
			local totalsA = session.playerStats.li
				+ session.playerStats.su
				+ session.playerStats.zhi
			local totalsB = session.brain.stats.li
				+ session.brain.stats.su
				+ session.brain.stats.zhi
			local winner = Resolver.breakStall(totalsA, totalsB)
			if winner == "a" then
				session.playerScore += 1
			else
				session.brainScore += 1
			end
			session.tieStreak = 0
			response.stallBroken = winner
		else
			response.replay = true
		end
	else
		session.tieStreak = 0
		if result.winner == "a" then
			session.playerScore += 1
		else
			session.brainScore += 1
		end
	end

	response.score = { you = session.playerScore, them = session.brainScore }

	local target = Config.Battle.ROUNDS_TO_WIN
	if session.playerScore >= target or session.brainScore >= target then
		session.phase = "done"
		response.match = applyMatchEnd(self, session, profile)
	else
		if not response.replay then
			session.round += 1
		end
		session.phase = "picking"
		session.playerPick = nil
		session.playerCharged = nil
		session.brainPick = nil
		session.brainCharged = nil
		session.flashDeadline = nil
	end
	return response
end

-- ── Live battles (two players, same server, challenge pad) ─────────────────

type LiveSide = {
	userId: number,
	stats: Stats,
	pick: Types.Stat?,
	charged: boolean?,
	displayName: string,
}

type LiveSession = {
	battleId: string,
	a: LiveSide,
	b: LiveSide,
	round: number,
	scoreA: number,
	scoreB: number,
	tieStreak: number,
	phase: "picking" | "flash" | "done",
	flashDeadline: number?,
}

local CHALLENGE_TTL = Config.Battle.CHALLENGE_TIMEOUT_SECONDS

function BattleService.challenge(self: any, userId: number, targetUserId: number): any
	if userId == targetUserId then
		return fail("bad_request")
	end
	if self._sessions[userId] or self._live[userId] then
		return fail("battle_in_progress")
	end
	if self._sessions[targetUserId] or self._live[targetUserId] then
		return fail("target_busy")
	end
	local profile = self._profiles:get(userId) :: Profile?
	local targetProfile = self._profiles:get(targetUserId) :: Profile?
	if not profile or not targetProfile then
		return fail("no_profile")
	end
	if not activeStats(profile) then
		return fail("no_active_beast")
	end
	if not activeStats(targetProfile) then
		return fail("target_has_no_beast")
	end
	if not self._nearPad(userId, targetUserId) then
		return fail("not_on_pad")
	end
	self._challenges[targetUserId] = { from = userId, expiresAt = self._now() + CHALLENGE_TTL }
	self._push(targetUserId, "ChallengeIncoming", {
		fromUserId = userId,
		fromName = self._displayName(userId),
	})
	return { ok = true, pending = true }
end

function BattleService.respondChallenge(self: any, userId: number, accept: boolean): any
	local challenge = self._challenges[userId]
	if not challenge or self._now() > challenge.expiresAt then
		self._challenges[userId] = nil
		return fail("no_challenge")
	end
	self._challenges[userId] = nil
	local fromUserId = challenge.from
	if not accept then
		self._push(fromUserId, "ChallengeDeclined", {})
		return { ok = true, accepted = false }
	end
	if
		self._sessions[fromUserId]
		or self._live[fromUserId]
		or self._sessions[userId]
		or self._live[userId]
	then
		return fail("battle_in_progress")
	end
	local profileA = self._profiles:get(fromUserId) :: Profile?
	local profileB = self._profiles:get(userId) :: Profile?
	if not profileA or not profileB then
		return fail("no_profile")
	end
	local statsA = activeStats(profileA)
	local statsB = activeStats(profileB)
	if not statsA or not statsB then
		return fail("no_active_beast")
	end

	counter += 1
	local session: LiveSession = {
		battleId = `lv{counter}`,
		a = {
			userId = fromUserId,
			stats = statsA :: Stats,
			pick = nil,
			charged = nil,
			displayName = self._displayName(fromUserId),
		},
		b = {
			userId = userId,
			stats = statsB :: Stats,
			pick = nil,
			charged = nil,
			displayName = self._displayName(userId),
		},
		round = 1,
		scoreA = 0,
		scoreB = 0,
		tieStreak = 0,
		phase = "picking",
		flashDeadline = nil,
	}
	self._live[fromUserId] = session
	self._live[userId] = session
	for _, side in { session.a, session.b } do
		local opponent = if side.userId == session.a.userId then session.b else session.a
		self._push(side.userId, "LiveStarted", {
			battleId = session.battleId,
			opponentName = opponent.displayName,
			opponentStats = opponent.stats,
			yourStats = side.stats,
		})
	end
	return { ok = true, accepted = true, battleId = session.battleId }
end

local function liveSide(session: LiveSession, userId: number): (LiveSide, LiveSide)
	if session.a.userId == userId then
		return session.a, session.b
	end
	return session.b, session.a
end

function BattleService.livePick(self: any, userId: number, payload: any): any
	local session = self._live[userId] :: LiveSession
	if session.battleId ~= payload.battleId or session.phase ~= "picking" then
		return fail("wrong_phase")
	end
	local stat = payload.stat
	if stat ~= "li" and stat ~= "su" and stat ~= "zhi" then
		return fail("bad_request")
	end
	local mine = liveSide(session, userId)
	if mine.pick then
		return fail("already_picked")
	end
	mine.pick = stat
	local profile = self._profiles:get(userId) :: Profile?
	if profile then
		(profile.pickHistogram :: any)[stat] += 1
	end

	if session.a.pick and session.b.pick then
		-- both picks are in: flashes fire SIMULTANEOUSLY for both players,
		-- each from their own band/mode mix, same 4-second window (spec)
		session.phase = "flash"
		session.flashDeadline = self._now() + Config.Quiz.FLASH_SECONDS
		for _, side in { session.a, session.b } do
			local flash = self._quiz:generateFlash(side.userId)
			if not flash then
				side.charged = false
			end
			self._push(side.userId, "FlashPrompt", {
				battleId = session.battleId,
				flash = flash,
				deadline = session.flashDeadline,
			})
		end
		return { ok = true, waiting = false, deadline = session.flashDeadline }
	end
	return { ok = true, waiting = true }
end

function BattleService.liveFlash(self: any, userId: number, payload: any): any
	local session = self._live[userId] :: LiveSession
	if session.battleId ~= payload.battleId or session.phase ~= "flash" then
		return fail("wrong_phase")
	end
	local result = self._quiz:submitFlash(userId, payload)
	if not result.ok then
		return result
	end
	local mine = liveSide(session, userId)
	mine.charged = result.charged == true
	if session.a.charged ~= nil and session.b.charged ~= nil then
		BattleService.liveResolve(self, userId, { battleId = session.battleId })
	end
	return { ok = true, charged = mine.charged }
end

function BattleService.liveResolve(self: any, userId: number, payload: any): any
	local session = self._live[userId] :: LiveSession?
	if not session or session.battleId ~= payload.battleId then
		return fail("no_battle")
	end
	if session.phase ~= "flash" then
		return fail("wrong_phase")
	end
	local now = self._now()
	if session.a.charged == nil or session.b.charged == nil then
		if now < (session.flashDeadline :: number) then
			return fail("flash_pending")
		end
		session.a.charged = session.a.charged or false
		session.b.charged = session.b.charged or false
	end

	local result = Resolver.resolveRound({
		stat = session.a.pick :: Types.Stat,
		value = (session.a.stats :: any)[session.a.pick],
		charged = session.a.charged :: boolean,
	}, {
		stat = session.b.pick :: Types.Stat,
		value = (session.b.stats :: any)[session.b.pick],
		charged = session.b.charged :: boolean,
	})

	local replay = false
	local stallWinner: ("a" | "b")? = nil
	if result.winner == "tie" then
		session.tieStreak += 1
		if session.tieStreak >= Config.Battle.MAX_TIE_REPLAYS then
			local totalsA = session.a.stats.li + session.a.stats.su + session.a.stats.zhi
			local totalsB = session.b.stats.li + session.b.stats.su + session.b.stats.zhi
			stallWinner = Resolver.breakStall(totalsA, totalsB)
			session.tieStreak = 0
		else
			replay = true
		end
	else
		session.tieStreak = 0
	end
	local roundWinner: ("a" | "b")? = if result.winner ~= "tie"
		then result.winner :: any
		else stallWinner
	if roundWinner == "a" then
		session.scoreA += 1
	elseif roundWinner == "b" then
		session.scoreB += 1
	end

	local target = Config.Battle.ROUNDS_TO_WIN
	local matchOver = session.scoreA >= target or session.scoreB >= target
	local matchPayloads: { [number]: any } = {}
	if matchOver then
		session.phase = "done"
		local winnerSide = if session.scoreA > session.scoreB then session.a else session.b
		local loserSide = if winnerSide == session.a then session.b else session.a
		for _, entry in { { side = winnerSide, won = true }, { side = loserSide, won = false } } do
			local profile = self._profiles:get(entry.side.userId) :: Profile?
			if profile then
				ProfileSchema.rollDaily(profile, now)
				local record = profile.battleRecord
				if entry.won then
					record.wins += 1
				else
					record.losses += 1
				end
				local code: Types.FaucetCode = if entry.won
					then "live_win"
					else "live_participation"
				local coin = Ledger.faucet(profile, code, {}, now)
				self._analytics:track(entry.side.userId, "faucet", code :: string, coin.delta, {})
				matchPayloads[entry.side.userId] = {
					playerWon = entry.won,
					bountyMath = if coin.delta > 0 then coin.mathString else nil,
					capNote = if coin.capped
						then "今天的对战奖励拿满啦! (live coins capped)"
						else nil,
					newCoins = profile.coins,
					record = record,
				}
			end
		end
		self._live[session.a.userId] = nil
		self._live[session.b.userId] = nil
	else
		if not replay then
			session.round += 1
		end
		session.phase = "picking"
		session.a.pick = nil
		session.a.charged = nil
		session.b.pick = nil
		session.b.charged = nil
		session.flashDeadline = nil
	end

	for _, side in { session.a, session.b } do
		local isA = side == session.a
		local mineReveal = if isA then result.a else result.b
		local theirsReveal = if isA then result.b else result.a
		local winnerForMe = if roundWinner == nil
			then "tie"
			elseif (roundWinner == "a") == isA then "a"
			else "b"
		self._push(side.userId, "RoundResult", {
			battleId = session.battleId,
			round = session.round,
			you = mineReveal,
			them = theirsReveal,
			winner = winnerForMe,
			replay = replay,
			score = {
				you = if isA then session.scoreA else session.scoreB,
				them = if isA then session.scoreB else session.scoreA,
			},
			match = matchPayloads[side.userId],
		})
	end
	return { ok = true, pushed = true }
end

return BattleService
