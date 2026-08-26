--!strict
-- Battle screens: the 12-rung ladder, secret stat pick, the 4-second charge
-- flash, simultaneous reveal with the ×2 math shown, and the match result.
-- The server computes everything; this renders responses and enforces nothing.

local Players = game:GetService("Players")

local Audio = require("./Audio")
local Cheers = require("../../shared/Data/Cheers")
local Ui = require("./Ui")

-- lightweight toast used by battle flows
local Hint = {}
function Hint.flash(text: string)
	local screenGui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	if not screenGui then
		return
	end
	local hud = screenGui:FindFirstChild("FusionZooHud")
	if not hud then
		return
	end
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 420, 0, 40)
	label.Position = UDim2.new(0.5, -210, 0, 120)
	label.BackgroundColor3 = Color3.fromRGB(240, 236, 228)
	label.TextColor3 = Color3.fromRGB(45, 41, 56)
	label.TextSize = 20
	label.Font = Enum.Font.SourceSansBold
	label.Text = text
	label.Parent = hud
	task.delay(2.2, function()
		label:Destroy()
	end)
end

local BattleUi = {}

type Remotes = {
	ladder: RemoteFunction,
	startNpc: RemoteFunction,
	startGhost: RemoteFunction,
	pickStat: RemoteFunction,
	submitFlash: RemoteFunction,
	resolveRound: RemoteFunction,
	challenge: RemoteFunction,
	respondChallenge: RemoteFunction,
	listOpponents: RemoteFunction,
	forfeit: RemoteFunction,
	events: RemoteEvent,
	cheer: RemoteEvent,
}

local remotes: Remotes
local onCoins: (coins: number, mathString: string?) -> ()

local gui: ScreenGui
local ladderPage: Frame
local ladderRows: Frame
local fightPage: Frame
local opponentLabel: TextLabel
local yourLabel: TextLabel
local scoreLabel: TextLabel
local statButtons: { [string]: TextButton } = {}
local flashOverlay: Frame
local flashPrompt: TextLabel
local flashListen: TextButton
local flashIcon: ImageLabel
local flashButtons: { TextButton } = {}
local flashButtonIcons: { ImageLabel } = {}
local flashBar: Frame
local revealLabel: TextLabel
local resultOverlay: Frame
local resultLabel: TextLabel

local battleId: string? = nil
local isLive = false
local currentRound = 1
local flashEndsAt = 0 -- os.clock() based: immune to device clock skew
local currentFlashSound: string? = nil
local currentQuestionId: string? = nil
local resolving = false

local STAT_ORDER = { "li", "su", "zhi" }
local STAT_TEXT: { [string]: string } = { li = "力 💪", su = "速 ⚡", zhi = "智 🧠" }

function BattleUi.init(
	battleRemotes: Remotes,
	coinCallback: (coins: number, mathString: string?) -> ()
)
	remotes = battleRemotes
	onCoins = coinCallback

	gui = Ui.new("ScreenGui", {
		Name = "BattleArena",
		ResetOnSpawn = false,
		Enabled = false,
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local scrim = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.COLORS.scrim,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local card = Ui.new("Frame", {
		Size = UDim2.new(0, 540, 0, 600),
		Position = UDim2.new(0.5, -270, 0.5, -300),
		BackgroundColor3 = Ui.COLORS.card,
		BorderSizePixel = 0,
		Parent = scrim,
	}, { Ui.corner(18), Ui.padding(12) })

	Ui.button({
		Text = "✕",
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(1, -44, 0, 0),
		TextSize = 22,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Parent = card,
	}).Activated
		:Connect(function()
			gui.Enabled = false
		end)

	-- ladder page
	ladderPage =
		Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = card })
	Ui.text({
		Text = "⚔️ 怪兽天梯 Monster Ladder",
		Size = UDim2.new(1, -50, 0, 34),
		TextSize = 24,
		Parent = ladderPage,
	})
	ladderRows = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.new(0, 0, 0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = ladderPage,
	}, {
		Ui.new(
			"UIListLayout",
			{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }
		),
	})

	-- fight page
	fightPage = Ui.new(
		"Frame",
		{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = card }
	)
	opponentLabel =
		Ui.text({ Text = "", Size = UDim2.new(1, 0, 0, 60), TextSize = 22, Parent = fightPage })
	scoreLabel = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0, 0, 0, 62),
		TextSize = 26,
		Parent = fightPage,
	})
	yourLabel = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 98),
		TextSize = 18,
		TextColor3 = Ui.COLORS.inkSoft,
		Parent = fightPage,
	})
	Ui.text({
		Text = "偷偷选一张卡! Pick your card in secret:",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 0, 150),
		TextSize = 18,
		Parent = fightPage,
	})
	for index, stat in STAT_ORDER do
		local button = Ui.button({
			Text = STAT_TEXT[stat],
			Size = UDim2.new(0, 150, 0, 110),
			Position = UDim2.new(0, 10 + (index - 1) * 168, 0, 184),
			TextSize = 30,
			Parent = fightPage,
		})
		button.Activated:Connect(function()
			BattleUi.pick(stat)
		end)
		statButtons[stat] = button
	end
	revealLabel = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 150),
		Position = UDim2.new(0, 0, 0, 320),
		TextSize = 26,
		Parent = fightPage,
	})

	-- flash overlay (the one place recognition IS the game)
	flashOverlay = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.COLORS.card,
		Visible = false,
		ZIndex = 6,
		Parent = card,
	}, { Ui.corner(18), Ui.padding(12) })
	Ui.text({
		Text = "⚡ 充能! Answer to CHARGE your card!",
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 20,
		Parent = flashOverlay,
	})
	flashBar = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 0, 34),
		BackgroundColor3 = Ui.COLORS.accent,
		BorderSizePixel = 0,
		Parent = flashOverlay,
	}, { Ui.corner(5) })
	flashPrompt = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 150),
		Position = UDim2.new(0, 0, 0, 52),
		TextSize = 100,
		Parent = flashOverlay,
	})
	flashListen = Ui.button({
		Text = "🔊",
		Size = UDim2.new(0, 110, 0, 110),
		Position = UDim2.new(0.5, -55, 0, 70),
		TextSize = 60,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Visible = false,
		Parent = flashOverlay,
	})
	flashListen.Activated:Connect(function()
		Audio.play(currentFlashSound)
	end)
	flashIcon = Ui.new("ImageLabel", {
		Size = UDim2.new(0, 130, 0, 130),
		Position = UDim2.new(0.5, -65, 0, 60),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = flashOverlay,
	})
	for index = 1, 3 do
		local button = Ui.button({
			Text = "",
			Size = UDim2.new(1, 0, 0, 70),
			Position = UDim2.new(0, 0, 0, 210 + (index - 1) * 80),
			TextSize = 40,
			Parent = flashOverlay,
		})
		local buttonIcon = Ui.new("ImageLabel", {
			Size = UDim2.new(0, 56, 0, 56),
			Position = UDim2.new(0.5, -28, 0.5, -28),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = button,
		})
		button.Activated:Connect(function()
			BattleUi.answerFlashIndexed(index)
		end)
		flashButtons[index] = button
		flashButtonIcons[index] = buttonIcon
	end

	-- match result overlay
	resultOverlay = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.COLORS.card,
		Visible = false,
		ZIndex = 8,
		Parent = card,
	}, { Ui.corner(18), Ui.padding(16) })
	resultLabel = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0.7, 0),
		TextSize = 34,
		Parent = resultOverlay,
	})
	local backButton = Ui.button({
		Text = "回天梯 Back to ladder",
		Size = UDim2.new(0.7, 0, 0, 50),
		Position = UDim2.new(0.15, 0, 0.8, 0),
		TextSize = 22,
		Parent = resultOverlay,
	})
	backButton.Activated:Connect(function()
		resultOverlay.Visible = false
		fightPage.Visible = false
		ladderPage.Visible = true
		BattleUi.renderLadder()
	end)

	-- cheer wheel: fixed catalog, shown while any battle screen is open
	local cheerBar = Ui.new("Frame", {
		Size = UDim2.new(0, 240, 0, 40),
		Position = UDim2.new(0.5, -120, 1, -46),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
	for _, cheer in Cheers :: { any } do
		local button = Ui.button({
			Text = cheer.emoji,
			Size = UDim2.new(0, 40, 0, 36),
			TextSize = 20,
			BackgroundColor3 = Ui.COLORS.cardDim,
			Parent = cheerBar,
		})
		button.Activated:Connect(function()
			remotes.cheer:FireServer({ cheerId = cheer.id })
		end)
	end
	remotes.cheer.OnClientEvent:Connect(function(payload)
		local cheerDef: any = nil
		for _, c in Cheers :: { any } do
			if c.id == payload.cheerId then
				cheerDef = c
			end
		end
		if cheerDef then
			Hint.flash(`{payload.fromName}: {cheerDef.text} {cheerDef.emoji}`)
		end
	end)

	-- live battle server pushes
	remotes.events.OnClientEvent:Connect(function(event: string, payload: any)
		if event == "ChallengeIncoming" then
			BattleUi.showChallenge(payload)
		elseif event == "ChallengeDeclined" then
			Hint.flash("对方拒绝了挑战 (declined)")
		elseif event == "LiveStarted" then
			gui.Enabled = true
			battleId = payload.battleId
			isLive = true
			currentRound = 1
			ladderPage.Visible = false
			resultOverlay.Visible = false
			fightPage.Visible = true
			revealLabel.Text = ""
			opponentLabel.Text =
				`⚔ 对战 {payload.opponentName}!\n对方: 力{payload.opponentStats.li} 速{payload.opponentStats.su} 智{payload.opponentStats.zhi}`
			yourLabel.Text =
				`你的兽: 力{payload.yourStats.li} 速{payload.yourStats.su} 智{payload.yourStats.zhi}`
			scoreLabel.Text = "0 : 0"
			BattleUi.setPickEnabled(true)
		elseif event == "FlashPrompt" then
			flashEndsAt = os.clock() + (payload.window or 4)
			if payload.flash then
				BattleUi.showFlashWithId(payload.flash)
			else
				-- no servable flash for us: still nudge the server after the
				-- window so a both-lapsed round can't stall the match
				task.delay((payload.window or 4) + 0.5, BattleUi.nudgeResolve)
			end
		elseif event == "RoundResult" then
			BattleUi.renderLiveRound(payload)
		elseif event == "LiveEnded" then
			isLive = false
			battleId = nil
			flashOverlay.Visible = false
			currentQuestionId = nil
			fightPage.Visible = false
			ladderPage.Visible = true
			Hint.flash("对方离开了 (opponent left)")
		end
	end)
end

-- incoming challenge dialog
local challengeFrame: Frame? = nil

function BattleUi.showChallenge(payload: any)
	gui.Enabled = true
	if challengeFrame then
		challengeFrame:Destroy()
	end
	local frame = Ui.new("Frame", {
		Size = UDim2.new(0, 340, 0, 150),
		Position = UDim2.new(0.5, -170, 0, 20),
		BackgroundColor3 = Ui.COLORS.accent,
		ZIndex = 10,
		Parent = gui,
	}, { Ui.corner(14), Ui.padding(10) })
	challengeFrame = frame
	Ui.text({
		Text = `⚔ {payload.fromName} 想跟你对战!`,
		Size = UDim2.new(1, 0, 0, 50),
		TextSize = 22,
		Parent = frame,
	})
	local accept = Ui.button({
		Text = "来! Accept",
		Size = UDim2.new(0.46, 0, 0, 44),
		Position = UDim2.new(0, 0, 1, -48),
		TextSize = 20,
		BackgroundColor3 = Ui.COLORS.good,
		Parent = frame,
	})
	local decline = Ui.button({
		Text = "不了 No",
		Size = UDim2.new(0.46, 0, 0, 44),
		Position = UDim2.new(0.54, 0, 1, -48),
		TextSize = 20,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Parent = frame,
	})
	accept.Activated:Connect(function()
		frame:Destroy()
		challengeFrame = nil
		remotes.respondChallenge:InvokeServer({ accept = true })
	end)
	decline.Activated:Connect(function()
		frame:Destroy()
		challengeFrame = nil
		remotes.respondChallenge:InvokeServer({ accept = false })
	end)
end

function BattleUi.renderLiveRound(payload: any)
	flashOverlay.Visible = false
	local you, them = payload.you, payload.them
	local verdict = if payload.winner == "a"
		then "你赢了这局! 🎉"
		elseif payload.winner == "b" then "对方赢了这局"
		else "平局! 再来!"
	revealLabel.Text =
		`你: {you.mathString}{if you.charged then " ⚡" else ""}\n对方: {them.mathString}{if them.charged
			then " ⚡"
			else ""}\n{verdict}`
	scoreLabel.Text = `{payload.score.you} : {payload.score.them}`
	if payload.match then
		local match = payload.match
		isLive = false
		battleId = nil
		task.delay(1.6, function()
			resultOverlay.Visible = true
			local lines = if match.playerWon
				then "🏆 胜利! VICTORY!"
				else "输了… 再练练!"
			if match.bountyMath then
				lines ..= `\n{match.bountyMath}`
				onCoins(match.newCoins, nil)
			end
			if match.capNote then
				lines ..= `\n{match.capNote}`
			end
			lines ..= `\n战绩: {match.record.wins}胜 {match.record.losses}负`
			resultLabel.Text = lines
			if match.playerWon then
				Audio.fanfare()
			end
		end)
	else
		currentRound = payload.round
		task.delay(1.4, function()
			BattleUi.setPickEnabled(true)
		end)
	end
end

function BattleUi.renderLadder()
	for _, child in ladderRows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local ladder = remotes.ladder:InvokeServer()
	if not ladder.ok then
		return
	end
	for _, rung in ladder.rungs :: { any } do
		local row = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 56),
			BackgroundColor3 = if rung.beaten
				then Ui.COLORS.good
				elseif rung.locked then Ui.COLORS.scrim
				else Ui.COLORS.cardDim,
			BackgroundTransparency = if rung.locked then 0.5 else 0,
			LayoutOrder = rung.rung,
			Parent = ladderRows,
		}, { Ui.corner(10) })
		local stars = string.rep("⚡", math.ceil(rung.chargeRate * 5))
		Ui.text({
			Text = `{rung.rung}. {rung.name} {if rung.beaten then "✅" else ""}`,
			Size = UDim2.new(0.5, 0, 1, 0),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if rung.locked then Ui.COLORS.card else Ui.COLORS.ink,
			Parent = row,
		}, { Ui.padding(8) })
		Ui.text({
			Text = if rung.locked
				then "🔒"
				else `力{rung.li} 速{rung.su} 智{rung.zhi} · {stars}`,
			Size = UDim2.new(0.3, 0, 1, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			TextSize = 15,
			TextColor3 = if rung.locked then Ui.COLORS.card else Ui.COLORS.inkSoft,
			Parent = row,
		})
		if not rung.locked and ladder.hasBeast then
			local fight = Ui.button({
				Text = "打! Fight",
				Size = UDim2.new(0, 90, 0, 38),
				Position = UDim2.new(1, -98, 0.5, -19),
				TextSize = 17,
				Parent = row,
			})
			fight.Activated:Connect(function()
				BattleUi.startNpc(rung.rung)
			end)
		end
	end
	-- ghost battle + live challenge entry points
	if ladder.hasBeast then
		local ghostRow = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 52),
			BackgroundColor3 = Ui.COLORS.cardDim,
			LayoutOrder = 100,
			Parent = ladderRows,
		}, { Ui.corner(10) })
		Ui.text({
			Text = "👻 幽灵兽 · 别的小朋友的兽 (他们睡觉时也在变强!)",
			Size = UDim2.new(1, -110, 1, 0),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = ghostRow,
		}, { Ui.padding(8) })
		local ghostFight = Ui.button({
			Text = "打! Fight",
			Size = UDim2.new(0, 90, 0, 38),
			Position = UDim2.new(1, -98, 0.5, -19),
			TextSize = 17,
			Parent = ghostRow,
		})
		ghostFight.Activated:Connect(function()
			BattleUi.startGhostBattle()
		end)

		local pvpRow = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 52),
			BackgroundColor3 = Ui.COLORS.cardDim,
			LayoutOrder = 101,
			Parent = ladderRows,
		}, { Ui.corner(10) })
		Ui.text({
			Text = "⚔ 挑战朋友 · 两人都站上挑战台!",
			Size = UDim2.new(1, -110, 1, 0),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = pvpRow,
		}, { Ui.padding(8) })
		local pvpButton = Ui.button({
			Text = "挑战!",
			Size = UDim2.new(0, 90, 0, 38),
			Position = UDim2.new(1, -98, 0.5, -19),
			TextSize = 17,
			Parent = pvpRow,
		})
		pvpButton.Activated:Connect(function()
			BattleUi.openChallengeList()
		end)
	end
	if not ladder.hasBeast then
		local note = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 44),
			BackgroundColor3 = Ui.COLORS.accent,
			LayoutOrder = 0,
			Parent = ladderRows,
		}, { Ui.corner(10) })
		Ui.text({
			Text = "先去融合屋造一只兽! Fuse a beast first!",
			Size = UDim2.fromScale(1, 1),
			TextSize = 18,
			Parent = note,
		})
	end
end

function BattleUi.startNpc(rung: number)
	local started = remotes.startNpc:InvokeServer({ rung = rung })
	if not started.ok then
		Audio.wobble()
		return
	end
	battleId = started.battleId
	isLive = false
	currentRound = 1
	ladderPage.Visible = false
	fightPage.Visible = true
	revealLabel.Text = ""
	local opponent = started.opponent
	opponentLabel.Text =
		`{opponent.name} ({opponent.pinyin})\n力{opponent.li} 速{opponent.su} 智{opponent.zhi} · 充能{string.rep(
			"⚡",
			math.ceil(opponent.chargeRate * 5)
		)}`
	yourLabel.Text =
		`你的兽: 力{started.yourStats.li} 速{started.yourStats.su} 智{started.yourStats.zhi}`
	scoreLabel.Text = "0 : 0"
	BattleUi.setPickEnabled(true)
end

function BattleUi.setPickEnabled(enabled: boolean)
	for _, button in statButtons do
		button.AutoButtonColor = enabled
		button.BackgroundColor3 = if enabled then Ui.COLORS.accent else Ui.COLORS.cardDim
	end
end

function BattleUi.pick(stat: string)
	if not battleId then
		return
	end
	local picked =
		remotes.pickStat:InvokeServer({ battleId = battleId, round = currentRound, stat = stat })
	if not picked.ok then
		Audio.wobble()
		return
	end
	BattleUi.setPickEnabled(false)
	if isLive then
		if picked.waiting then
			revealLabel.Text = "等对方出卡… (waiting for opponent)"
		end
		return -- flashes and results arrive as server pushes
	end
	flashEndsAt = os.clock() + (picked.window or 4)
	if picked.flash then
		BattleUi.showFlashWithId(picked.flash)
	else
		task.delay(0.5, function()
			BattleUi.resolve()
		end)
	end
end

function BattleUi.showFlash(flash: any)
	flashOverlay.Visible = true
	currentFlashSound = flash.prompt.soundId
	flashPrompt.Visible = false
	flashListen.Visible = false
	flashIcon.Visible = false
	if flash.mode == "listen-char" then
		flashListen.Visible = true
		Audio.play(currentFlashSound)
	elseif flash.mode == "picture-char" then
		flashIcon.Visible = true
		flashIcon.Image = flash.prompt.icon or ""
	else
		flashPrompt.Visible = true
		flashPrompt.Text = flash.prompt.char or ""
		Audio.play(currentFlashSound)
	end
	for index, button in flashButtons do
		local choice = flash.choices[index]
		button.Visible = choice ~= nil
		button.BackgroundColor3 = Ui.COLORS.accent
		flashButtonIcons[index].Visible = false
		if choice then
			if choice.kind == "icon" then
				button.Text = ""
				flashButtonIcons[index].Visible = true
				flashButtonIcons[index].Image = choice.display
			else
				button.Text = choice.display
				button.TextSize = if choice.kind == "pinyin" then 30 else 40
			end
		end
	end
	-- countdown on the LOCAL monotonic clock (window from the server), so a
	-- skewed device clock can't instantly close the flash; the server still
	-- enforces the real deadline
	local myBattle = battleId
	local windowSeconds = math.max(1, flashEndsAt - os.clock())
	task.spawn(function()
		while flashOverlay.Visible and battleId == myBattle do
			local remaining = flashEndsAt - os.clock()
			flashBar.Size =
				UDim2.new(math.clamp(remaining / math.max(1, windowSeconds), 0, 1), 0, 0, 10)
			if remaining <= 0 then
				flashOverlay.Visible = false
				BattleUi.nudgeResolve()
				break
			end
			task.wait(0.1)
		end
	end)
end

-- Ask the server to resolve once the window is over (NPC path resolves
-- directly; live path nudges the shared session in case both flashes lapsed).
function BattleUi.nudgeResolve()
	if not battleId then
		return
	end
	if isLive then
		task.delay(0.4, function()
			if isLive and battleId then
				remotes.resolveRound:InvokeServer({ battleId = battleId })
			end
		end)
	else
		BattleUi.resolve()
	end
end

function BattleUi.showFlashWithId(flash: any)
	currentQuestionId = flash.questionId
	BattleUi.showFlash(flash)
end

function BattleUi.answerFlashIndexed(index: number)
	if not battleId or not currentQuestionId then
		return
	end
	local result = remotes.submitFlash:InvokeServer({
		battleId = battleId,
		questionId = currentQuestionId,
		choiceIndex = index,
	})
	currentQuestionId = nil
	flashOverlay.Visible = false
	if result.ok and result.charged then
		Audio.happy()
		revealLabel.Text = "⚡ 充能成功! CHARGED!"
	else
		Audio.wobble()
		revealLabel.Text = "没充上… uncharged"
	end
	if not isLive then
		task.delay(0.4, function()
			BattleUi.resolve()
		end)
	end
end

function BattleUi.resolve()
	if not battleId or resolving then
		return
	end
	resolving = true
	local response = remotes.resolveRound:InvokeServer({ battleId = battleId })
	resolving = false
	if not response.ok then
		if response.err == "flash_pending" then
			task.delay(0.5, function()
				BattleUi.resolve()
			end)
		end
		return
	end

	local you, them = response.you, response.them
	local verdict = if response.winner == "a"
		then "你赢了这局! 🎉"
		elseif response.winner == "b" then "对方赢了这局"
		else "平局! 再来!"
	revealLabel.Text =
		`你: {you.mathString}{if you.charged then " ⚡" else ""}\n对方: {them.mathString}{if them.charged
			then " ⚡"
			else ""}\n{verdict}`
	scoreLabel.Text = `{response.score.you} : {response.score.them}`
	if response.winner == "a" then
		Audio.happy()
	elseif response.winner == "b" then
		Audio.sad()
	end

	if response.match then
		local match = response.match
		task.delay(1.6, function()
			resultOverlay.Visible = true
			local lines = if match.playerWon
				then "🏆 胜利! VICTORY!"
				else "输了… 喂喂你的兽再来!"
			if match.bountyMath then
				lines ..= `\n{match.bountyMath}`
				onCoins(match.newCoins, nil)
			end
			if match.rungAdvanced then
				lines ..= "\n⬆ 下一关解锁! Next monster unlocked!"
			end
			if match.capNote then
				lines ..= `\n{match.capNote}`
			end
			lines ..= `\n战绩: {match.record.wins}胜 {match.record.losses}负`
			resultLabel.Text = lines
			if match.playerWon then
				Audio.fanfare()
			end
		end)
	else
		if not response.replay then
			currentRound += 1
		end
		task.delay(1.4, function()
			BattleUi.setPickEnabled(true)
		end)
	end
end

function BattleUi.startGhostBattle()
	local started = remotes.startGhost:InvokeServer()
	if not started.ok then
		Audio.wobble()
		return
	end
	battleId = started.battleId
	isLive = false
	currentRound = 1
	ladderPage.Visible = false
	fightPage.Visible = true
	revealLabel.Text = ""
	local ghost = started.ghost
	local stars = string.rep("⚡", math.ceil(ghost.chargeRate * 5))
	opponentLabel.Text = `👻 {ghost.ownerDisplayName} 的幽灵兽{if ghost.golden
		then " 🌟"
		else ""}\n力{ghost.stats.li} 速{ghost.stats.su} 智{ghost.stats.zhi} · 充能{stars}\n(他学习越多, 兽越强!)`
	yourLabel.Text =
		`你的兽: 力{started.yourStats.li} 速{started.yourStats.su} 智{started.yourStats.zhi}`
	scoreLabel.Text = "0 : 0"
	BattleUi.setPickEnabled(true)
end

function BattleUi.openChallengeList()
	local list = remotes.listOpponents:InvokeServer()
	if not list.ok or #list.players == 0 then
		Hint.flash("没有别的玩家在线 (nobody else here)")
		return
	end
	for index, other in list.players :: { any } do
		if index > 4 then
			break
		end
		local row = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 44),
			BackgroundColor3 = Ui.COLORS.accent,
			LayoutOrder = 102 + index,
			Parent = ladderRows,
		}, { Ui.corner(10) })
		Ui.text({
			Text = other.name,
			Size = UDim2.new(1, -110, 1, 0),
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, { Ui.padding(8) })
		local send = Ui.button({
			Text = "挑战!",
			Size = UDim2.new(0, 90, 0, 32),
			Position = UDim2.new(1, -98, 0.5, -16),
			TextSize = 15,
			BackgroundColor3 = Ui.COLORS.good,
			Parent = row,
		})
		send.Activated:Connect(function()
			local result = remotes.challenge:InvokeServer({ targetUserId = other.userId })
			if result.ok then
				Hint.flash("挑战已发出! (challenge sent — both stand on the pad)")
			else
				Hint.flash(`不行: {result.err}`)
				Audio.wobble()
			end
		end)
	end
end

function BattleUi.open()
	gui.Enabled = true
	fightPage.Visible = false
	resultOverlay.Visible = false
	ladderPage.Visible = true
	BattleUi.renderLadder()
end

return BattleUi
