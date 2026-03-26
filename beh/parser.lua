-- beh/parser.lua
-- Recursive-descent parser for .beh source files.
--
-- Pipeline:  source string  ->  tokenize  ->  parse  ->  AST
--
-- Public API:
--   local beh = require('beh.parser')
--   local tree = beh.parse(source_string)
--   local tree = beh.parsefile(path)
--
-- Language changes from previous version:
--   * 'vars' replaced by 'var' keyword
--   * foreach always has a body ending with 'end'
--   * compare block ends with 'end'
--   * return is Lua-style: return expr, expr, ...
--   * semicolons allowed as sugar (ignored)

local tokenize = require('beh.tokenizer')
local ast      = require('beh.ast')

-- ─────────────────────────────────────────────────────────────────────────────
-- Parser object
-- ─────────────────────────────────────────────────────────────────────────────

local Parser = {}
Parser.__index = Parser

function Parser.new(source)
    local self = setmetatable({}, Parser)
    self.tokens = tokenize(source)
    self.pos    = 1
    return self
end

-- ── Token access ─────────────────────────────────────────────────────────────

function Parser:peek()
    return self.tokens[self.pos]
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

function Parser:parseBlock(stops)
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
        elseif t.value == 'compare' then return self:parseCompare()
        elseif t.value == 'if'      then return self:parseIf()
        elseif t.value == 'break'   then self:advance(); return ast.Break()
        elseif t.value == 'goto'    then return self:parseGoto()
        elseif t.value == 'return'  then return self:parseReturn()
        else   return nil  -- end / else / equal / larger / smaller
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

-- compare(a, b) equal...end larger...end smaller...end
function Parser:parseCompare()
    self:expect('compare', 'keyword')
    self:expect('(', 'symbol')
    local args = self:parseArgList()
    self:expect(')', 'symbol')

    local branches = {}
    local BRANCH = { equal = true, larger = true, smaller = true }
    while self:peek().type == 'keyword' and BRANCH[self:peek().value] do
        local kind = self:advance().value
        local body = self:parseBlock({'end', 'equal', 'larger', 'smaller'})
        self:expect('end', 'keyword')
        branches[#branches + 1] = { kind = kind, body = body }
    end
    self:expect('end', 'keyword')

    return ast.Compare(args, branches)
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
    if t.type == 'name' or t.type == 'number' then return true end
    if t.type == 'symbol' and (t.value == '-' or t.value == '(') then return true end
    if t.type == 'keyword' and (t.value == 'not' or t.value == 'foreach') then return true end
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

-- Statements starting with a name:
--   Name(args)                   -> Call
--   Name = expr                  -> Assign
--   Name, Name, ... = expr       -> Assign (multi-target)
function Parser:parseNameStmt()
    local first = self:advance().value

    if self:check(',', 'symbol') then
        local targets = { ast.Identifier(first) }
        while self:match(',', 'symbol') do
            targets[#targets + 1] = ast.Identifier(self:expect(nil, 'name').value)
        end
        self:expect('=', 'symbol')
        return ast.Assign(targets, self:parseExpr())

    elseif self:match('=', 'symbol') then
        return ast.Assign({ ast.Identifier(first) }, self:parseExpr())

    elseif self:check('(', 'symbol') then
        self:advance()
        local args = self:parseArgList()
        self:expect(')', 'symbol')
        return ast.Call(first, args)

    else
        local t = self:peek()
        error(string.format(
            "parse error at line %d: unexpected token after name '%s': %s '%s'",
            t.line, first, t.type, tostring(t.value)
        ))
    end
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

    -- foreach(args) body end   — always has a body
    elseif t.type == 'keyword' and t.value == 'foreach' then
        return self:parseForeach()

    elseif t.type == 'number' then
        self:advance()
        return ast.Number(t.value)

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

-- foreach(args) ... end
function Parser:parseForeach()
    self:expect('foreach', 'keyword')
    self:expect('(', 'symbol')
    local args = self:parseArgList()
    self:expect(')', 'symbol')
    local body = self:parseBlock({'end'})
    self:expect('end', 'keyword')
    return ast.Foreach(args, body)
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
