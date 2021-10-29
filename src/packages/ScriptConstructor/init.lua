local StarterGui = game:GetService("StarterGui")

local packages = script.Parent
local ApiDump = require(packages.ApiDump)
local IsGuiObject = require(packages.IsGuiObject)

local Constructor = require(script.Constructor)
local ValueToString = require(script.ValueToString)
local ObjectReferences = require(script.ObjectReferences)

local ScriptConstructor = { }

ScriptConstructor.Constructor = Constructor
ScriptConstructor.ValueToString = ValueToString

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

	local componentName = string.gsub(
		string.gsub(guiObject.Name, "[%c%z]+", ""),
		"%s+",
		"_"
	)

	if isComponent then
		constructor:Write(
			string.format("local function %s(props)", componentName)
		)
	end

	local function writeLinesForObject(object, indent, isLast)
		local isTopOfTree = object == guiObject
		local className = object.ClassName

		local startLine = constructor:Write(
			string.format("New %q {", className),
			indent
		)

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

			value = ValueToString(value, formatSettings, function(val)
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

			for index, child in pairs(validChildren) do
				writeLinesForObject(child, indent, index == #validChildren)
			end

			if isComponent and isTopOfTree then
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

		local endLine = constructor:Write(
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
		constructor:Write(string.format("\nreturn %s", componentName))
	else
		constructor:Append(
			string.format("local %s = ", componentName),
			startLine,
			"s"
		)
	end

	return constructor:Build()
end

return ScriptConstructor
