class_name LootPickup
extends Area3D
## A dropped item lying in the world (BUILD_PLAN step 22; Magewar loot_pickup /
## dropped item visuals reinterpreted): a small rarity-tinted emissive gem box, a thin
## vertical light beam in the rarity colour (taller for higher tiers, Borderlands-style
## readability without its assets), an OmniLight and a billboard Label3D with
## LootDrop.describe(). It is an Area3D on PICKUP_LAYER so step 23 can detect the player
## walking over it / looking at it. `drop` is the LootDrop it carries.

const PICKUP_LAYER := 5  ## physics layer 5 = pickups (1 world, 2 player, 3 enemies)
const GROUP := &"loot_pickups"
const BEAM_BASE := 1.5  ## m, Basic
const BEAM_PER_TIER := 0.5  ## m per rarity tier above Basic (pre-0.3.1; see BEAM_HEIGHTS)
## 0.3.1 P4 (M2): beam height per Rarity.Tier (batch_09_polish HANDOFF: 2.5 / 3.5 / 4.5 / 6,
## Primordial a step under Unique so every tier still reads taller).
const BEAM_HEIGHTS: PackedFloat64Array = [1.5, 2.5, 3.5, 4.5, 5.5, 6.0]
const MAGNET_SPEED := 6.0  ## m/s across the ground while pulled
const MAGNET_ARC := 0.35  ## m hop height over a full pull
const BEAM_FADE_NEAR := 0.6  ## m from the camera: beam fully faded
const BEAM_FADE_FAR := 3.0  ## m: beam at full strength beyond this
const GEM_SIZE := 0.25
const BEAM_SHADER := preload("res://shaders/fx/loot_beam.gdshader")  ## step 130
const RING_SHADER := preload("res://shaders/fx/loot_ring.gdshader")  ## step 130
const SWIRL_TIER := 4  ## Primordial and up: swirling bands
const RUNE_TIER := 5  ## Unique: rotating rune ticks in the ground ring
const PROP_SCALE := 1.6  ## step 123: ground props read at ~10 m

enum Auto { NONE, MANA, DUST, POTION, GOLD }  ## step 23: walk-over auto-collect kinds

var drop: LootDrop  ## the item (Interact to pick up); null for auto pickups
var auto: Auto = Auto.NONE
var amount := 0  ## mana points / dust / potion count for auto pickups
var potion: ConsumableItem
var color := Color.WHITE
var beam: MeshInstance3D
var ring: MeshInstance3D  ## step 130: ground ring
var gem: MeshInstance3D  ## rarity glow pad (step 123; was the gem box)
var prop: Node3D  ## step 123 ground prop (LootMeshes)
var light: OmniLight3D
var label: Label3D
var pull_from := Vector3.ZERO  ## M2: where the magnet pull started
var pulled := 0.0  ## M2: m travelled toward the player (0 = not pulled)
var shared := false  ## 0.3.2: dropped for the whole party
var share_id := 0
var _caption := ""


static func create(d: LootDrop, at: Vector3) -> LootPickup:
	var p := LootPickup.new()
	p.setup(d)
	p.position = at
	return p


## Mana orb (Magewar mana pickups): restores `n` mana on walk-over, waits while mana is full.
static func create_mana(n: int, at: Vector3) -> LootPickup:
	return _auto(Auto.MANA, n, null, at, Color(0.35, 0.55, 1.0), "Mana +%d" % n)


## Arcane Dust (step 26 salvage currency) on walk-over.
static func create_dust(n: int, at: Vector3) -> LootPickup:
	return _auto(Auto.DUST, n, null, at, Color(0.8, 0.6, 1.0), "Arcane Dust x%d" % n)


## Step 59: gold coins (Magewar gold_drop) on walk-over.
static func create_gold(n: int, at: Vector3) -> LootPickup:
	return _auto(Auto.GOLD, n, null, at, Color(1.0, 0.82, 0.2), "%d Gold" % n)


## Potions go to the quick-slot on walk-over; what does not fit stays on the ground.
static func create_potion(item: ConsumableItem, count: int, at: Vector3) -> LootPickup:
	return _auto(Auto.POTION, count, item, at, Color(1.0, 0.35, 0.35), "%s x%d" % [item.display_name, count])


static func _auto(k: Auto, n: int, item: ConsumableItem, at: Vector3, c: Color, text: String) -> LootPickup:
	var p := LootPickup.new()
	p.auto = k
	p.amount = n
	p.potion = item
	p._build("Pickup_%s" % Auto.keys()[k].to_lower(), c, text, String(Auto.keys()[k]).to_lower())
	p.position = at
	return p


func is_auto() -> bool:
	return auto != Auto.NONE


func setup(d: LootDrop) -> void:
	drop = d
	_build("Pickup_%s" % d.rarity_id, d.rarity_color(), d.describe(), LootMeshes.kind_for(d))


## Step 123: `kind` picks the LootMeshes ground prop; the rarity "gem" becomes a glowing pad under it.
func _build(n: String, c: Color, text: String, kind := "") -> void:
	name = n
	color = c
	collision_layer = 1 << (PICKUP_LAYER - 1)
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(GROUP)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.4
	cs.shape = sh
	cs.position.y = GEM_SIZE * 0.5
	add_child(cs)
	gem = MeshInstance3D.new()
	gem.name = "Gem"
	var bm := CylinderMesh.new()
	bm.top_radius = GEM_SIZE
	bm.bottom_radius = GEM_SIZE * 1.15
	bm.height = 0.02
	bm.radial_segments = 12
	bm.rings = 1
	gem.mesh = bm
	gem.position.y = 0.01
	var gm := StandardMaterial3D.new()
	gm.albedo_color = color
	gm.emission_enabled = true
	gm.emission = color
	gm.emission_energy_multiplier = 0.5
	gem.material_override = gm
	add_child(gem)
	prop = LootMeshes.prop_for(kind, color)
	prop.position.y = 0.02
	prop.scale = Vector3.ONE * PROP_SCALE
	add_child(prop)
	beam = MeshInstance3D.new()
	beam.name = "Beam"
	var t := Rarity.parse(drop.rarity_id) if drop else 0
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05 + 0.01 * maxi(t, 0)
	cm.bottom_radius = 0.09 + 0.015 * maxi(t, 0)
	cm.height = beam_height()
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.position.y = cm.height * 0.5
	# Step 130: shader beam (loot_beam.gdshader); the close fade lives in the shader now.
	var mm := ShaderMaterial.new()
	mm.shader = BEAM_SHADER
	mm.set_shader_parameter(&"beam_color", color)
	mm.set_shader_parameter(&"tier", float(maxi(t, 0)))
	mm.set_shader_parameter(&"swirl", 1.0 if t >= SWIRL_TIER else 0.0)
	mm.set_shader_parameter(&"fade_near", BEAM_FADE_NEAR)
	mm.set_shader_parameter(&"fade_far", BEAM_FADE_FAR)
	beam.material_override = mm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	ring = MeshInstance3D.new()
	ring.name = "Ring"
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * (0.9 + 0.1 * maxi(t, 0))
	ring.mesh = pm
	ring.position.y = 0.025
	var rm := ShaderMaterial.new()
	rm.shader = RING_SHADER
	rm.set_shader_parameter(&"ring_color", color)
	rm.set_shader_parameter(&"runes", 1.0 if t >= RUNE_TIER else 0.0)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.omni_range = 2.5
	light.light_energy = 0.8
	light.position.y = 0.5
	add_child(light)
	label = Label3D.new()
	label.name = "Label"
	_caption = text
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.position.y = 0.75
	add_child(label)
	refresh_caption()


## Instanced drops say so. A shared drop is visible to the party.
func refresh_caption() -> void:
	if label == null:
		return
	if shared:
		label.text = "Shared · " + _caption
	elif Coop.active():
		label.text = "Yours · " + _caption
	else:
		label.text = _caption


func beam_height() -> float:
	var t := Rarity.parse(drop.rarity_id) if drop else 0
	return BEAM_HEIGHTS[clampi(t, 0, BEAM_HEIGHTS.size() - 1)]


## M2: one magnet step toward `to` (the player's feet): slides across the ground at
## MAGNET_SPEED on a little hop that peaks halfway. Returns the new global position.
func pull_toward(to: Vector3, dt: float) -> Vector3:
	if pulled <= 0.0:
		pull_from = global_position
	var span := maxf((to - pull_from).length(), 1e-3)
	pulled = minf(pulled + MAGNET_SPEED * dt, span)
	global_position = magnet_point(pull_from, to, pulled / span)
	return global_position


## M2: the arc point at `t` (0..1) between `from` and `to`.
static func magnet_point(from: Vector3, to: Vector3, t: float) -> Vector3:
	var k := clampf(t, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)  # ease out
	return from.lerp(to, e) + Vector3(0, MAGNET_ARC * sin(PI * k), 0)
