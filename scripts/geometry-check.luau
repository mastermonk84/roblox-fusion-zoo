--!strict
-- Criterion 8b, headless: resolve every head × body rig combination at min and
-- max slot stats (plus legs/tail extremes), assert rigs stay valid (no NaN,
-- positive sizes, caps respected, legs touch the ground, head meets the neck),
-- and check pairwise silhouette distinctness INCLUDING orientation swaps
-- (A-head/B-body vs B-head/A-body). Run: lune run scripts/geometry-check

local process = require("@lune/process")

local RigMath = require("../src/shared/Rig/RigMath")
local Animals = require("../src/shared/Data/Animals")
local Config = require("../src/shared/Config")

local rigNames: { string } = {}
for _, animal in Animals :: { any } do
	table.insert(rigNames, animal.rig)
end
table.sort(rigNames)

local errors: { string } = {}
local function check(cond: boolean, message: string)
	if not cond then
		table.insert(errors, message)
	end
end

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function validate(spec: RigMath.RigSpec, label: string)
	check(#spec.parts >= 7, `{label}: too few parts ({#spec.parts})`)
	for _, part in spec.parts do
		for _, axis in { "x", "y", "z" } do
			local sizeAxis = (part.size :: any)[axis]
			local offsetAxis = (part.offset :: any)[axis]
			check(finite(sizeAxis) and sizeAxis > 0, `{label}: bad size {axis} in {part.module}`)
			check(finite(offsetAxis), `{label}: NaN offset {axis} in {part.module}`)
		end
	end
	-- legs reach the ground (feet at y≈0)
	local minFoot = math.huge
	for _, part in spec.parts do
		if part.module == "legs" then
			minFoot = math.min(minFoot, part.offset.y - part.size.y / 2)
		end
	end
	check(minFoot < 0.15 and minFoot > -0.15, `{label}: legs float/clip ({minFoot})`)
	-- head module overlaps the neck socket area
	local neck = spec.sockets.neck
	local headTouches = false
	for _, part in spec.parts do
		if part.module == "head" and part.feature == nil then
			local dy = math.abs(part.offset.y - neck.y)
			local dz = math.abs(part.offset.z - neck.z)
			if dy < part.size.y and dz < part.size.z then
				headTouches = true
			end
		end
	end
	check(headTouches, `{label}: head detached from neck socket`)
	-- overall height bounded by the scale cap
	check(spec.height < 30, `{label}: rig too tall ({spec.height})`)
end

local MIN_TOTALS = { body = 1, head = 1, legs = 1, tail = 0 }
local MAX = Config.Fusion.STAT_CAP
local MAX_TOTALS = { body = MAX, head = MAX, legs = MAX, tail = MAX }

local combos = 0
local silhouettes: { [string]: { number } } = {}

for _, headRig in rigNames do
	for _, bodyRig in rigNames do
		for _, totals in { MIN_TOTALS, MAX_TOTALS } do
			local label = `{headRig}-head/{bodyRig}-body@{totals.body}`
			local spec = RigMath.resolve({
				head = headRig,
				body = bodyRig,
				legs = nil,
				tail = nil,
				totals = totals :: any,
			})
			validate(spec, label)
			combos += 1
			if totals == MIN_TOTALS then
				silhouettes[`{headRig}|{bodyRig}`] = RigMath.silhouette(spec, 20)
			end
		end
	end
end

-- legs/tail extremes on a representative spread
for _, pair in { { "cat", "horse" }, { "elephant", "shrimp" }, { "dragon", "frog" } } do
	for _, legsRig in { "rabbit", "fish" } do
		for _, tailRig in { "tiger", "sheep" } do
			local spec = RigMath.resolve({
				head = pair[1],
				body = pair[2],
				legs = legsRig,
				tail = tailRig,
				totals = MAX_TOTALS :: any,
			})
			validate(spec, `{pair[1]}/{pair[2]}/{legsRig}/{tailRig}@max`)
			combos += 1
		end
	end
end

-- orientation swaps must read differently across the plot (silhouette distance)
local swapChecked, swapFailures = 0, 0
for i, a in rigNames do
	for j, b in rigNames do
		if i < j then
			local ab = silhouettes[`{a}|{b}`]
			local ba = silhouettes[`{b}|{a}`]
			local distance = RigMath.silhouetteDistance(ab, ba)
			swapChecked += 1
			if distance < 0.02 then
				swapFailures += 1
				check(
					false,
					`swap {a}/{b}: silhouettes nearly identical ({string.format("%.3f", distance)})`
				)
			end
		end
	end
end

-- scale cap respected: max-stat rig no more than cap× the min-stat rig height
for _, headRig in { "cat", "elephant" } do
	local small = RigMath.resolve({
		head = headRig,
		body = headRig,
		legs = nil,
		tail = nil,
		totals = MIN_TOTALS :: any,
	})
	local big = RigMath.resolve({
		head = headRig,
		body = headRig,
		legs = nil,
		tail = nil,
		totals = MAX_TOTALS :: any,
	})
	local ratio = big.height / small.height
	check(ratio <= Config.Rig.SCALE_CAP + 0.05, `{headRig}: growth ratio {ratio} exceeds cap`)
	check(ratio > 1.05, `{headRig}: max build should visibly outgrow min build ({ratio})`)
end

if #errors > 0 then
	print(`GEOMETRY CHECK FAILED — {#errors} error(s) across {combos} builds:`)
	for index, err in errors do
		if index > 25 then
			print(`  … and {#errors - 25} more`)
			break
		end
		print(`  ✗ {err}`)
	end
	process.exit(1)
end

print(`OK: {combos} builds valid, {swapChecked} orientation swaps distinct (0 failures)`)
