--!strict
-- Any two beasts can be fused. Stats add (capped), names concatenate, and a
-- handful of combos spell a real word — those get the celebration.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

-- Ordered pairs only: 熊猫 is a panda, 猫熊 is just a chimera.
local REAL_WORDS: { [string]: { name: string, emoji: string, english: string } } = {
	["熊猫"] = { name = "熊猫", emoji = "🐼", english = "panda" },
	["龙虾"] = { name = "龙虾", emoji = "🦞", english = "lobster" },
	["牛蛙"] = { name = "牛蛙", emoji = "🐸", english = "bullfrog" },
	["马鹿"] = { name = "马鹿", emoji = "🦌", english = "red deer" },
}

local module = {}

module.REAL_WORDS = REAL_WORDS

function module.addStats(a: Types.Stats, b: Types.Stats): Types.Stats
	return {
		power = math.min(a.power + b.power, Config.STAT_CAP),
		speed = math.min(a.speed + b.speed, Config.STAT_CAP),
		smarts = math.min(a.smarts + b.smarts, Config.STAT_CAP),
	}
end

-- Returns the real-word entry when the two beasts spell one, else nil.
function module.realWord(a: Types.Beast, b: Types.Beast)
	if #a.parts ~= 1 or #b.parts ~= 1 then
		return nil
	end
	return REAL_WORDS[a.parts[1] .. b.parts[1]]
end

function module.canFuse(a: Types.Beast, b: Types.Beast): (boolean, string?)
	if a.id == b.id then
		return false, "Pick two different beasts"
	end
	if #a.parts + #b.parts > Config.MAX_PARTS then
		return false, `A beast can only be {Config.MAX_PARTS} parts deep`
	end
	return true
end

-- Caller owns id assignment so the server stays the only source of ids.
function module.fuse(a: Types.Beast, b: Types.Beast, id: string): Types.Beast
	local parts = table.clone(a.parts)
	for _, part in b.parts do
		table.insert(parts, part)
	end

	local word = module.realWord(a, b)
	local name = word and word.name or table.concat(parts)
	local emoji = word and word.emoji or (a.emoji .. b.emoji)

	return {
		id = id,
		name = name,
		emoji = emoji,
		parts = parts,
		stats = module.addStats(a.stats, b.stats),
	}
end

return module
