--!strict
-- Boot: profiles first, then world and services (arriving in later milestones),
-- then the remote surface. Players who joined before boot finished are swept.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Profiles = require("./Services/Profiles")
local ProfileBackend = require("./Services/ProfileBackend")
local ProfileSchema = require("../shared/ProfileSchema")

-- Studio without API access still plays (loleris mock, no persistence).
local useMock = RunService:IsStudio()
	and not pcall(function()
		local DataStoreService = game:GetService("DataStoreService")
		DataStoreService:GetDataStore("__probe"):GetAsync("__probe")
	end)
if useMock then
	warn("[FusionZoo] DataStore unavailable — running on the mock store (no persistence)")
end

local profiles = Profiles.new(ProfileBackend.new(useMock))

local readyEvent -- Profile/Ready RE, wired in M2 alongside the quiz surface

local function onJoin(player: Player)
	local seed = player.UserId % 1000000007 -- deterministic per player, stable across sessions
	local profile = profiles:load(player.UserId, seed, os.time())
	if not profile then
		player:Kick(
			"你的存档还在另一台服务器上，请稍后再进入。 (Save is loading elsewhere — try again in a moment.)"
		)
		return
	end
	profiles:onRelease(player.UserId, function()
		if player.Parent then
			player:Kick("存档已保存，请重新进入。 (Save released — please rejoin.)")
		end
	end)
end

for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end
Players.PlayerAdded:Connect(onJoin)

Players.PlayerRemoving:Connect(function(player)
	profiles:release(player.UserId)
end)

-- Later milestones attach services here; keep the boot surface in one place.
local Boot = {
	profiles = profiles,
	schema = ProfileSchema,
	readyEvent = readyEvent,
}
_G.FusionZooBoot = Boot -- single, deliberate global: services published for cross-module wiring

print("[FusionZoo] server booted (M1: profiles + data pipeline)")
