# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Mingusbreath — a 1–4 player co-op 3D open-world game in Godot 4.6 (Forward+ renderer, GDScript). Procedurally-placed authored islands separated by open ocean, use-based skill leveling, melee/block combat, boats. Multiplayer is host-authoritative (listen server).

## Running & Building

There is no build/lint/CLI test step — this is a Godot project edited and run through the editor.

- **Run**: open `project.godot` in Godot 4.6 stable, press F5. Main scene is `scenes/ui/LobbyMenu.tscn`.
- **Steam multiplayer**: opt-in via the `--steam` launch flag (requires a running Steam client + the GodotSteam GDExtension under `addons/godotsteam/`). Without the flag, Steam init is skipped entirely.
- **Local two-instance dev test** (no Steam): launch two processes with `--offline --host` and `--offline --join 127.0.0.1`.
- **LAN**: host `--offline --host`; clients `--offline --join <host-LAN-IP>` (host opens inbound UDP 7777).
- The Godot MCP server is available — use `run_project` / `get_debug_output` to run and capture console output, `get_project_info` for project metadata.

## Tests

`tests/` is intended for GUT tests (save + generation systems) but is currently empty (`.gdkeep` only). No test runner is wired up yet.

## Architecture

The system is built on a small set of autoload singletons (registered in `project.godot` `[autoload]`). Rule: **autoloads never reach into scenes; scenes call autoloads or emit on `EventBus`.** `EventBus` is the decoupling layer — systems emit/listen on project-wide signals instead of holding references to each other.

Key autoloads:

- `EventBus` — project-wide signals (local per peer).
- `NetworkManager` — peer lifecycle, roster broadcast, world-load RPC, player spawn into `/World/Players`. Transports: GodotSteam or ENet.
- `AuthorityRouter` — multiplayer authority helpers (`server_only`, `owner_only`, `is_authority_for`).
- `GameState` — world seed, paused state, run-wide flags.
- `SaveSystem` — atomic snapshot/restore (write-temp → rename), version-tagged binary header, `Saveable` registry.
- `WorldStream` — distance-based island load/unload around the player; biome detection.
- `IslandRegistry` — deterministic seeded island placement; assigns `runtime_id`.
- `TimeOfDay`, `ZoneMap`, `SkillManager`, `InventoryRegistry`, `DiscoveryLog`, `AudioDirector`, `BoatManager`, `PickupManager`, `Ocean`.
- `Controls` — single input router for the **local** player. Game systems on remote peers ignore it.

### Determinism

Everything generative (island layout, placement) derives deterministically from a single 64-bit `GameState.world_seed`. Never store generated content in the save — only *modifications* to it. Per-island changes persist via `IslandDeltaStore`, keyed by `island.runtime_id` (stable per `(world_seed, slot_index)`).

### Multiplayer model

- **Authority**: each `Player` node's authority is its owning peer, derived from the node name `Player_<peer_id>`. HP/position/rotation/loadout flags replicate via `MultiplayerSynchronizer`; movement runs on the owner.
- **Damage**: any peer calls `target.take_damage(amount, attacker)`. If the caller is not the target's authority, it routes via `take_damage_rpc` to the owner, who applies HP and replicates back. Hitboxes apply damage only when `attacker.is_multiplayer_authority()`.
- **Spawn**: a `MultiplayerSpawner` in `World.tscn` replicates `/World/Players` children. Host spawns one `Player` per peer on world load and on late-join, offset on a small ring at the mainland anchor.
- **Time of day**: host owns the clock; guests tick locally at the last received rate. Host re-broadcasts on spawn, every 1 s while `T` is held, and once on `T` release.
- **Save split** (host world save vs per-guest profile) is a pending multiplayer phase — `SaveSystem` is currently host-owned.

### Player & combat

- Player is a `CharacterBody3D` with a `SpringArm3D` third-person camera. Two **parallel** state machines run independently: `movementSM` (locomotion: idle/run/sprint/jump/fall/swim) and `actionSM` (attack/block/dodge/sail). Code under `scripts/player/movement_states/` and `scripts/player/action_states/`.
- Combat: weapon scenes carry an `Area3D` hitbox toggled by animation tracks; hits route through `scripts/combat/combat_resolver.gd`, which applies skill multipliers + resistances. HP/stamina are transient (reset to max on load), not persisted.
- Enemy AI is a single per-instance FSM (Idle/Patrol/Sense/Chase/Attack/Flee/Return) under `scripts/enemies/enemy_states/`.

### Layout

`scenes/` mirrors `scripts/` for predictable navigation. `data/` holds `.tres` Resource content (items, biomes, enemies, skills) with no logic — schemas live in `scripts/data/*.gd`. `scenes/dev/` holds throwaway sandboxes (not shipped). Chat/console commands live under `scripts/commands/` (`CommandRegistry` autoload + `default/` and `debug/` command scripts).

## Reference

- `docs/planning/ARCHITECTURE.md` — full system design (note: written single-player-first; multiplayer was retrofitted afterward).
- `docs/planning/multiplayer/MULTIPLAYER_RETROFIT_PLAN.md` — authority rules + remaining multiplayer phases.
- `docs/planning/PHASE_*_PLAN.md` — per-phase implementation plans.
- `README.md` — install, run flags, system status table, autoload + input-action reference.
