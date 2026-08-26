--!strict
-- Every shared type in one place (spec requirement). Pure module: no engine types
-- beyond what both Roblox and Lune understand.

export type Stat = "li" | "su" | "zhi" -- 力 / 速 / 智
export type Slot = "head" | "body" | "legs" | "tail"
export type ModeClass = "listen" | "picture" | "pinyin"
export type QuizMode = "listen-char" | "char-picture" | "picture-char" | "char-pinyin"

-- Word-ready quiz item (v1 ships single characters; components > 1 arrives with
-- month-2 word flashes — everything downstream consumes this interface, never a
-- bare char field).
export type QuizItem = {
	text: string,
	components: { string },
	pinyin: string,
	english: string,
	band: number, -- 1..14, curriculum order
	seq: number, -- absolute 识字表 position 1..700 (primary sort)
	source: string, -- semester + lesson
	category: string, -- distractor ring 1 only
	needs_visual: boolean, -- gates picture modes ONLY
	grammar: boolean, -- function word: pinyin-mode only (spec hard rule)
	value: number?, -- numbers only: counting-picture repeat count
	confidence: string, -- "web" | "model" | "low" (review pipeline metadata)
}

export type Question = {
	questionId: string,
	mode: QuizMode,
	item: QuizItem,
	choices: { QuizItem }, -- index 1..3, shuffled
	correctIndex: number,
}

-- What the client is allowed to see of a Question.
export type QuestionPayload = {
	questionId: string,
	mode: QuizMode,
	prompt: {
		char: string?, -- char-picture / char-pinyin modes
		soundId: string?, -- listen mode: ONLY the sound, never the char
		pinyinFallback: string?,
	},
	choices: { { display: string, kind: string } },
	warmupRemaining: number,
}

export type CharState = {
	warm: number, -- consecutive clean solves (web mastery streak, the pacing tier)
	asked: number,
	evidence: { [string]: string }, -- modeClass -> earliest UTC dayKey with a clean solve
	firstDay: string?,
	lastDay: string?,
	mastered: boolean, -- cached MASTERED credential (two modes x two days; see Quiz/Mastery)
}

export type Beast = {
	id: string,
	name: string?, -- two mastered chars, bought; nil -> display derives from build
	slots: { head: string, body: string, legs: string?, tail: string? }, -- animal chars
	feed: { head: number, body: number, legs: number, tail: number }, -- feed belongs to the SLOT
	golden: boolean, -- real-word build variant
	colorway: string?,
	createdAt: number,
}

export type Daily = {
	dayKey: string,
	warmupCount: number,
	ghostCoins: number,
	liveCoins: number,
	ghostPayouts: { [string]: number }, -- ghostKey -> unix of last payout
}

export type Profile = {
	schemaVersion: number,
	createdAt: number,
	coins: number,
	level: number,
	cleanStreak: number,
	missStreak: number,
	seed: number,
	unlocked: number,
	pinyinMode: boolean,
	chars: { [string]: CharState },
	accuracy: { clean: number, total: number }, -- halved at window cap: rolling-ish
	daily: Daily,
	animals: { [string]: boolean }, -- owned animal chars
	beasts: { [string]: Beast },
	nextBeastId: number,
	activeBeastId: string?,
	slotsUnlocked: { legs: boolean, tail: boolean },
	ladderRung: number, -- highest NPC rung beaten, 0 = none
	battleRecord: { wins: number, losses: number },
	pickHistogram: { li: number, su: number, zhi: number }, -- feeds ghost pattern weighting
	realWordsFound: { [string]: boolean },
	decorations: { [string]: number },
	plotPlacements: { [string]: string }, -- grid index (as string key) -> itemId
	colorways: { [string]: boolean },
	tutorial: { grantsGiven: boolean, done: boolean },
}

export type Stats = { li: number, su: number, zhi: number }

export type AnimalDef = {
	char: string,
	pinyin: string,
	english: string,
	li: number,
	su: number,
	zhi: number,
	tier: number, -- rescue cost tier 1..5
	rig: string, -- RigData key
}

export type OpponentDef = {
	name: string,
	pinyin: string,
	li: number,
	su: number,
	zhi: number,
	rig: string?,
}

export type GhostSnapshot = {
	ownerUserId: number,
	ownerDisplayName: string,
	slots: { head: string, body: string, legs: string?, tail: string? },
	feed: { head: number, body: number, legs: number, tail: number },
	golden: boolean,
	stats: Stats,
	pickHistogram: { li: number, su: number, zhi: number },
	accuracy: number, -- clamped 0.2..0.9 at publish
	publishedAt: number,
}

export type BattleSide = {
	kind: "player" | "brain",
	userId: number?,
	brain: string?, -- "npc" | "ghost"
	stats: Stats,
	meta: { [string]: any },
}

export type RoundReveal = {
	stat: Stat,
	base: number,
	eff: number,
	charged: boolean,
	doubled: boolean,
	mathString: string,
}

export type FaucetCode =
	"clean_solve"
	| "level_up"
	| "npc_first_clear"
	| "ghost_win"
	| "live_win"
	| "live_participation"
	| "real_word"
	| "tutorial"

export type SinkCode =
	"rescue"
	| "feed"
	| "fuse"
	| "refuse"
	| "slot_unlock"
	| "name_beast"
	| "decoration"
	| "colorway"
	| "miss_penalty"

return {}
