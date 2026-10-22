-- Collects the instances and scripts of a scope, then runs the chosen checks on them.

local ScriptEditorService = game:GetService("ScriptEditorService")

local Lexer = require(script.Parent.Lexer)

local Scanner = {}

Scanner.Checks = {
	require(script.Parent.Checks.UiLayout),
	require(script.Parent.Checks.Tree),
	require(script.Parent.Checks.Scripts),
	require(script.Parent.Checks.Security),
	require(script.Parent.Checks.Performance),
	require(script.Parent.Checks.LiveApi),
}

Scanner.PlaceRoots = {
	"Workspace", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage",
	"StarterGui", "StarterPack", "StarterPlayer", "Lighting", "SoundService", "Teams", "TextChatService",
}

local SEVERITY_ORDER = { Error = 1, Warning = 2, Info = 3 }
-- Wally and other package folders hold code that the developer does not edit.
local SKIP_NAMES = { _Index = true }

local function readSource(item: LuaSourceContainer): string
	local ok, source = pcall(ScriptEditorService.GetEditorSource, ScriptEditorService, item)
	if ok and type(source) == "string" then
		return source
	end
	local okSource, raw = pcall(function()
		return (item :: any).Source
	end)
	return if okSource and type(raw) == "string" then raw else ""
end

function Scanner.placeRoots(): { Instance }
	local roots = {}
	for _, name in Scanner.PlaceRoots do
		local service = game:FindFirstChildOfClass(name) or game:FindFirstChild(name)
		if service then
			table.insert(roots, service)
		end
	end
	return roots
end

-- options: roots, enabled ({ [checkId] = true }), api, apiMessage, progress(text)
function Scanner.run(options)
	local started = os.clock()
	local progress = options.progress or function() end
	local lastYield = os.clock()
	local function yield()
		if os.clock() - lastYield > 0.03 then
			task.wait()
			lastYield = os.clock()
		end
	end

	progress("Reading the place...")
	local instances, scripts = {}, {}
	local seen = {}
	local function visit(item: Instance)
		if seen[item] or SKIP_NAMES[item.Name] then
			return
		end
		seen[item] = true
		table.insert(instances, item)
		if item:IsA("LuaSourceContainer") then
			table.insert(scripts, item)
		end
	end
	for _, root in options.roots do
		visit(root)
		for _, item in root:GetDescendants() do
			if not item:FindFirstAncestor("_Index") then
				visit(item)
			end
			yield()
		end
	end

	local entries = {}
	for index, item in scripts do
		local raw = readSource(item)
		local code, strings = Lexer.strip(raw)
		table.insert(entries, {
			script = item,
			raw = raw,
			code = code,
			strings = strings,
			codeLines = Lexer.lines(code),
			stringLines = Lexer.lines(strings),
		})
		if index % 10 == 0 then
			progress(string.format("Reading scripts %d / %d", index, #scripts))
		end
		yield()
	end

	local findings = {}
	local ctx = {
		roots = options.roots,
		instances = instances,
		scripts = entries,
		api = options.api,
		apiMessage = options.apiMessage,
		yield = yield,
	}
	for _, check in Scanner.Checks do
		if options.enabled[check.id] then
			progress("Checking " .. string.lower(check.name) .. "...")
			ctx.add = function(finding)
				finding.check = check.id
				finding.group = check.name
				finding.tag = finding.tag or string.upper(check.name)
				finding.key = table.concat({ check.id, finding.title, finding.path }, "|")
				table.insert(findings, finding)
			end
			local ok, err = pcall(check.run, ctx)
			if not ok then
				table.insert(findings, {
					check = check.id,
					group = check.name,
					tag = string.upper(check.name),
					severity = "Info",
					title = check.name .. " check stopped",
					path = "Daily Helper",
					text = "The check hit an error and its results are not complete: " .. tostring(err),
					key = check.id .. "|error",
				})
			end
		end
	end

	-- Scripts with the same code (copies of one rig or tool) give one finding with all copies.
	-- Apply then fixes every copy.
	local sourceId, nextId = {}, 0
	local idOf = {}
	for _, entry in entries do
		if not sourceId[entry.raw] then
			nextId += 1
			sourceId[entry.raw] = nextId
		end
		idOf[entry.script] = sourceId[entry.raw]
	end
	local merged, kept = {}, {}
	for _, finding in findings do
		local target = finding.target
		local id = typeof(target) == "Instance" and idOf[target]
		if id then
			local key = table.concat({ finding.check, finding.title, tostring(finding.line), id,
				if finding.fix then finding.fix.label else "" }, "|")
			local first = merged[key]
			if first then
				first.copies = first.copies or { first }
				table.insert(first.copies, finding)
				continue
			end
			merged[key] = finding
		end
		table.insert(kept, finding)
	end
	for _, finding in kept do
		local copies = finding.copies
		if copies then
			finding.path ..= string.format("  ·  same code in %d more %s", #copies - 1, if #copies == 2 then "script" else "scripts")
			finding.key ..= "|x" .. #copies
			if finding.fix then
				-- Keep each copy's own apply first. copies[1] is this finding, and its fix is
				-- replaced below. Calling copy.fix.apply after that calls this new fix again,
				-- with no end (stack overflow).
				local applies, scripts = {}, {}
				for _, copy in copies do
					if copy.fix then
						table.insert(applies, copy.fix.apply)
						for _, item in copy.fix.scripts or {} do
							table.insert(scripts, item)
						end
					end
				end
				finding.fix = {
					label = finding.fix.label .. string.format(" in %d scripts", #copies),
					risky = finding.fix.risky,
					-- The copies hold the same code, so the first copy's preview shows the change.
					preview = finding.fix.preview,
					scripts = scripts,
					apply = function()
						for _, apply in applies do
							local ok, err = apply()
							if not ok then
								return false, err
							end
						end
						return true
					end,
				}
			end
		end
	end
	findings = kept

	table.sort(findings, function(a, b)
		local sa, sb = SEVERITY_ORDER[a.severity] or 9, SEVERITY_ORDER[b.severity] or 9
		if sa ~= sb then
			return sa < sb
		end
		return a.key < b.key
	end)

	local counts = { Error = 0, Warning = 0, Info = 0 }
	for _, finding in findings do
		counts[finding.severity] = (counts[finding.severity] or 0) + 1
	end
	-- Each kind of problem costs once, and many hits of it cost a little more. A big place with
	-- one old habit in 200 lines does not drop to zero.
	local WEIGHTS = { Error = 12, Warning = 4, Info = 1 }
	local rules = {}
	for _, finding in findings do
		-- "Deprecated: :connect" and "Deprecated: .userId" are one rule.
		local title = string.gsub(string.match(finding.title, "^[^:]+") or finding.title, "%d+", "#")
		local rule = finding.severity .. "|" .. finding.check .. "|" .. title
		rules[rule] = (rules[rule] or 0) + 1
	end
	local penalty = 0
	for rule, hits in rules do
		local weight = WEIGHTS[string.match(rule, "^(%a+)")] or 1
		penalty += weight * (1 + 0.5 * math.log(hits, 2))
	end
	local score = math.clamp(math.floor(100 - penalty + 0.5), 0, 100)

	return findings, {
		scripts = #scripts,
		instances = #instances,
		seconds = os.clock() - started,
		counts = counts,
		score = score,
		time = os.time(),
	}
end

return Scanner
