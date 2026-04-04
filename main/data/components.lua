--[[
data.components.samplecomponent = {
	name = "<NAME>",
	texture = "<PATH/TO/IMAGE.png>",

	-- Optional
	visual = "<VISUAL-ID>",
	slot_type = "storage|liquid|radioactive|...", -- default 'storage'
	attachment_size = "Hidden|Internal|Small|Medium|Large", -- default 'Hidden'
	activation = "None|Always|Manual|OnFirstRegisterChange|OnComponentRegisterChange|OnFirstItemSlotChange|OnComponentItemSlotChange|OnAnyItemSlotChange|OnLowPower|OnPowerStoredEmpty|OnTrustChange|OnOtherCompFinish", -- default 'None'
	-- note: OnAnyItemSlotChange can not be set with other change flags
	slots = { <SLOT_TYPE> = <NUM>, ... },
	registers = { ... },
	power = -0.1,
	power_storage = 1000,
	drain_rate = 1,
	charge_rate = 5,
	bandwidth = 2,
	transfer_radius = 10,
	adjust_extra_power = true, -- needs to be set if the extra_power field of the component object is used
	adjust_light_color = true, -- needs to be set if the light_color field of the component object is used
	dumping_ground = true,
	effect = "fx_power_core", -- automatically spawned when this components visual is placed on the map
	effect_socket = "fx",
	trigger_radius = 8,
	trigger_channels = "bot|building|bug",
	production_recipe = CreateProductionRecipe(
		{ <INGREDIENT_ITEM_ID> = <INGREDIENT_NUM>, ... },
		{ <PRODUCTION_COMPONENT_ID> = <PRODUCTION_TICKS>, }
		-- Optional
		<AMOUNT_NUM>, --default: 1
	),
	on_add = function(self, comp) ... end,
	on_remove = function(self, comp) ... end,
	on_placed = function(self, comp) ... end,
	on_update = function(self, comp, cause) ... end,
	on_trigger = function(self, comp, other_entity) ... end,
	on_take_damage = function(self, comp, amount) ... end,
	on_faction_change = function(self, comp, old_faction) ... end,
	extra_stat = { { img, value, name } } -- for displaying extra stats for a component
	transient = true -- not kept between relocation or Deployers
}
]]

function AddRacePuzzleItem(entity, explorable_race, faction)
	if explorable_race == "robot" and faction and entity.has_extra_data then
		local reward_diff = entity.extra_data.difficulty
		if reward_diff then
			if reward_diff <= 5 then
				entity:AddItem(GenerateRobotRewardComp(1), 1)
			elseif reward_diff <= 7 then
				entity:AddItem(GenerateRobotRewardComp(2), 1)
			else
				entity:AddItem(GenerateRobotRewardComp(3), 1)
			end
		else
			entity:AddItem(GenerateRobotRewardComp(1), 1)
		end
	elseif explorable_race == "human" and entity.has_extra_data then
		if entity.extra_data.itemreward == 1 then
			entity:AddItem("blight_crystal", math.random(2,6))
		elseif entity.extra_data.itemreward == 2 then
			if math.random() < 0.5 then
				entity:AddItem("laterite", math.random(10, 19))
			else
				entity:AddItem("blight_crystal", math.random(2,6))
			end
			local warehouse = { "aluminiumrod", "aluminiumsheet", "blight_crystal" }
			entity:AddItem(warehouse[math.random(1, #warehouse)], math.random(2,6))
		elseif entity.extra_data.itemreward == 3 then
			if math.random() < 0.5 then
				entity:AddItem("aluminiumrod", math.random(2,6))
			else
				entity:AddItem("aluminiumsheet", math.random(2,6))
			end
		elseif entity.extra_data.itemreward == 4 then
			entity:AddItem("micropro", math.random(1,3))
		end
	end
end

function AddRaceTechItem(entity, explorable_race, faction)
	if explorable_race == "human" then
		local human_resources = { "aluminiumrod", "aluminiumsheet", "laterite"}
		entity:AddItem(human_resources[math.random(#human_resources)], math.random(2,5))
	--elseif explorable_race == "alien" then
	--	entity:AddItem("alien_datacube", math.random(2,3))
	elseif explorable_race == "robot" then
		if entity.has_extra_data then
			local reward_diff = entity.extra_data.difficulty
			local amt = math.random(1,5)
			if reward_diff then
				if reward_diff < 5 then
					entity:AddItem(GenerateRobotRewardItem(1), amt)
				elseif reward_diff <= 9 then
					entity:AddItem(GenerateRobotRewardItem(2), amt)
				else
					entity:AddItem(GenerateRobotRewardItem(3), amt)
				end
			else
				entity:AddItem(GenerateRobotRewardItem(1), amt)
			end
		end
	elseif explorable_race == "anomaly" then
		-- higher level tech
		local newcomp = GenerateRobotRewardComp(4)
		if newcomp then
			entity:AddItem(newcomp, 1)
		end
	end
end

data.component_register_filters = {
	color  = function(def, cat) return def.tag == "color" or cat.number_panel end,
	world  = function(def, cat) return cat.coord_panel or cat.entity_panel end,
	entity = function(def, cat) return cat.entity_panel end,
	coord  = function(def, cat) return cat.coord_panel end,
	number = function(def, cat) return cat.number_panel end,
	alien_synthesis = function(def, cat)
		return (def.attachment_size == "Internal" or def.attachment_size == "Small")
	end,
}

local function def_comp_activate(def, comp)
	comp:Activate()
end

local function reveal_if_stealthed(owner)
	if not owner.stealth then return end
	local stealth_component = owner:FindComponent("c_stealth", true)
	if not stealth_component then return end
	stealth_component.def:disable_stealth(owner)
	stealth_component:Activate()
end

local function on_add_charge(def, comp)
	comp.extra_data.charged = false
	comp:Activate() -- trigger to charge
end

local function on_remove_clear_extra_data(def, comp)
	comp.extra_data = nil
end

local function on_remove_clear_extra_data_keep_resimulated(def, comp)
	if not comp.has_extra_data then return end
	local ed = comp.extra_data
	if not ed.resimulated then
		comp.extra_data = nil
	elseif next(ed, next(ed)) then -- clear if there is anything but resimulated
		comp.extra_data = { resimulated = ed.resimulated }
	end
end

local function action_tooltip_set_target(def)
	return L("Set %s Target", def.name)
end

------------------------------------------------------
-- Base table for all components
Comp = {
	slot_type = "storage",
	stack_size = 1,
	texture = "Main/textures/icons/frame/replace.png"
}

function Comp:RegisterComponent(id, comp)
	comp.id = id
	comp.base_id = self.base_id or self.id or id
	if not comp.name then comp.name = id end
	--for k,v in pairs(comp) do if Tool.Hash(v) == Tool.Hash(self[k]) and k ~= "base_id" then print("COMPONENT INFO: Inherited component contains duplicated field value: " .. tostring(id) .. " (" .. tostring(k) .. " = " .. tostring(v):gsub("\n", "") .. ")") end end
	data.components[id] = setmetatable(comp, { __index = self })
	return comp
end
-----------------------------------------------
--------------- BOOST MODULES -----------------
-----------------------------------------------
local function BoostModuleOnAdd(self, comp) self:on_update_boosts(comp) end
local function BoostModuleOnRemove(self, comp) self:on_update_boosts(comp, comp) end


---------------- MAX HEALTH Boost Modules ----------------

local c_modulehealth = Comp:RegisterComponent("c_modulehealth",{
	attachment_size = "Internal", race = "robot", index = 1052, name = "Internal Health Module",
	desc = "Increased structural integrity, adds 200 durability",
	texture = "Main/textures/icons/components/module_health.png",
	visual = "v_generic_i",
	boost = 200, -- 20,
	power = -2,
	production_recipe = CreateProductionRecipe({ icchip = 1, refined_crystal = 1 }, { c_advanced_assembler = 30, }),
	on_add = BoostModuleOnAdd,
	on_remove = BoostModuleOnRemove,
})

function c_modulehealth:on_update_boosts(comp, remove_comp)
	local owner = comp.owner
	owner.max_health = (owner.def.health_points or 100) + SumModuleBoosts(owner, "c_modulehealth", remove_comp)
end

c_modulehealth:RegisterComponent("c_modulehealth_s",{
	attachment_size = "Small", race = "robot", index = 1052, name = "Small Health Module",
	desc = "Increased structural integrity, adds 400 durability",
	texture = "Main/textures/icons/components/Component_ModuleHealth_01_S.png",
	production_recipe = CreateProductionRecipe({ icchip = 5, hdframe = 5 }, { c_advanced_assembler = 60, }),
	visual = "v_modulehealth_s",
	boost = 400, -- 100,
	power = -2,
})

c_modulehealth:RegisterComponent("c_modulehealth_m",{
	attachment_size = "Medium", race = "robot", index = 1052, name = "Medium Health Module",
	desc = "Increased structural integrity, adds 600 durability",
	texture = "Main/textures/icons/components/Component_ModuleHealth_01_M.png",
	production_recipe = CreateProductionRecipe({ icchip = 8, hdframe = 8 }, { c_advanced_assembler = 80, }),
	visual = "v_modulehealth_m",
	boost = 600, -- 200,
	power = -2,
})

c_modulehealth:RegisterComponent("c_modulehealth_l",{
	attachment_size = "Large", race = "robot", index = 1052, name = "Large Health Module",
	desc = "Increased structural integrity, adds 1000 durability",
	texture = "Main/textures/icons/components/Component_ModuleHealth_01_L.png",
	production_recipe = CreateProductionRecipe({ icchip = 10, hdframe = 10 }, { c_advanced_assembler = 100, }),
	visual = "v_modulehealth_l",
	boost = 1000, -- 300,
	power = -2,
})

---------------- VISIBILITY RANGE Boost Modules ----------------

local c_modulevisibility = Comp:RegisterComponent("c_modulevisibility",{
	attachment_size = "Internal", race = "robot", index = 1054, name = "Internal Visibility Module",
	desc = "Increase visibility range by 5",
	texture = "Main/textures/icons/components/module_visibility.png",
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ icchip = 1, refined_crystal = 1 }, { c_advanced_assembler = 30, }),
	boost = 5,
	power = -2,
	on_add = BoostModuleOnAdd,
	on_remove = BoostModuleOnRemove,
})

function c_modulevisibility:on_update_boosts(comp, remove_comp)
	local owner = comp.owner
	Map.Defer(function() if owner.exists then
		owner.visibility_range = (owner.def.visibility_range or 1) + SumModuleBoosts(owner, "c_modulevisibility", remove_comp)
	end end)
end

c_modulevisibility:RegisterComponent("c_modulevisibility_s",{
	attachment_size = "Small", race = "robot", index = 1054, name = "Small Visibility Module",
	desc = "Increase visibility range by 10",
	production_recipe = CreateProductionRecipe({ icchip = 5, hdframe = 5 }, { c_advanced_assembler = 60, }),
	texture = "Main/textures/icons/components/Component_ModuleVisibility_01_S.png",
	visual = "v_modulevis_s",
	boost = 10,
	power = -2,
})

c_modulevisibility:RegisterComponent("c_modulevisibility_m",{
	attachment_size = "Medium", race = "robot", index = 1054, name = "Medium Visibility Module",
	desc = "Increase visibility range by 15",
	production_recipe = CreateProductionRecipe({ icchip = 8, hdframe = 8 }, { c_advanced_assembler = 80, }),
	texture = "Main/textures/icons/components/Component_ModuleVisibility_01_M.png",
	visual = "v_modulevis_m",
	boost = 15,
	power = -2,
})

c_modulevisibility:RegisterComponent("c_modulevisibility_l",{
	attachment_size = "Large", race = "robot", index = 1054, name = "Large Visibility Module",
	desc = "Increase visibility range by 20",
	production_recipe = CreateProductionRecipe({ icchip = 10, hdframe = 10 }, { c_advanced_assembler = 100, }),
	texture = "Main/textures/icons/components/Component_ModuleVisibility_01_L.png",
	visual = "v_modulevis_l",
	boost = 20,
	power = -2,
})

---------------- COMPONENT EFFICIENCY Boost Modules ----------------

local function ReSimulatorApplyBoosts(comp, remove_comp)
	local base_id, entity = comp.base_id, comp.owner

	if base_id == "c_resimulator" or base_id == "c_virus_ac" or base_id == "c_blight_ac" then
		local add_id, remove_id = not remove_comp and base_id, remove_comp and base_id
		local num_resim  = entity:CountComponents("c_resimulator", true)
		local had_resim  = (num_resim - (add_id    == "c_resimulator" and 1 or 0)) > 0
		local have_resim = (num_resim - (remove_id == "c_resimulator" and 1 or 0)) > 0

		if base_id == "c_resimulator" or base_id == "c_virus_ac" then
			local num_virus_ac = entity:CountComponents("c_virus_ac", true)
			local old_virus_ac = (num_virus_ac - (add_id    == "c_virus_ac" and 1 or 0)) * (had_resim  and 1 or 0)
			local new_virus_ac = (num_virus_ac - (remove_id == "c_virus_ac" and 1 or 0)) * (have_resim and 1 or 0)
			for i=old_virus_ac,new_virus_ac-1, 1 do StabilityAdd(entity.faction, "core_virus") end
			for i=old_virus_ac,new_virus_ac+1,-1 do StabilitySub(entity.faction, "core_virus") end
		end

		if base_id == "c_resimulator" or base_id == "c_blight_ac" then
			local num_blight_ac = entity:CountComponents("c_blight_ac", true)
			local old_blight_ac = (num_blight_ac - (add_id    == "c_blight_ac" and 1 or 0)) * (had_resim  and 1 or 0)
			local new_blight_ac = (num_blight_ac - (remove_id == "c_blight_ac" and 1 or 0)) * (have_resim and 1 or 0)
			for i=old_blight_ac,new_blight_ac-1, 1 do StabilityAdd(entity.faction, "core_blight") end
			for i=old_blight_ac,new_blight_ac+1,-1 do StabilitySub(entity.faction, "core_blight") end
		end
	end

	if base_id == "c_resimulator" or base_id == "c_moduleefficiency_g" then
		local faction = entity.faction
		local eff_comps, boost_sum, errs = faction:GetComponents("c_moduleefficiency_g", true), 100
		for i,eff_comp in ipairs(eff_comps) do
			if eff_comp ~= remove_comp then
				local eff_have_resim = eff_comp.owner:FindComponent("c_resimulator", true)
				if eff_have_resim == remove_comp then eff_have_resim = eff_comp.owner:FindComponent("c_resimulator", true, 2) end
				if eff_have_resim then
					boost_sum = boost_sum + eff_comp.def.boost
				else
					errs = errs or {}
					errs[i] = true
				end
			end
		end
		faction.component_boost = boost_sum
		for i,eff_comp in ipairs(eff_comps) do
			eff_comp:SetRegister(1, { id = eff_comp.id, num = boost_sum })
			if errs and errs[i] then eff_comp:FlagRegisterError(1, true) end
		end
	end
end

local function ReSimulatorModuleOnAdd(self, comp) ReSimulatorApplyBoosts(comp) end
local function ReSimulatorModuleOnRemove(self, comp) ReSimulatorApplyBoosts(comp, comp) end

local c_moduleefficiency_g = Comp:RegisterComponent("c_moduleefficiency_g", {
	attachment_size = "Internal", race = "robot", index = 1055, name = "Global Overclocking Boost",
	desc = "Global Overclocking Rate <hl>+50%</>, must be equipped on a Re-Simulator",
	texture = "Main/textures/icons/components/module_simulation_efficiency.png",
	visual = "v_generic_i",
	boost = 50, -- boost 50%
	registers = { { warning = "Current Global Efficiency Boost", read_only = true } },
	on_add = ReSimulatorModuleOnAdd,
	on_remove = ReSimulatorModuleOnRemove,
})

function c_moduleefficiency_g:get_reg_error(comp)
	return "Must be equipped on a Re-Simulator"
end

c_moduleefficiency_g:RegisterComponent("c_moduleefficiency_5", {
	attachment_size = "Internal", race = "robot", index = 1056, name = "Global Overclocking Boost",
	desc = "Global Overclocking Rate <hl>+5%</>, must be equipped on a Re-Simulator",
	boost = 5,
})

local c_moduleefficiency = Comp:RegisterComponent("c_moduleefficiency",{
	attachment_size = "Internal", race = "robot", index = 1051, name = "Internal Overclocking Module",
	desc = "Overclock component by 20%",
	texture = "Main/textures/icons/components/module_efficiency.png",
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ icchip = 1, refined_crystal = 1 }, { c_advanced_assembler = 30, }),
	boost = 20,
	on_add = BoostModuleOnAdd,
	on_remove = BoostModuleOnRemove,
})

function c_moduleefficiency:on_update_boosts(comp, remove_comp)
	local owner = comp.owner
	owner.component_boost = 100 + (owner.def.component_boost or 0) + SumModuleBoosts(owner, "c_moduleefficiency", remove_comp)
end

c_moduleefficiency:RegisterComponent("c_moduleefficiency_s",{
	attachment_size = "Small", race = "robot", index = 1051, name = "Small Overclocking Module",
	desc = "Overclock component by 50%",
	texture = "Main/textures/icons/components/Component_ModuleEfficiency_01_S.png",
	visual = "v_moduleoc_s",
	production_recipe = CreateProductionRecipe({ icchip = 5, hdframe = 5 }, { c_advanced_assembler = 60, }),
	boost = 50,
})

c_moduleefficiency:RegisterComponent("c_moduleefficiency_m",{
	attachment_size = "Medium", race = "robot", index = 1051, name = "Medium Overclocking Module",
	desc = "Overclock component by 100%",
	texture = "Main/textures/icons/components/Component_ModuleEfficiency_01_M.png",
	visual = "v_moduleoc_m",
	production_recipe = CreateProductionRecipe({ icchip = 8, hdframe = 8 }, { c_advanced_assembler = 80, }),
	boost = 100,
})

c_moduleefficiency:RegisterComponent("c_moduleefficiency_l",{
	attachment_size = "Large", race = "robot", index = 1051, name = "Large Overclocking Module",
	desc = "Overclock component by 150%",
	texture = "Main/textures/icons/components/Component_ModuleEfficiency_01_L.png",
	visual = "v_moduleoc_l",
	production_recipe = CreateProductionRecipe({ icchip = 10, hdframe = 10 }, { c_advanced_assembler = 100, }),
	boost = 150,
})

---------------- MOVE SPEED Boost Modules ----------------

local c_modulespeed = Comp:RegisterComponent("c_modulespeed",{
	attachment_size = "Internal", race = "robot", index = 1053, name = "Internal Movement Speed Module",
	desc = "Increase unit movement speed by 20%",
	texture = "Main/textures/icons/components/module_speed.png",
	production_recipe = CreateProductionRecipe({ icchip = 1, refined_crystal = 1 }, { c_advanced_assembler = 30, }),
	visual = "v_generic_i",
	boost = 20,
	on_add = BoostModuleOnAdd,
	on_remove = BoostModuleOnRemove,
})

function c_modulespeed:on_update_boosts(comp, remove_comp)
	local owner = comp.owner
	owner.move_boost = 100 + SumModuleBoosts(owner, "c_modulespeed", remove_comp)
end

c_modulespeed:RegisterComponent("c_modulespeed_s",{
	attachment_size = "Small", race = "robot", index = 1053, name = "Small Movement Speed Module",
	desc = "Increase unit movement speed by 50%",
	production_recipe = CreateProductionRecipe({ icchip = 5, hdframe = 5 }, { c_advanced_assembler = 60, }),
	texture = "Main/textures/icons/components/Component_ModuleSpeed_01_S.png",
	visual = "v_modulespeed_s",
	boost = 50,
	power = -2,
})

c_modulespeed:RegisterComponent("c_modulespeed_m",{
	attachment_size = "Medium", race = "robot", index = 1053, name = "Medium Movement Speed Module",
	desc = "Increase unit movement speed by 80%",
	production_recipe = CreateProductionRecipe({ icchip = 8, hdframe = 8 }, { c_advanced_assembler = 80, }),
	texture = "Main/textures/icons/components/Component_ModuleSpeed_01_M.png",
	visual = "v_modulespeed_m",
	boost = 80,
	power = -2,
})

c_modulespeed:RegisterComponent("c_modulespeed_l",{
	attachment_size = "Large", race = "robot", index = 1053, name = "Large Movement Speed Module",
	desc = "Increase unit movement speed by 120%",
	production_recipe = CreateProductionRecipe({ icchip = 10, hdframe = 10 }, { c_advanced_assembler = 100, }),
	texture = "Main/textures/icons/components/Component_ModuleSpeed_01_L.png",
	visual = "v_modulespeed_l",
	boost = 120,
	power = -2,
})

------------------------------------------------------
-- extra effects
local function dot_effect(compdef, comp, target)
	if not target.def.immortal and target.has_component_list then
		local dot = target:FindComponent("c_dot_effect")
		if dot then
			local ed = dot.extra_data
			ed.count, ed.compid, ed.damager = 0, comp.id, comp.owner
		else
			target:AddComponent("c_dot_effect", "hidden", { count = 0, compid = comp.id, damager = comp.owner })
		end
	end
end

Comp:RegisterComponent("c_dot_effect",{
	name = "Damage Over Time",
	desc = "Damage Over Time",
	texture = "Main/textures/icons/components/module_speed.png",
	visual = "v_generic_i",
	power = 0,
	activation = "Always",
	damage_type = "plasma_damage",
	on_update = function(self, comp, cause)
		local ed = comp.extra_data
		local weapon_def = data.all[ed.compid]
		if weapon_def then
			local owner, dps, damage_type = comp.owner, weapon_def.dotdps or 1, weapon_def.damage_type or "plasma"
			AddDamagedEnemy(owner, dps, damage_type)
			if owner.is_placed then owner:PlayEffect("fx_plasmasplat_1") end
			owner:RemoveHealth(dps, ed.damager, damage_type)
		end
		local count = (ed.count or 0) + 1
		if count >= (weapon_def and weapon_def.dothits or 1) then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end
		ed.count = count
		comp:SetStateSleep(TICKS_PER_SECOND)
	end,
})

local function slow_effect(compdef, comp, target)
	if not target.def.immortal and target.has_component_list
		and not target.faction:IsUnlocked("t_robots_antivirus")
		then
		local c = target:FindComponent("c_slow_effect")
		if c then
			c:Activate() -- restart duration
		else
			target:AddComponent("c_slow_effect", "hidden")
		end
		c = target:FindComponent("c_sluggish_effect")
		if c then
			c:Activate() -- restart duration
		else
			target:AddComponent("c_sluggish_effect", "hidden")
		end
	end
end

local function shieldrecharge_effect(compdef, comp, target)
	local charge = compdef.shield_charge
	for i=1,999 do
		if charge <= 0 then break end
		local shield_comp = comp.owner:FindComponent("c_shield_generator", true, i)
		if not shield_comp then break end
		charge = shield_comp.def:ChargeShield(shield_comp, charge)
	end
end

local function heal_effect(compdef, comp, target)
	local owner = comp.owner
	owner:AddHealth(compdef.healamt or 1)

	if owner.health == owner.max_health and math.random(1,4) == 1 then
		local loc = owner.location
		owner:MoveTo(loc.x + math.random(-3, 3), loc.y + math.random(-3, 3))
	end
end

local function electromag_effect(compdef, comp, target)
	local damage = compdef.disruptor
	for i=1,999 do
		if damage <= 0 then break end
		local shield_comp = target:FindComponent("c_shield_generator", true, i)
		if not shield_comp then break end
		damage = shield_comp.def:ApplyShieldDamage(shield_comp, damage, "electromag_damage")
	end
	shieldrecharge_effect(compdef, comp, target)
end

local function bitlock_effect(comp_def, comp, target)
	if not target.def.immortal and target.has_component_list
		and not target.faction:IsUnlocked("t_robots_antivirus")
		and not target:FindComponent("c_virus_protection")
		--and not target:FindComponent("c_virus_cure")
		and (not target.def.movement_speed or target.def.movement_speed > 0) then
		local effect = target:FindComponent("c_virus_bitlock_effect")
		if effect then
			effect.extra_data.count = 0
		else
			target:AddComponent("c_virus_bitlock_effect", "hidden", { wasshutoff = target.powered_down, count = 0 })
		end
	end
end

Comp:RegisterComponent("c_virus_bitlock_effect", {
	name = "BitLock Effect",
	effect = "fx_glitch2",
	activation = "Always",
	texture = "Main/textures/icons/components/Component_Virus3.png",
	desc = "bitlock effect",
	race = "virus",
	power = -5,
	on_update = function(self, comp, cause)
		comp.owner:Cancel()
		comp.owner.powered_down = true
		local ed = comp.extra_data
		local count = (ed.count or 0) + 1
		if count > 5 then
			comp.owner.powered_down = ed.wasshutoff
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end
		ed.count = count
		comp:SetStateSleep(TICKS_PER_SECOND)
	end,
})

c_modulespeed:RegisterComponent("c_slow_effect",{
	attachment_size = "Hidden", race = false, index = 9999, name = "Internal Slow Module",
	desc = "Decrease unit movement speed by 50%",
	production_recipe = false,
	texture = "Main/textures/icons/components/module_speed.png",
	visual = "v_generic_i",
	boost = -50,
	power = 0,
	activation = "Always",
	on_add = BoostModuleOnAdd,
	on_remove = BoostModuleOnRemove,
	duration = 25, -- duration of slow
	on_update = function(self, comp, cause)
		if cause & CC_FINISH_SLEEP == CC_FINISH_SLEEP then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end
		comp:SetStateSleep(self.duration)
	end,
})

c_moduleefficiency:RegisterComponent("c_sluggish_effect",{
	attachment_size = "Hidden", race = false, index = 9999, name = "Internal Low Efficiency Module",
	desc = "Decrease efficiency by 50%",
	production_recipe = false,
	texture = "Main/textures/icons/components/module_speed.png",
	visual = "v_generic_i",
	boost = -50,
	power = 0,
	activation = "Always",
	on_add = BoostModuleOnAdd,
	on_remove = BoostModuleOnRemove,
	duration = 25, -- duration of sluggish
	on_update = function(self, comp, cause)
		if cause & CC_FINISH_SLEEP == CC_FINISH_SLEEP then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end
		comp:SetStateSleep(self.duration)
	end,
})

------------------------ player components
local function battery_get_ui(self, comp)
	return UI.New([[<Box padding=4><Progress valign=center width=54 height=54 progress={progress} bg=progress_mask orientation=vertical color=ui_light bgcolor=ui_dark/></Box>]], {
		compicon = comp.def.texture,
		update = function(w)
			local comp_def, comp_details = comp.def, comp.power_details
			if comp_details then
				w.progress = comp_details.stored / comp_def.power_storage
				if w.tt then
					w.tt.text = L((comp_details.change ~= 0 and "%s: %.0f/%.0f (%+.0f)" or "%s: %.0f/%.0f"), "Stored", comp_details.stored, comp_def.power_storage, comp_details.change*TICKS_PER_SECOND)
				end
			end
		end,
		tooltip = function(w)
			w.tt = UI.New("<Box bg=popup_box_bg padding=12><Text/></Box>", { destruct = function() if w:IsValid() then w.tt = nil end end })[1]
			w:update()
			return w.tt.parent
		end,
	})
end


----- light -----
Comp:RegisterComponent("c_light", {
	attachment_size = "Small", race = "robot", index = 1044, name = "Light",
	texture = "Main/textures/icons/components/component_light_01_s.png",
	desc = "Illuminates the immediate area. Brightness and color can be changed via a register.",
	visual = "v_light_01_s",
	production_recipe = CreateProductionRecipe({ metalbar = 1, crystal = 1 }, { c_assembler = 5 }),
	adjust_light_color = true,
	default_light_color = { 1.0, 1.0, 1.0 },
	activation = "OnFirstRegisterChange",
	registers = { { filter = "color" } },
	on_update = function(self, comp)
		local intensity, reg_id = comp:GetRegisterData(1)
		local value_def = data.values[reg_id]
		local col = (value_def and value_def.color or self.default_light_color)
		comp.light_color = { col[1], col[2], col[3], ((intensity or 0) == 0 and 10 or math.min(intensity, 20)) }
	end,
})

Comp:RegisterComponent("c_light_rgb", {
	attachment_size = "Small", race = "robot", index = 1045, name = "Light RGB",
	texture = "Main/textures/icons/components/component_light_02_s.png",
	desc = "Illuminates the immediate area. Brightness and color can be changed via RGB registers.",
	visual = "v_light_01_s",
	production_recipe = CreateProductionRecipe({ metalbar = 1, crystal = 1 }, { c_assembler = 5 }),
	adjust_light_color = true,
	default_light_color = { 1.0, 1.0, 1.0, 10.0 },
	activation = "OnComponentRegisterChange",
	registers = {
		{ filter = "number", tip = "Red (0-31)", ui_icon="Main/textures/icons/color/color_red.png" },
		{ filter = "number", tip = "Green (0-31)", ui_icon="Main/textures/icons/color/color_green.png" },
		{ filter = "number", tip = "Blue  (0-31)", ui_icon="Main/textures/icons/color/color_blue.png" },
		{ filter = "number", tip = "Intensity", } },
	on_update = function(self, comp)
		local r, g, b, i = comp:GetRegisterNum(1), comp:GetRegisterNum(2), comp:GetRegisterNum(3), comp:GetRegisterNum(4)
		if r == 0 and g == 0 and b == 0 and i == 0 and comp:RegisterIsEmpty(1) and comp:RegisterIsEmpty(2) and comp:RegisterIsEmpty(3) and comp:RegisterIsEmpty(4) then
			comp.light_color = self.default_light_color
		else
			comp.light_color = { r / 31, g / 31, b / 31, (i == 0 and 10 or math.min(comp:GetRegisterNum(4), 64)) }
		end
	end,
})

----- fabricator -----
local function comp_create_link_to_visual(comp_def, comp)
	local reg = comp.owner:GetRegister(FRAMEREG_VISUAL)
	if reg.is_empty or reg.is_link then
		comp:LinkRegisterFromRegister(FRAMEREG_VISUAL, 1)
	end
end

local c_fabricator = Comp:RegisterComponent("c_fabricator", {
	attachment_size = "Small", race = "robot", index = 1001, name = "Fabricator",
	texture = "Main/textures/icons/components/Component_Fabricator_01_S.png",
	desc = "A small fabrication system able to process raw resources and simple components. Missing ingredients are available via register.",
	visual = "v_fabricator_01_s",
	power = -5,
	production_recipe = CreateProductionRecipe({ metalbar = 5, crystal = 5 }, { c_fabricator = 20, c_assembler = 20 }),
	production_effect = "fx_fabricator",
	activation = "OnFirstRegisterChange",
	registers = {
		{ type = "production", tip = "Click to change production", ui_apply = "Set Production", ui_icon = "icon_output" },
		{ tip = "Missing ingredient", warning = "Missing ingredient", read_only = true },
	},
	is_missing_ingredient_register = function(idx) return idx == 2 end,
	link_to_visual = true,
	on_add = comp_create_link_to_visual,
	get_ui = true,
})

function c_fabricator:action_tooltip() return L("Set %s Production", self.name) end
function c_fabricator:action_click(comp, widget)
	ShowRegisterSelection(widget, comp.owner, comp, 1)
end

function c_fabricator:get_reg_error(comp)
	local reg1_id, reg1_num, missing_id = comp:GetRegisterId(1), comp:GetRegisterNum(1), comp:GetRegisterId(2)
	local reg1_entity = not reg1_id and comp:GetRegisterEntity(1)
	if reg1_entity then reg1_id = reg1_entity.id end
	local product_def, blueprint_def = GetProduction(reg1_id, comp)
	local production_recipe = product_def and product_def.production_recipe
	local name = (blueprint_def and NOLOC(blueprint_def.name)) or (product_def and product_def.name) or (data.all[reg1_id] and data.all[reg1_id].name) or reg1_id or "this"

	if product_def and not comp.faction:IsUnlocked(reg1_id) then
		return L("Missing research to produce %s", name)
	elseif not production_recipe or not production_recipe.producers[self.id] then
		return L("Cannot produce %s in %s", name, self.name)
	elseif missing_id and (comp.owner:HaveFreeSpace(reg1_id) or product_def.data_name == "frames") then
		return L("Missing production ingredient %s", (data.all[missing_id] and data.all[missing_id].name or missing_id))
	elseif reg1_num and reg1_num == 0 then
		return "Cannot produce zero items"
	else
		return L("No inventory space to produce %s", name)
	end
end

function c_fabricator:end_production(comp, missing_item, flag_error, clear_extra)
	comp:SetRegister(2, missing_item)
	comp:FlagRegisterError(1, flag_error)
	comp:StopEffects()
	comp.animation_speed = 0
	if clear_extra then comp.extra_data = nil end
end

function c_fabricator:on_update(comp, cause)
	local count, reg1_id, reg1_entity = comp:GetRegisterData(1)
	if reg1_entity then reg1_id = reg1_entity.id end
	local product_def, blueprint_def
	if reg1_id then product_def, blueprint_def = GetProduction(reg1_id, comp) end

	if not product_def then
		-- Production cancel requested
		return self:end_production(comp, nil, count ~= nil, true)
	end

	if count == 0 then
		-- Invalid production amount, clear temporary blueprint
		return self:end_production(comp, nil, true, reg1_entity)
	end

	-- Complex check to make sure that something invalid can't be produced by just changing the number on a linked register
	local is_new_product = (cause & CC_ACTIVATED == CC_ACTIVATED) and ((cause & CC_CHANGED_REGISTER_ID == CC_CHANGED_REGISTER_ID) or not comp.is_working)
	local is_finish_production = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - is_new_product: " .. tostring(is_new_product) .. " - is_finish_production: " .. tostring(is_finish_production) .. " - has_power: " .. tostring(comp.owner.has_power))

	local production_recipe = product_def.production_recipe
	local production_ticks = production_recipe and production_recipe.producers[self.id]
	if is_new_product and not production_ticks then
		-- Invalid product or product that can't be produced by this component requested, forward it into missing ingredient register
		--print("[" .. comp.id .. ":on_update] Cannot produce " .. reg1_id)
		return self:end_production(comp, comp:GetRegister(1), true)
	end

	if (is_new_product or comp.ticker_target == 16) and not comp.faction:IsUnlocked(reg1_id) then
		--print("[" .. comp.id .. ":on_update] Haven't unlocked production item " .. reg1_id)
		self:end_production(comp, nil, true)
		return comp:SetStateSleep(16) -- sleep for a while, it might get unlocked
	end

	if reg1_entity and reg1_entity:ExistsOnFaction(comp.faction) and (not blueprint_def or (cause & CC_CHANGED_REGISTER_ENTITY) ~= 0) then
		blueprint_def = reg1_entity.faction == comp.faction and MakeBlueprintFromEntity(reg1_entity, nil, nil, true) or nil
		comp.extra_data.custom_blueprint = blueprint_def -- store temporary blueprint
	elseif (cause & CC_CHANGED_REGISTER_ENTITY) ~= 0 and blueprint_def and not (reg1_entity and reg1_entity:ExistsOnFaction(comp.faction)) then
		blueprint_def, comp.extra_data = nil, nil -- clear temporary blueprint
	end

	local is_bot_production = product_def.data_name == "frames"
	if is_finish_production and is_bot_production and is_new_product then
		-- Producing a bot can't finish and start new production in the same tick (because we don't know anymore what the register was set to when it started)
		is_finish_production = false
	end

	if is_finish_production then
		-- Finished production
		local drone_slot = is_bot_production and comp:GetProcessOutputSlot()
		local bot_ingredient_extra_datas = comp:FulfillProcess(is_bot_production)

		if is_bot_production then
			local owner = comp.owner
			local faction, location = owner.faction, owner.location
			if (product_def.movement_speed or 0) > 0 then
				FactionCount("built_bot", 1, faction)
			end
			if reg1_id == "f_bot_1s_b" then
				FactionCount("built_bot_1s_b", true, faction)
			end
			if reg1_id == "f_bot_2s" then
				FactionCount("built_bot_2s", true, faction)
			end
			if blueprint_def then
				FactionCount("built_bp_bot", true, faction)
			end
			Map.Defer(function()
				-- Create frame
				local built = CreateFrameOrBlueprint(faction, blueprint_def or product_def, nil, bot_ingredient_extra_datas)
				if not built then return end
				if drone_slot and drone_slot.exists then
					drone_slot.entity = built
				elseif not owner.exists or not built:DockInto(owner) then
					-- Put into world if it can't spawn docked into the production frame
					built:Place(owner.exists and owner.is_placed and owner or location)
					built:PlayEffect("fx_digital_in")
				end
				if comp.exists and not comp:RegisterIsEmpty(3) then
					local rally_reg = comp:GetRegister(3)
					if rally_reg.coord then
						built:MoveTo(rally_reg.coord, rally_reg.num)
					else
						EntitySetGoto(built, rally_reg, true)
					end
				end
			end)
		end

		if count >= 0 then
			if comp:RegisterIsLink(1) then
				local src_index, src_entity, src_comp = comp:GetRegisterLinkSource(1)
				local src_comp_def = src_comp and src_comp.def
				if not src_comp_def then
					-- source is a frame register which won't change on its own, continue with count as is
				elseif not src_comp_def.is_missing_ingredient_register or src_entity ~= comp.owner then
					-- source is on a different entity or a component which we don't know if it changes on its own, wait until next tick to see if it changes
					comp:FlagRegisterError(1, false)
					return comp:SetStateSleep(1)
				elseif src_comp_def.is_missing_ingredient_register(src_index) then
					-- source is a missing ingredient type register which will count down by the just produced amount
					if src_comp.is_sleeping then
						src_comp:Activate() -- wake up
					end
					count = count - production_recipe.amount
					if count <= 0 then
						-- Finished last production (but check again in 5 ticks that it really was last, there might be multiple link sources)
						self:end_production(comp, nil, false)
						return comp:SetStateSleep(5)
					end
				end
			else
				count = count - production_recipe.amount
				if count <= 0 then
					-- Finished last production
					comp:SetRegister(1, nil)
					return self:end_production(comp, nil, false, true)
				end
				comp:SetRegisterNum(1, count)
			end
		end
	end

	if not production_recipe then
		-- Cancel if recipe changed in old save / somehow got here and no recipe
		return self:end_production(comp, nil, count > 0)
	end

	-- Get production ingredients
	local ingredients = GetIngredients(production_recipe, blueprint_def)

	-- Prepare next production
	local outputs = (not is_bot_production or (self.slots and self.slots[product_def.slot_type])) and { [reg1_id] = production_recipe.amount }
	local order_count = (count + production_recipe.amount - 1) // production_recipe.amount
	local can_make, missing_register = comp:PrepareProduceProcess(ingredients, outputs, order_count)
	if not can_make then
		-- Missing ingredient or no space for output
		self:end_production(comp, missing_register, true)
		return comp:SetStateSleep()
	end

	comp:SetRegister(2, nil)
	comp:FlagRegisterError(1, false)
	if comp.owner.is_placed then
		comp:PlayWorkEffect(self.production_effect or "fx_fabricator", "fx")
		comp:SetWorkAnimationSpeed()
	end

	if not is_new_product and not is_finish_production and comp.is_working then
		-- Not a new production, no need to restart the work timer
		return comp:SetStateContinueWork()
	end

	-- Start work for as many ticks as the recipe requires
	return comp:SetStateStartWork(production_ticks)
end

----- assembler : fabricator -----
c_fabricator:RegisterComponent("c_assembler", {
	attachment_size = "Medium", race = "robot", index = 1001, name = "Assembler",
	texture = "Main/textures/icons/components/Component_Assembler_01_M.png",
	desc = "Main production facility for robotic components and robotic materials",
	visual = "v_assembler_01_m",
	production_effect = "fx_assembler",
	power = -10,
	production_recipe = CreateProductionRecipe({ metalplate = 5, crystal = 10 }, { c_fabricator = 40, c_assembler = 40 }),
	link_to_visual = true,
	on_add = function(comp_def, comp)
		comp_create_link_to_visual(comp_def, comp)
		FactionCount("equipped_assembler", true, comp.faction)
	end,
})

c_fabricator:RegisterComponent("c_data_analyzer", {
	attachment_size = "Large", race = "robot", index = 1002, name = "Data Analyzer",
	texture = "Main/textures/icons/components/Component_DataAnalyzer_01_L.png",
	desc = "Allows creation of Simulation Datacubes",
	visual = "v_dataanalyzer_L",
	power = -200,
	production_recipe = CreateProductionRecipe({ icchip = 5, hdframe = 5, optic_cable = 5 }, { c_advanced_assembler = 120, }),
})

----- refinery : fabricator -----
c_fabricator:RegisterComponent("c_refinery", {
	attachment_size = "Medium", race = "robot", index = 1003, name = "Refinery",
	texture = "Main/textures/icons/components/Component_Refinery_01_M.png",
	desc = "Advanced production facility for advanced material production",
	visual = "v_refinery_01_m",
	production_effect = "fx_refinery",
	power = -50,
	production_recipe = CreateProductionRecipe({ c_fabricator = 1, circuit_board = 10, energized_plate = 5 }, { c_assembler = 120 }),
})

----- robotics factory -----
local c_robotics_factory = c_fabricator:RegisterComponent("c_robotics_factory", {
	attachment_size = "Medium", race = "robot", index = 1002, name = "Robotics Assembler",
	texture = "Main/textures/icons/components/component_roboticsfactory_01_m.png",
	desc = "Dedicated laboratory for robotics",
	visual = "v_roboticsfactory_01_m",
	production_effect = "fx_robotics_factory",
	power = -30,
	production_recipe = CreateProductionRecipe({ c_fabricator = 1, reinforced_plate = 10, circuit_board = 5 }, { c_assembler = 20 }),
	registers = {
		c_fabricator.registers[1], -- production
		c_fabricator.registers[2], -- missing ingredient
		{ type = "entity", tip = "Rally point\n\nDrag to location, unit or building to set", ui_icon = "icon_context"},
	},
})

----- Medium Advanced Refinery -----
c_fabricator:RegisterComponent("c_advanced_refinery", {
	attachment_size = "Medium", race = "robot", index = 1004, name = "Advanced Refinery",
	texture = "Main/textures/icons/components/component_adv_refinery_01_l.png",
	desc = "High-tech production facility for advanced robotic materials",
	slots = { gas = 2 },
	visual = "v_adv_refinery_01_m",
	production_effect = "fx_assembler",
	power = -400,
	production_recipe = CreateProductionRecipe({ c_refinery = 1, hdframe = 10, icchip = 5, optic_cable = 5 }, { c_advanced_assembler = 200 }),
	registers = {
		c_fabricator.registers[1], -- production
		c_fabricator.registers[2], -- missing ingredient
		-- { type = "entity", tip = "Rally point\n\nDrag to location, unit or building to set", ui_icon = "icon_context"},
	},
})

----- Large Advanced Assembler -----
c_fabricator:RegisterComponent("c_advanced_assembler", {
	attachment_size = "Large", race = "robot", index = 1001, name = "Advanced Assembler",
	texture = "Main/textures/icons/components/component_adv_assembler_01_l.png",
	desc = "High-tech production facility for advanced robotic components",
	visual = "v_adv_assembler_01_l",
	production_effect = "fx_assembler",
	power = -350,
	production_recipe = CreateProductionRecipe({ c_assembler = 1, hdframe = 20, icchip = 10, cable = 10 }, { c_assembler = 200 }),
	-- production_recipe = CreateProductionRecipe({ hdframe = 20, blight_plasma = 10, blight_bar = 10 }, { c_assembler = 150 }),
	registers = {
		c_fabricator.registers[1], -- production
		c_fabricator.registers[2], -- missing ingredient
		-- { type = "entity", tip = "Rally point\n\nDrag to location, unit or building to set", ui_icon = "icon_context"},
	},
})

----- Large Advanced Alien Factory -----
c_fabricator:RegisterComponent("c_adv_alien_factory", {
	attachment_size = "Large", race = "alien", index = 5004, name = "Advanced Alien Factory",
	texture = "Main/textures/icons/components/Component_AdvancedAlienFactory_01_M.png",
	desc = "Alien and Robot technology, capable of producing Alien constructs and devices",
	visual = "v_adv_alien_factory_01_l",
	production_effect = "fx_assembler",
	power = -400,
	production_recipe = CreateProductionRecipe({ hdframe = 30, cpu = 10, energized_artifact = 10 }, { c_alien_factory_robots = 200 }),
	-- production_recipe = CreateProductionRecipe({ hdframe = 20, blight_plasma = 10, blight_bar = 10 }, { c_assembler = 150 }),
	registers = {
		c_fabricator.registers[1], -- production
		c_fabricator.registers[2], -- missing ingredient
	},
})

----- power_relay -----
local c_power_relay = Comp:RegisterComponent("c_power_relay", {
	attachment_size = "Medium", race = "robot", index = 1013, name = "Power Field",
	desc = "Creates or expands your logistics network, transferring power to nearby units and buildings. Produces no power on its own.",
	texture = "Main/textures/icons/components/Component_PowerRelay_01_M.png",
	visual = "v_power_relay_01_m",
	transfer_radius = 15,
	production_recipe = CreateProductionRecipe({ c_small_relay = 1, wire = 5, energized_plate = 5 }, { c_assembler = 60 }),
})

----- power_relay -----
c_power_relay:RegisterComponent("c_portable_relay", {
	attachment_size = "Internal", race = "robot", index = 1012, name = "Portable Power Field",
	desc = "Creates or expands your logistics network with a small area, transferring power to nearby units and buildings. Produces no power on its own. Most useful on a moveable unit given its short range.",
	texture = "Main/textures/icons/components/powerrelay.png",
	visual = "v_generic_i",
	transfer_radius = 3,
	production_recipe = CreateProductionRecipe({ crystal = 1, metalbar = 5 }, { c_assembler = 60 }),
})

----- small_relay -----
c_power_relay:RegisterComponent("c_small_relay", {
	attachment_size = "Small", race = "robot", index = 1013, name = "Small Power Field",
	texture = "Main/textures/icons/components/Component_PowerRelay_01_S.png",
	visual = "v_power_relay_01_s",
	transfer_radius = 8,
	production_recipe = CreateProductionRecipe({ reinforced_plate = 1, circuit_board = 1 }, { c_assembler = 30 }),
})

----- alien internal power field -----
c_power_relay:RegisterComponent("c_alien_field", {
	attachment_size = "Hidden", race = "alien", index = 5999, name = "Alien Field",
	texture = "Main/textures/icons/components/alien_powercore.png",
	transfer_radius = 20,
	production_recipe = false,
})

----- human internal power field -----
c_power_relay:RegisterComponent("c_internal_field", {
	attachment_size = "Hidden", race = "human", index = 3999, name = "Integrated Power Field",
	texture = "Main/textures/icons/components/powerrelay.png",
	transfer_radius = 6,
	production_recipe = false,
})

----- large_power_relay -----
c_power_relay:RegisterComponent("c_large_power_relay", {
	attachment_size = "Large", race = "human", index = 3011, name = "Large Power Field",
	texture = "Main/textures/icons/components/component_powerrelay_01_l.png",
	visual = "v_power_relay_01_l",
	transfer_radius = 20,
	production_recipe = CreateProductionRecipe({ c_power_relay = 1, ldframe = 10, refined_crystal = 10 }, { c_assembler = 60 }),
})

local c_uplink = Comp:RegisterComponent("c_uplink", {
	attachment_size = "Medium", race = "robot", index = 1041, name = "Uplink",
	texture = "Main/textures/icons/components/Component_Uplink_01_M.png",
	desc = "Uploads data to orbital mainframe for tech research",
	visual = "v_uplink_m",
	power = -20,
	production_effect = "fx_uplink",
	registers = {
		{ tip = "Current researching technology", read_only = true, ui_icon = "icon_uplink", click_action = true },
		{ tip = "Missing ingredient", read_only = true },
	},
	is_missing_ingredient_register = function(idx) return idx == 2 end,
	production_recipe = CreateProductionRecipe({ metalbar = 5, circuit_board = 1 }, { c_assembler = 20 }),
	activation = "Manual",
	on_pickup = function(faction)
		faction:Unlock("x_tc_components")
	end,
	action_tooltip = "Set Research",
	get_ui = true,
})

function c_uplink:action_click(comp, widget)
	OpenMainWindow("Tech", { param = comp:GetRegisterId(1) })
end

function c_uplink:on_add(comp)
	-- trigger unlocking of assembly tech when first equipped
	local race = comp.faction.extra_data.race
	if not race or race == "robot" then
		comp.faction:Unlock("t_assembly")
	end

	-- trigger counter
	FactionCount("equipped_uplink", true, comp.faction)

	-- auto start up to work on research
	comp:Activate()
end

function c_uplink:on_update(comp, cause)
	local current_tech_id, is_finish_production = comp:GetRegisterId(1), (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	local faction = comp.faction
	local faction_data = faction.extra_data
	local research_progress = faction_data.research_progress
	--print("[" .. comp.id .. ":on_update on " .. tostring(comp.owner) .. "] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - current_tech_id: " .. tostring(current_tech_id) .. " - is_finish_production: " .. tostring(is_finish_production) .. " - has_power: " .. tostring(comp.owner.has_power))

	if is_finish_production then
		if not research_progress then
			research_progress = {}
			faction_data.research_progress = research_progress
		end
		local current_tech_def = data.techs[current_tech_id]
		local remain = (current_tech_def and current_tech_def.progress_count or 0) - (research_progress[current_tech_id] or 0)
		if remain == 1 then
			comp:FulfillProcess()
			research_progress[current_tech_id] = nil
			faction:Unlock(current_tech_id)
		elseif remain > 0 then
			comp:FulfillProcess()
			research_progress[current_tech_id] = current_tech_def.progress_count - remain + 1
		end
	end

	-- find next tech in queue that needs research
	local owner, uplinks, sleep_on_inactive = comp.owner
	for req_int,id in ipairs(faction_data.research_queue or {}) do
		local def = data.techs[id]
		if not def then
			if research_progress then research_progress[id] = nil end
			table.remove(faction_data.research_queue, req_int)
			return comp:SetStateSleep()
		end

		local remain = (def and def.progress_count or 0) - (research_progress and research_progress[id] or 0)
		if remain <= 0 or not def.uplink_recipe then
			-- maybe tech definition changed?
			if research_progress then research_progress[id] = nil end
			faction:Unlock(id)
			return comp:SetStateSleep()
		end

		if not GetResearchableTech(faction)[id] then goto try_next_in_queue end

		-- Abort if we don't have power (or are powered off)
		if not uplinks and (self.power or 0) < 0 and not owner.has_power then
			sleep_on_inactive = 10
			break -- sleep for a while, power may change later so keep checking
		end

		-- When there are more than 1 uplink in the faction, check if we have the item slots necessary to process this tech
		local owner_slots, slot_types = owner.slots or {}, {}
		for i,slot in ipairs(owner_slots) do
			slot_types[slot.type] = (slot_types[slot.type] or 0) + 1
		end
		for ingredient_id,_ in pairs(def.uplink_recipe and def.uplink_recipe.ingredients or {}) do
			local ingredient_def = data.all[ingredient_id]
			local ingredient_slot_type = ingredient_def and ingredient_def.slot_type or "storage"
			if not slot_types[ingredient_slot_type] then
				-- this entity is missing an item slot to make this recipe so try next in queue
				sleep_on_inactive = 20
				goto try_next_in_queue
			elseif slot_types[ingredient_slot_type] == 1 then
				slot_types[ingredient_slot_type] = nil
			else
				slot_types[ingredient_slot_type] = slot_types[ingredient_slot_type] - 1
			end
		end

		local has_out_of_power
		if not uplinks then uplinks = comp.faction:GetComponents("c_uplink", true) end
		for _,uplink in ipairs(uplinks) do
			if uplink ~= comp and uplink:GetRegisterId(1) == id then
				remain = remain - 1
				has_out_of_power = has_out_of_power or ((uplink.def.power or 0) < 0 and not uplink.owner.has_power and uplink)
			end
		end

		-- Check if other uplinks already work on all remaining step
		if remain == 0 and not has_out_of_power then
			-- If we ultimately find nothing to work on, sleep for a while to see if another uplink gives up its work so we can take over
			if not sleep_on_inactive then sleep_on_inactive = 10 end
			goto try_next_in_queue
		end

		-- Prepare next process
		local uplink_recipe = def.uplink_recipe
		local can_make, missing_register, need_more_free_slots = comp:PrepareConsumeProcess(uplink_recipe.ingredients)

		-- If not enough slots for ingredients, free up the process request. Perhaps another uplink can continue it
		if need_more_free_slots and #uplinks > 1 then
			sleep_on_inactive = 20
			break -- sleep for a while, inventory may change later so keep checking
		end

		-- If we are taking over work from another uplink that is out of power or powered off, cancel that uplink's process
		if remain == 0 and has_out_of_power then
			has_out_of_power:StopEffects() -- stop sound
			has_out_of_power:CancelProcess()
			has_out_of_power:SetRegister(1, nil)
			has_out_of_power:SetRegister(2, nil)
		end

		comp:SetRegister(1, { id = id, num = 1 })
		comp:SetRegister(2, missing_register)

		-- If needed, wait for missing research ingredient to arrive
		if not can_make then
			comp:StopEffects() -- stop sound
			return comp:SetStateSleep()
		end

		comp:PlayWorkEffect(self.production_effect or "fx_uplink", "fx")

		if id == current_tech_id and not is_finish_production and comp.is_working then
			-- Not a new research step, no need to restart the work timer
			return comp:SetStateContinueWork()
		end

		-- Start work for as many ticks as the recipe requires
		do return comp:SetStateStartWork(math.ceil(uplink_recipe.ticks * (self.uplink_rate or 1))) end

		::try_next_in_queue::
	end

	comp:StopEffects() -- stop sound
	comp:CancelProcess()
	comp:SetRegister(1, nil)
	comp:SetRegister(2, nil)
	return sleep_on_inactive and comp:SetStateSleep(sleep_on_inactive)
end

----- repairer -----
local c_repairer = Comp:RegisterComponent("c_repairer", {
	attachment_size = "Medium", race = "robot", index = 1042, name = "Repair Component",
	texture = "Main/textures/icons/components/Component_Repairer_01_M.png",
	desc = "Allows repair of damaged units and buildings",
	power = -2,
	visual = "v_repairer_01_m",
	activation = "OnFirstRegisterChange",
	registers = {
		{ type = "entity", tip = "Preferred Repair Target", ui_icon = "icon_context", click_action = true, filter = 'entity' },
		{ read_only = true, tip = "Current Repair Target", click_action = true },
	},
	production_recipe = CreateProductionRecipe({ circuit_board = 5, reinforced_plate = 10 }, { c_assembler = 50 }),
	action_tooltip = "Repair Frame",
	on_add = on_add_charge,
	on_remove = on_remove_clear_extra_data,
	trigger_radius = 5,
	trigger_channels = "bot|building|bug",

	-- internal variable
	repair = 1,   -- repair health per use
	duration = 5, -- charge duration
	repair_fx = "fx_heal_unit",
})

function c_repairer:action_click(comp, widget)
	CursorChooseEntity("Select the frame to repair", function (target)
		if not comp.exists then return end -- got destroyed
		local arg = { comp = comp , reg = { entity = target } }
		if target and target.faction ~= comp.faction then
			ConfirmBox("Are you sure you want to repair a frame from another faction?", function()
				Action.SendForEntity("SetRegister", comp.owner, arg)
			end)
		else
			Action.SendForEntity("SetRegister", comp.owner, arg)
		end
	end, nil, comp.register_index)
end

function c_repairer:on_trigger(comp, other_entity)
	if not comp.is_working and comp.faction:GetTrust(other_entity) == "ALLY" then
		comp:Activate()
	end
end

function c_repairer:on_update(comp, cause)
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - My Range: " .. tostring(self.trigger_radius))
	local ed = comp.extra_data
	if cause & CC_FINISH_WORK ~= 0 then
		ed.charged = true
	elseif not ed.charged then
		return comp:SetStateStartWork(self.duration, false, true)
	end

	-- Check if there is a manually chosen target and if it's in repair range
	local owner, manual_target, repair_target = comp.owner, comp:GetRegisterEntity(1)
	local manual_in_range = manual_target and owner:IsInRangeOf(manual_target, self.trigger_radius)
	local manual_damaged = manual_target and manual_target.is_damaged
	if manual_target and manual_in_range and manual_damaged then
		repair_target = manual_target
	elseif owner.is_damaged then
		repair_target = owner
	else
		-- find closest unit to repair
		repair_target = comp:FindClosestTriggeringEntity(function(e)
			return e.is_damaged
		end, FF_OWNFACTION|FF_ALLYFACTION)
	end
	--print("                              Repair Target: " .. tostring(repair_target) .. " - Manual Target: " .. tostring(manual_target) .. " - Move Distance: " .. tostring(owner:GetRangeTo(manual_target or repair_target)) .. " - Repair Distance: " .. tostring(owner:GetRangeTo(repair_target or manual_target)))

	-- Move towards manual target if out of range but only when repair is needed
	if manual_target and manual_damaged and not manual_in_range then
		comp:RequestStateMove(manual_target, self.trigger_radius, true)
	end

	-- Set the current target register
	comp:SetRegisterEntity(2, repair_target or manual_target)

	if not repair_target or (not owner.has_power and (self.power or 0) < 0) then
		-- No repairable target in range or out of power, sleep (because owner or something in range could become damaged)
		--print("                              No repair target, sleeping"))
		return comp:SetStateSleep()
	end

	--print("                              Repairing - Have Power: " .. tostring(owner.has_power or self.power == 0) .. " - Repair Speed: " .. tostring(self.repair_speed) .. " - Repair: " .. tostring(self.repair))
	if owner.is_docked_on_map then
		Map.Defer(function() owner:Undock() end)
		return comp:SetStateSleep(1)
	end
	repair_target:AddHealth(self.repair)

	if self.repair_fx and owner.is_placed then
		repair_target:PlayEffect(self.repair_fx)
	end

	reveal_if_stealthed(owner)
	reveal_if_stealthed(repair_target)
	ed.charged = false
	return comp:SetStateStartWork(self.duration)
end

----- repairer -----
local c_repairer_aoe = Comp:RegisterComponent("c_repairer_aoe", {
	attachment_size = "Medium", race = "robot", index = 1043, name = "AOE Repair Component",
	texture = "Main/textures/icons/components/Component_Repairer_01_M_aoe.png",
	desc = "Allows repair of all damaged units and buildings in a radius",
	power = -15,
	visual = "v_repairer_AoE_01_m",
	activation = "OnFirstRegisterChange",
	production_recipe = CreateProductionRecipe({ c_repairer_small_aoe = 1, icchip = 3, hdframe = 2 }, { c_advanced_assembler = 50 }),
	trigger_radius = 5,
	trigger_channels = "bot|building|bug",
	on_add = on_add_charge,
	on_remove = on_remove_clear_extra_data,
	on_trigger = c_repairer.on_trigger,

	-- internal variable
	repair = 3,   -- repair health per use
	duration = 5, -- charge duration
	repair_fx = "fx_heal_unit",
})

function c_repairer_aoe:on_update(comp, cause)
	local ed = comp.extra_data
	if cause & CC_FINISH_WORK ~= 0 then
		ed.charged = true
	elseif not ed.charged then
		comp:StopEffects()
		return comp:SetStateStartWork(self.duration, false, true)
	end

	local owner, discharge = comp.owner
	if owner.has_power or (self.power or 0) >= 0 then
		if owner.is_damaged then
			owner:AddHealth(self.repair)
			owner:PlayEffect(self.repair_fx)
			discharge = true
		end

		comp:FindClosestTriggeringEntity(function(e)
			if e.is_damaged then
				e:AddHealth(self.repair)
				e:PlayEffect(self.repair_fx)
				reveal_if_stealthed(e)
				discharge = true
			end
		end, FF_OWNFACTION|FF_ALLYFACTION)
	end
	if not discharge then
		comp:StopEffects()
		return comp:SetStateSleep()
	end

	--if self.repair_fx and owner.is_placed and not comp.has_active_effects then
	--	comp:PlayEffect(self.repair_fx, "fx")
	--end
	if owner.is_docked_on_map then
		Map.Defer(function() owner:Undock() end)
		return comp:SetStateSleep(1)
	end

	reveal_if_stealthed(owner)
	ed.charged = false
	return comp:SetStateStartWork(self.duration)
end

c_repairer_aoe:RegisterComponent("c_repairer_small_aoe", {
	attachment_size = "Small", race = "robot", index = 1043, name = "Small AOE Repair Component",
	texture = "Main/textures/icons/components/Component_Repairer_01_S_aoe.png",
	visual = "v_repairer_AoE_01_s",
	production_recipe = CreateProductionRecipe({ c_repairer = 1, circuit_board = 5, hdframe = 1 }, { c_assembler = 50 }),

	-- internal variable
	power = -5,
	trigger_radius = 1,
	repair = 2,   -- repair health per use
})

c_repairer_aoe:RegisterComponent("c_alien_heart_repair", {
	attachment_size = "Hidden", race = "alien", index = 3999, name = "Auto Repair Module",
	desc = "Internal repair functions",
	texture = "Main/textures/icons/alien/alienbuilding_alienheart.png",
	production_recipe = false,
	get_ui = false,
	-- internal variable
	power = -5,
	trigger_radius = 1,
	range = 3,
	repair = 8,   -- repair health per use
})

c_repairer_aoe:RegisterComponent("c_human_repairkit", {
	attachment_size = "Hidden", race = "human", index = 3999, name = "Auto Repair Module",
	desc = "Internal repair functions",
	texture = "Main/textures/icons/components/repairkit_human.png",
	production_recipe = false,
	get_ui = true,
	-- internal variable
	power = -5,
	trigger_radius = 1,
	repair = 2,   -- repair health per use
})

local c_repairkit = Comp:RegisterComponent("c_repairkit", {
	attachment_size = "Internal", race = "robot", index = 1043, name = "Repair Kit",
	desc = "Can repair the unit or building it is equipped on",
	texture = "Main/textures/icons/components/repairkit.png",
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, crystal = 5 }, { c_assembler = 50 }),
	activation = "Always",
	power = -2,
	on_add = on_add_charge,
	on_remove = on_remove_clear_extra_data,
	repair = 1,
	duration = 10,
	repair_fx = "fx_heal_unit",
})

function c_repairkit:on_update(comp, cause)
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - My Range: " .. tostring(self.trigger_radius))
	local ed = comp.extra_data
	if cause & CC_FINISH_WORK ~= 0 then
		ed.charged = true
	elseif not ed.charged then
		return comp:SetStateStartWork(self.duration, false, true)
	end

	local owner = comp.owner
	if not owner.is_damaged or (not owner.has_power and (self.power or 0) < 0) then
		return comp:SetStateSleep(self.duration)
	end

	owner:AddHealth(self.repair)
	if self.repair_fx and owner.is_placed then
		owner:PlayEffect(self.repair_fx)
	end
	ed.charged = false
	return comp:SetStateStartWork(self.duration)
end

----- deployment -----
local c_deployment = Comp:RegisterComponent("c_deployment",{
	attachment_size = "Hidden", race = "robot", index = 1042, name = "Deployment",
	texture = "Main/textures/icons/hidden/integrated_deployer.png",
	desc = "Initial planetary colonization support package, cannot deploy while frame is active",
	visual = "v_generic_i",
	activation = "OnFirstRegisterChange",
	action_tooltip = "Deploy",
	required_resources = { "crystal", "metalore" },
	registers = { { tip = "Deploy Base", click_action = true, ui_icon = "icon_new", filter = 'coord' } },
	deployment_frame = "f_landingpod",
})

c_deployment:RegisterComponent("c_human_deployment",{
	attachment_size = "Hidden", race = "human", index = 3041, name = "HQ Deployment",
	required_resources = { "laterite", "metalore" },
	deployment_frame = "f_human_commandcenter",
})

function c_deployment:get_ui(comp)
	return nil, nil, false, UI.New([[<Box><Button width=240 height=56 icon=icon_new textalign=left style=hl text="Deploy Base" on_click={click}/></Box>]], {
		click = function() self:action_click(comp) end,
		hl = 0,
		update = Map.GetTotalDays() < 1.0 and function(self)
			if (self.hl//2 % 2) == 0 then self.color = "ui_dark"
			else self.color = "ui_light" end
			self.hl = self.hl + 1
			if self.hl == 32 then self.update = nil end
		end or nil
	})
end

function c_deployment:action_click(comp)
	local ed = comp.has_extra_data and comp.extra_data
	View.StartCursorConstruction(self.deployment_frame,
		function(location, rotation, is_valid) -- on confirm
			if not is_valid and comp.exists then Notification.Error("Cannot deploy here") return end -- continue cursor
			View.StopCursor()
			Quickview_HideGrid()
			if not comp.exists then return end

			local resources = { metalore = 0, crystal = 0, laterite  = 0}
			Map.FindClosestEntity(location.x, location.y, comp.owner.power_range + 2, function(e)
				if not comp.faction:IsDiscovered(e) then return end
				local id, amt = GetResourceHarvestItemId(e), GetResourceHarvestItemAmount(e)
				if id and resources[id] ~= REG_INFINITE then
					if amt == REG_INFINITE then resources[id] = REG_INFINITE
					else resources[id] = (resources[id] or 0) + amt
					end
				end
			end, FF_RESOURCE)

			local arg = { comp = comp, reg = { coord = location, num = rotation } }
			if (resources[self.required_resources[1]] ~= REG_INFINITE and resources[self.required_resources[1]] < 30) or (resources[self.required_resources[2]] ~= REG_INFINITE and resources[self.required_resources[2]] < 30) then
				ConfirmBox("Insufficient resources detected.\n\nAre you sure you want to deploy here?", function()
					Action.SendForEntity("SetRegister", arg.comp.owner, arg)
					UI.PlaySound("fx_ui_BUILD_ADD")
				end)
			else
				--ConfirmBox(L("Are you sure you want to deploy here?", resources.metalore), function()
				Action.SendForEntity("SetRegister", arg.comp.owner, arg)
				UI.PlaySound("fx_ui_BUILD_ADD")
				--end)
			end
		end,
		function() -- on abort
			Quickview_HideGrid()
		end,
		function(x, y, rotation, is_visible, can_place, is_powered, size_x, size_y) --check function
			return is_visible and can_place and not LocationBlockedByBlight({x, y, size_x, size_y})
		end)
	Quickview_ShowGrid(comp.owner.power_range, 3, 3)
end

function c_deployment:on_remove(comp)
	local temp = comp.has_extra_data and comp.extra_data.temp
	if temp then if temp.exists and temp.is_construction then temp:Destroy() end comp.extra_data.temp = nil end
end

function c_deployment:get_reg_error(comp)
	local deploy_location = comp:GetRegisterCoord(1)
	return deploy_location and not comp.faction:IsVisible(deploy_location) and "No visibility on target" or "Invalid location"
end

function c_deployment:on_update(comp, cause)
	if not comp.owner.is_placed then comp:FlagRegisterError(1, false)  return end
	local ed = comp.extra_data
	local temp = ed.temp
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - has_power: " .. tostring(comp.owner.has_power) .. " - temp: " .. tostring(temp))

	-- Check if a temporary construction site needs to get removed
	local deploy_location, old_location = comp:GetRegisterCoord(1), temp and temp.exists and temp.placed_location
	local spawn_temp = deploy_location and (not old_location or old_location.x ~= deploy_location.x or old_location.y ~= deploy_location.y)
	local lost_move_control = cause & CC_LOST_MOVE_CONTROL ~= 0
	if temp and (not deploy_location or spawn_temp or lost_move_control or not temp.exists) then
		if temp.exists then temp:Destroy() end
		ed.temp, temp = nil, nil
	end

	-- Check if movement was aborted, and if so, remove the temporary site and stop for now
	comp:FlagRegisterError(1, false)
	if lost_move_control then
		if not comp:RegisterIsLink(1) then
			return comp:SetRegister(1, nil)
		else
			return comp:SetStateSleep()
		end
	end

	if spawn_temp then
		-- If the location is not visible or invalid, sleep then try again
		local rotation = comp:GetRegisterNum(1)
		local invalid = not comp.faction:IsVisible(deploy_location) or not comp.faction:CanPlace(self.deployment_frame, deploy_location.x, deploy_location.y, rotation, true)
		if invalid then comp:FlagRegisterError(1) return comp:SetStateSleep() end

		-- Create a temporary fake construction site which will get destroyed once the lander arrives
		Map.Defer(function()
			if not comp.exists or (ed.temp and ed.temp.exists) then return end
			local newtemp = Map.CreateEntity(comp.faction, "f_construction", self.deployment_frame)
			newtemp:Place(deploy_location, rotation)
			newtemp:PlayEffect("fx_transfer")
			ed.temp = newtemp
		end)
		return comp:SetStateSleep(1) -- wait for temp to be created
	end

	-- Check if the construction site has been created and then make sure we are next to it
	if not temp or comp:RequestStateMove(temp, comp.owner.crane_range) then
		return
	end

	-- Remaining work (add construction component, unplace self) needs to be done deferred
	Map.Defer(function()
		if not comp.exists or ed.temp ~= temp then return end

		-- Pause any running behavior
		local lander = comp.owner
		for _,v in ipairs(lander.components) do
			if v.base_id == "c_behavior" and v.is_active then
				DebugBehavior(v, "PAUSE")
				v.extra_data.debug = "c_deployment" -- remember to restart
			end
		end

		local con_ed = temp:AddComponent("c_deploy_construction", "hidden").extra_data
		con_ed.lander = lander
		ed.temp = nil
		lander.faction:UpdateEntityInRegisters(lander, temp)
		lander.faction:RunUI("OnEntityRecreate", lander, temp, true)
		lander:Unplace()
		if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end -- force clear if placed again upon deployment cancellation
	end)
end

function Delay.EjectDropPod(arg)
	if not arg.entity or not arg.entity.exists then return end
	local loc = arg.location
	arg.entity:Place(arg.location)
	arg.entity:PlayEffect(arg.effect)
	if arg.notification then
		arg.entity.faction:RunUI(function()
			Notification.Add("droppod", "warning", "Drop Pod Ejected", L("Drop Pod Ejected at %d, %d", loc[1], loc[2]), {
				tooltip = "World Event",
				on_click = function() View.JumpCameraToEntities(arg.entity) end,
			})
		end)
	end
end

local c_deployer = Comp:RegisterComponent("c_deployer",{
	attachment_size = "Internal", race = "robot", index = 1045, name = "Deployer",
	texture = "Main/textures/icons/components/deployment.png",
	desc = "Unpacks into a completed unit or building",
	visual = "v_generic_i",
	activation = "OnFirstRegisterChange",
	action_tooltip = "Use",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, crystal = 5 }, { c_assembler = 30 }),
	registers = {
		{ tip = "Target", ui_icon = "icon_context", click_action = true, filter = 'world' },
		{ tip = "Acquired Unit/Building", click_action = true, read_only = true },
	}
})

function c_deployer:get_ui(comp)
	return nil, nil, false, UI.New("<Box><Button width=240 height=56 icon=icon_new textalign=left style=hl text={txt} on_click={click}/></Box>", {
		update = function(v)
			if not comp.exists then v:RemoveFromParent() return end
			local bp = comp.has_extra_data and comp.extra_data.bp
			v.txt = bp and "Deploy" or "Acquire"
		end,
		click = function()
			self:action_click(comp)
		end,
		tooltip = function(v)
			local bp = comp.has_extra_data and comp.extra_data.bp
			return bp and BuildDefinitionTooltip(bp) or "Select unit/building to acquire"
		end,
	})
end

function c_deployer:action_click(comp)
	local bp = comp.has_extra_data and comp.extra_data.bp
	if not bp then
		CursorChooseEntity("Select target to take in",
			function (target)
				if not comp.exists then return end -- deployer got destroyed

				-- Cannot acquire self or something of another faction or a construction site
				if not target or target == comp.owner or target.faction ~= comp.faction or target.is_construction or IsDroppedItem(target) then
					Notification.Error("Invalid Target")
					return
				end
				local deconstruct_err = CheckDeconstruct(target, nil, true)
				if deconstruct_err then
					Notification.Error(L("%s: %s", "Target not valid for re-deployment", deconstruct_err))
					return
				end

				Action.SendForEntity("SetRegister", comp.owner, { comp = comp, reg = { entity = target } })
			end, nil, comp.register_index)
	else
		View.StartCursorConstruction("f_construction", bp.frame or bp.visual,
			function(location, rotation, is_valid) -- on confirm
				if not is_valid and comp.exists then Notification.Error("Cannot deploy here") return end -- continue cursor
				View.StopCursor()
				Quickview_HideGrid()
				if not comp.exists then return end

				local owner = comp.owner
				Action.SendForEntity("SetRegister", owner, { comp = comp, reg = { coord = location, num = rotation } })
				UI.PlaySound("fx_ui_BUILD_ADD")
				if not owner:RegisterIsEmpty(FRAMEREG_GOTO) and not owner:RegisterIsLink(FRAMEREG_GOTO) then Action.SendForEntity("SetRegister", owner, { idx = FRAMEREG_GOTO }) end
			end,
			function() -- on abort
				Quickview_HideGrid()
			end,
			function(x, y, rotation, is_visible, can_place, is_powered, size_x, size_y) --check function
				return is_visible and can_place and not LocationBlockedByBlight({x, y, size_x, size_y}) and (IsBot(comp.owner) or (comp.owner:IsInRangeOf(x, y, size_x, size_y, comp.owner.crane_range)))
			end
		)
		Quickview_ShowGrid()
	end
end

function c_deployer:get_reg_error(comp)
	local target = comp:GetRegisterEntity(1)
	if not target or target == comp.owner or target.faction ~= comp.faction or target.is_construction or IsDroppedItem(target) then
		local bp = comp.has_extra_data and comp.extra_data.bp
		local bp_def = bp and data.frames[bp.frame]
		return bp and (not bp_def or bp_def.flags == "Space") and "Target not valid for re-deployment" or "Invalid Target"
	end
	local deconstruct_err = CheckDeconstruct(target, nil, true)
	if deconstruct_err then
		return L("%s: %s", "Target not valid for re-deployment", deconstruct_err)
	end
end

function c_deployer:on_add(comp)
	local bp = comp.has_extra_data and comp.extra_data.bp
	if bp then comp:SetRegister(2, { id = bp.frame, num = 1 }) end
end

function c_deployer:on_remove(comp)
	local temp = comp.has_extra_data and comp.extra_data.temp
	if temp then if temp.exists and temp.is_construction then temp:Destroy() end comp.extra_data.temp = nil end
end

function c_deployer:on_update(comp, cause)
	local ed = comp.extra_data
	local temp, bp = ed.temp, ed.bp
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - has_power: " .. tostring(comp.owner.has_power) .. " - temp: " .. tostring(temp))

	-- Stop any work effects
	comp:StopEffects()

	-- Check if a temporary construction site needs to get removed
	local deploy_location, old_location = bp and comp:GetRegisterCoord(1), temp and temp.exists and temp.placed_location
	local spawn_temp = deploy_location and (not old_location or old_location.x ~= deploy_location.x or old_location.y ~= deploy_location.y)
	local lost_move_control = cause & CC_LOST_MOVE_CONTROL ~= 0
	if temp and (not deploy_location or spawn_temp or lost_move_control or not temp.exists) then
		if temp.exists then temp:Destroy() end
		ed.temp, temp = nil, nil
	end

	-- Check if movement was aborted, and if so, remove the temporary site and stop for now
	comp:FlagRegisterError(1, false)
	if lost_move_control then
		if not comp:RegisterIsLink(1) then
			return comp:SetRegister(1, nil)
		else
			return comp:SetStateSleep()
		end
	end

	if spawn_temp then
		-- Can't deploy a satellite
		local bp_def = data.frames[bp.frame]
		if not bp_def or bp_def.flags == "Space" then
			return comp:FlagRegisterError(1)
		end

		-- If the location is not visible or invalid, sleep then try again
		local rotation = comp:GetRegisterNum(1)
		local invalid = not comp.faction:IsVisible(deploy_location) or not comp.faction:CanPlace("f_construction", deploy_location.x, deploy_location.y, rotation, bp.visual or bp.frame, true)
		if invalid then comp:FlagRegisterError(1) return comp:SetStateSleep() end

		-- Place deploy construction site
		Map.Defer(function()
			if not comp.exists or (ed.temp and ed.temp.exists) then return end
			local newtemp = Map.CreateEntity(comp.faction, "f_construction", bp.visual or bp.frame)
			newtemp:Place(deploy_location, rotation)
			newtemp:PlayEffect("fx_transfer")
			ed.temp = newtemp
		end)
		return comp:SetStateSleep(1) -- wait for temp to be constructed
	end

	if bp then
		-- Check if the construction site has been created and then make sure we are next to it
		if not temp or comp:RequestStateMove(temp, comp.owner.crane_range) then
			return
		end

		-- Remaining work (add construction component, destroy self if needed) needs to be done deferred
		Map.Defer(function()
			if not comp.exists or ed.temp ~= temp or not temp.exists then return end

			temp:AddComponent("c_deploy_construction", "hidden").extra_data.bp = bp
			ed.temp, ed.bp = nil, nil
			if ed.onetime then
				comp:Destroy()
			end
		end)

		-- Clear deployer registers and end
		if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
		comp:SetRegister(2, nil)
		return
	end

	-- No entity stored in deployer, check if there is something to acquire
	local target = comp:GetRegisterEntity(1)
	if not target then return end

	if target == comp.owner or target.faction ~= comp.faction or target.is_construction or IsDroppedItem(target) or CheckDeconstruct(target, nil, true) then
		return comp:FlagRegisterError(1)
	end

	local target_bp = MakeBlueprintFromEntity(target, false, true)
	if not target_bp then
		return comp:FlagRegisterError(1)
	end

	-- Make sure we are next to the target
	if comp:RequestStateMove(target, comp.owner.crane_range) then
		return
	end

	if cause & CC_FINISH_WORK == 0 then
		-- Start deconstruct work
		comp:PlayWorkEffect("fx_deconstructor")
		return comp:SetStateStartWork(30)
	end

	-- Clear target register now (unless link)
	if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end

	-- Remaining work (remove components, destroy target) needs to be done deferred
	Map.Defer(function()
		if not target.exists or not target.is_placed then return end
		if not comp.exists then return end

		-- Set deployer register, store the blueprint and destroy the target
		comp:SetRegister(2, { id = target.id, num = 1 })
		comp.extra_data.bp = target_bp
		comp.faction:RunUI("OnEntityRecreate", target, comp.owner)
		for _,v in ipairs(target.components or {}) do v:Destroy(true) end -- don't drop components
		target:Destroy(true)
	end)
end

----- construction -----
local c_deploy_construction = Comp:RegisterComponent("c_deploy_construction", {
	name = "Deployment Constructor",
	texture = "Main/textures/icons/components/int.png",
	desc = "deployment construction",
	activation = "Always",
})

function c_deploy_construction:on_update(comp, cause)
	local ed = comp.extra_data
	local bp = ed.bp

	if cause & CC_FINISH_WORK ~= CC_FINISH_WORK then
		-- Duration is 10 ticks via Deployer component and 30 via Lander Deployment component
		comp:PlayWorkEffect("fx_transfer") -- active effect indicates construction is progressing
		return comp:SetStateStartWork(bp and 10 or 30, false, true)
	end

	local lander = not bp and ed.lander
	local frame_id = lander and lander:FindComponent("c_deployment", true).def.deployment_frame or (bp and bp.frame)
	local temp = comp.owner
	local faction, loc, rotation = temp.faction, temp.placed_location, temp.rotation
	local x, y = loc.x, loc.y
	if not faction:CanPlace(frame_id, x, y, rotation, bp and bp.visual or nil) then
		-- Try again after 5 ticks
		faction:OrderEntitiesToMoveAway(temp)
		return comp:SetStateStartWork(TICKS_PER_SECOND)
	end

	-- Deployment is completing, signal c_deploy_construction:on_remove to not do anything anymore
	comp.extra_data = nil

	Map.Defer(function()
		if not temp.exists then return end
		local built = CreateFrameOrBlueprint(faction, (bp or data.frames[frame_id]), true, nil, nil, true, temp)
		if not built then error("failed to spawn frame") end
		--built:PlayEffect("fx_ui_BUILD_COMPLETE")

		-- spawn foundations around entity if it's a building
		CreateFoundationsForEntity(built, x, y, rotation)

		if lander then
			local lander_components = lander.components

			-- If behavior was running before deployment, continue it for MakeBlueprintFromEntity below (will be immediately destroyed afterwards anyway)
			for _,v in ipairs(lander_components) do
				if v.base_id == "c_behavior" and v.has_extra_data and v.extra_data.debug == "c_deployment" then
					DebugBehavior(v, "CONTINUE")
				end
			end

			local lander_bp = MakeBlueprintFromEntity(lander, false, false, true) -- copy settings

			-- move components and items from lander to building
			for _,v in ipairs(lander_components) do
				if v.base_id ~= "c_deployment" and v.id ~= "c_small_fusion_reactor" then
					local comp_hidden, comp_id, comp_extra = v.is_hidden, v.id, (v.has_extra_data and v.extra_data or nil)
					if comp_extra then v.extra_data = nil end
					local newcomp = comp_hidden and built:AddComponent(comp_id, "hidden", comp_extra) or built:AddComponent(comp_id, comp_extra)
					if not newcomp then built:AddItem(comp_id, comp_extra) end
				end
			end
			for _,v in ipairs(lander.slots) do
				if v.stack > 0 then
					local item_extra = v.has_extra_data and v.extra_data or nil
					if item_extra then v.extra_data = nil end
					built:AddItem(v.id, v.stack, item_extra)
				end
			end

			ApplyBlueprintToEntity(built, lander_bp) -- apply settings (register, logistics, locks)

			-- destroy the deploy entity without dropping items
			lander:Destroy(false)

			if frame_id == "f_landingpod" then
				FactionCount("built_landingpod", true, faction)

				-- spawn 2 carriers
				local car = Map.CreateEntity(faction, "f_carrier_bot")
				car:Place(x, y)
				car:PlayEffect("fx_digital_in")
				car = Map.CreateEntity(faction, "f_carrier_bot")
				car:Place(x, y)
				car:PlayEffect("fx_digital_in")
			end
		end
	end)
end

function c_deploy_construction:on_remove(comp)
	if not comp.has_extra_data then return end
	local ed, loc = comp.extra_data, comp.owner.location
	comp.extra_data = nil
	if ed.bp then
		Map.DropItemAt(loc, "c_deployer", { bp = ed.bp, onetime = true }, true)
	elseif ed.lander then
		Map.Defer(function() if ed.lander.exists then ed.lander:Place(loc) end end)
	end
end

local c_construction = Comp:RegisterComponent("c_construction", {
	name = "Constructor",
	texture = "Main/textures/icons/components/int.png",
	desc = "All-purpose system for building construction",
	activation = "Always",
})

local function WillBlockCheck(e)
	local cc = e:FindComponent("c_construction", true) -- treat finished construction components (waiting for Map.Defer) as blocking
	if cc and not cc.is_sleeping and not cc.is_working and not cc.is_updating then return 0 end -- return 0 for already finished
	return select(4, Map.CountTiles(e, 1)) > 0 -- return true if there are any passable tiles around it
end

local function WillBlockOffConstruction(site)
	local check, have_exit, have_blocking
	Map.FindClosestEntity(site, 1, function(e)
		local echeck = WillBlockCheck(e)
		if echeck == true then have_exit = true return end -- have passable tile around it - is exit point
		if echeck == false then if not check then check = { e } else check[#check+1] = e end end -- queue check
	end, FF_CONSTRUCTION | FF_OWNFACTION)
	if not check then return end -- no neighboring construction site to check
	have_exit = have_exit or (select(4, Map.CountTiles(site, 1)) > 0) -- have exit if there are any passable tiles around it
	local know, queue = { [site.key] = 0 }, { 0,0,0,0 } -- mark site as ignored (0) and pre-allocate space for 4 elements in queue
	for _,e in ipairs(check) do
		table.move(queue, #queue+1, #queue+#queue-1, 2) -- trim array to 1
		queue[1], know[e.key] = e, 0 -- queue first, mark as ignored (0)
		for i=1,99999 do
			local n = queue[i]
			if not n then
				if have_exit then return true end -- return true due to blocking off access to the exit
				have_blocking = true break -- remember as having a neighbor that would end up blocked off
			end
			if Map.FindClosestEntity(n, 1,
				function(m)
					local mkey = m.key
					local mknow = know[mkey]
					if mknow then return mknow == 1 end -- return true if marked as having path to exit
					local mcheck = WillBlockCheck(m)
					if mcheck == true then know[mkey] = 1 return true end -- have passable tile around it - is exit point
					if mcheck == false then queue[#queue+1], know[mkey] = m, 0 end -- queue to check
				end, FF_CONSTRUCTION | FF_OWNFACTION) then -- encountered site with known path to exit
				if have_blocking then return true end -- return true due to blocking off access to the exit
				for j=1,#queue do know[queue[j].key] = 1 end -- mark all checked as having path to exit
				have_exit = true break -- remember as having a path to an exit somewhere
			end
		end
	end
end

function c_construction:on_update(comp, cause)
	local entity = comp.owner
	local frame_id = entity:GetRegisterId(FRAMEREG_GOTO)
	local frame_def, blueprint_def = GetProduction(frame_id, entity)
	local ed = comp.has_extra_data and comp.extra_data

	if cause & CC_FINISH_WORK == CC_FINISH_WORK then
		comp:StopEffects() -- stop sound

		local faction, loc, rotation = entity.faction, entity.placed_location, entity.rotation
		local x, y = loc.x, loc.y
		if not faction:CanPlace(frame_id, x, y, rotation) then
			faction:OrderEntitiesToMoveAway(entity)
			return comp:SetStateStartWork(TICKS_PER_SECOND)
		end

		-- If this construction is finishing for a building with neighboring construction sites, make sure this building won't block off access to another site
		if frame_def.type ~= "Foundation" and (frame_def.movement_speed or 0) == 0 and select(3, Map.CountTiles(entity, 1)) > 0 and WillBlockOffConstruction(entity) then
			return comp:SetStateStartWork(TICKS_PER_SECOND)
		end

		-- Consume ingredients and place finished building
		local ingredient_extra_datas = comp:FulfillProcess(true)
		Map.Defer(function()
			if not entity.exists then return end
			for i=1,(ed and ed.integrated_data and #ed.integrated_data or 0) do
				local integrated_id, integrated_extra_data = ed.integrated_data[i][1], ed.integrated_data[i][2]
				ingredient_extra_datas = ingredient_extra_datas or {}
				ingredient_extra_datas[integrated_id] = ingredient_extra_datas[integrated_id] or {}
				table.insert(ingredient_extra_datas[integrated_id], integrated_extra_data)
			end
			local is_upgrade = (entity:GetRegisterNum(FRAMEREG_GOTO) > 0) -- make sure to get the register value before recreating the entity
			local built = CreateFrameOrBlueprint(faction, blueprint_def or frame_def, nil, ingredient_extra_datas, ed and ed.skip, nil, entity)
			if not built then error("failed to create frame") end
			--built:PlayEffect("fx_ui_BUILD_COMPLETE")

			-- spawn foundations if desired for the spawned frame
			CreateFoundationsForEntity(entity, x, y, rotation)

			if ed and ed.notifyoncompletion then
				faction:RunUI("OnConstructionCompleteNotification", built)
			end

			if not is_upgrade then
				-- dont count walls and foundations
				if frame_def.size ~= "Other" then
					FactionCount("buildings_built", 1, faction)
				end
			end
		end)
		return
	end

	if comp.is_working then
		comp:PlayWorkEffect("fx_transfer") -- effect might have stopped on shut down
		return comp:SetStateContinueWork()
	end

	local recipe = frame_def and frame_def.construction_recipe
	local recipe_ticks = recipe and recipe.ticks
	if not recipe and frame_def then -- probably unit upgrade
		recipe = frame_def.production_recipe
		for _,ticks in pairs(recipe and recipe.producers or {}) do
			recipe_ticks = (ticks > (recipe_ticks or 0) and ticks) or recipe_ticks
		end
	end

	local ingredients = GetIngredients(recipe, blueprint_def)
	if not ingredients or not recipe_ticks then
		-- This should not happen, a construction component should only be added on things with a recipe
		print(self.id .. " - No Recipe for " .. frame_id)
		entity:Destroy()
		return
	end

	local skip = ed and ed.skip
	if skip then
		local new_ing = {}
		for k,v in pairs(ingredients) do
			if not skip[k] then new_ing[k] = v end
		end
		ingredients = new_ing
	end

	-- Reserve or order construction ingredients item for consumption
	local can_make, missing_register = comp:PrepareConsumeProcess(ingredients)
	entity:SetRegister(FRAMEREG_SIGNAL, missing_register)
	if not can_make then
		return comp:SetStateSleep()
	end

	-- Start work for as many ticks as the recipe requires and get refreshed every tick
	comp:PlayWorkEffect("fx_transfer") -- active effect indicates construction is progressing
	local is_same_frame_upgrade = (entity:GetRegisterNum(FRAMEREG_GOTO) == 2)
	return comp:SetStateStartWork(is_same_frame_upgrade and 10 or recipe_ticks)
end

function UIMsg.OnConstructionCompleteNotification(entity)
	local key_id, entity_name, entity_texture, entity_location = "id" .. entity.key, entity.extra_data.name or entity.def.name, entity.def.texture, entity.location
	Notification.Add(key_id, entity_texture or "Main/textures/icons/values/construction.png", entity_name or "Construction Completed", "A construction was completed", {
		tooltip = "Construction Completed!",
		on_click = function(id) View.MoveCamera(entity_location.x, entity_location.y, false) Notification.Clear(id) end,
	})
end

local c_relocation = c_construction:RegisterComponent("c_relocation", { })

function c_relocation:on_update(comp, cause)
	local entity, ed = comp.owner, comp.extra_data
	local faction = entity.faction

	if comp.is_working then
		comp:PlayWorkEffect("fx_transfer") -- effect might have stopped on shut down
		return comp:SetStateContinueWork()
	end

	local deployer_hash, wait_for_anything, wait_for_deployer, my_deployer_slot = ed.deployer_hash
	for i=1,entity.slot_count do
		local slot = entity:GetSlot(i)
		local id, waiting = slot.id, slot.reserved_space
		wait_for_anything = wait_for_anything or waiting > 0
		wait_for_deployer = wait_for_deployer or (id == 'c_deployer' and waiting > 0)
		my_deployer_slot = my_deployer_slot or (id == 'c_deployer' and waiting == 0 and Tool.Hash(slot.extra_data) == deployer_hash and slot)
	end

	-- If the deployer has been taken out (i.e. the carrier was aborted/killed) then the relocation is aborted
	if not my_deployer_slot and not wait_for_deployer then
		Map.Defer(function() entity:Destroy() end)
	elseif wait_for_anything then
		return comp:SetStateSleep()
	elseif cause & CC_FINISH_WORK == CC_FINISH_WORK then
		comp:StopEffects() -- stop sound

		local bp = my_deployer_slot.extra_data.bp
		local frame_id, loc, rotation = bp.frame, entity.placed_location, entity.rotation
		local x, y = loc.x, loc.y
		if not faction:CanPlace(frame_id, x, y, rotation, bp.visual or frame_id) then
			faction:OrderEntitiesToMoveAway(entity)
			return comp:SetStateStartWork(TICKS_PER_SECOND)
		end

		-- If this construction is finishing for a building with neighboring construction sites, make sure this building won't block off access to another site
		local frame_def = data.all[frame_id]
		if frame_def.type ~= "Foundation" and (frame_def.movement_speed or 0) == 0 and select(3, Map.CountTiles(entity, 1)) > 0 and WillBlockOffConstruction(entity) then
			return comp:SetStateStartWork(TICKS_PER_SECOND)
		end

		-- Consume ingredients and place finished building
		Map.Defer(function()
			if not entity.exists or not my_deployer_slot.exists then return end
			my_deployer_slot:Clear()
			local built = CreateFrameOrBlueprint(faction, bp, true, nil, ed and ed.skip, true, entity)
			if not built then error("failed to create frame") end
			--built:PlayEffect("fx_ui_BUILD_COMPLETE")

			-- spawn foundations if desired for the spawned frame
			CreateFoundationsForEntity(entity, x, y, rotation)

			if ed and ed.notifyoncompletion then
				faction:RunUI("OnConstructionCompleteNotification", built)
			end
		end)
	else
		comp:PlayWorkEffect("fx_transfer") -- active effect indicates construction is progressing
		return comp:SetStateStartWork(10) -- unit relocation defaults to 10 ticks
	end
end

--- miner ---
local c_miner = Comp:RegisterComponent("c_miner", {
	attachment_size = "Small", race = "robot", index = 1002, name = "Miner",
	texture = "Main/textures/icons/components/Component_Miner_01_S.png",
	desc = "Basic mining drill - extracts metal and crystal",
	power = -3,
	visual = "v_miner_s",
	production_recipe = CreateProductionRecipe({ metalbar = 5, crystal = 5 }, { c_assembler = 20 }),
	activation = "OnFirstRegisterChange",
	action_tooltip = action_tooltip_set_target,
	registers = {
		{ type = "miner", tip = "Resource to mine and amount", ui_apply = "Set Mining Target", ui_icon = "icon_context" },
		{ read_only = true, tip = "Resource mining", },
	},
	miner_effect = "fx_miner",
	miner_range = 1,
	link_to_visual = true,
	on_add = function(comp_def, comp)
		comp_create_link_to_visual(comp_def, comp)
		FactionCount("equipped_miner", true, comp.faction)
	end,
	on_remove = on_remove_clear_extra_data,
	get_ui = true,
})

function c_miner:action_click(comp, widget)
	ShowRegisterSelection(widget, comp.owner, comp, 1)
end

function c_miner:get_reg_error(comp)
	local reg1 = comp:GetRegister(1)
	local entityharvestid = reg1.entity and GetResourceHarvestItemId(reg1.entity)
	local def = entityharvestid and data.all[entityharvestid] or reg1.def
	if not entityharvestid and def and def.harvest_id then def = data.all[def.harvest_id] end
	local id, reg1_num = entityharvestid or (def and def.id), reg1.num
	local want = id and reg1_num > 0 and (reg1_num - comp.owner:CountItem(id))
	local mining_recipe = def and def.mining_recipe
	if not mining_recipe or not mining_recipe[self.id] then
		return L("Cannot mine %s", def and def.name or "resource")
	elseif want and want <= 0 then
		return L("Already holding the requested amount %d of %s", reg1_num, def and def.name or "resource")
	elseif not comp.owner:HaveFreeSpace(id) or comp.extra_data.target then
		return L("No space in inventory for %s", def and def.name or "resource")
	else
		return L("No %s found in range", def and def.name or "resource")
	end
end

function c_miner:try_spawn_anomaly_particle(comp)
	-- also allow owner
	local o = comp.owner
	if o:AddItem("anomaly_particle", true) then
		o:PlayEffect("fx_digital_in")
	end
	Map.FindClosestEntity(comp.owner, 2, function(e)
		if math.random(1,3) == 3 and e:AddItem("anomaly_particle", true) then
			e:PlayEffect("fx_digital_in")
		end
	end, FF_OPERATING)
end

function c_miner:can_harvest(comp, resource_id)
	local item_def = data.all[resource_id]
	local mining_recipe = item_def and item_def.mining_recipe
	return mining_recipe and mining_recipe[self.id]
end

function c_miner:on_update(comp, cause)
	--print("[" .. tostring(comp.owner) .. "] [" .. comp.id .. "(" .. comp.socket_index .. "):on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - has_power: " .. tostring(comp.owner.has_power))
	local reg1_num, reg1_id, reg1_entity = comp:GetRegisterData(1)

	-- if the register is empty, remove any extra data and shut down
	if not reg1_num then
		comp:SetRegister(2, nil)
		on_remove_clear_extra_data_keep_resimulated(self, comp)
		return (comp.is_working or (cause & CC_FINISH_MOVE ~= 0)) and comp:SetStateSleep()
	end

	-- register entity or id changed, clear any remembered extra data
	if cause & (CC_CHANGED_REGISTER_ID | CC_CHANGED_REGISTER_ENTITY) ~= 0 then
		comp:SetRegister(2, nil)
		on_remove_clear_extra_data_keep_resimulated(self, comp)
		comp:CancelProcess()
	end

	-- check if we can just continue mining when the previous target still exists and we haven't moved
	local owner = comp.owner
	local extra_data, owner_location_x, owner_location_y = comp.extra_data, owner:GetLocationXY()
	local target, id, loc = extra_data.target, extra_data.id, extra_data.loc

	local miner_range = self.miner_range
	if cause & CC_FINISH_MOVE ~= 0 and target and target.exists and not owner:IsInRangeOf(target, miner_range) and comp.has_move_control then
		-- if its close enough and its a specific targeted entity, just try the resource
		-- Switch the register from a specific entity to the id
		if not reg1_id and reg1_entity and not comp:RegisterIsLink(1) and owner:GetRangeTo(reg1_entity) < owner.visibility_range then
			comp:SetRegister(1, { id = id, num = reg1_num == 0 and REG_INFINITE or reg1_num })
		end

		local avoid_target = extra_data.avoid_target
		if not avoid_target then
			avoid_target = { target }
			extra_data.avoid_target = avoid_target
		else
			for _,v in ipairs(avoid_target) do
				if target == v then
					goto already_avoided
				end
			end
			avoid_target[#avoid_target+1] = target
			::already_avoided::
		end

		extra_data.target = nil
		comp:SetRegister(2, nil)
		target = nil
	end

	if not target and loc and loc.x == owner_location_x and loc.y == owner_location_y then
		if extra_data.avoid_target then
			-- no movement but we have a list of avoided targets, clear the list to try them again
			extra_data.avoid_target = nil
		else
			-- no movement since we didn't find a target last time, continue waiting to get moved
			comp:SetRegister(2, nil)
			comp:FlagRegisterError(1)
			return comp:SetStateSleep()
		end
	end

	if not target or not target.exists or (loc and (loc.x ~= owner_location_x or loc.y ~= owner_location_y)) then
		target, id = reg1_entity, reg1_id
		if target then
			-- mining from a specific entity
			local di = IsDroppedItem(target)
			if not di and not IsResource(target) then target = nil end
			id = target and GetResourceHarvestItemId(target)
			if di then -- dropped item, find a resource
				for _,v in ipairs(target.slots) do
					local def = data.all[v.id]
					if def and def.tag == "resource" then
						id = v.id
						break
					end
				end
			end
		end
		local owner_faction = owner.faction
		local can_harvest = self:can_harvest(comp, id)
		local harvest_frame_def = not can_harvest and data.frames[id]
		if harvest_frame_def then
			id = harvest_frame_def.harvest_id
			can_harvest = self:can_harvest(comp, id)
		end
		if can_harvest and not owner_faction:IsUnlocked(id) then
			owner_faction:Unlock(id)
		end
		if not can_harvest then
			-- Nothing to do, turn off until target changes
			comp:SetRegister(2, nil)
			return comp:FlagRegisterError(1)
		elseif not target then
			-- find a resource for the requested item type
			local dropped_resource_def, unpowered_target = data.frames.f_dropped_resource
			local avoid_target, is_building = extra_data.avoid_target, IsBuilding(owner)
			target = Map.FindClosestEntity(owner, owner.has_movement and owner.visibility_range or miner_range, function(e)
				if avoid_target then
					for _,v in ipairs(avoid_target) do if e == v then return end end
				end

				if e.def == dropped_resource_def then -- only pick up one type of dropped items (scattered resources)
					if e:CountItem(id) ~= 0 then
						if is_building or owner_faction:GetPowerGridIndexAt(e, miner_range) then
							return true
						elseif not unpowered_target then
							unpowered_target = e
						end
					end
				elseif IsResource(e) then
					if harvest_frame_def and e.id ~= reg1_id then return end
					-- bots prefer resources inside logistics network
					if is_building or owner_faction:GetPowerGridIndexAt(e, miner_range) then
						return GetResourceHarvestItemId(e) == id
					elseif not unpowered_target and GetResourceHarvestItemId(e) == id then
						unpowered_target = e
					end
				end
			end, (harvest_frame_def and FF_RESOURCE or (FF_RESOURCE|FF_DROPPEDITEM)))
			if not target and unpowered_target then
				target = unpowered_target
			end

			if not target and loc and extra_data.target and comp:RequestStateMove(extra_data.target.exists and extra_data.target or loc, miner_range) then
				-- no resource found here, move back to the last place of work then scan again
				extra_data.target, extra_data.id, extra_data.loc = nil, nil, nil
				comp:FlagRegisterError(1)
				comp:SetRegister(2, nil)
				return -- execute move
			elseif not target then
				-- no resource found, sleep and wait until we get moved
				extra_data.target, extra_data.id, extra_data.loc = nil, nil, { x = owner_location_x, y = owner_location_y }
				comp:CancelProcess()
				comp:NotifyWorkFailed()
				comp:FlagRegisterError(1)
				comp:SetRegister(2, nil)
				return comp:SetStateSleep()
			end
		end
		extra_data.target, extra_data.id, extra_data.loc, loc = target, id, nil, nil
		--comp:LinkRegisterFromRegister(2, 4, target)
		comp:SetRegister(2, { entity = target, num = target:GetRegisterNum(FRAMEREG_GOTO) })
		cause = 0 -- start new work with the new target

		--[[ -- Show an effect on the selected target for debugging
		comp.faction:RunUI(function()
			local loc, tsz = target.placed_location, target.visual_def.tile_size
			for x=loc.x,loc.x+(tsz and tsz[1] or 1)-1 do for y=loc.y,loc.y+(tsz and tsz[2] or 1)-1 do View.PlayEffect("fx_ping", x, y) end end
		end)
		--]]
	end

	-- don't start work if we already hold the requested amount
	local want = reg1_num > 0 and (reg1_num - owner:CountItem(id))
	if want and want <= 0 then
		comp:CancelProcess()
		comp:FlagRegisterError(1)
		return comp:SetStateSleep()
	end

	-- if only the number was changed while already working just continue work
	if cause == (CC_ACTIVATED|CC_CHANGED_REGISTER_NUM) and comp.is_working then
		return comp:SetStateContinueWork()
	end

	-- make sure we can fit at least 1 item
	if not comp:PrepareGenerateProcess({ [id] = 1 }) then
		comp:NotifyWorkFailed()
		comp:FlagRegisterError(1)
		return comp:SetStateSleep()
	end
	comp:FlagRegisterError(1, false)

	-- Make sure we are positioned next to the target and not docked
	if comp:RequestStateMove(target, miner_range) then
		if not comp.has_move_control then
			-- Switch the register from a specific entity to the id
			if not reg1_id and not comp:RegisterIsLink(1) then
				comp:SetRegister(1, { id = id, num = reg1_num == 0 and REG_INFINITE or reg1_num })
			end
			extra_data.target = nil
			comp:SetRegister(2, nil)
		end
		return
	end

	-- Switch the register from a specific entity to the id
	if not reg1_id and not comp:RegisterIsLink(1) then
		comp:SetRegister(1, { id = id, num = reg1_num == 0 and REG_INFINITE or reg1_num })
	end

	-- Remember last work location
	if not loc or loc.x ~= owner_location_x or loc.y ~= owner_location_y then extra_data.loc = { x = owner_location_x, y = owner_location_y } end

	-- If we're targetting a dropped item, pick up the type and amount we want
	if IsDroppedItem(target) then
		comp:CancelProcess() -- free up reservation from PrepareGenerateProcess
		if target.def.on_interact then target.def:on_interact(target, owner, false, id, want) end
		extra_data.target, extra_data.id, extra_data.loc = nil, nil, nil
		comp:SetRegister(2, nil)
		return comp:SetStateStartWork(TICKS_PER_SECOND) -- use power for 5 ticks until looking for the next thing
	end

	if cause & CC_REFRESH == CC_REFRESH then
		-- Just refreshing, continue work
		if self.miner_activate then
			comp.owner:Activate()
		end
		if self.miner_effect then
			comp:PlayEffect(self.miner_effect, "fx", target, target.render_instances)
		end
		return comp:SetStateContinueWork()
	end

	if cause & CC_FINISH_WORK == CC_FINISH_WORK then
		-- Finished mining

		comp:FulfillProcess()
		Map.ThrowItemEffect(target, owner, id)

		if self.resource_mined then self:resource_mined(comp, id) end
		if id == "blight_crystal" and target:GetRegisterNum(FRAMEREG_STORE) ~= 1 and math.random(1,4) == 1 then -- check if not magnified (see c_blight_magnifier:on_update)
			c_miner:try_spawn_anomaly_particle(comp)
		end
		local amount = GetResourceHarvestItemAmount(target)
		if not amount or (amount <= 0 and amount ~= REG_INFINITE) then error("nothing provided") end

		if amount == 1 then
			local target_size = target.visual_def.tile_size
			if target_size and target_size[1] > 1 then
				owner.faction:RunUI("NotifyHarvestedRich", data.all[id], target, target.location.x, target.location.y)
			end
			target:PlayEffect("fx_digital")
			local dep = target.visual_def.depleted_visual_id
			if dep then
				target:SetRegister(FRAMEREG_GOTO, nil)
				target:SetVisual(dep, 0)
			else
				target:Destroy()
			end

			-- Harvested last thing, sleep a bit then search for the next target
			return comp:SetStateSleep(1, true)
		end

		-- only harvest if its not infinite
		if amount ~= REG_INFINITE then
			target:SetRegisterNum(FRAMEREG_GOTO, amount - 1)
		end

		local render_instances = target.render_instances
		if render_instances > 1 then
			local provider_data = target.extra_data
			local step = provider_data.step
			if not step then step = amount / render_instances provider_data.step = step end
			--print("[c_miner:on_update] amount:", amount, " - step:", step, " - render_instances:", render_instances)

			if (amount - 1) < (step * (render_instances - 1)) then
				-- remove instance
				target:PlayEffect("fx_digital", render_instances)
				target:RemoveEntityInstance()
			end
		end

		comp:SetRegister(2, { entity = target, num = target:GetRegisterNum(FRAMEREG_GOTO) })

		if want and want <= 1 then
			-- Harvested up to the requested amount
			return comp:SetStateSleep()
		end
	elseif extra_data.avoid_target then
		-- when starting mining work, clear previous avoid targets
		--print(owner, "clearing avoid targets", extra_data.avoid_target)
		extra_data.avoid_target = nil
	end

	-- Start mining work over as many ticks as the recipe requires (the passed true indicates we want to be occasionally refreshed to check if we're still in place and the resource still exists)
	if self.miner_effect then
		comp:PlayWorkEffect(self.miner_effect, "fx", target, target.render_instances)
	end
	return comp:SetStateStartWork(data.all[id].mining_recipe[self.id], true)
end

c_miner:RegisterComponent("c_adv_miner", {
	attachment_size = "Small", race = "robot", index = 1003, name = "Laser Mining Tool",
	texture = "Main/textures/icons/components/Component_Miner_02_S.png",
	desc = "Laser Mining Tool - extracts metal and crystal with high efficiency (2x)",
	power = -3,
	visual = "v_miner_adv_s",
	disregard_tooltip = true,
	-- production_recipe = false,
	production_recipe = CreateProductionRecipe({ fused_electrodes = 2, icchip = 2, optic_cable = 5 }, { c_assembler = 50 }),
	activation = "OnFirstRegisterChange",
	miner_effect = "fx_miner",
	miner_range = 1,
	on_remove = on_remove_clear_extra_data_keep_resimulated,
})

----- deconstructor -----
local c_deconstructor = Comp:RegisterComponent("c_deconstructor", {
	attachment_size = "Small", race = "robot", index = 1004, name = "Deconstructor",
	texture = "Main/textures/icons/components/Component_Deconstructor_01_S.png",
	desc = "Allows disassembly of completed units and buildings, refunding 100% of their cost",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, crystal = 10 }, { c_assembler = 30 }),
	power = -100,
	visual = "v_deconstructor_01_s",
	activation = "OnFirstRegisterChange",
	action_tooltip = action_tooltip_set_target,
	registers = {
		{ type = "entity", tip = "Target", ui_icon = "icon_target", click_action = true, filter = 'entity' },
	},

	range = 5,

	-- internal variable
	duration = 10, -- deconstruct duration
})

function c_deconstructor:action_click(comp, widget)
	CursorChooseEntity("Select the deconstruction target", function (target)
		if not comp.exists then return end -- got destroyed
		local arg = { comp = comp , reg = { entity = target } }
		Action.SendForEntity("SetRegister", comp.owner, arg)
	end,
	nil, comp.register_index, true)
end

function c_deconstructor:get_reg_error(comp)
	local reg1 = comp:GetRegister(1)
	local target_entity = reg1.entity
	if not target_entity then
		if not reg1.is_empty then
			return "Invalid Target"
		end
		return "No Target"
	end

	local target_frame_def = target_entity.has_extra_data and data.frames[target_entity.extra_data.resimulated] or target_entity.def
	local target_faction = target_entity.faction
	local own_faction = target_entity.faction == comp.faction
	local valid_faction = own_faction or (target_faction.is_world_faction and target_entity.lootable and not target_frame_def.immortal and target_frame_def.type ~= "DroppedItem")
	local deconstruct_error = valid_faction and CheckDeconstruct(target_entity, nil, (not own_faction or target_frame_def.drop_on_deconstruct))
	if deconstruct_error then return L("%s: %s", "Cannot deconstruct Target", deconstruct_error) end
	if not valid_faction then return "Cannot deconstruct Target" end

	return comp.owner:IsInRangeOf(target_entity, self.range) and "Cannot deconstruct Target" or "Not in range to deconstruct"
end

function c_deconstructor:on_update(comp, cause)
	local reg1 = comp:GetRegister(1)
	local target_entity = reg1.entity or (reg1.coord and Map.GetEntityAt(reg1.coord.x, reg1.coord.y))
	if not target_entity then
		if not reg1.is_empty then comp:FlagRegisterError(1) end
		comp:StopEffects()
		return
	end

	-- We are starting or finishing work on an entity, make sure its (still) our faction
	if cause & CC_REFRESH == 0 then
		local target_frame_def = target_entity.has_extra_data and data.frames[target_entity.extra_data.resimulated] or target_entity.def
		local target_faction = target_entity.faction
		local own_faction = target_entity.faction == comp.faction
		local valid_faction = own_faction or (target_faction.is_world_faction and target_entity.lootable and not target_frame_def.immortal and target_frame_def.type ~= "DroppedItem")
		local deconstruct_error = valid_faction and CheckDeconstruct(target_entity, nil, true)
		if deconstruct_error or not valid_faction then
			comp:FlagRegisterError(1)
			comp:StopEffects()
			return
		end
	end

	-- If work was finished, make sure the target entity did not change just now
	if cause & (CC_FINISH_WORK | CC_CHANGED_REGISTER_ENTITY) == CC_FINISH_WORK then
		-- Destroy target then turn off (drop frame definition ingredients along inventory)
		local target_frame_def = target_entity.has_extra_data and data.frames[target_entity.extra_data.resimulated] or target_entity.def
		local target_recipe = target_frame_def.production_recipe or target_frame_def.construction_recipe
		local drop_loc = target_frame_def.drop_on_deconstruct and target_entity.location
		target_entity:Destroy(true, target_recipe and target_recipe.ingredients, comp.owner)

		if drop_loc then
			target_frame_def.drop_on_deconstruct(drop_loc.x, drop_loc.y)
		end

		if not comp:RegisterIsLink(1) then
			comp:SetRegister(1, nil)
		end
		comp:StopEffects()
		return
	end

	-- Make sure we are next to the target
	if comp:RequestStateMove(target_entity, self.range) then
		comp:FlagRegisterError(1)
		comp:StopEffects()
		return
	end

	comp:PlayWorkEffect("fx_deconstructor", "fx")
	comp:FlagRegisterError(1, false)

	-- Start deconstruct work with refresh to check if work needs to continue
	return comp:SetStateStartWork(self.duration, true, (cause & CC_CHANGED_REGISTER_ENTITY == 0))
end

function Delay.DelayedDestroyEntity(args)
	if args.ent.exists then args.ent:Destroy(not args.nodrop) end
end

function Delay.DestroyExplorable(arg) -- use DelayedDestroyEntity, kept for backwards compat
	if arg.entity.exists then arg.entity:Destroy(false) end
end

function Delay.DelayedRemoveComponent(arg)
	if arg.comp.exists then arg.comp:Destroy() end
end

function Delay.TurretDamage(arg)
	local comp = arg.comp
	if comp.exists then
		comp.def:damage_func(comp, arg.entity, arg.loc)
	end
end

function Delay.TurretEffect(arg)
	arg.comp:PlayEffect(arg.effect, arg.socket, arg.target)
end

-----------------------
----- BASE TURRET -----
-----------------------
Comp:RegisterComponent("c_testdummy_healer", {
	name = "Test Dummy Healer",
	on_take_damage = function(self, comp, amount)
		comp.owner.health = comp.owner.max_health
	end,
})

local c_turret = Comp:RegisterComponent("c_turret", {
	attachment_size = "Medium", race = "robot", index = 1031, name = "Turret",
	texture = "Main/textures/icons/components/component_standardTurret_01_m.png",
	desc = "Medium sized turret with good damage and range",
	power = -10,
	visual = "v_turret_m",
	activation = "OnFirstRegisterChange|OnTrustChange",
	action_tooltip = action_tooltip_set_target,
	registers = {
		{ type = "entity", tip = "Preferred Target", ui_icon = "icon_target", click_action = true, filter = 'entity' },
		{ read_only = true, tip = "Current Target", click_action = true },
	},
	production_recipe = CreateProductionRecipe({  c_adv_portable_turret = 1, wire = 10, hdframe = 5 }, { c_assembler = 5 }),
	-- production_recipe = CreateProductionRecipe({ circuit_board = 1, energized_plate = 5, crystal = 10 }, { c_assembler = 5 }),
	on_add = on_add_charge,
	on_remove = on_remove_clear_extra_data,
	get_ui = true,

	trigger_radius = 7,
	attack_radius = 7,

	trigger_channels = "bot|building|bug",

	-- internal variable
	damage = 72,   -- damage per shot -- 8
	damage_type = "energy_damage",
	duration = 6, -- charge duration -- 2
	shoot_fx = "fx_turret_laser",  -- fx_turret_1
	shoot_speed = 1,
	shoot_socket = "fx",
	shoot_while_moving = true,
	--shoot_target = "ground", -- set to "air" or "ground" to limit, otherwise can shoot both
})

function c_turret:action_click(comp, widget)
	CursorChooseEntity("Select the attack target", function (target)
		if not comp.exists then return end -- got destroyed
		local arg = { comp = comp , reg = { entity = target } }
		if target and target.faction == comp.faction then
			ConfirmBox("Are you sure you want to attack your own unit/building?", function()
				Action.SendForEntity("SetRegister", comp.owner, arg)
			end)
		else
			Action.SendForEntity("SetRegister", comp.owner, arg)
		end
	end,
	nil, comp.register_index, true)
end

function c_turret:on_trigger(comp, other_entity)
	if comp.faction:GetTrust(other_entity) == "ENEMY" then
		comp:Activate()
	end
end

local function TurretApplyDamage(compdef, comp, enemy, damage, damage_type, damager, extra_effect)
	if damage_type then damage = math.ceil(CalcDamageReduction(damage, enemy.def.shield_type, damage_type)) end
	if (comp.def.damage_air_bonus and enemy.def.cost_modifier) or
		(comp.def.damage_ground_bonus and not enemy.def.cost_modifier) then
		damage = math.ceil(damage * (comp.def.damage_air_bonus or comp.def.damage_ground_bonus))
	end

	AddDamagedEnemy(enemy, damage, damage_type)
	enemy:RemoveHealth(damage, damager, damage_type)
	if enemy.exists and enemy.health > 0 and extra_effect then extra_effect(compdef, comp, enemy) end
end

function c_turret:damage_func(comp, e, trgloc)
	local damager, damager_faction = comp.owner, comp.faction
	local damage, damage_type, extra_effect = self.damage, self.damage_type, self.extra_effect
	local degrade = 1

	-- If e was destroyed or has moved more than 2 tiles away, see if there is another enemy at the location
	if not e or not e.exists or e:GetRangeSquaredTo(trgloc) > 4 then
		e = Map.GetEntityAt(trgloc.x, trgloc.y)
		if not e or damager_faction:GetTrust(e) ~= "ENEMY" then
			e = nil
		end
	end
	if e then
		-- Damage e for all weapon types except beam (so it will get damaged even if it is a resource or foundation)
		TurretApplyDamage(self, comp, e, damage, damage_type, damager, extra_effect)
		if self.beam_range then degrade = degrade - 0.1 end
	end

	if self.blast then
		if self.blast_fx then
			UI.Run(function() View.PlayEffect(self.blast_fx, trgloc.x, trgloc.y) end)
		end
		local affects_flying = self.affects_flying
		for _,enemy in ipairs(Map.GetEntitiesInRange(trgloc, self.blast, FF_OPERATING|FF_WALL|FF_GATE|FF_ENEMYFACTION, damager_faction)) do
			--  for splash damage, check trust if its an enemy (only specific splash damage affects air units)
			if e ~= enemy and (affects_flying or not IsFlyingUnit(enemy)) then
				TurretApplyDamage(self, comp, enemy, damage // 2, damage_type, damager, extra_effect) -- 50% splash damage
			end
		end
	elseif self.pulse then
		local affects_flying = self.affects_flying
		for _,enemy in ipairs(Map.GetEntitiesInRange(damager, self.pulse, FF_OPERATING|FF_WALL|FF_GATE|FF_ENEMYFACTION)) do
			-- check trust if its an enemy (only specific pulse damage affects air units)
			if e ~= enemy and (affects_flying or not IsFlyingUnit(enemy)) then
				TurretApplyDamage(self, comp, enemy, damage, damage_type, damager, extra_effect)
			end
		end
		if self.explode then
			Map.Delay("DelayedDestroyEntity", self.explode, { ent = comp.owner })
		end
	elseif self.beam_range then -- beam style (railgun)
		for _,enemy in ipairs(Map.GetEntitiesOnLine(damager, trgloc, self.beam_range, FF_OPERATING|FF_WALL|FF_GATE|FF_ENEMYFACTION)) do -- TODO: needs to specifically add in the target entity
			TurretApplyDamage(self, comp, enemy, math.floor(damage * degrade), damage_type, damager, extra_effect)
			degrade = degrade - 0.1
			if degrade <= 0.1 then break end
		end
	end
end

function c_turret:acquire_target_func(comp, type_filter, is_not)
	-- find closest enemy to attack
	local owner = comp.owner
	local owner_faction = owner.faction
	local shoot_target = self.shoot_target
	local is_player_controlled = owner_faction.is_player_controlled
	local invisible_in_range, found_wall
	local preferred_target
	local attack_target = comp:FindClosestTriggeringEntity(function(e)
		if not e.def.immortal and not e.is_construction and not e.stealth then
			if not is_player_controlled and IsBot(e) and e.powered_down then return end
			if shoot_target == "ground" and IsFlyingUnit(e) then return end
			if shoot_target == "air"and not IsFlyingUnit(e) then return end

			-- bug type filtering (if needed elsewhere move to a function)
			if type_filter then
				local id, ok = e.id, false
				if type_filter == "f_trilobyte1" then
					local id = e.id
					ok = id == "f_trilobyte1" or id == "f_trilobyte1a" or id == "f_trilobyte1b" or id =="f_trilobyte_testdummy"
				elseif type_filter == "f_scaramar1" then
					local id = e.id
					ok = id == "f_scaramar1" or id == "f_scaramar1_egg"
				elseif type_filter == "f_larva1" then
					local id = e.id
					ok = id == "f_larva1" or id == "f_larva2"
				elseif type_filter == "f_wasp1" then
					local id = e.id
					ok = id == "f_wasp1" or id == "f_wasp1_testdummy"
				else ok = id == type_filter
				end
				if is_not then ok = not ok end

				if not ok then
					if not preferred_target and owner_faction:IsVisible(e) then
						preferred_target = e
					end
					return
				end
			end
			if is_player_controlled and IsWall(e) then
				if not found_wall then found_wall = e end
				return
			end
			invisible_in_range = true
			return owner_faction:IsVisible(e)
		end
	end, FF_ENEMYFACTION)
	if not attack_target then attack_target = preferred_target end
	if not attack_target and found_wall then attack_target = found_wall end
	return attack_target, invisible_in_range
end

function c_turret:shoot_func(comp, attack_target)
	local owner = comp.owner
	--print("                              Attacking - Have Power: " .. tostring(owner.has_power or self.power == 0) .. " - Shoot Speed: " .. tostring(self.shoot_speed) .. " - Damage: " .. tostring(self.damage))
	--if cause & CC_FINISH_WORK ~= 0 and (owner.has_power or self.power == 0) then
	local owner_faction = owner.faction
	owner_faction:SetTrust(attack_target.faction, "ENEMY", true)
	owner_faction:AddMood("battle", 50)

	local curr_loc = attack_target.location
	if self.shoot_fx then
		if self.shoot_delay then
			Map.Delay("TurretEffect", self.shoot_delay, { comp = comp, target = attack_target, socket = self.shoot_socket, effect = self.shoot_fx })
		elseif self.beam_range then
			local beamx, beamy = Map.GetLocationInRange(owner, attack_target, self.beam_range)
			local tl = { beamx, beamy, 0.3 } -- make the beam hit a bit above ground
			comp:PlayEffect(self.shoot_fx, self.shoot_socket, data.fx[self.shoot_fx].particle and { Target = tl })
		elseif self.blast then
			curr_loc.x, curr_loc.y = attack_target:EstimateLocationInTicks(self.shoot_speed)
			comp:PlayEffect(self.shoot_fx, self.shoot_socket, data.fx[self.shoot_fx].particle and { Target = curr_loc })
		elseif self.pulse then
			comp:PlayEffect(self.shoot_fx, self.shoot_socket, owner)
		else
			comp:PlayEffect(self.shoot_fx, self.shoot_socket, attack_target)
		end
	end

	owner:Activate()

	-- delay actual caused damage by shot speed
	Map.Delay("TurretDamage", self.shoot_speed, { entity = attack_target, comp = comp, loc = curr_loc })

	reveal_if_stealthed(owner)
end

function c_turret:on_update(comp, cause)
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - My Range: " .. tostring(self.trigger_radius))

	-- finished charging
	if cause & CC_FINISH_WORK ~= 0 then
		comp.extra_data.charged = true
	end

	-- Check if there is a manually chosen target and if it's in attack range
	local invisible_in_range = false
	local search_radius = self.trigger_radius
	local attack_radius = self.attack_radius or search_radius
	local reg1_num, reg1_id, reg1_entity, reg1_coord_x, reg1_coord_y = comp:GetRegisterData(1)
	if reg1_id == "v_powereddown" then
		comp:SetRegister(2)
		return
	end
	local is_not = reg1_num == REG_NOT
	local owner, manual_target, attack_target = comp.owner, reg1_entity
	if (manual_target == owner) then manual_target = nil end
	if manual_target and not manual_target.is_placed then manual_target = nil end
	if manual_target then
		local shoot_target = self.shoot_target
		if manual_target.def.immortal or (shoot_target == "ground" and IsFlyingUnit(manual_target)) or (shoot_target == "air" and not IsFlyingUnit(manual_target)) then
			manual_target = nil
		end
	end

	if manual_target and owner:IsInRangeOf(manual_target, search_radius) then
		invisible_in_range = true
		if owner.faction:IsVisible(manual_target) then
			attack_target = manual_target
		end
	else
		attack_target, invisible_in_range = self:acquire_target_func(comp, reg1_id, is_not)
	end

	-- attack move
	if reg1_coord_x and not attack_target then
		if comp:RequestStateMove(reg1_coord_x, reg1_coord_y, reg1_num >= 0 and reg1_num or comp.def.attack_radius, true) then
			-- can't do anything if not charged
			if not comp.extra_data.charged then
				return comp:SetStateStartWork(self.duration, false, true)
			end
			return
		end

		-- got to location, clear register
		if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
	end

	-- Enforce HoldPosition
	local hold_position = reg1_id == "v_lock_locked" and not owner.is_docked
	if hold_position then
		comp:RequestStateMove(owner, 1, true) -- lock movement in place
	end

	-- can't do anything if not charged
	if not comp.extra_data.charged then
		return comp:SetStateStartWork(self.duration, false, true)
	end

	if not attack_target and not manual_target then
		-- Clear the current target register and shut down
		--print("                              No attack target or manual target, shutting down")
		comp:SetRegister(2, nil)
		return invisible_in_range and comp:SetStateSleep(1)
	end

	--print("                              Attack Target: " .. tostring(attack_target) .. " - Manual Target: " .. tostring(manual_target) .. " - Move Distance: " .. tostring(owner:GetRangeTo(manual_target or attack_target)) .. " - Attack Distance: " .. tostring(owner:GetRangeTo(attack_target or manual_target)))
	local aim_target    = attack_target or manual_target
	local pursue_target = manual_target or attack_target

	-- If the component has a set leash distance and the target is further than that from goto, abort
	local faction, leash_distance = owner.faction, self.leash_distance
	if leash_distance and not faction.is_player_controlled then
		local leash_goto = owner:GetRegisterEntity(FRAMEREG_GOTO)
		-- home entity destroyed?
		if not leash_goto and owner.is_placed then
			leash_goto = owner:GetRegisterCoord(FRAMEREG_GOTO)
			-- no home location set
			if not leash_goto then
				leash_goto = owner.location
				owner:SetRegisterCoord(FRAMEREG_GOTO, leash_goto)
				if not owner:FindComponent("c_bug_homeless") then Map.Defer(function() if owner.exists then owner:AddComponent("c_bug_homeless", "hidden") end end) end
			end
		end
		--print("                              Leash Goto: " .. tostring(leash_goto) .. " - Pursue Target: " .. tostring(pursue_target) .. " - Leash Distance: " .. tostring(leash_goto and pursue_target:GetRangeTo(leash_goto)))
		if leash_goto and not reg1_coord_x then
			if manual_target and attack_target and attack_target ~= manual_target and not manual_target:IsInRangeOf(leash_goto, leash_distance) then
				pursue_target = attack_target
			end
			if not pursue_target:IsInRangeOf(leash_goto, leash_distance) then
				-- Target is further away from goto than leash distance, clear current target and go back for now (but sleep if they come closer again)
				comp:SetRegister(2, nil)
				if owner.docked_garage == leash_goto then
					--print("                              Abort pursue, at home, shutting down")
					if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end -- we're back home, give up on any target
					return -- shut down
				else
					--print("                              Abort pursue, move back home")
					comp:RequestStateMove(leash_goto, 0, true)
					return comp:SetStateSleep()
				end
			end
		end
	end

	-- Set the current target register
	comp:SetRegisterEntity(2, aim_target)

	-- If set, move towards manual_target even while attacking a different attack_target that is in attack range
	local is_visible = faction:IsVisible(pursue_target)
	local is_seen = is_visible or faction:IsSeen(pursue_target)
	local need_move = not hold_position and is_seen and comp:RequestStateMove(pursue_target, is_visible and attack_radius or owner.def.visibility_range, true)
	if need_move and owner.is_docked then return comp:SetStateSleep(1) end

	-- Rotate the component towards the target we're focusing on (RequestStateMove above also does that but only if already in attack range)
	if need_move then comp:RotateComponent(aim_target) end

	-- Confirm range on attack_target because it can be further away than trigger_radius when using attack_radius
	if not attack_target or not owner:IsInRangeOf(attack_target, attack_radius) then
		local diffsq = owner:GetRangeSquaredTo(aim_target) - attack_radius
		local sleep = diffsq >= 36 and 5 or diffsq >= 16 and 3 or diffsq >= 4 and 2 or 1
		--print("                              Not in range (" .. math.sqrt(diffsq > 0 and diffsq or 1) .. " tiles away), sleeping " .. sleep .. " ticks", attack_radius, search_radius, comp.owner.is_moving)
		return comp:SetStateSleep(sleep)
	end

	-- Too close?
	if self.minimum_range and owner:IsInRangeOf(aim_target, self.minimum_range - 1) then
		return comp:SetStateSleep()
	end

	if comp.owner.powered_down then return end
	if not self.shoot_while_moving and owner.is_moving then
		return comp:SetStateSleep()
	end

	self:shoot_func(comp, attack_target)

	-- start charging again
	comp.extra_data.charged = false
	return comp:SetStateStartWork(self.duration)
end

----- PORTABLE TURRET ------
----------------------------

local c_portable_turret = c_turret:RegisterComponent("c_portable_turret", {
	attachment_size = "Small", race = "robot", index = 1031, name = "Small Turret",
	texture = "Main/textures/icons/components/Component_StarterTurret_01_S.png",
	desc = "Basic defensive turret",
	power = -5,
	visual = "v_starterturret_s",
	production_recipe = CreateProductionRecipe({ metalbar = 5, circuit_board = 1 }, { c_assembler = 15 }),
	trigger_radius = 7,
	attack_radius = 7,

	-- internal variable
	damage = 8, -- damage per shot -- 5
	damage_type = "energy_damage",
	duration = 5, -- charge duration -- 3
	shoot_while_moving = true,
	shoot_fx = "fx_turret_laser",
	shoot_speed = 0,
})

----- ADVANCED PORTABLE TURRET -----
------------------------------------

c_turret:RegisterComponent("c_adv_portable_turret", {
	attachment_size = "Small", race = "robot", index = 1032, name = "Small Advanced Turret",
	texture = "Main/textures/icons/components/Component_AdvancedTurret_01_S.png",
	desc = "A longer ranged small defensive turret",
	power = -5,
	visual = "v_starterturret_adv_s",
	production_recipe = CreateProductionRecipe({ c_portable_turret = 1, energized_plate = 5, circuit_board = 1 }, { c_assembler = 25 }), -- icchip
	trigger_radius = 7,
	attack_radius = 7,

	-- internal variable
	damage = 18, -- damage per shot -- 5
	damage_type = "energy_damage",
	duration = 6, -- charge duration -- 3
	shoot_while_moving = true,
	shoot_fx = "fx_turret_laser",
	shoot_speed = 0,
})

----- BLIGHT TURRET (Plasma Damage) -----
-----------------------------------------

c_portable_turret:RegisterComponent("c_portable_turret_red", {
	attachment_size = "Small", race = "blight", index = 2031, name = "Blight Turret",
	texture = "Main/textures/icons/components/Component_StarterTurret_Red_01_S.png",
	desc = "Blight crystal turret",
	power = -10,
	visual = "v_starterturret_red_s",
	production_recipe = CreateProductionRecipe({ c_portable_turret = 1, blight_plasma = 5 }, { c_assembler = 15 }),
	trigger_radius = 7,
	attack_radius = 7,

	-- internal variable
	damage = 44,
	damage_type = "plasma_damage",
	duration = 6,
	-- shoot_while_moving = false,
	shoot_fx = "fx_turret_laser",
	shoot_speed = 0,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 20,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 20, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

----- VIRUS TURRET -----
------------------------

c_portable_turret:RegisterComponent("c_portable_turret_green", {
	attachment_size = "Small", race = "virus", index = 4031, name = "Viral Turret",
	texture = "Main/textures/icons/components/Component_StarterTurret_Green_01_S.png",
	desc = "Virus turret",
	power = -10,
	visual = "v_starterturret_green_s",
	production_recipe = CreateProductionRecipe({ c_portable_turret = 1, infected_circuit_board = 1 }, { c_assembler = 15 }),
	trigger_radius = 7,
	attack_radius = 7,

	-- internal variable
	damage = 32, -- damage per shot --12--12
	damage_type = "energy_damage",
	duration = 8, -- charge duration -- 4--6
	-- shoot_while_moving = false,
	shoot_fx = "fx_turret_laser",
	shoot_speed = 0,
	extra_effect_name = "Slow",
	extra_effect = slow_effect,
	extra_stat = {
		{ "icon_tiny_damage", "50%", "Slow amount" },
		{ "icon_tiny_damage", "5s", "Slow Duration" },
	},
})

------------------------------------------
----- BASE (Medium) TURRET c_turret ------
------------------------------------------

----- LASER TURRET -----
------------------------

c_turret:RegisterComponent("c_laser_turret", {
	attachment_size = "Medium", race = "robot", index = 1032, name = "Laser Turret",
	texture = "Main/textures/icons/components/component_laserturret_01_m.png",
	desc = "Upgraded turret that fires a strong laser",
	power = -20,
	visual = "v_laser_turret_m",
	production_recipe = CreateProductionRecipe({ c_turret = 1, refined_crystal = 10, hdframe = 5, fused_electrodes = 10 }, { c_advanced_assembler = 5 }), -- hdframe = 4,
	trigger_radius = 7,
	attack_radius = 7,

	-- internal variable
	damage = 128, -- damage per shot -- 65
	damage_type = "energy_damage",
	duration = 6, -- charge duration -- 6
	shoot_while_moving = true,
	shoot_fx = "fx_turret_laser",
})

----- PLASMA CANNON -----
-------------------------

c_turret:RegisterComponent("c_plasma_cannon", {
	attachment_size = "Medium", race = "blight", index = 2031, name = "Plasma Cannon",
	texture = "Main/textures/icons/components/Component_PlasmaCannon_01_M.png",
	desc = "Plasma Cannon",
	power = -35,
	visual = "v_plasma_canon_m",
	production_recipe = CreateProductionRecipe({ c_photon_cannon = 1, cpu = 5, blight_plasma = 10, hdframe = 5 }, { c_advanced_assembler = 30, }),
	trigger_radius = 15,
	attack_radius = 15,
	minimum_range = 3,

	-- internal variable
	damage = 250, -- damage per shot -- 175
	duration = 25, -- charge duration -- 2
	shoot_speed = 9,
	damage_type = "plasma_damage",
	blast = 2,
	shoot_while_moving = false,
	shoot_fx = "fx_plasma_blast",
	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})


------ PHOTON BEAM ------
-------------------------

c_turret:RegisterComponent("c_photon_beam", {
	attachment_size = "Medium", race = "robot", index = 1033, name = "Photon Beam",
	texture = "Main/textures/icons/components/Component_PhotonBeam_01_M.png",
	desc = "Powerful and Penetrating Beam weapon. Limited effectiveness against air targets.",
	power = -20,
	visual = "v_photon_beam_m",
	production_recipe = CreateProductionRecipe({ c_photon_cannon = 1, icchip = 5, crystal_powder = 5, hdframe = 5 }, { c_advanced_assembler = 5 }),
	trigger_radius = 8,
	attack_radius = 8,

	-- internal variable
	damage = 120, -- damage per shot -- 90
	damage_type = "energy_damage",
	duration = 10, -- charge duration -- 10
	-- shoot_fx = "fx_turret_1",
	shoot_while_moving = false,
	shoot_fx = "fx_photon_beam",
	beam_range = 8,
	damage_air_bonus = 0.5,
})

----- PHOTON CANNON -----
-------------------------

c_turret:RegisterComponent("c_photon_cannon", {
	attachment_size = "Medium", race = "robot", index = 1034, name = "Photon Cannon",
	texture = "Main/textures/icons/components/Component_PhotonCannon_01_M.png",
	desc = "Hyper-advanced turret",
	power = -25,
	visual = "v_photon_canon_m",
	production_recipe = CreateProductionRecipe({ c_adv_portable_turret = 1, icchip = 5, refined_crystal = 2, hdframe = 5 }, { c_assembler = 5 }), -- crystal_power = 10
	trigger_radius = 10,
	attack_radius = 10,

	minimum_range = 2,

	-- internal variable
	damage = 180, -- damage per shot -- 120
	damage_type = "energy_damage",
	duration = 20, -- charge duration -- 10
	------ CANNON -------
	shoot_speed = 10,
	blast = 2,
	shoot_while_moving = false,
	shoot_fx = "fx_photon_bomb",
})

----- MISSILE TURRET -----
--------------------------

c_turret:RegisterComponent("c_missile_turret", {
	attachment_size = "Large", race = "human", index = 3031, name = "Missile Launcher",
	texture = "Main/textures/icons/components/Component_MissileLauncher_01_L.png",
	desc = "Mounted Missile turret",
	power = -50,
	visual = "v_missile_launcher_m",
	production_recipe = CreateProductionRecipe({ micropro = 5, smallreactor = 5, ldframe = 5 }, { c_human_factory = 20, c_human_factory_robots = 40 }),
	trigger_radius = 16,
	attack_radius = 16,
	minimum_range = 4,
	trigger_channels = "bot|building|bug",

	-- internal variable
	damage = 600, -- damage per shot -- 240
	duration = 30, -- charge duration -- 30
	damage_type = "physical_damage",
	shoot_fx = "fx_turret_missile",
	shoot_speed = 10, -- delay between shoot and hit
	blast = 2, -- splash range
	shoot_while_moving = false,
})

----- MELEE PULSE -----
-----------------------

c_turret:RegisterComponent("c_melee_pulse", {
	attachment_size = "Small", race = "robot", index = 1033, name = "Melee Pulse Attack",
	texture = "Main/textures/icons/components/component_melee_pulse.png",
	desc = "Strong energy pulse released against an adjacent target",
	power = -10, -- --10
	visual = "v_melee_pulse_s",
	production_recipe = CreateProductionRecipe({ energized_plate = 5, silicon = 2 }, { c_assembler = 5 }),
	trigger_radius = 1,
	attack_radius = 1,

	-- internal variable
	shoot_target = "ground",
	damage = 64, -- damage per shot
	damage_type = "energy_damage",
	duration = 8, -- charge duration
	shoot_while_moving = true,
	shoot_fx = "fx_pulse",
	shoot_socket = "_entity",
	pulse = 1,

	extra_effect = shieldrecharge_effect,
	extra_effect_name = "Shield Recharge",
	shield_charge = 20, -- also change in stat block below
	extra_stat = {
		{ "icon_tiny_damage", 20, "Shield Recharge" },
	},
})

----- PULSE DISRUPTER -----
-----------------------

c_turret:RegisterComponent("c_pulse_disrupter", {
	attachment_size = "Medium", race = "robot", index = 1035, name = "Pulse Disruptor Attack",
	texture = "Main/textures/icons/components/Component_PulseDisrupter_01_M.png",
	desc = "Disruptive energy pulse released against an adjacent target",
	power = -20, -- --20
	visual = "v_pulse_disrupter_m",
	production_recipe = CreateProductionRecipe({ c_melee_pulse = 1, hdframe = 5, refined_crystal = 5 }, { c_assembler = 5 }),
	trigger_radius = 1, -- 6
	attack_radius = 1,

	-- internal variable
	shoot_target = "ground",
	damage = 96, -- damage per shot --50
	damage_type = "energy_damage",
	duration = 8, -- charge duration -12
	shoot_while_moving = true,
	shoot_fx = "fx_pulse",
	shoot_socket = "_entity",
	pulse = 1,

	extra_effect = electromag_effect,
	extra_effect_name = "Disruptor",
	disruptor = 35,
	shield_charge = 30,
	extra_stat = {
		{ "icon_tiny_damage", 35, "Shield Damage" },
		{ "icon_tiny_damage", 30, "Shield Recharge" },
	},
})

----- PULSE LASERS -----
----------------------------

c_turret:RegisterComponent("c_pulselasers", {
	attachment_size = "Medium", race = "robot", index = 1036, name = "Pulse Lasers",
	texture = "Main/textures/icons/components/Component_PulseLasers_01_M.png",
	desc = "Short range rapid-fire pulse lasers. Very effective against air targets.",
	power = -10, -- --10
	visual = "v_pulselasers_m",
	-- production_recipe = CreateProductionRecipe({ cable = 5, hdframe = 5 }, { c_assembler = 5 }),
	production_recipe = CreateProductionRecipe({ c_portable_turret = 1, energized_plate = 6, wire = 4 }, { c_assembler = 5 }),
	trigger_radius = 6,
	attack_radius = 6,

	-- internal variable
	damage = 8, -- damage per shot --5
	damage_air_bonus = 2,
	damage_type = "energy_damage",
	duration = 1, -- charge duration --2
	shoot_while_moving = true,
	shoot_fx = "fx_turret_3",
})

----- TWIN AUTOCANNONS (HUMAN) -----
----------------------------

c_turret:RegisterComponent("c_twin_autocannons", {
	attachment_size = "Small", race = "human", index = 3031, name = "Twin Autocannons",
	texture = "Main/textures/icons/components/Component_TwinTurret_01_S.png",
	desc = "Long-range twin-autocannons. Effective against air targets.",
	power = -10, -- --10
	visual = "v_twin_autocannons_s",
	-- production_recipe = CreateProductionRecipe({ cable = 5, hdframe = 5 }, { c_assembler = 5 }),
	production_recipe = CreateProductionRecipe({ c_pulselasers =1, smallreactor = 2, transformer = 2, aluminiumrod = 5 }, { c_human_factory_robots = 5 }),
	trigger_radius = 6, -- 6
	attack_radius = 6, -- 6

	-- internal variable
	damage = 10, -- damage per shot --8
	damage_air_bonus = 1.5,
	damage_type = "physical_damage",
	duration = 1, -- charge duration --2--4
	shoot_while_moving = true,
	shoot_fx = "fx_turret_2",
})

----- RAILGUN -----
-------------------

c_turret:RegisterComponent("c_railgun", {
	attachment_size = "Medium", race = "human", index = 3031, name = "Railgun",
	texture = "Main/textures/icons/components/Component_Railgun_01_M.png",
	desc = "Electromagnetic force particle cannon. Limited effectiveness against air targets.",
	power = -50, -- --50
	visual = "v_railgun_m",
	production_recipe = CreateProductionRecipe({ c_photon_beam = 1,micropro = 5, smallreactor = 10, ldframe = 10 }, { c_human_factory_robots = 5 }),
	trigger_radius = 10,
	attack_radius = 10,

	-- internal variable
	damage = 168, -- damage per shot --150
	damage_type = "physical_damage",
	duration = 12, -- charge duration --15
	shoot_fx = "fx_railgun",
	beam_range = 10,
	damage_air_bonus = 0.5,
	shoot_while_moving = false,
})

----- PLASMA TURRET -----
-------------------------

c_turret:RegisterComponent("c_plasma_turret", {
	attachment_size = "Small", race = "blight", index = 2032, name = "Plasma Turret",
	texture = "Main/textures/icons/components/Component_PlasmaTurret_01_S.png",
	desc = "Plasma Turret",
	power = -15, -- -20
	visual = "v_blight_plasmaturret_s",
	production_recipe = CreateProductionRecipe({ c_portable_turret_red = 1, icchip = 3, blightbar = 10, hdframe = 2 }, { c_advanced_assembler = 30, }),
	trigger_radius = 7,
	attack_radius = 7,

	-- internal variable
	damage = 33, -- damage per shot -- 21
	damage_type = "plasma_damage",
	duration = 3, -- charge duration -- 50
	shoot_speed = 1,
	shoot_while_moving = true,
	shoot_fx = "fx_plasma_bolt",

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 25,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 25, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

----- VIRAL PULSE -----
-----------------------

c_turret:RegisterComponent("c_viral_pulse", {
	attachment_size = "Small", race = "virus", index = 4032, name = "Viral Pulse Attack",
	texture = "Main/textures/icons/components/Component_ViralPulse_01_S.png",
	desc = "Strong energy pulse containing the virus released against adjacent targets",
	power = -15, -- -10
	visual = "v_viral_pulse_s",
	production_recipe = CreateProductionRecipe({ c_pulse_disrupter = 1, hdframe = 5, infected_circuit_board = 2, }, { c_advanced_assembler = 30, }),
	trigger_radius = 1, -- 6
	attack_radius = 1,

	-- internal variable
	shoot_target = "ground",
	damage = 112, -- damage per shot
	damage_type = "energy_damage",
	duration = 8, -- charge duration
	shoot_fx = "fx_viral_pulse",
	shoot_while_moving = true,
	shoot_socket = "_entity",
	pulse = 1,
	extra_effect_name = "Slow",
	extra_effect = slow_effect,
	extra_stat = {
		{ "icon_tiny_damage", "50%", "Slow amount" },
		{ "icon_tiny_damage", "5s", "Slow Duration" },
	},
})

----- HYBRID BEAM CANNON -----
------------------------------

c_turret:RegisterComponent("c_hybrid_beam_cannon", {
	attachment_size = "Medium", race = "alien", index = 5031, name = "Hybrid Beam Cannon",
	texture = "Main/textures/icons/components/Component_AlienBeamTurret_01_M.png",
	desc = "Hybrid technology that generates a powerful condensed plasma beam. Limited effectiveness against air targets.",
	power = -100, -- --100
	visual = "v_hybrid_beam_cannon_m",
	production_recipe = CreateProductionRecipe({ energized_artifact = 1, cpu = 3, hdframe = 10 }, { c_adv_alien_factory = 150, }),

	trigger_radius = 15,
	attack_radius = 15,

	-- internal variable
	damage = 300, -- damage per shot --300
	damage_type = "plasma_damage",
	duration = 15, -- charge duration --15
	shoot_fx = "fx_plasma_beam",
	beam_range = 15,
	damage_air_bonus = 0.5,
	shoot_while_moving = false,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

----- HUMAN WEAPONS -----
-----------------------------
----- Single LIGHT CANNON (HUMAN) -----
-------------------------------------

c_turret:RegisterComponent("c_light_cannon", {
	attachment_size = "Small", race = "human", index = 3032, name = "Recoilless Rifle",
	texture = "Main/textures/icons/human/human_light_cannon.png",
	desc = "Short-range recoilless rifle",
	power = -10,
	visual = "v_human_light_turret",
	production_recipe = CreateProductionRecipe({ aluminiumrod = 5, aluminiumsheet = 5 }, { c_human_commandcenter =80, c_human_barracks = 20 }),
	trigger_radius = 8, -- 7
	attack_radius = 8, -- 7

	-- internal variable
	damage = 30, -- 45
	damage_type = "physical_damage",
	duration = 3,
	shoot_while_moving = true,
	shoot_fx = "fx_turret_2",
})

----- TWIN AUTOCANNONS (HUMAN) -----
----------------------------

c_turret:RegisterComponent("c_human_autocannons", {
	attachment_size = "Hidden", race = "human", index = 3031, name = "Autocannons",
	texture = "Main/textures/icons/human/human_autocannons.png",
	desc = "Mounted rapid-fire cannons. Effective against air targets.",
	power = -20, -- --10
	production_recipe = false,
	visual = "v_twin_autocannons_s",
	trigger_radius = 6, -- 6
	attack_radius = 6, -- 6

	-- internal variable
	damage = 12,
	damage_type = "physical_damage",
	damage_air_bonus = 1.5,
	duration = 1,
	shoot_while_moving = true,
	shoot_fx = "fx_turret_2",
})

----- HUMAN TANK TURRET -----
-----------------------------

c_turret:RegisterComponent("c_human_tank_turret", {
	attachment_size = "Medium", race = "human", index = 3032, name = "Tank Turret",
	desc = "A turret weapon for mounting on tanks",
	texture = "Main/textures/icons/human/human_tank_turret_01.png",
	power = -30,
	visual = "v_human_tank_turret",
	production_recipe = CreateProductionRecipe({ ceramictiles = 10, polymer = 5, smallreactor = 5 }, { c_human_vehiclefactory = 50 }),
	trigger_radius = 6, -- 6
	attack_radius = 6, -- 6

	-- internal variable
	damage = 180, -- 96 -- damage per shot
	damage_type = "physical_damage",
	duration = 9, -- charge duration
	shoot_while_moving = true,
	shoot_fx = "fx_turret_2",
})

----- HUMAN MISSILE LAUNCHER -----
----------------------------------

c_turret:RegisterComponent("c_human_missilelauncher", {
	attachment_size = "Large", race = "human", index = 3032, name = "Heavy Rocket Launcher",
	texture = "Main/textures/icons/human/human_rocket_launcher.png",
	desc = "Mounted Missile turret",
	power = -50,
	visual = "v_human_missile_launcher",
	production_recipe = CreateProductionRecipe({ c_micro_reactor = 1, ceramictiles = 20 }, { c_human_vehiclefactory = 50 }),
	trigger_radius = 20,
	attack_radius = 20,
	minimum_range = 4,
	trigger_channels = "bot|building|bug",

	-- internal variable
	damage = 162, -- 144 -- damage per shot
	duration = 18, ---- charge duration
	damage_type = "physical_damage",
	shoot_fx = "fx_turret_missile",
	shoot_speed = 10, -- delay between shoot and hit
	blast = 2, -- splash range
	shoot_while_moving = false,
})

c_turret:RegisterComponent("c_human_supportlauncher", {
	attachment_size = "Hidden", race = "human", index = 3033, name = "Support Launcher",
	texture = "Main/textures/icons/human/human_support_launcher.png",
	desc = "Mounted Support Grenade Launcher",
	power = -10,
	visual = "v_human_missile_launcher",
	production_recipe = false,
	trigger_radius = 7,
	attack_radius = 7,
	minimum_range = 1,
	trigger_channels = "bot|building|bug",

	-- internal variable
	damage = 90, -- 144 -- damage per shot
	duration = 30, ---- charge duration
	damage_type = "physical_damage",
	shoot_fx = "fx_turret_missile",
	shoot_speed = 4, -- delay between shoot and hit
	blast = 1, -- splash range
	shoot_while_moving = false,
})

-- defense drone only works when it has a dock
c_turret:RegisterComponent("c_defense_drone_turret", {
	attachment_size = "Hidden", race = "human", index = 3032, name = "Defense Drone Turret",
	texture = "Main/textures/icons/components/turret_defensedrone.png",
	desc = "Basic defensive turret",
	production_recipe = false,
	on_update = function(self, comp, cause)
		-- only run if comp.owner has a tether home?
		if comp.owner.reserved_redock_entity or comp.owner.docked_garage then
			return data.components.c_turret:on_update(comp, cause)
		end
		return comp:SetStateSleep(5)
	end,
})

----- solar cell -----
local c_solar_cell = Comp:RegisterComponent("c_solar_cell", {
	attachment_size = "Small", race = "robot", index = 1012, name = "Solar Cell",
	texture = "Main/textures/icons/components/Component_SolarPanel_01_S.png",
	desc = "Photovoltaic cell that supplies <hl>50</> power to your grid during daylight, with increased output throughout summer",
	visual = "v_solarpanel_01_s",
	production_recipe = CreateProductionRecipe({ crystal = 10, circuit_board = 2 }, { c_assembler = 80 }),
	activation = "Always",
	adjust_extra_power = true,
	registers = { { read_only = true, tip = "Power Production" } },
	-- internal variables
	solar_power_generated = 10,
	solar_power_summer = 5,
})

function c_solar_cell:on_update(comp, cause)
	local sun = Map.GetSunlightIntensity() > 0.0
	local blightpower = Map.GetBlightnessDelta(comp, -1) >= 0 or Map.GetSave().dust_storm
	local summer_power = sun and math.abs(Map.GetYearSeason()-0.5) < 0.25 and self.solar_power_summer or 0

	comp.extra_power = summer_power + ((sun or blightpower) and self.solar_power_generated or 0)
	comp:SetRegister(1, { id = "v_power_production", num = (comp.extra_power+(self.power or 0)) * TICKS_PER_SECOND })

	-- Periodically rotate component towards sun
	if (Map.GetTick() % 48) < 12 or (cause & CC_ACTIVATED == CC_ACTIVATED) then
		if not comp.owner.powered_down then
			local sundir_x, sundir_y = Map.GetSunlightDirection()
			local loc = comp.owner.location
			comp:RotateComponent(math.floor(loc.x+(sundir_x*1000)), math.floor(loc.y+(sundir_y*1000)))
		end
	end

	return comp:SetStateSleep(12)
end

----- solar panel -----
c_solar_cell:RegisterComponent("c_solar_panel", {
	attachment_size = "Medium", race = "robot", index = 1012, name = "Solar Panel",
	texture = "Main/textures/icons/components/Component_SolarPanel_01_M.png",
	desc = "Solar Panel that generates <hl>300</> power throughout the day and <hl>100</> during the night, with increased output during summer",
	visual = "v_solarpanel_01_m",
	production_recipe = CreateProductionRecipe({ c_solar_cell = 1, icchip = 1, refined_crystal = 5, hdframe = 5 }, { c_advanced_assembler = 30 }),

	-- internal variables
	solar_power_generated = 40,
	solar_power_summer = 30,
	power = 20,
})

----- wind_turbine -----
local c_wind_turbine = Comp:RegisterComponent("c_wind_turbine", {
	attachment_size = "Medium", race = "robot", index = 1011, name = "Wind Turbine",
	texture = "Main/textures/icons/components/Component_WindTurbine_01_M.png",
	desc = "Constant <hl>50</> power generation per second, <hl>100</> when located on the plateau",
	visual = "v_wind_turbine_m",
	production_recipe = CreateProductionRecipe({ circuit_board = 3, energized_plate = 6, wire = 5 }, { c_assembler = 100 }),
	activation = "Always",
	adjust_extra_power = true,
	max_power = 10,
	speed = 2,
	registers = {{ read_only = true}},
})

c_wind_turbine:RegisterComponent("c_wind_turbine_l", {
	attachment_size = "Large", race = "robot", index = 1011, name = "Large Wind Turbine",
	texture = "Main/textures/icons/components/Component_WindTurbine_01_M.png",
	desc = "Constant <hl>200</> power generation per second, <hl>400</> when located on the plateau",
	visual = "v_wind_turbine_l",
	production_recipe = CreateProductionRecipe({ c_wind_turbine = 1, circuit_board = 3, hdframe = 2, wire = 10 }, { c_assembler = 100 }),
	activation = "Always",
	adjust_extra_power = true,
	max_power = 40,
	speed = 1,
})

function c_wind_turbine:on_update(comp)
	if comp.owner.powered_down then return end
	-- more power when on plateau
	local max_power = self.max_power or 10
	local onplateau = Map.GetPlateauDelta(comp, -1) >= -0.1
	if onplateau then
		max_power =  max_power * 2 -- plateau gains
	end
	comp.animation_speed = self.speed * (onplateau and 2 or 1)
	local ds = Map.GetSave().dust_storm
	if ds then
		max_power = 0
		comp.animation_speed = 0
	end
	-- TODO: wind goes up and down based on world events
	comp.extra_power = max_power
	comp:SetRegister(1, { id = "v_power_production", num = (comp.extra_power+(self.power or 0)) * TICKS_PER_SECOND })

	return comp:SetStateSleep(7)
end

----- power cell
local c_power_cell = Comp:RegisterComponent("c_power_cell", {
	attachment_size = "Internal", race = "robot", index = 1011, name = "Power Cell",
	texture = "Main/textures/icons/components/powercell.png",
	desc = "Transmits <hl>500</> power per second over a small area",
	visual = "v_generic_i",
	power = 100,
	production_recipe = CreateProductionRecipe({ refined_crystal = 20, fused_electrodes = 10, optic_cable = 10, icchip = 10 }, { c_advanced_assembler = 100, }),
	transfer_radius = 10,
	registers = { { read_only = true, tip = "Power Production" } },
	get_ui = true,
})

function c_power_cell:on_add(comp)
	comp:SetRegister(1, { id = "v_power_production", num = (self.power or 0)* TICKS_PER_SECOND })
end

----- integrated cell -----
c_power_cell:RegisterComponent("c_integrated_cell", {
	attachment_size = "Hidden", race = "robot", index = 1011, name = "Integrated Cell",
	desc = "Power system built directly into structure",
	texture = "Main/textures/icons/hidden/integrated_cell.png",
	power = 40,
	transfer_radius = 8,
	production_recipe = false,
})

----- integrated power cell -----
c_power_cell:RegisterComponent("c_integrated_power_cell", {
	attachment_size = "Hidden", race = "robot", index = 1012, name = "Integrated Power Cell",
	desc = "Power system built directly into structure",
	texture = "Main/textures/icons/hidden/integrated_power_cell.png",
	power = 200,
	transfer_radius = 12,
	production_recipe = false,
})

----- power core
c_power_cell:RegisterComponent("c_power_core", {
	attachment_size = "Large", race = "robot", index = 1012, name = "Power Core",
	texture = "Main/textures/icons/components/component_powercore_01_l.png",
	desc = "Produces an exceptional amount of power per second over a small area",
	visual = "v_power_core_01_l",
	power = 400,
	transfer_radius = 15,
	production_recipe = CreateProductionRecipe({ icchip = 5, hdframe = 20, robot_datacube = 20 }, { c_advanced_assembler = 120, }),
	-- production_recipe = CreateProductionRecipe({ micropro = 20, ldframe = 40, hdframe = 20 }, { c_human_factory = 120 }),
	effect = "fx_power_core",
	effect_socket = "fx",
})

----- capacitor -----
local c_capacitor = Comp:RegisterComponent("c_capacitor", {
	attachment_size = "Internal", race = "robot", index = 1013, name = "Capacitor",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/capacitor.png",
	desc = "Stores excess power from your logistics network making it available when needed",
	power_storage = 4000,
	drain_rate = 20,
	charge_rate = 160,
	get_ui = battery_get_ui,
	production_recipe = CreateProductionRecipe({ circuit_board = 1, crystal = 10 }, { c_assembler = 30 }),
})

c_capacitor:RegisterComponent("c_integrated_capacitor", {
	attachment_size = "Hidden", race = "robot", index = 1014, name = "Integrated Capacitor",
	texture = "Main/textures/icons/hidden/integrated_capacitor.png",
	production_recipe = false,
})

Comp:RegisterComponent("c_higrade_capacitor", {
	attachment_size = "Hidden", race = "robot", index = 1015, name = "Hi-Grade Capacitor",
	texture = "Main/textures/icons/hidden/higrade_capacitor.png",
	visual = "v_generic_i",
	desc = "Stores excess power from your logistics network making it available when needed",
	power_storage = 10000,
	drain_rate = 50,
	charge_rate = 400,
	get_ui = battery_get_ui,
	--production_recipe = CreateProductionRecipe({ hdframe = 1, refined_crystal = 5 }, { c_assembler = 30 }),
})

data.update_mapping.c_large_capacitor = "c_medium_capacitor"
Comp:RegisterComponent("c_medium_capacitor", {
	attachment_size = "Medium", race = "robot", index = 1015, name = "Medium Capacitor",
	texture = "Main/textures/icons/components/component_crystalbattery_01_m.png",
	desc = "A medium sized Capacitor with a greater storage amount",
	visual = "v_crystalbattery_01_m",
	production_recipe = CreateProductionRecipe({ c_capacitor =1, energized_plate = 3, circuit_board = 2 }, { c_assembler = 20 }),
	get_ui = battery_get_ui,

	-- battery
	power_storage = 50000,
	drain_rate = 250,
	charge_rate = 2000,
})

----- small battery -----
Comp:RegisterComponent("c_small_battery", {
	attachment_size = "Small", race = "robot", index = 1014, name = "Small Battery",
	texture = "Main/textures/icons/components/component_capacitor_01_s.png",
	desc = "Rechargeable power cell",
	visual = "v_capacitor_01_s",
	power_storage = 30000,
	drain_rate = 30,
	charge_rate = 30,
	production_recipe = CreateProductionRecipe({ crystal = 10, circuit_board = 1 }, { c_assembler = 60 }), --  lithium = 5,
	get_ui = battery_get_ui,
})

----- signal_reader -----
--Unit to read signal from
local c_signal_reader = Comp:RegisterComponent("c_signal_reader", {
	attachment_size = "Internal", race = "robot", index = 1047, name = "Signal Reader",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/signal_reader.png",
	desc = "Allow reading of the signal register from a specific unit or building",
	registers = {
		{ type = "entity", tip = "<header>TARGET ENTITY</>\n\n <bl>Use to Select Entity to 'Read Signal' from</>\n\nDrag to Entity to set", ui_icon = "icon_target2"},
		{ tip = "<header>RECEIVED SIGNAL</>\n\n<bl>The Result returned from the Target's</> <hl>Signal</> register", ui_icon = "icon_signal", read_only = true }
	},
	production_recipe = CreateProductionRecipe({ circuit_board = 1 }, { c_assembler = 5 }),
	activation = "OnFirstRegisterChange",
})

function c_signal_reader:on_update(comp)
	local source_entity = comp:GetRegisterEntity(1)
	comp:SetRegister(2, nil)
	if source_entity then
		if source_entity.exists and not IsDroppedItem(source_entity) then
			comp:LinkRegisterFromRegister(2, 4, source_entity)
		end
	end
end

----- shared_storage -----
Comp:RegisterComponent("c_shared_storage", {
	attachment_size = "Internal", race = "robot", index = 1022, name = "Shared Storage",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/shared_storage.png",
	desc = "Designate locked inventory slots on this unit or building for dumping of excess items",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, }, { c_assembler = 20 }),
	dumping_ground = true,
})

Comp:RegisterComponent("c_internal_storage", {
	attachment_size = "Internal", race = "robot", index = 1021, name = "Internal Storage",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/internal_storage.png",
	desc = "Uses the internal socket as an item slot",
	slots = { storage = 1 },
	production_recipe = CreateProductionRecipe({ reinforced_plate = 5, wire = 5 }, { c_assembler = 20 }),
})

----- basic_cpu -----
local c_behavior = Comp:RegisterComponent("c_behavior", {
	attachment_size = "Internal", race = "robot", index = 1044, name = "Behavior Controller",
	texture = "Main/textures/icons/components/basic_cpu.png",
	desc = "Additional small, low-powered programmable device. Can be added to units and buildings without an integrated behavior controller.",
	visual = "v_generic_i",
	activation = "Manual",
	production_recipe = CreateProductionRecipe({ circuit_board = 1 }, { c_assembler = 40 }),
	get_ui = function(def, comp)
		local newui = UI.New([[
			<Box>
				<HorizontalList child_padding=4>
					<Button width=28 height=28 id=btnstart  on_click={on_click_behavior_start}/>
					<Button width=28 height=28 id=btnmodify on_click={on_click_behavior_modify} tooltip="Modify behavior" icon=icon_behav/>
					<Button width=28 height=28 id=btselect  on_click={on_click_behavior_select} tooltip="Select behavior" icon=icon_menu/>
				</HorizontalList>
			</Box>]], {
			comp = comp,
			update = function(b)
				local state, inst, txt = comp and comp.has_extra_data and comp.extra_data
				local revid, main_id = state and state.revid, state and state.main_id
				local asm, debug = state and ((revid and GetFactionBehaviorAsm(comp, revid)) or (main_id and GetFactionBehaviorAsmById(comp.faction, main_id))), state and state.debug
				if asm then
					inst = asm[state.lastcounter]
					inst = inst and b.comp.is_active and inst[1] and data.instructions[inst[1]]
					inst = inst and inst.name
					txt = inst and L("%d: %s", state.lastcounter, inst) or asm.code.name and L("<hl>%S</>", asm.code.name)
				end
				txt = txt or b.comp.def.name
				--b.insttxt.text = txt
				--b.insttxt.halign = inst and 'left' or 'center'
				--b.insttxt.tooltip = #txt > 20 and txt or nil

				local is_paused = not comp.is_active or (debug ~= nil and debug ~= 'BREAKPOINT')
				b.btnstart.hidden = not asm
				b.btnstart.tooltip = is_paused and "Start behavior" or "Stop behavior"
				b.btnstart.icon = is_paused and "icon_play" or "icon_stop"
				b.btnstart.debug = is_paused and "CONTINUE" or "STOP"
				b.btnmodify.hidden = not asm
				b.active_behavior = asm and state.main_id

				-- When the main code changes, force refresh the component box and its registers because names and hidden states might have changed
				local main_revid = asm and asm.code.id == main_id and revid
				if main_revid and b.last_main_revid ~= main_revid then
					if b.last_main_revid then b.compbox.hash = nil end
					b.last_main_revid = main_revid
				end
			end,

			on_click_behavior_start = function(b, btnstart)
				Action.SendForEntity("Behavior", comp.owner, { comp = comp, debug = btnstart.debug })
			end,

			on_click_behavior_modify = function(b, btnmodify)
				local state = comp and comp.has_extra_data and comp.extra_data
				local asm = state and state.main_id and GetFactionBehaviorAsmById(comp.faction, state.main_id)
				OpenMainWindow("Program", { comp = comp, code = Tool.Copy(asm.code), is_remote = true, library = Game.GetLocalPlayerFaction().extra_data.library, })
			end,

			on_click_behavior_select = function(b, btnselect)
				local owner, is_integrated = comp.owner, (comp.id == "c_integrated_behavior")
				local popup = UILibrarySelect(btnselect, 'C',
					function(item) Action.SendForEntity("Behavior", owner, { comp = comp, set_id = item.id, debug = "STOP" }) end, -- select
					function() Action.SendForEntity("Behavior", owner, is_integrated and { remove_integrated = true } or { comp = comp, debug = "CLEAR" }) end, -- clear
					function(folder) Action.SendForEntity("Behavior", owner, { folder = folder, comp = comp, create = true }) end, -- create
					b.active_behavior, comp.id)
				if popup and is_integrated then popup.clearbtn.text = "Remove Integrated Behavior" end
			end,
		})
		return nil, newui
	end,
})

----- integrated cpu -----
c_behavior:RegisterComponent("c_integrated_behavior", {
	attachment_size = "Hidden", race = "robot", index = 1041, name = "Integrated Behavior Controller",
	texture = "Main/textures/icons/hidden/behavior_controller.png",
	desc = "Integrated programmable device",
	production_recipe = false,
})

data.update_mapping.c_behavior_transfer = "c_behavior"
data.update_mapping.c_behavior_notify = "c_behavior"
data.update_mapping.c_behavior_requestor = "c_behavior"
data.update_mapping.c_behavior_countremain = "c_behavior"

local GetFactionBehaviorAsm, table_unpack = GetFactionBehaviorAsm, table.unpack

function c_behavior:on_add(comp)
	if comp.has_extra_data then
		local ed = comp.extra_data
		-- Set up the referenced behavior (but don't run it automatically)
		if not ed.revid and ed.main_id then SetBehavior(comp, ed.main_id, "STOP") end
	end
end

function c_behavior:on_remove(comp)
	-- Keep the referenced behavior, erase runtime state
	SetBehavior(comp, nil)
end

function c_behavior:on_faction_change(comp, old_faction)
	-- Must stop and wipe behavior because main_id and revid isn't owned by this entities faction anymore
	SetBehavior(comp, nil)
	comp.extra_data = nil
end

local function c_behavior_on_end(comp, state, asm)
	local blocks, returns = state.blocks, state.returns
	local block = blocks and blocks[#blocks]
	if block and (not block[4] or block[4] == (returns and #returns or 0)) then
		local next_counter, loop_inst_idx, it = block[1], block[2], block[3]
		state.counter = next_counter
		local inst = asm[loop_inst_idx]
		local op = data.instructions[inst and inst[1]]
		local op_next = op and op.next
		if not op_next and next_counter == 1 and #blocks == 1 then -- end of event block
			blocks[1] = nil
			return c_behavior_on_end(comp, state, asm)
		elseif op_next(comp, state, it, table_unpack(inst, 3)) then
			op.last(comp, state, it, table_unpack(inst, 3))
			blocks[#blocks] = nil
		end
		return asm
	elseif returns and #returns > 0 then
		local mem, counter, mem_count = state.mem
		state.revid, state.stk, counter, mem_count = table_unpack(table.remove(returns))
		state.counter, state.lastcounter = counter, counter
		table.move(mem, #mem+1, #mem+#mem-mem_count, mem_count+1) -- trim to mem_count
		--print("[c_behavior_on_end] Returned to return #" .. #returns  .. " - STK: " .. tostring(state.stk):gsub("\n", " "):gsub(" %p%d+%p: ", "") .. " - Mem: " .. tostring(state.mem):gsub("\n", " "):gsub(" %p%d+%p: ", ""))
		return GetFactionBehaviorAsm(comp, state.revid)
	elseif #asm > 0 then
		local clearmem = asm.lvs
		if clearmem then
			local mem = state.mem
			for _,i in ipairs(clearmem) do mem[i]:Clear() end
		end
		if not asm.code.keeparrays then
			state.arrays = nil
		end
		state.counter = 1
		return asm
	end
end

function c_behavior:on_update(comp, cause)
	local state, data_instructions = comp.extra_data, data.instructions
	--print("[" .. comp.id .. ":on_update] debug:", debug, " - cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - has_power: " .. tostring(comp.owner.has_power) .. " - counter: " .. tostring(state.counter) .. " - lastcounter: " .. tostring(state.lastcounter))
	local debug, revid, step, step_limit, breakpoints = state.debug, state.revid, 1

	if debug then
		if     debug == "STEP" then state.debug = "PAUSE" -- run one instruction then pause
		elseif debug == 'BREAKPOINT' then breakpoints = state.breakpoints -- check breakpoints
		elseif debug == 'BPHIT' then comp.faction:RunUI("OnBehaviorBreakpoint", comp) return
		else return end -- PAUSE, wait for user to continue
		step = 1000000001 -- force limit 1 step
	end

	local asm = GetFactionBehaviorAsm(comp, revid)
	if not asm then goto restart_changed_code end

	while true do
		local lastcounter = state.counter
		local inst = asm[lastcounter]

		while not inst do
			asm = c_behavior_on_end(comp, state, asm)
			if not asm then goto restart_changed_code end
			revid = state.revid -- refresh on return of call
			lastcounter = state.counter
			inst = asm[lastcounter]
		end

		--print(comp.id .. " - STEP " .. step .. " INSTRUCTION #" .. lastcounter .. ": OP: " .. inst[1] .. " - Next: " .. tostring(inst[2]) .. " - Args: " .. tostring({select(3, table.unpack(inst))}):gsub("\n", " "):gsub(" %p%d+%p: ", ""))
		state.counter = inst[2]
		state.lastcounter = lastcounter
		local res = data_instructions[inst[1]].func(comp, state, cause, table_unpack(inst, 3))

		-- a op func returning true means the instruction has put the behavior component into waiting state and we get activated again once that finishes
		if res == true then break end

		step_limit = (state.limit or 1)
		if step >= step_limit then
			if debug then
				if state.revid ~= revid then asm = GetFactionBehaviorAsm(comp, state.revid) end -- refresh asm if last op was a call
				if breakpoints and (state.counter ~= state.lastcounter or state.revid ~= revid) then
					while asm and not asm[state.counter] do asm = c_behavior_on_end(comp, state, asm) end
					if asm and breakpoints[(asm.code.id << 16) | state.counter] then
						if step_limit == 1 then comp:SetStateSleep(1) else comp.faction:RunUI("OnBehaviorBreakpoint", comp) end
						break -- pause execution next tick (or now if behavior runs unlocked)
					end
				end
				if not breakpoints then
					break -- pause execution
				elseif step - 1000000000 < step_limit then
					goto debug_continue_unlocked -- no breakpoint hit, continue unlocked behavior normally
				end
			end

			if step_limit == 1 then
				comp:SetStateSleep(1)
				break
			else
				InstError(comp, state, "Unlocked behavior exceeded instruction limit for a single step")
				return
			end

			::debug_continue_unlocked::
		end

		local new_revid = state.revid
		if new_revid ~= revid then
			revid = new_revid
			asm = GetFactionBehaviorAsm(comp, revid)
			if not asm then goto restart_changed_code end
		end
		step = step + 1
	end

	if not debug then return end

	do
		while asm and not asm[state.counter] do asm = c_behavior_on_end(comp, state, asm) end
		if breakpoints and (state.counter ~= state.lastcounter or state.revid ~= revid) then
			if asm and breakpoints[(asm.code.id << 16) | state.counter] then state.debug = 'BPHIT' end
		end
		return
	end

	::restart_changed_code::
	if not SetBehavior(comp, state.main_id, "RESTART") then return end
	if debug then comp.extra_data.debug = debug end
	return self:on_update(comp, cause)
end

local c_autobase = c_behavior:RegisterComponent("c_autobase", {
	attachment_size = "Internal", race = "alien", index = 5061, name = "AI Behavior Controller",
	desc = "Programmable automatic base management",
	key = "autobase",
	power = 0,
	texture = "Main/textures/icons/components/ai_controller.png",
	production_recipe = CreateProductionRecipe({ c_behavior = 1, crystal = 10 }, { c_alien_factory_robots = 80, c_assembler = 200 }),
})

data.update_mapping.c_autobase_ai = "c_autobase"

--- crane ---
local c_crane = Comp:RegisterComponent("c_crane", {
	attachment_size = "Medium", race = "robot", index = 1022, name = "Item Transporter",
	texture = "Main/textures/icons/components/Component_Transporter_01_M.png",
	visual = "v_transporter_01_m",
	power = -5,
	desc = "Enables automatic transfer of inventory directly between units and buildings in range",
	production_recipe = CreateProductionRecipe({ crystal_powder = 5, icchip = 2, cable = 5 }, { c_advanced_assembler = 20 }),
	range = 3,
})

function c_crane:on_add(comp)
	comp.owner.crane_range = math.max(comp.owner.crane_range, self.range)
end

function c_crane:on_remove(comp)
	local new_range = 0
	for i=1,999 do
		local crane_comp = comp.owner:FindComponent("c_crane", true, i)
		if not crane_comp then break end
		if crane_comp ~= comp then new_range = math.max(new_range, crane_comp.def.range) end
	end
	comp.owner.crane_range = new_range
end

--- portable crane ---
c_crane:RegisterComponent("c_portablecrane", {
	attachment_size = "Internal", race = "robot", index = 1023, name = "Portable Transporter",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/portable_transporter.png",
	power = 0,
	desc = "Enables automatic transfer of inventory directly between adjacent units and buildings",
	production_recipe = CreateProductionRecipe({ circuit_board = 5, wire = 1 }, { c_assembler = 50 }),
	range = 1,
})

--- long range portable crane ---
local c_internal_crane1 = c_crane:RegisterComponent("c_internal_crane1", {
	attachment_size = "Hidden", race = "robot", index = 1043, name = "Item Transporter",
	desc = "Integrated Transporter with short range",
	texture = "Main/textures/icons/hidden/internal_transporter.png",
	power = 0,
	production_recipe = false,
	visual = "v_generic_i",
	range = 1,
	get_ui = true,
})

c_internal_crane1:RegisterComponent("c_internal_crane2", {
	attachment_size = "Hidden", race = "robot", index = 1044, name = "Item Transporter",
	desc = "Integrated Transporter with decent range",
	range = 2,
})

c_crane:RegisterComponent("c_internal_transporter", {
	attachment_size = "Hidden", race = "human", index = 3021, name = "Item Transporter",
	texture = "Main/textures/icons/hidden/internal_transporter.png",
	desc = "Integrated Transporter with decent range",
	production_recipe = false,
	range = 3,
	get_ui = true,
})

c_crane:RegisterComponent("c_alien_crane2", {
	attachment_size = "Hidden", race = "alien", index = 5001, name = "Phase Transporter",
	texture = "Main/textures/icons/components/alien_integrated_component.png",
	desc = "Alien Transporter with a Range of 3",
	production_recipe = false,
	power = 0,
	range = 3,
	get_ui = true,
})

c_crane:RegisterComponent("c_alien_crane3", {
	attachment_size = "Hidden", race = "alien", index = 5009, name = "Phase Transporter",
	texture = "Main/textures/icons/components/alien_integrated_component.png",
	desc = "Alien Transporter with a Range of 4",
	production_recipe = false,
	power = 0,
	range = 4,
	get_ui = true,
})

-- portable_radar (most basic radar, inherited by more advanced variants)
-- tip = "<header>Received Signal</>\n\n<bl>The Result returned from the three filters</> <hl>Signal Parameter</>",
-- { tip = "<header>Received Signal</>\n\n<bl>The Result returned from the Target's</> <hl>Signal Parameter</>", ui_icon = "icon_signal", read_only = true }
local c_portable_radar = Comp:RegisterComponent("c_portable_radar", {
	attachment_size = "Internal", race = "robot", index = 1041, name = "Portable Radar",
	texture = "Main/textures/icons/components/portable_radar.png",
	desc = "Short range detection of resources and other objects in the world. All conditions must be met.",
	visual = "v_generic_i",
	power = -1,
	production_recipe = CreateProductionRecipe({ metalbar = 5, circuit_board = 1 }, { c_assembler = 30 }),
	activation = "OnComponentRegisterChange",
	registers = {
		{ type = "radar", tip = "<header>Search Filter [1]</>\n\n<bl>Search Filter [1] is Required to return a Radar Result</>\n\n\nClick to choose from <hl>Inventory Items</> or <hl>Information</> icons", ui_apply = "Set Filter", ui_icon = "icon_1_g" },
		{ type = "radar", tip = "<header>Search Filter [2]</>\n\n<bl>Search Filter [2] Refines the Radar Result</>\n\n\nClick to choose from <hl>Inventory Items</> or <hl>Information</> icons", ui_apply = "Set Filter", ui_icon = "icon_2_g" },
		{ type = "radar", tip = "<header>Search Filter [3]</>\n\n<bl>Search Filter [3] Refines the Radar Result</>\n\n\nClick to choose from <hl>Inventory Items</> or <hl>Information</> icons", ui_apply = "Set Filter", ui_icon = "icon_3_g" },
		{ read_only = true, ui_icon = "icon_radar", warning = '<Key action=\"ExecuteAction\" style=\"hl\"/> to move camera to Result', tip = "<header>RADAR RESULT</>\n\n<bl>SINGLE Result returned from combination (additive) of 1 - 3 filters</>\n\n\n<hl>Mouse Over</> To highlight 'Result' in the world\n\n<Key action=\"ExecuteAction\" style=\"hl\"/> to move camera to 'Result' in the world" },
	},

	range = 30, -- scan distance
	radar_show_range = 6,
	scan_delay = 2,
	on_add = def_comp_activate,
})

function c_portable_radar:get_ui(comp, noregs)
	if noregs then return end
	local regs_def = self.registers
	local num_regs = #regs_def
	local reg_index = comp.register_index - 1
	local newui = UI.New([[
		<HorizontalList>
			<VerticalList valign=bottom id=filters/>
			<Reg ent={en} empty_tooltip={resulttooltip} abs_index={absi} valign=bottom comp={c} reg_index={ri} id=result on_drag_start={link_on_drag_start} on_drag_cancel={link_on_drag_cancel} on_drag_complete={link_on_drag_complete} on_drop={link_on_drop}/>
		</HorizontalList>
	]], {
		en = comp.owner,
		absi = reg_index + num_regs,
		c = comp,
		ri = num_regs,
		resulttooltip = regs_def[num_regs].tip,
	})

	local reg_ret = {}
	for i=1,num_regs-1 do
		reg_ret[i] = newui.filters:Add("<RegNoNum on_drag_start={link_on_drag_start} on_drag_cancel={link_on_drag_cancel} on_drag_complete={link_on_drag_complete} on_drop={link_on_drop}/>", { ent = comp.owner, width=24, height=24, comp = comp, reg_index = i, abs_index = reg_index + i, empty_tooltip = regs_def[i].tip })
	end
	reg_ret[num_regs] = newui.result

	return newui, nil, reg_ret
end

c_portable_radar:RegisterComponent("c_scout_radar", {
	attachment_size = "Internal", race = "robot", index = 1042, name = "Scout Radar",
	desc = "Short range detection of resources and other objects in the world",
	texture = "Main/textures/icons/components/scout_radar.png",
	production_recipe = CreateProductionRecipe({ circuit_board = 1 }, { c_assembler = 30 }),
	registers = {
		{ type = "radar", tip = "<header>Search Filter</>\n\n<bl>Search Filter is Required to return a Radar Result</>\n\n\nClick to choose from <hl>Inventory Items</> or <hl>Information</> icons", ui_apply = "Set Filter", ui_icon = "icon_minus" },
		{ read_only = true, ui_icon = "icon_radar", warning = '<Key action=\"ExecuteAction\" style=\"hl\"/> to move camera to Result', tip = "<header>RADAR RESULT</>\n\n<bl>Result returned from filter</>\n\n\n<hl>Mouse Over</> To highlight 'Result' in the world\n\n<Key action=\"ExecuteAction\" style=\"hl\"/> to move camera to 'Result' in the world" },
	},

	range = 30, -- scan distance
	radar_show_range = 6,
	scan_delay = 10,
	radar_show_area = true,
})

local c_small_radar = c_portable_radar:RegisterComponent("c_small_radar", {
	attachment_size = "Small", race = "robot", index = 1041, name = "Small Radar",
	texture = "Main/textures/icons/components/Component_Radar_01_S.png",
	desc = "Scans for entities beyond visual range",
	visual = "v_radar_s",
	power = -1,
	production_recipe = CreateProductionRecipe({ c_portable_radar = 1, hdframe = 2, optic_cable = 5 }, { c_advanced_assembler = 30 }),

	-- lua variable
	range = 40, -- scan distance
	radar_show_range = 6,

	scan_delay = 10,
	radar_show_area = true,
})

function Delay.RadarHideArea(arg)
	arg.faction:HideArea(arg.x, arg.y, arg.range)
end

function c_portable_radar:on_update(comp, cause)
	--print("radar:", comp:CauseToString(cause),  tostring(comp:GetRegister(1)))
	local numregs = comp.register_count
	local reg1 = numregs > 0 and comp:GetRegister(1) or nil
	local reg1id = reg1 and reg1.id or nil
	local reg1num = reg1 and reg1.num

	if reg1id == nil then
		if numregs > 0 then
			--print("[portable_radar] Set to " .. (reg1.entity and "entity" or "nil"))
			comp:SetRegister(numregs, { entity = reg1.entity, num = nil }) -- passthrough for entity
		end
		if self.radar_show_area then
			if cause & CC_FINISH_WORK == CC_FINISH_WORK then
				--print("[portable_radar] Start Work")
				return comp:SetStateSleep(10)
			end

			local loc = comp.owner.location
			local len
			if comp.owner.visibility_range > self.range then
				len = math.random(self.range, comp.owner.visibility_range)
			else
				len = math.random(comp.owner.visibility_range, self.range)
			end

			local ang_deg = Map.GetTick()%360
			local loc_x = loc.x + math.floor(math.cos(math.rad(ang_deg))*(len))
			local loc_y = loc.y + math.floor(math.sin(math.rad(ang_deg))*(len))
			local self_range, comp_owner = self.radar_show_range+1, comp.owner

			local comp_faction = comp.faction
			Map.Defer(function()
				Map.SpawnChunks(loc_x-self_range-1, loc_y-self_range-1, (self_range*2)+2, (self_range*2)+2, comp_owner)
				comp_faction:RevealArea(loc_x, loc_y, self_range)
			end)

			Map.Delay("RadarHideArea", self.scan_delay+10, { faction = comp_faction, x = loc_x, y = loc_y, range = self_range })
			return comp:SetStateStartWork(self.scan_delay)
		end
		return
	end

	--------- mothership scanning using long range radar
	if reg1id == "v_mothership" and (comp.id == "c_radar" or comp.id == "c_radar_array") then
		if comp.faction.extra_data.mothership == nil then
			Map.Defer(function()
				-- spawn it the first time you scan for it from a satellite
				comp.faction.extra_data.mothership = Map.CreateEntity(comp.faction, "f_mothership")
				comp.faction.extra_data.mothership:AddComponent("c_mothership_repair")
				comp.faction.extra_data.mothership:AddComponent("c_mothership_eject")
				--local fix = comp.faction.extra_data.mothership:AddComponent("c_explorable_fix", "hidden")
				--fix.extra_data.explorable_fix = "anomaly_particle"
			end)
		elseif comp.faction.extra_data.mothership:FindComponent("c_mothership_eject") == nil then
			Map.Defer(function()
				comp.faction.extra_data.mothership:AddComponent("c_mothership_eject")
			end)
		end
		comp:SetRegister(numregs, { entity = comp.faction.extra_data.mothership, })
		return comp:SetStateSleep(self.scan_delay)
	end
	---------

	if cause & CC_FINISH_WORK ~= CC_FINISH_WORK then
		--print("[portable_radar] Start Work")
		if comp.is_working then
			return comp:SetStateContinueWork()
		end
		return comp:SetStateStartWork(TICKS_PER_SECOND)
	end

	-- fill out output
	local filters = { reg1id, reg1num, nil, nil, nil, nil }
	if filters[1] and numregs > 2 then
		filters[3] = comp:GetRegisterId(2)
		filters[4] = filters[3] and comp:GetRegisterNum(2)
		if filters[3] and numregs > 3 then
			filters[5] = comp:GetRegisterId(3)
			filters[6] = filters[5] and comp:GetRegisterNum(3)
		end
	end

	--print("[portable_radar] filters: " .. tostring(filters):gsub("\n", ""))
	local owner = comp.owner
	local loc = owner.location
	local range = self.range
	local num = REG_INFINITE
	Map.SpawnChunks(loc.x-(range//2), loc.y-(range//2), range, range, owner)
	local entity_filter, override_range = PrepareFilterEntity(filters)
	local closest_entity = Map.FindClosestEntity(owner, (override_range and math.min(math.max(override_range, 0), range) or range),
		function(e)
			local a,b = FilterEntity(owner, e, filters)
			if a and b then num = b end
			return a
		end, entity_filter)

	-- check result
	if closest_entity then
		--print("[portable_radar] Setting closest matching entity " .. tostring(closest_entity))
		--comp:SetRegisterEntity(numregs, closest_entity)
		comp:SetRegister(numregs, { entity = closest_entity, num = num })

		local faction = owner.faction
		if not faction:IsVisible(closest_entity) then
			--print("[portable_radar] [" .. Map.GetTick() .. "] reveal location " .. tostring(loc):gsub("\n", "") .. " for 23 ticks")
			local show_range, ent_x, ent_y = self.radar_show_range, closest_entity:GetLocationXY()
			faction:RevealArea(ent_x, ent_y, show_range)
			Map.Delay("RadarHideArea", 23, { faction = faction, x = ent_x, y = ent_y, range = show_range })
		end
	else
		--print("[portable_radar] No matching entity found")
		comp:SetRegister(numregs, nil)
	end
	return comp:SetStateSleep(self.scan_delay)
end

----- radio storage, transmitter and receiver
Comp:RegisterComponent("c_radio_storage", { })

function RadioDisconnect(comp, is_sender)
	local radio_storage, idx = comp.faction.extra_data.radio_storage
	if not radio_storage then return end

	local signal_idx = comp.register_count
	if is_sender then
		idx = radio_storage:GetRegisterLinkTarget(signal_idx, comp)
	else
		idx = comp:GetRegisterLinkSource(signal_idx, radio_storage)
	end
	if not idx then return end

	local radio_storage_ed = radio_storage.extra_data
	local conns = radio_storage_ed.conns
	conns[idx] = (conns[idx] > 1 and (conns[idx] - 1) or nil)
	if is_sender then
		radio_storage:UnlinkRegisterFromRegister(idx, signal_idx, comp)
	else
		comp:UnlinkRegisterFromRegister(signal_idx, idx, radio_storage)
	end
end

function RadioConnect(comp, is_sender, band)
	RadioDisconnect(comp, is_sender)
	if band.is_empty then return end

	local radio_storage = comp.faction.extra_data.radio_storage
	if not radio_storage then
		-- create the radio storage then call this function again
		Map.Defer(function()
			if not comp.exists then return end -- component already gone
			if not comp.faction.extra_data.radio_storage then -- can happen if deferred multiple times
				local radio_storage = Map.CreateEntity(comp.faction, "f_empty"):AddComponent("c_radio_storage", "hidden")
				radio_storage.extra_data = { bands = {}, conns = {} }
				comp.faction.extra_data.radio_storage = radio_storage
			end
			RadioConnect(comp, is_sender, band)
		end)
		return true
	end

	local radio_storage_ed = radio_storage.extra_data
	local bands, conns, idx, free_idx = radio_storage_ed.bands, radio_storage_ed.conns
	for i=1,#bands do
		if band == bands[i] then
			idx = i
			break
		elseif not conns[i] and not free_idx then
			free_idx = i
		end
	end
	if not idx then
		idx = free_idx or (#bands + 1)
		if not free_idx then radio_storage.register_count = idx end
		bands[idx] = band
	end
	conns[idx] = (conns[idx] or 0) + 1

	local signal_idx = comp.register_count
	if is_sender then
		-- Transmitter: Link our value register to the radio storage register
		radio_storage:LinkRegisterFromRegister(idx, signal_idx, comp)
	else
		-- Receiver: Link the radio storage register to our value register
		comp:LinkRegisterFromRegister(signal_idx, idx, radio_storage)
	end
	return true
end

local c_radio_transmitter = Comp:RegisterComponent("c_radio_transmitter", {
	attachment_size = "Internal", race = "robot", index = 1048, name = "Radio Transmitter",
	texture = "Main/textures/icons/components/radio_transmitter.png",
	desc = "Allows remote transmission of logic to Receiver Components",
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, silicon = 5 }, { c_assembler = 10 }),
	activation = "OnFirstRegisterChange",
	adjust_extra_power = true,
	registers = { { tip = "Band", any_value = true }, { tip = "Value", any_value = true } },
})

function c_radio_transmitter:on_remove(comp)
	RadioDisconnect(comp, true)
end

function c_radio_transmitter:on_update(comp)
	-- Conect and activate power usage
	comp.extra_power = RadioConnect(comp, true, comp:GetRegister(1)) and -5 or 0
end

----- radio receiver
local c_radio_receiver = Comp:RegisterComponent("c_radio_receiver", {
	attachment_size = "Internal", race = "robot", index = 1049, name = "Radio Receiver",
	texture = "Main/textures/icons/components/radio_receiver.png",
	desc = "Allows remote reception and modification of logic",
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, silicon = 5 }, { c_assembler = 10 }),
	activation = "OnFirstRegisterChange",
	registers = { { tip = "Band", any_value = true }, { tip = "Received Signal", read_only = true } },
})

function c_radio_receiver:on_remove(comp)
	RadioDisconnect(comp, false)
end

function c_radio_receiver:on_update(comp)
	RadioConnect(comp, false, comp:GetRegister(1))
end

local c_crystal_power = Comp:RegisterComponent("c_crystal_power", {
	attachment_size = "Small", race = "robot", index = 1011, name = "Crystal Power", --"Crystal Power Extractor",
	texture = "Main/textures/icons/components/component_crystalpower_01_s.png",
	desc = "Charges itself by consuming crystals, storing energy and supplies <hl>150</> power to your logistics network every second, but only when required",
	visual = "v_crystalpower_01_s",
	production_recipe = CreateProductionRecipe({ metalbar = 5, crystal = 10 }, { c_assembler = 20 }),
	activation = "OnPowerStoredEmpty",
	get_ui = battery_get_ui,
	consume_item = "crystal",

	-- battery
	power_storage = 6000,
	drain_rate = 30,
})

function c_crystal_power:on_update(comp, cause)
	-- on_update is also called when work has finished, only refill stored power when actually on low power
	if comp.stored_power > 0.5 then
		if comp.has_prepared_process then
			-- keep 1 ordered/reserved for once power runs out
			comp:PrepareConsumeProcess({[self.consume_item] = 1}, 1)
			return comp:SetStateSleep()
		end
		return
	end

	-- If still working from before but gotten activated again just continue work
	if cause & CC_FINISH_WORK == 0 and comp.is_working then
		return comp:SetStateContinueWork()
	end

	-- reserve or order 2 crystal so 1 can be consumed immediately and 1 is kept reserved
	local can_make = comp:PrepareConsumeProcess({[self.consume_item] = 1}, 2)
	if not can_make then
		return comp:SetStateSleep()
	end

	comp:FulfillProcess()

	-- refill stored power
	if self.requires_blight and Map.GetBlightnessDelta(comp.owner, -1) < 0 then
		comp.stored_power = self.power_storage // 3
	else
		comp.stored_power = self.power_storage
	end

	-- Start a 20 tick work until we can consume another crystal
	return comp:SetStateStartWork(20)
end

c_crystal_power:RegisterComponent("c_blightcrystal_power", {
	attachment_size = "Medium", race = "blight", index = 2012, name = "Blight Crystal Power",
	texture = "Main/textures/icons/components/component_blightcrystalpower_01_m.png",
	desc = "Charges itself by consuming blight crystals, storing energy and supplies power to your logistics network every second, but only when required",
	visual = "v_blightcrystalpower_01_m",
	production_recipe = CreateProductionRecipe({ c_crystal_power = 1, blightbar = 10, blight_crystal = 10 }, { c_advanced_assembler = 50 }),
	activation = "OnPowerStoredEmpty",
	get_ui = battery_get_ui,
	consume_item = "blight_crystal",

	-- battery
	power_storage = 20000,
	drain_rate = 100,
})

Comp:RegisterComponent("c_fission_reactor", {
	attachment_size = "Hidden", race = "human", index = 3011, name = "Mini Fission Plant",
	texture = "Main/textures/icons/components/mini_fission_plant.png",
	power = 20,
	on_add = c_power_cell.on_add,
	on_update = c_power_cell.on_update,
	registers = c_power_cell.registers,
	activation = c_power_cell.activiation,
	get_ui = true,
})

c_crystal_power:RegisterComponent("c_micro_reactor", {
	attachment_size = "Internal", race = "human", index = 3011, name = "Micro Reactor",
	texture = "Main/textures/icons/components/micro_reactor.png",
	desc = "Expends fuel rods to produce power for the structures",
	visual = "v_generic_i",
	consume_item = "fuel_rod",
	power_storage = 150000,
	drain_rate = 2000,
	production_recipe = CreateProductionRecipe({ smallreactor = 20, steelblock = 10 }, { c_human_factory = 100 }),
})

c_crystal_power:RegisterComponent("c_fusion_reactor", {
	attachment_size = "Hidden", race = "human", index = 3012, name = "Fusion Reactor",
	texture = "Main/textures/icons/components/fusion_reactor.png",
	desc = "Expends enriched fuel rods to produce power",
	production_recipe = false,
	consume_item = "enriched_fuel_rod",
	power = 10,
	power_storage = 600000,
	drain_rate = 10000,
	transfer_radius = 20,
})

c_crystal_power:RegisterComponent("c_fusion_generator", {
	attachment_size = "Hidden", race = "robot", index = 1013, name = "Fusion Reactor",
	texture = "Main/textures/icons/frame/building_3x3_fg.png",
	desc = "Expends Anomaly Particles to produce power",
	slots = { anomaly = 8 },
	production_recipe = false,
	consume_item = "anomaly_particle",
	power = 10000,
	power_storage = 1000000,
	drain_rate = 100000,
	transfer_radius = 25,
})

c_crystal_power:RegisterComponent("c_alien_powergenerator", {
	attachment_size = "Hidden", race = "alien", index = 5003, name = "Alien Power Nova",
	texture = "Main/textures/icons/components/alien_powercore.png",
	desc = "Central source of power and control for the Alien",
	production_recipe = false,
	consume_item = "plasma_crystal",
	power_storage = 100000,
	drain_rate = 500,
	transfer_radius = 12,
	effect = "fx_blight_extract",
	on_add = function(_, comp) comp.owner.has_blight_shield = true end,
})

local c_alien_powercore = Comp:RegisterComponent("c_alien_powercore", {
	name = "Alien Core",
	race = "alien",
	texture = "Main/textures/icons/components/alien_powercore.png",
	desc = "Central source of power and control for the Alien",
	activation = "Always",
	adjust_extra_power = true,
	consume_item = "blight_plasma",
	visual = "v_generic_i",
	hunger_delay = 100,
	power_storage = 5000,
	charge_rate = 200,
	drain_rate = 200,
	on_add = function(self, comp)
		comp.owner.has_blight_shield = true
		comp.stored_power = self.power_storage
	end,
})

function c_alien_powercore:on_update(comp, cause)
	local owner = comp.owner
	local fullhealth = owner.health == owner.max_health
	local has_power = owner.powered_down or (owner.has_power and comp.stored_power > 1500) or owner.faction.is_world_faction
	local in_blight = Map.GetBlightnessDelta(comp, -1) >= 0 or Map.GetSave().dust_storm
	local blight_power = in_blight and 30 or -5

	if fullhealth and has_power then
		-- full health and in blight or during dust storm, just sleep
		comp.extra_power = blight_power
		comp:CancelProcess()
		return comp:SetStateSleep(self.hunger_delay)
	end

	-- reserve or order 2 items so 1 can be consumed immediately and 1 is kept reserved
	local can_make = comp:PrepareConsumeProcess({[self.consume_item] = 1}, 2)
	if not can_make then -- doesn't have any
		if has_power or in_blight then
			-- in power grid or in blight and no plasma
			comp.extra_power = -20 + blight_power
			return comp:SetStateSleep(self.hunger_delay)
		end

		-- no power grid or not enough power, take damage, low power state
		if owner.health <= 100 then
			comp.extra_power = blight_power + -20
		else
			comp.extra_power = blight_power
			owner:RemoveHealth(100)
		end
		return comp:SetStateSleep(self.hunger_delay)
	end

	-- does have some
	comp.extra_power = 50 + blight_power
	owner:AddHealth(50)
	comp:FulfillProcess()
	return comp:SetStateSleep(self.hunger_delay)
end

c_power_cell:RegisterComponent("c_small_fusion_reactor", {
	attachment_size = "Hidden", race = "human", index = 3013, name = "Small Fusion Reactor",
	texture = "Main/textures/icons/components/fusion_reactor_small.png",
	desc = "Produces continuous power over a large area",
	production_recipe = false,
	power = 200,
	transfer_radius = 20,
})

----- power_transmitter -----
local c_power_transmitter = Comp:RegisterComponent("c_power_transmitter", {
	attachment_size = "Medium", race = "robot", index = 1014, name = "Power Transmitter",
	desc = "Transfers power to a single unit or building outside the logistics network",
	texture = "Main/textures/icons/components/Component_PowerTransmitter_01_M.png",
	visual = "v_power_transmitter_m",
	bandwidth = 20,
	production_recipe = CreateProductionRecipe({ circuit_board = 2, hdframe = 2, wire = 10 }, { c_assembler = 25 }),
	activation = "OnFirstRegisterChange",
	action_tooltip = action_tooltip_set_target,
	registers = { { type = "entity", tip = "Target", click_action = true, filter = 'entity' } },
	get_ui = true,
})

function c_power_transmitter:on_update(comp)
	comp.power_relay_target = comp:GetRegister(1).entity
end

function c_power_transmitter:action_click(comp, widget)
	CursorChooseEntity("Select target to receive power", function (target)
		if not comp.exists then return end -- got destroyed
		if target and target.faction == comp.faction then
			local arg = { comp = comp , reg = { entity = target } }
			Action.SendForEntity("SetRegister", comp.owner, arg)
		else
			Notification.Error("Cannot transmit power to other factions")
			Action.SendForEntity("SetRegister", comp.owner, { comp = comp })
		end
	end,
	nil, comp.register_index)
end

----- signpost -----
local c_signpost = Comp:RegisterComponent("c_signpost",{
	attachment_size = "Internal", race = "robot", index = 1046, name = "Sign Post",
	texture = "Main/textures/icons/components/signpost.png",
	desc = "Show text instead of the visual register",
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ circuit_board = 1 }, { c_assembler = 5 }),
	action_tooltip = "Set Sign",
})

function c_signpost:action_click(comp)
	InputBox("Enter the text for the sign post", "Sign Post",
		function (t) Action.SendForEntity("SignPostSetText", comp.owner, { comp = comp, sign = t }) end,
		comp.owner.extra_data.signpost or "")
end

function c_signpost:on_add(comp)
	if comp.has_extra_data then
		comp.owner:SetRegisterId(FRAMEREG_VISUAL, "c_signpost")
		comp.owner.extra_data.signpost = comp.extra_data.signpost
	end
end

function c_signpost:on_remove(comp)
	comp.owner.extra_data.signpost = nil
	if comp.owner:GetRegisterId(FRAMEREG_VISUAL) == "c_signpost" then
		comp.owner:SetRegister(FRAMEREG_VISUAL, nil)
	end
end

function c_signpost:get_ui(comp)
	return UI.New('<Box padding=4><Button width=54 height=54 icon=icon_keyboard on_click={click}/></Box>', {
		tooltip = "Set Sign",
		click = function() c_signpost:action_click(comp) end,
	}), nil
end

function EntityAction.SignPostSetText(entity, arg)
	if not arg.sign or arg.sign == "" then
		if arg.comp then arg.comp.extra_data.signpost = nil end
		entity.extra_data.signpost = nil
		if entity:GetRegisterId(FRAMEREG_VISUAL) == "c_signpost" then entity:SetRegister(FRAMEREG_VISUAL, nil) end
	else
		if arg.comp then arg.comp.extra_data.signpost = arg.sign end
		entity.extra_data.signpost = arg.sign
		entity:SetRegisterId(FRAMEREG_VISUAL, "c_signpost")
	end
end

------------------------------
------Added for Basefx
------------------------------
Comp:RegisterComponent("c_monolith_effect", {
	name = "storage structure",
	effect = "fx_alien_monolith",
	effect_socket = "basefx",
})
Comp:RegisterComponent("c_pylon_effect", {
	name = "socketbuilding",
	effect = "fx_alien_pylon",
	effect_socket = "basefx",
})
Comp:RegisterComponent("c_socketbuilding_effect", {
	name = "socketbuilding",
	effect = "fx_alien_socket_building",
	effect_socket = "basefx",
})
Comp:RegisterComponent("c_nexus_teleporter_effect", {
	name = "warp structure",
	effect = "fx_alien_teleporter",
	effect_socket = "basefx",
})
Comp:RegisterComponent("c_alien_storage_effect", {
	name = "storage structure",
	effect = "fx_alien_storage",
	effect_socket = "basefx",
})
Comp:RegisterComponent("c_sensortower_effect", {
	name = "storage structure",
	effect = "fx_alien_sensor_tower",
	effect_socket = "basefx",
})
Comp:RegisterComponent("c_turret_building_effect", {
	name = "storage structure",
	effect = "fx_alien_defense_turret",
	effect_socket = "basefx",
})

------Basefx

----------------------------------------------------------------------------------------------------------------
--------------------- Non player components

local c_particle_birds = Comp:RegisterComponent("c_particle_birds", {
	effect = "fx_birds",
	type = "Effect",
})

c_particle_birds:RegisterComponent("c_particle_leaves", {
	effect = "fx_leaves",
})

----- glitch
Comp:RegisterComponent("c_glitch", {
	texture = "Main/textures/icons/components/fx.png",
	effect = "fx_glitch",
})

--local c_glitch2 = Comp:RegisterComponent("c_glitch2", {
--	name = "Glitch 2",
--	texture = "Main/textures/icons/components/fx.png",
--	effect = "fx_glitch2",
--})


----- bug consume
local c_trilobyte_consume = Comp:RegisterComponent("c_trilobyte_consume", {
	name = "Trilobyte Consume",
	texture = "Main/textures/icons/components/int.png",
	desc = "consumes components into silica and infected circuit boards",
	power = 0,
	activation = "OnAnyItemSlotChange",
})

local function get_trilobyte_consume_rewards(id, num, tbl)
	local def = data.all[id]
	local recipe = def and def.production_recipe
	local recipe_ingredients = recipe and recipe.ingredients
	if recipe_ingredients and (recipe and recipe.amount or 1) == 1 then -- drop multi-amount recipes as is
		for sub_id, sub_num in pairs(recipe_ingredients) do
			tbl = get_trilobyte_consume_rewards(sub_id, (sub_num * num), tbl)
		end
	elseif def and num > 0 then
		if not tbl then tbl = {} end
		tbl[id] = (tbl[id] or 0) + num
	end
	for k,v in pairs(tbl or {}) do
		local item_def = data.items[k]
		if item_def and (item_def.slot_type == "anomaly" or item_def.slot_type == "gas") then return end
	end
	return tbl
end

function c_trilobyte_consume:on_update(comp, cause)
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - has_power: " .. tostring(comp.owner.has_power))
	if comp.is_working then return comp:SetStateContinueWork() end

	local owner = comp.owner
	if (cause & CC_FINISH_WORK) == CC_FINISH_WORK then
		local rewards, drop, more = comp.extra_data.rewards or {}

		for k,v in SortedPairs(rewards) do
			if v > 0 then
				if drop then more = true break end
				drop = math.min(v, 20)
				-- Drop rewards then maybe move a bit
				Map.DropItemAt(owner, k, drop)
				local x, y = owner:GetLocationXY()
				owner:MoveTo(x + math.random(-1, 1), y + math.random(-1, 1))
				rewards[k] = v - drop
				if v > drop then more = true break end
			end
		end

		-- consume item after dropping the first reward (if killed while dropping items, remaining rewards are lost)
		if comp.has_prepared_process then
			comp:FulfillProcess()
		end

		-- if new items are added during processing, drop them as is without disassembling
		for _,v in ipairs(owner.slots) do
			if v.unreserved_stack > 0 then
				owner:DropItem(v)
			end
		end

		if more then -- have more to drop, continue in 5 ticks
			return comp:SetStateStartWork(5)
		else -- done dropping, clear extra data then check for new items in 5 ticks
			FactionCount("trilobyte_consume", comp.extra_data.consume or 1, comp.faction)
			comp.extra_data = nil
			return comp:SetStateSleep(5)
		end
	end

	-- check for any items to drop
	for _,v in ipairs(owner.slots) do
		local have = v.unreserved_stack
		local id = have > 0 and (v.has_extra_data and v.extra_data.resimulated or v.id)
		local rewards = id and get_trilobyte_consume_rewards(id, have)
		local id_def = data.all[id]

		-- special scrap rewards for human items
		if comp.owner.id == "f_trilobyte1a" and rewards and id_def and id_def.race == "human" then
			local all_rewards = 0
			for k,v in pairs(rewards) do
				all_rewards = all_rewards + v
			end
			if all_rewards > 5 then
				all_rewards = all_rewards // 5
				rewards = { unstable_matter = all_rewards }
			end
		end
		if rewards and comp:PrepareConsumeProcess({ [id] = have }, v) then
			comp.extra_data.consume = have
			comp.extra_data.rewards = rewards
			return comp:SetStateStartWork(10)
		else
			if v.unreserved_stack > 0 then
				owner:DropItem(v)
			end
		end
	end
end


----- trilobyte_attack
local c_trilobyte_attack = c_turret:RegisterComponent("c_trilobyte_attack", {
	attachment_size = "Hidden", race = "virus", index = 4001, name = "Trilobyte Attack",
	texture = "Main/textures/icons/bugs/trilobite.png",
	desc = "Imbued with acidic venom that damages metal",
	production_recipe = false,
	power = 0,
	trigger_radius = 8, -- detect range

	-- internal variable
	attack_radius = 1, -- attack range

	shoot_fx = "fx_bug_attack",
	damage = 4, -- damage per shot -- 2
	damage_type = "physical_damage",
	duration = 3, -- charge duration
	shoot_while_moving = false,
	leash_distance = 30, -- stop follow if bug moved forther away from goto than this
})

function c_trilobyte_attack:on_update(comp, cause)
	if not comp.faction.is_player_controlled then
		local failed_move = cause & CC_FINISH_MOVE ~= 0 and comp.owner.state_path_blocked
		if failed_move or comp.owner.state_custom_1 then -- also for infected
			local ed = comp.extra_data
			if not ed.failed_move then
				ed.failed_move = Map.GetTick() + 900
			else
				if ed.failed_move < Map.GetTick() then
					-- make a house
					comp:SetRegister(1) -- stop attacking
					local homeless = comp.owner:FindComponent("c_bug_homeless")
					if not homeless then
						ed.failed_move = nil
						Map.Defer(function()
							if not comp.exists then return end
							local homeless = (comp.owner.health > 200) and comp.owner:AddComponent("c_bug_homeless")
							if homeless then
								homeless:Activate()
							else
								comp.owner:Destroy() -- cant add component, just destroy
							end
						end)
					else
						homeless:Activate()
					end
					return
				end
			end
		end
	end
	c_turret.on_update(self, comp, cause)
end

c_trilobyte_attack:RegisterComponent("c_trilobyte_attack_t2", {
	attachment_size = "Hidden", race = "virus", index = 4002, name = "Greelobyte",
	damage = 7,
	damage_type = "energy_damage",
	--duration = 5,
	extra_effect = bitlock_effect,
	extra_effect_name = "BitLock",
	shield_charge = 0,
	extra_stat = {
		{ "icon_tiny_damage", "5s", "BitLock Duration" },
	},
})

c_trilobyte_attack:RegisterComponent("c_trilobyte_attack_t3", {
	attachment_size = "Hidden", race = "virus", index = 4003, name = "Trilopew",
	texture = "Main/textures/icons/bugs/trilopew.png",
	damage = 12,
	damage_type = "plasma_damage",
	extra_effect = electromag_effect,
	extra_effect_name = "Disruptor",
	disruptor = 45,
	shield_charge = 0,
	extra_stat = {
		{ "icon_tiny_damage", 45, "Shield Damage" },
	},
	-- duration = 5,
})

c_trilobyte_attack:RegisterComponent("c_worm_beam", { -- c_alien_plasma_beam
	attachment_size = "Hidden", race = "virus", index = 4999, name = "Worm Attack",
	texture = "Main/textures/icons/bugs/worm.png",
	desc = false,
	power = 0, -- --100
	visual = "v_alien_plasma_beam_m",

	trigger_radius = 6,
	attack_radius = 6,

	-- internal variable
	damage = 400,
	damage_type = "physical_damage",
	duration = 20,
	shoot_speed = 5,
	shoot_fx = "fx_worm_attack", --"fx_plasma_beam",
	--shoot_delay  = 5,
	beam_range = 5,
})

c_trilobyte_attack:RegisterComponent("c_lucanops_beam", { -- c_alien_plasma_beam
	attachment_size = "Hidden", race = "virus", index = 4008, name = "Lucanops Attack",
	texture = "Main/textures/icons/bugs/lucanops.png",
	desc = "Powerful condensed plasma beam",
	power = 0, -- --100
	--visual = "v_alien_plasma_beam_m",

	trigger_radius = 3,
	attack_radius = 2,

	-- internal variable
	damage = 150,
	damage_type = "physical_damage",
	duration = 10,
	shoot_speed = 2,
	shoot_fx = "fx_bug_attack_snd",
	--shoot_delay  = 5,
	beam_range = 3,
})

-- LARVA
c_turret:RegisterComponent("c_larva_attack1", {
	attachment_size = "Hidden", race = "virus", index = 4014, name = "Larva",
	texture = "Main/textures/icons/bugs/larva1.png",
	power = 0,
	visual = "v_melee_pulse_s",
	production_recipe = false,
	trigger_radius = 8,
	attack_radius = 1,
	shoot_fx = false,

	-- internal variable
	damage = 300, -- damage per shot
	damage_type = "energy_damage",
	duration = 20,
	shoot_speed = 5,
	shoot_while_moving = false,
	pulse = 3,
	explode = 4,
	ignore_damagers = true,
})

c_turret:RegisterComponent("c_larva_attack2", {
	attachment_size = "Hidden", race = "virus", index = 4015, name = "Larva",
	texture = "Main/textures/icons/bugs/larva2.png",
	power = 0,
	visual = "v_melee_pulse_s",
	production_recipe = false,
	trigger_radius = 8,
	attack_radius = 1,
	shoot_fx = false,

	-- internal variable
	damage = 150, -- damage per shot
	damage_type = "energy_damage",
	duration = 20,
	shoot_speed = 5,
	shoot_while_moving = false,
	pulse = 1,
	explode = 4,
	ignore_damagers = true,
})

function c_trilobyte_attack:on_add(comp)
	comp.owner.has_blight_shield = true
end

function c_trilobyte_attack:on_take_damage(comp, amount, damager)
	if comp.owner.state_path_blocked then
		comp:SetRegisterEntity(1)
		return
	end
	-- if we dont have a target, set the target to whomever shot us first
	if not self.ignore_damagers and damager and damager.exists then
		local reg1 = comp:GetRegisterEntity(1)
		if not reg1 then
			comp:SetRegisterEntity(1, damager)
		elseif reg1 ~=damager and reg1:GetRangeSquaredTo(comp.owner) > damager:GetRangeSquaredTo(comp.owner) then
			comp:SetRegisterEntity(1, damager)
		end
	end
end

-- SCALE WORM
c_trilobyte_attack:RegisterComponent("c_trilobyte_attack1", {
	attachment_size = "Hidden", race = "virus", index = 4005, name = "Scale Worm",
	texture = "Main/textures/icons/bugs/gastarias.png",
	damage = 16, -- 12
	duration = 7,
	attack_radius = 1,
	shoot_while_moving = true,
	leash_distance = 36, -- stop follow if bug moved forther away from goto than this
})

-- MALIKA and MOTHIKA
c_trilobyte_attack:RegisterComponent("c_trilobyte_attack2", {
	attachment_size = "Hidden", race = "virus", index = 4007, name = "Malika",
	texture = "Main/textures/icons/bugs/scaramar.png",
	damage = 35, -- 30 -- 15
	duration = 7,
	attack_radius = 4,
	shoot_while_moving = false,
	leash_distance = 31,
	ignore_damagers = true
})

Comp:RegisterComponent("c_egg_spawner1", {
	trigger_radius = 15,
	trigger_channels = "all",
	on_trigger = function(self, comp, other_entity)
		if comp.faction:GetTrust(other_entity) == "ENEMY" then
			Map.Defer(function()
				if not comp.exists then return end

				-- spawn an egg
				local egg = Map.CreateEntity(comp.faction, "f_luanops_egg")
				egg:Place(comp.owner)
				local t = comp.owner:FindComponent("c_turret", true)
				if t then
					local reg = t:GetRegister(1)
					egg.extra_data.target = { id = reg.id, coord = reg.coord }
				end
				comp:Destroy()
			end)
		end
	end,
})

-- GIGAKAIJU
c_trilobyte_attack:RegisterComponent("c_trilobyte_attack4", {
	attachment_size = "Hidden", race = "virus", index = 4017, name = "Gigakaiju",
	texture = "Main/textures/icons/bugs/gigakaiju.png",
	damage = 450,
	duration = 14,
	attack_radius = 7,
	shoot_speed = 3,
	trigger_radius = 20,
	affects_flying = true,
	blast = 3,
	leash_distance = 27,
	shoot_fx = "fx_roar", --roar
	blast_fx = "fx_EMP", -- blast
	healamt = 50,
	extra_effect = heal_effect,
	extra_effect_name = "Heal",
	extra_stat = {
		{ "icon_tiny_damage", "50", "Heal" },
	},
})

-- TETRAPUSS
c_turret:RegisterComponent("c_tetrapuss_attack1", {
	attachment_size = "Hidden", race = "virus", index = 4016, name = "Glob Spit",
	texture = "Main/textures/icons/bugs/tetrapuss.png",
	desc = "Spits globs",
	power = 0,
	trigger_radius = 10,
	attack_radius = 10,

	minimum_range = 2,
	production_recipe = false,

	-- internal variable
	damage = 100, -- damage per shot -- 120
	damage_type = "energy_damage",
	duration = 20, -- charge duration -- 10
	------ CANNON -------
	shoot_speed = 10,
	blast = 2,
	shoot_fx = "fx_photon_bomb",
})

c_trilobyte_attack:RegisterComponent("c_tripodonte1", {
	attachment_size = "Hidden", race = "virus", index = 4013, name = "Malacostra",
	--texture = "Main/textures/icons/bugs/gastarid.png",
	damage = 180,
	duration = 16,
	shoot_speed = 4,
	leash_distance = 34,
	shoot_fx = "fx_bug_attack_snd",
	ignore_damagers = true,
	extra_effect = electromag_effect,
	extra_effect_name = "Disruptor",
	disruptor = 60,
	shield_charge = 0,
	extra_stat = {
		{ "icon_tiny_damage", 60, "Shield Damage" },
	},
	rage_speedup_comp = "c_tripodonte_speedup",
	on_trigger = function(self, comp, other_entity)
		if comp.faction:GetTrust(other_entity) == "ENEMY" then
			comp:Activate()
			if comp.owner:CountComponents(self.rage_speedup_comp) == 0 then
				comp.owner:AddComponent(self.rage_speedup_comp)
			end
		end
	end,
	on_take_damage = function(self, comp, damage, damager, damage_type)
		Map.Defer(function() if comp.exists then self:on_trigger(comp, damager) end end)
	end,
})

-- RAVAGER
c_trilobyte_attack:RegisterComponent("c_trilobyte_attack3", {
	attachment_size = "Hidden", race = "virus", index = 4010, name = "Bite", -- "Ravager Bite"
	texture = "Main/textures/icons/bugs/gastarid.png",
	damage = 49, -- 42
	duration = 7,
	shoot_speed = 1, -- 4
	leash_distance = 32,
	shoot_while_moving = true,
	ignore_damagers = true,
	shoot_fx = "fx_bug_attack_snd",
})

c_trilobyte_attack:RegisterComponent("c_wasp_attack1", {
	attachment_size = "Hidden", race = "virus", index = 4009, name = "Wasp Dive Attack",
	texture = "Main/textures/icons/bugs/toxicWasp.png",
	damage = 50, -- damage per shot
	duration = 10, -- charge duration
	shoot_speed = 4,
	leash_distance = 40,
	ignore_damagers = false,
	shoot_fx = "fx_bug_attack_snd",
})

-- speed up components (increase speed on rage)
c_modulespeed:RegisterComponent("c_tripodonte_speedup", {
	attachment_size = "Hidden", race = "virus", index = 4999,
	--name = "Rage", desc = "Increase speed on rage", -- unnecessary as UI never shows this component
	production_recipe = false,
	power = 0,
	boost = 200,
	remove_range = 5,
	activation = "Always",
	on_update = function(self, comp, cause)
		local attack_comp = comp.owner:FindComponent("c_turret", true)
		local ent = attack_comp:GetRegisterEntity(1) or attack_comp:GetRegisterEntity(2)
		local coord = not ent and attack_comp:GetRegisterCoord(1)
		if not attack_comp.is_working and not ent and (not coord or comp.owner:IsInRangeOf(coord, self.remove_range)) then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end
		return comp:SetStateSleep(100)
	end,
})

Comp:RegisterComponent("c_small_storage", {
	attachment_size = "Small", race = "robot", index = 1021, name = "Small Storage",
	texture = "Main/textures/icons/components/Component_Storage_01_S.png",
	desc = "Expands storage of Frame by <hl>4 slots</>",
	visual = "v_storage_01_s",
	slots = { storage = 4, },
	production_recipe = CreateProductionRecipe({ hdframe = 1, circuit_board = 1 }, { c_assembler = 20 }),
	--dumping_ground = true,
})

----- shield generator
local c_shield_generator = Comp:RegisterComponent("c_shield_generator", {
	attachment_size = "Internal", race = "robot", index = 1031, name = "Portable Shield Generator",
	texture = "Main/textures/icons/components/portable_shieldgenerator_purple.png",
	desc = "Energy shield - Uses power to charge a shield that mitigates up to <hl>60</> damage",
	visual = "v_generic_i",
	--visual = "v_shieldgenerator_01_m",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, energized_plate = 3, silicon = 2 }, { c_assembler = 20 }),
	--power_storage = 40, -- max damage reduction is 20
	--charge_rate = 1, -- charge 2 per tick
	shield_max = 60,
	shield_charge = -1,
	shield_effect = "fx_shield2",
	shield_type = "shield",
	activation = "Manual",
	adjust_extra_power = true,
	on_add = def_comp_activate,
	on_placed = def_comp_activate,
})

function c_shield_generator:ChargeShield(comp, charge)
	local ed = comp.extra_data
	local oldstored = ed.stored
	ed.stored = math.min(oldstored + charge, self.shield_max)
	return charge - (ed.stored - oldstored)
end

function c_shield_generator:ApplyShieldDamage(comp, damage, damage_type)
	local new_damage = self:on_take_damage(comp, damage, nil, damage_type)
	local reduced = damage - new_damage
	if reduced > 0 then
		AddDamagedEnemy(comp.owner, reduced, "electromag_damage")
	end
	return new_damage
end

function c_shield_generator:on_update(comp, cause)
	local owner, ed = comp.owner, comp.extra_data
	if ed.stored == nil then ed.stored = self.shield_max end

	local recharged = (comp.power_details.power * owner.efficiency) // 100
	ed.stored = ed.stored - recharged
	if ed.stored > self.shield_max then ed.stored = self.shield_max end
	if ed.stored > 0 then
		if not comp.has_active_effects and self.shield_effect and owner.is_placed then
			comp:PlayEffect(self.shield_effect, "_entity")
		end
	end

	-- recharge
	if ed.stored < self.shield_max then
		local tick = Map.GetTick()
		if not ed.next_charge or tick >= ed.next_charge then
			comp.extra_power = self.shield_charge
			comp:SetStateSleep(1)
		else
			comp.extra_power = 0
			return comp:SetStateSleep(ed.next_charge - tick)
		end
	else
		comp.extra_power = 0
	end
end

function c_shield_generator:on_take_damage(comp, damage, damager, damage_type)
	local ed = comp.extra_data
	ed.next_charge = Map.GetTick() + (3 * TICKS_PER_SECOND)
	local amount = math.ceil(CalcDamageReduction(damage, self.shield_type, damage_type))
	if ed.stored == nil then
		ed.stored = self.shield_max
	end
	local reduce_amount = ed.stored
	if reduce_amount == 0 then
		if comp.has_active_effects then comp:Activate() end
		return amount
	end
	if reduce_amount > amount then
		reduce_amount = amount
	end
	--print("Taking ", amount, " amount of damage - modifying it to ", amount - reduce_amount, " (have power stored: ", comp.stored_power, " - will use: ", (reduce_amount * self.damage_to_power_ratio), ")")
	ed.stored = math.max(ed.stored - reduce_amount, 0)
	comp:Activate()
	if ed.stored == 0 then
		if comp.has_active_effects then
			comp:StopEffects()
		end
	end

	return amount - reduce_amount
end

function c_shield_generator:get_ui(comp)
	return UI.New("<Box padding=4><Progress valign=center width=54 height=54 progress={progress} bg=progress_mask orientation=vertical color=ui_light bgcolor=ui_dark/></Box>", {
		--	return UI.New("<HorizontalList child_padding=4 padding=4><Image width=16 height=16 image={compicon}/><Progress valign=center progress={progress} width=220 bg=progress_mask height=12 color=powerbar bgcolor=ui_dark/></HorizontalList>", {
		--compicon = comp.def.texture,
		update = function(w)
			local ed = comp.extra_data
			local comp_def = comp.def
			w.progress = (ed.stored or comp_def.shield_max) / comp_def.shield_max
			if w.tt then
				w.tt.text = L((comp.extra_power ~= 0 and "%s: %.0f/%.0f (%+.0f)" or "%s: %.0f/%.0f"), "Shield", ed.stored or comp_def.shield_max, comp_def.shield_max, comp.extra_power*TICKS_PER_SECOND)
			end
		end,
		tooltip = function(w)
			if not w:IsValid() then return end
			w.tt = UI.New("<Box bg=popup_box_bg padding=12><Text/></Box>", { destruct = function() w.tt = nil end })[1]
			w:update()
			return w.tt.parent
		end,
	})
end

local c_shieldworm_shield = c_shield_generator:RegisterComponent("c_shieldworm_shield", {
	attachment_size = "Hidden", race = "virus", index = 4006, name = "ShieldWorm Shell",
	texture = "Main/textures/icons/hidden/trilobyte_shield.png",
	desc = "",
	visual = "v_generic_i",
	shield_max = 250, -- damage reduction
	shield_charge = 10, -- charge 2 per tick
	production_recipe = false,
	shield_effect = false,
	activation = "Always",
})

function c_shieldworm_shield:on_update(comp, cause)
	local ed = comp.extra_data
	local tick = Map.GetTick()
	if not ed.next_charge or tick >= ed.next_charge then
		local ed = comp.extra_data
		ed.stored = math.min((ed.stored or 0) + (TICKS_PER_SECOND * self.shield_charge), self.shield_max)
		return comp:SetStateSleep(TICKS_PER_SECOND) -- once a second
	else
		comp:SetStateSleep(ed.next_charge - tick)
	end
end

c_shieldworm_shield:RegisterComponent("c_trilobyte_shield", {
	attachment_size = "Hidden", race = "virus", index = 4004, name = "Trilobyte Shell",
	desc = "",
	visual = "v_generic_i",
	shield_max = 50, -- damage reduction
	shield_charge = 5, -- charge 2 per tick
})

--------------- c_ai_gitch_buildling
data.update_mapping.c_ai_gitch_buildling = "c_disappear_empty"
local c_disappear_empty = Comp:RegisterComponent("c_disappear_empty", {
	texture = "Main/textures/icons/components/int.png",
	activation = "OnAnyItemSlotChange",
})

function c_disappear_empty:on_update(comp, cause)
	for i,v in ipairs(comp.owner.slots) do
		if v.id then
			return -- still contains an item
		end
	end
	comp.owner:PlayEffect("fx_digital")
	comp.owner:Destroy(false)
end

--------------- c_ai_bot_behavior

local c_ai_bot_behavior = Comp:RegisterComponent("c_ai_bot_behavior", {
	name = "AI Bot",
	texture = "Main/textures/icons/components/int.png",
	trigger_radius = 2,
	trigger_channels = "bot",
	on_trigger = function(_, comp, other_entity)
		if not comp.extra_data.last_trigger_time and other_entity.faction.is_player_controlled then
			comp.extra_data.last_trigger = other_entity
			comp.extra_data.last_trigger_time = Map.GetTick()
			comp.extra_data.state = 2
		end
	end,
	activation = "Always",
})

function c_ai_bot_behavior:on_add(comp)
	comp.extra_data.started = Map.GetTick()
end

function c_ai_bot_behavior:on_update(comp, cause)
	local state = comp.extra_data.state or 1

	if state == 1 then
		if comp.extra_data.started + 250 > Map.GetTick() then
			return comp:SetStateSleep(30)
		end
		comp.extra_data.state = 3
		return comp:SetStateSleep(30)
		-- wait for a period of time
		--[[
		-- move towards main target
		local target_entity = comp.extra_data.target
		if target_entity and target_entity.exists then
			if comp:RequestStateMove(target_entity, 3) then return end
		end
		comp.extra_data.state = 3
		return comp:SetStateSleep(30) -- finished moving
		--]]
	elseif state == 2 then -- follow last trigger for a bit
		local lastt = comp.extra_data.last_trigger_time + 150
		if lastt < Map.GetTick() then
			comp.extra_data.state = 1
			return comp:SetStateSleep(TICKS_PER_SECOND)-- finished following
		end

		local last = comp.extra_data.last_trigger
		if last and last.exists then
			comp:RequestStateMove(last, 3)
		end
		return
	elseif state == 3 then -- disappear
		comp.owner:PlayEffect("fx_digital")
		comp.owner:Destroy(false)
	end
end

Comp:RegisterComponent("c_phase_plant", {
	name = "Phase Plant",
	texture = "Main/textures/icons/components/int.png",
	trigger_radius = 2,
	trigger_channels = "bot",
	effect = "fx_glitch",
	on_trigger = function (_, comp, other_entity)
		if comp.faction == other_entity.faction then return end -- don't phase own units
		local eloc = other_entity.location
		local loc = comp.owner.location
		other_entity:PlayEffect("fx_digital")
		other_entity:Place(loc.x + 3*(eloc.x- loc.x), loc.y + 3*(eloc.y-loc.y))
		local peaceful = Map.GetSettings().peaceful or 2
		if peaceful < 1 then return end
		other_entity:RemoveHealth(1, "full")

		-- if its not player controlled faction then make it disappear after a few times
		if not comp.faction.is_player_controlled then
			local times = comp.extra_data.times or 0
			times = times + 1
			local owner = comp.owner
			if times > 5 then
				Map.Defer(function() if owner.exists then owner:Destroy() end end)
			else
				comp.extra_data.times = times
			end
		end
	end,
})

Comp:RegisterComponent("c_damage_plant", {
	name = "Damage Plant",
	texture = "Main/textures/icons/items/leaves_power.png",
	trigger_radius = 2,
	trigger_channels = "bot",
	on_trigger = function (_, comp, other_entity)
		if other_entity.faction == comp.faction then return end
		--print("Lua on_trigger : c_damage_plant - ", other_entity, other_entity.faction)
		if other_entity:FindComponent("c_damage_plant_internal") then return end
		local new_comp = other_entity:AddComponent("c_damage_plant_internal")

		if other_entity.faction.id == "bugs" then
			if other_entity.id == "f_trilobyte1" or other_entity.id == "f_gastarias1" then
				-- return home
				local home = other_entity:GetRegister(FRAMEREG_GOTO)
				if home and home.entity then
					other_entity:MoveTo(home.entity)
				end
			end
		end

		-- disappear after several uses
		local c = comp.extra_data
		c.count = (c.count or 0) + 1
		if c.count > 10 then
			if math.random(4) == 1 then
				Map.Defer(function() if comp.exists then comp.owner:Destroy() end end)
			end
		end
	end,
})

Comp:RegisterComponent("c_damage_plant_internal", {
	name = "Damage Planet Internal",
	texture = "Main/textures/icons/items/leaves_power.png",
	activation = "Always",
	power = -1,
	effect = "fx_glitch_flower",
	on_update = function(self, comp, cause)
		-- set increased power usage
		comp.extra_power = -20
		-- check if you're still in range
		local plant = Map.FindClosestEntity(comp.owner, 2, function(e) if e.id == "f_damage_plant" then return true end end, FF_OPERATING)
		if not plant then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
		end
	end,
})

Comp:RegisterComponent("c_bug_homeless", {
	name = "Homeless Bug",
	texture = "Main/textures/icons/components/terraformer.png",
	activation = "Manual",
	on_add = def_comp_activate,
	on_update = function(_, comp, cause)
		-- remove from powered down or player bugs
		local owner = comp.owner
		if owner.powered_down or owner.faction.is_player_controlled then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end

		-- dont do anything if it has a home
		local currHome = owner:GetRegisterEntity(FRAMEREG_GOTO)
		if currHome then
			if currHome.faction.id == "bugs" then
				--print("has home, destroy")
				if owner.is_docked then
					Map.Defer(function()
						if comp.exists then comp:Destroy() end
					end)
					return
				elseif owner.state_path_blocked or not owner.is_moving then
					owner:SetRegister(FRAMEREG_GOTO)
					return comp:SetStateSleep(1)
				else
					return comp:SetStateSleep(20)
				end
			end
			return comp:SetStateSleep(300)
		end
		-- if its attacking then wait only a little bit
		local attack_comp = owner:FindComponent("c_turret", true)
		if attack_comp and not owner.state_path_blocked then
			local ent = attack_comp:GetRegisterEntity(1) or attack_comp:GetRegisterEntity(2)
			local coord = attack_comp:GetRegisterCoord(1)
			if attack_comp.is_working or ent or (coord and not owner:IsInRangeOf(coord, 5)) then
				--print(Map.GetTick(), comp, comp.exists, " - still attacking, sleep some more")
				return comp:SetStateSleep(300)
			end
		end

		-- offset wait
		if comp.extra_data.extrawait then
			comp.extra_data.extrawait = nil
			--print(Map.GetTick(), comp, comp.exists, " - requested to wait ")
			return comp:SetStateSleep(1)
		end

		-- find a hive with an empty slot
		local newhome = Map.FindClosestEntity(owner, 10, function(enemy)
			if enemy.id == "f_bug_hive" or enemy.id == "f_bug_hive_large" then
				-- check for empty slots
				for _,v in ipairs(enemy.slots) do
					if v.type == "bughole" and v.entity == nil then
						return true
					end
				end
			end
		end, FF_OPERATING)

		if newhome then
			-- tether to it
			-- print(Map.GetTick(), comp, comp.exists, " - Found new home")
			owner:SetRegisterEntity(FRAMEREG_GOTO, newhome)
			return comp:SetStateSleep(20)
		end

		-- tell everyone else to wait
		local foundlarge = false
		Map.FindClosestEntity(owner, 4, function(enemy)
			local c = enemy:FindComponent("c_bug_homeless")
			if c then c.extra_data.extrawait = true end
			if enemy.id == "f_bug_hive_large" then foundlarge = true end
		end, FF_OPERATING)

		Map.Defer(function()
			if not comp.exists then return end
			-- make a home
			--print(Map.GetTick(), comp, comp.owner, "make a home")
			local newhome = Map.CreateEntity(GetBugsFaction(), (comp.extra_data.large and not foundlarge) and "f_bug_hive_large" or "f_bug_hive")
			newhome:Place(comp.owner.location)
			local spawner = newhome:FindComponent("c_bug_spawn", true)
			if spawner then
				local ed = spawner.extra_data
				ed.bugs = {}
				ed.spawned = Map.GetTick()
				ed.lvl = 0
				ed.extra_spawned = 0
			end

			comp.owner:SetRegisterEntity(FRAMEREG_GOTO, newhome)

			-- destroying
			comp:Destroy()
		end)
	end,
	on_take_damage = function(self, comp, amount, damager)
		local turret = comp.owner:FindComponent("c_turret", true)
		if turret then
			local reg = turret:GetRegister(1)
			if not reg.entity and damager then
				turret:SetRegister(1, { coord = damager.location })
			end
		end
		Map.FindClosestEntity(comp.owner, 5, function(friend)
			if friend.faction == comp.faction then
				turret = friend:FindComponent("c_turret", true)
				if turret then
					local reg = turret:GetRegister(1)
					if not reg.entity and damager then
						turret:SetRegister(1, { coord = damager.location })
					end
				end
			end
		end, FF_OPERATING)
	end
})

function Delay.SpawnFromHive(args)
	--if not args.comp.exists then return end
	local i = args.level
	local loc = args.loc
	local target = args.target
	local bug = CreateBugForBugLevel(i, args.faction)
	if args.force then
		local hl = bug:AddComponent("c_bug_homeless", "hidden")
		hl.extra_data.large = math.random() < 0.1
	elseif args.owner then
		bug:SetRegisterEntity(FRAMEREG_GOTO, args.owner)
	elseif args.auto_destroy then
		bug.extra_data.auto_destroy = true
		Map.Delay("DelayedDestroyEntity", args.auto_destroy + math.random(1,200), { ent = bug, nodrop = true })
	end
	bug.has_blight_shield = true
	bug:Place(loc.x+math.random(-2, 2), loc.y+math.random(-2, 2))
	if args.force then
		-- with lots you need to scatter them a bit
		if bug:GetRangeTo(target) > 50 then
			-- find half way
			local loc1 = bug.location
			local loc2 = target
			loc1.x = loc1.x + ((loc2.x - loc1.x) // 2)
			loc1.y = loc1.y + ((loc2.y - loc1.y) // 2)
			bug:MoveTo(loc1.x+math.random(-20, 20), loc1.y+math.random(-20, 20), 15)
		else
			bug:MoveTo(loc.x+math.random(-6, 6), loc.y+math.random(-6, 6))
		end
	end
	local turret = bug:FindComponent("c_turret", true)
	turret:SetRegisterCoord(1, target)
	turret.extra_data.charged = true
	if args.comp and args.comp.exists then
		local ed_bugs = args.comp.extra_data.bugs
		if ed_bugs then ed_bugs[#ed_bugs+1] = bug end
	elseif not args.force then
		local hl = bug:AddComponent("c_bug_homeless", "hidden")
		hl.extra_data.large = math.random() < 0.1
	end
end

local c_bug_spawn = Comp:RegisterComponent("c_bug_spawn", {
	name = "Bug Hive Spawner",
	texture = "Main/textures/icons/components/terraformer.png",
	trigger_radius = 8,
	trigger_channels = "bot",

	on_trigger = function (self, comp, other_entity, force)
		if other_entity.faction.is_player_controlled then
			if math.abs(Map.GetYearSeason()-0.5) < 0.25 then
				self:on_trigger_action(comp, other_entity, force)
			end
		end
	end,

	on_trigger_action = function (self, comp, other_entity, force)
		-- remove from player hives
		local owner_faction = comp.faction
		if owner_faction.is_player_controlled then Map.Defer(function() if comp.exists then comp:Destroy() end end) return end

		-- activate all nearby normal hives
		if comp.id == "c_bug_spawner_large" then
			Map.FindClosestEntity(comp.owner, 10, function(e)
				if e.id ~= "f_bug_hive" then return end
				local c = e:FindComponent("c_bug_spawn")
				self:on_trigger_action(c, other_entity, force)
			end, FF_OPERATING)
		end

		if not other_entity.faction.is_player_controlled or owner_faction:GetTrust(other_entity) ~= "ENEMY" or other_entity.stealth then
			return
		end

		local extra_data = comp.extra_data
		local ed_bugs = extra_data.bugs
		if not ed_bugs then
			-- first time
			ed_bugs = {}
			extra_data.bugs = ed_bugs
			extra_data.spawned = Map.GetTick() - 901
			extra_data.lvl = 0
			extra_data.extra_spawned = 0
		end

		for i=#ed_bugs,1,-1 do
			if not ed_bugs[i].exists then table.remove(ed_bugs, i) end
		end

		local owner = comp.owner

		-- still bugs exist
		if #ed_bugs > 0 then
			--trigger docked bugs to attack
			for _,bug in ipairs(ed_bugs) do
				bug:FindComponent("c_turret", true):SetRegisterCoord(1, other_entity.location)
				if force then
					bug:SetRegisterEntity(FRAMEREG_GOTO, nil)
					if not bug:FindComponent("c_bug_homeless") then
						bug:AddComponent("c_bug_homeless", "hidden")
					end
				end
			end
			return
		end

		-- spawn timer has passed
		local map_tick, ed_spawned, ed_lvl, ed_extra_spawned = Map.GetTick(), extra_data.spawned, extra_data.lvl or 0, extra_data.extra_spawned or 0
		--print(Map.GetTick()-ed_spawned)
		if map_tick - ed_spawned < 900 and not force then return end

		-- decide spawn amount depending on how many bughole slots there are in the owner frame
		local early_easy = 2 + math.min(Map.GetTotalDays() // 2, 6)
		local max_num = (owner.id == "f_bug_hole" and 1 or early_easy) + ed_extra_spawned
		if StabilityGet then
			local stability = -StabilityGet()
			stability = stability // 500
			max_num = max_num + math.max(0, stability)
		end
		max_num = math.min(max_num, owner.def.slots and owner.def.slots.bughole) or 1
		local num = math.random(math.ceil(max_num / 3), max_num)

		-- calculate distance from other entities faction home or 0,0
		local loc = owner.location
		local other_faction = other_entity.faction
		local other_home =  other_faction.home_location
		local distloc = { x = loc.x, y = loc.y }
		if other_home then
			distloc.x = loc.x - other_home.x
			distloc.y = loc.y - other_home.y
		end
		local dist = (distloc.x*distloc.x)+(distloc.y*distloc.y)

		-- only do it for the blight
		local settings = Map.GetSettings()
		local plateau_level = settings.plateau_level
		local tile_h = Map.GetElevation(loc.x, loc.y)
		if tile_h < plateau_level then dist = 0 end

		-- player tech level + local spawn count added to level
		local player_level = GetPlayerFactionLevel(other_faction)

		-- artificially increase level based on distance from home
		if dist > 30000 then player_level = player_level + 5
		elseif dist > 90000 then player_level = player_level + 10
		elseif dist > 122500 then player_level = player_level + 20
		end

		--[[
		-- increase level based on number of bugs killed
		local counters = other_entity.faction.extra_data.counters
		local bugs_killed = (counters and counters["BugsKilled"])
		if bugs_killed then player_level = player_level + (bugs_killed // 10) end
		--]]
		if force and settings.peaceful == 3 then -- only aggressrive bugs get the boost
			local ramp = 0.4
			local level = math.ceil(player_level * ramp)
			local num_bugs = level+1
			num = math.max(num_bugs, num)
			if comp.faction.num_entities > 2000 then num = num // 3 end
		else
			num = math.min((player_level // 3)+1, num)
		end
		local bug_levels = GetBugCountsForLevel(player_level, num, force)
		--print("level: ", player_level, "num: ", num, " - ", bug_levels[1], bug_levels[2], bug_levels[3], bug_levels[4])

		-- for each bug type
		local rewards = 0
		local egg_spawner = false
		local spawn_delay = 1
		local num_bugs = 0


		local allbugs = 0
		for i=1,#bug_levels do
			allbugs = allbugs + bug_levels[i]
		end
		local num_waves = (allbugs // 30)+1
		--print("num waves:", num_waves, "total bugs:", allbugs)
		local target = other_entity.location

		for i=#bug_levels,1,-1 do
			if bug_levels[i] > 0 then
				-- spawn the number of bugs for that level
				for j=1,bug_levels[i] do
					rewards = rewards + (i * 3)
					num_bugs = num_bugs + 1
					local bug_delay = (((spawn_delay % 15) + ((math.random(1, num_waves)-1)*30))*3)+1
					--print(num_bugs, ":", bug_delay, "leve:", i)
					if bug_delay < 5 then bug_delay = 1 end
					Map.Delay("SpawnFromHive", bug_delay, {
						level = i,
						force = force,
						owner = owner,
						loc = Tool.Copy(loc),
						target = target,
						comp = comp,
					})
					spawn_delay = spawn_delay + 1
				end
			end
		end
		extra_data.spawned = map_tick
		extra_data.lvl = ed_lvl + 1

		-- 10% chance to spawn a new hole
		if comp.owner.id == "f_bug_hive" and ed_extra_spawned < 8 and math.random() <= 0.05 then
			local x, y = owner.location.x, owner.location.y
			local newx = math.random(x-4, x+4)
			local newy = math.random(y-4, y+4)
			local newbughole = Map.CreateEntity(owner_faction, "f_bug_hole")
			newbughole:Place(newx, newy)
			newbughole:PlayEffect("fx_digital_in")
			extra_data.extra_spawned = ed_extra_spawned + 1
		end

		if not extra_data.rewards then
			comp.owner:AddItem("bug_carapace", math.min(rewards, 20))
			extra_data.rewards = rewards
		end
	end,
	-- also trigger if it was attacked
	on_take_damage = function(self, comp, amount, damager)
		--if math.abs(Map.GetYearSeason()-0.5) >= 0.25 then
		--	-- TODO: trigger surrounding
		--end
		Map.Defer(function()
			if comp.exists and damager.exists then
				self:on_trigger_action(comp, damager)
			end
		end)
	end
})

c_bug_spawn:RegisterComponent("c_bug_spawner_large", {
	trigger_radius = 15,
	spawn_scout = true,
	activation = "Always",
	on_update = function(self, comp, cause)
		-- remove from player hives
		if comp.faction.is_player_controlled then Map.Defer(function() if comp.exists then comp:Destroy() end end) return end

		local bugs_faction = GetBugsFaction()
		-- prevent spawning after using the cheat or not in aggressive mode
		local settings = Map.GetSettings()
		local peaceful = settings.peaceful
		if peaceful == 1 then return comp:SetStateSleep(20000) end
		if peaceful ~= 3 and not settings.creep then return comp:SetStateSleep(10000) end
		if bugs_faction.num_entities > 4000 then return comp:SetStateSleep(1000) end

		-- slowly spawn bugs
		local extra_data = comp.extra_data
		if not extra_data.extra_spawned then
			extra_data.extra_spawned = 0
		end
		extra_data.extra_spawned = extra_data.extra_spawned + 1
		--print(comp, extra_data.extra_spawned)
		local owner = comp.owner
		if extra_data.extra_spawned > 10 then
			-- attack or spawn new hive
			--print("Num bugs: ", bugs_faction.num_entities)
			local rnd = math.random()
			if rnd < 0.2 then
				-- check how many bugs hives are close
				local hivecount = 0
				local found = Map.FindClosestEntity(comp.owner, 5, function(enemy)
					if enemy.id == "f_bug_hive" or enemy.id == "f_bug_hive_large" then
						hivecount = hivecount + 1
						if hivecount > 5 then
							return true
						end
					end
				end, FF_OPERATING)
				if not found then
					Map.Defer(function()
						if comp.exists then
							--print("- spawning extra hive", hivecount)
							local newhome = Map.CreateEntity(bugs_faction, "f_bug_hive")
							newhome:Place(owner.location)
							comp.extra_data.extra_spawned = 0
						end
					end)
				end
			elseif rnd > 0.3 then
				local closest_distance, closest_faction = 9999999

				-- get closest faction
				local towards
				for _, faction in ipairs(Map.GetFactions()) do
					if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
						local newdist = 9999998
						local test_entity = faction.entities[math.random(1, #faction.entities)]
						newdist = owner:GetRangeTo(test_entity)
						if newdist < closest_distance then
							closest_faction = faction
							closest_distance = newdist
							towards = test_entity
						end
					end
				end
				if closest_faction then
					-- force assault if there are too many bugs
					if ((peaceful == 2 and closest_distance > 20) or (closest_distance > 150)) and (bugs_faction.num_entities < 2000) then
						local rnd = math.random()
						if rnd > 0.6 then
							-- spawn a triloscout
							Map.Defer(function()
								--print("spawning scout")
								if not owner.exists then return end
								local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
								scout:Place(owner)
								local harvest_comp = scout:FindComponent("c_bug_harvest")
								harvest_comp.extra_data.home = owner
								if rnd > 0.7 or bugs_faction.num_entities > 500 then -- move it towards the enemy
									harvest_comp.extra_data.towards = towards and towards.location or closest_faction.home_location
								end
							end)
						end
						comp.extra_data.extra_spawned = 0
						return comp:SetStateSleep(math.random(4000,8000))
					elseif peaceful == 3 or (closest_distance <= 60) then -- only trigger attacks forcefully in aggressive mode or if really close in hostile
						-- trigger assault
						local ent = closest_faction.home_entity
						if not ent then
							for _,e in ipairs(closest_faction.entities) do
								if e.exists and e.is_placed then
									ent = e
									break
								end
							end
						end
						if ent then
							--print("triggering", comp.owner.location)
							Map.Defer(function()
								if comp.exists and ent.exists then
									self:on_trigger_action(comp, ent, true)
									comp.extra_data.extra_spawned = 0
								end
							end)
						end
					end
				end
			--else print("do nothing")
			end
		end

		return comp:SetStateSleep(math.random(300,600))
	end,
})

Comp:RegisterComponent("c_bug_harvest", {
	name = "Bug Harvest",
	activation = "Always",
	on_add = function(self, comp)
		local data = comp.extra_data
		data.state = "idle"
		data.target = nil
		data.wandertimes = 0
	end,
	on_update = function(self, comp, cause)
		local owner = comp.owner
		local data = comp.extra_data
		local target = data.target
		local home = data.home
		if target and not target.exists then
			data.state = "wander"
			data.target = nil
			return comp:SetStateSleep(1)
		end
		if owner.is_moving then return comp:SetStateSleep(5) end
		local state = data.state or "idle"
		if not target and state ~= "idle" and state ~= "wander" then
			data.state = "wander"
			return
		end
		if state == "idle" then
			-- find closest resource
			if home and home.exists then
				target = Map.FindClosestEntity(owner, 8, function(e)
					if IsResource(e) and GetResourceHarvestItemId(e) == "silica" and e:GetRangeTo(home) > 20 then return true end
					return false
				end, FF_RESOURCE)
			else
				-- scout dies if home dies
				Map.Defer(function() if owner.exists then owner:Destroy() end end)
				return comp:SetStateSleep(1)
			end
			if target then
				data.target = target
				data.state = "deploy"
			else
				data.state = "wander"
				data.wandertimes = (data.wandertimes or 1) + 1
				-- died of hunger
				if data.wandertimes > 50 then
					Map.Defer(function() owner:Destroy() end)
					return comp:SetStateSleep(1)
				end
			end
		elseif state == "deploy" then
			-- move to
			if not owner.state_path_blocked then
				if comp:RequestStateMove(target, 3) then return end
			end
			data.target = nil
			Map.Defer(function()
				if comp.exists then
					-- check local area
					local nearbyhive = Map.FindClosestEntity(comp.owner, 25, function(e)
						if e.id == "f_bug_hive_large" then
							return true
						end
					end, FF_OPERATING)

					local newhome = Map.CreateEntity(GetBugsFaction(), (nearbyhive or (math.random() > 0.8)) and "f_bug_hive" or "f_bug_hive_large")
					newhome:Place(owner.location)
					comp.extra_data.extra_spawned = 0
					owner:Destroy()
				end
			end)
			return comp:SetStateSleep(10)
		elseif state == "wander" then
			-- random tile with 10 squares on the plateau
			local loc = owner.location
			if data.towards then
				local tloc = data.towards
				local dx = math.min(math.max((tloc.x - loc.x) // 3, -50), 50)
				local dy = math.min(math.max((tloc.y - loc.y) // 3, -50), 50)
				--local denom = math.floor(math.sqrt((dx * dx) + (dy * dy)))
				loc.x = loc.x + dx + math.random(-5, 5)
				loc.y = loc.y + dy + math.random(-5, 5)
			else
				loc.x = loc.x + math.random(-15, 15)
				loc.y = loc.y + math.random(-15, 15)
			end
			data.state = "idle"
			return comp:RequestStateMove(loc, 1)
		end
	end,
})

Comp:RegisterComponent("c_egg_hatch", {
	name = "Egg",
	on_update = function(self, comp, cause)
		local work_finished = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
		if work_finished then
			-- hatch sleep until dead
			local owner = comp.owner
			owner:Activate()
			Map.Defer(function()
				if not owner.exists then return end
				local bug = Map.CreateEntity(owner.faction, "f_lucanops1")
				bug:Place(owner)
				local target = owner.extra_data.target
				if target then bug:FindComponent("c_turret", true):SetRegister(1, target) end
			end)
			Map.Delay("DelayedDestroyEntity", 14, { ent = owner }) -- destroy egg
			return comp:SetStateSleep(99999)
		end
		if comp.is_working then return comp:SetStateContinueWork() end
		return comp:SetStateStartWork(180)
	end,
	activation = "Always",
})

data.update_mapping.c_analyzer_scannable = "c_explorable_scannable"
local c_explorable_scannable = Comp:RegisterComponent("c_explorable_scannable", {
	name = "Intel Scanner",
	--texture = "Main/textures/icons/component/comp_scanner.png",
	type = "Puzzle",
})

function c_explorable_scannable:on_add(comp)
	comp.extra_data.hack_code = math.random(1000, 9999)
end

local c_explorable_fix = Comp:RegisterComponent("c_explorable_fix", {
	name = "Repair Required",
	texture = "Main/textures/icons/components/int.png",
	--effect = "fx_leaves",
	activation = "OnAnyItemSlotChange",
	type = "Puzzle",
	on_solved = function(comp, explorable_race, faction)
		comp.owner:SetRegister(FRAMEREG_SIGNAL, nil)
		AddRaceTechItem(comp.owner, explorable_race, faction)
	end,
	explorable_fix = "transformer",
})
function c_explorable_fix:on_update(comp, cause)
	local fix_item = comp.has_extra_data and comp.extra_data.explorable_fix or self.explorable_fix
	local slot = comp.owner:FindSlot(fix_item, 1)
	if slot then
		Map.Defer(function() if comp.exists and slot.exists and slot.unreserved_stack > 0 then FactionAction.ExplorableSolvePuzzle(comp.faction, { comp = comp, consume_slot = slot  }) end end)
	end
end

c_explorable_fix:RegisterComponent("c_explorable_fix_lvl2", {
	name = "Datakey Socket",
	type = "Puzzle",
	on_solved = function(comp, explorable_race, faction)
		AddRaceTechItem(comp.owner, explorable_race, faction)
	end,
	explorable_fix = "datakey",
})

Comp:RegisterComponent("c_explorable_autosolve", {
	registers = { { }, },
	type = "Puzzle",
	on_solved = function(comp, explorable_race, faction)
		local reg = comp:GetRegister(1)
		if reg then
			comp.owner:AddItem(reg.id, reg.num)
		end
		AddRaceTechItem(comp.owner, explorable_race, faction)
	end,
})

c_explorable_fix:RegisterComponent("c_explorable_admin_fix", {
	name = "Admin Console",
	explorable_fix = "datakey_blight",
	on_solved = function(comp, explorable_race, faction)
		comp.owner:SetRegister(FRAMEREG_SIGNAL, nil)
		comp.owner:AddItem("datakey_alien", 1)
		AddRaceTechItem(comp.owner, explorable_race, faction)
	end,
})

local c_virus = Comp:RegisterComponent("c_virus", {
	name = "Virus",
	texture = "Main/textures/tech/virus.png",
	activation = "Manual",
	trigger_radius = 1,
	trigger_channels = "bot|building",
	--boost = -50,
	disruptor = 9999, -- for negative effect
	shield_disrupt = 200, -- for positive effect when taking damage
	shield_charge = 0,
	adjust_extra_power = true,
	virus_effect = "fx_glitch2",
	on_placed = def_comp_activate, -- immediately play effect
})

function c_virus:on_take_damage(comp, amount)
	local damage = self.shield_disrupt
	local target = comp.owner
	for i=1,999 do
		if damage <= 0 then break end
		local shield_comp = target:FindComponent("c_shield_generator", true, i)
		if not shield_comp then break end
		damage = shield_comp.def:ApplyShieldDamage(shield_comp, damage, "electromag_damage")
	end
	shieldrecharge_effect(self, comp, target)
end

function c_virus:on_trigger(comp, other_entity)
	comp:Activate()
end

function c_virus:on_add(comp)
	comp.owner.state_custom_1 = true
end

function c_virus:on_remove(comp)
	comp.owner.state_custom_1 = false
end

function c_virus:on_update(comp, trigger)
	local faction = comp.faction
	local has_vac = faction:IsUnlocked("t_robots_virus_vaccine") -- no negative effects
	local has_av = faction:IsUnlocked("t_robots_antivirus") -- positive effects
	local owner = comp.owner
	local player_control = faction.is_player_controlled
	if player_control then
		if not has_vac then
			if not comp.has_active_effects and self.virus_effect and owner.is_placed then
				comp:PlayEffect(self.virus_effect, "_entity")
			end
			Map.Defer(function()
				if not comp.exists then return end
				slow_effect(comp.def, comp, comp.owner)
				electromag_effect(comp.def, comp, comp.owner)
			end)
		elseif has_av then
			if comp.has_active_effects then
				comp:StopEffects()
			end
			-- add boost
			comp.extra_power = 20
		end
	else
		if not has_vac and not comp.has_active_effects and self.virus_effect and owner.is_placed then
			comp:PlayEffect(self.virus_effect, "_entity")
		end
		Map.Defer(function() if comp.exists then slow_effect(comp.def, comp, comp.owner) end end)
	end

	for _,other_entity in ipairs(comp.triggering_entities) do
		if other_entity.has_component_list
			and not other_entity:FindComponent("c_virus")
			and not other_entity:FindComponent("c_virus_cure")
			and not other_entity:FindComponent("c_virus_protection")
			and not Map.FindClosestEntity(other_entity, 3, function(e)
				return e:FindComponent("c_virus_cure") ~= nil
			end, FF_OPERATING)
			then
			if owner.faction ~= other_entity.faction or math.random(4) == 1 then -- always infect other faction units
				--print(owner, "    INFECT", other_entity)
				other_entity:AddComponent("c_virus", "hidden")
				if not other_entity.faction:IsUnlocked("t_robotics_virus_discovery") then
					other_entity.faction:Unlock("t_robotics_virus_discovery")
				end
				FactionCount("virus_infection", true, other_entity.faction)
				other_entity.faction:RunUI("OnVirusNotification", other_entity)
				break
			end
		end
	end

	comp:SetStateSleep(75) -- wake up again after x ticks
end

-- unlocked when you get a virus
local c_virus_protection = Comp:RegisterComponent("c_virus_protection", {
	attachment_size = "Internal", race = "virus", index = 4013, name = "Virus Protection",
	desc = "Protects from receiving the virus and removes any viruses when equipped",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/virus_protection.png",
	production_recipe = CreateProductionRecipe({ infected_circuit_board = 1, reinforced_plate = 1 }, { c_assembler = 40, c_human_factory = 60 }),
})


----- portable analyzer -----
local c_small_scanner = Comp:RegisterComponent("c_small_scanner", {
	attachment_size = "Small", race = "robot", index = 1042, name = "Intel Scanner",
	desc = "Scan explorables internals to access the console. Can be used to gain the hacking code of enemy factions.",
	texture = "Main/textures/icons/components/Component_Scanner_01_S.png",
	visual = "v_scanner_s",
	power = -10,
	production_recipe = CreateProductionRecipe({ icchip = 1, silicon = 10, hdframe = 5 }, { c_advanced_assembler = 20 }),
	activation = "OnFirstRegisterChange",
	action_tooltip = action_tooltip_set_target,
	registers = {
		{ type = "entity", tip = "Item to scan", ui_icon = "icon_context", click_action = true, filter = 'entity' },
		{ read_only = true, tip = "Scan Result", },
	},
})

function c_small_scanner:action_click(comp, widget)
	CursorChooseEntity("Select the scanning target", function (target)
		if not comp.exists then return end -- got destroyed
		local arg = { comp = comp , reg = { entity = target } }
		Action.SendForEntity("SetRegister", comp.owner, arg)
	end,
	nil, comp.register_index)
end

function c_small_scanner:on_update(comp, cause)
	local scannable = comp:GetRegisterEntity(1)
	if not scannable or scannable.faction == comp.faction then
		comp:SetRegister(2, nil)
		comp:StopEffects()
		return
	end

	-- check if the scannable was already scanned
	if comp:GetRegisterEntity(2) == scannable then
		comp:StopEffects()
		return
	end

	-- move to scannable entity
	if comp:RequestStateMove(scannable) then comp:SetRegister(2, nil) return end

	-- Don't do anything yet if the explorable was already scanned but not fully solved
	local scannable_comp = scannable:FindComponent("c_explorable_scannable")
	local secondary_scan = scannable_comp and scannable_comp.extra_data.ok
	if secondary_scan and not scannable.extra_data.solved then
		comp:StopEffects()
		return comp:SetStateSleep(7) -- sleep, it might get solved later
	end

	-- If work was finished, make sure the target entity did not change just now
	if cause & (CC_FINISH_WORK | CC_CHANGED_REGISTER_ENTITY) == CC_FINISH_WORK then
		-- Finished scanning, set solved
		local need_sleep
		if secondary_scan then
			comp:SetRegister(2, { entity = scannable, num = scannable_comp.extra_data.hack_code })
		elseif scannable_comp then
			FactionAction.ExplorableSolvePuzzle(comp.faction, { comp = scannable_comp })
			local got_solved = scannable.extra_data.solved
			comp:SetRegister(2, got_solved and { entity = scannable, num = scannable_comp.extra_data.hack_code })
			need_sleep = not got_solved
			FactionCount("explorables_scanned", 1, comp.faction)
			if scannable.visual_def.explorable_race == "human" then
				FactionCount("human_explorables_scanned", 1, comp.faction)
				comp.faction:Unlock("transformer")
			elseif scannable.visual_id == "v_explorable_blightanomaly_02" then
				local counters = comp.faction.extra_data.counters
				local counter = counters and counters.m_human_c
				if counter == 13 then
					comp.faction:Unlock("datakey_alien")
					FactionCount("m_alien_a", 2, comp.faction, 'set_if_less')
				end
			end
		else
			-- scanned faction
			comp:SetRegister(2, { entity = scannable, num = scannable.has_extra_data and scannable.extra_data.hack_code or scannable.faction.extra_data.hack_code })
		end
		comp:StopEffects()
		return need_sleep and comp:SetStateSleep(7) -- sleep, it might get solved later
	end

	-- start scanning with refresh to check if we're still in place and the scannable still exists
	comp:PlayWorkEffect("fx_scan", "fx")
	comp:SetRegister(2, nil)
	return comp:SetStateStartWork(scannable.faction.is_world_faction and 30 or 120, true, (cause & CC_CHANGED_REGISTER_ENTITY == 0))
end

local c_alien_key = Comp:RegisterComponent("c_alien_key", {
	attachment_size = "Internal", race = "alien", index = 5063, name = "Alien Decryption Key",
	texture = "Main/textures/icons/components/alien_decryption_key.png",
	desc = "Allows interfacing with alien structures",
	visual = "v_generic_i",
	registers = {
		{ tip = "Key", read_only = true },
	},
	production_recipe = CreateProductionRecipe({ cpu = 1, power_petal = 10, hdframe = 1 }, { c_alien_factory_robots = 40 }),
	activation = "Always",
	glyph_array = { "v_signal_a", "v_signal_b", "v_signal_c", "v_signal_d", "v_signal_e" },
})

function c_alien_key:on_update(comp)
	local glyph_num = 1 + ((Map.GetTick() // 2) % #self.glyph_array)
	comp:SetRegisterId(1, self.glyph_array[glyph_num], glyph_num)
	return comp:SetStateSleep(2)
end

Comp:RegisterComponent("c_alien_lock", {
	name = "Alien Lock",
	texture = "Main/textures/icons/components/alien_lock.png",
	desc = "A locking device of unknown origin",
	type = "Puzzle",
	on_solved = function(comp, explorable_race, faction)
		if faction.extra_data.race ~= "alien" then
			comp.owner:AddItem("shaped_obsidian", math.random(3) + 2) -- 3-5
			comp.owner:AddItem("alien_datacube", math.random(3) - 1) -- 0-2
		end
		-- if its a monolith, activate it
		local owner = comp.owner
		if owner.visual_id == "v_explorable_monolith_01" then
			owner:SetVisual("v_explorable_monolith_02")
			owner:AddComponent("c_monolith_effect", "hidden")
			owner:AddComponent("c_monolith_lightning", "hidden")
			owner:PlayEffect("fx_digital_in")
		end
	end,
})

local resim_recipes = {
	-- robot
	c_miner     = { to = "c_adv_miner", use = "bb", amount = 5,  time =  50 },
	f_bot_1s_b  = { to = "f_bot_1s_as", use = "bb", amount = 15, time = 200 },
	f_bot_1m_a  = { to = "f_bot_1l_a", use = "bb", amount = 15, time = 200 },
	f_bot_1s_a  = { to = "f_bot_1s_adw", use = "bb", amount = 20, time = 200 },

	-- human
	c_turret = { to = "c_extractor", use = "hb", amount = 5, time =  50, requires="c_human_ac" },
	f_flyer_bot = { to = "f_human_flyer", use = "hb", amount = 10, time = 100, requires="c_human_ac" },
	f_bot_1m1s = { to = "f_human_tank", use = "hb", amount = 10, time = 100, requires="c_human_ac" },
	f_drone_miner_a = { to = "f_drone_adv_miner", use = "hb", amount = 5, time = 200, requires="c_human_ac" },
	c_power_transmitter = { to = "c_large_power_transmitter", use = "hb", amount = 10, time = 50, requires="c_human_ac" },
	f_human_explorer  = { to = "f_human_explorer_upgraded", use = "hb", amount = 5, time = 200, requires="c_human_ac", hidden = true },

	-- virus
	c_deconstructor = { to = "c_virus_recycler", use = "yb", amount = 5, time = 10, requires="c_virus_ac" },
	f_trilobyte1 = { to = "f_trilobyte1b", use = "yb", amount = 1, time = 30, requires="c_virus_ac"},
	f_gastarid1 = { to = "f_lucanops1", use = "yb", amount = 20, time = 100, requires="c_virus_ac"},
	f_gastarias1 = { to = "f_gastarias2", use = "yb", amount = 5, time = 100, requires="c_virus_ac"},
	f_drone_transfer_a = { to = "f_wasp1", use = "yb", amount = 1, time = 30, requires="c_virus_ac"},

	-- blight
	c_shield_generator = { to = "c_blight_shield", use = "rb", amount = 1, time = 50, requires="c_blight_ac" },
	c_crystal_power = { to = "c_blightcrystal_power", use = "rb", amount = 5, time = 50, requires="c_blight_ac" },
	c_shield_generator2 = { to = "c_shield_generator3", use = "rb", amount = 5, time = 100, requires = "c_blight_ac" },
	c_blight_converter = { to = "c_blight_magnifier", use = "rb", amount = 20, time = 100, requires = "c_blight_ac" },

	-- alien
	c_photon_beam = { to = "c_alien_ion_lance", use = "ab", amount = 5, time = 50, requires="c_alien_ac" },
	f_hybrid_alien_soldier = { to = "f_alien_soldier", use = "ab", amount = 10, time = 50, requires="c_alien_ac" },
	f_human_tankframe = { to = "f_alien_tankframe", use = "ab", amount = 20, time = 50, requires="c_alien_ac" },
	c_plasma_turret = { to = "c_sentinel_lance_comp", use = "ab", amount = 10, time = 50, requires="c_alien_ac" },

	higgs_oop_ai_core = { to = "higgs_ai_ac", requires="c_blight_ac", hidden = true }, -- use = "bb", amount = 10,
	-- recharge
	robot_research = { fill = "bb", amount = 5, time = 5 },
	virus_research = { fill = "yb", amount = 5, time = 5, requires="c_virus_ac" },
	blight_research = { fill = "rb", amount = 5, time = 5, requires="c_blight_ac" },
	human_research = { fill = "hb", amount = 5, time = 5, requires="c_human_ac" },
	alien_research = { fill = "ab", amount = 5, time = 5, requires="c_alien_ac" },

	robot_datacube = { fill = "bb", amount = 1, time = 5 },
	virus_research_data = { fill = "yb", amount = 1, time = 5, requires="c_virus_ac" },
	blight_datacube = { fill = "rb", amount = 1, time = 5, requires="c_blight_ac" },
	human_datacube = { fill = "hb", amount = 1, time = 5, requires="c_human_ac" },
	alien_datacube = { fill = "ab", amount = 1, time = 5, requires="c_alien_ac" },

	-- events
	elain_ai_core = {
		event = function(entity)
			Map.Defer(function()
				local newhome = GetPlayerFactionHomeOnGround()
				local newlander = FreeplaySpawnPlayer(entity.faction, { x=newhome[1], y=newhome[2] })

				-- restart repairs
				local mothership = entity.faction.extra_data.mothership
				if mothership and mothership:FindComponent("c_mothership_repair") == nil then
					mothership:AddComponent("c_mothership_repair")
				end

				-- unlock multicube -  TODO
				-- entity.faction:Unlock("rainbow_research")

				entity.faction:RunUI(function()
					if View.IsSelectedEntity(entity) then
						View.MoveCamera(newhome[1], newhome[2])
						View.SelectEntities(newlander)
						View.PlayEffect("fx_EMP", newhome[1], newhome[2])
					end
				end)

				if data.codex.x_freeplay_restart then
					entity.faction:Unlock("x_freeplay_restart")
				end
				entity.faction:UnlockAchievement("SPAWN_AWAYTEAM")
			end)
		end,
		time = 50,
		--require_all_cores = true,
	},

	-- converts your core to global efficiency module 5
	bot_ai_core = {
		to = "c_moduleefficiency_5",
		event = function(entity)
			Map.Defer(function()
				entity.faction:Unlock("c_moduleefficiency_5")

				-- restart repairs
				local mothership = entity.faction.extra_data.mothership
				if mothership and mothership:FindComponent("c_mothership_repair") == nil then
					mothership:AddComponent("c_mothership_repair")
				end

				if data.codex.x_freeplay_efficiency then
					entity.faction:Unlock("x_freeplay_efficiency")
				end
			end)
		end,
		time = 50,
		--require_all_cores = true,
	},
	higgs_broken_core = {
		event = function(entity)
			-- restart repairs
			local mothership = entity.faction.extra_data.mothership
			if mothership and mothership:FindComponent("c_mothership_repair") == nil then
				mothership:AddComponent("c_mothership_repair")
			end
			for i=1,40 do
				Map.Delay("spawn_higgs_reward", i * 2, { ent = entity })
			end
		end,
		time = 200,
	}
}

function Delay.spawn_higgs_reward(arg)
	local entity = arg.ent
	if entity.exists then
		Map.DropItemAt(entity.location, "robot_datacube", 5, true)
		Map.DropItemAt(entity.location, "human_datacube", 5, true)
		Map.DropItemAt(entity.location, "virus_research_data", 1, true)
		Map.DropItemAt(entity.location, "blight_datacube", 2, true)
	end
end

local function ac_get_ui(self, comp)
	if not StabilityGet then return end -- only available in freeplay scenario
	return nil, UI.New([[<VerticalList child_padding=2>
			<Box width=82 halign=center>
				<Button halign=fill height=19 icon=icon_small_find on_click={showrecipes} tooltip="Known Recipes"/>
			</Box>
			<Box padding=4>
				<Canvas width=84 height=27 child_fill=true>
					<Progress id=prog/>
					<Text id=num size=16 style=outline textalign=center opacity=0.7/>
				</Canvas>
			</Box>
		</VerticalList>]], {
		construct = function(view)
			local comp_id, col, cube_use, cube_id = comp.base_id
			if     comp_id == "c_blight_ac" then col, cube_use, cube_id = "purple",    "rb", "blight_datacube"
			elseif comp_id == "c_human_ac"  then col, cube_use, cube_id = "yellow",    "hb", "human_datacube"
			elseif comp_id == "c_virus_ac"  then col, cube_use, cube_id = "green",     "yb", "virus_research_data"
			elseif comp_id == "c_alien_ac"  then col, cube_use, cube_id = "red",       "ab", "alien_datacube"
			else                                 col, cube_use, cube_id = "lightblue", "bb", "robot_datacube" end
			view.prog.color, view.cube_use, view.cube_id = col, cube_use, cube_id
		end,
		showrecipes = function(view)
			if not comp or not comp.exists then return end
			UI.MenuPopup("<Box bg=popup_box_bg blur=true padding=8 py=1><VerticalList id=list child_padding=4/></Box>", {
				construct = function(box)
					box:TweenFromTo("sy", 0, 1, 100)
					local comp_id, use, cube = comp.base_id, view.cube_use, view.cube_id
					local list, header = box.list
					for k,v in pairs(resim_recipes) do
						if not v.hidden and v.to and v.amount and use == v.use and (not v.requires or v.requires == comp_id) then
							if not header then header = list:Add('<Text halign=center style=hl text="Known Recipes"/>') end
							local h = list:Add("<HorizontalList child_align=center child_padding=4/>")
							h:Add("<Reg bg=item_default/>", { def_id = cube, num = v.amount })
							h:Add("<Reg bg=item_default/>", { def_id = k, num = 1 })
							h:Add("<Image image=icon_small_arrow/>")
							h:Add("<Reg bg=item_default/>", { def_id = v.to, num = 1 })
						end
					end
					if not header then list:Add('<Text halign=center style=hl text="No Known Recipes"/>') end
				end,
			}, view, "UP")
		end,
		update = function(view)
			if not comp or not comp.exists then return end
			local resim_comp = comp.base_id == "c_resimulator" and comp or comp.owner:FindComponent("c_resimulator", true)
			if not resim_comp then return end

			local ed = resim_comp.has_extra_data and resim_comp.extra_data
			local num = (ed and ed[view.cube_use] or 0)
			view.num.text = tostring(num)
			view.prog.progress = num / 100
		end,
	})
end

local c_resimulator = Comp:RegisterComponent("c_resimulator", {
	attachment_size = "Hidden", race = "robot", index = 1045, name = "Re-Simulator Core",
	desc = "Reconstructs objects on a simulation level",
	texture = "Main/textures/icons/components/resimulator_robot.png",
	power = -400,
	resim_recipes = resim_recipes,
	activation = "OnAnyItemSlotChange",
	slots = { garage = 2 },
	registers = {
		{ tip = "Robot",  read_only = true },
		{ tip = "Human",  read_only = true },
		{ tip = "Virus",  read_only = true },
		{ tip = "Blight", read_only = true },
		{ tip = "Alien",  read_only = true },
	},
})

function c_resimulator:on_add(comp)
	-- This needs to be deferred so it can catch extra data set immediately after the component is being created (as part of f_building_sim)
	Map.Defer(function()
		if not comp.exists or not comp.has_extra_data then return end
		for key,num in pairs(comp.extra_data) do
			if     key == "bb" then comp:SetRegister(1, { id = "robot_datacube",      num = num })
			elseif key == "hb" then comp:SetRegister(2, { id = "human_datacube",      num = num })
			elseif key == "yb" then comp:SetRegister(3, { id = "virus_research_data", num = num })
			elseif key == "rb" then comp:SetRegister(4, { id = "blight_datacube",     num = num })
			elseif key == "ab" then comp:SetRegister(5, { id = "alien_datacube",      num = num })
			end
		end
	end)
end

function c_resimulator:get_ui(comp)
	local bigbtn_ui, reg_ui

	if StabilityGet then -- only available in freeplay scenario
		bigbtn_ui = UI.New([[
			<Box width=280 blur=true padding=8>
				<HorizontalList>
					<VerticalList child_padding=4 fill=true>
						<HorizontalList>
							<ProgressCircle id=progress image="Main/skin/Assets/component_progress.png" valign=top width=20 height=20/>
							<Text id=stability text="Stability" textalign=left halign=center fill=true margin_right=10/>
						</HorizontalList>
						<HorizontalList>
							<Progress id=leftbar height=20 valign=center sx=-1 fill=true color=virus/>
							<Image id=progressicon width=2 height=26 valign=center/>
							<Progress id=rightbar height=20 valign=center fill=true color=blight/>
						</HorizontalList>
					</VerticalList>
				</HorizontalList>
				</Box>]],
			{
				construct = function(view)
					view:refresh()
				end,
				every_frame_update = function(view)
					view.progress.progress = comp.interpolated_progress
				end,
				refresh = function(view)
					-- stability
					local _save = Map.GetSave()
					local unlocked_ending = _save.stability_locked == true
					unlocked_ending = unlocked_ending and not Game.GetLocalPlayerFaction():IsUnlocked("t_simulator_robots")
					view.progressicon.image = unlocked_ending and "icon_small_locked" or nil
					view.progressicon.width = unlocked_ending and 26 or 2

					local v = StabilityGet()
					view.leftbar.progress = (v < 0 and (v / -10000.0) or 0)
					view.rightbar.progress = (v > 0 and (v / 10000.0) or 0)
					local stability_info = data.stability_info
					for _, info in pairs(stability_info) do
						if v >= info.min_range and v <= info.max_range then
							view.stability.text = L("%s: %d\n\n%s", "Stability Rating", v, info.desc)
							break
						end
					end
				end,
				tooltip = function(w)
					w.tt = UI.New("<Box bg=popup_box_bg padding=12><VerticalList><Text/><Text/><Text/><Text/><Text/><Text/><Text hidden=true/></VerticalList></Box>", { destruct = function() if w:IsValid() then w.tt = nil end end })[1]
					w:update()
					return w.tt.parent
				end,
				update = function(view)
					-- bars
					if not comp or not comp.exists then return end
					local ed = comp.extra_data

					local bb = (ed.bb or 0)
					local yb = (ed.yb or 0)
					local rb = (ed.rb or 0)
					local hb = (ed.hb or 0)
					local ab = (ed.ab or 0)

					view.has =
					{
						--c_robot_ac = comp.owner:FindComponent("c_robot_ac", true),
						c_blight_ac = comp.owner:FindComponent("c_blight_ac", true),
						c_human_ac = comp.owner:FindComponent("c_human_ac", true),
						c_virus_ac = comp.owner:FindComponent("c_virus_ac", true),
						c_alien_ac = comp.owner:FindComponent("c_alien_ac", true),
					}
					if view.tt then
						local sum = bb+yb+rb+hb+ab
						view.tt[1].text = (sum > 499) and "<rl>DANGER:</> Overloaded" or (sum > 400 and "<hl>CAUTION:</> Overload Warning" or "<hl>WARNING:</> Overloading not advised")
						local t1 = view.tt[2]
						local t2 = view.tt[3]
						local t3 = view.tt[4]
						local t4 = view.tt[5]
						local t5 = view.tt[6]
						if bb > 0 then
							t1.hidden = false
							t1.text = string.format("<img id=\"robot_datacube\"/> %d", bb)
						else t1.hidden = true end
						if hb > 0 then
							t2.hidden = false
							t2.text = string.format("<img id=\"human_datacube\"/> %d", hb)
						else t2.hidden = true end
						if yb > 0 then
							t3.hidden = false
							t3.text = string.format("<img id=\"virus_research_data\"/> %d", yb)
						else t3.hidden = true end
						if rb > 0 then
							t4.hidden = false
							t4.text = string.format("<img id=\"blight_datacube\"/> %d", rb)
						else t4.hidden = true end
						if ab > 0 then
							t5.hidden = false
							t5.text = string.format("<img id=\"alien_datacube\"/> %d", ab)
						else t5.hidden = true end

						local t6 = view.tt[7]
						t6.hidden = false

						t6.text = L("\n%s:\n", "Discovered Stability Condition")
						local _save = Map.GetSave()
						local events = _save.stability_events
						for pass = 1,2 do
							if pass == 2 then t6.text = L("%S\n", t6.text) end
							for evt,_ in pairs(events or {}) do
								local stability_event = data.stability[evt]
								if not stability_event then -- old removed evt
								elseif pass == 1 and stability_event.amount > 0 then
									-- positive
									t6.text = L("%S<bl>+ %s</>\n", t6.text, stability_event.desc)
								elseif pass == 2 and stability_event.amount < 0 then
									-- negative
									t6.text = L("%S<gray>- %s</>\n", t6.text, stability_event.desc)
								end
							end
						end
					end
				end,
				destruct = function(view)
					UIMsg:Unbind("OnStabilityChanged", view.handle)
				end
			})

		bigbtn_ui.handle = function() bigbtn_ui:refresh() end
		UIMsg:Bind("OnStabilityChanged", bigbtn_ui.handle)

		local dummy
		dummy, reg_ui = ac_get_ui(self, comp)
	end
	return nil, reg_ui, true, bigbtn_ui
end

local c_virus_ac = Comp:RegisterComponent("c_virus_ac", {
	attachment_size = "Internal", race = "robot", index = 1064, name = "Virus Simulation Core",
	desc = "Connects Virus instances into Re-Simulator world stability",
	texture = "Main/textures/icons/components/resimulator_virus.png",
	production_recipe = CreateProductionRecipe({ c_resimulator_core = 1, virus_source_code = 3 }, { c_data_analyzer = 200, c_mission_human_aicenter = 100, c_human_aicenter = 80 }),
	visual = "v_generic_i",
	slots = { virus = 1, bughole = 1 },
	activation = "OnAnyItemSlotChange",
	power = 0,
	stability = -200,
	on_add = ReSimulatorModuleOnAdd,
	on_remove = ReSimulatorModuleOnRemove,
	get_ui = ac_get_ui,
})

function FactionAction.SendWormhole(faction, arg)
	local e = arg.entity
	if e and e.exists then
		e:Destroy(false)
	end
end

function c_virus_ac:on_update(comp, cause)
	if not comp.owner:FindComponent("c_resimulator", true) then return end

	-- find unit with virus container containing a virus
	local slot
	for _,v in ipairs(comp.owner.slots) do
		if v.entity and v.entity:CountItem("virus_source_code", true) > 0 then slot = v end
	end
	if not slot then return end

	local anomaly_entity = slot.entity

	if anomaly_entity:FindComponent("c_anomaly_event") then
		-- jumping in on itself... cross simulation wormhole event
		UI.Run(function()
			ConfirmBox("Send this unit through the wormhole?\n\nIt will be lost from the simulation.", function()
				local profile = Game.GetProfile()
				local jumpers = profile.jumpers or {}
				jumpers[#jumpers+1] = MakeBlueprintFromEntity(anomaly_entity, true)
				profile.jumpers = jumpers
				Action.SendForLocalFaction("SendWormhole", { entity = anomaly_entity })
			end)
		end)
		return
	end

	anomaly_entity:AddComponent("c_anomaly_event", "hidden")
	UI.Run("NotifyAnomaly", anomaly_entity, true)
end

Comp:RegisterComponent("c_blight_ac", {
	attachment_size = "Internal", race = "robot", index = 1062, name = "Blight Simulation Core",
	desc = "Connects Blight instances into Re-Simulator world stability",
	texture = "Main/textures/icons/components/resimulator_blight.png",
	production_recipe = CreateProductionRecipe({ anomaly_cluster = 1, datakey_blight = 5, c_resimulator_core = 1 }, { c_mission_human_aicenter = 150,  c_human_aicenter = 120, c_human_factory = 100, c_alien_factory_robots = 40 }),
	visual = "v_generic_i",
	power = -100,
	stability = 200,
	on_add = ReSimulatorModuleOnAdd,
	on_remove = ReSimulatorModuleOnRemove,
	get_ui = ac_get_ui,
})

Comp:RegisterComponent("c_human_ac", {
	attachment_size = "Internal", race = "robot", index = 1063, name = "Human Simulation Core",
	desc = "Expands functionality of Re-Simulator, adding Human recipes",
	texture = "Main/textures/icons/components/resimulator_human.png",
	--production_recipe = CreateProductionRecipe({ anomaly_cluster = 1,  }, { c_assembler = 40 }),
	production_recipe = CreateProductionRecipe({ c_resimulator_core = 1, anomaly_cluster = 1 }, { c_mission_human_aicenter = 150,  c_human_aicenter = 120, c_human_factory = 100 }),
	visual = "v_generic_i",
	-- stability = 200,
	get_ui = ac_get_ui,
})

Comp:RegisterComponent("c_alien_ac", {
	attachment_size = "Internal", race = "robot", index = 1065, name = "Alien Simulation Core",
	desc = "Expands functionality of Re-Simulator, adding Alien recipes",
	texture = "Main/textures/icons/components/resimulator_alien.png",
	production_recipe = CreateProductionRecipe({ energized_artifact = 10, c_resimulator_core = 1 }, { c_alien_factory_robots = 100 }),
	visual = "v_generic_i",
	power = -100,
	-- stability = 200,
	get_ui = ac_get_ui,
})

Comp:RegisterComponent("c_alien_sc", {
	attachment_size = "Internal", race = "robot", index = 1066, name = "Reformation Core",
	desc = "Expands functionality of Re-Simulator, allowing basic synthesization of components with Alien units",
	texture = "Main/textures/icons/components/resynthesizer_alien.png",
	production_recipe = CreateProductionRecipe({ energized_artifact = 10, c_resimulator_core = 1 }, { c_adv_alien_factory = 100 }),
	visual = "v_generic_i",
	power = -100,
	activation = "OnFirstRegisterChange",
	registers = {
		{ filter = "alien_synthesis", tip = "Click to change production", ui_icon = "icon_output" },
		{ tip = "Missing ingredient", warning = "Missing ingredient", read_only = true },
	},
	is_missing_ingredient_register = function(idx) return idx == 2 end,
	synthesis_material = "energized_artifact",
	synthesis_s_comp_cost = 20,
	synthesis_i_comp_cost = 10,
	duration = 5 * TICKS_PER_SECOND,
	get_reg_error = function(self, comp)
		if not comp.owner:FindComponent("c_resimulator") then return "Must be equipped on a Re-simulator" end
		local reg1_id = comp:GetRegisterId(1)
		if not reg1_id then return "Not a component" end
		local size = data.all[reg1_id] and data.all[reg1_id].attachment_size
		if not size then return "Not a component" end
		if size ~= "Internal" and size ~= "Small" then return "Component size too large" end

		local alien, simulated
		for _,slot in ipairs(comp.owner.slots) do
			local entity = slot.entity
			if entity and entity.def.race == "alien" then
				if entity.has_extra_data and entity.extra_data.resimulated then
					simulated = entity
				else
					alien = entity
				end
			end
		end
		if not alien then
			if simulated then return "Alien already synthesized" else return "Docked alien is required to synthesize" end
		end
		return "Missing ingredient"
	end,
	on_update = function(self, comp, cause)
		local owner = comp.owner
		if not owner:FindComponent("c_resimulator") then comp:FlagRegisterError(1) return end
		local reg1, reg1_id = comp:GetRegister(1), comp:GetRegisterId(1)
		if reg1.is_empty then comp:SetRegister(2, nil) return end
		local size = reg1_id and data.all[reg1_id] and data.all[reg1_id].attachment_size
		if not size or (size ~= "Internal" and size ~= "Small") then comp:SetRegister(2, nil) comp:FlagRegisterError(1) return end

		local alien
		for _,slot in ipairs(owner.slots) do
			local entity = slot.entity
			if entity and entity.def.race == "alien" and not (entity.has_extra_data and entity.extra_data.resimulated) then
				alien = entity
				break
			end
		end
		if not alien then
			comp:CancelProcess()
			comp:SetRegister(2, nil)
			comp:FlagRegisterError(1)
			return comp:SetStateSleep() -- waiting for alien to dock
		end

		if cause & CC_REFRESH == CC_REFRESH then
			return comp:SetStateContinueWork() -- just rechecking, continue work
		end

		if cause & CC_FINISH_WORK == CC_FINISH_WORK then
			local ingredient_extra_datas = comp:FulfillProcess(true)
			Map.Defer(function()
				if not alien.exists then return end
				alien:AddComponent(reg1_id, "hidden", ingredient_extra_datas and ingredient_extra_datas[reg1_id] and ingredient_extra_datas[reg1_id][1])
				alien:SetRegister(FRAMEREG_GOTO, nil)
				alien:Undock()
				alien.extra_data.resimulated = alien.id
			end)
			if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) return end
			return comp:SetStateSleep(1) -- recheck
		end

		local synthesis_cost = size == "Small" and self.synthesis_s_comp_cost or self.synthesis_i_comp_cost
		local can_make, missing_register = comp:PrepareConsumeProcess( { [self.synthesis_material] = synthesis_cost, [reg1_id] = 1 } )
		comp:SetRegister(2, missing_register)
		if not can_make then -- Missing ingredient
			comp:FlagRegisterError(1)
			return comp:SetStateSleep()
		end
		return comp:SetStateStartWork(self.duration, true)
	end,
})

Comp:RegisterComponent("c_synthesis_pool", {
	attachment_size = "Hidden", race = "alien", index = 5022, name = "Reformation Synthesizer",
	desc = "Allow advanced synthesization of Alien and non Alien units",
	texture = "Main/textures/icons/components/synthesizer.png",
	visual = "v_generic_i",
	power = -100,
	activation = "OnAnyItemSlotChange",
	registers = {
		{ tip = "Missing ingredient", warning = "Missing ingredient", read_only = true },
	},
	is_missing_ingredient_register = function(idx) return idx == 1 end,
	get_ui = true,
	synthesis_material = "energized_artifact",
	synthesis_s_comp_cost = 20,
	synthesis_i_comp_cost = 10,
	duration = 25 * TICKS_PER_SECOND,

	get_reg_error = function(self, comp)
		local alien, simulated, other_unit
		for _,slot in ipairs(comp.owner.slots) do
			local entity = slot.entity
			if entity then
				if entity.def.race == "alien" then
					if entity.has_extra_data and entity.extra_data.resimulated then
						simulated = entity
					else
						alien = entity
					end
				elseif entity.has_extra_data and entity.extra_data.resimulated then
					other_unit = entity
				end
			end
		end

		if not alien then
			if simulated then return "Alien already synthesized" else return "Docked alien is required to synthesize" end
		end

		if other_unit then
			local component, incompatible_component
			for s=1,other_unit.socket_count do
				local socket_comp = other_unit:GetComponent(s)
				if socket_comp then
					local size = data.all[socket_comp.id] and data.all[socket_comp.id].attachment_size
					if size == "Small" or size == "Internal" then component = true else incompatible_component = true end
				end
			end

			if not component then return "Other unit has no components equipped" end
			if not component and incompatible_component then return "Other unit contains components unsuitable for synthesis" end
		end

		return "Missing ingredient"
	end,
	on_update = function(self, comp, cause)
		local owner, alien, other_entity = comp.owner
		for _,slot in ipairs(owner.slots) do
			local entity = slot.entity
			if entity and not (entity.has_extra_data and entity.extra_data.resimulated) then
				if entity.def.race == "alien" then
					alien = entity
				else
					other_entity = entity
				end
			end
		end
		if not alien and not other_entity then comp:SetRegister(1, nil) comp:FlagRegisterError(1, false) return end
		if not alien or not other_entity then comp:SetRegister(1, nil) comp:FlagRegisterError(1) return end

		local synthesis_cost, synthesis_reserved, have_s_component, synthesis_reserve_ok = 0, 0
		for s=1,other_entity.socket_count do
			local socket_comp = other_entity:GetComponent(s)
			local socket_size = socket_comp and socket_comp.def.attachment_size
			if socket_size == "Small" and not have_s_component then -- Only store a single S component
				synthesis_cost, have_s_component = synthesis_cost + self.synthesis_s_comp_cost, socket_comp
			elseif socket_size == "Internal" then
				synthesis_cost = synthesis_cost + self.synthesis_i_comp_cost
			end
		end
		if synthesis_cost == 0 then comp:SetRegister(1, nil) comp:FlagRegisterError(1) return end

		if cause & (CC_FINISH_WORK|CC_REFRESH) ~= 0 then
			for i=1,999 do
				local s = comp:GetProcessConsumeSlot(i)
				if not s then break end
				synthesis_reserved = synthesis_reserved + s:CountConsumeAmount(comp)
			end
		end

		if cause & CC_REFRESH == CC_REFRESH and synthesis_reserved == synthesis_cost then
			return comp:SetStateContinueWork() -- just rechecking, continue work
		end

		if cause & CC_FINISH_WORK == CC_FINISH_WORK and synthesis_reserved == synthesis_cost then
			comp:FulfillProcess() -- consume synthesis material
			Map.Defer(function()
				if not alien.exists or not other_entity.exists then return end
				local done_s_component
				for s=1,other_entity.socket_count do
					local socket_comp = other_entity:GetComponent(s)
					local socket_size = socket_comp and socket_comp.def.attachment_size
					if socket_size == "Small" and not done_s_component then -- Only pass a single S component
						alien:AddComponent(socket_comp.id, "hidden", socket_comp:Destroy())
						done_s_component = true
					elseif socket_size == "Internal" then
						alien:AddComponent(socket_comp.id, "hidden", socket_comp:Destroy())
					end
				end
				other_entity:Destroy(owner)
				alien:SetRegister(FRAMEREG_GOTO, nil)
				alien:Undock()
				alien.extra_data.resimulated = alien.id
			end)
			comp.faction:UnlockAchievement("REFORMED")
			return comp:SetStateSleep(1) -- recheck if there is more to do
		end

		local can_make, missing_register = comp:PrepareConsumeProcess( { [self.synthesis_material] = synthesis_cost } )
		comp:SetRegister(1, missing_register)
		if not can_make then -- Missing ingredient
			comp:FlagRegisterError(1)
			return comp:SetStateSleep()
		end
		return comp:SetStateStartWork(self.duration, true)
	end,
})

local c_resimulator_all_cores = {
	"c_blight_ac",
	"c_human_ac",
	"c_virus_ac",
	"c_alien_ac",
}

local function c_resimulator_can_make(compdef, comp, ed, recipe)
	-- check we have enough goop
	if recipe.use and (ed[recipe.use] or -1) < (recipe.amount or 1) then
		return false
	end

	-- check we dont have too much goop
	if recipe.fill and (ed[recipe.fill] or 0) + (recipe.amount or 1) > 100 then
		return false
	end

	-- check for a required core
	if recipe.requires then
		if not comp.owner:FindComponent(recipe.requires, true) then
			return false
		end
	elseif recipe.require_all_cores then
		for _,v in ipairs(c_resimulator_all_cores) do
			if not comp.owner:FindComponent(v, true) then
				return false
			end
		end
	end

	-- check if there's a can_make function on the recipe
	if recipe.can_make and not recipe.can_make(comp) then
		return false
	end

	return true
end

local function UIResimulatorEvent(entity)
	Notification.Add("world_events", "warning", "Powerful Enemy Warning", "Approach with EXTREME caution", {
		tooltip = "World Event",
		on_click = entity and function() View.JumpCameraToEntities(entity) end,
	})
	Notification.Warning("Powerful Enemy Warning, EXTREME CAUTION ADVISED !!!")
end

function c_resimulator:on_update(comp, cause)
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - has_power: " .. tostring(comp.owner.has_power))
	local owner, ed = comp.owner, comp.extra_data
	local active_id = ed.recipe
	if active_id then
		local recipe = resim_recipes[active_id]
		if (cause & (CC_FINISH_WORK) == CC_FINISH_WORK) and recipe and c_resimulator_can_make(self, comp, ed, recipe) then
			local recipe_to, recipe_use, recipe_fill, recipe_event = recipe.to, recipe.use, recipe.fill, recipe.event
			if recipe_to and data.frames[recipe_to] then
				local faction, location = comp.faction, owner.placed_location
				local consume_slot1, consume_slot2 = comp:GetProcessConsumeSlot(1), comp:GetProcessConsumeSlot(2)
				local convert_unit = consume_slot1 and not consume_slot2 and consume_slot1.entity -- can convert single ingredient
				if convert_unit then comp:CancelProcess() end
				Map.Defer(function()
					if convert_unit then
						local unit_bp = MakeBlueprintFromEntity(convert_unit, false, false, true) -- copy settings
						unit_bp.powered_down = false -- switch to powered on again
						if unit_bp.regs then unit_bp.regs[-FRAMEREG_GOTO] = nil end -- clear goto register
						Map.RecreateEntity(convert_unit, recipe_to)
						ApplyBlueprintToEntity(convert_unit, unit_bp) -- apply settings (register, logistics, locks)
					else
						convert_unit = Map.CreateEntity(faction, recipe_to)
					end
					convert_unit:Place(owner.exists and owner.is_placed and owner or location)
					convert_unit.extra_data.resimulated = active_id
				end)
			end
			if recipe_use then
				if recipe.amount then
					ed[recipe_use] = ed[recipe_use] - (recipe.amount or 0)
					if recipe_use == "bb" then
						comp:SetRegister(1, { id = "robot_datacube", num = ed.bb })
					elseif recipe_use == "hb" then
						comp:SetRegister(2, { id = "human_datacube", num = ed.hb })
					elseif recipe_use == "yb" then
						comp:SetRegister(3, { id = "virus_research_data", num = ed.yb })
					elseif recipe_use == "rb" then
						comp:SetRegister(4, { id = "blight_datacube", num = ed.rb })
					elseif recipe_use == "ab" then
						comp:SetRegister(5, { id = "alien_datacube", num = ed.ab })
					end
				end
			end
			if recipe_fill then
				ed[recipe_fill] = (ed[recipe_fill] or 0) + (recipe.amount or 0)
				if recipe_fill == "bb" then
					comp:SetRegister(1, { id = "robot_datacube", num = ed.bb })
				elseif recipe_fill == "hb" then
					comp:SetRegister(2, { id = "human_datacube", num = ed.hb })
				elseif recipe_fill == "yb" then
					comp:SetRegister(3, { id = "virus_research_data", num = ed.yb })
				elseif recipe_fill == "rb" then
					comp:SetRegister(4, { id = "blight_datacube", num = ed.rb })
				elseif recipe_fill == "ab" then
					comp:SetRegister(5, { id = "alien_datacube", num = ed.ab })
				end

				if ed["bb"] == 100 and ed["yb"] == 100 and ed["rb"] == 100 and ed["hb"] == 100 and ed["ab"] == 100 then
					-- trigger event
					local hx, hy = owner.location.x, owner.location.y
					-- get closest hidden area to unit with a bit of random
					local loc_x, loc_y = owner.faction:FindClosestHiddenTile(hx+math.random(-25, 25), hy+math.random(-25, 25), 25000, true)
					if not loc_x then loc_x, loc_y = Map.GetUndiscoveredLocation() end
					local faction= comp.faction
					Map.Defer(function()
						local nme = Map.CreateEntity(GetBugsFaction(), "f_charcharosaurus1")
						nme:Place(loc_x, loc_y)
						--nme:SetRegisterEntity(FRAMEREG_GOTO, owner)
						nme.faction:SetTrust(faction, "ENEMY", true)
						faction:RunUI(UIResimulatorEvent, nme)
					end)

					ed["bb"] = 0
					ed["yb"] = 0
					ed["rb"] = 0
					ed["hb"] = 0
					ed["ab"] = 0
					comp:SetRegister(1)
					comp:SetRegister(2)
					comp:SetRegister(3)
					comp:SetRegister(4)
					comp:SetRegister(5)
				end
			end
			if recipe_event then
				recipe_event(owner)
			end
			local generate_component_slot
			if data.components[recipe_to] then
				for _,slot in ipairs(owner.slots) do
					if slot:CountGenerateAmount(comp) == 1 then
						generate_component_slot = slot
						break
					end
				end
			end
			comp:FulfillProcess()
			if generate_component_slot then
				-- generated a new component, mark it as resimulated
				generate_component_slot.extra_data.resimulated = active_id
			end
		elseif comp.is_working then
			if not owner.has_power then ed.recipe = nil return end
			return comp:SetStateContinueWork()
		end
		ed.recipe = nil -- clear
	end

	for i,v in ipairs(owner.slots) do
		local slot_id = v.id
		local recipe = slot_id and resim_recipes[slot_id]
		if recipe and c_resimulator_can_make(self, comp, ed, recipe) then
			if not owner.has_power then return end
			local outputs = recipe.to and (not data.frames[recipe.to] and { [recipe.to] = 1 } or nil)
			if comp:PrepareProduceProcess({ [slot_id] = 1 }, outputs) then
				ed.recipe = slot_id
				return comp:SetStateStartWork(recipe.time)
			end
		end
	end
end

data.update_mapping.c_robot_resim_comp = "c_resimulator_large"
data.update_mapping.c_human_resim_comp = "c_human_ac"
data.update_mapping.c_virus_resim_comp = "c_virus_ac"
data.update_mapping.c_blight_resim_comp = "c_blight_ac"
data.update_mapping.c_alien_resim_comp = "c_alien_ac"
data.update_mapping.resimulator_core = "c_resimulator_core"

Comp:RegisterComponent("c_resimulator_core", {
	attachment_size = "Internal", race = "robot", index = 1061, name = "Resimulator Core",
	desc = "An empty socketable core that interfaces with the Resimulator. Useless by itself.",
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ silica = 10, blight_crystal = 10 }, { c_data_analyzer = 150 }),
	texture = "Main/textures/icons/components/resimulator_core.png",
})

c_resimulator:RegisterComponent("c_resimulator_large", {
	attachment_size = "Large", race = "robot", index = 1061, name = "Robot Re-Simulation Component",
	desc = "Large re-simulation component",
	texture = "Main/textures/icons/components/ResimulatorRobot_L.png",
	production_recipe = CreateProductionRecipe({ circuit_board = 20, hdframe = 20, silicon = 20, crystal_powder = 20 }, { c_assembler = 150 }),
	visual = "v_dataanalyzer_L_Robot",
	on_add = ReSimulatorModuleOnAdd,
	on_remove = ReSimulatorModuleOnRemove,
})

----- extractor -----
c_miner:RegisterComponent("c_extractor", {
	attachment_size = "Medium", race = "human", index = 3001, name = "Laser Extractor",
	texture = "Main/textures/icons/components/Component_LaserExtractor_01_M.png",
	desc = "Laser that mines <hl>laterite</> and <hl>obsidian</>",
	power = -20,
	visual = "v_laserextractor_01_m",
	miner_effect = "fx_extractor",
	production_recipe = CreateProductionRecipe({ micropro = 1, transformer = 1, smallreactor = 1 }, { c_advanced_assembler = 40, c_human_factory_robots = 30 }),
	on_remove = on_remove_clear_extra_data_keep_resimulated,
})

-- Total boost calculations for components such as Blight Extractor and Blight Magnifier
local function get_work_time(comp, base_work_time, is_blight_boost)
	local reg_owner = comp.owner
	local faction_boost = reg_owner and (reg_owner.faction.component_boost-100) or 0
	local eff_boost = reg_owner and ((reg_owner.def.component_boost or 0) + (SumModuleBoosts(reg_owner, "c_moduleefficiency") or 0) + faction_boost)

	if comp and comp.socket_index > 0 then
		local b = GetAttachmentSize(comp.owner.visual_def.sockets[comp.socket_index][2]) > GetAttachmentSize(comp.def.attachment_size)
		eff_boost = eff_boost + (b and 50 or 0)
	end
	local work_time = base_work_time
	if is_blight_boost and Map.GetBlightnessDelta(comp, -1) >= 0 then work_time = work_time // 2 end
	local tick_boost = 0
	if (eff_boost and eff_boost ~= 0) or work_time ~= base_work_time then tick_boost = (work_time * 100 + 99 + eff_boost) // (100 + eff_boost) end

	return base_work_time / TICKS_PER_SECOND, tick_boost and tick_boost / TICKS_PER_SECOND
end

----- blight_extractor -----
local c_blight_extractor = Comp:RegisterComponent("c_blight_extractor", {
	attachment_size = "Small", race = "blight", index = 2001, name = "Blight Extractor",
	texture = "Main/textures/icons/components/component_blightextractor_01_s.png",
	desc = "Extracts blight gas when placed inside a blighted area",
	power = -10,
	visual = "v_blightextractor_s",
	slots = { gas = 1 },
	production_recipe = CreateProductionRecipe({ reinforced_plate = 5, crystal_powder = 10 }, { c_assembler = 40, c_human_factory = 40 }),
	extracts = "blight_extraction",
	extraction_time = 75,
	activation = "Always",
})

function c_blight_extractor:get_ui(comp)
	local function set_reg(w, id, hide_num)
		if id then w.warning.hidden = true w.extracting.image = id else w.warning.hidden = false w.extracting.image = data.values.v_blight.texture end
		w.numtxt.hidden = hide_num
	end

	return UI.New([[
		<Box padding=4 bg=reg_base_ro>
			<Canvas>
				<Image id=extracting valign=center width=48 height=48/>
				<Box id=numbox dock=bottom-left margin_left=1 margin_bottom=1 blocking=false bg=label_left color=ui_bg>
					<Text id=numtxt text="x2" hidden=true size=10 margin_left=2 margin_right=3/>
				</Box>
				<Image id=warning x=4 y=4 image=icon_small_warning color=yellow dock=bottom-right hidden=true/>
			</Canvas>
		</Box>]], {
		update = function(w)
			local blightdelta = Map.GetBlightnessDelta(comp, -1)
			if blightdelta < -0.02 then set_reg(w, nil, true)
			elseif blightdelta >= 0  then set_reg(w, data.all[comp.def.extracts].texture, false)
			else set_reg(w, data.all[comp.def.extracts].texture, true) end
		end,

		tooltip = function(w)
			w.tt = UI.New("<Box bg=popup_box_bg blur=true padding=12><HorizontalList child_align=center child_padding=10><Reg entity={entity} bg=card_box_bg def_id={def_id} num={num}/><Text size=12 text={txt}/></HorizontalList></Box>", {
				update = function(w)
					local blightdelta = Map.GetBlightnessDelta(comp, -1)
					if blightdelta < -0.02 then
						w.def_id = data.values.v_blight.id
						w.txt = "Must be placed inside the blight"
					else
						w.def_id = comp.def.extracts
						local work_name, work_time, work_time_boost = data.all[comp.def.extracts].name, get_work_time(comp, self.extraction_time, true)
						if work_time_boost == 0 or work_time == work_time_boost then
							w.txt = L("<bl>%s</>\n<hl>%.1f</>/min (<hl>%.1f</>s)", (work_name or "Unknown"), 60.0/work_time, work_time)
						else
							w.txt = L("<bl>%s</>\n<gl>%.1f</>/min (<hl>%.1f</>→<gl>%.1f</>s)", (work_name or "Unknown"), 60.0/work_time_boost, work_time, work_time_boost)
						end
					end
				end,
				destruct = function()
					w.tt = nil
				end
			})[1]
			w:update()
			return w.tt.parent
		end,
	})
end

function c_blight_extractor:on_update(comp, cause)
	-- check if we are in the blight
	local blightdelta = Map.GetBlightnessDelta(comp, -1)
	if blightdelta < -0.02 then
		comp:CancelProcess()
		comp:StopEffects()
		return comp:SetStateSleep() -- wait to be moved
	end

	if cause & CC_REFRESH == CC_REFRESH then
		return comp:SetStateContinueWork() -- just rechecking, continue work
	end

	local is_finish_extraction = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	if is_finish_extraction then
		comp:FulfillProcess()
	end

	if not comp:PrepareGenerateProcess( { [self.extracts] = 1 } ) then
		comp:StopEffects()
		return comp:SetStateSleep() -- wait until not full
	end

	if comp.owner.is_placed then comp:PlayWorkEffect("fx_blight_extract") end

	-- start working_miner with refresh to check if we're still in the blight
	local extraction_time = self.extraction_time
	if blightdelta >= 0 then extraction_time = extraction_time // 2 end
	return comp:SetStateStartWork(extraction_time, true)
end

c_fabricator:RegisterComponent("c_mission_human_aicenter", {
	attachment_size = "Hidden", race = "human", index = 3009, name = "AI Research Center",
	texture = "Main/textures/icons/human/human_building_communication_01.png",
	desc = "Multifaceted hardware and equipment for researching enigmatic technologies",
	production_effect = "fx_uplink",
	production_recipe = false,
	power = -100,
})


c_fabricator:RegisterComponent("c_alien_factory_robots", {
	attachment_size = "Large", race = "alien", index = 5001, name = "Alien Factory",
	texture = "Main/textures/icons/components/Component_Alien_Factory_01_L.png",
	desc = "A component formed from Alien and Robot technology, capable of producing Alien constructs and devices",
	slots = { anomaly = 2 },
	visual = "v_alienfactory_01_l",
	production_effect = "fx_alien_liquid",
	power = -500,
	production_recipe = CreateProductionRecipe({ obsidian_brick = 20, hdframe = 10, blight_plasma = 10, }, { c_advanced_assembler = 150, c_reforming_pool = 100, c_reforming_pool_comp = 100 }),
})

local c_virus_cure = Comp:RegisterComponent("c_virus_cure", {
	attachment_size = "Internal", race = "virus", index = 4061, name = "Virus Cure",
	desc = "Protection from the virus for nearby units and buildings",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/virus_cure.png",
	-- production_recipe = CreateProductionRecipe({ blight_crystal = 10, energized_plate = 2, bug_carapace = 1 }, { c_assembler = 40, c_human_factory = 60, }),
	production_recipe = CreateProductionRecipe({ reinforced_plate = 2, bug_carapace = 5 }, { c_assembler = 40, c_human_factory = 60, }),
	trigger_radius = 3,
	trigger_channels = "bot|building",
})

function c_virus_cure:on_add(comp)
	local virus_comp = comp.owner:FindComponent("c_virus")
	if virus_comp ~= nil then
		virus_comp:Destroy()
	end
end

function c_virus_cure:on_trigger(comp, other_entity)
	local virus_comp = other_entity:FindComponent("c_virus")
	if virus_comp ~= nil then
		virus_comp:Destroy()
		other_entity:PlayEffect("fx_digital")
		other_entity.powered_down = false

		-- check if its a glitch bot
		if other_entity.id == "f_exploreable_bot_glitch" then
			-- trigger quest
			FactionCount("cured_anomaly", true, comp.faction)
			other_entity:AddComponent("c_anomaly_go_home", "hidden")
		end

		if comp:PrepareGenerateProcess({ virus_source_code = 1 }) then
			comp:FulfillProcess()
		end

		-- also cure docked units
		for _,v in ipairs(other_entity.slots or {}) do
			local vir = v.entity and v.entity:FindComponent("c_virus")
			if vir then
				vir:Destroy()
				v.entity.powered_down = false
			end
		end
	end
end

----- large_storage -----
Comp:RegisterComponent("c_large_storage", {
	attachment_size = "Large", race = "robot", index = 1021, name = "Large Storage",
	texture = "Main/textures/icons/components/Component_LargeStorage_01_L.png",
	desc = "A larger storage component with <hl>20 slots</>",
	visual = "v_storage_l",
	slots = { storage = 20, },
	production_recipe = CreateProductionRecipe({ hdframe = 5, optic_cable = 10, fused_electrodes = 1 }, { c_advanced_assembler = 30 }),
})

----- virus_container -----
Comp:RegisterComponent("c_virus_container_i", {
	attachment_size = "Internal", race = "virus", index = 4021, name = "Internal Virus Containment",
	texture = "Main/textures/icons/components/component_viruscontainer_01_i.png",
	desc = "Container for holding virus infected items",
	power = 0,
	visual = "v_generic_i",
	slots = { virus = 3 },
	production_recipe = CreateProductionRecipe({ reinforced_plate = 1, blight_crystal = 2 }, { c_advanced_assembler = 40, c_human_aicenter = 40 }),
})

----- anomaly_container -----
Comp:RegisterComponent("c_anomaly_container_i", {
	attachment_size = "Internal", race = "alien", index = 5021, name = "Internal Anomaly Containment",
	texture = "Main/textures/icons/components/component_anomaly_container_i.png",
	desc = "Container for holding anomaly items",
	power = 0,
	visual = "v_generic_i",
	slots = { anomaly = 3 },
	production_recipe = CreateProductionRecipe({ microscope = 1, blightbar = 1 }, { c_human_factory = 10, c_human_factory_robots = 20, c_alien_factory_robots = 30 }),
})

Comp:RegisterComponent("c_anomaly_lattice", {
	attachment_size = "Internal", race = "alien", index = 5022, name = "Anomaly Lattice",
	texture = "Main/textures/icons/components/component_anomaly_lattice.png",
	desc = "Crystalline framework for storing anomaly energies",
	power = 0,
	visual = "v_generic_i",
	slots = { anomaly = 8 },
	production_recipe = CreateProductionRecipe({ blight_crystal = 2, crystalized_obsidian = 2 }, { c_reforming_pool = 30, c_reforming_pool_comp = 30 }),
})

----- unit_teleporter -----
local c_unit_teleport = Comp:RegisterComponent("c_unit_teleport", {
	attachment_size = "Large", race = "alien", index = 5041, name = "Unit Teleporter",
	texture = "Main/textures/icons/components/Component_UnitTeleporter_01_L.png",
	desc = "Transports units over a great distance. Interact with the teleporter to dock the unit you wish to teleport. Can only link and teleport to another teleporter.",
	visual = "v_teleporter_01_l",
	power = -30,
	teleport_cost = 0,
	production_recipe = CreateProductionRecipe({ hdframe = 20, obsidian_brick = 20, cpu = 10, phase_leaf = 10 }, { c_alien_factory_robots = 80 }), -- c_human_factory = 40, c_human_factory_robots = 80
	activation = "OnComponentItemSlotChange",
	slots = { garage = 1 },
	registers = {
		{ tip = "Target location", ui_apply = "Set Teleport Target", ui_icon = "icon_context" },
	},
	get_ui = true,
})

function c_unit_teleport:on_update(comp, cause)
	local work_finished = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	if not work_finished and comp.is_working then return comp:SetStateContinueWork() end

	for i,v in ipairs(comp.slots) do
		local docked_entity = v.entity
		local target_entity = docked_entity and comp:GetRegisterEntity(1)
		local valid_faction = target_entity and target_entity.faction:GetTrust(comp.faction) == "ALLY"

		if valid_faction and (target_entity:FindComponent(self.id) or self.id == "c_alien_teleporter") and target_entity.is_on_map then
			if work_finished then
				-- remove docked item, undock at destination
				Map.Defer(function()
					if not docked_entity.exists or not docked_entity.is_docked or not target_entity.exists then return end
					docked_entity:Place(target_entity)
					if not docked_entity:RegisterIsLink(FRAMEREG_GOTO) then docked_entity:SetRegister(FRAMEREG_GOTO) end
					docked_entity.faction:RunUI(function()
						if View.IsSelectedEntity(comp.owner) or View.IsSelectedEntity(docked_entity) then
							View.JumpCameraToEntities(docked_entity)
						end
					end)
				end)
				return
			end
			-- start teleporting
			if self.attachment_size ~= "Hidden" then comp:PlayEffect("fx_unit_teleport", "fx") end
			return comp:SetStateStartWork(1, false) -- teleport time based on distance?
		elseif target_entity and target_entity.id == "f_explorable_simulator" and self.id == "c_alien_teleporter" then
			if work_finished then
				Map.Defer(function()
					if not docked_entity.exists or not docked_entity.is_docked then return end
					local the_simulator = data.explorables.alien_a:PlaceTheSimulator(docked_entity.faction)
					docked_entity.faction:UnlockAchievement("THE_SIMULATOR")
					docked_entity:Place(the_simulator)
					if not docked_entity:RegisterIsLink(FRAMEREG_GOTO) then docked_entity:SetRegister(FRAMEREG_GOTO) end
					docked_entity.faction:RunUI(function()
						if View.IsSelectedEntity(comp.owner) or View.IsSelectedEntity(docked_entity) then
							View.JumpCameraToEntities(docked_entity)
						end
					end)
				end)
				return
			end
			-- start teleporting
			return comp:SetStateStartWork(1, false) -- teleport time based on distance?
		end

		-- cant teleport, undock
		if docked_entity then Map.Defer(function() docked_entity:Undock() end) end
	end
end

c_unit_teleport:RegisterComponent("c_alien_teleporter", {
	attachment_size = "Hidden", race = "alien", index = 5024, name = "Alien Teleporter",
	texture = "Main/textures/icons/alien/alienbuilding_teleporter.png",
	production_recipe = false,
})

c_unit_teleport:RegisterComponent("c_virus_teleporter", {
	attachment_size = "Hidden", race = "virus", index = 4061, name = "Virus Teleporter",
	texture = "Main/textures/icons/frame/virus_warp_point.png",
	desc = "A warp bridge that temporarily allows units to transport across large distances using virus teleporters. Virus Source Code can be used to strengthen the connection.",
	production_recipe = false,
	power = 0,
	slots = { garage = 1, virus = 1, bughole = 1 },
	registers = {{ tip = "Time", read_only = true }},
	on_add = function(self, comp)
		comp:LinkRegisterFromRegister(FRAMEREG_VISUAL, 1)
		if not comp.has_extra_data then comp.owner:Destroy() end -- maybe due to Deployer?
	end,
	on_remove = function(self, comp)
		local spawner = comp.extra_data.spawner
		if spawner and spawner.exists then spawner.def:close_warp(spawner) end
		comp.extra_data = nil
	end,
	on_update = function(self, comp, cause)
		local spawner = comp.extra_data.spawner
		if not spawner or not spawner.exists then -- shouldn't happen (c_virus_teleporter:on_remove should handle this)
			comp.owner:Destroy()
			return
		end
		local sleep_ticks = spawner.def:tick_time(spawner, comp)
		local slot = comp.owner:FindSlot("virus_source_code", 1)
		if slot then
			local expire = spawner.extra_data.expire
			local remain_ticks = expire - Map.GetTick()
			if remain_ticks < 4500 then
				slot:RemoveStack(1, true)
				expire = expire + (30 * TICKS_PER_SECOND)
				spawner.extra_data.expire = expire
			end
			comp:SetStateSleep(sleep_ticks or TICKS_PER_SECOND)
		else
			if sleep_ticks then comp:SetStateSleep(sleep_ticks) end
		end
		if (cause & (CC_CHANGED_ITEMSLOT_AMOUNT|CC_FINISH_WORK)) ~= 0 then
			-- This might call SetStateStartWork and overwrite SetStateSleep, but that's fine as long as the work time is less than a second
			c_unit_teleport.on_update(self, comp, cause)
		end
	end,
})
-------------------------------

local c_repairport = Comp:RegisterComponent("c_repairport", {
	attachment_size = "Medium", race = "human", index = 3022, name = "Repair Garage",
	texture = "Main/textures/icons/components/Component_RepairPort_01_M.png",
	desc = "Allows repair of damaged units",
	power = -2,
	visual = "v_repairport_01_m",
	activation = "OnComponentItemSlotChange",
	slots = { garage = 1 },
	production_recipe = CreateProductionRecipe({ engine = 1, aluminiumrod = 5 }, { c_human_factory = 20, c_human_factory_robots = 40 }),
	action_tooltip = "Repair Frame",
	repair_amount = 10,
	repair_time = 20,
})

function c_repairport:on_update(comp, cause)
	if cause & (CC_FINISH_WORK) == CC_FINISH_WORK then
		for i,v in ipairs(comp.slots) do
			local docked_entity = v.entity
			if docked_entity then
				--print("restoring docked item health")
				docked_entity.health = math.min(docked_entity.health + self.repair_amount, docked_entity.max_health)
			end
		end
	end

	for i,v in ipairs(comp.slots) do
		local docked_entity = v.entity
		if docked_entity then
			if docked_entity.is_damaged then
				return comp:SetStateStartWork(self.repair_time, false)
			end
		end
	end
	return comp:SetStateSleep()
end

c_repairport:RegisterComponent("c_transport_repair", {
	attachment_size = "Hidden", race = "human", index = 3999, name = "Repair Transport",
	slots = { garage = 10 },
	production_recipe = false,
	repair_amount = 10,
	repair_time = 20,
	power = -2,
})

c_repairport:RegisterComponent("c_bunker_repair_2", {
	attachment_size = "Hidden", race = "human", index = 3999, name = "Bunker Repair Facilities",
	slots = { garage = 2 },
	production_recipe = false,
	repair_amount = 20,
	repair_time = 20,
	power = -10,
})

c_repairport:RegisterComponent("c_bunker_repair_4", {
	attachment_size = "Hidden", race = "human", index = 3999, name = "Bunker Repair Facilities",
	slots = { garage = 4 },
	production_recipe = false,
	repair_amount = 30,
	repair_time = 10,
	power = -20,
})

local c_alien_deconstructor = Comp:RegisterComponent("c_alien_deconstructor", {
	attachment_size = "Hidden", race = "alien", index = 5018, name = "Alien Deconstructor",
	texture = "Main/textures/icons/alien/alienbuilding_storage.png",
	desc = "Allows deconstruction of Alien units",
	visual = "v_virus_robot_jammer",  --this is Hidden so no need for v_virus_robot_jammer
	power = 0,
	deconstruct_time = 40,
	activation = "OnComponentItemSlotChange",
	slots = { garage = 2 },
	action_tooltip = "Deconstruct Alien Frame",
	registers = {
		{ read_only = true, tip = "Alien unit being deconstructed" },
	},
	get_ui = true,
})

function c_alien_deconstructor:get_reg_error(comp)
	for i,slot in ipairs(comp.slots) do
		local docked_entity = slot.entity
		if docked_entity and slot.unreserved_stack == 1 then
			local docked_def = docked_entity.def
			local docked_alien_recipe = docked_def and docked_def.race == "alien" and docked_def.production_recipe
			local recycle_ingredients = docked_alien_recipe and docked_alien_recipe.ingredients
			if recycle_ingredients then
				return "Not enough inventory space for deconstructed ingredients"
			end
		end
	end
	return "Invalid Target"
end

function c_alien_deconstructor:on_update(comp, cause)
	local work_finished = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	if not work_finished and comp.is_working then return comp:SetStateContinueWork() end
	if work_finished then comp:FulfillProcess() end

	local had_invalid
	for i,slot in ipairs(comp.slots) do
		local docked_entity = slot.entity
		if docked_entity and slot.unreserved_stack == 1 then
			local docked_def = docked_entity.def
			local docked_alien_recipe = docked_def and docked_def.race == "alien" and docked_def.production_recipe
			local recycle_output = docked_alien_recipe and docked_alien_recipe.ingredients
			if recycle_output then
				if not recycle_output.anomaly_heart then
					recycle_output = Tool.Copy(recycle_output)
					recycle_output.anomaly_heart = 1
					local energized_artifact_num = recycle_output.energized_artifact or 0
					if energized_artifact_num > 0 then
						recycle_output.energized_artifact = nil
						recycle_output.alien_artifact = energized_artifact_num
					end
				end
				local was_powered_down = docked_entity.powered_down
				local success = comp:PrepareProduceProcess({ [docked_entity.id] = 1 }, recycle_output)
				comp:SetRegisterEntity(1, docked_entity)
				comp:FlagRegisterError(1, not success)
				if success then
					return comp:SetStateStartWork(self.deconstruct_time)
				end
				comp:CancelProcess() -- not enough space for output, cancel reserve of entity
				docked_entity.powered_down = was_powered_down -- restore (process turns off entitites)
				return comp:SetStateSleep(10) -- wait for inventory space becomes available
			end
			had_invalid = docked_entity
		end
	end
	comp:SetRegisterEntity(1, had_invalid)
	comp:FlagRegisterError(1, had_invalid ~= nil)
end

----- satellite_launcher
local c_satellite_launcher = c_fabricator:RegisterComponent("c_satellite_launcher", {
	attachment_size = "Hidden", race = "robot", index = 1999, name = "Satellite Launcher",
	desc = "Launches a satellite",
	texture = "Main/textures/icons/components/satellite_launcher.png",
	visual = "v_empty_inventory",
	power = -20,
	production_recipe = false,
	slots = { satellite = 1, },
	behavior_activate = function(self, comp)
		return EntityAction.LaunchAmac(comp.owner, { comp = comp }) ~= false
	end,
})

function c_satellite_launcher:get_ui(comp)
	local faction = comp.faction
	return UI.New([[<Box width=56 height=56 padding=4><Canvas>
						<Button id=launchbtn fill=true icon=icon_small_satellite on_click={launch}/>
						<Text id=timer dock=center size=20/>
					</Canvas></Box>]], {
		update = function(v)
			local item_slot = comp:GetSlot(1)
			local docked_satellite = item_slot and item_slot.entity
			local satellite = not docked_satellite and item_slot.reserved_entity
			if docked_satellite or not satellite then
				v.launchbtn.disabled = not docked_satellite
				v.launchbtn.tooltip = docked_satellite and "Launch Satellite" or "No Satellite to Launch"
				v.timer.text = ""
			else
				local travel_time, travel_tick = satellite.def.travel_time, Map.GetTick() - (satellite.extra_data.launched_at or 0)
				local remain_time = math.ceil(((travel_time * 2) - travel_tick) / TICKS_PER_SECOND)
				v.launchbtn.disabled = true
				v.launchbtn.tooltip = travel_tick < travel_time and "Satellite travelling to Mothership" or "Satellite returning to planet"
				v.timer.text = string.format("%d", math.max(0, remain_time))
			end
		end,
		launch = function()
			if not faction.has_blight_shield then return MessageBox("Atmospheric interference is too high. Find a way to reduce the influence of the blight to allow launching of satellites.", "Blight Interference") end
			Action.SendForEntity("LaunchAmac", comp.owner, { comp = comp })
		end,
	})
end

local c_satellite = Comp:RegisterComponent("c_satellite", {
	attachment_size = "Hidden", race = "robot", index = 1999, name = "Satellite System",
	texture = "Main/textures/icons/frame/satellite.png",
	visual = "v_empty_inventory",
	power = 0,
	activation = "OnFirstRegisterChange",
	action_tooltip = "Select Dock",
	registers = { { type = "entity", tip = "Landing Pad", ui_icon = "icon_target2", click_action = true, filter = 'entity' } },
	behavior_activate = function(self, comp)
		return EntityAction.LandSatellite(comp.owner) ~= false
	end
})

function c_satellite:can_launch(comp)
	local satellite = comp.owner
	local slot = satellite.docked_slot
	local launcher_comp = slot and slot.component
	return launcher_comp and launcher_comp.def.behavior_activate == c_satellite_launcher.behavior_activate and
		slot.type == satellite.def.slot_type and launcher_comp.faction == satellite.faction
end

function c_satellite:get_landing_slot(comp, check_target)
	-- Find landing slot (also handle launched_by of old saves)
	local satellite = comp.owner
	local target, landing_slot, already_at_target = check_target or comp:GetRegisterEntity(1)
	if not target then local old = satellite.has_extra_data and satellite.extra_data.launched_by target = old and old.exists and old.owner end
	if not target or target.faction ~= comp.faction then return end
	for _,slot in ipairs(target:GetSlotsByType(satellite.def.slot_type)) do
		local docked_entity = (slot.entity or slot.reserved_entity)
		if (docked_entity == satellite or docked_entity == nil) and slot.component and slot.component.def.behavior_activate == c_satellite_launcher.behavior_activate then
			landing_slot = slot
			already_at_target = (docked_entity == satellite)
			if already_at_target then break end
		end
	end
	return landing_slot, already_at_target
end

function c_satellite:find_landing_slot(comp)
	local satellite = comp.owner
	for _,slot in ipairs(satellite.faction:GetSlotsByType(satellite.def.slot_type)) do
		if not slot.entity and not slot.reserved_entity and slot.component and slot.component.def.behavior_activate == c_satellite_launcher.behavior_activate then
			return slot
		end
	end
end

function c_satellite:action_click(comp, widget)
	if not comp.faction.has_blight_shield then return MessageBox("Atmospheric interference is too high. Find a way to reduce the influence of the blight to allow launching of satellites.", "Blight Interference") end
	local satellite = comp.owner
	Notification.Warning("Select Dock")
	View.StartCursorChooseEntity(
		function(target) -- success
			View.StopCursor()
			if not target or not satellite.exists then return end
			local already_set = comp:GetRegisterEntity(1) == target
			if c_satellite:get_landing_slot(comp, target) and not already_set then
				Notification.Warning(L("Selected %s", (target and (target.visual_def.explorable_name or target.def.name) or "None")))
				Action.SendForEntity("SetRegister", satellite, { comp = comp, reg = { entity = target } })
			else
				Notification.Warning(already_set and "Item already exists on unit or building" or L("No space in inventory for %s", satellite.def.name))
			end
		end,
		function() Notification.Warning("Aborted") end
	)
end

function c_satellite:get_ui(comp)
	return UI.New([[<Box width=56 height=56 padding=4><Canvas>
						<Button id=btn fill=true icon=icon_small_satellite on_click={launchland}/>
						<Text id=timer dock=center size=20/>
					</Canvas></Box>]], {
		update = function(v)
			local satellite = comp.owner
			if satellite.is_docked then
				local can_launch = c_satellite:can_launch(comp)
				v.btn.disabled = not can_launch
				v.btn.tooltip = can_launch and "Launch Satellite" or "Landed"
				v.timer.text = ""
			else
				local ed = satellite.has_extra_data and satellite.extra_data
				local travel_time, travel_tick = satellite.def.travel_time, (Map.GetTick() - (ed and ed.launched_at or 0))
				if travel_tick > (travel_time * 2) or (travel_tick > travel_time and not (ed.landing_slot and ed.landing_slot.exists) and not c_satellite:get_landing_slot(comp)) then
					v.btn.disabled = false
					v.btn.tooltip = "Land Satellite"
					v.timer.text = ""
				else
					v.btn.disabled = true
					v.btn.tooltip = travel_tick < travel_time and "Satellite travelling to Mothership" or "Satellite returning to planet"
					v.timer.text = string.format("%d", math.ceil(((travel_time * 2) - travel_tick) / TICKS_PER_SECOND))
				end
			end
		end,
		launchland = function()
			if not comp.faction.has_blight_shield then return MessageBox("Atmospheric interference is too high. Find a way to reduce the influence of the blight to allow launching of satellites.", "Blight Interference") end
			local satellite = comp.owner
			if satellite.is_docked then
				Action.SendForEntity("LaunchAmac", satellite.docked_garage, { comp = satellite.docked_slot.component })
			elseif c_satellite:get_landing_slot(comp) or c_satellite:find_landing_slot(comp) then
				Action.SendForEntity("LandSatellite", satellite)
			else
				Notification.Error("No AMAC available for landing")
			end
		end,
	})
end

function c_satellite:on_update(comp, cause)
	local target, satellite, landing_slot, already_at_target = comp:GetRegisterEntity(1), comp.owner
	if target then landing_slot, already_at_target = c_satellite:get_landing_slot(comp, target) end
	comp:FlagRegisterError(1, not landing_slot and not comp:RegisterIsEmpty(1))

	local is_docked = satellite.is_docked
	if landing_slot and is_docked and not already_at_target and c_satellite:can_launch(comp) then
		-- LaunchAmac sets reserved_entity and schedules SatelliteJourney
		EntityAction.LaunchAmac(satellite.docked_garage, { comp = satellite.docked_slot.component }, landing_slot)
	elseif landing_slot and not is_docked then
		local ed, satellite_def = satellite.extra_data, satellite.def
		local expect_launched_at = Map.GetTick() - satellite_def.travel_time * 2
		if not ed.launched_at or ed.launched_at < expect_launched_at then
			-- Landing has failed some reschedule a landing
			landing_slot.reserved_entity = satellite
			ed.landing_slot, ed.launched_at = landing_slot, expect_launched_at + satellite_def.travel_time
			Map.Delay("SatelliteJourney", satellite_def.travel_time - satellite_def.landing_time, { satellite = satellite, landing_approach = true })
			Map.Delay("SatelliteJourney", satellite_def.travel_time,                              { satellite = satellite, to_the_planet    = true })
		elseif not already_at_target and not (ed.landing_slot and ed.landing_slot.exists) then
			-- Still on journey towards space (off_the_planet delay is scheduled) can freely choose landing target still
			landing_slot.reserved_entity = satellite
		end
	elseif not is_docked and satellite.reserved_redock_entity and not (satellite.extra_data.landing_slot and satellite.extra_data.landing_slot.exists) then
		satellite.reserved_redock_entity = nil -- clear if reserved anywhere
	end
end

function EntityAction.LaunchAmac(entity, arg, set_landing_slot) -- third argument is for c_satellite:on_update
	local faction, launcher_comp = entity.faction, arg.comp
	if not launcher_comp or not launcher_comp.exists or launcher_comp.owner ~= entity then return false end
	if not entity.faction.has_blight_shield then return false end

	local item_slot = launcher_comp:GetSlot(1)
	local satellite = item_slot and item_slot.entity
	local satellite_comp = satellite and satellite:FindComponent("c_satellite")
	if not satellite_comp then return false end

	-- Add repair items (if mothership still needs repair)
	local mothership = not set_landing_slot and satellite.faction.extra_data.mothership
	local repaircomp = mothership and mothership:FindComponent("c_mothership_repair")
	if repaircomp then
		local repair_ed = repaircomp.extra_data
		local repair_item = repair_ed.items
		-- go through the slots of the amac
		for i,slot in ipairs(launcher_comp.owner.slots) do
			if slot.id and not slot.entity then
				-- check if its needed for repair
				local took = 0
				if repair_item[slot.id] then
					local remaining = (repair_ed.max_items or 400)-repair_item[slot.id]
					took = (remaining > 0) and math.min(remaining, slot.unreserved_stack) or 0
					if took > 0 then
						satellite:TransferFrom(launcher_comp.owner, slot.id, took)
					end
				end
			end
		end
	end

	-- Store AMAC into landing target register (overwrite only if different to keep links)
	local landing_entity = set_landing_slot and set_landing_slot.owner or entity
	if satellite_comp:GetRegisterEntity(1) ~= landing_entity then
		satellite_comp:SetRegisterEntity(1, landing_entity)
	end

	-- Undock, start launch timer and play launch effect
	local ed = satellite.extra_data
	satellite:Undock(not set_landing_slot, false)
	if set_landing_slot then set_landing_slot.reserved_entity = satellite end
	ed.launched_at = Map.GetTick()
	Map.Delay("SatelliteJourney", satellite.def.travel_time, { satellite = satellite, off_the_planet = true })
	entity:PlayEffect(satellite.def.launch_effect, "launch")
	--faction:RunUI("OnEntityRecreate", entity, satellite)

	-- Only count if it is the first time launched
	if not ed.has_launched then
		FactionCount("satellites_launched", 1, faction)
		ed.has_launched = true
	end
end

function Delay.SatelliteJourney(arg)
	local satellite = arg.satellite
	local satellite_comp = satellite and satellite.exists and satellite:FindComponent("c_satellite")
	if not satellite_comp then return end -- maybe faction had game over

	-- Check if the satellite didn't land already (Which can happen if instruction "Land"
	-- is called the same tick where Map.Delay "Land" in about to be called)
	if satellite.is_docked then return end

	local faction, off_the_planet = satellite.faction, arg.off_the_planet
	if off_the_planet then
		local ms = faction.extra_data.mothership

		if not ms and Map.IsFrontEnd() then
			for _,slot in ipairs(satellite.slots) do
				if slot.id == "bot_ai_core" and slot.unreserved_stack > 0 then
					slot:RemoveStack(1)
					-- roll credits
					UI.Run(function()
						Game.GetProfile().escaped = true
						Game.NewGame({ scenario = "Main/Credits" })
					end)
					break
				end
			end
		end

		-- unlock robots faction
		if (faction.extra_data.race or "robot") ~= "robot" then
			faction:Unlock("t_robots_discovery")
		end

		local repaircomp = ms and ms:FindComponent("c_mothership_repair")
		if repaircomp then repaircomp.def:consume_items(repaircomp) end

		-- After repair mission try to deliver any other remaining items
		for _,slot in ipairs(satellite.slots) do
			if ms and slot.id and not slot.entity then
				if ms:HaveFreeSpace(slot.id, math.max(slot.unreserved_stack, 1)) then
					ms:TransferFrom(satellite, slot.id, slot.unreserved_stack)
				end
			end
		end
	end

	-- Use landing slot decided at landing approach or get the current target
	local ed = satellite.extra_data
	local landing_slot = ed.landing_slot
	if not landing_slot or not landing_slot.exists then
		landing_slot = c_satellite:get_landing_slot(satellite_comp)
	end

	if not landing_slot then
		-- Landing slot disappeared, clear timer and show notification
		if ed.launched_at then
			faction:RunUI(function()
				Notification.Add("idle_satellite", "Main/textures/icons/frame/satellite.png", "Idle Satellite", "The satellite launcher was lost, unable to land", {
					tooltip = "Idle Satellite",
					on_click = function(id) View.SelectEntities(satellite) Notification.Clear(id) end,
				})
			end)
		end
		ed.launched_at, ed.landing_slot = nil, nil
	elseif arg.landing_approach then
		-- Play landing effect
		landing_slot.owner:PlayEffect(satellite.def.landing_effect, "launch")
	elseif off_the_planet then
		-- Prepare journey back to AMAC
		local satellite_def = satellite.def
		ed.landing_slot = landing_slot
		Map.Delay("SatelliteJourney", satellite_def.travel_time - satellite_def.landing_time, { satellite = satellite, landing_approach = true })
		Map.Delay("SatelliteJourney", satellite_def.travel_time,                              { satellite = satellite, to_the_planet    = true })
	else
		-- Place in landing slot and clear timer
		landing_slot.entity = satellite
		ed.launched_at, ed.landing_slot, ed.launched_by = nil, nil, nil
		c_satellite:on_update(satellite_comp, CC_ACTIVATED) -- check if register already changed
		if not ed.launched_at then faction:RunUI("OnEntityRecreate", satellite, landing_slot.owner) end
	end
end

function EntityAction.LandSatellite(satellite)
	-- This function can return boolean false just for calls to this functions from inside the simulation, not actual actions
	if not satellite or not satellite.exists or satellite.is_docked then return false end
	local satellite_comp = satellite:FindComponent("c_satellite")
	if not satellite_comp then return false end

	-- on_update while not docked will try to land (or set the register error flag if it failed)
	c_satellite:on_update(satellite_comp, CC_ACTIVATED)

	-- If it failed, try to find a free amac and try initiating the landing again
	local landing_slot = not satellite.extra_data.launched_at and c_satellite:find_landing_slot(satellite_comp)
	if landing_slot then
		satellite_comp:SetRegisterEntity(1, landing_slot.owner)
		c_satellite:on_update(satellite_comp, CC_ACTIVATED)
	end
end

c_satellite_launcher:RegisterComponent("c_space_launcher", {
	name = "Space Launcher",
	texture = "Main/textures/icons/components/space_launcher.png",
	visual = "v_empty_inventory",
	slots = { satellite = 1, },
	race = "human",
})

----- hacking_tool -----
local c_hacking_tool = Comp:RegisterComponent("c_hacking_tool", {
	attachment_size = "Small", race = "human", index = 3041, name = "Hacking Tool",
	desc = "Hacks units or buildings to be controllable by you. Set the target and hack code into the first register to activate.",
	texture = "Main/textures/icons/components/Component_HackingTool_01_S.png",
	production_recipe = CreateProductionRecipe({ micropro = 5, microscope = 5, ldframe = 5 }, { c_human_factory = 100, c_human_factory_robots = 100 }),
	power = -1,
	visual = "v_hacking_tool_s",
	activation = "OnFirstRegisterChange",
	action_tooltip = action_tooltip_set_target,
	registers = {
		{ type = "entity", tip = "Target", ui_icon = "icon_context", click_action = true, filter = 'entity' },
	},

	-- internal variable
	range = 2, -- hack range (radius)
	duration = 150, -- hack duration
})

function c_hacking_tool:action_click(comp, widget)
	CursorChooseEntity("Select the hacking target", function (target)
		if not comp.exists then return end -- got destroyed
		local arg = { comp = comp , reg = { entity = target } }
		Action.SendForEntity("SetRegister", comp.owner, arg)
	end,
	nil, comp.register_index)
end

function c_hacking_tool:switch_faction(entity, new_faction)
	-- remove explorable puzzles and effects
	for _,v in ipairs(entity.components or {}) do
		local type = v.def.type
		if type == "Puzzle" or type == "Effect" then
			v:Destroy()
		end
	end
	entity.faction = new_faction
end

function c_hacking_tool:on_update(comp, cause)
	local reg1 = comp:GetRegister(1)
	local target_entity = reg1.entity
	if not target_entity then
		if not reg1.is_empty then comp:FlagRegisterError(1) end
		comp:StopEffects()
		return
	end

	-- Make sure it's a hackable bot or building and it's not our own faction already
	if cause & CC_REFRESH == 0 and (not IsHackable(target_entity) or target_entity.faction == comp.faction) then
		comp:FlagRegisterError(1)
		comp:StopEffects()
		return
	end

	-- Make sure we are in range of the target
	if comp:RequestStateMove(target_entity, self.range) then return end

	-- trying to hack, turn them into an enemy
	target_entity.faction:SetTrust(comp.faction, "ENEMY", true)

	-- Check if there is a key code required to hack this explorable
	if cause & CC_REFRESH == 0 then
		local scannable_comp = target_entity:FindComponent("c_explorable_scannable")
		local hack_code = scannable_comp and scannable_comp.extra_data.hack_code or (target_entity.has_extra_data and target_entity.extra_data.hack_code) or target_entity.faction.extra_data.hack_code
		--print("my code: ", reg1.num, " - its code: ", hack_code)
		if hack_code and hack_code ~= reg1.num then
			comp:FlagRegisterError(1)
			comp:StopEffects()
			return
		end
	end

	-- If work was finished, make sure the target entity did not change just now
	if cause & (CC_FINISH_WORK | CC_CHANGED_REGISTER_ENTITY) == CC_FINISH_WORK then
		-- if it had a hack_code then add instability
		local scannable_comp = target_entity:FindComponent("c_explorable_scannable")
		local hack_code = scannable_comp and scannable_comp.extra_data.hack_code or (target_entity.has_extra_data and target_entity.extra_data.hack_code) or target_entity.faction.extra_data.hack_code
		if hack_code then
			StabilityAdd(comp.faction, "hack_unit")
		end

		-- Switch target faction then turn off
		self:switch_faction(target_entity, comp.faction)
		comp:StopEffects()
		FactionCount("hacking_tool", 1, comp.faction)
		return
	end

	comp:PlayWorkEffect("fx_scan", "fx")

	reveal_if_stealthed(comp.owner)

	-- Start work with refresh to check if work should continue
	return comp:SetStateStartWork((target_entity.id == "f_charcharosaurus1" and 3 or 1) * self.duration, true, (cause & CC_CHANGED_REGISTER_ENTITY == 0))
end

----- power Unit
c_power_cell:RegisterComponent("c_power_unit", {
	attachment_size = "Small", race = "human", index = 3011, name = "Power Unit",
	texture = "Main/textures/icons/components/Component_PowerCell_01_S.png",
	desc = "Produces continuous power over a small area",
	visual = "v_power_cell_01_s",
	production_recipe = CreateProductionRecipe({ micropro = 5, ldframe = 10, smallreactor = 10 }, { c_human_factory = 40, c_human_factory_robots = 80 }),
	-- production_recipe = CreateProductionRecipe({ icchip = 2, hdframe = 10, refined_crystal = 20 }, { c_assembler = 40 }),
	-- production_recipe = CreateProductionRecipe({ micropro = 10, ldframe = 40 }, { c_human_factory = 40 }),
	power = 200,
	-- race = "human",
	-- power = 100,
	transfer_radius = 5,
})

----- blight power -----
local c_blight_power = Comp:RegisterComponent("c_blight_power", {
	attachment_size = "Medium", race = "blight", index = 2011, name = "Blight Power Generator",
	texture = "Main/textures/icons/components/Component_BlightPowerGenerator_01_M.png",
	desc = "Blight power extraction cell generating <hl>1000</> power inside the blight",
	visual = "v_blightpowergenerator_01_m",
	production_recipe = CreateProductionRecipe({ blightbar = 10, obsidian = 20, blight_plasma = 20 }, { c_advanced_assembler = 60, }),
	activation = "Always",
	registers = { { read_only = true, tip = "Power Production" } },
	slots = { gas = 2 },
	adjust_extra_power = true,
})

function c_blight_power:on_update(comp, cause)
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working))
	local in_blight = Map.GetBlightnessDelta(comp, -1) >= 0
	if in_blight and comp:PrepareConsumeProcess({ blight_extraction = 1 }) then
		comp:FulfillProcess()

		comp.extra_power = 200
		if comp.owner.is_placed then
			if not comp.has_active_effects then
				comp:PlayEffect("fx_blight_power")
			end
			comp:SetRegister(1, { id = "v_power_production", num = (comp.extra_power+(self.power or 0)) * TICKS_PER_SECOND })
			return comp:SetStateStartWork(75)
		else
			comp.extra_power = 0
			comp:StopEffects()
		end
	else
		comp.extra_power = 0
		comp:StopEffects()
	end
	comp:SetRegister(1, { id = "v_power_production", num = (comp.extra_power+(self.power or 0)) * TICKS_PER_SECOND })
	return comp:SetStateSleep(7)
end

----- battery -----
Comp:RegisterComponent("c_battery", {
	attachment_size = "Medium", race = "robot", index = 1016, name = "Medium Battery",
	texture = "Main/textures/icons/components/Component_Battery_01_M.png",
	desc = "Rechargeable cell that can store up to <hl>100,000</> power",
	visual = "v_battery_01_m",
	power_storage = 100000,
	drain_rate = 100,
	charge_rate = 100,
	production_recipe = CreateProductionRecipe({ c_small_battery = 1, hdframe = 2, refined_crystal = 10, icchip = 1 }, { c_advanced_assembler = 80 }), -- lithium = 10,
	get_ui = battery_get_ui,
})

----- large battery -----
Comp:RegisterComponent("c_large_battery", {
	attachment_size = "Large", race = "human", index = 3013, name = "Large Battery",
	texture = "Main/textures/icons/components/component_battery_01_l.png",
	desc = "Rechargeable cell that can store a large amount of power",
	visual = "v_battery_01_l",
	power_storage = 1000000,
	drain_rate = 1000,
	charge_rate = 1000,
	get_ui = battery_get_ui,
	production_recipe = CreateProductionRecipe({ ldframe = 4, transformer = 10, micropro = 5 }, { c_human_factory = 30, c_human_factory_robots = 60 }), -- lithium = 10,
})

----- large_power_transmitter -----
c_power_transmitter:RegisterComponent("c_large_power_transmitter", {
	attachment_size = "Large", race = "human", index = 3012, name = "Large Power Transmitter",
	texture = "Main/textures/icons/components/Component_PowerTransmitter_01_M.png",
	desc = "Transmits <hl>500</> power to a remote target",
	visual = "v_power_transmitter_l",
	bandwidth = 100,
	production_recipe = CreateProductionRecipe({ micropro = 5, transformer = 10, }, { c_human_factory = 40, c_human_factory_robots= 80 }),
})

----- humanity transmitter -----
c_power_transmitter:RegisterComponent("c_internal_transmitter", {
	attachment_size = "Hidden", race = "human", index = 3014, name = "Power Plant Transmitter",
	texture = "Main/textures/icons/components/Component_PowerTransmitter_01_M.png",
	bandwidth = 100,
	production_recipe = false,
})

data.update_mapping.c_storage = "c_medium_storage"
Comp:RegisterComponent("c_medium_storage", {
	attachment_size = "Medium", race = "robot", index = 1021, name = "Medium Storage",
	texture = "Main/textures/icons/components/Component_Storage_01_M.png",
	desc = "Expands storage of Frame by <hl>9 slots</>",
	visual = "v_storage_01_m",
	slots = { storage = 9, },
	production_recipe = CreateProductionRecipe({ c_small_storage = 1, hdframe = 6, cable = 10 }, { c_advanced_assembler = 20 }),
	--dumping_ground = true,
})

----- drone launcher -----

local c_drone_port = c_fabricator:RegisterComponent("c_drone_port", {
	attachment_size = "Small", race = "robot", index = 1022, name = "Drone Port",
	texture = "Main/textures/icons/components/component_droneport_s.png",
	desc = "Holds two drones",
	visual = "v_dronehub_01_s",
	production_effect = "fx_drone_production",
	production_recipe = CreateProductionRecipe({ circuit_board = 2, hdframe = 1 }, { c_advanced_assembler = 40, }),
	slots = { drone = 2 },
})

c_drone_port:RegisterComponent("c_drone_launcher", {
	attachment_size = "Medium", race = "human", index = 3021, name = "Drone Launcher",
	texture = "Main/textures/icons/components/component_dronehub_01_m.png",
	desc = "Flight center with  <hl>6 slots</> for logistic drones",
	visual = "v_dronehub_01_m",
	production_recipe = CreateProductionRecipe({ optic_cable = 10, micropro = 10, transformer = 5 }, { c_human_factory = 60, c_human_factory_robots = 120 }),
	slots = { drone = 6 },
})

c_drone_port:RegisterComponent("c_alien_droneport", {
	attachment_size = "Hidden", race = "alien", index = 5008, name = "Pylon",
	texture = "Main/textures/icons/alien/alienbuilding_pylon.png",
	desc = "Nexus point for drones, plasma crystal and worker production",
	production_recipe = false,
	slots = { drone = 4 },
	production_effect = "fx_alien_whirl", -- missing socket
	effect = "fx_alien_producer",
	effect_socket = "basefx",
})

c_drone_port:RegisterComponent("c_drone_comp", {
	attachment_size = "Internal", race = "human", index = 3021, name = "Drone Component",
	texture = "Main/textures/icons/components/drone_comp.png",
	desc = "Holds a single drone",
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ circuit_board = 3, energized_plate = 3 }, { c_advanced_assembler = 40, }),
	slots = { drone = 1 },
})

local c_landing_pad = c_fabricator:RegisterComponent("c_landing_pad", {
	attachment_size = "Large", race = "human", index = 3041, name = "Landing Pad",
	texture = "Main/textures/icons/components/Component_LandingPad_01_L.png",
	desc = "Landing Pad",
	visual = "v_landingpad_01_l",
	production_effect = "fx_drone_production",
	production_recipe = CreateProductionRecipe({ micropro = 5, ldframe = 20, transformer = 10 }, { c_human_factory = 60, c_human_factory_robots = 120 }),
	slots = { flyer = 3, },
})

function c_landing_pad:on_add(comp)
	comp.owner.has_landing_pad = true
end

function c_landing_pad:on_remove(comp)
	if comp.owner:CountComponents("c_landing_pad", true) == 1 then comp.owner.has_landing_pad = false end
end

--- blight shield ---
local c_blight_shield = Comp:RegisterComponent("c_blight_shield", {
	attachment_size = "Internal", race = "blight", index = 2001, name = "Blight Charger",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/blight_protection.png",
	desc = "Allows units to move into blighted areas, provides <hl>50</> power from the blight",
	production_recipe = CreateProductionRecipe({ circuit_board = 5, blight_crystal = 5 }, { c_assembler = 20, }),
	activation = "Always",
	adjust_extra_power = true,
})

function c_blight_shield:on_add(comp)
	comp.owner.has_blight_shield = true
end

function c_blight_shield:on_update(comp)
	if Map.GetBlightnessDelta(comp, -1) >= -0.02 then
		comp.extra_power = 10
		if not comp.has_active_effects and comp.owner.is_placed then
			comp:PlayEffect("fx_blight_shield", "_entity")
		end
	else
		comp.extra_power = 0
		comp:StopEffects()
	end
	return comp:SetStateSleep(7)
end

function c_blight_shield:on_remove(comp)
	if comp.owner:CountComponents("c_blight_shield", true) == 1 then comp.owner.has_blight_shield = false end
end

----- radar -----
c_small_radar:RegisterComponent("c_radar", {
	attachment_size = "Medium", race = "human", index = 3041, name = "Long-Range Radar",
	texture = "Main/textures/icons/components/Component_Radar_01_M.png",
	desc = "External mount doubles scanning range",
	visual = "v_radar_m",
	power = -1,
	production_recipe = CreateProductionRecipe({ ldframe = 1, transformer = 10, optic_cable = 5 }, { c_human_factory = 30, c_human_factory_robots = 60 }),

	-- lua variable
	range = 50, -- scan distance
	radar_show_range = 10,
	radar_show_area = false,
})

----- alien_stealth module -----
local c_stealth = Comp:RegisterComponent("c_stealth", {
	activation = "Manual",
	power = -10,
	charge_time = 10,
	on_add = def_comp_activate,
})

function c_stealth:on_remove(comp)
	local owner = comp.owner
	if owner.stealth and owner:CountComponents("c_stealth", true) == 1 then self:disable_stealth(owner) end
end

function c_stealth:disable_stealth(owner)
	owner.stealth = false
	for _,triggered_comp in ipairs(owner.triggered_components) do
		if triggered_comp.base_id == "c_turret" then
			triggered_comp.def:on_trigger(triggered_comp, owner)
		end
	end
end

function c_stealth:on_update(comp, cause)
	if comp.owner.stealth then return end

	local work_finished = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	if work_finished then
		comp.owner.stealth = true
		return
	end

	comp:SetStateStartWork(self.charge_time)
end

c_stealth:RegisterComponent("c_alien_stealth", {
	attachment_size = "Internal", race = "alien", index = 5031, name = "Alien Stealth Module",
	texture = "Main/textures/icons/components/alien_stealth.png",
	desc = "Alien undetectability",
	visual = "v_generic_i",
	power = -50,
	charge_time = 30,
	production_recipe = CreateProductionRecipe({ obsidian_brick = 5, cpu = 1 }, { c_alien_factory_robots = 40 }),  --  c_assembler
})

c_portable_radar:RegisterComponent("c_alien_sensor", {
	attachment_size = "Hidden", race = "alien", index = 5011, name = "Alien Sensors",
	desc = "Vehicle mounted sensor array",
	texture = "Main/textures/icons/components/alien_integrated_component.png",
	production_recipe = false,
	power = -10,
	production_effect = "fx_drone_production",

	-- lua variable
	range = 10, -- scan distance
	radar_show_range = 6, -- reveal area
	radar_show_area = false,
})

c_small_radar:RegisterComponent("c_alien_sensor_wide", {
	attachment_size = "Hidden", race = "alien", index = 5023, name = "Alien Broad Sensors",
	desc = "Vehicle mounted sensor array",
	texture = "Main/textures/icons/components/alien_integrated_component.png",
	production_recipe = false,
	power = -10,
	production_effect = "fx_drone_production",

	-- lua variable
	range = 25, -- scan distance
	radar_show_range = 6, -- reveal area
	radar_show_area = false,
})

c_stealth:RegisterComponent("c_integrated_stealth", {
	attachment_size = "Hidden", race = "alien", index = 5012, name = "Stealth Ability",
	texture = "Main/textures/icons/components/alien_integrated_component.png",
	desc = "Alien undetectability",
	power = -10,
	charge_time = 30,
	get_ui = true,
})

local c_portable_teleporter = Comp:RegisterComponent("c_portable_teleporter", {
	attachment_size = "Internal", race = "alien", index = 5034, name = "Unit Displacer",
	texture = "Main/textures/icons/components/alien_portable_teleporter.png",
	desc = "Teleport jump short distances",
	visual = "v_generic_i",
	activation = "OnFirstRegisterChange",
	power = -20,
	action_tooltip = "Teleport Jump",
	registers = { { tip = "Teleport Jump", click_action = true, ui_icon = "icon_target2", filter = 'coord' } },
	range = 5,
	charge_time = 20,
	can_move_building = false,
	production_recipe = CreateProductionRecipe({ obsidian_brick = 5, cpu = 1, phase_leaf = 2 }, { c_alien_factory_robots = 40 }),  --  c_assembler
	on_add = on_add_charge,
	on_remove = on_remove_clear_extra_data,
})

function c_portable_teleporter:get_ui(comp)
	-- text="Teleport Jump"
	return UI.New('<Box padding=4><Button width=54 height=54 icon=icon_new textalign=left style=hl tooltip="Teleport" on_click={click}/></Box>', { click = function() self:action_click(comp) end }), nil, true
end

function c_portable_teleporter:action_click(comp)
	if not self.can_move_building and IsBuilding(comp.owner) then Notification.Error("Buildings cannot use teleporter jump") return end
	if not comp.extra_data.charged then Notification.Error("Teleporter jump has not been charged yet") return end

	local owner = comp.owner
	Notification.Warning("Select teleport jump destination")
	View.StartCursorConstruction(owner.id, owner.visual_id, owner.rotation,
		function(location, rotation, is_valid) -- on confirm
			if not is_valid and comp.exists then Notification.Error("Cannot jump here") return end -- continue cursor
			View.StopCursor()
			if not comp.exists then return end

			Action.SendForEntity("SetRegister", owner, { comp = comp, reg = { coord = location, num = rotation } })
		end,
		function() Notification.Warning("Aborted") end, -- on abort
		function(x, y, rotation, is_visible, can_place, is_powered, size_x, size_y) --check function
			return is_visible and can_place and not LocationBlockedByBlight({x, y, size_x, size_y}) and owner.exists and owner:GetRangeTo(x, y) <= self.range
		end)
end

function c_portable_teleporter:on_update(comp, cause)
	--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working) .. " - has_power: " .. tostring(comp.owner.has_power) .. " - charged: " .. tostring(ed.charged))
	local ed = comp.extra_data
	if cause & CC_FINISH_WORK ~= 0 then
		ed.charged = true
	elseif not ed.charged then
		return comp:SetStateStartWork(self.charge_time, false, true)
	end

	local jump_location = comp:GetRegisterCoord(1)
	if not jump_location then return end

	local owner, x, y, rotation = comp.owner, jump_location.x, jump_location.y, comp:GetRegisterNum(1) % 4
	if not self.can_move_building and IsBuilding(owner) then return end

	local distance = owner:GetRangeTo(x, y)
	if distance > comp.def.range then
		return comp:SetStateSleep() -- try again later
	end

	if distance == 0 then
		local current_location = owner.placed_location
		if current_location.x == jump_location.x and current_location.y == jump_location.y and rotation == owner.rotation then return end
	end

	Map.Defer(function()
		if not comp.exists then return end
		owner:PlayEffect("fx_digital")
		owner:Place(x, y, rotation)
		owner:PlayEffect("fx_digital_in")
	end)

	if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
	ed.charged = nil
	return comp:SetStateStartWork(self.charge_time)
end

c_portable_teleporter:RegisterComponent("c_integrated_teleporter", {
	attachment_size = "Hidden", race = "alien", index = 5014, name = "Displace Ability",
	texture = "Main/textures/icons/components/alien_integrated_component.png",
	power = -5,
	range = 5,
	charge_time = 20,
	production_recipe = false,
})

----- terraformer
local c_terraformer = Comp:RegisterComponent("c_terraformer", {
	attachment_size = "Internal", race = "blight", index = 2032, name = "Purifying Terraformer",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/grass_terraformer.png",
	desc = "Adapted alien technology that purifies a blighted area",
	power = -200,
	terraforming_range = 10,
	terraforming_rate = -0.001,
	terraforming_target = Map.GetSettings().blight_threshold-0.1,
	activation = "Always",
	production_recipe = CreateProductionRecipe({ micropro = 10, blightbar = 10, obsidian = 20 }, { c_advanced_assembler = 30, }),
})

function c_terraformer:on_update(comp)
	local is_terraforming = (comp.extra_data.id ~= nil)
	local value = Map.GetBlightness(comp, self.terraforming_target)
	local hit_target = false
	if self.terraforming_rate > 0.0 then
		if value >= self.terraforming_target then hit_target = true end
	else
		if value <= self.terraforming_target then hit_target = true end
	end
	--print((hit_target and "true" or "false") .. " - " .. value .. ", " .. self.terraforming_target)
	if hit_target and is_terraforming then
		Map.StopTerraforming(comp.extra_data.id)
		comp.extra_data.id = nil
		--if self.owner:IsBuilding() then comp:SetStateSleep(9999) end -- TODO: check if this works
	elseif not hit_target and not is_terraforming then
		comp.extra_data.id = Map.StartTerraforming(comp.owner, self.terraforming_range, self.terraforming_rate)
	end

	--[[
	-- WIP
	if is_terraforming then
		-- check for adjacent crystals
		local convertcrystal = {}
		local found = false
		Map.FindClosestEntity(comp.owner, 2, function(e)
			-- check if crystal and blightness amount
			if e.id == "f_resourcenode_crystal" and Map.GetBlightnessDelta(e, -1) >= 0 and e.size.x == 1 then
				-- remove and turn into blight crystal
				local res = e:GetRegister(FRAMEREG_GOTO)
				if res.id == "crystal" then
					found = true
					convertcrystal[e] = res.num
				end
			end
		end, FF_RESOURCE)
		if found then
			Map.Defer(function()
				for k,v in pairs(convertcrystal) do
					local loc = k.location
					local num = v
					local bcrysvis = {
						"v_blightcrystal1a",
						"v_blightcrystal1b",
					}
					local visual = bcrysvis[math.random(#bcrysvis)]

					k:Destroy()
					local newent = Map.CreateEntity("world", "f_resourcenode_blightcrystal", visual)
					newent:SetRegister(FRAMEREG_GOTO, { id= "blight_crystal", num = num })
					newent:Place(loc)
					newent:PlayEffect("fx_digital_in")
				end
			end)
		end
	end
	--]]

	-- sleep for a bit
	comp:SetStateStartWork(5, false)
end

function c_terraformer:on_remove(comp)
	if comp.extra_data.id then
		Map.StopTerraforming(comp.extra_data.id)
	end
	comp.extra_data.id = nil
end

c_terraformer:RegisterComponent("c_blight_terraformer", {
	attachment_size = "Internal", race = "blight", index = 2033, name = "Alien Terraformer",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/terraformer.png",
	desc = "Alien technology that extracts blight from the ground creating an area of blight",
	power = -50,
	terraforming_range = 10,
	terraforming_rate = 0.001,
	terraforming_target = Map.GetSettings().blight_threshold+0.1,
	production_recipe = CreateProductionRecipe({ micropro = 10, blightbar = 10, obsidian = 20 }, { c_advanced_assembler = 30, }),
})

c_terraformer:RegisterComponent("c_alien_terraformer", {
	attachment_size = "Hidden", race = "alien", index = 5999, name = "Alien Integrated Terraformer",
	texture = "Main/textures/icons/components/terraformer.png",
	terraforming_range = 10,
	terraforming_rate = 0.0015,
	terraforming_target = Map.GetSettings().blight_threshold+0.2,
	production_recipe = false,
})

c_terraformer:RegisterComponent("c_alien_scout_terraformer", {
	attachment_size = "Hidden", race = "alien", index = 5999, name = "Alien Integrated Terraformer",
	texture = "Main/textures/icons/components/terraformer.png",
	terraforming_range = 5,
	terraforming_rate = 0.0007,
	terraforming_target = Map.GetSettings().blight_threshold+0.2,
	production_recipe = false,
})

--[[
c_terraformer:RegisterComponent("c_grass_terraformer", {
	attachment_size = "Internal", race = "alien", index = 5999, name = "Grass  Terraformer",
	visual = "v_generic_i",
	texture = ,
	desc = "Biome generator that pushes back blight",
	terraforming_range = 5,
	terraforming_rate = -0.004,
	terraforming_target = -0.1,
})
--]]

c_shield_generator:RegisterComponent("c_shield_generator2", {
	attachment_size = "Internal", race = "robot", index = 1032, name = "Shield Generator",
	texture = "Main/textures/icons/components/portable_shieldgenerator.png",
	desc = "Energy shield - Uses power to charge a shield that mitigates up to <hl>100</> damage",
	visual = "v_generic_i",
	--visual = "v_shieldgenerator_01_m",
	production_recipe = CreateProductionRecipe({ c_shield_generator = 1, circuit_board = 1, refined_crystal = 1, cable = 2 }, { c_assembler = 30 }),
	--power_storage = 80, -- damage reduction
	shield_max = 100,
	shield_charge = -2, -- charge 2 per tick
	shield_effect = "fx_shield",
})

c_shield_generator:RegisterComponent("c_shield_generator3", {
	attachment_size = "Internal", race = "blight", index = 2031, name = "Hyper Shield Generator",
	texture = "Main/textures/icons/components/portable_shieldgenerator_red.png",
	desc = "Energy shield - Uses power to charge a shield that mitigates up to <hl>150</> damage",
	visual = "v_generic_i",
	--visual = "v_shieldgenerator_01_m",
	-- production_recipe = CreateProductionRecipe({ icchip = 1, blight_plasma = 10, hdframe = 1 }, { c_assembler = 30 }),
	production_recipe = CreateProductionRecipe({ c_shield_generator2 = 1, icchip = 1, blight_plasma = 10, hdframe = 1 }, { c_advanced_assembler = 30, }),

	--power_storage = 160, -- damage reduction
	shield_max = 150,
	shield_charge = -3, -- charge 2 per tick
	shield_effect = "fx_shield3",
})

----- blight_container -----
Comp:RegisterComponent("c_blight_container_i", {
	attachment_size = "Internal", race = "blight", index = 2021, name = "Internal Blight Container",
	texture = "Main/textures/icons/components/component_blightcontainer_01_i.png",
	desc = "Container for holding blight gas",
	power = 0,
	visual = "v_generic_i",
	slots = { gas = 1 },
	-- production_recipe = CreateProductionRecipe({ hdframe = 1, crystal_powder = 2 }, { c_assembler = 40 }),
	production_recipe = CreateProductionRecipe({ reinforced_plate = 2, crystal_powder = 2 }, { c_assembler = 40, c_human_factory = 40 }),
})

Comp:RegisterComponent("c_blight_container_s", {
	attachment_size = "Small", race = "blight", index = 2021, name = "Blight Container Small",
	texture = "Main/textures/icons/components/component_blightcontainer_01_s.png",
	desc = "Small Container that holds blight gas",
	power = 0,
	visual = "v_blightcontainer_s",
	slots = { gas = 3 },
	-- production_recipe = CreateProductionRecipe({ hdframe = 2, crystal_powder = 2 }, { c_assembler = 40 }),
	production_recipe = CreateProductionRecipe({ reinforced_plate = 4, crystal_powder = 2 }, { c_assembler = 40, c_human_factory = 40 }),
})

Comp:RegisterComponent("c_blight_container_m", {
	attachment_size = "Medium", race = "blight", index = 2021, name = "Blight Container Medium",
	texture = "Main/textures/icons/components/component_blightcontainer_01_m.png",
	desc = "Container that holds blight gas",
	power = 0,
	visual = "v_blightcontainer_m",
	slots = { gas = 6 },
	-- production_recipe = CreateProductionRecipe({ hdframe = 4, crystal_powder = 4 }, { c_assembler = 80 }),
	production_recipe = CreateProductionRecipe({ c_blight_container_s = 1, reinforced_plate = 5, crystal_powder = 5 }, { c_advanced_assembler = 80, }),
})

function c_virus_protection:on_add(comp)
	local virus_comp = comp.owner:FindComponent("c_virus")
	if virus_comp ~= nil then
		virus_comp:Destroy()
		if comp.owner:FindComponent("c_virus_container_i") then
			comp.owner:AddItem("virus_source_code", true)
		end
	end
end
local c_virus_bitlock = c_turret:RegisterComponent("c_virus_bitlock", {
	attachment_size = "Medium", race = "virus", index = 4034, name = "Crypto BitLock",
	texture = "Main/textures/icons/components/Component_Virus3.png",
	desc = "Temporarily prevents enemy units from moving",
	power = -5,
	--activation = "Manual",
	visual = "v_virus_robot_antenna_03",
	production_recipe = CreateProductionRecipe({ energized_plate = 5, infected_circuit_board = 1 }, { c_assembler = 30, }),
	trigger_radius = 5,
	attack_radius = 5,

	trigger_channels = "bot|building|bug",

	duration = 25, -- charge duration

	-- internal variable
	damage = 2, -- damage per shot
	blast = 2,
	shoot_fx = "fx_turret_laser",
	shoot_speed = 1,
	extra_effect = bitlock_effect,
	extra_effect_name = "BitLock",
	extra_stat = {
		{ "icon_tiny_damage", "5s", "BitLock Duration" },
	},
})

c_fabricator:RegisterComponent("c_virus_decomposer", {
	attachment_size = "Large", race = "virus", index = 4001, name = "Robot Hive",
	texture = "Main/textures/icons/components/Component_VirusDecomposer_01_L.png",
	desc = "Robot configured hive for bug generation",
	visual = "v_virus_decomposer_l",
	--slots = { bughole = 1 },
	production_effect = "fx_alien_liquid",
	power = -70,
	production_recipe = CreateProductionRecipe({ energized_plate = 5, infected_circuit_board = 5, bug_carapace = 20 }, { c_advanced_assembler = 50, }),
})

c_fabricator:RegisterComponent("c_hive_spawner", {
	attachment_size = "Hidden", race = "virus", index = 4041, name = "Hive Spawner",
	texture = "Main/textures/icons/components/hive_spawner.png",
	desc = "Infected obsidian hive",
	visual = "v_virus_decomposer_l",
	production_effect = false,
	power = -150,
	production_recipe = false
})

c_fabricator:RegisterComponent("c_space_elevator_factory", {
	attachment_size = "Hidden", race = "human", index = 3999, name = "Space Elevator",
	texture = "Main/textures/icons/human/human_space_elevator.png",
	production_effect = "fx_uplink",
	production_recipe = false,
	power = 0,
})

-- Virus Components
Comp:RegisterComponent("c_warp_anchor", {
	attachment_size = "Internal", race = "virus", index = 4043, name = "Warp Anchor",
	visual = "v_generic_i",
	texture = "Main/textures/icons/components/component_virusanchor_01_i.png",
	desc = "Anchors a Warp Gate destination to a unit location",
	production_recipe = CreateProductionRecipe({ hdframe = 2, obsidian_infected = 1 }, { c_advanced_assembler = 200 }),
})

local c_warp_bridge = Comp:RegisterComponent("c_warp_bridge", {
	attachment_size = "Medium", race = "virus", index = 4042, name = "Warp Bridge",
	texture = "Main/textures/icons/components/Component_VirusPosessor_01_M.png",
	desc = "Warp temporarily to another place",
	power = -200,
	slots = { virus = 1 },
	visual = "v_virus_warp_bridge",
	production_recipe = CreateProductionRecipe({ hdframe = 20, infected_circuit_board = 20 }, { c_advanced_assembler = 200 }),
	activation = "OnFirstRegisterChange",
	registers = {
		{ filter = "coord", tip = "Target Destination", ui_icon = "icon_target" },
		{ read_only = true, tip = "Warp Bridge" },
	},

	launch_radius = 4, -- (tile distance)
	duration = 30 * TICKS_PER_SECOND, -- cast charge duration
	warp_bridge_exist_time = 200 * TICKS_PER_SECOND, -- time teleporters exist
	warp_bridge_exist_rand = 20 * TICKS_PER_SECOND, -- warp_bridge_exist_time + random time

	min_rand_length = 250, -- minimum number of tiles to spawn away from spell caster (tile distance)
	max_rand_length = 700, -- maximum numbers of tiles to spawn from spell caster (tile distance)

	-- passing in a num along with coordinate, activates "select_length" to have finer control of the cast distance (min_rand_length/max_rand_length)
	select_length_multiplier = 6, -- when also passing in num, scale of specified tile distance (1-100 tiles * select_length_multiplier)
	select_length_rand = 150, -- when also passing in num, random extra length (tile distance)

	random_tile_range = 64, -- random -+x -=y tile distance when placing end teleporter (tile distance)
	random_angle_range = 20, -- random -+ 360 angle (degrees)
})

function c_warp_bridge:on_remove(comp)
	if comp.has_extra_data then self:close_warp(comp) end
end

function c_warp_bridge:close_warp(comp)
	if not comp.has_extra_data then return end
	local ed = comp.extra_data
	local start_teleporter, end_teleporter = ed.start_teleporter, ed.end_teleporter
	comp.extra_data = nil
	comp:SetRegister(2, nil)
	if start_teleporter and start_teleporter.exists then
		start_teleporter:Destroy()
	end
	if end_teleporter and end_teleporter.exists then
		comp.faction:RunUI(function()
			local loc_x, loc_y = end_teleporter:GetLocationXY()
			Notification.Add("warp_bridge", end_teleporter.def.texture, "Warp Bridge Ended", L("The Warp Bridge at %d,%d has ended", loc_x, loc_y), {
				duration = 10,
				on_click = function() View.MoveCamera(loc_x, loc_y) end,
			})
		end)
		end_teleporter:Destroy()
	end
end

function c_warp_bridge:on_update(comp, cause)
	local owner, reg1 = comp.owner, comp:GetRegister(1)
	local reg1_coord, reg1_entity = reg1.coord, reg1.entity
	local anchor = reg1_entity and reg1_entity:FindComponent("c_warp_anchor")

	if not reg1_coord and not anchor then
		comp:StopEffects()
		comp:FlagRegisterError(1, not comp:RegisterIsEmpty(1))
		return
	end

	local aim_x, aim_y, pos_x, pos_y
	if anchor then
		aim_x, aim_y = owner:GetLocationXY()
		pos_x, pos_y = reg1_entity:GetLocationXY()
	else
		aim_x, aim_y, pos_x, pos_y = reg1_coord.x, reg1_coord.y, owner:GetLocationXY()
	end

	-- request consume item
	if not comp:PrepareConsumeProcess({ virus_source_code = 1 }) then
		comp:StopEffects()
		comp:FlagRegisterError(1)
		return comp:SetStateSleep()
	end

	comp:FlagRegisterError(1, false)
	if comp:RequestStateMove(aim_x, aim_y, self.launch_radius) then
		if IsBuilding(owner) then comp:FlagRegisterError(1) end -- can't move if a building
		comp:StopEffects()
		return -- wait until moved
	end

	reveal_if_stealthed(owner)

	if cause & CC_FINISH_WORK == 0 then
		comp:PlayWorkEffect("fx_glitch2", "fx")
		return comp:SetStateStartWork(self.duration, true, (cause & CC_CHANGED_REGISTER_COORD == 0)) -- charge
	end

	comp:FulfillProcess()
	comp:StopEffects()

	local passed_length = math.max(0, comp:GetRegisterNum(1))
	if not comp:RegisterIsLink(1) then
		comp:SetRegister(1, nil) -- clear register if not linked
	else
		comp:SetStateSleep(10) -- automatically try again if linked
	end

	Map.Defer(function()
		-- Override previous portal should it still exist
		if comp.has_extra_data then self:close_warp(comp) end
		local faction = comp.faction

		local start_teleporter = Map.CreateEntity(faction, "f_virus_teleporter")
		local start_point = start_teleporter:AddComponent("c_virus_teleporter", { spawner = comp })

		local end_teleporter = Map.CreateEntity(faction, "f_virus_teleporter")
		local end_point = end_teleporter:AddComponent("c_virus_teleporter", { spawner = comp })

		start_teleporter:Place(aim_x, aim_y)
		if self.shoot_fx then comp:PlayEffect(self.shoot_fx, self.shoot_socket, start_teleporter) end

		if anchor then
			end_teleporter:Place(pos_x, pos_y)
		else

			local length
			if passed_length == 0 then
				length = math.random(self.min_rand_length, self.max_rand_length)
			else
				length = math.max(100, math.ceil(self.min_rand_length + ((passed_length + 0.499) * self.select_length_multiplier) + math.random(0, self.select_length_rand)))
			end

			local ang_deg = (math.deg(math.atan(aim_y - pos_y , aim_x - pos_x))) + math.random(-self.random_angle_range, self.random_angle_range)
			local result_x = (pos_x + math.floor(math.cos(math.rad(ang_deg)) * (length))) + math.random(-self.random_tile_range, self.random_tile_range)
			local result_y = (pos_y + math.floor(math.sin(math.rad(ang_deg)) * (length))) + math.random(-self.random_tile_range, self.random_tile_range)

			local place_loc = GetRelativelySafeGround(owner, result_x, result_y, faction.has_blight_shield)
			pos_x, pos_y = place_loc.x, place_loc.y
			end_teleporter:Place(pos_x, pos_y)
		end

		faction:RunUI(function()
			Notification.Add("warp_bridge", end_teleporter.def.texture, "Warp Bridge Created", L("A Warp Bridge has been created at %d,%d", pos_x, pos_y), {
				duration = 10,
				on_click = function() View.JumpCameraToEntities(end_teleporter) Notification.Clear("warp_bridge") end
			})
		end)

		local expire = Map.GetTick() + self.warp_bridge_exist_time + math.random(0, self.warp_bridge_exist_rand)

		-- keep references to gate entities and expire tick
		local ed = comp.extra_data
		ed.start_teleporter = start_teleporter
		ed.end_teleporter = end_teleporter
		ed.expire = expire

		self:tick_time(comp, end_point) -- set time registers first time
		end_point:Activate() -- we use end point's on_update to call tick_time once every second
	end)
end

function c_warp_bridge:tick_time(comp, point_comp)
	if not comp.has_extra_data then return end
	local ed = comp.extra_data
	local start_teleporter, end_teleporter = ed.start_teleporter, ed.end_teleporter
	if point_comp.owner ~= end_teleporter then return end

	local start_point = ed.start_teleporter:FindComponent("c_virus_teleporter")
	local end_point = ed.end_teleporter:FindComponent("c_virus_teleporter")

	local remain_ticks = ed.expire - Map.GetTick()
	if remain_ticks <= 0 then
		self:close_warp(comp)
		return
	end

	local remain_seconds = math.ceil(remain_ticks / TICKS_PER_SECOND)
	start_point:SetRegister(1, { entity = end_teleporter, num = remain_seconds })
	end_point:SetRegister(1, { entity = start_teleporter, num = remain_seconds })
	comp:SetRegister(2, { entity = end_teleporter, num = remain_seconds })

	-- Return ticks until their next second so caller can call SetStateSleep (but also handle getting activated at random ticks)
	return ((remain_ticks-1) % TICKS_PER_SECOND) + 1
end

function c_warp_bridge:get_reg_error(comp)
	local owner, reg1 = comp.owner, comp:GetRegister(1)
	local reg1_coord, reg1_entity = reg1.coord, reg1.entity
	--local aim_x, aim_y, pos_x, pos_y = reg1_coord and reg1_coord.x, reg1_coord and reg1_coord.y, owner:GetLocationXY()
	local anchor = reg1_entity and reg1_entity:FindComponent("c_warp_anchor")
	local invalid_target = not reg1_coord and not anchor
	if invalid_target then return "Invalid Target" end
	local valid_range = anchor or reg1_coord and (comp.owner:GetRangeTo(reg1_coord) <= self.launch_radius)
	if not valid_range then return "Out of Range" end
	local ing = data.all.virus_source_code.name
	return L("Missing Ingredient: %s", ing)
end

-- A bot is turned into a bug
-- (A bug that holds reference to an unplaced unit
local c_virus_entity_holder = Comp:RegisterComponent("c_virus_entity_holder", {
	name = "Virus Possessor",
})

function c_virus_entity_holder:on_add(comp)
	comp:PlayEffect("fx_glitch_flower", "_entity")
	local old_entity = comp.extra_data.old_entity
	if not old_entity or not old_entity.exists or old_entity.is_on_map then comp.owner:Destroy() end -- maybe due to Deployer?
end

function c_virus_entity_holder:on_remove(comp)
	local ed = comp.extra_data
	local owner, old_entity = comp.owner, ed.old_entity
	if not old_entity or not old_entity.exists or old_entity.is_on_map then return end -- maybe due to Deployer?
	if owner.health <= 0 then
		old_entity:Destroy()
	else
		local place_at = ed.placed_location or owner.placed_location
		owner:Unplace()
		Map.Defer(function() if old_entity.exists then old_entity:Place(place_at) end end)
		old_entity.faction:RunUI("OnEntityRecreate", comp.owner, old_entity)
		owner.faction:RunUI("OnEntityRecreate", comp.owner, old_entity)
	end
end

c_miner:RegisterComponent("c_virus_claws", {
	attachment_size = "Hidden", race = "virus", index = 4011, name = "Claws",
	texture = "Main/textures/icons/bugs/gastarid.png",
	desc = "Claw away Obsidian rock from its roots",
	production_recipe = false,
	power = 0,
	miner_effect = false,
	miner_activate = true,
})

local c_virus_duplicator = Comp:RegisterComponent("c_virus_duplicator", {
	attachment_size = "Medium", race = "virus", index = 4043, name = "Virus Duplicator",
	texture = "Main/textures/icons/components/Component_Virus1.png",
	desc = "Spawn a resource into existence using a Virus hacked duplication glitch instigated from an alternate simulation",
	power = -200,
	visual = "v_virus_duplicator",
	production_recipe = CreateProductionRecipe({ infected_circuit_board = 10, hdframe = 5, obsidian_infected = 3 }, { c_advanced_assembler = 200, }),
	resources = {
		metalore = { "f_resourcenode_metal", "v_metalmedium1a" },
		crystal = { "f_resourcenode_crystal", "v_crystalmedium1a" },
		silica = { "f_resourcenode_silica", "v_silica_medium1" },
		obsidian = { "f_resourcenode_obsidian", "v_obsidian_medium" },
		laterite = { "f_resourcenode_laterite", "v_laterite_medium1" },
		blight_crystal = { "f_resourcenode_blightcrystal", "v_blightcrystal1a" },
	},

	consume_item = "datakey_virus",
	activation = "OnFirstRegisterChange",
	registers = {
		{ tip = "Resource node/Location", ui_icon = "icon_context", click_action = true, filter = 'world' },
		{ tip = "Duplicated Resource", click_action = true, read_only = true },
	},
	duplicate_time = 30 * TICKS_PER_SECOND,
	duplicate_cost = 199,
})

function c_virus_duplicator:get_reg_error(comp)
	local reg1, duplicated_resource = comp:GetRegister(1), self.resources[comp.has_extra_data and comp.extra_data.duplicated_node]
	if not duplicated_resource then -- acquire node
		local target = reg1.entity
		if not target then return "Invalid Target" end
		local resource_id = IsResource(target) and GetResourceHarvestItemId(target)
		local resource_num = resource_id and self.resources[resource_id] and GetResourceHarvestItemAmount(target)
		if not resource_id then return "Not a resource" end
		if (resource_num or 0) <= self.duplicate_cost then return "Insufficient resources remaining" end
		return "Virus Datakey required for duplication"
	else -- place node
		return reg1.coord and "Cannot place near another existing resource node" or "Invalid Target"
	end
end

function c_virus_duplicator:on_add(comp)
	local duplicated_node = comp.has_extra_data and comp.extra_data.duplicated_node
	if duplicated_node then comp:SetRegister(2, { id = duplicated_node, num = 1 }) end
end

function c_virus_duplicator:on_update(comp, cause)
	local reg1 = comp:GetRegister(1)
	local duplicated_node = comp.has_extra_data and comp.extra_data.duplicated_node
	local duplicated_resource = duplicated_node and self.resources[duplicated_node]
	comp:StopEffects()

	if not duplicated_resource then -- acquire node from given entity
		local target = reg1.entity
		local resource_id = target and IsResource(target) and GetResourceHarvestItemId(target)
		local resource_num = resource_id and self.resources[resource_id] and GetResourceHarvestItemAmount(target)
		if (resource_num or 0) <= self.duplicate_cost then -- invalid target or insufficient amount
			comp:FlagRegisterError(1, not reg1.is_empty)
			return
		end

		-- request consume item
		if not comp:PrepareConsumeProcess({ [self.consume_item] = 1 }) then
			comp:FlagRegisterError(1)
			return comp:SetStateSleep()
		end

		-- can work, make sure we are next to resource
		comp:FlagRegisterError(1, false)
		if comp:RequestStateMove(target) then return end

		-- If work was finished, make sure the target entity did not change just now
		if cause & (CC_FINISH_WORK | CC_CHANGED_REGISTER_ENTITY) ~= CC_FINISH_WORK then
			-- start acquisition
			comp:PlayWorkEffect("fx_glitch2", "fx")
			return comp:SetStateStartWork(self.duplicate_time, false, (cause & CC_CHANGED_REGISTER_ENTITY == 0))
		end

		-- Consume item, reduce resource amounts by cost
		comp:FulfillProcess()
		target:PlayEffect("fx_digital_in")
		AddResourceHarvestItemAmount(target, -self.duplicate_cost, resource_num)

		comp:SetRegister(2, { id = resource_id, num = 1 })
		comp.extra_data.duplicated_node = resource_id
		comp:PlayEffect("fx_viral_pulse")
		StabilityAdd(comp.faction, "duplicate_resource")
	else -- place node to given coordinate
		local coord = reg1.coord
		if not coord then
			comp:FlagRegisterError(1, not reg1.is_empty)
			return
		end

		local nearby_resource = Map.FindClosestEntity(coord, 2, function() return true end, FF_RESOURCE)
		if nearby_resource then
			comp:FlagRegisterError(1)
			return comp:SetStateSleep(10) -- wait for location to be cleared
		end

		-- can work, make sure we are next to destination
		comp:FlagRegisterError(1, false)
		if comp:RequestStateMove(coord, 1) then return end

		Map.Defer(function()
			local new_resource = Map.CreateEntity("world", duplicated_resource[1], duplicated_resource[2])
			new_resource:SetRegister(FRAMEREG_GOTO, { item = duplicated_node, amount = 1 })
			new_resource:Place(coord)
			new_resource:PlayEffect("fx_digital_in")
		end)

		comp.faction:UnlockAchievement("HOME_GROWN")

		comp:SetRegister(2, nil)
		comp.extra_data = nil
	end

	-- After acquiring/placing, clear the register or flag the linked input value as error (next step can't also be entity/coord)
	if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) else comp:FlagRegisterError(1) end
end

function c_virus_duplicator:action_tooltip(comp) return comp.has_extra_data and "Place" or "Duplicate" end
function c_virus_duplicator:action_click(comp)
	local duplicated_resource = self.resources[comp.has_extra_data and comp.extra_data.duplicated_node]
	if not duplicated_resource then -- acquire node
		CursorChooseEntity("Select resource to duplicate",
			function (target)
				if not comp.exists then return end -- got destroyed
				local resource_id = target and IsResource(target) and GetResourceHarvestItemId(target)
				local resource_num = resource_id and self.resources[resource_id] and GetResourceHarvestItemAmount(target)
				if (resource_num or 0) <= self.duplicate_cost then -- invalid target or insufficient amount
					Notification.Error(resource_num and "Insufficient resources remaining" or "Invalid Target")
					return
				end

				Action.SendForEntity("SetRegister", comp.owner, { comp = comp, reg = { entity = target } })
			end, nil, comp.register_index)
	else -- place node
		View.StartCursorConstruction(duplicated_resource[1], duplicated_resource[2],
			function(location, rotation, is_valid) -- on confirm
				if not is_valid and comp.exists then
					local nearby_resource = not is_valid and Map.FindClosestEntity(location, 2, function() return true end, FF_RESOURCE)
					Notification.Error(nearby_resource and "Cannot place near another resource node" or "Cannot deploy here")
					return -- continue cursor
				end
				View.StopCursor()
				Quickview_HideGrid()
				if not comp.exists then return end

				UI.PlaySound("fx_ui_BUILD_ADD")
				Action.SendForEntity("SetRegister", comp.owner, { comp = comp, reg = { coord = location, num = rotation } })
			end,
			function() -- on abort
				Quickview_HideGrid()
			end,
			function(x, y, rotation, is_visible, can_place, is_powered, size_x, size_y) --check function
				return is_visible and can_place and not LocationBlockedByBlight({x, y, size_x, size_y}) and (IsBot(comp.owner) or (comp.owner:IsInRangeOf(x, y, size_x, size_y, 1))) and not Map.FindClosestEntity(x, y, 2, function() return true end, FF_RESOURCE)
			end
		)
		Quickview_ShowGrid()
	end
end

local c_virus_destabilizer = Comp:RegisterComponent("c_virus_destabilizer", {
	attachment_size = "Medium", race = "virus", index = 4033, name = "Virus Destabilizer",
	texture = "Main/textures/icons/components/Component_Virus4.png",
	desc = "Destabilizes Obsidian using viral pattern",
	power = -5,
	visual = "v_virus_destabilizer",
	-- production_recipe = CreateProductionRecipe({ c_virus_bitlock = 1, virus_source_code = 1, hdframe = 5, infected_circuit_board = 3 }, { c_advanced_assembler = 30, }),
	production_recipe = CreateProductionRecipe({ c_virus_bitlock = 1, hdframe = 5, obsidian_infected = 3 }, { c_advanced_assembler = 30, }),
	activation = "OnFirstRegisterChange",
	slots = { virus = 1 },
	action_tooltip = action_tooltip_set_target,
	registers = {
		{ tip = "Target to destabilize", ui_icon = "icon_context", click_action = true, filter = 'entity' },
	},
	obsidian_cost = 2,
	attack_range = 3,
	destabilize_time = 5 * TICKS_PER_SECOND,
})

function c_virus_destabilizer:action_click(comp, widget)
	CursorChooseEntity("Select the target to destabilize", function (target)
		if not comp.exists then return end -- got destroyed
		local arg = { comp = comp , reg = { entity = target } }
		if target and target.faction == comp.faction then
			local recipe = target.def.production_recipe or target.def.construction_recipe
			local can_destabilize = recipe and (recipe.ingredients.obsidian or recipe.ingredients.obsidian_brick or recipe.ingredients.shaped_obsidian or recipe.ingredients.energized_artifact)
			if can_destabilize then
				ConfirmBox("Are you sure you want to destabilize your own unit/building?", function()
					Action.SendForEntity("SetRegister", comp.owner, arg)
				end)
			else
				Action.SendForEntity("SetRegister", comp.owner, arg)
			end
		else
			Action.SendForEntity("SetRegister", comp.owner, arg)
		end
	end,
	nil, comp.register_index, true)
end

function c_virus_destabilizer:get_reg_error(comp)
	return "Invalid Target for destabilization"
end

function c_virus_destabilizer:on_update(comp, cause)
	local target = comp:GetRegisterEntity(1)
	local target_def = target and target.def

	-- check target contains obsidian or obsidian brick
	local recipe = target_def and (target_def.production_recipe or target_def.construction_recipe)
	local can_destabilize = recipe and (recipe.ingredients.obsidian or recipe.ingredients.obsidian_brick or recipe.ingredients.shaped_obsidian or recipe.ingredients.energized_artifact)
	local is_explorable = target_def and target_def.is_explorable and target_def.race ~= "alien" and not target_def.immortal
	if not can_destabilize and not is_explorable then
		comp:FlagRegisterError(1, target ~= nil)
		comp:StopEffects()
		return
	end

	-- move to target
	comp:FlagRegisterError(1, false)
	if comp:RequestStateMove(target, self.attack_range) then comp:StopEffects() return end

	-- trying to destabilize, turn them into an enemy
	local owner, target_faction = comp.owner, target.faction
	if not target_faction.is_world_faction then
		target_faction:SetTrust(owner, "ENEMY", true)
		target.powered_down = true
	end
	reveal_if_stealthed(owner)

	-- If work was finished, make sure the target entity did not change just now
	if cause & (CC_FINISH_WORK | CC_CHANGED_REGISTER_ENTITY) == CC_FINISH_WORK then
		-- Finished deconstructing
		-- destroy unit and drop ingredients
		target:PlayEffect("fx_viral_pulse")

		local recipe_ingredients
		if is_explorable then
			-- drop scrap
			recipe_ingredients = { unstable_matter = math.random(15, 20) }
		else
			recipe_ingredients = Tool.Copy(recipe.ingredients)
		end

		local total_obsidian = 0
		local function calculate_obsidian_total(num, lvl, ingredients, amount)
			if ingredients then
				for sub_id, sub_num in pairs(ingredients) do
					local recipe = data.all[sub_id].production_recipe
					if sub_id == "obsidian_brick" or sub_id == "shaped_obsidian" then
						calculate_obsidian_total(sub_num * num // (amount or 1), lvl + 1, recipe and recipe.ingredients, recipe and recipe.amount)
					end
					if sub_id == "obsidian" then total_obsidian = total_obsidian + (sub_num * num // (amount or 1)) end
				end
			end
		end
		calculate_obsidian_total(1, 1, recipe_ingredients, 1)

		if recipe_ingredients.obsidian_brick then recipe_ingredients.obsidian_brick = nil end
		if recipe_ingredients.shaped_obsidian then recipe_ingredients.shaped_obsidian = nil end
		if total_obsidian > 0 then recipe_ingredients.obsidian = total_obsidian end

		local other_faction, loc_x, loc_y
		if recipe_ingredients.anomaly_heart then
			recipe_ingredients.anomaly_heart = nil
			other_faction = target_faction
			loc_x, loc_y = target:GetLocationXY()
		end

		-- Only pass damager if the target is on another faction or needs its (for on_destroy) to avoid showing notification for own units
		local damager = (target_faction ~= owner.faction or target_def.on_destroy) and owner
		target:Destroy(true, recipe_ingredients, owner, damager)

		StabilityAdd(comp.faction, "destabilize")
		if other_faction then
			Map.Defer(function()
				local worker = Map.CreateEntity(other_faction, "f_alien_worker")
				worker:Place(loc_x, loc_y)
			end)
		end
		if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
		comp:StopEffects()
		return
	end

	-- start destabilize
	if cause & CC_REFRESH ~= CC_REFRESH then
		target:PlayEffect("fx_viral_pulse")
		comp:PlayWorkEffect("fx_glitch2", "fx")
	end
	comp:SetStateStartWork(self.destabilize_time, true, (cause & CC_CHANGED_REGISTER_ENTITY == 0))
end

local c_virus_recycler = Comp:RegisterComponent("c_virus_recycler", {
	attachment_size = "Medium", race = "virus", index = 4041, name = "Component Recycler",
	texture = "Main/textures/icons/components/Component_VirusTurret_01_M.png",
	desc = "Virus Component for breaking down Tech",
	visual = "v_virus_component_recycler",
	production_recipe = CreateProductionRecipe({ infected_circuit_board = 10, hdframe = 5 }, { c_advanced_assembler = 30 }),
	power = 0,
	recycle_time = 50,
	activation = "OnAnyItemSlotChange",
	registers = {
		{ read_only = true, tip = "Current component being recycled", },
	},
})

function c_virus_recycler:get_reg_error(comp)
	return "Not enough room for output"
end

function c_virus_recycler:on_update(comp, cause)
	local work_finished = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	if not work_finished and comp.is_working then return comp:SetStateContinueWork() end
	if work_finished then comp:FulfillProcess() end

	local found_comp

	-- Find the first component in the inventory (should a delivery insert more than 1 at the same time)
	for k,v in ipairs(comp.owner.slots or {}) do
		if v.id then
			-- Check if a component and not a reserved order slot
			if v.unreserved_stack > 0 and data.components[v.id] then
				local recipe = data.all[v.id].production_recipe
				if (recipe) then
					found_comp = v
					comp:SetRegister(1, { id = v.id, num = 1 })
				end
			end
		end
	end

	if found_comp then
		local found_id = found_comp.has_extra_data and found_comp.extra_data.resimulated or found_comp.id
		local recipe = data.all[found_id].production_recipe
		local recycle_ingredients
		if recipe then
			recycle_ingredients = recipe.ingredients
		end

		if recycle_ingredients then
			if not comp:PrepareProduceProcess({ [found_comp.id] = 1 }, recycle_ingredients ) then
				comp:FlagRegisterError(1)
				return-- comp:SetStateSleep(TICKS_PER_SECOND)
			else
				return comp:SetStateStartWork(self.recycle_time, true)
			end
		end
	end

	comp:SetRegister(1, nil)
end

c_virus_bitlock:RegisterComponent("c_virus_jamming", {
	attachment_size = "Medium", race = "virus", index = 4031, name = "Virus Ray",
	texture = "Main/textures/icons/components/Component_VirusRay_01_M.png",
	desc = "Virus Turret with virus beam transmission",
	power = -25,
	visual = "v_virus_ray",
	production_recipe = CreateProductionRecipe({ c_portable_turret_green = 1, hdframe = 5, infected_circuit_board = 3 }, { c_advanced_assembler = 30 }),
	trigger_radius = 5,
	attack_radius = 5,

	extra_effect_name = "Infection",

	extra_effect = function(self, comp, target)
		if not target.def.immortal and target.has_component_list
			--and not target.faction:IsUnlocked("t_robots_antivirus")
			and not target:FindComponent("c_virus")
			and not target:FindComponent("c_virus_cure")
			and not target:FindComponent("c_virus_protection") then

			local vir = target:AddComponent("c_virus", "hidden")
			vir:Activate()
			if not target.faction:IsUnlocked("t_robotics_virus_discovery") then
				target.faction:Unlock("t_robotics_virus_discovery")
			end

			FactionCount("virus_infection", true, target.faction)
			target.faction:RunUI("OnVirusNotification", target)
		end
	end,
})

local c_virus_possessor = c_turret:RegisterComponent("c_virus_possessor", {
	attachment_size = "Medium", race = "virus", index = 4032, name = "Virus Possessor",
	texture = "Main/textures/icons/components/Component_VirusDestabilizer_01_M.png",
	desc = "Temporarily glitch a unit or building into a bug and take control of it for a limited time",
	power = -100,
	slots = { virus = 2 },
	visual = "v_virus_possessor",
	production_recipe = CreateProductionRecipe({ hdframe = 10, obsidian_infected = 5, infected_circuit_board = 10 }, { c_advanced_assembler = 30, }),
	trigger_radius = 6,
	attack_radius = 6,
	convert_time = 10 * TICKS_PER_SECOND,
	possessed_as_bug_time = 60 * TICKS_PER_SECOND,
	extra_effect_name = "Possession",
	damage = false, -- don't list as tooltip stat
	damage_type = false, -- don't list as tooltip stat
	shoot_speed = false, -- don't list as tooltip stat
})

function c_virus_possessor:get_reg_error(comp)
	return "Invalid Target"
end

function c_virus_possessor:on_update(comp, cause)
	local target = comp:GetRegisterEntity(1) or self:acquire_target_func(comp)
	comp:SetRegisterEntity(2, target)
	if not target then
		comp:StopEffects()
		return
	end

	-- Disallow immortal buildings, explorables, mission units, same faction, dropped items
	local invalid_target = target.def.immortal or target.def.size == "Mission" or target.id == "f_anomaly_sim"
		or comp.faction == target.faction or IsExplorable(target) or IsResource(target)
		or IsDroppedItem(target)
	if invalid_target then
		comp:FlagRegisterError(1)
		comp:StopEffects()
		return
	end

	-- move to target
	if comp:RequestStateMove(target, self.attack_radius) then return end

	-- trying to possess, turn them into an enemy
	target.faction:SetTrust(comp.faction, "ENEMY", true)
	reveal_if_stealthed(comp.owner)

	-- If work was finished, make sure the target entity did not change just now
	if cause & (CC_FINISH_WORK | CC_CHANGED_REGISTER_ENTITY) == CC_FINISH_WORK then
		-- Finished charging
		target:PlayEffect("fx_viral_pulse")

		local bug_name = "f_trilobyte1"

		local total = 0

		local min = 1 -- algo range minimum
		local max = 200 -- algo range maximum

		local mul_resource = 2
		local mul_simple_material = 2
		local mul_advanced_material = 3
		local mul_hitech_material = 3
		local mul_research = 4

		local global_scale = 1

		local ingredients = (target.def.production_recipe and target.def.production_recipe.ingredients) or (target.def.construction_recipe and target.def.construction_recipe.ingredients)

		local function calculate_ingredient_total(num, lvl, ingredients, amount)
			if ingredients then
				for sub_id, sub_num in pairs(ingredients) do
					local recipe = data.all[sub_id].production_recipe
					local tag = data.all[sub_id].tag
					calculate_ingredient_total(sub_num * num // (amount or 1), lvl + 1, recipe and recipe.ingredients, recipe and recipe.amount)

					if     tag == "resource"          then total = total + (sub_num * num / (amount or 1)) * mul_resource
					elseif tag == "simple_material"   then total = total + (sub_num * num / (amount or 1)) * mul_simple_material
					elseif tag == "advanced_material" then total = total + (sub_num * num / (amount or 1)) * mul_advanced_material
					elseif tag == "hitech_material"   then total = total + (sub_num * num / (amount or 1)) * mul_hitech_material
					elseif tag == "research"          then total = total + (sub_num * num / (amount or 1)) * mul_research end
				end
			end
		end

		local is_building = not IsBot(target) -- IsBuilding but not wall/gates
		if target.def.race == "virus" then
			bug_name = target.def.id
		elseif is_building then
			local visual = target.def.visual
			if visual then
				local tile_size = data.all[visual].tile_size
				if tile_size[1] == 1 or tile_size[2] == 1 then
					bug_name = "f_bug_hole"
				elseif tile_size[1] == 2 or tile_size[2] == 2 then
					bug_name = "f_bug_hive"
				else
					bug_name = "f_bug_hive_large"
				end
			end
		else
			if ingredients then
				calculate_ingredient_total(1, 1, ingredients, 1)
				total = total * global_scale
			else
				total = 1 -- fail safe
			end

			total = math.ceil(total/20)
			if total > max then total = max end
			if total <= 0 then total = min end

			if IsFlyingUnit(target) then
				if total > 80 then
					bug_name = "f_scaramar2"
				else
					bug_name = "f_wasp1"
				end
			elseif IsBuilding(target) then
				if total > 150 then
					bug_name = "f_bug_hive_large"
				elseif total > 100 then
					bug_name = "f_bug_hive"
				elseif total > 50 then
					bug_name = "f_bug_hole"
				else
					bug_name = "f_bug_hole"
				end
			else
				if total >= 100 then
					bug_name = "f_gastarid1"
				elseif total > 80 then
					bug_name = "f_scaramar1"
				elseif total > 60 then
					bug_name = "f_gastarias2"
				elseif total > 40 then
					bug_name = "f_gastarias1"
				end
			end
		end

		-- Spawn a bug to replace existing unit (even if it's already a bugs faction unit of the same type)
		if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
		comp:StopEffects()

		Map.Defer(function()
			local faction = comp.faction
			if not faction then return end -- component owner was destroyed
			local new_entity = Map.CreateEntity(faction, bug_name)
			if new_entity then
				local loc = target.placed_location
				target:Unplace()
				new_entity:Place(loc)
				local entity_holder = new_entity:AddComponent("c_virus_entity_holder", { old_entity = target, placed_location = is_building and loc or nil })
				Map.Delay("DelayedRemoveComponent", self.possessed_as_bug_time, { comp = entity_holder })
				if target.health < target.max_health then
					new_entity.health = math.ceil(new_entity.max_health * 0.9)
				end

				faction:RunUI("OnEntityRecreate", target, new_entity)
				target.faction:RunUI("OnEntityRecreate", target, new_entity)
			end
		end)
		return comp:SetStateSleep(1) -- check for another target the next tick
	end

	-- start possession
	target:PlayEffect("fx_viral_pulse")
	comp:PlayWorkEffect("fx_glitch2", "fx")
	return comp:SetStateStartWork(self.convert_time, true, (cause & CC_CHANGED_REGISTER_ENTITY == 0))
end

Comp:RegisterComponent("c_bug_wave_spawner", {
	attachment_size = "Hidden", race = "virus", index = 4999, name = "Bug Wave Spawner",
	texture = "Main/textures/icons/components/bug_wave_spawner.png",
	desc = "Clones waves of bugs into existence by replicating existing copies of the virus",
	visual = "v_generic_i",
	activation = "OnFirstRegisterChange",
	get_ui = true,
	registers = {
		{ type = "entity", tip = "Attack target\n\nDrag to location, unit or building to set", ui_icon = "icon_context"},
		{ read_only = true, tip = "Missing ingredient", },
	},
	get_reg_error = function(self, comp)
		if comp:RegisterIsEmpty(2) then return "Invalid location" end
		return "Missing ingredient"
	end,
	wave_spawn_cost = { silica = 20, bug_carapace = 20, obsidian_infected = 20, virus_source_code = 2,},
	wave_spawn_cooldown = 300 * TICKS_PER_SECOND,
	possessed_time = 90 * TICKS_PER_SECOND,
	on_update = function(self, comp, cause)
		local ed = comp.extra_data
		if cause & CC_FINISH_WORK ~= 0 then
			ed.charged = true
		elseif not ed.charged then
			return comp:SetStateStartWork(self.wave_spawn_cooldown, false, true)
		end

		local rally_target = comp:GetRegisterCoord(1)
		if not rally_target and not comp:GetRegisterEntity(1) then
			-- cancelled / nothing to do
			comp:SetRegister(2, nil)
			if not comp:RegisterIsEmpty(1) then comp:FlagRegisterError(1) end
			return
		end

		if cause & CC_REFRESH == CC_REFRESH then
			-- Just refreshing, continue work
			return comp:SetStateContinueWork()
		end

		local can_make, missing_register = comp:PrepareConsumeProcess(self.wave_spawn_cost)
		if not can_make then
			-- Missing ingredient or no space for output
			comp:SetRegister(2, missing_register)
			comp:FlagRegisterError(1)
			return comp:SetStateSleep()
		else
			comp:SetRegister(2, nil)
		end

		local owner = comp.owner
		local owner_faction = owner.faction
		local loc = owner.location
		local player_level = GetPlayerFactionLevel(owner_faction) // 2
		local possess_time = self.possessed_time
		if StabilityGet then
			-- modify bug types and duration based on stability
			local stability = -StabilityGet() // 500
			player_level = player_level + stability
			possess_time = possess_time + (stability * TICKS_PER_SECOND)
		end
		comp:FulfillProcess()
		ed.charged = nil
		Map.Defer(function()
			local bug_levels = GetBugCountsForLevel(player_level, math.min((player_level // 3)+1))

			local num_bugs = 0
			local spawn_delay = 1
			for i=1,#bug_levels do
				if bug_levels[i] > 0 then
					for j=1,bug_levels[i] do
						num_bugs = num_bugs + 1
						local bug_delay = (spawn_delay % 15)+1
						--print(num_bugs, ":", bug_delay, "leve:", i)
						Map.Delay("SpawnFromHive", bug_delay, {
							level = i,
							faction = owner_faction,
							loc = Tool.Copy(loc),
							target = rally_target,
							comp = comp,
							player = true,
							auto_destroy = possess_time,
						})
						spawn_delay = spawn_delay + 1
					end
				end
			end

			StabilityAdd(owner_faction, "spawn_bug_wave")
		end)
		if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
		return comp:SetStateStartWork(self.wave_spawn_cooldown, false, true)
	end,
	on_add = function(self,comp)
		local ed = comp.extra_data
		ed.charged = false
		comp:Activate()
	end,
})

-- Blight Components
local c_blight_magnifier = Comp:RegisterComponent("c_blight_magnifier", {
	attachment_size = "Medium", race = "blight", index = 2001, name = "Blight Magnifier",
	texture = "Main/textures/icons/components/Component_Blight1.png",
	desc = "Slowly regenerates nearby resources up to 200, only works if placed inside the blight",
	range = 2,
	power = -100,
	--effect = "fx_alien_liquid",
	visual = "v_blight_magnifier",
	activation = "Always",
	production_recipe = CreateProductionRecipe({ blightbar = 10, micropro = 5, blight_datacube = 5 }, { c_advanced_assembler = 60 }),
	magnify_time = 200,
})

function c_blight_magnifier:get_ui(comp)
	return UI.New([[
		<Box padding=4 bg=reg_base_ro><Canvas><Image id=img valign=center width=48 height=48/><Image id=warning x=4 y=4 image=icon_small_warning color=yellow dock=bottom-right hidden=true/></Canvas></Box>]], {
		update = function(w)
			local blightdelta = Map.GetBlightnessDelta(comp, -1)
			if blightdelta > 0 then w.warning.hidden = true w.img.image = data.values.v_resource.texture else w.warning.hidden = false w.img.image = data.values.v_blight.texture end
		end,

		tooltip = function(w)
			w.tt = UI.New("<Box bg=popup_box_bg blur=true padding=12><HorizontalList child_align=center child_padding=10><Reg entity={entity} bg=card_box_bg def_id={def_id} num={num}/><Text size=12 text={txt}/></HorizontalList></Box>", {
				update = function(w)
					local blightdelta = Map.GetBlightnessDelta(comp, -1)
					if blightdelta > 0 then
						w.def_id = data.values.v_resource.id
						local work_time, work_time_boost = get_work_time(comp, self.magnify_time, false)
						if work_time_boost == 0 or work_time == work_time_boost then
							w.txt = L("Regenerate <bl>Resource</>\n<hl>%.1f</>/min (<hl>%.1f</>s)", 60.0/work_time, work_time)
						else
							w.txt = L("Regenerate <bl>Resource</>\n<gl>%.1f</>/min (<hl>%.1f</>→<gl>%.1f</>s)", 60.0/work_time_boost, work_time, work_time_boost)
						end
					else
						w.def_id = data.values.v_blight.id
						w.txt = "Must be placed inside the blight"
					end
				end,
				destruct = function()
					w.tt = nil
				end
			})[1]
			w:update()
			return w.tt.parent
		end,
	})
end

function c_blight_magnifier:on_update(comp, cause)
	local owner = comp.owner
	local is_in_blight = Map.GetBlightnessDelta(owner, -1) >= 0 or Map.GetSave().dust_storm
	if not is_in_blight or owner.powered_down or not owner.is_placed then
		comp:StopEffects()
		return comp:SetStateSleep(50)
	end
	local is_finished_working = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	if is_finished_working then
		-- increase rewards if prociding anomaly particles
		local reward = 1
		local slot = owner:FindSlot("anomaly_particle", 1)
		if slot then
			slot:RemoveStack(1, true)
			reward = 3
		end

		Map.FindClosestEntity(owner, self.range, function(e)
			if AddResourceHarvestItemAmount(e, reward, 200) then
				e:SetRegisterNum(FRAMEREG_STORE, 1) -- mark as magnified (see c_miner:on_update)
			end
		end, FF_RESOURCE)
	end
	comp:PlayWorkEffect("fx_alien_liquid")
	return comp:SetStateStartWork(self.magnify_time, false)
end

local c_blight_converter = Comp:RegisterComponent("c_blight_converter", {
	attachment_size = "Medium", race = "blight", index = 2002, name = "Resource Converter",
	texture = "Main/textures/icons/components/Component_Blight3.png",
	desc = "Manipulates various resources into other resources. Usable inside the blight.",
	visual = "v_blight_converter",
	production_recipe = CreateProductionRecipe({ blightbar = 10, micropro = 1, blight_datacube = 1 }, { c_advanced_assembler = 60 }),
	activation = "OnAnyItemSlotChange",
	registers = { { read_only = true, tip = "Converting" }  },
	requires_blight = true,
	conversion_recipes = {
		{ id = "laterite",       amt =  1, t = 100, to = { ["metalore"] = 1, ["silica"] = 1 } },
		{ id = "blight_crystal", amt = 20, t = 100, to = { ["crystal"] = 5, ["unstable_matter"] = 1 }},
		{ id = "obsidian",       amt =  1, t = 100, to = { ["silica"] = 3 } },
	},
})

function c_blight_converter:get_ui(comp, noregs)
	local retval = UI.New([[<HorizontalList width=84 margin_left=4 margin_right=4>
			<Box fill=true><Button height=22 icon=icon_small_find on_click={showrecipes} tooltip="Known Recipes"/></Box>
		</HorizontalList>]], {
		showrecipes = function(view)
			if not comp or not comp.exists then return end
			UI.MenuPopup("<Box bg=popup_box_bg blur=true padding=8 py=1><VerticalList id=list child_padding=4/></Box>", {
				construct = function(box)
					box:TweenFromTo("sy", 0, 1, 100)
					local list, header = box.list
					for k,v in pairs(self.conversion_recipes) do
						if not v.requires_unlock or comp.faction:IsUnlocked(v.requires_unlock) then
							if not header then header = list:Add('<Text halign=center style=hl text="Known Recipes"/>') end
							local h = list:Add("<HorizontalList child_align=center child_padding=4/>")
							h:Add("<Reg bg=item_default/>", { def_id = v.id, num = v.amt })
							h:Add("<Image image=icon_small_arrow/>")
							for k2,v2 in pairs(v.to) do
								h:Add("<Reg bg=item_default/>", { def_id = k2, num = v2 })
							end
						end
					end
					if not header then list:Add('<Text halign=center style=hl text="No Known Recipes"/>') end
				end,
			}, view, "UP")
		end,
	})
	local regs_def = self.registers
	local num_regs = #regs_def
	local reg_index = comp.register_index - 1
	local convreg
	if not noregs then
		convreg = retval:Add('<Reg margin_left=2 margin_right=4 valign=bottom on_drag_start={link_on_drag_start} on_drag_cancel={link_on_drag_cancel} on_drag_complete={link_on_drag_complete} on_drop={link_on_drop}/>',
			{ ent = comp.owner, abs_index = reg_index + num_regs, comp = comp, reg_index = num_regs, empty_tooltip = regs_def[num_regs].tip })
	end
	return nil, retval, { convreg }
end

c_blight_converter:RegisterComponent("c_alien_converter", { -- soul weaver
	attachment_size = "Hidden", race = "alien", index = 5002, name = "Resource Manipulator",
	texture = "Main/textures/icons/alien/alienbuilding_2x2_extractor.png",
	desc = "Manipulates various resources into other resources. Usable inside the blight.",
	production_recipe = false,
	conversion_recipes = {
		-- alien specific ones
		{ id = "blight_crystal",   amt = 10, t = 100, to = { ["crystal"] = 2, ["unstable_matter"] = 1 } },
		{ id = "anomaly_particle", amt = 5, t = 100, to = { ["anomaly_cluster"] = 1 } },

		-- hybrid ones
		{ id = "laterite",         amt =  1, t = 100, to = { ["metalore"] = 1, ["silica"] = 1 } },
		{ id = "obsidian",         amt =  1, t = 100, to = { ["silica"] = 3 } },
		{ id = "reinforced_plate",      amt = 1, t = 100, to = { ["transformer"] = 1 }, requires_unlock = "transformer" },

		--{ id = "blight_crystal", amt = 20, t = 100, to = { ["crystal"] = 5, ["anomaly_particle"] = 1 } },
	},
})

function c_blight_converter:get_reg_error(comp)
	if self.requires_blight then
		local blightpower = Map.GetBlightnessDelta(comp, -1) >= 0 or Map.GetSave().dust_storm
		if not blightpower then
			return "Must be placed inside the blight"
		end
	end
	return "Not enough room for output"
end

function c_blight_converter:on_update(comp, cause)
	local work_finished = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	if work_finished then
		comp:SetRegister(1, nil)
		comp:FulfillProcess()
	end

	if self.requires_blight then
		-- must be placed in the blight to start working
		local blightpower = Map.GetBlightnessDelta(comp, -1) >= 0 or Map.GetSave().dust_storm
		if not blightpower then
			--comp:FlagRegisterError(1)
			comp:SetRegister(1, nil)
			return comp:SetStateSleep(TICKS_PER_SECOND)
		end
	end

	if not work_finished and comp.is_working then return comp:SetStateContinueWork() end

	local owner = comp.owner
	local funcCountItem = owner.CountItem
	for _,conv in ipairs(self.conversion_recipes) do
		if funcCountItem(owner, conv.id) >= conv.amt and (not conv.requires_unlock or comp.faction:IsUnlocked(conv.requires_unlock)) then
			if comp:PrepareProduceProcess({ [conv.id] = conv.amt }, conv.to) then
				comp:SetRegister(1, { id = conv.id, num = conv.amt })
				return comp:SetStateStartWork(conv.t, false)
			end
		end
	end
end

local c_virus_converter = c_blight_converter:RegisterComponent("c_virus_converter", {
	attachment_size = "Internal", race = "virus", index = 4031, name = "Virus Infector",
	texture = "Main/textures/icons/components/virus_infector.png",
	desc = "Manipulates various resources into other resources",
	slots = { virus = 3 },
	visual = "v_generic_i",
	production_recipe = CreateProductionRecipe({ hdframe = 5, infected_circuit_board = 5 }, { c_advanced_assembler = 30, }),
	conversion_recipes = {
		{ id = "obsidian", amt = 1, t = 100, to = { ["obsidian_infected"] = 1, }},
	},
	requires_blight = false,
})

c_virus_converter:RegisterComponent("c_ravager_virus_converter", {
	attachment_size = "Hidden", race = "virus", index = 4012, name = "Virus Infector",
	slots = { virus = 8 },
	texture = "Main/textures/icons/bugs/gastarid.png",
	production_recipe = false,
	conversion_recipes = {
		{ id = "obsidian", amt = 1, t = 50, to = { ["obsidian_infected"] = 1, }},
		{ id = "blight_crystal", amt = 5, t = 30, to =  { ["crystal_powder"] = 1 }},
		{ id = "silicon", amt = 20, t = 100, to = { ["virus_source_code"] = 1}},
	},
})

c_fabricator:RegisterComponent("c_bloom_producer", { -- plasma bloom
	attachment_size = "Hidden", race = "alien", index = 5999, name = "Bloom Producer",
	-- slots = { slots = 2 },
	texture = "Main/textures/icons/alien/alienbuilding_2x2_feeder.png",
	production_recipe = false,
	power = -30,
})

c_turret:RegisterComponent("c_turret_powerflower", {
	attachment_size = "Small", race = "alien", index = 5031, name = "Drain Turret",
	texture = "Main/textures/icons/components/Component_StarterTurret_01_Drain.png",
	desc = "Overloads a unit or building, causing power drain and other adverse effects",
	power = -5,
	--	activation = "Manual",
	visual = "v_starterturret_drain_s",
	production_recipe = CreateProductionRecipe({ alien_artifact = 1, cpu = 1, power_petal = 5 }, { c_alien_factory_robots = 15 }),
	trigger_radius = 8,
	attack_radius = 8,

	trigger_channels = "bot|building|bug",

	duration = 5, -- charge duration

	-- internal variable
	damage = 30,   -- damage per shot
	shoot_fx = "fx_turret_laser",
	shoot_speed = 1,
	extra_effect_name = "Power Drain",
	extra_effect = function(self, comp, target)
		if not target.def.immortal and target.has_component_list and not target:FindComponent("c_turret_powerflower_effect") then
			target:AddComponent("c_turret_powerflower_effect", "hidden")
			if target.faction.id == "bugs" then
				if target.id == "f_trilobyte1" or target.id == "f_gastarias1" then
					-- return home
					local home = target:GetRegister(FRAMEREG_GOTO)
					if home and home.entity then
						target:MoveTo(home.entity)
					end
				end
			end
		end
	end,
})

Comp:RegisterComponent("c_turret_powerflower_effect", {
	name = "Drain Turret Internal",
	texture = "Main/textures/icons/items/leaves_power.png",
	power = -20,
	effect = "fx_glitch_flower",
	on_add = function(self, comp)
		Map.Delay("DelayedRemoveComponent", 15, { comp = comp })
	end,
})

local c_turret_phaseflower = c_turret:RegisterComponent("c_turret_phaseflower", {
	attachment_size = "Medium", race = "alien", index = 5032, name = "Phase Turret",
	texture = "Main/textures/icons/components/component_turret_01_l_Phase.png",
	desc = "Overloads a unit or building with phase power, causing it be teleported away",
	power = -25,
	visual = "v_starterturret_phase_m",
	production_recipe = CreateProductionRecipe({ alien_artifact = 1, cpu = 1, phase_leaf = 10 }, { c_alien_factory_robots = 120 }),

	trigger_radius = 5,
	attack_radius = 5,

	trigger_channels = "bot|building|bug",

	duration = 16, -- charge duration

	-- internal variable
	damage = 48,   -- damage per shot
	damage_type = "plasma_damage",
	shoot_fx = "fx_turret_laser",
	shoot_speed = 1,
	extra_effect_name = "Phase",
})

function c_turret_phaseflower:extra_effect(comp, target)
	if not target.def.immortal and target.has_component_list and not target:FindComponent("c_turret_phaseflower_effect") then
		target:AddComponent("c_turret_phaseflower_effect", "hidden")
		if target and target.id and target.def.movement_speed then
			local eloc = target.location
			local loc = comp.owner.location
			target:PlayEffect("fx_digital")

			local pushx = 0 -- A sort of Vector2D.normalize but without using normalize
			if loc.x < eloc.x then pushx = 1 elseif loc.x > eloc.x then pushx = -1 end
			local pushy = 0
			if loc.y < eloc.y then pushy = 1 elseif loc.y > eloc.y then pushy = -1 end

			target:Place(eloc.x + 3 * pushx, eloc.y + 3 * pushy)
		end
	end
end

Comp:RegisterComponent("c_turret_phaseflower_effect", {
	name = "Phase Turret Internal",
	texture = "Main/textures/icons/items/leaves_phase.png",
	power = -20,
	effect = "fx_glitch_flower",
	on_add = function(self, comp)
		Map.Delay("DelayedRemoveComponent", 15, { comp = comp })
	end,
})

local c_alien_core = Comp:RegisterComponent("c_alien_core", {
	name = "Alien_Core",
	texture = "Main/textures/icons/components/int.png",
	effect = "fx_alien_core", --"fx_glitch2",
	effect_socket = "fx",
})

function c_alien_core:on_add(comp)
	comp.owner.has_blight_shield = true
	comp.owner.disconnected = false
end

c_turret:RegisterComponent("c_alien_attack", {
	attachment_size = "Hidden", race = "alien", index = 5016, name = "Pulse Ripper",
	desc = "Energized attack",
	texture = "Main/textures/icons/components/Component_AlienAttackIntegrated.png",
	production_recipe = false,
	trigger_radius = 10,
	attack_radius = 10,
	power = 0,

	-- internal variable
	damage = 20,   -- 24 -- damage per shot
	damage_air_bonus = 1.5,
	duration = 1, -- charge duration
	damage_type = "plasma_damage",
	shoot_fx = "fx_alien_attack",
	shoot_speed = 1,
})

----- ALIEN PLASMA WEAPONS -----
--------------------------------

c_portable_turret:RegisterComponent("c_alien_mini_turret", {
	attachment_size = "Hidden", race = "alien", index = 5013, name = "Plasma Slicer",
	texture = "Main/textures/icons/components/Component_AlienPlasmaSlicer.png",
	desc = "Blight crystal turret",
	power = -20, -- -15,
	visual = "v_starterturret_red_s",
	production_recipe = false,
	-- production_recipe = CreateProductionRecipe({ c_portable_turret = 1, blight_plasma = 5 }, { c_assembler = 15 }),
	trigger_radius = 7,
	attack_radius = 7,

	-- internal variable
	damage = 70, -- 42 -- damage per shot
	damage_type = "plasma_damage",
	duration = 7, -- charge duration
	shoot_fx = "fx_alien_attack1",
	shoot_speed = 0,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

c_turret:RegisterComponent("c_fusion_bolt", {
	attachment_size = "Hidden", race = "alien", index = 5019, name = "Fusion Bolt",
	desc = "Energized attack",
	texture = "Main/textures/icons/components/Component_AlienAttackIntegrated.png",
	production_recipe = false,
	trigger_radius = 8,
	attack_radius = 8,
	power = -65, -- -50,
	-- blast = 1,

	-- internal variable
	damage = 144,   -- 120 -- damage per shot
	duration = 6, -- charge duration
	damage_type = "plasma_damage",
	shoot_fx = "fx_alien_attack3",
	shoot_speed = 0,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

c_turret:RegisterComponent("c_plasma_shot", {
	attachment_size = "Hidden", race = "alien", index = 5015, name = "Plasma Blast",
	desc = "Energized attack",
	texture = "Main/textures/icons/components/Component_AlienAttackIntegrated.png",
	production_recipe = false,
	trigger_radius = 6,
	attack_radius = 6,
	power = -65, -- -40,

	-- internal variable
	damage = 84,   -- damage per shot
	duration = 7, -- charge duration
	damage_type = "plasma_damage",
	blast = 1,
	shoot_fx = "fx_alien_attack2",
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

c_turret:RegisterComponent("c_alien_ion_lance", { -- c_alien_plasma_beam
	attachment_size = "Medium", race = "alien", index = 5033, name = "Ion Lance",
	texture = "Main/textures/icons/components/Component_AlienPlasmaBeam_01_M.png",
	desc = "Powerful condensed plasma beam",
	power = -70, -- --60
	visual = "v_alien_plasma_beam_m",
	production_recipe = CreateProductionRecipe({ crystalized_obsidian = 5, plasma_crystal = 5 }, { c_alien_factory = 25, c_alien_factory_comp = 25 }),
	on_remove = on_remove_clear_extra_data_keep_resimulated,

	trigger_radius = 12,
	attack_radius = 12,

	-- internal variable
	damage = 72, -- 56
	damage_type = "plasma_damage",
	duration = 4,
	shoot_fx = "fx_plasma_beam",
	beam_range = 12,
	damage_air_bonus = 0.5,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

c_turret:RegisterComponent("c_sentinel_lance", {
	attachment_size = "Hidden", race = "alien", index = 5017, name = "Sentinel Ion Lance",
	texture = "Main/textures/icons/components/Component_AlienAttackIntegrated.png",
	desc = "Powerful condensed plasma beam",
	power = -80, -- --60
	visual = "v_alien_plasma_beam_m",
	production_recipe = false,
	on_remove = on_remove_clear_extra_data_keep_resimulated,

	trigger_radius = 12,
	attack_radius = 12,

	-- internal variable
	damage = 56,
	damage_type = "plasma_damage",
	duration = 4,
	shoot_fx = "fx_plasma_beam",
	beam_range = 12,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 30,
	dothits = 5,
	extra_stat = {
		{ "icon_tiny_damage", 30, "DoT Damage" },
		{ "icon_tiny_damage", "5s", "DoT Duration" },
	},
})

c_turret:RegisterComponent("c_particle_ripper", {
	attachment_size = "Small", race = "alien", index = 5032, name = "Particle Ripper",
	desc = "Energized attack",
	texture = "Main/textures/icons/components/Component_Alien_Particle_Ripper.png",
	visual = "v_alien_plasma_beam_s",
	-- production_recipe = false,
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 15, blight_plasma = 15 }, { c_alien_factory_robots = 100, c_alien_factory = 35, c_alien_factory_comp = 35 }),
	trigger_radius = 7,
	attack_radius = 7,
	power = -30, -- -20,

	-- internal variable
	damage = 30,   --24 -- damage per shot
	damage_air_bonus = 1.5,
	duration = 2, -- charge duration
	damage_type = "plasma_damage",
	shoot_fx = "fx_alien_attack",
	shoot_speed = 0,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

c_turret:RegisterComponent("c_alien_ripper", {
	attachment_size = "Hidden", race = "alien", index = 5004, name = "Integrated Ripper",
	desc = "Energized attack",
	texture = "Main/textures/icons/components/Component_AlienAttackIntegrated.png",
	visual = "v_alien_plasma_beam_s",
	production_recipe = false,
	trigger_radius = 7,
	attack_radius = 7,
	power = -30, -- -20,

	-- internal variable
	damage = 30,   -- 24 -- damage per shot
	damage_air_bonus = 1.5,
	duration = 2, -- charge duration
	damage_type = "plasma_damage",
	shoot_fx = "fx_alien_attack",
	shoot_speed = 0,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

c_miner:RegisterComponent("c_human_miner", {
	attachment_size = "Hidden", race = "human", index = 3010, name = "Human Miner",
	desc = "Human designed mining equipment that is capable of harvesting most resources",
	texture = "Main/textures/icons/human/Human_MiningMech_01.png",
	production_recipe = false,
	miner_effect = "fx_railgun",
	miner_range = 1,
	power = -20,
	disregard_tooltip = true,
	resource_mined = function(self, comp, id)
		if id == "laterite" or id == "silica" or id == "blight_crystal" then
			if math.random() > 0.5 then
				comp.owner:AddItem(id, true)
			end
		end
	end
})

-------------------------------------------
----- alien_miner -----
local c_alien_miner = c_miner:RegisterComponent("c_alien_miner", {
	attachment_size = "Hidden", race = "alien", index = 5006, name = "Alien Miner",
	texture = "Main/textures/icons/alien/alienbuilding_2x2_miner.png",
	desc = "Alien mining",
	production_recipe = false,
	miner_effect = "fx_alien_miner",
	miner_range = 1,
	power = -5, -- 0,
	disregard_tooltip = true,
	resource_mined = function(self, comp, id)
		if id == "obsidian" then
			local rnd = math.random()
			if rnd < 0.1 then -- 10%
				comp.owner:AddItem("shaped_obsidian", true)
			elseif rnd < 0.2 then -- 10%
				comp.owner:AddItem("blight_plasma", true)
			elseif rnd < 0.6 then -- 40%
				comp.owner:AddItem("obsidian", true)
			elseif rnd < 0.65 then -- 5%
				comp.owner:AddItem("unstable_matter", true)
			end
		elseif id == "blight_crystal" then
			comp.owner:AddItem("anomaly_particle", true)
		end
	end
})

function c_alien_miner:on_add(comp)
	comp.owner.has_blight_shield = true
	comp.owner.disconnected = false
end

local c_alien_feeder = c_blight_extractor:RegisterComponent("c_alien_feeder", {
	attachment_size = "Hidden", race = "alien", index = 5007, name = "Plasma Bloom",
	texture = "Main/textures/icons/alien/alienbuilding_2x2_feeder.png",
	desc = "Alien food production",
	production_recipe = false,
	effect = "fx_alien_feeder",
	effect_socket = "fx",
	power = 0,
	extracts = "blight_plasma",
	extraction_time = 25,
})

function c_alien_feeder:on_add(comp)
	comp.owner.has_blight_shield = true
	comp.owner.disconnected = false
end

c_turret:RegisterComponent("c_monolith_lightning", {
	attachment_size = "Hidden", race = "alien", index = 5020, name = "Monolith Lightning",
	texture = "Main/textures/icons/components/Component_AlienAttackIntegrated.png",
	desc = "Powerful plasma lightning strike",
	power = -150, -- -100,
	production_recipe = false,
	trigger_radius = 20,
	attack_radius = 20,

	-- internal variable
	damage = 252, -- 210
	damage_type = "plasma_damage",
	duration = 7,
	shoot_fx = "fx_alien_monolith_lightning",
	beam_range = 20,
	damage_air_bonus = 0.5,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
})

c_fabricator:RegisterComponent("c_heart_factory", {
	attachment_size = "Hidden", race = "alien", index = 5027, name = "Heart Shard",
	texture = "Main/textures/icons/alien/alienbuilding_alienheart.png",
	desc = "The core of the heart structure",
	production_recipe = false,
	production_effect = "fx_alien_whirl",
})

c_fabricator:RegisterComponent("c_reforming_pool", {
	attachment_size = "Hidden", race = "alien", index = 5021, name = "Reforming Pool", -- Alien Factory
	-- texture = "Main/textures/icons/components/Component_Assembler_01_S.png",
	texture = "Main/textures/icons/alien/alienbuilding_reformingpool.png",
	desc = "Restructuring of alien matter reshape and reform",
	production_recipe = false,
	production_effect = "fx_alien_whirl",
	effect = "fx_reforming_pool",
	effect_socket = "basefx"
})

c_fabricator:RegisterComponent("c_alien_factory", {
	attachment_size = "Hidden", race = "alien", index = 5010, name = "Formation Crucible",
	desc = "Giving form and function to Alien constructs",
	texture = "Main/textures/icons/alien/alienbuilding_2x2_producer.png",
	production_recipe = false,
	production_effect = "fx_alien_whirl",
	effect = "fx_alien_producer",
	effect_socket = "basefx",
	registers = {
		c_fabricator.registers[1], -- production
		c_fabricator.registers[2], -- missing ingredient
		{ type = "entity", tip = "Rally point\n\nDrag to location, unit or building to set", ui_icon = "icon_context"},
	},
})

local c_human_factory = c_fabricator:RegisterComponent("c_human_factory", {
	attachment_size = "Hidden", race = "human", index = 3001, name = "Human Factory",
	desc = "Human Factory production facilities",
	texture = "Main/textures/icons/human/Human_Building_3x3_Factory.png",
	production_recipe = false,
	power = 0,  --- -150,
	production_effect = "fx_fabricator",
})

c_robotics_factory:RegisterComponent("c_human_vehiclefactory", {
	attachment_size = "Hidden", race = "human", index = 3002, name = "Human Vehicle Factory",
	desc = "Vehicle Factory production facilities",
	texture = "Main/textures/icons/human/Human_Building_2x2_VehicleFactory_B.png",
	production_recipe = false,
	power = -1200,
	production_effect = "fx_drone_production",
})

c_small_radar:RegisterComponent("c_radar_array", {
	attachment_size = "Hidden", race = "human", index = 3043, name = "Radar Array",
	desc = "Array of sensor and data processing equipment",
	texture = "Main/textures/icons/human/human_radar_suite.png",
	production_recipe = false,
	power = -100,
	production_effect = "fx_drone_production",

	-- lua variable
	range = 80, -- scan distance
	radar_show_range = 10,
	radar_show_area = false,
})

c_small_radar:RegisterComponent("c_radar_suite", {
	attachment_size = "Hidden", race = "human", index = 3044, name = "Radar Suite",
	desc = "Vehicle mounted sensor array",
	texture = "Main/textures/icons/human/human_radar_suite.png",
	production_recipe = false,
	power = -20,
	production_effect = "fx_drone_production",

	-- lua variable
	range = 30, -- scan distance
	radar_show_range = 6, -- reveal area
	radar_show_area = false,
})

local c_human_datacomplex = c_fabricator:RegisterComponent("c_human_datacomplex", {
	attachment_size = "Hidden", race = "human", index = 3003, name = "Blight Analyzer",
	desc = "Blight analysis and supercomputing data facilities",
	texture = "Main/textures/icons/human/Human_Building_5x5_BlightResearch.png",
	production_recipe = false,
	power = -2000,
	production_effect = "fx_drone_production",
})

function c_human_datacomplex:get_reg_error(comp)
	if Map.GetBlightnessDelta(comp.owner) < 0 then
		return "Blight Analyzer can only operate inside the Blight"
	end
	return c_fabricator.get_reg_error(self, comp)
end

function c_human_datacomplex:on_update(comp, cause)
	if Map.GetBlightnessDelta(comp.owner) < 0 then
		return self:end_production(comp, nil, true, true)
	end
	return c_fabricator.on_update(self, comp, cause)
end

--[[ --- Human Power Unit
c_power_cell:RegisterComponent("c_human_power_unit", {
	attachment_size = "Hidden", race = "human", index = 3999, name = "Human Power Unit",
	texture = "Main/textures/icons/components/Component_PowerCell_01_S.png",
	desc = "Produces continuous power over a small area",
	visual = "v_power_cell_01_s",
	production_recipe = CreateProductionRecipe({ micropro = 5, ldframe = 10, smallreactor = 10 }, { c_human_factory = 40, c_human_factory_robots = 80 }),
	power = 200,
	transfer_radius = 15,
})
]]--

---------------------------------
----Human (not mission) ai center
---------------------------------
c_fabricator:RegisterComponent("c_human_aicenter", {
	attachment_size = "Hidden", race = "human", index = 3004, name = "Multimodal AI Center",
	texture = "Main/textures/icons/human/Human_Building_2x2_CommsBuilding.png",
	production_effect = "fx_uplink",
	production_recipe = false,
	power = -100,
})

c_fabricator:RegisterComponent("c_human_refinery", {
	attachment_size = "Hidden", race = "human", index = 3005, name = "Human Refinery",
	desc = "Material processing facilities",
	texture = "Main/textures/icons/human/Human_Building_2x2_Refinery.png",
	production_recipe = false,
	power = -600,
	production_effect = "fx_fabricator",
})

-----------------------------------
--- Hybrid Human Factory Component
-----------------------------------
c_human_factory:RegisterComponent("c_human_factory_robots", {
	attachment_size = "Large", race = "human", index = 3001, name = "Hybrid Human Factory",
	texture = "Main/textures/icons/components/Component_Amalgamator_01_L.png",
	desc = "A Large Factory equipped for making Human devices",
	visual = "v_amalgamator_01_l",
	power = -200,
	production_recipe = CreateProductionRecipe({ micropro = 5, transformer = 10, aluminiumsheet = 20, }, { c_advanced_assembler = 50, c_alien_factory_robots = 50 }),
})

-----------------------------------
--- Hybrid Human Analyzer Component
-----------------------------------
c_fabricator:RegisterComponent("c_human_science_analyzer_robots", {
	attachment_size = "Large", race = "human", index = 3002, name = "Human Science Analyzer",
	texture = "Main/textures/icons/components/component_ScienceAnalyzer_01_l.png",
	desc = "Robot Science Analyzer for Human Technology",
	visual = "v_scienceanalyzer_l",
	power = -400,
	production_recipe = CreateProductionRecipe({ micropro = 10, ldframe = 20, microscope = 10 }, { c_human_factory = 120, c_human_factory_robots = 120 }),
})

c_robotics_factory:RegisterComponent("c_human_commandcenter", {
	attachment_size = "Hidden", race = "human", index = 3006, name = "Human Command Center",
	desc = "Primary exploration and production facilities",
	texture = "Main/textures/icons/human/Human_Building_3x3_CommandHQ.png",
	production_recipe = false,
	power = -100,
	production_effect = "fx_drone_production",
})

c_robotics_factory:RegisterComponent("c_human_barracks", {
	attachment_size = "Hidden", race = "human", index = 3007, name = "Human Barracks",
	desc = "Human Training and Mecha production facilities",
	texture = "Main/textures/icons/human/Human_Building_2x2_Barracks.png",
	production_recipe = false,
	power = -1000,
	production_effect = "fx_drone_production",
})

c_human_factory:RegisterComponent("c_human_spaceport", {
	attachment_size = "Hidden", race = "human", index = 3008, name = "Human Spaceport",
	desc = "Aerospace production facilities",
	texture = "Main/textures/icons/human/Human_Building_3x3_SpacePort.png",
	power = -1000,
})

c_uplink:RegisterComponent("c_human_science", {
	attachment_size = "Hidden", race = "human", index = 3042, name = "Human Science",
	desc = "Human Orbital Comm-link",
	power = -500,
	texture = "Main/textures/icons/human/Human_Building_2x2_ScienceLab.png",
	production_recipe = false,
	uplink_rate = 0.2,
})

c_uplink:RegisterComponent("c_alien_research", {
	attachment_size = "Hidden", race = "alien", index = 5005, name = "Alien Research",
	texture = "Main/textures/icons/alien/alienbuilding_2x2_research.png",
	desc = "Spires for gathering and processing information",
	production_recipe = false,
	uplink_rate = 0.2,
	effect = "fx_alien_research_building",
	effect_socket = "basefx",
})

local c_mothership_repair = Comp:RegisterComponent("c_mothership_repair", {
	attachment_size = "Hidden", race = "robot", index = 1046, name = "Mothership Repairs",
	texture = "Main/textures/icons/frame/mothership.png",
	activation = "OnAnyItemSlotChange",
	registers = { { tip = "Need", read_only = true }, },
})

local mothership_repair_ui_layout = [[
	<Box>
		<VerticalList halign=center margin=3 child_padding=2 id=hzl>
		</VerticalList>
	</Box>
]]

local mothership_repair_ui_entry = [[
	<HorizontalList width=260>
		<Image image={repitem} width=20 height=20/>
		<Progress id=repprog width=170 height=20/>
		<Text text={reptxt} fill=true halign=right/>
	</HorizontalList>
]]

function c_mothership_repair:on_add_repair(comp)
	-- link to signal to indicate what is required for repair
	local reg = comp.owner:GetRegister(FRAMEREG_SIGNAL)
	if reg.is_empty or reg.is_link then
		comp:LinkRegisterFromRegister(FRAMEREG_SIGNAL, 1)
	end

	-- add first repair item
	local ed = comp.extra_data
	local max_items = ed.max_items or 400
	for k,v in pairs(ed.items) do
		local num = max_items - v
		comp:SetRegister(1, { id = k, num = num })
		break
	end
end

function c_mothership_repair:on_add(comp)

	local repair_items = {
		{ ["robot_datacube"] = 0,       ["energized_plate"] = 0,     ["wire"] = 0,               ["refined_crystal"] = 0,      ["circuit_board"] = 0,            ["reinforced_plate"] = 0, },
		{ ["datacube_matrix"] = 0,      ["hdframe"] = 0,             ["cable"] = 0,              ["fused_electrodes"] = 0,     ["icchip"] = 0,                   ["optic_cable"] = 0, },
		{ ["blight_datacube"] = 0,      ["blight_crystal"] = 0,      ["blightbar"] = 0,          ["blight_plasma"] = 0,        ["obsidian"] = 0,               },
		{ ["virus_research_data"] = 0,  ["bug_carapace"] = 0,        ["silica"] = 0,             ["obsidian_infected"] = 0,    ["infected_circuit_board"] = 0,   },
		{ ["transformer"] = 0,          ["smallreactor"] = 0,        ["aluminiumrod"] = 0,       ["laterite"] = 0,             ["datakey"] = 0,            ["aluminiumsheet"] = 0, },
		{ ["microscope"] = 0,           ["ldframe"] = 0,             ["concreteslab"] = 0,       ["engine"] = 0,               ["micropro"] = 0, },
		{ ["fuel_rod"] = 0,             ["polymer"] = 0,             ["gearbox"] = 0,            ["steelblock"] = 0,           ["ceramictiles"] = 0,             ["enriched_fuel_rod"] = 0, },
		{ ["obsidian_brick"] = 0,       ["phase_leaf"] = 0,          ["power_petal"] = 0,        ["alien_artifact"] = 0,       ["blight_plasma"] = 0,            ["shaped_obsidian"] = 0, },
		{ ["energized_artifact"] = 0,   ["cpu"] = 0,                 ["plasma_crystal"] = 0,     ["crystalized_obsidian"] = 0, ["uframe"] = 0,                   ["alien_artifact_research"] = 0,},
		{ ["robot_research"] = 0,       ["blight_research"] = 0,     ["virus_research"] = 0,     ["human_research"] = 0,       ["alien_research"] = 0,     },
		{ ["datakey_robot"] = 0,        ["datakey_blight"] = 0,      ["datakey_virus"] = 0,      ["datakey_human"] = 0,        ["datakey_alien"] = 0,     },
		{ ["rainbow_research"] = 0,     ["rainbowframe"] = 0, },

	--	{ [""] = 0,     [""] = 0,             [""] = 0,      [""] = 0,},
	}

	comp.extra_data.max_items = 400
	local counters = comp.faction.extra_data.counters
	local counter = counters and counters.repaired_mothership or 0

	if counter == true then
		comp.extra_data.max_items = 500
		counters.repaired_mothership = 1
	end

	comp.extra_data.items = Tool.Copy(repair_items[math.min(counter+1, #repair_items)])
	local amt = math.max(counter + 1 - #repair_items, 0)
	comp.extra_data.max_items = 500 + (amt * 100)
	self:on_add_repair(comp)
end

function c_mothership_repair:get_ui(comp)
	local reg_ui = UI.New(mothership_repair_ui_layout, {
		construct = function(w)
			local ed_item = comp.extra_data.items
			w.widgets = {}
			for k,v in pairs(comp.extra_data.items) do
				local def = data.items[k]
				if def then
					local wid = w.hzl:Add(mothership_repair_ui_entry, { repitem = def.texture, reptxt = L("%d", ed_item[v] or 0) })
					w.widgets[k] = wid
				end
			end
		end,
		update = function(w)
			local ed_item = comp.extra_data.items
			local max_items = comp.extra_data.max_items or 400
			if not comp or not comp.exists then return end
			local ed = comp.extra_data
			for k,v in pairs(w.widgets) do
				local prog = ed_item[k] and (ed_item[k]/max_items) or 0
				v.repprog.progress = prog
				v.repprog.color = (prog >= 1.0) and "green" or "red"
				v.reptxt = L("%d", ed_item[k] or 0)
			end
		end,
		tooltip = function(w)
			local tt_inner = UI.New(mothership_repair_ui_layout)
			local ed_item = comp.extra_data.items
			local maxamt = comp.extra_data.max_items or 400
			local i = 1
			for k,v in pairs(comp.extra_data.items) do
				local def = data.items[k]
				if not def then
					print("unknown repair item", k)
				else
					tt_inner.hzl:Add("<Canvas><Image color=ui_bg height=16 fill=true hidden={img}/><HorizontalList min_width=300><Image image={repimg} width=20 height=20/><Text text={repitemname}/><Text text={repamt} fill=true textalign=right/></HorizontalList></Canvas>", { img = (i % 2 == 0), repimg = def.texture, repitemname = def.name, repamt = L("%d/%d", ed_item[k] or 0, maxamt) })
					i = i + 1
				end
			end
			local tt = UI.New("Box")
			tt:SetContent(tt_inner)
			return tt
		end,
	})
	return nil, nil, false, reg_ui
end

function c_mothership_repair:consume_items(comp)
	-- check all slots for items
	local owner, ed = comp.owner, comp.extra_data
	local max_items = ed.max_items or 400
	for _,slot in ipairs(owner.slots) do
		local id = slot.id
		local so_far, incoming = (id and ed.items[id]), (id and slot.unreserved_stack)
		if so_far and incoming > 0 then
			local remaining = (max_items - so_far)
			local take = remaining > 0 and math.min(remaining, incoming) or 0
			if take > 0 then
				slot:RemoveStack(take, true)
				ed.items[id] = so_far + take
				incoming = incoming - take
			end
		end
		if incoming and incoming > 0 and owner.is_on_map then
			slot:RemoveStack(incoming)
			Map.DropItemAt(owner, id, incoming, true)
		end
	end
end

function c_mothership_repair:on_update(comp, cause)
	self:consume_items(comp)
	local ed = comp.extra_data
	local max_items = ed.max_items or 400
	-- check if its been fully repaired
	for itm,v in SortedPairs(ed.items) do
		if data.all[itm] and v < max_items then
			comp:SetRegister(1, { id = itm, num = max_items - v })
			return
		end
	end

	-- if it got here its repaired
	comp:SetRegister(1, nil)
	self:on_complete(comp)
end

--------------------------------
function UIEjectNotify(entity)
	local loc = entity.location
	Notification.Add("droppod", "warning", "Drop Pod Ejected", L("Drop Pod Ejected at %d, %d", loc.x, loc.y), {
		tooltip = "Drop Pod Ejected",
		on_click = entity and function() View.JumpCameraToEntities(entity) end,
	})
end

function c_mothership_repair:on_complete(comp)
	FactionCount("repaired_mothership", 1, comp.faction)
	comp.faction:UnlockAchievement("REPAIR_MOTHERSHIP")
	local bot = comp.owner:AddItem("bot_ai_core", true) == nil
	local elain = comp.owner:AddItem("elain_ai_core", true) == nil
	-- make sure the player doesnt miss the cores if the inventory is full
	if bot or elain then
		Map.Defer(function()
			local spacedrop = Map.CreateEntity(comp.faction, "f_spacedrop")
			if bot then spacedrop:AddItem("bot_ai_core", true) end
			if elain then spacedrop:AddItem("elain_ai_core", true) end
			FactionCount("ejected_mothership", true, comp.faction)

			local loc = comp.faction.home_location
			loc.x = loc.x + math.random(-40, 40)
			loc.y = loc.y + math.random(-40, 40)
			spacedrop:Place(loc)
			spacedrop:PlayEffect("fx_EMP")
			comp.faction:RunUI(UIEjectNotify, spacedrop)
		end)
	end

	Map.Defer(function() comp:Destroy() end)
end

local c_mothership_eject = Comp:RegisterComponent("c_mothership_eject", {
	attachment_size = "Hidden", race = "robot", index = 1047, name = "Mothership Eject",
	texture = "Main/textures/icons/frame/mothership.png",
	behavior_activate = function(self, comp)
		for k,v in ipairs(comp.owner.slots) do
			local amount = v.unreserved_stack
			if amount > 0 then
				Map.Defer(function() EntityAction.EjectToSurface(comp.owner) end)
				return true
			end
		end
		return false
	end,
})

--------------------------------

function EntityAction.EjectToSurface(entity)
	local spacedrop
	-- gather inventory
	for k,v in ipairs(entity.slots) do
		local amt = v.unreserved_stack
		if amt > 0 then
			if not spacedrop then spacedrop = Map.CreateEntity(entity.faction, "f_spacedrop") end
			local id = v.id
			local def = data.all[id]
			if def and def.slot_type ~= "storage" then
				spacedrop:AddSlots(def.slot_type)
			end
			local got = spacedrop:TransferFrom(entity, id, amt)
			if (id == "bot_ai_core" or id == "elain_ai_core") and (got or 0) > 0 then
				FactionCount("ejected_mothership", true, entity.faction)
			end
		end
	end
	if not spacedrop then return end
	local loc = entity.faction.home_location
	loc.x = loc.x + math.random(-40, 40)
	loc.y = loc.y + math.random(-40, 40)
	spacedrop:Place(loc)
	spacedrop:PlayEffect("fx_EMP")
	entity.faction:RunUI(UIEjectNotify, spacedrop)
end

function c_mothership_eject:get_ui(comp)
	return UI.New('<Box padding=4><Button width=54 height=54 icon=icon_new textalign=left tooltip="Eject" on_click={click}/></Box>', { click = function() self:action_click(comp) end })
end

function c_mothership_eject:action_click(comp)
	local entity = comp.owner
	if comp.faction.home_entity == nil then
		Notification.Warning('No faction home is set, Use <Key Action="FactionHome"/> to set')
		return
	end
	-- get inventory
	for k,v in ipairs(entity.slots) do
		local amount = v.unreserved_stack
		if amount > 0 then
			Action.SendForEntity("EjectToSurface", entity)
			return
		end
	end
	Notification.Warning("No Inventory to Eject")
end

--- ANOMALY Mission
Comp:RegisterComponent("c_anomaly_go_home", {
	activation = "Always",
	on_update = function(self, comp, cause)
		--print("[" .. comp.id .. ":on_update] cause: " .. comp:CauseToString(cause) .. " - comp.is_working: " .. tostring(comp.is_working))
		local comp_owner, save = comp.owner, Map.GetSave()
		local anomaly_base = save.robot_base
		if anomaly_base and anomaly_base:ExistsOnFaction("anomaly") then
			if comp_owner:GetRangeTo(anomaly_base) < 5 then
				Map.Defer(function() comp_owner:Destroy(false) end)
				return
			end
			comp_owner:SetRegister(1, { entity = anomaly_base })
			return comp:RequestStateMove(anomaly_base)
		end

		-- request spawn of anomaly base
		save.robot_spawn = true

		-- wander
		if not comp_owner.is_moving then
			-- find new location
			local l = comp_owner.location
			local x = l.x + math.random(-30,50)
			local y = l.y + math.random(-30,50)
			comp.extra_data.go = {x = x, y = y}
			Map.SpawnChunks(x, y, comp_owner)
		end
		comp:RequestStateMove(comp.extra_data.go)
	end,
	on_add = function(self, comp) comp.owner.has_blight_shield = true end,
})

c_fabricator:RegisterComponent("c_carrier_factory",{
	attachment_size = "Hidden", race = "robot", index = 1001, name = "Robot Factory",
	desc = "An integrated component capable of producing Runner Bots",
	texture = "Main/textures/icons/hidden/carrier_factory.png",
	production_recipe = false,
	production_effect = "fx_drone_production",
})

local c_particle_forge = c_fabricator:RegisterComponent("c_particle_forge", {
	attachment_size = "Hidden", race = "robot", index = 1002, name = "Particle Forge",
	texture = "Main/textures/icons/frame/building_3x3_pf.png",
	desc = "Re-materialize entities at the particle level created from anomaly particles",
	production_recipe = false,
	power = -3000,
})

--------------------- ANOMALY EVENT A -------------------
-- attached to units using tethered wormholes
Comp:RegisterComponent("c_anomaly_event", {
	activation = "Always",
	effect = "fx_glitch",
	on_take_damage = function(self, comp, cause)
		local state = comp.extra_data.state
		if state == 3 then comp:Activate() end
	end,
	on_update = function(self, comp, cause)
		local ed = comp.extra_data
		local state = ed.state
		if not state then -- 1
			local slot = comp.owner:FindSlot("virus_source_code", 1)
			if not slot then
				Map.Defer(function() comp:Destroy() end)
				return
			end
			slot:RemoveStack(1)
			ed.return_to = comp.owner.location
			ed.state = 2
			return comp:SetStateSleep(TICKS_PER_SECOND*6)
		elseif state == 2 then
			-- give 30 seconds
			Map.Defer(function()
				local loc, resim = ed.return_to, comp.owner.docked_garage
				local jumptox = loc.x + math.random(-300, 300)
				local jumptoy = loc.y + math.random(-300, 300)
				comp.owner:SetRegister(1, nil)
				comp.owner:Place(jumptox, jumptoy)
				comp.owner:PlayEffect("fx_digital_in")
				comp.owner:Cancel()

				comp.faction:RunUI(function()
					if View.IsSelectedEntity(comp.owner) or (resim and View.IsSelectedEntity(resim)) then
						View.MoveCamera(jumptox, jumptoy)
					end
				end)
				-- no cure
				if not comp.owner:FindComponent("c_virus")
					and not comp.owner:FindComponent("c_virus_cure")
					and not comp.owner:FindComponent("c_virus_protection")
					then
					comp.owner:AddComponent("c_virus", "hidden")
				end
				UI.Run("NotifyAnomaly", comp.owner)
			end)
			ed.state = 3
			return comp:SetStateSleep(TICKS_PER_SECOND*60)
		else
			Map.Defer(function()
				comp.owner:SetRegister(1, nil)
				comp.owner:Place(ed.return_to)
				comp.faction:RunUI(function()
					if View.IsSelectedEntity(comp.owner) then
						View.MoveCamera(ed.return_to.x, ed.return_to.y)
					end
				end)
				comp.owner:PlayEffect("fx_digital_in")
				comp.owner:Cancel()
				comp:Destroy()
			end)
		end
	end,
})

local function CheckAdminShell(comp)
	local e = comp and comp.exists and comp:GetRegisterEntity(1)
	local have_target, match_code, can_higgs, can_elain = e and e.id == "f_explorable_simulator"
	if have_target then
		local scannable_comp = e:FindComponent("c_explorable_scannable")
		local hack_code = scannable_comp and scannable_comp.extra_data.hack_code or 0
		match_code = hack_code and comp:GetRegisterNum(1) == hack_code
		if match_code then
			local stability = StabilityGet()
			can_higgs = stability <= -10000 and not comp.faction.extra_data.counters.higgs_ending
			can_elain = stability >= 10000 and not comp.faction.extra_data.counters.elain_ending
		end
	end
	return can_higgs, can_elain, have_target, match_code, e
end

local c_admin_shell = Comp:RegisterComponent("c_admin_shell", {
	attachment_size = "Hidden", race = "alien", index = 5028, name = "Console",
	texture = "Main/textures/icons/components/admin_shell.png",
	activation = "OnFirstRegisterChange",
	registers = {
		{ type = "entity", tip = "Connection Target", ui_icon = "icon_target" }
	},
})

function c_admin_shell:behavior_activate(comp)
	local can_higgs, can_elain, _, match_code = CheckAdminShell(comp)
	if can_higgs or can_elain then
		FactionAction.TryActivateSimulator(comp.faction, { comp = comp })
		return true
	end
	return false
end

local function SendArmy(is_alien)
	local profile, army = Game.GetProfile(), 0
	if is_alien then army = profile.alien_army or 0 else army = profile.bug_army or 0 end
	army = army + 1
	if is_alien then profile.alien_army = army else profile.bug_army = army end
end

function FactionAction.TryActivateSimulator(faction, arg)
	local comp = arg.comp
	local can_higgs, can_elain, _, match_code = CheckAdminShell(comp)
	if can_higgs or can_elain then
		FactionCount("m_alien_a", 10, faction, 'set_if_one_less')
	end

	if can_higgs then
		if data.codex.x_higgs_ending then
			faction:Unlock("x_higgs_ending")
		end
		FactionCount("higgs_ending", true, faction)
		Map.GetSave().stability_locked = true
		faction:UnlockAchievement("HIGGS_ENDING")
		faction:RunUI(function() SendArmy(false) end)
	elseif can_elain then
		if data.codex.x_elain_ending then
			faction:Unlock("x_elain_ending")
		end
		FactionCount("elain_ending", true, faction)
		Map.GetSave().stability_locked = true
		faction:UnlockAchievement("ELAIN_ENDING")
		faction:RunUI(function() SendArmy(true) end)
	end
end

function c_admin_shell:get_ui(comp)
	local button_ui = UI.New('<Box><Button id=btn on_click={click} icon=icon_confirm width=56 height=56/></Box>', {
		click = function()
			Action.SendForLocalFaction("TryActivateSimulator", { comp = comp })
		end,
		update = function(v)
			local can_higgs, can_elain, have_target, match_code, reg_entity = CheckAdminShell(comp)

			local activate = can_higgs or can_elain
			local error = not activate and (match_code and "Low Stability" or have_target and "Invalid Access Code" or reg_entity and "Invalid Target" or "No Target")
			v.btn.icon = activate and "icon_confirm" or "icon_deny"
			v.btn.tooltip = activate and "Activate" or L("%s: %s", "Unable to Activate", error)
			v.btn.disabled = not activate
		end,
	})

	local bigbtn_ui
	if StabilityGet then -- only available in freeplay scenario
		bigbtn_ui = UI.New([[<Box margin=2 width=240 blur=true padding=8>
			<HorizontalList margin=3 child_padding=2>
				<VerticalList child_padding=4 fill=true>
					<HorizontalList>
						<ProgressCircle id=progress image="Main/skin/Assets/component_progress.png" width=20 height=20 x=1 y=2/>
						<Text text="Stability" textalign=center halign=center fill=true margin_right=20/>
					</HorizontalList>
					<HorizontalList>
						<Progress id=leftbar height=20 valign=center sx=-1 fill=true color=virus/>
						<Image width=2 height=26 valign=center/>
						<Progress id=rightbar height=20 valign=center fill=true color=blight/>
					</HorizontalList>
				</VerticalList>
			</HorizontalList>
		</Box>]], {
			construct = function(view)
				view:refresh()
			end,
			every_frame_update = function(view)
				view.progress.progress = comp.interpolated_progress
			end,
			refresh = function(view)
				-- stability
				local v = StabilityGet()
				view.leftbar.progress = (v < 0 and (v / -10000.0) or 0)
				view.rightbar.progress = (v > 0 and (v / 10000.0) or 0)
			end,
			destruct = function(view)
				UIMsg:Unbind("OnStabilityChanged", view.handle)
			end
		})
		bigbtn_ui.handle = function() bigbtn_ui:refresh() end
		UIMsg:Bind("OnStabilityChanged", bigbtn_ui.handle)
	end

	return button_ui, nil, false, bigbtn_ui
end

function c_admin_shell:get_reg_error(comp)
	local _, _, have_target = CheckAdminShell(comp)
	return have_target and "Invalid Access Code" or "Invalid Target"
end

function c_admin_shell:on_update(comp, cause)
	local _, _, _, match_code = CheckAdminShell(comp)
	if match_code then
		FactionCount("m_alien_a", 9, comp.faction, 'set_if_one_less')
	end

	comp:FlagRegisterError(1, not comp:RegisterIsEmpty(1) and not match_code)
end

----------------------

Comp:RegisterComponent("c_observer_eye", {
	attachment_size = "Hidden", race = "alien", index = 5025, name = "Observer Eye",
	texture = "Main/textures/icons/alien/alienbuilding_observer.png",
	activation = "OnFirstRegisterChange",
	power = 0,
	registers = {
		{ type = "entity", tip = "Observe", ui_icon = "icon_context" },
	},
	get_ui = true,
	on_add = def_comp_activate,
	get_reg_error = function(self, comp)
		return "Invalid Target"
	end,
	on_update = function(self, comp, cause)
		-- If no target is set and register isn't linked, try to target The Simulator
		local target = comp:GetRegisterEntity(1)
		if not target or not target.is_placed then
			if target or comp:RegisterIsLink(1) then return end
			target = data.explorables.alien_a:FindTheSimulator(comp.faction)
			if not target then return end
			comp:SetRegisterEntity(1, target)
			if not target.is_placed then return end
		end

		-- Can only target owned units or two specific types of explorables
		local comp_faction, target_faction, target_is_observer = comp.faction, target.faction, target.id == "f_alien_observer"
		local valid_target = (target_faction == comp_faction) or (target_faction.is_world_faction and (target_is_observer or target.id == "f_explorable_simulator"))
		comp:FlagRegisterError(1, not valid_target)
		if not valid_target then return end

		-- A targeted observer won't move, so repeated reveal can take longer
		local reveal_duration = target_is_observer and (cause & CC_ACTIVATED == 0) and 30 or 10

		-- Reveal on finish work (reveal duration lasts exactly as long as the work duration)
		if cause & CC_FINISH_WORK ~= 0 then
			local loc_x, loc_y = target:GetLocationXY()
			local self_range = target_is_observer and 50 or 20
			local comp_owner = comp.owner
			Map.Defer(function()
				Map.SpawnChunks(loc_x-self_range-1, loc_y-self_range-1, (self_range*2)+2, (self_range*2)+2, comp_owner)
				comp_faction:RevealArea(loc_x, loc_y, self_range)
			end)
			Map.Delay("RadarHideArea", reveal_duration, { faction = comp_faction, x = loc_x, y = loc_y, range = self_range })
		end

		return comp:SetStateStartWork(reveal_duration)
	end,
})

local c_time_egg_transference = Comp:RegisterComponent("c_time_egg_transference", {
	attachment_size = "Hidden", race = "alien", index = 5026, name = "Item Transference",
	texture = "Main/textures/icons/alien/alienbuilding_egg.png",
	activation = "OnFirstRegisterChange",
	registers = {
		{ type = "entity", tip = "Target", ui_icon = "icon_context" },
	},
	get_ui = true,
})

function c_time_egg_transference:on_update(comp, cause)
	local owner, target = comp.owner, comp:GetRegisterEntity(1)
	if not target or target == owner or not target:ExistsOnFaction(owner.faction) then
		-- not another egg on the same faction
		return
	end
	if not target:FindComponent("c_time_egg_transference", true) then
		return comp:SetStateSleep(10)
	end

	local is_finish_work = (cause & CC_FINISH_WORK == CC_FINISH_WORK)
	for _,slot in ipairs(owner.slots) do
		if slot.unreserved_stack > 0 and target:HaveFreeSpace(slot.id) then
			if is_finish_work then
				local item_extra = slot.has_extra_data and slot.extra_data or nil
				if item_extra then slot.extra_data = nil end
				local addslot, added = target:AddItem(slot.id, slot.unreserved_stack, item_extra)
				slot:RemoveStack(added)
			else
				return comp:SetStateStartWork(10)
			end
		end
	end

	return comp:SetStateSleep(10)
end


Comp:RegisterComponent("c_sandbox_producer", {
	attachment_size = "Internal", index = 9999, name = "Producer",
	desc = "Produces items to fill inventory",
	activation = "Always",
	--registers = { { tip = "Iem to Producer",  } },
	visual = "v_generic_i",
	on_update = function(self, comp, cause)
		--local reg = comp:GetRegister(1)
		--if not reg or not reg.id then return end

		for i,slot in ipairs(comp.owner.slots or {}) do
			if slot.unreserved_space > 0 and comp:PrepareGenerateProcess({[slot.id] = slot.unreserved_space }) then
				comp:FulfillProcess()
				return
			end
		end
	end,
})

Comp:RegisterComponent("c_sandbox_consumer", {
	attachment_size = "Internal", index = 9999, name = "Consumer",
	desc = "Consumes items until inventory is empty",
	activation = "Always",
	visual = "v_generic_i",
	on_update = function(self, comp, cause)
		for i,slot in ipairs(comp.owner.slots or {}) do
			if slot.unreserved_stack > 0 then
				slot:RemoveStack(1, true)
			end
		end
	end,
})

c_fabricator:RegisterComponent("c_reforming_pool_comp", {
	attachment_size = "Large", race = "alien", index = 5002, name = "Reforming Pool Component",
	texture = "Main/textures/icons/components/Component_ReformingPool_01_L.png",
	desc = "A component version of the Reforming Pool",
	slots = { anomaly = 2 },
	visual = "v_ReformingPool_01_l",
	production_effect = "fx_alien_liquid",
	effect = "fx_reforming_pool",
	effect_socket = "basefx",
	power = -40,
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 15, alien_artifact = 1, hdframe = 10 }, { c_alien_factory_robots = 150, }),
})

c_fabricator:RegisterComponent("c_alien_factory_comp", {
	attachment_size = "Large", race = "alien", index = 5003, name = "Formation Crucible Component",
	desc = "Giving form and function to Alien constructs",
	texture = "Main/textures/icons/components/Component_Crucible_01_L.png",
	slots = { anomaly = 2 },
	visual = "v_AlienCrucible_01_l",
	production_effect = "fx_alien_whirl",
	effect = "fx_alien_producer",
	effect_socket = "basefx",
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 20, energized_artifact = 1, hdframe = 20 }, { c_adv_alien_factory = 150, }),
})

c_turret:RegisterComponent("c_sentinel_lance_comp", {
	attachment_size = "Large", race = "alien", index = 5031, name = "Sentinel Ion Lance Turret",
	texture = "Main/textures/icons/components/Component_SentinelTurret_01_M.png",
	desc = "Powerful condensed plasma beam",
	slots = { anomaly = 2 },
	visual = "v_SentinelTurret_01_l",
	power = 0,
	trigger_radius = 10,
	attack_radius = 10,

	-- internal variable
	damage = 42,
	damage_type = "plasma_damage",
	duration = 4,
	shoot_fx = "fx_plasma_beam",
	beam_range = 10,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 30,
	dothits = 5,
	extra_stat = {
		{ "icon_tiny_damage", 30, "DoT Damage" },
		{ "icon_tiny_damage", "5s", "DoT Duration" },
	},

	production_recipe = CreateProductionRecipe({ shaped_obsidian = 15, energized_artifact = 1, hdframe = 10 }, { c_adv_alien_factory = 150, }),
})

c_blight_extractor:RegisterComponent("c_plasma_bloom_comp", {
	attachment_size = "Large", race = "alien", index = 5005, name = "Plasma Bloom Component",
	texture = "Main/textures/icons/components/Component_PlasmaBloom_01_M.png",
	desc = "Alien food production",
	slots = { anomaly = 2 },
	visual = "v_PlasmaBloom_01_l",
	production_effect = "fx_alien_liquid",
	--effect = "fx_alien_feeder",
	effect_socket = "fx",
	power = -30,
	extracts = "blight_plasma",
	extraction_time = 50,
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 10, energized_artifact = 1, hdframe = 20 }, { c_adv_alien_factory = 150, }),
})

c_turret:RegisterComponent("c_monolith_lightning_comp", {
	attachment_size = "Large", race = "alien", index = 5032, name = "Monolith Lightning Component",
	texture = "Main/textures/icons/components/Component_Monolith_01_L.png",
	desc = "Powerful plasma lightning strike",
	visual = "v_Monolith_01_l",
	slots = { anomaly = 2 },
	power = -100,
	trigger_radius = 15,
	attack_radius = 15,

	-- internal variable
	damage = 170,
	damage_type = "plasma_damage",
	duration = 7,
	shoot_fx = "fx_alien_monolith_lightning",
	beam_range = 15,

	extra_effect = dot_effect,
	extra_effect_name = "Damage over Time",
	dotdps = 10,
	dothits = 3,
	extra_stat = {
		{ "icon_tiny_damage", 10, "DoT Damage" },
		{ "icon_tiny_damage", "3s", "DoT Duration" },
	},
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 15, energized_artifact = 1, hdframe = 20 }, { c_adv_alien_factory = 150, }),
})

c_uplink:RegisterComponent("c_alien_research_comp", {
	attachment_size = "Large", race = "alien", index = 5042, name = "Nexaspire Component",
	texture = "Main/textures/icons/components/Component_NexaSpire_01_L.png",
	visual = "v_NexaSpire_01_l",
	uplink_rate = 0.3,
	power = -100,
	effect = "fx_alien_research_building",
	effect_socket = "basefx",
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 10, energized_artifact = 1, hdframe = 20 }, { c_adv_alien_factory = 150, }),
})

c_small_radar:RegisterComponent("c_sensor_spike_comp", {
	attachment_size = "Large", race = "alien", index = 5043, name = "Sensor Spike Component",
	texture = "Main/textures/icons/components/Component_SensorSpikeComRadar_01_M.png",
	visual = "v_SensorSpikeComRadar_01_l",
	power = -100,
	production_effect = "fx_drone_production",

	-- lua variable
	range = 20, -- scan distance
	radar_show_range = 5, -- reveal area
	radar_show_area = false,

	production_recipe = CreateProductionRecipe({ shaped_obsidian = 10, energized_artifact = 1, hdframe = 20 }, { c_adv_alien_factory = 150, }),
})

c_crane:RegisterComponent("c_phase_transporter5", {
	attachment_size = "Large", race = "alien", index = 5021, name = "Long Range Phase Transporter",
	texture = "Main/textures/icons/components/Component_Range5Transporter_01_L.png",
	visual = "v_Range5Transporter_01_l",
	power = -50,
	range = 5,
	production_recipe = CreateProductionRecipe({ cpu = 10, crystalized_obsidian = 5, uframe = 10 }, { c_adv_alien_factory = 150, }),
})

c_crystal_power:RegisterComponent("c_alien_powergenerator_comp", {
	attachment_size = "Large", race = "alien", index = 5011, name = "Alien Power Nova Component",
	texture = "Main/textures/icons/components/Component_BlightPowerGenerator_01_L.png",
	desc = "Alien Power Generator",
	visual = "v_AlienPowerGenerator_01_l",
	power = 0,
	transfer_radius = 6,
	requires_blight = true,
	consume_item = "blight_plasma",
	power_storage = 50000,
	drain_rate = 250,
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 10, energized_artifact = 1, hdframe = 20 }, { c_adv_alien_factory = 150, }),
})

c_time_egg_transference:RegisterComponent("c_time_egg_transference_comp", {
	attachment_size = "Large", race = "alien", index = 5044, name = "Time Egg Component",
	desc = "Special alien component for material transference",
	texture = "Main/textures/icons/components/Component_TimeEgg_01_L.png",
	activation = "OnFirstRegisterChange",
	visual = "v_TimeEgg_01_l",
	power = -50,
	registers = {
		{ type = "entity", tip = "Target", ui_icon = "icon_context" },
	},
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 30, energized_artifact = 1, hdframe = 20 }, { c_adv_alien_factory = 150, }),
})

local c_the_simulator = Comp:RegisterComponent("c_the_simulator", {
	attachment_size = "Large", race = "alien", index = 5045, name = "The Simulator",
	desc = "The Simulator",
	texture = "Main/textures/icons/components/alienbuilding_simulator_comp.png",
	--activation = "OnAnyItemSlotChange",
	visual = "v_the_simulator",
	effect = "fx_simulator",
	production_recipe = CreateProductionRecipe({ rainbowframe = 50, rainbow_research = 50, }, { c_adv_alien_factory = 150, }),
	--registers = {
--{ read_only = true, tip = "Activate", },
--}
})

function c_the_simulator:get_ui(comp)
	local button_ui = UI.New('<Box><Canvas><Button id=btn on_click={click} icon=icon_confirm width=56 height=56><Image id=btnicon color=white image=icon_deny/></Button><Text text={txt} halign=right valign=bottom padding=8/></Canvas></Box>', {
		click = function()
			Action.SendForLocalFaction("TryActivateSimulatorExtract", { comp = comp })
		end,
		update = function(v)
			for k,slot in ipairs(comp.owner.slots) do
				if self.cores[slot.id or 0] then
					-- found
					local numkeys = comp.owner:CountItem("datakey_rainbow")
					if numkeys < 5 then
						local dt = data.items.datakey_rainbow
						v.btnicon.image = dt.texture
						v.txt = tostring(5-numkeys)
						v.btn.disabled = true
						v.btn.tooltip = DefinitionTooltip(dt)
						return
					end
					v.txt = ""
					v.btnicon.image = slot.def.texture
					v.btn.disabled = false
					v.btn.tooltip = "Extract"
					return
				end
			end
			v.btnicon.image = "icon_deny"
			v.btn.tooltip = "Disabled"
			v.btn.disabled = true
		end,
	})
	return button_ui
end

c_the_simulator.cores = {
	["bot_ai_core"] = {
		func = function(f, c)
			-- restart repairs
			local mothership = f.extra_data.mothership
			if mothership and mothership:FindComponent("c_mothership_repair") == nil then
				mothership:AddComponent("c_mothership_repair")
			end
			f:UnlockAchievement("ESCAPE")
			f:RunUI(function()
				local profile = Game.GetProfile()
				profile.allow_frontend_control = true
				profile.allow_race_selection = true
				profile.extracted = profile.extracted or {}
				profile.extracted[#profile.extracted+1] = "bot_ai_core"
				Notification.Warning("Extraction Complete")
			end)
		end
	},
	["elain_ai_core"] = {
		func = function(f, c)
			local mothership = f.extra_data.mothership
			if mothership and mothership:FindComponent("c_mothership_repair") == nil then
				mothership:AddComponent("c_mothership_repair")
			end
			f:RunUI(function()
				local profile = Game.GetProfile()
				profile.extracted = profile.extracted or {}
				profile.extracted[#profile.extracted+1] = "elain_ai_core"
				Notification.Warning("Extraction Complete")
			end)
		end
	},
	["higgs_ai_ac"] = {
		func = function(f, c)
			local mothership = f.extra_data.mothership
			if mothership and mothership:FindComponent("c_mothership_repair") == nil then
				mothership:AddComponent("c_mothership_repair")
			end
			f:RunUI(function()
				local profile = Game.GetProfile()
				profile.extracted = profile.extracted or {}
				profile.extracted[#profile.extracted+1] = "higgs_ai_ac"
				Notification.Warning("Extraction Complete")
			end)
		end
	},
}

function FactionAction.TryActivateSimulatorExtract(faction, arg)
	local comp = arg.comp
	local cores = comp.def.cores
	if not cores or comp.faction ~= faction then return end
	for k,v in ipairs(comp.owner.slots or {}) do
		if cores[v.id] and v.unreserved_stack > 0 then
			if comp.owner:CountItem("datakey_rainbow", true) >= 5 and comp:PrepareConsumeProcess({ [v.id] = 1, datakey_rainbow = 5 }, v) then
				cores[v.id].func(faction, comp)
				comp:FulfillProcess()
			end
			return
		end
	end
end
