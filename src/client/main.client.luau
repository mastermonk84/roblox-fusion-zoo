--!strict
-- Client boot. Controllers arrive with the Mission Kiosk in M2; for now this
-- proves the shared data modules replicate and load.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local curriculum = require(Shared:WaitForChild("Data"):WaitForChild("Curriculum")) :: { any }

print(`[FusionZoo] client booted — {#curriculum} quiz items loaded`)
