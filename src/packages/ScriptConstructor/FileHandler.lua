local LINE_PATTERN = ".-\n"

local function AddTrailingNewLine(str)
	if string.sub(str, -1, -1) ~= "\n" then
		str ..= "\n"
	end
	return str
end

local function RemoveTrailingNewLine(str)
	if string.sub(str, -1, -1) == "\n" then
		return string.sub(str, 1, -2)
	end
	return str
end

local function AddIndents(str, indent)
	if indent == 0 then
		return str
	end

	local lines = string.split(str, "\n")
	for i, line in pairs(lines) do
		lines[i] = string.rep("\t", indent) .. line
	end
	return table.concat(lines, "\n")
end

local FileHandler = { }
FileHandler.__index = FileHandler

function FileHandler.new(instance, initalSource)
	local self = setmetatable({
		source = initalSource or instance.Source or "";
		instance = instance;
	}, FileHandler)

	return self
end

function FileHandler:GetLines()
	self.source = AddTrailingNewLine(self.source)
	return string.gmatch(self.source, LINE_PATTERN)
end

function FileHandler:GetLineCount()
	return #string.split(self.source, LINE_PATTERN)
end

function FileHandler:GetLastLineNumber()
	return select(2, string.gsub(self.source, LINE_PATTERN, ""))
end

function FileHandler:GetLine(lineNumber)
	local contentBefore, contentAfter, contentAt = "", "", ""
	local counter = 1
	for line in self:GetLines() do
		if counter < lineNumber then
			contentBefore ..= line
		elseif counter > lineNumber then
			contentAfter ..= line
		else
			contentAt = line
		end

		counter += 1
	end

	return contentAt, contentBefore, contentAfter
end

function FileHandler:WriteLine(lineNumber, content, indent)
	indent = indent or 0
	lineNumber = lineNumber or 1

	local _, contentBefore, contentAfter = self:GetLine(lineNumber)
	contentBefore = AddTrailingNewLine(contentBefore)

	self.source = contentBefore
		.. (AddIndents(content, indent) .. "\n")
		.. contentAfter
end

function FileHandler:InsertLine(lineNumber, content, indent)
	indent = indent or 0
	lineNumber = lineNumber or self:GetLastLineNumber()

	local contentAt, contentBefore, contentAfter = self:GetLine(lineNumber)

	self.source = contentBefore
		.. (AddIndents(content, indent) .. "\n")
		.. contentAt
		.. contentAfter
end

function FileHandler:AppendToLine(lineNumber, content, position)
	lineNumber = lineNumber or 1
	position = position or "e"

	local contentAt, contentBefore, contentAfter = self:GetLine(lineNumber)
	contentAt = RemoveTrailingNewLine(contentAt)

	if position == "e" then
		contentAt ..= content
	elseif position == "s" then
		local raw, indents = string.gsub(contentAt, "\t", "")
		contentAt = string.rep("\t", indents) .. content .. raw
	end

	self.source = contentBefore .. AddTrailingNewLine(contentAt) .. contentAfter
end

function FileHandler:AppendLine(content, indent)
	indent = indent or 0

	local source = self.source

	if #source > 0 then
		source = AddTrailingNewLine(source)
	end

	source ..= AddIndents(content, indent) .. "\n"
	self.source = source
end

function FileHandler:GetSource()
	return self.source
end

function FileHandler:SetSource(source)
	self.source = source
end

function FileHandler:Save()
	return pcall(function()
		self.instance.Source = self.source
	end)
end

return FileHandler
