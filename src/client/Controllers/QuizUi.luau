--!strict
-- The Mission Kiosk screen: prompt card (character / 🔊 listen button / icon
-- pictures), three choice buttons, feedback states, level-up overlay. Pure
-- render + tap callback; every outcome decision arrives from the server.

local Players = game:GetService("Players")

local Audio = require("./Audio")
local Ui = require("./Ui")

local QuizUi = {}

local gui: ScreenGui
local promptChar: TextLabel
local promptListen: TextButton
local promptIcons: Frame
local modeHint: TextLabel
local choiceButtons: { TextButton } = {}
local choiceIcons: { ImageLabel } = {}
local feedback: TextLabel
local waitingCard: Frame
local card: Frame
local onTap: ((index: number) -> ())? = nil
local currentSoundId: string? = nil

function QuizUi.init(onChoiceTap: (index: number) -> (), onClose: () -> ())
	onTap = onChoiceTap
	gui = Ui.new("ScreenGui", {
		Name = "MissionKiosk",
		ResetOnSpawn = false,
		Enabled = false,
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	local scrim = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.COLORS.scrim,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = gui,
	})

	card = Ui.new("Frame", {
		Size = UDim2.new(0, 420, 0, 520),
		Position = UDim2.new(0.5, -210, 0.5, -260),
		BackgroundColor3 = Ui.COLORS.card,
		BorderSizePixel = 0,
		Parent = scrim,
	}, { Ui.corner(18), Ui.padding(14) })

	Ui.button({
		Text = "✕",
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(1, -44, 0, 4),
		TextSize = 22,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Parent = card,
	}).Activated
		:Connect(onClose)

	modeHint = Ui.text({
		Text = "",
		Size = UDim2.new(1, -60, 0, 26),
		TextSize = 18,
		TextColor3 = Ui.COLORS.inkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	-- prompt area (one of three renders is visible at a time)
	promptChar = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 170),
		Position = UDim2.new(0, 0, 0, 30),
		TextSize = 130,
		Visible = false,
		Parent = card,
	})
	promptListen = Ui.button({
		Text = "🔊",
		Size = UDim2.new(0, 130, 0, 130),
		Position = UDim2.new(0.5, -65, 0, 50),
		TextSize = 72,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Visible = false,
		Parent = card,
	})
	promptListen.Activated:Connect(function()
		Audio.play(currentSoundId)
	end)
	promptIcons = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 170),
		Position = UDim2.new(0, 0, 0, 30),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})

	-- three choice rows
	for index = 1, 3 do
		local button = Ui.button({
			Text = "",
			Size = UDim2.new(1, 0, 0, 74),
			Position = UDim2.new(0, 0, 0, 214 + (index - 1) * 84),
			TextSize = 44,
			Parent = card,
		})
		local icon = Ui.new("ImageLabel", {
			Size = UDim2.new(0, 60, 0, 60),
			Position = UDim2.new(0.5, -30, 0.5, -30),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = button,
		})
		button.Activated:Connect(function()
			local callback = onTap
			if callback then
				callback(index)
			end
		end)
		choiceButtons[index] = button
		choiceIcons[index] = icon
	end

	feedback = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 1, -30),
		TextSize = 20,
		TextColor3 = Ui.COLORS.inkSoft,
		Parent = card,
	})

	waitingCard = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.COLORS.card,
		Visible = false,
		Parent = card,
	}, { Ui.corner(18) })
	Ui.text({
		Text = "🎧 新的汉字内容马上就来!\nNew characters are on their way —\ncheck back soon!",
		Size = UDim2.fromScale(1, 1),
		TextSize = 26,
		Parent = waitingCard,
	})
end

function QuizUi.open()
	gui.Enabled = true
end

function QuizUi.close()
	gui.Enabled = false
end

function QuizUi.isOpen(): boolean
	return gui.Enabled
end

local MODE_HINTS: { [string]: string } = {
	["listen-char"] = "听一听, 选汉字 · Listen, pick the character",
	["char-picture"] = "这个字是什么? · Pick the picture",
	["picture-char"] = "看图选字 · Pick the character",
	["char-pinyin"] = "选拼音 · Pick the pinyin",
}

function QuizUi.showWaiting()
	waitingCard.Visible = true
end

function QuizUi.render(question: any)
	waitingCard.Visible = false
	modeHint.Text = MODE_HINTS[question.mode] or ""
	feedback.Text = ""
	currentSoundId = question.prompt.soundId

	promptChar.Visible = false
	promptListen.Visible = false
	promptIcons.Visible = false
	for _, child in promptIcons:GetChildren() do
		if child:IsA("ImageLabel") then
			child:Destroy()
		end
	end

	if question.mode == "listen-char" then
		promptListen.Visible = true
		Audio.play(currentSoundId)
	elseif question.mode == "picture-char" then
		promptIcons.Visible = true
		local count = question.prompt.value or 1
		for _ = 1, math.min(count, 10) do
			Ui.new("ImageLabel", {
				Size = UDim2.new(
					0,
					90 // math.max(1, count // 4),
					0,
					90 // math.max(1, count // 4)
				),
				Image = question.prompt.icon or "",
				BackgroundTransparency = 1,
				Parent = promptIcons,
			})
		end
	else
		promptChar.Visible = true
		promptChar.Text = question.prompt.char or ""
		Audio.play(currentSoundId)
	end

	for index, button in choiceButtons do
		local choice = question.choices[index]
		button.Visible = choice ~= nil
		button.BackgroundColor3 = Ui.COLORS.accent
		button.AutoButtonColor = true
		choiceIcons[index].Visible = false
		if choice then
			if choice.kind == "icon" then
				button.Text = ""
				choiceIcons[index].Visible = true
				choiceIcons[index].Image = choice.display
			else
				button.Text = choice.display
				button.TextSize = if choice.kind == "pinyin" then 32 else 44
			end
		end
	end
end

function QuizUi.markWrong(index: number)
	local button = choiceButtons[index]
	button.BackgroundColor3 = Ui.COLORS.bad
	button.AutoButtonColor = false
	feedback.Text = "再试一次! Try once more — next miss shows the answer."
	Audio.wobble()
end

function QuizUi.reveal(correctIndex: number)
	local button = choiceButtons[correctIndex]
	button.BackgroundColor3 = Ui.COLORS.good
	feedback.Text = "这个才对 — 记住它! That was the one."
	Audio.sad()
end

function QuizUi.celebrate(correctIndex: number)
	choiceButtons[correctIndex].BackgroundColor3 = Ui.COLORS.good
	Audio.happy()
end

function QuizUi.levelOverlay(text: string, up: boolean)
	local overlay = Ui.text({
		Text = text,
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.new(0, 0, 0.4, 0),
		TextSize = 44,
		BackgroundColor3 = if up then Ui.COLORS.good else Ui.COLORS.bad,
		BackgroundTransparency = 0.1,
		Parent = card,
	}, { Ui.corner(14) })
	if up then
		Audio.fanfare()
	end
	task.delay(1.8, function()
		overlay:Destroy()
	end)
end

return QuizUi
