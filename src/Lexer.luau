-- Blanks comments and strings in Luau source. Each blanked character becomes a space and each
-- newline stays, so a line and a column in the output point to the same text in the source.

local Lexer = {}

local function blank(text: string): string
	return (string.gsub(text, "[^\n]", " "))
end

-- Returns the end of a long bracket that opens at `start` ("[[", "[==["), or nil.
local function longBracketEnd(source: string, start: number): number?
	local equals = string.match(source, "^%[(=*)%[", start)
	if not equals then
		return nil
	end
	local close = "]" .. equals .. "]"
	local _, finish = string.find(source, close, start + #equals + 2, true)
	return finish or #source
end

-- Returns the end of a quoted string that opens at `start`.
local function quotedEnd(source: string, start: number, quote: string): number
	local index = start + 1
	local length = #source
	while index <= length do
		local char = string.sub(source, index, index)
		if char == "\\" then
			index += 2
		elseif char == quote then
			return index
		elseif char == "\n" and quote ~= "`" then
			return index - 1
		else
			index += 1
		end
	end
	return length
end

-- Returns two texts: `code` with comments and strings blanked, and `withStrings` with
-- only the comments blanked.
function Lexer.strip(source: string): (string, string)
	local code, withStrings = {}, {}
	local index = 1
	local length = #source
	while index <= length do
		local start = string.find(source, "[%-%[\"'`]", index)
		if not start then
			table.insert(code, string.sub(source, index))
			table.insert(withStrings, string.sub(source, index))
			break
		end
		local before = string.sub(source, index, start - 1)
		table.insert(code, before)
		table.insert(withStrings, before)
		local char = string.sub(source, start, start)
		local finish = nil
		local isComment = false
		if char == "-" then
			if string.sub(source, start + 1, start + 1) == "-" then
				isComment = true
				finish = longBracketEnd(source, start + 2)
				if not finish then
					local lineEnd = string.find(source, "\n", start, true)
					finish = if lineEnd then lineEnd - 1 else length
				end
			end
		elseif char == "[" then
			finish = longBracketEnd(source, start)
		else
			finish = quotedEnd(source, start, char)
		end
		if finish then
			local piece = string.sub(source, start, finish)
			table.insert(code, blank(piece))
			table.insert(withStrings, if isComment then blank(piece) else piece)
			index = finish + 1
		else
			table.insert(code, char)
			table.insert(withStrings, char)
			index = start + 1
		end
	end
	return table.concat(code), table.concat(withStrings)
end

function Lexer.lines(text: string): { string }
	local result = {}
	for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
		table.insert(result, line)
	end
	return result
end

return Lexer
