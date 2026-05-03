## DO NOT run during play. Editor-time only — bakes premade island terrain to .tres resources.
@tool
extends EditorScript


func _run() -> void:
	_bake_one(&"island_meadows_01")
	_bake_one(&"island_forest_01")
	_bake_one(&"island_tundra_01")
	_bake_one(&"island_desert_01")


func _bake_one(def_id: StringName) -> void:
	var seed_ := hash(String(def_id))
	var data := IslandGenerator.generate(seed_, 160, 10.0)
	var out_dir := "res://assets/islands/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var mesh_path := "%s%s_mesh.tres" % [out_dir, def_id]
	var col_path := "%s%s_collider.tres" % [out_dir, def_id]
	ResourceSaver.save(data["mesh"], mesh_path)
	ResourceSaver.save(data["collider"], col_path)
	print("baked ", def_id)
