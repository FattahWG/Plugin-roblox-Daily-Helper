-- Security: code that loads other code, hides what it does, or sends data out.
-- The plugin never changes these scripts. The developer reads them and decides.

local Util = require(script.Parent.Util)

local Check = {
	id = "security",
	name = "Security",
	desc = "Hidden require by id, getfenv, loadstring",
}

local RULES = {
	{
		pattern = "()%f[%w_]require%s*%(%s*[%d]",
		severity = "Error",
		title = "Hidden require by asset id",
		text = "The script loads a module from the web by its id. Free-model backdoors use this. "
			.. "Read the module before you keep it.",
	},
	{
		pattern = "()%f[%w_]require%s*%(%s*tonumber",
		severity = "Error",
		title = "Require with a computed id",
		text = "The script builds a module id at run time to hide it. Remove the script unless you wrote it.",
	},
	{
		pattern = "()%f[%w_][gs]etfenv%s*%(",
		severity = "Warning",
		title = "getfenv or setfenv",
		text = "These change the environment of other code and turn off Luau optimizations. "
			.. "Backdoors use them to hide calls.",
	},
	{
		pattern = "()%f[%w_]loadstring%s*%(",
		severity = "Warning",
		title = "loadstring",
		text = "The script runs text as code. Make sure that the text never comes from a player or the web.",
	},
}

function Check.run(ctx)
	for index, entry in ctx.scripts do
		for _, rule in RULES do
			Util.eachMatch(entry.codeLines, rule.pattern, function(lineNumber)
				ctx.add({
					severity = rule.severity,
					title = rule.title,
					path = Util.where(entry.script, lineNumber),
					target = entry.script,
					line = lineNumber,
					text = rule.text,
				})
			end)
		end

		-- Escaped text like "\104\116\116\112" hides words from a search.
		local _, escapes = string.gsub(entry.strings, "\\%d%d?%d?", "")
		if escapes >= 40 then
			ctx.add({
				severity = "Warning",
				title = "Obfuscated text",
				path = Util.where(entry.script),
				target = entry.script,
				line = 1,
				text = string.format("The script holds %d escaped characters. Hidden text often hides a "
					.. "module id or a web address.", escapes),
			})
		end

		Util.eachMatch(entry.stringLines, "()discord[app]*%.com/api/webhooks", function(lineNumber)
			ctx.add({
				severity = "Warning",
				title = "Discord webhook address",
				path = Util.where(entry.script, lineNumber),
				target = entry.script,
				line = lineNumber,
				text = "The script sends data to a Discord webhook. A webhook address in a game leaks, "
					.. "and free models use it to send out data.",
			})
		end)

		if index % 25 == 0 then
			ctx.yield()
		end
	end
end

return Check
