class_name CharacterModel
extends Node3D
## Ember Art batch_02 (Quaternius) character bodies. Instances a rigged GLB, scales it to a
## door-friendly height (~1.75 m), faces it down -Z, and plays Idle / Walk from its own
## movement (position delta), so tweens in cinematics, NPC walks and network-smoothed co-op
## players all animate without extra calls. Speakers / archetypes without a model keep their
## placeholder body - `for_speaker` / `for_archetype` return "". Step 119 (batch_03): the
## Elders (recoloured Quaternius wizards), Loli (KayKit witch, 1.3 m) and Nerd (KayKit
## scholar); KayKit models have no clips, so the Rig_Medium libraries are attached.

const HEIGHT := 1.75
const WALK_SPEED := 0.35  ## m/s above which the walk clip plays
const DIR := "res://assets/quaternius/"
## Ember Art drop-in for Bob. A rigged GLB here (Idle / Walk, about 1.75 m, facing +Z)
## replaces the placeholder below. Until that file exists, Bob uses the ash elder wizard
## with BOB_WEAR so he reads as a haggard old wizard, not the farmer and not Crazy Joe.
const BOB_ART := "res://assets/original/ember_art/characters/bob_wizard.glb"
const BOB_PLACEHOLDER := "elders/Elder_ash.glb"
const BOB_WEAR := Color(0.58, 0.46, 0.34)
const SPEAKERS := {
	"Bob": BOB_PLACEHOLDER,
	"Clerk": "clerk/Animated_Woman_green_dress.glb",
	"Crazy Joe": "crazy_joe/Animated_Wizard_old_man.glb",
	"Elder": "elders/Elder_crimson.glb",
	"Elder Green": "elders/Elder_green.glb",
	"Elder Ash": "elders/Elder_ash.glb",
	# step 120 (A2): the rest of the intro / town cast, reusing batch_02 bodies with tints
	"Wounded scavenger": "gal/Hooded_Adventurer.glb",
	"Bored Guard": "bob/Adventurer_male.glb",
	"Grizzled Patron": "bob/Farmer.glb",
	"Potion Merchant": "clerk/Animated_Woman_casual.glb",
	"Runesmith": "clerk/Business_Man.glb",
	"Tailor": "clerk/Animated_Woman_casual.glb",
	"Verdant Mother": "res://assets/original/ember_art/blightcoil/verdant_mother.glb",
}
## Speaker tints (alpha-blended overlay) so reused bodies read as different people.
const TINTS := {
	"Wounded scavenger": Color(0.45, 0.35, 0.25, 0.18),
	"Bored Guard": Color(0.35, 0.4, 0.55, 0.18),
	"Grizzled Patron": Color(0.3, 0.25, 0.2, 0.18),
	"Runesmith": Color(0.5, 0.3, 0.7, 0.18),
	"Tailor": Color(0.8, 0.3, 0.45, 0.18),
}
const ARCHETYPES := {
	"gal": "gal/Adventurer_female.glb",
	"buff": "buff/King_armored.glb",  # placeholder until a proper Buff model arrives
	"loli": "res://assets/kaykit/loli/Witch_Mage_1p3m.glb",
	"nerd": "res://assets/kaykit/nerd/Nerd_Scholar.glb",
}
## Per-model height overrides (m); everyone else is HEIGHT.
const HEIGHTS := {"Witch_Mage_1p3m.glb": 1.3, "Nerd_Scholar.glb": 1.6}
const KAYKIT_ANIMS := [
	"res://assets/kaykit/anims/Rig_Medium_General.glb", "res://assets/kaykit/anims/Rig_Medium_MovementBasic.glb"
]
const IDLE := ["Idle_Neutral", "Idle", "kaykit/Idle_A", "Rat_Idle", "Slime_Idle"]
const WALK := ["Walk", "kaykit/Walking_A", "Rat_Run", "Slime_Walk"]

var anim: AnimationPlayer
var _last := Vector3.INF
var _walking := false
var _speed := 0.0
var _held := ""  ## a clip frozen on its last frame (wounded); walk/idle do not steal it
var _resuming := false


## The model path for a dialogue speaker ("Summoned Gal" maps through the archetype), or "".
static func for_speaker(speaker: String) -> String:
	if speaker == "Bob" and ResourceLoader.exists(BOB_ART):
		return BOB_ART
	if SPEAKERS.has(speaker):
		var p := String(SPEAKERS[speaker])
		return p if p.begins_with("res://") else DIR + p
	if speaker.begins_with("Summoned "):
		return for_archetype(speaker.trim_prefix("Summoned ").to_lower())
	return ""


static func for_archetype(id: String) -> String:
	if not ARCHETYPES.has(id):
		return ""
	var p := String(ARCHETYPES[id])
	return p if p.begins_with("res://") else DIR + p


## A ready model node, or null when the path is empty / fails to load (caller keeps its placeholder).
## for_speaker + make + the speaker's tint (if any).
static func make_for_speaker(speaker: String) -> CharacterModel:
	var path := for_speaker(speaker)
	var cm := make(path)
	if cm and speaker == "Bob" and path != BOB_ART:
		_wear(cm, BOB_WEAR)
	if cm and TINTS.has(speaker):
		var m := StandardMaterial3D.new()
		m.albedo_color = TINTS[speaker]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for mi in cm.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = m
	return cm


static func make(path: String) -> CharacterModel:
	return make_sized(path, float(HEIGHTS.get(path.get_file(), HEIGHT)))


## Like make() with an explicit height (enemies fit their collision box).
static func make_sized(path: String, height: float) -> CharacterModel:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var cm := CharacterModel.new()
	cm.name = "CharacterModel"
	var inst := ps.instantiate() as Node3D
	inst.rotation.y = PI  # Quaternius faces +Z; Godot's forward is -Z
	cm.add_child(inst)
	cm._fit(inst, height)
	cm.anim = cm.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if cm.anim == null and inst.get_node_or_null("Rig_Medium/Skeleton3D") != null:
		cm.anim = _kaykit_player(inst)
	cm._play(IDLE)
	return cm


## KayKit Rig_Medium models ship without clips: borrow the pack's shared animation libraries
## (tracks are "Rig_Medium/Skeleton3D:bone", the same path under every KayKit model).
static func _kaykit_player(inst: Node3D) -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	inst.add_child(ap)
	ap.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	for src in KAYKIT_ANIMS:
		if not ResourceLoader.exists(src):
			continue
		var tmp := (load(src) as PackedScene).instantiate()
		var sp := tmp.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if sp:
			for n in sp.get_animation_list():
				if not lib.has_animation(n):
					lib.add_animation(n, sp.get_animation(n).duplicate())
		tmp.free()
	ap.add_animation_library("kaykit", lib)
	return ap


## Multiplies albedo on a duplicate of each surface, so a shared GLB (Joe, the Elders)
## is not recoloured for everyone.
static func _wear(cm: CharacterModel, tint: Color) -> void:
	for mi in cm.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var base := mesh.surface_get_material(s) as StandardMaterial3D
			if base == null:
				continue
			var m := base.duplicate() as StandardMaterial3D
			m.albedo_color = tint
			(mi as MeshInstance3D).set_surface_override_material(s, m)


func _fit(inst: Node3D, height: float = HEIGHT) -> void:
	var box := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a: AABB = _local_xform(inst, m) * m.get_aabb()
		# Skinned mesh: some exports (batch_04 rats/slimes) keep vertices in metres AND scale the
		# armature x100, so the naive box is tens of metres - then skip the armature scale. Batch_02
		# humanoids store cm-sized vertices under the same x100 armature, so they keep it.
		if m.get_parent() is Skeleton3D and m.get_parent().get_parent() is Node3D:
			var arm := m.get_parent().get_parent() as Node3D
			if arm != inst and not arm.scale.is_equal_approx(Vector3.ONE) and a.size.y > 20.0:
				a = (
					_local_xform(inst, arm.get_parent() as Node3D) * m.get_aabb()
					if arm.get_parent() != inst
					else m.get_aabb()
				)
		box = a if first else box.merge(a)
		first = false
	if first or box.size.y <= 0.001:
		return
	var s := height / box.size.y
	inst.scale *= s
	inst.position.y = -box.position.y * s


static func _local_xform(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## One non-looping clip (Talk, Attack, SporeSpray). Idle (or the held pose) resumes after.
func play_once(clip: String) -> bool:
	var full := _match(clip)
	if full == "":
		return false
	var a := anim.get_animation(full)
	a.loop_mode = Animation.LOOP_NONE
	if not anim.animation_finished.is_connected(_resume_idle):
		anim.animation_finished.connect(_resume_idle)
	anim.play(full, 0.15)
	return true


## Freeze `clip` on its last frame (the scavenger's fallen pose). Empty when the rig has no such clip.
func hold(clip: String) -> bool:
	var full := _match(clip)
	if full == "":
		return false
	_held = clip
	var a := anim.get_animation(full)
	a.loop_mode = Animation.LOOP_NONE
	anim.play(full)
	anim.seek(maxf(a.length - 0.05, 0.0), true)
	anim.pause()
	return true


func release() -> void:
	_held = ""
	_play(IDLE)


func holding() -> String:
	return _held


func _match(clip: String) -> String:
	if anim == null:
		return ""
	for full in anim.get_animation_list():
		var leaf := String(full).get_slice("|", 1) if String(full).contains("|") else String(full)
		if leaf == clip or String(full) == clip:
			return full
	return ""


func _resume_idle(_anim_name: StringName) -> void:
	if _resuming:
		return
	_resuming = true
	if _held != "":
		hold(_held)
	else:
		_play(IDLE)
	_resuming = false


func _play(names: Array) -> void:
	if anim == null:
		return
	for n in names:
		for full in anim.get_animation_list():
			if full == n or String(full).get_slice("|", 1) == n:
				var a := anim.get_animation(full)
				a.loop_mode = Animation.LOOP_LINEAR
				anim.play(full, 0.2)
				return


func is_walking() -> bool:
	return _walking


func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	var p := global_position
	if _last != Vector3.INF:
		var flat := Vector2(p.x - _last.x, p.z - _last.z).length() / dt
		_speed = lerpf(_speed, flat, clampf(dt * 10.0, 0.0, 1.0))
	_last = p
	var w := _speed > WALK_SPEED
	if w != _walking:
		_walking = w
		if _held == "":
			_play(WALK if w else IDLE)
