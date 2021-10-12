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
local ScriptConstructor = require(packages.ScriptConstructor)

local IsGuiObject = require(packages.IsGuiObject)
local IsLocal = root.IsLocal.Value

local utils = root.utils
local Janitor = require(utils.Janitor)
local TableUtil = require(utils.TableUtil)

local Fusion

local function log(func, ...)
	local args = { ...; }
	local str = table.remove(args, 1)
	func(
		"[Hydrogen" .. (IsLocal and " Local" or "") .. "] " .. tostring(str),
		table.unpack(args)
	)
end

local isOutdated = Updates:IsUpdateAvailable()
if isOutdated then
	warn(
		"Hydrogen is outdated!\nGet the latest version by going to Plugins > Manage Plugins > Click \"Update\" button under \"Hydrogen\"\nOR\nGet the latest release from the github page (https://github.com/Synthetic-Dev/Hydrogen/releases)!"
	)
end

if RunService:IsServer() then
	local success, result, err = ApiDump:FetchApiDump(plugin)
	if not success then
		log(
			error,
			"Unable to fetch latest ApiDump.\nError: "
				.. result
				.. "\nStack: "
				.. err
		)
	end
end

--[[
----------------------------------------------------------------------------------------------------------------------------------------
\        \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
 \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
  \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
   \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
    \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	 \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	  \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	   \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	    \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
\        \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
-----------------------------------------------------------------------------------------------------------------------------------------
]]

local janitor = Janitor.new()
local fusionJanitor = Janitor.new()

janitor:Add(fusionJanitor)

local NIL = { }
local defaultPluginSettings = {
	fusionInstance = NIL;
	output = NIL;
	formatting = {
		tableSeparator = ";";
		extraSeparator = false;
		sortServices = true;
	};
	log = {
		onSettingsChanged = false;
		onConversionStart = true;
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
local settingsName = "Hydrogen_Settings" .. (IsLocal and "_Local" or "")

local settingsNeedsSource = true

local settingsModule = settingsHolder:FindFirstChild(settingsName)
if not settingsModule or settingsModule.Source == "" then
	settingsModule = Instance.new("ModuleScript")
	settingsModule.Name = settingsName
	settingsModule.Parent = settingsHolder
else
	settingsNeedsSource = false
	local success, storedSettings = pcall(require, settingsModule:Clone())

	if success then
		local function addMissing(default, stored)
			for k, v in pairs(default) do
				if stored[k] == nil then
					settingsNeedsSource = true
					stored[k] = v
				elseif typeof(stored[k]) .. typeof(v) == "tabletable" then
					addMissing(v, stored[k])
				end
			end
		end

		addMissing(pluginSettings, storedSettings)
		pluginSettings = storedSettings
	end
end

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

local function getFusion()
	local isValid = false
	local fusion = pluginSettings.fusionInstance

	if fusion then
		if typeof(fusion) == "Instance" and fusion:IsA("ModuleScript") then
			local fusionTable
			local success, err = pcall(function()
				fusionTable = require(Fusion)
			end)

			if not success then
				log(
					warn,
					"An error occured when trying to require provided Fusion instance!\nStack: "
						.. err
				)
			end

			isValid = IsValidFusion(fusionTable)
		end

		if not isValid then
			log(warn, "Provided Fusion instance is not valid!")
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
					fusion = instance
					isValid = true
				end
			end
		end

		if not fusion then
			log(
				warn,
				"No Fusion instance was provided and Fusion could not be found!"
			)
		elseif Fusion ~= fusion then
			log(
				warn,
				"Found valid Fusion instance '" .. fusion:GetFullName() .. "'"
			)
		end
	end

	if isValid and Fusion ~= fusion then
		fusionJanitor:Cleanup()

		Fusion = fusion

		fusionJanitor:Add(fusion.AncestryChanged:Connect(function()
			if not fusion:IsDescendantOf(game) then
				log(warn, "Fusion instance was deleted")
				Fusion = nil
				getFusion()
			end
		end))
	end
end

local function onSettingsChanged(newSettings)
	if not newSettings then
		newSettings = require(settingsModule:Clone())
	end
	pluginSettings = newSettings

	getFusion()
end

local settingsSourceBeingEditted = false
local function connectOnSettingsChanged()
	local connection
	connection = settingsModule
		:GetPropertyChangedSignal("Source")
		:Connect(function()
			if settingsSourceBeingEditted then
				return
			end

			if StudioService.ActiveScript == settingsModule then
				repeat
					StudioService
						:GetPropertyChangedSignal("ActiveScript")
						:Wait()
					local activeScript = StudioService.ActiveScript
				until activeScript ~= settingsModule
			end

			-- print("Settings editted")

			local oldSettings = TableUtil.Copy(pluginSettings)
			local newSettings = require(settingsModule:Clone())

			-- print(oldSettings, newSettings)

			local changed = false
			local function checkHasChanged(old, new)
				for k, v in pairs(old) do
					local nv = new[k]

					if typeof(nv) ~= typeof(v) then
						changed = true
						return
					end

					if typeof(v) == "table" then
						checkHasChanged(v, nv)
					elseif nv ~= v then
						changed = true
					end

					if changed then
						return
					end
				end

				for k, v in pairs(new) do
					local ov = old[k]

					if typeof(ov) ~= typeof(v) then
						changed = true
						return
					end

					if typeof(v) == "table" then
						checkHasChanged(ov, v)
					elseif ov ~= v then
						changed = true
					end

					if changed then
						return
					end
				end
			end
			checkHasChanged(oldSettings, newSettings)

			if changed then
				if newSettings.log.onSettingsChanged then
					log(print, "Settings have changed")
				end

				onSettingsChanged(newSettings)
			end
		end)

	janitor:Add(connection)
	return connection
end

local function writeSettingsSource()
	settingsSourceBeingEditted = true

	local constructor = ScriptConstructor.Constructor.new(settingsModule)
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
					or ScriptConstructor:ValueToString(value)
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

	settingsSourceBeingEditted = false
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

		connectOnSettingsChanged()
		writeSettingsSource()
	end
end

if settingsNeedsSource then
	writeSettingsSource()
end
connectOnSettingsChanged()

--[[
----------------------------------------------------------------------------------------------------------------------------------------
\        \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
 \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
  \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
   \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
    \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	 \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	  \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	   \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	    \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
\        \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
-----------------------------------------------------------------------------------------------------------------------------------------
]]

local toolbar = plugin:CreateToolbar(
	"Hydrogen" .. (IsLocal and " (LOCAL)" or "")
)
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
		return log(warn, "UI cannot be converted while not in edit mode!")
	end

	if not Fusion then
		getFusion()

		if not Fusion then
			return log(warn, "No Fusion instance for conversion!")
		end
	end

	local guiObject = Selection:Get()[1]

	if not guiObject then
		return log(warn, "No object selected")
	end

	if not IsGuiObject(guiObject) then
		return log(
			warn,
			"Selected object '" .. guiObject.Name .. "' is not a 2D GuiObject"
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

	if pluginSettings.log.onConversionStart then
		log(print, "Converting '" .. guiObject.Name .. "' to Fusion")
	end

	ChangeHistoryService:SetWaypoint("Converting UI to Fusion")

	local scriptInstance = mode == "r" and Instance.new("LocalScript")
		or Instance.new("ModuleScript")
	scriptInstance.Name = guiObject.Name
	scriptInstance.Parent = output

	local success, result = pcall(function()
		return ScriptConstructor:ConstructSource(
			scriptInstance,
			guiObject,
			Fusion,
			mode,
			pluginSettings.formatting
		)
	end)

	if not success then
		log(
			error,
			"An issue occured while trying to convert '"
				.. guiObject.Name
				.. "'\nStack: "
				.. result
		)
	end

	scriptInstance.Source = result

	log(
		print,
		"Converted '" .. guiObject.Name .. "' to Fusion, showing in explorer..."
	)
	ChangeHistoryService:SetWaypoint("Converted UI to Fusion")

	Selection:Set({ scriptInstance; })
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

--[[
----------------------------------------------------------------------------------------------------------------------------------------
\        \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
 \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
  \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
   \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
    \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	 \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	  \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	   \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
	    \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
\        \        \        \        \        \        \        \        \        \        \        \        \        \        \        \
-----------------------------------------------------------------------------------------------------------------------------------------
]]

onSettingsChanged()

plugin.Unloading:Connect(function()
	log(warn, "Unloading...")
	janitor:Destroy()
end)
