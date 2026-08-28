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
local settingsCard: Frame? = nil

-- The parent-facing corner: pinyin-mode toggle behind a "pick the bigger
-- number" gate (same trick as the web version's parent panel).
function Hud.initSettings(setPinyin: RemoteFunction, getPinyin: () -> boolean)
	local gear = Ui.button({
		Text = "⚙",
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(1, -52, 0, 12),
		TextSize = 24,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Parent = gui,
	})
	gear.Activated:Connect(function()
		if settingsCard then
			settingsCard:Destroy()
			settingsCard = nil
			return
		end
		local bigger = math.random(30, 99)
		local smaller = math.random(10, bigger - 5)
		local flip = math.random() < 0.5
		local card = Ui.new("Frame", {
			Size = UDim2.new(0, 300, 0, 190),
			Position = UDim2.new(1, -312, 0, 60),
			BackgroundColor3 = Ui.COLORS.card,
			Parent = gui,
		}, { Ui.corner(14), Ui.padding(10) })
		settingsCard = card
		local prompt = Ui.text({
			Text = "家长: 点大的数字\nParents: tap the bigger number",
			Size = UDim2.new(1, 0, 0, 50),
			TextSize = 17,
			Parent = card,
		})
		local options = { if flip then bigger else smaller, if flip then smaller else bigger }
		for index, value in options do
			local button = Ui.button({
				Text = tostring(value),
				Size = UDim2.new(0.44, 0, 0, 54),
				Position = UDim2.new(if index == 1 then 0.02 else 0.54, 0, 0, 58),
				TextSize = 28,
				Parent = card,
			})
			button.Activated:Connect(function()
				if value ~= bigger then
					prompt.Text = "再试一次! Try again"
					return
				end
				-- unlocked: show the actual setting
				for _, child in card:GetChildren() do
					if child:IsA("TextButton") or child:IsA("TextLabel") then
						child:Destroy()
					end
				end
				local toggle: TextButton
				local function renderToggle()
					local on = getPinyin()
					toggle.Text = if on
						then "拼音题: 开 ✅ (Pinyin ON)"
						else "拼音题: 关 (Pinyin OFF)"
					toggle.BackgroundColor3 = if on then Ui.COLORS.good else Ui.COLORS.cardDim
				end
				Ui.text({
					Text = "拼音识字题 (孩子会拼音后再开)\nPinyin questions — enable once your child reads pinyin",
					Size = UDim2.new(1, 0, 0, 70),
					TextSize = 15,
					Parent = card,
				})
				toggle = Ui.button({
					Text = "",
					Size = UDim2.new(1, 0, 0, 46),
					Position = UDim2.new(0, 0, 0, 80),
					TextSize = 18,
					Parent = card,
				})
				toggle.Activated:Connect(function()
					local result = setPinyin:InvokeServer({ enabled = not getPinyin() })
					if result.ok then
						Hud.pinyinOn = not Hud.pinyinOn
						renderToggle()
					end
				end)
				renderToggle()
			end)
		end
	end)
end

Hud.pinyinOn = false

function Hud.init()
	gui = Ui.new("ScreenGui", {
		Name = "FusionZooHud",
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	local bar = Ui.new("Frame", {
		Size = UDim2.new(0, 0, 0, 42),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0, 12, 0, 12),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})

	-- floating pill chips, matching the kiosk reward rail
	local function chip(textColor: Color3): TextLabel
		local pill = Ui.new("Frame", {
			BackgroundColor3 = Ui.COLORS.card,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, 40),
			Parent = bar,
		}, {
			Ui.corner(12),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
			Ui.new("UIStroke", { Color = Ui.COLORS.cardDim, Thickness = 1, Transparency = 0.2 }),
		})
		return Ui.text({
			Text = "",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextSize = 22,
			TextWrapped = false,
			TextColor3 = textColor,
			Parent = pill,
		})
	end

	coinLabel = chip(Color3.fromRGB(138, 106, 0))
	levelLabel = chip(Color3.fromRGB(46, 150, 220))
	starsLabel = chip(Color3.fromRGB(181, 80, 47))
	levelLabel.Text = "L1"
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
