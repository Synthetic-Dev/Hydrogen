local root = script.Parent
local FileHandler = require(root.FileHandler)
local ObjectReferences = require(root.ObjectReferences)

local utils = root.Parent.Parent.utils
local TableUtil = require(utils.TableUtil)

local Constructor = { }
Constructor.__index = Constructor

local defaultFormatSettings = {
	sortServices = true;
}

function Constructor.new(instance, formatSettings)
	local self = setmetatable({
		instance = instance;
		references = ObjectReferences.new(instance);

		formatSettings = TableUtil.Assign(
			defaultFormatSettings,
			formatSettings or { }
		);

		sourcesHandlers = { };
		sourceNames = {
			"Services";
			"Modules";
			"Constants";
			"Body";
		};
		currentSource = "Body";

		serviceVarNames = setmetatable({ }, { __mode = "k"; });
		services = setmetatable({ }, { __mode = "v"; });
		modules = setmetatable({ }, { __mode = "v"; });
		variables = { };
	}, Constructor)

	return self
end

function Constructor:SetCurrentSource(name)
	assert(
		table.find(self.sourceNames, name),
		"No source '" .. name .. "' within construction."
	)
	self.currentSource = name
end

function Constructor:GetCurrentSource()
	local source = self.sourcesHandlers[self.currentSource]
	if not source then
		source = FileHandler.new(self.instance, "")
		self.sourcesHandlers[self.currentSource] = source
	end
	return source
end

function Constructor:RunInSource(sourceName, callback, ...)
	local previousSource = self.currentSource
	self:SetCurrentSource(sourceName)
	callback(...)
	self:SetCurrentSource(previousSource)
end

function Constructor:Write(content, indent, lineNumber)
	local handler = self:GetCurrentSource()
	if lineNumber then
		handler:WriteLine(lineNumber, content, indent)
	else
		handler:AppendLine(content, indent)
		lineNumber = handler:GetLastLineNumber()
	end
	return lineNumber
end

function Constructor:Append(content, lineNumber, position)
	local handler = self:GetCurrentSource()
	handler:AppendToLine(lineNumber, content, position)
	return lineNumber
end

function Constructor:Insert(content, lineNumber, indent)
	local handler = self:GetCurrentSource()
	handler:InsertLine(lineNumber, content, indent)
	return lineNumber
end

function Constructor:AddVariable(varName, varValue, bypass)
	if not bypass and table.find(self.variables, varName) then
		return
	end
	table.insert(self.variables, varName)

	if varValue == nil then
		self:Write(string.format("local %s", varName))
	else
		self:Write(string.format("local %s = %s", varName, varValue))
	end
end

function Constructor:AddService(service, varName)
	if table.find(self.services, service) then
		return
	end
	table.insert(self.variables, varName or service.Name)
	table.insert(self.services, service)

	if varName then
		self.serviceVarNames[service] = varName
	end
end

function Constructor:AddModule(module, varName, globalPath)
	if table.find(self.modules, module) then
		return
	end

	varName = varName or module.Name
	table.insert(self.modules, module)

	local path, requiredService = (
		globalPath and self.references.GetGlobalPath
		or self.references.GetBestPath
	)(self.references, module)

	if requiredService then
		self:AddService(requiredService)
	end

	self:RunInSource("Modules", function()
		self:AddVariable(varName, string.format("require(%s)", path))
	end)
end

function Constructor:Build()
	self:RunInSource("Services", function()
		if self.formatSettings.sortServices then
			table.sort(self.services, function(a, b)
				return #a.Name < #b.Name
			end)
		end

		for _, service in pairs(self.services) do
			self:AddVariable(
				self.serviceVarNames[service] or service.Name,
				self.references:GetPath(game, service),
				true
			)
		end
	end)

	local source = ""
	for _, sourceName in pairs(self.sourceNames) do
		local handler = self.sourcesHandlers[sourceName]
		if not handler or #handler:GetSource() == 0 then
			continue
		end
		source ..= handler:GetSource() .. "\n"
	end

	return source
end

return Constructor
