--!strict
-- The Mission Kiosk screen: prompt card (character on a 田字格 grid / 🔊 listen
-- button / icon pictures), three tactile choice controls (stacked pills for text,
-- square tiles for pictures), feedback states with motion, level-up overlay. Pure
-- render + tap callback; every outcome decision arrives from the server.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Audio = require("./Audio")
local Ui = require("./Ui")

local QuizUi = {}

local CARD_W, CARD_H = 420, 548
local PAD = 16
local INNER = CARD_W - PAD * 2
local EDGE = 5 -- press-depth of tactile buttons

type Choice = {
	holder: Frame,
	face: TextButton,
	edge: Frame,
	icon: ImageLabel,
	scale: UIScale,
}

local gui: ScreenGui
local card: Frame
local promptChar: TextLabel
local promptPinyin: TextLabel
local promptListen: TextButton
local promptIcons: Frame
local specimen: Frame
local modeHint: TextLabel
local railCoin: TextLabel
local railStreak: TextLabel
local railWarm: TextLabel
local choices: { Choice } = {}
local feedback: TextLabel
local waitingCard: Frame
local onTap: ((index: number) -> ())? = nil
local currentSoundId: string? = nil

-- ── tactile button: a face that presses down onto a darker edge ──────────────
local function makeTactile(parent: Instance, index: number): Choice
	local holder = Ui.new("Frame", {
		Name = "Choice" .. index,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	local edge = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 1, -EDGE),
		Position = UDim2.new(0, 0, 0, EDGE),
		BackgroundColor3 = Ui.COLORS.accentEdge,
		BorderSizePixel = 0,
		Parent = holder,
	}, { Ui.corner(16) })
	local face = Ui.new("TextButton", {
		Size = UDim2.new(1, 0, 1, -EDGE),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Ui.COLORS.accent,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = Ui.FONT,
		TextColor3 = Ui.COLORS.ink,
		Text = "",
		Parent = holder,
	}, { Ui.corner(16) })
	local scale = Ui.new("UIScale", { Scale = 1, Parent = face })
	local icon = Ui.new("ImageLabel", {
		Size = UDim2.new(0, 68, 0, 68),
		Position = UDim2.new(0.5, -34, 0.5, -34),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = face,
	})

	-- press depth
	face.MouseButton1Down:Connect(function()
		face.Position = UDim2.new(0, 0, 0, EDGE)
	end)
	local function lift()
		face.Position = UDim2.new(0, 0, 0, 0)
	end
	face.MouseButton1Up:Connect(lift)
	face.MouseLeave:Connect(lift)
	face.Activated:Connect(function()
		local cb = onTap
		if cb then
			cb(index)
		end
	end)

	return { holder = holder, face = face, edge = edge, icon = icon, scale = scale }
end

local function setFace(c: Choice, faceColor: Color3, edgeColor: Color3)
	c.face.BackgroundColor3 = faceColor
	c.edge.BackgroundColor3 = edgeColor
end

local function pop(c: Choice)
	c.scale.Scale = 1
	local up = TweenService:Create(
		c.scale,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.08 }
	)
	up.Completed:Connect(function()
		TweenService:Create(c.scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	up:Play()
end

local function shake(c: Choice)
	local base = c.holder.Position
	local seq = { 8, -8, 6, -4, 0 }
	local i = 0
	local function step()
		i += 1
		if i > #seq then
			c.holder.Position = base
			return
		end
		local t = TweenService:Create(
			c.holder,
			TweenInfo.new(0.05),
			{ Position = base + UDim2.fromOffset(seq[i], 0) }
		)
		t.Completed:Connect(step)
		t:Play()
	end
	step()
end

-- reward-rail chip: an auto-width pill with tinted text
local function makeChip(rail: Instance, textColor: Color3): TextLabel
	local pill = Ui.new("Frame", {
		BackgroundColor3 = Ui.COLORS.cardDim,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 26),
		Parent = rail,
	}, {
		Ui.corner(13),
		Ui.new("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
	})
	return Ui.text({
		Text = "",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextSize = 15,
		TextWrapped = false,
		TextColor3 = textColor,
		Parent = pill,
	})
end

function QuizUi.init(onChoiceTap: (index: number) -> (), onClose: () -> ())
	onTap = onChoiceTap
	gui = Ui.new("ScreenGui", {
		Name = "MissionKiosk",
		ResetOnSpawn = false,
		Enabled = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
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
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Position = UDim2.new(0.5, -CARD_W / 2, 0.5, -CARD_H / 2),
		BackgroundColor3 = Ui.COLORS.card,
		BorderSizePixel = 0,
		Parent = scrim,
	}, { Ui.corner(24), Ui.padding(PAD) })

	Ui.button({
		Text = "×",
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.new(1, -38, 0, 0),
		TextSize = 30,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Parent = card,
	}).Activated
		:Connect(onClose)

	-- ── reward rail (coins / streak / warm-up) ────────────────────────────────
	local rail = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -46, 0, 26),
		Position = UDim2.new(0, 0, 0, 2),
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	railCoin = makeChip(rail, Color3.fromRGB(138, 106, 0))
	railStreak = makeChip(rail, Color3.fromRGB(181, 80, 47))
	railWarm = makeChip(rail, Ui.COLORS.ink)
	railWarm.Parent.BackgroundColor3 = Ui.COLORS.accent
	railWarm.Parent.Visible = false

	modeHint = Ui.text({
		Text = "",
		Size = UDim2.new(1, -46, 0, 24),
		Position = UDim2.new(0, 0, 0, 34),
		TextSize = 18,
		TextColor3 = Ui.COLORS.inkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	-- ── specimen card ───────────────────────────────────────────────────────
	specimen = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 196),
		Position = UDim2.new(0, 0, 0, 64),
		BackgroundColor3 = Ui.COLORS.cardDim,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = card,
	}, { Ui.corner(18) })

	-- 田字格 practice grid (faint square + centre cross)
	local grid = Ui.new("Frame", {
		Size = UDim2.fromOffset(150, 150),
		Position = UDim2.new(0.5, -75, 0.5, -80),
		BackgroundTransparency = 1,
		Parent = specimen,
	}, {
		Ui.new("UIStroke", { Color = Ui.COLORS.grid, Thickness = 2, Transparency = 0.15 }),
	})
	Ui.new("Frame", { -- vertical
		Size = UDim2.new(0, 2, 1, 0),
		Position = UDim2.new(0.5, -1, 0, 0),
		BackgroundColor3 = Ui.COLORS.grid,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = grid,
	})
	Ui.new("Frame", { -- horizontal
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.new(0, 0, 0.5, -1),
		BackgroundColor3 = Ui.COLORS.grid,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = grid,
	})

	promptChar = Ui.text({
		Text = "",
		Size = UDim2.fromOffset(150, 150),
		Position = UDim2.new(0.5, -75, 0.5, -80),
		TextScaled = true,
		Visible = false,
		Parent = specimen,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 140 }) })
	promptPinyin = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 1, -32),
		TextSize = 20,
		TextColor3 = Ui.COLORS.teal,
		Visible = false,
		Parent = specimen,
	})
	promptListen = Ui.button({
		Text = "🔊",
		Size = UDim2.fromOffset(120, 120),
		Position = UDim2.new(0.5, -60, 0.5, -60),
		TextSize = 64,
		BackgroundColor3 = Ui.COLORS.card,
		Visible = false,
		Parent = specimen,
	})
	promptListen.Activated:Connect(function()
		Audio.play(currentSoundId)
	end)
	promptIcons = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = specimen,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})

	-- ── three choice controls (repositioned per mode) ───────────────────────
	for index = 1, 3 do
		choices[index] = makeTactile(card, index)
	end

	feedback = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 1, -26),
		TextSize = 20,
		TextColor3 = Ui.COLORS.inkSoft,
		Parent = card,
	})

	waitingCard = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.COLORS.card,
		Visible = false,
		Parent = card,
	}, { Ui.corner(24) })
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

-- Reward rail: coins / streak / warm-up ×2 (nil leaves a chip unchanged).
function QuizUi.setMeta(coins: number?, streak: number?, warmup: number?)
	if railCoin and coins then
		railCoin.Text = `🪙 {coins}`
	end
	if railStreak and streak then
		railStreak.Text = `🔥 {streak}`
	end
	if railWarm and warmup ~= nil then
		railWarm.Parent.Visible = warmup > 0
		railWarm.Text = `×2 · {warmup}`
	end
end

-- Stacked pills for text/pinyin; a row of square tiles for pictures.
local function layoutChoices(asTiles: boolean, count: number)
	if asTiles then
		local size = math.floor((INNER - 8 * (count - 1)) / count)
		local top = 276 + math.floor((196 - size) / 2)
		for i = 1, count do
			local c = choices[i]
			c.holder.Size = UDim2.fromOffset(size, size + EDGE)
			c.holder.Position = UDim2.fromOffset((i - 1) * (size + 8), top)
		end
	else
		local h = 60
		for i = 1, count do
			local c = choices[i]
			c.holder.Size = UDim2.new(1, 0, 0, h + EDGE)
			c.holder.Position = UDim2.new(0, 0, 0, 280 + (i - 1) * (h + 12))
		end
	end
end

function QuizUi.render(question: any)
	waitingCard.Visible = false
	modeHint.Text = MODE_HINTS[question.mode] or ""
	feedback.Text = ""
	currentSoundId = question.prompt.soundId
	QuizUi.setMeta(nil, nil, question.warmupRemaining)

	promptChar.Visible = false
	promptPinyin.Visible = false
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
			local dim = 96 // math.max(1, count // 4)
			Ui.new("ImageLabel", {
				Size = UDim2.fromOffset(dim, dim),
				Image = question.prompt.icon or "",
				BackgroundTransparency = 1,
				Parent = promptIcons,
			})
		end
	else
		promptChar.Visible = true
		promptChar.Text = question.prompt.char or ""
		if question.prompt.pinyin then -- present only if the server includes it
			promptPinyin.Visible = true
			promptPinyin.Text = question.prompt.pinyin
		end
		Audio.play(currentSoundId)
	end

	local asTiles = question.choices[1] ~= nil and question.choices[1].kind == "icon"
	layoutChoices(asTiles, #question.choices)

	for index, c in choices do
		local choice = question.choices[index]
		c.holder.Visible = choice ~= nil
		c.holder.Position = UDim2.new(
			c.holder.Position.X.Scale,
			c.holder.Position.X.Offset,
			c.holder.Position.Y.Scale,
			c.holder.Position.Y.Offset
		) -- reset any shake offset baseline
		c.face.Position = UDim2.new(0, 0, 0, 0)
		c.scale.Scale = 1
		setFace(c, Ui.COLORS.accent, Ui.COLORS.accentEdge)
		c.icon.Visible = false
		if choice then
			if choice.kind == "icon" then
				c.face.Text = ""
				c.icon.Visible = true
				c.icon.Image = choice.display
			else
				c.face.Text = choice.display
				c.face.TextSize = if choice.kind == "pinyin" then 30 else 42
			end
		end
	end
end

function QuizUi.markWrong(index: number)
	local c = choices[index]
	setFace(c, Ui.COLORS.bad, Ui.COLORS.badEdge)
	shake(c)
	feedback.Text = "再试一次! Try once more — next miss shows the answer."
	Audio.wobble()
end

function QuizUi.reveal(correctIndex: number)
	local c = choices[correctIndex]
	setFace(c, Ui.COLORS.good, Ui.COLORS.goodEdge)
	pop(c)
	feedback.Text = "这个才对 — 记住它! That was the one."
	Audio.sad()
end

function QuizUi.celebrate(correctIndex: number)
	local c = choices[correctIndex]
	setFace(c, Ui.COLORS.good, Ui.COLORS.goodEdge)
	pop(c)
	Audio.happy()
end

function QuizUi.levelOverlay(text: string, up: boolean)
	local overlay = Ui.text({
		Text = text,
		Size = UDim2.new(1, 0, 0, 96),
		Position = UDim2.new(0, 0, 0.42, 0),
		TextSize = 42,
		BackgroundColor3 = if up then Ui.COLORS.good else Ui.COLORS.bad,
		BackgroundTransparency = 0.1,
		Parent = card,
	}, { Ui.corner(16) })
	local scale = Ui.new("UIScale", { Scale = 0.7, Parent = overlay })
	TweenService:Create(
		scale,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
	if up then
		Audio.fanfare()
	end
	task.delay(1.8, function()
		overlay:Destroy()
	end)
end

return QuizUi
