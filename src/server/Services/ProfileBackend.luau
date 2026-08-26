--!strict
-- Production persistence backend: wraps the vendored loleris ProfileService
-- (session locking, autosave, ForceLoad lock stealing, BindToClose). The
-- loleris profile object already matches the Profiles.LoadedProfile surface
-- (.Data, :Release, :ListenToRelease, :IsActive), so this is a thin adapter.

local Config = require("../../shared/Config")

local ProfileBackend = {}

function ProfileBackend.new(useMock: boolean)
	local ProfileService = require("../Vendor/ProfileService") :: any
	local store = ProfileService.GetProfileStore(Config.Profile.DATASTORE_NAME, {})
	if useMock then
		-- Studio without API access: loleris' built-in mock keeps play sessions
		-- working with no persistence.
		store = store.Mock
	end
	return {
		load = function(key: string)
			-- ForceLoad: waits politely for the previous session, steals a dead
			-- one — exactly the crash-recovery semantics the criterion asks for.
			return store:LoadProfileAsync(key, "ForceLoad")
		end,
	}
end

return ProfileBackend
