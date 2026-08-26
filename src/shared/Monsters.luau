--!strict
-- The battle ladder. Each rung pays a bounty once, then unlocks the next.

local Types = require(script.Parent.Types)

local Monsters: { Types.Monster } = {
	{ name = "泥怪", emoji = "🫧", stats = { power = 2, speed = 2, smarts = 1 } },
	{ name = "石怪", emoji = "🪨", stats = { power = 4, speed = 1, smarts = 2 } },
	{ name = "风怪", emoji = "🌪️", stats = { power = 2, speed = 5, smarts = 3 } },
	{ name = "火怪", emoji = "🔥", stats = { power = 5, speed = 4, smarts = 3 } },
	{ name = "冰怪", emoji = "❄️", stats = { power = 4, speed = 4, smarts = 5 } },
	{ name = "影怪", emoji = "👾", stats = { power = 6, speed = 6, smarts = 5 } },
	{ name = "天怪", emoji = "🌌", stats = { power = 8, speed = 7, smarts = 7 } },
}

local module = {}

module.list = Monsters

-- Lowest rung the player has not beaten yet, or the last rung once cleared.
function module.next(defeated: { [string]: boolean }): (Types.Monster, number)
	for index, monster in Monsters do
		if not defeated[monster.name] then
			return monster, index
		end
	end
	return Monsters[#Monsters], #Monsters
end

return module
