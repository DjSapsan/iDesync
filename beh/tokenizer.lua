-- beh/tokenizer.lua
-- Pure tokenizer for .beh source files.
-- Input:  source string
-- Output: array of {type, value, line} tokens; last entry is {type='eof'}
--
-- Token types:
--   'keyword'  -- reserved word (see KEYWORDS below)
--   'name'     -- identifier (not a keyword)
--   'number'   -- numeric literal
--   'symbol'   -- operator or punctuation
--   'eof'      -- end of input

local KEYWORDS = {}
for _, kw in ipairs({
    'params', 'var',
    'repeat', 'compare', 'equal', 'larger', 'smaller',
    'foreach',
    'if', 'then', 'else', 'end',
    'break', 'goto',
    'function', 'return',
    'not',
}) do KEYWORDS[kw] = true end

-- Tried longest-first so '>=', '<=', '==' etc. match before '=', '<', '>'.
local SYMBOLS = {
    '>=', '<=', '==', '~=', '!=', '..',
    '=', ',', ';', '(', ')', '[', ']',
    '+', '-', '*', '/', '>', '<', '.',
}

local function tokenize(source)
    local tokens = {}
    local i = 1
    local line = 1
    local n = #source

    local function push(tp, val)
        tokens[#tokens + 1] = { type = tp, value = val, line = line }
    end

    while i <= n do
        local c = source:sub(i, i)

        -- Whitespace
        if c == ' ' or c == '\t' or c == '\r' then
            i = i + 1

        elseif c == '\n' then
            line = line + 1
            i = i + 1

        -- Single-line comment  --...
        elseif source:sub(i, i+1) == '--' then
            i = i + 2
            while i <= n and source:sub(i, i) ~= '\n' do i = i + 1 end

        -- Numbers
        elseif c >= '0' and c <= '9' then
            local j = i
            while i <= n do
                local ch = source:sub(i, i)
                if ch >= '0' and ch <= '9' then i = i + 1
                elseif ch == '.' or ch == 'x' or ch == 'X'
                    or ch == 'e' or ch == 'E'
                    or (ch >= 'a' and ch <= 'f')
                    or (ch >= 'A' and ch <= 'F') then i = i + 1
                else break end
            end
            push('number', source:sub(j, i - 1))

        -- Names and keywords
        elseif (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' then
            local j = i
            while i <= n do
                local ch = source:sub(i, i)
                if (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z')
                    or (ch >= '0' and ch <= '9') or ch == '_' then
                    i = i + 1
                else break end
            end
            local word = source:sub(j, i - 1)
            push(KEYWORDS[word] and 'keyword' or 'name', word)

        -- Symbols (longest match first)
        else
            local matched = false
            for _, sym in ipairs(SYMBOLS) do
                if source:sub(i, i + #sym - 1) == sym then
                    push('symbol', sym)
                    i = i + #sym
                    matched = true
                    break
                end
            end
            if not matched then
                error(string.format("tokenizer: unknown character '%s' at line %d", c, line))
            end
        end
    end

    push('eof', nil)
    return tokens
end

return tokenize
