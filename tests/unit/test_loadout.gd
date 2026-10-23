extends TestCase
## Step 10 done check (port of the archived test_loadout.cpp, old step 21): staff + wand
## slots, 0.4 s swap, per-slot cooldown, one mana pool, viewmodel poses / focus slide /
## gem colour / cast-point tracer, recoil + shake under reduced motion.
##  - a swap takes 24 ticks (60 Hz) with no cast, no mana check/cue, no spread draw/bloom;
##  - the Earthward Battlestaff's 0.55 s (33 tick) cooldown survives a swap (and keeps
##    counting while holstered) - Magewar resets it, ours doesn't;
##  - 10 Fire staff + 20 Swift Wind wand casts drain the same 100 pool;
##  - each slot casts with its own accuracy, bloom survives a swap;
##  - viewmodel at Magewar's poses, focus amount 1 -> slide x = 0, draw drop;
##  - gem colour = the element colour (cos >= 0.97): a real render of the viewmodel layer
##    when a GPU is present, else (headless dummy renderer: no viewport images) the
##    deterministic fallback = unshaded gem material colour + gem inside the viewmodel
##    camera's frustum + layer masks;
##  - the bolt ray stays at the eye, only the tracer starts at the cast point;
##  - recoil + shake are zero under reduced motion.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"

func _world(at: Vector3) -> Array:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	w.global_position = at
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	floor.add_child(cs)
	floor.position = Vector3(0, -0.5, 0)
	w.add_child(floor)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	var bolts := SpellBolts.new()
	bolts.auto_tick = false
	w.add_child(bolts)
	p.bolts = bolts
	return [w, p, bolts]

func _armed(at: Vector3, staff_id := "apprentice_fire_staff", wand_id := "swift_wind_wand") -> Array:
	var r := _world(at)
	var p: Player = r[1]
	p.equip(WieldableInstance.load_base(staff_id))
	p.equip(WieldableInstance.load_base(wand_id))
	return r

func _cos(a: Color, b: Color) -> float:
	var va := Vector3(a.r, a.g, a.b)
	var vb := Vector3(b.r, b.g, b.b)
	return va.dot(vb) / maxf(1e-9, va.length() * vb.length())

# --- Slots + swap -----------------------------------------------------------------------

func test_slots_by_type_and_selection() -> void:
	var r := _world(Vector3(3000, 0, -3000))
	var p: Player = r[1]
	var staff := WieldableInstance.load_base("apprentice_fire_staff")
	var wand := WieldableInstance.load_base("swift_wind_wand")
	check(p.caster.wieldable == null and not p.viewmodel.visible, "empty hands, viewmodel hidden")
	check(p.equip(wand) == Loadout.Slot.WAND, "a wand goes into the wand slot")
	check(p.loadout.active == Loadout.Slot.WAND and not p.loadout.swapping(), "empty hands: drawn at once")
	check(p.equip(staff) == Loadout.Slot.STAFF and p.loadout.active == Loadout.Slot.WAND, "staff stored, wand stays in hand")
	check(p.loadout.casters[0] != p.loadout.casters[1], "each slot its own Caster")
	check(p.loadout.casters[0].mana_spender.get_object() == p.mana and p.loadout.casters[1].mana_spender.get_object() == p.mana,
		"both slots spend player.mana")
	check(not p.loadout.select(Loadout.Slot.WAND), "selecting the slot in hand: no swap")
	p.tick(PlayerInput.hold([], ["slot_1"]), DT)
	check(p.loadout.active == Loadout.Slot.STAFF and p.loadout.swapping() and p.loadout.swaps == 1, "slot_1 draws the staff")
	# Mouse wheel = quickslot_next/prev (Magewar binds both to wheel down: ours prev = up).
	for i in 30:
		p.tick(PlayerInput.hold(), DT)
	p.tick(PlayerInput.hold([], ["quickslot_next_wieldable"]), DT)
	check(p.loadout.active == Loadout.Slot.WAND, "wheel next -> wand")
	p.tick(PlayerInput.hold([], ["quickslot_prev_wieldable"]), DT)
	check(p.loadout.active == Loadout.Slot.STAFF and p.loadout.swaps == 3, "wheel prev mid-swap -> staff (restarts the draw)")
	p.loadout.unequip(Loadout.Slot.WAND)
	check(not p.loadout.cycle(1) and not p.loadout.select(Loadout.Slot.WAND), "an empty slot can't be drawn")
	var up := InputMap.action_get_events(&"quickslot_prev_wieldable")
	var down := InputMap.action_get_events(&"quickslot_next_wieldable")
	check(up.size() == 1 and (up[0] as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP, "prev = wheel up")
	check(down.size() == 1 and (down[0] as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN, "next = wheel down")
	check(PlayerInput.ACTIONS.has(&"quickslot_next_wieldable") and PlayerInput.ACTIONS.has(&"quickslot_prev_wieldable"), "wheel actions read")
	r[0].free()

func test_swap_24_ticks_no_cast() -> void:
	var r := _armed(Vector3(3100, 0, -3000))
	var p: Player = r[1]
	var fire_held := PlayerInput.hold(["action_primary"], ["action_primary"])
	p.tick(PlayerInput.hold([], ["slot_2", "action_primary"]), DT)   # tick 0: swap + press
	var first := -1 if p.caster.casts == 0 else 0
	var refused_before := -1
	for t in range(1, 40):
		p.tick(fire_held, DT)
		if first < 0 and p.caster.casts > 0:
			first = t
			refused_before = p.caster.blocked
	print("    loadout: swap staff -> wand, first wand cast at tick %d (%d presses blocked)" % [first, p.loadout.swap_blocked])
	check(first == 24, "first cast 24 ticks (0.4 s) after the swap press (got %d)" % first)
	check(p.loadout.swap_blocked == 24, "24 presses blocked by the draw (%d)" % p.loadout.swap_blocked)
	check(p.loadout.casters[0].casts == 0, "the holstered staff never cast")
	check(p.not_enough_mana_cues == 0 and p.caster.mana_refused == 0 and refused_before == 0, "no mana check / cue during the swap")
	check_near(p.mana.value, 100.0 - 2.5 * p.caster.casts, 1e-9, "only real casts cost mana")
	r[0].free()

func test_earthward_cooldown_survives_swap() -> void:
	# Control: no swap, press every tick -> 2nd cast at tick 33 (0.55 s).
	var c := _armed(Vector3(3200, 0, -3000), "earthward_battlestaff")
	var pc: Player = c[1]
	var fire := PlayerInput.hold(["action_primary"], ["action_primary"])
	var control := -1
	for t in 60:
		pc.tick(fire, DT)
		if control < 0 and pc.caster.casts == 2:
			control = t
	c[0].free()
	# Swap away at tick 1 and back at tick 2: the draw ends at tick 26, the cooldown at 33.
	var r := _armed(Vector3(3300, 0, -3000), "earthward_battlestaff")
	var p: Player = r[1]
	var staff := p.loadout.casters[Loadout.Slot.STAFF]
	p.tick(fire, DT)
	check(staff.casts == 1, "cast at tick 0")
	p.tick(PlayerInput.hold([], ["slot_2"]), DT)
	check(staff.cooldown_left > 0.0 and staff.cooldown_left < 0.55, "holstered: still counting (%f)" % staff.cooldown_left)
	p.tick(PlayerInput.hold([], ["slot_1"]), DT)
	var second := -1
	for t in range(3, 60):
		p.tick(fire, DT)
		if second < 0 and staff.casts == 2:
			second = t
	print("    loadout: Earthward 2nd cast at tick %d with a swap-cancel (control %d; draw over at 26)" % [second, control])
	check(control == 33, "control: 33 ticks (got %d)" % control)
	check(second == 33, "swap doesn't reset the cooldown: tick 33, not 26 (got %d)" % second)
	# Holstered long enough: ready the moment the draw ends.
	p.tick(PlayerInput.hold([], ["slot_2"]), DT)
	var wand_ready := -1
	for t in 60:
		p.tick(PlayerInput.hold(), DT)
	check(staff.cooldown_left == 0.0, "cooled down while holstered")
	p.tick(PlayerInput.hold([], ["slot_1"]), DT)
	for t in range(1, 30):
		p.tick(fire, DT)
		if wand_ready < 0 and staff.casts == 3:
			wand_ready = t
	check(wand_ready == 24, "a holstered staff casts as soon as it's drawn (%d)" % wand_ready)
	r[0].free()

func test_staff_and_wand_share_one_mana_pool() -> void:
	var r := _armed(Vector3(3400, 0, -3000))
	var p: Player = r[1]
	var fire := PlayerInput.hold(["action_primary"], ["action_primary"])
	var staff := p.loadout.casters[Loadout.Slot.STAFF]
	var wand := p.loadout.casters[Loadout.Slot.WAND]
	var guard := 0
	while staff.casts < 10 and guard < 1000:
		p.tick(fire, DT)
		guard += 1
	check_near(p.mana.value, 50.0, 1e-9, "10 Fire staff casts: 50 left")
	p.tick(PlayerInput.hold([], ["slot_2"]), DT)
	check_near(p.mana.value, 50.0, 1e-9, "a swap never touches mana")
	while wand.casts < 20 and guard < 2000:
		p.tick(fire, DT)
		guard += 1
	print("    loadout: 10 Fire staff (5) + 20 Swift Wind (2.5) casts -> mana %.2f/%.0f, %d spends" % [p.mana.value, p.mana.max_value(), p.mana.spends])
	check(p.mana.value == 0.0 and p.mana.spends == 30, "10 x 5 + 20 x 2.5 = 100 from one pool (%f, %d)" % [p.mana.value, p.mana.spends])
	check(p.not_enough_mana_cues == 0, "no refusals so far")
	# Empty: the wand's next press is refused with the cue; a press during the swap isn't.
	var cues := 0
	for t in 12:
		p.tick(fire, DT)
	cues = p.not_enough_mana_cues
	check(cues > 0 and wand.mana_refused == cues, "empty pool: the wand shows 'Not enough mana!'")
	p.tick(PlayerInput.hold([], ["slot_1", "action_primary"]), DT)
	for t in 23:
		p.tick(fire, DT)
	check(p.not_enough_mana_cues == cues and staff.mana_refused == 0, "presses during a swap: no mana cue")
	p.tick(fire, DT)
	check(p.not_enough_mana_cues == cues + 1 and staff.mana_refused == 1, "after the draw the staff is refused too")
	# set_mana rebinds every slot.
	var m := Mana.new()
	p.set_mana(m)
	check(staff.mana_spender.get_object() == m and wand.mana_spender.get_object() == m, "set_mana rebinds both slots")
	r[0].free()

func test_own_accuracy_and_bloom_survives_swap() -> void:
	var r := _armed(Vector3(3500, 0, -3000))
	var p: Player = r[1]
	p.tick(PlayerInput.hold([], ["action_primary"]), DT)
	check(p.accuracy() == p.loadout.wieldable(Loadout.Slot.STAFF).accuracy(), "staff in hand: staff accuracy")
	var b0 := p.spread.bloom
	check(b0 > 0.0, "a cast blooms (%f)" % b0)
	# Control decay without a swap.
	var s := Spread.from_tuning(p.tuning)
	s.bloom = b0
	p.tick(PlayerInput.hold([], ["slot_2", "action_primary"]), DT)
	s.tick(DT)
	check(p.spread.bloom > 0.0 and is_equal_approx(p.spread.bloom, s.bloom), "bloom survives the swap (%f vs %f)" % [p.spread.bloom, s.bloom])
	for t in 5:
		p.tick(PlayerInput.hold(["action_primary"], ["action_primary"]), DT)
		s.tick(DT)
	check(is_equal_approx(p.spread.bloom, s.bloom), "presses during the draw add no bloom")
	check(p.accuracy() == p.loadout.wieldable(Loadout.Slot.WAND).accuracy(), "wand in hand: wand accuracy")
	r[0].free()

# --- Viewmodel --------------------------------------------------------------------------

func test_viewmodel_poses_focus_slide_and_draw() -> void:
	var r := _armed(Vector3(3600, 0, -3000))
	var p: Player = r[1]
	var vm := p.viewmodel
	check(vm.get_parent() == p.head, "the viewmodel follows the Head")
	check(Viewmodel.STAFF_POSE == Vector3(0.33, -0.26, -0.53) and Viewmodel.WAND_POSE == Vector3(0.3, -0.24, -0.5), "Magewar default_position poses")
	p.tick(PlayerInput.hold(), DT)
	check(vm.visible and vm.model.position.is_equal_approx(Viewmodel.STAFF_POSE), "staff at its pose (%s)" % vm.model.position)
	check(vm.fov == 75.0 and p.tuning.viewmodel_fov == 75.0, "viewmodel fov 75")
	var aim := PlayerInput.hold(["action_secondary"])
	for t in 6:
		p.tick(aim, DT)
	check_near(vm.model.position.x, 0.165, 1e-6, "half focused: half slid (%f)" % vm.model.position.x)
	for t in 6:
		p.tick(aim, DT)
	check(p.focus.amount() == 1.0 and vm.model.position.x == 0.0, "focus amount 1 -> slide x = 0")
	check(vm.model.position.is_equal_approx(Vector3(0.0, -0.26, -0.53)), "slide keeps default y/z")
	# Swap while focused: focus retargets (same 55), wand rises from below its focus pose.
	p.tick(PlayerInput.hold(["action_secondary"], ["slot_2"]), DT)
	check(p.focus.amount() == 1.0 and p.focus.fov == 55.0, "still focused during the swap")
	check(vm.shown_type == WieldableDef.Type.WAND, "wand shown")
	check(vm.model.position.is_equal_approx(Vector3(0.0, -0.24 - Viewmodel.DRAW_DROP, -0.5)), "draw starts DRAW_DROP below (%s)" % vm.model.position)
	for t in 24:
		p.tick(aim, DT)
	check(vm.model.position.is_equal_approx(Vector3(0.0, -0.24, -0.5)), "drawn: wand focus pose (%s)" % vm.model.position)
	check(p.camera.fov == 55.0 and vm.fov == 75.0, "camera zooms, viewmodel stays at 75")
	for t in 12:
		p.tick(PlayerInput.hold(), DT)
	check(vm.model.position.is_equal_approx(Viewmodel.WAND_POSE), "wand back at its hip pose")
	r[0].free()

func test_gem_colour_render_or_fallback() -> void:
	var table := ElementTable.load_default()
	for id in ["apprentice_fire_staff", "earthward_battlestaff", "novice_arcane_wand", "swift_wind_wand"]:
		var vm := Viewmodel.new()
		var w := WieldableInstance.load_base(id)
		vm.show_wieldable(w)
		var want := table.color(w.element())
		var c := _cos(vm.gem_color(), want)
		check(c >= 0.97, "%s gem colour cos %.4f" % [id, c])
		check((vm.gem.material_override as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "%s gem unshaded" % id)
		check(vm.gem.layers == Viewmodel.LAYER_MASK and vm.shaft.layers == Viewmodel.LAYER_MASK, "%s on the viewmodel layer only" % id)
		vm.free()
	var r := _armed(Vector3(3700, 0, -3000))
	var p: Player = r[1]
	var size := Vector2i(160, 120)
	var main_mask := p.camera.cull_mask
	p.viewmodel.enable_render(p.camera, size)
	p.tick(PlayerInput.hold(), DT)
	check(p.camera.cull_mask == main_mask & ~Viewmodel.LAYER_MASK and p.camera.cull_mask & 1 != 0, "main camera culls only the viewmodel layer")
	check(p.viewmodel.render_camera.cull_mask == Viewmodel.LAYER_MASK and p.viewmodel.render_camera.fov == 75.0, "viewmodel camera: its layer, 75 deg")
	check(p.viewmodel.render_viewport.transparent_bg, "transparent overlay")
	check(p.viewmodel.render_camera.global_transform.is_equal_approx(p.camera.global_transform), "viewmodel camera on the eye")
	check(p.viewmodel.gem_in_view(), "gem inside the viewmodel image (%s)" % p.viewmodel.gem_screen_position())
	var want_fire := table.color(ElementTable.Element.FIRE)
	if RenderingServer.get_video_adapter_name() != "":
		RenderingServer.force_draw(false)
		var img := p.viewmodel.render_viewport.get_texture().get_image()
		var px := p.viewmodel.gem_screen_position()
		var got := img.get_pixelv(Vector2i(px)) if img != null else Color.BLACK
		print("    viewmodel: rendered gem pixel %s (want %s), cos %.4f" % [got, want_fire, _cos(got, want_fire)])
		check(_cos(got, want_fire) >= 0.97, "rendered gem colour cos >= 0.97")
	else:
		print("    viewmodel: headless (no GPU) - gem colour checked via unshaded material %s + frustum %s, not a render" % [
			p.viewmodel.gem_color(), p.viewmodel.gem_screen_position()])
		check(_cos(p.viewmodel.gem_color(), want_fire) >= 0.97, "fallback: fire gem colour")
	r[0].free()

func test_ray_at_eye_tracer_from_cast_point() -> void:
	var r := _armed(Vector3(3800, 0, -3000))
	var p: Player = r[1]
	var bolts: SpellBolts = r[2]
	p.tick(PlayerInput.hold(), DT)
	var eye := p.eye_position()
	var tip := p.viewmodel.cast_point_position()
	p.tick(PlayerInput.hold([], ["action_primary"]), DT)
	check(bolts.live.size() == 1, "one bolt")
	var s: SpellBolts.Spawn = bolts.live[0].spawn
	check(s.origin.is_equal_approx(p.eye_position()) and s.origin.is_equal_approx(eye), "the bolt ray starts at the eye")
	check(s.has_visual_origin, "visual origin set")
	check(s.visual_origin.distance_to(tip) < 1e-4 and s.visual_origin.distance_to(eye) > 0.3, "cast point at the staff tip (%s)" % s.visual_origin)
	bolts.tick(DT)
	var lines := bolts.tracer_lines(1.0)
	check(lines.size() == 1 and lines[0].a.is_equal_approx(s.visual_origin), "tracer starts at the cast point")
	var far := SpellBolts.drawn_point(s, SpellBolts.CONVERGE)
	check(far.is_equal_approx(s.origin + s.direction * SpellBolts.CONVERGE), "tracer merges into the ray by CONVERGE m")
	r[0].free()

# --- Recoil + shake ---------------------------------------------------------------------

func test_recoil_shake_and_reduced_motion() -> void:
	var f := CameraFeel.new()
	f.add_recoil(1.0)
	f.add_shake(0.5)
	check(f.recoil_offset() == Vector3(0.0, 0.012, 0.05), "full kick: back 0.05, up 0.012")
	f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check(f.shake_offset.length() > 0.0 and f.offset().length() > 0.0, "shake moves the eye")
	for t in 7:
		f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check(f.recoil > 0.0, "kick lasts recoil_seconds (%f)" % f.recoil)
	f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check(f.recoil == 0.0, "back to rest in 9 ticks (0.15 s)")
	f.set_reduced_motion(true)
	check(f.shake == 0.0 and f.shake_offset == Vector2.ZERO and f.recoil_offset() == Vector3.ZERO, "reduced motion zeroes them")
	f.add_recoil(1.0)
	f.add_shake(1.0)
	f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check(f.recoil == 0.0 and f.shake == 0.0 and f.offset() == Vector2.ZERO, "reduced motion: kicks ignored")
	# Through the player: a staff cast kicks + shakes, none under reduced motion.
	var r := _armed(Vector3(3900, 0, -3000))
	var p: Player = r[1]
	p.tick(PlayerInput.hold(), DT)
	p.tick(PlayerInput.hold([], ["action_primary"]), DT)
	check(p.feel.recoil == 1.0 and p.feel.shake > 0.0 and p.feel.recoils == 1, "a staff cast: recoil + shake")
	check(p.viewmodel.model.position.z > Viewmodel.STAFF_POSE.z + 0.04, "viewmodel kicked back (%s)" % p.viewmodel.model.position)
	p.tick(PlayerInput.hold(), DT)
	check(absf(p.head.position.x) > 0.0, "shake offsets the head")
	var a := p.aim()
	check(a.origin.is_equal_approx(p.eye_position()), "aim = the (offset) eye, never the viewmodel")
	r[0].free()
	var q := _armed(Vector3(4000, 0, -3000))
	var pq: Player = q[1]
	pq.set_reduced_motion(true)
	pq.tick(PlayerInput.hold(), DT)
	pq.tick(PlayerInput.hold([], ["action_primary"]), DT)
	check(pq.caster.casts == 1 and pq.feel.recoil == 0.0 and pq.feel.shake == 0.0, "reduced motion: no recoil/shake")
	check(pq.viewmodel.model.position == Viewmodel.STAFF_POSE, "viewmodel exactly at its pose")
	pq.tick(PlayerInput.hold(), DT)
	check(pq.head.position.x == 0.0, "no head shake")
	# Wand: lighter kick, no shake.
	pq.set_reduced_motion(false)
	pq.tick(PlayerInput.hold([], ["slot_2"]), DT)
	for t in 24:
		pq.tick(PlayerInput.hold(), DT)
	pq.tick(PlayerInput.hold([], ["action_primary"]), DT)
	check(pq.loadout.casters[1].casts == 1 and is_equal_approx(pq.feel.recoil, 0.6) and pq.feel.shake == 0.0, "wand: 0.6 kick, no shake")
	q[0].free()
