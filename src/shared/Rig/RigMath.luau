--!strict
-- Pure rig resolution: a build (slot occupants + slot stat totals) becomes a
-- list of primitive-part specs with plain {x,y,z} vectors, so geometry-check
-- can validate every combination headless and CreatureService just instantiates.
--
-- Visual growth is a legibility mechanic: each module scales +6%/point above
-- baseline 3 on its slot's total stat, clamped to ×1.55, with axis emphasis
-- (legs lengthen more than thicken, tails extend, bodies bulk, heads grow
-- uniformly). Sockets are re-solved from the scaled body so plugs always meet.

local Config = require("../Config")
local Rigs = require("../Data/Rigs")

local RigMath = {}

export type Vec = { x: number, y: number, z: number }
export type PartSpec = {
	module: string, -- "body" | "head" | "legs" | "tail"
	shape: string, -- "Block" | "Ball" | "Cylinder" | "Wedge"
	size: Vec,
	offset: Vec, -- from rig origin (ground under body center)
	color: { number }, -- {r,g,b} 0-255
	feature: string?,
}
export type RigSpec = {
	parts: { PartSpec },
	sockets: { neck: Vec, tail: Vec, legs: { Vec } },
	height: number,
	bounds: { min: Vec, max: Vec },
}

export type RigParams = {
	primary: { number },
	secondary: { number },
	accent: { number },
	bodyType: string,
	body: { number },
	head: { number },
	legLength: number,
	legThickness: number,
	tail: { kind: string, length: number },
	headFeatures: { string },
	bodyFeatures: { string },
}

local BASELINE = 3

local function vec(x: number, y: number, z: number): Vec
	return { x = x, y = y, z = z }
end

function RigMath.moduleScale(stat: number): number
	local raw = 1 + Config.Rig.SCALE_PER_POINT * math.max(0, stat - BASELINE)
	return math.min(Config.Rig.SCALE_CAP, raw)
end

local function rigFor(name: string): RigParams
	local params = (Rigs :: any).rigs[name]
	assert(params, `no rig params for {name}`)
	return params :: RigParams
end

export type Build = {
	head: string, -- rig names (animals.json "rig")
	body: string,
	legs: string?,
	tail: string?,
	totals: { body: number, head: number, legs: number, tail: number },
}

function RigMath.resolve(build: Build): RigSpec
	local bodyRig = rigFor(build.body)
	local headRig = rigFor(build.head)
	local legsRig = rigFor(build.legs or build.body)
	local parts: { PartSpec } = {}

	local bodyScale = RigMath.moduleScale(build.totals.body)
	local headScale = RigMath.moduleScale(build.totals.head)
	local legScale = RigMath.moduleScale(build.totals.legs)
	local tailScale = RigMath.moduleScale(build.totals.tail)

	-- ── legs (length scales fully, thickness at 40% emphasis) ──────────────
	local legLength = legsRig.legLength * legScale
	local legThickness = legsRig.legThickness * (1 + (legScale - 1) * 0.4)
	if bodyRig.bodyType == "fish" or bodyRig.bodyType == "snake" then
		legLength = legsRig.legLength * 0.5 * legScale -- fins/nubs stay low
	end

	-- ── body, resting on the legs ──────────────────────────────────────────
	local bodySize =
		vec(bodyRig.body[1] * bodyScale, bodyRig.body[2] * bodyScale, bodyRig.body[3] * bodyScale)
	local bodyCenterY = legLength + bodySize.y / 2
	table.insert(parts, {
		module = "body",
		shape = if bodyRig.bodyType == "fish" then "Ball" else "Block",
		size = bodySize,
		offset = vec(0, bodyCenterY, 0),
		color = bodyRig.primary,
	})

	for _, feature in bodyRig.bodyFeatures do
		if feature == "wings" then
			for _, side in { -1, 1 } do
				table.insert(parts, {
					module = "body",
					shape = "Block",
					size = vec(0.4, bodySize.y * 0.5, bodySize.z * 0.62),
					offset = vec(side * (bodySize.x / 2 + 0.2), bodyCenterY + bodySize.y * 0.18, 0),
					color = bodyRig.secondary,
					feature = "wing",
				})
			end
		elseif feature == "wool" then
			table.insert(parts, {
				module = "body",
				shape = "Ball",
				size = vec(bodySize.x * 1.12, bodySize.y * 0.7, bodySize.z * 0.9),
				offset = vec(0, bodyCenterY + bodySize.y * 0.32, 0),
				color = bodyRig.secondary,
				feature = "wool",
			})
		elseif
			feature == "shell"
			or feature == "segments"
			or feature == "stripes"
			or feature == "spines"
			or feature == "fins"
		then
			table.insert(parts, {
				module = "body",
				shape = if feature == "shell" then "Ball" else "Block",
				size = vec(bodySize.x * 0.85, bodySize.y * 0.35, bodySize.z * 0.75),
				offset = vec(0, bodyCenterY + bodySize.y * 0.42, 0),
				color = bodyRig.accent,
				feature = feature,
			})
		end
	end

	-- ── leg parts at four sockets under the body ───────────────────────────
	local legSockets: { Vec } = {}
	local legOffsetX = bodySize.x / 2 - legThickness / 2
	local legOffsetZ = bodySize.z / 2 - legThickness / 2 - 0.2
	for _, dz in { -1, 1 } do
		for _, dx in { -1, 1 } do
			local socket = vec(dx * legOffsetX, legLength, dz * legOffsetZ)
			table.insert(legSockets, socket)
			table.insert(parts, {
				module = "legs",
				shape = "Block",
				size = vec(legThickness, legLength, legThickness),
				offset = vec(socket.x, legLength / 2, socket.z),
				color = legsRig.primary,
			})
		end
	end

	-- ── head at the neck socket (front-top of the body) ────────────────────
	local headSize =
		vec(headRig.head[1] * headScale, headRig.head[2] * headScale, headRig.head[3] * headScale)
	local neck = vec(0, bodyCenterY + bodySize.y / 2, -(bodySize.z / 2))
	local headCenter = vec(0, neck.y + headSize.y * 0.35, neck.z - headSize.z * 0.25)
	table.insert(parts, {
		module = "head",
		shape = "Block",
		size = headSize,
		offset = headCenter,
		color = headRig.primary,
	})
	-- eyes: every head gets them (universal readability)
	for _, side in { -1, 1 } do
		table.insert(parts, {
			module = "head",
			shape = "Ball",
			size = vec(0.5, 0.5, 0.3),
			offset = vec(
				side * headSize.x * 0.26,
				headCenter.y + headSize.y * 0.16,
				headCenter.z - headSize.z / 2
			),
			color = { 35, 32, 38 },
			feature = "eye",
		})
	end

	for _, feature in headRig.headFeatures do
		if feature == "pointy_ears" or feature == "upright_ears" then
			for _, side in { -1, 1 } do
				table.insert(parts, {
					module = "head",
					shape = "Wedge",
					size = vec(0.7, 0.9, 0.5),
					offset = vec(
						side * headSize.x * 0.32,
						headCenter.y + headSize.y / 2 + 0.4,
						headCenter.z
					),
					color = headRig.primary,
					feature = feature,
				})
			end
		elseif feature == "tall_ears" then
			for _, side in { -1, 1 } do
				table.insert(parts, {
					module = "head",
					shape = "Block",
					size = vec(0.55, 2.0, 0.35),
					offset = vec(
						side * headSize.x * 0.28,
						headCenter.y + headSize.y / 2 + 1.0,
						headCenter.z
					),
					color = headRig.secondary,
					feature = feature,
				})
			end
		elseif
			feature == "big_round_ears"
			or feature == "small_round_ears"
			or feature == "round_ears"
			or feature == "big_flat_ears"
		then
			local earSize = if feature == "big_round_ears"
				then 1.1
				elseif feature == "big_flat_ears" then 1.5
				else 0.6
			for _, side in { -1, 1 } do
				table.insert(parts, {
					module = "head",
					shape = "Ball",
					size = vec(earSize, earSize, 0.4),
					offset = vec(
						side * (headSize.x * 0.42 + earSize * 0.2),
						headCenter.y + headSize.y * 0.42,
						headCenter.z
					),
					color = headRig.primary,
					feature = feature,
				})
			end
		elseif feature == "floppy_ears" then
			for _, side in { -1, 1 } do
				table.insert(parts, {
					module = "head",
					shape = "Block",
					size = vec(0.4, 1.2, 0.8),
					offset = vec(side * (headSize.x / 2 + 0.2), headCenter.y, headCenter.z),
					color = headRig.secondary,
					feature = feature,
				})
			end
		elseif feature == "beak" or feature == "hook_beak" then
			table.insert(parts, {
				module = "head",
				shape = "Wedge",
				size = vec(0.7, 0.6, 1.0),
				offset = vec(
					0,
					headCenter.y - headSize.y * 0.05,
					headCenter.z - headSize.z / 2 - 0.4
				),
				color = headRig.accent,
				feature = feature,
			})
		elseif feature == "snout" or feature == "long_snout" or feature == "wide_mouth" then
			local snoutLength = if feature == "long_snout" then 1.4 else 0.7
			table.insert(parts, {
				module = "head",
				shape = "Block",
				size = vec(headSize.x * 0.55, headSize.y * 0.4, snoutLength),
				offset = vec(
					0,
					headCenter.y - headSize.y * 0.2,
					headCenter.z - headSize.z / 2 - snoutLength / 2
				),
				color = headRig.secondary,
				feature = feature,
			})
		elseif feature == "trunk" then
			table.insert(parts, {
				module = "head",
				shape = "Block",
				size = vec(0.7, 2.2, 0.7),
				offset = vec(0, headCenter.y - headSize.y / 2 - 0.9, headCenter.z - headSize.z / 2),
				color = headRig.primary,
				feature = feature,
			})
		elseif feature == "horns" or feature == "curl_horns" then
			for _, side in { -1, 1 } do
				table.insert(parts, {
					module = "head",
					shape = if feature == "curl_horns" then "Ball" else "Wedge",
					size = vec(0.6, 0.8, 0.6),
					offset = vec(
						side * headSize.x * 0.45,
						headCenter.y + headSize.y * 0.45,
						headCenter.z + headSize.z * 0.1
					),
					color = headRig.accent,
					feature = feature,
				})
			end
		elseif feature == "whiskers" or feature == "antennae" then
			for _, side in { -1, 1 } do
				table.insert(parts, {
					module = "head",
					shape = "Block",
					size = vec(0.1, 1.2, 0.1),
					offset = vec(
						side * headSize.x * 0.5,
						headCenter.y
							+ (
								if feature == "antennae"
									then headSize.y * 0.5
									else -headSize.y * 0.1
							),
						headCenter.z - headSize.z * 0.3
					),
					color = headRig.accent,
					feature = feature,
				})
			end
		elseif feature == "mane" then
			table.insert(parts, {
				module = "head",
				shape = "Block",
				size = vec(headSize.x * 0.5, headSize.y * 1.0, 0.5),
				offset = vec(
					0,
					headCenter.y + headSize.y * 0.3,
					headCenter.z + headSize.z / 2 + 0.2
				),
				color = headRig.secondary,
				feature = feature,
			})
		elseif feature == "comb" then
			table.insert(parts, {
				module = "head",
				shape = "Block",
				size = vec(0.3, 0.7, 1.1),
				offset = vec(0, headCenter.y + headSize.y / 2 + 0.3, headCenter.z),
				color = headRig.accent,
				feature = feature,
			})
		elseif feature == "eye_bumps" then
			for _, side in { -1, 1 } do
				table.insert(parts, {
					module = "head",
					shape = "Ball",
					size = vec(0.8, 0.8, 0.8),
					offset = vec(
						side * headSize.x * 0.3,
						headCenter.y + headSize.y / 2 + 0.2,
						headCenter.z - headSize.z * 0.2
					),
					color = headRig.primary,
					feature = feature,
				})
			end
		elseif feature == "tongue" then
			table.insert(parts, {
				module = "head",
				shape = "Block",
				size = vec(0.2, 0.1, 0.9),
				offset = vec(
					0,
					headCenter.y - headSize.y * 0.25,
					headCenter.z - headSize.z / 2 - 0.45
				),
				color = headRig.accent,
				feature = feature,
			})
		elseif feature == "brow" or feature == "big_eyes" then
			-- rendered via the universal eyes; brow adds a strip
			if feature == "brow" then
				table.insert(parts, {
					module = "head",
					shape = "Block",
					size = vec(headSize.x * 0.8, 0.25, 0.4),
					offset = vec(
						0,
						headCenter.y + headSize.y * 0.3,
						headCenter.z - headSize.z / 2 + 0.1
					),
					color = headRig.accent,
					feature = feature,
				})
			end
		end
	end

	-- ── tail from the TAIL occupant (or the body animal's default) ─────────
	local tailRig = rigFor(build.tail or build.body)
	local tailKind = tailRig.tail.kind
	local tailSocket = vec(0, bodyCenterY + bodySize.y * 0.2, bodySize.z / 2)
	if tailKind ~= "none" then
		local tailLength = tailRig.tail.length * tailScale
		local tailGirth = 0.5 * (1 + (tailScale - 1) * 0.3)
		local shape = if tailKind == "puff"
			then "Ball"
			elseif tailKind == "fin" or tailKind == "fan" then "Wedge"
			else "Block"
		local size = if tailKind == "puff"
			then vec(tailLength, tailLength, tailLength)
			elseif tailKind == "thin" then vec(0.25, 0.25, tailLength)
			else vec(tailGirth, tailGirth, tailLength)
		table.insert(parts, {
			module = "tail",
			shape = shape,
			size = size,
			offset = vec(
				0,
				tailSocket.y + tailLength * 0.15,
				tailSocket.z + (if tailKind == "puff" then size.z * 0.4 else tailLength / 2)
			),
			color = tailRig.primary,
			feature = tailKind,
		})
	end

	-- bounds + validity data
	local minBound = vec(math.huge, math.huge, math.huge)
	local maxBound = vec(-math.huge, -math.huge, -math.huge)
	for _, part in parts do
		minBound.x = math.min(minBound.x, part.offset.x - part.size.x / 2)
		minBound.y = math.min(minBound.y, part.offset.y - part.size.y / 2)
		minBound.z = math.min(minBound.z, part.offset.z - part.size.z / 2)
		maxBound.x = math.max(maxBound.x, part.offset.x + part.size.x / 2)
		maxBound.y = math.max(maxBound.y, part.offset.y + part.size.y / 2)
		maxBound.z = math.max(maxBound.z, part.offset.z + part.size.z / 2)
	end

	return {
		parts = parts,
		sockets = { neck = neck, tail = tailSocket, legs = legSockets },
		height = maxBound.y,
		bounds = { min = minBound, max = maxBound },
	}
end

-- Coarse side-profile occupancy grid (Z × Y) for silhouette distinctness.
function RigMath.silhouette(spec: RigSpec, cells: number): { number }
	local grid = table.create(cells * cells, 0)
	local minZ, maxZ = spec.bounds.min.z, spec.bounds.max.z
	local minY, maxY = spec.bounds.min.y, spec.bounds.max.y
	local spanZ = math.max(0.001, maxZ - minZ)
	local spanY = math.max(0.001, maxY - minY)
	for _, part in spec.parts do
		local z0 = math.floor((part.offset.z - part.size.z / 2 - minZ) / spanZ * cells)
		local z1 = math.ceil((part.offset.z + part.size.z / 2 - minZ) / spanZ * cells)
		local y0 = math.floor((part.offset.y - part.size.y / 2 - minY) / spanY * cells)
		local y1 = math.ceil((part.offset.y + part.size.y / 2 - minY) / spanY * cells)
		for zi = math.max(0, z0), math.min(cells - 1, z1 - 1) do
			for yi = math.max(0, y0), math.min(cells - 1, y1 - 1) do
				grid[zi * cells + yi + 1] = 1
			end
		end
	end
	return grid
end

function RigMath.silhouetteDistance(a: { number }, b: { number }): number
	local diff = 0
	for i, cell in a do
		if cell ~= b[i] then
			diff += 1
		end
	end
	return diff / #a
end

return RigMath
