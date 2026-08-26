--!strict
-- The whole remote surface. Handlers register through Net.handle, which wraps
-- them in the standard shell: schema guard -> token-bucket rate limit ->
-- handler. No remote is created anywhere else; the client finds everything
-- under ReplicatedStorage/Remotes/<Group>/<Name>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Guard = require("../shared/Util/Guard")

local Net = {}

local root: Folder? = nil

type Bucket = { tokens: number, last: number }
local buckets: { [string]: Bucket } = {}

local RATE = 5 -- requests/second refill
local BURST = 10

local function allow(player: Player, remoteName: string): boolean
	local key = `{player.UserId}:{remoteName}`
	local now = os.clock()
	local bucket = buckets[key]
	if not bucket then
		bucket = { tokens = BURST, last = now }
		buckets[key] = bucket
	end
	bucket.tokens = math.min(BURST, bucket.tokens + (now - bucket.last) * RATE)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function folder(): Folder
	if root then
		return root
	end
	local created = Instance.new("Folder")
	created.Name = "Remotes"
	created.Parent = ReplicatedStorage
	root = created
	return created
end

local function group(name: string): Folder
	local parent = folder()
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing :: Folder
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

-- RemoteFunction with the standard shell. Handlers return a table; guard
-- failures and rate-limit hits return { ok = false, err = ... } uniformly so
-- the client has one error path and probes learn nothing.
function Net.handle(
	groupName: string,
	name: string,
	guard: Guard.Check?,
	handler: (Player, any) -> any
)
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = group(groupName)
	remote.OnServerInvoke = function(player: Player, payload: any)
		if not allow(player, `{groupName}/{name}`) then
			return { ok = false, err = "slow_down" }
		end
		if guard and not guard(payload) then
			return { ok = false, err = "bad_request" }
		end
		return handler(player, payload)
	end
end

-- Server-push RemoteEvent.
function Net.event(groupName: string, name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = group(groupName)
	return remote
end

-- Client-fired RemoteEvent with the same shell (cheers only).
function Net.listen(
	groupName: string,
	name: string,
	guard: Guard.Check?,
	handler: (Player, any) -> ()
): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = group(groupName)
	remote.OnServerEvent:Connect(function(player: Player, payload: any)
		if not allow(player, `{groupName}/{name}`) then
			return
		end
		if guard and not guard(payload) then
			return
		end
		handler(player, payload)
	end)
	return remote
end

return Net
