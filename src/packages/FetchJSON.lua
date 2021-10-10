local HttpService = game:GetService("HttpService")

return function(url)
	local success, result = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not success then
		local httpDisabled = string.find(result, "not enabled")
		return false, httpDisabled and "HTTPDisabled" or "HTTPError", result
	end

	success, result = pcall(function()
		return HttpService:JSONDecode(result)
	end)
	if not success then
		return false, "JSONDecodeError", result
	end

	return true, result
end
