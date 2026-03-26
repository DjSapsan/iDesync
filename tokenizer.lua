local lpeg = require("lpeg")

local P, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V
local C, Ct, Cc = lpeg.C, lpeg.Ct, lpeg.Cc

-- Module table
local Tokenizer = {}

-- Basic patterns
local alpha = R('az', 'AZ')
local digit = R('09')
local alnum = alpha + digit
local space = S(' \t\n\r')^1
local newline = P('\n')
local ident = (alpha + P'_') * (alnum + P'_')^0

-- Token constructors
local function T(type)
    return function(value)
        return {type = type, value = value}
    end
end

-- Patterns for different token types
local patterns = {
    -- Comments
    comment = P'--' * (1 - newline)^0 * (newline + -1) / T'COMMENT',

    -- String literals
    string = (P'"' * (P'\\"' + (1 - P'"'))^0 * P'"' +
             P"'" * (P"\\'" + (1 - P"'"))^0 * P"'") / T'STRING',

    -- Keywords
    keyword_control = (P'if' + 'else' + 'goto' + 'break' + 'compare' + 
                      'wait' + 'repeat' + 'for' + 'while' + 'equal' + 
                      'larger' + 'smaller' + 'do' + 'then' + 'not' + 
                      'and' + 'or' + 'foreach' + 'end') * 
                      -(alnum + P'_') / T'KEYWORD_CONTROL',

    keyword_decl = (P'function' + 'params' + 'vars') * 
                   -(alnum + P'_') / T'KEYWORD_DECLARATION',

    keyword_return = P'return' * -(alnum + P'_') / T'KEYWORD_RETURN',

    -- Operators
    operator = (P'==' + '~=' + '<=' + '>=' + '<' + '>' + 
               '+' + '-' + '*' + '/' + '^' + '%') / T'OPERATOR',

    operator_logical = (P'and' + 'or' + 'not') * 
                      -(alnum + P'_') / T'OPERATOR_LOGICAL',

    -- Numbers
    number = (P'-'^-1 * digit^1 * (P'.' * digit^0)^-1) / T'NUMBER',

    -- Function calls
    func_important = (P'_' * ident) * #(space^0 * P'(') / T'FUNCTION_IMPORTANT',
    func_builtin = ident * #(space^0 * P'(') / T'FUNCTION_BUILTIN',

    -- Identifiers
    identifier = ident / T'IDENTIFIER',

    -- Delimiters
    lparen = P'(' / T'LPAREN',
    rparen = P')' / T'RPAREN',
    comma = P',' / T'COMMA',
    equals = P'=' / T'EQUALS',
    lbracket = P'[' / T'LBRACKET',
    rbracket = P']' / T'RBRACKET',

    -- Whitespace
    space = space
}

-- Build the complete grammar
local grammar = P{
    'all',
    all = Ct((
        patterns.comment +
        patterns.string +
        patterns.keyword_control +
        patterns.keyword_decl +
        patterns.keyword_return +
        patterns.operator +
        patterns.operator_logical +
        patterns.number +
        patterns.func_important +
        patterns.func_builtin +
        patterns.identifier +
        patterns.lparen +
        patterns.rparen +
        patterns.comma +
        patterns.equals +
        patterns.lbracket +
        patterns.rbracket +
        patterns.space
    )^0)
}


-- Assuming 'grammar' is defined elsewhere, you'll need to either:
-- 1. Define it in this module, or
-- 2. Pass it as a parameter to the tokenize function
local function tokenize(input)
    local tokens = lpeg.match(grammar, input)
    if not tokens then
        error("Failed to tokenize input")
    end

    -- Filter out whitespace and add line numbers
    local result = {}
    local line = 1
    for _, token in ipairs(tokens) do
        if token.type ~= "WHITESPACE" then
            token.line = line
            table.insert(result, token)
        end
        -- Count newlines
        if token.value then
            line = line + select(2, token.value:gsub("\n", "\n"))
        end
    end

    return result
end

-- Expose the function in the module
Tokenizer.tokenize = tokenize

-- Return the module
return Tokenizer