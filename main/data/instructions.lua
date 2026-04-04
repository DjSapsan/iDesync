-- arg - { 'in'/'out'/'exec', name(string), desc (string), filter (instruction_argument_filters), is extra param (bool)}
-- a op func returning true means the instruction has put the behavior component into waiting state and we get activated again once that finishes
--[=[
data.instructions.<instruction_id> = {
	-- Main logic executed when the instruction runs
	func = function(comp, state, cause, ...)
		-- Implementation here
		-- You can use helper functions like Get, Set, GetNum, GetEntity, etc.
		-- Return true if the instruction yields/waits
	end,
	-- (Optional) function to generate an additional argument which will be passed to func after cause
	make_asm = function(inst)
		-- i.e. return inst.c or 1
	end,

	-- (Optional) Additional execution control
	next = function(comp, state, it, ...)
		-- For loop/iterator instructions
	end,
	last = function(comp, state, it, ...)
		-- Cleanup or jump after loop ends
	end,

	-- (Optional) Extra argument definition for execution path branching
	exec_arg = { index, "Label", "Description", },

	-- (Optional) List of arguments (inputs, outputs, execution branches)
	args = {
		{ 'in',  "Input Name",  "Description", filter?, expanded? },
		{ 'out', "Output Name", "Description", nil?, expanded?},
		{ 'exec',"Exec Path",   "Description", nil?, expanded? },
	},

	-- (Optional) UI customization for the node editor
	node_ui = function(canvas, inst, program_ui)
		-- Add buttons, combos, text, etc.
		-- Return height (number of pixels) for the node UI
	end,

	-- Metadata
	name     = "Instruction Name",
	desc     = "Short description of what this does",
	category = "Flow | Unit | Global | Math | Move | Component | AutoBase",
	icon     = "path/to/icon.png",

	-- (Optional) Extended explanation (supports markup and inline images)
	explain  = [[Detailed explanation
	<hl>Highlighted text</>
	<img image="path/to/example.png"/>]],

	-- (Optional) Sample encoded string for serialization/examples
	sample   = "encoded_sample_data_string",
}
--]=]
data.instructions = {}
data.instruction_color = {
	Flow = "white",
	Unit = "light_red",
	Global = "yellow",
	Math = "green",
	Move = "orange",
	Component = "cyan",
	AutoBase = "light_blue",
}

local function GetStack(state, i)
	if not i then return end
	local stk = state.stk
	if type(stk) ~= "table" then
		if i > stk then return i - stk, true end
		return i
	end

	local up = 0
	::nextup::
	if i >= #stk then
		--print("    Sub accessing sub memory (" .. i .. " - " .. stk[1] .. ") = " .. (i - stk[1]), state.mem[i - stk[1]])
		return i - stk[1], true
	end
	if i < 0 then
		--print("    Sub accessing frame register " .. i)
		return i
	end
	--print("    Sub accessing parent stack of return #" .. (#state.returns - (up or 0)) .. ": " .. i  .. " ==> " .. tostring(stk[i + 1]))
	i = stk[i + 1]
	if not i then return end
	local returns = state.returns
	stk = returns[#returns - up][2]
	if type(stk) == "table" then
		up = up + 1
		goto nextup
	end
	if i > stk then
		--print("    Sub accessing main memory (" .. i .. " - " .. stk .. ") = " .. (i - stk), state.mem[i - stk])
		return i - stk, true
	end
	--print("    Sub accessing behavior parameter " .. tostring(i))
	return i
end

local GetCachedBehaviorAsm, GetFactionBehaviorAsmById = GetCachedBehaviorAsm, GetFactionBehaviorAsmById

local function CallRadio(fn, comp, state, j, setval)
	local fregs = GetCachedBehaviorAsm(state.revid).fregs
	local radio_storage = comp.faction.extra_data.radio_storage
	local radio_storage_names = radio_storage and radio_storage.extra_data.names
	local idx = radio_storage_names and radio_storage_names[fregs and fregs[-99 - j]]
	if not idx then return (fn == 'GetRegister' and Tool.NewRegisterObject()) or (fn == 'GetRegisterNum' and 0) or nil end
	if fn ~= 'SetRegister' or not radio_storage:RegisterIsLink(idx) then return radio_storage[fn](radio_storage, idx, setval) end
end

-- Global functions that can also be used by mods
function InstGet(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return Tool.NewRegisterObject() end
	if inmem then return state.mem[j] end
	if j > 0 then return comp:GetRegister(j) end
	if j >= -99 then return comp.owner:GetRegister(-j) end
	return CallRadio('GetRegister', comp, state, j)
end

function InstGetNum(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return 0 end
	if inmem then return state.mem[j].num end
	if j > 0 then return comp:GetRegisterNum(j) end
	if j >= -99 then return comp.owner:GetRegisterNum(-j) end
	return CallRadio('GetRegisterNum', comp, state, j)
end

function InstGetCoord(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return nil end
	if inmem then return state.mem[j].coord end
	if j > 0 then return comp:GetRegisterCoord(j) end
	if j >= -99 then return comp.owner:GetRegisterCoord(-j) end
	return CallRadio('GetRegisterCoord', comp, state, j)
end

function InstGetId(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return nil end
	if inmem then return state.mem[j].id end
	if j > 0 then return comp:GetRegisterId(j) end
	if j >= -99 then return comp.owner:GetRegisterId(-j) end
	return CallRadio('GetRegisterId', comp, state, j)
end

function InstGetEntity(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return nil end
	if inmem then return state.mem[j].entity end
	if j > 0 then return comp:GetRegisterEntity(j) end
	if j >= -99 then return comp.owner:GetRegisterEntity(-j) end
	return CallRadio('GetRegisterEntity', comp, state, j)
end

function InstSet(comp, state, i, val)
	local j, inmem = GetStack(state, i)
	if not j then return end
	if inmem then state.mem[j]:Init(val) return end
	if j > 0 then comp:SetRegister(j, val) return end
	if j >= -99 then comp.owner:SetRegister(-j, val) return end
	CallRadio('SetRegister', comp, state, j, val)
end

function InstError(comp, state, err)
	comp.faction:RunUI(function()
		local entity = comp.owner
		Notification.Add("notify_behavior", comp.def.texture, "Behavior", err, {
			on_click = function() View.SelectEntities(entity) View.FollowEntity(entity) end,
		})
	end)
	return data.instructions.exit.func(comp, state)
end

function InstUnrollReturns(state)
	local returns = state.returns
	if returns and #returns > 0 then
		-- unroll block and return stacks and reset program counter
		local mem, old_counter, mem_count = state.mem
		state.revid, state.stk, old_counter, mem_count = table.unpack(returns[1])
		table.move(mem, #mem+1, #mem+#mem-mem_count, mem_count+1) -- trim to mem_count
		table.move(returns, #returns+1, #returns+#returns, 1) -- trim to 0
		return true
	end
end

function InstBeginBlock(comp, state, it)
	local next_counter, loop_inst_idx = state.counter, state.lastcounter
	local inst = GetCachedBehaviorAsm(state.revid)[loop_inst_idx]
	local op = data.instructions[inst[1]]
	if op.next and op.next(comp, state, it, table.unpack(inst, 3)) then
		op.last(comp, state, it, table.unpack(inst, 3))
	else
		local blocks = state.blocks
		if not blocks then blocks = {} state.blocks = blocks end
		if #blocks >= 40 then return InstError(comp, state, "Behavior exceeded loop recursion limit") end
		blocks[#blocks + 1] = { next_counter, loop_inst_idx, it, state.returns and #state.returns or 0 }
	end
end

function InstTriggerEvent(ev_comp)
	local ev_ed = ev_comp.extra_data
	local comp = ev_ed.owner
	if not comp then Map.Defer(function() if ev_comp.exists then ev_comp:Destroy() end end) return end
	local state = comp.extra_data
	if not comp.is_active or (state.debug ~= nil and state.debug ~= 'BREAKPOINT') then return end -- don't trigger while paused
	local blocks = state.blocks
	local block_inst_idx, ev_inst_idx = blocks and blocks[1] and blocks[1][4] == 0 and blocks[1][2], ev_ed.inst_idx
	if block_inst_idx == ev_inst_idx then return end -- don't trigger same event twice
	local asm = GetFactionBehaviorAsm(comp, state.returns and state.returns[1] and state.returns[1][1] or state.revid)
	if not asm then return end -- don't trigger already modified behavior
	local block_inst_def = block_inst_idx and asm[block_inst_idx] and data.instructions[asm[block_inst_idx][1]]
	if block_inst_def and block_inst_def.event_setup then return end -- don't trigger while another event is running
	if not blocks then blocks = {0} state.blocks = blocks else table.move(blocks, #blocks+1, #blocks+#blocks-1, 2) end -- trim to 1
	blocks[1] = { 1, ev_inst_idx, false, 0 }
	local inst = asm[ev_inst_idx]
	state.counter = (inst and inst[2] or false)
	if InstUnrollReturns(state) then state.lastcounter = 1 end -- so program editor doesn't highlight the wrong instruction
	local ev_inst_def = data.instructions[inst and inst[1]]
	local event_trigger = ev_inst_def and ev_inst_def.event_trigger
	if event_trigger then event_trigger(comp, state, ev_comp, table.unpack(inst, 3)) end
	if state.breakpoints and state.breakpoints[(asm.code.id << 16) | (state.counter or 1)] then state.debug = 'BPHIT' end
	comp:Activate()
end

-- Local references for shorter names and avoiding global lookup on every use
local Get, GetNum, GetCoord, GetId, GetEntity, Set, BeginBlock = InstGet, InstGetNum, InstGetCoord, InstGetId, InstGetEntity, InstSet, InstBeginBlock

-- Filter function for register selection when setting constant input value in behavior editor
data.instruction_argument_filters = {
	any          = function(def, cat) return not cat.entity_panel end, -- any value including negative numbers
	entity       = function(def, cat) return false end, -- no register selection, just registers/parameters/variables
	posnum       = function(def, cat) return cat.number_panel end, -- just positive number
	num          = function(def, cat) return cat.number_panel or cat.allow_negative or cat.allow_infinite or cat.allow_not end, -- just number
	coord        = function(def, cat) return cat.coord_panel end, -- coord
	coord_num    = function(def, cat) return cat.number_panel or cat.allow_negative or cat.coord_panel or cat.allow_infinite or cat.allow_not end, -- number or coord
	item         = function(def, cat) return cat.tab == "item" end, -- item tab only
	item_num     = function(def, cat) return cat.tab == "item" or cat.number_panel  or cat.allow_negative or cat.allow_infinite or cat.allow_not end,
	comp         = function(def, cat) return def.attachment_size end, -- component item
	comp_num     = function(def, cat) return def.attachment_size or cat.number_panel end,
	frame        = function(def, cat) return cat.tab == "frame" end, -- frame tab only
	frame_num    = function(def, cat) return cat.tab == "frame" or cat.number_panel end,
	radar        = function(def, cat) return cat.number_panel or cat.allow_negative or cat.allow_infinite or cat.allow_not or cat.tab == "item" or cat.tab == "frame" or def.tag == "entityfilter" end,
	resource_num = function(def, cat) return def.tag == "resource" or cat.number_panel or cat.allow_negative or cat.allow_infinite or cat.allow_not end,
	tech         = function(def, cat) return cat.is_tech end,
}

-- dummy instruction used as a replacement in the editor when an instruction gets removed from the definitions
data.instructions.nop =
{
	func = function() end,
	args = { },
	name = "Invalid Instruction",
	desc = "Instruction has been removed, behavior needs to be updated",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
	explain = [[Invalid Instruction - likely a deprecated function was replaced with this node.]],
}

local function GetSeenEntityOrSelf(comp, state, ent)
	if not ent then return comp.owner end
	local reg = Get(comp, state, ent)
	if reg.is_empty then return nil end
	local entity = reg.entity
	return entity and comp.faction:IsSeen(entity) and entity or nil
end

local function GetFactionEntityOrSelf(comp, state, ent)
	if not ent then return comp.owner end
	local reg = Get(comp, state, ent)
	if reg.is_empty then return nil end
	local entity = reg.entity
	return entity and comp.faction == entity.faction and entity or nil
end

local function GetAdjacentFactionEntityOrSelf(comp, state, in_unit)
	if not in_unit then return comp.owner end
	local ent = GetEntity(comp, state, in_unit)
	if not ent then return end
	local faction = comp.faction
	if ent.faction ~= faction or ent.is_construction then return end
	if ent:IsTouching(comp) then return ent end

	if comp.def.key == "autobase" then
		-- must be in same logistics network
		local grid_owner = faction:GetPowerGridIndexAt(comp)
		local grid_other = faction:GetPowerGridIndexAt(ent)
		return grid_owner and grid_owner == grid_other and ent
	end
end

local function GetSourceNode(state)
	return GetCachedBehaviorAsm(state.revid).code[state.lastcounter]
end

local function GetComponentFromSortedGroupIndex(comp, state, compid, group_index, other_owner, query_base_id)
	local group_index_num = GetNum(comp, state, group_index)
	if group_index_num == REG_INFINITE then return end

	-- If using default group index (0) and looking for a component matching the behavior controller, return itself
	if group_index_num == 0 and not query_base_id and comp.id == compid and (not other_owner or other_owner == comp.owner) then return comp end

	-- Get the UI listed order and not equipped component order
	local owner = other_owner or comp.owner
	return owner:FindComponent(compid, query_base_id, (group_index_num < 1 and 1 or group_index_num), true)
end

--------------------------------------------------------------------------------------------------------------------------
--------------------------------------- FLOW -----------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------

local function call_ui(canvas, inst, program_ui)
	local sub_code = inst.sub == 0 and program_ui.code or program_ui.library[inst.sub]
	canvas:Add('<Text halign=fill y=40 textalign=center style=hl/>').text = (inst.op == 'call' and "Subroutine" or "Behavior")
	canvas:Add('<Text halign=fill y=64 textalign=center margin_left=4 margin_right=4 clip=true/>', { text = sub_code and (NOLOC(sub_code.name) or "New Behavior") or "none" })
	if sub_code and inst.sub and inst.sub ~= 0 and inst.sub ~= program_ui.code.id then
		local param_hash = Tool.Hash(sub_code.name, sub_code.parameters, sub_code.pnames)
		canvas:Add('<Button halign=fill y=88 margin_left=104 margin_right=10 text="Edit"/>', {
			on_click = function()
				local edit_code = program_ui.library[inst.sub]
				if not edit_code then return end
				program_ui[1]:Add("Program", { code = program_ui.is_remote and Tool.Copy(edit_code) or edit_code, outer_ui = program_ui })
			end,
			update = function()
				local edit_code = program_ui.library[inst.sub]
				local new_hash = edit_code and Tool.Hash(edit_code.name, edit_code.parameters, edit_code.pnames)
				if param_hash == new_hash then return end
				param_hash = new_hash
				program_ui:Refresh(true)
			end,
		})
	end
	canvas:Add('<Button halign=fill y=88 margin_left=10 margin_right=10/>', {
		margin_right = (sub_code and 104 or 10),
		text = (sub_code and "Select" or "Select Subroutine"),
		on_click = function(btn)
			local function on_select(item)
				local was_changed, params, pinits = inst.sub ~= item.id, item.parameters, item.pinits
				inst.sub = item.id
				for i,is_out in ipairs(params or {}) do
					if not is_out and pinits and pinits[i] then
						inst[i] = pinits[i] -- apply default value
					elseif is_out and type(inst[i]) == "table" then
						inst[i] = nil -- can't have constant in output
					end
				end
				UI.CloseMenuPopup()
				if was_changed then program_ui:Refresh() end
			end
			UILibrarySelect(btn, 'C', on_select,
				nil,
				program_ui.is_remote and function(folder)
					UILibrarySaveBehaviorAsNew({ type = 'C' }, function (newitem)
						on_select(newitem)
					end)
				end or nil,
				inst.sub, program_ui.comp and program_ui.comp.id, program_ui.library)
		end,
	})
	return 80
end

local function call_var_args(inst, code, library)
	local sub_code = inst.sub == 0 and code or library[inst.sub]
	local parameters = sub_code and sub_code.parameters
	if not parameters then return end
	local pnames, res = sub_code and sub_code.pnames, {}
	for i,v in ipairs(parameters) do
		res[#res+1] = v
		res[#res+1] = pnames and pnames[i] or false
	end
	return res
end

data.instructions.call =
{
	func = function(comp, state, cause, sub, ...)
		local returns, mem, oldstk = state.returns, state.mem, state.stk
		if not returns then returns = {} state.returns = returns end
		if #returns >= 20 then
			return InstError(comp, state, "Behavior exceeded call depth limit")
		end
		local asm, mem_index = sub == 0 and GetCachedBehaviorAsm(state.revid) or GetFactionBehaviorAsmById(comp.faction, sub), #mem
		if not asm then return end -- behavior deleted or modified
		returns[#returns + 1] = { state.revid, oldstk, state.counter, mem_index, state.lastcounter } -- return record
		table.move(asm.mem, 1, #asm.mem, mem_index + 1, mem) -- increase stack memory by amount of sub
		for i=mem_index + 1,#mem do mem[i] = Tool.NewRegisterObject(mem[i]) end -- copy values (don't reference)
		local code_parameters = asm.code.parameters
		local stk = (code_parameters and { #code_parameters - mem_index, table.unpack(code_parameters) } or { -mem_index })
		for i=2,#stk do
			local arg = select(i - 1, ...)
			if arg then stk[i] = arg -- got input argument
			elseif stk[i] then -- empty output argument must exist as the parameter might be used like a local variable
				mem[#mem + 1] = Tool.NewRegisterObject()
				stk[i] = #mem + (type(oldstk) == "table" and oldstk[1] or oldstk)
			end
		end
		state.revid, state.stk, state.counter, state.lastcounter = asm.revid, stk, 1, 1 -- subroutine state
		--print("[call] Return #" .. #returns  .. " - STK: " .. tostring(state.stk):gsub("\n", " "):gsub(" %p%d+%p: ", "") .. " - MEM: " .. tostring(state.mem):gsub("\n", " "):gsub(" %p%d+%p: ", "") .." - OLDSTK: " .. tostring(returns[#returns][3]):gsub("\n", " "):gsub(" %p%d+%p: ", "") .." - OLDMEM: " .. returns[#returns][5])
	end,
	name = "Call",
	desc = "Call a subroutine",
	category = "Flow",
	icon = "icon_input",
	node_ui = call_ui,
	make_asm = function(inst)
		return inst.sub or false
	end,
	var_args = call_var_args,
	explain = [[Runs a different behavior and then continues running the current behavior.]],
}

data.instructions.last =
{
	func = function(comp, state)
		local blocks = state.blocks
		if not blocks or #blocks == 0 then
			return InstError(comp, state, "Break called while not in loop")
		end
		local next_counter, loop_inst_idx, it = table.unpack(table.remove(blocks))
		local inst = GetCachedBehaviorAsm(state.revid)[loop_inst_idx]
		local op = data.instructions[inst and inst[1]]
		if op then op.last(comp, state, it, table.unpack(inst, 3)) end
	end,
	exec_arg = false,
	name = "Break",
	desc = "Break out of a loop",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Deny.png",
	explain = [[Breaks out of a loop and continues running from the <hl>Done</> pin of the loop.]],
}

data.instructions.exit =
{
	func = function(comp, state)
		InstUnrollReturns(state)
		state.counter = 1
		state.blocks, state.returns, state.debug = nil

		-- Because data.instructions.exit gets called as a regular function outside of c_behavior:on_update, we can't use GetCachedBehaviorAsm here.
		-- And in addition to GetFactionBehaviorAsm we use GetFactionBehaviorAsmById as a fallback in case the behavior revision was already modified.
		local asm = GetFactionBehaviorAsm(comp, state.revid) or GetFactionBehaviorAsmById(comp.faction, state.main_id)
		if asm and asm.code.keeparrays ~= "store" then state.arrays = nil end

		UpdateEntityBehaviorState(comp.owner, comp)
		return true
	end,
	exec_arg = false,
	name = "Exit",
	desc = "Stops execution of the behavior",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Deny.png",
	explain = [[Stops running the current behavior.]],
}

data.instructions.restart =
{
	func = function(comp, state)
		state.counter = false -- forces restart and calling of c_behavior_on_end
		if InstUnrollReturns(state) then state.lastcounter = 1 end -- so program editor doesn't highlight the wrong instruction
		state.blocks = nil
	end,
	exec_arg = false,
	name = "Restart",
	desc = "Restart execution of the behavior",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Deny.png",
	explain = [[Restarts a behavior from the <hl>Program Start</> node.]],
}

data.instructions.unlock = {
	func = function(comp, state)
		if Map.GetSettings().block_unlocked_behaviors then
			return InstError(comp, state, "Behavior used unlock instruction which has been disabled on this server")
		end
		state.limit = 1000
	end,
	name = "Unlock",
	desc = "Run as many instructions as possible. Use wait instructions to throttle execution.",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Unlocked.png",
	explain = [[By default, behaviors will run one instruction per tick. Unlock will allow multiple instructions to execute within one tick until it hits a wait instruction, the end of the behavior, or an instruction that takes time to execute such as a Synchronous <hl>Move Unit</> instruction. If more than 1000 instructions are executed in one tick then the behavior controller will crash at that location.]],
}

data.instructions.lock = {
	func = function(comp, state)
		state.limit = 1
	end,
	name = "Lock",
	desc = "Run one instruction at a time",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Unlocked.png",
	explain = [[Will lock the behavior to run at one instruction per game tick, if you have previously Unlocked the behavior, returning it to the default behavior.]],
}

data.instructions.label =
{
	func = function() end,
	args = { { 'in', "Label", "Label identifier", 'any' } },
	name = "Label",
	desc = "Labels can be jumped to from anywhere in a behavior",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
	sample = "5m3YxVw84XJFlw24tPSo1r2L8L3mKUrZ2SEiKA1NUiEH1MDB7y0QmVQm0Qz9aJ3hYzUj1tPR554Fop503HO9MG3M0r9Y3y90eu2MBd5m2xxcAA0962pa0oCuIy1cMU7G2iiUGY3Y4d1W2Nd5410aQYkf28dFvn3EQa3r3klEil1kXFpA0AbN7C2i2XeI0Mc4Oj",
	explain = [[Sets a label at a location in the behavior. You can make the behavior run instructions from the label by using the <hl>Jump</> instruction.]],
}

data.instructions.jump =
{
	func = function(comp, state, cause, label)
		label = Get(comp, state, label)
		local asm = GetCachedBehaviorAsm(state.revid)
		for i=1,#asm do
			if asm[i][1] == "label" and label == Get(comp, state, asm[i][3]) then
				state.counter = i
				return
			end
		end
	end,
	args = { { 'in', "Label", "Label identifier", 'any' } },
	name = "Jump",
	desc = "Jumps execution to label with the same label id",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/J Value.png",
	sample = "5m3YxVw84XJFlw24tPSo1r2L8L3mKUrZ2SEiKA1NUiEH1MDB7y0QmVQm0Qz9aJ3hYzUj1tPR554Fop503HO9MG3M0r9Y3y90eu2MBd5m2xxcAA0962pa0oCuIy1cMU7G2iiUGY3Y4d1W2Nd5410aQYkf28dFvn3EQa3r3klEil1kXFpA0AbN7C2i2XeI0Mc4Oj",
	explain = [[Will jump to a location in the behavior specified by a <hl>Label</> instruction.

Jumps can be dynamic and passed via <bl>parameter</> or <bl>variable</>]],
}

data.instructions.wait =
{
	func = function(comp, state, cause, time)
		local t = GetNum(comp, state, time)
		if t <= 0 then return end
		comp:SetStateSleep(t)
		return true
	end,
	args = { { 'in', "Time", "Number of ticks to wait", 'posnum' } },
	name = "Wait Ticks",
	desc = "Pauses execution of the behavior until 1 or more ticks later",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Wait.png",
	explain = [[Will pause the current behavior for the specified number of game ticks. There are 5 game ticks per second.]],
}

data.instructions.compare_register =
{
	func = function(comp, state, cause, if_differ, val1, val2)
		local r1, r2 = Get(comp, state, val1), Get(comp, state, val2)
		if r1 ~= r2 then
			state.counter = if_differ
		end
	end,
	exec_arg = { 1, "If Equal", "Where to continue if the registers are the same" },
	args = {
		{ 'exec', "If Different", "Where to continue if the registers differ" },
		{ 'in', "Value 1" },
		{ 'in', "Value 2" },
	},
	name = "Compare Register",
	desc = "Compares Registers for equality",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[compares if both the <hl>id</> and the <hl>number</> in two registers are the same and continues execution based on the result.]],
}

data.instructions.get_unit_type =
{
	func = function(comp, state, cause, in_entity, out_type)
		local e = GetEntity(comp, state, in_entity)
		if not e then Set(comp, state, out_type) return end
		Set(comp, state, out_type, { id = e.id })
	end,
	args = {
		{ 'in', "Unit", "The unit to check" },
		{ 'out', "Type" },
	},
	name = "Get Unit Type",
	desc = "Get the frame type of the unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Returns the frame <hl>Type</> of the given game entity in <hl>Unit.</>

<img image="Main/textures/behaviors/get_unit_type.png"/>]],
}

data.instructions.is_unit_a =
{
	func = function(comp, state, cause, in_entity, in_type, is_not)
		local e = GetSeenEntityOrSelf(comp, state, in_entity)
		local id = GetId(comp, state, in_type)
		if not e or e.id ~= id then state.counter = is_not return end
	end,
	exec_arg = { 1, "Is" },
	args = {
		{ 'in', "Unit", "The unit to check" },
		{ 'in', "Type" },
		{ 'exec', "Is Not", },
	},
	name = "Is Unit A",
	desc = "Checks if a unit is a specific frame type",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	sample = "2o3bEIye3WrUtE2fYjuy1wlqdV1w59mf2iQlyI105y6x3TtEgX0ffVcy0b7mKE01h86f06C20F1StfRo1oB4Tb2vy9Oa34kRoI0HtniT",
	explain = [[Checks if a <hl>Unit</> is of the <hl>Type</> specified and continues execution based on the result.]],
}

data.instructions.compare_item =
{
	func = function(comp, state, cause, if_differ, val1, val2)
		local r1, r2 = Get(comp, state, val1), Get(comp, state, val2)
		local r1_id, r2_id = r1.id, r2.id
		local r1_entity, r2_entity = not r1_id and r1.entity, not r2_id and r2.entity
		if r1_entity then r1_id = r1_entity.id end
		if r2_entity then r2_id = r2_entity.id end
		if r1_id == nil and r2_id == nil then return end
		if r1_id ~= r2_id or (not r1_id and not r2_id) then
			state.counter = if_differ
		end
	end,
	exec_arg = { 1, "If Equal", "Where to continue if the types are the same" },
	args = {
		{ 'exec', "If Different", "Where to continue if the types differ" },
		{ 'in', "Value 1" },
		{ 'in', "Value 2" },
	},
	name = "Compare Item",
	desc = "Compares Item or Unit type",
	category = "Flow",
	sample = "V058hik057a9u1rA6CX23e62m1rBwi400RbvO30DTnN28Eyyc27JP8K25rKi522kYYn09gHnE1CWFHK34kil01meMtZ25rrbw00RbvO22TJ3D25rsXl28AqqD22kYxZ01o7",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Compares two registers to check if the <hl>ids</> are the same and continues execution based on the result.]],
}

data.instructions.compare_entity =
{
	func = function(comp, state, cause, if_differ, val1, val2)
		local r1_entity, r2_entity = GetEntity(comp, state, val1), GetEntity(comp, state, val2)
		if r1_entity ~= r2_entity or (not r1_entity and not r2_entity) then
			state.counter = if_differ
		end
	end,
	exec_arg = { 1, "If Equal", "Where to continue if the units are the same" },
	args = {
		{ 'exec', "If Different", "Where to continue if the units differ" },
		{ 'in', "Unit 1" },
		{ 'in', "Unit 2" },
	},
	name = "Compare Unit",
	desc = "Compares Units",
	category = "Flow",
	sample = "2q3bEIye3Ws2zI1vrccS1GoXMX07HSFF1bRCNE17PfAn12QQs91US35J2fs4Ba0Ux6g00Pgo7D2klRh83P9qqb36BxQb0gY5U91BKK5Z3iUISL0re9Rm",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Compares two registers to check if the <hl>Units</> are the same and continues execution based on the result.]],
}

data.instructions.is_a =
{
	func = function(comp, state, cause, if_differ, val1, val2)
		local r1 = Get(comp, state, val1)
		r1 = r1.id or (r1.entity and r1.entity.def.id)
		local r2 = GetId(comp, state, val2)
		if r1 ~= r2 or (not r1 and not r2) then
			state.counter = if_differ
		end
	end,
	exec_arg = { 1, "If Equal", "Where to continue if the units are the same" },
	args = {
		{ 'exec', "If Different", "Where to continue if the units differ" },
		{ 'in', "Item" },
		{ 'in', "Type" },
	},
	name = "Is a",
	sample = "3j3bEIye3WrUtE3NmKKO0fg4Fu0iQOzR1UUFJB1DnjZG2DYCpz0DmwUj1lhzTr3ZZOXx2giHRa4TyyAi1gU1i90DiXUG2N9faf3a56cs3HOsnc34pBNo4Ru6Wv0j8EAd",
	desc = "Compares if an item of unit is of a specific type",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Checks if a <hl>Item</> is of a specific <hl>Type</> and continues execution based on the result.]],
}

data.instructions.get_type =
{
	func = function(comp, state, cause, in_val, out_type)
		local reg = Get(comp, state, in_val)
		local reg_id = reg.id
		if not reg_id then
			local reg_ent = reg.entity
			if reg_ent then
				Set(comp, state, out_type, { id = reg_ent.def.id })
			else
				Set(comp, state, out_type)
			end
			return
		end

		Set(comp, state, out_type, { id = reg_id })
	end,
	args = {
		{ 'in', "Item/Unit" },
		{ 'out', "Type" },
	},
	name = "Get Type",
	desc = "Gets the type from an item or unit",
	category = "Global",
	sample = "2h3bEIye3Ws2zI1vrccS1GoXMX07HSFF1bRCNE17PfAn12QQs91US35J2fs4Ba0n7R081Dqt8l2ONsvP1XxBYI001eT232ZeBCh",
	icon = "Main/skin/Icons/Common/56x56/Processing.png",
	explain = [[Puts the <hl>Type</> of an <hl>Item</> or <hl>Unit</> into a register.]],
}

data.instructions.value_type =
{
	func = function(comp, state, cause, item, exec_item, exec_entity, exec_component, exec_tech, exec_value, exec_coord)
		local value = Get(comp, state, item)
		if not value or value.is_empty then
			return
		elseif value.entity then
			state.counter = exec_entity
		elseif value.tech_id then
			state.counter = exec_tech
		elseif value.component_id then
			state.counter = exec_component
		elseif value.item_id then
			state.counter = exec_item
		elseif value.value_id then
			state.counter = exec_value
		elseif value.coord then
			state.counter = exec_coord
		end
	end,
	exec_arg = { 1, "No Match", "Where to continue if there is no match" },
	args = {
		{ 'in', "Data", "Data to test" },
		{ 'exec', "Item", "Item Type" },
		{ 'exec', "Unit", "Unit Type" },
		{ 'exec', "Component", "Component Type" },
		{ 'exec', "Tech", "Tech Type", nil, true },
		{ 'exec', "Value", "Information Value Type", nil, true },
		{ 'exec', "Coord", "Coordinate Value Type", nil, true },
	},
	name = "Data type switch",
	desc = "Switch based on type of value",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Processing.png",
	explain = [[Continues execution of the behavior depending on the type inside the passed <hl>Data</> register.]],
}

data.instructions.get_first_locked_0 =
{
	func = function(comp, state, cause, first_locked)
		for _,v in ipairs(comp.owner.slots) do
			if v.locked and v.id and v.stack == 0 then
				Set(comp, state, first_locked, { id = v.id, num = 1 })
				return
			end
		end
		Set(comp, state, first_locked)
	end,
	args = {
		{ 'out', "Item", "The first locked item id with no item", },
	},
	name = "Get First Locked Id",
	desc = "Gets the first item where the locked slot exists but there is no item in it",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[<img image="Main/textures/behaviors/get_first_locked_id2.png"/>

Returns the first locked slot without any items in it.

<img image="Main/textures/behaviors/get_first_locked_id1.png"/>]],
}

data.instructions.unit_type =
{
	func = function(comp, state, cause, in_unit, if_building, if_bot, if_construction)
		-- dont include self here so when people pass no unit it returns no unit
		--GetSeenEntityOrSelf(comp, state, in_unit)
		local ent = GetEntity(comp, state, in_unit)
		if not ent then
		elseif ent.is_construction then
			state.counter = if_construction
		elseif IsBot(ent) then
			state.counter = if_bot
		elseif IsBuilding(ent) then
			state.counter = if_building
		end
	end,
	exec_arg = { 5, "No Unit", "No visible unit passed", nil, true },
	args = {
		{ 'in', "Unit", "The unit to check", 'entity', },
		{ 'exec', "Building", "Where to continue if the unit is a building" },
		{ 'exec', "Bot", "Where to continue if the unit is a bot" },
		{ 'exec', "Construction", "Where to continue if the unit is a construction site", nil, true },
	},
	name = "Unit Type",
	desc = "Divert program depending on unit type",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	sample = "6W3YxVw81l9GKn2WCHGi0gj82b0g6aYz2vmKaq065ucK3CmCWp1vfP4E2H7Du24HyWfh2S9odm2unxFm1ZO5Nm31faUf2ntqRd0vOFMP13x0s72wB42D2bgl5M1OVg801NWdOF3rw96g00s4gL0x5PUT1nI3uf08dxmi27v6e23DoVNK1HPv",
	explain = [[Continues execution of the behavior depending on the type of <hl>Unit</> passed.

<hl>Dropped items</> will be executed as <hl>No Unit</>]],
}

data.instructions.select_nearest =
{
	func = function(comp, state, cause, exec_a, exec_b, entity_a, entity_b, closer_entity)
		local ent_a = GetEntity(comp, state, entity_a)
		local ent_b = GetEntity(comp, state, entity_b)

		if not ent_a and not ent_b then
			Set(comp, state, closer_entity)
			return
		end

		local faction, owner = comp.faction, comp.owner
		local dist_a = ent_a and faction:IsSeen(ent_a) and owner:GetRangeSquaredTo(ent_a) or 9999999999
		local dist_b = ent_b and faction:IsSeen(ent_b) and owner:GetRangeSquaredTo(ent_b) or 9999999999

		if dist_a <= dist_b then
			Set(comp, state, closer_entity, {entity = ent_a, num = dist_a})
			if exec_a then state.counter = exec_a end
		else
			Set(comp, state, closer_entity, {entity = ent_b, num = dist_b})
			if exec_b then state.counter = exec_b end
		end
	end,
	args = {
		{ 'exec', "A", "A is nearer (or equal)" },
		{ 'exec', "B", "B is nearer" },
		{ 'in', "Unit A", nil, 'entity' },
		{ 'in', "Unit B", nil, 'entity' },
		{ 'out', "Closest", "Closest unit", nil, true },
	},
	name = "Select Nearest",
	desc = "Branches based on which unit is closer, optional branches for closer unit",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Closest Enemy.png",
	explain = [[Passing two <hl>Units</> will continue execution based on which one is closer to the unit running the behavior. An option parameter can also be used to get which unit is closer.]],
}

data.instructions.for_entities_in_range =
{
	func = function(comp, state, cause, range, f1, f2, f3, out_entity, exec_done)
		local owner, range = comp.owner, GetNum(comp, state, range)
		if range < 1 then
			range = range == REG_INFINITE and owner.visibility_range or 1
		elseif range > owner.visibility_range then
			range = owner.visibility_range
		end

		local f1id = GetId(comp, state, f1)
		local filters = { f1id, f1id and GetNum(comp, state, f1), nil, nil, nil, nil }
		if filters[1] then
			filters[3] = GetId(comp, state, f2)
			filters[4] = filters[3] and GetNum(comp, state, f2)
			if filters[3] then
				filters[5] = GetId(comp, state, f3)
				filters[6] = filters[5] and GetNum(comp, state, f3)
			end
		end

		local it = { 2 }
		local entity_filter, override_range = PrepareFilterEntity(filters)
		Map.FindClosestEntity(owner, math.min(override_range or range, range), function(e)
			local ret, num = FilterEntity(owner, e, filters)
			if ret then
				it[#it+1] = num and { entity = e, num = num } or e
			end
		end, entity_filter)

		return BeginBlock(comp, state, it)
	end,

	next = function(comp, state, it, range, f1, f2, f3, out_entity, exec_done)
		local i = it[1]
		if i > #it then return true end
		local elem = it[i]
		if type(elem) == "table" then
			Set(comp, state, out_entity, elem)
		else
			Set(comp, state, out_entity, { entity = elem })
		end
		it[1] = i + 1
	end,

	last = function(comp, state, it, range, f1, f2, f3, out_entity, exec_done)
		-- this would clear the variable on loop end or break
		-- leave it valid for now as its useful for breaks
		--Set(comp, state, out_entity, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "Range", "Range (up to units visibility range)", 'posnum' },
		{ 'in', "Filter", "Filter to check", 'radar' },
		{ 'in', "Filter", "Second Filter", 'radar', true },
		{ 'in', "Filter", "Third Filter", 'radar', true },
		{ 'out', "Unit", "Current Unit in loop" },
		{ 'exec', "Done", "Finished looping through all units in range" },
	},
	name = "Loop Units (Range)",
	desc = "Performs code for all units in visibility range of the unit",
	category = "Flow",
	sample = "V058hik02qAks21cKXI2NbWvV2AjPm81vjnu321MU3Q1q0ayl21cbNw00W1gr25via528CEU31r8wR721MTit21KIal22kYQZ3YGixs1CVzMM02rudx1CW6ow1vjlnH21MU3Q21MPWZ21KGRc0yJrtP28EzzP22WKBc2Dq0xw00UuuY01G",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Loops over all entities within the given range.
Default is range 1, or visibility range if ∞ is passed

Optional filters allow you to only get desired units.]],
}

data.instructions.for_research =
{
	func = function(comp, state, cause, out_tech, exec_done)
		local techs = GetResearchableTech(comp.faction)

		local it = { 2 }
		for _,v in ipairs(techs) do
			it[#it+1] = v
		end

		return BeginBlock(comp, state, it)
	end,

	next = function(comp, state, it, out_tech, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_tech, { tech = it[i] })
		it[1] = i + 1
	end,

	last = function(comp, state, it, out_tech, exec_done)
		Set(comp, state, out_tech, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'out', "Tech", "Researchable Tech" },
		{ 'exec', "Done", "Finished looping through all researchable tech" },
	},
	name = "Loop Research",
	desc = "Performs code for all researchable tech",
	category = "Flow",
	sample = "3h3YxVw83N5hsf4870ro1w6gCm2iQlyI3b6v712hIRUP1jxAlq2pXtmm3Ff3bE2N2Q6i1wlqdV15Hlaf1DtsHb1sz2n90AgpPZ0PrBQg12syJi0aV2c50Nwd3O0o5W",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Loops through all technologies available for research.]],
}

data.instructions.for_research_unlocks =
{
	func = function(comp, state, cause, in_tech, out_unlock, exec_done)
		local tech = GetId(comp, state, in_tech)
		tech = tech and data.techs[tech]
		if not tech or not tech.unlocks then state.counter = exec_done return end

		local it = { 2 }
		for _,v in ipairs(tech.unlocks) do
			if not data.values[v] and not data.codex[v] then
				it[#it+1] = v
			end
		end

		return BeginBlock(comp, state, it)
	end,

	next = function(comp, state, it, in_tech, out_unlock, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_unlock, { id = it[i] })
		it[1] = i + 1
	end,

	last = function(comp, state, it, in_tech, out_unlock, exec_done)
		Set(comp, state, out_unlock, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "Tech", "Tech", 'tech' },
		{ 'out', "Unlock", "Unlocks" },
		{ 'exec', "Done", "Finished looping through all unlocks" },
	},
	name = "Loop Research Unlocks",
	desc = "Performs code for all unlocks for a researchable tech",
	category = "Flow",
	sample = "4j3YxVw83N5hsf4870Km1w6gCm2iQlyI3b6v712hIRUP1jxAlq2pXtmm3Ff3bE2N2Q6i1wlqdV0Ux6wP09XDbH1Do6aR1EqNvT2du1M44DohJF1t7hjx3Jk1Rf0pTQdH0BS6ZI02gBTK0rYsiK3AeTx109yTOU0pj94S2ux",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Loops through all items that are unlocked for a particular research.]],
}

data.instructions.is_unlocked =
{
	func = function(comp, state, cause, in_id, exec_nomatch)
		local id = GetId(comp, state, in_id)
		if not id or not comp.faction:IsUnlocked(id) then
			state.counter = exec_nomatch
		end
	end,
	args = {
		{ 'in', "Id", "Input Id"},
		{ 'exec', "No Match", "Execution path if there is no match" },
	},
	explain = [[Checks if your faction has researched a specific item or technology and continues execution based on the result.]],
	name = "Is Researched",
	desc = "Checks whether a faction has something researched",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.for_producers =
{
	func = function(comp, state, cause, in_product, out_producer, exec_done)
		local item_id = GetId(comp, state, in_product)
		local product_def, producers = item_id and data.all[item_id]
		local ent = not product_def and GetEntity(comp, state, in_product)

		if product_def then
			local production_recipe = product_def and (product_def.production_recipe or product_def.construction_recipe)
			producers = production_recipe and production_recipe.producers or product_def.mining_recipe

			-- is Research (uplink_recipe)
			if not producers then
				production_recipe = product_def.uplink_recipe
				producers = production_recipe and production_recipe.producers

				if (producers) then
					local is_unlocked = comp.faction:IsUnlocked(item_id)
					local progress = comp.faction.extra_data.research_progress and comp.faction.extra_data.research_progress[item_id] or 0
					local remain = (product_def.progress_count and product_def.progress_count or progress) - progress

					if not is_unlocked and remain > 0 and producers then
						local it = { 2 }
						if producers then
							-- return the remainder of the research, not just one stack
							for item,n in SortedPairs(producers) do
								it[#it + 1] = { id = item, num = n*remain }
							end

							return BeginBlock(comp, state, it)
						end
					else
						Set(comp, state, out_producer)
						return
					end
				end
			else
				-- if not research and unlocked send the product
				if not comp.faction:IsUnlocked(item_id) then
					Set(comp, state, out_producer)
					return
				end
			end
		elseif ent then
			item_id = ent.def.id

			if not comp.faction:IsUnlocked(item_id) then
				Set(comp, state, out_producer)
				return
			end

			-- from the entity get whether it's a bot or a building from the def.id
			product_def = data.all[item_id]
			local production_recipe = product_def and (product_def.production_recipe or product_def.construction_recipe)
			producers = production_recipe and production_recipe.producers or product_def.mining_recipe
		end


		local it = { 2 }
		if producers then
			for item,n in SortedPairs(producers) do
				it[#it + 1] = { id = item, num = n }
			end
			return BeginBlock(comp, state, it)
		end
		Set(comp, state, out_producer)
		state.counter = exec_done
	end,

	next = function(comp, state, it, in_product, out_producer, exec_done)
		local i = it[1]
		local id
		while i <= #it and not comp.faction:IsUnlocked(it[i].id) do
			i = i+1
		end
		if i > #it then return true end
		Set(comp, state, out_producer, it[i])
		it[1] = i + 1
	end,

	last = function(comp, state, it, in_product, out_producer, exec_done)
		--Set(comp, state, out_producer, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "Production", "Production" },
		{ 'out', "Producer", "Producer" },
		{ 'exec', "Done", "Finished looping through all item producers" },
	},
	explain = [[Loops through all components that can produce a given item and returns the component and its production time.]],
	name = "Loop Producers",
	desc = "Gets all producers for a production with their production time",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.for_producers_items =
{
	func = function(comp, state, cause, c, in_producer, out_item, exec_done)
		local producer_id = GetId(comp, state, in_producer)
		local it = { 1 }
		local def, recipe
		local list_array = c == 1 and comp.faction.unlocked_items or comp.faction.unlocks
		local data_array = c == 1 and data.items or data.all
		for i,k in ipairs(list_array) do
			def = data_array[k]
			local recipe = def.production_recipe
			recipe = recipe and recipe.producers or def.mining_recipe
			recipe = recipe and recipe[producer_id]
			if recipe then
				it[#it + 1] = { id = k }
			end
		end
		if #it > 1 then
			return BeginBlock(comp, state, it)
		else
			local extracts = data.all[producer_id].extracts
			if extracts then
				it[#it + 1] = { id = extracts }
				return BeginBlock(comp, state, it)
			end
		end
		Set(comp, state, out_item)
		state.counter = exec_done
	end,

	next = function(comp, state, it, c, in_producer, out_item, exec_done)
		local i = it[1]
		i = i + 1
		if i > #it then return true end
		Set(comp, state, out_item, it[i])
		it[1] = i
	end,

	last = function(comp, state, it, c, in_producer, out_item, exec_done)
		--Set(comp, state, out_item, nil)
		state.counter = exec_done
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Only Items", "All Unlocks" }
		combo.value = inst.c or 1
		return 34
	end,
	args = {
		{ 'in', "Producer", "Producer" },
		{ 'out', "Item", "Item" },
		{ 'exec', "Done", "Finished looping through all items" },
	},
	sample = "4j3YxVw83WrDqD2fYjuz1j3MVd3ZRfWE1c5oAT3EiyEW0kGOAD19i5RG3JlJSv3HVtw82D3pvI0Q7VQX2SBv2A11I1P40ZC10t1eeALa0Kq2BC0Ga2hD3djiSq0LmhmR1GMKQ803DQis048utU3JxDNA0pAghE3BL",
	name = "Loop Producer Items",
	desc = "Loops through all unlocked items a production component can produce",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.get_unlocked_components = {
	func = function(comp, state, cause, out_item, exec_done)
		local it = { 1 }
		local f = comp.faction
		for i,k in ipairs(f.unlocked_components) do
			local recipe = data.components[k].production_recipe
			recipe = recipe and recipe.producers
			for compid,_ in SortedPairs(recipe or {}) do
				if f:IsUnlocked(compid) then
					it[#it + 1] = { id = k }
					break
				end
			end
		end
		if #it > 1 then return BeginBlock(comp, state, it) end
		Set(comp, state, out_item)
		state.counter = exec_done
	end,

	next = function(comp, state, it, out_item, exec_done)
		local i = it[1]
		i = i + 1
		if i > #it then return true end
		Set(comp, state, out_item, it[i])
		it[1] = i
	end,

	last = function(comp, state, it, out_item, exec_done)
		--Set(comp, state, out_item, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'out', "Item", "Item" },
		{ 'exec', "Done", "Finished looping through all produceable components" },
	},
	sample = "3f3YxVw84XJFlx0w3xzi3tXhH132VJta0glM5t13Fzcn36qizZ4Zc0RV2EUKVt3bqDPN0RImB10ZC4121j8nHm2iRN081x05GM2mZB4N0Gf4tl0CBpFD0Q0HB80aYUoX1JkTgB0tJcm4",
	name = "Loop Unlocked Components",
	desc = "Loops through all produceable unlocked components with a recipe",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.get_research =
{
	func = function(comp, state, cause, out_research)
		local faction_data = comp.faction.extra_data
		local q = faction_data.research_queue or faction_data.research_paused
		if q and q[1] then
			Set(comp, state, out_research, { tech = q[1]})
		else
			Set(comp, state, out_research, nil)
		end
	end,
	explain = [[Returns the current technology being researched, if any.]],
	args = { { 'out', "Tech", "First active research" }, },
	name = "Get Research",
	desc = "Returns the first active research tech",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.get_research_requirement =
{
	func = function(comp, state, cause, in_research, out_research)
		local r = Get(comp, state, in_research)
		local tech_id = r.tech_id
		if not tech_id then return end

		if not tech_id then
			Set(comp, state, out_research, nil)
			return
		end

		local def = data.techs[tech_id]
		local require_tech = def.require_tech[comp.faction.extra_data.race or "robot"] or def.require_tech[1]

		-- no category for listing is an auto unlock research
		if require_tech and not data.techs[require_tech].category then
			Set(comp, state, out_research, nil)
			return
		end

		Set(comp, state, out_research, { tech = require_tech})
	end,
	args = {
		{ 'in', "Tech", "The research to investigate for prior tech requirements", 'tech' },
		{ 'out', "Requirement", "The tech required for the research (if needed)", },
	},
	explain = [[Returns the prerequisite technology for a given research if one exists.]],
	name = "Get Research Requirement",
	desc = "Returns the research required (if needed)",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.set_research =
{
	func = function(comp, state, cause, in_research)
		local r = Get(comp, state, in_research)
		local tech = r.tech_id
		if not tech or not GetResearchableTech(comp.faction)[tech] then return end

		local function ArrayContains(arr, val)
			if not arr then return end
			for _,v in ipairs(arr) do
				if v == val then return true end
			end
		end

		local faction_data = comp.faction.extra_data
		local q = faction_data.research_queue or faction_data.research_paused
		if q and (#q >= 3 or ArrayContains(q, tech)) then return end
		FactionAction.SetResearch(comp.faction, { id = tech })
	end,
	args = { { 'in', "Tech", "First active research", 'tech' }, },
	name = "Set Research",
	desc = "Add a new research into the active research queue",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Adds a new research into the active research queue, but only if the queue isn't full and previous research requirements have been completed.]],
}

data.instructions.clear_research =
{
	func = function(comp, state, cause, in_research)
		local faction_data = comp.faction.extra_data
		local r = Get(comp, state, in_research)
		local tech = r.tech_id
		if not tech then
			faction_data.research_queue, faction_data.research_paused = { }, nil
		else
			local q = faction_data.research_queue or faction_data.research_paused
			local faction_data = comp.faction.extra_data
			local q = faction_data.research_queue or faction_data.research_paused

			local q, q_idx = faction_data.research_queue or faction_data.research_paused, -1
			if not q then q = {} faction_data.research_queue = q end
			for i,v in ipairs(q) do if v == tech then q_idx = i break end end

			table.remove(q, q_idx)
		end

		-- Trigger uplink updates
		for _,c in ipairs(comp.faction:GetComponents("c_uplink", true)) do
			c:Activate()
		end
	end,
	explain = [[Removes a technology from the research queue or clears the queue if none is specified.]],
	args = { { 'in', "Tech", "Tech to remove from research queue", 'tech' }, },
	name = "Clear Research",
	desc = "Clears a research from research queue, or entire queue if no tech passed",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.for_number =
{
	func = function(comp, state, cause, from, to, step, val, exec_done)
		local nfrom, nto, nstep = GetNum(comp, state, from), GetNum(comp, state, to), (step and GetNum(comp, state, step))
		if nfrom == REG_INFINITE or nstep == 0 then state.counter = exec_done return end
		return BeginBlock(comp, state, { nfrom + (nstep and -nstep or ((nfrom <= nto or nto == REG_INFINITE) and -1 or 1)) })
	end,

	next = function(comp, state, it, from, to, step, val, exec_done)
		local i, from_reg, nto, nstep = it[1], Get(comp, state, from), GetNum(comp, state, to), (step and GetNum(comp, state, step))
		if nto == REG_INFINITE then
			i = i + (nstep or 1)
			if i > 2147483647 then i = i - 4294967294 elseif i < (REG_NOT+1) then i = i + 4294967294 end
		elseif not nstep then
			if i == nto then return true end
			i = i + (from_reg.num <= nto and 1 or -1)
		else
			i = i + nstep
			if nstep > 0 then if i > nto then return true end elseif i < nto then return true end
		end
		local newval = Tool.NewRegisterObject(from_reg)
		newval.num = i
		Set(comp, state, val, newval)
		it[1] = i
	end,

	last = function(comp, state, it, from, to, step, val, exec_done)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "From", "Loop start number", 'num' },
		{ 'in', "To", "Loop end number", 'num' },
		{ 'in', "Step", "Increment step, use -1 or 1 based on inputs if left empty", 'num', true },
		{ 'out', "Value", "Current number" },
		{ 'exec', "Done", "Finished loop" },
	},
	name = "Loop Number",
	desc = "Performs code for all numbers in a range",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Loops from a start number to an end number with optional step increments.]],
}

--------------------------------------------------------------------------------------------------------------------------
--------------------------------------- MATH -----------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------

data.instructions.check_number =
{
	func = function(comp, state, cause, if_larger, if_smaller, val1, val2)
		local num1, num2 = GetNum(comp, state, val1), GetNum(comp, state, val2)

		if num1 == REG_INFINITE and num2 == REG_INFINITE then
			return
		elseif num1 == REG_INFINITE then
			state.counter = if_larger
			return
		elseif num2 == REG_INFINITE then
			state.counter = if_smaller
			return
		end

		local d = num1 - num2
		if d < 0 then
			state.counter = if_smaller
		elseif d > 0 then
			state.counter = if_larger
		end
	end,
	exec_arg = { 1, "If Equal", "Where to continue if the numerical values are the same" },
	args = {
		{ 'exec', "If Larger", "Where to continue if Value is larger than Compare" },
		{ 'exec', "If Smaller", "Where to continue if Value is smaller than Compare" },
		{ 'in', "Value", "The value to check with", 'num' },
		{ 'in', "Compare", "The number to check against", 'num' },
	},
	name = "Compare Number",
	desc = "Divert program depending on number of Value and Compare",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Compares two numerical values and diverts logic depending on whether one is larger or smaller or both the same.]],
}

data.instructions.set_reg =
{
	func = function(comp, state, cause, value, output)
		--local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		--if not ent then return end -- don't set if a unit is passed but the unit is nil

		--print("[SET_REG] value: #" .. value, Get(comp, state, value), " - output: #" .. output, Get(comp, state, output))
		Set(comp, state, output, Get(comp, state, value))
	end,
	args = {
		{ 'in', "Value", nil, 'any' },
		{ 'out', "Target" },
		--{ 'in', "Unit", "The unit to copy value to (if not self)", 'entity', true },
	},
	explain = [[Copies a value from one register to another.

The <hl>Value</> can be a constant register or a value passed via a <bl>parameter</> or <bl>variable</>.
The <hl>Target</> can be any <bl>parameter</> or <bl>variable</>.]],
	name = "Copy",
	desc = "Copy a value to a frame register, parameter or variable",
	sample = "3W3bEIye46U9yq3NmKKR12zdfK0kGNlX0yMA8M1sAjR732tz0E0OauG50T7oyz1j5YIq2gViSb24q4jh1UWD624cqTiE2H2sxW27unYF000qIO0f0uTP1",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
}

data.instructions.set_comp_reg =
{
	func = function(comp, state, cause, value, to, group_index)
		to = Get(comp, state, to)
		local to_id, to_num = to.id, math.max(to.num, 1)
		local to_comp = to_id and GetComponentFromSortedGroupIndex(comp, state, to_id, group_index)
		if not to_comp or to_num > to_comp.register_count then return end

		local register_defs = to_comp.def.registers
		local register_def = register_defs and register_defs[to_num]
		if register_def and register_def.read_only then return end

		to_comp:SetRegister(to_num, Get(comp, state, value))
	end,
	args = {
		{ 'in', "Value", "Value to set", 'any' },
		{ 'in', "To", "Component and register number to set", 'comp_num' },
		{ 'in', "Component Index", "Component index if multiple are equipped", 'posnum', true },
	},
	explain = [[Writes a value to a register of the specified component

<hl>Component Index</> can be used to specify the component if multiple are equipped.]],
	name = "Set to Component",
	desc = "Writes a value into a component register",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Set Component Reg.png",
}

data.instructions.get_comp_reg =
{
	func = function(comp, state, cause, from, value, group_index)
		from = Get(comp, state, from)
		local from_id, from_num = from.id, math.max(from.num, 1)
		local from_comp = from_id and GetComponentFromSortedGroupIndex(comp, state, from_id, group_index)
		Set(comp, state, value, from_comp and from_comp:GetRegister(from_num))
	end,
	args = {
		{ 'in', "From", "Component and register number to get", 'comp_num' },
		{ 'out', "Value", "Value of Register"},
		{ 'in', "Component Index", "Component index if multiple are equipped", 'posnum', true },
	},
	explain = [[Reads a value from a register of a specific component and register offset.

<hl>Component Index</> can be used to specify the component if multiple are equipped.]],
	name = "Get from Component",
	desc = "Reads a value from a component register",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Set Component Reg.png",
}

data.instructions.is_working =
{
	func = function(comp, state, cause, not_working, getcomp, group_index, out_component_id)
		local getcompid = GetId(comp, state, getcomp)
		if not getcompid then
			-- If nothing is set, search all sockets in the entity
			for _,v in ipairs(comp.owner.components) do
				if v.is_working then
					-- Return when finding any working component
					Set(comp, state, out_component_id, { id = v.id } )
					return
				end
			end
		else
			local checkcomp = GetComponentFromSortedGroupIndex(comp, state, getcompid, group_index)
			if checkcomp and checkcomp.is_working then return end
		end
		Set(comp, state, out_component_id, nil)
		state.counter = not_working
	end,
	args = {
		{ 'exec', "Is Not Working", "If the requested component is NOT currently working" },
		{ 'in', "Component", "Specific component to check or empty to check all components", 'comp' },
		{ 'in', "Component Index", "Component index if multiple are equipped", 'posnum', true },
		{ 'out', "Value", "Returns the currently working component", 'entity', true },
	},
	explain = [[Checks if a component is currently functioning and returns the component if so.]],
	name = "Is Working",
	desc = "Checks whether a particular component is currently working",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.get_equipped_num =
{
	func = function(comp, state, cause, getcomp, value, entity_in)
		local getcompreg = Get(comp, state, getcomp)
		local getcompid = getcompreg and getcompreg.id
		if not getcompid then Set(comp, state, value, nil ) return end
		local target_entity = GetEntity(comp, state, entity_in)

		if target_entity then
			if not comp.faction:IsSeen(target_entity) then
				Set(comp, state, value, nil )
				return
			end
		else
			if entity_in then Set(comp, state, value, nil ) return end
			target_entity = comp.owner
		end

		Set(comp, state, value, { id = getcompid, num = target_entity:CountComponents(getcompid) } )
	end,
	args = {
		{ 'in', "Component ID", "Component to search for", 'comp_num' },
		{ 'out', "Value" },
		{ 'in', "Unit", "The unit to check (if not self)", 'entity', true },
	},
	explain = [[Returns how many of a specific component are equipped on a unit.]],
	name = "Get Equipped Num",
	desc = "Returns how many of a component are equipped",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.set_number =
{
	func = function(comp, state, cause, val, in_num, to)
		local orig_reg = Get(comp, state, val)
		local reg = Get(comp, state, in_num)
		local r = Tool.NewRegisterObject(orig_reg) -- copy to avoid changing from
		if reg.num then r.num = reg.num end
		if reg.coord then r.coord = reg.coord end
		Set(comp, state, to, r)
	end,
	args = {
		{ 'in', "Value" },
		{ 'in', "Num/Coord", nil, 'coord_num' },
		{ 'out', "To" },
	},
	explain = [[Updates the number or coordinate portion of a register with a new value.]],
	name = "Set Number",
	desc = "Sets the numerical/coordinate part of a value",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.combine_coordinate =
{
	func = function(comp, state, cause, num_x, num_y, out_coord)
		local new_x = GetNum(comp, state, num_x)
		local new_y = GetNum(comp, state, num_y)

		if (new_x == REG_INFINITE or new_y == REG_INFINITE) then
			Set(comp, state, out_coord)
			return
		end

		Set(comp, state, out_coord, { coord = { new_x, new_y } })
	end,
	args = {
		{ 'in', "x", nil, 'num' },
		{ 'in', "y", nil, 'num' },
		{ 'out', "Result" },
	},
	explain = [[Creates a coordinate value from two numbers representing x and y.]],
	name = "Combine Coordinate",
	desc = "Returns a coordinate made from x and y values",
	sample = "4V3bEIye4F8vRo3y6yyh3JEC0q24sJs03rIg9h2z3dS82bosJY1WB3Vs1QfWh92ynD070esWUe3ZPz5S2OXx7G2gdoO42uB0rM26iLRk3ZPWuv2Sb5Jy0XWKb013xIEd2j1hb32ijKDE09r9hZ0jBjWK3sm",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.separate_coordinate =
{
	func = function(comp, state, cause, in_coord, out_x, out_y)
		local coordinate = GetCoord(comp, state, in_coord)

		if not coordinate then
			Set(comp, state, out_x)
			Set(comp, state, out_y)
			return
		end

		if (coordinate.x == REG_INFINITE or coordinate.y == REG_INFINITE) then
			Set(comp, state, out_x)
			Set(comp, state, out_y)
			return
		end

		Set(comp, state, out_x, { num = coordinate.x })
		Set(comp, state, out_y, { num = coordinate.y })
	end,
	args = {
		{ 'in', "Coordinate", nil, 'coord' },
		{ 'out', "x" },
		{ 'out', "y" },
	},
	explain = [[Splits a coordinate value into separate x and y outputs.]],
	name = "Separate Coordinate",
	desc = "Split a coordinate into x and y values",
	category = "Math",
	sample = "4V3bEIye4F8vRo3y6yyh3JEC0q24sJs03rIg9h2z3dS82bosJY1WB3Vs1QfWh92ynD070esWUe3ZPz5S2OXx7G2gdoO42uB0rM26iLRk3ZPWuv2Sb5Jy0XWKb013xIEd2j1hb32ijKDE09r9hZ0jBjWK3sm",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.combine_register =
{
	func = function(comp, state, cause, in_num, in_entity, out_register, in_x, in_y)
		local is_valid_coord = true
		local new_x, new_y

		-- find if coords exist
		local reg = Get(comp, state, in_x)
		if reg.is_empty then
			is_valid_coord = false
		else
			reg = Get(comp, state, in_y)

			if reg.is_empty then
				is_valid_coord = false
			else
				new_x = GetNum(comp, state, in_x)
				new_y = GetNum(comp, state, in_y)

				if (new_x == REG_INFINITE or new_y == REG_INFINITE) then
					is_valid_coord = false
				end
			end
		end

		local number = GetNum(comp, state, in_num)
		local ent = GetEntity(comp, state, in_entity)
		local reg_id = GetId(comp, state, in_entity)

		if is_valid_coord then
			-- Entity is passed along with coordinate but the coordinate display overrides the icon in the UI
			Set(comp, state, out_register, { num = number, entity = ent or nil, id = reg_id or nil, coord = { new_x, new_y } } )
		else
			Set(comp, state, out_register, { num = number, entity = ent or nil, id = reg_id or nil } )
		end
	end,
	args = {
		{ 'in', "Num" },
		{ 'in', "Unit" },
		{ 'out', "Register", nil, 'entity' },
		{ 'in', "x", nil, nil, true },
		{ 'in', "y", nil, nil, true },
	},
	explain = [[Creates a register from individual components like number, entity, ID, and coordinates.

Note: A Register can hold a number, and then one of the following: ID, entity, coordinate.]],
	name = "Combine Register",
	desc = "Combine to make a register from separate parameters",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.separate_register =
{
	func = function(comp, state, cause, in_register, out_num, out_entity, out_id, out_x, out_y)

		local coordinate = GetCoord(comp, state, in_register)

		if coordinate then
			Set(comp, state, out_x, { num = coordinate.x })
			Set(comp, state, out_y, { num = coordinate.y })
		else
			Set(comp, state, out_x)
			Set(comp, state, out_y)
		end

		-- Returning infinity in this case is likely preferable since otherwise original data would be lost
		Set(comp, state, out_num, { num = GetNum(comp, state, in_register) } )

		local ent = GetEntity(comp, state, in_register)

		if ent then
			Set(comp, state, out_entity, { entity = ent } )
		else
			Set(comp, state, out_entity)
		end

		local reg_id = GetId(comp, state, in_register)

		if reg_id then
			Set(comp, state, out_id, { id = reg_id } )
		else
			Set(comp, state, out_id)
		end
	end,
	args = {
		{ 'in', "Register", nil, 'entity' },
		{ 'out', "Num" },
		{ 'out', "Unit", nil, nil, true  },
		{ 'out', "ID", nil, nil, true  },
		{ 'out', "x", nil, nil, true },
		{ 'out', "y", nil, nil, true },
	},
	explain = [[Splits a register into its individual parts: number, entity, ID, x, and y.]],
	name = "Separate Register",
	desc = "Split a register into separate parameters",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.bitwise_op = {
	func = function(comp, state, cause, op_type, in_val1, in_val2, out_val)
		local val = Get(comp, state, in_val1)
		local a = val.num
		local b = GetNum(comp, state, in_val2)
		local result = 0

		if     op_type ==  1 then result = a & b  -- AND
		elseif op_type ==  2 then result = a | b  -- OR
		elseif op_type ==  3 then result = a ~ b  -- XOR
		elseif op_type ==  4 then result = ~a     -- NOT (ignores b)
		elseif op_type ==  5 then result = a << b -- Shift Left
		elseif op_type ==  6 then result = a >> b -- Shift Right
		elseif op_type ==  7 then result = a == b and 1 or 0 -- Compare Equal
		elseif op_type ==  8 then result = a >  b and 1 or 0 -- Compare Larger
		elseif op_type ==  9 then result = a >= b and 1 or 0 -- Compare Larger or Equal
		elseif op_type == 10 then result = a + b             -- Add
		elseif op_type == 11 then result = a - b             -- Subtract
		elseif op_type == 12 then result = a * b             -- Multiply
		elseif op_type == 13 then result = a // b            -- Divide
		elseif op_type == 14 then result = a % b             -- Modulo
		end

		Set(comp, state, out_val, { num = result, id = val.id })
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,

	args = {
		{ 'in', "A", "First value (or value for NOT)", 'num' },
		{ 'in', "B", "Second value (ignored for NOT)", 'num', true },
		{ 'out', "Result", "Bitwise operation result" },
	},

	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo width=180 on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "AND", "OR", "XOR", "NOT", "Shift Left", "Shift Right", "Compare Equal", "Compare Larger", "Compare Larger or Equal", "Add", "Subtract", "Multiply", "Divide", "Modulo" }
		combo.value = inst.c or 1
		combo.tooltip = function (cmb) return cmb.text end
		return 34
	end,
	name = "Bitwise Op",
	desc = "Performs a bitwise operation on two values",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Performs bitwise logic on two numbers.]],
}

data.instructions.check_bit = {
	func = function(comp, state, cause, exec_clear, in_value, in_bit_index)
		local value = GetNum(comp, state, in_value)
		local bit_index = GetNum(comp, state, in_bit_index)

		if bit_index <= 0 or bit_index > 32 then
			state.counter = exec_clear
		end

		local mask = 1 << (bit_index-1)
		if (value & mask) == 0 then
			state.counter = exec_clear
		end
	end,

	args = {
		{ 'exec', "Bit Clear", "Execution path if bit is clear" },
		{ 'in', "Value", "The number to check", 'num' },
		{ 'in', "Bit Index", "Bit index (1 = least significant)", 'num' },
	},

	exec_arg = { 1, "Bit Set", "Execution path if bit is set" },
	name = "Check Bit",
	desc = "Checks if a specific bit is set in a number",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Checks whether the bit at a specific index is set in the input <hl>Value</>. Index is 1-based (1 = least significant bit).

If the bit is set (1), execution jumps to the <hl>Bit Set</> path.
If the bit is clear (0), execution jumps to the <hl>Bit Clear</> path.]],
}

data.instructions.add =
{
	func = function(comp, state, cause, left, right, res)
		Set(comp, state, res, Get(comp, state, left) + Get(comp, state, right))
	end,
	args = {
		{ 'in', "To", nil, 'any' },
		{ 'in', "Num", nil, 'coord_num' },
		{ 'out', "Result" },
	},
	explain = [[Adds two values together and returns the result.]],
	name = "Add",
	desc = "Adds a number or coordinate to another number or coordinate",
	sample = "4n3YxVw80sfebZ3FYilH1mhyfZ1aqqXJ3mEgt61mSlGp1lR1A02pEzn83JGOGx2yjtHI03dj7c393Dme48tMBM0oR9Wf3gYKqo4Ir13P0oIFCO1kWMsT3Fqfg00LjJLm4bI1Jf2giIcU4BzdP64d1urc15VNyW2ReA392sJGaE32eOpU00IptM4J1AVYH",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Add Numbers.png",
}

data.instructions.sub =
{
	func = function(comp, state, cause, left, right, res)
		Set(comp, state, res, Get(comp, state, left) - Get(comp, state, right))
	end,
	args = {
		{ 'in', "From", nil, 'any' },
		{ 'in', "Num", nil, 'coord_num' },
		{ 'out', "Result" },
	},
	explain = [[Subtracts the value in <hl>Num</> from the value in <hl>From</> and stores the result.]],
	name = "Subtract",
	desc = "Subtracts a number or coordinate from another number or coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Substact Numbers.png",
}

data.instructions.mul =
{
	func = function(comp, state, cause, left, right, res)
		Set(comp, state, res, Get(comp, state, left) * Get(comp, state, right))
	end,
	args = {
		{ 'in', "To", nil, 'any' },
		{ 'in', "Num", nil, 'coord_num' },
		{ 'out', "Result" },
	},
	explain = [[Multiplies two values and returns the result.]],
	name = "Multiply",
	desc = "Multiplies a number or coordinate from another number or coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Mul Numbers.png",
}

data.instructions.div =
{
	func = function(comp, state, cause, left, right, res)
		Set(comp, state, res, Get(comp, state, left) // Get(comp, state, right))
	end,
	args = {
		{ 'in', "From", nil, 'any' },
		{ 'in', "Num", nil, 'coord_num' },
		{ 'out', "Result" },
	},
	explain = [[Divides the value in <hl>Num</> from the value in <hl>From</> and stores the floored integer result.]],
	name = "Divide",
	desc = "Divides a number or coordinate from another number or coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Divide Numbers.png",
}

data.instructions.modulo =
{
	func = function(comp, state, cause, left, right, res)
		Set(comp, state, res, Get(comp, state, left) % Get(comp, state, right))
	end,
	args = {
		{ 'in', "Num", nil, 'any' },
		{ 'in', "By", nil, 'coord_num' },
		{ 'out', "Result" },
	},
	explain = [[Calculates the remainder of a division of <hl>Num</> by the value in <hl>By</>.]],
	name = "Modulo",
	desc = "Get the remainder of a division",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Mul Numbers.png",
}

data.instructions.random_number =
{
	func = function(comp, state, cause, min, max, out_num)
		local min_num, max_num = GetNum(comp, state, min), GetNum(comp, state, max)
		if (min_num == REG_INFINITE or max_num == REG_INFINITE) or (min_num == 0 and max_num == 0) then Set(comp, state, out_num, nil) return end
		if min_num == max_num then Set(comp, state,out_num, min_num) return end
		if min_num > max_num then local num = min_num min_num = max_num max_num = num end
		Set(comp, state, out_num, math.random(min_num, max_num))
	end,
	args = {
		{ 'in', "Min", nil, 'num' },
		{ 'in', "Max", nil, 'num' },
		{ 'out', "Result" },
	},
	name = "Random Number",
	desc = "Returns a random number value between a min and max value",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Generates a random number between and including the specified minimum and maximum numbers.]],
}

data.instructions.random_coordinate =
{
	func = function(comp, state, cause, in_value, range, out_coord)
		local range, ent, coord = GetNum(comp, state, range), GetEntity(comp, state, in_value)
		if range == 0 then Set(comp, state, out_coord) return end
		if not ent then coord = GetCoord(comp, state, in_value) else coord = ent.location end
		if not coord then Set(comp, state, out_coord) return end
		Set(comp, state, out_coord, { coord = { coord.x + math.random(-range, range), coord.y + math.random(-range, range) } })
	end,
	args = {
		{ 'in', "Coordinate", "Entity or Coordinate", 'coord' },
		{ 'in', "Range", "Radius range from coordinate", 'posnum' },
		{ 'out', "Result" },
	},
	name = "Random Coordinate",
	desc = "Returns a random coordinate from a location within a specified range",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	sample = "4n3YxVw80sfebZ3FYilH1mhyfZ1aqqXJ3mEgt61mSlGp1lR1A02pEzn83JGOGx2yjtHI03dj7c393Dme48tMBM0oR9Wf3gYKqo4Ir13P0oIFCO1kWMsT3Fqfg00LjJLm4bI1Jf2giIcU4BzdP64d1urc15VNyW2ReA392sJGaE32eOpU00IptM4J1AVYH",
	explain = [[Generates a random coordinate within a certain range, which can include inaccessible coordinates.]],
}

data.instructions.getfreespace =
{
	func = function(comp, state, cause, item_in, item_out, in_unit)
		local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		if not ent then Set(comp, state, item_out, nil) return end
		item_in = GetId(comp, state, item_in)
		Set(comp, state, item_out, item_in and { id = item_in, num = ent:CountFreeSpace(item_in) })
	end,
	args = {
		{ 'in', "Item", "Item to check can fit", "item" },
		{ 'out', "Result", "Number of a specific item that can fit on a unit" },
		{ 'in', "Unit", "The unit to check (if not self)", 'entity', true },
	},
	explain = [[Calculates how many of a specific item can fit into a unit's inventory.]],
	name = "Get space for item",
	desc = "Returns how many of the input item can fit in the inventory",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
}
data.instructions.checkfreespace =
{
	func = function(comp, state, cause, if_cantfit, item_in, in_unit)
		local ent = GetFactionEntityOrSelf(comp, state, in_unit) or comp.owner
		local item_reg = Get(comp, state, item_in)
		local item_id = item_reg.id
		local item_entity = not item_id and item_reg.entity
		if item_entity then
			if IsDroppedItem(item_entity) then
				for _,v in ipairs(item_entity.slots or {}) do
					if v.id and v.unreserved_stack > 0 and ent:HaveFreeSpace(v.id) then
						return
					end
				end
				state.counter = if_cantfit
				return
			end
			item_id = GetResourceHarvestItemId(item_entity)
		end
		if item_id then
			local canfit = ent:HaveFreeSpace(item_id, math.max(item_reg.num, 1))
			if not canfit then state.counter = if_cantfit end
		end
	end,
	args = {
		{ 'exec', "Can't Fit", "Execution if it can't fit the item" },
		{ 'in', "Item", "Item and amount to check can fit", 'item_num' },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
	},
	explain = [[Checks if a unit has enough inventory space to store a given item and quantity.]],
	name = "Check space for item",
	desc = "Checks if free space is available for an item and amount",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
}

data.instructions.lock_slots =
{
	func = function(comp, state, cause, c, item_in, num)
		local slot_length = comp.owner.slot_count
		-- Beacon?
		if slot_length == 0 then
			return
		end
		local slots = comp.owner.slots

		local item_reg, owner = Get(comp, state, item_in), comp.owner
		local item_id = item_reg.id

		if slots then
			local index = GetNum(comp, state, num)

			if index > 0 and index <= slot_length  then
				local slot = owner.slots[index]
				if slot then
					if c == 2 or slot.locked == false then -- only override locked slots if its set to override
						-- if slot already empty or item_in contains nil, then just lock as is
						if slot.stack == 0 then slot.locked = false end
						if (item_id == nil) then
							slot.locked = true
						else
							slot:SetLockedItem(item_id)
						end
					end
				end
			else
				for _,v in ipairs(slots) do
					-- Stop "ALL locking" touching the special storage types like, garage drone and gas
					if v.type == "storage" then
						if c == 2 or v.locked == false then -- only override locked slots if its set to override
							if v.stack == 0 then v.locked = false end
							if (item_id == nil) then
								v.locked = true
							else
								v:SetLockedItem(item_id)
							end
						end
					end
				end
			end
		end
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	args = {
		{ 'in', "Item", "Item type to try locking to the slots", 'item_num' },
		{ 'in', "Slot index", "Individual slot to lock", 'posnum', true },
	},
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Only Unlocked", "Override Locked" }
		combo.value = inst.c or 1
		return 34
	end,
	name = "Lock Item Slots",
	desc = "Lock all storage slots or a specific item slot index",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
	sample = "2d3bEIye2qnppo1wlqdV2piXHJ4colJi49hpUS49FnY40DeO5V1nK8gH4JRU453rnJr82huMTb1NlveV1qm7Hu1DhRzS3INCCr06d0Qc",
	explain = [[Prevents items from being added or removed from specified inventory slots.]]
}

data.instructions.unlock_slots =
{
	func = function(comp, state, cause, num)
		local slot_length = comp.owner.slot_count
		-- Beacon?
		if slot_length == 0 then
			return
		end
		local slots = comp.owner.slots

		if slots then
			local index = GetNum(comp, state, num)

			if index > 0 and index <= slot_length  then
				local slot = slots[index]
				if slot then
					slot.locked = false
				end
			else
				for _,v in ipairs(slots) do
					-- Stop "ALL locking" touching the special storage types like, garage, drone and gas etc
					if v.type == "storage" then
						v.locked = false
					end
				end
			end
		end
	end,
	args = {
		{ 'in', "Slot index", "Individual slot to unlock", 'posnum', true },
	},
	name = "Unlock Item Slots",
	desc = "Unlock all inventory slots or a specific item slot index",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
	explain = [[Unlocks previously restricted inventory slots for use.]],
}

data.instructions.get_health =
{
	func = function(comp, state, cause, target, percent, current, max)
		local target_entity = GetFactionEntityOrSelf(comp, state, target)
		-- If target_entity not valid use reference to Self
		if target_entity and comp.faction:IsSeen(target_entity) then
			local h, mh = target_entity.health, target_entity.max_health
			local health_percent = math.floor(h*100/mh)

			Set(comp, state, percent, { entity = target_entity, num = health_percent })
			Set(comp, state, current, { entity = target_entity, num = target_entity.health })
			Set(comp, state, max, { entity = target_entity, num = target_entity.max_health })

			return
		end

		Set(comp, state, percent, nil)
		Set(comp, state, current, nil)
		Set(comp, state, max, nil)
	end,
	args = {
		{ 'in', "Unit", "Unit to check", 'entity' },
		{ 'out', "Percent", "Percentage of health remaining" },
		{ 'out', "Current", "Value of health remaining", nil, true },
		{ 'out', "Max", "Value of maximum health", nil, true },
	},
	name = "Get Health",
	desc = "Gets a unit's health as a percentage, current remaining and max amount",
	category = "Math",
	icon = "Main/skin/Icons/Common/56x56/H Value.png",
	explain = [[Gets health values for a Unit. Defaults to the unit the behavior is executing on.

<hl>Percent</> is the current health as a percentage of max health
<hl>Current</> is the actual amount of health points left
<hl>Max</> is the maximum amount of health points

Optional <hl>Unit</> parameter to specify a different unit in your faction.]],
}

data.instructions.get_shield =
{
	func = function(comp, state, cause, target, percent, current, max)
		local target_entity = GetFactionEntityOrSelf(comp, state, target)
		-- If target_entity not valid use reference to Self
		if target_entity and comp.faction:IsSeen(target_entity) then
			local current_shield = 0
			local max_shield = 0

			-- check for multiple equipped shields
			for ii,v in ipairs(target_entity.components) do
				if v and v.id == "c_shield_generator" or v.id == "c_shield_generator2" or v.id == "c_shield_generator3" then
					current_shield = current_shield + v.extra_data.stored
					max_shield = max_shield + v.def.shield_max
				end
			end

			-- shield(s) found
			if max_shield > 0 then
				local s, ms = current_shield, max_shield
				local shield_percent = math.floor(s*100/ms)

				Set(comp, state, percent, { entity = target_entity, num = shield_percent })
				Set(comp, state, current, { entity = target_entity, num = current_shield })
				Set(comp, state, max, { entity = target_entity, num = max_shield })

				return
			end
		end

		Set(comp, state, percent, nil)
		Set(comp, state, current, nil)
		Set(comp, state, max, nil)
	end,
	args = {
		{ 'in', "Unit", "Unit to check", 'entity' },
		{ 'out', "Percent", "Percentage of shield remaining" },
		{ 'out', "Current", "Value of shield remaining", nil, true },
		{ 'out', "Max", "Value of maximum shield amount", nil, true },
	},
	name = "Get Shield",
	desc = "Get a unit's shield as a percentage, current remaining and max amount",
	category = "Math",
	icon = "Main/skin/Icons/Common/56x56/H Value.png",
	explain = [[Returns the current shield value of a unit, if equipped.]],
}

data.instructions.get_entity_at =
{
	func = function(comp, state, cause, in_coord, out_result)
		local faction = comp.faction
		local coord = GetCoord(comp, state, in_coord)
		if not coord then
			Set(comp, state, out_result)
			return
		end

		local result = Map.GetEntityAt(coord.x, coord.y)
		if result and comp.faction:IsSeen(result) then
			Set(comp, state, out_result, { entity = result })
		else
			Set(comp, state, out_result)
		end
	end,
	args = {
		{ 'in', "Coordinate", "Coordinate to get Unit from", 'coord' },
		{ 'out', "Result" },
	},
	name = "Get Unit At",
	desc = "Gets the best matching unit at a coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
	explain = [[Returns the unit located at a specific coordinate if visible.]],
}

data.instructions.get_grid_effeciency =
{
	func = function(comp, state, cause, res)
		local owner, faction = comp.owner, comp.faction
		local grid_index = faction:GetPowerGridIndexAt(owner)
		local grid = grid_index and faction:GetPowerGrid(grid_index)
		Set(comp, state, res, { entity = owner, num = grid and grid.efficiency or 0 })
	end,
	args = {
		{ 'out', "Result" },
	},
	name = "Get Grid Efficiency",
	desc = "Gets the value of the Grid Efficiency as a percent",
	category = "Math",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
	explain = [[Returns the efficiency rating of a component connected to the power grid.]],
}

data.instructions.get_battery =
{
	func = function(comp, state, cause, res)
		Set(comp, state, res, { entity = comp.owner, num = comp.owner.battery_percent })
	end,
	args = {
		{ 'out', "Result" },
	},
	name = "Get Battery",
	desc = "Gets the value of the Battery level as a percent",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Check Battery.png",

	explain = [[Returns the unit and current battery level percentage as a number in the <hl>Result</> parameter.

	When multiple batteries are equipped, all batteries will be calculated.

	A unit that has no batteries equipped will always return zero, even while inside a power grid that has <bl>Unused</> power.]],
}

data.instructions.get_self =
{
	func = function(comp, state, cause, res)
		Set(comp, state, res, { entity = comp.owner })
	end,
	args = {
		{ 'out', "Result" },
	},
	name = "Get Self",
	desc = "Gets the value of the Unit running the behavior",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
	sample = "V02rugE1CW6YQ1rAMqo34kZAG1kNZqx1sI96h00UuuY0FuEN730UuGE1tR5zU00UuuY016",
	explain = [[Returns a reference to the unit running the behavior.]],
}
--------------------------------------------------------------------------------------------------------------------------
--------------------------------------- UNIT -----------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------

data.instructions.read_signal =
{
	func = function(comp, state, cause, in_unit, res)
		local ent = GetEntity(comp, state, in_unit)
		Set(comp, state, res, ent and ent:GetRegister(FRAMEREG_SIGNAL) or nil)
	end,
	args = {
		{ 'in', "Unit", "The owned unit to check for", 'entity' },
		{ 'out', "Result", "Value of units Signal register" },
	},
	name = "Read Signal",
	desc = "Reads the Signal register of another unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Scan.png",
	explain = [[Reads the current value of the <hl>Signal</> register from a Unit. This instruction does not require a signal reading component to be equipped.]],
}

data.instructions.is_empty =
{
	func = function(comp, state, cause, in_value, exec_empty, exec_has)
		local reg = Get(comp, state, in_value)
		if reg.is_empty then state.counter = exec_empty
		else state.counter = exec_has
		end
	end,
	exec_arg = false,
	args = {
		{ 'in', "Value", "Value to check", },
		{ 'exec', "Empty", "Where to continue if the value is empty" },
		{ 'exec', "Has Value", "Where to continue if the value exists" },
		--{ 'exec', "Space", "Where to continue if the unit is in space" },
	},
	name = "Is Empty",
	desc = "Checks a value if it is empty",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Checks the passed value and if it is empty diverts logic using the result.]],
}
data.instructions.read_radio =
{
	func = function(comp, state, cause, in_band, res)
		local radio_storage = comp.faction.extra_data.radio_storage
		local radio_storage_bands = radio_storage and radio_storage.extra_data.bands
		if not radio_storage_bands then Set(comp, state, res) return end

		local band, idx = Get(comp, state, in_band)
		for i,v in ipairs(radio_storage_bands) do
			if v == band then
				idx = i
				break
			end
		end

		if not idx then Set(comp, state, res) return end
		Set(comp, state, res, radio_storage:GetRegister(idx))
	end,
	args = {
		{ 'in', "Band", "The band to check for" },
		{ 'out', "Result", "Value of the radio signal" },
	},
	name = "Read Radio",
	desc = "Reads the Radio signal on a specified band",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Scan.png",
	explain = [[Receives and processes a message from the radio system. This instruction does not require a radio receiving component to be equipped.]],
}

data.instructions.for_signal =
{
	func = function(comp, state, cause, in_signal, out_unit, exec_done)
		local signal = Get(comp, state, in_signal)

		local it = { 2 }
		for _,v in ipairs(comp.faction.entities) do
			local unit_sig = v:GetRegister(FRAMEREG_SIGNAL)
			if unit_sig and unit_sig.id == signal.id then
				it[#it+1] = v
			end
		end

		return BeginBlock(comp, state, it)
	end,

	next = function(comp, state, it, in_signal, out_unit, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_unit, { entity = it[i] })
		it[1] = i + 1
	end,

	last = function(comp, state, it, in_signal, out_unit, exec_done)
		Set(comp, state, out_unit, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "Signal", "Signal" },
		{ 'out', "Unit", "Unit with signal" },
		{ 'exec', "Done", "Finished looping through all units with signal" },
	},
	deprecated = true,
	name = "*Loop Signal*",
	desc = "*DEPRECATED* Use Loop Signal (Match) instead",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Loops over all signal channels or lines available to the unit or component.]],
}

data.instructions.for_signal_match =
{
	func = function(comp, state, cause, filter_type, in_signal, out_unit, out_signal, exec_done)
		local signal = GetId(comp, state, in_signal)
		local signal_num = GetNum(comp, state, in_signal)
		local owner = comp.owner
		local it = { 2 }

		local function FilterForSignal(signal_ent, filter_type)
			local function FilterSpecialNum(num)
				if num == REG_NOT then num = 0
				elseif num == REG_INFINITE then num = 2147483647 end
				return num
			end

			-- filter_type == 1 "Match" -- "Match" is default so FilterForSignal function is not called
			local reg_num
			if filter_type == 2 then -- "Exact"
				for i = #signal_ent, 1, -1 do
					reg_num = signal_ent[i]:GetRegister(FRAMEREG_SIGNAL).num
					if signal_num ~= reg_num then table.remove(signal_ent, i) end
				end
				return signal_ent
			elseif filter_type == 3 then -- "Not Exact"
				for i = #signal_ent, 1, -1 do
					reg_num = signal_ent[i]:GetRegister(FRAMEREG_SIGNAL).num
					if signal_num == reg_num then table.remove(signal_ent, i) end
				end
				return signal_ent
			end

			local num = FilterSpecialNum(Tool.Copy(signal_num))

			if filter_type == 4 then -- < "Less Than"
				for i = #signal_ent, 1, -1 do
					reg_num = FilterSpecialNum(signal_ent[i]:GetRegister(FRAMEREG_SIGNAL).num)
					if num <= reg_num then table.remove(signal_ent, i) end
				end
			elseif filter_type == 5 then -- <= "Exact Or Less Than"
				for i = #signal_ent, 1, -1 do
					reg_num = FilterSpecialNum(signal_ent[i]:GetRegister(FRAMEREG_SIGNAL).num)
					if num < reg_num then table.remove(signal_ent, i) end
				end
			elseif filter_type == 6 then -- > "More Than"
				for i = #signal_ent, 1, -1 do
					reg_num = FilterSpecialNum(signal_ent[i]:GetRegister(FRAMEREG_SIGNAL).num)
					if num >= reg_num then table.remove(signal_ent, i) end
				end
			elseif filter_type == 7 then -- >= "Exact Or More Than"
				for i = #signal_ent, 1, -1 do
					reg_num = FilterSpecialNum(signal_ent[i]:GetRegister(FRAMEREG_SIGNAL).num)
					if num > reg_num then table.remove(signal_ent, i) end
				end
			end

			return signal_ent
		end

		if signal == nil then
			signal = Get(comp, state, in_signal)
			local e = signal.entity
			local signal_ent = comp.faction:GetEntitiesWithRegister(FRAMEREG_SIGNAL, e, true)
			if signal_ent and filter_type ~= 1 then signal_ent = FilterForSignal(signal_ent, filter_type) end
			for _,v in ipairs(signal_ent) do
				local unit_sig = v:GetRegister(FRAMEREG_SIGNAL)
				it[#it+1] = v
				it[#it+1] = unit_sig
			end
		else
			local faction, filters = comp.faction, { signal, signal_num }
			local signal_ent = faction:GetEntitiesWithRegister(FRAMEREG_SIGNAL, signal, true)
			if signal_ent and filter_type ~= 1 then signal_ent = FilterForSignal(signal_ent, filter_type) end
			for _,v in ipairs(signal_ent) do
				local unit_sig = v:GetRegister(FRAMEREG_SIGNAL)
				if unit_sig then
					local unit_sig_id, unit_sig_entity = unit_sig.id, unit_sig.entity
					if unit_sig_id == signal then
						it[#it+1] = v
						it[#it+1] = { id = unit_sig_id, num = unit_sig.num, entity = unit_sig_entity }
					elseif unit_sig_entity and unit_sig_entity:MatchFilter(PrepareFilterEntity(filters), faction) then
						local ret, num = FilterEntity(owner, unit_sig_entity, filters)
						if ret then
							it[#it+1] = v
							it[#it+1] = { id = unit_sig_id, num = num or unit_sig.num, entity = unit_sig_entity }
						end
					end
				end
			end
		end
		return BeginBlock(comp, state, it)
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,

	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50 width=185/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Match", "Exact", "Not Exact", "Less Than", "Exact Or Less Than", "More Than", "Exact Or More Than" }
		combo.value = inst.c or 1
		return 34
	end,

	next = function(comp, state, it, filter_type, in_signal, out_unit, out_signal, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_unit, { entity = it[i] })
		Set(comp, state, out_signal, it[i+1])
		it[1] = i + 2
	end,

	last = function(comp, state, it, filter_type, in_signal, out_unit, out_signal, exec_done)
		--Set(comp, state, out_unit, nil)
		--Set(comp, state, out_signal, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "Signal", "Signal" },
		{ 'out', "Unit", "Found Unit with signal" },
		{ 'out', "Signal", "Found signal", 'entity', true },
		{ 'exec', "Done", "Finished looping through all units with signal" },
	},
	name = "Loop Signal",
	desc = "Loops through all units with a signal of similar type and additional number checks",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Loops through signal inputs and returns only those matching specific criteria.]],
}

data.instructions.check_altitude =
{
	func = function(comp, state, cause, in_target, if_valley, if_plateau)
		local ent = GetSeenEntityOrSelf(comp, state, in_target)
		if not ent then
			local coord = GetCoord(comp, state, in_target)
			if not coord or not comp.faction:IsDiscovered(coord) then
				--print("no coord or not discovered")
			elseif Map.GetPlateauDelta(coord.x, coord.y, -1) >= 0 then
				state.counter = if_plateau
			else
				state.counter = if_valley
			end
		elseif Map.GetPlateauDelta(ent, -1) >= 0 then
			state.counter = if_plateau
		else
			state.counter = if_valley
		end
	end,
	exec_arg = { 4, "No Visibility", "No visibility on target", nil, true },
	args = {
		{ 'in', "Target", "The unit or coordinate to check for (if not self)", 'coord', true },
		{ 'exec', "Valley", "Where to continue if the unit or coordinate is in a valley" },
		{ 'exec', "Plateau", "Where to continue if the unit or coordinate is on a plateau" },
		--{ 'exec', "Space", "Where to continue if the unit is in space" },
	},
	name = "Check Altitude",
	desc = "Divert program depending on location of a unit or coordinate",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[
Branches execution based on the altitude of the unit. Defaults to the unit the behavior is equipped on

<img image="Main/textures/behaviors/check_altitude.png"/>

Optional parameter <hl>Target</> can specify a different unit to check. An extra pin becomes available for when the unit is not visible to you.]],
}

data.instructions.check_blightness =
{
	func = function(comp, state, cause, in_target, if_blight)
		local ent = GetSeenEntityOrSelf(comp, state, in_target)
		if not ent then
			local coord = GetCoord(comp, state, in_target)
			if coord and comp.faction:IsDiscovered(coord) and Map.GetBlightnessDelta(coord.x, coord.y, -1) >= 0 then
				state.counter = if_blight
			end
		elseif Map.GetBlightnessDelta(ent, -1) >= 0 then
			state.counter = if_blight
		end
	end,
	args = {
		{ 'in', "Target", "The unit or coordinate to check for (if not self)", 'coord', true },
		{ 'exec', "Blight", "Where to continue if the unit is in the blight" },
	},
	name = "Check Blightness",
	desc = "Divert program depending on location of a unit or coordinate",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Conditional node which diverts program logic depending on whether the unit or a specific location is inside the <hl>blight</>.

This instruction will only return true for locations <bl>inside</> and not <bl>near</> the blight.
Note: <img id="c_blight_extractor" style="hl"/> work near the blight.

<hl>Target</>
External target to check. Target will default to the unit running the Behavior if no value has been set.]],
}

data.instructions.check_health =
{
	func = function(comp, state, cause, if_full, in_unit)
		local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		if ent and not ent.is_damaged then
			state.counter = if_full
		end
	end,
	args = {
		{ 'exec', "Full", "Where to continue if at full health" },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
	},
	name = "Check Health",
	desc = "Check a unit's health",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/H Value.png",
	explain = [[Checks a unit's current health and continues execution based on the result. Defaults to the unit the behavior is running on.

Optional <hl>Unit</> parameter to specify a different unit in your faction.]],
}

data.instructions.check_battery =
{
	func = function(comp, state, cause, if_full, in_unit)
		local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		if ent and ent.battery_percent == 100 then
			state.counter = if_full
		end
	end,
	args = {
		{ 'exec', "Full", "Where to continue if battery power is fully recharged" },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
	},
	name = "Check Battery",
	desc = "Checks the Battery level of a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Check Battery.png",
	explain = [[Conditional node which diverts program logic depending on whether a unit's battery power reserves are <hl>Full</>. Defaults to the unit the behavior is running on.

A unit that has no batteries equipped will never be <hl>Full</>, even while inside a power grid that has <bl>Unused</> power. When multiple batteries are equipped all will need to be full.

An optional <hl>Unit</> parameter allows specifying a different unit in your faction.]],
}

data.instructions.check_grid_effeciency =
{
	func = function(comp, state, cause, if_full, in_unit)
		local ent = GetSeenEntityOrSelf(comp, state, in_unit)
		if not ent then return end
		local faction = comp.faction
		local grid_index = faction:GetPowerGridIndexAt(ent)
		local grid = grid_index and faction:GetPowerGrid(grid_index)
		if grid and grid.efficiency == 100 then
			state.counter = if_full
		end
	end,
	args = {
		{ 'exec', "Full", "Where to continue if at full efficiency" },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
	},
	name = "Check Grid Efficiency",
	desc = "Checks the Efficiency of the logistics network the unit is on",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
	explain = [[Evaluates how efficiently a component is connected to the grid.]],
}

data.instructions.count_item =
{
	func = function(comp, state, cause, c, item, output, in_unit)
		--print("[COUNT_ITEM] item: " .. tostring(GetId(comp, state, item)) .. " (#" .. tostring(item) .. ") - output: #" .. tostring(output))
		local ent, item_id = GetFactionEntityOrSelf(comp, state, in_unit), GetId(comp, state, item)
		-- if nil see if it's an ally
		if not ent then
			local ent_check = GetEntity(comp, state, in_unit)

			if ent_check and comp.faction:IsSeen(ent_check) and ent_check.faction:GetTrust(comp.faction) == "ALLY" then
				ent = ent_check
			else
				-- Return and don't get total from self if "in_unit" failed
				Set(comp, state, output, nil)
				return
			end
		end

		local total = 0
		if ent then
			for i,v in ipairs(ent.slots) do
				if v.id then
					if not item_id or v.id == item_id then
						if c == 2 then
							total = total + v.reserved_stack
						else
							total = total + v.stack
						end
					end
				end
			end
		end
		Set(comp, state, output, { item = item_id, num = total })
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Remaining", "Reserved" }
		combo.value = inst.c or 1
		return 34
	end,

	args = {
		{ 'in', "Item", "Item to count", "item" },
		{ 'out', "Result", "Number of this item in inventory or empty if none exist" },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
	},
	name = "Count Items",
	desc = "Counts the number of the passed item contained in the unit's inventory",
	category = "Unit",
	sample = "V058hik2woTaI21cbOz00W1gr22TIuo1kNaSL20D0P300UuuY3HEnhN02q3fd21cPWy39I8mL1or2Op29Kcbj25sxo500UuuYm",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Counts how many of a specific item are stored in a unit's inventory.

You can request how many items are <hl>Remaining</> in the unit or how many are <hl>Reserved</>.]],
}

local function GetNumSockets(def, socket_size)
	local socks = data.visuals[def.visual].sockets
	if not socks then return 0 end
	local retNum = 0
	for _,v in ipairs(socks) do
		if v[2] == socket_size then retNum = retNum + 1 end
	end
	return retNum
end

local stats_unit = {
	{
		function(def, e)
			local health_boost = e and SumModuleBoosts(e, "c_modulehealth") or 0
			return def.health_points+math.floor(health_boost)
		end,
		"Durability" },
	{
		function(def, e)
			local range_boost = e and SumModuleBoosts(e, "c_modulevisibility") or 0
			return def.visibility_range+math.floor(range_boost)
		end,
		"Visibility Range" },
	{
		function(def, e)
			local move_boost = e and SumModuleBoosts(e, "c_modulespeed") or 0
			return def.movement_speed+math.floor((move_boost*0.01*def.movement_speed)+0.5)
		end,
		"Movement Speed" },
	--{ function(def) local p = def.power return (p and p < 0) and (p*-TICKS_PER_SECOND) or 0 end, "Power Usage" },

	{ function(def, e) return GetNumSockets(def, "Internal") end, "Internal Sockets" },
	{ function(def, e) return GetNumSockets(def, "Small") end, "Small Sockets" },
	{ function(def, e) return GetNumSockets(def, "Medium") end, "Medium Sockets" },
	{ function(def, e) return GetNumSockets(def, "Large") end, "Large Sockets" },
}

local stats_power = {
	{ function(pd) return pd and pd.produced*TICKS_PER_SECOND or 0 end, "Producing" },
	{ function(pd) return pd and pd.required*TICKS_PER_SECOND or 0 end, "Requiring" },
	{ function(pd) return pd and pd.efficiency or 100 end, "Efficiency" },
	{ function(pd) return pd and pd.consumed*TICKS_PER_SECOND or 0 end, "Consuming" },
	{ function(pd) return pd and pd.received*TICKS_PER_SECOND or 0 end, "Receiving" },
	{ function(pd) return pd and pd.transmitted*TICKS_PER_SECOND or 0 end, "Transmitting" },
}

local stats_item = {
	{ "stack_size", "Maximum Stack" },
	{ function(def) return def.range or def.attack_radius or def.transfer_radius or def.miner_range or def.trigger_radius end, "Range" },
	{ "minimum_range", "Min. Range" },
	{ "damage", "Damage" },
	--{ "attack_pattern", "Attack Pattern" },
	{ function(def) return def.damage_type and data.damage_names[def.damage_type] or 0 end, "Damage Type"} ,
	{ "blast", "Blast Radius" },
	{ "shoot_while_moving", "Move and Fire" },
	{ function(def) return (def.damage and def.duration) and def.damage*(TICKS_PER_SECOND/def.duration) or 0 end, "DPS" },
	{ "power_storage", "Power Storage" },
	{ function(def) return (def.drain_rate or 0)*TICKS_PER_SECOND end, "Drain Rate" },
	{ function(def) return (def.charge_rate or 0)*TICKS_PER_SECOND end, "Charge Rate" },
	{ function(def) return (def.bandwidth or 0)*TICKS_PER_SECOND end, "Bandwidth" },
	{ "drone_range", "Drone Range" },
	{ function(def) return (def.power or 0)*TICKS_PER_SECOND end, "Power" },
}

data.instructions.get_unit_info =
{
	func = function(comp, state, cause, c, in_unit, output)
		local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		if not ent then return end

		local def, stat, val = ent.def, stats_unit[c][1]
		if type(stat) == "string" then
			val = def[stat] or 0
		else
			val = stat and stat(def, comp.owner) or 0
		end
		Set(comp, state, output, { id = ent.id, num = val})
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50 width=180/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		local texts = {}
		for i,v in ipairs(stats_unit) do
			texts[#texts+1] = v[2]
		end
		combo.texts = texts
		combo.value = inst.c or 1
		return 34
	end,
	args = {
		{ 'in', "Unit", "The unit to check", },
		{ 'out', "Result", "Returns a specific Unit info" },
	},
	name = "Get Unit Info",
	desc = "Gets information on a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Returns data about a specific unit such as the <bl>Durability</> or <bl>Visibility Range</>.

Return type info can be selected from the dropdown menu.]],
}

data.instructions.get_unit_power_info =
{
	func = function(comp, state, cause, c, in_unit, output)
		local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		if not ent then
			Set(comp, state, output, { num = 0 })
			return
		end

		local def = ent.def
		local stat = stats_power[c][1]
		local power_details = ent.power_details
		local val = stat and stat(power_details) or 0
		Set(comp, state, output, { id = ent.id, num = val})
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50 width=180/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		local texts = {}
		for i,v in ipairs(stats_power) do
			texts[#texts+1] = v[2]
		end
		combo.texts = texts
		combo.value = inst.c or 1
		return 34
	end,
	args = {
		{ 'in', "Unit", "The unit to check", },
		{ 'out', "Result", "Returns a specific Unit's power info" },
	},
	name = "Get Unit Power Info",
	desc = "Gets power information on a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Returns power information about a specific unit such as the power <bl>Producing</> or <bl>Receiving</>.

Return type info can be selected from the dropdown menu.]],
}

data.instructions.get_item_info =
{
	func = function(comp, state, cause, c, in_id, output)
		local item_id = GetId(comp, state, in_id)
		if not item_id then return Set(comp, state, output) end
		local def, stat, val = data.all[item_id], stats_item[c][1]
		if type(stat) == "string" then
			val = def[stat] or 0
		else
			val = stat(def)
		end
		Set(comp, state, output, { id = item_id, num = val})
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50 width=180/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		local texts = {}
		for i,v in ipairs(stats_item) do
			texts[#texts+1] = v[2]
		end
		combo.texts = texts
		combo.value = inst.c or 1
		return 34
	end,
	args = {
		{ 'in', "Item", "The item to check", },
		{ 'out', "Result", "Number of this item's chosen information" },
	},
	name = "Get Item Info",
	desc = "Gets information on an item",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Returns data about a specific item such as the <bl>Maximum Stack</> or <bl>Range</>.

Return type info can be selected from the dropdown menu.]],
}

data.instructions.count_slots =
{
	func = function(comp, state, cause, c, output, in_unit)
		--print("[COUNT_SLOTS] item: " .. tostring(GetId(comp, state, item)) .. " (#" .. tostring(item) .. ") - output: #" .. tostring(output))
		local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		-- if nil see if it's an ally
		if not ent then
			local ent_check = GetEntity(comp, state, in_unit)

			if ent_check and comp.faction:IsSeen(ent_check) and ent_check.faction:GetTrust(comp.faction) == "ALLY" then
				ent = ent_check
			else
				-- Return and don't get total from self if "in_unit" failed
				Set(comp, state, output, nil)
				return
			end
		end
		local total = 0
		if ent then
			if c == 1 then
				total = ent.slot_count
			else
				local slottypes = { "ALL", "storage", "gas", "virus", "anomaly", "drone", "garage", "alien", "satellite" }
				local stype = slottypes[c]
				for i,v in ipairs(ent.slots) do
					if v.type == stype then
						total = total + 1
					end
				end
			end
		end
		Set(comp, state, output, { entity = ent, num = total })
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50 width=100/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "ALL", "storage", "gas", "virus", "anomaly", "drone", "garage", "alien", "satellite" }
		combo.value = inst.c or 1
		return 34
	end,

	args = {
		{ 'out', "Result", "Number of slots of this type" },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
	},
	name = "Count Slots",
	desc = "Returns the number of slots in this unit of the given type",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[This instruction returns the unit and the number of slots found using the search type.

Return type can be selected from the dropdown menu for a specific slot type or <bl>ALL</>.]],
}

data.instructions.get_max_stack =
{
	func = function(comp, state, cause, in_item, out_stacksize)
		local item_id = GetId(comp, state, in_item)
		local idef = data.all[item_id]
		if item_id then
			Set(comp, state, out_stacksize, { item = item_id, num = idef and idef.stack_size or 1 })
		else
			Set(comp, state, out_stacksize)
		end
	end,
	args = {
		{ 'in', "Item", "Item to count", 'item_num' },
		{ 'out', "Max Stack", "Max Stack", },
	},
	name = "Get Max Stack",
	desc = "Returns the amount an item can stack to",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Returns the maximum stack size for a specific item.]],
}

data.instructions.have_item =
{
	func = function(comp, state, cause, item, exec_have, in_unit)
		--print("[COUNT_ITEM] item: " .. tostring(GetId(comp, state, item)) .. " (#" .. tostring(item) .. ") - output: #" .. tostring(output))
		local ent, reg = GetFactionEntityOrSelf(comp, state, in_unit), Get(comp, state, item)
		local item_id = reg.item_id
		if ent and item_id then
			local amt = ent:CountItem(item_id)
			local reg_num = reg.num
			if reg_num == REG_INFINITE then reg_num = 999999 end
			if amt >= reg_num then
				state.counter = exec_have
			end
		end
	end,
	args = {
		{ 'in', "Item", "Item to count", 'item_num' },
		{ 'exec', "Have Item", "have the specified item" },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
	},
	name = "Have Item",
	desc = "Checks if you have at least a specified amount of an item",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Checks if a unit possesses a given item in its inventory and divert logic if the item exists.]],
}

data.instructions.can_equip =
{
	func = function(comp, state, cause, in_unit, in_comp, exec_cant)
		local comp_id = GetId(comp, state, in_comp)
		if not comp_id then state.counter = exec_cant return end

		local reg_id = GetId(comp, state, in_unit)
		if reg_id then
			-- check frame type
			local frame_def = data.frames[reg_id]
			local sockets = frame_def and frame_def.visual
			sockets = sockets and data.visuals[sockets]
			sockets = sockets and sockets.sockets
			local comp_def = data.components[comp_id]
			if not sockets or not comp_def then state.counter = exec_cant return end
			-- check socket sizes

			local comp_sock_size = GetAttachmentSize(comp_def.attachment_size)
			for i,v in ipairs(sockets) do
				if comp_sock_size <= GetAttachmentSize(v[2]) then return end
			end
			state.counter = exec_cant
			return
		end

		local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		if ent then
			-- check entity
			local socket = ent:GetFreeSocket(comp_id)
			if not socket then state.counter = exec_cant end
			return
		end
		state.counter = exec_cant
	end,
	args = {
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
		{ 'in', "Component", "Component to equip", "comp" },
		{ 'exec', "Cannot Equip", "If the component is unable to be equipped" },
	},
	name = "Can Equip",
	explain = [[Checks if a specific component can be equipped on the specified unit or frame type.

If a unit is able to equip a component it will check if there are available sockets.
If a unit type is passed it will check if the frame has any socket able to equip the component]],
	desc = "Checks if a component can be equipped on a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Home.png",
}

data.instructions.equip_component =
{
	func = function(comp, state, cause, no_comp, equip_comp, equip_index)
		local socket
		local num = GetNum(comp, state, equip_index)
		-- if 'equip_index' exists, override and to try equip from index first...
		if num and num > 0 then
			local index_slot = comp.owner.slots[num]
			if index_slot then
				local comp_id = index_slot.id
				if comp_id then
					socket = comp.owner:GetFreeSocket(comp_id)
					if not socket then state.counter = no_comp return end
					if index_slot.unreserved_stack > 0 then
						if comp_id == GetId(comp, state, equip_comp) then
							Map.Defer(function() EntityAction.InvToComp(comp.owner, { slot = index_slot, comp_index = socket }) end)
							return
						end
					end
				end
			end
		end

		-- ... but then if that failed continue on and
		--  try with 'equip_comp' should that value also exist
		local comp_id = GetId(comp, state, equip_comp)
		if not comp_id then state.counter = no_comp return end

		socket = comp.owner:GetFreeSocket(comp_id)
		if not socket then state.counter = no_comp return end

		for _,v in ipairs(comp.owner.slots) do
			if v.id == comp_id and v.unreserved_stack > 0 then
				-- found it.. equip it
				Map.Defer(function() EntityAction.InvToComp(comp.owner, { slot = v, comp_index = socket }) end)
				return
			end
		end
		if no_comp then state.counter = no_comp end
	end,
	args = {
		{ 'exec', "No Component", "If you don't current hold the requested component" },
		{ 'in', "Component", "Component to equip", "comp" },
		{ 'in', "Slot index", "Individual slot to equip component from", 'posnum', true },
	},
	name = "Equip Component",
	desc = "Equips a component if it exists",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Home.png",
	explain = [[Equips a component from inventory if it exists into an available socket if available.]],
}

data.instructions.unequip_component =
{
	func = function(comp, state, cause, no_comp, unequip_comp, unequip_index)
		local num = GetNum(comp, state, unequip_index)
		-- if 'unequip_index' exists, override and to try unequip from index
		if num and num > 0 then
			local socket = comp.owner:GetComponent(num)
			if not socket then
				if no_comp then state.counter = no_comp end
				return
			end

			local index_slot = comp.owner:GetFreeSlot(socket.id)
			if index_slot then
				Map.Defer(function() EntityAction.CompToInv(comp.owner, { comp = socket, slot = index_slot }) end)
			end
		else
			local comp_id = GetId(comp, state, unequip_comp)
			if not comp_id then return end

			local found_comp = comp.owner:FindComponent(comp_id)
			if found_comp == nil then
				if no_comp then state.counter = no_comp return end
			end
			if found_comp and found_comp.is_hidden then state.counter = no_comp return end

			local slot = comp.owner:GetFreeSlot(comp_id)
			if slot then
				Map.Defer(function() EntityAction.CompToInv(comp.owner, { comp = found_comp, slot = slot }) end)
			end
		end
	end,
	args = {
		{ 'exec', "No Component", "If you don't current hold the requested component or slot was empty" },
		{ 'in', "Component", "Component to unequip", "comp" },
		{ 'in', "Slot index", "Individual slot to try to unequip component from", 'posnum', true },
	},
	name = "Unequip Component",
	desc = "Unequips a component if it exists",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Detach.png",
	explain = [[Removes a component from a unit and places it into its inventory but only if free space is available.]],
}

data.instructions.get_closest_entity =
{
	func = function(comp, state, cause, f1, f2, f3, output)
		local owner = comp.owner

		local f1id = GetId(comp, state, f1)
		local filters = { f1id, f1id and GetNum(comp, state, f1), nil, nil, nil, nil }
		if filters[1] then
			filters[3] = GetId(comp, state, f2)
			filters[4] = filters[3] and GetNum(comp, state, f2)
			if filters[3] then
				filters[5] = GetId(comp, state, f3)
				filters[6] = filters[5] and GetNum(comp, state, f3)
			end
		end
		local entity_filter, override_range = PrepareFilterEntity(filters)
		local range, num = owner.visibility_range
		local res = Map.FindClosestEntity(owner, math.min(override_range or range, range), function(e)
			local id,n = FilterEntity(owner, e, filters)
			num = id and n
			return id end,
			entity_filter)
		Set(comp, state, output, { entity = res, num = num })
	end,
	args = {
		{ 'in', "Filter", "Filter to check", 'radar' },
		{ 'in', "Filter", "Second Filter", 'radar', true },
		{ 'in', "Filter", "Third Filter", 'radar', true },
		{ 'out', "Output", "Unit" },
	},
	name = "Get Closest Unit",
	desc = "Gets the closest visible unit matching a filter",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Closest Enemy.png",
	explain = [[Finds and returns the closest visible unit.]],
}

data.instructions.match =
{
	func = function(comp, state, cause, in_unit, f1, f2, f3, failed)
		local owner = comp.owner
		local f1id = GetId(comp, state, f1)
		local filters = { f1id, f1id and GetNum(comp, state, f1), nil, nil, nil, nil }
		if filters[1] then
			filters[3] = GetId(comp, state, f2)
			filters[4] = filters[3] and GetNum(comp, state, f2)
			if filters[3] then
				filters[5] = GetId(comp, state, f3)
				filters[6] = filters[5] and GetNum(comp, state, f3)
			end
		end
		local unit = not in_unit and owner or GetEntity(comp, state, in_unit)
		local res = unit and unit:MatchFilter(PrepareFilterEntity(filters), owner.faction) and FilterEntity(owner, unit, filters)
		if not res then state.counter = failed end
	end,
	args = {
		{ 'in', "Unit", "Unit to Filter, defaults to Self", 'entity' },
		{ 'in', "Filter", "Filter to check", 'radar' },
		{ 'in', "Filter", "Second Filter", 'radar', true },
		{ 'in', "Filter", "Third Filter", 'radar', true },
		{ 'exec', "Failed", "Did not match filter" },
	},
	name = "Match",
	desc = "Filters the passed unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Compares two values and diverts logic depending on the result.]],
}

data.instructions.switch =
{
	func = function(comp, state, cause, in_unit, in_c1, out_c1, in_c2, out_c2, in_c3, out_c3, in_c4, out_c4, in_c5, out_c5)
		local owner, faction = comp.owner, comp.faction
		local unit = not in_unit and owner or GetEntity(comp, state, in_unit)

		if unit then
			local filters = { false, false }
			local function test_unit(in_c)
				filters[1], filters[2] = GetId(comp, state, in_c), GetNum(comp, state, in_c)
				return unit:MatchFilter(PrepareFilterEntity(filters), faction) and FilterEntity(owner, unit, filters)
			end
			if in_c1 and test_unit(in_c1) then state.counter = out_c1 return end
			if in_c2 and test_unit(in_c2) then state.counter = out_c2 return end
			if in_c3 and test_unit(in_c3) then state.counter = out_c3 return end
			if in_c4 and test_unit(in_c4) then state.counter = out_c4 return end
			if in_c5 and test_unit(in_c5) then state.counter = out_c5 return end
		else
			local function test_id(id, in_c)
				local in_id = GetId(comp, state, in_c)
				if not in_id then return false end
				return in_id == id
			end
			unit = Get(comp, state, in_unit)
			local id = unit.id
			if not id then return end
			if unit then
				if in_c1 and test_id(id, in_c1) then state.counter = out_c1 return end
				if in_c2 and test_id(id, in_c2) then state.counter = out_c2 return end
				if in_c3 and test_id(id, in_c3) then state.counter = out_c3 return end
				if in_c4 and test_id(id, in_c4) then state.counter = out_c4 return end
				if in_c5 and test_id(id, in_c5) then state.counter = out_c5 return end
			end
		end
	end,
	exec_arg = { 1, "Default", "Did not match filter" },
	args = {
		{ 'in', "Input", "Unit or item to Filter", 'entity' },
		{ 'in', "Case 1", "Case 1", 'radar' },
		{ 'exec', "1", "Case 1" },
		{ 'in', "Case 2", "Case 2", 'radar', true },
		{ 'exec', "2", "Case 2", nil, true },
		{ 'in', "Case 3", "Case 3", 'radar', true },
		{ 'exec', "3", "Case 3", nil, true },
		{ 'in', "Case 4", "Case 4", 'radar', true },
		{ 'exec', "4", "Case 4", nil, true },
		{ 'in', "Case 5", "Case 5", 'radar', true },
		{ 'exec', "5", "Case 5", nil, true },
	},
	name = "Switch",
	desc = "Filters the passed unit or item",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Switches to different execution paths based on an input value.]],
}

data.instructions.dodrop =
{
	func = function(comp, state, cause, c, target, item, path_blocked)
		local reg, target_coord, target_entity, source_entity, moved = Get(comp, state, item), GetCoord(comp, state, target), GetEntity(comp, state, target), comp.owner
		moved = target_entity and (source_entity.docked_garage == target_entity or target_entity.docked_garage == source_entity)
		local can_transfer = moved or source_entity.has_crane or source_entity.has_movement
		if (not (can_transfer)) or (not target_coord and (not target_entity or not target_entity.exists or (target_entity.faction ~= source_entity.faction and not target_entity.lootable and not comp.faction:GetTrust(target_entity) == "ALLY"))) then
			return
		end

		local function transfer(item_id, limit)
			local have = source_entity:CountItem(item_id, true) -- count unreserved stacks
			if have == 0 then return end
			if not target_coord and (target_entity.is_construction or not target_entity:HaveFreeSpace(item_id)) and not target_entity:IsWaitingForOrder(item_id, true) then return end

			if not moved then
				local need_move, repeat_blocked = comp:RequestStateMove(target_coord or target_entity, math.max(comp.owner.crane_range, 1))
				if repeat_blocked then
					comp:SetStateSleep(1)
					state.counter = path_blocked
					return true
				elseif need_move then
					-- Not yet next to the target, wait for move to complete then repeat this instruction
					state.counter = state.lastcounter
					return true
				end
				moved = true
			end

			if target_coord then
				comp.owner:DropItem(item_id, limit or have, target_coord.x, target_coord.y)
			else
				if target_entity.is_construction then
					-- get reserved amount as limit
					local needed = 0
					for _,v in ipairs(target_entity.slots) do
						if v.id == item_id then needed = needed + v.reserved_space end
					end
					limit = limit and math.min(limit, needed) or needed
				end
				target_entity:TransferFrom(source_entity, item_id, limit or have, true)
			end
		end

		local reg_item_id = reg.item_id
		if reg_item_id then
			local num = reg.num
			if num and num > 0 then
				if c == 2 then
					if not target_coord then
						-- remove amount already in target
						num = num - target_entity:CountItem(reg_item_id)
					end
				end
				if num > 0 and transfer(reg_item_id, num) then return true end
			else
				if transfer(reg_item_id) then return true end
			end
		elseif reg.is_empty then -- transfer all
			for i,v in ipairs(source_entity.slots or {}) do
				if v.unreserved_stack > 0 and transfer(v.id) then return true end
			end
		end

		comp:SetStateSleep(1)
		return true
	end,
	make_asm = function(inst)
		return inst.c or 2
	end,
	node_ui = function(canvas, inst, program_ui, op, show_extra)
		--if not show_extra then return 0 end
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Specified Amount", "Up to Amount" }
		combo.value = inst.c or 2
		return 34
	end,
	args = {
		{ 'in', "Destination", "Unit or destination to bring items to", 'entity' },
		{ 'in', "Item / Amount", "Item and amount to drop off", "item_num", true },
		{ 'exec', "Path Blocked", "If path to destination was blocked" },
	},
	name = "Drop Off Items",
	desc = "Drop off items at a unit or location",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Drop Items.png",
	sample = "4W3bEIye3fwNjk3JECPg0y39MG3hY0aB1ec5xT1UMwde1Zo3HO0gAAgb12wbKZ1UOcsF0LrwGE49YVIh2SYWFg0glIqD2VsJgH1WSiu53zcym80tUIMz2mzZEP0ol6XE0k9G5N001DOZ3zge2Ep",
	explain = [[Drops off items to a unit or location on the ground.

An optional <hl>Item/Amount</> can be specified, or default to all items in inventory.

<bl>Up to Amount</> means it will only drop off up to that many items from its inventory
<bl>Specified Amount</> will attempt to transfer that many items when dropping off]],
}

data.instructions.dopickup =
{
	func = function(comp, state, cause, c, source, item, path_blocked)
		local reg, source_entity, target_entity, moved = Get(comp, state, item), GetEntity(comp, state, source), comp.owner
		moved = source_entity and (source_entity.docked_garage == target_entity or target_entity.docked_garage == source_entity)
		local can_transfer = moved or target_entity.has_crane or target_entity.has_movement
		if not source_entity or not source_entity.exists or (target_entity.faction ~= source_entity.faction and not source_entity.lootable) or (not (can_transfer)) then
			return
		end

		local function transfer(item_id, limit)
			local have = source_entity:CountItem(item_id, true) -- count unreserved stacks
			if have == 0 then return end
			if not target_entity:HaveFreeSpace(item_id) then return end

			if not moved then
				local need_move, repeat_blocked = comp:RequestStateMove(source_entity, comp.owner.crane_range)
				if repeat_blocked then
					comp:SetStateSleep(1)
					state.counter = path_blocked
					return true
				elseif need_move then
					-- Not yet next to the source, wait for move to complete then repeat this instruction
					state.counter = state.lastcounter
					return true
				end
				moved = true
			end

			target_entity:TransferFrom(source_entity, item_id, limit or have, true)
		end

		local reg_item_id = reg.item_id
		if reg_item_id then
			local num = reg.num
			if num and num > 0 then

				-- remove amount already in target
				if c == 2 then
					num = num - target_entity:CountItem(reg_item_id)
				end
				if num > 0 and transfer(reg_item_id, num) then return true end
			else
				if transfer(reg_item_id) then return true end
			end
		elseif reg.is_empty then -- transfer all
			for i,v in ipairs(source_entity.slots or {}) do
				if v.unreserved_stack > 0 and transfer(v.id) then return true end
			end
		end

		comp:SetStateSleep(1)
		return true
	end,
	make_asm = function(inst)
		return inst.c or 2
	end,
	node_ui = function(canvas, inst, program_ui, op, show_extra)
		--if not show_extra then return 0 end
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Specified Amount", "Up to Amount" }
		combo.value = inst.c or 2
		return 34
	end,
	args = {
		{ 'in', "Source", "Unit to take items from", 'entity' },
		{ 'in', "Item / Amount", "Item and amount to pick up", "item_num", true },
		{ 'exec', "Path Blocked", "If path to destination was blocked" },
	},
	name = "Pick Up Items",
	desc = "Picks up items from a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Pick Up Items.png",
	sample = "4W3bEIye3fwNjk3JECPg0y39MG3hY0aB1ec5xT1UMwde1Zo3HO0gAAgb12wbKZ1UOcsF0LrwGE49YVIh2SYWFg0glIqD2VsJgH1WSiu53zcym80tUIMz2mzZEP0ol6XE0k9G5N001DOZ3zge2Ep",
	explain = [[Picks up items from a unit.

If an <hl>Item/Amount</> is specified then it will only try to pick up that many.

<bl>Up to Amount</> means it will only pick up to that many items into its inventory
<bl>Specified Amount</> will attempt to transfer that many items when picking up]],
}

data.instructions.request_item =
{
	func = function(comp, state, cause, c, item, channel)
		local r = Get(comp, state, item)
		local r_item_id, r_num = r.item_id, r.num
		if not r_item_id then return end
		if c == 1 then
			local have_amount = comp.owner:CountItem(r_item_id)
			if r_num == REG_INFINITE or r_num == REG_NOT then r_num = 999999 end
			r_num = r_num + have_amount
			if r_num < 0 then r_num = 0 end
		elseif r_num <= 0 then
			return
		end
		channel = GetNum(comp, state, channel)
		comp:OrderItem(r_item_id, r_num, channel >= 1 and channel <= 4 and (1 << (channel-1)) or nil)
	end,
	make_asm = function(inst)
		return inst.c or 2
	end,
	node_ui = function(canvas, inst, program_ui, op, show_extra)
		--if not show_extra then return 0 end
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Specified Amount", "Up to Amount" }
		combo.value = inst.c or 2
		return 34
	end,
	args = {
		{ 'in', "Item", "Item and amount to order", 'item_num' },
		{ 'in', "Channel", "Optionally request on a specific logistics channel (1-4)", 'posnum', true },
	},
	name = "Request Item",
	desc = "Requests an item if it doesn't exist in the inventory",
	category = "Unit",
	sample = "V02rMa900Zlp221cKrw34kYhJ1meMtZ25rrbw07Fz2w24kaMu28DbjZ1rBxEt23ezW900A",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Requests a specific amount of a specific item from the logistics system. The request remains valid as long as the behavior is active.

Infinite requests will request into all available slots but do not continue to request once items are taken out unless the instruction called again]],
}

data.instructions.order_to_shared_storage =
{
	func = function(comp, state, cause)
		comp.owner:IssueDumpingOrders()
	end,
	name = "Order to Shared Storage",
	desc = "Request Inventory to be sent to nearest shared storage with corresponding locked item slots",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Create orders to send the inventory of this unit to shared storage. Will only work if free space is available in locked item slots on an external unit equipped with a Shared Storage component.]],
}

data.instructions.request_wait =
{
	func = function(comp, state, cause, c, item, channel)
		local r = Get(comp, state, item)
		local r_item_id, r_num = r.item_id, r.num
		if not r_item_id then return end

		local have_amount = comp.owner:CountItem(r_item_id)
		if c == 1 then -- wait for specified amount
			local blocks = state.blocks
			local block = blocks and blocks[#blocks]
			local start_have_amount = block and block[2] == state.lastcounter and block[3]
			r_num = r_num + (start_have_amount or have_amount)
			if not start_have_amount then -- first time, no block yet
				if r_num <= have_amount then return end -- can't wait for 0, negative or infinite
				BeginBlock(comp, state, have_amount) -- remember have_amount at start of wait
			elseif r_num <= have_amount then -- continuing wait
				blocks[#blocks] = nil -- end loop
				return -- have the requested amount
			end
		elseif have_amount >= r_num then -- wait up to amount
			return -- have the requested amount
		end
		channel = GetNum(comp, state, channel)
		comp:OrderItem(r_item_id, (r_num == REG_INFINITE and 999999) or (r_num > 0 and r_num) or 0, channel >= 1 and channel <= 4 and (1 << (channel-1)) or nil)
		state.counter = state.lastcounter
		comp:SetStateSleep(1)
		return true
	end,
	make_asm = function(inst)
		return inst.c or 2
	end,
	node_ui = function(canvas, inst, program_ui, op, show_extra)
		--if not show_extra then return 0 end
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Specified Amount", "Up to Amount" }
		combo.value = inst.c or 2
		return 34
	end,
	args = {
		{ 'in', "Item", "Item and amount to order", 'item_num' },
		{ 'in', "Channel", "Optionally request on a specific logistics channel (1-4)", 'posnum', true },
	},
	name = "Request Wait",
	desc = "Requests up to a specified amount of an item and waits until that amount exists in inventory",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Waits until a previously requested item or event has completed.]],
}

data.instructions.get_active_order =
{
	func = function(comp, state, cause, source, target, amount)
		local order = comp.owner.active_order

		if order then
			Set(comp, state, source, { entity = order.source_entity})
			Set(comp, state, target, { entity = order.target_entity})
			Set(comp, state, amount, { id = order.item_id, num = order.amount})
		else
			Set(comp, state, source, nil)
			Set(comp, state, target, nil)
			Set(comp, state, amount, nil)
		end
	end,
	args = {
		{ 'out', "Source" },
		{ 'out', "Target" },
		{ 'out', "Amount" },
	},
	name = "Get Active Order",
	desc = "Gets the source, target, and amount data from the current active order",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Returns the current order or task assigned to the unit.]],
}

data.instructions.get_resource_num =
{
	func = function(comp, state, cause, entity, result)
		local r = GetEntity(comp, state, entity)
		if IsResource(r) then
			Set(comp, state, result, { id = GetResourceHarvestItemId(r), num = GetResourceHarvestItemAmount(r) } )
		else
			Set(comp, state, result, nil)
		end
	end,
	args = {
		{ 'in', "Resource", "Resource Node to check", 'entity' },
		{ 'out', "Result" },
	},
	name = "Get Resource Num",
	desc = "Gets the amount of resource",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
	explain = [[Returns the quantity of resource remaining in a resource deposit.]],
}

data.instructions.get_inventory_item =
{
	func = function(comp, state, cause, item, exec_none)
		local slot_length = comp.owner.slot_count
		-- Beacon?
		if slot_length == 0 then
			Set(comp, state, item, nil)
			state.counter = exec_none
			return
		end

		for i,v in ipairs(comp.owner.slots) do
			if v.id and v.stack > 0 then
				Set(comp, state, item, { item = v.id, num = v.stack })
				return
			end
		end
		state.counter = exec_none
		Set(comp, state, item, nil)
	end,
	args = {
		{ 'out', "Item" },
		{ 'exec', "No Items", "No items in inventory" },
	},
	name = "First Item",
	desc = "Reads the first item in the inventory of the unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Retrieves a reference to the first item from the unit's inventory. Diverts logic if no items are found.]],
}

data.instructions.get_inventory_item_index =
{
	func = function(comp, state, cause, num, item, exec_none)
		local slot_length = comp.owner.slot_count
		-- Beacon?
		if slot_length == 0 then
			Set(comp, state, item, nil)
			state.counter = exec_none
			return
		end

		local index = GetNum(comp, state, num)

		if index > 0 and index <= slot_length then
			local slot = comp.owner:GetSlot(index)
			if slot then
				local e = slot.entity or slot.reserved_entity
				local i = not e and slot.id
				if e or i then
					Set(comp, state, item, { entity = slot.entity or slot.reserved_entity, item = i, num = slot.unreserved_stack } )
					return
				end
				--[[
				if slot.stack > 0 then
					Set(comp, state, item, { item = slot.id, num = slot.stack })
					return
				elseif slot.locked or slot.reserved_space > 0 then
					Set(comp, state, item, { item = slot.id, num = slot.stack })
					state.counter = exec_none
					return
				end
				--]]
			end
		end

		state.counter = exec_none
		Set(comp, state, item, nil)
	end,
	args = {
		{ 'in', "Index", "Slot index", 'posnum' },
		{ 'out', "Item" },
		{ 'exec', "No Item", "Item not found" },
	},
	name = "Get Inventory Item",
	desc = "Reads the item contained in the specified slot index",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Returns the index of a specific item from the inventory.]],
}

data.instructions.sequence =
{
	func = function(comp, state, cause, exec_first, exec_second, exec_third, exec_fourth, exec_last)
		local steps = { 1 }
		if exec_first then steps[#steps+1] = exec_first end
		if exec_second then steps[#steps+1] = exec_second end
		if exec_third then steps[#steps+1] = exec_third end
		if exec_fourth then steps[#steps+1] = exec_fourth end
		return BeginBlock(comp, state, steps)
	end,

	next = function(comp, state, it, exec_first, exec_second, exec_third, exec_fourth, exec_last)
		local i = it[1]
		if i > #it then return true end
		state.counter = it[i+1]
		it[1] = i + 1
	end,

	last = function(comp, state, it, exec_first, exec_second, exec_third, exec_fourth, exec_last)
		state.counter = exec_last
	end,
	exec_arg = false,
	args = {
		{ 'exec', "First", "First" },
		{ 'exec', "Second", "Second", nil, true },
		{ 'exec', "Third", "Third", nil, true },
		{ 'exec', "Fourth", "Fourth", nil, true },
		{ 'exec', "Last", "Last" },
	},
	name = "Sequence",
	desc = "Executes a series of exec nodes in sequence",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	--sample = "4w3YxVw83N5hsf2N72v21wlqdV1w59mf2iQlyI3b6kSN2qNbeT2ucU4M2du9081bSutT2MBBeE2xTuTJ1urOph1tHKMr0LRWRM0avnxQ3jO9Ys38Uk5H1z4OKy1wmQOj1i1HdI0DAn5Y2bW0Av0gyF8N1lgBc51H40X518RUgK0s33RY2IR",
	--explain = [[]],
}

data.instructions.for_component =
{
	func = function(comp, state, cause, out_val, out_index, exec_done)
		return BeginBlock(comp, state, { 1 })
	end,

	next = function(comp, state, it, out_val, out_index, exec_done)
		local i, first_non_hiden, entity, c = it[1], it[2] or 999, comp.owner

		while i < first_non_hiden do
			c = entity:GetHiddenComponent(i)
			if not c then it[2], first_non_hiden = i, i break end
			i = i + 1
			local comp_def = c.def
			if comp_def.get_ui then break end
		end

		while not c do
			i = i + 1
			local socket = i - first_non_hiden
			if socket > entity.socket_count then return true end
			c = entity:GetComponent(socket)
		end

		it[1] = i
		Set(comp, state, out_val, { id = c.id } )

		if out_index then
			local index = it[3] or 1
			it[3] = index + 1
			Set(comp, state, out_index, { id = c.id, num = index } )
		end
	end,

	last = function(comp, state, it, val, out_index, exec_done)
		state.counter = exec_done
	end,

	args = {
		{ 'out', "Component", "Equipped component" },
		{ 'out', "Index", "Returns the index of the result", 'num', true },
		{ 'exec', "Done", "Finished loop" },
	},
	name = "Loop Equipped Components",
	desc = "Loops through equipped Components",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	sample = "4w3YxVw83N5hsf2N72v21wlqdV1w59mf2iQlyI3b6kSN2qNbeT2ucU4M2du9081bSutT2MBBeE2xTuTJ1urOph1tHKMr0LRWRM0avnxQ3jO9Ys38Uk5H1z4OKy1wmQOj1i1HdI0DAn5Y2bW0Av0gyF8N1lgBc51H40X518RUgK0s33RY2IR",
	explain = [[Loops over all components equipped on the current unit including hidden components.

Loop instructions do not need the execution line to be connected back to the start and will automatically continue the loop when it reaches the end of an execution path.]],
}

data.instructions.has_like_component =
{
	func = function(comp, state, cause, in_comp, in_unit, exec_fail)
		local basecomp = GetId(comp, state, in_comp)
		local entity = GetFactionEntityOrSelf(comp, state, in_unit)
		if not basecomp or not entity then
			state.counter = exec_fail
			return
		end
		local basedef = data.components[basecomp]
		local baseid = (basedef and basedef.base_id) or basecomp
		local findcomp = entity:FindComponent(baseid, true)
		if not findcomp then state.counter = exec_fail end
	end,
	args = {
		{ 'in', "Component", "Component" },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
		{ 'exec', "Failed", "Failed" },
	},
	name = "Has Like Component",
	desc = "Checks Unit for a component type",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Checks if the Unit has a component that is like the one passed]],
}
data.instructions.for_inventory_item =
{
	func = function(comp, state, cause, val, exec_done, r_stack, ur_stack, r_space, ur_space, out_index, in_unit)
		local ent = GetSeenEntityOrSelf(comp, state, in_unit)
		if not ent then return end
		local can_see_faction = ent.faction == comp.faction or comp.faction:GetTrust(ent, "ALLY")
		if not can_see_faction then return end
		local slot_length = ent.slot_count
		-- Beacon?
		if slot_length == 0 then
			Set(comp, state, val, nil)
			state.counter = exec_done
			return
		end

		return BeginBlock(comp, state, { 1, ent, slot_length })
	end,

	next = function(comp, state, it, val, exec_done, r_stack, ur_stack, r_space, ur_space, out_index, in_unit)
		--local from, to = it[1], it[2]
		local i = it[1]
		local ent = it[2]

		if type(ent) ~= "userdata" or not ent.exists then return true end

		local slot = ent:GetSlot(i)
		if not slot then
			Set(comp, state, r_stack)
			Set(comp, state, ur_stack)
			Set(comp, state, r_space)
			Set(comp, state, ur_space)
			Set(comp, state, out_index)
			return true
		end

		Set(comp, state, val, { entity = slot.entity or slot.reserved_entity, item = slot.id, num = slot.unreserved_stack } )

		Set(comp, state, r_stack, { item = slot.id, num = slot.reserved_stack } )
		Set(comp, state, ur_stack, { item = slot.id, num = slot.unreserved_stack } )
		Set(comp, state, r_space, { item = slot.id, num = slot.reserved_space } )
		Set(comp, state, ur_space, { item = slot.id, num = slot.unreserved_space } )
		Set(comp, state, out_index, { num = i })

		i = i + 1
		it[1] = i
	end,

	last = function(comp, state, it, val, exec_done, r_stack, ur_stack, r_space, ur_space, out_index, in_unit)
		state.counter = exec_done
	end,

	args = {
		{ 'out', "Inventory", "Item Inventory" },
		{ 'exec', "Done", "Finished loop" },
		{ 'out', "Reserved Stack", "Items reserved for outgoing order or recipe", 'num', true },
		{ 'out', "Unreserved Stack", "Items available", 'num', true },
		{ 'out', "Reserved Space", "Space reserved for an incoming order", 'num', true },
		{ 'out', "Unreserved Space", "Remaining space", 'num', true },
		{ 'out', "Index", "Slot Index", 'num', true },
		{ 'in', "Unit", "Unit", 'entity', true },
	},
	name = "Loop Inventory Slots",
	desc = "Loops through Inventory",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Loops through each item currently stored in a unit's inventory.]],
}

data.instructions.for_research_ingredients =
{
	func = function(comp, state, cause, product, out_ingredient, exec_done)
		local item_id = GetId(comp, state, product)
		local product_def = item_id and data.all[item_id]

		if not product_def then
			Set(comp, state, out_ingredient)
			return
		end

		local production_recipe = product_def.uplink_recipe

		if production_recipe and production_recipe.ingredients then
			local ingredients = production_recipe.ingredients
			local it = { 2 }
			for item,n in SortedPairs(ingredients) do
				it[#it + 1] = { id = item, num = n }
			end

			return BeginBlock(comp, state, it)
		end
	end,

	next = function(comp, state, it, product, out_ingredient, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_ingredient, { id = it[i].id, num = it[i].num,  })
		it[1] = i + 1
	end,

	last = function(comp, state, it, product, out_ingredient, exec_done)
		-- this would clear the variable on loop end or break
		-- leave it valid for now as its useful for breaks
		--Set(comp, state, out_ingredient, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "Research", nil, 'tech' },
		{ 'out', "Ingredient", "Research Ingredient" },
		{ 'exec', "Done", "Finished loop" },
	},
	name = "Loop Research Ingredients",
	desc = "Loops through Ingredients",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Loops through the required ingredients for a research technology.]],
}

data.instructions.for_recipe_ingredients =
{
	func = function(comp, state, cause, product, out_ingredient, exec_done)
		local item_id = GetId(comp, state, product)
		local product_def, ingredients = item_id and data.all[item_id]
		local ent = not product_def and GetEntity(comp, state, product)

		if product_def then
			local production_recipe = product_def and (product_def.production_recipe or product_def.construction_recipe)
			ingredients = production_recipe and production_recipe.ingredients

			-- is Research (uplink_recipe)
			if not ingredients then
				production_recipe = product_def.uplink_recipe
				ingredients = production_recipe and production_recipe.ingredients

				if (ingredients) then
					local is_unlocked = comp.faction:IsUnlocked(item_id)
					local progress = comp.faction.extra_data.research_progress and comp.faction.extra_data.research_progress[item_id] or 0
					local remain = (product_def.progress_count and product_def.progress_count or progress) - progress

					if not is_unlocked and remain > 0 and ingredients then
						local it = { 2 }
						if ingredients then
							-- return the remainder of the research, not just one stack
							for item,n in SortedPairs(ingredients) do
								it[#it + 1] = { id = item, num = n*remain }
							end

							return BeginBlock(comp, state, it)
						end
					else
						--Set(comp, state, out_ingredient)
						state.counter = exec_done
						return
					end
				end
			else
				-- if not research and unlocked send the product
				if not comp.faction:IsUnlocked(item_id) then
					Set(comp, state, out_ingredient)
					state.counter = exec_done
					return
				end
			end
		elseif ent then
			if ent.def.id == "f_construction" then
				local fd, bd = GetProduction(ent:GetRegisterId(FRAMEREG_GOTO), ent)
				ingredients = fd and GetIngredients((fd.construction_recipe or fd.production_recipe), bd)
			else
				item_id = ent.def.id

				if not comp.faction:IsUnlocked(item_id) then
					Set(comp, state, out_ingredient)
					state.counter = exec_done
					return
				end

				-- from the entity get whether it's a bot or a building from the def.id
				product_def = data.all[item_id]
				local production_recipe = product_def and (product_def.production_recipe or product_def.construction_recipe)
				ingredients = production_recipe and production_recipe.ingredients
			end
		end

		local it = { 2 }
		if ingredients then
			for item,n in SortedPairs(ingredients) do
				it[#it + 1] = { id = item, num = n }
			end
			return BeginBlock(comp, state, it)
		else
			Set(comp, state, out_ingredient)
			state.counter = exec_done
			return
		end
	end,

	next = function(comp, state, it, product, out_ingredient, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_ingredient, { id = it[i].id, num = it[i].num,  })
		it[1] = i + 1
	end,

	last = function(comp, state, it, product, out_ingredient, exec_done)
		-- this would clear the variable on loop end or break
		-- leave it valid for now as its useful for breaks
		--Set(comp, state, out_ingredient, nil)
		state.counter = exec_done
	end,
	args = {
		{ 'in', "Recipe", nil, "item" },
		{ 'out', "Ingredient", "Recipe Ingredient" },
		{ 'exec', "Done", "Finished loop" },
	},
	name = "Loop Recipe Ingredients",
	desc = "Loops through Ingredients",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Loops through each ingredient required for a given recipe.]],
}

data.instructions.get_inventory_total =
{
	func = function(comp, state, cause, res, in_unit)
		local ent = GetFactionEntityOrSelf(comp, state, in_unit)

		-- if nil see if it's an ally
		if not ent then
			local ent_check = GetEntity(comp, state, in_unit)

			if ent_check and comp.faction:IsSeen(ent_check) and ent_check.faction:GetTrust(comp.faction) == "ALLY" then
				ent = ent_check
			else
				-- Return and don't get total from self if "in_unit" failed
				Set(comp, state, res)
				return
			end
		end

		local total = 0

		if ent then
			for i,v in ipairs(ent.slots) do
				if v.id then
					total = total + v.stack
				end
			end
		end

		Set(comp, state, res, { num = total })
	end,
	args = {
		{ 'out', "Result" },
		{ 'in', "Unit", "The unit to check for (if not self)", 'entity', true },
	},
	name = "Inventory Total",
	desc = "Returns the total contained in inventory",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Returns the total number of a specific item from the inventory.]],
}

data.instructions.get_distance =
{
	func = function(comp, state, cause, target, output, source)

		local entity_t, coord_t, coord_s, reg_t
		local reg_s = Get(comp, state, source)
		local entity_s = reg_s.entity
		if reg_s.is_empty then entity_s = comp.owner end -- if optional param is empty, get self

		-- cant see source entity
		if entity_s and not comp.faction:IsSeen(entity_s) then goto failed_distance end

		reg_t = Get(comp, state, target)
		if reg_t.is_empty then goto failed_distance end -- no target

		entity_t = reg_t.entity

		-- cant see target entity
		if entity_t and not comp.faction:IsSeen(entity_t) then goto failed_distance end

		coord_t = reg_t.coord

		if not entity_t and not coord_t then goto failed_distance end -- target not an entity or a coord

		-- distance from source entity to target entity/coord
		if entity_s then
			Set(comp, state, output, { entity = entity_s, num = entity_s:GetRangeTo(entity_t or coord_t) })
			return
		end

		coord_s = reg_s.coord
		if not coord_s then goto failed_distance end -- source is not an entity or coord

		-- if the target is an entity
		if entity_t then
			Set(comp, state, output, { entity = entity_t, num = entity_t:GetRangeTo(coord_s) })
			return
		end

		-- if both are coordintes
		if coord_t and coord_s then
			local distX = math.abs(coord_s.x - coord_t.x)
			local distY = math.abs(coord_s.y - coord_t.y)
			local diagonal = math.floor(math.sqrt((distX * distX) + (distY * distY)))

			Set(comp, state, output, { num = diagonal })
			return
		end


		::failed_distance::
		Set(comp, state, output, { num = REG_INFINITE })
	end,
	args = {
		{ 'in', "Target", "Target unit", 'entity' },
		{ 'out', "Distance", "Unit and its distance in the numerical part of the value" },
		{ 'in', "Unit", "The unit to measure from (if not self)", 'entity', true },
	},
	name = "Distance",
	desc = "Returns distance to a unit",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Closest Enemy.png",
	explain = [[Calculates the distance between the current unit and a target coordinate or unit.]],
}

data.instructions.order_transfer =
{
	func = function(comp, state, cause, target_entity, item)
		-- get current ordered amount?
		target_entity = GetEntity(comp, state, target_entity)
		item = Get(comp, state, item)
		local item_id, amount = item.item_id, item.num
		if not target_entity or not item_id then return end
		--print("making order from " .. comp.owner.def.name .. " to " .. target_entity.def.name)
		if (target_entity.is_docked and target_entity.docked_garage == comp.owner) or
			(comp.owner.is_docked and comp.owner.docked_garage == target_entity) then
			target_entity:TransferFrom(comp.owner, item_id, amount, false, false)
		else
			comp.faction:OrderTransfer(comp.owner, target_entity, item_id, amount > 0 and amount, true)
		end
	end,
	args = {
		{ 'in', "Target", "Target unit", 'entity' },
		{ 'in', "Item", "Item and amount to transfer", 'item_num' },
	},
	name = "Order Transfer To",
	desc = "Transfers an Item to another Unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Transfer items or resources between the inventories of units.]],
}

data.instructions.is_logistics =
{
	func = function(comp, state, cause, in_unit, exec_outside)
		local ent1 = GetEntity(comp, state, in_unit)
		local power_grid_index = ent1 and ent1.power_grid_index
		if power_grid_index and ent1.faction == comp.faction then return end
		local coord = GetCoord(comp, state, in_unit)
		if coord then if comp.faction:GetPowerGridIndexAt( coord ) then return end end
		state.counter = exec_outside
	end,
	exec_arg = { 1, "Inside", "Where to continue if unit or coordinate is in a logistics network" },
	args = {
		{ 'in', "Unit", "Unit or Coordinate", 'entity' },
		{ 'exec', "Outside", "If not inside a logistics network" },
	},
	name = "Is Inside Logistics Network",
	desc = "Checks if a unit or coordinates is in the logistics network",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
	explain = [[Diverts logic depending on whether a unit or coordinate is inside a logistics network.]],
}

data.instructions.is_same_grid =
{
	func = function(comp, state, cause, in_unit1, in_unit2, exec_diff)
		local ent1, ent2 = GetEntity(comp, state, in_unit1), GetEntity(comp, state, in_unit2)
		local e1gi = ent1 and ent1.power_grid_index
		local e2gi = ent2 and ent2.power_grid_index
		if e1gi and e2gi and ent1.faction == comp.faction and ent1.faction == ent2.faction and e1gi == e2gi then return end
		local coord1 = GetCoord(comp, state, in_unit1)
		if e2gi and ent2.faction == comp.faction and not e1gi and coord1 then if comp.faction:GetPowerGridIndexAt( {coord1.x, coord1.y} ) == e2gi then return end end
		local coord2 = GetCoord(comp, state, in_unit2)
		if e1gi and ent1.faction == comp.faction and not e2gi and coord2 then if comp.faction:GetPowerGridIndexAt( {coord2.x, coord2.y} ) == e1gi then return end end
		if coord1 and coord2 then if comp.faction:GetPowerGridIndexAt( {coord1.x, coord1.y} ) == comp.faction:GetPowerGridIndexAt( {coord2.x, coord2.y} ) then return end end
		state.counter = exec_diff
	end,
	exec_arg = { 1, "Same Grid", "Where to continue if both units or coordinates are in the same logistics network" },
	args = {
		{ 'in', "Unit", "First Unit or Coordinate", 'entity' },
		{ 'in', "Unit", "Second Unit or Coordinate", 'entity' },
		{ 'exec', "Different", "Different logistics networks" },
	},
	name = "Is Same Grid",
	desc = "Checks if two units or coordinates are in the same logistics network",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
	explain = [[Returns true if the two entities are on the same logistics network.]],
}
data.instructions.is_moving =
{
	func = function(comp, state, cause, not_moving, path_blocked, no_result, in_unit)
		local entity = GetSeenEntityOrSelf(comp, state, in_unit)
		if not entity then
			state.counter = no_result
			return
		end
		if entity.state_path_blocked then state.counter = path_blocked return end
		if not entity.is_moving then state.counter = not_moving return end
	end,
	exec_arg = { 1, "Moving", "Where to continue if unit is moving" },
	args = {
		{ 'exec', "Not Moving", "Where to continue if unit is not moving" },
		{ 'exec', "Path Blocked", "Where to continue if unit is path blocked" },
		{ 'exec', "No Result", "Where to continue if unit is out of visual range" },
		{ 'in', "Unit", "The unit to check (if not self)", 'entity', true },
	},
	name = "Is Moving",
	desc = "Checks the movement state of a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Checks the movement status of a unit and diverts logic according to the result.]],
}

data.instructions.is_passable =
{
	func = function(comp, state, cause, in_coord, impassable, passable)
		local loc = GetCoord(comp, state, in_coord)
		if loc then
			local a, b = Map.CountTiles(loc, 0, true)
			if comp.faction:IsVisible(loc) then
				if a > 0 or b > 0 then state.counter = impassable else state.counter = passable end
			elseif comp.faction:IsDiscovered(loc) then
				if a > 0 then
					state.counter = impassable
				else
					local e = Map.GetEntityAt(loc.x, loc.y)
					if e and comp.faction:IsSeen(e) then
						state.counter = impassable
					else
						state.counter = passable
					end
				end
			end
		end
	end,
	args = {
		{ "in", "Coordinate", "The location in a discovered tile to check", "coord" },
		{ "exec", "Impassable", "Unit is unable to pass through this coordinate"},
		{ "exec", "Passable", "Unit is able to pass through this coordinate" }
	},
	name = "Is Passable",
	desc = "Checks whether a location is passable",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Returns whether a location is passable by units and diverts logic according to the result.]],
}

data.instructions.is_fixed =
{
	func = function(comp, state, cause, in_index, is_fixed)
		local owner = comp.owner
		local slot_length = owner.slot_count
		-- Beacon?
		if slot_length == 0 then
			return
		end
		local slots = owner.slots

		if slots then
			local index = GetNum(comp, state, in_index)

			if index > 0 and index <= slot_length  then
				local slot = owner.slots[index]
				if slot and slot.locked == true then
					state.counter = is_fixed
					return
				end
			end
		end
	end,
	args = {
		{ 'in', "Slot index", "Individual slot to check", 'posnum', },
		{ 'exec', "Is Locked", "Where to continue if inventory slot is locked" },
	},
	name = "Is Item Slot Locked",
	desc = "Check if a specific item slot is locked",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
	explain = [[Checks if an item slot of the inventory is locked and diverts logic depending on the result.]],
}

data.instructions.is_equipped =
{
	func = function(comp, state, cause, in_id, is_equipped, out_num)
		local component_id = GetId(comp, state, in_id)

		local owner = comp.owner
		local found = 0

		for _,v in ipairs(owner.components) do
			if v.id == component_id then
				found = found + 1
			end
		end

		Set(comp, state, out_num, { num = found })

		if found > 0 then state.counter = is_equipped end
	end,
	args = {
		{ 'in', "Component", "Component to check", "comp" },
		{ 'exec', "Component Equipped", "Where to continue if component is equipped" },
		{ 'out', "Result", "Returns how many instances of a component equipped on this Unit", nil, true },
	},
	name = "Is Equipped",
	desc = "Check if a specific component has been equipped",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
	explain = [[Checks if a specific component is currently equipped on a unit and returns how many were found. Diverts logic depending on the result.]],
}

data.instructions.shutdown =
{
	func = function(comp, state, cause)
		comp.owner.powered_down = true
	end,
	name = "Turn Off",
	desc = "Shuts down the power of the Unit",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
	explain = [[Turns <hl>OFF</> the power of the unit.]],
}

data.instructions.turnon =
{
	func = function(comp, state, cause)
		comp.owner.powered_down = false
	end,
	name = "Turn On",
	desc = "Turns on the power of the Unit",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
	explain = [[Turns <hl>ON</> the power of the unit.]],
}

data.instructions.connect =
{
	func = function(comp, state, cause)
		comp.owner.disconnected = false
	end,
	name = "Connect",
	desc = "Connects the Unit to the Logistics Network",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Carry.png",
	explain = [[Does nothing if already connected.

Note: This instruction cannot be used to perform the action on an external unit.]],
}

data.instructions.disconnect =
{
	func = function(comp, state, cause)
		comp.owner.disconnected = true
	end,
	name = "Disconnect",
	desc = "Disconnects the Unit from the Logistics Network",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Carry.png",
	explain = [[Does nothing if already disconnected.

Note: This instruction cannot be used to perform the action on an external unit.]],
}

data.instructions.enable_transport_route =
{
	func = function(comp, state, cause)
		if not IsBuilding(comp.owner) then
			comp.owner.logistics_transport_route = true
		end
	end,
	name = "Enable Transport Route",
	desc = "Enable Unit to deliver on transport route",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Carry.png",
	explain = [[Does nothing if already enabled.

Note: This instruction cannot be used to perform the action on an external unit.]],
}

data.instructions.disable_transport_route =
{
	func = function(comp, state, cause)
		if not IsBuilding(comp.owner) then
			comp.owner.logistics_transport_route = false
		end
	end,
	name = "Disable Transport Route",
	desc = "Disable Unit to deliver on transport route",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Carry.png",
	explain = [[Does nothing if already disabled.

Note: This instruction cannot be used to perform the action on an external unit.]],
}

data.instructions.set_logistics_options =
{
	func = function(comp, state, cause)
		local src_node = GetSourceNode(state)
		local c, c2 = src_node.c or {}, src_node.c2
		for k, v in pairs(c) do
			comp.owner["logistics_" .. k] = c2[k] == true
		end
	end,
	name = "Set Logistics",
	desc = "Sets current unit to the specified logistics settings",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Network.png",
	node_ui = function(canvas, inst, program_ui)
		local vertlist = canvas:Add("<VerticalList x=10 y=50/>")
		local function check(btn, on) btn.on, btn.icon = on, (on == true and "icon_small_confirm") or (on == 2 and "icon_small_durability") or nil end

		vertlist:Add("<Button text='Settings' on_change={on_click}/>", {
			on_click = function(btn)
				UI.MenuPopup([[
					<Box bg=popup_box_bg padding=4 blur=true>
						<VerticalList child_padding=4>
							<Box bg=popup_pattern padding=4>
								<Text text="Logistics Settings" style=hl textalign=center/>
							</Box>
							<Box bg=popup_additional_bg padding=8 id=transportbox>
								<VerticalList child_padding=4 id=list2/>
							</Box>
							<Box bg=popup_additional_bg padding=8>
								<VerticalList child_padding=4>
									<HorizontalList child_padding=8><Text fill=true text="Connect to Logistics Network" hidden=true on_click={connect}/><Button width=24 height=24 id=togglebtn hidden=true on_click={connect}/></HorizontalList>
									<Box margin=4 padding=6 id=logisticsbox>
										<VerticalList child_padding=4 id=list/>
									</Box>
								</VerticalList>
							</Box>
						</VerticalList>
					</Box>]], {
					construct = function(menu)
						menu:TweenFromTo("sy", 0, 1, 100)
						local list, list2, btns = menu.list, menu.list2, {}
						menu.btns = btns

						for _,v in ipairs(data.logistics_flags) do
							local flag = v.flag
							if flag then
								local hl = (flag == "transport_route" and list2 or list):Add("<HorizontalList child_padding=8><Text fill=true on_click={toggle}/><Button width=24 height=24 id=togglebtn on_click={toggle}/></HorizontalList>")
								hl.flag, hl.tooltip, hl[1].text = flag, v.tooltip, v.label
								btns[flag] =  hl[2]
							else
								list:Add("Spacer", { height= 10 })
							end
						end

						list:Add('<Button text="Reset Settings" on_click={reset}/>')
					end,
					connect = function(menu, btn)
						inst.c = inst.c or {}
						inst.c.disconnected = not btn.on
					end,
					toggle = function(menu, hl, btn)
						inst.c = inst.c or {}
						local newval, flag = not btn.on, hl.flag
						inst.c[flag] = newval
						check(btn, newval)
						program_ui:set_dirty(true)
						program_ui:Refresh()
					end,
					update = function(menu)
						inst.c = inst.c or {}
						local val = true -- not inst.c.disconnected

						menu.togglebtn.active = val == true
						menu.logisticsbox.opacity = val and 1 or 0.5

						for flag,b in pairs(menu.btns) do
							check(b, inst.c[flag])
							--b.active = inst.c[flag] == true-- and flag == "transport_route"
						end
					end,
				}, canvas, "UP")
			end
		})

		local yheight = 34
		inst.c = inst.c or {}
		inst.c2 = inst.c2 or {}
		for _,v in ipairs(data.logistics_flags) do
			local flag = v.flag
			local show = inst.c[flag]
			if show then
				vertlist:Add("Spacer", { height= 10 })
				local hl = vertlist:Add("<HorizontalList child_padding=8><Text fill=true on_click={toggle}/><Button width=24 height=24 id=togglebtn on_click={toggle}/></HorizontalList>")
				hl.flag, hl.tooltip, hl[1].text = flag, v.tooltip, v.label
				check(hl.togglebtn, inst.c2[flag])
				hl.toggle = function(h2, btn)
					inst.c2 = inst.c2 or {}
					local newval, f = not btn.on, h2.flag
					inst.c2[f] = newval
					check(btn, newval)
					program_ui:set_dirty(true)
					program_ui:Refresh()
				end
				yheight = yheight + 34
			end
		end

		return yheight
	end,
	sample = "2i3flt3g43MHy42CkT121UP6Yj0JlyqH3blvYp12jvHB3Z8O1I3cRcuK13mqwz3cMEYr3cZLWf0g2H8j3cDS2L0RImB10trpdK1nVgZI1MR7684Gjv",
	explain = [[Allows full customization of any of the unit's Logistic Settings in a single instruction.

Click the <hl>Settings</> button to add specific variables to edit.]],
}

data.instructions.sort_storage =
{
	func = function(comp, state, cause)
		EntityAction.SortInventory(comp.owner, { slot_type = "storage" })
	end,
	name = "Sort Storage",
	desc = "Sorts Storage Containers on Unit",
	category = "Unit",
	icon = "Main/skin/Icons/Common/32x32/Sort.png",
	explain = [[Sorts items in the storage into an efficient order and combines stacks together.]],
}

data.instructions.solve =
{
	func = function(comp, state, cause, target, missing, exec_failed)
		local reg = Get(comp, state, target)
		local target_entity = reg and (reg.entity or reg.coord)
		if not target_entity or not IsExplorable(target_entity) or target_entity.extra_data.solved then
			Set(comp, state, missing, nil)
			return
		end
		local owner = comp.owner

		local has_scannable = target_entity:FindComponent("c_explorable_scannable")
		if has_scannable and not has_scannable.extra_data.ok then
			local scanner = owner:FindComponent("c_small_scanner")
			if not scanner or not owner.has_power then
				state.counter = exec_failed
				Set(comp, state, missing, { id = scanner and "v_unpowered" or "c_small_scanner", num = 1 })
				comp:SetStateSleep(1)
				return true
			end

			scanner:SetRegisterEntity(1, target_entity)
			state.counter = state.lastcounter
			Set(comp, state, missing, nil)
			comp:WaitForOtherCompFinish(scanner)
			return true
		end

		local solve_puzzle_comp, slot_with_fix_item, override_item
		for _,puzzle_comp in ipairs(target_entity.components or {}) do
			local puzzle_comp_def = puzzle_comp.def
			local puzzle_comp_extra_data = puzzle_comp_def.type == "Puzzle" and puzzle_comp.extra_data
			if puzzle_comp_extra_data and not puzzle_comp_extra_data.ok then
				-- check item fixables
				override_item = puzzle_comp_extra_data.explorable_override or puzzle_comp_def.explorable_override
				local fix_item = puzzle_comp_extra_data.explorable_fix or puzzle_comp_def.explorable_fix
				if fix_item or override_item then
					slot_with_fix_item = owner:FindSlot(fix_item or override_item, 1)
					if slot_with_fix_item then
						solve_puzzle_comp = puzzle_comp
						break
					end
					if fix_item or override_item then
						Set(comp, state, missing, { id = fix_item or override_item, num = 1 })
						state.counter = exec_failed
						comp:SetStateSleep(1)
						return true
					end
				elseif puzzle_comp.id == "c_explorable_autosolve" then
					solve_puzzle_comp = puzzle_comp
					break
				elseif puzzle_comp.id == "c_alien_lock" then
					if owner:FindComponent("c_alien_key") then
						solve_puzzle_comp = puzzle_comp
						break
					end
				end

				-- remaining puzzles should just need to wait until theyre done
				local id = puzzle_comp.id
				Set(comp, state, missing, { id = id, num = 1 })
				state.counter = exec_failed
				comp:SetStateSleep(1)
				return true
			end
		end

		-- if it got here without being solved and theres an override item then set missing to that
		if not solve_puzzle_comp then
			if override_item then
				Set(comp, state, missing, { id = override_item, num = 1 })
				state.counter = exec_failed
				comp:SetStateSleep(1)
				return true
			end
		end

		-- Mark puzzle or explorable as solved then repeat this instruction
		state.counter = state.lastcounter
		Set(comp, state, missing, nil)

		if comp:RequestStateMove(target_entity) then
			-- Not yet next to the target, wait for move to complete then repeat this instruction
			return true
		end

		if solve_puzzle_comp then
			FactionAction.ExplorableSolvePuzzle(owner.faction, { comp = solve_puzzle_comp, consume_slot = slot_with_fix_item })
		else
			FactionAction.ExplorableSetSolved(owner.faction, { entity = target_entity })
		end

		comp:SetStateSleep(1)
		return true
	end,
	args = {
		{ 'in', "Target", "Explorable to solve", 'entity' },
		{ 'out', "Missing", "Missing repair item, scanner component or Unpowered" },
		{ 'exec', "Failed", "Missing item, component, or power to scan" },
	},
	name = "Solve Explorable",
	desc = "Attempt to solve an explorable",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Drop Items.png",
	explain = [[Will attempt to solve the next item on an unsolved explorable. <hl>Missing</> will contain the required item if failed to solve it. Diverts logic if solving fails.]],
}

data.instructions.for_repair_ingredients =
{
	func = function(comp, state, cause, target_entity, out_ingredient, exec_done)
		local entity = GetEntity(comp, state, target_entity)
		if not entity then Set(comp, state, out_ingredient, nil) state.counter = exec_done return end
		local has_repair = entity:FindComponent("c_mothership_repair", true)
		if not has_repair then Set(comp, state, out_ingredient, nil) state.counter = exec_done return end

		local ingredients = { }
		if has_repair.extra_data and has_repair.extra_data.items then
			local max_items = has_repair.extra_data.max_items or 0
			local items = has_repair.extra_data.items
			for item,n in SortedPairs(items) do
				local total = (max_items - n)
				if total > 0 then ingredients[item] = total end
			end
		end

		if ingredients then
			local it = { 2 }
			for item,n in SortedPairs(ingredients) do
				it[#it + 1] = { id = item, num = n }
			end

			return BeginBlock(comp, state, it)
		end
	end,

	next = function(comp, state, it, target_entity, out_ingredient, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_ingredient, { id = it[i].id, num = it[i].num,  })
		it[1] = i + 1
	end,

	last = function(comp, state, it, target_entity, out_ingredient, exec_done)
		-- this would clear the variable on loop end or break
		-- leave it valid for now as its useful for breaks
		--Set(comp, state, out_ingredient, nil)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "Target", "Unit" },
		{ 'out', "Ingredient", "Repair Ingredient" },
		{ 'exec', "Done", "Finished looping through all mission repair ingredients" },
	},
	name = "Loop Repair Ingredients",
	desc = "Loops through each ingredient required to repair a mission unit",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Loops through each ingredient required to repair for a mission objective.]],
}

data.instructions.is_docked =
{
	func = function(comp, state, cause, exec_nodock, out_garage)
		local garage = comp.owner.docked_garage
		Set(comp, state, out_garage, { entity = garage })
		if not garage then
			state.counter = exec_nodock
		end
	end,
	args = {
		{ 'exec', "No Dock", "Where to continue if unit is not docked" },
		{ 'out', "Garage", "Unit" },
	},
	name = "Is Docked",
	desc = "Check if a unit is docked and get its garage",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
	explain = [[Checks if the unit is docked and returns the garage if docked or diverts logic is not docked.]],
}

local function GetRegisterOrComponentRegister(comp, state, reg, index, writable)
	local getcompreg = Get(comp, state, reg)
	local getcompid = getcompreg.id
	local num = getcompreg.num
	if getcompid then
		local regcomp = GetComponentFromSortedGroupIndex(comp, state, getcompid, index)
		if not regcomp then return end
		if num <= 0 then num = 1 end
		local register_defs = writable and regcomp.def.registers
		local register_def = register_defs and register_defs[num]
		if register_def and register_def.read_only then return end
		return regcomp:GetRegister(num)
	end
	if num == 1 then return FRAMEREG_SIGNAL
	elseif num == 2 then return FRAMEREG_VISUAL
	elseif num == 3 then return FRAMEREG_STORE
	elseif num == 4 then return FRAMEREG_GOTO end
end

data.instructions.set_link =
{
	func = function(comp, state, cause, from, from_index, to, to_index)
		local reg_from = GetRegisterOrComponentRegister(comp, state, from, from_index)
		local reg_to = GetRegisterOrComponentRegister(comp, state, to, to_index, true)
		if reg_from and reg_to then comp.owner:LinkRegisterFromRegister(reg_to, reg_from) end
	end,
	args = {
		{ 'in', "From", "Component and register number to start a new link", 'comp_num' },
		{ 'in', "Component Index", "Component index if multiple components equipped of same type", 'posnum', true },
		{ 'in', "To", "Component and register number to end a new link", 'comp_num' },
		{ 'in', "Component Index", "Component index if multiple components equipped of same type", 'posnum', true },
	},
	name = "Set Link",
	desc = "Set register link",
	category = "Unit",
	sample = "4d3bEIye2fVSng3WqwOU0xokOC25vA8t2JZIgm1UWD613pjgUE0zP4hW36Q9Ly0EoTor3jiXVs1Wqoo80vHdhz4C75Bj3KrEF548U0Xb3es3Dl1mCf1Z000qQ41OU5jHe",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
	explain = [[Creates a link between two registers.

<hl>From</> specifies the component and register number on that register to start the link
<hl>To</> specifies the component and register number of the register to end the link

- If no number is specified it will get the first register.
- Extra variables for <hl>Component Index</> allow specifying registers if multiple of the same component are equipped.
- If no component is specified then it will use the frame registers for the unit.

Example:
- Link the result register of the Scout Radar to the frames <bl>Visual</> Register
- Link the Missing Ingredient register of the second equipped fabricator to the units <bl>Signal</> Register.]],
}

data.instructions.clear_link =
{
	func = function(comp, state, cause, from, from_index, to, to_index)
		local reg_from = GetRegisterOrComponentRegister(comp, state, from, from_index)
		local reg_to = GetRegisterOrComponentRegister(comp, state, to, to_index)
		if reg_from and reg_to then comp.owner:UnlinkRegisterFromRegister(reg_to, reg_from) end
	end,
	args = {
		{ 'in', "From", "Component/Register Index to start clearing a link", 'comp_num' },
		{ 'in', "Component Index", "Index for when multiple components equipped of same type", 'posnum', true },
		{ 'in', "To", "Component/Register Index to end clearing a link", 'comp_num' },
		{ 'in', "Component Index", "Index for when multiple components equipped of same type", 'posnum', true },
	},
	name = "Clear Link",
	desc = "Clear register link",
	sample = "V02rugD00ZrgW1kIyn229KtvP1mdoOq2yRWLc02Gtj720HOnj000gcg29Kh6o04YPFt1r9kT41z2xSD2yPbs9018W0VU",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
	explain = [[Clears a specific established link or connection

See <hl>Set Link</> for parameter details.]],
}

data.instructions.clear_all_links =
{
	func = function(comp, state, cause)
		for _, l in ipairs(comp.owner:GetRegisterLinks(false, true) or {}) do
			local reg_from, reg_to = l.source_index, l.index
			local comp_from, comp_to = (reg_from > FRAMEREG_COUNT and l.source_component), (reg_to > FRAMEREG_COUNT and l.component)
			if (not comp_from or not comp_from.is_hidden or comp_from.def.get_ui) and (not comp_to or not comp_to.is_hidden or comp_to.def.get_ui) then
				comp.owner:UnlinkRegisterFromRegister(reg_to, reg_from)
			end
		end
	end,
	name = "Clear All Links",
	desc = "Clear all register links on this unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
	explain = [[Clear all register links on the unit holding the Behavior controller. Including links to and from components that contain registers.

Note: This instruction cannot be used to perform the action on an external unit.]],
}

--[[
data.instructions.dodock =
{
	func = function(comp, state, cause, target)
		target = GetEntity(comp, state, target)
		if target and target.exists then
			if comp:RequestStateMove(target) then
				-- Not yet next to the garage frame, wait for move to complete then repeat this instruction
				state.counter = state.lastcounter
				return true
			end
			comp.owner:DockInto(target)
		end
		comp:SetStateSleep(1)
		return true
	end,
	args = { { 'in', "Target", "Unit" } },
	name = "Dock",
	desc = "Docks an item on the following target",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Dock.png",
}

data.instructions.doundock =
{
	func = function(comp, state)
		if comp.owner.is_docked then
			Map.Defer(function() comp.owner:Undock() end)
		end
		return comp:SetStateSleep(1)
	end,
	name = "Undock",
	desc = "Undocks an item on the following target",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Undock.png",
}

--]]

--------------------------------------------------------------------------------------------------------------------------
--------------------------------------- MOVE -----------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------

data.instructions.stop =
{
	func = function(comp, state, cause, target)
		comp.owner:Cancel()
	end,
	name = "Stop Unit",
	desc = "Stop movement and abort what is currently controlling the unit's movement",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
	explain = [[Halts all movement and actions currently being executed by the unit.]],
}

data.instructions.get_location =
{
	func = function(comp, state, cause, in_entity, out_coord)
		local ent = GetSeenEntityOrSelf(comp, state, in_entity)
		if ent then
			Set(comp, state, out_coord, { coord = { ent.location.x, ent.location.y }})
		end
	end,
	args = {
		{ 'in', "Unit", "Unit to get coordinates of", 'entity' },
		{ 'out', "Coord", "Coordinate of unit", },
	},
	name = "Get Location",
	desc = "Gets location of a seen unit",
	category = "Global",
	sample = "4n3YxVw80sfebZ3FYilH1mhyfZ1aqqXJ3mEgt61mSlGp1lR1A02pEzn83JGOGx2yjtHI03dj7c393Dme48tMBM0oR9Wf3gYKqo4Ir13P0oIFCO1kWMsT3Fqfg00LjJLm4bI1Jf2giIcU4BzdP64d1urc15VNyW2ReA392sJGaE32eOpU00IptM4J1AVYH",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Gets the current coordinate of the unit.]],
}

data.instructions.get_offset =
{
	func = function(comp, state, cause, in_target, out_offset)
		local reg = Get(comp, state, in_target)
		local target_entity = reg.entity
		local target_coord = target_entity and target_entity.location or reg.coord
		if not target_coord then return end

		local l1 = target_coord
		local l2 = comp.owner.location
		local ofs = {
			x = l2.x - l1.x,
			y = l2.y - l1.y
		}
		Set(comp, state, out_offset, { coord = ofs })
	end,
	args = {
		{ 'in', "Target", "Unit/Coord to get offset from", 'coord' },
		{ 'out', "Offset", "Offset from unit", 'coord' },
	},
	name = "Get Offset",
	desc = "Gets current offset from a unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[<hl>Target</> specifies the unit or coord you want to get the offset from]],
	sample = "2W3bEIye4XJFlw0eSEdy3tXhH132VJta0glM3R1vgfPV2XzKR33GxCnS1mFGcl4SPuUM30qovr0QMAzZ1Ds",
}

data.instructions.move_offset =
{
	func = function(comp, state, cause, in_offset, in_entity)
		local move_ofs = GetCoord(comp, state, in_offset)
		local e = GetSeenEntityOrSelf(comp, state, in_entity)
		if move_ofs and e then
			local loc = e.location
			if not comp:RequestStateMove(loc.x+move_ofs.x, loc.y+move_ofs.y) then comp:SetStateSleep(1) end
		else
			comp:SetStateSleep(1)
		end
		return true
	end,
	args = {
		{ 'in', "Offset", "Offset to move to", 'coord' },
		{ 'in', "Unit", "Unit to offset from", 'entity', true },
	},
	name = "Move Offset",
	desc = "Moves to a specific offset of current location or specified unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[<hl>Offset</> is the x,y offset amount to move
Optional <hl>Unit</> can specify a unit as the base for the offset.
Defaults to current location.]],
	sample = "2W3bEIye4XJFlw0eSEdy3tXhH132VJta0glM3R1vgfPV2XzKR33GxCnS1mFGcl4SPuUM30qovr0QMAzZ1Ds",
}

data.instructions.move_east =
{
	func = function(comp, state, cause, target)
		local move_dist = GetNum(comp, state, target)
		local loc = comp.owner.location
		if not comp:RequestStateMove(loc.x+move_dist, loc.y) then comp:SetStateSleep(1) end
		return true
	end,
	args = {
		{ 'in', "Number", "Number of tiles to move East", 'posnum' },
	},
	deprecated = true,
	name = "Move East",
	desc = "Moves towards a tile East of the current location at the specified distance",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Moves the unit a specified number of tiles to the east.]],
}

data.instructions.move_west =
{
	func = function(comp, state, cause, target)
		local move_dist = GetNum(comp, state, target)
		local loc = comp.owner.location
		if not comp:RequestStateMove(loc.x-move_dist, loc.y) then comp:SetStateSleep(1) end
		return true
	end,
	args = {
		{ 'in', "Number", "Number of tiles to move West", 'posnum' },
	},
	deprecated = true,
	name = "Move West",
	desc = "Moves towards a tile West of the current location at the specified distance",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Moves the unit a specified number of tiles to the west.]],
}

data.instructions.move_north =
{
	func = function(comp, state, cause, target)
		local move_dist = GetNum(comp, state, target)
		local loc = comp.owner.location
		if not comp:RequestStateMove(loc.x, loc.y-move_dist) then comp:SetStateSleep(1) end
		return true
	end,
	args = {
		{ 'in', "Number", "Number of tiles to move North", 'posnum' },
	},
	deprecated = true,
	name = "Move North",
	desc = "Moves towards a tile North of the current location at the specified distance",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Moves the unit a specified number of tiles to the north.]],
}

data.instructions.move_south =
{
	func = function(comp, state, cause, target)
		local move_dist = GetNum(comp, state, target)
		local loc = comp.owner.location
		if not comp:RequestStateMove(loc.x, loc.y+move_dist) then comp:SetStateSleep(1) end
		return true
	end,
	args = {
		{ 'in', "Number", "Number of tiles to move South", 'posnum' },
	},
	deprecated = true,
	name = "Move South",
	desc = "Moves towards a tile South of the current location at the specified distance",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Moves the unit a specified number of tiles to the south.]],
}

data.instructions.domove_async =
{
	func = function(comp, state, cause, target)
		local reg = Get(comp, state, target)
		local target = reg and (reg.entity or reg.coord)
		if not target then return end
		comp.owner:MoveTo(target)
	end,
	args = {
		{ 'in', "Target", "Unit to move to", 'entity' },
	},
	deprecated = true,
	name = "Move Unit (Async)*",
	desc = "*DEPRECATED* Use Move Unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Starts a movement to a location but the behavior logic moves onto the next instruction and does not wait for the move instruction to complete.]],
}

data.instructions.attack_move =
{
	func = function(comp, state, cause, in_target, in_unit)
		local ent = GetAdjacentFactionEntityOrSelf(comp, state, in_unit)
		if not ent then return end

		local reg = Get(comp, state, in_target)
		local target_entity = reg.entity
		local target_coord = target_entity and target_entity.location or reg.coord

		local turret
		local turret_range
		for i=1,999 do
			local next_turret = ent:FindComponent("c_turret", true, i)
			if not next_turret then break end
			local next_range = next_turret.def.attack_radius
			if not turret or next_range > turret_range then
				turret = next_turret
				turret_range = next_range
			end
		end
		if turret then
			if not target_coord then
				turret:SetRegister(1, nil)
			else
				turret:SetRegister(1, { coord = target_coord, num = reg.num })
			end
		end
	end,
	args = {
		{ "in", "Target", "Target unit or coordinate", 'coord' },
		{ 'in', "Unit", "Unit", 'entity', true },
	},
	name = "Attack Move",
	desc = "Moves towards a location stopping to attack any enemies encountered",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Moves toward a location while stopping to attack any enemies encountered along the way.]],
}

data.instructions.simulation_tick =
{
	func = function(comp, state, cause, out_tick)
		Set(comp, state, out_tick, { num = Map.GetTick() })
	end,
	args = {
		{ 'out', "Tick", "Simulation Tick"}
	},
	name = "Simulation Tick",
	category = "Math",
	desc = "Returns the current Simulation Tick",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.domove =
{
	func = function(comp, state, cause, c, target, exec_fail, in_unit)
		local ent = GetAdjacentFactionEntityOrSelf(comp, state, in_unit)
		if not ent then if exec_fail then state.counter = exec_fail end return end

		local reg = Get(comp, state, target)
		local target = reg and (reg.entity or reg.coord)
		if not target then return end
		if c == 2 or comp.owner ~= ent then
			ent:MoveTo(target, math.max(reg.num, 0))
		else
			local need_move, repeat_blocked = comp:RequestStateMove(target, math.max(reg.num, 0))
			if repeat_blocked then
				comp:SetStateSleep(1)
				state.counter = exec_fail
			elseif need_move then
				-- Not yet next to the target, wait for move to complete then repeat this instruction
				state.counter = state.lastcounter
			else
				comp:SetStateSleep(1)
			end
			return true
		end
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Synchronous", "Asynchronous" }
		combo.value = inst.c or 1
		return 34
	end,

	args = {
		{ 'in', "Target", "Unit to move to, the number specifies the range in which to be in", 'entity' },
		{ 'exec', "Path Blocked", "Where to continue if unit is path blocked" },
		{ 'in', "Unit", "Target Unit", 'entity', true },
	},
	name = "Move Unit",
	desc = "Moves to another unit or within a range of another unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Moves the unit to the specified target location or within range of it by specifying the number in the register.]],
}

data.instructions.domove_range =
{
	func = function(comp, state, cause, target)
		local reg = Get(comp, state, target)
		local target = reg and (reg.entity or reg.coord)
		if not target then return end
		if not comp:RequestStateMove(target, math.max(reg.num, 0)) then comp:SetStateSleep(1) end
		return true
	end,
	args = {
		{ 'in', "Target", "Unit to move to, the number specifies the range in which to be in", 'entity' },
	},
	deprecated = true,
	name = "*Move Unit (Range)*",
	desc = "*DEPRECATED* Use Move Unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Moves toward a target location until within a specified range.]],
}
--[[ old version
data.instructions.domove =
{
	func = function(comp, state, cause, target)
		local reg = Get(comp, state, target)
		local target = reg and (reg.entity or reg.coord)
		if not target then return end
		if not comp:RequestStateMove(target) then comp:SetStateSleep(1) end
		return true
	end,
	args = {
		{ 'in', "Target", "Unit to move to", 'entity' },
	},
	name = "Move Unit",
	desc = "Move to another unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
}
]]--

data.instructions.moveaway_range =
{
	func = function(comp, state, cause, c, target)
		local reg = Get(comp, state, target)
		if not reg or not reg.entity then return end
		local range = reg.num > 0 and reg.num or 5

		-- find location away from unit
		local l1, l2 = comp.owner.location, reg.entity.location

		local x = l1.x-l2.x
		local y = l1.y-l2.y
		local denom = math.sqrt((x*x)+(y*y))
		if denom > range then return end
		if denom == 0 then
			if c == 2 then comp.owner:MoveTo(l1.x+range, l1.y) return end
			if not comp:RequestStateMove(l1.x+range, l1.y) then comp:SetStateSleep(1) end
		else
			local lx = math.ceil((x/denom)*range)+l2.x
			local ly = math.ceil((y/denom)*range)+l2.y
			if c == 2 then comp.owner:MoveTo(lx, ly) return end
			if not comp:RequestStateMove(lx, ly) then comp:SetStateSleep(1) end
		end
		return true
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Synchronous", "Asynchronous" }
		combo.value = inst.c or 1
		return 34
	end,
	args = {
		{ 'in', "Target", "Unit to move away from", 'entity' },
	},
	name = "Move Away (Range)",
	desc = "Moves out of range of another unit, the number value of the target specifies the range",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Moves the unit away from a target until it is outside the of specified range specified in the number of the register.]],
}

data.instructions.scout =
{
	func = function(comp, state, cause, c)
		local loc = comp.faction.home_location
		local target_loc = comp.owner.location
		local vx = target_loc.x - loc.x
		local vy = target_loc.y - loc.y
		local len = math.sqrt(vx * vx + vy * vy)
		if len == 0 then -- i am the faction home
			local newx, newy = comp.faction:FindClosestHiddenTile(target_loc.x, target_loc.y, 1000)
			if newx == nil then
				-- pick random direction
				target_loc.x = target_loc.x + math.random(-10, 10)
				target_loc.y = target_loc.y + math.random(-10, 10)
			else
				target_loc.x, target_loc.y = newx, newy
			end
		elseif len < 40 then
			-- * check distance from base and move away from it if too close
			--print(target_loc, len)
			target_loc.x, target_loc.y = math.floor(target_loc.x + (vx*20)/len), math.floor(target_loc.y + (vy*20)/len)
			--print(target_loc)
		else
			-- not very smart...
			-- * try to head towards hidden tiles? target_loc.x, target_loc.y = comp.faction:FindClosestHiddenTile(target_loc.x, target_loc.y, 1000)
			-- * try to not get stuck... how to detect stuck?
			-- * avoid blight! this should probably be part of the pathing/movement system...

			-- add some randomness
			local ang_deg = Map.GetTick()%360
			local rx=math.floor(math.cos(math.rad(ang_deg))*(len/15))
			local ry=math.floor(math.sin(math.rad(ang_deg))*(len/15))

			-- go around in circles wiht a bit of loopy loop randomness
			target_loc.x, target_loc.y = math.floor(target_loc.x + (vy*(len/10))/len)+rx, math.floor(target_loc.y + (-vx*(len/10))/len)+ry
		end

		-- async
		if c == 2 then comp.owner:MoveTo(target_loc.x, target_loc.y) return end

		-- sync
		local moveret = comp:RequestStateMove(target_loc.x, target_loc.y)
		if not moveret then state.counter = state.lastcounter comp:SetStateSleep(5) end
		return true
	end,
	make_asm = function(inst)
		return inst.c or 1
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) if inst.c ~= value then inst.c = value program_ui:set_dirty(true) end end})
		combo.texts = { "Synchronous", "Asynchronous" }
		combo.value = inst.c or 1
		return 34
	end,
	name = "Scout",
	desc = "Moves in a scouting pattern around the factions home location",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Scout.png",
	explain = [[Sends the unit to explore unknown areas in a spiral movement around your faction home.]],
}

data.instructions.scout_rand_range =
{
	func = function(comp, state, cause, in_range, in_lastLoc)
		local target_loc = comp.owner.location
		local range = GetNum(comp, state, in_range)
		if range <= 0 then range = 5 end

		if in_lastLoc then
			local lastCoord = GetCoord(comp, state, in_lastLoc)
			if lastCoord then
				local x1, x2, y1, y2 = lastCoord.x, target_loc.x, lastCoord.y, target_loc.y
				if x1 ~= x2 or y1 ~= y2 then
					local dx, dy = x2-x1, y2-y1
					target_loc.x = target_loc.x + math.ceil(dx*1.5)
					target_loc.y = target_loc.y + math.ceil(dy*1.5)
				end
			end
		end

		-- pick random direction
		target_loc.x = target_loc.x + math.random(-range, range)
		target_loc.y = target_loc.y + math.random(-range, range)

		comp.owner:MoveTo(target_loc.x, target_loc.y)
	end,
	args = {
		{ 'in', "Range", "Range to scout", 'posnum' },
		{ 'in', "Coord", "Last Coordinate", 'coord' },
	},
	name = "Scout Range",
	desc = "Moves in a random direction a specified amount\nOptionally pass a coordinate to give some directionality",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Scout.png",
	explain = [[Scouts a random location within a defined range.]],
}
-- these dont work because you cant have an negative number in a register...
--[[
data.instructions.domovexy =
{
	func = function(comp, state, cause, x, y)
		if not comp:RequestStateMove(GetNum(comp, state, x), GetNum(comp, state, y)) then comp:SetStateSleep(1) end
		return true
	end,
	args = {
		{ { 'in', "X", "X Coordinate", 'num' } },
		{ { 'in', "Y", "Y Coordinate", 'num' } },
	},
	name = "Move To Coordinate",
	desc = "Move to a specific coordinate",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move to X Y.png",
}

data.instructions.getxy =
{
	func = function(comp, state, cause, x, y)
		local loc = comp.owner.location
		Set(comp, state, x, loc.x)
		Set(comp, state, y, loc.y)
	end,
	args = {
		{ { 'out', "X", "X Coordinate" } },
		{ { 'out', "Y", "Y Coordinate" } },
	},
	name = "Get unit Coordinates",
	desc = "Gets the X and Y coordinate of a Unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move to X Y.png",
}
--]]

--------------------------------------------------------------------------------------------------------------------------
--------------------------------------- COMPONENT -----------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
data.instructions.for_count_resources =
{
	func = function(comp, state, cause, out_resource, exec_done)
		local resources = { }
		local location = comp.owner.location

		local range = comp.owner.power_range
		if range == 0 then range = comp.owner.visibility_range end
		Map.FindClosestEntity(location.x, location.y, range - 1, function(e)
			if not comp.faction:IsDiscovered(e) then return end
			local id, amt = GetResourceHarvestItemId(e), GetResourceHarvestItemAmount(e)
			if id and resources[id] ~= REG_INFINITE then
				if amt == REG_INFINITE then resources[id] = REG_INFINITE
				else resources[id] = (resources[id] or 0) + amt
				end
			end
		end, FF_RESOURCE)
		local it = { 2 }
		for k,v in SortedPairs(resources) do
			it[#it+1] = k
			it[#it+1] = v
		end
		return BeginBlock(comp, state, it)
	end,

	next = function(comp, state, it, out_resource, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_resource, { id = it[i], num = it[i+1] })
		it[1] = i + 2
	end,

	last = function(comp, state, it, out_resource, exec_done)
		-- this would clear the variable on loop end or break
		-- leave it valid for now as its useful for breaks
		--Set(comp, state, out_entity, nil)
		state.counter = exec_done
	end,
	args = {
		{ 'out', "Resource" },
		{ 'exec', "Done" },
	},
	name = "Loop Nearby Resources",
	desc = "Scans for nearby resources in power field or visibility range",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Scan.png",
	explain = [[Loops over all resource types and counts the total amount of each in the power field or visibility range.]],
}

data.instructions.deploy =
{
	func = function(comp, state, cause, in_coord)
		local owner = comp.owner
		local deployer = owner:FindComponent("c_deployment") or owner:FindComponent("c_deployer")
		if not deployer then return end
		local coord = GetCoord(comp, state, in_coord) or owner.location
		local x, y = comp.faction:GetPlaceableLocation("f_landingpod", coord.x, coord.y, true)
		deployer:SetRegister(1, { coord = { x = x, y = y}})
	end,
	name = "Deploys held unit",
	desc = "Deploys the first found held unit at location specified or current location",
	category = "Component",
	args = {
		{ 'in', "Coord", "location to deploy" }
	},
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
	explain = [[Deploys a unit to a specified location.]],
}

data.instructions.wait_component =
{
	func = function(comp, state, cause, in_comp, group_index, exec_not_working)
		if cause & CC_OTHER_COMP_FINISH_WORK ~= 0 then
			comp:SetStateSleep(1)
			return true
		end

		local comp_id = GetId(comp, state, in_comp)
		local found_comp = comp_id and GetComponentFromSortedGroupIndex(comp, state, comp_id, group_index)

		if found_comp then
			if not found_comp.is_working and exec_not_working then state.counter = exec_not_working return end
			comp:WaitForOtherCompFinish(found_comp)
			return true
		end
		comp:SetStateSleep(1)
		return true
	end,
	args = {
		{ 'in', "Component", "Component to wait for", 'comp'},
		{ 'in', "Component Index", "Component index if multiple are equipped", 'posnum', true },
		{ 'exec', "Not Working", "Execution path if the component isn't currently working", nil, true},
	},
	name = "Wait Component",
	desc = "Waits for a component before continuing behavior",
	sample = "V02rMa9057Lu41kIyn329KtvP1mdoOq2yRWLc3BYvDV28Aqyl20Fjl11rAJLk22kZQc01oI",
	explain = [[Waits on a specified component to finish their current work cycle and then resumes execution of the behavior]],
	category = "Component",
	icon = "Main/skin/Icons/Special/Commands/Wait.png"
}
data.instructions.scan =
{
	func = function(comp, state, cause, f1, f2, f3, result, no_result)
		local owner = comp.owner
		local radar = owner:FindComponent("c_portable_radar", true)

		local f1id = GetId(comp, state, f1)
		local filters = { f1id, f1id and GetNum(comp, state, f1), nil, nil, nil, nil }
		if filters[1] then
			filters[3] = GetId(comp, state, f2)
			filters[4] = filters[3] and GetNum(comp, state, f2)
			if filters[3] then
				filters[5] = GetId(comp, state, f3)
				filters[6] = filters[5] and GetNum(comp, state, f3)
			end
		end

		if not radar then
			local num
			local entity_filter, override_range = PrepareFilterEntity(filters)
			local range = owner.visibility_range
			local res = Map.FindClosestEntity(owner, math.min(override_range or range, range), function(e)
				local a, b = FilterEntity(owner, e, filters)
				if a then
					num = b
				end
				return a
			end, entity_filter)
			Set(comp, state, result, { entity = res, num = num })
			if not res then
				state.counter = no_result
			end
			comp:SetStateSleep(1)
			return true
		end

		local vals = { Get(comp, state, f1), Get(comp, state, f2), Get(comp, state, f3) }
		local radar_reg_count, filters_changed = #radar.def.registers
		for i=1,math.min(#vals, radar_reg_count - 1) do
			if radar:GetRegister(i) ~= vals[i] then
				radar:SetRegister(i, vals[i])
				filters_changed = true
			end
		end

		if filters_changed or cause & CC_OTHER_COMP_FINISH_WORK == 0 then
			state.counter = state.lastcounter
			comp:WaitForOtherCompFinish(radar)
			return true
		end

		Set(comp, state, result, radar:GetRegister(radar_reg_count))

		if not GetEntity(comp, state, result) then state.counter = no_result end

		for i=1,math.min(#vals, radar_reg_count - 1) do
			radar:SetRegister(i, nil)
		end
	end,
	args = {
		{ 'in', "Filter 1", "First filter", 'radar' },
		{ 'in', "Filter 2", "Second filter", 'radar' },
		{ 'in', "Filter 3", "Third filter", 'radar' },
		{ 'out', "Result" },
		{ 'exec', "No Result", "Execution path if no results are found" },
	},
	name = "Radar",
	desc = "Scan for the closest unit that matches the filters",
	category = "Component",
	icon = "Main/skin/Icons/Special/Commands/Scan.png",
	explain = [[Scans the nearby environment for objects or entities of interest. This instruction does not require a radar component to be equipped.]],
}

data.instructions.mine =
{
	func = function(comp, state, cause, resource, no_mine, inv_full)
		local owner = comp.owner
		local m = owner:FindComponent("c_miner", true)
		local miner = m

		if not miner then -- no miner
			--Set(comp, state, resource, nil)
			state.counter = no_mine
			comp:SetStateSleep(1)
			return true
		end

		-- get all miners on entity
		local miners = { }
		local i = 1
		while m do
			miners[#miners+1] = m
			i=i+1
			m = owner:FindComponent("c_miner", true, i)
		end
		--[[
		if cause & CC_OTHER_COMP_FAIL_WORK ~= 0 then
			state.counter = no_mine
			comp:SetStateSleep(1)
			return true
		end
		--]]

		local val = Get(comp, state, resource)

		if not val or (val.id == nil and val.entity == nil) then
			for _, m in ipairs(miners) do m:SetRegister(1, nil) end -- stop mining if empty
			state.counter = no_mine
			return
		end

		-- check path
		if owner.state_path_blocked then
			owner:Cancel()
			state.counter = no_mine
			for _, m in ipairs(miners) do m:SetRegister(1, nil) end
			return
		end

		-- check power
		local details = owner.power_details
		if not details or details.efficiency == 0 then
			state.counter = no_mine
			for _, m in ipairs(miners) do m:SetRegister(1, nil) end
			return
		end

		-- has required amount
		local harvestid = val.id or GetResourceHarvestItemId(val.entity)
		if harvestid and val.num > 0 then
			local hasAmt = owner:CountItem(harvestid)
			if hasAmt >= val.num then
				state.counter = inv_full
				for _, m in ipairs(miners) do m:SetRegister(1, nil) end
				return true
			end
		end

		-- probably a dropped item, cant mine
		if not harvestid then return end

		-- set reg
		local miner_reg = miner:GetRegister(1)

		if miner_reg.entity then
			-- miner holds an resource node
			if val.entity and miner_reg.entity ~= val.entity then
				for _, m in ipairs(miners) do m:SetRegister(1, val) end
			end
		elseif miner_reg.id then
			if val.id and miner_reg.id ~= val.id then
				-- mismatching id
				for _, m in ipairs(miners) do m:SetRegister(1, val) end
			elseif miner_reg.id ~= harvestid then
				-- doesnt match the requested resource id
				for _, m in ipairs(miners) do m:SetRegister(1, val) end
			elseif val.entity and val.entity ~= miner.extra_data.target then
				for _, m in ipairs(miners) do m:SetRegister(1, val) end
			end
		else
			for _, m in ipairs(miners) do m:SetRegister(1, val) end
		end

		-- no space
		local canfit = owner:HaveFreeSpace(harvestid, 1)

		if canfit == false then
			state.counter = inv_full

			-- Only set is different from current
			if val.id and miner_reg.id ~= val.id then
				for _, m in ipairs(miners) do m:SetRegister(1, nil) end
			end
			return
		end
	end,
	args = {
		{ 'in', "Resource", "Resource to Mine", "resource_num" },
		{ 'exec', "Cannot Mine", "Execution path if mining was unable to be performed" },
		{ 'exec', "Full", "Execution path if can't fit resource into inventory" },
	},
	name = "Mine",
	desc = "Mine a single resource deposit",
	category = "Component",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Starts mining nearby resource deposits and divert logic depending on whether the unit cannot mine or inventory is full.]],
}

--------------------------------------------------------------------------------------------------------------------------
--------------------------------------- GLOBAL -----------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------

data.instructions.get_stability =
{
	func = function(comp, state, cause, out_stability)
		if StabilityGet then
			local stability = StabilityGet()
			Set(comp, state, out_stability, { num = stability })
		else
			Set(comp, state, out_stability, { num = 0 })
		end
	end,

	args = {
		{ 'out', "Number", "Stability" },
	},
	name = "Get Stability",
	desc = "Gets the current world stability",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Returns the current world stability as a number.]],
}
data.instructions.percent_value =
{
	func = function(comp, state, cause, in_value, in_max, out_percent)
		local value, max = GetNum(comp, state, in_value), GetNum(comp, state, in_max)
		if max == 0 or value == 0 then
			Set(comp, state, out_percent, { num = 0 })
		else
			Set(comp, state, out_percent, { num = (value*100) // max })
		end
	end,

	args = {
		{ 'in', "Value", "Value to check" },
		{ 'in', "Max Value", "Max Value to get percentage of" },
		{ 'out', "Number", "Percent" },
	},
	name = "Percent",
	desc = "Gives you the percent that value is of Max Value",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Calculates a percentage-based value from an input number.]],
}

data.instructions.remap_value =
{
	func = function(comp, state, cause, in_value, in_low_input, in_high_input, in_low_target, in_high_target, out_result)
		local value, low_input, high_input, low_target, high_target = GetNum(comp, state, in_value), GetNum(comp, state, in_low_input), GetNum(comp, state, in_high_input), GetNum(comp, state, in_low_target), GetNum(comp, state, in_high_target)
		local dif_target = high_target-low_target
		local dif_input = high_input-low_input

		if dif_target == 0 or dif_input == 0 then
			Set(comp, state, out_result, { num = high_target })
		else
			local outnum = low_target+ (value-low_input) * (dif_target) // (dif_input)
			outnum = math.min(outnum, high_target)
			outnum = math.max(outnum, low_target)
			Set(comp, state, out_result, { num = outnum })
		end
	end,

	args = {
		{ 'in', "Value", "Value to Remap" },
		{ 'in', "Input Low", "Low value for input" },
		{ 'in', "Input High", "High value for input" },
		{ 'in', "Target Low", "Low value for target" },
		{ 'in', "Target high", "High value for target" },
		{ 'out', "Result", "Remapped value" },
	},
	name = "Remap",
	desc = "Remaps a value between two ranges",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Maps a number from one value range to another.]],
}

data.instructions.is_daynight =
{
	func = function(comp, state, cause, if_day, if_night)
		state.counter = Map.GetSunlightIntensity() > 0.0 and if_day or if_night
	end,

	exec_arg = false,
	args = {
		{ 'exec', "Day", "Where to continue if it is nighttime" },
		{ 'exec', "Night", "Where to continue if it is daytime" },
	},
	name = "Is Day/Night",
	desc = "Divert program depending time of day",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Checks whether it is currently day or night in the world.]],
}

data.instructions.get_season =
{
	func = function(comp, state, cause, if_winter, if_spring, if_summer, if_fall)
		local season = Map.GetYearSeason()
		local season_no = (math.floor((season + 0.125) * 4.0) % 4) + 1
		if season_no == 1 then state.counter = if_winter
		elseif season_no == 2 then state.counter = if_spring
		elseif season_no == 3 then state.counter = if_summer
		else state.counter = if_fall
		end
	end,

	exec_arg = false,
	args = {
		{ 'exec', "Winter", "Where to continue if it is winter" },
		{ 'exec', "Spring", "Where to continue if it is spring" },
		{ 'exec', "Summer", "Where to continue if it is summer" },
		{ 'exec', "Fall", "Where to continue if it is fall" },
	},
	name = "Get Season",
	desc = "Divert program depending on season",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
	explain = [[Returns the current season and diverts logic depending on the season.]],
}
data.instructions.faction_item_amount =
{
	func = function(comp, state, cause, item, output, exec_none)
		local item_id = GetId(comp, state, item)
		if not item_id then
			Set(comp, state, output, nil)
			return
		end
		local hasAmt = comp.faction:GetItemAmount(item_id)
		if hasAmt == 0 then
			state.counter = exec_none
		end
		Set(comp, state, output, { item = item_id, num = hasAmt })
	end,
	args = {
		{ 'in', "Item", "Item to count", "item" },
		{ 'out', "Result", "Number of this item in your faction" },
		{ 'exec', "None", "Execution path when none of this item exists in your faction" },
	},
	name = "Faction Item Amount",
	desc = "Counts the number of the passed item in your logistics network",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
}
data.instructions.readkey =
{
	func = function(comp, state, cause, frame, key)
		local reg = Get(comp, state, frame)
		Set(comp, state, key, {})
		if not reg or not reg.entity then
			--print("no entity")
			return
		end
		if reg.entity.extra_data and reg.entity.extra_data.solved == true then
			local scannable = reg.entity:FindComponent("c_explorable_scannable")
			if scannable and scannable.extra_data.hack_code then
				Set(comp, state, key, { entity = reg.entity, num = scannable.extra_data.hack_code})
			end
		end
	end,
	args = {
		{ 'in', "Frame", "Structure to read the key for", 'entity' },
		{ 'out', "Key", "Number key of structure" },
	},
	name = "Read Key",
	desc = "Attempts to read the internal key of the unit",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Read Key.png",
	explain = [[Reads a value from a configuration or storage key.]],
}

data.instructions.can_produce =
{
	func = function(comp, state, cause, can_prod, product_id, in_component)
		local product_def = data.all[GetId(comp, state, product_id)]
		if not product_def then
			local entity = GetEntity(comp, state, product_id)
			if entity then product_def = entity.def end
		end
		local owner, production_recipe = comp.owner, product_def and (product_def.production_recipe or product_def.construction_recipe)
		local producers = (production_recipe and production_recipe.producers) or (product_def and product_def.mining_recipe)
		if producers then
			-- only check the owner if a component wasnt specified
			local component_id = GetId(comp, state, in_component)
			if component_id then
				for k,v in pairs(producers) do
					if k == component_id then
						state.counter = can_prod
						return
					end
				end
			else
				for k,v in pairs(producers) do
					if owner:CountComponents(k) > 0 then
						state.counter = can_prod
						return
					end
				end
			end
		end
	end,
	name = "Can Produce",
	desc = "Returns if a unit can produce an item",
	exec_arg = { 1, "Cannot Produce", "Where to continue if the item cannot be produced" },
	args = {
		{ 'exec', "Can Produce", "Where to continue if the item can be produced" },
		{ 'in', "Item", "Production Item", "item" },
		{ 'in', "Component", "Optional Component to check (if Component not equipped)", 'comp_num', true },
	},
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Can Produce.png",
	explain = [[Checks if a unit can produce a specific item and diverts logic depending on the result.]],
}

data.instructions.get_ingredients =
{
	func = function(comp, state, cause, product, out1, out2, out3)
		local item_id = GetId(comp, state, product)
		local product_def, ingredients = item_id and data.all[item_id]
		local ent = not product_def and GetEntity(comp, state, product)
		local count = 1
		if product_def then
			local production_recipe = product_def.production_recipe or product_def.uplink_recipe
			ingredients = production_recipe.ingredients
			if product_def.progress_count then count = product_def.progress_count end
		elseif ent and ent.is_construction then
			local fd, bd = GetProduction(ent:GetRegisterId(FRAMEREG_GOTO), ent)
			ingredients = fd and GetIngredients((fd.construction_recipe or fd.production_recipe), bd)
		end
		local res = { }
		if ingredients then
			for rec_item,rec_num in SortedPairs(ingredients) do
				res[#res + 1] = { id = rec_item, num = rec_num*count }
			end
		end
		table.sort(res, function(a, b) return a.id < b.id end)
		Set(comp, state, out1, res[1])
		Set(comp, state, out2, res[2])
		Set(comp, state, out3, res[3])
	end,
	args = {
		{ 'in', "Product", nil, "item" },
		{ 'out', "Out 1", "First Ingredient" },
		{ 'out', "Out 2", "Second Ingredient" },
		{ 'out', "Out 3", "Third Ingredient" },
	},
	deprecated = true, -- use loop ingredients instead
	name = "Get Ingredients",
	desc = "Returns the ingredients required to produce an item",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Ingradients.png",
	explain = [[Returns the required ingredients for producing a specified item or recipe.]],
}

data.instructions.notify =
{
	func = function(comp, state, cause, txt, notify_value, timeout_value)
		local reg = Get(comp, state, notify_value)
		local reg_id, reg_entity, reg_num, reg_coord = reg.id, reg.entity, reg.num, reg.coord
		local timeout = GetNum(comp, state, timeout_value)

		local reg_def
		if reg_entity then
			reg_def = reg_entity.def
		elseif reg_id then
			reg_def = data.all[reg_id]
		elseif reg_num ~= 0 or reg_coord then
			reg_def = data.components.c_behavior
		else
			reg_def = data.values.v_notify
		end

		if reg_def then
			comp.faction:RunUI(function()
				local entity = reg_entity or comp.owner
				if reg_coord then
					local jump_location = reg.coord
					Notification.Add(string.format("C%d|%d", reg_coord.x, reg_coord.y) or "notify_behavior", reg_def.texture, L("Notify (%s)", string.format("%d,%d", reg_coord.x, reg_coord.y)), NOLOC(txt) or reg_def.name or "Notification", {
						tooltip = "Behavior Notification",
						on_click = function() View.MoveCamera(jump_location.x, jump_location.y, false) end,
						duration = timeout > 0 and timeout,
					})
				else
					Notification.Add(reg_id or "notify_behavior", reg_def.texture, reg_num ~= 0 and L("Notify (%s)", (reg_num == REG_INFINITE and "∞") or (reg_num == REG_NOT and "≠") or tostring(reg_num)) or "Notify", NOLOC(txt) or reg_def.name or "Notification", {
						tooltip = "Behavior Notification",
						on_click = function() View.JumpCameraToEntities(entity) end,
						duration = timeout > 0 and timeout,
					})
				end
			end)
		end
	end,
	make_asm = function(inst)
		return inst.txt or false
	end,
	node_ui = function(canvas, inst, program_ui)
		canvas:Add('<Text x=10 y=50 text="Text:" style=hl/>')
		canvas:Add('<InputText x=10 y=70 margin=2 width=170 height=34 style=hl/>', {
			text = inst.txt,
			on_commit = function(btn, txt)
				if txt and txt == "" then txt = nil end
				if inst.txt == txt then return end
				inst.txt = txt
				program_ui:set_dirty(true)
			end,
		})
		return 64
	end,
	args = {
		{ 'in', "Notify Value", "Notification Value" },
		{ 'in', "Timeout", "Notification Value", 'num', true },
	},
	name = "Notify",
	desc = "Triggers a faction notification",
	category = "Global",
	sample = "V02rugD00ZsUA21cKTA34kYhJ1rBwi41rBxFC07Fz2w28CU1P0as2O11rBwhY1rBxFC28EzzP22WKBc2Dq0xw00UuuY01S",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
	explain = [[Shows an in-game notification with the specified register and some text.

<img image="Main/textures/behaviors/notify_image.png"/>

If the <hl>Notify Value</> passed is a unit then clicking on the notification will jump the camera to that unit.]],
}

data.instructions.get_resource_item =
{
	func = function(comp, state, cause, res_node, res_item, exec_notresource)
		local node = GetEntity(comp, state, res_node)
		if not node or not IsResource(node) then
			Set(comp, state, res_item)
			state.counter = exec_notresource
			return
		end
		Set(comp, state, res_item, { id = GetResourceHarvestItemId(node) } )
	end,
	args = {
		{ 'in', "Resource Deposit", "Resource Deposit", 'entity' },
		{ 'out', "Resource", "Resource Type" },
		{ 'exec', "Not Resource", "Continue here if it wasn't a resource deposit" },
	},
	name = "Resource Type",
	desc = "Gets the resource type from a resource deposit",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
	explain = [[Returns the resource type from the resource deposit. Diverts logic if the passed variable isn't a resource deposit.]],
}

data.instructions.gettrust =
{
	func = function(comp, state, cause, if_ally, if_neutral, if_enemy, target)
		if target then
			local target_entity = GetEntity(comp, state, target)
			if target_entity and target_entity.exists then
				local trust = target_entity.faction:GetTrust(comp.faction)
				if trust == "ALLY" then state.counter = if_ally
				elseif trust == "ENEMY" then state.counter = if_enemy
				elseif trust == "NEUTRAL" then state.counter = if_neutral
				end
			end
		end
	end,
	exec_arg = { 1, "No Unit", "No Unit Passed" },
	args = {
		{ 'exec', "Ally", "Target unit considers you an ally" },
		{ 'exec', "Neutral", "Target unit considers you neutral" },
		{ 'exec', "Enemy", "Target unit considers you an enemy" },
		{ 'in', "Unit", "Target Unit", 'entity' },
	},
	name = "Get Trust",
	desc = "Gets the trust level of the unit towards you",
	category = "Global",
	icon = "Main/skin/Icons/Common/56x56/Question.png",
	explain = [[Returns the trust of the unit passed towards your own faction and diverts logic according to the result.]],
}

data.instructions.gethome =
{
	func = function(comp, state, cause, result)
		Set(comp, state, result, { entity = comp.faction.home_entity })
	end,
	args = {
		{ 'out', "Result", "Factions home unit" },
	},
	name = "Get Home",
	desc = "Gets the factions home unit",
	category = "Global",
	icon = "Main/skin/Icons/Common/56x56/Question.png",
	explain = [[Returns the designated home or base location of the unit.]],
}

data.instructions.ping =
{
	func = function(comp, state, cause, target_entity_id)
		local target = Get(comp, state, target_entity_id)
		local coord = target.entity and comp.faction:IsSeen(target.entity) and target.entity.location or target.coord
		if coord then
			comp.faction:RunUI(function()
				View.PlayEffect("fx_ping", coord.x, coord.y)
				local minimap = UI.FindWidgetWithTag("Minimap")
				if minimap then minimap:AddPing(coord.x, coord.y, "ui_light", 500) end -- just show for 500 ms
			end)
		end
	end,
	args = {
		{ 'in', "Target", "Target unit", 'entity' },
	},
	name = "Ping",
	desc = "Plays the Ping effect and notifies other players playing in the same faction",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
	sample = "V02rugE1CW6YQ1rAMqo34kZAG1kNZqx1sI96h00UuuY0FuEN730UuGE1tR5zU00UuuY016",
	explain = [[Sends a ping signal to a coordinate or unit and a notification to all players in the faction. Can only be seen by the current faction.]],
}

local function build_produce_ui(canvas, inst, program_ui, op)
	local inst_def = data.instructions[op]
	canvas:Add('<Text halign=fill y=40 textalign=center style=hl/>').text = (inst_def.produce_type)
	local inst_library_id = inst.bp
	local library_item = inst_library_id and program_ui.library[inst_library_id]
	local inst_frame_id = library_item and library_item.frame or inst.frame
	local frame_def = inst_frame_id and data.frames[inst_frame_id]
	local frame_name = frame_def and (library_item and library_item.name and NOLOC(library_item.name) or frame_def.name or "Unnamed")
	local show_name = library_item and (library_item.name or (library_item.multi and "New Multi Blueprint" or "New Blueprint")) or frame_name or "Unnamed"
	if library_item or frame_def then canvas:Add('<Text halign=fill y=64 textalign=center margin_left=4 margin_right=4 clip=true/>', { text = show_name, tooltip = DefinitionTooltip(library_item or frame_def) }) end
	local popup_layout = inst_def.produce_type == "Building"
		and "<Box padding=5><BuildView on_select={on_select} library={library}/></Box>"
		or "<Box padding=5><SimpleRegisterSelection width=626 max_height=536 on_select_id={on_select_id} def_filter={bot_def_filter} is_production=true library={library}/></Box>"
	canvas:Add('<Button halign=fill y=88 margin_left=10 margin_right=10/>', {
		text = L("Select %s", inst_def.produce_type),
		on_click = function(btn)
			UI.MenuPopup(popup_layout, {
				library = program_ui.library,
				inst = inst,
				on_select_id = function(menu, regsel, id, library_id)
					menu:on_select(nil, library_id, not library_id and id)
				end,
				on_select = function(menu, buildview, library_id, frame_id)
					local ins, was_changed = menu.inst
					if library_id then
						was_changed = ins.bp ~= library_id or ins.frame ~= nil
						ins.bp, ins.frame = library_id, nil
						local bp = was_changed and program_ui.library[library_id]
						if bp and bp.params then
							local argc = (inst_def.args and #inst_def.args or 0)
							for i,entry in ipairs(bp.params) do
								if not ins[argc+i] and entry[2] then ins[argc+i] = Tool.Copy(entry[2]) end
							end
						end
					elseif frame_id then
						was_changed = ins.frame ~= frame_id or ins.bp ~= nil
						ins.frame, ins.bp = frame_id, nil
					end
					UI.CloseMenuPopup()
					if was_changed then program_ui:Refresh() end
				end,
				bot_def_filter = function(def)
					return def.movement_speed or (def.frame and data.frames[def.frame].movement_speed)
				end,
			}, btn)
		end,
	})
	return 80
end

local function build_produce_var_args(inst, code, library)
	local inst_library_id = inst.bp
	local library_item = inst_library_id and library and library[inst_library_id]
	local params = library_item and library_item.params
	if not params then return end
	local res = {}
	for _,entry in ipairs(params) do
		res[#res+1] = false -- input
		res[#res+1] = entry[1]
	end
	return res
end

local function build_produce_setup_bp(comp, state, ...)
	local inst, faction = GetSourceNode(state), comp.faction
	local faction_library_id, faction_library = inst.bp, faction.extra_data.library
	local bp = faction_library_id and faction_library and faction_library[faction_library_id]
	local frame_id = bp and bp.frame or inst.frame
	if not frame_id then return end
	if bp and not BlueprintIsCustomized(bp) then bp = nil end
	if bp and not FactionHasUnlockedCustomBlueprint(faction, bp) then return end
	if bp then bp = ProcessLibraryBlueprint(bp) end -- returns copy
	if bp and bp.params then
		local param_vals = {...}
		for i,v in ipairs(param_vals) do
			local val = v and Get(comp, state, v)
			val = val and { id = val.id, entity = val.entity, coord = val.coord, num = val.num }
			if not val or not next(val) then val = false elseif val.num == 0 and (val.id or val.entity or val.coord) then val.num = nil end
			param_vals[i] = val
		end
		SetLibraryBlueprintParams(bp, param_vals)
	end
	if not bp and not faction:IsUnlocked(frame_id) then return end
	return frame_id, bp, faction
end

data.instructions.build =
{
	func = function(comp, state, cause, in_location, in_rotation, on_failed, ...)
		local frame_id, bp, faction = build_produce_setup_bp(comp, state, ...)
		if not frame_id then state.counter = on_failed return end

		local location, rotation = GetCoord(comp, state, in_location), GetNum(comp, state, in_rotation)
		local loc = location or comp.owner.location
		local x, y = loc.x, loc.y
		if not faction:IsVisible(x, y) or not faction:CanPlace(frame_id, x, y, rotation, true) then state.counter = on_failed return end

		Map.Defer(function()
			local e = CreateConstructionSite(faction, frame_id, x, y, rotation)
			if bp then e.extra_data.custom_blueprint = bp end
		end)
	end,
	args = {
		{ 'in', "Coordinate", "Target location, or at currently location if not specified", 'coord', true },
		{ 'in', "Rotation", "Building Rotation (0 to 3) (default 0)", 'posnum', true },
		{ 'exec', "Construction Failed", "Where to continue if construction fails" },
	},
	name = "Place Construction",
	desc = "Places a construction site for a specific structure",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	node_ui = build_produce_ui,
	var_args = build_produce_var_args,
	produce_type = "Building",
	explain = [[Begins construction of a specified building or structure at the target location. Logic can be diverted if creation of the construction fails.]],
}

data.instructions.produce =
{
	func = function(comp, state, cause, ...)
		local frame_id, bp = build_produce_setup_bp(comp, state, ...)
		if not frame_id then return end

		local frame_def = data.frames[frame_id]
		local production_recipe = frame_def and frame_def.production_recipe
		if not production_recipe or not production_recipe.producers then return end

		local owner = comp.owner
		for k,v in SortedPairs(production_recipe.producers) do
			local prodcomp = owner:FindComponent(k)
			if prodcomp then
				prodcomp:SetRegister(1, { id = frame_id, num = 1 })
				if bp then
					prodcomp.extra_data.custom_blueprint = bp
				elseif prodcomp.has_extra_data then
					local ed = prodcomp.extra_data
					ed.custom_blueprint = nil
					if not next(ed) then comp.extra_data = nil end
				end
				return
			end
		end
	end,
	name = "Produce Unit",
	desc = "Sets a production component to produce a blueprint",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	node_ui = build_produce_ui,
	var_args = build_produce_var_args,
	produce_type = "Unit",
	explain = [[Begins production of a specified item using available ingredients.]],
}

data.instructions.set_signpost =
{
	func = function(comp, state, cause, txt)
		comp.owner.extra_data.signpost = txt
	end,
	make_asm = function(inst)
		return inst.txt or false
	end,
	name = "Set Signpost",
	desc = "Set the signpost to specific text",
	category = "Component",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
	node_ui = function(canvas, inst, program_ui)
		canvas:Add('<Text x=10 y=50 text="Text:" style=hl/>')
		canvas:Add('<InputText x=10 y=70 margin=2 width=170 height=34 style=hl/>', {
			text = inst.txt,
			on_commit = function(btn, txt)
				if txt and txt == "" then txt = nil end
				if inst.txt == txt then return end
				inst.txt = txt
				program_ui:set_dirty(true)
			end,
		})
		return 64
	end,
	explain = [[Sets a visible marker or label at a location for guidance.]],
}

data.instructions.activate =
{
	func = function(comp, state, cause, exec_failed)
		for _,activate_comp in ipairs(comp.owner.components) do
			local activate_comp_def = activate_comp.def
			local behavior_activate = activate_comp_def.behavior_activate
			if behavior_activate then
				if not behavior_activate(activate_comp_def, activate_comp, comp) then state.counter = exec_failed end
				return
			end
		end
		state.counter = exec_failed
	end,
	args = {
		{ 'exec', "Failed", "Failed" },
	},
	name = "Activate",
	desc = "Activate",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.launch =
{
	func = function(comp, state, cause)
		for _,activate_comp in ipairs(comp.owner.components) do
			local activate_comp_def = activate_comp.def
			local behavior_activate = activate_comp_def.behavior_activate
			if behavior_activate == data.components.c_satellite_launcher.behavior_activate or behavior_activate == data.components.c_mothership_eject.behavior_activate then
				behavior_activate(activate_comp_def, activate_comp, comp)
				return
			end
		end
	end,
	name = "Launch",
	desc = "Launches a satellite if executed on an AMAC or a Drop Pod to the planet if executed on the Mothership",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Launches a unit, such as a drone or rocket, from its current position if equipped on an appropriate launcher.]],
}

data.instructions.abort_construction =
{
	func = function(comp, state, cause, target_entity)
		local entity = GetEntity(comp, state, target_entity)
		if entity and IsConstruction(entity) and entity.faction == comp.faction then
			Map.Defer(function()
				if entity.exists then entity:Destroy() end
			end)
		end
	end,
	args = {
		{ 'in', "Target", "Target Construction", 'entity' },
	},
	name = "Abort Construction",
	desc = "Abort an owned construction",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Aborts the construction of a structure or unit, dropping any delivered ingredients to the ground.

Note: Units that became construction sites using the Edit feature will be deconstructed and not cancelled.]],
}

data.instructions.lookat =
{
	func = function(comp, state, cause, target_entity_coord)
		local target = Get(comp, state, target_entity_coord)
		target = target and target.entity or target.coord
		if not target then return end
		comp.owner:LookAt(target)
	end,
	args = {
		{ 'in', "Target", "Target unit or coordinate", 'coord' },
	},
	name = "Look At",
	desc = "Turns the unit to look at a unit or a coordinate",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
	explain = [[Rotates the unit to face a specific target or coordinate.]],
}

data.instructions.land =
{
	func = function(comp, state, cause)
		local sat = comp.owner:FindComponent("c_satellite")
		if sat then
			EntityAction.LandSatellite(comp.owner)
		end
	end,
	name = "Land",
	desc = "Tells a satellite that has been launched to land",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	explain = [[Lands a satellite to the unit that launched it. Should the original launching location no longer exist, will try to land at another vacant location if one exists.]],
}


--------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
data.instructions.debug_print =
{
	func = function(comp, state, cause, notify_value)
		local reg = Get(comp, state, notify_value)

		--comp.faction:RunUI("OnReceivedChat", { player_id = "DebugPrint", txt = "id: " .. (reg.id or "nil") .. ", num : " .. (reg.num or 0)})
		print("[DEBUGPRINT]", reg)
	end,
	args = { { 'in', "Print Value", "Notification Value" } },
	name = "DebugPrint",
	desc = "Debug print to log",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
	explain = [[Outputs a debug message for developers during behavior execution.]],
}

--------------------------------------------------------------------------------------------------------------------------
--------------------------------------- AUTO BASE ------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
local function AutoBaseResetLogistics(e, high_prio)
	e.disconnected, e.logistics_channel_1, e.logistics_supplier, e.logistics_requester, e.logistics_carrier, e.logistics_crane_only, e.logistics_flying_only, e.logistics_transport_route, e.logistics_high_priority =
		false, true, true, true, true, false, false, false, high_prio or false
end

local function AutoBaseSendMiner(owner, miner, id, node, amount)
	--print("[AUTO BASE] Send miner to get "..(amount or "infinite").." of "..id)
	if miner:GetRegisterId(1) == id and miner:GetRegisterNum(1) == (amount or REG_INFINITE) and miner.is_working then return end
	miner:SetRegister(1, { entity = node, amount = (amount or REG_INFINITE) })
	local freeslot = not miner.owner:HaveFreeSpace(id) and miner.owner:GetSlot(1)
	if freeslot and freeslot.unreserved_stack > 0 then
		-- miner has something in the inventory, just give it to the auto base owner
		owner.faction:OrderTransfer(miner.owner, owner, freeslot, true)
	end
end

local function AutoBaseOrderFromStored(ab, owner, target, id, amount)
	if (ab.carriers or 0) < 1 then return end -- no one to deliver
	if not target:GetFreeSlot(id, amount) then return end -- target has no space (avoid OrderTransfer order directly equipping component which would confuse AutoBaseEquip)
	local faction = owner.faction
	local function func(e)
		local slot = e.faction == faction and e:FindSlot(id, amount)
		if not slot then return end
		if faction:OrderTransfer(e, target, id, amount, true) then return true end
	end
	if (ab.stored[id] or 0) >= amount and Map.FindClosestEntity(owner, ab.range, func, FF_OPERATING) then
		return true -- found in stored
	elseif target ~= owner and func(owner) then
		return true -- found in owner
	end
end

local function AutoBaseEquip(ab, owner, e, comp_id, fulfill_func)
	local have = e:FindSlot(comp_id)
	AutoBaseResetLogistics(e)
	if have and have.unreserved_stack > 0 then
		local socket = e:GetFreeSocket(comp_id)
		if not socket then
			for i=1,e.socket_count do if e:CheckSocketSize(comp_id, i) and e:GetComponent(i).base_id ~= "c_behavior" then socket = i break end end
			if not socket then print("[AUTO BASE] Unable to equip "..comp_id.." on ", e) return end
		end
		Map.Defer(function() EntityAction.InvToComp(e, { slot = have, comp_index = socket }) end)
		return 1 -- equipped successfully
	elseif have and have.has_order and have.reserved_space > 0 then
		return 3 -- waiting for incoming order
	end

	local time = fulfill_func and fulfill_func(ab, owner, comp_id, 1)
	if time then return time end -- waiting for fulfillment

	return AutoBaseOrderFromStored(ab, owner, e, comp_id, 1) and 3 -- waiting for new incoming order
end

local function AutoBaseFulfill(ab, owner, id, amount, recursiveness, ignore_stored)
	--print("[AUTO BASE] Need "..amount.." of "..id.." (producers: "..(ab.producers[id] or 0)..", stored: "..(ab.stored[id] or 0)..", held: "..(owner:CountItem(id) or 0)..")")
	if (ab.producers[id] or 0) > 0 then return end -- it's being made somewhere
	local miss = amount - (not ignore_stored and ab.stored[id] or 0)
	if miss <= 0 then return end
	miss = miss - owner:CountItem(id)
	if miss <= 0 then return end

	local need_def = data.all[id]
	local need_recipe = need_def and need_def.production_recipe
	if not need_recipe and need_def and need_def.mining_recipe then return true end -- special case handled outside
	if not need_recipe or not need_recipe.producers or not need_recipe.ingredients then
		print("[AUTO BASE] Stuck while needing "..id.." but don't know its recipe")
		return
	end

	local mine_id, mine_amount
	for ing_id, ing_amount in SortedPairs(need_recipe.ingredients) do
		local time = AutoBaseFulfill(ab, owner, ing_id, miss * ing_amount, (recursiveness or 0) + 1)
		if time then
			if time ~= true then return time end
			mine_id, mine_amount = ing_id, miss * ing_amount
		end
	end

	local time, first_researched_prod_comp_id
	for comp_id,prod_time in SortedPairs(need_recipe.producers) do
		local prod = owner:FindComponent(comp_id)
		if prod then
			if prod:GetRegisterId(1) == id and prod:GetRegisterNum(1) == miss then
				--print("[AUTO BASE] Already making "..miss.." of "..id.." with producer "..comp_id)
				time = ((miss > 1 or not prod.is_working) and prod_time or 2)
				break
			end
			--print("[AUTO BASE] Making "..miss.." of "..id.." with producer "..comp_id)
			prod:SetRegister(1, { id = id, num = miss })
			time = prod_time -- started local work on something needed
			break
		end

		time = AutoBaseEquip(ab, owner, owner, comp_id)
		if time then break end -- waiting for incoming order/equipping

		first_researched_prod_comp_id = first_researched_prod_comp_id or (owner.faction:IsUnlocked(comp_id) and comp_id)
	end
	if first_researched_prod_comp_id and not time and (not recursiveness or recursiveness <= 20) then
		time = AutoBaseFulfill(ab, owner, first_researched_prod_comp_id, 1, (recursiveness or 0) + 1, true)
		if not time and not recursiveness then print("[AUTO BASE] Stuck while needing "..miss.." of "..id.." but don't have means to produce it") end
	end

	-- Need to send the miner last in this function so it happens only for the most urgently required material
	if mine_id and ((ab.miners[mine_id] or 0) == 0 or ab.carriers == 0) and (ab.temp_miner or ab.working_miner or ab.free_miner) then
		local mine_node = ab.nodes[mine_id]
		if mine_node then
			AutoBaseSendMiner(owner, ab.temp_miner or ab.working_miner or ab.free_miner, mine_id, mine_node, mine_amount)
			local mining_recipe = data.items[mine_id].mining_recipe
			local mining_time = mining_recipe and mining_recipe[(ab.temp_miner or ab.working_miner or ab.free_miner).id]
			if mining_time then time = (time or 0) + mining_time * mine_amount end
			ab.temp_miner, ab.working_miner, ab.free_miner = nil, nil, nil -- in use
		end
	end

	return time
end

data.instructions.gather_information =
{
	func = function(comp, state, cause, range)
		--print("[AUTO BASE] --------------------------------------------------------------------------------------------------")
		if comp.def.key ~= "autobase" then return end -- running autobase behavior on regular behavior component
		local ab = state.autobase
		if not ab then ab = {} state.autobase = ab end
		ab.carriers = 0
		ab.free_socket_bot = nil
		ab.miners = ab.miners or {}
		ab.nodes = ab.nodes or {}
		ab.working_miner = nil
		ab.free_miner = nil
		ab.temp_miner = nil
		ab.turret_bots = 0
		ab.producers = ab.producers or {}
		ab.free_producers = ab.free_producers or {}
		ab.free_building = nil
		ab.stored = ab.stored or {}
		ab.construction_need = nil
		ab.construction_exists = false

		ab.registered = {}

		local range = GetNum(comp, state, range)
		if range <= 0 then range = 15 end
		ab.range = range

		-- reuse tables and arrays for performance
		for k in next, ab.producers do ab.producers[k] = 0 end
		for k in next, ab.miners do ab.miners[k] = 0 end
		for k in next, ab.nodes do ab.nodes[k] = nil end
		for k in next, ab.free_producers do ab.free_producers[k] = nil end
		for k in next, ab.stored do ab.stored[k] = 0 end

		local owner = comp.owner
		local faction, power_grid_index = owner.faction, owner.power_grid_index
		Map.FindClosestEntity(owner, range, function(e)
			if e.faction ~= faction then
				if IsResource(e) and faction:GetPowerGridIndexAt(e) == power_grid_index then
					local id = GetResourceHarvestItemId(e)
					if id and not ab.nodes[id]then ab.nodes[id] = e end
				end
			elseif e.power_grid_index ~= power_grid_index and (e.powered_down or faction:GetPowerGridIndexAt(e) ~= power_grid_index) then
				-- ignore powered down units and units outside of power grid
			elseif IsBot(e) then
				local miner = e:FindComponent("c_miner", true)
				local turret = not miner and e:FindComponent("c_turret", true)
				if miner then
					local miner_id, miner_num = miner:GetRegisterId(1), miner:GetRegisterNum(1)
					local miner_entity = not miner_id and miner:GetRegisterEntity(1)
					if miner_entity then miner_id = GetResourceHarvestItemId(miner_entity) end
					if miner_id and (e.is_moving or miner.is_working or e:CountItem(miner_id) > 0) then
						if miner_num <= 0 then -- only count infinite mining
							ab.miners[miner_id] = (ab.miners[miner_id] or 0) + 1
						else
							ab.temp_miner = ab.temp_miner or miner
						end
						ab.working_miner = ab.working_miner or miner
					else ab.free_miner = ab.free_miner or miner end
				elseif turret then
					ab.turret_bots = ab.turret_bots + 1
				elseif e.id == "f_carrier_bot" then
					ab.carriers = ab.carriers + 1
				else
					if (not ab.free_socket_bot or ab.free_socket_bot.key < e.key) and e:GetFreeSocket("c_miner") then ab.free_socket_bot = e end
				end
			elseif IsConstruction(e) then
				if e.powered_down then e.powered_down = false end
				ab.construction_need = ab.construction_need or e:GetRegister(FRAMEREG_SIGNAL)
				ab.construction_exists = true
			elseif e.slot_count > 0 and e.id ~= "f_building_sim" then
				local fab = e:FindComponent("c_fabricator", true)
				if fab then
					local fab_id = fab:GetRegisterId(1)
					if fab_id then
						ab.producers[fab_id] = (ab.producers[fab_id] or 0) + 1
					elseif not (e.has_extra_data and e.extra_data.autobase_register) then
						ab.free_producers[#ab.free_producers + 1] = fab
					end
				elseif not (e.has_extra_data and e.extra_data.autobase_register) then
					ab.free_building = ab.free_building or e
				end
				for _,slot in ipairs(e.slots) do
					local item_id = slot.id
					local item_available = item_id and slot.unreserved_stack
					if item_available and item_available > 0 then ab.stored[item_id] = (ab.stored[item_id] or 0) + item_available end
				end
			end
		end)

		for _,e in ipairs(comp.faction.entities) do
			-- check register
			local abreg = e.has_extra_data and e.extra_data.autobase_register
			if abreg then ab.registered[abreg] = (ab.registered[abreg] or 0) + 1 end
		end

		--local enemy
		-- loop signal registers
		for _,e in ipairs(comp.faction:GetEntitiesWithRegister(FRAMEREG_SIGNAL, true)) do
			local signal_entity = e:GetRegisterEntity(FRAMEREG_SIGNAL)
			if signal_entity then
				-- add signaled resources
				if IsResource(signal_entity) then
					if faction:GetPowerGridIndexAt(signal_entity) == power_grid_index then
						local id = GetResourceHarvestItemId(e)
						if id and not ab.nodes[id]then ab.nodes[id] = e end
					end
				--elseif not enemy and faction:GetTrust(signal_entity) == "ENEMY" then
				--	enemy = signal_entity
				end
			end
		end
	end,

	args = {
		{ 'in', "Range", "Range of operation", 'posnum' },
	},
	name = "Gather Information",
	desc = "Collect information for running the auto base controller",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
	explain = [[Scans the surrounding area or unit to gather intelligence.]],
}

data.instructions.get_registered =
{
	func = function(comp, state, cause, in_id, out_value)
		local ab = state.autobase
		if not ab then return end
		local id = GetId(comp, state, in_id)
		if id and ab.registered[id] then
			Set(comp, state, out_value, { id = id, num = ab.registered[id]})
			return
		end
		Set(comp, state, out_value)
	end,
	args = {
		{ 'in', "Id", "Id to get register of" },
		{ 'out', "Value", "Value of registered Unit" },
	},
	name = "Get Registered",
	desc = "Get number of registered buildings",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
	explain = [[Retrieves the most recently registered value.]],
}

data.instructions.make_carrier =
{
	func = function(comp, state, cause, frame_num, on_work)
		local ab = state.autobase
		if not ab then return end

		local frame_num = Get(comp, state, frame_num)
		if ab.carriers >= frame_num.num then return end
		local sleep = AutoBaseFulfill(ab, comp.owner, frame_num.id, 1) or 3

		comp:SetStateSleep(sleep)
		state.counter = on_work
		return true
	end,
	args = {
		{ 'in', "Carriers", "Type and count of carriers to make", "frame_num" },
		{ 'exec', "If Working", "Where to continue if the unit started working" },
	},
	name = "Make Carriers",
	desc = "Construct carrier bots for delivering orders or to use for other tasks",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
	explain = [[Creates carrier bots for transporting goods.]],
}

data.instructions.make_miner =
{
	func = function(comp, state, cause, resource_num, frameid, on_work)
		local ab = state.autobase
		if not ab then return end

		local item_id = GetId(comp, state, resource_num)
		if not item_id or (ab.miners[item_id] or 0) >= GetNum(comp, state, resource_num) then return end
		if not ab.nodes[item_id] then return end

		local sleep = 3
		if ab.free_miner or ab.temp_miner then
			if ab.temp_miner then
				ab.temp_miner:SetRegister(1, nil)
				ab.free_miner, ab.temp_miner = ab.free_miner or ab.temp_miner, nil
			end
			AutoBaseSendMiner(comp.owner, ab.free_miner, item_id, ab.nodes[item_id])
		else
			if not ab.free_socket_bot or not ab.free_socket_bot.exists then
				local frameid = GetId(comp, state, frameid)
				sleep = AutoBaseFulfill(ab, comp.owner, frameid, 1) or 3
			else
				sleep = AutoBaseEquip(ab, comp.owner, ab.free_socket_bot, "c_miner", AutoBaseFulfill) or 5
			end
		end

		comp:SetStateSleep(sleep)
		state.counter = on_work
		return true
	end,
	args = {
		{ 'in', "Resource/Count", "Resource type and number of miners to maintain", 'item_num' },
		{ 'in', "Frame", "Unit to create if none are free", 'frame' },
		{ 'exec', "If Working", "Where to continue if the unit started working" },
	},
	name = "Make Miners",
	desc = "Construct and equip miner components on available carrier bots",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
	explain = [[Creates miner bots capable of extracting resources.]],
}

data.instructions.serve_construction =
{
	func = function(comp, state, cause, on_work)
		local ab = state.autobase
		if not ab then return end

		if not ab.construction_need then
			if ab.construction_exists then
				comp:SetStateSleep(1)
				state.counter = on_work
			else
				return
			end
		end
		local sleep = ab.construction_need.id and AutoBaseFulfill(ab, comp.owner, ab.construction_need.id, ab.construction_need.num) or 3
		comp:SetStateSleep(sleep)
		state.counter = on_work
		return true
	end,
	args = { { 'exec', "If Working", "Where to continue if the unit started working" }, },
	name = "Serve Construction",
	desc = "Produce materials needed in construction sites",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
	explain = [[Assigns the unit to serve at a nearby construction site.]],
}

data.instructions.make_producer =
{
	func = function(comp, state, cause, item_num, prodcomp_id, frame_id, offset, on_work)
		local ab = state.autobase
		if not ab then return end

		local item_id = GetId(comp, state, item_num)
		if not item_id or (ab.producers[item_id] or 0) >= GetNum(comp, state, item_num) then return end

		local prodcomp_id = GetId(comp, state, prodcomp_id)
		for i,fab in ipairs(ab.free_producers) do
			if fab.id == prodcomp_id then
				local producer = table.remove(ab.free_producers, i)
				producer:SetRegister(1, { id = item_id, num = REG_INFINITE })
				ab.producers[item_id] = (ab.producers[item_id] or 0) + 1

				-- lock dedicated producers to 1 stack
				local ingredients = data.all[item_id].production_recipe.ingredients
				local count = 1
				for _,_ in pairs(ingredients) do
					count = count + 1
				end
				for i,slot in ipairs(producer.owner.slots) do
					if i > count then slot.locked = true end
				end

				comp:SetStateSleep(1)
				state.counter = on_work
				return true
			end
		end

		local owner, faction = comp.owner, comp.faction
		local building = ab.free_building and Map.FindClosestEntity(owner, ab.range, function(e)
			if e.faction ~= faction or not IsBuilding(e) or (e.has_extra_data and e.extra_data.autobase_register) then return end
			if e:GetFreeSocket(prodcomp_id) then return true end
			local prod = e:FindComponent(prodcomp_id)
			local prod = prod and prod:GetRegister(1)
			return  prod and prod.is_empty
		end, FF_OPERATING)

		local sleep
		if building then
			sleep = AutoBaseEquip(ab, owner, building, prodcomp_id, AutoBaseFulfill) or 5
		else
			local loc = owner.location
			local offset = GetCoord(comp, state, offset)
			local frame_id = GetId(comp, state, frame_id)
			if not offset or not frame_id then return end
			Map.Defer(function()
				local place_x, place_y = comp.faction:GetPlaceableLocation(frame_id, loc.x + offset.x, loc.y + offset.y, true)
				CreateConstructionSite(comp.faction, frame_id, place_x, place_y).logistics_high_priority = true
			end)
			sleep = 5
		end

		comp:SetStateSleep(sleep)
		state.counter = on_work
		return true
	end,
	args = {
		{ 'in', "Item/Count", "Item type and number of producers to maintain", 'item_num' },
		{ 'in', "Component", "Production component", "comp" },
		{ 'in', "Building", "Building type to use as producer", 'frame' },
		{ 'in', "Location", "Location offset from self", 'coord' },
		{ 'exec', "If Working", "Where to continue if the unit started working" },
	},
	name = "Make Producer",
	desc = "Build and maintain dedicated production buildings",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
	explain = [[Converts the unit into a production facility for crafting items.]],
}

data.instructions.make_turret_bots =
{
	func = function(comp, state, cause, frame_num, on_work)
		local ab = state.autobase
		if not ab then return end

		if ab.turret_bots >= GetNum(comp, state, frame_num) then return end

		local sleep = 3
		if not ab.free_socket_bot or not ab.free_socket_bot.exists then
			local frameid = GetId(comp, state, frame_num)
			sleep = AutoBaseFulfill(ab, comp.owner, frameid, 1) or 3
		else
			sleep = AutoBaseEquip(ab, comp.owner, ab.free_socket_bot, "c_portable_turret", AutoBaseFulfill) or 5
		end
		comp:SetStateSleep(sleep)
		state.counter = on_work
		return true
	end,
	args = {
		{ 'in', "Number", "Number of turret bots to maintain" },
		{ 'exec', "If Working", "Where to continue if the unit started working" },
	},
	name = "Make Turret Bots",
	desc = "Construct and equip turret components on available carrier bots",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
	explain = [[Creates turret bots for defense or attack purposes.]],
}

data.instructions.set_reg_remotely =
{
	func = function(comp, state, cause, in_unit, value, to, group_index, exec_fail)
		local ent = GetAdjacentFactionEntityOrSelf(comp, state, in_unit)
		if not ent then if exec_fail then state.counter = exec_fail end return end

		to = Get(comp, state, to)
		local to_id, to_num = to.id, math.max(to.num, 1)
		local to_comp = to_id and GetComponentFromSortedGroupIndex(comp, state, to_id, group_index, ent)
		if to_comp then
			if to_num > to_comp.register_count then return end
			local register_defs = to_comp.def.registers
			local register_def = register_defs and register_defs[to_num]
			if register_def and register_def.read_only then return end
			to_comp:SetRegister(to_num, Get(comp, state, value))
		elseif not to_id then
			if to_num > 4 then to_num = 4 end
			ent:SetRegister(5-to_num, Get(comp, state, value))
		end
	end,
	args = {
		{ 'in', "Unit", "The unit to set component register on (if not self)", 'entity' },
		{ 'in', "Value", "Value to set remotely", 'any' },
		{ 'in', "To", "Component and register number to set", 'comp_num' },
		{ 'in', "Component Index", "Component index if multiple are equipped", 'posnum', true },
		{ 'exec',"Failed", "Failed to set register", nil, true },
	},
	name = "Set to Component Remotely",
	desc = "Writes a value into a component register on an external unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Set Component Reg.png",
	explain = [[Remotely set an external unit's component register to a value. Diverts logic if instruction fails.

The source and target units <bl>must be adjacent</> unless running on an <img id="c_autobase" style="hl"/>.]],
}

data.instructions.get_reg_remotely =
{
	func = function(comp, state, cause, in_unit, from, value, group_index, exec_fail)
		local ent = GetAdjacentFactionEntityOrSelf(comp, state, in_unit)
		if not ent then if exec_fail then state.counter = exec_fail end return end

		from = Get(comp, state, from)
		local from_id, from_num = from.id, math.max(from.num, 1)
		local from_comp = from_id and GetComponentFromSortedGroupIndex(comp, state, from_id, group_index, ent)
		if from_comp then
			Set(comp, state, value, from_comp:GetRegister(from_num))
		elseif not from_id then
			if from_num > 4 then from_num = 4 end
			Set(comp, state, value, ent:GetRegister(5-from_num))
		end
	end,
	args = {
		{ 'in', "Unit", "The unit to get component register from (if not self)", 'entity' },
		{ 'in', "From", "Component and register number to get remotely", 'comp_num' },
		{ 'out', "Value", "Value of Register"},
		{ 'in', "Component Index", "Component index if multiple are equipped", 'posnum', true },
		{ 'exec',"Failed", "Failed to get register", nil, true },
	},
	name = "Get from Component Remotely",
	desc = "Reads a value from a component register on an external unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Set Component Reg.png",
	explain = [[Remotely read an external unit's component register value. Diverts logic if instruction fails.

The source and target units <bl>must be adjacent</> unless running on an <img id="c_autobase" style="hl"/>.]],
	--key = "autobase",
}

data.instructions.equip_component_remotely =
{
	func = function(comp, state, cause, in_unit, no_comp, equip_comp, equip_index)
		if comp.def.key ~= "autobase" then return end
		local ent = GetAdjacentFactionEntityOrSelf(comp, state, in_unit)
		if not ent then return end -- don't set if a unit is passed but the unit is nil

		local socket
		local num = GetNum(comp, state, equip_index)
		-- if 'equip_index' exists, override and to try equip from index first...
		if num and num > 0 then
			local index_slot = ent.slots[num]
			if index_slot then
				local comp_id = index_slot.id
				if comp_id then
					socket = ent:GetFreeSocket(comp_id)
					if not socket then state.counter = no_comp return end
					if index_slot.unreserved_stack > 0 then
						if comp_id == GetId(comp, state, equip_comp) then
							Map.Defer(function() EntityAction.InvToComp(ent, { slot = index_slot, comp_index = socket }) end)
							return
						end
					end
				end
			end
		end

		-- ... but then if that failed continue on and
		--  try with 'equip_comp' should that value also exist
		local comp_id = GetId(comp, state, equip_comp)
		if not comp_id then state.counter = no_comp return end

		socket = ent:GetFreeSocket(comp_id)
		if not socket then state.counter = no_comp return end

		for _,v in ipairs(ent.slots) do
			if v.id == comp_id and v.unreserved_stack > 0 then
				-- found it.. equip it
				Map.Defer(function() EntityAction.InvToComp(ent, { slot = v, comp_index = socket }) end)
				return
			end
		end
		if no_comp then state.counter = no_comp end
	end,
	args = {
		{ 'in', "Unit", "The unit to equip component on (if not self)", 'entity' },
		{ 'exec', "No Component", "If the unit doesn't hold the requested component" },
		{ 'in', "Component", "Component to equip", "comp" },
		{ 'in', "Slot index", "Individual slot to equip component from", 'posnum', true },
	},
	name = "Equip Component Remotely",
	desc = "Equips a component if it exists in the unit's inventory",
	category = "AutoBase",
	icon = "Main/skin/Icons/Common/56x56/Home.png",
	key = "autobase",
	explain = [[Remotely command an external unit to equip a component from its own inventory. Diverts logic if the component fails to equip.

Note: Both units must be in the same logistics network.]],
}

data.instructions.unequip_component_remotely =
{
	func = function(comp, state, cause, in_unit, no_comp, unequip_comp, unequip_index)
		if comp.def.key ~= "autobase" then return end
		local ent = GetAdjacentFactionEntityOrSelf(comp, state, in_unit)
		if not ent then return end -- don't set if a unit is passed but the unit is nil

		local num = GetNum(comp, state, unequip_index)
		-- if 'unequip_index' exists, override and to try unequip from index
		if num and num > 0 then
			local socket = ent:GetComponent(num)
			if not socket then
				if no_comp then state.counter = no_comp end
				return
			end

			local index_slot = ent:GetFreeSlot(socket.id)
			if index_slot then
				Map.Defer(function() EntityAction.CompToInv(ent, { comp = socket, slot = index_slot }) end)
			end
		else
			local comp_id = GetId(comp, state, unequip_comp)
			if not comp_id then return end

			local found_comp = ent:FindComponent(comp_id)
			if found_comp == nil then
				if no_comp then state.counter = no_comp return end
			end
			if found_comp and found_comp.is_hidden then state.counter = no_comp return end

			local slot = ent:GetFreeSlot(comp_id)
			if slot then
				Map.Defer(function() EntityAction.CompToInv(ent, { comp = found_comp, slot = slot }) end)
			end
		end
	end,
	args = {
		{ 'in', "Unit", "The unit to equip component on (if not self)", 'entity' },
		{ 'exec', "No Component", "If you don't current hold the requested component or slot was empty" },
		{ 'in', "Component", "Component to unequip", "comp" },
		{ 'in', "Slot index", "Individual slot to try to unequip component from", 'posnum', true },
	},
	name = "Unequip Component Remotely",
	desc = "Unequips a component if it exists",
	category = "AutoBase",
	icon = "Main/skin/Icons/Common/56x56/Detach.png",
	key = "autobase",
	explain = [[Remotely command an external unit to unequip a component that it currently has equipped. Diverts logic if the component fails to unequip.

Note: Both units must be in the same logistics network.]],
}

data.instructions.load_behavior =
{
	func = function(comp, state, cause, sub, in_unit, group_index, out_failed, ...)
		if not sub then return end
		local ent = GetAdjacentFactionEntityOrSelf(comp, state, in_unit)
		if not ent then state.counter = out_failed return end

		local behavior_comp = GetComponentFromSortedGroupIndex(comp, state, "c_behavior", group_index, ent, true)
		if not behavior_comp then
			local frame_def = ent.def
			local can_have_integrated_behavior = not frame_def.type and frame_def.race == "robot" and not frame_def.no_integrated_behavior
			if not can_have_integrated_behavior then state.counter = out_failed return end
			local have_integrated_behavior = can_have_integrated_behavior and ent:CountComponents("c_integrated_behavior") > 0
			if have_integrated_behavior then state.counter = out_failed return end
			behavior_comp = ent:AddComponent("c_integrated_behavior")
			if not behavior_comp then state.counter = out_failed return end
		end

		SetBehavior(behavior_comp, sub)

		-- Variable arguments can have a different count if the behavior was since edited, always set all registers to avoid theoretical state discrepancy
		for i=1,behavior_comp.register_count do
			local in_reg = select(i, ...)
			behavior_comp:SetRegister(i, in_reg and Get(comp, state, in_reg) or nil)
		end
	end,
	args = {
		{ 'in', "Unit", "The unit to load the behavior on (if not self)", 'entity' },
		{ 'in', "Component Index", "Component index if multiple are equipped", 'posnum', true },
		{ 'exec', "Failed", "Failed" },
	},
	name = "Load Behavior",
	node_ui = call_ui,
	make_asm = function(inst)
		return inst.sub or false
	end,
	var_args = call_var_args,
	desc = "Load and run a behavior on an external unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Set Component Reg.png",
	explain = [[Remotely run a behavior on another unit. Will automatically install an <img id="c_integrated_behavior" style="hl"/> if needed.

The source and target units <bl>must be adjacent</> unless running on an <img id="c_autobase" style="hl"/>.]],
}

data.instructions.build_registered =
{
	func = function(comp, state, cause, in_location, in_rotation, in_register, on_work, on_failed, ...)
		local ab = state.autobase
		if not ab then return end

		-- should we build this
		local id = GetId(comp, state, in_register)
		local num = GetNum(comp, state, in_register)
		if not id then state.counter = on_failed return end
		local regged = ab.registered[id]
		if regged and regged >= num then
			return
		end

		local frame_id, bp, faction = build_produce_setup_bp(comp, state, ...)
		if not frame_id then state.counter = on_failed return end

		local location, rotation = GetCoord(comp, state, in_location), GetNum(comp, state, in_rotation)
		local loc = comp.owner.location
		local x, y = location.x, location.y
		local place_x, place_y = comp.faction:GetPlaceableLocation(frame_id, loc.x + x, loc.y + y, true)

		--if not faction:CanPlace(frame_id, x, y, rotation, true) then state.counter = on_failed return end

		if not bp then bp = { frame = frame_id } end
		bp.spawn_extra_data = { autobase_register = id }

		Map.Defer(function()
			local e = CreateConstructionSite(faction, frame_id, place_x, place_y, rotation)
			e.extra_data.custom_blueprint = bp
		end)

		comp:SetStateSleep(1)
		state.counter = on_work
		return true
	end,
	args = {
		{ 'in', "Coordinate", "Target location, or at currently location if not specified", 'coord', true },
		{ 'in', "Rotation", "Building Rotation (0 to 3) (default 0)", 'posnum', true },
		{ 'in', "Id", "Id to register with" },
		{ 'exec', "If Working", "Where to continue if the unit started working" },
		{ 'exec', "Construction Failed", "Where to continue if construction fails" },
	},
	name = "Build Registered",
	desc = "Places a building to be registered",
	category = "AutoBase",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	node_ui = build_produce_ui,
	var_args = build_produce_var_args,
	produce_type = "Building",
	key = "autobase",
	explain = [[Constructs a structure or unit defined in a register at a given location or the current location if not specified.]],
}

data.instructions.produce_registered =
{
	func = function(comp, state, cause, in_register, on_work, ...)
		local ab = state.autobase
		if not ab then return end

		-- should we build this
		local id = GetId(comp, state, in_register)
		local num = GetNum(comp, state, in_register)
		--if not id then state.counter = on_failed return end
		local regged = ab.registered[id]
		if regged and regged >= num then
			return
		end

		local frame_id, bp = build_produce_setup_bp(comp, state, ...)
		if not frame_id then return end

		local frame_def = data.frames[frame_id]
		local production_recipe = frame_def and frame_def.production_recipe
		if not production_recipe or not production_recipe.producers then return end

		if not bp then bp = { frame = frame_id } end
		bp.spawn_extra_data = { autobase_register = id }

		local owner = comp.owner
		for k,v in SortedPairs(production_recipe.producers) do
			local prodcomp = owner:FindComponent(k)
			if prodcomp and not prodcomp.is_working and prodcomp:GetRegisterId() == nil then
				prodcomp:SetRegister(1, { id = frame_id, num = 1 })
				prodcomp.extra_data.custom_blueprint = bp
				comp:SetStateSleep(1)
				state.counter = on_work
				return true
			end
		end
		comp:SetStateSleep(1)
		state.counter = on_work
		return true
	end,
	args = {
		{ 'in', "Id", "Id to register with" },
		{ 'exec', "If Working", "Where to continue if the unit started working" },
	},

	name = "Produce Registered Unit",
	desc = "Sets a production component to produce a blueprint",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	node_ui = build_produce_ui,
	var_args = build_produce_var_args,
	produce_type = "Unit",
	key = "autobase",
	explain = [[Produces an item based on the recipe stored in a register.]],
}

Comp:RegisterComponent("c_event_reg", {
	activation = "OnFirstRegisterChange",
	registers = { {} },
	transient = true,
	on_remove = function(self, comp)
		RadioDisconnect(comp, false)
	end,
	on_update = function(self, comp)
		InstTriggerEvent(comp)
	end
})

data.instructions.event_radio =
{
	func = function(comp, state, cause, out_signal)
		-- Shouldn't be called directly, but can if it is the very first instruction
		state.counter = false -- forces restart and calling of c_behavior_on_end
	end,
	node_ui = function(canvas, inst, program_ui)
		local band = inst.band
		canvas:Add('<Text y=40 text="Band" style=hl halign=center/>')
		canvas:Add('<Reg y=60 halign=center/>', {
			def_id = band and band.id, entity = band and band.entity, coord = band and band.coord, num = band and band.num,
			on_click = function(reg)
				local function register_on_set(rsel, val)
					reg.def_id, reg.entity, reg.coord, reg.num = val.id, val.entity, val.coord, val.num
					if not val or not next(val) then val = nil elseif val.num == 0 and (val.id or val.entity or val.coord) then val.num = nil end
					if Tool.Hash(val) ~= Tool.Hash(inst.band) then inst.band = val program_ui:set_dirty(true) end
				end
				local rsel = ShowRegisterSelection(reg, register_on_set, nil, nil, { hide_entity_panel = true })
				if rsel then rsel:SetRegister({ id = reg.def_id, entity = reg.entity, coord = reg.coord, num = reg.num }) end
			end,
		})
		return 64
	end,
	event_setup = function(comp, source_node)
		if not source_node.band then return end
		local ev_comp = comp.owner:AddComponent("c_event_reg")
		RadioConnect(ev_comp, false, Tool.NewRegisterObject(source_node.band))
		return ev_comp
	end,
	event_trigger = function(comp, state, ev_comp, out_signal)
		if out_signal then Set(comp, state, out_signal, ev_comp:GetRegister(1)) end
	end,
	args = {
		{ 'out', "Signal", "Signal value" }
	},
	name = "Radio Event",
	desc = "Run event when the signal of the specified radio band changes its value",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.event_parameter =
{
	func = function(comp, state, cause, out_signal)
		-- Shouldn't be called directly, but can if it is the very first instruction
		state.counter = false -- forces restart and calling of c_behavior_on_end
	end,
	node_ui = function(canvas, inst, program_ui)
		canvas:Add('<Text y=40 text="Parameter" style=hl halign=center/>')
		local txt = canvas:Add('<Text y=60 text="None" halign=center/>')
		local btn = canvas:Add('<Button y=80 text="Select" halign=center/>')
		btn.on_click = function(btn)
			local parameters, pnames = program_ui.code.parameters, program_ui.code.pnames
			local box = UI.MenuPopup("<Box padding=5><VerticalList/></Box>", btn, "DOWN")
			if not box then return end
			for i=1,(parameters and #parameters or 0) do
				box[1]:Add("Button", { text = NOLOC(pnames and pnames[i] or string.format("P%d", i)), on_click = function(b) txt.text = b.text inst.pnum = i program_ui:set_dirty(true) UI.CloseMenuPopup(b) end })
			end
			box[1]:Add("Button", { text = L("- %s -", "None"), on_click = function(b) txt.text = "None" inst.pnum = nil program_ui:set_dirty(true) UI.CloseMenuPopup(b) end })
		end
		local pnum, pnames = inst.pnum, program_ui.code.pnames
		if pnum then txt.text = NOLOC(pnames and pnames[pnum] or string.format("P%d", pnum)) end
		return 64
	end,
	event_setup = function(comp, source_node)
		if not source_node.pnum then return end
		local ev_comp = comp.owner:AddComponent("c_event_reg")
		ev_comp:LinkRegisterFromRegister(1, source_node.pnum, comp)
		return ev_comp
	end,
	args = {},
	name = "Parameter Event",
	desc = "Run event when the value of the specified parameter changes",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.memory_get =
{
	func = function(comp, state, cause, in_index, out_value)
		in_index = Get(comp, state, in_index)
		local key = in_index.id or (in_index.entity and in_index.entity.key) or (in_index.coord and (in_index.coord.x .. ":" .. in_index.coord.y))
		local arrays = state.arrays
		local array = arrays and arrays[key]
		local val
		if array then
			-- get last value if no number is specified (0)
			local num = in_index.num
			val = array[num > 0 and num or #array]
		end
		Set(comp, state, out_value, val)
	end,
	args = {
		{ 'in', "Index", "Array identifier and index" },
		{ 'out', "Value" },
	},
	name = "Memory Get",
	desc = "Get memory array element",
	category = "Memory",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Retrieves a value from a named memory location. If no number index is specified it will get the value of the last element in the array.]],
}

data.instructions.memory_set =
{
	func = function(comp, state, cause, in_index, in_value, out_oldvalue)
		in_index = Get(comp, state, in_index)
		local key = in_index.id or (in_index.entity and in_index.entity.key) or (in_index.coord and (in_index.coord.x .. ":" .. in_index.coord.y))
		if not key then return end

		local arrays = state.arrays
		if not arrays then
			arrays = {}
			state.arrays = arrays
		end

		local array = arrays[key]
		if not array then
			array = {}
			arrays[key] = array
		end

		local num = in_index.num
		local index = num > 0 and num or #array + 1
		Set(comp, state, out_oldvalue, array[index])
		array[index] = Tool.NewRegisterObject(Get(comp, state, in_value))
	end,
	args = {
		{ 'in', "Index", "Array identifier and index" },
		{ 'in', "Value" },
		{ 'out', "Old", "Previous value" }
	},
	name = "Memory Set",
	desc = "Set memory array value at a given index",
	category = "Memory",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Set memory array value at a given index. No index will add a new element to the end of the array (push).]],
}

data.instructions.memory_length =
{
	func = function(comp, state, cause, in_index, out_value)
		in_index = Get(comp, state, in_index)
		local key = in_index.id or (in_index.entity and in_index.entity.key) or (in_index.coord and (in_index.coord.x .. ":" .. in_index.coord.y))
		local arrays = state.arrays
		if key then
			local array = arrays and arrays[key]
			Set(comp, state, out_value, { id = key, num = (array and #array or 0) })
		elseif arrays then
			local arraycount = 0
			for k in next, arrays do arraycount = arraycount + 1 end
			Set(comp, state, out_value, { num = arraycount })
		else
			Set(comp, state, out_value, { num = 0 })
		end
	end,
	args = {
		{ 'in', "Index", "Array identifier" },
		{ 'out', "Value" },
	},
	name = "Memory Length",
	desc = "Get length of memory array",
	category = "Memory",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Retrieves the length of a memory array.

Will return the length of the memory array specified by the <hl>id</> or the total number of created arrays if no <hl>id</> is specified.]],
}

data.instructions.memory_insert =
{
	func = function(comp, state, cause, in_index, in_value)
		in_index = Get(comp, state, in_index)
		local key = in_index.id or (in_index.entity and in_index.entity.key) or (in_index.coord and (in_index.coord.x .. ":" .. in_index.coord.y))
		if not key then return end

		local arrays = state.arrays
		if not arrays then
			arrays = {}
			state.arrays = arrays
		end

		local array = arrays[key]
		if not array then
			array = {}
			arrays[key] = array
		end

		local newval = Tool.NewRegisterObject(Get(comp, state, in_value))
		local index = in_index.num
		local len = #array
		if index <= 0 or index > len then -- insert element at end
			array[len+1] = newval
		else -- insert element in middle (shift upwards)
			table.insert(array, index, newval)
		end
	end,
	args = {
		{ 'in', "Index", "Array identifier and index" },
		{ 'in', "Value", "Value" },
	},
	name = "Memory Insert",
	desc = "Insert value into memory array",
	category = "Memory",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Insert value into memory array, shifting elements above upwards. No index will add a new element to the end of the array (push).]],
}

data.instructions.memory_remove =
{
	func = function(comp, state, cause, in_index, out_oldvalue)
		in_index = Get(comp, state, in_index)
		local key = in_index.id or (in_index.entity and in_index.entity.key) or (in_index.coord and (in_index.coord.x .. ":" .. in_index.coord.y))
		local arrays = state.arrays
		local array = arrays and arrays[key]
		if not array then return end

		local index = in_index.num
		local oldval
		if index == REG_INFINITE then -- clear the array
			arrays[key] = nil
		else
			local len = #array
			if index <= 0 then -- remove last element
				oldval = array[len]
				array[len] = nil
			elseif index < len then -- remove element, shift downwards
				oldval = table.remove(array, index)
			else -- remove last element or element in unsequenced part of the array
				oldval = array[index]
				array[index] = nil
			end

			-- clear if empty
			if not next(array) then arrays[key] = nil end
		end
		Set(comp, state, out_oldvalue, oldval)
	end,
	args = {
		{ 'in', "Index", "Array identifier and index" },
		{ 'out', "Old Value", "Removed value" },
	},
	name = "Memory Remove",
	desc = "Remove value from memory array",
	category = "Memory",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Remove value from a memory array, shifting elements above downwards.
No index will remove from the end of the array (pop).
Specifying ∞ will clear the array.]],
}

data.instructions.memory_loop =
{
	func = function(comp, state, cause, in_index, out_value, exec_done, out_index)
		in_index = Get(comp, state, in_index)
		local key = in_index.id or (in_index.entity and in_index.entity.key) or (in_index.coord and (in_index.coord.x .. ":" .. in_index.coord.y))
		local arrays = state.arrays
		local it
		if not arrays then
			it = {}
		elseif not key then -- loop all keys
			it = {}
			local entities
			for k,v in SortedPairs(arrays) do
				if type(k) == "string" then
					it[#it+1] = k
				else
					if not entities then entities = {} end
					entities[#entities+1] = k
				end
			end
			table.sort(it)
			if entities then
				table.sort(entities)
				for i,v in ipairs(entities) do
					it[#it+1] = v
				end
			end
		elseif arrays[key] then
			it = { key = key, num = 1 }
		else
			it = {}
		end
		return BeginBlock(comp, state, it)
	end,

	next = function(comp, state, it, in_index, out_value, exec_done, out_index)
		local function ParseKey(key, num)
			if type(key) == "string" then
				local x,y = string.match(key, "(%d+):(%d+)")
				if x then
					return { coord = { x//1, y//1}, num = num }
				else
					return { id = key, num = num }
				end
			else
				return { entity = Map.GetEntityFromKey(key), num = num }
			end
		end
		local key = it.key
		local num = it.num or 1
		local val

		if key then -- iterating array
			local array = state.arrays[key]
			val = array and array[num]
			if val == nil then return true end
			if out_index then
				Set(comp, state, out_index, ParseKey(key, num))
			end
		else -- iterating keys
			val = it[num]
			if val == nil then return true end
			val = ParseKey(val)
		end
		Set(comp, state, out_value, val)
		it.num = num + 1
	end,

	last = function(comp, state, it, in_index, out_value, exec_done, out_index)
		state.counter = exec_done
	end,

	args = {
		{ 'in', "Id", "Array identifier or empty to loop through known identifiers" },
		{ 'out', "Value" },
		{ 'exec', "Done", "Finished loop" },
		{ 'out', "Index", nil, nil, true },
	},
	name = "Loop Memory",
	desc = "Loops through memory array or known array identifiers",
	category = "Memory",
	sample = "5V3YxVw83JETKb3V8u6o0iV6Ya3Jm0vf25wHsQ1DnjVG1EhaLv1NUYvM1MDB7y1AtPzc1Mr8XB36hwCE2jUAWn1Pi73B2dYEbz3zcrTB0oLJd328jlrA3ka87s3r89zO3Ixrjo3pwI720c9HSy0VNcd40bClk31dWIL81s8Y3S00Jq0Y0yAVfc3mu",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
	explain = [[Loops through all entries stored in a memory list

If an <hl>id</> is specified then it will enumerate all sequential values of that id starting from 1

If <hl>NO id</> is specified then it will enumerate over all the id key values.]],
}
