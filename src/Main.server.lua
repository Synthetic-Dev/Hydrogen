local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local StudioService = game:GetService("StudioService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Studio = settings().Studio
local Theme = Studio.Theme
local isDarkMode = Theme.Name == "Dark"

local root = script.Parent

local packages = root.packages
local ApiDump = require(packages.ApiDump)
local Updates = require(packages.Updates)
local IsGuiObject = require(packages.IsGuiObject)
local ModuleConstructor = require(packages.ModuleConstructor)

local utils = root.utils
local Janitor = require(utils.Janitor)
local TableUtil = require(utils.TableUtil)

local Fusion

local isOutdated = Updates:IsUpdateAvailable()
if isOutdated then
	warn(
		"Hydrogen is outdated!\nGet the latest version by going to Plugins > Manage Plugins > Click \"Update\" button under \"Hydrogen\"\nOR\nGet the latest release from the github page (https://github.com/Synthetic-Dev/Hydrogen/releases)!"
	)
end

if RunService:IsServer() then
	local success, result, err = ApiDump:FetchApiDump(plugin)
	if not success then
		error(
			"[Hydrogen] Unable to fetch latest ApiDump.\nError: "
				.. result
				.. "\nStack: "
				.. err
		)
	end
end

local janitor = Janitor.new()

local NIL = { }
local defaultPluginSettings = {
	fusionInstance = NIL;
	output = NIL;
	formatting = {
		tableSeparator = ";";
		extraSeparator = false;
	};
}

local function GetDefaultPluginSettings()
	local _settings = TableUtil.Copy(defaultPluginSettings)
	_settings.fusionInstance = NIL
	_settings.output = NIL

	return _settings
end

local pluginSettings = GetDefaultPluginSettings()

local settingsHolder = game:GetService("AnalyticsService")
local settingsName = "Hydrogen_Settings"

local settingsNeedsSource = true

local settingsModule = settingsHolder:FindFirstChild(settingsName)
if not settingsModule then
	settingsModule = Instance.new("ModuleScript")
	settingsModule.Name = settingsName
	settingsModule.Parent = settingsHolder
else
	settingsNeedsSource = false
	local storedSettings = require(settingsModule)

	local function addMissing(default, stored)
		for k, v in pairs(default) do
			if not stored[k] then
				settingsNeedsSource = true
				stored[k] = v
			elseif typeof(stored[k]) .. typeof(v) == "tabletable" then
				addMissing(v, stored[k])
			end
		end
	end

	addMissing(pluginSettings, storedSettings)
	pluginSettings = storedSettings

	if settingsNeedsSource then
		settingsModule:Destroy()

		settingsModule = Instance.new("ModuleScript")
		settingsModule.Name = settingsName
		settingsModule.Parent = settingsHolder
	end
end

local function connectOnSettingsChanged()
	local connection
	connection = settingsModule
		:GetPropertyChangedSignal("Source")
		:Connect(function()
			connection:Disconnect()

			if StudioService.ActiveScript == settingsModule then
				repeat
					StudioService
						:GetPropertyChangedSignal("ActiveScript")
						:Wait()
					local activeScript = StudioService.ActiveScript
				until activeScript ~= settingsModule
			end

			local source = settingsModule.Source
			settingsModule:Destroy()

			settingsModule = Instance.new("ModuleScript")
			settingsModule.Name = settingsName
			settingsModule.Source = source
			settingsModule.Parent = settingsHolder

			pluginSettings = require(settingsModule)

			janitor:Add(connectOnSettingsChanged())
		end)

	return connection
end

janitor:Add(connectOnSettingsChanged())

local function writeSettingsSource()
	local constructor = ModuleConstructor.Constructor.new(settingsModule)
	constructor:Write(
		"-- Save and close this script in order to apply settings"
	)
	constructor:Write("")
	constructor:Write("return {")

	local function writeKVs(t, indent)
		for key, value in pairs(t) do
			if typeof(value) == "table" and value ~= NIL then
				constructor:Write(string.format("%s = {", key), indent)
				writeKVs(value, indent + 1)
				constructor:Write("};", indent)
			else
				value = value == NIL and "nil"
					or ModuleConstructor:ValueToString(value)
				constructor:Write(
					string.format("%s = %s;", key, value)
						.. (
							(
								key == "fusionInstance"
								and " -- Add reference to Fusion instance here, if not provided the plugin will try to find the Fusion instance"
							)
							or (key == "output" and " -- In the future you will select where components are placed via UI, however, the folder reference goes here for now")
							or ""
						),
					indent
				)
			end
		end
	end

	writeKVs(pluginSettings, 1)

	constructor:Write("}")

	settingsModule.Source = constructor:Build()
end

if settingsNeedsSource then
	writeSettingsSource()
end

local toolbar = plugin:CreateToolbar("Hydrogen")
janitor:Add(toolbar)

local themeChangeFuncs = { }
local function OnThemeChange(func)
	table.insert(themeChangeFuncs, func)
end

janitor:Add(Studio.ThemeChanged:Connect(function()
	Theme = Studio.Theme
	isDarkMode = Theme.Name == "Dark"

	for _, func in pairs(themeChangeFuncs) do
		func()
	end
end))

local convertToRaw = toolbar:CreateButton(
	"Convert to Raw",
	"Convert the ui into a script containing the Fusion tree.",
	isDarkMode and "rbxassetid://7701675844" or "rbxassetid://7701675842"
)
OnThemeChange(function()
	convertToRaw.Icon = isDarkMode and "rbxassetid://7701675844"
		or "rbxassetid://7701675842"
end)

local convertToComponent = toolbar:CreateButton(
	"Convert to Component",
	"Convert the ui into a modulescript that returns a Fusion component.",
	isDarkMode and "rbxassetid://7701675841" or "rbxassetid://7701675862"
)
OnThemeChange(function()
	convertToComponent.Icon = isDarkMode and "rbxassetid://7701675841"
		or "rbxassetid://7701675862"
end)

local settingsButton = toolbar:CreateButton(
	"Settings",
	"Open settings.",
	isDarkMode and "rbxassetid://7704843199" or "rbxassetid://7704843209"
)
OnThemeChange(function()
	settingsButton.Icon = isDarkMode and "rbxassetid://7704843199"
		or "rbxassetid://7704843209"
end)

convertToRaw.ClickableWhenViewportHidden = true
convertToComponent.ClickableWhenViewportHidden = true
settingsButton.ClickableWhenViewportHidden = true

local function Convert(mode)
	if not RunService:IsEdit() then
		return warn("[Hydrogen] UI cannot be converted while not in edit mode!")
	end

	if not Fusion then
		error("[Hydrogen] No Fusion instance!")
	end

	local guiObject = Selection:Get()[1]

	if not guiObject then
		return warn("[Hydrogen] No object selected")
	end

	if not IsGuiObject(guiObject) then
		return warn(
			"[Hydrogen] Selected object '"
				.. guiObject.Name
				.. "' is not a 2D GuiObject"
		)
	end

	local output = pluginSettings.output
	if not output then
		local folder = ReplicatedStorage:FindFirstChild("Hydrogen/out")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Hydrogen/out"
			folder.Parent = ReplicatedStorage
		end
		output = folder
	end

	ChangeHistoryService:SetEnabled(true)

	print("[Hydrogen] Converting '" .. guiObject.Name .. "' to Fusion")
	ChangeHistoryService:SetWaypoint("Converting UI to Fusion")

	local scriptInstance = mode == "r" and Instance.new("LocalScript")
		or Instance.new("ModuleScript")
	scriptInstance.Name = guiObject.Name
	scriptInstance.Parent = output

	local source = ModuleConstructor:ConstructSource(
		scriptInstance,
		guiObject,
		Fusion,
		mode,
		pluginSettings.formatting
	)
	scriptInstance.Source = source

	print(
		"[Hydrogen] Converted '"
			.. guiObject.Name
			.. "' to Fusion, showing in explorer..."
	)
	ChangeHistoryService:SetWaypoint("Converted UI to Fusion")

	Selection:Set({ scriptInstance; })
end

local function assureSettings()
	if settingsModule.Parent == nil then
		pluginSettings = GetDefaultPluginSettings()
		settingsModule = nil
	end

	if not settingsModule then
		settingsModule = Instance.new("ModuleScript")
		settingsModule.Name = settingsName
		settingsModule.Parent = settingsHolder

		janitor:Add(connectOnSettingsChanged())

		writeSettingsSource()
	end
end

convertToRaw.Click:Connect(function()
	assureSettings()
	Convert("r")
	task.delay(0.1, convertToRaw.SetActive, convertToRaw, false)
end)

convertToComponent.Click:Connect(function()
	assureSettings()
	Convert("c")
	task.delay(0.1, convertToComponent.SetActive, convertToComponent, false)
end)

settingsButton.Click:Connect(function()
	assureSettings()

	if settingsModule then
		plugin:OpenScript(settingsModule)
	end
end)

local function IsValidFusion(t)
	local isValid = false

	if typeof(t) == "table" then
		local invalid = false
		for _, k in pairs({
			"New";
			"Children";
			"OnEvent";
			"OnChange";
			"State";
			"Computed";
		}) do
			if not t[k] then
				invalid = true
				break
			end
		end

		if not invalid then
			isValid = true
		end
	end

	return isValid
end

Fusion = pluginSettings.fusionInstance
if Fusion then
	local isValid = false
	if typeof(Fusion) == "Instance" and Fusion:IsA("ModuleScript") then
		local fusionTable
		local success, err = pcall(function()
			fusionTable = require(Fusion)
		end)

		if not success then
			error(
				"[Hydrogen] An error occured when trying to require provided Fusion instance!\nStack: "
					.. err
			)
		end

		isValid = IsValidFusion(fusionTable)
	end

	if not isValid then
		error("[Hydrogen] Provided Fusion instance is not valid!")
	end
else
	local placesToFindFusion = {
		ReplicatedStorage;
		game:GetService("ReplicatedFirst");
		game:GetService("ServerScriptService");
		game:GetService("ServerStorage");
	}

	for _, place in pairs(placesToFindFusion) do
		local instance = place:FindFirstChild("Fusion")
		if instance and instance:IsA("ModuleScript") then
			local fusionTable
			local success = pcall(function()
				fusionTable = require(instance)
			end)

			if success and IsValidFusion(fusionTable) then
				Fusion = instance
			end
		end
	end

	if not Fusion then
		error(
			"[Hydrogen] No Fusion instance was provided and Fusion could not be found!"
		)
	else
		warn(
			"[Hydrogen] Found valid Fusion instance '"
				.. Fusion:GetFullName()
				.. "'"
		)
	end
end

plugin.Unloading:Connect(function()
	warn("[Hydrogen] Unloading...")
	janitor:Destroy()
end)
