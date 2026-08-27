--!strict
-- The animated Battle Arena: a ViewportFrame that stages the player's fusion
-- beast against an opponent on two platforms, with an HP/type HUD, driven by the
-- same StartNpc / PickStat / SubmitFlash / ResolveRound responses BattleUi
-- already receives. A round = TweenService lunge + hit spark + HP drain +
-- damage number + faint. The beast model is built client-side from the shared
-- RigMath specs (the exact silhouette the server would place in the zoo).
--
-- This is the arena surface only; BattleUi owns the remotes and the stat/flash
-- controls and calls in here to show state and play each resolved round.

local TweenService = game:GetService("TweenService")

local Animals = require("../../shared/Data/Animals")
local RigMath = require("../../shared/Rig/RigMath")
local SlotStats = require("../../shared/Fusion/SlotStats")
local Types = require("../../shared/Types")
local Ui = require("./Ui")

type Beast = Types.Beast
type AnimalDef = Types.AnimalDef

local BattleArena = {}

local ANIMAL_INDEX = SlotStats.index(Animals :: { AnimalDef })
local RIG_BY_CHAR: { [string]: string } = {}
for _, animal in Animals :: { AnimalDef } do
	RIG_BY_CHAR[animal.char] = animal.rig
end

local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
	Wedge = Enum.PartType.Block,
}

-- ── build a beast model from RigMath specs (client port of CreatureService) ──
local function specForBeast(beast: Beast): RigMath.RigSpec
	local totals = SlotStats.slotTotals(beast, ANIMAL_INDEX)
	return RigMath.resolve({
		head = RIG_BY_CHAR[beast.slots.head],
		body = RIG_BY_CHAR[beast.slots.body],
		legs = if beast.slots.legs then RIG_BY_CHAR[beast.slots.legs] else nil,
		tail = if beast.slots.tail then RIG_BY_CHAR[beast.slots.tail] else nil,
		totals = {
			body = totals.body,
			head = totals.head,
			legs = totals.legs,
			tail = totals.tail or 0,
		},
	})
end

local function modelFromSpec(spec: RigMath.RigSpec, origin: Vector3): Model
	local model = Instance.new("Model")
	local primary: BasePart? = nil
	for _, ps in spec.parts do
		local part: BasePart
		if ps.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			local shaped = Instance.new("Part")
			shaped.Shape = SHAPES[ps.shape] or Enum.PartType.Block
			part = shaped
		end
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(ps.size.x, ps.size.y, ps.size.z)
		part.Color = Color3.fromRGB(ps.color[1], ps.color[2], ps.color[3])
		part.CFrame = CFrame.new(origin + Vector3.new(ps.offset.x, ps.offset.y, ps.offset.z))
		part.Name = ps.module
		part.Parent = model
		if ps.module == "body" and primary == nil then
			primary = part
		end
	end
	model.PrimaryPart = primary
	return model
end

-- opponent NPCs aren't fusions; stage a simple stylized boss blob.
local function opponentModel(origin: Vector3, tint: Color3): Model
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(3.4, 3.4, 3.4)
	body.Anchored, body.CanCollide, body.CastShadow = true, false, false
	body.Color = tint
	body.Material = Enum.Material.Slate
	body.CFrame = CFrame.new(origin + Vector3.new(0, 1.7, 0))
	body.Parent = model
	for i = -1, 1, 2 do
		local eye = Instance.new("Part")
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.6, 0.6, 0.6)
		eye.Anchored, eye.CanCollide, eye.CastShadow = true, false, false
		eye.Color = Color3.fromRGB(20, 16, 24)
		eye.CFrame = body.CFrame * CFrame.new(i * 0.7, 0.4, -1.6)
		eye.Parent = model
	end
	model.PrimaryPart = body
	return model
end

-- ── the arena surface ────────────────────────────────────────────────────────
local gui: ScreenGui
local viewport: ViewportFrame
local world: WorldModel
local cam: Camera
local pModel: Model?
local fModel: Model?
local pBaseCFrame: CFrame
local fBaseCFrame: CFrame

local pHpBar: Frame
local fHpBar: Frame
local pName: TextLabel
local fName: TextLabel

local P_SPOT = Vector3.new(-4.5, 0, 0)
local F_SPOT = Vector3.new(4.5, 0, 1.5)

local function hudPanel(parent: Instance, side: string): (Frame, TextLabel)
	local panel = Ui.new("Frame", {
		Size = UDim2.new(0, 210, 0, 54),
		Position = if side == "p" then UDim2.new(0, 12, 0, 12) else UDim2.new(1, -222, 0, 12),
		BackgroundColor3 = Color3.fromRGB(22, 15, 34),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Ui.corner(12), Ui.padding(8) })
	local name = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 16,
		TextColor3 = Color3.fromRGB(244, 236, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local track = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 0, 26),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = panel,
	}, { Ui.corner(7) })
	local fill = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = if side == "p" then Ui.COLORS.good else Ui.COLORS.bad,
		BorderSizePixel = 0,
		Parent = track,
	}, { Ui.corner(7) })
	return fill, name
end

function BattleArena.init()
	gui = Ui.new("ScreenGui", {
		Name = "BattleArena",
		ResetOnSpawn = false,
		Enabled = false,
		IgnoreGuiInset = true,
		DisplayOrder = 15,
		Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"),
	})
	local stage = Ui.new("Frame", {
		Size = UDim2.new(0, 640, 0, 340),
		Position = UDim2.new(0.5, -320, 0.5, -230),
		BackgroundColor3 = Color3.fromRGB(16, 11, 26),
		BorderSizePixel = 0,
		Parent = gui,
	}, { Ui.corner(20) })

	viewport = Ui.new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 196, 232),
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(180, 180, 190),
		LightColor = Color3.fromRGB(255, 246, 224),
		LightDirection = Vector3.new(-0.4, -1, -0.3),
		Parent = stage,
	}, { Ui.corner(20) })

	world = Instance.new("WorldModel")
	world.Parent = viewport
	cam = Instance.new("Camera")
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 4.5, 15), Vector3.new(0, 2, 0))
	cam.FieldOfView = 50
	viewport.CurrentCamera = cam
	cam.Parent = viewport

	-- ground + two platforms inside the viewport world
	local ground = Instance.new("Part")
	ground.Size = Vector3.new(60, 1, 30)
	ground.Anchored, ground.CanCollide, ground.CastShadow = true, false, false
	ground.Color = Color3.fromRGB(120, 176, 108)
	ground.Material = Enum.Material.Grass
	ground.CFrame = CFrame.new(0, -0.5, 0)
	ground.Parent = world
	for _, spot in { P_SPOT, F_SPOT } do
		local pad = Instance.new("Part")
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(0.5, 7, 7)
		pad.Anchored, pad.CanCollide, pad.CastShadow = true, false, false
		pad.Color = Color3.fromRGB(96, 150, 86)
		pad.CFrame = CFrame.new(spot) * CFrame.Angles(0, 0, math.rad(90))
		pad.Parent = world
	end

	pHpBar, pName = hudPanel(stage, "p")
	fHpBar, fName = hudPanel(stage, "f")
end

-- Show a matchup. player = active beast (slots/feed); foe = { name, tint }.
function BattleArena.show(player: Beast, foe: { name: string, tint: Color3? })
	if pModel then
		pModel:Destroy()
	end
	if fModel then
		fModel:Destroy()
	end
	pModel = modelFromSpec(specForBeast(player), P_SPOT);
	(pModel :: Model):PivotTo(CFrame.new(P_SPOT) * CFrame.Angles(0, math.rad(90), 0))
	pModel.Parent = world
	pBaseCFrame = (pModel :: Model):GetPivot()

	fModel = opponentModel(F_SPOT, foe.tint or Color3.fromRGB(140, 138, 150))
	fModel.Parent = world
	fBaseCFrame = (fModel :: Model):GetPivot()

	pName.Text = player.name or (player.slots.head .. player.slots.body)
	fName.Text = foe.name
	pHpBar.Size = UDim2.fromScale(1, 1)
	fHpBar.Size = UDim2.fromScale(1, 1)
	gui.Enabled = true
end

function BattleArena.setHp(pFrac: number, fFrac: number)
	TweenService
		:Create(pHpBar, TweenInfo.new(0.5), { Size = UDim2.fromScale(math.clamp(pFrac, 0, 1), 1) })
		:Play()
	TweenService
		:Create(fHpBar, TweenInfo.new(0.5), { Size = UDim2.fromScale(math.clamp(fFrac, 0, 1), 1) })
		:Play()
end

-- Play one resolved round: winner "a" = player lunges, else the foe does.
function BattleArena.playRound(winner: string, pFrac: number, fFrac: number)
	local atkModel = if winner == "a" then pModel else fModel
	local base = if winner == "a" then pBaseCFrame else fBaseCFrame
	if not atkModel or not base then
		return
	end
	local toward = if winner == "a" then Vector3.new(3, 0, 0.75) else Vector3.new(-3, 0, -0.75)
	local lunge = base * CFrame.new(toward)
	local prim = (atkModel :: Model).PrimaryPart
	if not prim then
		return
	end
	-- lunge in, then recoil back
	local t1 = TweenService:Create(
		prim,
		TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ CFrame = lunge }
	);
	(atkModel :: Model):PivotTo(base) -- ensure baseline
	t1.Completed:Connect(function()
		BattleArena.setHp(pFrac, fFrac)
		TweenService:Create(
			prim,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = base }
		):Play()
	end)
	t1:Play()
end

function BattleArena.hide()
	if gui then
		gui.Enabled = false
	end
end

-- Standalone demo for verification (a 猫+鸟 beast vs a rock boss).
function BattleArena.demo()
	if not gui then
		BattleArena.init()
	end
	BattleArena.show(
		{
			id = "demo",
			slots = { head = "猫", body = "鸟" },
			feed = { head = 0, body = 0, legs = 0, tail = 0 },
			golden = false,
			name = "喵鸟",
		} :: any,
		{ name = "石头怪", tint = Color3.fromRGB(140, 138, 150) }
	)
end

return BattleArena
