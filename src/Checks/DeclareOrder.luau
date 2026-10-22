-- A name used before its top-level `local` line. Above that line, Luau reads a global of the same
-- name, which is nil. The classic case: a function near the top calls a helper whose `local` is
-- further down, and the call fails only when that function runs.
-- The fix is a forward declaration: `local Name` above the first use, and the later
-- `local Name = value` becomes `Name = value`.

local Edit = require(script.Parent.Parent.Edit)
local Util = require(script.Parent.Util)

local DeclareOrder = {}

-- Built-in names. A script can shadow them on purpose (local workspace = game.Workspace).
local BUILT_IN = {}
for _, name in {
	"game", "workspace", "script", "plugin", "shared", "_G", "Instance", "Vector3", "Vector2", "CFrame", "Color3",
	"UDim", "UDim2", "Enum", "Ray", "Region3", "Rect", "TweenInfo", "BrickColor", "NumberRange", "NumberSequence",
	"ColorSequence", "PhysicalProperties", "Random", "DateTime", "RaycastParams", "OverlapParams", "Font", "Axes",
	"Faces", "Content", "SharedTable", "task", "math", "string", "table", "os", "debug", "coroutine", "utf8",
	"bit32", "buffer", "vector", "print", "warn", "error", "require", "type", "typeof", "pairs", "ipairs", "next",
	"select", "tostring", "tonumber", "unpack", "pcall", "xpcall", "assert", "setmetatable", "getmetatable",
	"rawget", "rawset", "rawequal", "rawlen", "tick", "time", "wait", "delay", "spawn", "settings", "UserSettings",
	"version", "stats", "elapsedTime", "gcinfo", "newproxy", "collectgarbage",
} do
	BUILT_IN[name] = true
end

local KEYWORD_STARTS = { ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true }

-- The first line of the top-level statement that holds `lineNumber`: the nearest line above that
-- starts at column 1 with a word that does not close a block.
local function statementStart(lines: { string }, lineNumber: number): number
	for index = lineNumber, 1, -1 do
		local word = string.match(lines[index], "^([%a_][%w_]*)")
		if word and not KEYWORD_STARTS[word] then
			return index
		end
	end
	return 1
end

-- Lines inside a type declaration. Types have their own names in Luau, so `export type Icon = ...`
-- above `local Icon = {}` is not a use of the variable.
local function typeLines(lines: { string }): { [number]: boolean }
	local inside = {}
	local depth, open = 0, false
	for lineNumber, line in lines do
		if not open and (string.find(line, "^%s*export%s+type%s") or string.find(line, "^%s*type%s+[%a_]")) then
			open = true
			depth = 0
		end
		if open then
			inside[lineNumber] = true
			for char in string.gmatch(line, "[{}()]") do
				depth += if char == "{" or char == "(" then 1 else -1
			end
			-- The declaration goes on while a bracket is open or the line ends in "=", "|", "&" or "->".
			if depth <= 0 and not string.find(line, "[=|&]%s*$") and not string.find(line, "%->%s*$") then
				open = false
			end
		end
	end
	return inside
end

function DeclareOrder.run(ctx, entry)
	local lines = entry.codeLines
	local typeLine = typeLines(lines)

	-- 1. Top-level declarations (column 1), the first one of each name.
	local declared = {}
	for lineNumber, line in lines do
		local fn = string.match(line, "^local%s+function%s+([%a_][%w_]*)")
		if fn then
			declared[fn] = declared[fn] or { line = lineNumber, kind = "function" }
		else
			local list, rest = string.match(line, "^local%s+([%a_][%w_%s,]*)(.*)$")
			if list then
				local names = {}
				for name in string.gmatch(list, "[%a_][%w_]*") do
					table.insert(names, name)
				end
				local kind = if #names > 1 then "multi"
					elseif string.find(rest, "^:") or string.find(rest, "^<") then "typed"
					elseif string.find(rest, "^=") then "value"
					elseif string.find(rest, "^%s*$") then "bare"
					else "other"
				for _, name in names do
					declared[name] = declared[name] or { line = lineNumber, kind = kind }
				end
			end
		end
	end

	-- 2. Names that also have an inner declaration somewhere: a local, a parameter or a loop variable.
	-- The use may be that inner one, so these are skipped to stay safe.
	local shadowed = {}
	for lineNumber, line in lines do
		for list in string.gmatch(line, "%f[%w_]local%s+([%a_][%w_%s,]*)") do
			for name in string.gmatch(list, "[%a_][%w_]*") do
				local decl = declared[name]
				if decl and decl.line ~= lineNumber then
					shadowed[name] = true
				end
			end
		end
		for params in string.gmatch(line, "%f[%w_]function[^(]*%(([^)]*)%)") do
			for name in string.gmatch(params, "[%a_][%w_]*") do
				shadowed[name] = true
			end
		end
		for list in string.gmatch(line, "%f[%w_]for%s+([%a_][%w_%s,]*)") do
			for name in string.gmatch(list, "[%a_][%w_]*") do
				shadowed[name] = true
			end
		end
	end

	-- 3. The first use of each declared name above its declaration.
	local firstUse = {}
	for lineNumber, line in lines do
		for column, name in string.gmatch(line, "()([%a_][%w_]*)") do
			local decl = declared[name]
			if decl and lineNumber < decl.line and not firstUse[name] and not shadowed[name] and not BUILT_IN[name]
				and not typeLine[lineNumber] then
				local before = Util.charBefore(line, column)
				-- A type after "->" (and after ":" or "::", which isField covers) is not the variable.
				local isType = string.find(string.sub(line, 1, column - 1), "%->%s*$") ~= nil
				local after = string.sub(line, column + #name)
				-- "a.name", "a:name" and a table key "{ name = 1 }" are not the variable.
				local isField = before == "." or before == ":"
				local isKey = string.find(after, "^%s*=[^=]") and (before == "{" or before == "," or before == ";"
					or (before == "" and string.find(line, ",%s*$")))
				if not isField and not isKey and not isType and string.sub(line, column - 1, column - 1) ~= "." then
					firstUse[name] = lineNumber
				end
			end
		end
	end

	for name, useLine in firstUse do
		local decl = declared[name]
		local finding = {
			severity = "Error",
			tag = "SCRIPTS",
			title = "Used before its local line: " .. name,
			path = Util.where(entry.script, useLine),
			target = entry.script,
			line = useLine,
			text = string.format("Line %d uses %s, but local %s is on line %d. Above that line, Luau reads a global %s, "
				.. "which is nil. Declare it above its first use.", useLine, name, name, decl.line, name),
		}
		local declLine = lines[decl.line]
		local insertAfter = statementStart(lines, useLine) - 1
		local compute = nil
		if decl.kind == "function" then
			local old = string.match(declLine, "^local%s+function%s+" .. name .. "%f[^%w_]")
			compute = Edit.chain({
				Edit.computeReplaceMany({ { decl.line, 1, old, "function " .. name } }),
				Edit.computeInsertLineAfter(insertAfter, nil, "local " .. name),
			})
		elseif decl.kind == "value" or decl.kind == "bare" then
			local old = string.match(declLine, "^local%s+" .. name .. "%f[^%w_]")
			-- "local Name" with no value becomes an empty line.
			compute = Edit.chain({
				Edit.computeReplaceMany({ { decl.line, 1, old, if decl.kind == "value" then name else "" } }),
				Edit.computeInsertLineAfter(insertAfter, nil, "local " .. name),
			})
		end
		if compute then
			finding.fix = Edit.scriptFix(entry.script, string.format("Declare %s above line %d", name, useLine), compute, true)
		else
			finding.text ..= " This declaration has several names or a type, so move it by hand."
		end
		ctx.add(finding)
	end
end

return DeclareOrder
