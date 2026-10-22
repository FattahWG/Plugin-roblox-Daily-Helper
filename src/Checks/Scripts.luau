-- Scripts: names used before their local line, deprecated globals and datatype members, and more
-- than one ProcessReceipt.

local Edit = require(script.Parent.Parent.Edit)
local Util = require(script.Parent.Util)
local DataTypes = require(script.Parent.DataTypes)
local DeclareOrder = require(script.Parent.DeclareOrder)

local Check = {
	id = "scripts",
	name = "Scripts",
	desc = "Declare order, deprecated globals and CFrame names",
}

local GLOBALS = {
	wait = { new = "task.wait", text = "Use task.wait(). It runs on the task scheduler and does not throttle." },
	delay = { new = "task.delay", text = "Use task.delay(). The old delay() waits for the next throttled step." },
	spawn = {
		new = "task.spawn",
		risky = true,
		text = "Use task.spawn() or task.defer(). task.spawn runs the function at once, and spawn() "
			.. "waited a frame first. Check the order of your code.",
	},
}

function Check.run(ctx)
	local receipts = {}
	for index, entry in ctx.scripts do
		local code = entry.code
		for name, info in GLOBALS do
			if string.find(code, "%f[%w_]" .. name .. "%s*%(") then
				-- A script that defines its own function of that name is fine.
				local own = string.find(code, "local%s+" .. name .. "%f[^%w_]")
					or string.find(code, "local%s+function%s+" .. name .. "%f[^%w_]")
					or string.find(code, "%f[%w_]function%s+" .. name .. "%f[^%w_]")
				if not own then
					local spots = {}
					Util.eachMatch(entry.codeLines, "()%f[%w_]" .. name .. "%s*%(", function(lineNumber, column)
						local before = Util.charBefore(entry.codeLines[lineNumber], column)
						if before ~= "." and before ~= ":" then
							table.insert(spots, { lineNumber, column, name, info.new })
						end
					end)
					if #spots > 0 then
						local first = spots[1][1]
						local where = Util.where(entry.script, first)
						if #spots > 1 then
							where ..= string.format("  (+%d more)", #spots - 1)
						end
						ctx.add({
							severity = "Warning",
							tag = "SCRIPTS",
							title = "Deprecated global: " .. name .. "()",
							path = where,
							target = entry.script,
							line = first,
							text = info.text,
							fix = Edit.scriptFix(entry.script, name .. "() → " .. info.new .. "()"
								.. (if #spots > 1 then string.format(" (%d lines)", #spots) else ""),
								Edit.computeReplaceMany(spots), info.risky),
						})
					end
				end
			end
		end
		DeclareOrder.run(ctx, entry)
		DataTypes.run(ctx, entry)
		if string.find(code, "ProcessReceipt%s*=") then
			table.insert(receipts, entry.script)
		end
		if index % 25 == 0 then
			ctx.yield()
		end
	end

	if #receipts > 1 then
		local names = {}
		for _, item in receipts do
			table.insert(names, item.Name)
		end
		ctx.add({
			severity = "Error",
			title = Util.plural(#receipts, "script sets", "scripts set") .. " ProcessReceipt",
			path = table.concat(names, ", "),
			target = receipts,
			text = "MarketplaceService keeps only the last ProcessReceipt. Purchases that the other scripts "
				.. "handle are lost. Keep one ProcessReceipt and route each product from it.",
		})
	end
end

return Check
