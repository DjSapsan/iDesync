-- beh/opcodes.lua
-- Extracts instruction metadata from main/data/instructions.lua via sandboxed
-- execution, and provides a .beh camelCase -> opcode snake_case resolver.
--
-- Requires Lua 5.4+ (uses load() with env parameter).
--
-- Usage:
--   local opcodes = require('beh.opcodes')
--   local meta = opcodes.get("check_number")
--   local id, meta = opcodes.resolve("lockSlots")  -- "lock_slots", {args=...}

local M = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Sandbox loader: execute instructions.lua in a fake environment
-- ─────────────────────────────────────────────────────────────────────────────

local all_opcodes  -- lazily loaded cache

local function load_instructions(path)
    local f = assert(io.open(path, "r"), "opcodes: cannot open " .. path)
    local src = f:read("*a")
    f:close()

    -- The data table that instructions.lua populates
    local data = { instructions = {}, instruction_color = {} }

    -- A no-op function and a table that returns no-ops for any key
    local noop = function() end
    local stub_mt = { __index = function() return noop end }
    local function stub() return setmetatable({}, stub_mt) end

    -- Sandbox environment with all globals that instructions.lua references
    local env = {
        data = data,
        -- Game engine objects (stubbed)
        Tool   = stub(),
        Map    = stub(),
        -- Global functions referenced at top level
        GetCachedBehaviorAsm       = noop,
        GetFactionBehaviorAsmById  = noop,
        GetLibraryRevId            = function(id, rev) return 0 end,
        UpdateEntityBehaviorState  = noop,
        ClearFactionBehaviorCache  = noop,
        -- Frame register constants
        FRAMEREG_SIGNAL = -3,
        FRAMEREG_VISUAL = -4,
        FRAMEREG_STORE  = -1,
        FRAMEREG_GOTO   = -2,
        FRAMEREG_COUNT  = -2,
        REG_INFINITE    = 2147483647,
        REG_NOT         = -2147483648,
        -- Lua standard library
        type = type, tostring = tostring, tonumber = tonumber,
        pairs = pairs, ipairs = ipairs, select = select,
        next = next, rawget = rawget, rawset = rawset,
        table = table, string = string, math = math,
        error = error, pcall = pcall, xpcall = xpcall,
        print = noop, assert = assert,
        setmetatable = setmetatable, getmetatable = getmetatable,
        unpack = table.unpack,
        require = function() return {} end,
    }
    env._G = env

    local chunk, err = load(src, "instructions.lua", "t", env)
    if not chunk then
        error("opcodes: failed to parse instructions.lua: " .. tostring(err))
    end

    -- Execute. Some runtime code may error on missing game objects, but
    -- all the table assignments (data.instructions.X = {...}) happen
    -- unconditionally at the top level and will succeed.
    pcall(chunk)

    -- Extract only the metadata we need from each instruction definition
    local result = {}
    for id, def in pairs(data.instructions) do
        local entry = {
            name     = def.name,
            category = def.category,
        }

        if def.args then
            entry.args = {}
            for i, a in ipairs(def.args) do
                entry.args[i] = {
                    dir    = a[1],        -- "in", "out", "exec"
                    name   = a[2] or "",  -- display name
                    filter = a[4],        -- filter type or nil
                }
            end
        end

        -- exec_arg: {index, name, desc} or false or nil
        if def.exec_arg ~= nil then
            if def.exec_arg == false then
                entry.exec_arg = false
            else
                entry.exec_arg = {
                    index = def.exec_arg[1],
                    name  = def.exec_arg[2],
                }
            end
        end

        -- Loop detection: instructions with next/last are loop iterators
        if type(def.next) == "function" then
            entry.is_loop = true
        end

        result[id] = entry
    end

    return result
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Name resolution: .beh camelCase -> Desynced snake_case opcode
-- ─────────────────────────────────────────────────────────────────────────────

local OVERRIDES = {
    -- .beh name = opcode id (for irregular mappings)
    pickItems   = "dopickup",
    dropItems   = "dodrop",
    countItems  = "count_item",
    nearest     = "select_nearest",
    lockSlots   = "lock_slots",
    unlockSlots = "unlock_slots",
}

local function camel_to_snake(name)
    local s = name:gsub("(%l)(%u)", "%1_%2")
    s = s:gsub("(%u)(%u%l)", "%1_%2")
    return s:lower()
end

function M.load(data_path)
    data_path = data_path or "main/data/instructions.lua"
    all_opcodes = load_instructions(data_path)
    return all_opcodes
end

function M.get_all()
    if not all_opcodes then M.load() end
    return all_opcodes
end

function M.get(opcode_id)
    if not all_opcodes then M.load() end
    return all_opcodes[opcode_id]
end

--- Resolve a .beh function name to an opcode id.
--- Returns opcode_id, metadata_table  or  nil if not found.
function M.resolve(beh_name)
    if not all_opcodes then M.load() end

    -- Check manual overrides
    if OVERRIDES[beh_name] then
        local ov = OVERRIDES[beh_name]
        return ov, all_opcodes[ov]
    end

    -- Exact match
    if all_opcodes[beh_name] then
        return beh_name, all_opcodes[beh_name]
    end

    -- camelCase -> snake_case
    local snake = camel_to_snake(beh_name)
    if all_opcodes[snake] then
        return snake, all_opcodes[snake]
    end

    -- All lowercase
    local lower = beh_name:lower()
    if all_opcodes[lower] then
        return lower, all_opcodes[lower]
    end

    return nil
end

--- Return list of input args: {{pos=N, name=..., filter=...}, ...}
function M.input_args(info)
    if not info or not info.args then return {} end
    local result = {}
    for i, a in ipairs(info.args) do
        if a.dir == "in" then
            result[#result + 1] = { pos = i, name = a.name, filter = a.filter }
        end
    end
    return result
end

--- Return list of output args: {{pos=N, name=...}, ...}
function M.output_args(info)
    if not info or not info.args then return {} end
    local result = {}
    for i, a in ipairs(info.args) do
        if a.dir == "out" then
            result[#result + 1] = { pos = i, name = a.name }
        end
    end
    return result
end

--- Return list of exec args: {{pos=N, name=...}, ...}
function M.exec_args(info)
    if not info or not info.args then return {} end
    local result = {}
    for i, a in ipairs(info.args) do
        if a.dir == "exec" then
            result[#result + 1] = { pos = i, name = a.name }
        end
    end
    return result
end

M.camel_to_snake = camel_to_snake

--- Convert a game data exec label to a .beh branch name.
--- "If Equal" -> "equal", "Path Blocked" -> "pathBlocked", "Done" -> "done"
function M.label_to_branch_name(label)
    -- Strip "If " prefix
    local s = label:gsub("^If ", "")
    -- Split on spaces, camelCase: first word lowercase, rest capitalized
    local parts = {}
    for word in s:gmatch("%S+") do parts[#parts + 1] = word end
    local result = parts[1]:lower()
    for i = 2, #parts do
        result = result .. parts[i]:sub(1, 1):upper() .. parts[i]:sub(2):lower()
    end
    return result
end

--- Build a mapping from branch names to exec arg positions for an instruction.
--- Returns {branch_name -> {pos=N, source="exec_arg"|"arg"}} and the
--- fallthrough branch name (from exec_arg).
function M.branch_map(info)
    if not info then return {}, nil end
    local map = {}
    local fallthrough = nil

    -- exec_arg is the fallthrough path
    if info.exec_arg and info.exec_arg ~= false then
        fallthrough = M.label_to_branch_name(info.exec_arg.name)
        map[fallthrough] = { pos = info.exec_arg.index, source = "exec_arg" }
    end

    -- exec args in the args list
    if info.args then
        for i, a in ipairs(info.args) do
            if a.dir == "exec" then
                local bname = M.label_to_branch_name(a.name)
                map[bname] = { pos = i, source = "arg" }
            end
        end
    end

    return map, fallthrough
end

return M
