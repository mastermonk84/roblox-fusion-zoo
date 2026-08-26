--!strict
-- UTC day math. Pure: every function takes an explicit unix time so tests and
-- the mastery two-day rule are deterministic. Rollover is 00:00 UTC.

local Time = {}

local SECONDS_PER_DAY = 86400
local DAYS_PER_400Y = 146097
local DAYS_PER_100Y = 36524

-- Civil-from-days (Howard Hinnant's algorithm) so we avoid os.date, which
-- Roblox restricts in some contexts and which reads ambient state.
local function civilFromDays(z: number): (number, number, number)
	z += 719468
	local era = math.floor(z / DAYS_PER_400Y)
	local doe = z - era * DAYS_PER_400Y
	local yoe = math.floor(
		(
			doe
			- math.floor(doe / 1460)
			+ math.floor(doe / DAYS_PER_100Y)
			- math.floor(doe / (DAYS_PER_400Y - 1))
		) / 365
	)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	if m <= 2 then
		y += 1
	end
	return y, m, d
end

-- "2026-08-26" for any unix timestamp, UTC.
function Time.dayKey(unix: number): string
	local days = math.floor(unix / SECONDS_PER_DAY)
	local y, m, d = civilFromDays(days)
	return string.format("%04d-%02d-%02d", y, m, d)
end

function Time.sameDay(a: number, b: number): boolean
	return math.floor(a / SECONDS_PER_DAY) == math.floor(b / SECONDS_PER_DAY)
end

return Time
