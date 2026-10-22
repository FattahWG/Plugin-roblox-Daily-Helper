-- UI and layout: draw order, text limits, fixed pixel windows, usernames on screen.

local Edit = require(script.Parent.Parent.Edit)
local Util = require(script.Parent.Util)

local Check = {
	id = "ui",
	name = "UI and layout",
	desc = "ZIndex, fixed pixels, text limits, DisplayName",
}

local NEW_SCREEN_GUI = "^(%s*)local%s+([%a_][%w_]*)%s*=%s*Instance%.new%(%s*[\"']ScreenGui[\"']%s*%)%s*;?%s*$"

function Check.run(ctx)
	-- 1. ScreenGuis in the tree that draw in Global order.
	for _, item in ctx.instances do
		if item:IsA("ScreenGui") and item.ZIndexBehavior == Enum.ZIndexBehavior.Global then
			ctx.add({
				severity = "Warning",
				title = "ScreenGui uses Global ZIndex",
				path = Util.path(item),
				target = item,
				text = "Set ZIndexBehavior to Sibling. Then a child always draws above its parent, "
					.. "and a ZIndex counts only among siblings.",
				fix = {
					label = "ZIndexBehavior → Sibling",
					apply = function()
						item.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
						return true
					end,
				},
			})
		end
	end
	ctx.yield()

	-- 2. Scripts that make a ScreenGui and never set its ZIndexBehavior. A new ScreenGui is Global.
	for _, entry in ctx.scripts do
		if string.find(entry.strings, "Instance%.new%(%s*[\"']ScreenGui[\"']") and not string.find(entry.code, "ZIndexBehavior", 1, true) then
			for lineNumber, line in entry.stringLines do
				if string.find(line, "Instance%.new%(%s*[\"']ScreenGui[\"']") then
					local indent, name = string.match(line, NEW_SCREEN_GUI)
					local finding = {
						severity = "Warning",
						title = "New ScreenGui with Global ZIndex",
						path = Util.where(entry.script, lineNumber),
						target = entry.script,
						line = lineNumber,
						text = "Instance.new(\"ScreenGui\") starts as Global. A copied window can then draw "
							.. "over its own rows. Set ZIndexBehavior to Sibling after you make it.",
					}
					if name then
						finding.fix = Edit.scriptFix(entry.script, name .. ".ZIndexBehavior = Sibling",
							Edit.computeInsertLineAfter(lineNumber, "Instance%.new",
								indent .. name .. ".ZIndexBehavior = Enum.ZIndexBehavior.Sibling"))
					end
					ctx.add(finding)
				end
			end
		end
	end
	ctx.yield()

	-- 3. Scaled text with no size limit, in one finding for the whole scope.
	local scaled, guis = {}, {}
	for _, item in ctx.instances do
		if (item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox")) and item.TextScaled
			and not item:FindFirstChildOfClass("UITextSizeConstraint") then
			table.insert(scaled, item)
			local gui = item:FindFirstAncestorWhichIsA("LayerCollector")
			if gui then
				guis[gui] = true
			end
		end
	end
	if #scaled > 0 then
		local guiCount = 0
		for _ in guis do
			guiCount += 1
		end
		ctx.add({
			severity = "Info",
			title = Util.plural(#scaled, "scaled text has", "scaled texts have") .. " no size limit",
			path = "In " .. Util.plural(guiCount, "GUI") .. ". Press Select to see them",
			target = scaled,
			text = "TextScaled with no UITextSizeConstraint grows very big on a large screen. "
				.. "Add a constraint with a MaxTextSize that fits your design.",
		})
	end
	ctx.yield()

	-- 4. Big windows with a fixed pixel size and no UIScale.
	for _, item in ctx.instances do
		if item:IsA("ScreenGui") and not item:FindFirstChildWhichIsA("UIScale", true) then
			for _, child in item:GetChildren() do
				if child:IsA("GuiObject") and child.Size.X.Scale == 0 and child.Size.Y.Scale == 0
					and child.Size.X.Offset >= 300 and child.Size.Y.Offset >= 300 then
					ctx.add({
						severity = "Info",
						title = "Window has a fixed pixel size",
						path = Util.path(child),
						target = child,
						text = string.format("%d x %d pixels is huge on a small phone and small on a big screen. "
							.. "Use Scale sizes, or add a UIScale that reads the screen size.",
							child.Size.X.Offset, child.Size.Y.Offset),
					})
				end
			end
		end
	end
	ctx.yield()

	-- 5. A username shown in a text. Players see their DisplayName everywhere else.
	for _, entry in ctx.scripts do
		for lineNumber, line in entry.codeLines do
			if string.find(line, "Text%s*=") then
				for _, pattern in { "[Pp]layer%.Name%f[^%w_]", "[Pp]lr%.Name%f[^%w_]" } do
					local at = string.find(line, pattern)
					if at then
						local column = string.find(line, ".Name", at, true)
						ctx.add({
							severity = "Info",
							title = "Username shown in a text",
							path = Util.where(entry.script, lineNumber),
							target = entry.script,
							line = lineNumber,
							text = "Players know each other by DisplayName. Show player.DisplayName, and keep "
								.. "Name or UserId only as a key.",
							fix = Edit.scriptFix(entry.script, ".Name → .DisplayName",
								Edit.computeReplaceMany({ { lineNumber, column, ".Name", ".DisplayName" } }), true),
						})
						break
					end
				end
			end
		end
	end
end

return Check
