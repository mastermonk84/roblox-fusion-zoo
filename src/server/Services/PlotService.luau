--!strict
-- Claimable player plots (pet-sim pattern): 8 fenced squares fanning out from
-- the plots origin. Claim on join, release on leave. A plot displays the
-- owner's rescued animals and beasts as live creatures plus placed
-- decorations; anyone can walk in and look (hover cards are client-side from
-- creature attributes). Rebuilt whenever the owner's zoo changes.

local Workspace = game:GetService("Workspace")

local CreatureService = require("./CreatureService")
local Decorations = require("../../shared/Data/Decorations")
local WorldService = require("./WorldService")
local Types = require("../../shared/Types")

type Profile = Types.Profile

local PLOT_COUNT = 8
local PLOT_SIZE = 30
local PLOT_GAP = 8

local DECOR_INDEX: { [string]: any } = {}
for _, d in Decorations :: { any } do
	DECOR_INDEX[d.id] = d
end

local PlotService = {}
PlotService.__index = PlotService

type Plot = {
	index: number,
	origin: Vector3,
	folder: Folder,
	ownerUserId: number?,
	creatures: Folder,
	decorations: Folder,
	sign: TextLabel,
}

function PlotService.new()
	local self = setmetatable({
		_plots = {} :: { [number]: Plot },
		_byOwner = {} :: { [number]: Plot },
	}, PlotService)

	local root = Instance.new("Folder")
	root.Name = "FusionZooPlots"
	local origin = WorldService.ANCHORS.plotsOrigin
	for index = 1, PLOT_COUNT do
		local row = math.floor((index - 1) / 4)
		local col = (index - 1) % 4
		local plotOrigin = origin
			+ Vector3.new(col * (PLOT_SIZE + PLOT_GAP), 0, row * (PLOT_SIZE + PLOT_GAP))
		local folder = Instance.new("Folder")
		folder.Name = `Plot{index}`

		local floor = Instance.new("Part")
		floor.Anchored = true
		floor.Size = Vector3.new(PLOT_SIZE, 0.4, PLOT_SIZE)
		floor.Position = plotOrigin + Vector3.new(0, 0.2, 0)
		floor.Color = Color3.fromRGB(188, 214, 156)
		floor.Material = Enum.Material.Grass
		floor.Name = "Floor"
		floor.Parent = folder

		-- low fence (blocks nothing — plots are open by design)
		for _, edge in { -1, 1 } do
			for _, axis in { "x", "z" } do
				local rail = Instance.new("Part")
				rail.Anchored = true
				rail.CanCollide = false
				if axis == "x" then
					rail.Size = Vector3.new(PLOT_SIZE, 1, 0.4)
					rail.Position = plotOrigin + Vector3.new(0, 0.9, edge * PLOT_SIZE / 2)
				else
					rail.Size = Vector3.new(0.4, 1, PLOT_SIZE)
					rail.Position = plotOrigin + Vector3.new(edge * PLOT_SIZE / 2, 0.9, 0)
				end
				rail.Color = Color3.fromRGB(160, 116, 74)
				rail.Material = Enum.Material.WoodPlanks
				rail.Parent = folder
			end
		end

		local post = Instance.new("Part")
		post.Anchored = true
		post.Size = Vector3.new(0.6, 5, 0.6)
		post.Position = plotOrigin + Vector3.new(-PLOT_SIZE / 2 + 1, 2.5, -PLOT_SIZE / 2 + 1)
		post.Color = Color3.fromRGB(160, 116, 74)
		post.Parent = folder
		local signBoard = Instance.new("Part")
		signBoard.Anchored = true
		signBoard.Size = Vector3.new(4.5, 2, 0.3)
		signBoard.Position = post.Position + Vector3.new(2, 1.6, 0)
		signBoard.Color = Color3.fromRGB(255, 252, 245)
		signBoard.Parent = folder
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = signBoard
		local sign = Instance.new("TextLabel")
		sign.Size = UDim2.fromScale(1, 1)
		sign.BackgroundTransparency = 1
		sign.Text = "空地 Open"
		sign.TextScaled = true
		sign.Font = Enum.Font.SourceSansBold
		sign.TextColor3 = Color3.fromRGB(45, 41, 56)
		sign.Parent = gui

		local creatures = Instance.new("Folder")
		creatures.Name = "Creatures"
		creatures.Parent = folder
		local decorationsFolder = Instance.new("Folder")
		decorationsFolder.Name = "Decorations"
		decorationsFolder.Parent = folder

		folder.Parent = root
		self._plots[index] = {
			index = index,
			origin = plotOrigin,
			folder = folder,
			ownerUserId = nil,
			creatures = creatures,
			decorations = decorationsFolder,
			sign = sign,
		}
	end
	root.Parent = Workspace
	return self
end

function PlotService.claim(self: any, userId: number, displayName: string): number?
	for _, plot in self._plots :: { [number]: Plot } do
		if plot.ownerUserId == nil then
			plot.ownerUserId = userId
			plot.sign.Text = `{displayName}\n的动物园`
			self._byOwner[userId] = plot
			return plot.index
		end
	end
	return nil
end

function PlotService.release(self: any, userId: number)
	local plot = self._byOwner[userId] :: Plot?
	if plot then
		plot.ownerUserId = nil
		plot.sign.Text = "空地 Open"
		plot.creatures:ClearAllChildren()
		plot.decorations:ClearAllChildren()
		self._byOwner[userId] = nil
	end
end

-- Deterministic scatter positions inside the plot.
local function scatter(origin: Vector3, index: number): Vector3
	local angle = index * 2.399963 -- golden angle: even spread, no RNG
	local radius = 3 + (index % 5) * 2.2
	return origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Rebuild the plot's creatures + decorations from the profile.
function PlotService.refresh(self: any, userId: number, profile: Profile, displayName: string)
	local plot = self._byOwner[userId] :: Plot?
	if not plot then
		return
	end
	plot.creatures:ClearAllChildren()

	local placed = 0
	for _, beast in profile.beasts do
		local model = CreatureService.buildBeast(beast, displayName, scatter(plot.origin, placed))
		model:SetAttribute("WanderCenterX", plot.origin.X)
		model:SetAttribute("WanderCenterZ", plot.origin.Z)
		model:SetAttribute("WanderRadius", PLOT_SIZE / 2 - 4)
		model.Parent = plot.creatures
		placed += 1
	end
	for char in profile.animals do
		local model = CreatureService.buildAnimal(char, scatter(plot.origin, placed))
		if model then
			model:SetAttribute("WanderCenterX", plot.origin.X)
			model:SetAttribute("WanderCenterZ", plot.origin.Z)
			model:SetAttribute("WanderRadius", PLOT_SIZE / 2 - 4)
			model.Parent = plot.creatures
			placed += 1
		end
	end

	plot.decorations:ClearAllChildren()
	for slotKey, itemId in profile.plotPlacements do
		local item = DECOR_INDEX[itemId]
		local gridIndex = tonumber(slotKey)
		if item and gridIndex then
			local row = math.floor((gridIndex - 1) / 4)
			local col = (gridIndex - 1) % 4
			local position = plot.origin
				+ Vector3.new(-PLOT_SIZE / 2 + 4 + col * 7, 1, PLOT_SIZE / 2 - 3 - row * 4)
			local decoration = Instance.new("Part")
			decoration.Anchored = true
			decoration.Size = Vector3.new(1.6, 2, 1.6)
			decoration.Position = position
			decoration.Color = Color3.fromRGB(214, 206, 190)
			decoration.Name = item.id
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.new(0, 90, 0, 30)
			billboard.StudsOffset = Vector3.new(0, 1.6, 0)
			billboard.AlwaysOnTop = false
			billboard.Parent = decoration
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Text = `{item.name}`
			text.TextScaled = true
			text.Font = Enum.Font.SourceSansBold
			text.TextColor3 = Color3.fromRGB(255, 252, 245)
			text.Parent = billboard
			decoration.Parent = plot.decorations
		end
	end
end

return PlotService
