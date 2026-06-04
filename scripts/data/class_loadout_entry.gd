class_name ClassLoadoutEntry
extends Resource

# One row of a ClassDef.starting_inventory. Tiny nested resource so the array
# is typed and inspector-friendly, and so future per-entry fields (e.g.
# equip_on_spawn) cost one @export here, no .tres migration.

@export var item_id: StringName = &""
@export var count: int = 1
