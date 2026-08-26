--!strict
-- Per-item mode eligibility. This is where the spec's asset rules live:
--   listen    needs a SoundId in the audio manifest (and never grammar words)
--   picture   needs needs_visual AND an icon (or, later, a rig model)
--   pinyin    always possible (grammar words: ONLY this)
-- An item with zero currently-eligible modes is "deferred": skipped by the
-- sampler, excluded from freshness, surfaced on the progress screen.

local Types = require("../Types")

type QuizItem = Types.QuizItem

export type Manifests = {
	audio: { [string]: string },
	icons: { [string]: string },
}

local Item = {}

function Item.listenEligible(item: QuizItem, manifests: Manifests): boolean
	return not item.grammar and manifests.audio[item.text] ~= nil
end

function Item.pictureEligible(item: QuizItem, manifests: Manifests): boolean
	return item.needs_visual and manifests.icons[item.text] ~= nil
end

function Item.pinyinOnly(item: QuizItem): boolean
	return item.grammar
end

-- Which quiz modes can serve this item right now, given assets + the player's
-- pinyin toggle. Order matters nowhere; this is a set.
function Item.eligibleModes(
	item: QuizItem,
	manifests: Manifests,
	pinyinOn: boolean
): { [string]: boolean }
	local modes: { [string]: boolean } = {}
	if item.grammar then
		if pinyinOn then
			modes["char-pinyin"] = true
		end
		return modes
	end
	if Item.listenEligible(item, manifests) then
		modes["listen-char"] = true
	end
	if Item.pictureEligible(item, manifests) then
		modes["char-picture"] = true
		modes["picture-char"] = true
	end
	if pinyinOn then
		modes["char-pinyin"] = true
	end
	return modes
end

function Item.isDeferred(item: QuizItem, manifests: Manifests, pinyinOn: boolean): boolean
	return next(Item.eligibleModes(item, manifests, pinyinOn)) == nil
end

-- Mode classes for the mastery credential: both picture directions count once.
function Item.modeClass(mode: string): string
	if mode == "listen-char" then
		return "listen"
	elseif mode == "char-picture" or mode == "picture-char" then
		return "picture"
	end
	return "pinyin"
end

-- Classes this item could EVER serve (asset-independent): the mastery rule
-- needs to know whether two distinct classes are reachable in principle.
-- Non-grammar items always reach listen (audio will exist) and pinyin.
function Item.reachableClassCount(item: QuizItem): number
	if item.grammar then
		return 1
	end
	return if item.needs_visual then 3 else 2
end

return Item
