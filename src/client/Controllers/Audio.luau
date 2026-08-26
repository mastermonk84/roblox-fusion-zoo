--!strict
-- SoundId playback with a small cache. Listen-mode prompts, replay buttons,
-- and reveal speech all come through here; a missing/empty id is a silent
-- no-op (criterion 9: never an error state).

local SoundService = game:GetService("SoundService")

local Audio = {}

local cache: { [string]: Sound } = {}

function Audio.play(soundId: string?)
	if not soundId or soundId == "" then
		return
	end
	local id = soundId :: string
	local sound = cache[id]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = 1
		sound.Parent = SoundService
		cache[id] = sound
	end
	sound:Play()
end

-- Cheap synth cues (correct/wrong/level-up) until bespoke SFX exist: pitched
-- variants of one rbxasset click so we ship zero external assets.
local function cue(pitch: number)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.PlaybackSpeed = pitch
	sound.Volume = 0.5
	sound.Parent = SoundService
	sound:Play()
	task.delay(2, function()
		sound:Destroy()
	end)
end

function Audio.happy()
	cue(1.2)
	task.delay(0.09, function()
		cue(1.5)
	end)
end

function Audio.wobble()
	cue(0.6)
end

function Audio.fanfare()
	for i, pitch in { 1.0, 1.26, 1.5, 2.0 } do
		task.delay(0.1 * (i - 1), function()
			cue(pitch)
		end)
	end
end

function Audio.sad()
	cue(0.5)
	task.delay(0.12, function()
		cue(0.4)
	end)
end

return Audio
