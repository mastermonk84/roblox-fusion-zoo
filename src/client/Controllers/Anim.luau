--!strict
-- Client-side procedural life for every tagged creature: waypoint wander
-- inside the plot, sine bob, and proximity hover cards (name / owner / build /
-- stats — the open-information surface feeding the battle mind-game). No
-- animation pipeline; models are anchored and pivoted whole.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Ui = require("./Ui")

local Anim = {}

type CreatureState = {
	model: Model,
	target: Vector3,
	origin: Vector3,
	speed: number,
	phase: number,
	nextPickAt: number,
	card: BillboardGui?,
}

local creatures: { [Model]: CreatureState } = {}

local function makeCard(model: Model): BillboardGui?
	local primary = model.PrimaryPart
	if not primary then
		return nil
	end
	local height = (model:GetAttribute("Height") :: number?) or 6
	local card = Instance.new("BillboardGui")
	card.Size = UDim2.new(0, 190, 0, 74)
	card.StudsOffset = Vector3.new(0, height + 1.6, 0)
	card.AlwaysOnTop = true
	card.Enabled = false
	local frame = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.COLORS.card,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Parent = card,
	}, { Ui.corner(10), Ui.padding(6) })
	local name = (model:GetAttribute("HoverName") :: string?) or model.Name
	local owner = (model:GetAttribute("HoverOwner") :: string?) or ""
	local build = (model:GetAttribute("HoverBuild") :: string?) or ""
	local stats = (model:GetAttribute("HoverStats") :: string?) or ""
	Ui.text({
		Text = `{if model:GetAttribute("Golden") then "🌟 " else ""}{name}`,
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 19,
		Parent = frame,
	})
	Ui.text({
		Text = build,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 24),
		TextSize = 15,
		TextColor3 = Ui.COLORS.inkSoft,
		Parent = frame,
	})
	Ui.text({
		Text = `{stats}{if owner ~= "" then ` · {owner}` else ""}`,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 44),
		TextSize = 14,
		TextColor3 = Ui.COLORS.inkSoft,
		Parent = frame,
	})
	card.Parent = primary
	return card
end

local function track(model: Model)
	if creatures[model] then
		return
	end
	task.defer(function()
		if not model.PrimaryPart then
			model:GetPropertyChangedSignal("PrimaryPart"):Wait()
		end
		local pivot = model:GetPivot()
		creatures[model] = {
			model = model,
			target = pivot.Position,
			origin = pivot.Position,
			speed = 2.4,
			phase = math.random() * math.pi * 2,
			nextPickAt = 0,
			card = makeCard(model),
		}
	end)
end

local function untrack(model: Model)
	creatures[model] = nil
end

function Anim.init()
	for _, model in CollectionService:GetTagged("FusionZooCreature") do
		track(model :: Model)
	end
	CollectionService:GetInstanceAddedSignal("FusionZooCreature"):Connect(function(instance)
		track(instance :: Model)
	end)
	CollectionService:GetInstanceRemovedSignal("FusionZooCreature"):Connect(function(instance)
		untrack(instance :: Model)
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		local now = os.clock()
		local character = Players.LocalPlayer.Character
		local myPosition = if character and character.PrimaryPart
			then character.PrimaryPart.Position
			else nil

		for model, state in creatures do
			if not model.Parent then
				creatures[model] = nil
				continue
			end
			local centerX = model:GetAttribute("WanderCenterX") :: number?
			local radius = (model:GetAttribute("WanderRadius") :: number?) or 0

			-- pick a fresh waypoint now and then
			if centerX and now >= state.nextPickAt then
				local centerZ = (model:GetAttribute("WanderCenterZ") :: number?) or 0
				local angle = math.random() * math.pi * 2
				local reach = math.random() * radius
				state.target = Vector3.new(
					centerX + math.cos(angle) * reach,
					state.origin.Y,
					centerZ + math.sin(angle) * reach
				)
				state.nextPickAt = now + 3 + math.random() * 4
			end

			local pivot = model:GetPivot()
			local flat =
				Vector3.new(state.target.X - pivot.Position.X, 0, state.target.Z - pivot.Position.Z)
			local distance = flat.Magnitude
			local bob = math.sin(now * 4 + state.phase) * 0.18
			if distance > 0.5 then
				local step = math.min(distance, state.speed * deltaTime)
				local direction = flat.Unit
				local newPosition = pivot.Position + direction * step
				model:PivotTo(
					CFrame.lookAt(
						Vector3.new(newPosition.X, state.origin.Y + bob + 0.1, newPosition.Z),
						Vector3.new(state.target.X, state.origin.Y + bob + 0.1, state.target.Z)
					)
				)
			else
				local position = pivot.Position
				model:PivotTo(
					pivot.Rotation + Vector3.new(position.X, state.origin.Y + bob, position.Z)
				)
			end

			-- hover card on approach
			if state.card and myPosition then
				state.card.Enabled = (pivot.Position - myPosition).Magnitude < 16
			end
		end
	end)
end

return Anim
