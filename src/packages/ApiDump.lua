--[[
    A modified version of Elttob's ApiDump module.
]]

local packages = script.Parent
local FetchJSON = require(packages.FetchJSON)

local URL =
	"https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json"
local MAX_CACHE_TIME = (60 ^ 2) * 48

local ROOT_CLASS = "<<<ROOT>>>"

local ApiDump = { }
ApiDump.Cached = nil

function ApiDump:FetchApiDump(plugin)
	local shouldSave = plugin:GetSetting("ApiDumpSave") == true

	if shouldSave then
		local lastCached = plugin:GetSetting("ApiDumpLastCached") or 0
		if os.time() - lastCached < MAX_CACHE_TIME then
			local cached = plugin:GetSetting("ApiDumpCached")
			self.Cached = cached
			if cached then
				return true
			end
		end
	end

	local success, result, err = FetchJSON(URL)
	if not success then
		return false, result, err
	end

	self.Cached = result

	if shouldSave then
		pcall(function()
			plugin:SetSetting("ApiDumpCached", result)
			plugin:SetSetting("ApiDumpLastCached", os.time())
		end)
	end

	return true
end

local classEntryCache = { }
function ApiDump:GetClassEntry(className)
	if classEntryCache[className] then
		return classEntryCache[className]
	end

	for _, entry in pairs(self.Cached.Classes) do
		if entry.Name == className then
			classEntryCache[className] = entry
			return entry
		end
	end
end

local subclassesCache = { }
function ApiDump:GetSubclasses(className)
	if subclassesCache[className] then
		return subclassesCache[className]
	end

	local subclasses = { }
	for _, entry in pairs(self.Cached.Classes) do
		if entry.Superclass == className then
			table.insert(subclasses, entry)
		end
	end

	subclassesCache[className] = subclasses
	return subclasses
end

local membersCache = { }
function ApiDump:GetMembers(className)
	if membersCache[className] then
		return membersCache[className]
	end
	local members = { }

	local entries = { }

	do
		local currentEntry = self:GetClassEntry(className)
		while currentEntry and currentEntry.Superclass ~= ROOT_CLASS do
			table.insert(entries, 1, currentEntry)
			currentEntry = self:GetClassEntry(currentEntry.Superclass)
		end

		if currentEntry == nil then
			error("Classname '" .. className .. "' could not be found")
		end

		table.insert(entries, 1, currentEntry)
	end

	for _, entry in ipairs(entries) do
		for _, member in ipairs(entry.Members) do
			table.insert(members, member)
		end
	end

	membersCache[className] = members
	return members
end

function ApiDump:IsService(className)
	local entry = self:GetClassEntry(className)
	return table.find(entry.Tags or { }, "Service")
end

local ignoreTags = {
	ReadOnly = true;
	Deprecated = true;
	Hidden = true;
	NotScriptable = true;
}
function ApiDump:GetProperties(className)
	local members = self:GetMembers(className)

	local props = { }
	for _, member in ipairs(members) do
		if member.MemberType == "Property" then
			local canBeEditted = true
			if member.Tags then
				for _, tag in pairs(member.Tags) do
					if ignoreTags[tag] then
						canBeEditted = false
						break
					end
				end
			end

			if canBeEditted then
				table.insert(props, member.Name)
			end
		end
	end

	return props
end

return ApiDump
