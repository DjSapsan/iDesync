-- beh/parser.lua
-- Recursive-descent parser for .beh source files.
--
-- Pipeline:  source string  ->  tokenize  ->  preprocess  ->  parse  ->  AST
--
-- Public API:
--   local beh = require('beh.parser')
--   local tree = beh.parse(source_string)
--   local tree = beh.parsefile(path)
--
-- Language:
--   * 'var' declares compiled variables
--   * 'local' declares preprocessor variables (text substitution, removed before parse)
--   * Any function call can have sub-blocks (complex call):
--       name(args) body branchLabel body end ... end end
--   * All instruction names are camelCase
--   * String literals: "Metal Ore", 'Dashbot'

local tokenize = require('beh.tokenizer')
local ast      = require('beh.ast')
local opcodes  = require('beh.opcodes')

-- ─────────────────────────────────────────────────────────────────────────────
-- Preprocessor: local variable text substitution
-- ─────────────────────────────────────────────────────────────────────────────

local function preprocess(tokens)
    -- Collect local declarations and substitute values.
    -- local name = <single token value>
    -- Scoping: file-level locals are global; function-scoped locals
    -- only apply within that function body.

    -- First pass: find all local declarations, record their scope ranges
    local to_remove = {}  -- indices of tokens to remove (ranges)
    local substitutions = {}  -- { {name, replacement_tok, scope_start, scope_end} }

    local i = 1
    while i <= #tokens do
        local t = tokens[i]
        if t.type == 'keyword' and t.value == 'local' then
            -- Expect: local <name> = <value>
            local name_tok = tokens[i + 1]
            local eq_tok   = tokens[i + 2]
            local val_tok  = tokens[i + 3]

            if not name_tok or name_tok.type ~= 'name' then
                error(string.format(
                    "preprocess error at line %d: expected name after 'local'",
                    t.line))
            end
            if not eq_tok or eq_tok.value ~= '=' then
                error(string.format(
                    "preprocess error at line %d: expected '=' after 'local %s'",
                    t.line, name_tok.value))
            end
            if not val_tok or (val_tok.type ~= 'string' and val_tok.type ~= 'number'
                              and val_tok.type ~= 'name') then
                error(string.format(
                    "preprocess error at line %d: local value must be a string, number, or name",
                    t.line))
            end

            -- Determine scope: find enclosing function boundary
            -- Walk backwards to find if we're inside a function
            local scope_start = i + 4  -- after the declaration
            local scope_end = #tokens

            -- Check for enclosing function by scanning forward from beginning
            -- Simple approach: scan backwards for unmatched 'function'
            local func_depth = 0
            for j = 1, i - 1 do
                local tj = tokens[j]
                if tj.type == 'keyword' then
                    if tj.value == 'function' then
                        func_depth = func_depth + 1
                    elseif tj.value == 'end' then
                        func_depth = func_depth - 1
                    elseif tj.value == 'if' or tj.value == 'repeat' then
                        func_depth = func_depth + 1
                    end
                end
            end
            -- Actually this approach is wrong because if/repeat also use end.
            -- Better: just track function..end pairs specifically.
            -- For simplicity, locals declared at nesting depth 0 (before any
            -- function keyword) are file-scoped. Locals inside a function
            -- keyword block are function-scoped.

            -- Find if we're inside a function block
            local depth = 0
            for j = 1, i - 1 do
                local tj = tokens[j]
                if tj.type == 'keyword' then
                    if tj.value == 'function' or tj.value == 'if'
                        or tj.value == 'repeat' then
                        depth = depth + 1
                    elseif tj.value == 'end' then
                        depth = depth - 1
                    end
                end
            end
            -- Now scan from i forward, find the end that brings us back to
            -- depth-1 (the function's closing end)
            if depth > 0 then
                -- We're nested. Find the matching end
                local d = depth
                for j = i + 4, #tokens do
                    local tj = tokens[j]
                    if tj.type == 'keyword' then
                        if tj.value == 'function' or tj.value == 'if'
                            or tj.value == 'repeat' then
                            d = d + 1
                        elseif tj.value == 'end' then
                            d = d - 1
                            if d < depth then
                                scope_end = j
                                break
                            end
                        end
                    end
                end
            end

            -- Check for duplicate
            for _, sub in ipairs(substitutions) do
                if sub.name == name_tok.value
                    and scope_start >= sub.scope_start
                    and scope_start <= sub.scope_end then
                    io.stderr:write(string.format(
                        "warning: duplicate local '%s' at line %d (previous at line %d)\n",
                        name_tok.value, t.line, sub.line))
                end
            end

            substitutions[#substitutions + 1] = {
                name = name_tok.value,
                replacement = val_tok,
                scope_start = scope_start,
                scope_end = scope_end,
                line = t.line,
            }

            -- Mark tokens for removal (local name = value)
            to_remove[#to_remove + 1] = { from = i, to = i + 3 }
            i = i + 4
        else
            i = i + 1
        end
    end

    -- Remove local declarations (in reverse order to preserve indices)
    for j = #to_remove, 1, -1 do
        local r = to_remove[j]
        for k = r.to, r.from, -1 do
            table.remove(tokens, k)
        end
        -- Adjust scope ranges for subsequent substitutions
        local removed = r.to - r.from + 1
        for _, sub in ipairs(substitutions) do
            if sub.scope_start > r.from then
                sub.scope_start = sub.scope_start - removed
            end
            if sub.scope_end > r.from then
                sub.scope_end = sub.scope_end - removed
            end
        end
    end

    -- Apply substitutions
    for idx = 1, #tokens do
        local t = tokens[idx]
        if t.type == 'name' then
            for _, sub in ipairs(substitutions) do
                if t.value == sub.name
                    and idx >= sub.scope_start
                    and idx <= sub.scope_end then
                    -- Replace token in-place
                    tokens[idx] = {
                        type = sub.replacement.type,
                        value = sub.replacement.value,
                        line = t.line,
                    }
                    break
                end
            end
        end
    end

    return tokens
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Parser object
-- ─────────────────────────────────────────────────────────────────────────────

local Parser = {}
Parser.__index = Parser

function Parser.new(source)
    local self = setmetatable({}, Parser)
    local tokens = tokenize(source)
    self.tokens = preprocess(tokens)
    self.pos    = 1
    return self
end

-- ── Token access ─────────────────────────────────────────────────────────────

function Parser:peek(offset)
    offset = offset or 0
    return self.tokens[self.pos + offset]
end

function Parser:advance()
    local t = self.tokens[self.pos]
    if t.type ~= 'eof' then self.pos = self.pos + 1 end
    return t
end

function Parser:check(value, ttype)
    local t = self:peek()
    if ttype and t.type  ~= ttype then return false end
    if value  and t.value ~= value then return false end
    return true
end

function Parser:match(value, ttype)
    if self:check(value, ttype) then return self:advance() end
end

function Parser:expect(value, ttype)
    local t = self:match(value, ttype)
    if not t then
        local cur = self:peek()
        error(string.format(
            "parse error at line %d: expected %s'%s', got %s '%s'",
            cur.line,
            ttype and (ttype .. ':') or '',
            tostring(value),
            cur.type, tostring(cur.value)
        ), 2)
    end
    return t
end

-- ── Branch label detection ───────────────────────────────────────────────────
-- A bare name NOT followed by '(', '=', or ',' is a branch label.

function Parser:isBranchLabel()
    local t = self:peek()
    if t.type ~= 'name' then return false end
    local next_t = self:peek(1)
    if not next_t then return true end
    if next_t.type == 'symbol' and
        (next_t.value == '(' or next_t.value == '=' or next_t.value == ',') then
        return false
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Top level
-- ─────────────────────────────────────────────────────────────────────────────

function Parser:parse()
    local params = nil
    local stmts  = {}
    local funcs  = {}

    if self:check('params', 'keyword') then
        params = self:parseParamList()
    end

    while not self:check(nil, 'eof') do
        while self:match(';', 'symbol') do end
        if self:check(nil, 'eof') then break end
        if self:check('function', 'keyword') then
            funcs[#funcs + 1] = self:parseFuncDef()
        else
            local s = self:parseStatement()
            if s then
                stmts[#stmts + 1] = s
            else
                local t = self:peek()
                error(string.format(
                    "parse error at line %d: unexpected token %s '%s' at top level",
                    t.line, t.type, tostring(t.value)
                ))
            end
        end
    end

    return ast.Program(params, ast.Block(stmts), funcs)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Declarations
-- ─────────────────────────────────────────────────────────────────────────────

-- params [ Name, Name, ... ]
function Parser:parseParamList()
    self:expect('params', 'keyword')
    self:expect('[', 'symbol')
    local names = {}
    while not self:check(']', 'symbol') do
        names[#names + 1] = self:expect(nil, 'name').value
        self:match(',', 'symbol')
    end
    self:expect(']', 'symbol')
    return ast.ParamList(names)
end

-- var Name [, Name, ...] [= expr]
function Parser:parseVar()
    self:expect('var', 'keyword')
    local names = { self:expect(nil, 'name').value }
    while self:match(',', 'symbol') do
        names[#names + 1] = self:expect(nil, 'name').value
    end
    local value = nil
    if self:match('=', 'symbol') then
        value = self:parseExpr()
    end
    return ast.Local(names, value)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Block / statement list
-- ─────────────────────────────────────────────────────────────────────────────

function Parser:parseBlock(stops, branch_aware)
    local stmts = {}
    while true do
        while self:match(';', 'symbol') do end
        local t = self:peek()
        if t.type == 'eof' then break end
        if t.type == 'keyword' then
            local halt = false
            for _, s in ipairs(stops) do
                if t.value == s then halt = true; break end
            end
            if halt then break end
        end
        -- If branch_aware, stop when we see a bare branch label
        if branch_aware and self:isBranchLabel() then
            break
        end
        local prev = self.pos
        local stmt = self:parseStatement()
        if stmt then
            stmts[#stmts + 1] = stmt
        elseif self.pos == prev then
            error(string.format(
                "parse error at line %d: unexpected token %s '%s' inside block",
                t.line, t.type, tostring(t.value)
            ))
        end
    end
    return ast.Block(stmts)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Statements
-- ─────────────────────────────────────────────────────────────────────────────

function Parser:parseStatement()
    local t = self:peek()

    if t.type == 'keyword' then
        if     t.value == 'var'     then return self:parseVar()
        elseif t.value == 'repeat'  then return self:parseRepeat()
        elseif t.value == 'if'      then return self:parseIf()
        elseif t.value == 'break'   then self:advance(); return ast.Break()
        elseif t.value == 'goto'    then return self:parseGoto()
        elseif t.value == 'return'  then return self:parseReturn()
        else   return nil  -- end / else — block terminators
        end

    elseif t.type == 'name' then
        return self:parseNameStmt()

    else
        return nil
    end
end

-- repeat ... end
function Parser:parseRepeat()
    self:expect('repeat', 'keyword')
    local body = self:parseBlock({'end'})
    self:expect('end', 'keyword')
    return ast.Repeat(body)
end

-- if expr then ... [else ...] end
function Parser:parseIf()
    self:expect('if', 'keyword')
    local cond  = self:parseExpr()
    self:expect('then', 'keyword')
    local tbody = self:parseBlock({'end', 'else'})
    local ebody = nil
    if self:match('else', 'keyword') then
        ebody = self:parseBlock({'end'})
    end
    self:expect('end', 'keyword')
    return ast.If(cond, tbody, ebody)
end

-- goto(LABEL)
function Parser:parseGoto()
    self:expect('goto', 'keyword')
    self:expect('(', 'symbol')
    local label = self:expect(nil, 'name').value
    self:expect(')', 'symbol')
    return ast.Goto(label)
end

-- return [expr, expr, ...]
function Parser:parseReturn()
    self:expect('return', 'keyword')
    local vals = {}
    if self:canStartExpr() then
        vals[#vals + 1] = self:parseExpr()
        while self:match(',', 'symbol') do
            vals[#vals + 1] = self:parseExpr()
        end
    end
    return ast.Return(vals)
end

function Parser:canStartExpr()
    local t = self:peek()
    if t.type == 'name' or t.type == 'number' or t.type == 'string' then return true end
    if t.type == 'symbol' and (t.value == '-' or t.value == '(') then return true end
    if t.type == 'keyword' and t.value == 'not' then return true end
    return false
end

-- function name(P1, P2) body end
function Parser:parseFuncDef()
    self:expect('function', 'keyword')
    local name   = self:expect(nil, 'name').value
    self:expect('(', 'symbol')
    local params = {}
    while not self:check(')', 'symbol') do
        params[#params + 1] = self:expect(nil, 'name').value
        self:match(',', 'symbol')
    end
    self:expect(')', 'symbol')

    local body = self:parseBlock({'end'})
    self:expect('end', 'keyword')
    return ast.FuncDef(name, params, body)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Complex call parsing: name(args) [body] [branchLabel body end]* end
-- ─────────────────────────────────────────────────────────────────────────────

function Parser:parseComplexTail(name, args)
    -- Parse optional implicit body (loop iteration body) and branch labels.
    -- Stops body on 'end' keyword or bare branch label.
    local body = self:parseBlock({'end'}, true)  -- branch_aware = true
    if #body.stmts == 0 then body = nil end

    -- Parse branch labels
    local branches = {}
    while self:peek().type == 'name' and self:isBranchLabel() do
        local kind = self:advance().value
        local branch_body = self:parseBlock({'end'}, true)
        self:expect('end', 'keyword')
        branches[#branches + 1] = { kind = kind, body = branch_body }
    end

    self:expect('end', 'keyword')  -- outer end of complex call
    return ast.ComplexCall(name, args, body, branches)
end

-- Statements starting with a name:
--   Name(args)                                -> Call or ComplexCall
--   Name(args) body branchLabel...end end     -> ComplexCall
--   Name = expr                               -> Assign
--   Name, Name, ... = expr                    -> Assign (multi-target)
--   Name, Name = Name(args) branches end      -> Assign with ComplexCall value
function Parser:parseNameStmt()
    local first = self:advance().value

    if self:check(',', 'symbol') then
        -- Multi-target: Name, Name, ... = expr
        local targets = { ast.Identifier(first) }
        while self:match(',', 'symbol') do
            targets[#targets + 1] = ast.Identifier(self:expect(nil, 'name').value)
        end
        self:expect('=', 'symbol')
        local expr = self:parseExpr()

        -- Check if the RHS call has complex sub-blocks
        if expr.type == "Call" and not self:check(nil, 'eof') then
            if self:isComplexFollowing(expr.name) then
                local complex = self:parseComplexTail(expr.name, expr.args)
                return ast.Assign(targets, complex)
            end
        end

        return ast.Assign(targets, expr)

    elseif self:match('=', 'symbol') then
        -- Single target: Name = expr
        local expr = self:parseExpr()

        -- Check if the RHS call has complex sub-blocks
        if expr.type == "Call" and not self:check(nil, 'eof') then
            if self:isComplexFollowing(expr.name) then
                local complex = self:parseComplexTail(expr.name, expr.args)
                return ast.Assign({ ast.Identifier(first) }, complex)
            end
        end

        return ast.Assign({ ast.Identifier(first) }, expr)

    elseif self:check('(', 'symbol') then
        -- Call: Name(args) or ComplexCall
        self:advance()
        local args = self:parseArgList()
        self:expect(')', 'symbol')

        -- Check if this call has sub-blocks (complex call)
        if self:isComplexFollowing(first) then
            return self:parseComplexTail(first, args)
        end

        return ast.Call(first, args)

    else
        local t = self:peek()
        error(string.format(
            "parse error at line %d: unexpected token after name '%s': %s '%s'",
            t.line, first, t.type, tostring(t.value)
        ))
    end
end

-- Check if the next tokens indicate a complex call body/branches follow.
-- func_name is used for opcodes lookup to detect loop instructions.
function Parser:isComplexFollowing(func_name)
    local t = self:peek()
    if t.type == 'eof' then return false end
    -- A bare branch label → complex call with branches
    if t.type == 'name' and self:isBranchLabel() then return true end
    -- Loop opcode → has implicit body (detected via game data)
    if func_name then
        local _, info = opcodes.resolve(func_name)
        if info and info.is_loop then
            -- Next must be something that can start a statement
            if t.type == 'keyword' then
                return t.value ~= 'end' and t.value ~= 'else'
            end
            return t.type == 'name'
        end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Expressions
-- ─────────────────────────────────────────────────────────────────────────────

local BINOPS = {}
for _, op in ipairs({'+','-','*','/','==','~=','!=','>=','<=','>','<'}) do
    BINOPS[op] = true
end

function Parser:parseExpr()
    local left = self:parseUnary()
    while true do
        local t = self:peek()
        if t.type == 'symbol' and BINOPS[t.value] then
            local op    = self:advance().value
            local right = self:parseUnary()
            left = ast.BinOp(op, left, right)
        else
            break
        end
    end
    return left
end

function Parser:parseUnary()
    if self:check('-', 'symbol') then
        self:advance()
        return ast.UnaryOp('-', self:parsePrimary())
    elseif self:check('not', 'keyword') then
        self:advance()
        return ast.UnaryOp('not', self:parsePrimary())
    end
    return self:parsePrimary()
end

function Parser:parsePrimary()
    local t = self:peek()

    -- (expr) grouping
    if t.type == 'symbol' and t.value == '(' then
        self:advance()
        local expr = self:parseExpr()
        self:expect(')', 'symbol')
        return expr

    elseif t.type == 'number' then
        self:advance()
        return ast.Number(t.value)

    elseif t.type == 'string' then
        self:advance()
        return ast.String(t.value)

    elseif t.type == 'name' then
        local name = self:advance().value
        if self:check('(', 'symbol') then
            self:advance()
            local args = self:parseArgList()
            self:expect(')', 'symbol')
            return ast.Call(name, args)
        end
        return ast.Identifier(name)

    else
        error(string.format(
            "parse error at line %d: expected expression, got %s '%s'",
            t.line, t.type, tostring(t.value)
        ), 2)
    end
end

function Parser:parseArgList()
    local args = {}
    if self:check(')', 'symbol') then return args end
    args[#args + 1] = self:parseExpr()
    while self:match(',', 'symbol') do
        args[#args + 1] = self:parseExpr()
    end
    return args
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public interface
-- ─────────────────────────────────────────────────────────────────────────────

local function parse(source)
    return Parser.new(source):parse()
end

local function parsefile(path)
    local f = assert(io.open(path, 'r'), "cannot open: " .. path)
    local src = f:read('*a')
    f:close()
    return parse(src)
end

return {
    parse     = parse,
    parsefile = parsefile,
    Parser    = Parser,
}
