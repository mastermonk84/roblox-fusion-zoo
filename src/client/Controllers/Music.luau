--!strict
-- Background music: one scene track at a time with a short crossfade, plus a
-- one-shot victory sting. Tracks come from Data/MusicManifest; a track whose
-- soundId is unfilled ("") is silently skipped — the game is fully playable
-- with no music at all (same degradation posture as the audio manifest).
--
-- Scenes: "hub" (default wander), "kiosk" (quiz open), "battle" (match live).
-- sting() plays the victory bell over a ducked scene track, hard-capped at
-- the manifest's maxSeconds (the source clip is ~32s — too long for a sting).

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MusicManifest = require("../../shared/Data/MusicManifest")

local FADE_SECONDS = 0.8
local STING_DUCK = 0.25 -- scene volume multiplier while the sting plays

type Track = {
	soundId: string,
	loop: boolean,
	volume: number,
	maxSeconds: number?,
}

local Music = {}

local sounds: { [string]: Sound } = {}
local currentScene: string? = nil
local stingToken = 0
local ducked = false

local function trackFor(scene: string): Track?
	local track = (MusicManifest :: { [string]: Track })[scene]
	if track == nil or track.soundId == "" then
		return nil
	end
	return track
end

local function soundFor(scene: string): Sound?
	local existing = sounds[scene]
	if existing then
		return existing
	end
	local track = trackFor(scene)
	if not track then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = `Music_{scene}`
	sound.SoundId = track.soundId
	sound.Looped = track.loop
	sound.Volume = 0
	sound.Parent = SoundService
	sounds[scene] = sound
	return sound
end

local function fadeTo(sound: Sound, volume: number, seconds: number)
	TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = volume })
		:Play()
end

local function sceneVolume(scene: string): number
	local track = trackFor(scene)
	local base = if track then track.volume else 0
	return if ducked then base * STING_DUCK else base
end

-- Crossfade to the scene's track. Unknown/unfilled scenes fade everything out.
function Music.setScene(scene: string)
	if scene == currentScene then
		return
	end
	local previous = currentScene
	currentScene = scene
	if previous then
		local old = sounds[previous]
		if old then
			fadeTo(old, 0, FADE_SECONDS)
			task.delay(FADE_SECONDS + 0.1, function()
				if currentScene ~= previous and old.Volume < 0.01 then
					old:Stop()
				end
			end)
		end
	end
	local sound = soundFor(scene)
	if sound then
		if not sound.IsPlaying then
			sound.TimePosition = 0
			sound:Play()
		end
		fadeTo(sound, sceneVolume(scene), FADE_SECONDS)
	end
end

-- One-shot victory sting: duck the scene track, play the bell, fade it out at
-- the cap (or its natural end), restore the scene. Re-entrant: a new sting
-- restarts cleanly and cancels the previous restore.
function Music.sting()
	local track = trackFor("victory")
	if not track then
		return
	end
	local sound = soundFor("victory")
	if not sound then
		return
	end
	stingToken += 1
	local token = stingToken
	ducked = true
	if currentScene then
		local scene = sounds[currentScene]
		if scene then
			fadeTo(scene, sceneVolume(currentScene :: string), 0.3)
		end
	end
	sound:Stop()
	sound.TimePosition = 0
	sound.Volume = track.volume
	sound:Play()
	local cap = track.maxSeconds or 10
	task.delay(cap - 1, function()
		if token ~= stingToken then
			return
		end
		fadeTo(sound, 0, 1)
	end)
	task.delay(cap, function()
		if token ~= stingToken then
			return
		end
		sound:Stop()
		ducked = false
		if currentScene then
			local scene = sounds[currentScene]
			if scene then
				fadeTo(scene, sceneVolume(currentScene :: string), FADE_SECONDS)
			end
		end
	end)
end

function Music.init()
	Music.setScene("hub")
end

return Music
