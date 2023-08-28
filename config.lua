Config = {}

Config.UseESX = false						-- Use ESX Framework
Config.UseQBCore = true					-- Use QBCore Framework (Ignored if Config.UseESX = true)

Config.ThirdEyeName = 'qb-target' 			-- Name of third eye aplication
Config.Use3DText = true                        -- Use 3D text to interact
Config.NHMenu = false						-- Use NH-Context [https://github.com/nighmares/nh-context]
Config.QBMenu = true						-- Use QB-Menu (Ignored if Config.NHInput = true) [https://github.com/qbcore-framework/qb-input]
Config.OXLib = false						-- Use the OX_lib (Ignored if Config.NHInput or Config.QBInput = true) [https://github.com/overextended/ox_lib] !! must add shared_script '@ox_lib/init.lua' and lua54 'yes' to fxmanifest!!
Config.ElevatorWaitTime = 3					-- How many seconds until the player arrives at their floor

Config.Notify = {
	enabled = true,							-- Display hint notification?
	distance = 3.0,							-- Distance from elevator that the hint will show
	message = "Target the elevator to use"	-- Text of the hint notification
}

Config.Elevators = {
	--[[Mafia = {	
		{
			coords = vector3(368.97, -59.72, 111.96), heading = 0.0, level = "Floor 2", label = "Level 2",
		},
		{ 																											--	Use this as example and make your elevatores
			coords = vector3(370.17, -56.24, 103.36), heading = 0.0, level = "Floor 1", label = "Level 1",
		},
		{
			coords = vector3(380.71, -15.17, 83.0), heading = 0.0, level = "Floor 0", label = "Ground"
		},
	},]]
}
