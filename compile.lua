local json = require("dkjson")

local Compiler = {}

local BLOCKS = {}  -- Initialize empty table

function Compiler.initialize()
    Compiler.ast = {}
    Compiler.symbols = {}
end

function Compiler.newBlock(name, N_inputs, N_outputs, N_flows)
    local block = {}
    block.op = name         -- instruction name
    block.cmt = nil         -- optional comment

    if N_inputs then
        block.inputs = {}
        for i = 1, N_inputs do
            block.inputs[i] = false  -- default values are false - nothing
        end
    end

    if N_outputs then
        block.outputs = {}
        for i = 1, N_outputs do
            block.outputs[i] = false -- default values are false - nothing
        end
    end

    if N_flows then
        block.flows = {}
        for i = 1, N_flows do
            block.flows[i] = false   -- default values are false - nothing
        end
    end

    BLOCKS[name] = block
    return block
end

local function tokenize(input)
    local tokens = {}
    local patterns = {
        -- Comments
        {"COMMENT", "^%-%-[^\n]*"},        -- Line comments

        -- String literals
        {"STRING", '^"([^"\\]|\\.)*"'},    -- Double quoted strings with escapes
        {"STRING", "^'([^'\\]|\\.)*'"},    -- Single quoted strings with escapes

        -- Keywords
        {"KEYWORD_CONTROL", "^(if|else|goto|break|compare|wait|repeat|for|while|equal|larger|smaller|do|then|not|and|or|foreach|end)\\b"},
        {"KEYWORD_DECLARATION", "^(function|params|vars)\\b"},
        {"KEYWORD_RETURN", "^return\\b"},

        -- Operators
        {"OPERATOR", "^(==|~=|<=|>=|<|>|%+|%-|%*|/|%^|%)"},
        {"OPERATOR_LOGICAL", "^(and|or|not)\\b"},

        -- Numbers
        {"NUMBER", "^-?%d+%.?%d*"},

        -- Function calls
        {"FUNCTION_IMPORTANT", "^_[a-zA-Z][a-zA-Z0-9_]*(?=\\s*\\()"},  -- Important functions starting with _
        {"FUNCTION_BUILTIN", "^[a-zA-Z][a-zA-Z0-9_]*(?=\\s*\\()"},     -- Regular function calls

        -- Identifiers and variables
        {"IDENTIFIER", "^[a-zA-Z_][a-zA-Z0-9_]*"},

        -- Delimiters
        {"LPAREN", "^%("},
        {"RPAREN", "^%)"},
        {"COMMA", "^,"},
        {"EQUALS", "^="},

        -- Whitespace
        {"WHITESPACE", "^%s+"},
    }

    input = input .. "\n"  -- Add newline to help with pattern matching
    local line = 1

    while #input > 0 do
        local matched = false
        for _, pat in ipairs(patterns) do
            local tokenType, pattern = pat[1], pat[2]
            local s, e = input:find(pattern)
            if s then
                local token = input:sub(s, e)
                if tokenType ~= "WHITESPACE" then
                    -- Strip quotes from strings
                    if tokenType == "STRING" then
                        token = token:sub(2, -2)
                    end

                    table.insert(tokens, {
                        type = tokenType,
                        value = token,
                        line = line
                    })
                else
                    -- Count newlines in whitespace
                    line = line + select(2, token:gsub("\n", "\n"))
                end

                input = input:sub(e + 1)
                matched = true
                break
            end
        end

        if not matched then
            error(string.format("Line %d: Unexpected character: %s", line, input:sub(1,1)))
        end
    end

    return tokens
end

function Compiler.readProgram(filename)
    local file = io.open(filename, "r")
    if not file then
        error("Cannot open file: " .. filename)
    end
    local content = file:read("*all")
    file:close()
    return tokenize(content)
end

function Compiler.test()
    local tokens = Compiler.readProgram("src.beh")
    for i, token in ipairs(tokens) do
        print(string.format("[%d] type: %s, value: %s", i, token.type, token.value))
    end
end

function Compiler.parse(tokens)
    local ast = {
        type = "Program",
        body = {}
    }

    local current = 1

    local function peek()
        return tokens[current]
    end

    local function advance()
        current = current + 1
        return tokens[current - 1]
    end

    local function isAtEnd()
        return current > #tokens
    end

    local function parseStatement()
        local token = peek()

        if token.type == "KEYWORD" then
            if token.value == "function" then
                return parseFunctionDeclaration()
            elseif token.value == "if" then
                return parseIfStatement()
            elseif token.value == "vars" or token.value == "params" then
                return parseVarDeclaration()
            end
        end

        return parseExpressionStatement()
    end

    -- Add main parsing loop
    while not isAtEnd() do
        table.insert(ast.body, parseStatement())
    end

    return ast
end

return Compiler