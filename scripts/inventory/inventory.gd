class_name Inventory
extends Node

signal changed

const MAX_SLOTS := 20

# Each slot: { "item_id": StringName, "count": int }
var slots: Array[Dictionary] = []

func _ready() -> void:
	SaveSystem.register(self)

# Returns leftover count that didn't fit (0 = all added).
func add(item_id: StringName, count: int) -> int:
	var remaining := count
	# Fill existing stacks first.
	for slot in slots:
		if remaining <= 0:
			break
		if slot["item_id"] == item_id:
			var def = InventoryRegistry.get_item(item_id)
			var max_stack: int = def.max_stack if def != null else 99
			var space := max_stack - int(slot["count"])
			if space > 0:
				var take := mini(space, remaining)
				slot["count"] += take
				remaining -= take
	# Open new slots for remainder.
	while remaining > 0 and slots.size() < MAX_SLOTS:
		var def = InventoryRegistry.get_item(item_id)
		var max_stack: int = def.max_stack if def != null else 99
		var take := mini(max_stack, remaining)
		slots.append({"item_id": item_id, "count": take})
		remaining -= take
	if remaining > 0:
		push_warning("[Inventory] full — %d x %s did not fit" % [remaining, item_id])
	changed.emit()
	return remaining

# Returns false if not enough items present.
func remove(item_id: StringName, count: int) -> bool:
	if count_of(item_id) < count:
		return false
	var remaining := count
	for i in range(slots.size() - 1, -1, -1):
		if remaining <= 0:
			break
		if slots[i]["item_id"] == item_id:
			var take := mini(slots[i]["count"], remaining)
			slots[i]["count"] -= take
			remaining -= take
			if slots[i]["count"] <= 0:
				slots.remove_at(i)
	changed.emit()
	return true

func count_of(item_id: StringName) -> int:
	var total := 0
	for slot in slots:
		if slot["item_id"] == item_id:
			total += int(slot["count"])
	return total

func save_data() -> Dictionary:
	var out: Array = []
	for slot in slots:
		out.append({"item_id": str(slot["item_id"]), "count": slot["count"]})
	return {"slots": out}

func load_data(d: Dictionary) -> void:
	slots.clear()
	for entry in d.get("slots", []):
		slots.append({"item_id": StringName(entry["item_id"]), "count": int(entry["count"])})
