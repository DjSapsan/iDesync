-- beh/json.lua
-- Minimal JSON encoder for Desynced behavior output.
-- Handles: objects (string-keyed tables), arrays (integer-keyed tables),
-- strings, numbers, booleans, and false/nil.
--
-- Usage:
--   local json = require('beh.json')
--   print(json.encode(value))
--   print(json.encode(value, true))  -- pretty-printed

local M = {}

local encode_value  -- forward declaration

local function is_array(t)
    local n = #t
    if n == 0 then
        -- Check if it has any keys at all
        return next(t) == nil
    end
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            return false
        end
    end
    return true
end

local function escape_string(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"', '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return '"' .. s .. '"'
end

-- Sort keys: numeric-string keys first (by numeric value), then alpha keys
local function sorted_keys(t)
    local nums, strs = {}, {}
    for k in pairs(t) do
        if type(k) == "string" then
            local n = tonumber(k)
            if n then
                nums[#nums + 1] = k
            else
                strs[#strs + 1] = k
            end
        end
    end
    table.sort(nums, function(a, b) return tonumber(a) < tonumber(b) end)
    table.sort(strs)
    for _, s in ipairs(strs) do
        nums[#nums + 1] = s
    end
    return nums
end

local function encode_array(t, pretty, depth)
    local parts = {}
    local indent = pretty and string.rep("  ", depth) or ""
    local inner  = pretty and string.rep("  ", depth + 1) or ""
    for i = 1, #t do
        parts[#parts + 1] = encode_value(t[i], pretty, depth + 1)
    end
    if pretty then
        return "[\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. indent .. "]"
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encode_object(t, pretty, depth)
    local keys = sorted_keys(t)
    if #keys == 0 then return "{}" end
    local parts = {}
    local indent = pretty and string.rep("  ", depth) or ""
    local inner  = pretty and string.rep("  ", depth + 1) or ""
    for _, k in ipairs(keys) do
        local v = t[k]
        local val = encode_value(v, pretty, depth + 1)
        if pretty then
            parts[#parts + 1] = escape_string(k) .. ": " .. val
        else
            parts[#parts + 1] = escape_string(k) .. ":" .. val
        end
    end
    if pretty then
        return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. indent .. "}"
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encode_value = function(v, pretty, depth)
    depth = depth or 0
    local vtype = type(v)
    if v == nil then
        return "null"
    elseif vtype == "boolean" then
        return v and "true" or "false"
    elseif vtype == "number" then
        if v == math.floor(v) and math.abs(v) < 2^53 then
            return string.format("%d", v)
        end
        return tostring(v)
    elseif vtype == "string" then
        return escape_string(v)
    elseif vtype == "table" then
        if is_array(v) then
            return encode_array(v, pretty, depth)
        else
            return encode_object(v, pretty, depth)
        end
    else
        error("json: cannot encode type " .. vtype)
    end
end

function M.encode(value, pretty)
    return encode_value(value, pretty, 0)
end

return M
