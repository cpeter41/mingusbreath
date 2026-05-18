# Mingusbreath

1–4 player co-op 3D open-world game built in Godot 4.6. Procedurally generated islands separated by open ocean, use-based skill leveling, melee/block combat, boats for island-to-island travel. Multiplayer is host-authoritative (listen server) over Steam Networking with an ENet localhost fallback for dev.

## Tech

- **Engine**: Godot 4.6 stable — Forward+ renderer
- **Language**: GDScript (C# / GDExtension only if profiler demands it)
- **World**: 4 km × 4 km ocean with 12 deterministically-placed authored islands, distance-streamed around player, difficulty-zoned
- **Save**: Binary via `FileAccess` + `var_to_bytes`, atomic write (write-temp → rename), version-tagged header
- **Multiplayer**: Host-authoritative listen server. Owner-auth movement, RPC-routed damage, replicated HP / loadout / time-of-day. Transports: GodotSteam GDExtension (Steam friends-only lobbies, P2P relay) or ENet (localhost for two-instance dev).

## Installation

### Prerequisites

- **Godot 4.6 stable** — the project targets Godot `4.6` with the Forward+
  renderer (`config/features` in `project.godot`). Download the matching
  build (e.g. `Godot_v4.6.2-stable_win64.exe`) from
  [godotengine.org](https://godotengine.org). Other 4.x versions are not
  supported.
- **GodotSteam GDExtension** — required for Steam multiplayer (friends-only
  lobbies, P2P relay). Solo play and ENet/LAN multiplayer work *without* it.
  Download the GDExtension from [godotsteam.com](https://godotsteam.com).
- **Steam client** — must be running for Steam multiplayer only.

### Steps

1. Install Godot 4.6 stable (see Prerequisites).
2. Clone this repository.
3. Install GodotSteam:
   - Download the GodotSteam GDExtension build for Godot 4.6.
   - Add `godotsteam` to an `addons` folder next to `project.godot` in the directory.
   - ~~Place a `steam_appid.txt` containing `480` (the Spacewar test app id)
     next to `project.godot`.~~
4. Open `project.godot` in Godot 4.6 and press F5 to run.
5. *(Optional — to run the test suite)* On a fresh checkout the GdUnit4 test
   framework is not included. Install it once:
   ```sh
   pwsh tests/install_gdunit4.ps1      # POSIX: tests/install_gdunit4.sh
   godot --headless --path . --import  # refresh the class cache
   ```
   Then run `pwsh tests/run_tests.ps1`. See `tests/README.md` for details.

### Running

- **Solo / multiplayer via the lobby** — F5 launches `LobbyMenu`. Pick a world
  and character, then Solo, Host, or Join.
- **Steam multiplayer** — Steam init is opt-in: launch with the `--steam`
  command-line flag (and a running Steam client). Without it, Steam is skipped
  so the client never shows "Now Playing".
- **Local two-instance dev test (no Steam, no GodotSteam needed)** — launch two
  Godot processes with `--offline --host` and `--offline --join 127.0.0.1`.
- **LAN play** — host runs `--offline --host`; other machines run
  `--offline --join <host-LAN-IP>`. The host must allow inbound UDP port 7777.

## Project Structure

```
globals/        Autoload singletons (GameState, EventBus, SaveSystem, NetworkManager, etc.)
data/           .tres Resources — items, recipes, biomes, enemies, skills, ships, zones
scripts/        GDScript logic (player, combat, ai, ships, world, crafting, inventory, ui, util)
scenes/         .tscn files mirroring scripts/ layout (+ scenes/ui/LobbyMenu.tscn)
shaders/        Water, foliage wind, toon, sky, world-border
assets/         Models, textures, sfx, music
tests/          GdUnit4 tests (unit + integration; mirrors scripts/ layout)
docs/planning/  Architecture doc, phase plans, multiplayer retrofit plan
```

## Systems

| System | Status |
|--------|--------|
| Project skeleton + autoloads + save round-trip | Phase 1 — done |
| Player controller + camera + melee combat + test island | Phase 2 — done |
| Skill curves + inventory + basic boat | Phase 3 — done |
| Combat depth (block / dodge / stamina / parry) + enemy AI | Phase 4 — done |
| TimeOfDay + premade-island streaming + biomes + per-island deltas + save schema v2 | Phase 5 — done |
| Difficulty zones + overhead map + ZoneDebug overlay (F2) | Phase 6 — done |
| Multiplayer retrofit — networking core, owner-auth players, RPC damage, loadout visuals, host-broadcast time-of-day | done (phases 0-3, 7 of retrofit plan) |
| Multiplayer remaining — boats, save split (host world + per-guest profile), enemy server-auth (deferred), pickup replication (deferred) | pending |
| Foliage, real ocean shader, naval combat, biome spawn tables | future |

## Global Services

| Autoload | Role |
|----------|------|
| `EventBus` | Decoupled project-wide signals (local per peer) |
| `SteamLobby` | GodotSteam wrapper — `createLobby`, `joinLobby`, overlay-invite handler. Inert if Steam unavailable |
| `NetworkManager` | Peer lifecycle, roster broadcast, world-load RPC, player spawn into `/World/Players`. Transports: Steam or ENet |
| `AuthorityRouter` | Helpers — `server_only`, `owner_only`, `is_authority_for` |
| `Ocean` | Ocean shader / mesh helpers |
| `SaveSystem` | Atomic snapshot/restore, Saveable registry (host-owned; per-guest profile split is a remaining MP phase) |
| `GameState` | World seed, paused state, run-wide flags |
| `TimeOfDay` | Game clock, dawn/day/dusk/night phases. Host ticks; broadcasts to guests on player spawn, while T held (1 s), and on T release |
| `WorldStream` | Distance-based island load/unload around player; biome detection |
| `IslandRegistry` | Deterministic seeded island placement; runtime_id assignment |
| `ZoneMap` | Difficulty zone field + F2 debug overlay toggle |
| `SkillManager` | Per-skill XP/level tracking, level-up events |
| `InventoryRegistry` | Lookup table of all `ItemDef`s by id |
| `DiscoveryLog` | Discovered map regions + crafting stations |
| `AudioDirector` | Music stems per biome/combat, sfx pool |
| `BoatManager` | Tracks spawned boats; saves/restores positions across reloads |
| `Controls` | Single input router for the local player (UI, mouse capture, action queries). Game systems on remote peers ignore it |

## Input Actions

| Context | Actions |
|---------|---------|
| Movement | `move_forward/back/left/right`, `jump`, `sprint`, `dodge` |
| Combat | `attack_light`, `attack_heavy`, `block`, `interact` |
| UI | `inventory`, `map`, `pause` |
| Boat | `throttle_up/down`, `rudder_left/right`, `fire_cannon`, `spawn_boat` |
| Debug | `reset_save` (R), `time_accel` (T — host only, F2 debug overlay must be on) |

## Multiplayer model (quick reference)

- **Authority**: each Player node's authority is its owning peer (derived from name `Player_<peer_id>`). HP, position, rotation, loadout flags replicate via `MultiplayerSynchronizer`. Movement runs on the owner.
- **Damage**: any peer calls `target.take_damage(amount, attacker)`. If we're not the target's authority, it routes via `take_damage_rpc` to the owner who applies HP and replicates back.
- **Hitbox**: only the attacker's authority applies damage (`attacker.is_multiplayer_authority()` guard).
- **Spawn**: `MultiplayerSpawner` in `World.tscn` replicates `/World/Players` children. Host spawns one Player per peer (self + each connected guest) on world load and on late-join. Per-peer spawn offsets on a small ring at the mainland anchor to avoid physics overlap.
- **Time of day**: host owns the clock and `current_rate`. Guests tick locally at the last rate they received; host re-sends on spawn, every 1 s while `T` is held, and once on `T` release.

## Docs

- [`docs/planning/ARCHITECTURE.md`](docs/planning/ARCHITECTURE.md) — full system design
- [`docs/planning/MULTIPLAYER_RETROFIT_PLAN.md`](docs/planning/MULTIPLAYER_RETROFIT_PLAN.md) — multiplayer retrofit plan + authority rules + remaining phases
- [`docs/planning/PHASE_1_PLAN.md`](docs/planning/PHASE_1_PLAN.md) — skeleton + autoloads
- [`docs/planning/PHASE_2_PLAN.md`](docs/planning/PHASE_2_PLAN.md) — player + combat
- [`docs/planning/PHASE_3_PLAN.md`](docs/planning/PHASE_3_PLAN.md) — skills + inventory + boat
- [`docs/planning/PHASE_4_PLAN.md`](docs/planning/PHASE_4_PLAN.md) — combat depth + enemies
- [`docs/planning/PHASE_5_PLAN.md`](docs/planning/PHASE_5_PLAN.md) — TimeOfDay + island streaming + biomes
