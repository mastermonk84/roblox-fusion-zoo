--!strict
-- Shared fixtures for quiz specs: the real curriculum plus synthetic manifests
-- (full coverage, partial coverage, empty) and a fresh profile.

local Curriculum = require("../../src/shared/Data/Curriculum")
local ProfileSchema = require("../../src/shared/ProfileSchema")
local Types = require("../../src/shared/Types")

type QuizItem = Types.QuizItem

local Helpers = {}

Helpers.NOW = 1787748347 -- 2026-08-26 UTC
Helpers.items = Curriculum :: { QuizItem }

function Helpers.fullManifests(): { audio: { [string]: string }, icons: { [string]: string } }
	local audio: { [string]: string } = {}
	local icons: { [string]: string } = {}
	for _, item in Helpers.items do
		if not item.grammar then
			audio[item.text] = `rbxassetid://1{item.seq}`
		end
		if item.needs_visual then
			icons[item.text] = `rbxassetid://2{item.seq}`
		end
	end
	return { audio = audio, icons = icons }
end

function Helpers.emptyManifests(): { audio: { [string]: string }, icons: { [string]: string } }
	return { audio = {}, icons = {} }
end

-- Audio for bands 1..n only, icons for everything visual.
function Helpers.partialManifests(
	maxBand: number
): { audio: { [string]: string }, icons: { [string]: string } }
	local full = Helpers.fullManifests()
	local audio: { [string]: string } = {}
	for _, item in Helpers.items do
		if item.band <= maxBand and full.audio[item.text] then
			audio[item.text] = full.audio[item.text]
		end
	end
	return { audio = audio, icons = full.icons }
end

function Helpers.freshProfile(seed: number): Types.Profile
	return ProfileSchema.template(seed, Helpers.NOW)
end

return Helpers
