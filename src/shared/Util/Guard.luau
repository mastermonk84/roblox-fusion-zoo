--!strict
-- Payload validation for every remote. Combinator style so handler guards read
-- as schemas. All checks are cheap and never throw.

local Guard = {}

export type Check = (value: any) -> boolean

function Guard.isString(v: any): boolean
	return type(v) == "string"
end

function Guard.isBoolean(v: any): boolean
	return type(v) == "boolean"
end

function Guard.stringOf(maxLen: number): Check
	return function(v: any): boolean
		return type(v) == "string" and #v <= maxLen and #v > 0
	end
end

function Guard.integer(min: number, max: number): Check
	return function(v: any): boolean
		return type(v) == "number" and v == math.floor(v) and v >= min and v <= max
	end
end

function Guard.oneOf(allowed: { string }): Check
	return function(v: any): boolean
		if type(v) ~= "string" then
			return false
		end
		return table.find(allowed, v) ~= nil
	end
end

-- Exact-shape table check: every listed key passes its check, no extra keys.
function Guard.shape(fields: { [string]: Check }): Check
	return function(v: any): boolean
		if type(v) ~= "table" then
			return false
		end
		for key, check in fields do
			if not check((v :: { [string]: any })[key]) then
				return false
			end
		end
		for key in v :: { [string]: any } do
			if fields[key] == nil then
				return false
			end
		end
		return true
	end
end

function Guard.optional(check: Check): Check
	return function(v: any): boolean
		return v == nil or check(v)
	end
end

return Guard
