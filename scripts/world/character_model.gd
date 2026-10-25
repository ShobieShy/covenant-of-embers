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
const SPEAKERS := {
	"Bob": "bob/Farmer.glb",
	"Clerk": "clerk/Animated_Woman_green_dress.glb",
	"Crazy Joe": "crazy_joe/Animated_Wizard_old_man.glb",
	"Elder": "elders/Elder_crimson.glb",
	"Elder Green": "elders/Elder_green.glb",
	"Elder Ash": "elders/Elder_ash.glb",
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


## The model path for a dialogue speaker ("Summoned Gal" maps through the archetype), or "".
static func for_speaker(speaker: String) -> String:
	if SPEAKERS.has(speaker):
		return DIR + String(SPEAKERS[speaker])
	if speaker.begins_with("Summoned "):
		return for_archetype(speaker.trim_prefix("Summoned ").to_lower())
	return ""


static func for_archetype(id: String) -> String:
	if not ARCHETYPES.has(id):
		return ""
	var p := String(ARCHETYPES[id])
	return p if p.begins_with("res://") else DIR + p


## A ready model node, or null when the path is empty / fails to load (caller keeps its placeholder).
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


func _fit(inst: Node3D, height: float = HEIGHT) -> void:
	var box := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a: AABB = _local_xform(inst, m) * m.get_aabb()
		# Skinned mesh: vertices are already in armature units; the armature's own scale (x100 in
		# some Quaternius exports) is baked into the bones, so skip it or the fit shrinks to nothing.
		if m.get_parent() is Skeleton3D and m.get_parent().get_parent() is Node3D:
			var arm := m.get_parent().get_parent() as Node3D
			if arm != inst and not arm.scale.is_equal_approx(Vector3.ONE):
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
		_play(WALK if w else IDLE)
