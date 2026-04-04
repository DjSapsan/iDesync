--[[

data.values.v_example = {
	name = "<NAME>",
	texture = "<PATH/TO/IMAGE.png>",
}

]]

-- Alien Signals
data.values.v_signal_a = { tag = "alien_signal", race = "alien", index = 5001, name = "?", texture = "Main/textures/icons/alien_text/alien_a.png" }
data.values.v_signal_b = { tag = "alien_signal", race = "alien", index = 5002, name = "?", texture = "Main/textures/icons/alien_text/alien_b.png" }
data.values.v_signal_c = { tag = "alien_signal", race = "alien", index = 5003, name = "?", texture = "Main/textures/icons/alien_text/alien_c.png" }
data.values.v_signal_d = { tag = "alien_signal", race = "alien", index = 5004, name = "?", texture = "Main/textures/icons/alien_text/alien_d.png" }
data.values.v_signal_e = { tag = "alien_signal", race = "alien", index = 5005, name = "?", texture = "Main/textures/icons/alien_text/alien_e.png" }

-- Colors
data.values.v_color_red         = { tag = "color", index =  1, name = "Red",         texture = "Main/textures/icons/color/color_red.png",         color = { 1,0,0 } }
data.values.v_color_green       = { tag = "color", index =  2, name = "Green",       texture = "Main/textures/icons/color/color_green.png",       color = { 0,1,0 } }
data.values.v_color_blue        = { tag = "color", index =  3, name = "Blue",        texture = "Main/textures/icons/color/color_blue.png",        color = { 0,0,1 } }
data.values.v_color_yellow      = { tag = "color", index =  4, name = "Yellow",      texture = "Main/textures/icons/color/color_yellow.png",      color = { 1,1,0 } }
data.values.v_color_cyan        = { tag = "color", index =  5, name = "Cyan",        texture = "Main/textures/icons/color/color_cyan.png",        color = { 0,1,1 } }
data.values.v_color_magenta     = { tag = "color", index =  6, name = "Magenta",     texture = "Main/textures/icons/color/color_magenta.png",     color = { 1,0,1 } }
data.values.v_color_black       = { tag = "color", index =  7, name = "Black",       texture = "Main/textures/icons/color/color_black.png",       color = { 0,0,0 } }
data.values.v_color_brown       = { tag = "color", index =  8, name = "Brown",       texture = "Main/textures/icons/color/color_brown.png",       color = { 0.4,0.2,0.2 } }
data.values.v_color_crimson     = { tag = "color", index =  9, name = "Crimson",     texture = "Main/textures/icons/color/color_crimson.png",     color = { 0.7,0,0 } }
data.values.v_color_dark_grey   = { tag = "color", index = 10, name = "Dark Gray",   texture = "Main/textures/icons/color/color_dark_grey.png",   color = { 0.1,0.1,0.1 } }
data.values.v_color_light_green = { tag = "color", index = 11, name = "Light Green", texture = "Main/textures/icons/color/color_light_green.png", color = { 0.5,1,0.5 } }
data.values.v_color_light_grey  = { tag = "color", index = 12, name = "Light Gray",  texture = "Main/textures/icons/color/color_light_grey.png",  color = { 0.3,0.3,0.3 } }
data.values.v_color_pink        = { tag = "color", index = 13, name = "Pink",        texture = "Main/textures/icons/color/color_pink.png",        color = { 1,0.1,0.1 } }
data.values.v_color_white       = { tag = "color", index = 14, name = "White",       texture = "Main/textures/icons/color/color_white.png",       color = { 1,1,1 } }
data.values.v_color_pastel      = { tag = "color", index = 15, name = "Pastel",      texture = "Main/textures/icons/color/color_pastel.png",      color = { 1,1,0.1 } }

-- Radar Filters
data.values.v_own_faction   = { tag = "entityfilter", index =  1, name = "Owned",                desc = "Units and buildings owned by your faction", texture = "Main/textures/icons/values/owned.png" }
data.values.v_ally_faction  = { tag = "entityfilter", index =  2, name = "Ally",                 desc = "Units and buildings owned by an allied faction", texture = "Main/textures/icons/values/friendly.png" }
data.values.v_enemy_faction = { tag = "entityfilter", index =  3, name = "Enemy",                desc = "Units and buildings owned by an enemy faction", texture = "Main/textures/icons/values/enemy.png" }
data.values.v_world_faction = { tag = "entityfilter", index =  4, name = "World",                desc = "Explorables", texture = "Main/textures/icons/values/world.png" }
data.values.v_bot           = { tag = "entityfilter", index =  5, name = "Unit",                 desc = "Units which can move", texture = "Main/textures/icons/values/unit.png" }
data.values.v_building      = { tag = "entityfilter", index =  6, name = "Building",             desc = "Buildings", texture = "Main/textures/icons/values/building.png" }
data.values.v_is_foundation = { tag = "entityfilter", index =  7, name = "Foundation",           desc = "Foundations without a building on top", texture = "Main/textures/icons/frame/Foundations_2.png" }
data.values.v_wall          = { tag = "entityfilter", index =  8, name = "Wall",                 desc = "Walls", texture = "Main/textures/icons/values/wall.png" }
data.values.v_construction  = { tag = "entityfilter", index =  9, name = "Construction",         desc = "Unfinished construction sites", texture = "Main/textures/icons/values/construction.png" }
data.values.v_is_flower     = { tag = "entityfilter", index = 10, name = "Flower",               desc = "Peculiar fauna on the plateau", texture = "Main/textures/icons/values/flower.png", }
data.values.v_droppeditem   = { tag = "entityfilter", index = 11, name = "Dropped Item",         desc = "Dropped items and scattered resources", texture = "Main/textures/icons/values/dropped_item.png" }
data.values.v_resource      = { tag = "entityfilter", index = 12, name = "Resource",             desc = "Resource nodes and scattered resources", texture = "Main/textures/icons/values/resource.png" }
data.values.v_mineable      = { tag = "entityfilter", index = 13, name = "Mineable",             desc = "Mineable resource nodes", texture = "Main/textures/icons/values/mineable.png" }
data.values.v_robot_faction = { tag = "entityfilter", index = 14, name = "Robot",                desc = "Matches Robot units and buildings", texture = "Main/textures/icons/values/bot.png", }
data.values.v_bug_faction   = { tag = "entityfilter", index = 15, name = "Bug",                  desc = "Matches Bug units and buildings", texture = "Main/textures/icons/values/bug.png", }
data.values.v_human_faction = { tag = "entityfilter", index = 16, name = "Human",                desc = "Matches Human units and buildings", texture = "Main/textures/icons/values/human.png", }
data.values.v_alien_faction = { tag = "entityfilter", index = 17, name = "Alien",                desc = "Matches Alien units and buildings", texture = "Main/textures/icons/values/alien.png", }
data.values.v_anomaly       = { tag = "entityfilter", index = 18, name = "Anomaly",              desc = "Matches Anomaly units and buildings", texture = "Main/textures/icons/values/anomaly.png"}
data.values.v_solved        = { tag = "entityfilter", index = 19, name = "Solved",               desc = "Fully solved explorables", texture = "Main/textures/icons/values/solved.png", }
data.values.v_unsolved      = { tag = "entityfilter", index = 20, name = "Unsolved",             desc = "Not yet fully solved explorables", texture = "Main/textures/icons/values/unsolved.png", }
data.values.v_can_loot      = { tag = "entityfilter", index = 21, name = "Can Loot",             desc = "Matches dropped items, scattered resources and partially or fully solved explorables", texture = "Main/textures/icons/values/lootable.png", }
data.values.v_in_powergrid  = { tag = "entityfilter", index = 22, name = "In Logistics Network", desc = "Units and buildings located inside the logistics network", texture = "Main/textures/icons/states/connected.png?filter=bilinear?mipmaps=true", }
data.values.v_setnum        = { tag = "entityfilter", index = 23, name = "Set Number",           desc = "Specify the numerical value returned by the radar", texture = "Main/textures/icons/values/set_num.png", radar_use_number = true }
data.values.v_maxrange      = { tag = "entityfilter", index = 24, name = "Max Range",            desc = "Limit the range of search", texture = "Main/textures/icons/values/max_range.png", radar_use_number = true }
data.values.v_infected      = { tag = "entityfilter", index = 25, name = "Infected",             desc = "Units and buildings that have been infected", texture = "Main/textures/icons/values/glitch_virus.png" }
data.values.v_damaged       = { tag = "entityfilter", index = 26, name = "Damaged",              desc = "Units and buildings not at full health", texture = "Main/textures/icons/values/damaged.png" }
data.values.v_emergency     = { tag = "entityfilter", index = 27, name = "Slightly Damaged",     desc = "Units and buildings with less than 75% health", texture = "Main/textures/icons/states/emergency.png?filter=bilinear?mipmaps=true", }
data.values.v_broken        = { tag = "entityfilter", index = 28, name = "Heavily Damaged",      desc = "Units and buildings with less than 25% health", texture = "Main/textures/icons/states/broken.png?filter=bilinear?mipmaps=true" }
data.values.v_unpowered     = { tag = "entityfilter", index = 29, name = "Out of Power",         desc = "Owned units and buildings operating at less than 20% efficiency", texture = "Main/textures/icons/states/unpowered.png?filter=bilinear?mipmaps=true" }
data.values.v_powereddown   = { tag = "entityfilter", index = 30, name = "Shutdown",             desc = "Owned units and buildings that have been shutdown", texture = "Main/textures/icons/states/powereddown.png?filter=bilinear?mipmaps=true" }
data.values.v_moving        = { tag = "entityfilter", index = 31, name = "Moving",               desc = "Owned units that are currently moving", texture = "Main/textures/icons/values/moving.png?filter=bilinear?mipmaps=true", }
data.values.v_pathblocked   = { tag = "entityfilter", index = 32, name = "Path Blocked",         desc = "Owned units that have their path blocked", texture = "Main/textures/icons/states/pathblocked.png?filter=bilinear?mipmaps=true", }
data.values.v_idle          = { tag = "entityfilter", index = 33, name = "Idle",                 desc = "Owned units and buildings that are idle", texture = "Main/textures/icons/states/idle.png?filter=bilinear?mipmaps=true" }
data.values.v_mothership    = { tag = "entityfilter", index = 34, name = "Mothership",           desc = "Used to locate the Mothership", texture = "Main/textures/icons/values/mothership_value.png", }

-- Opposing Radar Filters (one of each pair could be removed if filtering offered a NOT option)
data.values.v_valley        = { tag = "entityfilter", index = 40, name = "Valley",               desc = "Matches things on the low valley (not on the plateau)", texture = "Main/textures/icons/values/valley.png" }
data.values.v_plateau       = { tag = "entityfilter", index = 41, name = "Plateau",              desc = "Matches things on the high plateau (not on the valley)", texture = "Main/textures/icons/values/plateau.png" }
data.values.v_not_blight    = { tag = "entityfilter", index = 42, name = "Not Blight",           desc = "Matches objects outside the blight", texture = "Main/textures/icons/values/not_blight.png" }
data.values.v_blight        = { tag = "entityfilter", index = 43, name = "Blight",               desc = "Matches objects inside the blight", texture = "Main/textures/icons/values/blight.png" }
data.values.v_is_grounded   = { tag = "entityfilter", index = 44, name = "Grounded",             desc = "Units and buildings that are on the ground (not flying)", texture = "Main/textures/icons/values/ground.png", }
data.values.v_is_flying     = { tag = "entityfilter", index = 45, name = "Flying",               desc = "Units that fly in the air (not grounded)", texture = "Main/textures/icons/values/flying.png", }

-- Selectable Shape Values
data.values.v_arrow_up        = { tag = "value", index =  1, name = "Arrow Up",         texture = "Main/textures/icons/values/arrow_up.png" }
data.values.v_arrow_down      = { tag = "value", index =  2, name = "Arrow Down",       texture = "Main/textures/icons/values/arrow_down.png" }
data.values.v_arrow_left      = { tag = "value", index =  3, name = "Arrow Left",       texture = "Main/textures/icons/values/arrow_left.png" }
data.values.v_arrow_right     = { tag = "value", index =  4, name = "Arrow Right",      texture = "Main/textures/icons/values/arrow_right.png" }
data.values.v_arrow_upleft    = { tag = "value", index =  5, name = "Arrow Up Left",    texture = "Main/textures/icons/values/arrow_leftup.png" }
data.values.v_arrow_upright   = { tag = "value", index =  6, name = "Arrow Up Right",   texture = "Main/textures/icons/values/arrow_rightup.png" }
data.values.v_arrow_downleft  = { tag = "value", index =  7, name = "Arrow Down left",  texture = "Main/textures/icons/values/arrow_leftdown.png" }
data.values.v_arrow_downright = { tag = "value", index =  8, name = "Arrow Down Right", texture = "Main/textures/icons/values/arrow_rightdown.png" }
data.values.v_transport_route = { tag = "value", index =  9, name = "Transport Route",  texture = "Main/textures/icons/values/arrow_route.png" }
data.values.v_octagon         = { tag = "value", index = 10, name = "Octagon",          texture = "Main/textures/icons/values/octagon.png" }
data.values.v_pentagon        = { tag = "value", index = 11, name = "Pentagon",         texture = "Main/textures/icons/values/pentagon.png" }
data.values.v_star            = { tag = "value", index = 12, name = "Star",             texture = "Main/textures/icons/values/star.png" }
data.values.v_lock_locked     = { tag = "value", index = 13, name = "Locked",           texture = "Main/textures/icons/values/lock_lock.png" }
data.values.v_lock_unlocked   = { tag = "value", index = 14, name = "Unlocked",         texture = "Main/textures/icons/values/lock_unlock.png" }
data.values.v_alert           = { tag = "value", index = 15, name = "Alert",            texture = "Main/textures/icons/values/alert.png" }
data.values.v_power_production = { tag = "value", index = 16, name = "Power Production", texture = "Main/textures/icons/values/power.png" }

-- Selectable Letter Values
data.values.v_letter_A = { tag = "value", index = 101, name = "A", texture = "Main/textures/icons/values/A.png" }
data.values.v_letter_B = { tag = "value", index = 102, name = "B", texture = "Main/textures/icons/values/B.png" }
data.values.v_letter_C = { tag = "value", index = 103, name = "C", texture = "Main/textures/icons/values/C.png" }
data.values.v_letter_D = { tag = "value", index = 104, name = "D", texture = "Main/textures/icons/values/D.png" }
data.values.v_letter_E = { tag = "value", index = 105, name = "E", texture = "Main/textures/icons/values/E.png" }
data.values.v_letter_F = { tag = "value", index = 106, name = "F", texture = "Main/textures/icons/values/F.png" }
data.values.v_letter_G = { tag = "value", index = 107, name = "G", texture = "Main/textures/icons/values/G.png" }
data.values.v_letter_H = { tag = "value", index = 108, name = "H", texture = "Main/textures/icons/values/H.png" }
data.values.v_letter_I = { tag = "value", index = 109, name = "I", texture = "Main/textures/icons/values/I.png" }
data.values.v_letter_J = { tag = "value", index = 110, name = "J", texture = "Main/textures/icons/values/J.png" }
data.values.v_letter_K = { tag = "value", index = 111, name = "K", texture = "Main/textures/icons/values/K.png" }
data.values.v_letter_L = { tag = "value", index = 112, name = "L", texture = "Main/textures/icons/values/L.png" }
data.values.v_letter_M = { tag = "value", index = 113, name = "M", texture = "Main/textures/icons/values/M.png" }
data.values.v_letter_N = { tag = "value", index = 114, name = "N", texture = "Main/textures/icons/values/N.png" }
data.values.v_letter_O = { tag = "value", index = 115, name = "O", texture = "Main/textures/icons/values/O.png" }
data.values.v_letter_P = { tag = "value", index = 116, name = "P", texture = "Main/textures/icons/values/P.png" }
data.values.v_letter_Q = { tag = "value", index = 117, name = "Q", texture = "Main/textures/icons/values/Q.png" }
data.values.v_letter_R = { tag = "value", index = 118, name = "R", texture = "Main/textures/icons/values/R.png" }
data.values.v_letter_S = { tag = "value", index = 119, name = "S", texture = "Main/textures/icons/values/S.png" }
data.values.v_letter_T = { tag = "value", index = 120, name = "T", texture = "Main/textures/icons/values/T.png" }
data.values.v_letter_U = { tag = "value", index = 121, name = "U", texture = "Main/textures/icons/values/U.png" }
data.values.v_letter_V = { tag = "value", index = 122, name = "V", texture = "Main/textures/icons/values/V.png" }
data.values.v_letter_W = { tag = "value", index = 123, name = "W", texture = "Main/textures/icons/values/W.png" }
data.values.v_letter_X = { tag = "value", index = 124, name = "X", texture = "Main/textures/icons/values/X.png" }
data.values.v_letter_Y = { tag = "value", index = 125, name = "Y", texture = "Main/textures/icons/values/Y.png" }
data.values.v_letter_Z = { tag = "value", index = 126, name = "Z", texture = "Main/textures/icons/values/Z.png" }

-- Selectable Number Values
data.values.v_number_0 = { tag = "value", index = 201, name = "0", texture = "Main/textures/icons/values/number_0.png" }
data.values.v_number_1 = { tag = "value", index = 202, name = "1", texture = "Main/textures/icons/values/number_1.png" }
data.values.v_number_2 = { tag = "value", index = 203, name = "2", texture = "Main/textures/icons/values/number_2.png" }
data.values.v_number_3 = { tag = "value", index = 204, name = "3", texture = "Main/textures/icons/values/number_3.png" }
data.values.v_number_4 = { tag = "value", index = 205, name = "4", texture = "Main/textures/icons/values/number_4.png" }
data.values.v_number_5 = { tag = "value", index = 206, name = "5", texture = "Main/textures/icons/values/number_5.png" }
data.values.v_number_6 = { tag = "value", index = 207, name = "6", texture = "Main/textures/icons/values/number_6.png" }
data.values.v_number_7 = { tag = "value", index = 208, name = "7", texture = "Main/textures/icons/values/number_7.png" }
data.values.v_number_8 = { tag = "value", index = 209, name = "8", texture = "Main/textures/icons/values/number_8.png" }
data.values.v_number_9 = { tag = "value", index = 210, name = "9", texture = "Main/textures/icons/values/number_9.png" }

-- Misc Values (used as icons by notifications and read-only registers, not selectable by the player)
data.values.v_notify           = { texture = "Main/textures/icons/values/notify.png" }
data.values.v_blueprint_param  = { name = "Blueprint Parameter", texture = "Main/skin/Icons/Common/56x56/Key.png" }
