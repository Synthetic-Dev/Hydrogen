local root = script.Parent
local packages = root.Parent
local ApiDump = require(packages.ApiDump)

local ObjectReferences = { }
ObjectReferences.__index = ObjectReferences

local function GetServiceAncestor(object)
	if object.Parent == game then
		return nil
	end

	local serviceName = string.split(object:GetFullName(), ".")[1]
	local service = game:GetService(serviceName)
	return service
end

function ObjectReferences.new(instance)
	local self = setmetatable({
		instance = instance;
	}, ObjectReferences)

	return self
end

function ObjectReferences:GetServiceAncestor()
	return GetServiceAncestor(self.instance)
end

function ObjectReferences:DoesShareServiceWith(object)
	return GetServiceAncestor(self.instance) == GetServiceAncestor(object)
end

function ObjectReferences:GetPath(start, target, varName)
	if start == game and ApiDump:IsService(target.ClassName) then
		return string.format("game:GetService(%q)", target.ClassName)
	end

	local startPath = "game." .. start:GetFullName()
	local targetPath = "game." .. target:GetFullName()

	local path = self.instance == start and "script" or (varName or start.Name)

	if target:IsDescendantOf(start) then
		return path .. string.sub(targetPath, #startPath + 1)
	end

	startPath = string.split(startPath, ".")

	local parent = start
	while not target:IsDescendantOf(parent) do
		path ..= ".Parent"
		table.remove(startPath, #startPath)
		parent = parent.Parent

		if parent == target then
			return path
		end
	end

	return path .. string.sub(targetPath, #table.concat(startPath, ".") + 1)
end

function ObjectReferences:GetBestPath(target, varName)
	local start = self.instance
	local requiredService
	if not self:DoesShareServiceWith(target) then
		requiredService = GetServiceAncestor(target)
		if requiredService then
			start = requiredService
		end
	end

	if ApiDump:IsService(target.ClassName) then
		requiredService = target
		return (varName or target.Name), requiredService
	end

	return self:GetPath(start, target, varName), requiredService
end

function ObjectReferences:GetGlobalPath(target, varName)
	local start = GetServiceAncestor(target)

	if start == target then
		return (varName or target.Name), start
	end

	return self:GetPath(start, target, varName), start
end

return ObjectReferences
