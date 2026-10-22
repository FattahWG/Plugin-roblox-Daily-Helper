-- Reads the deprecated members and classes from the Roblox API dump of the current Studio build.
-- The full dump is large, so the plugin keeps only a small list in its settings and downloads
-- the dump again only when Roblox ships a new Studio version.

local HttpService = game:GetService("HttpService")

local ApiDump = {}

local VERSION_URL = "https://setup.rbxcdn.com/versionQTStudio"
local DUMP_URL = "https://setup.rbxcdn.com/%s-Full-API-Dump.json"
local CACHE_KEY = "ApiCache"
local CACHE_FORMAT = 1

export type Data = {
	format: number,
	version: string,
	-- Member names that are deprecated on every class that has them.
	members: { [string]: string },
	-- Case-only renames, for example clone -> Clone.
	renames: { [string]: string },
	classes: { [string]: boolean },
}

local function hasTag(item, tag: string): boolean
	for _, value in item.Tags or {} do
		if value == tag then
			return true
		end
	end
	return false
end

local function build(dump, version: string): Data
	local deprecated, live = {}, {}
	local classes = {}
	for _, class in dump.Classes do
		if hasTag(class, "Deprecated") then
			classes[class.Name] = true
		end
		for _, member in class.Members do
			if hasTag(member, "Deprecated") then
				deprecated[member.Name] = deprecated[member.Name] or class.Name
			else
				live[member.Name] = true
			end
		end
	end
	local members, renames = {}, {}
	for name, className in deprecated do
		if not live[name] then
			members[name] = className
			local upper = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
			if upper ~= name and live[upper] then
				renames[name] = upper
			end
		end
	end
	return { format = CACHE_FORMAT, version = version, members = members, renames = renames, classes = classes }
end

-- Returns data, status ("live", "cached" or "offline") and a message for the log.
function ApiDump.load(plugin: Plugin): (Data?, string, string)
	local cached = plugin:GetSetting(CACHE_KEY)
	if type(cached) ~= "table" or cached.format ~= CACHE_FORMAT then
		cached = nil
	end

	local ok, version = pcall(HttpService.GetAsync, HttpService, VERSION_URL)
	if not ok or type(version) ~= "string" or not string.match(version, "^version%-%x+$") then
		if cached then
			return cached, "cached", "API dump " .. cached.version .. " read from the cache (offline)"
		end
		return nil, "offline", "The API dump did not load. Allow HTTP for setup.rbxcdn.com and run again."
	end

	if cached and cached.version == version then
		-- The cache matches today's Studio build, thus it is as good as a new download.
		return cached, "live", "API dump " .. version .. " read from the cache (current)"
	end

	local fetched, body = pcall(HttpService.GetAsync, HttpService, string.format(DUMP_URL, version))
	if not fetched then
		if cached then
			return cached, "cached", "API dump download failed. The old cache " .. cached.version .. " is used."
		end
		return nil, "offline", "The API dump download failed: " .. tostring(body)
	end
	local decoded, dump = pcall(HttpService.JSONDecode, HttpService, body)
	if not decoded or type(dump) ~= "table" or type(dump.Classes) ~= "table" then
		return cached, if cached then "cached" else "offline", "The API dump has an unknown format."
	end
	local data = build(dump, version)
	plugin:SetSetting(CACHE_KEY, data)
	local count = 0
	for _ in data.members do
		count += 1
	end
	return data, "live", string.format("API dump %s downloaded: %d deprecated members", version, count)
end

return ApiDump
