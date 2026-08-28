--!strict
-- All zoo actions: rescue (MASTERED-gated), fuse/re-fuse (slot builds),
-- feeding, slot unlocks, naming (mastered-chars-only — the no-free-text
-- guarantee), decorations, colorways, active beast. Engine-free: deps are
-- injected, every rule testable headless. Costs come from Config/FeedCurve,
-- never from the client.

local Animals = require("../../shared/Data/Animals")
local Colorways = require("../../shared/Data/Colorways")
local Config = require("../../shared/Config")
local Decorations = require("../../shared/Data/Decorations")
local FeedCurve = require("../../shared/Fusion/FeedCurve")
local Ledger = require("../../shared/Economy/Ledger")
local Mastery = require("../../shared/Quiz/Mastery")
local RealWords = require("../../shared/Fusion/RealWords")
local SlotStats = require("../../shared/Fusion/SlotStats")
local Types = require("../../shared/Types")

type Profile = Types.Profile
type Beast = Types.Beast

local ANIMAL_INDEX = SlotStats.index(Animals :: { Types.AnimalDef })
local MAX_BEASTS = 12

local DECOR_INDEX: { [string]: any } = {}
for _, d in Decorations :: { any } do
	DECOR_INDEX[d.id] = d
end
local COLORWAY_INDEX: { [string]: any } = {}
for _, c in Colorways :: { any } do
	COLORWAY_INDEX[c.id] = c
end

local ZooService = {}
ZooService.__index = ZooService

export type Deps = {
	profiles: any,
	analytics: any,
	now: (() -> number)?,
	onBeastChanged: ((userId: number, profile: Profile) -> ())?, -- ghost publish + world refresh hook
}

function ZooService.new(deps: Deps)
	return setmetatable({
		_profiles = deps.profiles,
		_analytics = deps.analytics,
		_now = deps.now or os.time,
		_onBeastChanged = deps.onBeastChanged or function() end,
	}, ZooService)
end

local function fail(err: string): any
	return { ok = false, err = err }
end

local function getProfile(self: any, userId: number): Profile?
	return self._profiles:get(userId)
end

-- Public info for the rescue pen: every animal with owned/gate state — locked
-- silhouettes advertise what studying buys next.
function ZooService.rescueList(self: any, userId: number): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local list = {}
	for _, animal in Animals :: { Types.AnimalDef } do
		table.insert(list, {
			char = animal.char,
			pinyin = animal.pinyin,
			english = animal.english,
			rig = animal.rig,
			li = animal.li,
			su = animal.su,
			zhi = animal.zhi,
			cost = Config.Economy.RESCUE_TIERS[animal.tier],
			owned = profile.animals[animal.char] == true,
			mastered = Mastery.isMastered(profile, animal.char),
		})
	end
	return { ok = true, animals = list, coins = profile.coins }
end

function ZooService.rescue(self: any, userId: number, char: string): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local animal = ANIMAL_INDEX[char]
	if not animal then
		return fail("no_such_animal")
	end
	if profile.animals[char] then
		return fail("already_owned")
	end
	if not Mastery.isMastered(profile, char) then
		return fail("character_not_mastered") -- 先学会 "{char}" 这个字!
	end
	local cost = Config.Economy.RESCUE_TIERS[animal.tier]
	local paid = Ledger.sink(profile, "rescue", cost)
	if not paid.ok then
		return fail(paid.err :: string)
	end
	profile.animals[char] = true
	self._analytics:track(userId, "sink", "rescue", paid.delta, { char = char })
	self._onBeastChanged(userId, profile) -- the rescued animal appears in the plot
	return { ok = true, char = char, coinMath = paid.mathString, newCoins = profile.coins }
end

local function occupantsValid(profile: Profile, slots: { [string]: string? }): string?
	for _, slot in { "head", "body", "legs", "tail" } do
		local char = slots[slot]
		if char ~= nil then
			if not ANIMAL_INDEX[char] then
				return "no_such_animal"
			end
			if not profile.animals[char] then
				return "animal_not_owned"
			end
		end
	end
	if not slots.head or not slots.body then
		return "need_head_and_body"
	end
	return nil
end

local function slotGateError(profile: Profile, slots: { [string]: string? }): string?
	if slots.legs ~= nil and not profile.slotsUnlocked.legs then
		return "legs_slot_locked"
	end
	if slots.tail ~= nil and not profile.slotsUnlocked.tail then
		return "tail_slot_locked"
	end
	return nil
end

-- Pays real-word discovery bonuses for combos this profile has never built.
local function realWordPayout(self: any, userId: number, profile: Profile, beast: Beast): { any }
	local discovered = {}
	for _, word in RealWords.matches(beast) do
		local coin = Ledger.faucet(profile, "real_word", { comboWord = word.word }, self._now())
		if coin.delta > 0 then
			table.insert(discovered, {
				word = word.word,
				pinyin = word.pinyin,
				english = word.english,
				coinMath = coin.mathString,
			})
			self._analytics:track(userId, "faucet", "real_word", coin.delta, { word = word.word })
		end
	end
	return discovered
end

local function beastPayload(beast: Beast): any
	return {
		id = beast.id,
		name = beast.name,
		slots = beast.slots,
		feed = beast.feed,
		golden = beast.golden,
		colorway = beast.colorway,
		stats = SlotStats.resolve(beast, ANIMAL_INDEX),
	}
end

ZooService.beastPayload = beastPayload

function ZooService.fuse(self: any, userId: number, payload: any): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	-- head/body are the entry fusion; legs is a starting slot (unlocked in
	-- onboarding), tail stays gated behind the ladder and is added via refuse.
	local slots = { head = payload.head, body = payload.body, legs = payload.legs }
	local invalid = occupantsValid(profile, slots)
	if invalid then
		return fail(invalid)
	end
	local gated = slotGateError(profile, slots)
	if gated then
		return fail(gated)
	end
	local count = 0
	for _ in profile.beasts do
		count += 1
	end
	if count >= MAX_BEASTS then
		return fail("zoo_full")
	end
	local paid = Ledger.sink(profile, "fuse", Config.Economy.FUSE_COST)
	if not paid.ok then
		return fail(paid.err :: string)
	end

	local beast: Beast = {
		id = `b{profile.nextBeastId}`,
		name = nil,
		slots = {
			head = slots.head :: string,
			body = slots.body :: string,
			legs = slots.legs,
			tail = nil,
		},
		feed = { head = 0, body = 0, legs = 0, tail = 0 },
		golden = false,
		colorway = nil,
		createdAt = self._now(),
	}
	profile.nextBeastId += 1
	beast.golden = RealWords.isGolden(beast)
	profile.beasts[beast.id] = beast
	if not profile.activeBeastId then
		profile.activeBeastId = beast.id
	end
	local discovered = realWordPayout(self, userId, profile, beast)
	self._analytics:track(userId, "sink", "fuse", paid.delta, { beast = beast.id })
	self._onBeastChanged(userId, profile)
	return {
		ok = true,
		beast = beastPayload(beast),
		coinMath = paid.mathString,
		newCoins = profile.coins,
		realWords = discovered,
	}
end

function ZooService.refuse(self: any, userId: number, payload: any): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local beast = profile.beasts[payload.beastId]
	if not beast then
		return fail("no_such_beast")
	end
	local slots =
		{ head = payload.head, body = payload.body, legs = payload.legs, tail = payload.tail }
	local invalid = occupantsValid(profile, slots)
	if invalid then
		return fail(invalid)
	end
	local gate = slotGateError(profile, slots)
	if gate then
		return fail(gate)
	end
	local paid = Ledger.sink(profile, "refuse", Config.Economy.REFUSE_COST)
	if not paid.ok then
		return fail(paid.err :: string)
	end

	-- Feed levels belong to the beast's SLOTS: they survive the swap untouched.
	beast.slots = {
		head = slots.head :: string,
		body = slots.body :: string,
		legs = slots.legs,
		tail = slots.tail,
	}
	beast.golden = RealWords.isGolden(beast)
	local discovered = realWordPayout(self, userId, profile, beast)
	self._analytics:track(userId, "sink", "refuse", paid.delta, { beast = beast.id })
	self._onBeastChanged(userId, profile)
	return {
		ok = true,
		beast = beastPayload(beast),
		coinMath = paid.mathString,
		newCoins = profile.coins,
		realWords = discovered,
	}
end

function ZooService.feedSlot(self: any, userId: number, payload: any): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local beast = profile.beasts[payload.beastId]
	if not beast then
		return fail("no_such_beast")
	end
	local slot = payload.slot
	if slot ~= "head" and slot ~= "body" and slot ~= "legs" and slot ~= "tail" then
		return fail("bad_slot")
	end
	if
		(slot == "legs" and beast.slots.legs == nil) or (slot == "tail" and beast.slots.tail == nil)
	then
		return fail("slot_empty")
	end
	local feed = beast.feed :: any
	local cost = FeedCurve.costToNext(feed[slot])
	if not cost then
		return fail("slot_maxed")
	end
	local paid = Ledger.sink(profile, "feed", cost :: number)
	if not paid.ok then
		return fail(paid.err :: string)
	end
	feed[slot] += 1
	self._analytics:track(userId, "sink", "feed", paid.delta, { beast = beast.id, slot = slot })
	self._onBeastChanged(userId, profile)
	return {
		ok = true,
		beast = beastPayload(beast),
		newFeedLevel = feed[slot],
		nextCost = FeedCurve.costToNext(feed[slot]),
		coinMath = paid.mathString,
		newCoins = profile.coins,
	}
end

function ZooService.unlockSlot(self: any, userId: number, slot: string): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local unlock = (Config.Economy.SLOT_UNLOCKS :: any)[slot]
	if not unlock then
		return fail("bad_slot")
	end
	local unlocked = profile.slotsUnlocked :: any
	if unlocked[slot] then
		return fail("already_unlocked")
	end
	if profile.ladderRung < unlock.rung then
		return fail("rung_too_low") -- 先打败第 {rung} 关!
	end
	local paid = Ledger.sink(profile, "slot_unlock", unlock.cost)
	if not paid.ok then
		return fail(paid.err :: string)
	end
	unlocked[slot] = true
	self._analytics:track(userId, "sink", "slot_unlock", paid.delta, { slot = slot })
	return { ok = true, slot = slot, coinMath = paid.mathString, newCoins = profile.coins }
end

function ZooService.nameBeast(self: any, userId: number, payload: any): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local beast = profile.beasts[payload.beastId]
	if not beast then
		return fail("no_such_beast")
	end
	local chars = payload.chars
	if type(chars) ~= "table" or #chars ~= 2 then
		return fail("bad_request")
	end
	-- The no-free-text guarantee: both characters must be MASTERED quiz items.
	for _, char in chars :: { string } do
		if type(char) ~= "string" or not Mastery.isMastered(profile, char) then
			return fail("character_not_mastered")
		end
	end
	local paid = Ledger.sink(profile, "name_beast", Config.Economy.NAME_COST)
	if not paid.ok then
		return fail(paid.err :: string)
	end
	beast.name = chars[1] .. chars[2]
	self._analytics:track(
		userId,
		"sink",
		"name_beast",
		paid.delta,
		{ beast = beast.id, name = beast.name }
	)
	self._onBeastChanged(userId, profile)
	return { ok = true, name = beast.name, coinMath = paid.mathString, newCoins = profile.coins }
end

function ZooService.setActiveBeast(self: any, userId: number, beastId: string): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	if not profile.beasts[beastId] then
		return fail("no_such_beast")
	end
	profile.activeBeastId = beastId
	self._onBeastChanged(userId, profile)
	return { ok = true }
end

function ZooService.buyDecoration(self: any, userId: number, itemId: string): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local item = DECOR_INDEX[itemId]
	if not item then
		return fail("no_such_item")
	end
	local paid = Ledger.sink(profile, "decoration", item.cost)
	if not paid.ok then
		return fail(paid.err :: string)
	end
	profile.decorations[itemId] = (profile.decorations[itemId] or 0) + 1
	self._analytics:track(userId, "sink", "decoration", paid.delta, { item = itemId })
	return {
		ok = true,
		coinMath = paid.mathString,
		newCoins = profile.coins,
		owned = profile.decorations[itemId],
	}
end

function ZooService.placeDecoration(self: any, userId: number, payload: any): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local itemId = payload.itemId
	if not DECOR_INDEX[itemId] then
		return fail("no_such_item")
	end
	local gridIndex = payload.gridIndex
	if
		type(gridIndex) ~= "number"
		or gridIndex ~= math.floor(gridIndex)
		or gridIndex < 1
		or gridIndex > 12
	then
		return fail("bad_request")
	end
	-- placements never exceed owned count
	local placed = 0
	for _, placedId in profile.plotPlacements do
		if placedId == itemId then
			placed += 1
		end
	end
	local slotKey = tostring(gridIndex)
	if profile.plotPlacements[slotKey] == itemId then
		return fail("already_there")
	end
	if placed >= (profile.decorations[itemId] or 0) then
		return fail("not_owned")
	end
	profile.plotPlacements[slotKey] = itemId
	self._onBeastChanged(userId, profile) -- decorations render on the plot immediately
	return { ok = true, gridIndex = gridIndex, itemId = itemId }
end

function ZooService.buyColorway(self: any, userId: number, payload: any): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local colorway = COLORWAY_INDEX[payload.colorwayId]
	if not colorway then
		return fail("no_such_item")
	end
	local beast = profile.beasts[payload.beastId]
	if not beast then
		return fail("no_such_beast")
	end
	if not profile.colorways[payload.colorwayId] then
		local paid = Ledger.sink(profile, "colorway", colorway.cost)
		if not paid.ok then
			return fail(paid.err :: string)
		end
		profile.colorways[payload.colorwayId] = true
		self._analytics:track(
			userId,
			"sink",
			"colorway",
			paid.delta,
			{ colorway = payload.colorwayId }
		)
	end
	beast.colorway = payload.colorwayId
	self._onBeastChanged(userId, profile)
	return { ok = true, newCoins = profile.coins }
end

-- Full zoo snapshot for the client.
function ZooService.snapshot(self: any, userId: number): any
	local profile = getProfile(self, userId)
	if not profile then
		return fail("no_profile")
	end
	local beasts = {}
	for _, beast in profile.beasts do
		table.insert(beasts, beastPayload(beast))
	end
	local masteredChars = {}
	for text, state in profile.chars do
		if state.mastered then
			table.insert(masteredChars, text)
		end
	end
	table.sort(masteredChars)
	return {
		ok = true,
		coins = profile.coins,
		masteredChars = masteredChars,
		animals = profile.animals,
		beasts = beasts,
		activeBeastId = profile.activeBeastId,
		slotsUnlocked = profile.slotsUnlocked,
		ladderRung = profile.ladderRung,
		decorations = profile.decorations,
		plotPlacements = profile.plotPlacements,
		colorways = profile.colorways,
	}
end

return ZooService
