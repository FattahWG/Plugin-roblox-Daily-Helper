-- The Log tab store. Entries stay in the plugin settings for each place, never in the place.

local Log = {}
Log.__index = Log

local MAX_ENTRIES = 300

export type Entry = { time: number, kind: string, text: string }

local function placeKey(): string
	if game.PlaceId ~= 0 then
		return "Log_" .. game.PlaceId
	end
	return "Log_local_" .. game.Name
end

function Log.new(plugin: Plugin)
	local self = setmetatable({}, Log)
	self.plugin = plugin
	self.key = placeKey()
	local saved = plugin:GetSetting(self.key)
	self.entries = if type(saved) == "table" then saved else {}
	self.changed = Instance.new("BindableEvent")
	return self
end

function Log:add(kind: string, text: string)
	table.insert(self.entries, { time = os.time(), kind = kind, text = text })
	while #self.entries > MAX_ENTRIES do
		table.remove(self.entries, 1)
	end
	self.plugin:SetSetting(self.key, self.entries)
	self.changed:Fire()
end

function Log:clear()
	table.clear(self.entries)
	self.plugin:SetSetting(self.key, self.entries)
	self.changed:Fire()
end

-- os.date in Roblox gives only tables, thus the clock text is built by hand.
function Log.clock(time: number): string
	local parts = os.date("*t", time)
	return string.format("%02d:%02d:%02d", parts.hour, parts.min, parts.sec)
end

function Log.day(time: number): string
	local parts = os.date("*t", time)
	local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
	return string.format("%d %s, %02d:%02d", parts.day, months[parts.month], parts.hour, parts.min)
end

function Log:text(): string
	local lines = {}
	for _, entry in self.entries do
		table.insert(lines, string.format("%s  [%s]  %s", Log.clock(entry.time), entry.kind, entry.text))
	end
	return table.concat(lines, "\n")
end

return Log
