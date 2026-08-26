--!strict
-- One RemoteFunction for player actions, one RemoteEvent for state pushes.
-- The server owns every number; the client only ever renders what it is sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "FusionZooRemotes"

local module = {}

function module.server(): (RemoteFunction, RemoteEvent)
	assert(RunService:IsServer(), "Remotes.server() is server-only")

	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	local action = folder:FindFirstChild("Action") :: RemoteFunction?
	if not action then
		action = Instance.new("RemoteFunction")
		action.Name = "Action"
		action.Parent = folder
	end

	local state = folder:FindFirstChild("State") :: RemoteEvent?
	if not state then
		state = Instance.new("RemoteEvent")
		state.Name = "State"
		state.Parent = folder
	end

	return action :: RemoteFunction, state :: RemoteEvent
end

function module.client(): (RemoteFunction, RemoteEvent)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild("Action") :: RemoteFunction, folder:WaitForChild("State") :: RemoteEvent
end

return module
