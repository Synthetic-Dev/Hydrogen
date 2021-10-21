local StudioService = game:GetService("StudioService")

local packages = script.Parent
local ScriptConstructor = require(packages.ScriptConstructor)

local utils = packages.Parent.utils
local Signal = require(utils.Signal)
local Janitor = require(utils.Janitor)

local NULL = { }

local SettingsManager = { }
SettingsManager.__index = SettingsManager

SettingsManager.Null = NULL

local function FindFirstChildWithNameWhichIsA(parent, name, class, recursive)
	local children = parent:GetChildren()
	local child
	for _, object in pairs(children) do
		if object.Name == name and object:IsA(class) then
			child = object
			break
		end
	end

	if not child and recursive then
		for _, object in pairs(children) do
			child = FindFirstChildWithNameWhichIsA(
				object,
				name,
				class,
				recursive
			)
			if child then
				break
			end
		end
	end

	return child
end

local function Require(instance)
	return pcall(require, instance:Clone())
end

local function Copy(t)
	local nT = { }

	for k, v in pairs(t) do
		if v == NULL then
			nT[k] = NULL
		elseif typeof(v) == "table" then
			nT[k] = Copy(v)
		else
			nT[k] = v
		end
	end

	return nT
end

function SettingsManager.new(name, parent, defaults, comments)
	defaults = defaults or { }
	comments = comments or { }

	local janitor = Janitor.new()

	local self = setmetatable({
		_name = name;
		_parent = parent;

		_dirtySource = true;
		_sourceBeingEditted = false;

		_onChanged = Signal.new(janitor);
		_janitor = janitor;

		defaults = defaults;
		comments = comments;
		settings = nil;
		instance = nil;
	}, SettingsManager)

	self.settings = self:GetDefaults()

	local instance = FindFirstChildWithNameWhichIsA(
		parent,
		name,
		"ModuleScript"
	)
	if not instance or instance.Source == "" then
		instance = Instance.new("ModuleScript")
		instance.Name = name
		instance.Parent = parent
	else
		self._dirtySource = false
		local success, storedSettings = Require(instance)

		if success then
			local function findMissing(default, stored)
				for k, v in pairs(default) do
					if stored[k] == nil then
						self._dirtySource = true
						stored[k] = v
					elseif typeof(stored[k]) .. typeof(v) == "tabletable" then
						findMissing(v, stored[k])
					end
				end
			end

			findMissing(self.settings, storedSettings)
			self.settings = storedSettings
		end
	end

	self.instance = instance

	if self._dirtySource then
		self:_updateSource()
	end
	self:_connectToSource()

	return self
end

function SettingsManager:GetSettings()
	local settings = self.settings
	if not settings then
		local success, _settings = Require(self.instance)
		if success then
			settings = _settings
		end
	end
	self.settings = settings

	local valid = Copy(settings)

	local function Clean(t)
		for k, v in pairs(t) do
			if v == NULL then
				t[k] = nil
			elseif typeof(v) == "table" then
				Clean(v)
			end
		end
	end

	Clean(valid)

	return valid
end

function SettingsManager:GetSetting(name)
	return self:GetSettings()[name]
end

function SettingsManager:GetDefaults()
	return Copy(self.defaults)
end

function SettingsManager:_waitTillClosed()
	if StudioService.ActiveScript == self.instance then
		repeat
			StudioService:GetPropertyChangedSignal("ActiveScript"):Wait()
		until StudioService.ActiveScript ~= self.instance
	end
end

function SettingsManager:_connectToSource()
	local connection
	connection = self.instance
		:GetPropertyChangedSignal("Source")
		:Connect(function()
			if self._sourceBeingEditted then
				return
			end

			self:_waitTillClosed()

			local oldSettings = self:GetSettings()
			local success, newSettings = Require(self.instance)
			if not success then
				error(newSettings)
			end

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
				self.settings = newSettings
				self._onChanged:Fire(self:GetSettings(), oldSettings)
			end
		end)

	self._janitor:Add(connection)
end

function SettingsManager:_updateSource()
	self._sourceBeingEditted = true

	local constructor = ScriptConstructor.Constructor.new(self.instance)
	constructor:Write(
		"-- Save and close this script in order to apply settings"
	)
	constructor:Write("")
	constructor:Write("return {")

	local function writeKVs(t, indent, comments)
		comments = comments or { }

		for key, value in pairs(t) do
			local comment = comments[key]

			if typeof(value) == "table" and value ~= NULL then
				constructor:Write(
					string.format(
						"%s = {"
							.. (
								typeof(comment) == "string"
									and string.format(
										" -- %s",
										tostring(comment)
									)
								or ""
							),
						key
					),
					indent
				)
				writeKVs(value, indent + 1)
				constructor:Write(
					"};",
					indent,
					typeof(comment) == "table" and comment
				)
			else
				value = value == NULL and "nil"
					or ScriptConstructor.ValueToString(value)
				constructor:Write(
					string.format(
						"%s = %s;"
							.. (
								comment
									and string.format(
										" -- %s",
										tostring(comment)
									)
								or ""
							),
						key,
						value
					),
					indent
				)
			end
		end
	end

	writeKVs(self.settings, 1, self.comments)

	constructor:Write("}")
	self.instance.Source = constructor:Build()
	self._sourceBeingEditted = false
end

function SettingsManager:Assure()
	if self.instance.Parent == nil then
		self.settings = self:GetDefaults()
		self.instance = nil
	end

	if not self.instance then
		self.instance = Instance.new("ModuleScript")
		self.instance.Name = self._name
		self.instance.Parent = self._parent

		self:_connectToSource()
		self:_updateSource()
	end
end

function SettingsManager:OnSettingsChanged(func)
	return self._onChanged:Connect(func)
end

function SettingsManager:Destroy()
	self._janitor:Destroy()
end

return SettingsManager
