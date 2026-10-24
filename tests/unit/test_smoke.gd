extends TestCase


func test_engine_is_godot_4() -> void:
	check(Engine.get_version_info().major == 4, "Godot 4 required")


func test_project_settings() -> void:
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "forward_plus", "Forward+ renderer")
	check(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == 60, "60 Hz physics")


func test_main_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	check(packed != null, "main.tscn loads")
	var root := packed.instantiate()
	check(root.get_node_or_null("Player/Head/Camera3D") is Camera3D, "player camera present")
	check_near(root.get_node("Player/Head/Camera3D").fov, 75.0, 0.001, "hip FOV")
	root.free()


func test_kenney_blaster_imports() -> void:
	var scene: PackedScene = load("res://assets/kenney/blaster-kit/Models/GLB format/blaster-a.glb")
	check(scene != null, "blaster-a.glb imported")
	if scene:
		var n := scene.instantiate()
		check(n.find_children("*", "MeshInstance3D", true, false).size() > 0, "blaster has meshes")
		n.free()


func test_main_scene_loads_midden() -> void:
	var root: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var level := root.get_node_or_null("Level")
	check(level != null and level.get_meta("level_id", "") == "midden_greybox", "main instances the Midden")
	check(level != null and level.get_node("Boxes").get_child_count() == 17, "17 boxes in main")
	root.free()
