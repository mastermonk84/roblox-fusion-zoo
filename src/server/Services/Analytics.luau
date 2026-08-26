--!strict
-- Faucet/sink/quiz/battle event stream. M2 ships the buffer + session totals;
-- the DataStore flush lands in M6. Engine-free so service specs run headless.

local Analytics = {}
Analytics.__index = Analytics

export type Event = {
	t: number,
	userId: number,
	type: string,
	code: string,
	amount: number,
	meta: { [string]: any }?,
}

function Analytics.new(now: (() -> number)?)
	return setmetatable({
		_now = now or os.time,
		_buffer = {} :: { Event },
		_totals = {} :: { [number]: { [string]: number } }, -- userId -> code -> sum
	}, Analytics)
end

function Analytics.track(
	self: any,
	userId: number,
	eventType: string,
	code: string,
	amount: number,
	meta: { [string]: any }?
)
	table.insert(self._buffer, {
		t = self._now(),
		userId = userId,
		type = eventType,
		code = code,
		amount = amount,
		meta = meta,
	})
	local userTotals = self._totals[userId]
	if not userTotals then
		userTotals = {}
		self._totals[userId] = userTotals
	end
	local key = `{eventType}:{code}`
	userTotals[key] = (userTotals[key] or 0) + amount
end

function Analytics.sessionTotals(self: any, userId: number): { [string]: number }
	return self._totals[userId] or {}
end

function Analytics.drain(self: any): { Event }
	local out = self._buffer
	self._buffer = {}
	return out
end

return Analytics
