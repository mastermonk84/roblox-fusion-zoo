--!strict
-- The leveling state machine, ported from the web engine's code (not its stale
-- README): cleanToAdvance {3,4,6,8,8}, 4 misses drop a level, +8 unlocked per
-- level-up, retry resets the clean streak, second-wrong resets it too.

local Config = require("../Config")
local Types = require("../Types")

type Profile = Types.Profile

local Leveling = {}

export type Outcome = "clean" | "retry" | "miss"

export type Events = {
	levelUp: boolean,
	levelDown: boolean,
	newLevel: number,
	cleanStreak: number,
	needed: number,
}

function Leveling.needed(level: number): number
	local ramp = Config.Quiz.CLEAN_TO_ADVANCE
	return ramp[math.min(level, #ramp)]
end

-- Mutates the leveling fields of the profile; mastery and coins are handled by
-- their own modules. deckSize caps unlocked growth.
function Leveling.apply(profile: Profile, outcome: Outcome, deckSize: number): Events
	local events: Events = {
		levelUp = false,
		levelDown = false,
		newLevel = profile.level,
		cleanStreak = profile.cleanStreak,
		needed = Leveling.needed(profile.level),
	}

	if outcome == "clean" then
		local newClean = profile.cleanStreak + 1
		local needed = Leveling.needed(profile.level)
		profile.missStreak = 0
		if newClean >= needed and profile.level < Config.Quiz.MAX_LEVEL then
			profile.level += 1
			profile.cleanStreak = 0
			profile.unlocked = math.min(deckSize, profile.unlocked + Config.Quiz.UNLOCK_PER_LEVEL)
			events.levelUp = true
		else
			-- At MAX_LEVEL the streak still wraps to zero (web behavior).
			profile.cleanStreak = if newClean >= needed then 0 else newClean
		end
	elseif outcome == "retry" then
		-- Correct on the second tap: no penalty, but the clean streak resets.
		profile.cleanStreak = 0
		profile.missStreak = 0
	else -- miss
		profile.cleanStreak = 0
		local newMiss = profile.missStreak + 1
		local drop = newMiss >= Config.Quiz.MISSES_TO_DROP and profile.level > 1
		if drop then
			profile.level -= 1
			events.levelDown = true
		end
		-- The counter resets at the threshold even at level 1 (web behavior).
		profile.missStreak = if newMiss >= Config.Quiz.MISSES_TO_DROP then 0 else newMiss
	end

	events.newLevel = profile.level
	events.cleanStreak = profile.cleanStreak
	events.needed = Leveling.needed(profile.level)
	return events
end

return Leveling
