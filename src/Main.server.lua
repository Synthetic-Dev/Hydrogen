local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local root = script.Parent

local packages = root.packages
local ApiDump = require(packages.ApiDump)
local Updates = require(packages.Updates)
local SettingsManager = require(packages.SettingsManager)
local ScriptConstructor = require(packages.ScriptConstructor)

local PluginBar = require(packages.PluginBar)

local IsGuiObject = require(packages.IsGuiObject)
local IsLocal = root.IsLocal.Value

local utils = root.utils
local Janitor = require(utils.Janitor)

local Fusion

local function log(func, ...)
	local args = { ...; }
	local str = table.remove(args, 1)

	if func == error then
		args[1] = args[1] and args[1] + 1 or 2
	end

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
elseif IsLocal then
	local current = Updates:GetVersion()
	local github = Updates:GetCachedLatestVersion()

	if Updates:GetVersionNumber(current) > Updates:GetVersionNumber(github) then
		log(print, "Plugin is running future version.")
	end
end

do
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

local pluginSettings = SettingsManager.new(
	"Hydrogen_Settings" .. (IsLocal and "_Local" or ""),
	game:GetService("AnalyticsService"),
	{
		fusionInstance = SettingsManager.Null;
		output = SettingsManager.Null;
		formatting = {
			tableSeparator = ";";
			extraSeparator = false;
			sortServices = true;
		};
		log = {
			onSettingsChanged = false;
			onConversionStart = true;
		};
	},
	{
		fusionInstance = "Add reference to Fusion instance here, if not provided the plugin will try to find the Fusion instance";
		output = "In the future you will select where components are placed via UI, however, the folder reference goes here for now";
	}
)

janitor:Add(pluginSettings)

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
	local settings = pluginSettings:GetSettings()

	local isValid = false
	local fusion = settings.fusionInstance

	if fusion then
		if typeof(fusion) == "Instance" and fusion:IsA("ModuleScript") then
			local fusionTable
			local success, err = pcall(function()
				fusionTable = require(fusion)
			end)

			if not success then
				task.spawn(
					log,
					error,
					"An error occured when trying to require provided Fusion instance!\nStack: "
						.. err
				)
				return
			end

			isValid = IsValidFusion(fusionTable)
		end

		if not isValid then
			log(warn, "Provided Fusion instance is not valid!")
		else
			log(
				print,
				"Provided Fusion instance '"
					.. fusion:GetFullName()
					.. "' is valid."
			)
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
				print,
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

pluginSettings:OnSettingsChanged(function(newSettings, _oldSettings)
	if newSettings.log.onSettingsChanged then
		log(print, "Settings have changed")
	end

	getFusion()
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

local function FilteredSelection()
	local selected = Selection:Get()
	local filtered = { }
	local invalid = { }

	for _, obj in pairs(selected) do
		if not IsGuiObject(obj) then
			table.insert(invalid, obj.Name)
		else
			table.insert(filtered, obj)
		end
	end

	if #invalid > 0 then
		log(
			warn,
			"Selected object(s) '"
				.. table.concat(invalid, "', '")
				.. "' are not 2D GuiObject(s)"
		)
	end

	return filtered
end

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

	local guiObjects = FilteredSelection()

	if #guiObjects == 0 then
		return log(print, "No valid objects selected")
	end

	local output = pluginSettings:GetSetting("output")
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
	ChangeHistoryService:SetWaypoint("Converting UI to Fusion")

	local scriptInstances = { }

	for _, guiObject in pairs(guiObjects) do
		if pluginSettings:GetSetting("log").onConversionStart then
			log(print, "Converting '" .. guiObject.Name .. "' to Fusion")
		end

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
				pluginSettings:GetSetting("formatting")
			)
		end)

		if not success then
			scriptInstance:Destroy()
			task.spawn(
				log,
				error,
				"An issue occured while trying to convert '"
					.. guiObject.Name
					.. "'\nStack: "
					.. result
			)
		end

		scriptInstance.Source = result
		table.insert(scriptInstances, scriptInstance)

		log(print, "Converted '" .. guiObject.Name .. "' to Fusion")
	end

	if #scriptInstances > 0 then
		ChangeHistoryService:SetWaypoint("Converted UI to Fusion")

		log(print, "Showing converted UI(s) in explorer...")

		Selection:Set(scriptInstances)
	end
end

local toolbar = PluginBar.new(
	plugin,
	"Hydrogen" .. (IsLocal and " (LOCAL)" or "")
)
janitor:Add(toolbar)

local convertToRaw = toolbar:AddButton(
	"Convert to Raw",
	"Convert the ui into a script containing the Fusion tree.",
	{
		dark = "rbxassetid://7701675844";
		light = "rbxassetid://7701675842";
	},
	true
)

local convertToComponent = toolbar:AddButton(
	"Convert to Component",
	"Convert the ui into a modulescript that returns a Fusion component.",
	{
		dark = "rbxassetid://7701675841";
		light = "rbxassetid://7701675862";
	},
	true
)

local settingsButton = toolbar:AddButton("Settings", "Open settings.", {
	dark = "rbxassetid://7704843199";
	light = "rbxassetid://7704843209";
}, true)

convertToRaw.Click:Connect(function()
	pluginSettings:Assure()

	Convert("r")
	task.delay(0.1, convertToRaw.SetActive, convertToRaw, false)
end)

convertToComponent.Click:Connect(function()
	pluginSettings:Assure()

	Convert("c")
	task.delay(0.1, convertToComponent.SetActive, convertToComponent, false)
end)

settingsButton.Click:Connect(function()
	pluginSettings:Assure()

	if pluginSettings.instance then
		plugin:OpenScript(pluginSettings.instance)
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

getFusion()

plugin.Unloading:Connect(function()
	log(print, "Unloading...")
	janitor:Destroy()
end)
