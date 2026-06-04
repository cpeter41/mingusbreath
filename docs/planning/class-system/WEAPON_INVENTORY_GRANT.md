# Plan: Weapons as one-time-granted inventory items

## Context

Today each class spawns with a class-driven weapon **visual** only — `Player._mount_class_weapon()` instances `ClassDef.weapon_scene` under `WeaponMount` every spawn (`scripts/player/player.gd:170-181`). `ClassDef.starting_inventory` is empty for all 4 shipped classes (`data/classes/*.tres`), so the inventory has no weapon entry at all.

User wants the class's weapon to also live as a real inventory item — granted **once** at first world-load for that character, then loaded from save on subsequent runs (never re-granted, even if the player drops or consumes it).

The "grant once, persist forever" pattern already exists:

- `Player._apply_starting_inventory()` (`scripts/player/player.gd:105-116`) iterates `ClassDef.starting_inventory` and adds each entry **only if `inventory.count_of(item_id) == 0`**.
- Fires from `Player._on_world_loaded()` (`scripts/player/player.gd:423`), host-authority side only.
- Runs **after** `ProfileSave.load_or_init()` (`scripts/world/world_root.gd:52`) has restored the character's saved inventory.
- Net effect: brand-new character → loadout granted; returning character with a saved inventory → guard skips, save wins.

So nothing about the runtime flow changes. The fix is purely data: add 4 weapon `ItemDef` `.tres` files and populate each class's `starting_inventory` with one `ClassLoadoutEntry` pointing at the matching item.

The visual mount (`_mount_class_weapon`) stays independent of inventory state — class still drives what model appears in the right hand. Coupling them (drop-to-unequip etc.) is out of scope; that's a future inventory-equip feature, not this fix.

## Changes

### 1. Create 4 `ItemDef` `.tres` files under `data/items/`

Mirror `data/items/sword.tres` / `shield.tres`. `item_type` uses the existing `ItemDef.ItemType` enum (`scripts/data/item_def.gd:4`): `WEAPON = 2`, `TOOL = 3` (celtic shield uses `TOOL` = 3 to match the existing shield.tres convention — shields aren't `WEAPON` in this schema). `weapon_skill_id = &"swords"` for all melee + harpoon for now (no archery skill yet; tunable later, no migration needed).

| File | id | display_name | item_type | weapon_skill_id |
|------|----|---------------|----|------------|
| `data/items/ranger_bow.tres`    | `&"ranger_bow"`    | "Ranger Bow"     | 2 | `&"swords"` |
| `data/items/celtic_shield.tres` | `&"celtic_shield"` | "Celtic Shield"  | 3 | `&""`       |
| `data/items/rogue_dagger.tres`  | `&"rogue_dagger"`  | "Rogue Dagger"   | 2 | `&"swords"` |
| `data/items/double_axe.tres`    | `&"double_axe"`    | "Double Axe"     | 2 | `&"swords"` |

All `max_stack = 1`. Description text per-item, one short sentence.

### 2. Populate each class's `starting_inventory`

Edit `data/classes/{harpooner,bulwark,corsair,berserker}.tres`. Replace the current `starting_inventory = Array[Resource]([])` with one `ClassLoadoutEntry` sub-resource referencing the matching weapon item id, count 1.

Pattern (harpooner shown — mirror for the other three with their item ids):

```gdscript
[ext_resource type="Script" path="res://scripts/data/class_loadout_entry.gd" id="4_loadout"]

[sub_resource type="Resource" id="grant_weapon"]
script = ExtResource("4_loadout")
item_id = &"ranger_bow"
count = 1

[resource]
...
starting_inventory = Array[Resource]([SubResource("grant_weapon")])
```

Mapping:
- harpooner → `ranger_bow`
- bulwark → `celtic_shield`
- corsair → `rogue_dagger`
- berserker → `double_axe`

### 3. Stale save data — manual wipe

Existing character saves under `user://characters/<name>.dat` still contain the old `sword` + `shield` items granted before the recent class-framework refactor. The idempotent guard in `_apply_starting_inventory()` keys on `item_id`, so the OLD items will persist alongside the new class weapon (e.g. corsair would have both a `sword` from the legacy save AND a freshly-granted `rogue_dagger`).

Recommended: delete `user://characters/*.dat` between runs for any character created before this fix. No code migration — these are dev-only character slots; cleaner than a one-time migration that would have to ship forever.

(Resolved path on Windows: `%APPDATA%/Godot/app_userdata/Mingusbreath/characters/`.)

### 4. Visual mount stays unchanged

`_mount_class_weapon()` continues to instance `cdef.weapon_scene` regardless of inventory contents. Inventory and visual are intentionally decoupled in this fix. A future "equip/unequip" feature can couple them by reading the equipped slot from `Inventory` and re-mounting on change.

## Critical files

| Action | File |
|--------|------|
| Create | `data/items/ranger_bow.tres` |
| Create | `data/items/celtic_shield.tres` |
| Create | `data/items/rogue_dagger.tres` |
| Create | `data/items/double_axe.tres` |
| Edit   | `data/classes/harpooner.tres` |
| Edit   | `data/classes/bulwark.tres` |
| Edit   | `data/classes/corsair.tres` |
| Edit   | `data/classes/berserker.tres` |
| Reuse  | `scripts/data/item_def.gd` (schema, no change) |
| Reuse  | `scripts/data/class_loadout_entry.gd` (schema, no change) |
| Reuse  | `scripts/player/player.gd:105-116, 423` (`_apply_starting_inventory` + idempotent guard — no change) |
| Reuse  | `scripts/world/world_root.gd:52` (`ProfileSave.load_or_init()` ordering — no change) |

## Verification

1. **Fresh character → grant fires.** Wipe `%APPDATA%/Godot/app_userdata/Mingusbreath/characters/*.dat`. Open `project.godot` in Godot 4.6, F5 from `LobbyMenu`. Create one character per class. For each: enter world, open inventory (`I`), confirm exactly one weapon item present matching the class (no sword, no shield).
2. **Returning character → save wins.** With the same character that just got the weapon, exit to lobby (triggers `ProfileSave.save()` via `pause_menu.gd:103` / `world_root.gd:65,75`). Drop the weapon (or `inventory.remove()` via console). Re-enter the world. Inventory should be EMPTY of the class weapon — `_apply_starting_inventory()` skips because the saved inventory has loaded first and the guard checks `count_of() == 0` against the post-load state.

   Wait — re-check: dropping decrements count to 0. On reload, save has 0, guard sees 0, grant fires again. That's the "drop → respawn" loophole already inherent in the design; flagged but not in scope to fix here.

   True "granted-once-ever" test: between exits, don't drop. Just confirm count stays at 1 across exit/re-enter — meaning grant didn't double-add.
3. **Visual still correct.** All four classes still show the correct weapon model on the right hand (CelticShield, RangerBow, RogueDagger, DoubleAxe) — independent of inventory state.
4. **MCP smoke.** Run via `mcp__godot__run_project`, tail `mcp__godot__get_debug_output` — watch for `InventoryRegistry` complaints about missing item ids (means a `.tres` typo) or `ClassLoadoutEntry` script-binding errors.
