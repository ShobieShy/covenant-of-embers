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
const BEAM_PER_TIER := 0.5  ## m per rarity tier above Basic
const BEAM_FADE_NEAR := 0.6  ## m from the camera: beam fully faded
const BEAM_FADE_FAR := 3.0  ## m: beam at full strength beyond this
const GEM_SIZE := 0.25
const PROP_SCALE := 1.6  ## step 123: ground props read at ~10 m

enum Auto { NONE, MANA, DUST, POTION, GOLD }  ## step 23: walk-over auto-collect kinds

var drop: LootDrop  ## the item (Interact to pick up); null for auto pickups
var auto: Auto = Auto.NONE
var amount := 0  ## mana points / dust / potion count for auto pickups
var potion: ConsumableItem
var color := Color.WHITE
var beam: MeshInstance3D
var gem: MeshInstance3D  ## rarity glow pad (step 123; was the gem box)
var prop: Node3D  ## step 123 ground prop (LootMeshes)
var light: OmniLight3D
var label: Label3D


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
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.06
	cm.height = beam_height()
	beam.mesh = cm
	beam.position.y = cm.height * 0.5
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(color, 0.55)
	# Up close the beam filled the screen: fade it out inside BEAM_FADE_FAR, gone at BEAM_FADE_NEAR.
	mm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mm.distance_fade_min_distance = BEAM_FADE_NEAR
	mm.distance_fade_max_distance = BEAM_FADE_FAR
	beam.material_override = mm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.omni_range = 2.5
	light.light_energy = 0.8
	light.position.y = 0.5
	add_child(light)
	label = Label3D.new()
	label.name = "Label"
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.position.y = 0.75
	add_child(label)


func beam_height() -> float:
	var t := Rarity.parse(drop.rarity_id) if drop else 0
	return BEAM_BASE + BEAM_PER_TIER * maxi(t, 0)
