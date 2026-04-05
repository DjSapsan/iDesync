-- Extract instruction metadata from main/data/instructions.lua -> JSON
-- Usage: lua desynced-ext/extract-instructions.lua > desynced-ext/instructions-data.json

local function noop() end
local callable_mt
callable_mt = {
    __index = function() return setmetatable({}, callable_mt) end,
    __call = function() return setmetatable({}, callable_mt) end,
    __newindex = function() end,
}
local function make_mock() return setmetatable({}, callable_mt) end

-- Build sandboxed environment
local data = {}
local env = {
    data = data,
    Map = make_mock(),
    Tool = make_mock(),
    UI = make_mock(),
    Comp = make_mock(),
    NOLOC = noop,
    REG_INFINITE = 999999,
    math = math,
    type = type,
    pairs = pairs,
    ipairs = ipairs,
    tostring = tostring,
    tonumber = tonumber,
    print = noop,
    error = noop,
    pcall = pcall,
    xpcall = xpcall,
    select = select,
    unpack = unpack or table.unpack,
    table = table,
    string = string,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    rawset = rawset,
    rawget = rawget,
    next = next,
    require = function() return {} end,
    assert = function(v) return v end,
}
setmetatable(env, { __index = function() return noop end })

-- Load file
local chunk, err = loadfile("main/data/instructions.lua", "t", env)
if not chunk then
    -- Lua 5.1 fallback
    chunk, err = loadfile("main/data/instructions.lua")
    if not chunk then
        io.stderr:write("Failed to load: " .. tostring(err) .. "\n")
        os.exit(1)
    end
    if setfenv then setfenv(chunk, env) end
end

-- Execute - ignore errors (game API calls like Comp:RegisterComponent)
-- We wrap in pcall; if it fails partway, we still get whatever was defined
pcall(chunk)

local instructions = data.instructions or {}

-- Collect keys in sorted order for deterministic output
local keys = {}
for k in pairs(instructions) do
    keys[#keys + 1] = k
end
table.sort(keys)

-- JSON helpers
local function json_escape(s)
    if type(s) ~= "string" then return tostring(s) end
    return (s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t'))
end

local function arg_to_json(arg)
    if type(arg) ~= "table" then return "null" end
    local parts = {}
    parts[#parts + 1] = '"direction":"' .. json_escape(arg[1] or "") .. '"'
    parts[#parts + 1] = '"name":"' .. json_escape(arg[2] or "") .. '"'
    if arg[3] then parts[#parts + 1] = '"desc":"' .. json_escape(arg[3]) .. '"' end
    if arg[4] then parts[#parts + 1] = '"filter":"' .. json_escape(arg[4]) .. '"' end
    if arg[5] then parts[#parts + 1] = '"extra":true' end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Output JSON
io.write("{\n")
for i, id in ipairs(keys) do
    local inst = instructions[id]
    if inst and type(inst) == "table" and inst.name then
        if i > 1 then io.write(",\n") end

        io.write('  "' .. json_escape(id) .. '": {\n')
        io.write('    "name": "' .. json_escape(inst.name) .. '"')

        if inst.desc then
            io.write(',\n    "desc": "' .. json_escape(inst.desc) .. '"')
        end
        if inst.category then
            io.write(',\n    "category": "' .. json_escape(inst.category) .. '"')
        end
        if inst.icon then
            io.write(',\n    "icon": "' .. json_escape(inst.icon) .. '"')
        end

        -- args
        if inst.args and type(inst.args) == "table" and #inst.args > 0 then
            io.write(',\n    "args": [\n')
            for j, arg in ipairs(inst.args) do
                if j > 1 then io.write(',\n') end
                io.write('      ' .. arg_to_json(arg))
            end
            io.write('\n    ]')
        end

        -- exec_arg
        if inst.exec_arg then
            if type(inst.exec_arg) == "table" then
                io.write(',\n    "exec_arg": {')
                io.write('"index":' .. tostring(inst.exec_arg[1] or 0))
                if inst.exec_arg[2] then
                    io.write(',"label":"' .. json_escape(inst.exec_arg[2]) .. '"')
                end
                if inst.exec_arg[3] then
                    io.write(',"desc":"' .. json_escape(inst.exec_arg[3]) .. '"')
                end
                io.write('}')
            elseif inst.exec_arg == false then
                io.write(',\n    "exec_arg": false')
            end
        end

        io.write('\n  }')
    end
end
io.write("\n}\n")

io.stderr:write("Extracted " .. #keys .. " instructions\n")
