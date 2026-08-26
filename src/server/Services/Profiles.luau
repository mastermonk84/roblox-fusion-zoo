--!strict
-- Session-locked player profiles. The persistence backend is injected:
--   prod: Backends.profileService() wrapping the vendored loleris ProfileService
--         (session locking, autosave, BindToClose — all battle-tested there)
--   tests: an in-memory mock implementing the same three functions
-- Schema logic (template/migrate/reconcile/daily) lives in shared/ProfileSchema
-- so it stays pure and headless-tested.

local ProfileSchema = require("../../shared/ProfileSchema")
local Types = require("../../shared/Types")

type Profile = Types.Profile

export type LoadedProfile = {
	Data: any,
	Release: (self: LoadedProfile) -> (),
	ListenToRelease: (self: LoadedProfile, fn: () -> ()) -> (),
	IsActive: (self: LoadedProfile) -> boolean,
}

export type Backend = {
	-- Returns nil when the profile could not be session-locked (another live
	-- server holds it and refuses to let go).
	load: (key: string) -> LoadedProfile?,
}

export type Profiles = {
	load: (self: Profiles, userId: number, seed: number, now: number) -> Profile?,
	get: (self: Profiles, userId: number) -> Profile?,
	release: (self: Profiles, userId: number) -> (),
	onRelease: (self: Profiles, userId: number, fn: () -> ()) -> (),
	activeCount: (self: Profiles) -> number,
}

local Profiles = {}
Profiles.__index = Profiles

function Profiles.new(backend: Backend): Profiles
	local self = setmetatable({
		_backend = backend,
		_loaded = {} :: { [number]: LoadedProfile },
	}, Profiles)
	return (self :: any) :: Profiles
end

function Profiles.load(self: any, userId: number, seed: number, now: number): Profile?
	local stale = self._loaded[userId]
	if stale then
		-- rejoin raced ahead of the previous session's release: let the old
		-- lock go first, then load fresh
		stale:Release()
		self._loaded[userId] = nil
	end
	local loaded = self._backend.load(`player_{userId}`)
	if not loaded then
		return nil
	end
	local profile = loaded :: LoadedProfile
	-- Order matters: migrate first (schema shape), then reconcile (fill new
	-- defaults), then daily rollover.
	ProfileSchema.migrate(profile.Data)
	ProfileSchema.reconcile(profile.Data, seed, now)
	ProfileSchema.rollDaily(profile.Data, now)
	self._loaded[userId] = profile
	profile:ListenToRelease(function()
		self._loaded[userId] = nil
	end)
	return profile.Data :: Profile
end

function Profiles.get(self: any, userId: number): Profile?
	local loaded = self._loaded[userId]
	if loaded and loaded:IsActive() then
		return loaded.Data :: Profile
	end
	return nil
end

function Profiles.release(self: any, userId: number)
	local loaded = self._loaded[userId]
	if loaded then
		loaded:Release()
		self._loaded[userId] = nil
	end
end

function Profiles.onRelease(self: any, userId: number, fn: () -> ())
	local loaded = self._loaded[userId]
	if loaded then
		loaded:ListenToRelease(fn)
	end
end

function Profiles.activeCount(self: any): number
	local n = 0
	for _ in self._loaded do
		n += 1
	end
	return n
end

return Profiles
