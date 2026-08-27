--!strict
-- The animated Battle Arena: a ViewportFrame that stages the player's fusion
-- beast against an opponent on two platforms, with a name + round-pip HUD.
-- Mounted into BattleUi's fight page; driven by the same StartNpc/PickStat/
-- SubmitFlash/ResolveRound responses. A round = the winner lunges, the loser
-- flinches, a spark + shake fire, the winner's pip fills; match over = the
-- loser faints. The beast model is built client-side from the shared RigMath
-- specs — the exact silhouette the server places in the zoo.
--
-- ViewportFrames have no physics, so the rig's independently-anchored parts are
-- moved as a whole via Model:PivotTo (manual lerp), never by tweening one part.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Animals = require("../../shared/Data/Animals")
local Config = require("../../shared/Config")
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

local STAT_COLOR: { [string]: Color3 } = {
	li = Color3.fromRGB(255, 107, 61),
	su = Color3.fromRGB(38, 198, 245),
	zhi = Color3.fromRGB(178, 107, 255),
}

local P_SPOT = Vector3.new(-4.2, 0, 0)
local F_SPOT = Vector3.new(4.2, 0, 0)
local P_FACE = CFrame.Angles(0, math.rad(90), 0) -- rig forward -> +X (toward foe)
local F_FACE = CFrame.Angles(0, math.rad(-90), 0)
local PIPS = 3

-- ── model building (client port of CreatureService.instantiate) ──────────────
local function modelFromSpec(spec: RigMath.RigSpec): Model
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
		part.CFrame = CFrame.new(Vector3.new(ps.offset.x, ps.offset.y, ps.offset.z))
		part.Name = ps.module
		part.Parent = model
		if ps.module == "body" and primary == nil then
			primary = part
		end
	end
	model.PrimaryPart = primary
	return model
end

local function beastModel(beast: Beast): Model
	local totals = SlotStats.slotTotals(beast, ANIMAL_INDEX)
	return modelFromSpec(RigMath.resolve({
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
	}))
end

local function opponentModel(tint: Color3): Model
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(3.6, 3.6, 3.6)
	body.Anchored, body.CanCollide, body.CastShadow = true, false, false
	body.Color = tint
	body.Material = Enum.Material.Slate
	body.CFrame = CFrame.new(0, 1.8, 0)
	body.Parent = model
	for i = -1, 1, 2 do
		local eye = Instance.new("Part")
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.62, 0.62, 0.25)
		eye.Anchored, eye.CanCollide, eye.CastShadow = true, false, false
		eye.Color = Color3.fromRGB(240, 60, 60)
		eye.CFrame = body.CFrame * CFrame.new(i * 0.7, 0.35, -1.75)
		eye.Parent = model
	end
	model.PrimaryPart = body
	return model
end

-- ── surface state ────────────────────────────────────────────────────────────
local container: Frame
local containerBase: UDim2
local viewport: ViewportFrame
local world: WorldModel
local cam: Camera
local pModel: Model?
local fModel: Model?
local pName: TextLabel
local fName: TextLabel
local pPips: { Frame } = {}
local fPips: { Frame } = {}
local sparkBall: Part
local hitFlash: Frame
local telegraph: TextLabel

local function makePips(panel: Instance, tint: Color3): { Frame }
	local row = Ui.new("Frame", {
		Size = UDim2.new(0, PIPS * 16 - 5, 0, 11),
		Position = UDim2.new(0, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 5),
		}),
	})
	local out = {}
	for _ = 1, PIPS do
		out[#out + 1] = Ui.new("Frame", {
			Size = UDim2.fromOffset(11, 11),
			BackgroundColor3 = Color3.fromRGB(70, 62, 86),
			BorderSizePixel = 0,
			Parent = row,
		}, {
			Ui.corner(6),
			Ui.new("UIStroke", { Color = tint, Thickness = 1, Transparency = 0.4 }),
		})
	end
	return out
end

local function panel(parent: Instance, side: string, tint: Color3): (TextLabel, { Frame })
	local p = Ui.new("Frame", {
		Size = UDim2.new(0, 176, 0, 44),
		Position = if side == "p" then UDim2.new(0, 10, 0, 10) else UDim2.new(1, -186, 0, 10),
		BackgroundColor3 = Color3.fromRGB(22, 15, 34),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Ui.corner(11), Ui.padding(8) })
	local name = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 15,
		TextColor3 = Color3.fromRGB(244, 236, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = p,
	})
	return name, makePips(p, tint)
end

-- Mount the arena into a parent frame (BattleUi's fight page reserves the top).
function BattleArena.mount(parent: Instance)
	if container then
		container:Destroy()
	end
	container = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 210),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(16, 11, 26),
		BorderSizePixel = 0,
		Parent = parent,
	}, { Ui.corner(16) })
	containerBase = container.Position

	viewport = Ui.new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(126, 200, 234),
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(190, 190, 198),
		LightColor = Color3.fromRGB(255, 246, 224),
		LightDirection = Vector3.new(-0.4, -1, -0.35),
		Parent = container,
	}, { Ui.corner(16) })

	world = Instance.new("WorldModel")
	world.Parent = viewport
	cam = Instance.new("Camera")
	cam.FieldOfView = 46
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 3.4, 11), Vector3.new(0, 2.1, 0))
	viewport.CurrentCamera = cam
	cam.Parent = viewport

	local ground = Instance.new("Part")
	ground.Size = Vector3.new(60, 1, 26)
	ground.Anchored, ground.CanCollide, ground.CastShadow = true, false, false
	ground.Color = Color3.fromRGB(122, 178, 110)
	ground.Material = Enum.Material.Grass
	ground.CFrame = CFrame.new(0, -0.5, 0)
	ground.Parent = world
	for _, spot in { P_SPOT, F_SPOT } do
		local pad = Instance.new("Part")
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(0.4, 6.6, 6.6)
		pad.Anchored, pad.CanCollide, pad.CastShadow = true, false, false
		pad.Color = Color3.fromRGB(98, 152, 88)
		pad.CFrame = CFrame.new(spot) * CFrame.Angles(0, 0, math.rad(90))
		pad.Parent = world
	end

	-- ParticleEmitters don't render in ViewportFrames; use a neon burst part
	-- (parts do render) plus a UI hit-flash for punch.
	sparkBall = Instance.new("Part")
	sparkBall.Shape = Enum.PartType.Ball
	sparkBall.Material = Enum.Material.Neon
	sparkBall.Color = Color3.fromRGB(255, 244, 150)
	sparkBall.Transparency = 1
	sparkBall.Size = Vector3.new(0.5, 0.5, 0.5)
	sparkBall.Anchored, sparkBall.CanCollide, sparkBall.CastShadow = true, false, false
	sparkBall.CFrame = CFrame.new(0, 2, 0)
	sparkBall.Parent = world

	hitFlash = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = container,
	}, { Ui.corner(16) })

	-- contextual "速 克 力!" advantage teach, shown on a triangle-advantaged win
	telegraph = Ui.text({
		Text = "",
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.new(0, 10, 0, 60),
		TextSize = 26,
		Visible = false,
		ZIndex = 4,
		Parent = container,
	})

	pName, pPips = panel(container, "p", Ui.COLORS.good)
	fName, fPips = panel(container, "f", Ui.COLORS.bad)
end

local function setPips(pips: { Frame }, score: number)
	for i, pip in pips do
		pip.BackgroundColor3 = if i <= score then Ui.COLORS.good else Color3.fromRGB(70, 62, 86)
	end
end

local function fillPip(pip: Frame, tint: Color3)
	pip.BackgroundColor3 = tint
	local s = Ui.new("UIScale", { Scale = 1.6, Parent = pip })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.4, function()
		s:Destroy()
	end)
end

-- Stage a matchup. player = active beast; foe = { name, tint? }.
function BattleArena.show(player: Beast, foe: { name: string, tint: Color3? })
	if not container then
		return
	end
	if pModel then
		pModel:Destroy()
	end
	if fModel then
		fModel:Destroy()
	end
	pModel = beastModel(player)
	pModel.Parent = world;
	(pModel :: Model):PivotTo(CFrame.new(P_SPOT) * P_FACE)
	fModel = opponentModel(foe.tint or Color3.fromRGB(140, 138, 150))
	fModel.Parent = world;
	(fModel :: Model):PivotTo(CFrame.new(F_SPOT) * F_FACE)

	pName.Text = player.name or (player.slots.head .. player.slots.body)
	fName.Text = foe.name
	setPips(pPips, 0)
	setPips(fPips, 0)
	if container.Visible == false then
		container.Visible = true
	end
end

-- animate a model's whole pivot (viewport has no physics) over dur seconds.
local function lerpPivot(model: Model, from: CFrame, to: CFrame, dur: number)
	local t0 = os.clock()
	while true do
		local a = math.min(1, (os.clock() - t0) / dur)
		model:PivotTo(from:Lerp(to, a))
		if a >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

local function shake()
	task.spawn(function()
		for _ = 1, 6 do
			container.Position = containerBase
				+ UDim2.fromOffset(math.random(-6, 6), math.random(-5, 5))
			task.wait(0.03)
		end
		container.Position = containerBase
	end)
end

local function faint(model: Model, base: CFrame)
	local tipped = base * CFrame.Angles(0, 0, math.rad(78)) + Vector3.new(0, -0.4, 0)
	task.spawn(function()
		lerpPivot(model, model:GetPivot(), tipped, 0.5)
	end)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 0.85 }):Play()
		end
	end
end

-- Teach the rock-paper-scissors triangle in context: when the winning stat
-- triangle-beats the losing stat, flash e.g. "速 克 力!" in the winner's colour.
local function showAdvantage(winnerStat: string, loserStat: string)
	if not telegraph then
		return
	end
	local wl = Config.STAT_LABELS[winnerStat] or winnerStat
	local ll = Config.STAT_LABELS[loserStat] or loserStat
	telegraph.Text = `⚡ {wl} → {ll}` -- RPS-style "beats" arrow (type advantage, not magnitude)
	telegraph.TextColor3 = STAT_COLOR[winnerStat] or Color3.fromRGB(255, 255, 255)
	telegraph.Visible = true
	local s = Ui.new("UIScale", { Scale = 0.6, Parent = telegraph })
	TweenService
		:Create(
			s,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		:Play()
	task.delay(1.3, function()
		telegraph.Visible = false
		s:Destroy()
	end)
end

-- Play one resolved round. winner "a" = you, "b" = foe, else a tie (no clash).
function BattleArena.playRound(info: {
	winner: string,
	youScore: number,
	themScore: number,
	matchOver: boolean?,
	playerWon: boolean?,
	winnerStat: string?,
	loserStat: string?,
})
	if not container or not pModel or not fModel then
		return
	end
	setPips(pPips, info.youScore)
	setPips(fPips, info.themScore)
	if info.winner ~= "a" and info.winner ~= "b" then
		return -- tie: no lunge
	end
	local atk = if info.winner == "a" then pModel else fModel
	local def = if info.winner == "a" then fModel else pModel
	local atkBase = if info.winner == "a"
		then CFrame.new(P_SPOT) * P_FACE
		else CFrame.new(F_SPOT) * F_FACE
	local defBase = if info.winner == "a"
		then CFrame.new(F_SPOT) * F_FACE
		else CFrame.new(P_SPOT) * P_FACE
	local dir = if info.winner == "a" then 1 else -1

	task.spawn(function()
		lerpPivot(atk, atkBase, atkBase + Vector3.new(dir * 3.1, 0, 0), 0.16)
		-- impact
		sparkBall.CFrame = CFrame.new(dir * 1.6, 2, 0)
		sparkBall.Size = Vector3.new(0.5, 0.5, 0.5)
		sparkBall.Transparency = 0.05
		TweenService:Create(
			sparkBall,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(4.2, 4.2, 4.2), Transparency = 1 }
		):Play()
		hitFlash.BackgroundTransparency = 0.4
		TweenService:Create(hitFlash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		shake()
		if
			info.winnerStat
			and info.loserStat
			and Config.Battle.TRIANGLE[info.winnerStat] == info.loserStat
		then
			showAdvantage(info.winnerStat, info.loserStat)
		end
		local newPip = if info.winner == "a" then pPips[info.youScore] else fPips[info.themScore]
		if newPip then
			fillPip(newPip, Ui.COLORS.good)
		end
		-- loser flinch + attacker recoil (parallel)
		task.spawn(function()
			lerpPivot(def, defBase, defBase + Vector3.new(dir * 0.9, 0, 0), 0.1)
			lerpPivot(def, defBase + Vector3.new(dir * 0.9, 0, 0), defBase, 0.25)
		end)
		lerpPivot(atk, atkBase + Vector3.new(dir * 3.1, 0, 0), atkBase, 0.28)
		if info.matchOver then
			task.wait(0.15)
			if info.playerWon then
				faint(fModel :: Model, defBase)
			else
				faint(pModel :: Model, if info.winner == "b" then defBase else atkBase)
			end
		end
	end)
end

function BattleArena.hide()
	if container then
		container.Visible = false
	end
end

return BattleArena
