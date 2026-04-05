-- beh/ast.lua
-- AST node constructors for .beh programs.
-- Every node is a plain table with a 'type' field plus type-specific fields.
--
-- Node types:
--   Program      params body funcs
--   ParamList    names
--   Block        stmts
--   -- statements --
--   Local        names value       (local declaration, value may be nil)
--   Assign       targets value
--   Call         name args
--   ComplexCall  name args body branches  (body may be nil; each branch: {kind, body})
--   If           cond tbody ebody
--   Repeat       body
--   Break
--   Goto         label
--   Return       values
--   FuncDef      name params body
--   -- expressions --
--   Identifier   name
--   Number       value
--   String       value
--   BinOp        op left right
--   UnaryOp      op operand

local function node(kind, fields)
    local t = fields or {}
    t.type = kind
    return t
end

return {
    -- Top level
    Program    = function(params, body, funcs)
                     return node('Program', {params=params, body=body, funcs=funcs}) end,
    ParamList  = function(names)
                     return node('ParamList', {names=names}) end,
    Block      = function(stmts)
                     return node('Block', {stmts=stmts}) end,

    -- Statements
    Local      = function(names, value)
                     return node('Local', {names=names, value=value}) end,
    Assign     = function(targets, value)
                     return node('Assign', {targets=targets, value=value}) end,
    Call       = function(name, args)
                     return node('Call', {name=name, args=args}) end,
    ComplexCall = function(name, args, body, branches)
                     return node('ComplexCall', {name=name, args=args, body=body, branches=branches}) end,
    If         = function(cond, tbody, ebody)
                     return node('If', {cond=cond, tbody=tbody, ebody=ebody}) end,
    Repeat     = function(body)
                     return node('Repeat', {body=body}) end,
    Break      = function()        return node('Break') end,
    Goto       = function(label)   return node('Goto',   {label=label}) end,
    Return     = function(values)  return node('Return', {values=values}) end,
    FuncDef    = function(name, params, body)
                     return node('FuncDef', {name=name, params=params, body=body}) end,

    -- Expressions
    Identifier = function(name)           return node('Identifier', {name=name}) end,
    Number     = function(value)          return node('Number',     {value=tonumber(value)}) end,
    String     = function(value)          return node('String',     {value=value}) end,
    BinOp      = function(op, left, right)return node('BinOp',      {op=op, left=left, right=right}) end,
    UnaryOp    = function(op, operand)    return node('UnaryOp',    {op=op, operand=operand}) end,
}
