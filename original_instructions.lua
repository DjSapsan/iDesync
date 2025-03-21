-- arg - { "in"/"out"/"exec", name(string), desc (string), filter (instruction_argument_filters), is extra param (bool)}

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
	stk = state.returns[#state.returns - up][2]
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

-- Global functions that can also be used by mods
function InstGet(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return Tool.NewRegisterObject() end
	if inmem then return state.mem[j] end
	if j > 0 then return comp:GetRegister(j) end
	return comp.owner:GetRegister(-j)
end

function InstGetNum(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return 0 end
	if inmem then return state.mem[j].num end
	if j > 0 then return comp:GetRegisterNum(j) end
	return comp.owner:GetRegisterNum(-j)
end

function InstGetCoord(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return nil end
	if inmem then return state.mem[j].coord end
	if j > 0 then return comp:GetRegisterCoord(j) end
	return comp.owner:GetRegisterCoord(-j)
end

function InstGetId(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return nil end
	if inmem then return state.mem[j].id end
	if j > 0 then return comp:GetRegisterId(j) end
	return comp.owner:GetRegisterId(-j)
end

function InstGetEntity(comp, state, i)
	local j, inmem = GetStack(state, i)
	if not j then return nil end
	if inmem then return state.mem[j].entity end
	if j > 0 then return comp:GetRegisterEntity(j) end
	return comp.owner:GetRegisterEntity(-j)
end

function InstSet(comp, state, i, val)
	local j, inmem = GetStack(state, i)
	if not j then return end
	if inmem then state.mem[j]:Init(val)
	elseif j > 0 then comp:SetRegister(j, val)
	else comp.owner:SetRegister(-j, val) end
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

local GetCachedBehaviorAsm, GetFactionBehaviorAsmById = GetCachedBehaviorAsm, GetFactionBehaviorAsmById
function InstBeginBlock(comp, state, it)
	local next_counter, loop_inst_idx = state.counter, state.lastcounter
	local inst = GetCachedBehaviorAsm(state.revid)[loop_inst_idx]
	local op = data.instructions[inst[1]]
	if op.next(comp, state, it, table.unpack(inst, 3)) then
		op.last(comp, state, it, table.unpack(inst, 3))
	else
		local blocks = state.blocks
		if not blocks then blocks = {} state.blocks = blocks end
		if #blocks >= 40 then
			return InstError(comp, state, "Behavior exceeded loop recursion limit")
		end
		blocks[#blocks + 1] = { next_counter, loop_inst_idx, it, state.returns and #state.returns or 0 }
	end
end

-- Local references for shorter names and avoiding global lookup on every use
local Get, GetNum, GetCoord, GetId, GetEntity, Set, BeginBlock = InstGet, InstGetNum, InstGetCoord, InstGetId, InstGetEntity, InstSet, InstBeginBlock

-- Filter function for register selection when setting constant input value in behavior editor
data.instruction_argument_filters = {
	any          = function(def, cat) return true end, -- any value including negative numbers
	entity       = function(def, cat) return false end, -- no register selection, just registers/parameters/variables
	num          = function(def, cat) return cat.number_panel or cat.allow_negative end, -- just number
	coord        = function(def, cat) return cat.coord_panel end, -- coord
	coord_num    = function(def, cat) return cat.number_panel or cat.allow_negative or cat.coord_panel end, -- number or coord
	item         = function(def, cat) return cat.tab == "item" end, -- item tab only
	item_num     = function(def, cat) return cat.tab == "item" or cat.number_panel end,
	comp         = function(def, cat) return def.attachment_size end, -- component item
	comp_num     = function(def, cat) return def.attachment_size or cat.number_panel end,
	frame        = function(def, cat) return cat.tab == "frame" end, -- frame tab only
	frame_num    = function(def, cat) return cat.tab == "frame" or cat.number_panel end,
	radar        = function(def, cat) return def.tag == "resource" or def.tag == "entityfilter" or cat.number_panel end,
	resource     = function(def, cat) return def.tag == "resource" end,
	resource_num = function(def, cat) return def.tag == "resource" or cat.number_panel end,
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

local function GetSourceNode(state)
	return GetCachedBehaviorAsm(state.revid).code[state.lastcounter]
end

local function GetComponentFromSortedGroupIndex(comp, state, compid, group_index)
	local group_index_num = GetNum(comp, state, group_index)
	if group_index_num == REG_INFINITE then return end

	local owner = comp.owner
	for s=1,999 do
		local hidden_comp = owner:GetHiddenComponent(s)
		if not hidden_comp then break end
		if hidden_comp.id == compid then
			if group_index_num <= 1 then return hidden_comp end
			group_index_num = group_index_num - 1
		end
	end

	-- Get the UI listed order and not equipped component order
	for s=1,owner.socket_count do
		local socket_comp = owner:GetComponent(s)
		if socket_comp and socket_comp.id == compid then
			if group_index_num <= 1 then return socket_comp end
			group_index_num = group_index_num - 1
		end
	end
end

--------------------------------------------------------------------------------------------------------------------------
--------------------------------------- FLOW -----------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------

data.instructions.call =
{
	func = function(comp, state, cause, sub, ...)
		local returns, mem = state.returns, state.mem
		if not returns then returns = {} state.returns = returns end
		if #returns >= 20 then
			return InstError(comp, state, "Behavior exceeded call depth limit")
		end
		local asm, mem_index = sub == 0 and GetCachedBehaviorAsm(state.revid) or GetFactionBehaviorAsmById(comp.faction, sub), #mem
		if not asm then return end -- behavior deleted or modified
		returns[#returns + 1] = { state.revid, state.stk, state.counter, mem_index, state.lastcounter } -- return record
		table.move(asm.mem, 1, #asm.mem, mem_index + 1, mem) -- increase stack memory by amount of sub
		for i=mem_index + 1,#mem do mem[i] = Tool.NewRegisterObject(mem[i]) end -- copy values (don't reference)
		local code_parameters = asm.code.parameters or ""
		local stk = { #code_parameters - mem_index, table.unpack(code_parameters) }
		for i=2,#stk do
			local arg = select(i - 1, ...)
			if arg then stk[i] = arg -- got input argument
			elseif stk[i] then -- empty output argument must exist as the parameter might be used like a local variable
				mem[#mem + 1] = Tool.NewRegisterObject()
				stk[i] = #mem
			end
		end
		state.revid, state.stk, state.counter, state.lastcounter = asm.revid, stk, 1, 1 -- subroutine state
		--print("[call] Return #" .. #returns  .. " - STK: " .. tostring(state.stk):gsub("\n", " "):gsub(" %p%d+%p: ", "") .. " - MEM: " .. tostring(state.mem):gsub("\n", " "):gsub(" %p%d+%p: ", "") .." - OLDSTK: " .. tostring(returns[#returns][3]):gsub("\n", " "):gsub(" %p%d+%p: ", "") .." - OLDMEM: " .. returns[#returns][5])
	end,
	name = "Call",
	desc = "Call a subroutine",
	category = "Flow",
	icon = "icon_input",
	node_ui = function(canvas, inst, program_ui)
		local sub_code = inst.sub == 0 and program_ui.code or program_ui.library[inst.sub]
		canvas:Add('<Text x=20 y=60 text="Subroutine" style=hl/>')
		canvas:Add('<Text x=30 y=84/>', { text = sub_code and (NOLOC(sub_code.name) or "New Behavior") or "none" })
		if sub_code and inst.sub and inst.sub ~= 0 and inst.sub ~= program_ui.code.id then
			local param_hash = Tool.Hash(sub_code.parameters)
			canvas:Add('<Button dock=top-right x=-20 y=108 text="Edit"/>', {
				on_click = function()
					local edit_code = program_ui.library[inst.sub]
					if not edit_code then return end
					program_ui[1]:Add("<Modal dock=fill/>"):SetContent("<Program margin=5 margin_top=20 margin_bottom=0/>", {
						code = program_ui.is_remote and Tool.Copy(edit_code) or edit_code,
						comp = program_ui.comp, is_remote = program_ui.is_remote, library = program_ui.library,
						close = function(w)
							w.parent:RemoveFromParent()
						end,
					})
				end,
				update = function()
					local edit_code = program_ui.library[inst.sub]
					local new_hash = edit_code and Tool.Hash(edit_code.parameters)
					if param_hash == new_hash then return end
					param_hash = new_hash
					program_ui:Refresh(true)
				end,
			})
		end
		canvas:Add('<Button y=108/>', {
			dock = (sub_code and "top-left" or "top"),
			x = (sub_code and 20 or 0),
			text = (sub_code and "Select" or "Select Subroutine"),
			on_click = function(btn)
				UILibrarySelectBehavior(btn,
					function(item)
						inst.sub = item.id
						UI.CloseMenuPopup()
						program_ui:Refresh()
					end,
					nil, nil, inst.sub, program_ui.comp and program_ui.comp.def, program_ui.library)
			end,
		})
		return 100, sub_code
	end,
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
}

data.instructions.exit =
{
	func = function(comp, state)
		-- unroll block and return stacks and reset program counter
		if state.returns and #state.returns > 0 then
			local mem, old_counter, mem_count = state.mem
			state.revid, state.stk, old_counter, mem_count = table.unpack(state.returns[1])
			table.move(mem, #mem+1, #mem+#mem-mem_count, mem_count+1) -- trim to mem_count
		end
		state.counter = 1
		state.blocks, state.returns, state.debug = nil, nil, nil
		UpdateEntityBehaviorState(comp.owner, comp)
		return true
	end,
	exec_arg = false,
	name = "Exit",
	desc = "Stops execution of the behavior",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Deny.png",
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
	icon = "Main/skin/Icons/Common/56x56/Unlocked.png"
}

data.instructions.lock = {
	func = function(comp, state)
		state.limit = 1
	end,
	name = "Lock",
	desc = "Run one instruction at a time",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Unlocked.png"
}

data.instructions.label =
{
	func = function() end,
	args = { { "in", "Label", "Label identifier", "any" } },
	name = "Label",
	desc = "Labels can be jumped to from anywhere in a behavior",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
}

data.instructions.jump =
{
	func = function(comp, state, cause, label)
		label = Get(comp, state, label)
		for i,v in ipairs(GetCachedBehaviorAsm(state.revid)) do
			if v[1] == "label" and label == Get(comp, state, v[3]) then
				state.counter = i
				return
			end
		end
	end,
	args = { { "in", "Label", "Label identifier", "any" } },
	name = "Jump",
	desc = "Jumps execution to label with the same label id",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/J Value.png"
}

data.instructions.wait =
{
	func = function(comp, state, cause, time)
		local t = GetNum(comp, state, time)
		comp:SetStateSleep(math.max(t or 1, 1))
		return true
	end,
	args = { { "in", "Time", "Number of ticks to wait", "num" } },
	name = "Wait Ticks",
	desc = "Pauses execution of the behavior until 1 or more ticks later (5 ticks=1 second)",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Wait.png",
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
		{ "exec", "If Different", "Where to continue if the registers differ" },
		{ "in", "Value 1" },
		{ "in", "Value 2" },
	},
	name = "Compare Register",
	desc = "Compares Registers for equality",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.get_unit_type =
{
	func = function(comp, state, cause, in_entity, out_type)
		local e = GetEntity(comp, state, in_entity)
		if not e then Set(comp, state, out_type) return end
		Set(comp, state, out_type, { id = e.id })
	end,
	args = {
		{ "in", "Entity", "Entity" },
		{ "out", "Type" },
	},
	name = "Get Unit Type",
	desc = "Get the frame type of the unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "in", "Entity" },
		{ "in", "Type" },
		{ "exec", "Is Not", },
	},
	name = "Is Unit A",
	desc = "Get the frame type of the unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "exec", "If Different", "Where to continue if the types differ" },
		{ "in", "Value 1" },
		{ "in", "Value 2" },
	},
	name = "Compare Item",
	desc = "Compares Item or Unit type",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.compare_entity =
{
	func = function(comp, state, cause, if_differ, val1, val2)
		local r1_entity, r2_entity = GetEntity(comp, state, val1), GetEntity(comp, state, val2)
		if r1_entity ~= r2_entity or (not r1_entity and not r2_entity) then
			state.counter = if_differ
		end
	end,
	exec_arg = { 1, "If Equal", "Where to continue if the entities are the same" },
	args = {
		{ "exec", "If Different", "Where to continue if the entities differ" },
		{ "in", "Entity 1" },
		{ "in", "Entity 2" },
	},
	name = "Compare Entity",
	desc = "Compares Entities",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
	exec_arg = { 1, "If Equal", "Where to continue if the entities are the same" },
	args = {
		{ "exec", "If Different", "Where to continue if the entities differ" },
		{ "in", "Item" },
		{ "in", "Type" },
	},
	name = "Is a",
	desc = "Compares if an item of entity is of a specific type",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "in", "Item/Entity" },
		{ "out", "Type" },
	},
	name = "Get Type",
	desc = "Gets the type from an item or entity",
	category = "Global",
	icon = "Main/skin/Icons/Common/56x56/Processing.png"
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
		{ "in", "Data", "Data to test" },
		{ "exec", "Item", "Item Type" },
		{ "exec", "Entity", "Entity Type" },
		{ "exec", "Component", "Component Type" },
		{ "exec", "Tech", "Tech Type", nil, true },
		{ "exec", "Value", "Information Value Type", nil, true },
		{ "exec", "Coord", "Coordinate Value Type", nil, true },
	},
	name = "Data type switch",
	desc = "Switch based on type of value",
	category = "Flow",
	icon = "Main/skin/Icons/Common/56x56/Processing.png"
}

data.instructions.get_first_locked_0 =
{
	func = function(comp, state, cause, first_locked)
		for _,v in ipairs(comp.owner.slots) do
			if v.id and v.locked and v.stack == 0 then
				Set(comp, state, first_locked, { id = v.id, num = 1 })
				return
			end
		end
		Set(comp, state, first_locked)
	end,
	args = {
		{ "out", "Item", "The first locked item id with no item", },
	},
	name = "Get First Locked Id",
	desc = "Gets the first item where the locked slot exists but there is no item in it",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "in", "Unit", "The unit to check", "entity", },
		{ "exec", "Building", "Where to continue if the entity is a building" },
		{ "exec", "Bot", "Where to continue if the entity is a bot" },
		{ "exec", "Construction", "Where to continue if the entity is a construction site", nil, true },
	},
	name = "Unit Type",
	desc = "Divert program depending on unit type",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		local dist_a = ent_a and faction:IsSeen(ent_a) and owner:GetRangeTo(ent_a) or 9999999999
		local dist_b = ent_b and faction:IsSeen(ent_b) and owner:GetRangeTo(ent_b) or 9999999999

		if dist_a <= dist_b then
			Set(comp, state, closer_entity, {entity = ent_a, num = dist_a})
			if exec_a then state.counter = exec_a end
		else
			Set(comp, state, closer_entity, {entity = ent_b, num = dist_b})
			if exec_b then state.counter = exec_b end
		end
	end,
	args = {
		{ "exec", "A", "A is nearer (or equal)" },
		{ "exec", "B", "B is nearer" },
		{ "in", "Unit A", nil, "entity" },
		{ "in", "Unit B", nil, "entity" },
		{ "out", "Closest", "Closest unit", nil, true },
	},
	name = "Select Nearest",
	desc = "Branches based on which unit is closer, optional branches for closer unit",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Closest Enemy.png",
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
		Map.FindClosestEntity(owner, math.min(override_range or range, range), entity_filter, function(e)
			local ret, num = FilterEntity(owner, e, filters)
			if ret then
				it[#it+1] = num and { entity = e, num = num } or e
			end
		end)

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
		{ "in", "Range", "Range (up to units visibility range)", "num" },
		{ "in", "Filter", "Filter to check", "radar" },
		{ "in", "Filter", "Second Filter", "radar", true },
		{ "in", "Filter", "Third Filter", "radar", true },
		{ "out", "Entity", "Current Entity" },
		{ "exec", "Done", "Finished looping through all entities in range" },
	},
	name = "Loop Entities (Range)",
	desc = "Performs code for all entities in visibility range of the unit",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.for_research =
{
	func = function(comp, state, cause, out_tech, exec_done)
		local techs = comp.faction.researchable_techs

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
		{ "out", "Tech", "Researchable Tech" },
		{ "exec", "Done", "Finished looping through all researchable tech" },
	},
	name = "Loop Research",
	desc = "Performs code for all researchable tech",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
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
		{ "in", "Id", "Input Id"},
		{ "exec", "No Match", "Execution path if there is no match" },
	},
	name = "Is Unlocked",
	desc = "Checks whether a faction has an id unlocked",
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
			producers = production_recipe and production_recipe.producers

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
							for item,n in pairs(producers) do
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
			if ent.def.convert_to then
				-- unpacked items return their packaged form recipe instead
				item_id = ent.def.convert_to
			else
				item_id = ent.def.id
			end

			if not comp.faction:IsUnlocked(item_id) then
				Set(comp, state, out_producer)
				return
			end

			-- from the entity get whether it's a bot or a building from the def.id
			product_def = data.all[item_id]
			local production_recipe = product_def and (product_def.production_recipe or product_def.construction_recipe)
			producers = production_recipe and production_recipe.producers
		end


		local it = { 2 }
		if producers then
			for item,n in pairs(producers) do
				it[#it + 1] = { id = item, num = n }
			end
			return BeginBlock(comp, state, it)
		end
		Set(comp, state, out_producer)
	end,

	next = function(comp, state, it, in_product, out_producer, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_producer, it[i])
		it[1] = i + 1
	end,

	last = function(comp, state, it, in_product, out_producer, exec_done)
		--Set(comp, state, out_producer, nil)
		state.counter = exec_done
	end,

	args = {
		{ "in", "Production", "Production" },
		{ "out", "Producer", "Producer" },
		{ "exec", "Done", "Finished looping through all researchable tech" },
	},
	name = "Loop Producers",
	desc = "Gets all producers for a production",
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
	args = { { "out", "Tech", "First active research" }, },
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

		local tech_required = data.techs[tech_id].require_tech

		-- no category for listing is an auto unlock research
		if (tech_required[1] and not data.techs[tech_required[1]].category) then
			Set(comp, state, out_research, nil)
			return
		end

		Set(comp, state, out_research, { tech = tech_required[1] or nil})
	end,
	args = {
		{ "in", "Tech", "The research to investigate for prior tech requirements", "tech" },
		{ "out", "Requirement", "The tech required for the research (if needed)", },
	},
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
		if not tech or not comp.faction:IsResearchable(tech) then return end

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
	args = { { "in", "Tech", "First active research", "tech" }, },
	name = "Set Research",
	desc = "Returns the first active research tech",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
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
	args = { { "in", "Tech", "Tech to remove from research queue" }, },
	name = "Clear Research",
	desc = "Clears a research from queue, or entire queue if no tech passed",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

--[[
data.instructions.for_number =
{
	func = function(comp, state, cause, from, to, val, exec_done)
		local from, to = GetNum(comp, state, from), GetNum(comp, state, to)
		Set(comp, state, val, { num = from + (from <= to and -1 or 1) })
		return BeginBlock(comp, state, { from + (from <= to and -1 or 1) })
	end,

	next = function(comp, state, it, from, to, val, exec_done)
		local from, to, i = GetNum(comp, state, from), GetNum(comp, state, to)
		local up, i = (from <= to), it[1]
		if (up and i >= to) or (not up and i <= to) then return true end
		i = i + (up and 1 or -1)
		Set(comp, state, val, { num = i })
		it[1] = i
	end,

	last = function(comp, state, it, from, to, val, exec_done)
		state.counter = exec_done
	end,

	args = {
		{ "in", "From", "Loop start number", "num" },
		{ "in", "To", "Loop end number", "num" },
		{ "out", "Value", "Current number" },
		{ "exec", "Done", "Finished loop" },
	},
	name = "Loop Number",
	desc = "Performs code for all numbers in range",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}
--]]

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
		{ "exec", "If Larger", "Where to continue if Value is larger than Compare" },
		{ "exec", "If Smaller", "Where to continue if Value is smaller than Compare" },
		{ "in", "Value", "The value to check with", "num" },
		{ "in", "Compare", "The number to check against", "num" },
	},
	name = "Compare Number",
	desc = "Divert program depending on number of Value and Compare",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "in", "Value", nil, "any" },
		{ "out", "Target" },
		--{ "in", "Unit", "The unit to copy value to (if not self)", "entity", true },
	},
	name = "Copy",
	desc = "Copy a value to a frame register, parameter or variable",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
}

data.instructions.set_comp_reg =
{
	func = function(comp, state, cause, value, setcomp, group_index)
		local setcompreg = Get(comp, state, setcomp)
		local setcompid, setregnum = setcompreg.id, math.max(setcompreg.num or 1, 1)
		if not setcompid then return end

		local setcomp = GetComponentFromSortedGroupIndex(comp, state, setcompid, group_index)
		if not setcomp then return end

		local setcomp_def = setcomp and setcomp.def
		local setcomp_regdef = setcomp_def and setcomp_def.registers
		if setcomp_def and setregnum <= setcomp.register_count and (not setcomp_regdef or not setcomp_regdef[setregnum] or not setcomp_regdef[setregnum].read_only) then
			setcomp:SetRegister(setregnum, Get(comp, state, value))
		end
	end,
	args = {
		{ "in", "Value", nil, "any" },
		{ "in", "Component/Index", "Component and register number to set", "comp_num" },
		{ "in", "Group/Index", "Component group index if multiple are equipped", "num", true },
	},
	name = "Set to Component",
	desc = "Writes a value into a component register",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Set Component Reg.png",
}

data.instructions.get_comp_reg =
{
	func = function(comp, state, cause, getcomp, value, group_index)
		local getcompreg = Get(comp, state, getcomp)
		local getcompid = getcompreg.id
		if not getcompid then return end

		local getcomp = GetComponentFromSortedGroupIndex(comp, state, getcompid, group_index)
		if not getcomp then return end

		Set(comp, state, value, getcomp and getcomp:GetRegister(math.max(getcompreg.num or 1, 1)))
	end,
	args = {
		{ "in", "Component/Index", "Component and register number to get", "comp_num" },
		{ "out", "Value" },
		{ "in", "Group/Index", "Component group index if multiple are equipped", "num", true },
	},
	name = "Get from Component",
	desc = "Reads a value from a component register",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Set Component Reg.png",
}

data.instructions.is_working =
{
	func = function(comp, state, cause, not_working, getcomp, group_index, out_component_id)
		local getcompreg = Get(comp, state, getcomp)

		local getcompid = getcompreg.id
		if not getcompid then
			local components = comp.owner.components
			-- If nothing is set, search all sockets in the entity
			for _,v in ipairs(components) do
				if v.is_working then
					-- Return when finding any working component
					Set(comp, state, out_component_id, { id = v.id } )
					return
				end
			end

			Set(comp, state, out_component_id, nil)
			state.counter = not_working
			return
		end

		local getcomp = GetComponentFromSortedGroupIndex(comp, state, getcompid, group_index)
		if not getcomp then Set(comp, state, out_component_id, nil) state.counter = not_working return end
		if not getcomp.is_working then Set(comp, state, out_component_id, nil) state.counter = not_working return end
	end,
	args = {
		{ "exec", "Is Not Working", "If the requested component is NOT currently working" },
		{ "in", "Component/Index", "Component to get", "comp_num" },
		{ "in", "Group/Index", "Component group index if multiple are equipped", "num", true },
		{ "out", "Value", "Returns the component ID currently working", "entity", true },
	},
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
		{ "in", "Component ID", "Component to search for", "comp_num" },
		{ "out", "Value" },
		{ "in", "Unit", "The unit to check (if not self)", "entity", true },
	},
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
		{ "in", "Value" },
		{ "in", "Num/Coord", nil, "coord_num" },
		{ "out", "To" },
	},
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
		{ "in", "x", nil, "any" },
		{ "in", "y", nil, "any" },
		{ "out", "Result" },
	},
	name = "Combine Coordinate",
	desc = "Returns a coordinate made from x and y values",
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
		{ "in", "Coordinate", nil, "coord_num" },
		{ "out", "x" },
		{ "out", "y" },
	},
	name = "Separate Coordinate",
	desc = "Split a coordinate into x and y values",
	category = "Math",
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
		{ "in", "Num" },
		{ "in", "Entity" },
		{ "out", "Register", nil, "entity" },
		{ "in", "x", nil, nil, true },
		{ "in", "y", nil, nil, true },
	},
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
		{ "in", "Register", nil, "entity" },
		{ "out", "Num" },
		{ "out", "Entity", nil, nil, true  },
		{ "out", "ID", nil, nil, true  },
		{ "out", "x", nil, nil, true },
		{ "out", "y", nil, nil, true },
	},
	name = "Separate Register",
	desc = "Split a register into separate parameters",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.add =
{
	func = function(comp, state, cause, from, num, to)
		local reg = Get(comp, state, from)
		local from_coord = GetCoord(comp, state, from)
		local num_coord = GetCoord(comp, state, num)

		local from_num = GetNum(comp, state, from)
		local num_num = GetNum(comp, state, num)

		if (from_num == REG_INFINITE or num_num == REG_INFINITE) then
			-- result returns infinite should it exist
			from_num = REG_INFINITE
		else
			-- otherwise calculate the num
			from_num = from_num + num_num
		end

		-- both coords exist
		if (from_coord and num_coord) then
			from_coord.x = from_coord.x + num_coord.x
			from_coord.y = from_coord.y + num_coord.y

			Set(comp, state, to, { num = from_num, coord = from_coord })
		-- copy left coord only
		elseif (from_coord and not num_coord) then
			Set(comp, state, to, { num = from_num, coord = from_coord })
		-- copy right coord only
		elseif (not from_coord and num_coord) then
			Set(comp, state, to, { num = from_num, coord = num_coord })
		-- no coords
		else
			Set(comp, state, to, { num = from_num, entity = reg.entity, id = reg.id })
		end
	end,
	args = {
		{ "in", "To", nil, "coord_num" },
		{ "in", "Num", nil, "coord_num" },
		{ "out", "Result" },
	},
	name = "Add",
	desc = "Adds a number or coordinate to another number or coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Add Numbers.png",
}

data.instructions.sub =
{
	func = function(comp, state, cause, from, num, to)
		local reg = Get(comp, state, from)
		local from_coord = GetCoord(comp, state, from)
		local num_coord = GetCoord(comp, state, num)

		local from_num = GetNum(comp, state, from)
		local num_num = GetNum(comp, state, num)

		if (from_num == REG_INFINITE or num_num == REG_INFINITE) then
			-- result returns infinite should it exist
			from_num = REG_INFINITE
		else
			-- otherwise calculate the num
			from_num = from_num - num_num
		end

		-- both coords exist
		if (from_coord and num_coord) then
			from_coord.x = from_coord.x - num_coord.x
			from_coord.y = from_coord.y - num_coord.y

			Set(comp, state, to, { num = from_num, coord = from_coord })
		-- copy left coord only
		elseif (from_coord and not num_coord) then
			Set(comp, state, to, { num = from_num, coord = from_coord })
		-- copy right coord only
		elseif (not from_coord and num_coord) then
			Set(comp, state, to, { num = from_num, coord = num_coord })
		-- no coords
		else
			Set(comp, state, to, { num = from_num, entity = reg.entity, id = reg.id })
		end
	end,
	args = {
		{ "in", "From", nil, "coord_num" },
		{ "in", "Num", nil, "coord_num" },
		{ "out", "Result" },
	},
	name = "Subtract",
	desc = "Subtracts a number or coordinate from another number or coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Substact Numbers.png",
}

data.instructions.mul =
{
	func = function(comp, state, cause, from, num, to)
		local from_coord = GetCoord(comp, state, from)
		local num_coord = GetCoord(comp, state, num)

		-- Coord calculation
		if (from_coord and num_coord) then
			from_coord.x = from_coord.x * num_coord.x
			from_coord.y = from_coord.y * num_coord.y

			Set(comp, state, to, { coord = from_coord })
			return
		end

		-- Mismatch (num*coord OR coord*num)
		if (from_coord and not num_coord) or (not from_coord and num_coord) then
			local coeff

			if (from_coord and num) then
				coeff = GetNum(comp, state, num)

				if (coeff and coeff ~= REG_INFINITE) then
					from_coord.x = from_coord.x * coeff
					from_coord.y = from_coord.y * coeff

					Set(comp, state, to, { coord = from_coord })
				end
			elseif (num_coord and from) then
				coeff = GetNum(comp, state, from)

				if (coeff and coeff ~= REG_INFINITE) then
					num_coord.x = num_coord.x * coeff
					num_coord.y = num_coord.y * coeff

					Set(comp, state, to, { coord = num_coord })
				end
			end

			return
		end

		-- Avoid infinity for two nums
		if (GetNum(comp, state, from) == REG_INFINITE) or (GetNum(comp, state, num) == REG_INFINITE) then
			Set(comp, state, to)
			return
		end

		-- Num calculation
		local from_num = Tool.NewRegisterObject(Get(comp, state, from)) -- copy to avoid changing from
		from_num.num = from_num.num * GetNum(comp, state, num)
		Set(comp, state, to, from_num)
	end,
	args = {
		{ "in", "To", nil, "coord_num" },
		{ "in", "Num", nil, "coord_num" },
		{ "out", "Result" },
	},
	name = "Multiply",
	desc = "Multiplies a number or coordinate from another number or coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Mul Numbers.png",
}

data.instructions.div =
{
	func = function(comp, state, cause, from, num, to)
		local from_coord = GetCoord(comp, state, from)
		local num_coord = GetCoord(comp, state, num)

		-- Coord calculation
		if (from_coord and num_coord) then
			local divisorX = num_coord.x
			local divisorY = num_coord.y

			-- Avoid infinity
			if (divisorX == REG_INFINITE) or (divisorY == REG_INFINITE) then
				Set(comp, state, to)
				return
			end

			from_coord.x = from_coord.x // (divisorX == 0 and 1 or divisorX)
			from_coord.y = from_coord.y // (divisorY == 0 and 1 or divisorY)

			Set(comp, state, to, { coord = from_coord })
			return
		end

		-- Mismatch (num/coord OR coord/num)
		if (from_coord and not num_coord) or (not from_coord and num_coord) then
			local coeff

			if (from_coord and num) then
				coeff = GetNum(comp, state, num)
				if (coeff and coeff ~= REG_INFINITE) then
					from_coord.x = from_coord.x // (coeff == 0 and 1 or coeff)
					from_coord.y = from_coord.y // (coeff == 0 and 1 or coeff)
					Set(comp, state, to, { coord = from_coord })
				end
			elseif (num_coord and from) then
				coeff = GetNum(comp, state, from)

				if (coeff and coeff ~= REG_INFINITE) then
					num_coord.x = num_coord.x // (coeff == 0 and 1 or coeff)
					num_coord.y = num_coord.y // (coeff == 0 and 1 or coeff)
					Set(comp, state, to, { coord = num_coord })
				end
			end

			return
		end

		-- Avoid infinity for two nums
		if (GetNum(comp, state, from) == REG_INFINITE) or (GetNum(comp, state, num) == REG_INFINITE) then
			Set(comp, state, to)
			return
		end

		-- Num calculation
		local from_num = Tool.NewRegisterObject(Get(comp, state, from)) -- copy to avoid changing from
		local divisor = GetNum(comp, state, num)
		from_num.num = from_num.num // (divisor == 0 and 1 or divisor)
		Set(comp, state, to, from_num)
	end,
	args = {
		{ "in", "From", nil, "coord_num" },
		{ "in", "Num", nil, "coord_num" },
		{ "out", "Result" },
	},
	name = "Divide",
	desc = "Divides a number or coordinate from another number or coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Divide Numbers.png",
}

data.instructions.modulo =
{
	func = function(comp, state, cause, num, divisor, to)
		local divisor, res = Get(comp, state, divisor), Tool.NewRegisterObject(Get(comp, state, num)) -- copy to avoid changing input

		local divisor_n = divisor.num
		local divisor_x, divisor_y = divisor.coord_x or divisor_n, divisor.coord_y or divisor_n
		local res_x, res_y = res.coord_x, res.coord_y

		if           divisor_n ~= 0 and divisor_n ~= REG_INFINITE then res.num     = res.num % divisor_n end
		if res_x and divisor_x ~= 0 and divisor_x ~= REG_INFINITE then res.coord_x = res_x   % divisor_x end
		if res_y and divisor_y ~= 0 and divisor_y ~= REG_INFINITE then res.coord_y = res_y   % divisor_y end

		Set(comp, state, to, res)
	end,
	args = {
		{ "in", "Num", nil, "coord_num" },
		{ "in", "By", nil, "coord_num" },
		{ "out", "Result" },
	},
	name = "Modulo",
	desc = "Get the remainder of a division",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Mul Numbers.png",
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
		{ "in", "Item", "Item to check can fit", "item" },
		{ "out", "Result", "Number of a specific item that can fit on a unit" },
		{ "in", "Unit", "The unit to check (if not self)", "entity", true },
	},
	name = "Get space for item",
	desc = "Returns how many of the input item can fit in the inventory",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
}

data.instructions.checkfreespace =
{
	func = function(comp, state, cause, if_cantfit, item_in)
		local item_reg, owner = Get(comp, state, item_in), comp.owner
		local item_id = item_reg.id
		local item_entity = not item_id and item_reg.entity
		if item_entity then
			if IsDroppedItem(item_entity) then
				for _,v in ipairs(item_entity.slots or {}) do
					if v.id and v.unreserved_stack > 0 and owner:HaveFreeSpace(v.id) then
						return
					end
				end
				state.counter = if_cantfit
				return
			end
			item_id = GetResourceHarvestItemId(item_entity)
		end
		if item_id then
			local canfit = owner:HaveFreeSpace(item_id, math.max(item_reg.num, 1))
			if not canfit then state.counter = if_cantfit end
		end
	end,
	args = {
		{ "exec", "Can't Fit", "Execution if it can't fit the item" },
		{ "in", "Item", "Item and amount to check can fit", "item_num" },
	},
	name = "Check space for item",
	desc = "Checks if free space is available for an item and amount",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
}

data.instructions.lock_slots =
{
	func = function(comp, state, cause, item_in, num)
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
					-- if slot already empty or item_in contains nil, then just lock as is
					if (item_id == nil or slot.id ~= nil) then
						slot.locked = true
					else
						slot:SetLockedItem(item_id)
					end
				end
			else
				for _,v in ipairs(slots) do
					-- Stop "ALL locking" touching the special storage types like, garage drone and gas
					if v.type == "storage" then
						if (item_id == nil or v.id ~= nil) then
							v.locked = true
						else
							v:SetLockedItem(item_id)
						end
					end
				end
			end
		end
	end,
	args = {
		{ "in", "Item", "Item type to try fixing to the slots", "item_num" },
		{ "in", "Slot index", "Individual slot to fix", "num", true },
	},
	name = "Fix Item Slots",
	desc = "Fix all storage slots or a specific item slot index",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
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
		{ "in", "Slot index", "Individual slot to unfix", "num", true },
	},
	name = "Unfix Item Slots",
	desc = "Unfix all inventory slots or a specific item slot index",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
}

data.instructions.get_health =
{
	func = function(comp, state, cause, target, percent, current, max)
		local target_entity = GetSeenEntityOrSelf(comp, state, target)
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
		{ "in", "Entity", "Entity to check", "entity" },
		{ "out", "Percent", "Percentage of health remaining" },
		{ "out", "Current", "Value of health remaining", nil, true },
		{ "out", "Max", "Value of maximum health", nil, true },
	},
	name = "Get Health",
	desc = "Gets a unit's health as a percentage, current remaining and max amount",
	category = "Math",
	icon = "Main/skin/Icons/Common/56x56/H Value.png"
}

data.instructions.get_shield =
{
	func = function(comp, state, cause, target, percent, current, max)
		local target_entity = GetSeenEntityOrSelf(comp, state, target)
		-- If target_entity not valid use reference to Self
		if target_entity and comp.faction:IsSeen(target_entity) then
			local current_shield = 0
			local max_shield = 0

			-- check for multiple equipped shields
			for ii,v in ipairs(comp.owner.components) do
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
		{ "in", "Entity", "Entity to check", "entity" },
		{ "out", "Percent", "Percentage of shield remaining" },
		{ "out", "Current", "Value of shield remaining", nil, true },
		{ "out", "Max", "Value of maximum shield amount", nil, true },
	},
	name = "Get Shield",
	desc = "Get a unit's shield as a percentage, current remaining and max amount",
	category = "Math",
	icon = "Main/skin/Icons/Common/56x56/H Value.png"
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
		{ "in", "Coordinate", "Coordinate to get Entity from", "coord_num" },
		{ "out", "Result" },
	},
	name = "Get Entity At",
	desc = "Gets the best matching entity at a coordinate",
	category = "Math",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
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
		{ "out", "Result" },
	},
	name = "Get Grid Efficiency",
	desc = "Gets the value of the Grid Efficiency as a percent",
	category = "Math",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
}

data.instructions.get_battery =
{
	func = function(comp, state, cause, res)
		Set(comp, state, res, { entity = comp.owner, num = comp.owner.battery_percent })
	end,
	args = {
		{ "out", "Result" },
	},
	name = "Get Battery",
	desc = "Gets the value of the Battery level as a percent",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Check Battery.png",
}

data.instructions.get_self =
{
	func = function(comp, state, cause, res)
		Set(comp, state, res, { entity = comp.owner })
	end,
	args = {
		{ "out", "Result" },
	},
	name = "Get Self",
	desc = "Gets the value of the Unit executing the behavior",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Set Register.png",
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
		{ "in", "Unit", "The owned unit to check for", "entity" },
		{ "out", "Result", "Value of units Signal register" },
	},
	name = "Read Signal",
	desc = "Reads the Signal register of another unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Scan.png",
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
		{ "in", "Value", "Value to check", },
		{ "exec", "Empty", "Where to continue if the value is empty" },
		{ "exec", "Has Value", "Where to continue if the value exists" },
		--{ "exec", "Space", "Where to continue if the unit is in space" },
	},
	name = "Is Empty",
	desc = "Checks a value if it is empty",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "in", "Band", "The band to check for" },
		{ "out", "Result", "Value of the radio signal" },
	},
	name = "Read Radio",
	desc = "Reads the Radio signal on a specified band",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Scan.png",
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
		{ "in", "Signal", "Signal" },
		{ "out", "Entity", "Entity with signal" },
		{ "exec", "Done", "Finished looping through all entities with signal" },
	},
	name = "*Loop Signal*",
	desc = "*DEPRECATED* Use Loop Signal (Match) instead",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.for_signal_match =
{
	func = function(comp, state, cause, in_signal, out_unit, out_signal, exec_done)
		local signal = GetId(comp, state, in_signal)
		local signal_num = GetNum(comp, state, in_signal)
		local owner = comp.owner
		local it = { 2 }
		if signal == nil then
			signal = Get(comp, state, in_signal)
			local e = signal.entity
			local signal_ent = comp.faction:GetEntitiesWithRegister(FRAMEREG_SIGNAL, e, true)
			for _,v in ipairs(signal_ent) do
				local unit_sig = v:GetRegister(FRAMEREG_SIGNAL)
				it[#it+1] = v
				it[#it+1] = unit_sig
			end
		else
			local faction, filters = comp.faction, { signal, signal_num }
			local signal_ent = faction:GetEntitiesWithRegister(FRAMEREG_SIGNAL, signal, true)
			for _,v in ipairs(signal_ent) do
				local unit_sig = v:GetRegister(FRAMEREG_SIGNAL)
				if unit_sig then
					local unit_sig_id, unit_sig_entity = unit_sig.id, unit_sig.entity
					if unit_sig_id == signal then
						it[#it+1] = v
						it[#it+1] = { id = unit_sig_id, num = unit_sig.num, entity = unit_sig_entity }
					elseif unit_sig_entity and faction:MatchEntityFilter(unit_sig_entity, PrepareFilterEntity(filters)) then
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

	next = function(comp, state, it, in_signal, out_unit, out_signal, exec_done)
		local i = it[1]
		if i > #it then return true end
		Set(comp, state, out_unit, { entity = it[i] })
		Set(comp, state, out_signal, it[i+1])
		it[1] = i + 2
	end,

	last = function(comp, state, it, in_signal, out_unit, out_signal, exec_done)
		--Set(comp, state, out_unit, nil)
		--Set(comp, state, out_signal, nil)
		state.counter = exec_done
	end,

	args = {
		{ "in", "Signal", "Signal" },
		{ "out", "Entity", "Entity with signal" },
		{ "out", "Signal", "Found signal", "entity", true },
		{ "exec", "Done", "Finished looping through all entities with signal" },
	},
	name = "Loop Signal (Match)",
	desc = "Loops through all units with a signal of similar type",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}
data.instructions.check_altitude =
{
	func = function(comp, state, cause, in_unit, if_valley, if_plateau)
		local ent = GetSeenEntityOrSelf(comp, state, in_unit)
		if not ent then
		elseif Map.GetPlateauDelta(ent, -1) >= 0 then
			state.counter = if_plateau
		else
			state.counter = if_valley
		end
	end,
	exec_arg = { 4, "No Unit", "No visible unit passed", nil, true },
	args = {
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
		{ "exec", "Valley", "Where to continue if the unit is in a valley" },
		{ "exec", "Plateau", "Where to continue if the unit is on a plateau" },
		--{ "exec", "Space", "Where to continue if the unit is in space" },
	},
	name = "Check Altitude",
	desc = "Divert program depending on location of a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.check_blightness =
{
	func = function(comp, state, cause, in_unit, if_blight)
		local ent = GetSeenEntityOrSelf(comp, state, in_unit)
		if not ent then
		elseif Map.GetBlightnessDelta(ent, -1) >= 0 then
			state.counter = if_blight
		end
	end,
	args = {
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
		{ "exec", "Blight", "Where to continue if the unit is in the blight" },
	},
	name = "Check Blightness",
	desc = "Divert program depending on location of a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.check_health =
{
	func = function(comp, state, cause, if_full, in_unit)
		local ent = GetSeenEntityOrSelf(comp, state, in_unit)
		if ent and not ent.is_damaged then
			state.counter = if_full
		end
	end,
	args = {
		{ "exec", "Full", "Where to continue if at full health" },
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
	},
	name = "Check Health",
	desc = "Check a units health",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/H Value.png"
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
		{ "exec", "Full", "Where to continue if battery power is fully recharged" },
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
	},
	name = "Check Battery",
	desc = "Checks the Battery level of a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Check Battery.png",
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
		{ "exec", "Full", "Where to continue if at full efficiency" },
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
	},
	name = "Check Grid Efficiency",
	desc = "Checks the Efficiency of the logistics network the unit is on",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
}

data.instructions.count_item =
{
	func = function(comp, state, cause, item, output, in_unit)
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
		local c = GetSourceNode(state).c
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
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		combo.texts = { "Remaining", "Reserved" }
		combo.value = inst.c or 1
		return 34
	end,

	args = {
		{ "in", "Item", "Item to count", "item" },
		{ "out", "Result", "Number of this item in inventory or empty if none exist" },
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
	},
	name = "Count Items",
	desc = "Counts the number of the passed item in its inventory",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
}

local stats_unit = {
	{ "health_points", "Durability" },
	{
		function(def, e)
			local move_boost = e and SumModuleBoosts(e, "c_modulespeed") or 0
			return def.movement_speed+math.floor((move_boost*0.01*def.movement_speed)+0.5)
		end,
		"Movement Speed" },
	{ function(def) return (def.power or 0)*TICKS_PER_SECOND end, "Power Usage" },
}

local stats_item = {
	{ "stack_size", "Maximum Stack" },
	{ "range", "Range" },
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
	func = function(comp, state, cause, in_unit, output)
		--print("[COUNT_ITEM] item: " .. tostring(GetId(comp, state, item)) .. " (#" .. tostring(item) .. ") - output: #" .. tostring(output))
		local ent = GetFactionEntityOrSelf(comp, state, in_unit)
		local def = ent.def
		local c = GetSourceNode(state).c or 1
		local val
		local stat = stats_unit[c][1]
		if type(stat) == "string" then
			val = def[stat] or 0
		else
			val = stat(def, comp.owner)
		end
		Set(comp, state, output, { id = ent.id, num = val})
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50 width=180/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		local texts = {}
		for i,v in ipairs(stats_unit) do
			texts[#texts+1] = v[2]
		end
		combo.texts = texts
		combo.value = inst.c or 1
		return 34
	end,
	args = {
		{ "in", "Unit", "The unit to check", },
		{ "out", "Result", "Number of this item in inventory or empty if none exist" },
	},
	name = "Get Unit Info",
	desc = "Gets information on a unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
}

data.instructions.get_item_info =
{
	func = function(comp, state, cause, in_id, output)
		local item_id = GetId(comp, state, in_id)
		if not item_id then return Set(comp, state, output) end
		local def = data.all[item_id]
		local c = GetSourceNode(state).c
		local val
		local stat = stats_item[c or 1][1]
		if type(stat) == "string" then
			val = def[stat] or 0
		else
			val = stat(def)
		end
		Set(comp, state, output, { id = item_id, num = val})
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50 width=180/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		local texts = {}
		for i,v in ipairs(stats_item) do
			texts[#texts+1] = v[2]
		end
		combo.texts = texts
		combo.value = inst.c or 1
		return 34
	end,
	args = {
		{ "in", "Item", "The item to check", },
		{ "out", "Result", "Number of this item in inventory or empty if none exist" },
	},
	name = "Get Item Info",
	desc = "Gets information on an item",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
}

data.instructions.count_slots =
{
	func = function(comp, state, cause, output, in_unit)
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
		local c = GetSourceNode(state).c or 1
		if ent then
			if c == 1 then
				total = ent.slot_count
			else
				local slottypes = { "ALL", "storage", "gas", "virus", "anomaly", "drone", "garage" }
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
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50 width=100/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		combo.texts = { "ALL", "storage", "gas", "virus", "anomaly", "drone", "garage" }
		combo.value = inst.c or 1
		return 34
	end,

	args = {
		{ "out", "Result", "Number of slots of this type" },
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
	},
	name = "Count Slots",
	desc = "Returns the number of slots in this unit of the given type",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
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
		{ "in", "Item", "Item to count", "item_num" },
		{ "out", "Max Stack", "Max Stack", },
	},
	name = "Get Max Stack",
	desc = "Returns the amount an item can stack to",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
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
		{ "in", "Item", "Item to count", "item_num" },
		{ "exec", "Have Item", "have the specified item" },
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
	},
	name = "Have Item",
	desc = "Checks if you have at least a specified amount of an item",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
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
		{ "exec", "No Component", "If you don't current hold the requested component" },
		{ "in", "Component", "Component to equip", "comp" },
		{ "in", "Slot index", "Individual slot to equip component from", "num", true },
	},
	name = "Equip Component",
	desc = "Equips a component if it exists",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Home.png"
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
		{ "exec", "No Component", "If you don't current hold the requested component or slot was empty" },
		{ "in", "Component", "Component to unequip", "comp" },
		{ "in", "Slot index", "Individual slot to try to unequip component from", "num", true },
	},
	name = "Unequip Component",
	desc = "Unequips a component if it exists",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Detach.png"
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
		local range = owner.visibility_range
		local res, num = Map.FindClosestEntity(owner, math.min(override_range or range, range), entity_filter, function(e) return FilterEntity(owner, e, filters) end)
		Set(comp, state, output, { entity = res, num = num })
	end,
	args = {
		{ "in", "Filter", "Filter to check", "radar" },
		{ "in", "Filter", "Second Filter", "radar", true },
		{ "in", "Filter", "Third Filter", "radar", true },
		{ "out", "Output", "Entity" },
	},
	name = "Get Closest Entity",
	desc = "Gets the closest visible entity matching a filter",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Closest Enemy.png",
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
		local res = unit and owner.faction:MatchEntityFilter(unit, PrepareFilterEntity(filters)) and FilterEntity(owner, unit, filters)
		if not res then state.counter = failed end
	end,
	args = {
		{ "in", "Unit", "Unit to Filter, defaults to Self", "entity" },
		{ "in", "Filter", "Filter to check", "radar" },
		{ "in", "Filter", "Second Filter", "radar", true },
		{ "in", "Filter", "Third Filter", "radar", true },
		{ "exec", "Failed", "Did not match filter" },
	},
	name = "Match",
	desc = "Filters the passed entity",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.switch =
{
	func = function(comp, state, cause, in_unit, in_c1, out_c1, in_c2, out_c2, in_c3, out_c3, in_c4, out_c4, in_c5, out_c5)
		local owner, faction = comp.owner, comp.faction
		local unit = not in_unit and owner or GetEntity(comp, state, in_unit)
		if not unit then return end

		local filters = { false, false }
		local function test_case(in_c)
			filters[1], filters[2] = GetId(comp, state, in_c), GetNum(comp, state, in_c)
			return faction:MatchEntityFilter(unit, PrepareFilterEntity(filters)) and FilterEntity(owner, unit, filters)
		end

		if in_c1 and test_case(in_c1) then state.counter = out_c1 return end
		if in_c2 and test_case(in_c2) then state.counter = out_c2 return end
		if in_c3 and test_case(in_c3) then state.counter = out_c3 return end
		if in_c4 and test_case(in_c4) then state.counter = out_c4 return end
		if in_c5 and test_case(in_c5) then state.counter = out_c5 return end
	end,
	exec_arg = { 1, "Default", "Did not match filter" },
	args = {
		{ "in", "Unit", "Unit to Filter, defaults to Self", "entity" },
		{ "in", "Case 1", "Case 1", "radar" },
		{ "exec", "1", "Case 1" },
		{ "in", "Case 2", "Case 2", "radar", true },
		{ "exec", "2", "Case 2", nil, true },
		{ "in", "Case 3", "Case 3", "radar", true },
		{ "exec", "3", "Case 3", nil, true },
		{ "in", "Case 4", "Case 4", "radar", true },
		{ "exec", "4", "Case 4", nil, true },
		{ "in", "Case 5", "Case 5", "radar", true },
		{ "exec", "5", "Case 5", nil, true },
	},
	name = "Switch",
	desc = "Filters the passed entity",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.dodrop =
{
	func = function(comp, state, cause, target, item)
		local reg, target_coord, target_entity, source_entity, moved = Get(comp, state, item), GetCoord(comp, state, target), GetEntity(comp, state, target), comp.owner
		moved = source_entity.docked_garage == target_entity or (target_entity and target_entity.docked_garage == source_entity)
		local can_transfer = moved or source_entity.has_crane or source_entity.has_movement
		if (not (can_transfer)) or (not target_coord and (not target_entity or not target_entity.exists or (target_entity.faction ~= source_entity.faction and not target_entity.lootable and not comp.faction:GetTrust(target_entity) == "ALLY"))) then
			return
		end

		local function transfer(item_id, limit)
			local have = source_entity:CountItem(item_id, true) -- count unreserved stacks
			if have == 0 then return end
			if not target_coord and (target_entity.is_construction and not target_entity:IsWaitingForOrder(item_id) or (not target_entity.is_construction) and not target_entity:HaveFreeSpace(item_id)) then return end

			if not moved and comp:RequestStateMove(target_coord or target_entity, math.max(comp.owner.crane_range, 1)) then
				-- Not yet next to the position, wait for move to complete then repeat this instruction
				state.counter = state.lastcounter
				return true
			end

			moved = true

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
		local c = GetSourceNode(state).c or 2
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
	node_ui = function(canvas, inst, program_ui, op, show_extra)
		--if not show_extra then return 0 end
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		combo.texts = { "Specified Amount", "Up to Amount" }
		combo.value = inst.c or 2
		return 34
	end,
	args = {
		{ "in", "Destination", "Unit or destination to bring items to", "entity" },
		{ "in", "Item / Amount", "Item and amount to drop off", "item_num", true },
	},
	name = "Drop Off Items",
	desc = "Drop off items at a unit or destination\n\nIf a number is set it will drop off an amount to fill the target unit up to that amount\nIf unset it will try to drop off everything.",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Drop Items.png",
}

data.instructions.dopickup =
{
	func = function(comp, state, cause, source, item)
		local reg, source_entity, target_entity, moved = Get(comp, state, item), GetEntity(comp, state, source), comp.owner
		moved = (source_entity and source_entity.docked_garage == target_entity) or target_entity.docked_garage == source_entity
		local can_transfer = moved or target_entity.has_crane or target_entity.has_movement
		if not source_entity or not source_entity.exists or (target_entity.faction ~= source_entity.faction and not source_entity.lootable) or (not (can_transfer)) then
			return
		end

		local function transfer(item_id, limit)
			local have = source_entity:CountItem(item_id, true) -- count unreserved stacks
			if have == 0 or not target_entity:HaveFreeSpace(item_id) then return end
			if not have then -- somehow this can be nil???
				print("[dopickup] CountItem returned "..tostring(have).." on entity "..tostring(source_entity).." (exists: "..tostring(source_entity and source_entity.exists)..")")
				return
			end
			if not moved and comp:RequestStateMove(source_entity, comp.owner.crane_range) then
				-- Not yet next to the source, wait for move to complete then repeat this instruction
				state.counter = state.lastcounter
				return true
			end
			moved = true
			target_entity:TransferFrom(source_entity, item_id, limit or have, true)
		end

		local reg_item_id = reg.item_id
		local c = GetSourceNode(state).c or 2
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
	node_ui = function(canvas, inst, program_ui, op, show_extra)
		--if not show_extra then return 0 end
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		combo.texts = { "Specified Amount", "Up to Amount" }
		combo.value = inst.c or 2
		return 34
	end,
	args = {
		{ "in", "Source", "Unit to take items from", "entity" },
		{ "in", "Item / Amount", "Item and amount to pick up", "item_num", true },
	},
	name = "Pick Up Items",
	desc = "Picks up a specific number of items from an entity\n\nWill try to pick up the specified amount, if no amount\nis specified it will try to pick up everything.",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Pick Up Items.png",
}

data.instructions.request_item =
{
	func = function(comp, state, cause, item)
		local r = Get(comp, state, item)
		if not r.item_id then return end
		comp:OrderItem(r.item_id, ((r.num == REG_INFINITE and 999999) or (r.num > 0 and r.num) or 0))
	end,
	args = { { "in", "Item", "Item and amount to order", "item_num" } },
	name = "Request Item",
	desc = "Requests an item if it doesn't exist in the inventory",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.order_to_shared_storage =
{
	func = function(comp, state, cause)
		comp.owner:IssueDumpingOrders()
	end,
	name = "Order to Shared Storage",
	desc = "Request Inventory to be sent to nearest shared storage with corresponding locked slots",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.request_wait =
{
	func = function(comp, state, cause, item)
		local r = Get(comp, state, item)
		local r_item_id, r_num = r.item_id, r.num
		if not r_item_id then return end

		local c = GetSourceNode(state).c or 2
		if c == 1 then r_num = r_num + comp.owner:CountItem(r_item_id) end
		comp:OrderItem(r_item_id, ((r_num == REG_INFINITE and 999999) or (r_num > 0 and r_num) or 0))

		-- check inventory
		local hasAmt = comp.owner:CountItem(r_item_id)
		if hasAmt >= r_num then return end
		state.counter = state.lastcounter
		comp:SetStateSleep(1)
		return true
	end,
	node_ui = function(canvas, inst, program_ui, op, show_extra)
		--if not show_extra then return 0 end
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		combo.texts = { "Specified Amount", "Up to Amount" }
		combo.value = inst.c or 2
		return 34
	end,
	args = { { "in", "Item", "Item and amount to order", "item_num" } },
	name = "Request Wait",
	desc = "Requests up to a specified amount of an item and waits until that amount exists in inventory",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
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
		{ "out", "Source" },
		{ "out", "Target" },
		{ "out", "Amount" },
	},
	name = "Get Active Order",
	desc = "Gets the source, target and amount data from the current active order",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
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
		{ "in", "Resource", "Resource Node to check", "entity" },
		{ "out", "Result" },
	},
	name = "Get Resource Num",
	desc = "Gets the amount of resource",
	category = "Math",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
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
		{ "out", "Item" },
		{ "exec", "No Items", "No items in inventory" },
	},
	name = "First Item",
	desc = "Reads the first item in your inventory",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
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
			if slot.id then
				if slot.stack > 0 then
					Set(comp, state, item, { item = slot.id, num = slot.stack })
					return
				elseif slot.locked or slot.reserved_space > 0 then
					Set(comp, state, item, { item = slot.id, num = slot.stack })
					state.counter = exec_none
					return
				end
			end
		end

		state.counter = exec_none
		Set(comp, state, item, nil)
	end,
	args = {
		{ "in", "Index", "Slot index", "num" },
		{ "out", "Item" },
		{ "exec", "No Item", "Item not found" },
	},
	name = "Get Inventory Item",
	desc = "Reads the item contained in the specified slot index",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
}

data.instructions.for_component =
{
	func = function(comp, state, cause, val, out_index, exec_done)
		local slot_length = comp.owner.socket_count
		-- Runner?
		if slot_length == 0 then
			Set(comp, state, val, nil)
			Set(comp, state, out_index, nil)
			state.counter = exec_done
			return
		end

		return BeginBlock(comp, state, { 1, slot_length })
	end,

	next = function(comp, state, it, val, out_index, exec_done)
		local from, to = it[1], it[2]
		local i = it[1]
		if (i == (to + 1)) then return true end
		local found_index = 0

		for ii,v in ipairs(comp.owner.components) do
			if v.socket_index == i then
				found_index = ii
				break
			end
		end

		local foundcomp = nil
		if found_index == 0 then
			Set(comp, state, val, nil)
		else
			local component = comp.owner.components[found_index]
			foundcomp = component.id
			Set(comp, state, val, { id = foundcomp } )
		end

		Set(comp, state, out_index, { id = foundcomp, num = i } )

		i = i + 1
		it[1] = i
	end,

	last = function(comp, state, it, val, out_index, exec_done)
		state.counter = exec_done
	end,

	args = {
		{ "out", "Component", "Equipped Component ID" },
		{ "out", "Index", "Returns the index of the result", "num" },
		{ "exec", "Done", "Finished loop", true },
	},
	name = "Loop Component Slots",
	desc = "Loops through Components",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
}

data.instructions.for_inventory_item =
{
	func = function(comp, state, cause, val, exec_done, r_stack, ur_stack, r_space, ur_space)
		local slot_length = comp.owner.slot_count
		-- Beacon?
		if slot_length == 0 then
			Set(comp, state, val, nil)
			state.counter = exec_done
			return
		end

		return BeginBlock(comp, state, { 1, slot_length })
	end,

	next = function(comp, state, it, val, exec_done, r_stack, ur_stack, r_space, ur_space)
		local from, to = it[1], it[2]
		local i = it[1]

		local slot = comp.owner:GetSlot(i)
		if not slot then
			Set(comp, state, r_stack)
			Set(comp, state, ur_stack)
			Set(comp, state, r_space)
			Set(comp, state, ur_space)
			return true
		end

		Set(comp, state, val, { entity = slot.entity or slot.reserved_entity, item = slot.id, num = slot.unreserved_stack } )

		Set(comp, state, r_stack, { item = slot.id, num = slot.reserved_stack } )
		Set(comp, state, ur_stack, { item = slot.id, num = slot.unreserved_stack } )
		Set(comp, state, r_space, { item = slot.id, num = slot.reserved_space } )
		Set(comp, state, ur_space, { item = slot.id, num = slot.unreserved_space } )

		i = i + 1
		it[1] = i
	end,

	last = function(comp, state, it, val, exec_done, r_stack, ur_stack, r_space, ur_space)
		state.counter = exec_done
	end,

	args = {
		{ "out", "Inventory", "Item Inventory" },
		{ "exec", "Done", "Finished loop" },
		{ "out", "Reserved Stack", "Items reserved for outgoing order or recipe", "num", true },
		{ "out", "Unreserved Stack", "Items available", "num", true },
		{ "out", "Reserved Space", "Space reserved for an incoming order", "num", true },
		{ "out", "Unreserved Space", "Remaining space", "num", true },
	},
	name = "Loop Inventory Slots",
	desc = "Loops through Inventory",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
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

		if production_recipe.ingredients then
			local ingredients = production_recipe.ingredients
			local it = { 2 }
			for item,n in pairs(ingredients) do
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
		{ "in", "Research", nil, "tech" },
		{ "out", "Ingredient", "Research Ingredient" },
		{ "exec", "Done", "Finished loop" },
	},
	name = "Loop Research Ingredients",
	desc = "Loops through Ingredients",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
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
							for item,n in pairs(ingredients) do
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
				if ent.def.convert_to then
					-- unpacked items return their packaged form recipe instead
					item_id = ent.def.convert_to
				else
					item_id = ent.def.id
				end

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
			for item,n in pairs(ingredients) do
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
		{ "in", "Recipe", nil, "item" },
		{ "out", "Ingredient", "Recipe Ingredient" },
		{ "exec", "Done", "Finished loop" },
	},
	name = "Loop Recipe Ingredients",
	desc = "Loops through Ingredients",
	category = "Flow",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
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
		{ "out", "Result" },
		{ "in", "Unit", "The unit to check for (if not self)", "entity", true },
	},
	name = "Inventory Total",
	desc = "Returns the total contained in inventory",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Item.png",
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
		{ "in", "Target", "Target unit", "entity" },
		{ "out", "Distance", "Unit and its distance in the numerical part of the value" },
		{ "in", "Unit", "The unit to measure from (if not self)", "entity", true },
	},
	name = "Distance",
	desc = "Returns distance to a unit",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Closest Enemy.png",
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
		{ "in", "Target", "Target unit", "entity" },
		{ "in", "Item", "Item and amount to transfer", "item_num" },
	},
	name = "Order Transfer To",
	desc = "Transfers an Item to another Unit",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
}

data.instructions.is_same_grid =
{
	func = function(comp, state, cause, in_unit1, in_unit2, exec_diff)
		local ent1, ent2 = GetEntity(comp, state, in_unit1), GetEntity(comp, state, in_unit2)
		local e1gi = ent1 and ent1.power_grid_index
		local e2gi = ent2 and ent2.power_grid_index
		if e1gi and e2gi and ent1.faction == comp.faction and ent1.faction == ent2.faction and e1gi == e2gi then return end
		state.counter = exec_diff
	end,
	exec_arg = { 1, "Same Grid", "Where to continue if both entities are in the same logistics network" },
	args = {
		{ "in", "Entity", "First Entity", "entity" },
		{ "in", "Entity", "Second Entity", "entity" },
		{ "exec", "Different", "Different logistics networks" },
	},
	name = "Is Same Grid",
	desc = "Checks if two entities are in the same logistics network",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Power.png",
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
	exec_arg = { 1, "Moving", "Where to continue if entity is moving" },
	args = {
		{ "exec", "Not Moving", "Where to continue if entity is not moving" },
		{ "exec", "Path Blocked", "Where to continue if entity is path blocked" },
		{ "exec", "No Result", "Where to continue if entity is out of visual range" },
		{ "in", "Unit", "The unit to check (if not self)", "entity", true },
	},
	name = "Is Moving",
	desc = "Checks the movement state of an entity",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Move To.png"
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
		{ "in", "Slot index", "Individual slot to check", "num", },
		{ "exec", "Is Fixed", "Where to continue if inventory slot is fixed" },
	},
	name = "Is Fixed",
	desc = "Check if a specific item slot index is fixed",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
}

data.instructions.is_equipped =
{
	func = function(comp, state, cause, in_id, is_equipped, out_num)
		local component_id = GetId(comp, state, in_id)
		local moose = data.all[component_id]

		local component_data = data.all[component_id]
		local convert_to
		if component_data then convert_to = component_data.convert_to end

		local owner = comp.owner
		local found = 0

		if convert_to then -- packaged item check
			local slot_length = owner.slot_count
			-- Beacon?
			if slot_length == 0 then
				return
			end
			local slots = owner.slots

			if slots then
				for _,slot in ipairs(slots) do
					-- 1) check against both packaged and unpackaged id so the user can drag in either
					-- 2) don't check stack amount, eg Else when a drone is on delivery it won't be counted
					if (not (slot.def and slot.def.slot_type == "storage")) and (slot.unreserved_stack > 0 or slot.reserved_space > 0) and (slot.id == convert_to or slot.id == component_data.id) then
						found = found + 1
					end
				end
			end
		else -- regular component check
			for _,v in ipairs(owner.components) do
				if v.id == component_id then
					found = found + 1
				end
			end
		end

		Set(comp, state, out_num, { num = found })

		if found > 0 then state.counter = is_equipped end
	end,
	args = {
		{ "in", "Component", "Component to check", "comp" },
		{ "exec", "Component Equipped", "Where to continue if component is equipped" },
		{ "out", "Result", "Returns how many instances of a component equipped on this Unit", nil, true },
	},
	name = "Is Equipped",
	desc = "Check if a specific component has been equipped",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
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
}

data.instructions.connect =
{
	func = function(comp, state, cause)
		comp.owner.disconnected = false
	end,
	name = "Connect",
	desc = "Connects Units from Logistics Network",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Carry.png",
}

data.instructions.disconnect =
{
	func = function(comp, state, cause)
		comp.owner.disconnected = true
	end,
	name = "Disconnect",
	desc = "Disconnects Units from Logistics Network",
	category = "Unit",
	icon = "Main/skin/Icons/Common/56x56/Carry.png",
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
}

data.instructions.unpackage_all =
{
	func = function(comp, state, cause, target)
		local target_slots = comp.owner.slots
		local target_entity

		if target then
			target_entity = GetEntity(comp, state, target)
			if not target_entity then
				target_entity = comp.owner
			else
				local source_entity = comp.owner
				if not target_entity or not target_entity.exists or (target_entity.faction ~= source_entity.faction and not comp.faction:GetTrust(target_entity) == "ALLY") or (not (source_entity.has_movement or source_entity.has_crane)) then
					return
				end
			end

			if target_entity.slots then
				target_slots = target_entity.slots
			end
		else
			target_entity = comp.owner
		end

		local source_slots = comp.owner.slots
		local target_slots_owner
		if (target_slots[1]) then
			target_slots_owner = target_slots[1].owner
		end

		for _,slot in ipairs(source_slots) do
			-- if its a packaged item
			if slot.def and slot.def.slot_type == "storage" and slot.def.convert_to and slot.unreserved_stack > 0 then
				-- try to convert item
				local convert_slot = target_slots_owner:GetFreeSlot(slot.def.convert_to, 1)
				if convert_slot then
					if target_entity ~= comp.owner then
						if comp:RequestStateMove(target_entity, comp.owner.crane_range) then
							-- Not yet next to the target, wait for move to complete then repeat this instruction
							state.counter = state.lastcounter
							return true
						end
					end

					local convert_slot_owner = convert_slot.owner
					ConvertItemType(convert_slot_owner, slot, convert_slot, true)
					if target_entity ~= comp.owner then
						Map.ThrowItemEffect(slot.owner, convert_slot_owner, slot.id)
					end

					state.counter = state.lastcounter
					comp:SetStateSleep(1)
					return true
				end
			end
		end
	end,
	args = {
		{ "in", "Unit", "The destination to try and unpack (if not self)", "entity", true },
	},
	name = "Unpackage All",
	desc = "Tries to unpack all packaged items",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Drop Items.png",
}

data.instructions.package_all =
{
	func = function(comp, state, cause, target)
		local target_slots = comp.owner.slots
		local target_entity

		if target then
			target_entity = GetEntity(comp, state, target)
			if not target_entity then
				target_entity = comp.owner
			else
				local source_entity = comp.owner
				if (target_entity and target_entity.faction ~= source_entity.faction) or (not (source_entity.has_movement or source_entity.has_crane)) then
					return
				end
			end

			if target_entity.slots then
				target_slots = target_entity.slots
			end
		else
			target_entity = comp.owner
		end

		local source_slots = comp.owner.slots
		local source_slots_owner
		if (source_slots[1]) then
			source_slots_owner = source_slots[1].owner
		end

		for _,slot in ipairs(target_slots) do
			-- if its a packaged item
			if slot.def and slot.def.slot_type ~= "storage" and slot.def.convert_to and slot.unreserved_stack > 0 then
				-- try to convert item
				local convert_slot = source_slots_owner:GetFreeSlot(slot.def.convert_to, 1)
				if convert_slot then
					if target_entity ~= comp.owner then
						if comp:RequestStateMove(target_entity, comp.owner.crane_range) then
							-- Not yet next to the target, wait for move to complete then repeat this instruction
							state.counter = state.lastcounter
							return true
						end
					end

					local convert_slot_owner = convert_slot.owner
					ConvertItemType(convert_slot_owner, slot, convert_slot, true)

					if target_entity ~= comp.owner then
						Map.ThrowItemEffect(target_entity, convert_slot_owner, slot.id)
					end

					state.counter = state.lastcounter
					comp:SetStateSleep(1)
					return true
				end
			end
		end
	end,
	args = {
		{ "in", "Unit", "The destination to try and pack (if not self)", "entity", true },
	},
	name = "Package All",
	desc = "Tries to pack all packable units into items",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Pick Up Items.png",
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
				end

				-- remaining puzzles like alien lock just need to wait until theyre done
				local id = puzzle_comp.id
				if id == "c_alien_lock" then id = "c_alien_key" end
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

		-- Need to defer this because solving explorable might spawn new entities
		Map.Defer(function()
			if solve_puzzle_comp then
				FactionAction.ExplorableSolvePuzzle(owner.faction, { comp = solve_puzzle_comp, consume_slot = slot_with_fix_item })
			else
				FactionAction.ExplorableSetSolved(owner.faction, { entity = target_entity })
			end
		end)

		comp:SetStateSleep(1)
		return true
	end,
	args = {
		{ "in", "Target", "Explorable to solve", "entity" },
		{ "out", "Missing", "Missing repair item, scanner component or Unpowered" },
		{ "exec", "Failed", "Missing item, component or power to scan" },
	},
	name = "Solve Explorable",
	desc = "Attempt to solve explorable with inventory items",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Drop Items.png",
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
		{ "exec", "No Dock", "Where to continue if unit is not docked" },
		{ "out", "Garage", "entity" },
	},
	name = "Is Docked",
	desc = "Check if a unit is docked and get its garage",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Count Free Space.png",
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
	args = { { "in", "Target", "entity" } },
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
	desc = "Stop movement and abort what is currently controlling the entities movement",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
}

data.instructions.get_location =
{
	func = function(comp, state, cause, in_entity, out_coord)
		local ent = GetSeenEntityOrSelf(comp, state, in_entity)
		if ent and comp.faction:IsSeen(ent) then
			Set(comp, state, out_coord, { coord = { ent.location.x, ent.location.y }})
		end
	end,
	args = {
		{ "in", "Entity", "Entity to get coordinates of", "entity" },
		{ "out", "Coord", "Coordinate of entity", },
	},
	name = "Get Location",
	desc = "Gets location of a a seen entity",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
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
		{ "in", "Number", "Number of tiles to move East", "num" },
	},
	name = "Move East",
	desc = "Moves towards a tile East of the current location at the specified distance",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
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
		{ "in", "Number", "Number of tiles to move West", "num" },
	},
	name = "Move West",
	desc = "Moves towards a tile West of the current location at the specified distance",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
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
		{ "in", "Number", "Number of tiles to move North", "num" },
	},
	name = "Move North",
	desc = "Moves towards a tile North of the current location at the specified distance",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
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
		{ "in", "Number", "Number of tiles to move South", "num" },
	},
	name = "Move South",
	desc = "Moves towards a tile South of the current location at the specified distance",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
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
		{ "in", "Target", "Unit to move to", "entity" },
	},
	name = "Move Unit (Async)*",
	desc = "*DEPRECATED* Use Move Unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
}

data.instructions.attack_move =
{
	func = function(comp, state, cause, in_target)
		local e = comp.owner
		local reg = Get(comp, state, in_target)
		local target_entity = reg.entity
		local target_coord = target_entity and target_entity.location or reg.coord
		if not target_coord then return end

		local turret = e:FindComponent("c_turret", true)
		if turret then
			turret:SetRegisterCoord(1, target_coord)
		end
	end,
	args = {
		{  "Target", "Target unit or coordinate", "coord" },
	},
	name = "Attack Move",
	desc = "Moves towards a location stopping to attack any enemies encountered",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
}

data.instructions.domove =
{
	func = function(comp, state, cause, target)
		local reg = Get(comp, state, target)
		local target = reg and (reg.entity or reg.coord)
		if not target then return end
		local c = GetSourceNode(state).c
		if c == 2 then
			comp.owner:MoveTo(target, math.max(reg.num, 0))
		else
			if not comp:RequestStateMove(target, math.max(reg.num, 0)) then comp:SetStateSleep(1) end
			return true
		end
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		combo.texts = { "Synchronous", "Asynchronous" }
		combo.value = inst.c or 1
		return 34
	end,

	args = {
		{ "in", "Target", "Unit to move to, the number specifies the range in which to be in", "entity" },
	},
	name = "Move Unit",
	desc = "Moves to another unit or within a range of another unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
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
		{ "in", "Target", "Unit to move to, the number specifies the range in which to be in", "entity" },
	},
	name = "*Move Unit (Range)*",
	desc = "*DEPRECATED* Use Move Unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
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
		{ "in", "Target", "Unit to move to", "entity" },
	},
	name = "Move Unit",
	desc = "Move to another unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
}
]]--

data.instructions.moveaway_range =
{
	func = function(comp, state, cause, target)
		local reg = Get(comp, state, target)
		if not reg or not reg.entity then return end
		local range = reg.num > 0 and reg.num or 5

		-- find location away from unit
		local l1, l2 = comp.owner.location, reg.entity.location

		local x = l1.x-l2.x
		local y = l1.y-l2.y
		local denom = math.sqrt((x*x)+(y*y))
		local c = GetSourceNode(state).c
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
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		combo.texts = { "Synchronous", "Asynchronous" }
		combo.value = inst.c or 1
		return 34
	end,
	args = {
		{ "in", "Target", "Unit to move away from", "entity" },
	},
	name = "Move Away (Range)",
	desc = "Moves out of range of another unit",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
}

data.instructions.scout =
{
	func = function(comp, state)
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
		local c = GetSourceNode(state).c
		if c == 2 then comp.owner:MoveTo(target_loc.x, target_loc.y) return end

		-- sync
		local moveret = comp:RequestStateMove(target_loc.x, target_loc.y)
		if not moveret then state.counter = state.lastcounter comp:SetStateSleep(5) end
		return true
	end,
	node_ui = function(canvas, inst, program_ui)
		local combo = canvas:Add("<Combo on_change={on_change} x=10 y=50/>", { on_change = function(btn, value) inst.c = value program_ui:set_dirty(true) end})
		combo.texts = { "Synchronous", "Asynchronous" }
		combo.value = inst.c or 1
		return 34
	end,
	name = "Scout",
	desc = "Moves in a scouting pattern around the factions home location",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Scout.png",
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
		{ "in", "Range", "Range to scout", "num" },
		{ "in", "Coord", "Last Coord", "coord" },
	},
	name = "Scout Range",
	desc = "Moves in a random direction a specified amount\nOptionally pass a coordinate to give some directionality",
	category = "Move",
	icon = "Main/skin/Icons/Special/Commands/Scout.png",
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
		{ { "in", "X", "X Coordinate", "num" } },
		{ { "in", "Y", "Y Coordinate", "num" } },
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
		{ { "out", "X", "X Coordinate" } },
		{ { "out", "Y", "Y Coordinate" } },
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
		local resources = { metalore = 0, crystal = 0, }
		local location = comp.owner.location

		local range = comp.owner.power_range
		if range == 0 then range = comp.owner.visibility_range end
		Map.FindClosestEntity(location.x, location.y, range - 1, "Resource", function(e)
			if not comp.faction:IsDiscovered(e) then return end
			local id, amt = GetResourceHarvestItemId(e), GetResourceHarvestItemAmount(e)
			if id and resources[id] ~= REG_INFINITE then
				if amt == REG_INFINITE then resources[id] = REG_INFINITE
				else resources[id] = (resources[id] or 0) + amt
				end
			end
		end)
		local it = { 2 }
		for k,v in pairs(resources) do
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
		{ "out", "Resource" },
		{ "exec", "Done" },
	},
	name = "Loop Nearby Resources",
	desc = "Scans for nearby resources in power field range",
	category = "Unit",
	icon = "Main/skin/Icons/Special/Commands/Scan.png",
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
	desc = "Deploys held unit at location specified or current location",
	category = "Component",
	args = {
		{ "in", "Coord", "location to deploy" }
	},
	icon = "Main/skin/Icons/Special/Commands/Move To.png",
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
			local res = Map.FindClosestEntity(owner, math.min(override_range or range, range), entity_filter, function(e) local a, b = FilterEntity(owner, e, filters) if a then num = b end return a end)
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
		{ "in", "Filter 1", "First filter", "radar" },
		{ "in", "Filter 2", "Second filter", "radar" },
		{ "in", "Filter 3", "Third filter", "radar" },
		{ "out", "Result" },
		{ "exec", "No Result", "Execution path if no results are found" },
	},
	name = "Radar",
	desc = "Scan for the closest unit that matches the filters",
	category = "Component",
	icon = "Main/skin/Icons/Special/Commands/Scan.png",
}

data.instructions.mine =
{
	func = function(comp, state, cause, resource, no_mine, inv_full)
		local miner = comp.owner:FindComponent("c_miner", true)
		if not miner then -- no miner
			--Set(comp, state, resource, nil)
			state.counter = no_mine
			comp:SetStateSleep(1)
			return true
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
			state.counter = no_mine
			return
		end

		-- check path
		if comp.owner.state_path_blocked then
			state.counter = no_mine
			miner:SetRegister(1, nil)
			return
		end

		-- check power
		local details = comp.owner.power_details
		if not details or details.efficiency == 0 then
			state.counter = no_mine
			miner:SetRegister(1, nil)
			return
		end

		-- has required amount
		local harvestid = val.id or GetResourceHarvestItemId(val.entity)
		if harvestid and val.num > 0 then
			local hasAmt = comp.owner:CountItem(harvestid)
			if hasAmt >= val.num then
				state.counter = inv_full
				miner:SetRegister(1, nil)
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
				miner:SetRegister(1, val)
			end
		elseif miner_reg.id then
			if val.id and miner_reg.id ~= val.id then
				-- mismatching id
				miner:SetRegister(1, val)
			elseif miner_reg.id ~= harvestid then
				-- doesnt match the requested resource id
				miner:SetRegister(1, val)
			elseif val.entity and val.entity ~= miner.extra_data.target then
				miner:SetRegister(1, val)
			end
		else
			miner:SetRegister(1, val)
		end

		-- no space
		local canfit = comp.owner:HaveFreeSpace(harvestid, 1)

		if canfit == false then
			state.counter = inv_full

			-- Only set is different from current
			if val.id and miner_reg.id ~= val.id then
				miner:SetRegister(1, nil)
			end
			return
		end
	end,
	args = {
		{ "in", "Resource", "Resource to Mine", "resource_num" },
		{ "exec", "Cannot Mine", "Execution path if mining was unable to be performed" },
		{ "exec", "Full", "Execution path if can't fit resource into inventory" },
	},
	name = "Mine",
	desc = "Mines a single resource",
	category = "Component",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
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
		{ "out", "Number", "Stability" },
	},
	name = "Get Stability",
	desc = "Gets the current world stability",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "in", "Value", "Value to check" },
		{ "in", "Max Value", "Max Value to get percentage of" },
		{ "out", "Number", "Percent" },
	},
	name = "Percent",
	desc = "Gives you the percent that value is of Max Value",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "in", "Value", "Value to Remap" },
		{ "in", "Input Low", "Low value for input" },
		{ "in", "Input High", "High value for input" },
		{ "in", "Target Low", "Low value for target" },
		{ "in", "Target high", "High value for target" },
		{ "out", "Result", "Remapped value" },
	},
	name = "Remap",
	desc = "Remaps a value between two ranges",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
}

data.instructions.is_daynight =
{
	func = function(comp, state, cause, if_day, if_night)
		state.counter = Map.GetSunlightIntensity() > 0.0 and if_day or if_night
	end,

	exec_arg = false,
	args = {
		{ "exec", "Day", "Where to continue if it is nighttime" },
		{ "exec", "Night", "Where to continue if it is daytime" },
	},
	name = "Is Day/Night",
	desc = "Divert program depending time of day",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "exec", "Winter", "Where to continue if it is Winter" },
		{ "exec", "Spring", "Where to continue if it is Spring" },
		{ "exec", "Summer", "Where to continue if it is Summer" },
		{ "exec", "Fall", "Where to continue if it is Fall" },
	},
	name = "Get Season",
	desc = "Divert program depending on season",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Compare Values.png",
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
		{ "in", "Item", "Item to count", "item" },
		{ "out", "Result", "Number of this item in your faction" },
		{ "exec", "None", "Execution path when none of this item exists in your faction" },
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
		{ "in", "Frame", "Structure to read the key for", "entity" },
		{ "out", "Key", "Number key of structure" },
	},
	name = "Read Key",
	desc = "Attempts to reads the internal key of the unit",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Read Key.png",
}

data.instructions.can_produce =
{
	func = function(comp, state, cause, can_prod, product_id, in_component)
		local product_def = data.all[GetId(comp, state, product_id)]
		local owner, production_recipe = comp.owner, product_def and product_def.production_recipe
		if production_recipe then
			for k,v in pairs(production_recipe.producers) do
				if owner:CountComponents(k) > 0 then
					state.counter = can_prod
					return
				end
			end

			local component_id = GetId(comp, state, in_component)

			-- Try in_component if original check failed
			if component_id then
				for k,v in pairs(production_recipe.producers) do
					if k == component_id then
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
		{ "exec", "Can Produce", "Where to continue if the item can be produced" },
		{ "in", "Item", "Production Item", "item" },
		{ "in", "Component", "Optional Component to check (if Component not equipped)", "entity", true },
	},
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Can Produce.png",
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
			for rec_item,rec_num in pairs(ingredients) do
				res[#res + 1] = { id = rec_item, num = rec_num*count }
			end
		end
		table.sort(res, function(a, b) return a.id < b.id end)
		Set(comp, state, out1, res[1])
		Set(comp, state, out2, res[2])
		Set(comp, state, out3, res[3])
	end,
	args = {
		{ "in", "Product", nil, "item" },
		{ "out", "Out 1", "First Ingredient" },
		{ "out", "Out 2", "Second Ingredient" },
		{ "out", "Out 3", "Third Ingredient" },
	},
	name = "Get Ingredients",
	desc = "Returns the ingredients required to produce an item",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Ingradients.png",
}

data.instructions.notify =
{
	func = function(comp, state, cause, notify_value)
		local reg = Get(comp, state, notify_value)
		local reg_id, reg_entity, reg_num, reg_coord = reg.id, reg.entity, reg.num, reg.coord

		local reg_def
		if reg_entity then
			reg_def = reg_entity.def
		elseif reg_id then
			reg_def = data.all[reg_id]
		elseif reg_num ~= 0 then
			reg_def = data.components.c_behavior
		else
			reg_def = data.values.v_notify
		end

		if reg_def then
			comp.faction:RunUI(function()
				local entity = reg_entity or comp.owner
				local num_txt
				if reg_coord then
					num_txt = string.format("%d,%d", reg_coord.x, reg_coord.y)
					local jump_location = reg.coord
					Notification.Add(string.format("C%d|%d", reg_coord.x, reg_coord.y) or "notify_behavior", reg_def.texture, num_txt ~= 0 and L("Notify (%s)", num_txt) or "Notify", GetSourceNode(state).txt or reg_def.name or "Notification", {
						tooltip = "Behavior Notification",
						on_click = function() View.MoveCamera(jump_location.x, jump_location.y, false) end,
					})
				else
					num_txt = reg_num
					Notification.Add(reg_id or "notify_behavior", reg_def.texture, num_txt ~= 0 and L("Notify (%s)", num_txt) or "Notify", GetSourceNode(state).txt or reg_def.name or "Notification", {
						tooltip = "Behavior Notification",
						on_click = function() View.JumpCameraToEntities(entity) end,
					})
				end
			end)
		end
	end,
	node_ui = function(canvas, inst, program_ui)
		canvas:Add('<Text x=10 y=50 text="Text:" style=hl/>')
		canvas:Add('<InputText x=10 y=70 margin=2 width=170 height=34 style=hl/>', {
			text = inst.txt,
			on_commit = function(btn, txt)
				inst.txt = txt
				program_ui:set_dirty(true)
			end,
		})
		return 64
	end,
	args = { { "in", "Notify Value", "Notification Value" } },
	name = "Notify",
	desc = "Triggers a faction notification",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
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
		{ "in", "Resource Node", "Resource Node", "entity" },
		{ "out", "Resource", "Resource Type" },
		{ "exec", "Not Resource", "Continue here if it wasn't a resource node" },
	},
	name = "Resource Type",
	desc = "Gets the resource type from an resource node",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
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
		{ "exec", "Ally", "Target unit considers you an ally" },
		{ "exec", "Neutral", "Target unit considers you neutral" },
		{ "exec", "Enemy", "Target unit considers you an enemy" },
		{ "in", "Unit", "Target Unit", "entity" },
	},
	name = "Get Trust",
	desc = "Gets the trust level of the unit towards you",
	category = "Global",
	icon = "Main/skin/Icons/Common/56x56/Question.png",
}

data.instructions.gethome =
{
	func = function(comp, state, cause, result)
		Set(comp, state, result, { entity = comp.faction.home_entity })
	end,
	args = {
		{ "out", "Result", "Factions home unit" },
	},
	name = "Get Home",
	desc = "Gets the factions home unit",
	category = "Global",
	icon = "Main/skin/Icons/Common/56x56/Question.png",
}

data.instructions.ping =
{
	func = function(comp, state, cause, target_entity_id)
		local target = Get(comp, state, target_entity_id)
		if target.entity then
			if comp.faction:IsSeen(target.entity) then
				comp.faction:RunUI(function() View.DoPlayerPing(target.entity) end)
			end
		elseif target and target.coord then
			comp.faction:RunUI(function() View.DoPlayerPing(target.coord.x, target.coord.y) end)
		end
	end,
	args = {
		{ "in", "Target", "Target unit", "entity" },
	},
	name = "Pings a Unit",
	desc = "Plays the Ping effect and notifies other players",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
}

local function build_produce_ui(canvas, inst, program_ui, op)
	local inst_def = data.instructions[op]
	canvas:Add('<Text x=20 y=50 style=hl/>').text = (inst_def.produce_type)
	local inst_library_id = inst.bp
	local library_item = inst_library_id and program_ui.library[inst_library_id]
	local inst_frame_id = library_item and library_item.frame or inst.frame
	local frame_def = inst_frame_id and data.frames[inst_frame_id]
	local frame_name = frame_def and (library_item and library_item.name and NOLOC(library_item.name) or frame_def.name or "Unnamed")
	if frame_name then canvas:Add('<Text x=30 y=74/>', { text = frame_name, tooltip = DefinitionTooltip(library_item or frame_def) }) end
	local popup_layout
	if inst_def.produce_type == "Building" then
		popup_layout = "<Box padding=5><BuildView on_select={on_select} library={library} hide_last_copied=true/></Box>"
	else
		popup_layout = "<Box padding=5><SimpleRegisterSelection width=626 max_height=536 on_select_id={on_select_id} def_filter={bot_def_filter} is_production=true hide_last_copied=true library={library}/></Box>"
	end
	canvas:Add('<Button dock=top y=98 margin_left=10 margin_right=10/>', {
		text = L("Select %s", inst_def.produce_type),
		on_click = function(btn)
			UI.MenuPopup(popup_layout, {
				library = program_ui.library,
				inst = inst,
				on_select_id = function(menu, regsel, id, library_id)
					menu:on_select(nil, library_id, not library_id and id)
				end,
				on_select = function(menu, buildview, library_id, frame_id)
					local ins = menu.inst
					if frame_id then
						ins.frame, ins.bp = frame_id, nil
					else
						ins.bp, ins.frame = library_id, nil
					end
					UI.CloseMenuPopup()
					program_ui:Refresh()
				end,
				bot_def_filter = function(def)
					return def.movement_speed or (def.frame and data.frames[def.frame].movement_speed)
				end,
			}, btn)
		end,
	})
	return 90
end

data.instructions.build =
{
	func = function(comp, state, cause, in_location, in_rotation, on_failed)
		local inst, faction = GetSourceNode(state),  comp.faction
		local faction_library_id, faction_library = inst.bp, faction.extra_data.library
		local bp = faction_library_id and faction_library and faction_library[faction_library_id]
		local frame_id = bp and bp.frame or inst.frame
		if not frame_id then state.counter = on_failed return end
		if bp and not BlueprintIsCustomized(bp) then bp = nil end

		local location, rotation = GetCoord(comp, state, in_location), GetNum(comp, state, in_rotation)
		local loc = location or comp.owner.location
		local x, y = loc.x, loc.y
		if not faction:CanPlace(frame_id, x, y, rotation, true) then state.counter = on_failed return end
		if bp and not FactionHasUnlockedCustomBlueprint(faction, bp) then state.counter = on_failed return end
		if not bp and not faction:IsUnlocked(frame_id) then state.counter = on_failed return end

		Map.Defer(function()
			local e = CreateConstructionSite(faction, frame_id, x, y, rotation)
			if bp then
				ProcessLibraryBlueprint(bp, function(processed_bp)
					e.extra_data.custom_blueprint = Tool.Copy(processed_bp)
				end)
			end
		end)
	end,
	args = {
		{ "in", "Coordinate", "Target location, or at currently location if not specified", "coord_num", true },
		{ "in", "Rotation", "Building Rotation (0 to 3) (default 0)", "num", true },
		{ "exec", "Construction Failed", "Where to continue if construction failed" },
	},
	name = "Place Construction",
	desc = "Places a construction site for a specific structure",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	node_ui = build_produce_ui,
	produce_type = "Building",
}

data.instructions.produce =
{
	func = function(comp, state, cause)
		local inst, faction = GetSourceNode(state),  comp.faction
		local faction_library_id, faction_library = inst.bp, faction.extra_data.library
		local bp = faction_library_id and faction_library and faction_library[faction_library_id]
		local frame_id = bp and bp.frame or inst.frame
		if not frame_id then return end
		if bp and not BlueprintIsCustomized(bp) then bp = nil end

		local frame_def = data.frames[frame_id]
		local production_recipe = frame_def and frame_def.production_recipe
		if not production_recipe or not production_recipe.producers then return end
		if bp and not FactionHasUnlockedCustomBlueprint(faction, bp) then return end
		if not bp and not faction:IsUnlocked(frame_id) then return end

		local owner = comp.owner
		for k,v in pairs(production_recipe.producers) do
			local prodcomp = owner:FindComponent(k)
			if prodcomp then
				prodcomp:SetRegister(1, { id = frame_id, num = 1 })
				if bp then
					ProcessLibraryBlueprint(bp, function(processed_bp)
						prodcomp.extra_data.custom_blueprint = Tool.Copy(processed_bp)
					end)
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
	produce_type = "Bot",
}

data.instructions.set_signpost =
{
	func = function(comp, state, cause)
		comp.owner.extra_data.signpost = GetSourceNode(state).txt
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
				inst.txt = txt
				program_ui:set_dirty(true)
			end,
		})
		return 64
	end,
}

data.instructions.launch =
{
	func = function(comp, state, cause)
		local launcher = comp.owner:FindComponent("c_satellite_launcher")
		if launcher and comp.faction.has_blight_shield then
			EntityAction.LaunchAmac(comp.owner, { comp = launcher })
		end
	end,
	name = "Launch",
	desc = "Launches a satellite if equipped on an AMAC",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
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
		{ "in", "Target", "Target unit or coordinate", "coord" },
	},
	name = "Lookat",
	desc = "Turns the unit to look at a unit or a coordinate",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
}

data.instructions.land =
{
	func = function(comp, state, cause)
		local sat = comp.owner:FindComponent("c_satellite")
		if sat then
			local ed = comp.owner.extra_data
			local launcher = ed and ed.launched_by
			if not launcher or not launcher.exists then
				--Notification.Error("The satellite launcher was lost, unable to land")
				return
			end
			local item_slot = launcher:GetSlot(1)
			if not item_slot or item_slot.entity then
				--Notification.Error("The satellite launcher is not free for landing")
				return
			end

			EntityAction.LandSatellite(comp.owner)
		end
	end,
	name = "Land",
	desc = "Tells a satellite that has been launched to land",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
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
	args = { { "in", "Print Value", "Notification Value" } },
	name = "DebugPrint",
	desc = "Debug print to log",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Notify.png",
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
	if (ab.stored[id] or 0) >= amount and Map.FindClosestEntity(owner, ab.range, "Operating", func) then
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

	local time, first_prod_comp_id
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

		first_prod_comp_id = first_prod_comp_id or comp_id
	end
	if not time and (not recursiveness or recursiveness <= 20) then
		time = AutoBaseFulfill(ab, owner, first_prod_comp_id, 1, (recursiveness or 0) + 1, true)
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
		local signal_ent = comp.faction:GetEntitiesWithRegister(FRAMEREG_SIGNAL, true)
		for _,e in ipairs(signal_ent) do
			local unit_sig = e:GetRegister(FRAMEREG_SIGNAL)
			local signal_entity = unit_sig.entity
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
		{ "in", "Range", "Range of operation", "num" },
	},
	name = "Gather Information",
	desc = "Collect information for running the auto base controller",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
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
		{ "in", "Id", "Id to get register of" },
		{ "out", "Value", "Value of registered Unit" },
	},
	name = "Get Registered",
	desc = "Get number of registered buildings",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
}

data.instructions.make_carrier =
{
	func = function(comp, state, cause, frame_num, on_work)
		local ab = state.autobase
		if not ab then return end

		local frame_num = Get(comp, state, frame_num)
		if ab.carriers >= (frame_num.num or 1) then return end
		local sleep = AutoBaseFulfill(ab, comp.owner, frame_num.id, 1) or 3

		comp:SetStateSleep(sleep)
		state.counter = on_work
		return true
	end,
	args = {
		{ "in", "Carriers", "Type and count of carriers to make", "frame_num" },
		{ "exec", "If Working", "Where to continue if the unit started working" },
	},
	name = "Make Carriers",
	desc = "Construct carrier bots for delivering orders or to use for other tasks",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
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
			if not ab.free_socket_bot then
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
		{ "in", "Resource/Count", "Resource type and number of miners to maintain", "item_num" },
		{ "in", "Frame", "Unit to create if none are free"},
		{ "exec", "If Working", "Where to continue if the unit started working" },
	},
	name = "Make Miners",
	desc = "Construct and equip miner components on available carrier bots",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
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
	args = { { "exec", "If Working", "Where to continue if the unit started working" }, },
	name = "Serve Construction",
	desc = "Produce materials needed in construction sites",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
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
		local building = ab.free_building and Map.FindClosestEntity(owner, ab.range, "Operating", function(e)
			if e.faction ~= faction or not IsBuilding(e) or (e.has_extra_data and e.extra_data.autobase_register) then return end
			if e:GetFreeSocket(prodcomp_id) then return true end
			local prod = e:FindComponent(prodcomp_id)
			local prod = prod and prod:GetRegister(1)
			return  prod and prod.is_empty
		end)

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
		{ "in", "Item/Count", "Item type and number of producers to maintain", "item_num" },
		{ "in", "Component", "Production component", "comp" },
		{ "in", "Building", "Building type to use as producer", "frame" },
		{ "in", "Location", "Location offset from self", "coord" },
		{ "exec", "If Working", "Where to continue if the unit started working" },
	},
	name = "Make Producer",
	desc = "Build and maintain dedicated production buildings",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
}

data.instructions.make_turret_bots =
{
	func = function(comp, state, cause, frame_num, on_work)
		local ab = state.autobase
		if not ab then return end

		if ab.turret_bots >= GetNum(comp, state, frame_num) then return end

		local sleep = 3
		if not ab.free_socket_bot then
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
		{ "in", "Number", "Number of turret bots to maintain" },
		{ "exec", "If Working", "Where to continue if the unit started working" },
	},
	name = "Make Turret Bots",
	desc = "Construct and equip turret components on available carrier bots",
	category = "AutoBase",
	icon = "icon_input",
	key = "autobase",
}

data.instructions.build_registered =
{
	func = function(comp, state, cause, in_location, in_rotation, in_register, on_work, on_failed)
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

		local inst, faction = GetSourceNode(state),  comp.faction
		local faction_library_id, faction_library = inst.bp, faction.extra_data.library
		local bp = faction_library_id and faction_library and faction_library[faction_library_id]
		local frame_id = bp and bp.frame or inst.frame
		if not frame_id then state.counter = on_failed return end

		if bp then
			if not FactionHasUnlockedCustomBlueprint(faction, bp) then state.counter = on_failed return end
			ProcessLibraryBlueprint(bp, function(processed_bp) bp = Tool.Copy(processed_bp) end)
		else
			if not faction:IsUnlocked(frame_id) then state.counter = on_failed return end
			bp = { frame = frame_id }
		end
		bp.spawn_extra_data = { autobase_register = id }

		local location, rotation = GetCoord(comp, state, in_location), GetNum(comp, state, in_rotation)
		local loc = comp.owner.location
		local x, y = location.x, location.y
		local place_x, place_y = comp.faction:GetPlaceableLocation(frame_id, loc.x + x, loc.y + y, true)

		--if not faction:CanPlace(frame_id, x, y, rotation, true) then state.counter = on_failed return end

		Map.Defer(function()
			local e = CreateConstructionSite(faction, frame_id, place_x, place_y, rotation)
			e.extra_data.custom_blueprint = bp
		end)

		comp:SetStateSleep(1)
		state.counter = on_work
		return true
	end,
	args = {
		{ "in", "Coordinate", "Target location, or at currently location if not specified", "coord_num", true },
		{ "in", "Rotation", "Building Rotation (0 to 3) (default 0)", "num", true },
		{ "in", "Id", "Id to register with" },
		{ "exec", "If Working", "Where to continue if the unit started working" },
		{ "exec", "Construction Failed", "Where to continue if construction failed" },
	},
	name = "Build Registered",
	desc = "Places a building to be registered",
	category = "AutoBase",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	node_ui = build_produce_ui,
	produce_type = "Building",
	key = "autobase",
}

data.instructions.produce_registered =
{
	func = function(comp, state, cause, in_register, on_work)
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

		local inst, faction = GetSourceNode(state),  comp.faction
		local faction_library_id, faction_library = inst.bp, faction.extra_data.library
		local bp = faction_library_id and faction_library and faction_library[faction_library_id]
		local frame_id = bp and bp.frame or inst.frame
		if not frame_id then return end

		if bp then
			if not FactionHasUnlockedCustomBlueprint(faction, bp) then return end
			ProcessLibraryBlueprint(bp, function(processed_bp) bp = Tool.Copy(processed_bp) end)
		else
			if not faction:IsUnlocked(frame_id) then return end
			bp = { frame = frame_id }
		end
		bp.spawn_extra_data = { autobase_register = id }

		local frame_def = data.frames[frame_id]
		local production_recipe = frame_def and frame_def.production_recipe
		if not production_recipe or not production_recipe.producers then return end

		local owner = comp.owner
		for k,v in pairs(production_recipe.producers) do
			local prodcomp = owner:FindComponent(k)
			if prodcomp and prodcomp:GetRegisterId() == nil then
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
		{ "in", "Id", "Id to register with" },
		{ "exec", "If Working", "Where to continue if the unit started working" },
	},

	name = "Produce Registered Unit",
	desc = "Sets a production component to produce a blueprint",
	category = "Global",
	icon = "Main/skin/Icons/Special/Commands/Make Order.png",
	node_ui = build_produce_ui,
	produce_type = "Bot",
	key = "autobase",
}
