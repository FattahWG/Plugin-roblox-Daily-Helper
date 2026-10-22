-- Live API: members and classes that the API dump of today's Studio build marks deprecated.

local Edit = require(script.Parent.Parent.Edit)
local Util = require(script.Parent.Util)

local Check = {
	id = "api",
	name = "Live API",
	desc = "Deprecated members from today's API dump",
}

-- RBXScriptSignal and RBXScriptConnection are data types, thus the dump does not list them.
local SIGNAL_RENAMES = { connect = "Connect", disconnect = "Disconnect" }

-- Lower-case names are common in game code. Only these classic Roblox names count.
local LOWER_NAMES = {
	connect = true, disconnect = true, findFirstChild = true, getChildren = true, isA = true,
	isDescendantOf = true, className = true, userId = true, localPlayer = true, children = true,
}

local MAX_GROUPS = 200

function Check.run(ctx)
	local api = ctx.api
	if not api then
		ctx.add({
			severity = "Info",
			title = "Live API check skipped",
			path = "Plugin settings",
			text = ctx.apiMessage or "The API dump did not load.",
		})
		return
	end

	local own = Util.ownNames(ctx)
	local groups = 0
	for index, entry in ctx.scripts do
		local found = {}
		local order = {}
		Util.eachMatch(entry.codeLines, "()([%.:])%s*([%a_][%w_]*)", function(lineNumber, column, accessor, name)
			local line = entry.codeLines[lineNumber]
			-- ".." joins strings, and "a .. Velocity" is not a member.
			if string.sub(line, column - 1, column - 1) == "." or own[name] then
				return
			end
			-- Enum.KeyCode.Insert is an enum item, not a member.
			if string.find(string.sub(line, 1, column - 1), "Enum%s*%.%s*[%w_]+%s*$") then
				return
			end
			local className = api.members[name]
			local rename = api.renames[name]
			if not className and accessor == ":" and SIGNAL_RENAMES[name] then
				className, rename = "RBXScriptSignal", SIGNAL_RENAMES[name]
			end
			if not className or (not string.find(name, "%u") and not LOWER_NAMES[name]) then
				return
			end
			-- A definition line names the game's own function.
			if string.find(line, "^%s*function") or string.find(line, "^%s*local%s+function") then
				return
			end
			local key = accessor .. name
			if not found[key] then
				found[key] = { accessor = accessor, name = name, className = className, rename = rename, spots = {} }
				table.insert(order, key)
			end
			local nameColumn = string.find(line, name, column, true)
			table.insert(found[key].spots, { lineNumber, nameColumn, name, rename or name })
		end)

		for _, key in order do
			if groups >= MAX_GROUPS then
				break
			end
			groups += 1
			local group = found[key]
			local spots = group.spots
			local first = spots[1][1]
			local where = Util.where(entry.script, first)
			if #spots > 1 then
				where ..= string.format("  (+%d more)", #spots - 1)
			end
			local finding = {
				severity = "Warning",
				title = string.format("Deprecated: %s%s", group.accessor, group.name),
				path = where,
				target = entry.script,
				line = first,
				text = string.format("%s.%s is deprecated in the API of Studio %s. Read its page in the "
					.. "Roblox docs for the replacement.", group.className, group.name, api.version),
			}
			if group.rename then
				finding.text = string.format("%s.%s is deprecated. Use %s%s. It does the same.",
					group.className, group.name, group.accessor, group.rename)
				finding.fix = Edit.scriptFix(entry.script, string.format("%s%s → %s%s%s", group.accessor, group.name, group.accessor, group.rename,
					if #spots > 1 then string.format(" (%d lines)", #spots) else ""), Edit.computeReplaceMany(spots))
			end
			ctx.add(finding)
		end

		Util.eachMatch(entry.stringLines, "()Instance%.new%(%s*[\"']([%w_]+)[\"']", function(lineNumber, _, className)
			if api.classes[className] then
				ctx.add({
					severity = "Warning",
					title = "Deprecated class: " .. className,
					path = Util.where(entry.script, lineNumber),
					target = entry.script,
					line = lineNumber,
					text = className .. " is deprecated in the API of Studio " .. api.version
						.. ". New features do not support it.",
				})
			end
		end)
		if index % 25 == 0 then
			ctx.yield()
		end
	end

	local byClass = {}
	for _, item in ctx.instances do
		if api.classes[item.ClassName] then
			byClass[item.ClassName] = byClass[item.ClassName] or {}
			table.insert(byClass[item.ClassName], item)
		end
	end
	for className, items in byClass do
		ctx.add({
			severity = "Info",
			title = Util.plural(#items, className .. " object") .. " (deprecated class)",
			path = "Press Select to see them",
			target = items,
			text = className .. " is deprecated in the API of Studio " .. api.version
				.. ". It still works, but replace it when you next change that part of the game.",
		})
	end
end

return Check
