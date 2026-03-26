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

--- OPTIONAL: --example flag ---
-- Usage: lua main.lua --example
if arg and arg[1] == "--example" then
	local inputFile = "Example.base"
	local outputFile = "Example.json"

	-- Read the encoded string
	local f = assert(io.open(inputFile, "r"))
	local encoded = f:read("*a"):match("^%s*(.-)%s*$") -- trim whitespace
	f:close()

	-- Decode via node (inline eval since dsconvert.js has no CLI)
	local nodeCmd = string.format(
		[[node -e "const fs=require('fs');eval(fs.readFileSync('dsconvert.js','utf8'));const info={};const obj=DesyncedStringToObject('%s',info);console.log(JSON.stringify(obj,null,2));" ]],
		encoded
	)
	local handle = assert(io.popen(nodeCmd, 'r'))
	local jsonStr = handle:read("*a")
	handle:close()

	local out = assert(io.open(outputFile, "w"))
	out:write(jsonStr)
	out:close()

	print("Decoded " .. inputFile .. " -> " .. outputFile)
	os.exit(0)
end

--- RUN ---
local beh = require("beh.parser")

local fileName = (arg and arg[1]) or "src.beh"
local tree = beh.parsefile(fileName)

-- ── AST printer ─────────────────────────────────────────────────────────────

local function expr_str(node)
    if not node then return "nil" end
    local t = node.type
    if t == "Identifier" then return node.name
    elseif t == "Number"  then return tostring(node.value)
    elseif t == "BinOp"   then
        return string.format("(%s %s %s)", expr_str(node.left), node.op, expr_str(node.right))
    elseif t == "UnaryOp" then
        return string.format("(%s %s)", node.op, expr_str(node.operand))
    elseif t == "Call"    then
        local a = {}
        for _, arg in ipairs(node.args) do a[#a+1] = expr_str(arg) end
        return string.format("%s(%s)", node.name, table.concat(a, ", "))
    elseif t == "Foreach" then
        local a = {}
        for _, arg in ipairs(node.args) do a[#a+1] = expr_str(arg) end
        return string.format("foreach(%s)%s", table.concat(a, ", "),
            node.body and " {body}" or "")
    else
        return "<" .. t .. ">"
    end
end

local print_node   -- forward declaration

local function indent(d) return string.rep("  ", d) end

local function print_block(block, d)
    if not block or #block.stmts == 0 then
        print(indent(d) .. "(empty)")
        return
    end
    for _, s in ipairs(block.stmts) do print_node(s, d) end
end

print_node = function(node, d)
    d = d or 0
    local pad = indent(d)
    local t   = node.type

    if t == "Assign" then
        local targets = {}
        for _, tgt in ipairs(node.targets) do targets[#targets+1] = tgt.name end
        if node.value.type == "Foreach" then
            local a = {}
            for _, arg in ipairs(node.value.args) do a[#a+1] = expr_str(arg) end
            print(pad .. table.concat(targets, ", ") .. " = foreach("
                .. table.concat(a, ", ") .. ")")
            if node.value.body then
                print_block(node.value.body, d + 1)
            end
        else
            print(pad .. table.concat(targets, ", ") .. " = " .. expr_str(node.value))
        end

    elseif t == "Call" then
        local a = {}
        for _, arg in ipairs(node.args) do a[#a+1] = expr_str(arg) end
        print(pad .. node.name .. "(" .. table.concat(a, ", ") .. ")")

    elseif t == "If" then
        print(pad .. "if " .. expr_str(node.cond))
        print_block(node.tbody, d + 1)
        if node.ebody then
            print(pad .. "else")
            print_block(node.ebody, d + 1)
        end
        print(pad .. "end")

    elseif t == "Repeat" then
        print(pad .. "repeat")
        print_block(node.body, d + 1)
        print(pad .. "end")

    elseif t == "Compare" then
        local a = {}
        for _, arg in ipairs(node.args) do a[#a+1] = expr_str(arg) end
        print(pad .. "compare(" .. table.concat(a, ", ") .. ")")
        for _, branch in ipairs(node.branches) do
            print(pad .. "  " .. branch.kind)
            print_block(branch.body, d + 2)
            print(pad .. "  end")
        end

    elseif t == "Break"  then print(pad .. "break")
    elseif t == "Goto"   then print(pad .. "goto(" .. node.label .. ")")
    elseif t == "Return" then
        local v = {}
        for _, val in ipairs(node.values) do v[#v+1] = expr_str(val) end
        print(pad .. "return " .. table.concat(v, ", "))

    elseif t == "Local" then
        local names = table.concat(node.names, ", ")
        if node.value and node.value.type == "Foreach" then
            local a = {}
            for _, arg in ipairs(node.value.args) do a[#a+1] = expr_str(arg) end
            print(pad .. "var " .. names .. " = foreach(" .. table.concat(a, ", ") .. ")")
            print_block(node.value.body, d + 1)
        elseif node.value then
            print(pad .. "var " .. names .. " = " .. expr_str(node.value))
        else
            print(pad .. "var " .. names)
        end

    elseif t == "FuncDef" then
        print(pad .. "function " .. node.name .. "(" .. table.concat(node.params, ", ") .. ")")
        print_block(node.body, d + 1)
        print(pad .. "end")

    else
        print(pad .. "<" .. t .. ">")
    end
end

-- ── Print the parsed tree ────────────────────────────────────────────────────

print("=== AST: " .. fileName .. " ===")
print()

local tr = tree
if tr.params then
    io.write("params: ")
    print(table.concat(tr.params.names, ", "))
end
print()
print("--- body ---")
print_block(tr.body, 0)

if #tr.funcs > 0 then
    print()
    print("--- functions ---")
    for _, fn in ipairs(tr.funcs) do
        print_node(fn, 0)
    end
end
