extends TestCase
## Steps 119-121 + 120 (A2): every speaker / archetype / enemy model loads and fits to a sane
## scale (guards the skinned-armature fit: batch_02 humanoids once came out 400x too big).


func _scale_ok(path: String, cm: CharacterModel) -> void:
	check(cm != null, "loads " + path)
	if cm:
		var s := (cm.get_child(0) as Node3D).scale.y
		check(s > 0.01 and s < 10.0, "%s fit scale %f" % [path, s])
		cm.free()


func test_speakers_and_archetypes() -> void:
	for sp: String in CharacterModel.SPEAKERS:
		_scale_ok(sp, CharacterModel.make_for_speaker(sp))
	for id: String in CharacterModel.ARCHETYPES:
		_scale_ok(id, CharacterModel.make(CharacterModel.for_archetype(id)))


func test_intro_cast_has_models() -> void:
	for sp in ["Elder", "Clerk", "Wounded scavenger", "Bored Guard", "Potion Merchant", "Runesmith", "Tailor"]:
		check(CharacterModel.for_speaker(sp) != "", "model for " + sp)


func test_enemy_models() -> void:
	for id: String in EnemyModels.MODELS:
		_scale_ok(id, EnemyModels.make(id, 1.0))
