-- Place tree: same-name siblings and empty folders. A second item with the same name hides
-- from FindFirstChild and WaitForChild, and the bug shows only at run time.

local Util = require(script.Parent.Util)

local Check = {
	id = "tree",
	name = "Place tree",
	desc = "Same-name siblings, empty folders",
}

-- Classes that scripts look up by name. Parts and models often share names on purpose.
local LOOKUP_CLASSES = {
	"Folder", "Configuration", "LuaSourceContainer", "RemoteEvent", "RemoteFunction",
	"UnreliableRemoteEvent", "BindableEvent", "BindableFunction", "ValueBase", "LayerCollector",
}

local function isLookup(item: Instance): boolean
	for _, className in LOOKUP_CLASSES do
		if item:IsA(className) then
			return true
		end
	end
	return false
end

local function isEmptyFolder(item: Instance): boolean
	return item.ClassName == "Folder" and #item:GetChildren() == 0 and next(item:GetAttributes()) == nil
		and #item:GetTags() == 0
end

local function remove(items: { Instance })
	for _, item in items do
		item.Parent = nil
	end
	return true
end

-- True when some script names this folder in its code or in a string ("Data", .Data,
-- :WaitForChild("Data")). Then the folder can be a target that a script fills or waits for.
local function usedByScripts(ctx, name: string): Instance?
	for _, entry in ctx.scripts do
		if string.find(entry.strings, name, 1, true) then
			local plain = string.gsub(name, "%W", "%%%0")
			if string.find(entry.strings, "%f[%w_]" .. plain .. "%f[^%w_]") then
				return entry.script
			end
		end
	end
	return nil
end

function Check.run(ctx)
	local seenParents = {}
	local empty = {}
	for index, item in ctx.instances do
		if isEmptyFolder(item) then
			table.insert(empty, item)
		end
		local parent = item.Parent
		if parent and not seenParents[parent] and isLookup(item) then
			seenParents[parent] = true
			local byName = {}
			for _, child in parent:GetChildren() do
				if isLookup(child) then
					byName[child.Name] = byName[child.Name] or {}
					table.insert(byName[child.Name], child)
				end
			end
			for name, group in byName do
				if #group > 1 then
					-- The first one wins a lookup. Empty folder copies after it can go.
					local extras = {}
					-- A name that scripts use stays: the script can wait for the copy.
					if not usedByScripts(ctx, name) then
						for i = 2, #group do
							if isEmptyFolder(group[i]) then
								table.insert(extras, group[i])
							end
						end
					end
					local finding = {
						severity = "Warning",
						title = string.format("%d items named \"%s\"", #group, name),
						path = Util.path(parent),
						target = group,
						text = "FindFirstChild and WaitForChild return only one of them, and a script can "
							.. "get the wrong one. Rename or merge them.",
					}
					if #extras > 0 then
						finding.fix = {
							label = "Remove " .. Util.plural(#extras, "empty copy", "empty copies"),
							apply = function()
								return remove(extras)
							end,
						}
					end
					ctx.add(finding)
				end
			end
		end
		if index % 2000 == 0 then
			ctx.yield()
		end
	end

	-- Keep the folders that a script names. Only the others can go.
	local unused, used = {}, 0
	for _, folder in empty do
		if usedByScripts(ctx, folder.Name) then
			used += 1
		else
			table.insert(unused, folder)
		end
	end
	empty = unused
	if used > 0 then
		ctx.add({
			severity = "Info",
			title = Util.plural(used, "empty folder is", "empty folders are") .. " named in scripts",
			path = "Kept, not offered for removal",
			text = "A script names these folders, so a script can fill them or wait for them at run time. "
				.. "Daily Helper does not offer to remove them.",
		})
	end
	if #empty > 0 then
		ctx.add({
			severity = "Info",
			title = Util.plural(#empty, "empty folder"),
			path = "Press Select to see them",
			target = empty,
			text = "Empty folders with no attributes and no tags, and no script names them. A script can still "
				.. "reach a folder by its path in other ways, so check before you remove them.",
			fix = {
				label = "Remove " .. Util.plural(#empty, "empty folder"),
				risky = true,
				apply = function()
					return remove(empty)
				end,
			},
		})
	end
end

return Check
