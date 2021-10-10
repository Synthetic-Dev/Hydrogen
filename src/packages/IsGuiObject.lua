local guiObjectClassNames = {
	"GuiBase2d";
	"GuiObject";
	"UIComponent";
}

return function(object)
	for _, className in pairs(guiObjectClassNames) do
		if object:IsA(className) then
			return true
		end
	end
	return false
end
