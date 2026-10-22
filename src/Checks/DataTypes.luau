-- Old datatype members (CFrame, Vector3, Vector2, Color3). Studio's Script Analysis marks them in
-- orange, but the API dump lists classes only, so these come from a fixed list. Roblox renamed them
-- years ago and keeps the old names working, so the list does not change.
-- The plugin cannot know the type of a value, so each rule also tests the text before the dot.

local Edit = require(script.Parent.Parent.Edit)
local Util = require(script.Parent.Util)

local DataTypes = {}

-- Text before ".p" or ".lookVector" that names a CFrame.
local CFRAME_BEFORE = {
	"[Cc][Ff][Rr][Aa][Mm][Ee]%s*$", -- part.CFrame, cframe, myCFrame
	"CoordinateFrame%s*$",
	"Focus%s*$",
	"%f[%w_][Cc][Ff]%d*%s*$", -- cf, CF, cf2
	"GetPivot%(%)%s*$",
	"[Cc][01]%s*$", -- weld.C0, weld.C1
}

local PROPERTIES = {
	p = { new = "Position", cframe = true },
	lookVector = { new = "LookVector", cframe = true },
	rightVector = { new = "RightVector", cframe = true },
	upVector = { new = "UpVector", cframe = true },
	unit = { new = "Unit" },
	magnitude = { new = "Magnitude" },
}

local METHODS = {
	inverse = "Inverse", lerp = "Lerp", toWorldSpace = "ToWorldSpace", toObjectSpace = "ToObjectSpace",
	pointToWorldSpace = "PointToWorldSpace", pointToObjectSpace = "PointToObjectSpace",
	vectorToWorldSpace = "VectorToWorldSpace", vectorToObjectSpace = "VectorToObjectSpace",
	components = "GetComponents", toEulerAnglesXYZ = "ToEulerAnglesXYZ", toAxisAngle = "ToAxisAngle",
}

local function namesCFrame(before: string): boolean
	for _, pattern in CFRAME_BEFORE do
		if string.find(before, pattern) then
			return true
		end
	end
	return false
end

-- The number of top-level commas inside the brackets that open at `open`, or nil when the
-- closing bracket is on another line.
local function topLevelCommas(line: string, open: number): number?
	local depth, commas = 0, 0
	for index = open, #line do
		local char = string.sub(line, index, index)
		if char == "(" or char == "{" or char == "[" then
			depth += 1
		elseif char == ")" or char == "}" or char == "]" then
			depth -= 1
			if depth == 0 then
				return commas
			end
		elseif char == "," and depth == 1 then
			commas += 1
		end
	end
	return nil
end

-- Field names that some script assigns: "config.unit = ...". Datatype properties are read-only,
-- so an assigned name belongs to a game table.
local function assignedFields(ctx): { [string]: boolean }
	if ctx.assignedFields then
		return ctx.assignedFields
	end
	local names = {}
	for _, entry in ctx.scripts do
		for name in string.gmatch(entry.code, "%.([%a_][%w_]*)%s*=[^=]") do
			names[name] = true
		end
	end
	ctx.assignedFields = names
	return names
end

-- Adds one finding per old name per script.
function DataTypes.run(ctx, entry)
	local own = Util.ownNames(ctx)
	local assigned = assignedFields(ctx)
	local groups, order = {}, {}
	local function add(key, title, text, label, spot)
		if not groups[key] then
			groups[key] = { title = title, text = text, label = label, spots = {} }
			table.insert(order, key)
		end
		table.insert(groups[key].spots, spot)
	end

	for lineNumber, line in entry.codeLines do
		-- Properties: ".name" that is not a call.
		for column, name in string.gmatch(line, "()%.([%a_][%w_]*)") do
			local rule = PROPERTIES[name]
			local after = string.sub(line, column + 1 + #name)
			if rule and string.sub(line, column - 1, column - 1) ~= "." and not string.find(after, "^%s*%(") then
				local before = string.sub(line, 1, column - 1)
				local ok = if rule.cframe then namesCFrame(before) else not (own[name] or assigned[name])
				if ok then
					add("." .. name, "Deprecated: ." .. name,
						string.format(".%s is the old name. Use .%s. It gives the same value.", name, rule.new),
						string.format(".%s → .%s", name, rule.new), { lineNumber, column + 1, name, rule.new })
				end
			end
		end
		-- Methods: ":name(".
		for column, name in string.gmatch(line, "():([%a_][%w_]*)%s*%(") do
			local new = METHODS[name]
			if new and not own[name] then
				add(":" .. name, "Deprecated: :" .. name .. "()",
					string.format(":%s() is the old name. Use :%s(). It does the same.", name, new),
					string.format(":%s() → :%s()", name, new), { lineNumber, column + 1, name, new })
			end
		end
		-- CFrame.new(position, lookAt) with two values is CFrame.lookAt.
		for column in string.gmatch(line, "()%f[%w_]CFrame%.new%s*%(") do
			local open = string.find(line, "(", column, true) :: number
			if topLevelCommas(line, open) == 1 then
				add("CFrame.new2", "Deprecated: CFrame.new(pos, lookAt)",
					"CFrame.new with two positions is the old form. CFrame.lookAt takes the same two values.",
					"CFrame.new(a, b) → CFrame.lookAt(a, b)", { lineNumber, column + 7, "new", "lookAt" })
			end
		end
	end

	for _, key in order do
		local group = groups[key]
		local spots = group.spots
		local first = spots[1][1]
		local where = Util.where(entry.script, first)
		if #spots > 1 then
			where ..= string.format("  (+%d more)", #spots - 1)
		end
		local label = group.label
		ctx.add({
			severity = "Warning",
			tag = "SCRIPTS",
			title = group.title,
			path = where,
			target = entry.script,
			line = first,
			text = group.text,
			fix = Edit.scriptFix(entry.script, label .. (if #spots > 1 then string.format(" (%d lines)", #spots) else ""),
				Edit.computeReplaceMany(spots)),
		})
	end
end

return DataTypes
