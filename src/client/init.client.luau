--!strict
-- Everything the kids touch. The client renders server state and nothing else —
-- coins, stats and battle outcomes are all decided on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local action, state = Remotes.client()
local player = Players.LocalPlayer

local INK = Color3.fromRGB(28, 26, 38)
local CARD = Color3.fromRGB(255, 252, 245)
local ACCENT = Color3.fromRGB(255, 176, 59)
local PICKED = Color3.fromRGB(126, 217, 163)

local function new<T>(class: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(class)
	for key, value in props do
		(instance :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	return instance
end

local function corner(radius: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function button(text: string, size: UDim2, position: UDim2, color: Color3): TextButton
	return new("TextButton", {
		Text = text,
		Size = size,
		Position = position,
		BackgroundColor3 = color,
		TextColor3 = INK,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		AutoButtonColor = true,
		BorderSizePixel = 0,
	}, { corner(10) })
end

local gui = new("ScreenGui", {
	Name = "FusionZoo",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local coinsLabel = new("TextLabel", {
	Text = "🪙 …",
	Size = UDim2.new(0, 220, 0, 52),
	Position = UDim2.new(0, 16, 0, 16),
	BackgroundColor3 = CARD,
	TextColor3 = INK,
	Font = Enum.Font.GothamBold,
	TextSize = 26,
	BorderSizePixel = 0,
	Parent = gui,
}, { corner(12) })

local logLabel = new("TextLabel", {
	Text = "欢迎! Answer a mission to earn coins.",
	Size = UDim2.new(0, 640, 0, 44),
	Position = UDim2.new(0, 16, 1, -60),
	BackgroundColor3 = CARD,
	TextColor3 = INK,
	Font = Enum.Font.Gotham,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	BorderSizePixel = 0,
	Parent = gui,
}, { corner(12), new("UIPadding", { PaddingLeft = UDim.new(0, 12) }) })

local function say(text: string)
	logLabel.Text = text
end

-- Mission card ------------------------------------------------------------

local missionCard = new("Frame", {
	Size = UDim2.new(0, 300, 0, 300),
	Position = UDim2.new(0, 16, 0, 84),
	BackgroundColor3 = CARD,
	BorderSizePixel = 0,
	Parent = gui,
}, { corner(14) })

local charLabel = new("TextLabel", {
	Text = "?",
	Size = UDim2.new(1, 0, 0, 110),
	BackgroundTransparency = 1,
	TextColor3 = INK,
	Font = Enum.Font.GothamBold,
	TextSize = 72,
	Parent = missionCard,
})

local choiceButtons: { TextButton } = {}
for index = 1, 4 do
	local choice = button("", UDim2.new(1, -24, 0, 38), UDim2.new(0, 12, 0, 108 + index * 44), ACCENT)
	choice.Parent = missionCard
	choiceButtons[index] = choice
end

local function setMission(char: string?, choices: { string }?)
	charLabel.Text = char or "?"
	for index, choice in choiceButtons do
		local text = choices and choices[index]
		choice.Text = text or "—"
		choice.Visible = text ~= nil
		choice.BackgroundColor3 = ACCENT
	end
end

-- Zoo ---------------------------------------------------------------------

local zooCard = new("Frame", {
	Size = UDim2.new(0, 340, 0, 300),
	Position = UDim2.new(0, 332, 0, 84),
	BackgroundColor3 = CARD,
	BorderSizePixel = 0,
	Parent = gui,
}, { corner(14) })

local zooList = new("ScrollingFrame", {
	Size = UDim2.new(1, -16, 1, -108),
	Position = UDim2.new(0, 8, 0, 8),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = zooCard,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local rescueButton = button(`Rescue 🪙{Config.RESCUE_COST}`, UDim2.new(0, 150, 0, 38), UDim2.new(0, 8, 1, -92), ACCENT)
rescueButton.Parent = zooCard

local fuseButton = button(`Fuse 🪙{Config.FUSE_COST}`, UDim2.new(0, 150, 0, 38), UDim2.new(0, 174, 1, -92), ACCENT)
fuseButton.Parent = zooCard

local battleButton = button("Battle ⚔️", UDim2.new(0, 150, 0, 38), UDim2.new(0, 8, 1, -46), PICKED)
battleButton.Parent = zooCard

local feedButton = button(`Feed 🪙{Config.FEED_COST}`, UDim2.new(0, 150, 0, 38), UDim2.new(0, 174, 1, -46), ACCENT)
feedButton.Parent = zooCard

local selected: { string } = {}
local beasts: { Types.Beast } = {}

local function statLine(beast: Types.Beast): string
	return `力{beast.stats.power} 速{beast.stats.speed} 智{beast.stats.smarts}`
end

local renderZoo: () -> ()

local function toggle(id: string)
	local at = table.find(selected, id)
	if at then
		table.remove(selected, at)
	else
		table.insert(selected, id)
		if #selected > 2 then
			table.remove(selected, 1)
		end
	end
	renderZoo()
end

function renderZoo()
	for _, child in zooList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for index, beast in beasts do
		local isPicked = table.find(selected, beast.id) ~= nil
		local row = button(
			`{beast.emoji} {beast.name}   {statLine(beast)}`,
			UDim2.new(1, -8, 0, 34),
			UDim2.new(),
			isPicked and PICKED or Color3.fromRGB(240, 236, 228)
		)
		row.LayoutOrder = index
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextSize = 16
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = row })
		row.Activated:Connect(function()
			toggle(beast.id)
		end)
		row.Parent = zooList
	end
end

-- Wiring ------------------------------------------------------------------

local busy = false

local function invoke(kind: string, payload: any?): any
	if busy then
		return nil
	end
	busy = true
	local ok, result = pcall(function()
		return action:InvokeServer(kind, payload)
	end)
	busy = false

	if not ok then
		say(`Something went wrong: {result}`)
		return nil
	end
	if typeof(result) == "table" and result.ok == false then
		say(result.error or "Not allowed")
		return nil
	end
	return result
end

local function nextMission()
	local result = invoke("quiz")
	if result then
		setMission(result.char, result.choices)
		say("Which one is this character?")
	end
end

for index, choice in choiceButtons do
	choice.Activated:Connect(function()
		local result = invoke("answer", { index = index })
		if not result then
			return
		end

		if result.correct then
			say(`对! +🪙{result.coins}`)
			task.wait(0.6)
			nextMission()
		elseif result.again then
			choice.BackgroundColor3 = Color3.fromRGB(228, 130, 130)
			say("Try once more — the next miss reveals it.")
		else
			local answer = choiceButtons[result.reveal]
			if answer then
				answer.BackgroundColor3 = PICKED
			end
			say("That one was the answer. Here comes another.")
			task.wait(1.2)
			nextMission()
		end
	end)
end

rescueButton.Activated:Connect(function()
	local result = invoke("rescue")
	if result then
		say(`Rescued {result.beast.emoji} {result.beast.name} ({result.pinyin} · {result.english})`)
	end
end)

fuseButton.Activated:Connect(function()
	if #selected < 2 then
		say("Tap two beasts in the zoo first.")
		return
	end
	local result = invoke("fuse", { a = selected[1], b = selected[2] })
	if result then
		selected = {}
		if result.realWord then
			say(`🎉 真词! {result.beast.emoji} {result.beast.name} — {result.realWord.english}!`)
		else
			say(`Fused: {result.beast.emoji} {result.beast.name}   {statLine(result.beast)}`)
		end
	end
end)

feedButton.Activated:Connect(function()
	if #selected == 0 then
		say("Tap a beast to feed it.")
		return
	end
	local stat = Config.STATS[math.random(1, #Config.STATS)]
	local result = invoke("feed", { id = selected[#selected], stat = stat })
	if result then
		say(`Fed {result.beast.emoji} {result.beast.name} → {Config.STAT_LABELS[stat]} {statLine(result.beast)}`)
	end
end)

battleButton.Activated:Connect(function()
	if #selected == 0 then
		say("Tap a beast to send into battle.")
		return
	end
	local result = invoke("battle", { id = selected[#selected] })
	if not result then
		return
	end

	say(`⚔️ vs {result.monster.emoji} {result.monster.name}…`)
	for _, round in result.rounds do
		task.wait(0.8)
		local yours = `{Config.STAT_LABELS[round.yourStat]} {round.yourValue}{round.yourDoubled and " (×2)" or ""}`
		local theirs = `{Config.STAT_LABELS[round.theirStat]} {round.theirValue}{round.theirDoubled and " (×2)" or ""}`
		say(`{yours}  vs  {theirs}  →  {round.youWon and "赢!" or "输"}`)
	end

	task.wait(0.8)
	if result.youWon then
		say(result.bounty > 0 and `胜利! +🪙{result.bounty} — next monster unlocked` or "胜利! (already cleared)")
	else
		say(`{result.monster.name} won this one. Feed your beast and try again.`)
	end
end)

state.OnClientEvent:Connect(function(snapshot)
	coinsLabel.Text = `🪙 {snapshot.coins}   {snapshot.monster.emoji} {snapshot.monster.name}`
	beasts = snapshot.beasts
	local alive: { string } = {}
	for _, beast in beasts do
		if table.find(selected, beast.id) then
			table.insert(alive, beast.id)
		end
	end
	selected = alive
	renderZoo()
end)

setMission(nil, nil)
nextMission()
