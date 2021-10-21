local Studio = settings().Studio
local Theme = Studio.Theme
local isDarkMode = Theme.Name == "Dark"

local PluginBar = { }
PluginBar.__index = PluginBar

function PluginBar.new(plugin, name)
	local self = setmetatable({
		Name = name;

		_plugin = plugin;
		_toolbar = plugin:CreateToolbar(name);
		_themeChangedFuncs = setmetatable({ }, { __mode = "k"; });
	}, PluginBar)

	self._onThemeChanged = Studio.ThemeChanged:Connect(function()
		Theme = Studio.Theme
		isDarkMode = Theme.Name == "Dark"

		for _, func in pairs(self._themeChangedFuncs) do
			func(Theme, isDarkMode)
		end
	end)

	return self
end

local PluginButton = { }
do
	PluginButton.__index = PluginButton

	local function GetIcon(icons)
		return (typeof(icons) == "string" and icons)
			or icons[isDarkMode and "dark" or "light"]
			or "rbxasset://textures/ui/ErrorIcon.png"
	end

	function PluginButton.new(
		pluginBar,
		name,
		description,
		icons,
		clickableWhenViewportHidden
	)
		icons = icons or { }

		local icon = GetIcon(icons)

		local self = setmetatable({
			Name = name;
			Description = description;

			_icons = icons;
			_button = pluginBar._toolbar:CreateButton(name, description, icon);
			_pluginBar = pluginBar;
		}, PluginButton)

		self:OnThemeChanged(function(_theme, _isDarkMode)
			self:SetIcon(GetIcon(self._icons))
		end)

		self.Click = self._button.Click

		if clickableWhenViewportHidden ~= nil then
			self:SetClickableWhenViewportIsHidden(clickableWhenViewportHidden)
		end

		return self
	end

	function PluginButton:SetClickableWhenViewportIsHidden(isClickable)
		self._button.ClickableWhenViewportHidden = not not isClickable
	end

	function PluginButton:SetEnabled(enabled)
		if enabled == nil then
			enabled = true
		end

		self._button.Enabled = enabled
	end

	function PluginButton:SetActive(active)
		self._button:SetActive(active)
	end

	function PluginButton:SetIcon(icon)
		self._button.Icon = icon or "rbxasset://textures/ui/ErrorIcon.png"
	end

	function PluginButton:OnThemeChanged(func)
		self._pluginBar._themeChangedFuncs[self._button] = func
	end

	function PluginButton:Destroy()
		self._button:Destroy()

		table.clear(self)
		setmetatable(self, nil)
	end
end

function PluginBar:AddButton(
	name,
	description,
	icons,
	clickableWhenViewportHidden
)
	return PluginButton.new(
		self,
		name,
		description,
		icons,
		clickableWhenViewportHidden
	)
end

function PluginBar:Destroy()
	self._toolbar:Destroy()
	self._onThemeChanged:Disconnect()

	table.clear(self)
	setmetatable(self, nil)
end

return PluginBar
