--!strict
-- Instantiates RigMath part specs as anchored Models, tags them with
-- attributes for client hover cards / procedural animation, and drives a
-- simple server-side wander (waypoint hopping; the client smooths and bobs).

local CollectionService = game:GetService("CollectionService")

local Animals = require("../../shared/Data/Animals")
local Colorways = require("../../shared/Data/Colorways")
local Config = require("../../shared/Config")
local RigMath = require("../../shared/Rig/RigMath")
local SlotStats = require("../../shared/Fusion/SlotStats")
local Types = require("../../shared/Types")

type Beast = Types.Beast
type AnimalDef = Types.AnimalDef

local ANIMAL_INDEX = SlotStats.index(Animals :: { AnimalDef })
local RIG_BY_CHAR: { [string]: string } = {}
for _, animal in Animals :: { AnimalDef } do
	RIG_BY_CHAR[animal.char] = animal.rig
end
local COLORWAY_INDEX: { [string]: any } = {}
for _, c in Colorways :: { any } do
	COLORWAY_INDEX[c.id] = c
end

local CreatureService = {}

local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
	Wedge = Enum.PartType.Block, -- wedges use WedgePart below
}

local function toColor(rgb: { number }, colorway: any?): Color3
	if colorway then
		-- colorways tint the primary hue toward the palette color
		local target = Color3.fromRGB(colorway.color[1], colorway.color[2], colorway.color[3])
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3]):Lerp(target, 0.55)
	end
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Builds one creature model from a resolved spec at a world position.
function CreatureService.instantiate(
	spec: RigMath.RigSpec,
	origin: Vector3,
	meta: {
		name: string,
		ownerName: string?,
		statsText: string?,
		buildText: string?,
		golden: boolean,
		sparkleSlots: number,
		colorway: any?,
	}
): Model
	local model = Instance.new("Model")
	model.Name = meta.name

	local primaryPart: BasePart? = nil
	for _, partSpec in spec.parts do
		local part: BasePart
		if partSpec.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			local shaped = Instance.new("Part")
			shaped.Shape = SHAPES[partSpec.shape] or Enum.PartType.Block
			part = shaped
		end
		part.Anchored = true
		part.CanCollide = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(partSpec.size.x, partSpec.size.y, partSpec.size.z)
		local tintable = partSpec.feature == nil or partSpec.module == "body"
		part.Color = toColor(partSpec.color, if tintable then meta.colorway else nil)
		if meta.golden then
			part.Material = Enum.Material.Metal
			part.Reflectance = 0.18
			if partSpec.feature == nil then
				part.Color = part.Color:Lerp(Color3.fromRGB(255, 214, 90), 0.35)
			end
		end
		part.CFrame = CFrame.new(
			origin + Vector3.new(partSpec.offset.x, partSpec.offset.y, partSpec.offset.z)
		)
		part.Name = `{partSpec.module}{if partSpec.feature then "_" .. partSpec.feature else ""}`
		part:SetAttribute("Module", partSpec.module)
		part.Parent = model
		if partSpec.module == "body" and primaryPart == nil then
			primaryPart = part
		end
	end
	model.PrimaryPart = primaryPart

	-- maxed-slot sparkle (legibility, not decoration)
	if meta.sparkleSlots > 0 and primaryPart then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Rate = 2 + meta.sparkleSlots * 2
		sparkle.Lifetime = NumberRange.new(0.6, 1.1)
		sparkle.Speed = NumberRange.new(0.5, 1.2)
		sparkle.Size = NumberSequence.new(0.25)
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		sparkle.Parent = primaryPart
	end

	model:SetAttribute("HoverName", meta.name)
	model:SetAttribute("HoverOwner", meta.ownerName or "")
	model:SetAttribute("HoverStats", meta.statsText or "")
	model:SetAttribute("HoverBuild", meta.buildText or "")
	model:SetAttribute("Golden", meta.golden)
	model:SetAttribute("Height", spec.height)
	CollectionService:AddTag(model, "FusionZooCreature")
	return model
end

-- A beast in a player's plot.
function CreatureService.buildBeast(beast: Beast, ownerName: string, origin: Vector3): Model
	local totals = SlotStats.slotTotals(beast, ANIMAL_INDEX)
	local stats = SlotStats.resolve(beast, ANIMAL_INDEX)
	local spec = RigMath.resolve({
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
	local sparkles = 0
	for _, level in beast.feed :: any do
		if level >= Config.Rig.SPARKLE_AT then
			sparkles += 1
		end
	end
	local buildText = beast.slots.head
		.. "头 "
		.. beast.slots.body
		.. "身"
		.. (if beast.slots.legs then " " .. beast.slots.legs .. "腿" else "")
		.. (if beast.slots.tail then " " .. beast.slots.tail .. "尾" else "")
	local displayName = beast.name or (beast.slots.head .. beast.slots.body)
	return CreatureService.instantiate(spec, origin, {
		name = displayName,
		ownerName = ownerName,
		statsText = `力{stats.li} 速{stats.su} 智{stats.zhi}`,
		buildText = buildText,
		golden = beast.golden,
		sparkleSlots = sparkles,
		colorway = if beast.colorway then COLORWAY_INDEX[beast.colorway] else nil,
	})
end

-- A plain rescued animal wandering the plot.
function CreatureService.buildAnimal(char: string, origin: Vector3): Model?
	local animal = ANIMAL_INDEX[char]
	if not animal then
		return nil
	end
	local spec = RigMath.resolve({
		head = animal.rig,
		body = animal.rig,
		legs = nil,
		tail = nil,
		totals = { body = animal.li, head = animal.zhi, legs = animal.su, tail = 0 },
	})
	return CreatureService.instantiate(spec, origin, {
		name = `{char} {animal.pinyin}`,
		ownerName = nil,
		statsText = `力{animal.li} 速{animal.su} 智{animal.zhi}`,
		buildText = animal.english,
		golden = false,
		sparkleSlots = 0,
		colorway = nil,
	})
end

return CreatureService
