--!strict
-- Verbatim port of the web game's rng.ts. mulberry32 must reproduce the exact
-- JS sequence (uint32 wrap, Math.imul, /2^32) so a kid's deck order survives a
-- backup restore across platforms.

local Rng = {}

-- Math.imul: 32-bit multiply mod 2^32. Split one factor into 16-bit halves so
-- every intermediate product stays exact in a double (< 2^53).
local function umul32(a: number, b: number): number
	local al = a % 65536
	local ah = math.floor(a / 65536) % 65536
	return (al * b + (ah * b % 65536) * 65536) % 4294967296
end

export type Rand = () -> number

function Rng.mulberry32(seed: number): Rand
	local a = math.floor(seed) % 4294967296
	return function(): number
		a = (a + 0x6D2B79F5) % 4294967296
		local t = umul32(bit32.bxor(a, bit32.rshift(a, 15)), bit32.bor(1, a))
		t = bit32.bxor(
			(t + umul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(61, t))) % 4294967296,
			t
		)
		return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
	end
end

-- Fisher-Yates with descending i, identical to the web version.
function Rng.seededShuffle<T>(items: { T }, rand: Rand): { T }
	local arr = table.clone(items)
	for i = #arr, 2, -1 do
		local j = math.floor(rand() * i) + 1
		arr[i], arr[j] = arr[j], arr[i]
	end
	return arr
end

export type Weighted<T> = { { item: T, weight: number } }

function Rng.weightedPick<T>(items: Weighted<T>, rand: Rand): T
	local total = 0
	for _, entry in items do
		total += entry.weight
	end
	local roll = rand() * total
	for _, entry in items do
		roll -= entry.weight
		if roll <= 0 then
			return entry.item
		end
	end
	return items[#items].item
end

function Rng.pick<T>(items: { T }, rand: Rand): T
	return items[math.floor(rand() * #items) + 1]
end

return Rng
