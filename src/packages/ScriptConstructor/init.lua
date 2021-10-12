local StarterGui = game:GetService("StarterGui")

local packages = script.Parent
local ApiDump = require(packages.ApiDump)
local IsGuiObject = require(packages.IsGuiObject)

local Constructor = require(script.Constructor)
local ObjectReferences = require(script.ObjectReferences)

local ScriptConstructor = { }

ScriptConstructor.Constructor = Constructor

local function trimNumber(num)
	return math.round(num * 1e4) / 1e4
end

function ScriptConstructor:ValueToString(value, instanceHandler)
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
				value = ObjectReferences.new(value):GetPath(game, value)
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
		value = string.format("%q", value)
	elseif typeOf == "number" then
		value = trimNumber(value)
	end

	return tostring(value)
end

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
function ScriptConstructor:ConstructSource(
	scriptInstance,
	guiObject,
	fusion,
	contructType,
	formatSettings
)
	contructType = contructType or "r"
	local isComponent = contructType == "c"

	local scriptReferences = ObjectReferences.new(scriptInstance)
	local constructor = Constructor.new(scriptInstance, {
		sortServices = formatSettings.sortServices;
	})

	constructor:SetCurrentSource("Modules")

	constructor:AddModule(fusion, "Fusion", true)
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
				string.format("New %q {", className),
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
				string.format("%s = New %q {", name, className),
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
			if
				(
					not isTopOfTree
					or isComponent
					or not object:IsA("LayerCollector")
				) and property == "Parent"
			then
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
					local path, requiredService = scriptReferences:GetBestPath(
						val
					)
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

return ScriptConstructor
