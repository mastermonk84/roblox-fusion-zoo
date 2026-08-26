--!strict
-- Every coin movement in the game goes through these two functions. Faucets
-- apply caps/cooldowns/doubling; sinks check funds. Both return the coin math
-- string the UI must show ("🪙 7 − 1 = 6" — the free math practice is a design
-- feature, not decoration). Callers never touch profile.coins directly.

local Config = require("../Config")
local Types = require("../Types")

type Profile = Types.Profile

local Ledger = {}

export type FaucetResult = {
	ok: boolean,
	delta: number,
	mathString: string,
	capped: boolean, -- a cap or cooldown reduced/blocked the payout
	reason: string?,
}

export type SinkResult = {
	ok: boolean,
	delta: number,
	mathString: string,
	err: string?,
}

local function mathString(before: number, delta: number): string
	if delta >= 0 then
		return `🪙 {before} + {delta} = {before + delta}`
	end
	return `🪙 {before} − {-delta} = {before + delta}`
end

-- ctx carries per-code context: ghostKey for ghost_win, comboWord for
-- real_word. `now` is unix time (server clock); daily rollover is the caller's
-- responsibility (ProfileSchema.rollDaily) before any faucet/sink.
function Ledger.faucet(
	profile: Profile,
	code: Types.FaucetCode,
	ctx: { [string]: any },
	now: number
): FaucetResult
	local economy = Config.Economy
	local amount = 0
	local capped = false

	if code == "clean_solve" then
		amount = economy.CLEAN_SOLVE
		if profile.daily.warmupCount < economy.WARMUP_DOUBLE_COUNT then
			amount *= 2
			profile.daily.warmupCount += 1
		end
	elseif code == "level_up" then
		amount = economy.LEVEL_UP_BONUS
	elseif code == "npc_first_clear" then
		amount = economy.NPC_FIRST_CLEAR
	elseif code == "ghost_win" then
		local ghostKey = ctx.ghostKey :: string
		local lastPaid = profile.daily.ghostPayouts[ghostKey]
		local onCooldown = lastPaid ~= nil and now - lastPaid < economy.GHOST_COOLDOWN_SECONDS
		if onCooldown or profile.daily.ghostCoins + economy.GHOST_WIN > economy.GHOST_DAILY_CAP then
			capped = true
		else
			amount = economy.GHOST_WIN
			profile.daily.ghostCoins += amount
			profile.daily.ghostPayouts[ghostKey] = now
		end
	elseif code == "live_win" or code == "live_participation" then
		local pay = if code == "live_win" then economy.LIVE_WIN else economy.LIVE_PARTICIPATION
		if profile.daily.liveCoins + pay > economy.LIVE_DAILY_CAP then
			capped = true
		else
			amount = pay
			profile.daily.liveCoins += amount
		end
	elseif code == "real_word" then
		local word = ctx.comboWord :: string
		if profile.realWordsFound[word] then
			amount = 0 -- once per combo, ever
		else
			profile.realWordsFound[word] = true
			amount = economy.REAL_WORD_BONUS
		end
	elseif code == "tutorial" then
		amount = ctx.amount :: number
	end

	local before = profile.coins
	profile.coins += amount
	return {
		ok = true,
		delta = amount,
		mathString = mathString(before, amount),
		capped = capped,
		reason = if capped then "daily_cap" else nil,
	}
end

-- The miss penalty is a "sink" with a floor at zero, never below.
function Ledger.missPenalty(profile: Profile): SinkResult
	local before = profile.coins
	local delta = -math.min(profile.coins, Config.Economy.MISS_PENALTY)
	profile.coins += delta
	return {
		ok = true,
		delta = delta,
		mathString = if delta < 0 then mathString(before, delta) else `🪙 {before}`,
		err = nil,
	}
end

function Ledger.sink(profile: Profile, code: Types.SinkCode, cost: number): SinkResult
	assert(cost >= 0, `sink {code}: negative cost`)
	if profile.coins < cost then
		return {
			ok = false,
			delta = 0,
			mathString = `🪙 {profile.coins}`,
			err = "not_enough_coins",
		}
	end
	local before = profile.coins
	profile.coins -= cost
	return {
		ok = true,
		delta = -cost,
		mathString = mathString(before, -cost),
		err = nil,
	}
end

return Ledger
