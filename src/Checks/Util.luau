-- Shared helpers for the checks.

local Util = {}

-- Calls fn(lineNumber, column, ...captures) for each match of `pattern` in each line.
-- The pattern must start with a position capture "()".
function Util.eachMatch(lines: { string }, pattern: string, fn: (number, number, ...string) -> ())
	for lineNumber, line in lines do
		local from = 1
		while true do
			local results = { string.find(line, pattern, from) }
			if not results[1] then
				break
			end
			fn(lineNumber, results[3], table.unpack(results, 4))
			from = results[2] + 1
		end
	end
end

-- The character before a column, spaces skipped.
function Util.charBefore(line: string, column: number): string
	local before = string.match(string.sub(line, 1, column - 1), "(%S)%s*$")
	return before or ""
end

function Util.path(instance: Instance): string
	local ok, name = pcall(instance.GetFullName, instance)
	return if ok then name else instance.Name
end

-- A short path for a script line: "Parent.Script : 12".
function Util.where(script: Instance, line: number?): string
	local name = Util.path(script)
	return if line then name .. " : " .. line else name
end

function Util.plural(count: number, one: string, many: string?): string
	return string.format("%d %s", count, if count == 1 then one else (many or one .. "s"))
end

-- Names that the game code defines itself: methods, module functions, self fields and table keys.
-- A deprecated Roblox name that the game also defines is most likely the game's own.
function Util.ownNames(ctx): { [string]: boolean }
	if ctx.ownNames then
		return ctx.ownNames
	end
	local scripts = ctx.scripts
	local names = {}
	local patterns = {
		"function%s+[%w_%.:]-[%.:]([%a_][%w_]*)%s*%(",
		"[%.:]([%a_][%w_]*)%s*=%s*function",
		"self%.([%a_][%w_]*)%s*=[^=]",
		"[{,;]%s*([%a_][%w_]*)%s*=[^=]",
	}
	for _, entry in scripts do
		for _, pattern in patterns do
			for name in string.gmatch(entry.code, pattern) do
				names[name] = true
			end
		end
		for _, line in entry.codeLines do
			local name = string.match(line, "^%s*([%a_][%w_]*)%s*=[^=]")
			if name then
				names[name] = true
			end
		end
	end
	ctx.ownNames = names
	return names
end

return Util
