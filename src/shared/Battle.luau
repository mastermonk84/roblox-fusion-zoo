--!strict
-- Best-of-3. Each round both sides reveal one random stat card; the triangle
-- doubles an advantaged stat and the bigger number wins. Ties go to the kid.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

export type Round = {
	yourStat: string,
	theirStat: string,
	yourValue: number,
	theirValue: number,
	yourDoubled: boolean,
	theirDoubled: boolean,
	youWon: boolean,
}

export type Result = {
	rounds: { Round },
	youWon: boolean,
}

local module = {}

local function roll(random: Random): string
	return Config.STATS[random:NextInteger(1, #Config.STATS)]
end

function module.resolve(mine: Types.Stats, theirs: Types.Stats, random: Random): Result
	local rounds: { Round } = {}
	local wins, losses = 0, 0

	while wins < 2 and losses < 2 and #rounds < Config.BATTLE_ROUNDS do
		local yourStat, theirStat = roll(random), roll(random)
		local yourDoubled = Config.BEATS[yourStat] == theirStat
		local theirDoubled = Config.BEATS[theirStat] == yourStat

		local mineByName = mine :: { [string]: number }
		local theirsByName = theirs :: { [string]: number }
		local yourValue = mineByName[yourStat] * (yourDoubled and 2 or 1)
		local theirValue = theirsByName[theirStat] * (theirDoubled and 2 or 1)
		local youWon = yourValue >= theirValue

		if youWon then
			wins += 1
		else
			losses += 1
		end

		table.insert(rounds, {
			yourStat = yourStat,
			theirStat = theirStat,
			yourValue = yourValue,
			theirValue = theirValue,
			yourDoubled = yourDoubled,
			theirDoubled = theirDoubled,
			youWon = youWon,
		})
	end

	return { rounds = rounds, youWon = wins > losses }
end

return module
