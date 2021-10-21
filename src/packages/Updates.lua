local packages = script.Parent
local FetchJSON = require(packages.FetchJSON)

local Version = require(packages.Parent.Version)

local URL =
	"https://raw.githubusercontent.com/Synthetic-Dev/Hydrogen/main/src/Version.json"

local Updates = { }

function Updates:GetVersion()
	return Version
end

function Updates:GetLatestVersion()
	local success, result, err = FetchJSON(URL)
	if not success then
		error(
			"An error occured while trying to fetch latest plugin version.\nError: "
				.. result
				.. "\nStack: "
				.. err,
			1
		)
	end

	self.CachedLatestVersion = result

	return result
end

function Updates:GetCachedLatestVersion()
	return self.CachedLatestVersion or self:GetLatestVersion()
end

function Updates:GetVersionNumber(version)
	return version.major * 10000 + version.minor * 100 + version.patch
end

function Updates:IsUpdateAvailable()
	local localVersion = self:GetVersion()
	local latestVersion = self:GetCachedLatestVersion()

	if not latestVersion then
		return false
	end

	local isOutdated = self:GetVersionNumber(latestVersion)
		> self:GetVersionNumber(localVersion)

	return isOutdated
end

return Updates
