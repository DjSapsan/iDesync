local json = require("dkjson")

-- Function to call a JavaScript function
-- DesyncedStringToObject / ObjectToDesyncedString
local function callJSFunction(functionName, ...)
	local args = table.concat({...}, '" "')
	local command = string.format('node dsconvert.js %s "%s"', functionName, args)

	local handle = io.popen(command, 'r')
	if handle then
			local obj = handle:read("*a")
			handle:close()

			return obj
	else
			error("Failed to execute command")
	end
end

--- RUN ---

local fileName = "Example.txt"
local file = io.open(fileName, "r")
if not file then
  error("Failed to open file: " .. fileName)
end

local inputStr = file:read("*a")
file:close()

local objson = callJSFunction("DesyncedStringToObject", inputStr)
print("Output:", objson)