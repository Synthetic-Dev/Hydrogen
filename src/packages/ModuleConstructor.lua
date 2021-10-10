local StarterGui = game:GetService("StarterGui")

local packages = script.Parent
local ApiDump = require(packages.ApiDump)
local IsGuiObject = require(packages.IsGuiObject)

local ModuleConstructor = { }

local function AddTrailingNewLine(str)
	if string.sub(str, -1, -1) ~= "\n" then
		str ..= "\n"
	end
	return str
end

local function RemoveTrailingNewLine(str)
	if string.sub(str, -1, -1) == "\n" then
		return string.sub(str, 1, -2)
	end
	return str
end

local function GetLine(source, line)
	source = AddTrailingNewLine(source)

	local contentBefore, contentAfter, contentAt = "", "", ""
	local counter = 1
	for aLine in string.gmatch(source, ".-\n") do
		if counter < line then
			contentBefore ..= aLine
		elseif counter > line then
			contentAfter ..= aLine
		else
			contentAt = aLine
		end

		counter += 1
	end

	return contentAt, contentBefore, contentAfter
end

local function GetLastLineNum(source)
	return select(2, string.gsub(source, ".-\n", ""))
end

function ModuleConstructor:WriteLine(source, line, content, indent)
	indent = indent or 0
	line = line or 1

	local _, contentBefore, contentAfter = GetLine(source, line)
	contentBefore = AddTrailingNewLine(contentBefore)

	source = contentBefore
		.. (string.rep("\t", indent) .. content .. "\n")
		.. contentAfter
	return source
end

function ModuleConstructor:InsertLine(source, line, content, indent)
	indent = indent or 0
	line = line or GetLastLineNum(source)

	local contentAt, contentBefore, contentAfter = GetLine(source, line)

	return contentBefore
		.. (string.rep("\t", indent) .. content .. "\n")
		.. contentAt
		.. contentAfter
end

function ModuleConstructor:AppendToLine(source, line, content, position)
	line = line or 1
	position = position or "e"

	local contentAt, contentBefore, contentAfter = GetLine(source, line)
	contentAt = RemoveTrailingNewLine(contentAt)

	if position == "e" then
		contentAt ..= content
	elseif position == "s" then
		local raw, indents = string.gsub(contentAt, "\t", "")
		contentAt = string.rep("\t", indents) .. content .. raw
	end

	source = contentBefore .. AddTrailingNewLine(contentAt) .. contentAfter
	return source
end

function ModuleConstructor:AppendLine(source, content, indent)
	indent = indent or 0

	if #source > 0 then
		source = AddTrailingNewLine(source)
	end

	source ..= string.rep("\t", indent) .. content .. "\n"
	return source
end

local function GetServiceAncestor(object)
	if object.Parent == game then
		return nil
	end

	local serviceName = string.split(object:GetFullName(), ".")[1]
	local service = game:GetService(serviceName)
	return service
end

local function AreUnderSameService(object1, object2)
	return GetServiceAncestor(object1) == GetServiceAncestor(object2)
end

local function GetPath(start, target, _script, varName)
	if start == game and ApiDump:IsService(target.ClassName) then
		return string.format("game:GetService(\"%s\")", target.ClassName)
	end

	local startPath = "game." .. start:GetFullName()
	local targetPath = "game." .. target:GetFullName()

	local path = _script == start and "script" or (varName or start.Name)

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

local function GetBestPath(_script, target, varName)
	local start = _script
	local requiredService
	if not AreUnderSameService(start, target) then
		requiredService = GetServiceAncestor(target)
		if requiredService then
			start = requiredService
		end
	end

	if ApiDump:IsService(target.ClassName) then
		requiredService = target
		return (varName or target.Name), requiredService
	end

	return GetPath(start, target, _script, varName), requiredService
end

function ModuleConstructor:RequireModule(_script, module, varName)
	varName = varName or module.Name

	local path, requiredService = GetBestPath(_script, module)

	return string.format("local %s = require(%s)", varName, path),
		requiredService
end

local function trimNumber(num)
	return math.round(num * 1e4) / 1e4
end

function ModuleConstructor:ValueToString(value, instanceHandler)
	local typeOf = typeof(value)
	if type(value) == "userdata" and typeOf ~= "EnumItem" then
		if typeOf == "UDim2" then
			local xOffset = trimNumber(value.X.Offset)
			local xScale = trimNumber(value.X.Scale)
			local yOffset = trimNumber(value.Y.Offset)
			local yScale = trimNumber(value.Y.Scale)

			if
				(xOffset == 0 and yOffset == 0)
				and (math.abs(xScale) > 0 or math.abs(yScale) > 0)
			then
				value = string.format("UDim2.fromScale(%s, %s)", xScale, yScale)
			elseif
				(xScale == 0 and yScale == 0)
				and (math.abs(xOffset) > 0 or math.abs(xOffset) > 0)
			then
				value = string.format(
					"UDim2.fromOffset(%s, %s)",
					xOffset,
					yOffset
				)
			else
				value = string.format(
					"UDim2.new(%s, %s, %s, %s)",
					xScale,
					xOffset,
					yScale,
					yOffset
				)
			end
		elseif typeOf == "Color3" then
			local r = math.round(value.R * 255)
			local g = math.round(value.G * 255)
			local b = math.round(value.B * 255)

			if r + g + b == 0 then
				value = "Color3.new()"
			elseif r + g + b == 255 * 3 then
				value = "Color3.new(1, 1, 1)"
			else
				value = string.format("Color3.fromRGB(%s, %s, %s)", r, g, b)
			end
		elseif typeOf == "Instance" then
			if instanceHandler then
				value = instanceHandler(value)
			else
				value = GetPath(game, value, script)
			end
		else
			local values = string.split(tostring(value), ", ")

			for index, val in pairs(values) do
				if tonumber(val) then
					values[index] = tostring(trimNumber(tonumber(val)))
				end
			end

			value = string.format(
				"%s.new(%s)",
				typeOf,
				table.concat(values, ", ")
			)
		end
	elseif typeOf == "string" then
		value = string.format("\"%s\"", value)
	elseif typeOf == "number" then
		value = trimNumber(value)
	end

	return tostring(value)
end

local Constructor = { }
do
	Constructor.__index = Constructor

	function Constructor.new(instance)
		local self = setmetatable({
			instance = instance;

			sources = { };
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

	function Constructor:GetSource()
		local source = self.sources[self.currentSource]
		if not source then
			source = ""
			self.sources[self.currentSource] = source
		end

		return source
	end

	function Constructor:SetSource(content)
		self.sources[self.currentSource] = content
	end

	function Constructor:RunInSource(source, callback, ...)
		local previousSource = self.currentSource
		self:SetCurrentSource(source)
		callback(...)
		self:SetCurrentSource(previousSource)
	end

	function Constructor:Write(content, indent, line)
		local source = self:GetSource()
		if line then
			source = ModuleConstructor:WriteLine(source, line, content, indent)
		else
			source = ModuleConstructor:AppendLine(source, content, indent)
			line = GetLastLineNum(source)
		end
		self:SetSource(source)

		return line
	end

	function Constructor:Append(content, line, position)
		local source = self:GetSource()
		source = ModuleConstructor:AppendToLine(source, line, content, position)
		self:SetSource(source)

		return line
	end

	function Constructor:Insert(content, line, indent)
		local source = self:GetSource()
		source = ModuleConstructor:InsertLine(source, line, content, indent)
		self:SetSource(source)

		return line
	end

	function Constructor:AddVariable(varName, varValue)
		if table.find(self.variables, varName) then
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
		table.insert(self.variables, varName)
		table.insert(self.services, service)

		if varName then
			self.serviceVarNames[service] = varName
		end
	end

	function Constructor:AddModule(module, varName)
		if table.find(self.modules, module) then
			return
		end
		table.insert(self.variables, varName)
		table.insert(self.modules, module)

		local content, requiredService = ModuleConstructor:RequireModule(
			self.instance,
			module,
			varName
		)
		if requiredService then
			self:AddService(requiredService)
		end

		self:RunInSource("Modules", self.Write, self, content)
	end

	function Constructor:Build()
		self:RunInSource("Services", function()
			table.sort(self.services, function(a, b)
				return #a.Name < #b.Name
			end)

			for _, service in pairs(self.services) do
				self:AddVariable(
					self.serviceVarNames[service] or service.Name,
					GetPath(game, service)
				)
			end
		end)

		local source = ""

		for _, sourceName in pairs(self.sourceNames) do
			local subSource = self.sources[sourceName]
			if not subSource or #subSource == 0 then
				continue
			end
			source ..= subSource .. "\n"
		end

		return source
	end
end

ModuleConstructor.Constructor = Constructor

local ignoreProperty = { }
do
	local function textObject(object, property)
		if property == "TextSize" or property == "TextWrapped" then
			return object.TextScaled
		end
		return false
	end

	ignoreProperty.TextLabel = textObject
	ignoreProperty.TextButton = textObject
	ignoreProperty.TextBox = textObject
end

local defaultObjectCache = { }
function ModuleConstructor:ConstructSource(
	_script,
	guiObject,
	fusion,
	contructType,
	formatSettings
)
	contructType = contructType or "r"
	local isComponent = contructType == "c"

	local constructor = Constructor.new(_script)

	constructor:SetCurrentSource("Modules")

	constructor:AddModule(fusion, "Fusion")
	constructor:AddVariable("New", "Fusion.New")
	constructor:AddVariable("Children", "Fusion.Children")

	constructor:SetCurrentSource("Body")

	if isComponent then
		constructor:Write(
			string.format("local function %s(props)", guiObject.Name)
		)
	end

	local function writeLinesForObject(object, indent, siblings, isLast)
		siblings = siblings or { }

		local isTopOfTree = object == guiObject
		local className = object.ClassName

		local startLine, endLine
		if isTopOfTree then
			startLine = constructor:Write(
				string.format("New \"%s\" {", className),
				indent
			)
		else
			local name = object.Name

			local counter = 1
			while table.find(siblings, name) do
				name = string.format("%s_%d", object.Name, counter)
				counter += 1
			end

			table.insert(siblings, name)

			startLine = constructor:Write(
				string.format("%s = New \"%s\" {", name, className),
				indent
			)
		end

		indent += 1

		local properties = ApiDump:GetProperties(className)

		local defaultObject = defaultObjectCache[className]
		if not defaultObject then
			defaultObject = Instance.new(className)
			defaultObjectCache[className] = defaultObject
		end

		local shouldIgnoreProperty = ignoreProperty[className]

		local propertiesToChange = { }
		for _, property in pairs(properties) do
			if property == "Name" then
				continue
			end
			if (not isTopOfTree or isComponent) and property == "Parent" then
				continue
			end

			local value = object[property]

			if value ~= nil and value ~= defaultObject[property] then
				if
					shouldIgnoreProperty
					and shouldIgnoreProperty(object, property)
				then
					continue
				end

				table.insert(propertiesToChange, property)
			end
		end

		local children = object:GetChildren()
		local validChildren = { }

		if #children > 0 then
			for _, child in pairs(children) do
				if IsGuiObject(child) then
					table.insert(validChildren, child)
				end
			end
		end

		for index, property in pairs(propertiesToChange) do
			local value = object[property]

			value = self:ValueToString(value, function(val)
				if property == "Parent" and val == StarterGui then
					constructor:AddService(game:GetService("Players"))

					constructor:RunInSource("Constants", function()
						constructor:AddVariable("Player", "Players.LocalPlayer")
						constructor:AddVariable("PlayerGui", "Player.PlayerGui")
					end)

					val = "PlayerGui"
				else
					local path, requiredService = GetBestPath(_script, val)
					if requiredService then
						constructor:AddService(requiredService)
					end

					val = path
				end

				return val
			end)

			constructor:Write(
				string.format(
					"%s = %s"
						.. (
							(
									index == #propertiesToChange
									and not formatSettings.extraSeparator
									and #validChildren == 0
								)
								and ""
							or formatSettings.tableSeparator
						),
					property,
					value
				),
				indent
			)
		end

		if #validChildren > 0 then
			constructor:Write("", indent)
			constructor:Write("[Children] = {", indent)
			indent += 1

			local childrenSiblings = { }

			for index, child in pairs(validChildren) do
				writeLinesForObject(
					child,
					indent,
					childrenSiblings,
					index == #validChildren
				)
			end

			if isComponent then
				constructor:Write("", indent)
				constructor:Write("props[Children]", indent)
			end

			indent -= 1

			constructor:Write(
				"}"
					.. (
						formatSettings.extraSeparator
							and formatSettings.tableSeparator
						or ""
					),
				indent
			)
		end

		indent -= 1

		endLine = constructor:Write(
			"}"
				.. (
					(
							isTopOfTree
							or (
								isLast
								and not formatSettings.extraSeparator
								and not isComponent
							)
						)
						and ""
					or formatSettings.tableSeparator
				),
			indent
		)

		return startLine, endLine
	end

	local startLine = writeLinesForObject(guiObject, isComponent and 1 or 0)

	if isComponent then
		constructor:Append("return ", startLine, "s")
		constructor:Write("end")
		constructor:Write(string.format("\nreturn %s", guiObject.Name))
	else
		constructor:Append(
			string.format("local %s = ", guiObject.Name),
			startLine,
			"s"
		)
	end

	return constructor:Build()
end

return ModuleConstructor
