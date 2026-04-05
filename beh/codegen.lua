-- beh/codegen.lua
-- Code generator: walks AST and emits Desynced JSON instruction format.
--
-- Usage:
--   local codegen = require('beh.codegen')
--   local result = codegen.generate(ast_program, {name = "My Behavior"})
--   -- result is a Lua table matching Desynced JSON structure

local opcodes = require('beh.opcodes')

local codegen = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Emitter: accumulates instructions (1-based internally)
-- ─────────────────────────────────────────────────────────────────────────────

local Emitter = {}
Emitter.__index = Emitter

function Emitter.new()
    return setmetatable({ insts = {}, count = 0 }, Emitter)
end

function Emitter:emit(inst)
    self.count = self.count + 1
    self.insts[self.count] = inst
    return self.count
end

function Emitter:patch(idx, field, val)
    self.insts[idx][field] = val
end

function Emitter:here()
    return self.count + 1
end

-- Convert 1-based internal index to 0-based JSON index
local function to_json_idx(idx)
    if type(idx) == "number" then return idx - 1 end
    return idx
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Scope: tracks params, vars, user functions
-- ─────────────────────────────────────────────────────────────────────────────

local function new_scope(param_names, func_map)
    local scope = {
        param_names = param_names or {},
        params = {},        -- name -> 1-based index
        vars = {},          -- name -> true (tracking only)
        funcs = func_map or {},  -- name -> {dep_index, param_names}
    }
    for i, name in ipairs(scope.param_names) do
        scope.params[name] = i
    end
    return scope
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Expression resolution: AST expr node -> JSON arg value
-- ─────────────────────────────────────────────────────────────────────────────

local function resolve_value(node, scope)
    if not node then return false end
    local t = node.type

    if t == "Number" then
        return { num = node.value }

    elseif t == "String" then
        return { id = node.value }

    elseif t == "Identifier" then
        if scope.params[node.name] then
            return scope.params[node.name]  -- integer param reference
        end
        scope.vars[node.name] = true
        return node.name  -- string variable name

    elseif t == "UnaryOp" and node.op == "-" and node.operand.type == "Number" then
        return { num = -node.operand.value }

    end
    return nil  -- complex expression, needs separate instruction
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Instruction builder: maps arg values to 0-based JSON keys
-- ─────────────────────────────────────────────────────────────────────────────

local function make_inst(op, args_by_pos, extra)
    local inst = { op = op }
    if args_by_pos then
        for pos, val in pairs(args_by_pos) do
            if val ~= nil then
                inst[tostring(pos - 1)] = val
            end
        end
    end
    if extra then
        for k, v in pairs(extra) do
            inst[k] = v
        end
    end
    return inst
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Compiler: compiles a body (Block) into an Emitter
-- ─────────────────────────────────────────────────────────────────────────────

local function compile_behavior(scope, body_block, em)
    em = em or Emitter.new()

    -- Break target stack: each entry = {done_patches}
    -- done_patches is a list of {idx, field} to patch with the "after loop" address
    local loop_stack = {}

    -- ── Forward declarations ────────────────────────────────────────────

    local emit_stmt, emit_block

    -- ── Helper: map .beh call args to opcode input positions ────────────

    local function map_call_args(beh_args, info)
        local arg_map = {}
        if not info or not info.args then
            -- No metadata (e.g., unknown opcode), just map positionally
            for i, a in ipairs(beh_args) do
                arg_map[i] = resolve_value(a, scope)
            end
            return arg_map
        end

        -- Collect input arg positions
        local in_positions = {}
        for i, a in ipairs(info.args) do
            if a.dir == "in" then
                in_positions[#in_positions + 1] = i
            end
        end

        -- Map .beh args to input positions
        for i, a in ipairs(beh_args) do
            local pos = in_positions[i]
            if pos then
                arg_map[pos] = resolve_value(a, scope)
            end
        end

        return arg_map
    end

    -- ── Helper: map assign targets to opcode output positions ───────────

    local function map_output_targets(targets, info, arg_map)
        if not info or not info.args or not targets then return end
        local out_positions = {}
        for i, a in ipairs(info.args) do
            if a.dir == "out" then
                out_positions[#out_positions + 1] = i
            end
        end
        for i, tgt in ipairs(targets) do
            local pos = out_positions[i]
            if pos then
                arg_map[pos] = resolve_value(tgt, scope)
            end
        end
    end

    -- ── Emit: Call statement ────────────────────────────────────────────

    local function emit_call(node)
        local op_id, info = opcodes.resolve(node.name)
        if not op_id then
            -- Check if it's a user-defined function
            local func_info = scope.funcs[node.name]
            if func_info then
                -- Emit call instruction
                local arg_map = {}
                for i, a in ipairs(node.args) do
                    arg_map[i] = resolve_value(a, scope)
                end
                em:emit(make_inst("call", arg_map, { sub = func_info.dep_index }))
                return
            end
            -- Unknown function, emit as-is with warning
            io.stderr:write("warning: unknown function '" .. node.name .. "'\n")
            local arg_map = {}
            for i, a in ipairs(node.args) do
                arg_map[i] = resolve_value(a, scope)
            end
            em:emit(make_inst(node.name, arg_map))
            return
        end

        local arg_map = map_call_args(node.args, info)
        em:emit(make_inst(op_id, arg_map))
    end

    -- ── Emit: ComplexCall (generalized branches + loops) ────────────────

    local function emit_complex_call(name, args, body, branches, targets)
        local op_id, info = opcodes.resolve(name)
        if not op_id then
            -- User-defined function with complex call (shouldn't happen normally)
            io.stderr:write("warning: unknown complex function '" .. name .. "'\n")
            return
        end

        local arg_map = map_call_args(args, info)
        if targets then
            map_output_targets(targets, info, arg_map)
        end

        local bmap, fallthrough = opcodes.branch_map(info)
        local is_loop = info and info.is_loop

        -- For loops with body: emit loop instruction, body, loop-back, then branches
        if is_loop and body and body.stmts and #body.stmts > 0 then
            local loop_idx = em:emit(make_inst(op_id, arg_map))
            local body_start = em:here()

            -- Push loop context for break
            local loop_ctx = { done_patches = {} }
            loop_stack[#loop_stack + 1] = loop_ctx

            emit_block(body)

            -- Loop back: last body instruction points to body_start
            if em.count >= body_start then
                local last_inst = em.insts[em.count]
                if last_inst.next == nil then
                    last_inst.next = to_json_idx(body_start)
                end
            end

            local after_loop = em:here()

            -- Emit named branches (e.g., "done")
            local end_jumps = {}
            for _, branch in ipairs(branches or {}) do
                local binfo = bmap[branch.kind]
                if binfo then
                    local branch_start = em:here()
                    em:patch(loop_idx, tostring(binfo.pos - 1), to_json_idx(branch_start))
                    emit_block(branch.body)
                    local jmp = em:emit(make_inst("nop", nil, { next = false }))
                    end_jumps[#end_jumps + 1] = jmp
                else
                    io.stderr:write("warning: unknown branch '"
                        .. branch.kind .. "' for " .. name .. "\n")
                end
            end

            local after_all = em:here()

            -- Patch exec args that weren't used (point to after_loop)
            for bname, binfo in pairs(bmap) do
                if binfo.source == "arg" then
                    -- Check if this branch was provided
                    local found = false
                    for _, branch in ipairs(branches or {}) do
                        if branch.kind == bname then found = true; break end
                    end
                    if not found then
                        em:patch(loop_idx, tostring(binfo.pos - 1), to_json_idx(after_loop))
                    end
                end
            end

            -- Patch break targets
            for _, patch in ipairs(loop_ctx.done_patches) do
                em:patch(patch.idx, patch.field, to_json_idx(after_all))
            end

            -- Patch end jumps
            for _, jmp_idx in ipairs(end_jumps) do
                em:patch(jmp_idx, "next", to_json_idx(after_all))
            end

            loop_stack[#loop_stack] = nil
            return
        end

        -- Non-loop complex call (branching, like check_number)
        local check_idx = em:emit(make_inst(op_id, arg_map))

        -- Build branch bodies
        local branch_bodies = {}  -- kind -> {start, end_jump}
        local end_jumps = {}

        -- Determine emit order: fallthrough branch first, then others
        local ordered = {}
        if fallthrough then
            for _, branch in ipairs(branches or {}) do
                if branch.kind == fallthrough then
                    ordered[#ordered + 1] = branch
                    break
                end
            end
        end
        for _, branch in ipairs(branches or {}) do
            if branch.kind ~= fallthrough then
                ordered[#ordered + 1] = branch
            end
        end

        for idx, branch in ipairs(ordered) do
            local branch_start = em:here()
            emit_block(branch.body)
            -- Jump past remaining branches (except for last branch)
            local jmp = nil
            if idx < #ordered then
                jmp = em:emit(make_inst("nop", nil, { next = false }))
                end_jumps[#end_jumps + 1] = jmp
            end
            branch_bodies[branch.kind] = { start = branch_start, end_jump = jmp }
        end

        local after_all = em:here()

        -- Patch exec arg positions to branch start addresses
        for _, branch in ipairs(branches or {}) do
            local binfo = bmap[branch.kind]
            local bdata = branch_bodies[branch.kind]
            if binfo and bdata then
                if binfo.source == "arg" then
                    em:patch(check_idx, tostring(binfo.pos - 1), to_json_idx(bdata.start))
                elseif binfo.source == "exec_arg" and branch.kind ~= fallthrough then
                    -- Non-fallthrough exec_arg: patch next
                    em:patch(check_idx, "next", to_json_idx(bdata.start))
                end
                -- Fallthrough (exec_arg) naturally falls through, no patch needed
            end
        end

        -- Patch missing branches to skip to after_all
        if fallthrough and not branch_bodies[fallthrough] then
            -- No fallthrough branch: next should skip
            local first_non_ft = nil
            for _, branch in ipairs(ordered) do
                if branch.kind ~= fallthrough then
                    first_non_ft = branch_bodies[branch.kind]
                    break
                end
            end
            if first_non_ft then
                em:patch(check_idx, "next", to_json_idx(first_non_ft.start))
            else
                em:patch(check_idx, "next", to_json_idx(after_all))
            end
        end

        -- Patch exec args for branches not provided → skip to after_all
        for bname, binfo in pairs(bmap) do
            if binfo.source == "arg" and not branch_bodies[bname] then
                em:patch(check_idx, tostring(binfo.pos - 1), to_json_idx(after_all))
            end
        end

        -- Patch end jumps to after_all
        for _, jmp_idx in ipairs(end_jumps) do
            em:patch(jmp_idx, "next", to_json_idx(after_all))
        end
    end

    -- ── Emit: Assignment ────────────────────────────────────────────────

    local function emit_assign(node)
        local val = node.value

        -- Case: assign from ComplexCall (loops + branches)
        if val.type == "ComplexCall" then
            emit_complex_call(val.name, val.args, val.body, val.branches, node.targets)
            return
        end

        -- Case: assign from call
        if val.type == "Call" then
            local op_id, info = opcodes.resolve(val.name)
            if op_id then
                local arg_map = map_call_args(val.args, info)
                map_output_targets(node.targets, info, arg_map)
                em:emit(make_inst(op_id, arg_map))
                return
            end

            -- User-defined function call with output
            local func_info = scope.funcs[val.name]
            if func_info then
                local arg_map = {}
                -- Map inputs
                for i, a in ipairs(val.args) do
                    arg_map[i] = resolve_value(a, scope)
                end
                -- Outputs go into param slots after the declared input params
                local n_func_params = #func_info.param_names
                for i, tgt in ipairs(node.targets) do
                    arg_map[n_func_params + i] = resolve_value(tgt, scope)
                end
                em:emit(make_inst("call", arg_map, { sub = func_info.dep_index }))
                return
            end

            -- Unknown function
            io.stderr:write("warning: unknown function '" .. val.name .. "'\n")
            local arg_map = {}
            for i, a in ipairs(val.args) do
                arg_map[i] = resolve_value(a, scope)
            end
            em:emit(make_inst(val.name, arg_map))
            return
        end

        -- Case: assign from BinOp (arithmetic)
        if val.type == "BinOp" and (val.op == "+" or val.op == "-"
                                 or val.op == "*" or val.op == "/") then
            local op_map = { ["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "div" }
            local arith_op = op_map[val.op]
            -- arith ops: 1:in(To/From), 2:in(Num), 3:out(Result)
            local left_val  = resolve_value(val.left, scope)
            local right_val = resolve_value(val.right, scope)
            local target    = resolve_value(node.targets[1], scope)
            local arg_map = { [1] = left_val, [2] = right_val, [3] = target }
            em:emit(make_inst(arith_op, arg_map))
            return
        end

        -- Case: simple value assignment -> set_reg
        local target = resolve_value(node.targets[1], scope)
        local value  = resolve_value(val, scope)
        -- set_reg: 1:in(Value), 2:out(Target)
        em:emit(make_inst("set_reg", { [1] = value, [2] = target }))
    end

    -- ── Emit: If statement ──────────────────────────────────────────────

    local function emit_if(node)
        local cond = node.cond

        -- Case: if BinOp(> < >= <= == ~= !=) then body end
        if cond.type == "BinOp" and (cond.op == ">" or cond.op == "<"
            or cond.op == ">=" or cond.op == "<="
            or cond.op == "==" or cond.op == "~=" or cond.op == "!=") then

            local left_val  = resolve_value(cond.left, scope)
            local right_val = resolve_value(cond.right, scope)
            -- check_number: 1:exec(If Larger), 2:exec(If Smaller),
            --               3:in(Value), 4:in(Compare)
            -- exec_arg: fallthrough = "If Equal"
            local arg_map = { [3] = left_val, [4] = right_val }
            local check_idx = em:emit(make_inst("check_number", arg_map))

            -- Determine which paths go to body vs skip
            -- Body follows immediately (body_start = check_idx + 1)
            local op = cond.op

            -- Emit then body
            emit_block(node.tbody)

            -- Emit else body if present
            local else_jump_idx = nil
            if node.ebody then
                -- Jump past else at end of then-body
                else_jump_idx = em:emit(make_inst("jump", nil, { next = false }))
            end

            local after_then = em:here()

            -- Emit else body
            local after_else = after_then
            if node.ebody then
                emit_block(node.ebody)
                after_else = em:here()
                -- Patch the jump at end of then-body
                em.insts[else_jump_idx].next = to_json_idx(after_else)
            end

            local skip = to_json_idx(node.ebody and after_then or after_then)

            -- Patch check_number exec paths based on operator
            if op == ">" then
                em:patch(check_idx, "1", skip)
                em:patch(check_idx, "next", skip)
            elseif op == "<" then
                em:patch(check_idx, "0", skip)
                em:patch(check_idx, "next", skip)
            elseif op == ">=" then
                em:patch(check_idx, "1", skip)
            elseif op == "<=" then
                em:patch(check_idx, "0", skip)
            elseif op == "==" then
                em:patch(check_idx, "0", skip)
                em:patch(check_idx, "1", skip)
            elseif op == "~=" or op == "!=" then
                em:patch(check_idx, "next", skip)
            end

            return
        end

        -- Case: if not Call(...) then body end
        if cond.type == "UnaryOp" and cond.op == "not" and cond.operand.type == "Call" then
            local call = cond.operand
            local op_id, info = opcodes.resolve(call.name)
            if op_id and info then
                local arg_map = map_call_args(call.args, info)
                local check_idx = em:emit(make_inst(op_id, arg_map))

                -- Emit body
                emit_block(node.tbody)
                local after_body = em:here()

                -- "not" inverts: the exec branch (failure) falls through to body,
                -- success (fallthrough/next) skips body
                em:patch(check_idx, "next", to_json_idx(after_body))
                return
            end
        end

        -- Case: if Call(...) then body end (without not)
        if cond.type == "Call" then
            local op_id, info = opcodes.resolve(cond.name)
            if op_id and info then
                local arg_map = map_call_args(cond.args, info)
                local check_idx = em:emit(make_inst(op_id, arg_map))

                -- Emit body
                emit_block(node.tbody)
                local after_body = em:here()

                -- Success (fallthrough/next) enters body,
                -- failure exec branch skips body
                if info.args then
                    for i, a in ipairs(info.args) do
                        if a.dir == "exec" then
                            em:patch(check_idx, tostring(i - 1), to_json_idx(after_body))
                        end
                    end
                end
                return
            end
        end

        -- Fallback: emit condition as a check and body
        io.stderr:write("warning: unsupported if-condition type: " .. cond.type .. "\n")
    end

    -- ── Emit: Repeat loop ───────────────────────────────────────────────

    local function emit_repeat(node)
        local loop_start = em:here()

        -- Push repeat loop context (for break at repeat level)
        local loop_ctx = { done_patches = {}, is_repeat = true }
        loop_stack[#loop_stack + 1] = loop_ctx

        emit_block(node.body)

        -- Last instruction loops back to start
        local last_inst = em.insts[em.count]
        if last_inst and last_inst.next == nil then
            last_inst.next = to_json_idx(loop_start)
        elseif em.count >= 1 then
            em:emit(make_inst("nop", nil, { next = to_json_idx(loop_start) }))
        end

        local after_loop = em:here()

        -- Patch any break targets
        for _, patch in ipairs(loop_ctx.done_patches) do
            em:patch(patch.idx, patch.field, to_json_idx(after_loop))
        end

        loop_stack[#loop_stack] = nil
    end

    -- ── Emit: Local (var declaration) ───────────────────────────────────

    local function emit_local(node)
        for _, name in ipairs(node.names) do
            scope.vars[name] = true
        end
        if node.value then
            local value = resolve_value(node.value, scope)
            if value ~= nil then
                -- set_reg for each name with initial value
                for _, name in ipairs(node.names) do
                    local target = scope.params[name] or name
                    em:emit(make_inst("set_reg", { [1] = value, [2] = target }))
                end
            end
        end
    end

    -- ── Emit: Break ─────────────────────────────────────────────────────

    local function emit_break()
        if #loop_stack == 0 then
            io.stderr:write("warning: break outside of loop\n")
            return
        end

        local ctx = loop_stack[#loop_stack]
        if ctx.is_repeat then
            -- Break from repeat loop: jump past the loop
            local jmp_idx = em:emit(make_inst("nop", nil, { next = false }))
            ctx.done_patches[#ctx.done_patches + 1] = { idx = jmp_idx, field = "next" }
        else
            -- Break from foreach/loop: emit 'last' opcode
            em:emit(make_inst("last", nil, { next = false }))
        end
    end

    -- ── Emit: Goto ──────────────────────────────────────────────────────

    local function emit_goto(node)
        em:emit(make_inst("jump", { [1] = { id = node.label } }, { next = false }))
    end

    -- ── Emit: Return ────────────────────────────────────────────────────

    local function emit_return(node)
        if node.values and #node.values > 0 then
            local n_params = 0
            for _ in pairs(scope.params) do n_params = n_params + 1 end
            for i, val in ipairs(node.values) do
                local v = resolve_value(val, scope)
                if v ~= nil then
                    em:emit(make_inst("set_reg", { [1] = v, [2] = n_params + i }))
                end
            end
        end
        em:emit(make_inst("exit", nil, { next = false }))
    end

    -- ── Emit: any statement ─────────────────────────────────────────────

    emit_stmt = function(node)
        local t = node.type
        if     t == "Call"        then emit_call(node)
        elseif t == "Assign"      then emit_assign(node)
        elseif t == "ComplexCall"  then emit_complex_call(node.name, node.args, node.body, node.branches, nil)
        elseif t == "If"          then emit_if(node)
        elseif t == "Repeat"      then emit_repeat(node)
        elseif t == "Local"       then emit_local(node)
        elseif t == "Break"       then emit_break()
        elseif t == "Goto"        then emit_goto(node)
        elseif t == "Return"      then emit_return(node)
        else
            io.stderr:write("warning: unsupported statement type: " .. t .. "\n")
        end
    end

    -- ── Emit: block ─────────────────────────────────────────────────────

    emit_block = function(block)
        if not block or not block.stmts then return end
        for _, stmt in ipairs(block.stmts) do
            emit_stmt(stmt)
        end
    end

    -- ── Run ─────────────────────────────────────────────────────────────

    emit_block(body_block)

    return em
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Assemble output: convert emitter to Desynced JSON table
-- ─────────────────────────────────────────────────────────────────────────────

local function assemble_output(em, params, deps, name)
    local result = {}

    -- Convert 1-based instructions to 0-based string keys
    for i = 1, em.count do
        local inst = em.insts[i]
        result[tostring(i - 1)] = inst
    end

    -- Add metadata
    if params and #params > 0 then
        result.pnames = params
        local parameters = {}
        for i = 1, #params do
            parameters[i] = true
        end
        result.parameters = parameters
    end

    if deps and #deps > 0 then
        result.dependencies = deps
    end

    if name then
        result.name = name
    end

    return result
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

function codegen.generate(ast_program, options)
    options = options or {}

    -- First, compile all user-defined functions as sub-behaviors
    local deps = {}
    local func_map = {}  -- name -> {dep_index, param_names}

    for _, func_def in ipairs(ast_program.funcs) do
        local func_scope = new_scope(func_def.params, {})
        local func_em = compile_behavior(func_scope, func_def.body)

        local dep = assemble_output(func_em, func_def.params, nil, func_def.name)
        deps[#deps + 1] = dep
        func_map[func_def.name] = {
            dep_index = #deps,
            param_names = func_def.params,
        }
    end

    -- Compile main behavior
    local param_names = ast_program.params and ast_program.params.names or {}
    local main_scope = new_scope(param_names, func_map)
    local main_em = compile_behavior(main_scope, ast_program.body)

    return assemble_output(main_em, param_names, deps, options.name)
end

return codegen
