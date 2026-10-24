class_name CharacterModel
extends Node3D
## Ember Art batch_02 (Quaternius) character bodies. Instances a rigged GLB, scales it to a
## door-friendly height (~1.75 m), faces it down -Z, and plays Idle / Walk from its own
## movement (position delta), so tweens in cinematics, NPC walks and network-smoothed co-op
## players all animate without extra calls. Speakers / archetypes without a model keep their
## placeholder body (Nerd, Loli and the rest) - `for_speaker` / `for_archetype` return "".

const HEIGHT := 1.75
const WALK_SPEED := 0.35  ## m/s above which the walk clip plays
const DIR := "res://assets/quaternius/"
const SPEAKERS := {
	"Bob": "bob/Farmer.glb",
	"Clerk": "clerk/Animated_Woman_green_dress.glb",
	"Crazy Joe": "crazy_joe/Animated_Wizard_old_man.glb",
}
const ARCHETYPES := {
	"gal": "gal/Adventurer_female.glb",
	"buff": "buff/King_armored.glb",  # placeholder until a proper Buff model arrives
}
const IDLE := ["Idle_Neutral", "Idle"]
const WALK := ["Walk"]

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
	return DIR + String(ARCHETYPES[id]) if ARCHETYPES.has(id) else ""


## A ready model node, or null when the path is empty / fails to load (caller keeps its placeholder).
static func make(path: String) -> CharacterModel:
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
	cm._fit(inst)
	cm.anim = cm.find_child("AnimationPlayer", true, false) as AnimationPlayer
	cm._play(IDLE)
	return cm


func _fit(inst: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a: AABB = _local_xform(inst, m) * m.get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first or box.size.y <= 0.001:
		return
	var s := HEIGHT / box.size.y
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
		for full in [String(n), "CharacterArmature|" + String(n)]:
			if anim.has_animation(full):
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
