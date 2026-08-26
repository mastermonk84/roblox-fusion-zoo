--!strict
-- Minimal TestEZ-API-compatible runner. Spec files require this module, take
-- locals for describe/it/expect, and return a function; scripts/run-tests
-- collects and executes them under Lune. The module is engine-pure, so the same
-- specs can run inside Studio from a bootstrap script.

export type Node = {
	name: string,
	kind: "describe" | "it",
	fn: (() -> ())?,
	children: { Node },
	skip: boolean,
	focus: boolean,
}

export type Result = {
	name: string,
	path: string,
	ok: boolean,
	err: string?,
	skipped: boolean,
}

local Testkit = {}

local root: Node
local current: Node

local function newNode(name: string, kind: "describe" | "it"): Node
	return { name = name, kind = kind, fn = nil, children = {}, skip = false, focus = false }
end

function Testkit.reset()
	root = newNode("", "describe")
	current = root
end

Testkit.reset()

function Testkit.describe(name: string, fn: () -> ())
	local node = newNode(name, "describe")
	table.insert(current.children, node)
	local prev = current
	current = node
	fn()
	current = prev
end

function Testkit.it(name: string, fn: () -> ())
	local node = newNode(name, "it")
	node.fn = fn
	table.insert(current.children, node)
end

function Testkit.itSKIP(name: string, _fn: () -> ())
	local node = newNode(name, "it")
	node.skip = true
	table.insert(current.children, node)
end

function Testkit.itFOCUS(name: string, fn: () -> ())
	local node = newNode(name, "it")
	node.fn = fn
	node.focus = true
	table.insert(current.children, node)
end

-- beforeEach applies to the current describe block and everything nested in it.
local beforeEachMap: { [Node]: { () -> () } } = {}

function Testkit.beforeEach(fn: () -> ())
	local list = beforeEachMap[current]
	if not list then
		list = {}
		beforeEachMap[current] = list
	end
	table.insert(list, fn)
end

-- ── expect (TestEZ matcher surface) ─────────────────────────────────────────

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a :: { [any]: any } do
		if not deepEqual(v, (b :: { [any]: any })[k]) then
			return false
		end
	end
	for k in b :: { [any]: any } do
		if (a :: { [any]: any })[k] == nil then
			return false
		end
	end
	return true
end

Testkit.deepEqual = deepEqual

local function fmt(v: any): string
	if type(v) == "table" then
		local parts = {}
		for k, val in v :: { [any]: any } do
			table.insert(parts, `{tostring(k)}={tostring(val)}`)
			if #parts >= 6 then
				table.insert(parts, "…")
				break
			end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

export type Expectation = {
	to: any,
	never: any,
}

function Testkit.expect(value: any): any
	local function check(cond: boolean, message: string)
		if not cond then
			error(message, 0)
		end
	end
	local expectation = {}
	local function build(negate: boolean)
		local chain: any = {}
		chain.be = chain
		chain.been = chain
		chain.have = chain
		chain.was = chain
		chain.at = chain
		function chain.equal(other: any)
			local eq = value == other
			check(
				eq ~= negate,
				`expected {fmt(value)}{negate and " never" or ""} to equal {fmt(other)}`
			)
			return chain
		end
		function chain.deepEqual(other: any)
			local eq = deepEqual(value, other)
			check(
				eq ~= negate,
				`expected {fmt(value)}{negate and " never" or ""} to deep-equal {fmt(other)}`
			)
			return chain
		end
		function chain.ok()
			local isOk = value ~= nil and value ~= false
			check(isOk ~= negate, `expected {fmt(value)}{negate and " never" or ""} to be ok`)
			return chain
		end
		function chain.near(other: number, limit: number?)
			local eps = limit or 1e-7
			local isNear = type(value) == "number" and math.abs((value :: number) - other) <= eps
			check(
				isNear ~= negate,
				`expected {fmt(value)}{negate and " never" or ""} to be near {other} (±{eps})`
			)
			return chain
		end
		function chain.throw(substring: string?)
			local ok, err = pcall(value :: () -> ())
			local threw = not ok
				and (substring == nil or string.find(tostring(err), substring, 1, true) ~= nil)
			check(
				threw ~= negate,
				`expected function{negate and " never" or ""} to throw {substring or ""} (got: {tostring(
					err
				)})`
			)
			return chain
		end
		return chain
	end
	expectation.to = build(false)
	expectation.never = { to = build(true) }
	return expectation
end

-- ── execution ───────────────────────────────────────────────────────────────

local function hasFocus(node: Node): boolean
	if node.focus then
		return true
	end
	for _, child in node.children do
		if hasFocus(child) then
			return true
		end
	end
	return false
end

function Testkit.collect(specName: string, body: () -> ()): Node
	Testkit.reset()
	local wrapper = newNode(specName, "describe")
	root.children = { wrapper }
	local prev = current
	current = wrapper
	body()
	current = prev
	return wrapper
end

function Testkit.execute(
	node: Node,
	results: { Result },
	path: string,
	befores: { () -> () },
	focusOnly: boolean
)
	local myBefores = table.clone(befores)
	for _, fn in beforeEachMap[node] or {} do
		table.insert(myBefores, fn)
	end
	for _, child in node.children do
		local childPath = if path == "" then child.name else `{path} › {child.name}`
		if child.kind == "describe" then
			Testkit.execute(child, results, childPath, myBefores, focusOnly and not child.focus)
		else
			if child.skip or (focusOnly and not child.focus) then
				table.insert(
					results,
					{ name = child.name, path = childPath, ok = true, err = nil, skipped = true }
				)
			else
				local ok, err = pcall(function()
					for _, fn in myBefores do
						fn()
					end
					local body = child.fn :: () -> ()
					body()
				end)
				table.insert(results, {
					name = child.name,
					path = childPath,
					ok = ok,
					err = if ok then nil else tostring(err),
					skipped = false,
				})
			end
		end
	end
end

function Testkit.runSpec(specName: string, body: () -> ()): { Result }
	local tree = Testkit.collect(specName, body)
	local results: { Result } = {}
	Testkit.execute(tree, results, specName, {}, hasFocus(tree) and not tree.focus)
	return results
end

return Testkit
