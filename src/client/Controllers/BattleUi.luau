--!strict
-- Battle screens: the 12-rung ladder, secret stat pick, the 4-second charge
-- flash, simultaneous reveal with the ×2 math shown, and the match result.
-- The server computes everything; this renders responses and enforces nothing.

local Players = game:GetService("Players")

local Audio = require("./Audio")
local Ui = require("./Ui")

local BattleUi = {}

type Remotes = {
	ladder: RemoteFunction,
	startNpc: RemoteFunction,
	pickStat: RemoteFunction,
	submitFlash: RemoteFunction,
	resolveRound: RemoteFunction,
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
local flashButtons: { TextButton } = {}
local flashBar: Frame
local revealLabel: TextLabel
local resultOverlay: Frame
local resultLabel: TextLabel

local battleId: string? = nil
local currentRound = 1
local currentDeadline = 0
local currentFlashSound: string? = nil
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
	ladderRows = Ui.new(
		"ScrollingFrame",
		{
			Size = UDim2.new(1, 0, 1, -44),
			Position = UDim2.new(0, 0, 0, 40),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Parent = ladderPage,
		},
		{
			Ui.new(
				"UIListLayout",
				{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }
			),
		}
	)

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
	for index = 1, 3 do
		local button = Ui.button({
			Text = "",
			Size = UDim2.new(1, 0, 0, 70),
			Position = UDim2.new(0, 0, 0, 210 + (index - 1) * 80),
			TextSize = 40,
			Parent = flashOverlay,
		})
		button.Activated:Connect(function()
			BattleUi.answerFlashIndexed(index)
		end)
		flashButtons[index] = button
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
	currentDeadline = picked.deadline
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
	flashPrompt.Visible = flash.mode ~= "listen-char"
	flashListen.Visible = flash.mode == "listen-char"
	flashPrompt.Text = flash.prompt.char or ""
	if flash.mode == "listen-char" or flash.prompt.soundId then
		Audio.play(flash.prompt.soundId)
	end
	for index, button in flashButtons do
		local choice = flash.choices[index]
		button.Visible = choice ~= nil
		button.BackgroundColor3 = Ui.COLORS.accent
		if choice then
			button.Text = choice.display
			button.TextSize = if choice.kind == "pinyin" then 30 else 40
		end
	end
	-- countdown bar → auto-resolve at the deadline (client clock approximates
	-- the server's unix deadline; the server enforces the real one)
	local myBattle = battleId
	task.spawn(function()
		while flashOverlay.Visible and battleId == myBattle do
			local fraction = math.clamp((currentDeadline - os.time()) / 4, 0, 1)
			flashBar.Size = UDim2.new(fraction, 0, 0, 10)
			if os.time() >= currentDeadline then
				flashOverlay.Visible = false
				BattleUi.resolve()
				break
			end
			task.wait(0.1)
		end
	end)
end

local currentQuestionId: string? = nil

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
	task.delay(0.4, function()
		BattleUi.resolve()
	end)
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

function BattleUi.open()
	gui.Enabled = true
	fightPage.Visible = false
	resultOverlay.Visible = false
	ladderPage.Visible = true
	BattleUi.renderLadder()
end

return BattleUi
