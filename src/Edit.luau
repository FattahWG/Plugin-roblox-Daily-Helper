-- Safe script and property edits for the Apply button. A script fix is a `compute(source)` function
-- that returns the new source, or nil when the text is no longer the text the audit found. The same
-- function makes the before/after preview and the real edit, so the preview shows what Apply does.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Edit = {}

local MAX_SHIFT = 5
local PREVIEW_LINES = 6

-- Returns the first and the last index of a line, without its newline.
local function lineSpan(source: string, lineNumber: number): (number?, number?)
	if lineNumber < 1 then
		return nil, nil
	end
	local start = 1
	for _ = 2, lineNumber do
		local newline = string.find(source, "\n", start, true)
		if not newline then
			return nil, nil
		end
		start = newline + 1
	end
	local newline = string.find(source, "\n", start, true)
	local finish = if newline then newline - 1 else #source
	if string.sub(source, finish, finish) == "\r" then
		finish -= 1
	end
	return start, finish
end

local function shifts()
	local list = {}
	for step = 0, MAX_SHIFT * 2 do
		table.insert(list, if step % 2 == 1 then (step + 1) // 2 else -(step // 2))
	end
	return list
end
local SHIFTS = shifts()

-- An earlier fix can add or remove a line above a spot. This finds the line shift (0, then +1,
-- -1, up to 5) at which every spot still holds its old text, or nil.
local function findShift(source: string, spots: { { any } }): number?
	for _, shift in SHIFTS do
		local good = true
		for _, spot in spots do
			local start, finish = lineSpan(source, spot[1] + shift)
			local at = start and start + spot[2] - 1
			if not at or at + #spot[3] - 1 > (finish :: number) or string.sub(source, at, at + #spot[3] - 1) ~= spot[3] then
				good = false
				break
			end
		end
		if good then
			return shift
		end
	end
	return nil
end

function Edit.readSource(script: LuaSourceContainer): string
	local ok, source = pcall(ScriptEditorService.GetEditorSource, ScriptEditorService, script)
	if ok and type(source) == "string" then
		return source
	end
	return (script :: any).Source
end

-- ===== compute functions =====

-- Replaces many spots as one change. Each spot is { line, column, old, new }.
function Edit.computeReplaceMany(spots: { { any } })
	local ordered = table.clone(spots)
	-- The last spot goes first, thus an edit never moves a spot that is still to come.
	table.sort(ordered, function(a, b)
		if a[1] ~= b[1] then
			return a[1] > b[1]
		end
		return a[2] > b[2]
	end)
	return function(source: string): string?
		local shift = findShift(source, ordered)
		if not shift then
			return nil
		end
		for _, spot in ordered do
			local start = lineSpan(source, spot[1] + shift) :: number
			local at = start + spot[2] - 1
			source = string.sub(source, 1, at - 1) .. spot[4] .. string.sub(source, at + #spot[3])
		end
		return source
	end
end

-- Adds a new line after a line. `expect` is a pattern that the old line must match.
-- lineNumber 0 adds the line at the top of the script.
function Edit.computeInsertLineAfter(lineNumber: number, expect: string?, newLine: string)
	return function(source: string): string?
		local newline = if string.find(source, "\r\n", 1, true) then "\r\n" else "\n"
		if lineNumber == 0 then
			return newLine .. newline .. source
		end
		for _, shift in SHIFTS do
			local start, finish = lineSpan(source, lineNumber + shift)
			if start and finish and (expect == nil or string.find(string.sub(source, start, finish), expect)) then
				return string.sub(source, 1, finish) .. newline .. newLine .. string.sub(source, finish + 1)
			end
		end
		return nil
	end
end

-- Runs computes one after the other. Any nil stops the whole change.
function Edit.chain(computes: { (string) -> string? })
	return function(source: string): string?
		for _, compute in computes do
			local result = compute(source)
			if result == nil then
				return nil
			end
			source = result
		end
		return source
	end
end

-- ===== preview =====

local function splitLines(text: string): { string }
	local lines = {}
	for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
		table.insert(lines, line)
	end
	return lines
end

-- Returns up to PREVIEW_LINES rows { kind = "-" | "+", line = number, text = string }, or nil and a reason.
-- The changes are small (renames, one added line), so a greedy walk finds them.
function Edit.preview(script: LuaSourceContainer, compute: (string) -> string?)
	local old = Edit.readSource(script)
	local new = compute(old)
	if new == nil then
		return nil, "The code changed after the audit. Run the audit again."
	end
	local a, b = splitLines(old), splitLines(new)
	local rows = {}
	local i, j = 1, 1
	while (i <= #a or j <= #b) and #rows < PREVIEW_LINES do
		if a[i] == b[j] then
			i += 1
			j += 1
		elseif a[i] == b[j + 1] then
			table.insert(rows, { kind = "+", line = j, text = b[j] })
			j += 1
		elseif a[i + 1] == b[j] then
			table.insert(rows, { kind = "-", line = i, text = a[i] })
			i += 1
		else
			if a[i] then
				table.insert(rows, { kind = "-", line = i, text = a[i] })
			end
			if b[j] then
				table.insert(rows, { kind = "+", line = j, text = b[j] })
			end
			i += 1
			j += 1
		end
	end
	return rows
end

-- ===== writing =====

-- Runs `compute(oldSource) -> newSource?` on a script. A nil result cancels the edit.
function Edit.update(script: LuaSourceContainer, compute: (string) -> string?): (boolean, string?)
	local failure = nil
	local ok, err = pcall(function()
		ScriptEditorService:UpdateSourceAsync(script, function(old)
			local new = compute(old)
			if new == nil then
				failure = "The code changed after the audit. Run the audit again."
			end
			return new
		end)
	end)
	if not ok then
		return false, tostring(err)
	end
	if failure then
		return false, failure
	end
	return true, nil
end

-- A fix for one script. Apply, preview and restore all use the same compute function.
function Edit.scriptFix(script: LuaSourceContainer, label: string, compute: (string) -> string?, risky: boolean?)
	return {
		label = label,
		risky = risky,
		scripts = { script },
		compute = compute,
		apply = function()
			return Edit.update(script, compute)
		end,
		preview = function()
			return Edit.preview(script, compute)
		end,
	}
end

-- Puts a saved source back, but only when the script still holds what the fix wrote.
function Edit.restore(script: LuaSourceContainer, original: string, written: string): (boolean, string?)
	return Edit.update(script, function(current)
		if current ~= written then
			return nil
		end
		return original
	end)
end

-- Runs a change as one undo step with a name. Returns ok, error.
function Edit.record(name: string, change: () -> (boolean, string?)): (boolean, string?)
	local recording = ChangeHistoryService:TryBeginRecording("Daily Helper: " .. name)
	local ok, done, err = pcall(change)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok and done then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not ok then
		return false, tostring(done)
	end
	return done, err
end

return Edit
