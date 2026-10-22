-- The plugin state and actions. init.server.luau starts it with the real plugin and dock window,
-- and a test can start it with a stand-in plugin and a ScreenGui.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local Selection = game:GetService("Selection")

local ApiDump = require(script.Parent.ApiDump)
local Edit = require(script.Parent.Edit)
local Log = require(script.Parent.Log)
local Scanner = require(script.Parent.Scanner)
local View = require(script.Parent.View)

local App = {}

App.VERSION = "0.2.0"

-- plugin: needs GetSetting, SetSetting and OpenScript. widget: a DockWidgetPluginGui or a ScreenGui.
function App.start(plugin, widget)
	local log = Log.new(plugin)
	local statsKey = "Stats_" .. string.sub(log.key, 5)

	local enabled = plugin:GetSetting("Enabled")
	if type(enabled) ~= "table" then
		enabled = {}
		for _, check in Scanner.Checks do
			enabled[check.id] = true
		end
	end

	local studioVersion = string.match(version(), "^(%d+%.%d+)") or version()

	local app = {
		log = log,
		checks = Scanner.Checks,
		apiVersion = nil,
		versionText = string.format("v%s  ·  Studio %s", App.VERSION, studioVersion),
		state = {
			-- "intro" (start screen), "info" (Information) or "main" (the tabs).
			screen = "intro",
			infoFrom = "intro",
			tab = "Scan",
			scope = "place",
			enabled = enabled,
			running = false,
			progress = "",
			findings = {},
			stats = plugin:GetSetting(statsKey),
			filter = "All",
			apiStatus = "unknown",
			overlay = nil,
			picked = {},
			scale = 1.25,
			query = "",
		},
		actions = {},
	}
	local state, actions = app.state, app.actions
	local savedScale = plugin:GetSetting("UiScale")
	if type(savedScale) == "number" and savedScale >= 1 and savedScale <= 2 then
		state.scale = savedScale
	end
	local cache = plugin:GetSetting("ApiCache")
	app.apiVersion = if type(cache) == "table" and type(cache.version) == "string" then cache.version else nil
	local view

	local function render()
		if view then
			view:render()
		end
	end

	-- The findings with a fix that the developer has not decided on yet.
	function app.pendingFixes()
		local result = {}
		for _, finding in state.findings do
			if finding.fix and (finding.status == nil or finding.status == "Failed") then
				table.insert(result, finding)
			end
		end
		return result
	end

	local function short(finding): string
		return string.format("%s  ·  %s", if finding.fix then finding.fix.label else finding.title, finding.path)
	end

	-- ===== actions =====

	function actions.setScale(scale: number)
		state.scale = scale
		plugin:SetSetting("UiScale", scale)
		view:applyScale()
		render()
	end

	function actions.start()
		state.screen = "main"
		render()
	end

	function actions.showInfo()
		if state.screen ~= "info" then
			state.infoFrom = state.screen
		end
		state.screen = "info"
		render()
	end

	function actions.back()
		state.screen = if state.infoFrom == "main" then "main" else "intro"
		render()
	end

	function actions.setTab(name: string)
		state.tab = name
		render()
	end

	function actions.setScope(scope: string)
		state.scope = scope
		render()
	end

	function actions.toggleCheck(id: string)
		state.enabled[id] = not state.enabled[id]
		plugin:SetSetting("Enabled", state.enabled)
		render()
	end

	function actions.setFilter(filter: string)
		state.filter = filter
		if view then
			view.shown = 40
		end
		render()
	end

	function actions.run()
		if state.running then
			return
		end
		local roots = if state.scope == "selection" then Selection:Get() else Scanner.placeRoots()
		if #roots == 0 then
			log:add("failed", "Nothing is selected. Select an object, or choose Whole place.")
			state.tab = "Log"
			render()
			return
		end
		local count = 0
		for _, on in state.enabled do
			if on then
				count += 1
			end
		end
		if count == 0 then
			log:add("failed", "No check is on. Turn on a check first.")
			state.tab = "Log"
			render()
			return
		end

		state.running = true
		state.progress = "Starting..."
		render()
		log:add("info", string.format("Audit started  ·  %s  ·  %d checks",
			if state.scope == "selection" then "selection" else "whole place", count))

		task.spawn(function()
			local api, apiMessage = nil, nil
			if state.enabled.api then
				if view then
					view:setProgress("Reading the Roblox API...")
				end
				local status
				api, status, apiMessage = ApiDump.load(plugin)
				state.apiStatus = status
				if api then
					app.apiVersion = api.version
				end
				log:add(if api then "info" else "failed", apiMessage)
			end
			local ok, findings, stats = pcall(Scanner.run, {
				roots = roots,
				enabled = state.enabled,
				api = api,
				apiMessage = apiMessage,
				progress = function(text)
					state.progress = text
					if view then
						view:setProgress(text)
					end
				end,
			})
			state.running = false
			if not ok then
				log:add("failed", "The audit stopped: " .. tostring(findings))
				state.tab = "Log"
				render()
				return
			end
			state.findings = findings
			state.stats = stats
			state.filter = "All"
			state.picked = {}
			if view then
				view.shown = 40
			end
			plugin:SetSetting(statsKey, stats)
			log:add("done", string.format("Audit done  ·  %d scripts  ·  %d findings  ·  score %d",
				stats.scripts, #findings, stats.score))
			state.tab = "Findings"
			-- Ask the developer at once. A risky change starts unticked.
			local pending = app.pendingFixes()
			for _, finding in pending do
				state.picked[finding] = not finding.fix.risky
			end
			state.overlay = if #pending > 0 then "prompt" else nil
			render()
		end)
	end

	function actions.open(finding)
		local target = finding.target
		if typeof(target) == "Instance" and target:IsA("LuaSourceContainer") then
			task.spawn(function()
				local options = nil
				if finding.line then
					options = { HighlightRange = { Start = { Line = finding.line, Character = 1 }, End = { Line = finding.line, Character = 1 } } }
				end
				local ok, err = ScriptEditorService:OpenScriptDocumentAsync(target, options)
				if not ok then
					plugin:OpenScript(target, finding.line or 1)
					if err then
						warn("[Daily Helper] " .. tostring(err))
					end
				end
			end)
			return
		end
		local items = if typeof(target) == "Instance" then { target } else target
		local alive = {}
		for _, item in items or {} do
			if item.Parent then
				table.insert(alive, item)
			end
		end
		Selection:Set(alive)
	end

	local function applyOne(finding): boolean
		-- Keep each script's text first. Restore puts it back if the developer does not like the change.
		local before = {}
		for _, item in finding.fix.scripts or {} do
			table.insert(before, { script = item, original = Edit.readSource(item) })
		end
		local ok, err = Edit.record(finding.fix.label, finding.fix.apply)
		if ok then
			for _, saved in before do
				saved.written = Edit.readSource(saved.script)
			end
			finding.snapshots = if #before > 0 then before else nil
			finding.status = "Applied"
			finding.note = nil
			log:add("applied", "Applied  ·  " .. short(finding))
		else
			finding.status = "Failed"
			finding.note = tostring(err or "The change did not apply.")
			log:add("failed", "Failed  ·  " .. short(finding) .. "  ·  " .. finding.note)
		end
		return ok
	end

	function actions.apply(finding)
		task.spawn(function()
			applyOne(finding)
			render()
		end)
	end

	function actions.skip(finding)
		finding.status = "Skipped"
		log:add("skipped", "Skipped  ·  " .. short(finding))
		render()
	end

	function actions.restore(finding)
		local snapshots = finding.snapshots
		if not snapshots then
			return
		end
		task.spawn(function()
			local restored, failed = 0, nil
			for _, saved in snapshots do
				local ok, err = Edit.restore(saved.script, saved.original, saved.written)
				if ok then
					restored += 1
				else
					failed = err
				end
			end
			if failed then
				finding.note = "Restore stopped: the script changed after Apply. Nothing was overwritten in that script."
				log:add("failed", "Restore stopped  ·  " .. short(finding))
			else
				finding.status = "Restored"
				finding.snapshots = nil
				finding.note = nil
				log:add("undo", string.format("Restored  ·  %s  ·  %d %s", short(finding), restored, if restored == 1 then "script" else "scripts"))
			end
			render()
		end)
	end

	function actions.setQuery(text: string)
		state.query = text
		if view then
			view.shown = 40
		end
		render()
	end

	function actions.review(finding)
		finding.status = "Reviewed"
		log:add("reviewed", "Reviewed  ·  " .. short(finding))
		render()
	end

	function actions.openPrompt()
		state.picked = {}
		for _, finding in app.pendingFixes() do
			state.picked[finding] = not finding.fix.risky
		end
		state.overlay = "prompt"
		render()
	end

	function actions.togglePick(finding)
		state.picked[finding] = not state.picked[finding]
		render()
	end

	function actions.applyPicked()
		local chosen, left = {}, {}
		for _, finding in app.pendingFixes() do
			if state.picked[finding] then
				table.insert(chosen, finding)
			else
				table.insert(left, finding)
			end
		end
		state.overlay = nil
		render()
		task.spawn(function()
			local applied = 0
			for _, finding in chosen do
				if applyOne(finding) then
					applied += 1
				end
			end
			for _, finding in left do
				log:add("skipped", "Not applied  ·  " .. short(finding) .. "  ·  developer choice")
			end
			log:add("done", string.format("Applied %d of %d chosen changes", applied, #chosen))
			render()
		end)
	end

	function actions.closeOverlay()
		if state.overlay == "prompt" then
			log:add("info", "Apply prompt closed  ·  no change made")
		end
		state.overlay = nil
		render()
	end

	function actions.openCopy()
		state.overlay = "copy"
		render()
	end

	function actions.clearLog()
		log:clear()
		render()
	end

	view = View.new(widget, app)

	local connections = {}
	table.insert(connections, log.changed.Event:Connect(function()
		if state.tab == "Log" and not state.running then
			render()
		end
	end))
	table.insert(connections, ChangeHistoryService.OnUndo:Connect(function(waypoint)
		local name = string.match(waypoint, "^Daily Helper: (.+)$")
		if name then
			log:add("undo", "Undo  ·  " .. name)
		end
	end))
	table.insert(connections, ChangeHistoryService.OnRedo:Connect(function(waypoint)
		local name = string.match(waypoint, "^Daily Helper: (.+)$")
		if name then
			log:add("redo", "Redo  ·  " .. name)
		end
	end))
	-- Each time the developer turns the window on, it opens on the start screen. A closed window
	-- stops the blob animation.
	table.insert(connections, widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if widget.Enabled then
			if not state.running then
				state.screen = "intro"
				state.overlay = nil
			end
			render()
		else
			view:stopBlob()
		end
	end))
	table.insert(connections, settings().Studio.ThemeChanged:Connect(function()
		view:build()
	end))

	function app.stop()
		for _, connection in connections do
			connection:Disconnect()
		end
		view:stopBlob()
		log.changed:Destroy()
		if view.root then
			view.root:Destroy()
		end
	end

	app.view = view
	return app
end

return App
