# Multiplayer tests

Host-authoritative multiplayer is the hardest surface to test — it needs two
live peers. This directory is **Phase 4 scaffold**: the design is fixed, one
in-process smoke test exists, the two-peer harness is not yet built.

These suites are **excluded from the default `run_tests` scan** (which covers
`unit/` + `integration/`). Run them explicitly:

```sh
pwsh tests/run_tests.ps1 multiplayer
```

## Current state

- `test_mp_smoke.gd` — in-process sanity for the offline/authority primitives
  (`NetworkManager.is_offline()`, `is_authority_for()`, `AuthorityRouter`).
  Runs today; no second peer involved.

## Planned harness (not built)

A meta-runner launches two headless Godot processes and asserts on their log
output:

- **Host** — `godot --headless -- --offline --host`
- **Client** — `godot --headless -- --offline --join 127.0.0.1`

The runner scrapes stdout for roster / spawn / save markers and fails if the
expected sequence does not appear within a timeout.

### Target scenarios (see `docs/planning/tests/TEST_EXPANSION_PLAN.md` Phase 9)

| Suite | Asserts |
|-------|---------|
| `test_authority.gd` | `Player_<peer_id>` node authority maps to the owning peer |
| `test_damage_routing.gd` | non-authority damage routes via `take_damage_rpc` to the owner |
| `test_spawn.gd` | host spawns one `Player` per peer; late-joiners land on the anchor ring |
| `test_world_save_ownership.gd` | a returning client's `SaveSystem.save()` is a no-op (guards commit 8578500) |

Build order: harness meta-runner first (process launch + log scrape +
timeout), then the four scenario suites on top of it.
