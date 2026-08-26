--!strict
-- Criterion 6 basics: template validity, migration chain, reconcile, daily
-- rollover, rolling accuracy, DataStore-storability, leave/rejoin round-trip,
-- and crash-simulation lock recovery — all against the mock backend.

local T = require("../testkit")
local ProfileSchema = require("../../src/shared/ProfileSchema")
local Config = require("../../src/shared/Config")
local Profiles = require("../../src/server/Services/Profiles")
local MockBackend = require("./mockbackend")
local describe, it, expect = T.describe, T.it, T.expect

local NOW = 1787748347 -- 2026-08-26 UTC
local DAY = 86400

return function()
	describe("template", function()
		it("starts at the configured schema version with starting coins", function()
			local p = ProfileSchema.template(42, NOW)
			expect(p.schemaVersion).to.equal(Config.Profile.SCHEMA_VERSION)
			expect(p.coins).to.equal(Config.Economy.STARTING_COINS)
			expect(p.level).to.equal(1)
			expect(p.unlocked).to.equal(Config.Quiz.UNLOCK_START)
			expect(p.daily.dayKey).to.equal("2026-08-26")
			expect(p.tutorial.grantsGiven).to.equal(false)
		end)
	end)

	describe("migrate + reconcile", function()
		it("upgrades a version-0 blob and fills every missing field", function()
			local old: any = { coins = 33, level = 3 }
			ProfileSchema.migrate(old)
			ProfileSchema.reconcile(old, 7, NOW)
			expect(old.schemaVersion).to.equal(Config.Profile.SCHEMA_VERSION)
			expect(old.coins).to.equal(33) -- existing values survive
			expect(old.level).to.equal(3)
			expect(old.slotsUnlocked.legs).to.equal(false)
			expect(old.daily.dayKey).to.equal("2026-08-26")
			expect(type(old.chars)).to.equal("table")
		end)

		it("fills missing nested keys without clobbering siblings", function()
			local old: any = { slotsUnlocked = { legs = true } }
			ProfileSchema.migrate(old)
			ProfileSchema.reconcile(old, 7, NOW)
			expect(old.slotsUnlocked.legs).to.equal(true)
			expect(old.slotsUnlocked.tail).to.equal(false)
		end)
	end)

	describe("daily rollover", function()
		it("resets counters when the UTC day changes, not before", function()
			local p = ProfileSchema.template(1, NOW)
			p.daily.warmupCount = 5
			p.daily.ghostCoins = 10
			ProfileSchema.rollDaily(p, NOW + 3600)
			expect(p.daily.warmupCount).to.equal(5) -- same day
			ProfileSchema.rollDaily(p, NOW + DAY)
			expect(p.daily.warmupCount).to.equal(0)
			expect(p.daily.ghostCoins).to.equal(0)
			expect(p.daily.dayKey).to.equal("2026-08-27")
		end)
	end)

	describe("rolling accuracy", function()
		it("is 0.5 with no evidence and tracks clean rate", function()
			local p = ProfileSchema.template(1, NOW)
			expect(ProfileSchema.accuracy(p)).to.equal(0.5)
			for i = 1, 10 do
				ProfileSchema.recordAnswer(p, i <= 7)
			end
			expect(ProfileSchema.accuracy(p)).to.be.near(0.7)
		end)

		it("halves at the window so recent play dominates", function()
			local p = ProfileSchema.template(1, NOW)
			for _ = 1, Config.Profile.ACCURACY_WINDOW - 1 do
				ProfileSchema.recordAnswer(p, false) -- terrible history
			end
			ProfileSchema.recordAnswer(p, false)
			expect(p.accuracy.total < Config.Profile.ACCURACY_WINDOW).to.equal(true)
			for _ = 1, 150 do
				ProfileSchema.recordAnswer(p, true) -- strong recent run
			end
			expect(ProfileSchema.accuracy(p) > 0.5).to.equal(true)
		end)
	end)

	describe("persistence (mock backend)", function()
		it("survives leave/rejoin with mastery and beast state intact", function()
			local backend = MockBackend.new()
			local profiles = Profiles.new(backend :: any)
			local p = profiles:load(1001, 42, NOW)
			assert(p, "load failed")
			p.coins = 77
			p.chars["马"] = {
				warm = 3,
				asked = 9,
				evidence = { listen = "2026-08-25", picture = "2026-08-26" },
				firstDay = "2026-08-25",
				lastDay = "2026-08-26",
				mastered = true,
			}
			p.beasts["b1"] = {
				id = "b1",
				name = nil,
				slots = { head = "马", body = "蛙", legs = nil, tail = nil },
				feed = { head = 2, body = 0, legs = 0, tail = 0 },
				golden = false,
				colorway = nil,
				createdAt = NOW,
			}
			profiles:release(1001)
			expect(profiles:get(1001)).to.equal(nil)

			local again = profiles:load(1001, 42, NOW + 100)
			assert(again, "reload failed")
			expect(again.coins).to.equal(77)
			expect(again.chars["马"].warm).to.equal(3)
			expect(again.chars["马"].mastered).to.equal(true)
			expect(again.beasts["b1"].slots.head).to.equal("马")
			expect(again.beasts["b1"].feed.head).to.equal(2)
		end)

		it("refuses a second concurrent load (session lock)", function()
			local backend = MockBackend.new()
			local a = Profiles.new(backend :: any)
			local b = Profiles.new(backend :: any)
			expect(a:load(2002, 1, NOW)).to.be.ok()
			expect(b:load(2002, 1, NOW)).to.equal(nil)
		end)

		it("recovers after a crash: lock steals, data = last autosave", function()
			local backend = MockBackend.new()
			local a = Profiles.new(backend :: any)
			local p = a:load(3003, 1, NOW)
			assert(p, "load failed")
			p.coins = 50
			local mock: any = backend
			mock:save("player_3003") -- autosave tick
			p.coins = 99 -- unsaved progress, then the server dies
			mock:simulateCrash("player_3003")

			local b = Profiles.new(backend :: any)
			local recovered = b:load(3003, 1, NOW + 60)
			assert(recovered, "post-crash load failed")
			expect(recovered.coins).to.equal(50) -- last autosave won
		end)

		it("rejects DataStore-unstorable profiles at the save boundary", function()
			local backend = MockBackend.new()
			local profiles = Profiles.new(backend :: any)
			local p = profiles:load(4004, 1, NOW)
			assert(p, "load failed")
			local anyP: any = p
			anyP.bad = { [true] = "boolean key" }
			expect(function()
				profiles:release(4004)
			end).to.throw("bad key type")
		end)

		it("round-trips a template profile unchanged", function()
			local backend = MockBackend.new()
			local profiles = Profiles.new(backend :: any)
			local p = profiles:load(5005, 42, NOW)
			assert(p, "load failed")
			local snapshot = (backend :: any).load and true
			profiles:release(5005)
			local stored = (backend :: any):storedData("player_5005")
			local fresh = ProfileSchema.template(42, NOW)
			expect(T.deepEqual(stored, fresh)).to.equal(true)
			expect(snapshot).to.equal(true)
		end)
	end)
end
