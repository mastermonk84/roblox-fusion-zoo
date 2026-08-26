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
		_sessions = {} :: { [number]: Session }, -- one live battle per player
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

return BattleService
