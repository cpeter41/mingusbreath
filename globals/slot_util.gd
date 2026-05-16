class_name SlotUtil
# Shared helpers for save-slot files (worlds, characters).


## Returns `base` if `<dir><base>.dat` is free, else `base_1`, `base_2`, ...
static func unique_name(dir: String, base: String) -> String:
	var d := DirAccess.open(dir)
	if d == null or not d.file_exists(base + ".dat"):
		return base
	var i := 1
	while d.file_exists("%s_%d.dat" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]


## Lists every `*.dat` in `dir`, extension stripped, sorted.
static func list_slots(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".dat"):
			out.append(fname.get_basename())
		fname = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
