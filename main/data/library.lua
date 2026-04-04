function GetLibraryRevId(id, rev) return (rev << 32) | id end
local function GetRevId(id, rev) return (rev << 32) | id end
local function GetIdFromRevId(revid) return revid & 0xFFFFFFFF end
local function GetRevFromRevId(revid) return revid >> 32 end

-- Only GetFactionBehaviorAsm and ClearFactionBehaviorCache are allowed to touch this table.
-- GetFactionBehaviorAsm must have a deterministic results regardless what exists in this table.
local asm_cache = {}

function ClearFactionBehaviorCache(id, rev)
	asm_cache[GetRevId(id, rev)] = nil
end

-- Can only be called from places that are certain that GetFactionBehaviorAsm has just been called
function GetCachedBehaviorAsm(revid)
	return asm_cache[revid]
end

function GetFactionBehaviorAsm(faction_or_comp, revid)
	local asm = asm_cache[revid]
	if asm then return asm end

	local id, library = GetIdFromRevId(revid), (faction_or_comp.meta_type == 'faction' and faction_or_comp or faction_or_comp.faction).extra_data.library
	local code = library and library[id]
	if not code or code.id ~= id or code.rev ~= GetRevFromRevId(revid) or code.type ~= 'C' then
		return nil
	end

	local args = (type(code.parameters) == "table" and #code.parameters or 0)
	--print("[GetFactionBehaviorAsm] regs: " .. args)
	asm = {}
	local instructions, mem, fill_lvs, lvs, vars, fregs = data.instructions, {}, not code.keepvars
	for inst_idx,inst in ipairs(code) do
		local inst_op, next = inst.op, inst.next
		local inst_def = instructions[inst_op]
		if not inst_def then inst_op, inst_def = "nop", instructions.nop end
		local asminst = { inst_op, (next == nil and inst_idx < #code and inst_idx + 1 or next and next <= #code and next or false) }
		local arg_defs, var_args = inst_def.args, inst_def.var_args and inst_def.var_args(inst, code, library)
		if inst_def.make_asm then asminst[#asminst + 1] = inst_def.make_asm(inst) end
		for i=1,(arg_defs and #arg_defs or 0)+(var_args and #var_args//2 or 0) do
			local val, is_exec, asmarg = inst[i], (arg_defs and arg_defs[i] and arg_defs[i][1] == "exec")
			local val_type = type(val)
			if is_exec then
				-- exec jump, calculate absolute target address
				asmarg = (val == nil and inst_idx < #code and inst_idx + 1 or val and val <= #code and val or false)
				--print("    [#" .. inst_idx .. ":" .. inst_op .. "] arg[" .. i .. "]: SET EXEC JUMP TO " .. tostring(asmarg))
			elseif val_type == "table" and val.fr then
				-- faction register
				local freg = val.fr
				if not fregs then fregs = {} end
				for i,v in ipairs(fregs) do if freg == v then asmarg = -99 - i break end end
				if not asmarg then fregs[#fregs+1] = freg asmarg = -99 - #fregs end
			elseif val_type == "table" then
				-- constant value
				mem[#mem + 1] = Tool.NewRegisterObject(val)
				asmarg = args + #mem
				--print("    [#" .. inst_idx .. ":" .. inst_op .. "] arg[" .. i .. "]: SET CONSTANT TO " .. tostring(data[#data]))
			elseif val_type == "number" and ((val > 0 and val <= args) or (val < 0 and val >= -4)) then
				-- parameter (if > 0) or frame register (if < 0)
				asmarg = val
				--print("    [#" .. inst_idx .. ":" .. inst_op .. "] arg[" .. i .. "]: LINK FROM " .. tostring(asmarg))
			elseif val_type == "string" then
				-- local variable
				if not vars then vars = {} end
				if not vars[val] then
					mem[#mem + 1] = Tool.NewRegisterObject()
					vars[val] = args + #mem
					if fill_lvs then
						if not lvs then lvs = {} end
						lvs[#lvs+1] = #mem
					end
				end
				asmarg = vars[val]
				--print("    [#" .. inst_idx .. ":" .. inst_op .. "] arg[" .. i .. "]: VARIABLE: " .. arg)
			else
				-- unused argument
				asmarg = false
				--print("    [#" .. inst_idx .. ":" .. inst_op .. "] arg[" .. i .. "]: UNUSED - argtype: " .. tostring(argtype))
			end
			asminst[#asminst + 1] = asmarg
		end
		asm[inst_idx] = asminst
		if inst_def.event_setup then
			asm.events = asm.events or {}
			asm.events[#asm.events+1] = inst_idx
		end
	end
	asm.revid, asm.code, asm.mem, asm.lvs, asm.fregs = revid, code, mem, lvs, fregs

	asm_cache[revid] = asm

	--print("-----------------------------------------------------------")
	--print("Function ["..id.."]: " .. (code.name or ''))
	--print("Parameters: " .. tostring(code.parameters):gsub("\n", " "):gsub(" %p%d+%p: ", ""))
	--print("Mem: " .. tostring(mem):gsub("\n", " "):gsub(" %p%d+%p: ", ""))
	--for i=1,#asm do print("[" .. i .. "] OP: " .. asm[i][1] .. " - Next: " .. tostring(asm[i][2]) .. " - Args: " .. tostring({select(3, table.unpack(asm[i]))}):gsub("\n", " "):gsub(" %p%d+%p: ", "")) end
	--print("-----------------------------------------------------------")
	--for i=1,#asm do if asm[i][1] == 'call' then GetFactionBehaviorAsm(faction_or_comp, asm[i][3]) end end

	return asm
end

function GetFactionBehaviorAsmById(faction, id)
	local library = faction.extra_data.library
	local code = library and library[id]
	return code and GetFactionBehaviorAsm(faction, GetRevId(id, code.rev))
end

function UpdateEntityBehaviorState(e, stopped_comp)
	for i=1,999 do
		local comp = e:FindComponent("c_behavior", true, i)
		if not comp then e.state_custom_2 = false return end
		if comp ~= stopped_comp and comp.is_active then e.state_custom_2 = true return end
	end
end

function SetBehavior(comp, id, debug, counter, breakpoints)
	local old_state = comp.has_extra_data and comp.extra_data
	if old_state and old_state.event_comps then
		for _,ev_comp in ipairs(old_state.event_comps) do
			if ev_comp.exists then
				ev_comp.extra_data.owner = nil -- disable until actually destroyed
				Map.Defer(function() if ev_comp.exists then ev_comp:Destroy() end end)
			end
		end
		old_state.event_comps = nil
	end

	local asm = GetFactionBehaviorAsmById(comp.faction, id)
	if not asm then
		if old_state then -- Keep the referenced behavior, erase runtime state
			old_state.revid, old_state.stk, old_state.counter, old_state.lastcounter, old_state.mem, old_state.blocks, old_state.returns, old_state.debug = nil
			local library = comp.faction.extra_data.library
			local code = library and library[old_state.main_id]
			if not code or code.keeparrays ~= "store" then old_state.arrays = nil end
		end
		if debug ~= "RESTART" then
			comp:Shutdown()
			comp.register_count = 0
		end
		UpdateEntityBehaviorState(comp.owner, comp)
		return
	end

	local code, keep_args = asm.code, (old_state and old_state.main_id == id and comp.register_count or 0)
	local args = (type(code.parameters) == "table" and #code.parameters or 0)
	local state = { revid = asm.revid, stk = args, counter = 1, lastcounter = 1, mem = Tool.Copy(asm.mem), main_id = id }
	if breakpoints then state.breakpoints = breakpoints end
	comp.register_count = args
	comp.extra_data = state

	-- Keep arrays across states when using "Keep memory arrays until behavior is switched" setting
	if code.keeparrays == "store" and old_state and old_state.main_id == id then
		state.arrays = old_state.arrays
	end

	-- Apply default parameter values
	local pinits = args > keep_args and code.pinits
	for i=keep_args+1,args do
		comp:SetRegister(i, pinits and pinits[i] or nil)
	end

	-- Spawn event listeners
	if asm.events then
		Map.Defer(function()
			local state = comp.has_extra_data and comp.extra_data
			if not state or state.revid ~= asm.revid or state.event_comps then return end
			state.event_comps = {}
			for _,ev_inst_idx in ipairs(asm.events) do
				local op, next = asm[ev_inst_idx][1], asm[ev_inst_idx][2]
				local ev_comp = next and data.instructions[op].event_setup(comp, code[ev_inst_idx])
				if ev_comp then
					ev_comp.extra_data.owner, ev_comp.extra_data.inst_idx = comp, ev_inst_idx
					ev_comp:ClearActivationChangeFlags()
					state.event_comps[#state.event_comps+1] = ev_comp
				end
			end
		end)
	end

	if asm.fregs then
		local radio_storage = comp.faction.extra_data.radio_storage
		local radio_storage_names = radio_storage and radio_storage.extra_data.names
		for _,v in ipairs(asm.fregs) do
			if not radio_storage_names or not radio_storage_names[v] then
				FactionAction.FactionRegister(comp.faction, { create = true, name = v })
			end
		end
	end

	if not debug or debug == "CONTINUE" then
		if breakpoints then state.debug = 'BREAKPOINT' end
		comp:Activate()
		comp.owner.state_custom_2 = true
		return
	end

	if debug == "RESTART" then
		return #asm > 0
	elseif debug == "SETCOUNTER" then
		state.debug = "PAUSE"
		state.counter = counter
	elseif debug ~= "STOP" then
		state.debug = "PAUSE"
	end

	comp:Shutdown()
	UpdateEntityBehaviorState(comp.owner, comp)
end

function DebugBehavior(comp, debug, counter, breakpoints)
	local state = comp.has_extra_data and comp.extra_data
	if not state or not state.revid then return end
	if breakpoints then state.breakpoints = EmptyTableAsNil(breakpoints) end

	if not debug or debug == "CONTINUE" then
		state.lastcounter = state.counter
		state.debug = (state.breakpoints and 'BREAKPOINT' or nil)
		comp:Activate()
		comp.owner.state_custom_2 = true
	elseif debug == "STOP" then
		data.instructions.exit.func(comp, state)
		comp:Shutdown()
	elseif debug == "STEP" and state.debug then
		state.debug = "STEP"
		comp:Activate()
	elseif debug == "SETCOUNTER" then
		state.debug = "PAUSE"
		state.counter = counter
		comp:Shutdown()
	elseif debug == "CLEAR" then
		SetBehavior(comp, nil)
		comp.extra_data = nil
	elseif debug == "WIPEARRAYS" then
		comp.extra_data.arrays = nil
	else
		state.debug = "PAUSE"
		comp:Shutdown()
	end
end

local BehaviorValidateRules<const> = {
	name         = function(v) return type(v) == "string" end,
	icon         = function(v) return type(v) == "string" end,
	desc         = function(v) return type(v) == "string" end,
	op           = function(v) return type(v) == "table" and type(v.op) == "string" end,
	keepvars     = function(v) return type(v) == "boolean" end,
	keeparrays   = function(v) return type(v) == "string" end,
	parameters   = function(v) if type(v) ~= "table" then return false end for _,w in ipairs(v) do if type(w) ~= "boolean"               then return false end end end,
	pnames       = function(v) if type(v) ~= "table" then return false end for _,w in ipairs(v) do if type(w) ~= "string" and w ~= false then return false end end end,
	pinits       = function(v) if type(v) ~= "table" then return false end for _,w in ipairs(v) do if type(w) ~= "table" and w ~= false  then return false end end end,
	subs         = function(v) if type(v) ~= "table" then return false end for _,w in ipairs(v) do if type(w) ~= "table"                 then return false end ValidateCustomBehavior(w) end end,
	dependencies = function(v) return type(v) == "table" end,
}
function ValidateCustomBehavior(code)
	for k,v in pairs(code) do
		local rule = BehaviorValidateRules[type(k) == "number" and "op" or k]
		if not rule or rule(v) == false then code[k] = nil end -- remove bad or unknown field
	end
	return code[1]
end

local BlueprintValidateRules BlueprintValidateRules = {
	frame = function(v, bp, is_multi) -- matches ValidBlueprintEntity function in UI
		local def = data.frames[v]
		if is_multi then return def and def.type ~= "Foundation" and def.visual and def.construction_recipe or false end
		return def and def.type ~= "Foundation" or false
	end,
	name             = function(v) return type(v) == "string" end,
	icon             = function(v) return type(v) == "string" end,
	desc             = function(v) return type(v) == "string" end,
	powered_down     = function(v) return type(v) == "boolean" end,
	disconnected     = function(v) return type(v) == "boolean" end,
	logistics        = function(v) if type(v) ~= "table" then return false end for _,w in  pairs(v) do if type(w) ~= "boolean"                       then return false end end end,
	regs             = function(v) if type(v) ~= "table" then return false end for _,w in  pairs(v) do if type(w) ~= "table" and type(w) ~= "number" then return false end end end,
	locks            = function(v) if type(v) ~= "table" then return false end for _,w in ipairs(v) do if type(w) == "table"                         then return false end end end,
	links            = function(v) if type(v) ~= "table" then return false end for _,w in ipairs(v) do if type(w) ~= "table" or #w ~= 2              then return false end end end,
	recurring_orders = function(v) if type(v) ~= "table" then return false end for _,w in ipairs(v) do if type(w) ~= "table" or #w < 2               then return false end end end,
	components       = function(v, bp)
		if type(v) ~= "table" then return false end
		local frame_def = data.frames[bp.frame]
		local visual_def = frame_def and (type(frame_def.visual) == "table" and frame_def.visual or data.visuals[frame_def.visual])
		local sockets, used_sockets, has_integrated_behavior = visual_def and visual_def.sockets, {}
		for i=#v,1,-1 do
			local w, invalid = v[i]
			if type(w) ~= "table" or #w < 2 or type(w[1]) ~= "string" then
				invalid = true
			elseif w[1] == "c_integrated_behavior" then --w[2] can be "hidden" or -1 (backwards compatibility)
				invalid = frame_def.race ~= "robot" or frame_def.no_integrated_behavior or has_integrated_behavior
				if not invalid then has_integrated_behavior = true end
			elseif type(w[2]) == "number" then -- allow hidden/inherent components for register references
				local comp_def, socket_def = data.components[w[1]], sockets and sockets[w[2]]
				invalid = not comp_def or not socket_def or used_sockets[w[2]] or GetAttachmentSize(comp_def.attachment_size) > (GetAttachmentSize(socket_def[2]) or 0)
				if not invalid then used_sockets[w[2]] = true end
			end
			if invalid then table.remove(v, i) end
		end
		return #v > 0
	end,
	params           = function(v, bp, is_multi) if is_multi or type(v) ~= "table" then return false end for _,w in ipairs(v) do if type(w) ~= "table" then return false end end end,
	x                = function(v, bp, is_multi) return is_multi and type(v) == "number" end,
	y                = function(v, bp, is_multi) return is_multi and type(v) == "number" end,
	rotation         = function(v, bp, is_multi) return is_multi and type(v) == "number" end,
	multi            = function(multi, outer_bp, is_multi)
		if type(multi) ~= "table" or is_multi or outer_bp.frame then return false end
		for _,bp in ipairs(multi) do
			for k,v in pairs(bp) do
				local rule = BlueprintValidateRules[k]
				if not rule or rule(v, bp, true) == false then bp[k] = nil end -- remove bad or unknown field
			end
			if not bp.frame then return false end
		end
	end,
	dependencies     = function(v) return type(v) == "table" end, -- TODO: Validate dependency blueprints/behaviors
}
function ValidateCustomBlueprint(bp)
	for k,v in pairs(bp) do
		local rule = BlueprintValidateRules[k]
		if not rule or rule(v, bp) == false then bp[k] = nil end -- remove bad or unknown field
	end
	return bp.frame or bp.multi
end

function FactionHasUnlockedCustomBlueprint(faction, custom_blueprint)
	if custom_blueprint.multi then
		for _,v in ipairs(custom_blueprint.multi) do
			if not FactionHasUnlockedCustomBlueprint(faction, v) then return false end
		end
	else
		if not faction:IsUnlocked(custom_blueprint.frame) then return false end
		--for i,comp in ipairs(custom_blueprint.components or {}) do
		--	if not faction:IsUnlocked(comp[1]) then return false end
		--end
	end
	return true
end

function ProcessLibraryBlueprint(bp, func)
	local org_id, org_rev, org_type, org_folder, org_order = bp.id, bp.rev, bp.type, bp.folder, bp.order
	bp.id, bp.rev, bp.type, bp.folder, bp.order = nil, nil, nil, nil, nil -- library fields
	if bp.reg_values or bp.lock_values or bp.data_name or bp.prefab or bp.race or bp.texture then
		print("blueprint has old fields", bp)
		bp.reg_values, bp.lock_values, bp.data_name, bp.prefab, bp.race, bp.texture = nil, nil, nil, nil, nil, nil
	end
	local res = not func and Tool.Copy(bp) or func(bp)
	bp.id, bp.rev, bp.type, bp.folder, bp.order = org_id, org_rev, org_type, org_folder, org_order
	return res
end

function SetLibraryBlueprintParams(bp, param_vals)
	local multi = bp.multi
	bp.params = nil
	for m=1,(multi and #multi or 1) do
		local unit = multi and multi[m] or bp
		for regkey,v in pairs(unit.regs or {}) do
			if type(v) == "number" then
				unit.regs[regkey] = param_vals[v] and Tool.Copy(param_vals[v]) or nil
			end
		end
		for i,v in pairs(unit.locks or {}) do
			if type(v) == "number" then
				unit.locks[i] = param_vals[v] and (param_vals[v].id or true) or nil
			end
		end
		for i=(unit.recurring_orders and #unit.recurring_orders or 0),1,-1 do
			local v = unit.recurring_orders[i][1]
			if type(v) == "number" then
				unit.recurring_orders[i][1] = param_vals[v] and param_vals[v].id
				unit.recurring_orders[i][2] = param_vals[v] and param_vals[v].num or 0
				if unit.recurring_orders[i][2] <= 0 and unit.recurring_orders[i][2] ~= REG_INFINITE then
					table.remove(unit.recurring_orders, i)
					unit.recurring_orders = EmptyTableAsNil(unit.recurring_orders)
				end
			end
		end
	end
end

function BlueprintTransform(bp_multi, rotate, flipx, flipy, return_frame_size)
	local minx, maxx, miny, maxy = 9999999999, -9999999999, 9999999999, -9999999999
	for loop=0,1 do
		for i=1,#bp_multi do
			local m = bp_multi[i]
			local x, y, rot = m.x, m.y, m.rotation or 0
			local frame_def = data.frames[m.frame]
			local visual_def = frame_def and (type(frame_def.visual) == "table" and frame_def.visual or data.visuals[frame_def.visual]) or data.visuals[m.visual]
			local size, cflip = visual_def and visual_def.tile_size, (rot & 1) == 1
			local sizex, sizey = size and size[cflip and 2 or 1] or 1, size and size[cflip and 1 or 2] or 1
			if loop == 0 then -- measure min/max
				minx, miny, maxx, maxy = math.min(minx, x), math.min(miny, y), math.max(maxx, x+sizex), math.max(maxy, y+sizey)
				if return_frame_size then m.sizex, m.sizey = visual_def and sizex, sizey end
			else -- apply
				if     rotate == 0 then x, y, rot = x - minx,         y - miny,         (rot    ) % 4
				elseif rotate == 1 then x, y, rot = y - miny,         maxx - x - sizex, (rot + 1) % 4
				elseif rotate == 2 then x, y, rot = maxx - x - sizex, maxy - y - sizey, (rot + 2) % 4
				elseif rotate == 3 then x, y, rot = maxy - y - sizey, x - minx,         (rot + 3) % 4 end
				if flipx or flipy then
					local fx, fy = maxx - minx, maxy - miny
					if rotate and rotate & 1 == 1 then fx, fy, sizex, sizey = fy, fx, sizey, sizex end
					if flipx then x, rot = fx - x - sizex, (rot + (sizex > sizey and 2 or 0)) % 4 end
					if flipy then y, rot = fy - y - sizey, (rot + (sizey > sizex and 2 or 0)) % 4 end
				end
				m.x, m.y, m.rotation = x, y, (rot ~= 0 and rot or nil)
			end
		end
		if loop == 0 and (rotate or 0) == 0 and not flipx and not flipy and minx == 0 and miny == 0 then break end
	end
end

local iter_nothing, iter_components = function() end, function(bp_components, i)
	while true do
		i = i + 1
		local comp = bp_components[i]
		if not comp then return end
		local comp_id, payload = comp[1], comp[3]
		local payload_comp_def = payload and data.components[comp_id]
		local payload_base_id = payload_comp_def and payload_comp_def.base_id
		if payload_base_id then return i, comp, payload, payload_base_id end
	end
end
local function iblueprintcomponents(tbl)
	local comps = tbl.components
	if comps then return iter_components, comps, 0 end
	local multi = tbl.multi
	if not multi then return iter_nothing end
	local iter_multi_temp
	return function(tbl_multi, i)
		while true do
			if iter_multi_temp then
				local comp_idx, comp, payload, payload_base_id = iter_components(iter_multi_temp, i & 0xFFF)
				i = i & 0xFFFF000
				if comp then return i | comp_idx, comp, payload, payload_base_id end
			end
			i = i + 0x1000
			local bp = tbl_multi[i >> 12]
			if not bp then return end
			iter_multi_temp = bp.components
		end
	end, multi, 0
end

local function UnpackOldCompactedItemToLibraryTable(tbl, ttype, out, sub_mapping, sub_id) -- tbl will get modified by this (caller needs to Tool.Copy if needed)
	if type(tbl) ~= "table" then
		if type(tbl) == "string" then tbl = Tool.StringToTable(tbl) end
		if type(tbl) ~= "table" then print('[LIBRARY] invalid embedded item', tbl) return 1 end
	end

	local tbl_id = sub_id or (#out + 1)
	out[tbl_id] = tbl
	tbl.type, tbl.id, tbl.rev = ttype, tbl_id, 1

	if ttype == 'B' then -- blueprint
		for comp_idx,bpcomp,payload,payload_base_id in iblueprintcomponents(tbl) do
			if payload_base_id == 'c_behavior' then
				bpcomp[3] = UnpackOldCompactedItemToLibraryTable(payload, 'C', out)
			elseif payload_base_id == 'c_fabricator' then
				bpcomp[3] = UnpackOldCompactedItemToLibraryTable(payload, 'B', out)
			end
		end
	elseif ttype == 'C' then -- behavior
		if tbl.subs then
			if sub_mapping then print('[LIBRARY] Compacted behavior should only have subs in the most outer table') end
			sub_mapping = {}
			local sub_out_base = #out
			for sub_idx,sub in ipairs(tbl.subs) do
				out[sub_out_base + sub_idx] = false -- to be filled out below
				sub_mapping[sub_idx] = sub_out_base + sub_idx
			end
			for sub_idx,sub in ipairs(tbl.subs) do
				UnpackOldCompactedItemToLibraryTable(sub, 'C', out, sub_mapping, sub_out_base + sub_idx)
			end
			tbl.subs = nil
		end

		for inst_idx,inst in ipairs(tbl) do
			if inst.sub and inst.sub ~= 0 then
				local mapped = sub_mapping and sub_mapping[inst.sub] or nil
				if not mapped then print('[LIBRARY] Compacted behavior references invalid sub: ', inst.sub, mapped) end
				inst.sub = mapped
			elseif inst.bp and inst.bp ~= 0 then
				inst.bp = UnpackOldCompactedItemToLibraryTable(inst.bp, 'B', out)
			end
		end
	else error('Unknown library item') end

	return tbl_id
end

local function UnpackCompactedItemToLibraryTable(tbl, ttype, out, ...) -- tbl will get modified by this (caller needs to Tool.Copy if needed)
	local outer_dependencies = ...
	local dependencies = outer_dependencies or tbl.dependencies
	if not dependencies then -- potentially in old format
		return UnpackOldCompactedItemToLibraryTable(tbl, ttype, out)
	end

	local tbl_id = 1
	if outer_dependencies then
		if type(tbl) ~= "number" then print('[LIBRARY] invalid reference', tbl) return 1 end
		if tbl == -1 then return 1 end -- -1 denotes reference to outer
		tbl_id = tbl + 1
		if out[tbl_id] then return tbl_id end -- already processed
		tbl = dependencies[tbl]
		if type(tbl) ~= "table" then print('[LIBRARY] invalid reference', tbl) return 1 end
	end

	out[tbl_id] = tbl
	tbl.type, tbl.id, tbl.rev = ttype, tbl_id, 1

	if ttype == 'B' then -- blueprint
		for comp_idx,bpcomp,payload,payload_base_id in iblueprintcomponents(tbl) do
			if payload_base_id == 'c_behavior' then
				bpcomp[3] = UnpackCompactedItemToLibraryTable(payload, 'C', out, dependencies)
			elseif payload_base_id == 'c_fabricator' then
				bpcomp[3] = UnpackCompactedItemToLibraryTable(payload, 'B', out, dependencies)
			end
		end
	elseif ttype == 'C' then -- behavior
		for inst_idx,inst in ipairs(tbl) do
			if inst.sub and inst.sub ~= 0 then
				inst.sub = UnpackCompactedItemToLibraryTable(inst.sub, 'C', out, dependencies)
			elseif inst.bp and inst.bp ~= 0 then
				inst.bp = UnpackCompactedItemToLibraryTable(inst.bp, 'B', out, dependencies)
			end
		end
	else error('Unknown library item') end

	if not outer_dependencies then tbl.dependencies = nil end
	return tbl_id
end

local function PackLibraryItemToCompactedItem(library_or_factionholder, id_or_item, item_type, outer, skip_self_as_dependency) -- item won't get modified by this
	local id, library_item = type(id_or_item) == "number" and id_or_item, id_or_item
	if id then
		if type(library_or_factionholder) ~= "table" then library_or_factionholder = library_or_factionholder.faction.extra_data.library end
		library_item = library_or_factionholder and library_or_factionholder[id]
	end
	if not library_item then return nil end
	if library_item.type and item_type ~= library_item.type then print("library item type didn't match", library_item.type, item_type) return end

	local item, depnum = Tool.Copy(library_item)
	if outer and not skip_self_as_dependency then
		local item_id = library_item.id
		if item_id and item_id == outer.id then
			return -1 -- -1 denotes reference to outer
		end
		local depnums, dependencies = outer.depnums
		if not depnums then
			depnums, dependencies = {}, {}
			outer.depnums, outer.dependencies = depnums, dependencies
		elseif depnums[item_id] then
			return depnums[item_id]
		else
			dependencies = outer.dependencies
		end
		depnum = #dependencies + 1
		dependencies[depnum] = item
		if item_id then depnums[item_id] = depnum end
	end

	if item_type == 'B' then
		for comp_idx,bpcomp,payload,payload_base_id in iblueprintcomponents(item) do
			if payload_base_id == 'c_behavior' and payload ~= 0 then
				bpcomp[3] = PackLibraryItemToCompactedItem(library_or_factionholder, payload, 'C', outer or item)
			elseif payload_base_id == 'c_fabricator' then
				bpcomp[3] = PackLibraryItemToCompactedItem(library_or_factionholder, payload, 'B', outer or item)
			end
		end
	elseif item_type == 'C' then
		for inst_idx,inst in ipairs(item) do
			if inst.sub and inst.sub ~= 0 then
				inst.sub = PackLibraryItemToCompactedItem(library_or_factionholder, inst.sub, 'C', outer or item)
			elseif inst.bp and inst.bp ~= 0 then
				inst.bp = PackLibraryItemToCompactedItem(library_or_factionholder, inst.bp, 'B', outer or item)
			end
		end
	else error('Unknown library item') end

	-- Remove library fields (after dependencies have been evaluated, so self recursion can be detected with id above)
	item.id, item.rev, item.type, item.folder, item.order = nil, nil, nil, nil, nil

	-- For dependencies just return the dependency number
	if depnum then return depnum end

	-- For the outer item clean up dependencies then return the item table with everything
	item.depnums = nil
	return item
end

local function BlueprintHasNestedItems(bp, parent) -- provided for backward compatiblity (new correct blueprints would only need to check if .dependencies exists or not)
	local deps = (parent or bp).dependencies
	for comp_idx,bpcomp,payload,payload_base_id in iblueprintcomponents(bp) do
		local is_dep, is_table = deps and deps[payload], type(payload) == "table"
		if payload_base_id == 'c_behavior' and (is_dep or is_table) then return true end
		if payload_base_id == 'c_fabricator' and (is_dep or (is_table and (parent or BlueprintHasNestedItems(payload, bp)))) then return true end
	end
	return false
end

local function LibraryHashItem(library, item, out_deps, ...)
	local first_pass_child
	if ... then -- more arguments means called by LibraryHashItem
		local dep_item_id, reflist, refidx, dep_item_type = item, ...
		reflist[refidx] = dep_item_id
		item = library[dep_item_id]
		if not item then out_deps[dep_item_id] = false return 0 end -- item was probably deleted
		if item.type ~= dep_item_type then print("[LibraryHashItem] Unexpected type", item.type, "of dependency", dep_item_id) return 0 end

		if not out_deps.second_pass then
			local hash = out_deps[dep_item_id]
			if hash then
				if hash == true then -- detected recursion
					out_deps.recursion = true
					if out_deps.out_recursion then out_deps.out_recursion[dep_item_id] = true end -- if the caller is interested in this
				end
				return hash
			end
			first_pass_child = true
		elseif out_deps[dep_item_id] then
			return true -- reached recursing point
		end
	end

	local item_id, item_rev, item_type, item_folder, item_order = item.id, item.rev, item.type, item.folder, item.order

	out_deps[item_id] = true -- for recursion detection
	local bp_payloads, code_subs, code_bps
	if item_type == 'B' then
		for comp_idx,bpcomp,payload,payload_base_id in iblueprintcomponents(item) do
			if payload_base_id == 'c_behavior' and payload ~= 0 then
				if not bp_payloads then bp_payloads = {} end
				bpcomp[3] = LibraryHashItem(library, payload, out_deps, bp_payloads, comp_idx, 'C')
			elseif payload_base_id == 'c_fabricator' then
				if not bp_payloads then bp_payloads = {} end
				bpcomp[3] = LibraryHashItem(library, payload, out_deps, bp_payloads, comp_idx, 'B')
			end
		end
	elseif item_type == 'C' then
		for inst_idx,inst in ipairs(item) do
			if inst.sub and inst.sub ~= 0 then
				if not code_subs then code_subs = {} end
				inst.sub = LibraryHashItem(library, inst.sub, out_deps, code_subs, inst_idx, 'C')
			elseif inst.bp and inst.bp ~= 0 then
				if not code_bps then code_bps = {} end
				inst.bp = LibraryHashItem(library, inst.bp, out_deps, code_bps, inst_idx, 'B')
			end
		end
	else error('[LIBRARY] Unknown item type') end

	item.id, item.rev, item.folder, item.order = nil, nil, nil, nil
	local hash = Tool.Hash(item)
	item.id, item.rev, item.folder, item.order = item_id, item_rev, item_folder, item_order

	if bp_payloads then
		for comp_idx,v in pairs(bp_payloads) do
			if comp_idx <= 0xFFF then -- see iblueprintcomponents
				item.components[comp_idx][3] = v
			else
				item.multi[comp_idx >> 12].components[comp_idx & 0xFFF][3] = v
			end
		end
	end
	if code_subs then
		for inst_idx,inst_sub in pairs(code_subs) do
			item[inst_idx].sub = inst_sub
		end
	end
	if code_bps then
		for inst_idx,inst_bp in pairs(code_bps) do
			item[inst_idx].bp = inst_bp
		end
	end

	if first_pass_child then
		if out_deps.recursion then
			-- After encountering recursion, any child needs to be re-evaluated starting from it.
			-- For example, in a recursion like A->B->C->A, B needs to be hashed as B->C->A->B.
			-- So we run a second pass where out_deps is just used for recursion detection.
			out_deps[item_id] = LibraryHashItem(library, item, { second_pass = true, [item_id] = true })
		else
			out_deps[item_id] = hash
		end
	else
		if out_deps.recursion then out_deps.recursion = nil end
		out_deps[item_id] = nil
	end

	return hash
end

local function LibraryGetAllHashes(library, opt_type_name_table)
	if not library then return {} end
	local id_hashes, hash_ids = {}, {}
	for id,v in pairs(library) do
		if not id_hashes[id] then id_hashes[id] = LibraryHashItem(library, v, id_hashes) end
		if opt_type_name_table and v.name then opt_type_name_table[v.type][v.name] = id end
	end
	for id,hash in pairs(id_hashes) do hash_ids[hash] = id end
	return hash_ids
end

local function LibraryApplyMapping(item, mapping)
	local item_type = item.type
	if item_type == 'B' then
		for comp_idx,bpcomp,payload,payload_base_id in iblueprintcomponents(item) do
			if payload_base_id == 'c_behavior' or payload_base_id == 'c_fabricator' then
				local mapped = mapping[payload]
				if mapped == nil then error('library import of blueprint has missed mapping from blueprint ' .. tostring(payload)) end
				bpcomp[3] = mapped or nil -- convert false (explicitly ignore) to nil
			end
		end
	elseif item_type == 'C' then
		for _,inst in ipairs(item) do
			if inst.sub and inst.sub ~= 0 then
				if not mapping[inst.sub] then error('library import of behavior has missed mapping from behavior ' .. tostring(inst.sub)) end
				inst.sub = mapping[inst.sub]
			elseif inst.bp and inst.bp ~= 0 then
				local mapped = mapping[inst.bp]
				if mapped == nil then error('library import of behavior has missed mapping from blueprint ' .. tostring(inst.bp)) end
				inst.bp = mapped or nil -- convert false (explicitly ignore) to nil
			end
		end
	else error('Unknown library item') end
	return item
end

local function LibraryPerformImport(library_owner, temp_library, temp_hashes, mapping, library_id_count_owner, default_folder)
	local library = library_owner.library
	if not library then library = {} library_owner.library = library end
	local library_hashes = LibraryGetAllHashes(library)
	local id_count = library_id_count_owner.library_id_count or 0
	for temp_id, temp_hash in pairs(temp_hashes) do
		local target_id = library_hashes[temp_hash]
		if target_id then -- already existing
			mapping[temp_id] = target_id
			temp_hashes[temp_id] = false -- mark as no import required
		elseif temp_hash then
			id_count = id_count + 1
			library_id_count_owner.library_id_count = id_count
			mapping[temp_id] = id_count
			library_hashes[temp_hash] = id_count
		end
	end

	for temp_id, temp_hash in pairs(temp_hashes) do
		local mapped, item = mapping[temp_id], temp_library[temp_id]
		if temp_hash then -- import required
			LibraryApplyMapping(item, mapping)
			item.id, item.rev, item.folder = mapped, item.rev or 1, (item.folder ~= -1 and (item.folder or default_folder) or nil)
			library[item.id] = item
		elseif mapped == item then -- apply mapping to embedded blueprint (for ImportBlueprint)
			LibraryApplyMapping(item, mapping)
			item.id, item.rev, item.type, item.folder, item.order = nil, nil, nil, nil, nil
		end
	end
	return mapping[1] -- return the id of the first item in the temp_library
end

function UploadBehavior(comp, main, debug, counter) -- main will get modified by this (caller needs to Tool.Copy if needed)
	local temp_library, temp_hashes = {}, {}
	UnpackCompactedItemToLibraryTable(main, 'C', temp_library)
	temp_hashes[1] = LibraryHashItem(temp_library, main, temp_hashes)
	local id = LibraryPerformImport(comp.faction.extra_data, temp_library, temp_hashes, {}, Map.GetSave())
	SetBehavior(comp, id, debug, counter)
end

-- Passing true for include_internals will make it include non-default visuals and hidden components
function MakeBlueprintFromEntity(entity_or_entities, allow_construction, include_internals, skip_dependency_embed)
	local single_entity, res, multi_frames, multi_min_x, multi_min_y = type(entity_or_entities) ~= "table" and entity_or_entities
	local num_entities = (single_entity and 1 or #entity_or_entities)
	if num_entities > 1 then
		multi_frames = {}
		res = { multi = multi_frames }
	end

	for entity_index=1,num_entities do
		local entity, bp = single_entity or entity_or_entities[entity_index]

		if entity.is_construction then
			if not allow_construction then return end
			local id, bpref, have_internals = GetConstructionSiteIdOrBP(entity, true, true)
			if id or (bpref and not BlueprintIsCustomized(bpref)) then
				bp = { frame = id or bpref.frame }
			elseif bpref then
				if bpref.id then error("[MakeBlueprintFromEntity] Construction blueprint is not expected to have an id") end
				if not bpref.frame then error("[MakeBlueprintFromEntity] Construction blueprint is expected to have frame set") end
				bp = (skip_dependency_embed or have_internals) and Tool.Copy(bpref) or PackLibraryItemToCompactedItem(entity, bpref, 'B', res, true)
				if have_internals then
					-- Everything added with include_internals below needs to be cleaned up again here (avoid internal state getting cloned)
					bp.visual, bp.spawn_extra_data, bp.damage = nil, nil, nil -- clear internal fields
					local comps, regs, links = bp.components, bp.regs, bp.links
					for i=(comps and #comps or 0),1,-1 do -- clean up components
						local comp = comps[i]
						local payload_comp_def = comp[3] and data.components[comp[1]]
						local payload_base_id = payload_comp_def and payload_comp_def.base_id
						if payload_base_id == "c_deployer" or payload_base_id == "c_resimulator" then
							comp[3] = nil
						end
						if not comp[3] and (comp[2] == "hidden" or comp[2] == "inherent") then
							-- For hidden/inherent components without payload we need to find any register references to this components (and if there are none, remove the component and decrement component indices in register references)
							local function get_comp_idx(k) return tonumber(string.match(k, "(%d+)|")) or 0 end
							if regs then for k,v in pairs(regs) do if get_comp_idx(k) == i then goto has_reg_ref end end end
							if links then for _,v in ipairs(links) do if get_comp_idx(v[1]) == i or get_comp_idx(v[2]) == i then goto has_reg_ref end end end
							local function decrement_idx(k) local ki = get_comp_idx(k) return ki > i and string.gsub(k, '%d+|', (ki-1)..'|') or k end
							if regs then local newr = {} for k,v in pairs(regs) do newr[decrement_idx(k)] = v end regs, bp.regs = newr, newr end
							if links then for _,v in ipairs(links) do v[1], v[2] = decrement_idx(v[1]), decrement_idx(v[2]) end end
							table.remove(comps, i)
							::has_reg_ref::
						end
					end
					if skip_dependency_embed and bp.dependencies then
						local bp_library, bp_hashes, mapping, faction_names = {}, {}, {}, {B={},C={}}
						UnpackCompactedItemToLibraryTable(bp, 'B', bp_library)
						if bp ~= bp_library[1] then error("unexpected") end
						local faction_hashes = LibraryGetAllHashes(entity.faction.extra_data.library, faction_names)
						for bp_id,v in ipairs(bp_library) do
							local hash = bp_hashes[bp_id]
							if not hash and bp_id ~= 1 then hash = LibraryHashItem(bp_library, v, bp_hashes) bp_hashes[bp_id] = hash end
							mapping[bp_id] = hash and (faction_hashes[hash] or faction_names[v.type][v.name]) or false
						end
						LibraryApplyMapping(bp, mapping)
						bp.type, bp.id, bp.rev = nil -- clear library fields added by UnpackCompactedItemToLibraryTable
					end
				end
			end
		else
			local frame_def = entity.def
			bp = { frame = entity.id }

			if not frame_def.type then -- not for walls/gates
				-- Make a list of components inherited from the frame definition
				local entity_components, entity_links, frame_def_components, inherent_comps = entity.components, entity:GetRegisterLinks(), frame_def.components
				if frame_def_components then
					for _,v in ipairs(frame_def_components) do
						inherent_comps = inherent_comps or {}
						inherent_comps[v[1]] = (inherent_comps[v[1]] or 0) + 1
					end
				end

				-- Fill out frame registers
				local reg_map, bp_frame_regs, regs = {}, FRAMEREG_COUNT --entity.frame_register_count
				local function AddReg(idx, map, skip_val)
					reg_map[idx] = map
					if skip_val or entity:RegisterIsEmpty(idx) or entity:RegisterIsLink(idx) then return end
					if not regs then regs = {} bp.regs = regs end
					local reg = entity:GetRegister(idx)
					local reg_id, reg_num, reg_entity, reg_coord = reg.id, reg.num
					if not reg_id then reg_entity = reg.entity if not reg_entity then reg_coord = reg.coord end end
					if reg_num == 0 and (reg_id or reg_entity or reg_coord) then reg_num = nil end
					regs[map] = { id = reg_id, entity = reg_entity, coord = reg_coord, num = reg_num }
					if (idx == -FRAMEREG_GOTO or idx == -FRAMEREG_STORE) and entity:RegisterQueueLength(idx) > 1 then
						local arr = entity:RegisterQueueGetAll(idx)
						table.remove(arr, 1)
						for i,v in ipairs(arr) do arr[i] = { id = v.id, entity = v.entity, coord = v.coord, num = (v.num ~= 0 and v.num or nil) } end
						regs[map].queue = arr
					end
					return true
				end
				for i=1,bp_frame_regs do AddReg(i, i) end
				--if bp_frame_regs ~= FRAMEREG_COUNT then res.frame_regs = bp_frame_regs end

				-- Fill list of components including active behaviors and production blueprints
				local deps, components, links, locks, logistics = res or bp
				for _,comp in ipairs(entity_components) do
					local id, def, hidden, reg_num = comp.id, comp.def, comp.is_hidden, comp.register_count
					if def.transient then goto skip_component end

					-- Set component, active behavior program and deployer blueprint
					local base_id, bpcomp_3, bpcomp_4 = comp.base_id
					if base_id == "c_behavior" and comp.has_extra_data then
						local beh_id = comp.extra_data.main_id
						if beh_id then bpcomp_3 = skip_dependency_embed and beh_id or PackLibraryItemToCompactedItem(comp, beh_id, 'C', deps) end
						if beh_id and not comp.is_active then bpcomp_4 = true end -- remember paused behavior
					elseif base_id == "c_fabricator" and comp.has_extra_data then
						local fab_bp = comp.extra_data.custom_blueprint
						if fab_bp then bpcomp_3 = skip_dependency_embed and fab_bp or PackLibraryItemToCompactedItem(comp, fab_bp, 'B', deps) end
					elseif base_id == "c_deployer" and comp.has_extra_data and include_internals then
						local deployer_bp = comp.extra_data.bp
						if deployer_bp then bpcomp_3 = Tool.TableToString(deployer_bp) end
					elseif base_id == "c_resimulator" and comp.has_extra_data and include_internals then
						bpcomp_3 = Tool.Copy(comp.extra_data)
					end

					-- Fill out components registers
					local bpcomp_idx, relevant, comp_reg_idx, rdefs = (components and #components + 1 or 1), include_internals or (not hidden or bpcomp_3), comp.register_index, def.registers
					for i=1,reg_num do
						relevant = AddReg(comp_reg_idx - 1 + i, string.format('%d|%d', bpcomp_idx, i), rdefs and rdefs[i] and rdefs[i].read_only) or relevant
					end

					-- Figure out if this hidden component has any links to or from its registers (and needs to be stored in the bp)
					if not relevant then
						for _,v in ipairs(entity_links) do
							if math.ult(v.index - comp_reg_idx, reg_num) or math.ult(v.source_index - comp_reg_idx, reg_num) then relevant = true break end
						end
						if not relevant then goto skip_component end
					end

					-- Register relevant component (either is non-hidden, has meta data in bpcomp3 order has registers/links)
					local bpcomp = { id, hidden and "hidden" or comp.socket_index, bpcomp_3, bpcomp_4 }
					if inherent_comps and (inherent_comps[id] or 0) > 0 then inherent_comps[id], bpcomp[2] = inherent_comps[id] - 1, "inherent" end
					if not components then components = {} bp.components = components end
					components[bpcomp_idx] = bpcomp
					::skip_component::
				end

				-- Fill list of register links
				for _,v in ipairs(entity_links) do
					local i_trg, i_src = v.index, v.source_index
					local o_trg, o_src = reg_map[i_trg], reg_map[i_src]
					if o_trg and o_src then
						if not links then links = {} bp.links = links end
						links[#links + 1] = { o_trg, o_src }
					end
				end

				-- Fill list of locked item slots
				for i,slot in ipairs(entity.slots) do
					if slot.locked then
						if not locks then locks = {} bp.locks = locks end
						locks[i] = slot.id or true
					end
				end

				-- Fill logistics settings
				for _,v in ipairs(data.logistics_flags) do
					if v.flag then
						if v.flag then
							local flag = entity["logistics_" .. v.flag]
							if flag ~= v.default then
								if not logistics then logistics = {} bp.logistics = logistics end
								logistics[v.flag] = flag
							end
						end
					end
				end

				-- Entity info
				local disconnected, disconnected_default = entity.disconnected, frame_def.start_disconnected or false
				if entity.powered_down then bp.powered_down = true end
				if disconnected ~= disconnected_default then bp.disconnected = disconnected end
			end

			-- Recurring orders
			for i,o in ipairs(entity.faction:GetActiveOrders(entity)) do
				if o.target_entity == entity and o.recurring then
					bp.recurring_orders = bp.recurring_orders or {}
					bp.recurring_orders[#bp.recurring_orders+1] = { o.item_id, o.amount, o.channel_bitmask }
				end
			end

			-- Entity name
			local ed = entity.has_extra_data and entity.extra_data
			local name = ed and ed.name
			if name then bp.name = name end

			if include_internals then
				local visual_id, ed_first_key = entity.visual_id, ed and next(ed)
				if visual_id ~= frame_def.visual and frame_def.type ~= "Wall" then bp.visual = visual_id end
				if ed_first_key and (ed_first_key ~= 'name' or next(ed, ed_first_key)) then bp.spawn_extra_data = Tool.Copy(entity.extra_data) end
				if entity.is_damaged then bp.damage = entity.max_health - entity.health end
			end
		end

		if not multi_frames then
			-- Clean up temporary table added and used by PackLibraryItemToCompactedItem in the loop above
			if bp then bp.depnums = nil end

			return bp
		end

		if bp then
			local loc, rotation = entity.placed_location, entity.rotation
			local x, y = loc.x, loc.y
			bp.x, bp.y, bp.rotation = x, y, (rotation > 0 and rotation or nil)
			multi_frames[#multi_frames+1] = bp
			multi_min_x, multi_min_y = (multi_min_x and math.min(multi_min_x, x) or x), (multi_min_y and math.min(multi_min_y, y) or y)
		end
	end

	-- Clean up temporary table added and used by PackLibraryItemToCompactedItem in the loop above
	res.depnums = nil

	if #multi_frames == 0 then return end
	if #multi_frames == 1 then local bp = multi_frames[1] bp.x, bp.y, bp.rotation = nil, nil, nil return bp end

	for i,bp in ipairs(multi_frames) do
		bp.x, bp.y = bp.x - multi_min_x, bp.y - multi_min_y
		if bp.regs then
			for _,reg in pairs(bp.regs) do
				local reg_queue = reg.queue
				for q=0,(reg_queue and #reg_queue or 0) do
					local r = (q == 0 and reg or reg_queue[q])
					local reg_entity = r.entity
					if reg_entity then
						for entity_index,entity in ipairs(entity_or_entities) do
							if reg_entity == entity then
								r.entity = entity_index
								break
							end
						end
					end
				end
			end
		end
	end

	return res
end

local function ImportBlueprint(faction, bp, folder, only_dependencies)  -- bp will get modified by this (caller needs to Tool.Copy if needed)
	-- Hash all nested items of this blueprint to dep_hashes
	local temp_library, temp_hashes, mapping = {}, {}, {}
	UnpackCompactedItemToLibraryTable(bp, 'B', temp_library)
	local bp_hash = LibraryHashItem(temp_library, bp, temp_hashes)

	if only_dependencies then
		-- Blueprints in production components stay embedded (only behaviors and blueprints used by behaviors are imported to the library)
		for comp_idx,bpcomp,payload,payload_base_id in iblueprintcomponents(bp) do -- payload is a library id after UnpackCompactedItemToLibraryTable
			if payload_base_id == 'c_fabricator' then
				temp_hashes[payload] = false -- make LibraryPerformImport not import it
				mapping[payload] = temp_library[payload] -- make LibraryApplyMapping embed it
			end
		end
	else
		temp_hashes[1] = bp_hash
	end

	-- Perform import of any nested behaviors and blueprints used by behaviors (and the blueprint ifself unless only_dependencies) into the faction library
	LibraryPerformImport(faction.extra_data, temp_library, temp_hashes, mapping, Map.GetSave(), folder)
	if only_dependencies then
		LibraryApplyMapping(bp, mapping)
		bp.id, bp.rev, bp.type = nil, nil, nil -- after LibraryApplyMapping, remove temp fields added by UnpackCompactedItemToLibraryTable
		return bp
	end
end

local function ConvertOldBlueprint(bp_components, bp_regs, bp_links, entity)
	-- Detect oldfmt format which referenced component registers via just an index instead of an encoded string
	if not bp_components then return end
	if bp_regs then for k,_ in pairs(bp_regs) do if type(k) == "string" then return end if k > 4 then goto oldfmt end end end
	if bp_links then for _,v in pairs(bp_links) do if type(v[1]) == "string" or type(v[2]) == "string" then return end if v[1] > 4 or v[2] > 4 then goto oldfmt end end end
	do return end -- not in old format

	::oldfmt::
	local bp_reg_ofs, linkmap = FRAMEREG_COUNT --bp.frame_regs or FRAMEREG_COUNT
	for bpcomp_idx,v in ipairs(bp_components) do
		local comp_def, bp_reg_num = data.components[v[1]]
		if not comp_def then print("Unknown component in old blueprint", v[1]) end -- likely registers will shift after encountering an invalid component
		local code = v[3] and type(v[3]) == "number" and comp_def and comp_def.base_id == "c_behavior" and (entity and entity.faction.extra_data.library or Game.GetProfile().library)[v[3]]
		bp_reg_num = (code and (v[4] or (type(code.parameters) == "table" and #code.parameters) or 0)) or (comp_def and comp_def.registers and #comp_def.registers) or 0
		for i=1,bp_reg_num do
			local idx, map = bp_reg_ofs + i, string.format('%d|%d', bpcomp_idx, i)
			if bp_regs then local r = bp_regs[idx] if r then bp_regs[map], bp_regs[idx] = r, nil end end
			if bp_links then linkmap = linkmap or {} linkmap[idx] = map end
		end
		bp_reg_ofs = bp_reg_ofs + bp_reg_num
	end
	if bp_links then for _,v in pairs(bp_links) do local l1, l2 = linkmap[v[1]], linkmap[v[2]] if l1 then v[1] = l1 end if l2 then v[2] = l2 end end end
end

function BlueprintIsCustomized(bp)
	local first_key = next(bp)
	return first_key and (first_key ~= 'frame' or next(bp, first_key))
end

function ApplyBlueprintToEntity(entity, bp)
	if entity.is_construction then error("[ApplyBlueprintToEntity] Cannot apply to construction") end
	if bp.rev then print("[ApplyBlueprintToEntity] Called with raw library blueprint") end
	local frame_def, bp_disconnected, bp_powered_down = entity.def
	if not frame_def.type then -- not for walls/gates
		local imported_bp = BlueprintHasNestedItems(bp) and ImportBlueprint(entity.faction, Tool.Copy(bp), "Imported", true)
		if imported_bp then bp = imported_bp end
		local bp_components, bp_regs, bp_links, bp_locks = bp.components, bp.regs, bp.links, bp.locks
		ConvertOldBlueprint(bp_components, bp_regs, bp_links, entity)

		-- Prepare register index mapping and apply frame registers
		local linkmap, bp_frame_regs = bp_links and {}, FRAMEREG_COUNT --bp.frame_regs or FRAMEREG_COUNT
		for i=1,math.min(entity.frame_register_count, bp_frame_regs) do
			local reg = bp_regs and bp_regs[i]
			entity:SetRegister(i, reg)
			if linkmap then linkmap[i] = i end
			if (i == -FRAMEREG_GOTO or i == -FRAMEREG_STORE) and reg and reg.queue then
				for queue_idx,v in ipairs(reg.queue) do
					entity:RegisterQueueSet(i, v, 1 + queue_idx)
				end
			end
		end
		local integrated_on_entity, integrated_in_bp = entity:FindComponent("c_integrated_behavior")
		if bp_components then
			for _,v in ipairs(bp_components) do if v[1] == "c_integrated_behavior" then integrated_in_bp = true break end end
		end
		if not integrated_in_bp and integrated_on_entity then
			integrated_on_entity:Destroy()
		end
		if bp_components then -- Generate mapping from components in blueprint to components in entity
			if integrated_in_bp and not integrated_on_entity and entity.def.race == "robot" and not entity.def.no_integrated_behavior then
				entity:AddComponent("c_integrated_behavior")
			end
			if not imported_bp then bp_components = Tool.Copy(bp_components) end -- deep copy now to take ownership of the content used and modified below
			local bp_components_used = 0

			local function ApplyComponent(comp, bpcomp_idx, v, bpcomp_def)
				v[1] = false -- use only once
				local base_id = bpcomp_def.base_id
				if base_id == "c_behavior" then
					if type(v[3]) ~= "number" then DebugBehavior(comp, "CLEAR")
					elseif SetBehavior(comp, v[3], v[4] and "STOP") == false then comp.register_count = 0 end -- v[4] means behavior was paused
				elseif base_id == "c_fabricator" then
					if type(v[3]) == "number" then -- Otherwise blueprints in production components are embedded (also done by ImportBlueprint)
						local library = comp.faction.extra_data.library
						v[3] = library and Tool.Copy(library[v[3]]) or nil
						if v[3] then v[3].id, v[3].rev, v[3].type, v[3].folder, v[3].order = nil end -- no library fields while stored in component
					end
					if v[3] then
						comp.extra_data.custom_blueprint = v[3] -- don't deep copy v[3]
					elseif comp.has_extra_data then
						local ed = comp.extra_data
						ed.custom_blueprint = nil
						if not next(ed) then comp.extra_data = nil end
					end
				end
				local reg_ofs, regdefs = comp.register_index - 1, comp.def.registers
				for i=1,comp.register_count do
					local regdef, r, o = regdefs and regdefs[i], reg_ofs+i, string.format('%d|%d', bpcomp_idx, i)
					if not regdef or not regdef.read_only then entity:SetRegister(r, bp_regs and bp_regs[o]) end
					if linkmap then linkmap[o] = r end
				end
				bp_components_used = bp_components_used + 1
			end

			-- First match and apply components directly by id, in a second loop match by base_id
			local entity_components = entity.components
			for comp_idx,comp in ipairs(entity_components) do
				local id = comp.id
				for bpcomp_idx,v in ipairs(bp_components) do if v[1] == id then ApplyComponent(comp, bpcomp_idx, v, comp.def) entity_components[comp_idx] = false break end end
			end
			if bp_components_used ~= #bp_components then
				for _,comp in ipairs(entity_components) do
					if comp then
						local bid, defs, def = comp.base_id, data.components
						for bpcomp_idx,v in ipairs(bp_components) do def = defs[v[1]] if def and def.base_id == bid then ApplyComponent(comp, bpcomp_idx, v, def) break end end
					end
				end
			end
		end

		-- Apply register links
		if bp_links then
			for _,v in ipairs(bp_links) do
				local trg, src = linkmap[v[1]], linkmap[v[2]]
				if trg and src then entity:LinkRegisterFromRegister(trg, src) end
			end
		end

		-- Apply locked item slots, clear anything not set
		for i,slot in ipairs(entity.slots) do
			local bp_lock = bp_locks and bp_locks[i]
			if bp_lock and bp_lock ~= true then
				slot:SetLockedItem(bp_lock)
				if bp_lock and bp_lock ~= true and slot.id ~= bp_lock then slot.locked = false end
			else
				slot.locked = bp_lock or false
			end
		end

		-- Clear and apply recurring orders
		for i,o in ipairs(entity.faction:GetActiveOrders(entity)) do
			if o.target_entity == entity and o.recurring then
				entity.faction:CancelOrder(o.id)
			end
		end
		if bp.recurring_orders then
			for _,v in ipairs(bp.recurring_orders) do
				entity:OrderItem(v[1], v[2], "Recurring", v[3])
			end
		end

		-- Apply disconnect and power down only on entities with components/items/registers
		bp_disconnected, bp_powered_down = bp.disconnected, bp.powered_down
		if bp_disconnected == nil then bp_disconnected = (data.frames[bp.frame] or frame_def).start_disconnected or false end
	end

	-- Apply logistics settings (revert to defaults if entity has no item slots)
	local bp_logistics, bp_name = (entity.slot_count > 0 and bp.logistics or nil), bp.name
	for _,v in ipairs(data.logistics_flags) do
		if v.flag then
			if v.flag ~= 'carrier' or IsBot(entity) then
				local val = bp_logistics and bp_logistics[v.flag]
				if val == nil then val = v.default end
				entity["logistics_" .. v.flag] = val
			end
		end
	end

	-- Set entity info
	entity.powered_down = bp_powered_down or false
	entity.disconnected = bp_disconnected or (bp_disconnected == nil and frame_def.start_disconnected) or false

	-- Set entity name
	if bp_name and bp_name ~= "" then
		entity.extra_data.name = bp_name
	elseif entity.has_extra_data and entity.extra_data.name then
		entity.extra_data.name = nil
		if not next(entity.extra_data) then entity.extra_data = nil end
	end
end

function CreateFrameOrBlueprint(faction, def, include_internals, extra_data_collection, component_skip_list, dependency_need_import, replace_entity)
	local is_blueprint = def.data_name ~= "frames"
	local frame_id, entity, pass_items = is_blueprint and def.frame or def.id
	if replace_entity then
		for i=1,replace_entity.slot_count do
			local slot = replace_entity:GetSlot(i)
			local res = slot.unreserved_stack
			if res > 0 then
				local ent = res == 1 and slot.entity
				pass_items = pass_items or {}
				pass_items[#pass_items+1] = { slot.id, res, not ent and slot:Clear(), ent }
				if ent then slot.entity = nil end
			end
		end
		entity = Map.RecreateEntity(replace_entity, frame_id, (include_internals and is_blueprint and def.visual or nil), false, false)
	else
		entity = Map.CreateEntity(faction, frame_id, (include_internals and is_blueprint and def.visual or nil))
	end
	if entity and is_blueprint then
		local imported_bp = dependency_need_import and BlueprintHasNestedItems(def) and ImportBlueprint(entity.faction, Tool.Copy(def), "Imported", true)
		if imported_bp then def = imported_bp end
		local bp_components, bp_regs, bp_links, bp_locks, bp_logistics = def.components, def.regs, def.links, def.locks, def.logistics
		ConvertOldBlueprint(bp_components, bp_regs, bp_links, entity)

		local frame_register_count = entity.frame_register_count
		if frame_register_count then
			-- Prepare register index mapping and apply frame registers
			local reg_map, bp_frame_regs, inherents = (bp_regs or bp_links or bp_components) and {}, FRAMEREG_COUNT --bp.frame_regs or FRAMEREG_COUNT
			if reg_map then for i=1,math.min(frame_register_count, bp_frame_regs) do reg_map[i] = i end end

			-- Add blueprint components
			if bp_components then
				for bpcomp_idx,v in ipairs(bp_components) do
					local comp_id, sock_idx, payload = v[1], ((type(v[2]) == "number" or (include_internals and v[2] == "hidden")) and v[2]), v[3]
					local payload_comp_def = payload and data.components[comp_id]
					local payload_base_id, comp, ed = payload_comp_def and payload_comp_def.base_id
					if component_skip_list and component_skip_list[comp_id] then
						-- no extra_data if removed by skip list below
					elseif payload_base_id == "c_fabricator" then
						if type(payload) == "number" then -- Otherwise blueprints in production components are embedded (also done by ImportBlueprint)
							local library = faction.extra_data.library
							local item = library and Tool.Copy(library[payload])
							if item then ed, item.id, item.rev, item.type, item.folder, item.order = { custom_blueprint = item }, nil end -- no library fields while stored in component
						else
							ed = { custom_blueprint = Tool.Copy(payload) }
						end
					elseif payload_base_id == "c_deployer" and include_internals then
						ed = { bp = (type(payload) == "string" and Tool.StringToTable(payload) or Tool.Copy(payload)) }
					elseif payload_base_id == "c_resimulator" and include_internals then
						ed = Tool.Copy(payload)
					elseif extra_data_collection and extra_data_collection[comp_id] and #extra_data_collection[comp_id] > 0 then
						ed = table.remove(extra_data_collection[comp_id])
					end
					if comp_id == "c_integrated_behavior" then
						if entity.def.race == "robot" and not entity.def.no_integrated_behavior then
							comp = entity:FindComponent(comp_id) or entity:AddComponent(comp_id)
						end
					elseif sock_idx then
						comp = entity:AddComponent(comp_id, sock_idx, ed) or entity:AddComponent(comp_id, "auto", ed)
						if not comp and not entity:AddItem(comp_id, ed) then Map.DropItemAt(entity, comp_id, ed, true) end
					elseif v[2] == "inherent" then
						local inherentnum = 1
						if bpcomp_idx < #bp_components or inherents then
							if not inherents then inherents = {} end
							inherentnum = (inherents[comp_id] or 0) + 1
							inherents[comp_id] = inherentnum
						end
						comp = entity:FindComponent(comp_id, inherentnum)
						if comp and ed then comp.extra_data = ed end
						if not comp then print("[CreateFrameOrBlueprint] Could not find inherent component " .. comp_id) end
					elseif v[2] == "auto" then -- support old alpha blueprints
						comp = entity:AddComponent(comp_id, "auto", ed)
					end
					if comp then
						if payload_base_id == "c_behavior" then
							SetBehavior(comp, payload, v[4] and "STOP") -- v[4] means behavior was paused
						end
						local reg_ofs = comp.register_index - 1
						for i=1,comp.register_count do
							reg_map[string.format('%d|%d', bpcomp_idx, i)] = reg_ofs+i
							reg_map[reg_ofs+i] = true -- remember known registers for link clearing below
						end
					end
				end

				-- Clear any default links made by component adding (clear only known registers, avoid clearing links made on hidden components like behavior events)
				for _,v in ipairs(entity:GetRegisterLinks()) do
					if reg_map[v.index] and reg_map[v.source_index] then
						entity:UnlinkRegisterFromRegister(v.index, v.source_index)
					end
				end
			end

			if reg_map then
				-- Set register values and links
				if bp_regs then
					for k,reg in pairs(bp_regs) do
						local i = reg_map[k]
						if i then
							entity:SetRegister(i, reg)
							if (i == -FRAMEREG_GOTO or i == -FRAMEREG_STORE) and reg and reg.queue then
								for queue_idx,v in ipairs(reg.queue) do
									entity:RegisterQueueSet(i, v, 1 + queue_idx)
								end
							end
						end
					end
				end
				if bp_links then
					for _,v in ipairs(bp_links) do
						if #v == 4 then break end -- skip links of old alpha blueprints
						local trg, src = reg_map[v[1]], reg_map[v[2]]
						if trg and src then entity:LinkRegisterFromRegister(trg, src) end
					end
				end
			end
		end

		-- Set locked item slots
		if bp_locks then
			for i,v in pairs(bp_locks) do
				local slot = entity:GetSlot(i)
				if slot then slot:SetLockedItem(v) if v and v ~= true and slot.id ~= v then slot.locked = false end end
			end
		end

		-- Set logistics settings
		if bp_logistics then
			for v,val in pairs(bp_logistics) do entity["logistics_" .. v] = val end
		end

		-- Recurring orders
		if def.recurring_orders then
			for _,v in ipairs(def.recurring_orders) do
				entity:OrderItem(v[1], v[2], "Recurring", v[3])
			end
		end

		-- Set entity info
		local bp_name, bp_powered_down, bp_disconnected, bp_spawn_extra_data  = def.name, def.powered_down, def.disconnected, def.spawn_extra_data
		if bp_name and bp_name ~= "" then entity.extra_data.name = bp_name end
		if bp_powered_down then entity.powered_down = true end
		if bp_disconnected ~= nil then entity.disconnected = bp_disconnected end
		if bp_spawn_extra_data then entity.extra_data = Tool.Copy(bp_spawn_extra_data) end -- can be used in special cases even without include_internals
		if include_internals and def.damage then entity.health = math.max(entity.health - def.damage, 1) end
	end
	if component_skip_list then -- post-remove skips (so we dont need to patch up register indexes)
		for comp_id,v in pairs(component_skip_list) do
			while v do
				local comp = entity:FindComponent(comp_id)
				if not comp then break end
				comp:Destroy()
			end
		end
	end
	if extra_data_collection then
		for comp_id,arr in pairs(extra_data_collection) do
			for i=1,999 do
				if #arr == 0 then break end
				local comp = entity:FindComponent(comp_id, i)
				if not comp then break end
				if not comp.has_extra_data then comp.extra_data = table.remove(arr) end
			end
		end
	end
	if pass_items then
		for i,v in ipairs(pass_items) do
			local deployer_bp = v[1] == "c_deployer" and v[3] and v[3].onetime and v[3].bp
			local deployer_bp_def = deployer_bp and data.frames[deployer_bp.frame]
			if deployer_bp_def and deployer_bp_def.flags == "Space" and entity:GetFreeSlot(deployer_bp_def.id) then -- satellite one time deployer
				v[4] = CreateFrameOrBlueprint(faction, v[3].bp, true, nil, nil, true)
			end
			if v[4] then -- entity
				if not v[4]:DockInto(entity) then v[4]:Place(entity) end
			else
				local slot, added = entity:AddItem(v[1], v[2], v[3])
				local remain = v[2] - (added or 0)
				if remain > 0 then Map.DropItemAt(entity, v[1], remain, v[3], true) end
			end
		end
	end
	return entity
end

function LibraryUpgradeOldProfile()
	-- Fill out temp_library/temp_hashes with everything in the old profile (can include duplicates)
	local profile, temp_library, temp_hashes = Game.GetProfile(), {}, {}
	for type,list in pairs({ B = profile.blueprints, C = profile.behaviors }) do
		for _,rawitem in ipairs(list) do
			local item, temp_id = Tool.Copy(rawitem), #temp_library + 1
			item.reg_values, item.lock_values, item.data_name, item.prefab, item.race, item.texture, item.num = nil -- clear old fields
			UnpackOldCompactedItemToLibraryTable(item, type, temp_library)
			temp_hashes[temp_id] = LibraryHashItem(temp_library, item, temp_hashes)
			if not item.folder then item.folder = -1 end -- mark as being in root
		end
	end

	LibraryPerformImport(profile, temp_library, temp_hashes, {}, profile, "Imported")

	-- Finished data upgrade, delete old tables
	profile.blueprints, profile.behaviors = nil, nil
end

function LibraryUpgradeOldSave()
	for _,faction in ipairs(Map.GetFactions()) do
		local temp_library, import_hashes, custom_blueprints, behaviors = {}, {}, {}, {}

		-- Process blueprints in fabricator and construction components (only add depdendencies to import_hashes)
		for comp_id, is_costruction in pairs({ c_fabricator = false, c_construction = true }) do
			for _,comp in ipairs(faction:GetComponents(comp_id, true)) do
				local holder = is_costruction and comp.owner or comp
				local ed = holder.has_extra_data and holder.extra_data
				local bp = ed and ed.custom_blueprint
				if bp and BlueprintHasNestedItems(bp) then
					local temp_id = #temp_library + 1
					bp.reg_values, bp.lock_values, bp.data_name, bp.prefab, bp.race, bp.texture, bp.num = nil -- clear old fields
					UnpackOldCompactedItemToLibraryTable(bp, 'B', temp_library)
					LibraryHashItem(temp_library, bp, import_hashes)
					custom_blueprints[ed] = temp_id
				end
			end
		end

		-- Process behaviors (add both dependencies and outer behaviors to import_hashes)
		for _,comp in ipairs(faction:GetComponents("c_behavior", true)) do
			local ed = comp.has_extra_data and comp.extra_data
			local code = ed and ed.main
			if code then
				local temp_id = #temp_library + 1
				UnpackOldCompactedItemToLibraryTable(code, 'C', temp_library)
				import_hashes[temp_id] = LibraryHashItem(temp_library, code, import_hashes)
				behaviors[comp] = temp_id
			end
		end

		if #temp_library > 0 then
			local mapping = {}
			LibraryPerformImport(faction.extra_data, temp_library, import_hashes, mapping, Map.GetSave())

			-- Apply processed blueprints back to components (only dependencies were imported, the blueprints themselves stay in the components)
			for ed,temp_id in pairs(custom_blueprints) do
				local item = LibraryApplyMapping(temp_library[temp_id], mapping)
				item.id, item.rev, item.type = nil, nil, nil -- no library fields while stored in component
				ed.custom_blueprint = item
			end

			-- Apply processed behaviors (which are now only references to the faction library)
			for comp,temp_id in pairs(behaviors) do
				local debug, counter = "STOP", nil
				if comp.is_active then
					local state = comp.extra_data
					debug, counter = "CONTINUE", ((state.returns and #state.returns > 0) and state.returns[1][1] or state.counter)
				end
				SetBehavior(comp, mapping[temp_id], debug, counter)
			end
		end
	end
end

-- Make some of the functions available globally
_ENV.UnpackCompactedItemToLibraryTable = UnpackCompactedItemToLibraryTable
_ENV.PackLibraryItemToCompactedItem = PackLibraryItemToCompactedItem
_ENV.LibraryHashItem = LibraryHashItem
_ENV.LibraryGetAllHashes = LibraryGetAllHashes
_ENV.LibraryApplyMapping = LibraryApplyMapping
_ENV.ImportBlueprint = ImportBlueprint
_ENV.ConvertOldBlueprint = ConvertOldBlueprint
