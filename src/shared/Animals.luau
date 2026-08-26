--!strict
-- The rescuable pool. Every entry is a Grade-1 curriculum character the kids
-- already meet in missions, so the zoo doubles as review.

local Types = require(script.Parent.Types)

local Animals: { Types.Animal } = {
	{ char = "马", pinyin = "mǎ", english = "horse", emoji = "🐴", stats = { power = 3, speed = 4, smarts = 2 } },
	{ char = "牛", pinyin = "niú", english = "cow", emoji = "🐮", stats = { power = 5, speed = 1, smarts = 2 } },
	{ char = "羊", pinyin = "yáng", english = "sheep", emoji = "🐑", stats = { power = 2, speed = 2, smarts = 3 } },
	{ char = "猫", pinyin = "māo", english = "cat", emoji = "🐱", stats = { power = 2, speed = 4, smarts = 4 } },
	{ char = "狗", pinyin = "gǒu", english = "dog", emoji = "🐶", stats = { power = 3, speed = 3, smarts = 4 } },
	{ char = "熊", pinyin = "xióng", english = "bear", emoji = "🐻", stats = { power = 5, speed = 2, smarts = 2 } },
	{ char = "虎", pinyin = "hǔ", english = "tiger", emoji = "🐯", stats = { power = 5, speed = 4, smarts = 2 } },
	{ char = "兔", pinyin = "tù", english = "rabbit", emoji = "🐰", stats = { power = 1, speed = 5, smarts = 3 } },
	{ char = "鸟", pinyin = "niǎo", english = "bird", emoji = "🐦", stats = { power = 1, speed = 5, smarts = 3 } },
	{ char = "鱼", pinyin = "yú", english = "fish", emoji = "🐟", stats = { power = 2, speed = 3, smarts = 2 } },
	{ char = "蛙", pinyin = "wā", english = "frog", emoji = "🐸", stats = { power = 2, speed = 3, smarts = 3 } },
	{ char = "虾", pinyin = "xiā", english = "shrimp", emoji = "🦐", stats = { power = 1, speed = 4, smarts = 2 } },
	{ char = "鸡", pinyin = "jī", english = "chicken", emoji = "🐔", stats = { power = 1, speed = 3, smarts = 2 } },
	{ char = "鹿", pinyin = "lù", english = "deer", emoji = "🦌", stats = { power = 2, speed = 5, smarts = 3 } },
	{ char = "龙", pinyin = "lóng", english = "dragon", emoji = "🐲", stats = { power = 5, speed = 4, smarts = 5 } },
}

local byChar: { [string]: Types.Animal } = {}
for _, animal in Animals do
	byChar[animal.char] = animal
end

local module = {}

module.list = Animals

function module.get(char: string): Types.Animal?
	return byChar[char]
end

-- Weighted so the dragon stays rare — it is the only 5/4/5 in the pool.
function module.roll(random: Random): Types.Animal
	while true do
		local candidate = Animals[random:NextInteger(1, #Animals)]
		if candidate.char ~= "龙" or random:NextNumber() < 0.08 then
			return candidate
		end
	end
end

return module
