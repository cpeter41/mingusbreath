# Player Class Framework — Implementation Plan

## Context

Mingusbreath currently has exactly one kind of player. Stats are hardcoded in
`scripts/player/player.gd` (`max_hp = 100`, `max_stamina = 150`, `speed = 5`)
and the starting loadout is a hardcoded sword + shield grant in
`_on_world_loaded()`. There is no notion of a player class.

We want a **data-driven, modular player-class framework**: a player picks a
class when creating a character in the lobby, and that class drives stats and
starting loadout. For now all four shipped classes are functionally identical
(same stats, same loadout) — the point of this phase is the *scaffolding*, so
that varying a parameter or adding a class later is a one-line / one-file
change. Outcome: a clean `ClassDef` resource type, a registry autoload, lobby
selection, and class-driven stat/loadout application that replicates correctly
in 1–4 player host-authoritative multiplayer.

### Decisions

- **Class is locked at character creation.** Chosen via a lobby dropdown when
  the `+` button creates a character; immutable afterward. Selecting an
  existing character shows its class read-only.
- **Ship 4 class definitions:** Bulwark, Harpooner, Corsair, Berserker. All four have
  identical parameters for now (matches "each character the same for now");
  they differ only in `id` / `display_name` / `description`. Names are
  flavour-only — future model-swap selects scenes independently of the id.

## Architecture

Follows the project's established data convention: schema scripts in
`scripts/data/*.gd` (`class_name`, `extends Resource`, `@export` only, **zero
logic**); content `.tres` in `data/<category>/`; a registry autoload that scans
the directory at `_ready()` (mirrors `globals/inventory_registry.gd` and
`globals/skill_manager.gd`).

### 1. Schema: `ClassLoadoutEntry` — `scripts/data/class_loadout_entry.gd`

A tiny nested resource for one starting-inventory line. Its own file so it has
a registered `class_name` usable as a typed-array element.

```gdscript
class_name ClassLoadoutEntry
extends Resource

@export var item_id: StringName = &""
@export var count: int = 1
```

Rationale for a nested resource over a typed `Dictionary`: resource composition
is already the project pattern (`IslandDef.biome: BiomeDef`); `Array[...]` is
strongly typed and inspector-friendly; it extends cleanly (a future per-entry
field is one `@export`, no `.tres` migration); and it avoids the
`StringName`-vs-`String` dictionary-key footgun (`Inventory.add` keys on
`StringName`).

### 2. Schema: `ClassDef` — `scripts/data/class_def.gd`

```gdscript
class_name ClassDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null

# Stats applied to the Player on spawn.
@export var max_hp: float = 100.0
@export var max_stamina: float = 150.0
@export var move_speed: float = 5.0

# Granted once, idempotently, at world load.
@export var starting_inventory: Array[ClassLoadoutEntry] = []

# Item id (from data/items/) of the class's primary weapon. Informational in
# this phase; kept separate from starting_inventory so future logic (HUD weapon
# glyph, default-equipped slot, model/anim selection) can read it directly.
@export var primary_weapon: StringName = &""
```

This covers the named parameters (weapon type → `primary_weapon` + loadout,
starting health → `max_hp`, starting inventory → `starting_inventory`). Adding a
new parameter later = one `@export` here + one line in `_apply_class()`.

### 3. Autoload: `ClassRegistry` — `globals/class_registry.gd`

Near-verbatim copy of `inventory_registry.gd`. **No `class_name`** (autoloads
are referenced by their autoload name; a `class_name` would clash — matches
`InventoryRegistry` / `SkillManager`).

```gdscript
extends Node

const CLASSES_DIR := "res://data/classes/"
const DEFAULT_CLASS_ID := &"bulwark"   # fallback; must name a shipped class

var classes: Dictionary = {}   # StringName -> ClassDef

func _ready() -> void:
    _scan_classes()

func _scan_classes() -> void:
    var d := DirAccess.open(CLASSES_DIR)
    if d == null:
        return
    d.list_dir_begin()
    var fname := d.get_next()
    while fname != "":
        if not d.current_is_dir() and fname.ends_with(".tres"):
            var res := load(CLASSES_DIR + fname)
            if res != null and "id" in res:
                classes[StringName(res.id)] = res
        fname = d.get_next()
    d.list_dir_end()

func get_class_def(id: StringName) -> ClassDef:
    return classes.get(id, null)

func class_ids() -> Array:          # stable sorted list for the lobby dropdown
    var ids := classes.keys()
    ids.sort()
    return ids

func resolve(id: StringName) -> ClassDef:   # never returns null if any class exists
    var def := get_class_def(id)
    if def != null:
        return def
    def = get_class_def(DEFAULT_CLASS_ID)
    if def != null:
        return def
    var ids := class_ids()
    return classes[ids[0]] if not ids.is_empty() else null
```

Register in `project.godot` `[autoload]` after `InventoryRegistry`:
```
ClassRegistry="*res://globals/class_registry.gd"
```

### 4. Content: `data/classes/*.tres`

New directory `data/classes/` with four `ClassDef` resources — `bulwark.tres`,
`harpooner.tres`, `corsair.tres`, `berserker.tres`. All four carry identical parameters
this phase:

| field | value |
|---|---|
| `max_hp` | `100.0` |
| `max_stamina` | `150.0` |
| `move_speed` | `5.0` |
| `starting_inventory` | `[ {sword,1}, {shield,1} ]` (two `ClassLoadoutEntry` sub-resources) |
| `primary_weapon` | `&"sword"` |

`id` / `display_name` / `description` differ per file (`&"bulwark"` /
`"Bulwark"` / …). Authoring note: create these via the Godot editor
(Create Resource → `ClassDef`, add `ClassLoadoutEntry` sub-resources) so
format/UIDs are engine-correct. Adding a 5th class later = drop another `.tres`.

## Persistence — class fixed on the character

Class is a per-character attribute stored beside the `ProfileSave` slot in a
**sidecar file** `user://characters/<name>.class` (plain text, the class id).

Why a sidecar rather than the character `.dat`: `<name>.dat` is written only by
`ProfileSave.save()` during an active world session with registered nodes; the
lobby must read/write class with **no session active**. A sidecar keeps the
lobby path trivial and avoids touching the versioned `.dat` schema.

Add to `globals/profile_save.gd`:

```gdscript
const DEFAULT_CLASS_ID := &"bulwark"

func _class_path(char_name: String) -> String:
    return CHARACTERS_DIR + char_name + ".class"

func get_character_class(char_name: String) -> StringName:
    if char_name == "":
        return DEFAULT_CLASS_ID
    var p := _class_path(char_name)
    if not FileAccess.file_exists(p):
        return DEFAULT_CLASS_ID
    var f := FileAccess.open(p, FileAccess.READ)
    if f == null:
        return DEFAULT_CLASS_ID
    var s := f.get_as_text().strip_edges()
    f.close()
    return StringName(s) if s != "" else DEFAULT_CLASS_ID

func set_character_class(char_name: String, class_id: StringName) -> void:
    if char_name == "":
        return
    var f := FileAccess.open(_class_path(char_name), FileAccess.WRITE)
    if f != null:
        f.store_string(String(class_id))
        f.close()

func current_class() -> StringName:
    return get_character_class(current_character)
```

- `create_character()` (line 55) — after creating the `.dat`, seed the `.class`
  file with `DEFAULT_CLASS_ID` so no slot ever lacks a class (covers the
  cmdline `--offline` auto-created "default" character). The lobby's
  `_on_char_add` then overwrites it with the user's chosen class.
- `delete_profile()` (line 159) — also remove `_class_path()` for tidiness.

## Networking — how `class_id` reaches the spawned Player

The riskiest part. Class must be correct on **every** peer's copy of the
Player, applied before stats/loadout are read.

### Lobby → `NetworkManager.peers`

Extend the **existing** `_register_character` RPC (no new RPC):

- `_on_connected_to_server()` — guest call becomes
  `_register_character.rpc_id(1, ProfileSave.current_character, ProfileSave.current_class())`.
- `_register_character(char_name, class_id)` — host also stores
  `peers[sender]["class"] = class_id` alongside the existing `["character"]`.

The host never calls `_register_character`, so add a resolver:

```gdscript
func _class_for_peer(peer_id: int) -> StringName:
    if peer_id == multiplayer.get_unique_id():
        return ProfileSave.current_class()          # host / OFFLINE: own profile
    var rec: Dictionary = peers.get(peer_id, {})
    return StringName(rec.get("class", ClassRegistry.DEFAULT_CLASS_ID))
```

### `NetworkManager` → spawned Player → all peers

**Replicate `class_id` as a spawn-synced var on the Player's
`MultiplayerSynchronizer` — not an RPC.** The `SRC_player`
`SceneReplicationConfig` already marks `position`, `hp`, etc. with
`spawn = true` (verified: `properties/0..9` in `Player.tscn`). A `spawn = true`
property is baked into the **spawn packet**, so every peer receives `class_id`
atomically with the node, before that peer's `_ready` runs — no RPC-vs-spawn
race. (`set_spawn_position` is `rpc_id` to a single peer; class needs all peers.)

1. `player.gd` — add a self-applying replicated var:
   ```gdscript
   var class_id: StringName = &"bulwark":
       set(v):
           class_id = v
           _apply_class()      # safe early: writes only plain fields
   ```
2. `Player.tscn` `SRC_player` — add one entry after `properties/9`:
   ```
   properties/10/path = NodePath(".:class_id")
   properties/10/spawn = true
   properties/10/replication_mode = 0      # Never re-sent; spawn packet only
   ```
   Mode `0` (Never) is correct — class is fixed for the node's lifetime.
3. `network_manager.gd` `_spawn_player_for_peer()` — set `class_id` **before
   `add_child`** (right after `set_multiplayer_authority`), exactly as
   `position` is pre-placed today so the spawner snapshots it:
   ```gdscript
   p.class_id = _class_for_peer(peer_id)
   ```

## Player — applying the class

### `_apply_class()` — stats

```gdscript
func _apply_class() -> void:
    var cdef := ClassRegistry.resolve(class_id)
    if cdef == null:
        return
    max_hp = cdef.max_hp
    max_stamina = cdef.max_stamina
    speed = cdef.move_speed
```

Touches only plain fields (no `@onready` node access) so it is safe when the
`class_id` setter fires before `_ready`. Idempotent. Call sites:

- The `class_id` setter (host pre-`add_child` set; guest spawn-packet arrival).
- `_ready()`, **before** the existing `hp = max_hp` / `stamina = max_stamina`
  (`player.gd:122-123`) — so a fresh host player starts at class-correct
  hp/stamina, not the `@export` default.

**Guest HUD correctness:** `max_hp`/`max_stamina`/`speed` are *not* replicated.
The `hp`/`stamina` setters emit `EventBus.player_*_changed` only when
`is_multiplayer_authority()`, so each peer's HUD only reads its **own** local
player's `max_hp` — and that local player ran `_apply_class()` with the
spawn-delivered `class_id`. Every peer derives the floats deterministically from
the replicated `class_id` + `ClassRegistry` (same "replicate the key, derive
the rest" pattern as `has_sword`/`has_shield`). Replicating the floats would add
three config entries for no gain.

### `_apply_starting_inventory()` — idempotent loadout grant

Replace the hardcoded block in `_on_world_loaded()` (`player.gd:376-379`):

```gdscript
func _apply_starting_inventory() -> void:
    var cdef := ClassRegistry.resolve(class_id)
    if cdef == null:
        return
    for entry in cdef.starting_inventory:
        if entry == null or entry.item_id == &"":
            continue
        if inventory.count_of(entry.item_id) == 0:
            inventory.add(entry.item_id, entry.count)
```

Stays inside the authority-only branch of `_on_world_loaded`. Keeps the existing
per-item `count_of(id) == 0` guard, so a returning character (inventory already
restored by `ProfileSave.load_or_init()`, which `world_root.gd:52` runs before
`world_loaded`) is not double-granted. Preserves current behaviour exactly,
including the known edge case that fully depleting a starter item re-grants it
next load — intentional parity, not a regression.

`_on_inventory_changed()` still derives `has_sword`/`has_shield` from
`count_of`, so weapon visuals keep working unchanged.

## Lobby UI — class locked at creation

### Nodes added to `scenes/ui/LobbyMenu.tscn`

Under `$Columns/SlotsColumn`, **above** the `CharCreate` row (the dropdown feeds
the `+` button):

- `SlotsColumn/ClassLabel` — `Label`, text "Class (new character)".
- `SlotsColumn/ClassDropdown` — `OptionButton`; each item's text is a class
  `display_name`, each item's metadata holds the class `id` (`StringName`).

(Small structural `.tscn` edit — do via the Godot editor or the Godot MCP
`add_node` tool to match sibling-dropdown theming.)

### `lobby_menu.gd` wiring

`@onready var _class_dropdown: OptionButton = $Columns/SlotsColumn/ClassDropdown`

The dropdown serves the **next-created** character. It is interactive only while
the create field has text; otherwise it read-only-displays the selected
character's locked class.

```gdscript
func _refresh_class_dropdown() -> void:
    _class_dropdown.clear()
    for cid in ClassRegistry.class_ids():
        var def := ClassRegistry.get_class_def(cid)
        var label := def.display_name if def != null and def.display_name != "" else String(cid)
        var idx := _class_dropdown.item_count
        _class_dropdown.add_item(label)
        _class_dropdown.set_item_metadata(idx, cid)
    _sync_class_dropdown_state()

# Enabled while typing a new character name; otherwise shows the selected
# character's locked class, read-only.
func _sync_class_dropdown_state() -> void:
    var creating := _char_name_edit.text.strip_edges() != ""
    if not creating and ProfileSave.current_character != "":
        var cur := ProfileSave.current_class()
        for i in _class_dropdown.item_count:
            if _class_dropdown.get_item_metadata(i) == cur:
                _class_dropdown.select(i)
                break
    _class_dropdown.disabled = (not creating) or (not NetworkManager.is_offline())
```

Hooks:
- `_ready()` — connect `_char_name_edit.text_changed` to a handler that calls
  `_sync_class_dropdown_state()`; call `_refresh_class_dropdown()` after
  `_refresh_char_dropdown()`.
- `_on_char_selected()` — call `_sync_class_dropdown_state()` so the dropdown
  reflects the newly selected character's class.
- `_on_char_add()` — read the chosen class **before** clearing the field:
  ```gdscript
  var class_id: StringName = _class_dropdown.get_item_metadata(_class_dropdown.selected)
  var created := ProfileSave.create_character(base)
  ProfileSave.set_character_class(created, class_id)
  ```
  then the existing refresh calls (`_refresh_char_dropdown`, select, set status)
  plus `_sync_class_dropdown_state()`.
- `_refresh_buttons()` — the `disabled` rule in `_sync_class_dropdown_state()`
  already locks the dropdown once a session starts (`not is_offline()`); call
  `_sync_class_dropdown_state()` from `_refresh_buttons()` for consistency.
- `_refresh_roster()` (optional) — append `rec.get("class", "?")` to each peer
  line for test visibility.

## Files

### Create
| File | Purpose |
|---|---|
| `scripts/data/class_loadout_entry.gd` | `ClassLoadoutEntry` resource. |
| `scripts/data/class_def.gd` | `ClassDef` schema. |
| `globals/class_registry.gd` | `ClassRegistry` autoload. |
| `data/classes/bulwark.tres` `harpooner.tres` `corsair.tres` `berserker.tres` | The 4 shipped classes. |

### Modify
| File | Change |
|---|---|
| `project.godot` | `[autoload]`: add `ClassRegistry`. |
| `scripts/player/player.gd` | Replicated `class_id` var + setter; `_apply_class()`; call in `_ready()` before `hp = max_hp`; `_apply_starting_inventory()`; replace hardcoded grant in `_on_world_loaded()`. |
| `scenes/player/Player.tscn` | `SRC_player`: add `properties/10` = `class_id` (`spawn = true`, `replication_mode = 0`). |
| `globals/network_manager.gd` | `_register_character` (+ `class_id` arg); `_on_connected_to_server` (pass class); store `peers[…]["class"]`; add `_class_for_peer()`; set `p.class_id` in `_spawn_player_for_peer` before `add_child`. |
| `globals/profile_save.gd` | `get_character_class` / `set_character_class` / `current_class` / `_class_path`; seed `.class` in `create_character`; remove `.class` in `delete_profile`. |
| `scripts/ui/lobby_menu.gd` | `_class_dropdown` onready; `_refresh_class_dropdown`; `_sync_class_dropdown_state`; hook `_char_name_edit.text_changed`, `_on_char_selected`, `_on_char_add`, `_refresh_buttons`, `_ready`. |
| `scenes/ui/LobbyMenu.tscn` | Add `ClassLabel` + `ClassDropdown` under `SlotsColumn`. |

## Verification

### Static / boot
1. Open in Godot editor (or MCP `run_project`). No parse errors on new scripts;
   `ClassRegistry` listed as a loaded autoload.
2. `data/classes/bulwark.tres` loads as a `ClassDef` with two
   `ClassLoadoutEntry` rows — confirms schema + `.tres` format.

### Solo (offline)
3. `run_project`. In the lobby, type a new character name → `ClassDropdown`
   enables; pick "Harpooner"; press `+`. Re-select that character → dropdown shows
   "Harpooner", disabled. Confirms locked-at-creation + sidecar persistence.
4. Start Solo; watch `get_debug_output`. In-world: HUD hp 100 / stamina 150
   (via `_apply_class()`); player has sword + shield (loadout-driven grant).
5. Save & quit, relaunch, load the same character: still 1× sword / 1× shield —
   confirms `_apply_starting_inventory()` idempotency.

### Two-instance local multiplayer (critical replication test)
6. Instance A `--offline --host`, instance B `--offline --join 127.0.0.1`.
7. Host `get_debug_output`: `Player_<id>` spawned for both peers; no
   `unable to process the pending spawn` / spawner errors — confirms the new
   `class_id` `spawn=true` entry doesn't break the spawn packet.
8. Both instances: each peer's own HUD shows correct stats; both players show
   their loadout on the model.
9. **Differentiation test** (proves the framework): temporarily edit
   `data/classes/harpooner.tres` to `move_speed = 8`, `max_hp = 70`,
   loadout = sword only. Set instance B's character to a Harpooner. After spawn,
   on **both** instances B moves faster, has 70 max hp, and carries only a
   sword — confirms `class_id` rode the spawn packet and `_apply_class()` ran on
   the non-authority copy. Revert the temp edit after.
10. **Mid-session join:** host enters the world first, then launch the joiner;
    repeat 8–9 — exercises the `_guest_world_ready` → `_spawn_player_for_peer`
    path where an RPC-based class would be most likely to race.

## Trade-offs & future work

- **Riskiest part — replication timing.** Mitigated by a `spawn = true`,
  `replication_mode = 0` synced var (rides the spawn packet, atomic with the
  node) instead of an RPC, and by the host setting `class_id` before
  `add_child` (mirrors proven `position` pre-placement). The self-applying
  setter makes the value take effect whenever it arrives.
- **Derived vs replicated stats.** Deriving the stat floats from `class_id` +
  `ClassRegistry` on every peer keeps the synchronizer minimal; assumes every
  peer's `data/classes/` is identical (true for a shared build — revisit if
  classes ever become moddable/DLC).
- **Class locked at creation.** No in-game respec; changing class means making a
  new character. Acceptable for this phase, easily revisited.
- **Weapon visuals still hardcoded.** `has_sword`/`has_shield` remain
  item-specific. Stats and loadout are fully data-driven; generalising the
  weapon *visual* mount to arbitrary weapon items is the natural next step.
- **Future per-class parameters** the scaffolding now supports with a single
  `@export` each: model `PackedScene` (e.g. swap the Bulwark to a `Warrior.gltf`
  rig, the Harpooner to a `Ranger.gltf` rig — class id stays decoupled from
  the asset filename), starting skill levels, damage multipliers, ability lists.
