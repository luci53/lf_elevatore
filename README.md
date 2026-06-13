# lf_elevatore

[![luacheck](https://github.com/luci53/lf_elevatore/actions/workflows/luacheck.yml/badge.svg)](https://github.com/luci53/lf_elevatore/actions/workflows/luacheck.yml)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Create your own elevators anywhere on your FiveM server — in the config **or live in-game with a command**. Framework-agnostic: works on **QBox**, **QBCore** and **ESX** with automatic detection.

## Features

- 🛗 Unlimited elevators with unlimited floors
- 🔍 ox_target / qb-target third-eye support (auto-detected) + ox_lib TextUI `[E]` prompt
- 🛡️ **Server-side validation** — job, gang, item and PIN checks run on the server, not the client
- 🔢 **PIN-code floors** — keypad dialog; codes live server-side and are never sent to clients
- 👥 **Group travel** — players standing next to you ride along
- 🌐 **Routing bucket support** — send players into instanced interiors per floor
- 🛠️ **In-game creator** — `/elevator create` lets admins build elevators without touching the config, saved to JSON
- 🔔 Arrival sound (native frontend sound or interact-sound)
- 🌍 Translations via ox_lib locales (`locales/*.json`)

## Dependencies

| Resource | Required | Notes |
|----------|----------|-------|
| [ox_lib](https://github.com/CommunityOx/ox_lib) | ✅ Yes | Menus, TextUI, callbacks, locales |
| [ox_target](https://github.com/CommunityOx/ox_target) / [qb-target](https://github.com/qbcore-framework/qb-target) | Optional | Third-eye interaction (auto-detected) |
| [ox_inventory](https://github.com/CommunityOx/ox_inventory) | Optional | Used for item checks when present |

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
| `/elevator add` | Add a floor at your current position (opens a dialog for name, PIN, jobs, bucket…) |
| `/elevator save` | Save the elevator (needs at least 2 floors) — live for everyone instantly |
| `/elevator cancel` | Discard the current session |
| `/elevator delete <name>` | Delete an elevator created in-game |
| `/elevator list` | List all elevators |

In-game elevators are stored in `data/elevators.json` and survive restarts.

## Configuration

`config.lua` is **server-only**: clients receive a sanitized copy of the elevator data, so PIN codes never leave the server.

```lua
Config.Framework = 'auto'       -- 'auto' | 'qbox' | 'qbcore' | 'esx'
Config.Target = 'auto'          -- 'auto' | 'ox_target' | 'qb-target' | false
Config.UseTextUI = true         -- [E] prompt via ox_lib TextUI
Config.ElevatorWaitTime = 3     -- travel time in seconds
Config.GroupTravel = { enabled = true, radius = 3.0 }
Config.Sounds = { arrive = { type = 'native', name = 'PICK_UP', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' } }
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
| `gangs` | `{ ballas = 0 }` | Gang name → minimum grade (QBox/QBCore) |
| `items` | `{ 'keycard' }` | Player needs at least one listed item |
| `requireAll` | `true` | Must pass **every** restriction type set (default: any one is enough) |
| `pin` | `'4521'` | Keypad code, validated server-side |
| `bucket` | `1` | Routing bucket applied on arrival (`0` = public world, omit = unchanged) |

Floors with no restrictions are public. Old v1 configs (including `jobAndItem`) keep working.

## Translations

Copy `locales/en.json` to `locales/<lang>.json` and translate. The language follows the `ox:locale` convar (`setr ox:locale es`).

## Update notifications

On startup the server prints a one-line notice if a newer release is on GitHub. Turn it off with:

```cfg
setr lf_elevatore:versionCheck false
```

## Support

If this helped you, drop a ⭐ on the repo!
