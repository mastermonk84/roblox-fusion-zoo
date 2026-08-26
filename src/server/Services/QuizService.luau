--!strict
-- Server side of missions and (from M4) battle charge flashes. Owns the
-- pending-question tables — the correct index never leaves the server — and
-- routes every outcome through Leveling/Mastery/Ledger. Two namespaces share
-- one validation path: mission answers mint coins and touch mastery; flash
-- answers only report charged/uncharged.

local Config = require("../../shared/Config")
local Curriculum = require("../../shared/Data/Curriculum")
local AudioManifest = require("../../shared/Data/AudioManifest")
local IconManifest = require("../../shared/Data/IconManifest")
local Deck = require("../../shared/Quiz/Deck")
local Generator = require("../../shared/Quiz/Generator")
local Item = require("../../shared/Quiz/Item")
local Leveling = require("../../shared/Quiz/Leveling")
local Mastery = require("../../shared/Quiz/Mastery")
local Ledger = require("../../shared/Economy/Ledger")
local ProfileSchema = require("../../shared/ProfileSchema")
local Rng = require("../../shared/Util/Rng")
local Time = require("../../shared/Util/Time")
local Types = require("../../shared/Types")

type Profile = Types.Profile
type Question = Types.Question
type QuizItem = Types.QuizItem

local DEFAULT_MANIFESTS: Item.Manifests = { audio = AudioManifest, icons = IconManifest }
local ITEMS = Curriculum :: { QuizItem }

export type Pending = {
	question: Question,
	taps: number,
	wrongIndex: number?,
	namespace: "mission" | "flash",
	deadline: number?, -- flash only
}

local QuizService = {}
QuizService.__index = QuizService

export type Deps = {
	profiles: any, -- Services/Profiles
	analytics: any, -- Services/Analytics
	now: (() -> number)?, -- injectable clock for tests
	manifests: Item.Manifests?, -- injectable asset manifests for tests
}

function QuizService.new(deps: Deps)
	local self = setmetatable({
		_profiles = deps.profiles,
		_analytics = deps.analytics,
		_now = deps.now or os.time,
		_manifests = deps.manifests or DEFAULT_MANIFESTS,
		_pendingMission = {} :: { [number]: Pending },
		_pendingFlash = {} :: { [number]: Pending },
		_recent = {} :: { [number]: { string } },
		_rand = {} :: { [number]: Rng.Rand },
		_deckCache = {} :: { [number]: { QuizItem } },
	}, QuizService)
	return self
end

function QuizService.dropPlayer(self: any, userId: number)
	self._pendingMission[userId] = nil
	self._pendingFlash[userId] = nil
	self._recent[userId] = nil
	self._rand[userId] = nil
end

local function randFor(self: any, userId: number): Rng.Rand
	local rand = self._rand[userId]
	if not rand then
		-- Per-session stream; determinism only matters for the deck order.
		rand = Rng.mulberry32((self._now() * 977 + userId) % 4294967296)
		self._rand[userId] = rand
	end
	return rand
end

local function deckFor(self: any, profile: Profile): { QuizItem }
	local deck = self._deckCache[profile.seed]
	if not deck then
		deck = Deck.ordered(ITEMS, profile.seed)
		self._deckCache[profile.seed] = deck
	end
	return deck
end

local function viewFor(self: any, profile: Profile): Generator.View
	local deck = deckFor(self, profile)
	return {
		allItems = ITEMS,
		workingSet = Deck.workingSet(deck, profile.unlocked),
		states = profile.chars,
		level = profile.level,
		pinyinOn = profile.pinyinMode,
		manifests = self._manifests,
	}
end

-- What the client is allowed to see. Listen prompts carry ONLY the SoundId.
function QuizService.payloadFor(
	self: any,
	question: Question,
	warmupRemaining: number
): Types.QuestionPayload
	local audio = self._manifests.audio
	local icons = self._manifests.icons
	local item = question.item
	local mode = question.mode
	local prompt: any = {}
	if mode == "listen-char" then
		prompt.soundId = audio[item.text]
	elseif mode == "picture-char" then
		prompt.icon = icons[item.text]
		prompt.value = item.value
	else -- char-picture / char-pinyin show the target character
		prompt.char = item.text
		prompt.soundId = audio[item.text] -- replay button, when audio exists
	end

	local choices = {}
	for _, choice in question.choices do
		if mode == "char-picture" then
			table.insert(choices, {
				display = icons[choice.text] or "",
				kind = "icon",
				value = choice.value,
			})
		elseif mode == "char-pinyin" then
			table.insert(choices, { display = choice.pinyin, kind = "pinyin" })
		else
			table.insert(choices, { display = choice.text, kind = "char" })
		end
	end

	return {
		questionId = question.questionId,
		mode = mode,
		prompt = prompt,
		choices = choices,
		warmupRemaining = warmupRemaining,
	} :: any
end

local function warmupRemaining(profile: Profile): number
	return math.max(0, Config.Economy.WARMUP_DOUBLE_COUNT - profile.daily.warmupCount)
end

-- ── Missions ────────────────────────────────────────────────────────────────

function QuizService.requestQuestion(self: any, userId: number): any
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return { ok = false, err = "no_profile" }
	end
	ProfileSchema.rollDaily(profile, self._now())

	local recent = self._recent[userId]
	if not recent then
		recent = {}
		self._recent[userId] = recent
	end

	local question = Generator.generate(viewFor(self, profile), recent, randFor(self, userId))
	if not question then
		-- Everything currently deferred (no assets / pinyin off): friendly wait
		-- state, never an error (criterion 9).
		self._pendingMission[userId] = nil
		return { ok = true, waiting = true }
	end

	-- Re-requesting voids the previous question: no answer-scouting.
	self._pendingMission[userId] = { question = question, taps = 0, namespace = "mission" }

	table.insert(recent, question.item.text)
	if #recent > Config.Quiz.RECENT_RING then
		table.remove(recent, 1)
	end

	local payload = QuizService.payloadFor(self, question, warmupRemaining(profile))
	return { ok = true, question = payload }
end

function QuizService.submitAnswer(self: any, userId: number, payload: any): any
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return { ok = false, err = "no_profile" }
	end
	local pending = self._pendingMission[userId] :: Pending?
	if not pending or pending.question.questionId ~= payload.questionId then
		return { ok = false, err = "no_such_question" }
	end
	local index = payload.choiceIndex
	if
		type(index) ~= "number"
		or index ~= math.floor(index)
		or index < 1
		or index > #pending.question.choices
	then
		return { ok = false, err = "bad_request" }
	end
	if pending.taps >= 2 or index == pending.wrongIndex then
		return { ok = false, err = "no_taps_left" }
	end

	local now = self._now()
	ProfileSchema.rollDaily(profile, now)
	local question = pending.question
	local item = question.item
	local deckSize = #deckFor(self, profile)
	local dayKey = Time.dayKey(now)

	if index == question.correctIndex then
		local clean = pending.taps == 0
		self._pendingMission[userId] = nil
		local outcome: string, coin, masteredNow
		if clean then
			outcome = "clean"
			masteredNow = Mastery.recordClean(profile, item, question.mode, dayKey)
			coin = Ledger.faucet(profile, "clean_solve", {}, now)
		else
			outcome = "retry"
			Mastery.recordRetry(profile, item)
			coin = { delta = 0, mathString = `🪙 {profile.coins}` }
			masteredNow = false
		end
		ProfileSchema.recordAnswer(profile, clean)
		local events = Leveling.apply(profile, outcome :: any, deckSize)
		local levelUpCoin = nil
		if events.levelUp then
			levelUpCoin = Ledger.faucet(profile, "level_up", {}, now)
		end
		Mastery.expandWorkingSet(profile, deckFor(self, profile), self._manifests)
		self._analytics:track(
			userId,
			"quiz",
			outcome,
			coin.delta + (levelUpCoin and levelUpCoin.delta or 0),
			{
				text = item.text,
				mode = question.mode,
			}
		)
		return {
			ok = true,
			outcome = outcome,
			coinDelta = coin.delta,
			coinMath = coin.mathString,
			newCoins = profile.coins,
			levelUp = events.levelUp,
			levelDown = false,
			newLevel = profile.level,
			cleanStreak = profile.cleanStreak,
			streakNeeded = events.needed,
			levelUpMath = if levelUpCoin then levelUpCoin.mathString else nil,
			masteredNow = if masteredNow then item.text else nil,
			warmupRemaining = warmupRemaining(profile),
		}
	end

	if pending.taps == 0 then
		-- First wrong tap: free retry, nothing recorded (web behavior).
		pending.taps = 1
		pending.wrongIndex = index
		return { ok = true, outcome = "retryPending", wrongIndex = index }
	end

	-- Second wrong tap: reveal, -1 floored, mastery/leveling miss.
	self._pendingMission[userId] = nil
	local penalty = Ledger.missPenalty(profile)
	Mastery.recordMiss(profile, item)
	ProfileSchema.recordAnswer(profile, false)
	local events = Leveling.apply(profile, "miss", deckSize)
	self._analytics:track(
		userId,
		"quiz",
		"miss",
		penalty.delta,
		{ text = item.text, mode = question.mode }
	)
	return {
		ok = true,
		outcome = "miss",
		correctIndex = question.correctIndex,
		revealText = item.text,
		revealSoundId = self._manifests.audio[item.text],
		coinDelta = penalty.delta,
		coinMath = penalty.mathString,
		newCoins = profile.coins,
		levelUp = false,
		levelDown = events.levelDown,
		newLevel = profile.level,
		cleanStreak = profile.cleanStreak,
		streakNeeded = events.needed,
		warmupRemaining = warmupRemaining(profile),
	}
end

function QuizService.setPinyinMode(self: any, userId: number, enabled: boolean): any
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return { ok = false, err = "no_profile" }
	end
	profile.pinyinMode = enabled
	return { ok = true }
end

function QuizService.progressSummary(self: any, userId: number): any
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return { ok = false, err = "no_profile" }
	end
	local progress = Mastery.progress(profile, ITEMS)
	return {
		ok = true,
		total = progress.total,
		of = progress.of,
		bands = progress.bands,
		deferredByToggle = progress.deferredByToggle,
		level = profile.level,
		coins = profile.coins,
	}
end

-- ── Battle charge flashes (consumed by BattleService in M4) ────────────────

function QuizService.generateFlash(self: any, userId: number): (any, Pending?)
	local profile = self._profiles:get(userId) :: Profile?
	if not profile then
		return nil, nil
	end
	local question = Generator.generate(
		viewFor(self, profile),
		self._recent[userId] or {},
		randFor(self, userId)
	)
	if not question then
		return nil, nil
	end
	local pending: Pending = {
		question = question,
		taps = 0,
		namespace = "flash",
		deadline = self._now() + Config.Quiz.FLASH_SECONDS,
	}
	self._pendingFlash[userId] = pending
	return QuizService.payloadFor(self, question, 0), pending
end

-- Returns charged?, validated exactly like a mission answer but touching
-- nothing: no coins, no leveling, no mastery (spec).
function QuizService.submitFlash(self: any, userId: number, payload: any): any
	local pending = self._pendingFlash[userId] :: Pending?
	if not pending or pending.question.questionId ~= payload.questionId then
		return { ok = false, err = "no_such_question" }
	end
	self._pendingFlash[userId] = nil
	if self._now() > (pending.deadline :: number) then
		return { ok = true, charged = false, late = true }
	end
	local charged = payload.choiceIndex == pending.question.correctIndex
	return { ok = true, charged = charged }
end

return QuizService
