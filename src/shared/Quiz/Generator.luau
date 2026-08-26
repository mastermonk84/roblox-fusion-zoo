--!strict
-- One question, end to end: mode -> target -> distractors -> shuffled choices.
-- Consumed by BOTH mission questions and battle charge flashes; everything is
-- expressed against the QuizItem interface (never a bare char), so month-2
-- word items are a data addition.

local Config = require("../Config")
local Distractors = require("./Distractors")
local Item = require("./Item")
local ModePicker = require("./ModePicker")
local Rng = require("../Util/Rng")
local Sampler = require("./Sampler")
local Types = require("../Types")

type QuizItem = Types.QuizItem
type CharState = Types.CharState
type Question = Types.Question

local Generator = {}

export type View = {
	allItems: { QuizItem },
	workingSet: { QuizItem },
	states: { [string]: CharState },
	level: number,
	pinyinOn: boolean,
	manifests: Item.Manifests,
}

local counter = 0

function Generator.generate(view: View, recent: { string }, rand: Rng.Rand): Question?
	local counts = ModePicker.poolCounts(view.workingSet, view.manifests, view.pinyinOn)
	local mode = ModePicker.pick(view.level, view.pinyinOn, counts, rand)
	if not mode then
		return nil -- nothing eligible at all; caller shows the waiting state
	end
	local chosenMode = mode :: string

	local pool = Sampler.pool(view.workingSet, chosenMode, view.manifests, view.pinyinOn)
	local target = Sampler.pickTarget(pool, view.states, recent, rand)
	if not target then
		return nil
	end
	local chosenTarget = target :: QuizItem

	local choices =
		Distractors.choose(view.allItems, chosenTarget, chosenMode, view.manifests, rand)
	if #choices < Config.Quiz.CHOICES then
		return nil -- content invariant tests make this unreachable; degrade quietly
	end
	choices = Rng.seededShuffle(choices, rand)

	local correctIndex = 0
	for index, choice in choices do
		if choice.text == chosenTarget.text then
			correctIndex = index
			break
		end
	end

	counter += 1
	return {
		questionId = `q{counter}`,
		mode = chosenMode :: any,
		item = chosenTarget,
		choices = choices,
		correctIndex = correctIndex,
	}
end

return Generator
