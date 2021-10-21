local root = script.Parent

local utils = root.Parent.Parent.utils
local TableUtil = require(utils.TableUtil)

local ObjectReferences = require(root.ObjectReferences)

local function trimNumber(num)
	return math.round(num * 1e4) / 1e4
end

function ValueToString(value, formatSettings, instanceHandler)
	formatSettings = TableUtil.Assign({
		tableSeparator = ",";
		extraSeparator = false;
	}, formatSettings or { })

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
		elseif
			table.find(
				{ "NumberSequenceKeypoint"; "ColorSequenceKeypoint"; },
				typeOf
			)
		then
			local includeEnvelope = typeOf == "NumberSequenceKeypoint"

			value = string.format(
				"%s.new(%s, %s" .. (includeEnvelope and ", %s" or "") .. ")",
				typeOf,
				trimNumber(value.Time),
				ValueToString(value.Value, formatSettings, instanceHandler),
				includeEnvelope and trimNumber(value.Envelope)
			)
		elseif table.find({ "NumberSequence"; "ColorSequence"; }, typeOf) then
			local tempValue = "%s.new({\n"
			local keypoints = value.Keypoints

			for index, keypoint in ipairs(keypoints) do
				tempValue ..= "\t" .. ValueToString(
					keypoint,
					formatSettings,
					instanceHandler
				) .. ((index == #keypoints and not formatSettings.extraSeparator) and "" or formatSettings.tableSeparator) .. "\n"
			end

			value = string.format(tempValue, typeOf) .. "})"
		else
			local separator = ", "

			-- Have to include this edge case due to `tostring` formatting inconsistencies
			if table.find({ "NumberRange"; }, typeOf) then
				separator = " "
			end

			local values = string.split(tostring(value), separator)

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

return ValueToString
