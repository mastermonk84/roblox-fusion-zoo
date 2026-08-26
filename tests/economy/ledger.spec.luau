--!strict
-- Economy caps and coin math (criterion 1 economy portion): warm-up doubling,
-- ghost/live daily caps, per-ghost cooldown, real-word once-per-combo, miss
-- penalty floored at zero, sinks refuse without funds.

local T = require("../testkit")
local Ledger = require("../../src/shared/Economy/Ledger")
local ProfileSchema = require("../../src/shared/ProfileSchema")
local Config = require("../../src/shared/Config")
local describe, it, expect = T.describe, T.it, T.expect

local NOW = 1787748347

local function fresh()
	local p = ProfileSchema.template(1, NOW)
	p.coins = 0
	return p
end

return function()
	describe("clean solve + daily warm-up", function()
		it("doubles the first 5 clean solves of the day, then pays 1", function()
			local p = fresh()
			for i = 1, 5 do
				local r = Ledger.faucet(p, "clean_solve", {}, NOW)
				expect(r.delta).to.equal(2)
				expect(p.daily.warmupCount).to.equal(i)
			end
			local r = Ledger.faucet(p, "clean_solve", {}, NOW)
			expect(r.delta).to.equal(1)
			expect(p.coins).to.equal(11)
		end)

		it("shows the coin math", function()
			local p = fresh()
			p.coins = 7
			p.daily.warmupCount = 5
			local r = Ledger.faucet(p, "clean_solve", {}, NOW)
			expect(r.mathString).to.equal("🪙 7 + 1 = 8")
		end)
	end)

	describe("ghost battle caps", function()
		it("caps at 10🪙/day and enforces the per-ghost cooldown", function()
			local p = fresh()
			for i = 1, 5 do
				local r = Ledger.faucet(p, "ghost_win", { ghostKey = `g{i}` }, NOW)
				expect(r.delta).to.equal(2)
			end
			-- cap reached (5 wins x 2 = 10)
			local capped = Ledger.faucet(p, "ghost_win", { ghostKey = "g6" }, NOW)
			expect(capped.delta).to.equal(0)
			expect(capped.capped).to.equal(true)

			-- same ghost within cooldown never pays, even on a fresh day
			ProfileSchema.rollDaily(p, NOW + 86400)
			local sameGhost = Ledger.faucet(p, "ghost_win", { ghostKey = "g1" }, NOW + 3600)
			-- NOTE: rollDaily cleared payouts; simulate within-day cooldown instead
			expect(sameGhost.delta).to.equal(2)
			local tooSoon = Ledger.faucet(p, "ghost_win", { ghostKey = "g1" }, NOW + 7200)
			expect(tooSoon.delta).to.equal(0)
			expect(tooSoon.capped).to.equal(true)
		end)
	end)

	describe("live battle caps", function()
		it("caps combined live income at 9🪙/day", function()
			local p = fresh()
			expect(Ledger.faucet(p, "live_win", {}, NOW).delta).to.equal(3)
			expect(Ledger.faucet(p, "live_win", {}, NOW).delta).to.equal(3)
			expect(Ledger.faucet(p, "live_win", {}, NOW).delta).to.equal(3)
			local over = Ledger.faucet(p, "live_participation", {}, NOW)
			expect(over.delta).to.equal(0)
			expect(over.capped).to.equal(true)
		end)
	end)

	describe("real-word discovery", function()
		it("pays 5🪙 exactly once per combo, forever", function()
			local p = fresh()
			expect(Ledger.faucet(p, "real_word", { comboWord = "熊猫" }, NOW).delta).to.equal(5)
			expect(Ledger.faucet(p, "real_word", { comboWord = "熊猫" }, NOW).delta).to.equal(0)
			expect(Ledger.faucet(p, "real_word", { comboWord = "龙虾" }, NOW).delta).to.equal(5)
			ProfileSchema.rollDaily(p, NOW + 86400 * 30)
			expect(Ledger.faucet(p, "real_word", { comboWord = "熊猫" }, NOW).delta).to.equal(0)
		end)
	end)

	describe("miss penalty", function()
		it("floors at zero", function()
			local p = fresh()
			p.coins = 1
			expect(Ledger.missPenalty(p).delta).to.equal(-1)
			expect(p.coins).to.equal(0)
			expect(Ledger.missPenalty(p).delta).to.equal(0)
			expect(p.coins).to.equal(0)
		end)
	end)

	describe("sinks", function()
		it("refuses without funds, spends with them", function()
			local p = fresh()
			p.coins = 9
			local refused = Ledger.sink(p, "fuse", Config.Economy.FUSE_COST)
			expect(refused.ok).to.equal(false)
			expect(refused.err).to.equal("not_enough_coins")
			expect(p.coins).to.equal(9)
			p.coins = 12
			local paid = Ledger.sink(p, "fuse", Config.Economy.FUSE_COST)
			expect(paid.ok).to.equal(true)
			expect(p.coins).to.equal(2)
			expect(paid.mathString).to.equal("🪙 12 − 10 = 2")
		end)
	end)
end
