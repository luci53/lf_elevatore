-- NOTE: This file is SERVER-ONLY since v3. Clients receive a sanitized copy of the
-- elevator data (PIN codes are stripped), so codes can safely live in this file.

Config = {}

-- Framework: 'auto' detects qbx_core -> qb-core -> es_extended at runtime.
-- Set to 'qbox', 'qbcore' or 'esx' to force a specific framework.
Config.Framework = 'auto'

-- Third-eye targeting: 'auto' detects ox_target -> qb-target.
-- Set to 'ox_target', 'qb-target', or false to disable targeting entirely.
Config.Target = 'auto'

Config.UseTextUI = true				-- ox_lib TextUI prompt + interact key (works with or without targeting)
Config.InteractKey = 38				-- Control id for the TextUI interaction (38 = E)
Config.InteractDistance = 2.0		-- Distance at which the TextUI prompt appears

Config.ElevatorWaitTime = 3			-- Seconds of "travel time" between floors (screen stays faded)
Config.FadeTime = 1000				-- Screen fade in/out duration in ms

Config.Debug = false				-- Draw target/zone debug outlines

-- Players standing close to whoever presses the button ride along.
-- Per elevator override: set `groupTravel = false` on the elevator table.
Config.GroupTravel = {
	enabled = true,
	radius = 3.0,					-- meters around the requester
}

-- Sounds. Each is { type = 'native', name, set } or { type = 'interact-sound', name, volume }, or false.
Config.Sounds = {
	arrive = { type = 'native', name = 'PICK_UP', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },	-- on arrival
	travel = false,																			-- looped/started while "travelling" (false = none)
	-- arrive = { type = 'interact-sound', name = 'ding', volume = 0.3 },	-- requires interact-sound resource
}

Config.ArrivalShake = true			-- subtle camera shake on arrival for immersion

-- Time-restricted floors (the `hours` floor option). By default the in-game
-- floor hours are compared against the server's real-world hour. To use your
-- own time source (e.g. an in-game clock resource), return 0-23 from getHour.
Config.BusinessHours = {
	getHour = nil,	-- e.g. function() return GlobalState.gameHour end
}

-- Usage logging. Logs whenever a restricted/PIN/owner floor is used (or every
-- move if logAllMoves = true).
Config.Logging = {
	enabled = false,
	logAllMoves = false,
	useOxLib = false,	-- send through ox_lib's lib.logger (configure ox:logger convar)
	webhook = '',		-- Discord webhook URL (leave empty to skip)
}

-- Ace principal allowed to use the in-game /elevator creator command.
Config.AdminGroup = 'group.admin'

--[[
	Elevator format (each elevator is an array of floors):

	coords     - vector3, where the player is teleported to / interacts from (required)
	heading    - number, heading applied after teleport (default 0.0)
	level      - string, name shown in menus and prompts (required)
	label      - string, description shown under the floor name
	size       - vector3, target zone size override (default vec3(5.0, 4.0, 3.0))

	Restrictions (all optional - floor is public when none are set):
	jobs       - { [jobName] = minGrade }   e.g. { police = 0, ambulance = 2 }
	gangs      - { [gangName] = minGrade }  QBox/QBCore (ox_core treats both as groups)
	items      - { 'item_a', 'item_b' }     player needs at least one of these
	owners     - { 'CITIZENID', 'license:abc' }  only these identities may use it
	consumeItem- true = remove 1 of the matched access item on a successful trip
	hours      - { open = 9, close = 17 }   floor only usable in this window
	             (overnight ok, e.g. { open = 22, close = 6 }); see Config.BusinessHours
	requireAll - true = must pass EVERY restriction type set above
	             false/nil = passing ANY restriction type is enough
	             ('jobAndItem' from v1 configs is still accepted)
	pin        - string PIN code, e.g. '4521'. Asked via keypad, checked on the
	             server, never sent to clients. Applies on top of other restrictions.
	bucket     - number, routing bucket players are moved into on arrival
	             (for instanced interiors). Use 0 to return to the public world.
	             Omit to leave the player's bucket unchanged.

	Elevator-level keys (optional, set next to the floor list):
	label       - menu title for this elevator
	groupTravel - false to disable group travel for this elevator only
]]

Config.Elevators = {
	--[[Mafia = {
		label = 'Mafia HQ',
		groupTravel = true,
		{
			coords = vector3(368.97, -59.72, 111.96), heading = 0.0,
			level = 'Floor 2', label = 'Penthouse',
			jobs = { mafia = 2 },
			pin = '4521',
			bucket = 1,
		},
		{
			coords = vector3(370.17, -56.24, 103.36), heading = 0.0,
			level = 'Floor 1', label = 'Offices',
			jobs = { mafia = 0 },
			bucket = 1,
		},
		{
			coords = vector3(380.71, -15.17, 83.0), heading = 0.0,
			level = 'Floor 0', label = 'Ground',
			bucket = 0,
		},
	},]]
}
