--!strict
-- Two-tier mastery.
--   warm     = web's streak mastery (>= 3 clean solves). Pacing tier: drives
--              the 0.12 review weight and MIN_FRESH working-set expansion.
--   MASTERED = the credential: clean-solve evidence spanning >= 2 mode classes
--              AND >= 2 distinct UTC days. Items that can only ever serve one
--              class (grammar words) relax to >= 2 distinct days in that class.
-- Gates rescue, the /700 progress count, and the beast-naming pool.

local Config = require("../Config")
local Item = require("./Item")
local Types = require("../Types")

type Profile = Types.Profile
type CharState = Types.CharState
type QuizItem = Types.QuizItem

local Mastery = {}

local function stateFor(profile: Profile, text: string): CharState
	local state = profile.chars[text]
	if not state then
		state = {
			warm = 0,
			asked = 0,
			evidence = {},
			firstDay = nil,
			lastDay = nil,
			mastered = false,
		}
		profile.chars[text] = state
	end
	return state
end

local function distinctDays(state: CharState): number
	local days: { [string]: boolean } = {}
	for _, day in state.evidence do
		days[day] = true
	end
	local n = 0
	for _ in days do
		n += 1
	end
	-- Same-class clean solves on later days extend lastDay; count it too so a
	-- single-class item can satisfy the two-day rule.
	if state.firstDay and state.lastDay and state.firstDay ~= state.lastDay then
		n = math.max(n, 2)
	end
	return n
end

local function recompute(item: QuizItem, state: CharState): boolean
	local classes = 0
	for _ in state.evidence do
		classes += 1
	end
	local days = distinctDays(state)
	if Item.reachableClassCount(item) >= Config.Mastery.MODE_CLASSES_REQUIRED then
		return classes >= Config.Mastery.MODE_CLASSES_REQUIRED
			and days >= Config.Mastery.DAYS_REQUIRED
	end
	-- Single-class items: the two-DAY spacing still holds; two modes can't.
	return classes >= 1 and days >= Config.Mastery.DAYS_REQUIRED
end

function Mastery.recordClean(
	profile: Profile,
	item: QuizItem,
	mode: string,
	dayKey: string
): boolean
	local state = stateFor(profile, item.text)
	state.warm += 1
	state.asked += 1
	local class = Item.modeClass(mode)
	if state.evidence[class] == nil then
		state.evidence[class] = dayKey
	end
	state.firstDay = state.firstDay or dayKey
	state.lastDay = dayKey
	local was = state.mastered
	state.mastered = recompute(item, state)
	return state.mastered and not was -- true exactly when this solve MASTERED it
end

function Mastery.recordRetry(profile: Profile, item: QuizItem)
	local state = stateFor(profile, item.text)
	state.asked += 1
	-- warm streak held, not reset (web behavior for retries)
end

function Mastery.recordMiss(profile: Profile, item: QuizItem)
	local state = stateFor(profile, item.text)
	state.asked += 1
	state.warm = 0
end

function Mastery.isMastered(profile: Profile, text: string): boolean
	local state = profile.chars[text]
	return state ~= nil and state.mastered
end

-- Working-set expansion (web behavior + deferral awareness): grow the prefix
-- by 8 while fewer than MIN_FRESH servable-and-unwarm items are in play. Items
-- deferred by missing assets/toggle don't count as fresh — but if the whole
-- set is deferred, don't chase the horizon.
function Mastery.expandWorkingSet(
	profile: Profile,
	deck: { QuizItem },
	manifests: Item.Manifests
): number
	local grew = 0
	while profile.unlocked < #deck do
		local fresh = 0
		local anyEligible = false
		local limit = math.min(#deck, math.max(Config.Quiz.UNLOCK_START, profile.unlocked))
		for i = 1, limit do
			local item = deck[i]
			if not Item.isDeferred(item, manifests, profile.pinyinMode) then
				anyEligible = true
				local state = profile.chars[item.text]
				local warm = state ~= nil and state.warm >= Config.Quiz.WARM_STREAK
				if not warm then
					fresh += 1
				end
			end
		end
		if not anyEligible or fresh >= Config.Quiz.MIN_FRESH then
			break
		end
		profile.unlocked = math.min(#deck, profile.unlocked + Config.Quiz.UNLOCK_PER_LEVEL)
		grew += Config.Quiz.UNLOCK_PER_LEVEL
	end
	return grew
end

-- Progress screen data: mastered counts per band over curriculum items only.
function Mastery.progress(
	profile: Profile,
	items: { QuizItem }
): {
	total: number,
	of: number,
	bands: { { band: number, mastered: number, of: number } },
	deferredByToggle: number,
}
	local bands: { { band: number, mastered: number, of: number } } = {}
	for band = 1, Config.Content.BANDS do
		bands[band] = { band = band, mastered = 0, of = 0 }
	end
	local total = 0
	local deferredByToggle = 0
	for _, item in items do
		if (item :: any).bonus then
			continue
		end
		local entry = bands[item.band]
		entry.of += 1
		if Mastery.isMastered(profile, item.text) then
			entry.mastered += 1
			total += 1
		end
		if item.grammar and not profile.pinyinMode then
			deferredByToggle += 1
		end
	end
	return {
		total = total,
		of = Config.Content.TOTAL_ITEMS,
		bands = bands,
		deferredByToggle = deferredByToggle,
	}
end

return Mastery
