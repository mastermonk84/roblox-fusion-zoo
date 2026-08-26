--!strict
-- Always-on HUD: coin counter, level chip, streak stars, and the floating
-- coin-math flash ("🪙 7 − 1 = 6") — the shown arithmetic is a design feature.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = require("./Ui")

local Hud = {}

local gui: ScreenGui
local coinLabel: TextLabel
local levelLabel: TextLabel
local starsLabel: TextLabel

function Hud.init()
	gui = Ui.new("ScreenGui", {
		Name = "FusionZooHud",
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	local bar = Ui.new("Frame", {
		Size = UDim2.new(0, 330, 0, 46),
		Position = UDim2.new(0, 12, 0, 12),
		BackgroundColor3 = Ui.COLORS.card,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		Ui.corner(12),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
		Ui.padding(8),
	})

	coinLabel = Ui.text({
		Text = "🪙 …",
		Size = UDim2.new(0, 90, 1, 0),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bar,
	})
	levelLabel = Ui.text({
		Text = "L1",
		Size = UDim2.new(0, 44, 1, 0),
		TextSize = 22,
		TextColor3 = Ui.COLORS.inkSoft,
		Parent = bar,
	})
	starsLabel = Ui.text({
		Text = "",
		Size = UDim2.new(0, 160, 1, 0),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bar,
	})
end

function Hud.setCoins(coins: number)
	coinLabel.Text = `🪙 {coins}`
end

function Hud.setLevel(level: number)
	levelLabel.Text = `L{level}`
end

function Hud.setStreak(streak: number, needed: number)
	local stars = ""
	for i = 1, needed do
		stars ..= if i <= streak then "⭐" else "☆"
	end
	starsLabel.Text = stars
end

-- kind: "earn" | "spend" | "sad" | "info"
function Hud.flash(text: string, kind: string)
	local colors: { [string]: Color3 } = {
		earn = Ui.COLORS.good,
		spend = Ui.COLORS.accent,
		sad = Ui.COLORS.bad,
		info = Ui.COLORS.cardDim,
	}
	local flashLabel = Ui.text({
		Text = text,
		Size = UDim2.new(0, 360, 0, 44),
		Position = UDim2.new(0.5, -180, 0, 70),
		TextSize = 30,
		BackgroundColor3 = colors[kind] or Ui.COLORS.cardDim,
		BackgroundTransparency = 0,
		Parent = gui,
	}, { Ui.corner(12) })
	local tween = TweenService:Create(
		flashLabel,
		TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -180, 0, 30), TextTransparency = 1, BackgroundTransparency = 1 }
	)
	tween:Play()
	task.delay(1.5, function()
		flashLabel:Destroy()
	end)
end

return Hud
