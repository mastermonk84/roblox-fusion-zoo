--!strict
-- Boot: world, profiles, services, then the remote surface. Handlers stay
-- one-liners into services; every decision lives behind them in pure modules.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Net = require("./Net")
local Analytics = require("./Services/Analytics")
local AnalyticsFlush = require("./Services/AnalyticsFlush")
local BattleService = require("./Services/BattleService")
local Animals = require("../shared/Data/Animals")
local Cheers = require("../shared/Data/Cheers")
local GhostService = require("./Services/GhostService")
local GhostStores = require("./Services/GhostStores")
local ProfileBackend = require("./Services/ProfileBackend")
local Profiles = require("./Services/Profiles")
local PlotService = require("./Services/PlotService")
local QuizService = require("./Services/QuizService")
local WorldService = require("./Services/WorldService")
local ZooService = require("./Services/ZooService")
local Guard = require("../shared/Util/Guard")
local Rng = require("../shared/Util/Rng")
local Types = require("../shared/Types")

type Profile = Types.Profile

-- ── world ───────────────────────────────────────────────────────────────────
WorldService.build()

-- ── services ────────────────────────────────────────────────────────────────
-- Studio without API access still plays (loleris mock, no persistence).
local canPersist = pcall(function()
	local DataStoreService = game:GetService("DataStoreService")
	DataStoreService:GetDataStore("__probe"):GetAsync("__probe")
end)
if not canPersist then
	warn("[FusionZoo] DataStore unavailable — running on the mock store (no persistence)")
end

local profiles = Profiles.new(ProfileBackend.new(not canPersist))
local analytics = Analytics.new()
local quiz = QuizService.new({ profiles = profiles, analytics = analytics })
local plots = PlotService.new()

-- live-battle server pushes ride one RemoteEvent per player
local battleEvents = Net.event("Battle", "Events")
local PAD_RANGE = 15

local function nearPad(userIdA: number, userIdB: number): boolean
	local pad = workspace:FindFirstChild("FusionZooWorld")
		and workspace.FusionZooWorld:FindFirstChild("BattleArena") :: Model?
	local padPart = pad and pad:FindFirstChild("ChallengePad") :: BasePart?
	if not padPart then
		return false
	end
	for _, userId in { userIdA, userIdB } do
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local root = character and character.PrimaryPart
		if not root or (root.Position - padPart.Position).Magnitude > PAD_RANGE then
			return false
		end
	end
	return true
end

local battle = BattleService.new({
	profiles = profiles,
	quiz = quiz,
	analytics = analytics,
	push = function(userId, event, payload)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			battleEvents:FireClient(player, event, payload)
		end
	end,
	nearPad = nearPad,
	displayName = function(userId)
		local player = Players:GetPlayerByUserId(userId)
		return if player then player.DisplayName else `Player{userId}`
	end,
})
local ghosts = GhostService.new({ profiles = profiles, stores = GhostStores.new() })
AnalyticsFlush.start(analytics)
local zoo = ZooService.new({
	profiles = profiles,
	analytics = analytics,
	onBeastChanged = function(userId, profile)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			plots:refresh(userId, profile, player.DisplayName)
			-- the active beast auto-publishes to the ghost pool on change (spec)
			task.spawn(function()
				ghosts:publish(userId, player.DisplayName)
			end)
		end
	end,
})

-- ── remote surface ──────────────────────────────────────────────────────────
local readyEvent = Net.event("Profile", "Ready")

local function stateFor(profile: Profile): any
	return {
		coins = profile.coins,
		level = profile.level,
		cleanStreak = profile.cleanStreak,
		pinyinMode = profile.pinyinMode,
		animals = profile.animals,
		beasts = profile.beasts,
		slotsUnlocked = profile.slotsUnlocked,
		ladderRung = profile.ladderRung,
	}
end

-- The Ready push races the client's boot on real joins (RemoteEvents are not
-- queued for scripts that haven't connected); the client pulls this once.
Net.handle("Profile", "GetState", nil, function(player)
	local profile = profiles:get(player.UserId)
	if not profile then
		return { ok = false, err = "no_profile" }
	end
	local state = stateFor(profile)
	state.ok = true
	return state
end)

Net.handle("Quiz", "RequestQuestion", nil, function(player)
	return quiz:requestQuestion(player.UserId)
end)

Net.handle(
	"Quiz",
	"SubmitAnswer",
	Guard.shape({ questionId = Guard.stringOf(24), choiceIndex = Guard.integer(1, 3) }),
	function(player, payload)
		return quiz:submitAnswer(player.UserId, payload)
	end
)

Net.handle(
	"Quiz",
	"SetPinyinMode",
	Guard.shape({ enabled = Guard.isBoolean }),
	function(player, payload)
		return quiz:setPinyinMode(player.UserId, payload.enabled)
	end
)

Net.handle("Progress", "GetSummary", nil, function(player)
	return quiz:progressSummary(player.UserId)
end)

-- zoo surface
Net.handle("Zoo", "GetRescueList", nil, function(player)
	return zoo:rescueList(player.UserId)
end)
Net.handle("Zoo", "Rescue", Guard.shape({ char = Guard.stringOf(8) }), function(player, payload)
	return zoo:rescue(player.UserId, payload.char)
end)
Net.handle(
	"Zoo",
	"Fuse",
	Guard.shape({
		head = Guard.stringOf(8),
		body = Guard.stringOf(8),
		legs = Guard.optional(Guard.stringOf(8)),
	}),
	function(player, payload)
		return zoo:fuse(player.UserId, payload)
	end
)
Net.handle(
	"Zoo",
	"Refuse",
	Guard.shape({
		beastId = Guard.stringOf(12),
		head = Guard.stringOf(8),
		body = Guard.stringOf(8),
		legs = Guard.optional(Guard.stringOf(8)),
		tail = Guard.optional(Guard.stringOf(8)),
	}),
	function(player, payload)
		return zoo:refuse(player.UserId, payload)
	end
)
Net.handle(
	"Zoo",
	"FeedSlot",
	Guard.shape({
		beastId = Guard.stringOf(12),
		slot = Guard.oneOf({ "head", "body", "legs", "tail" }),
	}),
	function(player, payload)
		return zoo:feedSlot(player.UserId, payload)
	end
)
Net.handle(
	"Zoo",
	"UnlockSlot",
	Guard.shape({ slot = Guard.oneOf({ "legs", "tail" }) }),
	function(player, payload)
		return zoo:unlockSlot(player.UserId, payload.slot)
	end
)
Net.handle("Zoo", "NameBeast", nil, function(player, payload)
	if type(payload) ~= "table" or type(payload.beastId) ~= "string" then
		return { ok = false, err = "bad_request" }
	end
	return zoo:nameBeast(player.UserId, payload)
end)
Net.handle(
	"Zoo",
	"SetActiveBeast",
	Guard.shape({ beastId = Guard.stringOf(12) }),
	function(player, payload)
		return zoo:setActiveBeast(player.UserId, payload.beastId)
	end
)
Net.handle(
	"Zoo",
	"BuyDecoration",
	Guard.shape({ itemId = Guard.stringOf(24) }),
	function(player, payload)
		return zoo:buyDecoration(player.UserId, payload.itemId)
	end
)
Net.handle(
	"Zoo",
	"PlaceDecoration",
	Guard.shape({ itemId = Guard.stringOf(24), gridIndex = Guard.integer(1, 12) }),
	function(player, payload)
		return zoo:placeDecoration(player.UserId, payload)
	end
)
Net.handle(
	"Zoo",
	"BuyColorway",
	Guard.shape({ beastId = Guard.stringOf(12), colorwayId = Guard.stringOf(24) }),
	function(player, payload)
		return zoo:buyColorway(player.UserId, payload)
	end
)
Net.handle("Zoo", "GetSnapshot", nil, function(player)
	return zoo:snapshot(player.UserId)
end)

-- battle surface
Net.handle("Battle", "GetLadder", nil, function(player)
	return battle:ladder(player.UserId)
end)
Net.handle(
	"Battle",
	"StartNpc",
	Guard.shape({ rung = Guard.integer(1, 12) }),
	function(player, payload)
		return battle:startNpc(player.UserId, payload.rung)
	end
)
Net.handle(
	"Battle",
	"PickStat",
	Guard.shape({
		battleId = Guard.stringOf(16),
		round = Guard.integer(1, 99),
		stat = Guard.oneOf({ "li", "su", "zhi" }),
	}),
	function(player, payload)
		return battle:pickStat(player.UserId, payload)
	end
)
Net.handle(
	"Battle",
	"SubmitFlash",
	Guard.shape({
		battleId = Guard.stringOf(16),
		questionId = Guard.stringOf(24),
		choiceIndex = Guard.integer(1, 3),
	}),
	function(player, payload)
		return battle:submitFlash(player.UserId, payload)
	end
)
Net.handle(
	"Battle",
	"ResolveRound",
	Guard.shape({ battleId = Guard.stringOf(16) }),
	function(player, payload)
		return battle:resolveRound(player.UserId, payload)
	end
)
Net.handle("Battle", "StartGhost", nil, function(player)
	local snapshot = ghosts:fetch(player.UserId)
	if not snapshot then
		return { ok = false, err = "no_ghosts" }
	end
	return battle:startGhost(player.UserId, snapshot)
end)
Net.handle(
	"Battle",
	"Challenge",
	Guard.shape({ targetUserId = Guard.integer(0, 2 ^ 52) }),
	function(player, payload)
		return battle:challenge(player.UserId, payload.targetUserId)
	end
)
Net.handle(
	"Battle",
	"RespondChallenge",
	Guard.shape({ accept = Guard.isBoolean }),
	function(player, payload)
		return battle:respondChallenge(player.UserId, payload.accept)
	end
)
Net.handle("Battle", "Forfeit", nil, function(player)
	return battle:forfeit(player.UserId)
end)
Net.handle("Battle", "ListOpponents", nil, function(player)
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(list, { userId = other.UserId, name = other.DisplayName })
		end
	end
	return { ok = true, players = list }
end)

-- cheer wheel: fixed catalog only, rebroadcast to everyone (small servers)
local cheerCatalog: { [string]: boolean } = {}
for _, cheer in Cheers :: { any } do
	cheerCatalog[cheer.id] = true
end
local cheerEvent: RemoteEvent
cheerEvent = Net.listen(
	"Battle",
	"Cheer",
	Guard.shape({ cheerId = Guard.stringOf(24) }),
	function(player, payload)
		if not cheerCatalog[payload.cheerId] then
			return
		end
		cheerEvent:FireAllClients({ fromName = player.DisplayName, cheerId = payload.cheerId })
	end
)

-- ── player lifecycle ────────────────────────────────────────────────────────
local ANIMAL_CHARS: { string } = {}
for _, animal in Animals :: { any } do
	table.insert(ANIMAL_CHARS, animal.char)
end

-- Three distinct starter animals — random, but derived from the player's stable
-- seed so a given player always gets the same onboarding trio. Granted once and
-- exempt from the MASTERED gate; three animals + the legs slot let session one
-- flow rescue→fuse (head/body/legs)→battle.
local function starterAnimals(seed: number): { string }
	local pool = Rng.seededShuffle(ANIMAL_CHARS, Rng.mulberry32(seed % 4294967296))
	return { pool[1], pool[2], pool[3] }
end

local function pushReady(player: Player, profile: Profile)
	readyEvent:FireClient(player, stateFor(profile))
end

local function onJoin(player: Player)
	local seed = player.UserId % 1000000007 -- deterministic, stable across sessions
	local profile = profiles:load(player.UserId, seed, os.time())
	if not player.Parent then
		-- the player left while the profile was loading: release the lock now
		profiles:release(player.UserId)
		return
	end
	if not profile then
		player:Kick(
			"你的存档还在另一台服务器上，请稍后再进入。 (Save is loading elsewhere — try again shortly.)"
		)
		return
	end
	if not profile.tutorial.grantsGiven then
		-- Scripted onboarding: three random starter animals arrive as tutorial
		-- gifts, exempt from the MASTERED gate, and the legs slot opens so the
		-- first fusion is a full 3-part beast (head/body/legs = 智/力/速).
		for _, char in starterAnimals(seed) do
			profile.animals[char] = true
		end
		profile.slotsUnlocked.legs = true
		profile.tutorial.grantsGiven = true
	end
	profiles:onRelease(player.UserId, function()
		quiz:dropPlayer(player.UserId)
		battle:dropPlayer(player.UserId)
		plots:release(player.UserId)
		if player.Parent then
			player:Kick("存档已保存，请重新进入。 (Save released — please rejoin.)")
		end
	end)
	plots:claim(player.UserId, player.DisplayName)
	plots:refresh(player.UserId, profile, player.DisplayName)
	task.spawn(function()
		ghosts:publish(player.UserId, player.DisplayName)
	end)
	pushReady(player, profile)
end

for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end
Players.PlayerAdded:Connect(onJoin)

Players.PlayerRemoving:Connect(function(player)
	-- capture the final ghost snapshot synchronously, write it async, and
	-- release the profile without waiting on DataStore latency
	local profile = profiles:get(player.UserId)
	if profile then
		local snapshot =
			GhostService.snapshotOf(profile, player.UserId, player.DisplayName, os.time())
		if snapshot then
			task.spawn(function()
				ghosts:publishSnapshot(player.UserId, snapshot)
			end)
		end
	end
	battle:dropPlayer(player.UserId)
	plots:release(player.UserId)
	profiles:release(player.UserId)
end)

if RunService:IsStudio() then
	print(
		"[FusionZoo] Studio session — remember Game Settings → Security → API Services for saves"
	)
end
print("[FusionZoo] server booted — v1 complete")
