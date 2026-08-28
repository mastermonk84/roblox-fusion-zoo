--!strict
-- The 识字进度 screen — the screenshot-worthy acquisition surface. Big total,
-- fourteen band bars, and an honest note for characters waiting on assets or
-- the pinyin toggle. Recognition claims only.

local Players = game:GetService("Players")

local Ui = require("./Ui")

local ProgressUi = {}

local gui: ScreenGui
local totalLabel: TextLabel
local bandsFrame: Frame
local noteLabel: TextLabel

function ProgressUi.init(onClose: () -> ())
	gui = Ui.new("ScreenGui", {
		Name = "ProgressBoard",
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

	local card = Ui.new("Frame", {
		Size = UDim2.new(0, 520, 0, 560),
		Position = UDim2.new(0.5, -260, 0.5, -280),
		BackgroundColor3 = Ui.COLORS.card,
		BorderSizePixel = 0,
		Parent = scrim,
	}, { Ui.corner(18), Ui.padding(16) })

	Ui.button({
		Text = "×",
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(1, -44, 0, 4),
		TextSize = 30,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Parent = card,
	}).Activated
		:Connect(onClose)

	Ui.text({
		Text = "识字进度 · Character mastery",
		Size = UDim2.new(1, -46, 0, 30),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	totalLabel = Ui.text({
		Text = "…/700",
		Size = UDim2.new(1, 0, 0, 72),
		Position = UDim2.new(0, 0, 0, 36),
		TextSize = 60,
		TextColor3 = Ui.COLORS.accent,
		Parent = card,
	})

	bandsFrame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 380),
		Position = UDim2.new(0, 0, 0, 116),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new(
			"UIListLayout",
			{ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }
		),
	})

	noteLabel = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 1, -40),
		TextSize = 16,
		TextColor3 = Ui.COLORS.inkSoft,
		Parent = card,
	})
end

function ProgressUi.open()
	gui.Enabled = true
end

function ProgressUi.close()
	gui.Enabled = false
end

function ProgressUi.render(summary: any)
	totalLabel.Text = `{summary.total}/{summary.of}`
	for _, child in bandsFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, band in summary.bands :: { any } do
		local row = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 23),
			BackgroundTransparency = 1,
			LayoutOrder = band.band,
			Parent = bandsFrame,
		})
		Ui.text({
			Text = `第{band.band}关`,
			Size = UDim2.new(0, 64, 1, 0),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.COLORS.inkSoft,
			Parent = row,
		})
		local track = Ui.new("Frame", {
			Size = UDim2.new(1, -130, 0, 12),
			Position = UDim2.new(0, 70, 0.5, -6),
			BackgroundColor3 = Ui.COLORS.cardDim,
			BorderSizePixel = 0,
			Parent = row,
		}, { Ui.corner(6) })
		if band.mastered > 0 then
			Ui.new("Frame", {
				Size = UDim2.new(band.mastered / band.of, 0, 1, 0),
				BackgroundColor3 = Ui.COLORS.good,
				BorderSizePixel = 0,
				Parent = track,
			}, { Ui.corner(6) })
		end
		Ui.text({
			Text = `{band.mastered}/{band.of}`,
			Size = UDim2.new(0, 52, 1, 0),
			Position = UDim2.new(1, -52, 0, 0),
			TextSize = 15,
			TextColor3 = Ui.COLORS.inkSoft,
			Parent = row,
		})
	end
	if summary.deferredByToggle > 0 then
		noteLabel.Text =
			`{summary.deferredByToggle} 个字等拼音模式 · {summary.deferredByToggle} characters unlock with pinyin mode (parent settings)`
	else
		noteLabel.Text = ""
	end
end

return ProgressUi
