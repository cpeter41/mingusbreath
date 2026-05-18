# Lint Cleanup — `scripts/` backlog

`globals/` is gdlint-clean. `scripts/` still has **50 violations**. This doc
hands that work to a future agent.

## Running the linter

`gdtoolkit` is installed (`pip install gdtoolkit`, v4.5.0). The CLIs live at
`%APPDATA%\Python\Python314\Scripts\` — not on PATH by default. Either add that
dir to PATH or invoke with the full path.

```powershell
$env:Path += ";$env:APPDATA\Python\Python314\Scripts"
gdlint scripts\          # report
gdformat --diff scripts\ # preview formatting changes
```

Default rules: 100-char line limit, max 6 returns/function, snake_case
identifiers, gdtoolkit's class-definitions order
(signals → enums → consts → exports → pub vars → priv vars → onready → methods).

## Categories

### Safe — mechanical, no identifier changes (38)

**max-line-length (19)** — wrap the line. Same approach used in `globals/`:
split call args / `%`-format expressions / function signatures across lines.

- `scripts/combat/hitbox.gd:22`
- `scripts/data/skill_def.gd:6`
- `scripts/dev/test_island.gd:43`
- `scripts/enemies/enemy_states/action_state/attack.gd:86`
- `scripts/enemies/enemy_states/action_state/enemy_action_state.gd:16`
- `scripts/items/item_pickup.gd:26`, `:79`
- `scripts/player/player.gd:44`
- `scripts/ui/lobby_menu.gd:226`, `:227`
- `scripts/world/island_generator.gd:85`, `:116`
- `scripts/world/island_placer.gd:65`, `:97`, `:100`, `:156`
- `scripts/world/zone_generator.gd:109`, `:146`, `:189`

**class-definitions-order (18)** — reorder top-level declarations to the
gdtoolkit order above. Move the block, don't rewrite logic.

- `scripts/combat/sword.gd` — lines 6, 9, 10, 11, 13, 14, 15, 17, 18, 19
- `scripts/enemies/enemy_states/action_state/attack.gd:6`
- `scripts/enemies/enemy_states/movement_state/idle.gd:4`
- `scripts/enemies/enemy_states/movement_state/patrol.gd:5`, `:6`
- `scripts/enemies/enemy_states/movement_state/sense.gd:4`
- `scripts/player/player.gd:47`, `:331`, `:332`

**unused-argument (1)** — prefix the param with `_` (or use it).

- `scripts/commands/chat_command.gd:21` — arg `args`

### Needs identifier renames — touches references across files (12)

**class-variable-name (8) — `movementSM` / `actionSM`.** gdlint wants
snake_case (`movement_sm` / `action_sm`). ⚠️ **These camelCase names are the
deliberate design vocabulary** — ARCHITECTURE.md and CLAUDE.md both call the
two parallel state machines "movementSM" and "actionSM". Decide before
touching:
  - **Option A** — rename everywhere (`movementSM` → `movement_sm`, etc.),
    update both `.gd` references and the two docs. Wide diff.
  - **Option B** — keep the names, add a `.gdlintrc` that disables
    `class-variable-name` or widens its pattern. Smaller, preserves the
    design vocabulary. Likely the better call.
  - Files: `enemy.gd:18,19`, `enemy_action_state.gd:5`,
    `enemy_states/movement_state/state.gd:5`, `player.gd:64,65`,
    `player/action_states/state.gd:5`, `player/movement_states/state.gd:7`.

**load-constant-name (2)** — `command_registry.gd:7,10`: consts `_HelpCommand`
/ `_GotoCommand` (preloaded scripts). gdlint wants `SCREAMING_SNAKE_CASE`. The
PascalCase-with-underscore is a common Godot idiom for preloaded classes;
rename to e.g. `_HELP_COMMAND` or add a `.gdlintrc` exception. Update refs in
the same file.

**function-variable-name (1)** — `bake_islands.gd:17`: local `seed_` (trailing
underscore to dodge the `seed()` builtin). Rename to something like
`world_seed`; local scope only, low risk.

### Needs a refactor (1)

**max-returns (1)** — `scripts/ui/controls_legend.gd:141`, `_event_label` has
>6 returns. Likely a long input-event → label dispatch. Either convert to a
lookup `Dictionary` (see the `controls.gd:_unhandled_input` refactor in commit
history for the pattern) or split into helpers.

## Suggested approach

1. Do the 38 safe fixes first — purely mechanical, low review cost.
2. Decide A vs B on `movementSM`/`actionSM` — Option B (`.gdlintrc`) is
   recommended so the design names survive.
3. Handle the remaining renames + the `max-returns` refactor.
4. Verify: `gdlint scripts\` reports `Success: no problems found`.

A project `.gdlintrc` at the repo root would also let you pin rule config
(line length, disabled rules) instead of relying on gdtoolkit defaults.
