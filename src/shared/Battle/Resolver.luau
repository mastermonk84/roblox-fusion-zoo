--!strict
-- Round resolution: both sides have secretly picked a stat card and resolved
-- their charge flash. The triangle (速>力, 智>速, 力>智) doubles the advantaged
-- side ONLY when its card is charged; uncharged cards never double. Higher
-- effective value wins; equal values are a tie the match layer replays.

local Config = require("../Config")
local Types = require("../Types")

local Resolver = {}

export type SidePlay = {
	stat: Types.Stat,
	value: number,
	charged: boolean,
}

export type Reveal = {
	stat: Types.Stat,
	label: string,
	base: number,
	eff: number,
	charged: boolean,
	doubled: boolean,
	mathString: string,
}

export type RoundResult = {
	winner: "a" | "b" | "tie",
	a: Reveal,
	b: Reveal,
}

local function reveal(mine: SidePlay, theirs: SidePlay): Reveal
	local advantaged = Config.Battle.TRIANGLE[mine.stat] == theirs.stat
	local doubled = advantaged and mine.charged
	local eff = mine.value * (if doubled then 2 else 1)
	local label = Config.STAT_LABELS[mine.stat]
	return {
		stat = mine.stat,
		label = label,
		base = mine.value,
		eff = eff,
		charged = mine.charged,
		doubled = doubled,
		-- the x2 math is shown, always (design law: arithmetic on screen)
		mathString = if doubled then `{label} {mine.value} ×2 = {eff}` else `{label} {mine.value}`,
	}
end

function Resolver.resolveRound(a: SidePlay, b: SidePlay): RoundResult
	local revealA = reveal(a, b)
	local revealB = reveal(b, a)
	local winner: "a" | "b" | "tie" = "tie"
	if revealA.eff > revealB.eff then
		winner = "a"
	elseif revealB.eff > revealA.eff then
		winner = "b"
	end
	return { winner = winner, a = revealA, b = revealB }
end

-- Tie-break after MAX_TIE_REPLAYS consecutive ties: higher total build stats,
-- then the challenger (side a).
function Resolver.breakStall(totalsA: number, totalsB: number): "a" | "b"
	if totalsB > totalsA then
		return "b"
	end
	return "a"
end

return Resolver
