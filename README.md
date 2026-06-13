# lf_elevatore

[![luacheck](https://github.com/luci53/lf_elevatore/actions/workflows/luacheck.yml/badge.svg)](https://github.com/luci53/lf_elevatore/actions/workflows/luacheck.yml)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Create your own elevators anywhere on your FiveM server — in the config **or live in-game with a command**. Framework-agnostic: works on **QBox**, **ox_core**, **QBCore** and **ESX** with automatic detection.

## Features

- 🛗 Unlimited elevators with unlimited floors
- 🔍 ox_target / qb-target third-eye support (auto-detected) + ox_lib TextUI `[E]` prompt
- 🛡️ **Server-side validation** — job, gang, item, owner and PIN checks run on the server, not the client
- 🔢 **PIN-code floors** — keypad dialog; codes live server-side and are never sent to clients
- 🎫 **Item access** — require an item, optionally **consumed** on use (one-time passes)
- 👤 **Owner-only floors** — restrict a floor to specific citizenids/identifiers
- ⏰ **Time-restricted floors** — open/close hours per floor (overnight windows supported)
- 🔧 **Maintenance lock** — take an elevator out of service live (`/elevator lock`, or via export for heists)
- 👥 **Group travel** — players standing next to you ride along
- 🌐 **Routing bucket support** — send players into instanced interiors per floor
- 🛠️ **In-game creator/editor** — build & edit elevators with commands, saved to JSON
- 🧩 **Developer API** — exports + events to drive elevators from other resources
- 📝 **Usage logging** — Discord webhook and/or ox_lib logger
- 🔔 Arrival sound + camera shake (immersion), optional travel sound
- 🌍 Translations via ox_lib locales (`locales/*.json`)

## Dependencies

| Resource | Required | Notes |
|----------|----------|-------|
| [ox_lib](https://github.com/CommunityOx/ox_lib) | ✅ Yes | Menus, TextUI, callbacks, locales |
| [ox_target](https://github.com/CommunityOx/ox_target) / [qb-target](https://github.com/qbcore-framework/qb-target) | Optional | Third-eye interaction (auto-detected) |
| [ox_inventory](https://github.com/CommunityOx/ox_inventory) | Optional | Used for item checks/consumption when present |

Supported frameworks (auto-detected): **qbx_core**, **ox_core**, **qb-core**, **es_extended**.

## Installation

1. Download or clone this repo into `resources/`
2. Make sure `ox_lib` starts **before** this resource
3. Add `ensure lf_elevatore` to your `server.cfg`
4. Configure elevators in `config.lua` — or just use `/elevator create` in-game
5. Restart your server

## In-game creator (admin)

Requires the ace permission set in `Config.AdminGroup` (default `group.admin`).

| Command | Description |
|---------|-------------|
| `/elevator create <name>` | Start building a new elevator |
| `/elevator add` | Add a floor at your current position (dialog: name, PIN, jobs, owners, hours, bucket…) |
| `/elevator removefloor <n>` | Remove floor number `n` from the current session |
| `/elevator save` | Save the elevator (needs at least 2 floors) — live for everyone instantly |
| `/elevator edit <name>` | Load a saved elevator back into a session to add/remove floors |
| `/elevator cancel` | Discard the current session |
| `/elevator delete <name>` | Delete an elevator created in-game |
| `/elevator lock <name>` / `unlock <name>` | Take an elevator out of / back into service |
| `/elevator list` | List all elevators (and their lock state) |

In-game elevators are stored in `data/elevators.json` and survive restarts.

## Configuration

`config.lua` is **server-only**: clients receive a sanitized copy of the elevator data, so PIN codes never leave the server.

```lua
Config.Framework = 'auto'       -- 'auto' | 'qbox' | 'oxcore' | 'qbcore' | 'esx'
Config.Target = 'auto'          -- 'auto' | 'ox_target' | 'qb-target' | false
Config.UseTextUI = true         -- [E] prompt via ox_lib TextUI
Config.ElevatorWaitTime = 3     -- travel time in seconds
Config.GroupTravel = { enabled = true, radius = 3.0 }
Config.ArrivalShake = true      -- camera shake on arrival
Config.Sounds = { arrive = { type = 'native', name = 'PICK_UP', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' }, travel = false }
Config.BusinessHours = { getHour = nil }   -- hook your in-game clock here; defaults to server real time
Config.Logging = { enabled = false, logAllMoves = false, useOxLib = false, webhook = '' }
```

### Adding an elevator

```lua
Config.Elevators = {
    Hospital = {
        label = 'Pillbox Hospital',
        {
            coords = vector3(338.54, -583.88, 74.16), heading = 250.0,
            level = 'Roof', label = 'Helipad',
            jobs = { ambulance = 0 },
        },
        {
            coords = vector3(341.55, -580.42, 28.79), heading = 70.0,
            level = 'Ground', label = 'Main Entrance',
        },
    },
}
```

### Floor options

| Key | Example | Description |
|-----|---------|-------------|
| `jobs` | `{ police = 2 }` | Job name → minimum grade |
| `gangs` | `{ ballas = 0 }` | Gang name → minimum grade (QBox/QBCore; ox_core treats both as groups) |
| `items` | `{ 'keycard' }` | Player needs at least one listed item |
| `consumeItem` | `true` | Remove 1 of the matched item on a successful trip (one-time pass) |
| `owners` | `{ 'ABC12345' }` | Only these citizenids/identifiers may use the floor |
| `hours` | `{ open = 9, close = 17 }` | Floor only usable in this window (overnight ok: `{ open = 22, close = 6 }`) |
| `requireAll` | `true` | Must pass **every** restriction type set (default: any one is enough) |
| `pin` | `'4521'` | Keypad code, validated server-side |
| `bucket` | `1` | Routing bucket applied on arrival (`0` = public world, omit = unchanged) |

Floors with no restrictions are public. Old v1 configs (including `jobAndItem`) keep working.

`hours` are compared against the **server's real-world hour** by default. To use an in-game
clock, set `Config.BusinessHours.getHour` to a function returning the hour (0–23), e.g.
`function() return GlobalState.gameHour end`.

## Developer API

**Server exports**

```lua
exports.lf_elevatore:getElevators()                 -- sanitized elevator table
exports.lf_elevatore:isLocked(name)                 -- boolean
exports.lf_elevatore:setLocked(name, true)          -- take out of / back into service
exports.lf_elevatore:addElevator(name, data, persist) -- data = { label=, floors={...} }; persist=true writes JSON
exports.lf_elevatore:removeElevator(name)
```

**Client export**

```lua
exports.lf_elevatore:openElevator(name)  -- opens the floor menu from the nearest floor
```

**Events**

```lua
-- server
AddEventHandler('lf_elevatore:playerMoved', function(src, elevator, fromIndex, toIndex, passengers) end)
-- client
AddEventHandler('lf_elevatore:arrived', function(elevator, level, coords) end)
```

Example — cut power to an elevator during a heist:

```lua
exports.lf_elevatore:setLocked('BankVault', true)   -- locked: nobody can ride
-- ...later...
exports.lf_elevatore:setLocked('BankVault', false)
```

## Logging

Set `Config.Logging.enabled = true`. By default only restricted/PIN/owner floors are logged
(set `logAllMoves = true` for every trip). Provide a Discord `webhook`, and/or set
`useOxLib = true` to route through `lib.logger` (configure the `ox:logger` convar).

## Translations

Copy `locales/en.json` to `locales/<lang>.json` and translate. The language follows the `ox:locale` convar (`setr ox:locale es`).

## Update notifications

On startup the server prints a one-line notice if a newer release is on GitHub. Turn it off with:

```cfg
setr lf_elevatore:versionCheck false
```

## Support

If this helped you, drop a ⭐ on the repo!
