--[[

data.items.sampleitem = {
	name = "<NAME>",
	texture = "<PATH/TO/IMAGE.png>",
	slot_type = "storage|intel|liquid|radioactive|...",
	-- Optional
	stack_size = <COUNT>, --default: 1
	visual = "<VISUAL>", -- visual to use when visible in world
	-- Recipe of produced item
	production_recipe = CreateProductionRecipe(
		{ <INGREDIENT_ITEM_ID> = <INGREDIENT_NUM>, ... },
		{ <PRODUCTION_COMPONENT_ID> = <PRODUCTION_TICKS>, }
		-- Optional
		<AMOUNT_NUM>, --default: 1
	),
	-- Recipe of resources harvested from the world
	mining_recipe = CreateMiningRecipe({ <MINER_COMPONENT_ID = <MINING_TICKS>, ... }),
}

-- when renaming an id
data.update_mapping.simulation_data = "datacube_matrix"

]]

data.items.metalore = {
	tag = "resource", index = 1, name = "Metal Ore",
	desc = "Rock permeated with shiny fragments of strong building material",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_metalore",
	texture = "Main/textures/icons/items/metalore.png",
	mining_recipe = CreateMiningRecipe({
		c_miner = 30,
		c_adv_miner = 15,
		c_human_miner = 20,
		c_alien_miner = 30,
	}),
}

data.items.crystal = {
	tag = "resource", index = 2, name = "Crystal Chunk",
	desc = "An unprocessed grouping of raw crystals",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_crystal",
	texture = "Main/textures/icons/items/rawcrystal.png",
	mining_recipe = CreateMiningRecipe({
		c_miner = 25,
		c_adv_miner = 12,
		c_human_miner = 20,
		c_alien_miner = 25,
	}),
}

data.items.laterite = {
	tag = "resource", index = 4, name = "Laterite Ore",
	desc = "Unprocessed rocks rich in Aluminum",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_laterite",
	texture = "Main/textures/icons/items/laterite.png",
	mining_recipe = CreateMiningRecipe({
		c_extractor = 30,
		c_human_miner = 30,
		c_alien_miner = 30,
	}),
}

data.items.aluminiumrod = {
	tag = "simple_material", race = "human", index = 3001, name = "Aluminum Rod",
	desc = "Lightweight rods of pure Aluminum",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_aluminium_rod",
	texture = "Main/textures/icons/items/aluminumcops.png",
	production_recipe = CreateProductionRecipe({ laterite = 3, metalore = 1 }, { c_human_factory = 60, c_refinery = 120, c_human_refinery = 40, c_human_commandcenter = 60 }),
}

data.items.aluminiumsheet = {
	tag = "simple_material", race = "human", index = 3002, name = "Aluminum Sheet",
	desc = "Flat sheets of pure Aluminum",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_aluminium_sheet",
	texture = "Main/textures/icons/items/aluminumsheets.png",
	production_recipe = CreateProductionRecipe({ aluminiumrod = 1, silica = 1 }, { c_human_factory = 150, c_refinery = 200, c_human_refinery = 100, c_human_commandcenter = 120 }),
}

data.items.silica = {
	tag = "resource", index = 3, name = "Silica Sand",
	desc = "Silica sand, usually found at high altitudes",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_silica",
	texture = "Main/textures/icons/items/silica.png",
	mining_recipe = CreateMiningRecipe({
		c_miner = 30,
		c_adv_miner = 15,
		c_human_miner = 20,
		c_alien_miner = 30,
	}),
}

data.items.fused_electrodes = {
	tag = "hitech_material", race = "robot", index = 1004, name = "Fused Electrodes",
	desc = "Electrodes, but fused",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/fused_electrodes.png",
	visual = "v_fused_electrodes",
	production_recipe = CreateProductionRecipe({ refined_crystal = 2, silicon = 1, }, { c_advanced_refinery = 300 }), -- c_refinery
}

data.items.reinforced_plate = {
	tag = "advanced_material", index = 1, name = "Reinforced Plate",
	desc = "Plates re-engineered with added strength and durability",
	slot_type = "storage",
	-- race = "robot",
	stack_size = 20,
	texture = "Main/textures/icons/items/reinforced_plate.png",
	visual = "v_reinforced_plate",
	production_recipe = CreateProductionRecipe({ metalbar = 2, metalplate = 1 }, {
		c_assembler = 40,
		c_human_factory = 40
	}),
}

data.items.optic_cable = {
	tag = "hitech_material", race = "robot", index = 1003, name = "Optic Cable",
	desc = "Cable that sends signals using light",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/optic_cable.png",
	visual = "v_optic_cable",
	production_recipe = CreateProductionRecipe({ refined_crystal = 2, cable = 2 }, { c_refinery = 200, c_advanced_refinery = 35 }),
}

data.items.circuit_board = {
	tag = "advanced_material", race = "robot", index = 1001, name = "Circuit Board",
	desc = "A board full of circuits",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/circuit_board.png",
	visual = "v_circuit_board",
	production_recipe = CreateProductionRecipe({ metalplate =  3, crystal = 5 }, { c_assembler = 60, c_human_factory = 40 }),
}

data.items.infected_circuit_board = {
	tag = "advanced_material", race = "robot", index = 1002, name = "Infected Circuit Board",
	desc = "Virus infected circuit board. Can be used to override security systems.",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/infected_circuit_board.png",
	visual = "v_circuit_board_infected",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, bug_carapace = 1 }, { c_assembler = 120, c_mission_human_aicenter = 100, c_human_aicenter = 80 }),
}

data.items.obsidian = {
	tag = "resource", index = 6, name = "Obsidian Chunk",
	desc = "Black, volcanic ore",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_obsidian",
	texture = "Main/textures/icons/items/obsidian.png",
	mining_recipe = CreateMiningRecipe({
		c_extractor = 50,
		c_human_miner = 30,
		c_alien_miner = 50,
		c_virus_claws = 50,
	}),
}

data.items.obsidian_infected = {
	tag = "resource", race = "virus", index = 9, name = "Infected Obsidian Chunk",
	desc = "Black, volcanic ore infected with the virus",
	texture = "Main/textures/icons/items/obsidian_infected.png",
	slot_type = "virus",
	stack_size = 20,
	visual = "v_obsidian",
	-- production_recipe = CreateProductionRecipe({ obsidian = 5, bug_carapace = 5 }, { c_virus_decomposer = 60 }),
}

data.items.metalbar = {
	tag = "simple_material", index = 1, name = "Metal Bar",
	desc = "Bars of metal created from smelted ore",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_metalbar",
	texture = "Main/textures/icons/items/metalbar.png",
	production_recipe = CreateProductionRecipe({ metalore = 1 }, { c_fabricator = 20, c_human_refinery = 40 }),
}

data.items.metalplate = {
	tag = "simple_material", index = 2, name = "Metal Plate",
	desc = "Flat, heavy sheets created from smelted ore",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_metalplate",
	texture = "Main/textures/icons/items/metalplate.png",
	production_recipe = CreateProductionRecipe({ metalbar = 2 }, { c_fabricator = 30, c_human_refinery = 60 }),
}

data.items.foundationplate = {
	tag = "simple_material", race = "robot", index = 1001, name = "Foundation Plate",
	desc = "Machine-pressed and formed metal foundation",
	slot_type = "storage",
	stack_size = 40,
	texture = "Main/textures/icons/items/foundation_plate.png",
	production_recipe = CreateProductionRecipe({ metalbar = 1 }, { c_fabricator = 5 }, 5),
}

data.items.ldframe = {
	tag = "hitech_material", race = "human", index = 3002, name = "Low-Density Frame",
	desc = "Machine-pressed frame built for low weight applications",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/low_density_frame.png",
	visual = "v_low_density_frame",
	production_recipe = CreateProductionRecipe({ aluminiumsheet = 3, aluminiumrod = 3 }, { c_human_factory_robots = 200, c_human_factory = 120 }),
}

data.items.energized_plate = {
	tag = "advanced_material", race = "robot", index = 1004, name = "Energized Plate",
	desc = "Machine-pressed frame built for heavy-duty applications",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/energized_plate.png",
	visual = "v_energized_plate",
	production_recipe = CreateProductionRecipe({ reinforced_plate = 2, crystal = 2 }, { c_robotics_factory = 100, c_human_factory = 200 }),
}

data.items.hdframe = {
	tag = "hitech_material", race = "robot", index = 1001, name = "High-Density Frame",
	desc = "Machine-pressed frame built for heavy-duty applications",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/high_density_frame.png",
	visual = "v_high_density_frame",
	production_recipe = CreateProductionRecipe({ energized_plate = 3, wire = 3 }, { c_robotics_factory = 150 }),
}

data.items.uframe = {
	tag = "hitech_material", race = "robot", index = 1005, name = "Ultra Frame",
	desc = "Micro layered high and low density frames",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/ultra_frame.png",
	visual = "v_high_density_frame",
	production_recipe = CreateProductionRecipe({ hdframe = 5, ldframe = 5 }, { c_advanced_refinery = 240 }),
}

data.items.beacon_frame = {
	tag = "advanced_material", race = "robot", index = 1003, name = "Beacon Kit",
	desc = "A small beacon that can be built to mark locations on your minimap",
	slot_type = "storage",
	stack_size = 5,
	texture = "Main/textures/icons/items/beacon_material.png",
	visual = "v_beacon",
	production_recipe = CreateProductionRecipe({ circuit_board = 1, reinforced_plate = 1 }, { c_assembler = 36 }),
}

data.items.refined_crystal = {
	tag = "advanced_material", race = "robot", index = 1006, name = "Refined Crystal",
	desc = "A single polished crystal",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_refined_crystal",
	texture = "Main/textures/icons/items/refinedcrystal.png",
	production_recipe = CreateProductionRecipe({ energized_plate = 1, crystal_powder = 3 }, { c_refinery = 200, c_advanced_refinery = 40 }),
}

data.items.crystal_powder = {
	tag = "advanced_material", race = "robot", index = 1005, name = "Crystal Powder",
	desc = "A pile of ground crystal dust",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_crystal_powder",
	texture = "Main/textures/icons/items/crystalpowder.png",
	production_recipe = CreateProductionRecipe({ crystal = 3, silica = 1 }, {
		c_refinery = 120,
		c_advanced_refinery = 25,
		c_human_factory = 40,
	}),
}

data.items.plasma_crystal = {
	tag = "resource", race = "alien", index = 10, name = "Plasma Crystal",
	desc = "Crystal energized with plasma",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_plasma_crystal",
	texture = "Main/textures/icons/items/energized_crystal.png",
	production_recipe = CreateProductionRecipe({ crystal = 5, blight_plasma = 5 }, { c_alien_droneport = 100, c_bloom_producer = 100 }),
}

data.items.obsidian_brick = {
	tag = "simple_material", race = "alien", index = 5001, name = "Obsidian Brick",
	desc = "Volcanic rock that has been formed into bricks",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_obsidian_brick",
	texture = "Main/textures/icons/items/obsidianbrick.png",
	production_recipe = CreateProductionRecipe({ obsidian = 2, silica = 1 }, { c_advanced_refinery = 60, c_reforming_pool = 10, c_heart_factory = 30, c_alien_droneport = 10, c_reforming_pool_comp = 30, })
}

data.items.shaped_obsidian = {
	tag = "advanced_material", race = "alien", index = 5003, name = "Shaped Obsidian",
	desc = "Obsidian shapes formed from manipulating obsidian sub-structures",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_obsidian_brick", --- TODO
	texture = "Main/textures/icons/items/shaped_obsidian.png",
	production_recipe = CreateProductionRecipe({ obsidian_brick = 4, }, { c_alien_factory_robots = 200, c_reforming_pool = 20, c_alien_droneport = 30, c_reforming_pool_comp = 60, c_heart_factory = 60, c_advanced_refinery = 120 }),
}

data.items.crystalized_obsidian = {
	tag = "advanced_material", race = "alien", index = 5005, name = "Crystalized Obsidian",
	desc = "Restructured obsidian for better resonance with anomaly energies",
	slot_type = "storage",
	stack_size = 20,
	visual = "v_obsidian_brick", --- TODO
	texture = "Main/textures/icons/items/crystalized_obsidian.png",
	production_recipe = CreateProductionRecipe({ shaped_obsidian = 1, plasma_crystal = 5, blight_plasma = 5, unstable_matter = 1 }, { c_reforming_pool = 100, c_reforming_pool_comp = 200 }), -- c_reforming_pool_comp = 100
}

data.items.alien_artifact = {
	tag = "advanced_material", race = "alien", index = 5002, name = "Alien Artifact",
	desc = "A mysterious contraption of unknown origin",
	slot_type = "storage",
	research_type = "alien",
	research_points = 40,
	texture = "Main/textures/icons/items/alien_artifact.png",
	visual = "v_alien_artifact",
	production_recipe = CreateProductionRecipe({ obsidian_brick = 3, blight_crystal = 1 }, { c_alien_factory_robots = 120, c_reforming_pool = 30, c_heart_factory = 80, c_reforming_pool_comp = 60 }), -- c_alien_factory = 80, c_alien_droneport = 40
	stack_size = 20,
}

data.items.alien_artifact_research = {
	tag = "research", race = "alien", index = 42, name = "Research Artifact",
	desc = "A strange obsidian formation that pulses with energy",
	slot_type = "storage",
	research_type = "alien",
	research_points = 40,
	texture = "Main/textures/icons/items/research_artifact.png",
	visual = "v_alien_artifact",
	production_recipe = CreateProductionRecipe({ empty_artifact_research = 2, energized_artifact = 1 }, { c_reforming_pool = 200, c_reforming_pool_comp = 400 }), --  c_alien_factory = 400, -- c_alien_factory_robots = 800, -- c_reforming_pool_comp = 200
	stack_size = 20,
}

data.items.empty_artifact_research = {
	tag = "research", race = "alien", index = 41, name = "Empty Research Artifact",
	desc = "A strange obsidian formation that pulses with energy",
	slot_type = "storage",
	research_type = "alien",
	research_points = 40,
	texture = "Main/textures/icons/items/empty_research_artifact.png",
	visual = "v_alien_artifact",
	production_recipe = CreateProductionRecipe({ blight_plasma = 10, shaped_obsidian = 2, unstable_matter = 1 }, { c_alien_factory_robots = 300, c_alien_droneport = 200 }),
	stack_size = 20,
}

data.items.silicon = {
	tag = "simple_material", index = 3, name = "Silicon",
	desc = "Silica that has been refined into pure silicon rods",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_silicon",
	texture = "Main/textures/icons/items/silicon.png",
	production_recipe = CreateProductionRecipe({ silica = 2 }, { c_fabricator = 80, c_human_refinery = 60 }),
}

data.items.wire = {
	tag = "simple_material", index = 4, name = "Wire",
	desc = "Metal cables useful in building electronics",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_wire",
	texture = "Main/textures/icons/items/wire.png",
	production_recipe = CreateProductionRecipe({ metalplate = 1, silica = 1 }, { c_fabricator = 80, c_human_refinery = 60 }),
}

data.items.cable = {
	tag = "advanced_material", race = "robot", index = 1007, name = "Cable",
	desc = "Metal cables useful in building electronics",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_cable",
	texture = "Main/textures/icons/items/cable.png",
	production_recipe = CreateProductionRecipe({ crystal = 2, wire = 2, silicon = 1 }, { c_refinery = 100, c_human_factory = 60, c_advanced_refinery = 20, }),
}

data.items.icchip = {
	tag = "hitech_material", race = "robot", index = 1002, name = "IC Chip",
	desc = "Simple semiconducting device used in electronics",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_icchip",
	texture = "Main/textures/icons/items/icchip.png",
	production_recipe = CreateProductionRecipe({ silicon = 3, circuit_board = 5, cable = 3 }, { c_robotics_factory = 300, c_human_factory = 200 }),
}

-- move to human factory
data.items.micropro = {
	tag = "hitech_material", race = "human", index = 3001, name = "Microprocessor",
	desc = "Man-made data processing unit",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_micropro",
	texture = "Main/textures/icons/items/microprocessor.png",
	production_recipe = CreateProductionRecipe({ blight_crystal = 10, blight_plasma = 5, icchip = 1 }, { c_robotics_factory = 200, c_human_factory_robots = 100, c_human_factory = 50 }),
}

data.items.cpu = {
	tag = "hitech_material", race = "alien", index = 5001, name = "CPU",
	desc = "Assemblage of microprocessors for advanced applications",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_cpu",
	texture = "Main/textures/icons/items/cpu.png",
	production_recipe = CreateProductionRecipe({ phase_leaf = 1, micropro = 1, blight_crystal = 5 }, { c_alien_factory_robots = 100, c_alien_factory = 80, c_alien_factory_comp = 80 }),
}

data.items.fuel_rod = {
	tag = "hitech_material", race = "human", index = 3003, name = "Reactor Fuel Rods",
	desc = "Consumed to provide energy to Micro Reactors",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/reactor_fuel_rods.png",
	visual = "v_fused_electrodes",
	production_recipe = CreateProductionRecipe({ laterite = 1, crystal = 5, }, { c_advanced_refinery = 100, c_human_commandcenter = 50, c_human_refinery = 25 }, 5),
}

data.items.enriched_fuel_rod = {
	tag = "hitech_material", race = "human", index = 3006, name = "Enriched Reactor Fuel Rods",
	desc = "Consumed to provide energy to Fusion Reactors",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/reactor_rods_enriched.png",
	visual = "v_fused_electrodes",
	production_recipe = CreateProductionRecipe({ fuel_rod = 10, steelblock = 1 }, { c_human_factory = 250 }),
}

--[[
data.items.plasma_rod = {
	tag = "hitech_material", race = "blight", index = 9999, name = "Plasma Reactor Rods",
	desc = "Consumed to provide energy to Fusion Reactors",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/plasma_reactor_rods.png",
	visual = "v_fused_electrodes",
	production_recipe = CreateProductionRecipe({ enriched_fuel_rod = 5, fused_electrodes = 5, blight_plasma = 5 }, { c_advanced_refinery = 150 }),
}
]]--

-- human resources
data.items.steelblock = {
	tag = "advanced_material", race = "human", index = 3006, name = "Steel Block",
	desc = "Steel blocks for building human ground units",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_metalplate",
	texture = "Main/textures/icons/items/steelblock.png",
	production_recipe = CreateProductionRecipe({ metalbar = 2, aluminiumrod = 1 }, { c_human_refinery = 200, c_advanced_refinery = 300 }), -- c_human_factory_robots = 100
}

data.items.concreteslab = {
	tag = "advanced_material", race = "human", index = 3005, name = "Concrete Slab",
	desc = "Concrete slab for making human foundations and buildings",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_metalplate",
	texture = "Main/textures/icons/items/concreteslab.png",
	production_recipe = CreateProductionRecipe({ silicon = 2, laterite = 2 }, { c_human_factory_robots = 200, c_human_refinery = 100, c_advanced_refinery = 250 }), -- c_human_factory_robots = 48
}

data.items.ceramictiles = {
	tag = "hitech_material", race = "human", index = 3004, name = "Ceramic Tiles",
	desc = "Silicon Carbide tiles for protection of space vehicles",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_metalplate",
	texture = "Main/textures/icons/items/ceramictile.png",
	production_recipe = CreateProductionRecipe({ silicon = 1, concreteslab = 2 }, { c_human_refinery = 150, c_advanced_refinery = 250 }), -- c_human_factory_robots = 50
}

data.items.polymer = {
	tag = "hitech_material", race = "human", index = 3005, name = "Composite Mesh",
	desc = "Plastic, resilient material for human units and buildings",
	stack_size = 20,
	slot_type = "storage",
	visual = "v_metalplate",
	texture = "Main/textures/icons/items/polymer.png",
	production_recipe = CreateProductionRecipe({ steelblock = 2, ceramictiles = 3 }, { c_human_factory = 200, c_advanced_refinery = 300  }),  -- c_human_factory_robots = 48
}

-- Research data


----------- THIS IS THE INTEL CUBES  --------------

----------- xxxxx_datacube  --------------
----------- xxxxx_databank  --------------

data.items.robot_datacube = {
	tag = "research", index = 1, name = "Robotics Datacube",
	desc = "A cube of incredibly dense data, the result of running millions of simulations",
	locked_desc = "Located in ruined structures throughout the world",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/robot_research_cube.png",
	visual = "v_robot_data",
	production_recipe = CreateProductionRecipe({ crystal_powder = 2, hdframe = 1 }, { c_robotics_factory = 300, }),
}

data.items.alien_datacube = {
	tag = "research", index = 5, name = "Alien Datacube",
	desc = "Partial data on alien technology. Further analysis required.",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/alien_datacube.png",
	visual = "v_alien_data",
	production_recipe = CreateProductionRecipe({ obsidian_brick = 5, anomaly_cluster = 1 }, { c_alien_factory_robots = 300, }),
}

data.items.human_datacube = {
	tag = "research", index = 3, name = "Human Datacube",
	desc = "Data collected by remote-unit observation and recording",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/human_datacube.png",
	visual = "v_human_data",
	production_recipe = CreateProductionRecipe({ blight_crystal = 1, laterite = 5 }, { c_human_aicenter = 300, c_human_factory_robots = 400, c_human_factory = 400, }),
}

data.items.blight_datacube = {
	tag = "research", index = 2, name = "Blight Datacube",
	desc = "Data collected by remote-unit observation and recording",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/blight_datacube.png",
	visual = "v_alien_data",
	production_recipe = CreateProductionRecipe({ robot_datacube = 1, blight_plasma = 5 }, { c_refinery = 300, c_human_aicenter = 240 }),
}

data.items.virus_research_data = {
	tag = "research", index = 4, name = "Virus Datacube",
	desc = "A section of virus code, needed to learn the nature of the virus",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/virus_research_data.png",
	visual = "v_virus_data",
	production_recipe = CreateProductionRecipe({ robot_datacube = 1, infected_circuit_board = 1 }, { c_virus_decomposer = 300, }),
}

data.items.empty_databank = {
	tag = "research", race = "human", index = 31, name = "Empty Data Bank",
	desc = "A databank that can hold research data",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/empty_databank.png",
	visual = "v_simulation_data",
	production_recipe = CreateProductionRecipe({ aluminiumsheet = 5, steelblock = 2 }, { c_human_science_analyzer_robots = 320, c_human_factory = 200 }), -- c_human_data_processor = 100, -- aluminiumrod = 5, silicon = 5
	-- production_recipe = CreateProductionRecipe({ ldframe = 2, microscope = 1 }, { c_human_science_analyzer_robots = 160 }),
}

data.items.human_databank = {
	tag = "research", race = "human", index = 32, name = "Human Data Bank",
	desc = "A databank that holds human research data",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/human_databank.png",
	visual = "v_human_data",
	production_recipe = CreateProductionRecipe({ human_datacube = 1, empty_databank = 1 }, { c_human_science_analyzer_robots = 240, c_mission_human_aicenter = 200, c_human_aicenter= 160 }), -- c_human_data_processor = 120
}

--------   THIS IS THE SIMULATION MATRICES   ------

----------- EMPTY matrices  --------------
----------- datacube_matrix  --------------

data.items.datacube_matrix = {
	tag = "research", race = "robot", index = 11, name = "Datacube Matrix",
	desc = "A construct that allows access to the dense layers of datacubes",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/simulationdata.png",
	visual = "v_simulation_data",
	production_recipe = CreateProductionRecipe({ optic_cable = 2, hdframe = 2 }, { c_robotics_factory = 320, }),
}


----------- RESEARCH Matrices  --------------
----------- Datacube + Empty Matrix ---------

----------- xxxxxx_research


data.items.robot_research = {
	tag = "research", race = "robot", index = 12, name = "Robotics Research",
	desc = "Allows for advanced robotic technology",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/robot_research.png",
	visual = "v_advanced_robotics_research",
	production_recipe = CreateProductionRecipe({ datacube_matrix = 1, robot_datacube = 1 }, { c_data_analyzer = 400, }),
}


data.items.human_research = {
	tag = "research", race = "robot", index = 14, name = "Human Research",
	desc = "Data analysis of human technology",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/human_research.png",
	visual = "v_human_research_item",
	production_recipe = CreateProductionRecipe({ datacube_matrix = 1, human_datacube = 1 }, { c_data_analyzer = 400, }),
}

data.items.alien_research = {
	tag = "research", race = "robot", index = 16, name = "Alien Research",
	desc = "Data analysis of alien technology",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/alien_research.png",
	visual = "v_alien_research_item",
	production_recipe = CreateProductionRecipe({ alien_datacube = 1, datacube_matrix = 1 }, { c_data_analyzer = 400, }),
}

data.items.blight_research = {
	tag = "research", race = "robot", index = 13, name = "Blight Research",
	desc = "Scans of the hostile environment endemic to planet",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/blight_research.png",
	visual = "v_blight_research_item",
	production_recipe = CreateProductionRecipe({ datacube_matrix = 1, blight_datacube = 1, }, { c_data_analyzer = 400, }),
}

data.items.virus_research = {
	tag = "research", race = "robot", index = 15, name = "Virus Research",
	desc = "Computer-modeled analysis of the viral pathogen",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/virus_research.png",
	visual = "v_virus_research",
	production_recipe = CreateProductionRecipe({ virus_research_data = 1, datacube_matrix = 1 }, { c_data_analyzer = 400, }),
}

--------- DEPRECATED PACKAGES ---------
local deprecated_item_def = { slot_type = "storage", stack_size = 1, index = 0, name = "package", texture = "Main/textures/icons/items/packeddrone_a.png" }
data.items.drone_transfer_package  = deprecated_item_def
data.items.drone_transfer_package2 = deprecated_item_def
data.items.drone_miner_package     = deprecated_item_def
data.items.drone_adv_miner_package = deprecated_item_def
data.items.drone_defense_package1  = deprecated_item_def
data.items.flyer_package_m         = deprecated_item_def
data.items.satellite_package       = deprecated_item_def
data.items.space_satellite_package = deprecated_item_def

data.items.blight_crystal = {
	tag = "resource", index = 5, name = "Blight Crystal Chunk",
	desc = "A crystal energized with power",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/blightcrystal.png",
	visual = "v_blight_crystal",
	mining_recipe = CreateMiningRecipe({
		c_miner = 50,
		c_adv_miner = 25,
		c_human_miner = 30,
		c_alien_miner = 50,
	}),
}

data.items.blight_extraction = {
	tag = "resource", race = "blight", index = 8, name = "Blight Gas",
	desc = "Extracted blight gas essence. Needs a container component to be held.",
	texture = "Main/textures/icons/items/blight_extraction.png",
	slot_type = "gas",
	stack_size = 100,
	extracted_by = { c_blight_extractor = true },
}

data.items.blightbar = {
	tag = "simple_material", index = 5, name = "Blight Bar",
	desc = "A bar of blight",
	texture = "Main/textures/icons/items/blightbar.png",
	visual = "v_blightbar",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ metalbar = 2, blight_crystal = 5 }, { c_refinery = 100, c_human_refinery = 100 }),
}

data.items.blight_plasma = {
	tag = "simple_material", race = "blight", index = 2001, name = "Blight Plasma",
	desc = "Processed blight gas into a goop form",
	texture = "Main/textures/icons/items/blight_plasma.png",
	slot_type = "storage",
	visual = "v_blight_plasma",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ blight_extraction = 20, blight_crystal = 5 }, { c_refinery = 150, c_human_datacomplex = 120 }),
}

data.items.gearbox = {
	tag = "advanced_material", race = "human", index = 3007, name = "Gear Box",
	desc = "Useful for repairing Human technology",
	texture = "Main/textures/icons/items/human/gearbox.png",
	visual = "v_gears",
	slot_type = "storage",
	stack_size = 20,
	-- production_recipe = CreateProductionRecipe({ reinforced_plate = 5, aluminiumrod = 5 }, { c_assembler = 200, c_human_factory = 50, c_human_commandcenter = 100 }), --blightbar = 5
	production_recipe = CreateProductionRecipe({ metalbar = 2, aluminiumrod = 1 }, { c_advanced_assembler = 200, c_human_barracks = 50, c_human_commandcenter = 100, }),
}

data.items.microscope = {
	tag = "advanced_material", race = "human", index = 3003, name = "Microscope",
	desc = "Useful for repairing Human technology",
	texture = "Main/textures/icons/items/human/microscope.png",
	visual = "v_microscope",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ transformer = 1, wire = 1, ldframe = 1 }, { c_human_factory_robots = 200, c_human_aicenter = 100, c_human_factory = 300,  }),
}

data.items.transformer = {
	tag = "advanced_material", race = "human", index = 3001, name = "Transformer",
	desc = "Useful for repairing Human technology",
	texture = "Main/textures/icons/items/human/transformer.png",
	visual = "v_transformer",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ crystal = 1, reinforced_plate = 1 }, {
		c_assembler = 150,
		c_human_factory_robots = 100,
		c_human_vehiclefactory = 30
	}),
}

data.items.smallreactor = {
	tag = "advanced_material", race = "human", index = 3002, name = "Small Modular Reactor",
	desc = "Mini Power Reactor for Small Units",
	texture = "Main/textures/icons/items/human/smallreactor.png",
	visual = "v_small_reactor",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ transformer = 1, blightbar = 1 }, {
		c_assembler = 200,
		c_human_factory_robots = 150,
		c_human_vehiclefactory = 50
	}),
	-- production_recipe = CreateProductionRecipe({ transformer = 1, blightbar = 1 }, { c_advanced_assembler = 200, c_human_factory = 100, c_human_factory_robots = 150, }),
}

data.items.engine = {
	tag = "advanced_material", race = "human", index = 3004, name = "Engine",
	desc = "Develop Human Flight Capability",
	texture = "Main/textures/icons/items/human/engine.png",
	visual = "v_engine",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ smallreactor = 1, aluminiumsheet = 10 }, {
		c_human_factory_robots = 200,
		c_human_vehiclefactory = 100
	}),
}

data.items.datakey = {
	tag = "research", index = 21, name = "Blank Datakey",
	desc = "Datakeys store key information and have interface ports for secure access points",
	texture = "Main/textures/icons/items/datakey_empty.png",
	visual = "v_gears",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ blightbar = 5, aluminiumrod = 10 }, { c_assembler = 60, c_human_datacomplex = 30 }),
}

data.items.datakey_blight = {
	tag = "research", race = "blight", index = 23, name = "Blight Datakey",
	desc = "Holds key Blight data and has a port interfacing with administrative consoles",
	texture = "Main/textures/icons/items/datakey_blight.png",
	visual = "v_gears",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ datakey_human = 1 }, { c_human_science_analyzer_robots = 30, c_human_factory = 30, c_human_datacomplex = 30 }),
}

data.items.datakey_human = {
	tag = "research", race = "human", index = 24, name = "Human Datakey",
	desc = "Holds key Human data and Human research analysis",
	texture = "Main/textures/icons/items/datakey_human.png",
	visual = "v_gears",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ datakey = 1, human_research = 1 }, { c_human_science_analyzer_robots = 30, c_human_datacomplex = 30 }),
}

data.items.datakey_virus = {
	tag = "research", race = "virus", index = 25, name = "Virus Datakey",
	desc = "Holds key Virus data and has a port for hacking into administrative consoles",
	texture = "Main/textures/icons/items/datakey_virus.png",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ virus_source_code = 1, datakey_human = 1 }, { c_human_science_analyzer_robots = 30, c_human_datacomplex = 30 }),
}

data.items.datakey_alien = {
	tag = "research", race = "alien", index = 26, name = "Alien Datakey",
	desc = "Holds key Alien data and has interface ports for Alien structures",
	texture = "Main/textures/icons/items/datakey_alien.png",
	visual = "v_gears",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ datakey_blight = 1, alien_research = 1 }, { c_adv_alien_factory = 30,  }),
}

data.items.datakey_robot = {
	tag = "research", race = "robot", index = 22, name = "Robot Datakey",
	desc = "Holds key Robot and Simulation data",
	texture = "Main/textures/icons/items/datakey_robot.png",
	visual = "v_gears",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ robot_research = 1, datakey = 1 }, { c_data_analyzer = 30, c_human_datacomplex = 30  }),
}

data.items.higgs_source_code = {
	tag = "hitech_material", race = "human", index = 3011, name = "HIGGS Source Code",
	desc = "Evolved HIGGS data",
	slot_type = "virus",
	stack_size = 1,
	texture = "Main/textures/icons/items/code_HIGGS.png",
	production_recipe = CreateProductionRecipe({ virus_source_code = 1, blight_extraction = 20 }, { c_human_datacomplex = 120 }),
}

data.items.anomaly_heart = {
	tag = "advanced_material", race = "alien", index = 5001, name = "Anomaly Heart",
	desc = "A conscious ball of energy",
	texture = "Main/textures/icons/items/anomaly_heart.png",
	slot_type = "anomaly",
	stack_size = 5,
	production_recipe = CreateProductionRecipe({ blight_plasma = 20, anomaly_cluster = 1 }, { c_space_elevator_factory = 150, c_alien_factory_robots = 300, c_heart_factory = 100, c_bloom_producer = 100 }), --  c_alien_factory = 150, -- blight_plasma = 20, anomaly_cluster = 1
}

data.items.bot_ai_core = {
	tag = "hitech_material", race = "alien", index = 5021, name = "AI Core",
	desc = "An advanced AI core with control capabilities that interface with advanced technologies such as the Mothership navigation systems.\n\n<bl>Core Function</>: The ability to adapt and evolve to overcome adversity and improve efficiency",
	slot_type = "storage",
	stack_size = 1,
	texture = "Main/textures/icons/items/ai_core_PLAYER.png",
	visual = "v_bot_ai_core",
	production_recipe = false,
}

data.items.elain_ai_core = {
	tag = "hitech_material", race = "human", index = 3024, name = "ELAIN AI Core",
	desc = "<hl>E</>mergent\n<hl>L</>ogistics\n<hl>A</>rtificial\n<hl>I</>ntelligence\n<hl>N</>etwork.\n\n<bl>Core Function</>: Responsible for guidance and assistance throughout our mission expanding our knowledge base into undiscovered technologies",
	slot_type = "storage",
	stack_size = 1,
	texture = "Main/textures/icons/items/ai_core_ELAIN.png",
	visual = "v_bot_ai_core",
	production_recipe = false,
}

data.items.energized_artifact = {
	tag = "advanced_material", race = "alien", index = 5004, name = "Energized Artifact",
	desc = "An activated alien artifact",
	slot_type = "storage",
	research_type = "alien",
	research_points = 40,
	texture = "Main/textures/icons/items/alien_artifact_energized.png",
	visual = "v_alien_artifact",
	production_recipe = CreateProductionRecipe({ alien_artifact = 1, anomaly_heart = 1 }, { c_reforming_pool = 30, c_reforming_pool_comp = 90, c_heart_factory = 60, c_space_elevator_factory = 10, c_alien_factory_robots = 120 }), -- c_alien_factory = 40,
	stack_size = 20,
}

data.items.higgs_oop_ai_core = {
	tag = "hitech_material", race = "human", index = 3022, name = "HIGGS Out-of-Phase AI Core",
	desc = "The advanced controller unit of HIGGS, but it is not syncing properly",
	slot_type = "storage",
	stack_size = 1,
	texture = "Main/textures/icons/items/ai_out-of-phase-HIGGS.png",
	visual = "v_bot_ai_core",
	production_recipe = false,
}

data.items.higgs_ai_ac = {
	tag = "hitech_material", race = "human", index = 3023, name = "HIGGS AI Core",
	desc = "The advanced controller unit of HIGGS",
	slot_type = "storage",
	texture = "Main/textures/icons/items/ai_core_HIGGS.png",
	visual = "v_bot_ai_core",
	stack_size = 1,
	production_recipe = CreateProductionRecipe({ elain_ai_core = 1, higgs_source_code = 1 }, { c_mission_human_aicenter = 150, c_human_aicenter = 100, c_human_science_analyzer_robots = 300 }),
}

data.items.higgs_broken_core = {
	tag = "hitech_material", race = "human", index = 3021, name = "HIGGS Broken Core",
	desc = "Advanced HIGGS controller, but all smashed up",
	slot_type = "storage",
	texture = "Main/textures/icons/items/ai_HIGGS_broken.png",
	visual = "v_bot_ai_core",
	stack_size = 1,
	production_recipe = false,
}

data.items.bug_carapace = {
	tag = "resource", index = 7, name = "Bug Chitin",
	desc = "Silica reinforced shell of bugs",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/bug_chitin.png",
	production_recipe = CreateProductionRecipe({ silica = 2, blight_crystal = 2 }, { c_refinery = 200, c_mission_human_aicenter = 150, c_human_aicenter = 120, }),
	visual = "v_default_item",
}

data.items.anomaly_particle = {
	tag = "hitech_material", race = "alien", index = 5011, name = "Anomaly Particle",
	desc = "A particle of pure anomaly data",
	slot_type = "anomaly",
	stack_size = 20,
	texture = "Main/textures/icons/items/anomaly_particle.png",
	visual = "v_bot_ai_core",
	extracted_by = {
		c_anomaly_container_i = true,
	},
	production_recipe = CreateProductionRecipe({ unstable_matter = 1 }, { c_particle_forge = 150 }),
}

data.items.anomaly_cluster = {
	tag = "hitech_material", race = "alien", index = 5003, name = "Dense Anomaly Cluster",
	slot_type = "anomaly",
	stack_size = 10,
	texture = "Main/textures/icons/items/anomaly_cluster.png",
	visual = "v_bot_ai_core",
	production_recipe = CreateProductionRecipe({ anomaly_particle = 5 }, { c_mission_human_aicenter = 200, c_human_aicenter = 150, c_human_science_analyzer_robots = 300, c_alien_factory_robots = 300 }),
}

data.items.power_petal = {
	tag = "hitech_material", race = "alien", index = 5004, name = "Power Petal",
	desc = "A flower petal infused with power",
	slot_type = "storage",
	stack_size = 10,
	production_recipe = CreateProductionRecipe({ obsidian_brick = 5, blight_extraction = 10 }, { c_advanced_refinery = 150 }), -- c_refinery
	texture = "Main/textures/icons/items/leaves_power.png",
}

data.items.phase_leaf = {
	tag = "hitech_material", race = "alien", index = 5002, name = "Phase Leaf",
	desc = "A leave that shifts and shimmers in place",
	slot_type = "storage",
	stack_size = 10,
	production_recipe = CreateProductionRecipe({ obsidian_brick = 5, blight_plasma = 5 }, { c_advanced_refinery = 200 }), -- c_refinery
	texture = "Main/textures/icons/items/leaves_phase.png",
}

data.items.virus_source_code = {
	tag = "hitech_material", race = "virus", index = 4001, name = "Virus Source Code",
	desc = "A seemingly malicious piece of source code that tries to alter the structures of infected systems. Recovered from a Glitch bot using a Cure Virus and Containment Component.",
	slot_type = "virus",
	stack_size = 1,
	texture = "Main/textures/icons/items/code_virus.png",
}

data.items.rainbow_research = {
	tag = "research", index = 17, name = "MultiCube",
	desc = "A cocktail of research data",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/rainbow_research.png",
	visual = "v_default_item",
	production_recipe = CreateProductionRecipe({ robot_research = 1, human_research = 1, virus_research = 1, alien_research = 1, blight_research = 1 }, { c_data_analyzer = 400 }),
}

data.items.rainbowframe = {
	tag = "research", race = "robot", index = 18, name = "Multi-frame",
	desc = "Ultra frames that integrate the full range of technologies",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/rainbow_frame.png",
	visual = "v_high_density_frame",
	production_recipe = CreateProductionRecipe({ uframe = 1, crystalized_obsidian = 3, obsidian_infected = 3 }, { c_particle_forge = 250 }),
}

data.items.datakey_rainbow = {
	tag = "research", race = "alien", index = 27, name = "Multi-key",
	desc = "A skeleton key",
	texture = "Main/textures/icons/items/datakey_rainbow.png",
	visual = "v_gears",
	slot_type = "storage",
	stack_size = 20,
	production_recipe = CreateProductionRecipe({ datakey_blight = 1, datakey_virus = 1, datakey_human = 1, datakey_alien = 1, datakey_robot = 1,  }, { c_adv_alien_factory = 30,  }),
}

data.items.unstable_matter = {
	tag = "advanced_material", index = 9001, name = "Unstable Matter",
	desc = "Unstable Matter",
	slot_type = "storage",
	stack_size = 20,
	texture = "Main/textures/icons/items/unstable_matter.png",
}
