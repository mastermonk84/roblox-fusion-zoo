--!strict
-- The zoo screens: Rescue pen (owned / rescuable / locked-silhouette rows),
-- Fusion Lab (pick head + body, celebrate real words), and Beast management
-- (feed per slot, re-fuse slots, naming from mastered characters only).
-- Renders server payloads; all rules and costs live server-side.

local Players = game:GetService("Players")

local Audio = require("./Audio")
local Ui = require("./Ui")

local ZooUi = {}

type Remotes = {
	rescueList: RemoteFunction,
	rescue: RemoteFunction,
	fuse: RemoteFunction,
	refuse: RemoteFunction,
	feedSlot: RemoteFunction,
	unlockSlot: RemoteFunction,
	nameBeast: RemoteFunction,
	setActive: RemoteFunction,
	snapshot: RemoteFunction,
}

local remotes: Remotes
local onCoins: (coins: number, mathString: string?) -> ()

local gui: ScreenGui
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = {}
local rescueRows: Frame
local fuseHeadList: Frame
local fuseBodyList: Frame
local fuseLegsList: Frame
local fuseButton: TextButton
local fuseResult: TextLabel
local beastList: Frame
local beastDetail: Frame
local namePicker: Frame

local pickedHead: string? = nil
local pickedBody: string? = nil
local pickedLegs: string? = nil
local selectedBeastId: string? = nil
local namePicks: { string } = {}

local function switchTab(name: string)
	for tabName, page in pages do
		page.Visible = tabName == name
		tabButtons[tabName].BackgroundColor3 = if tabName == name
			then Ui.COLORS.accent
			else Ui.COLORS.cardDim
	end
end

function ZooUi.init(zooRemotes: Remotes, coinCallback: (coins: number, mathString: string?) -> ())
	remotes = zooRemotes
	onCoins = coinCallback

	gui = Ui.new("ScreenGui", {
		Name = "ZooScreens",
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
		Size = UDim2.new(0, 560, 0, 580),
		Position = UDim2.new(0.5, -280, 0.5, -290),
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

	-- tabs
	local tabBar = Ui.new("Frame", {
		Size = UDim2.new(1, -50, 0, 40),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new(
			"UIListLayout",
			{ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }
		),
	})
	for _, tab in
		{
			{ "rescue", "救援 Rescue" },
			{ "fuse", "融合 Fuse" },
			{ "beasts", "我的兽 Beasts" },
		}
	do
		local button = Ui.button({
			Text = tab[2],
			Size = UDim2.new(0, 150, 1, 0),
			TextSize = 20,
			BackgroundColor3 = Ui.COLORS.cardDim,
			Parent = tabBar,
		})
		button.Activated:Connect(function()
			switchTab(tab[1])
			ZooUi.refresh()
		end)
		tabButtons[tab[1]] = button
	end

	-- pages
	for _, name in { "rescue", "fuse", "beasts" } do
		pages[name] = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 1, -50),
			Position = UDim2.new(0, 0, 0, 50),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = card,
		})
	end

	-- rescue page: scrolling rows
	rescueRows = Ui.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = pages.rescue,
	}, {
		Ui.new(
			"UIListLayout",
			{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }
		),
	})

	-- fuse page: three pickers (head/body/legs → 智/力/速) + button
	local COL = 1 / 3
	local function slotLabel(text: string, i: number)
		Ui.text({
			Text = text,
			Size = UDim2.new(COL, -6, 0, 24),
			Position = UDim2.new(COL * i, i * 3, 0, 0),
			TextSize = 16,
			Parent = pages.fuse,
		})
	end
	local function slotList(i: number): Frame
		return Ui.new("ScrollingFrame", {
			Size = UDim2.new(COL, -6, 1, -120),
			Position = UDim2.new(COL * i, i * 3, 0, 28),
			BackgroundColor3 = Ui.COLORS.cardDim,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Parent = pages.fuse,
		}, {
			Ui.corner(10),
			Ui.new(
				"UIGridLayout",
				{ CellSize = UDim2.new(0, 50, 0, 50), CellPadding = UDim2.new(0, 4, 0, 4) }
			),
		})
	end
	slotLabel("头 HEAD (智)", 0)
	slotLabel("身 BODY (力)", 1)
	slotLabel("腿 LEGS (速)", 2)
	fuseHeadList = slotList(0)
	fuseBodyList = slotList(1)
	fuseLegsList = slotList(2)
	fuseButton = Ui.tactile({
		Text = "🧬 融合! Fuse 🪙10",
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.new(0, 0, 1, -88),
		TextSize = 24,
		TextColor3 = Color3.fromRGB(74, 45, 6),
		BackgroundColor3 = Ui.COLORS.accent,
		radius = 16,
		Parent = pages.fuse,
	})
	fuseResult = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 1, -32),
		TextSize = 18,
		TextColor3 = Ui.COLORS.inkSoft,
		Parent = pages.fuse,
	})
	fuseButton.Activated:Connect(function()
		if not pickedHead or not pickedBody then
			fuseResult.Text = "先选一个头和一个身! Pick a head and a body first."
			return
		end
		local result =
			remotes.fuse:InvokeServer({ head = pickedHead, body = pickedBody, legs = pickedLegs })
		if not result.ok then
			fuseResult.Text = `不行: {result.err}`
			Audio.wobble()
			return
		end
		onCoins(result.newCoins, result.coinMath)
		local beast = result.beast
		if #result.realWords > 0 then
			local word = result.realWords[1]
			fuseResult.Text =
				`🌟 真的有这个词! {word.word} ({word.english}) {word.coinMath}`
			Audio.fanfare()
		elseif beast.golden then
			fuseResult.Text = `✨ 金色的 {beast.slots.head}{beast.slots.body}!`
			Audio.fanfare()
		else
			fuseResult.Text =
				`✨ 新怪兽诞生! {beast.slots.head}{beast.slots.body}{beast.slots.legs or ""} 力{beast.stats.li} 速{beast.stats.su} 智{beast.stats.zhi}`
			Audio.happy()
		end
		pickedHead = nil
		pickedBody = nil
		pickedLegs = nil
		ZooUi.refresh()
	end)

	-- beasts page: list + detail
	beastList = Ui.new("ScrollingFrame", {
		Size = UDim2.new(0.45, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = pages.beasts,
	}, {
		Ui.new(
			"UIListLayout",
			{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }
		),
	})
	beastDetail = Ui.new("Frame", {
		Size = UDim2.new(0.55, -8, 1, 0),
		Position = UDim2.new(0.45, 8, 0, 0),
		BackgroundColor3 = Ui.COLORS.cardDim,
		BorderSizePixel = 0,
		Parent = pages.beasts,
	}, { Ui.corner(10), Ui.padding(10) })

	namePicker = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.COLORS.card,
		Visible = false,
		ZIndex = 5,
		Parent = card,
	}, { Ui.corner(18), Ui.padding(12) })

	switchTab("rescue")
end

-- ── rendering ───────────────────────────────────────────────────────────────

local function clearChildren(parent: Instance, class: string)
	for _, child in parent:GetChildren() do
		if child:IsA(class :: any) then
			child:Destroy()
		end
	end
end

local function renderRescue(snapshot: any, list: any)
	clearChildren(rescueRows, "Frame")
	local order = 0
	for _, animal in list.animals :: { any } do
		order += 1
		local state = if animal.owned then "owned" elseif animal.mastered then "ready" else "locked"
		local row = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 56),
			BackgroundColor3 = if state == "locked" then Ui.COLORS.scrim else Ui.COLORS.cardDim,
			BackgroundTransparency = if state == "locked" then 0.55 else 0,
			LayoutOrder = order,
			Parent = rescueRows,
		}, { Ui.corner(10) })
		Ui.text({
			Text = animal.char,
			Size = UDim2.new(0, 52, 1, 0),
			TextSize = 38,
			TextColor3 = if state == "locked" then Ui.COLORS.card else Ui.COLORS.ink,
			Parent = row,
		})
		Ui.text({
			Text = if state == "locked"
				then `??? · 学会 "{animal.char}" 就能救它!`
				else `{animal.pinyin} · {animal.english} · 力{animal.li} 速{animal.su} 智{animal.zhi}`,
			Size = UDim2.new(1, -190, 1, 0),
			Position = UDim2.new(0, 56, 0, 0),
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if state == "locked" then Ui.COLORS.card else Ui.COLORS.ink,
			Parent = row,
		})
		if state == "owned" then
			Ui.text({
				Text = "✅",
				Size = UDim2.new(0, 120, 1, 0),
				Position = UDim2.new(1, -126, 0, 0),
				TextSize = 26,
				Parent = row,
			})
		elseif state == "ready" then
			local buy = Ui.tactile({
				Text = `救! 🪙{animal.cost}`,
				Size = UDim2.new(0, 116, 0, 42),
				Position = UDim2.new(1, -124, 0.5, -21),
				TextSize = 20,
				TextColor3 = Color3.fromRGB(12, 81, 50),
				BackgroundColor3 = Ui.COLORS.good,
				radius = 12,
				Parent = row,
			})
			buy.Activated:Connect(function()
				local result = remotes.rescue:InvokeServer({ char = animal.char })
				if result.ok then
					onCoins(result.newCoins, result.coinMath)
					Audio.happy()
					ZooUi.refresh()
				else
					Audio.wobble()
				end
			end)
		else
			Ui.text({
				Text = "🔒",
				Size = UDim2.new(0, 120, 1, 0),
				Position = UDim2.new(1, -126, 0, 0),
				TextSize = 24,
				Parent = row,
			})
		end
	end
	local _ = snapshot
end

local function animalCell(parent: Frame, char: string, picked: boolean, onPick: () -> ())
	local cell = Ui.new("TextButton", {
		Text = char,
		Font = Ui.FONT,
		TextSize = 30,
		TextColor3 = Ui.COLORS.ink,
		BackgroundColor3 = if picked then Ui.COLORS.accent else Ui.COLORS.card,
		AutoButtonColor = true,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		Ui.corner(12),
		Ui.new("UIStroke", {
			Color = if picked then Ui.COLORS.accentEdge else Color3.fromRGB(226, 216, 196),
			Thickness = if picked then 3 else 1,
			Transparency = if picked then 0 else 0.35,
		}),
	})
	cell.Activated:Connect(onPick)
end

local function renderFuse(snapshot: any)
	clearChildren(fuseHeadList, "TextButton")
	clearChildren(fuseBodyList, "TextButton")
	clearChildren(fuseLegsList, "TextButton")
	for char in snapshot.animals :: { [string]: boolean } do
		animalCell(fuseHeadList, char, pickedHead == char, function()
			pickedHead = char
			renderFuse(snapshot)
		end)
		animalCell(fuseBodyList, char, pickedBody == char, function()
			pickedBody = char
			renderFuse(snapshot)
		end)
		animalCell(fuseLegsList, char, pickedLegs == char, function()
			pickedLegs = char
			renderFuse(snapshot)
		end)
	end
end

local renderBeastDetail: (snapshot: any) -> ()

local function renderBeasts(snapshot: any)
	clearChildren(beastList, "TextButton")
	for _, beast in snapshot.beasts :: { any } do
		local displayName = beast.name or (beast.slots.head .. beast.slots.body)
		local active = snapshot.activeBeastId == beast.id
		local row = Ui.button({
			Text = `{if beast.golden then "🌟" else "🐾"} {displayName}\n力{beast.stats.li} 速{beast.stats.su} 智{beast.stats.zhi}{if active
				then " · 出战"
				else ""}`,
			Size = UDim2.new(1, -8, 0, 60),
			TextSize = 18,
			BackgroundColor3 = if selectedBeastId == beast.id
				then Ui.COLORS.good
				else Ui.COLORS.cardDim,
			Parent = beastList,
		})
		row.Activated:Connect(function()
			selectedBeastId = beast.id
			ZooUi.refresh()
		end)
	end
	renderBeastDetail(snapshot)
end

renderBeastDetail = function(snapshot: any)
	clearChildren(beastDetail, "TextLabel")
	clearChildren(beastDetail, "TextButton")
	local beast: any = nil
	for _, candidate in snapshot.beasts :: { any } do
		if candidate.id == selectedBeastId then
			beast = candidate
		end
	end
	if not beast then
		Ui.text({
			Text = "← 选一只兽",
			Size = UDim2.fromScale(1, 1),
			TextSize = 22,
			Parent = beastDetail,
		})
		return
	end

	local displayName = beast.name or (beast.slots.head .. beast.slots.body)
	Ui.text({
		Text = `{displayName} · 力{beast.stats.li} 速{beast.stats.su} 智{beast.stats.zhi}`,
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 20,
		Parent = beastDetail,
	})

	local y = 36
	local SLOT_LABELS: { [string]: string } =
		{ head = "头智", body = "身力", legs = "腿速", tail = "尾" }
	local FOODS: { [string]: string } =
		{ body = "肉 ròu", legs = "果 guǒ", head = "鱼 yú", tail = "蛋 dàn" }
	for _, slot in { "head", "body", "legs", "tail" } do
		local occupant = beast.slots[slot]
		local feedLevel = beast.feed[slot]
		local rowText = `{SLOT_LABELS[slot]}: {occupant or "—"} 喂{feedLevel}/10`
		Ui.text({
			Text = rowText,
			Size = UDim2.new(0.55, 0, 0, 34),
			Position = UDim2.new(0, 0, 0, y),
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = beastDetail,
		})
		if occupant then
			local cost = feedLevel + 1
			local feedButton = Ui.button({
				Text = if feedLevel >= 10 then "MAX" else `喂{FOODS[slot]} 🪙{cost}`,
				Size = UDim2.new(0.42, 0, 0, 30),
				Position = UDim2.new(0.58, 0, 0, y),
				TextSize = 15,
				BackgroundColor3 = if feedLevel >= 10 then Ui.COLORS.cardDim else Ui.COLORS.accent,
				Parent = beastDetail,
			})
			feedButton.Activated:Connect(function()
				local result = remotes.feedSlot:InvokeServer({ beastId = beast.id, slot = slot })
				if result.ok then
					onCoins(result.newCoins, result.coinMath)
					Audio.happy()
					ZooUi.refresh()
				else
					Audio.wobble()
				end
			end)
		end
		y += 38
	end

	local setActive = Ui.tactile({
		Text = "⚔ 出战! Battle beast",
		Size = UDim2.new(1, 0, 0, 38),
		Position = UDim2.new(0, 0, 0, y + 4),
		TextSize = 18,
		TextColor3 = Color3.fromRGB(12, 81, 50),
		BackgroundColor3 = Ui.COLORS.good,
		radius = 12,
		Parent = beastDetail,
	})
	setActive.Activated:Connect(function()
		local result = remotes.setActive:InvokeServer({ beastId = beast.id })
		if result.ok then
			Audio.happy()
			ZooUi.refresh()
		end
	end)

	local nameButton = Ui.tactile({
		Text = "✏ 取名字 Name 🪙3",
		Size = UDim2.new(1, 0, 0, 38),
		Position = UDim2.new(0, 0, 0, y + 46),
		TextSize = 18,
		TextColor3 = Color3.fromRGB(74, 45, 6),
		BackgroundColor3 = Ui.COLORS.accent,
		radius = 12,
		Parent = beastDetail,
	})
	nameButton.Activated:Connect(function()
		ZooUi.openNamePicker(snapshot, beast.id)
	end)
end

-- Naming: pick exactly two characters from the MASTERED pool. No free text.
function ZooUi.openNamePicker(snapshot: any, beastId: string)
	namePicks = {}
	namePicker.Visible = true
	clearChildren(namePicker, "TextButton")
	clearChildren(namePicker, "TextLabel")
	clearChildren(namePicker, "ScrollingFrame")

	local title = Ui.text({
		Text = "选两个学会的字 · Pick 2 mastered characters",
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 20,
		Parent = namePicker,
	})
	local grid = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -120),
		Position = UDim2.new(0, 0, 0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = namePicker,
	}, {
		Ui.new(
			"UIGridLayout",
			{ CellSize = UDim2.new(0, 56, 0, 56), CellPadding = UDim2.new(0, 4, 0, 4) }
		),
	})

	local confirm: TextButton
	local function renderPicks()
		title.Text = if #namePicks == 0
			then "选两个学会的字 · Pick 2 mastered characters"
			else `名字: {table.concat(namePicks)}`
		confirm.Visible = #namePicks == 2
	end

	for _, char in snapshot.masteredChars :: { string } do
		local cell = Ui.button({
			Text = char,
			TextSize = 30,
			BackgroundColor3 = Ui.COLORS.card,
			Parent = grid,
		})
		cell.Activated:Connect(function()
			table.insert(namePicks, char)
			if #namePicks > 2 then
				table.remove(namePicks, 1)
			end
			renderPicks()
		end)
	end

	confirm = Ui.button({
		Text = "就叫这个! (🪙3)",
		Size = UDim2.new(0.6, 0, 0, 44),
		Position = UDim2.new(0.2, 0, 1, -104),
		TextSize = 22,
		Visible = false,
		Parent = namePicker,
	})
	confirm.Activated:Connect(function()
		local result = remotes.nameBeast:InvokeServer({ beastId = beastId, chars = namePicks })
		if result.ok then
			onCoins(result.newCoins, result.coinMath)
			Audio.happy()
			namePicker.Visible = false
			ZooUi.refresh()
		else
			title.Text = "还没学会这个字 (not mastered yet)"
			Audio.wobble()
		end
	end)
	local cancel = Ui.button({
		Text = "算了 Cancel",
		Size = UDim2.new(0.6, 0, 0, 36),
		Position = UDim2.new(0.2, 0, 1, -52),
		TextSize = 18,
		BackgroundColor3 = Ui.COLORS.cardDim,
		Parent = namePicker,
	})
	cancel.Activated:Connect(function()
		namePicker.Visible = false
	end)
end

function ZooUi.refresh()
	if not gui.Enabled then
		return
	end
	local snapshot = remotes.snapshot:InvokeServer()
	if not snapshot.ok then
		return
	end
	onCoins(snapshot.coins, nil)
	if pages.rescue.Visible then
		local list = remotes.rescueList:InvokeServer()
		if list.ok then
			renderRescue(snapshot, list)
		end
	elseif pages.fuse.Visible then
		renderFuse(snapshot)
	elseif pages.beasts.Visible then
		renderBeasts(snapshot)
	end
end

function ZooUi.open(tab: string)
	gui.Enabled = true
	switchTab(tab)
	ZooUi.refresh()
end

return ZooUi
