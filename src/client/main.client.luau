--!strict
-- Client boot: HUD, kiosk flow, progress board. The client renders and
-- requests; every number on screen came from a server response.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anim = require("./Controllers/Anim")
local Audio = require("./Controllers/Audio")
local Hud = require("./Controllers/Hud")
local ProgressUi = require("./Controllers/ProgressUi")
local QuizUi = require("./Controllers/QuizUi")
local ZooUi = require("./Controllers/ZooUi")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local quizFolder = remotes:WaitForChild("Quiz")
local requestQuestion = quizFolder:WaitForChild("RequestQuestion") :: RemoteFunction
local submitAnswer = quizFolder:WaitForChild("SubmitAnswer") :: RemoteFunction
local getSummary = remotes:WaitForChild("Progress"):WaitForChild("GetSummary") :: RemoteFunction
local readyEvent = remotes:WaitForChild("Profile"):WaitForChild("Ready") :: RemoteEvent
local zooFolder = remotes:WaitForChild("Zoo")

local currentQuestionId: string? = nil
local busy = false

local function nextQuestion()
	local result = requestQuestion:InvokeServer()
	if not result or not result.ok then
		return
	end
	if result.waiting then
		currentQuestionId = nil
		QuizUi.showWaiting()
		return
	end
	currentQuestionId = result.question.questionId
	QuizUi.render(result.question)
end

local function onChoiceTap(index: number)
	if busy or not currentQuestionId or not QuizUi.isOpen() then
		return
	end
	busy = true
	local result =
		submitAnswer:InvokeServer({ questionId = currentQuestionId, choiceIndex = index })
	busy = false
	if not result or not result.ok then
		return
	end

	if result.outcome == "retryPending" then
		QuizUi.markWrong(result.wrongIndex)
		return
	end

	-- terminal outcomes update the HUD from server numbers
	Hud.setCoins(result.newCoins)
	Hud.setLevel(result.newLevel)
	Hud.setStreak(result.cleanStreak, result.streakNeeded)

	if result.outcome == "clean" or result.outcome == "retry" then
		QuizUi.celebrate(index)
		if result.coinDelta > 0 then
			Hud.flash(result.coinMath, "earn")
		end
		if result.masteredNow then
			Hud.flash(`🏅 学会了 {result.masteredNow}! Mastered!`, "earn")
		end
		if result.levelUp then
			QuizUi.levelOverlay(`⬆ Level {result.newLevel}!`, true)
			if result.levelUpMath then
				task.delay(0.8, function()
					Hud.flash(result.levelUpMath, "earn")
				end)
			end
		end
		currentQuestionId = nil
		task.delay(if result.levelUp then 2.0 else 0.8, function()
			if QuizUi.isOpen() then
				nextQuestion()
			end
		end)
	elseif result.outcome == "miss" then
		QuizUi.reveal(result.correctIndex)
		Audio.play(result.revealSoundId)
		if result.coinDelta < 0 then
			Hud.flash(result.coinMath, "sad")
		end
		if result.levelDown then
			QuizUi.levelOverlay(`Level {result.newLevel} — 慢慢来!`, false)
		end
		currentQuestionId = nil
		task.delay(if result.levelDown then 2.2 else 1.6, function()
			if QuizUi.isOpen() then
				nextQuestion()
			end
		end)
	end
end

Hud.init()
QuizUi.init(onChoiceTap, function()
	QuizUi.close()
end)
ProgressUi.init(function()
	ProgressUi.close()
end)
ZooUi.init({
	rescueList = zooFolder:WaitForChild("GetRescueList") :: RemoteFunction,
	rescue = zooFolder:WaitForChild("Rescue") :: RemoteFunction,
	fuse = zooFolder:WaitForChild("Fuse") :: RemoteFunction,
	refuse = zooFolder:WaitForChild("Refuse") :: RemoteFunction,
	feedSlot = zooFolder:WaitForChild("FeedSlot") :: RemoteFunction,
	unlockSlot = zooFolder:WaitForChild("UnlockSlot") :: RemoteFunction,
	nameBeast = zooFolder:WaitForChild("NameBeast") :: RemoteFunction,
	setActive = zooFolder:WaitForChild("SetActiveBeast") :: RemoteFunction,
	snapshot = zooFolder:WaitForChild("GetSnapshot") :: RemoteFunction,
}, function(coins, mathString)
	Hud.setCoins(coins)
	if mathString then
		Hud.flash(mathString, "spend")
	end
end)
Anim.init()

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "KioskPrompt" then
		QuizUi.open()
		nextQuestion()
	elseif prompt.Name == "PenPrompt" then
		ZooUi.open("rescue")
	elseif prompt.Name == "LabPrompt" then
		ZooUi.open("fuse")
	elseif prompt.Name == "BoardPrompt" then
		local summary = getSummary:InvokeServer()
		if summary and summary.ok then
			ProgressUi.render(summary)
			ProgressUi.open()
		end
	end
end)

readyEvent.OnClientEvent:Connect(function(state)
	Hud.setCoins(state.coins)
	Hud.setLevel(state.level)
	Hud.setStreak(state.cleanStreak, 3)
end)

local player = Players.LocalPlayer
print(`[FusionZoo] client ready for {player.Name}`)
