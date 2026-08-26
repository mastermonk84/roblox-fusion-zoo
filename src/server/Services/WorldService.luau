--!strict
-- Builds the whole place procedurally at server start (nothing is hand-placed
-- in Studio): ground, spawn plaza, Mission Kiosk, Progress Board. The zoo
-- plots, Fusion Lab, and Battle Arena footprints arrive with M3/M4 — their
-- anchor positions are already reserved here so the hub layout stays stable.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local WorldService = {}

local GRASS = Color3.fromRGB(124, 189, 107)
local STONE = Color3.fromRGB(214, 206, 190)
local WOOD = Color3.fromRGB(160, 116, 74)
local ROOF = Color3.fromRGB(214, 100, 92)
local INK = Color3.fromRGB(45, 41, 56)

WorldService.ANCHORS = {
	kiosk = Vector3.new(26, 0, 0),
	board = Vector3.new(-26, 0, 0),
	lab = Vector3.new(0, 0, 42),
	arena = Vector3.new(0, 0, -46), -- M4
	plotsOrigin = Vector3.new(64, 0, -48),
	rescuePen = Vector3.new(-64, 0, -40),
}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function label(parent: Instance, face: Enum.NormalId, text: string, textSize: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = parent
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = INK
	textLabel.TextScaled = textSize == 0
	textLabel.TextSize = textSize
	textLabel.Font = Enum.Font.SourceSansBold
	textLabel.Parent = gui
	return textLabel
end

function WorldService.build(): Folder
	local world = Instance.new("Folder")
	world.Name = "FusionZooWorld"

	-- ground + plaza
	part({
		Name = "Ground",
		Size = Vector3.new(400, 2, 400),
		Position = Vector3.new(0, -1, 0),
		Color = GRASS,
		Material = Enum.Material.Grass,
	}, world)
	part({
		Name = "Plaza",
		Size = Vector3.new(48, 0.4, 48),
		Position = Vector3.new(0, 0.2, 0),
		Color = STONE,
		Material = Enum.Material.Slate,
	}, world)

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Position = Vector3.new(0, 0.9, 12)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Color = STONE
	spawnLocation.Parent = world

	-- ── Mission Kiosk 任务亭 ──────────────────────────────────────────────
	local kioskPos = WorldService.ANCHORS.kiosk
	local kiosk = Instance.new("Model")
	kiosk.Name = "MissionKiosk"
	local counter = part({
		Size = Vector3.new(8, 4, 4),
		Position = kioskPos + Vector3.new(0, 2, 0),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
	}, kiosk)
	part({
		Size = Vector3.new(10, 0.8, 6),
		Position = kioskPos + Vector3.new(0, 6.5, 0),
		Color = ROOF,
		Material = Enum.Material.SmoothPlastic,
	}, kiosk)
	label(counter, Enum.NormalId.Front, "任务亭\nMissions", 0)
	label(counter, Enum.NormalId.Back, "任务亭\nMissions", 0)

	local kioskPrompt = Instance.new("ProximityPrompt")
	kioskPrompt.Name = "KioskPrompt"
	kioskPrompt.ActionText = "学汉字 Study!"
	kioskPrompt.ObjectText = "任务亭"
	kioskPrompt.MaxActivationDistance = 12
	kioskPrompt.RequiresLineOfSight = false
	kioskPrompt.Parent = counter
	kiosk.Parent = world

	-- ── Progress Board 识字进度 ───────────────────────────────────────────
	local boardPos = WorldService.ANCHORS.board
	local board = part({
		Name = "ProgressBoard",
		Size = Vector3.new(1, 10, 14),
		Position = boardPos + Vector3.new(0, 5, 0),
		Color = INK,
		Material = Enum.Material.SmoothPlastic,
	}, world)
	label(board, Enum.NormalId.Right, "识字进度\nProgress", 0)
	part({
		Size = Vector3.new(3, 0.6, 16),
		Position = boardPos + Vector3.new(0, 10.3, 0),
		Color = ROOF,
	}, world)

	local boardPrompt = Instance.new("ProximityPrompt")
	boardPrompt.Name = "BoardPrompt"
	boardPrompt.ActionText = "看进度 Progress"
	boardPrompt.ObjectText = "识字进度"
	boardPrompt.MaxActivationDistance = 14
	boardPrompt.RequiresLineOfSight = false
	boardPrompt.Parent = board

	-- ── Fusion Lab 融合屋 ─────────────────────────────────────────────────
	local labPos = WorldService.ANCHORS.lab
	local lab = Instance.new("Model")
	lab.Name = "FusionLab"
	local labBase = part({
		Size = Vector3.new(12, 1, 12),
		Position = labPos + Vector3.new(0, 0.5, 0),
		Color = STONE,
		Material = Enum.Material.Slate,
	}, lab)
	local machine = part({
		Size = Vector3.new(5, 7, 5),
		Position = labPos + Vector3.new(0, 4.5, 0),
		Color = Color3.fromRGB(130, 120, 200),
		Material = Enum.Material.Neon,
	}, lab)
	machine.Transparency = 0.25
	label(labBase, Enum.NormalId.Top, "", 0)
	local labSign = part({
		Size = Vector3.new(8, 2, 0.4),
		Position = labPos + Vector3.new(0, 9, 0),
		Color = ROOF,
	}, lab)
	label(labSign, Enum.NormalId.Front, "融合屋 Fusion Lab", 0)
	local labPrompt = Instance.new("ProximityPrompt")
	labPrompt.Name = "LabPrompt"
	labPrompt.ActionText = "融合! Fuse!"
	labPrompt.ObjectText = "融合屋"
	labPrompt.MaxActivationDistance = 12
	labPrompt.RequiresLineOfSight = false
	labPrompt.Parent = machine
	lab.Parent = world

	-- ── Rescue Pen 救援站: locked animals as silhouettes with their char ──
	local penPos = WorldService.ANCHORS.rescuePen
	local pen = Instance.new("Model")
	pen.Name = "RescuePen"
	local penBase = part({
		Size = Vector3.new(56, 0.6, 26),
		Position = penPos + Vector3.new(0, 0.3, 0),
		Color = Color3.fromRGB(222, 205, 170),
		Material = Enum.Material.Sand,
	}, pen)
	local penPrompt = Instance.new("ProximityPrompt")
	penPrompt.Name = "PenPrompt"
	penPrompt.ActionText = "救援! Rescue!"
	penPrompt.ObjectText = "救援站"
	penPrompt.MaxActivationDistance = 16
	penPrompt.RequiresLineOfSight = false
	penPrompt.Parent = penBase
	pen.Parent = world
	WorldService.rescuePenModel = pen

	-- ── Battle Arena 竞技场 ───────────────────────────────────────────────
	local arenaPos = WorldService.ANCHORS.arena
	local arena = Instance.new("Model")
	arena.Name = "BattleArena"
	local ring = part({
		Size = Vector3.new(26, 0.8, 26),
		Position = arenaPos + Vector3.new(0, 0.4, 0),
		Color = Color3.fromRGB(212, 160, 120),
		Material = Enum.Material.Slate,
	}, arena)
	local arenaSign = part({
		Size = Vector3.new(10, 2.4, 0.4),
		Position = arenaPos + Vector3.new(0, 8, 8),
		Color = ROOF,
	}, arena)
	label(arenaSign, Enum.NormalId.Front, "竞技场 Arena", 0)
	label(arenaSign, Enum.NormalId.Back, "竞技场 Arena", 0)
	local arenaPrompt = Instance.new("ProximityPrompt")
	arenaPrompt.Name = "ArenaPrompt"
	arenaPrompt.ActionText = "打怪! Battle!"
	arenaPrompt.ObjectText = "竞技场"
	arenaPrompt.MaxActivationDistance = 16
	arenaPrompt.RequiresLineOfSight = false
	arenaPrompt.Parent = ring
	-- challenge pad (live battles, M5)
	local pad = part({
		Name = "ChallengePad",
		Size = Vector3.new(8, 0.6, 8),
		Position = arenaPos + Vector3.new(18, 0.5, 0),
		Color = Color3.fromRGB(130, 120, 200),
		Material = Enum.Material.Neon,
	}, arena)
	pad.Transparency = 0.3
	arena.Parent = world

	Lighting.Ambient = Color3.fromRGB(140, 140, 140)
	Lighting.Brightness = 2.4
	Lighting.ClockTime = 13.5

	world.Parent = Workspace
	return world
end

return WorldService
