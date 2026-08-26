--!strict
-- Boot: world, profiles, services, then the remote surface. Handlers stay
-- one-liners into services; every decision lives behind them in pure modules.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Net = require("./Net")
local Analytics = require("./Services/Analytics")
local ProfileBackend = require("./Services/ProfileBackend")
local Profiles = require("./Services/Profiles")
local QuizService = require("./Services/QuizService")
local WorldService = require("./Services/WorldService")
local Guard = require("../shared/Util/Guard")
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

-- ── remote surface ──────────────────────────────────────────────────────────
local readyEvent = Net.event("Profile", "Ready")

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

-- ── player lifecycle ────────────────────────────────────────────────────────
local TUTORIAL_ANIMALS = { "猫", "鸟" } -- user-approved onboarding exemption

local function pushReady(player: Player, profile: Profile)
	readyEvent:FireClient(player, {
		coins = profile.coins,
		level = profile.level,
		cleanStreak = profile.cleanStreak,
		pinyinMode = profile.pinyinMode,
		animals = profile.animals,
		beasts = profile.beasts,
		slotsUnlocked = profile.slotsUnlocked,
		ladderRung = profile.ladderRung,
	})
end

local function onJoin(player: Player)
	local seed = player.UserId % 1000000007 -- deterministic, stable across sessions
	local profile = profiles:load(player.UserId, seed, os.time())
	if not profile then
		player:Kick(
			"你的存档还在另一台服务器上，请稍后再进入。 (Save is loading elsewhere — try again shortly.)"
		)
		return
	end
	if not profile.tutorial.grantsGiven then
		-- Scripted onboarding: the first two animals arrive as tutorial gifts,
		-- exempt from the MASTERED gate, so rescue→fuse→battle fits session one.
		for _, char in TUTORIAL_ANIMALS do
			profile.animals[char] = true
		end
		profile.tutorial.grantsGiven = true
	end
	profiles:onRelease(player.UserId, function()
		quiz:dropPlayer(player.UserId)
		if player.Parent then
			player:Kick("存档已保存，请重新进入。 (Save released — please rejoin.)")
		end
	end)
	pushReady(player, profile)
end

for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end
Players.PlayerAdded:Connect(onJoin)

Players.PlayerRemoving:Connect(function(player)
	profiles:release(player.UserId)
end)

if RunService:IsStudio() then
	print(
		"[FusionZoo] Studio session — remember Game Settings → Security → API Services for saves"
	)
end
print("[FusionZoo] server booted (M2: quiz engine + kiosk + progress board)")
