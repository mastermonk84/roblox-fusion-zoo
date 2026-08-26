--!strict
-- Headless test runner: lune run scripts/run-tests [-- --filter <substring>]
-- Globs tests/**/*.spec.luau, executes each through the testkit, exits nonzero
-- on any failure. Every spec file returns `function() ... end`.

local fs = require("@lune/fs")
local process = require("@lune/process")

local filter: string? = nil
for i, arg in process.args do
	if arg == "--filter" and process.args[i + 1] then
		filter = process.args[i + 1]
	end
end

local Testkit = require("../tests/testkit")

local specFiles: { string } = {}
local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local full = `{dir}/{name}`
		if fs.isDir(full) then
			walk(full)
		elseif string.match(name, "%.spec%.luau$") then
			table.insert(specFiles, full)
		end
	end
end
walk("tests")
table.sort(specFiles)

local passed, failed, skipped = 0, 0, 0
local failures: { { path: string, err: string } } = {}
local startedAt = os.clock()

for _, file in specFiles do
	if filter and not string.find(file, filter, 1, true) then
		continue
	end
	local specName = string.gsub(file, "^tests/", "")
	specName = string.gsub(specName, "%.spec%.luau$", "")
	-- Lune resolves requires relative to THIS file; specs live in ../tests/.
	local modulePath = "../" .. string.gsub(file, "%.luau$", "")
	local body = (require :: any)(modulePath) :: () -> ()
	local results = Testkit.runSpec(specName, body)
	for _, r in results do
		if r.skipped then
			skipped += 1
		elseif r.ok then
			passed += 1
		else
			failed += 1
			table.insert(failures, { path = r.path, err = r.err or "?" })
		end
	end
end

local elapsed = os.clock() - startedAt
if #failures > 0 then
	print("")
	for _, f in failures do
		print(`  ✗ {f.path}`)
		print(`      {f.err}`)
	end
end
print("")
print(
	`{passed} passed, {failed} failed, {skipped} skipped  ({string.format("%.2f", elapsed)}s, {#specFiles} spec files)`
)
if failed > 0 then
	process.exit(1)
end
