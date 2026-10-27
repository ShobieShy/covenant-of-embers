class_name WorldStreamer
extends Node3D
## OW3 (OPEN_WORLD_PLAN section 3): streams the 128 m world cells (res://world/cells/,
## tools/build_cells.gd) around every viewer (local players, co-op avatars,
## stream_viewers). Cells within RING of a viewer's cell are requested with
## ResourceLoader.load_threaded_request; finished loads are added at most one per frame and
## only while the frame's add budget (BUDGET_MS) lasts. A cell leaves once no viewer is
## within RING + 1 (hysteresis ring), so walking along a cell line never thrashes.
## OW4b: each cell's baked NavigationMesh (res://world/nav/, tools/bake_world_nav.gd)
## streams on the same rings as its own NavigationRegion3D child (one per frame); nav
## exists for the strips between zones too, where there is no content cell.

const CELL := 128.0
const RING := 2  ## 5 x 5 cells loaded around each viewer
const BUDGET_MS := 2.0
const DIR := "res://world/cells/"
const NAV_DIR := "res://world/nav/"

var cells_dir := DIR
var loaded := {}  ## Vector2i -> Node3D in the tree
var _pending := {}  ## Vector2i -> path being loaded on a thread
var _ready_q: Array[Vector2i] = []
var _known := {}  ## Vector2i -> true for cells that exist on disk
var nav_dir := NAV_DIR
var nav := {}  ## Vector2i -> NavigationRegion3D in the tree
var _nav_known := {}
var stream_partners := false  ## tests: stream around RemotePlayers without a session
var viewer_override: Array[Vector3] = []  ## tests / tools
var hold := false  ## OW11b: no new cell loads while an interior loads (one threaded load at a time)


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _ready() -> void:
	scan()


func scan() -> void:
	_scan_dir(cells_dir, ".tscn", _known)
	_scan_dir(nav_dir, ".res", _nav_known)


static func _scan_dir(dir: String, ext: String, out: Dictionary) -> void:
	out.clear()
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			var p := f.get_basename().split("_")
			if p.size() == 2:
				out[Vector2i(int(p[0]), int(p[1]))] = true


func viewers() -> Array[Vector3]:
	if not viewer_override.is_empty():
		return viewer_override
	var out: Array[Vector3] = []
	if not is_inside_tree():
		return out
	for g in [Player.GROUP, &"stream_viewers"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and (n as Node3D).is_inside_tree():
				out.append((n as Node3D).global_position)
	if stream_partners or Coop.is_host():  # OW9: the host simulates around every partner
		var left := CoopLeash.MAX_PLAYERS - 1
		for n in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
			if left <= 0:
				break
			if n is Node3D and (n as Node3D).is_inside_tree():
				out.append((n as Node3D).global_position)
				left -= 1
	return out


## Cells within `ring` of any viewer (Chebyshev distance in cells), existing on disk only.
func wanted(pts: Array[Vector3], ring: int, known: Dictionary = {}) -> Dictionary:
	if known.is_empty():
		known = _known
	var out := {}
	for v in pts:
		var c := cell_of(Vector2(v.x, v.z))
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var k := c + Vector2i(dx, dz)
				if known.has(k):
					out[k] = true
	return out


func _process(_delta: float) -> void:
	step()


## A streamer freed mid-load (a test, a scene change) collects its threaded loads first, so
## the loader never keeps a stale request for the next streamer of the same cells.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for k in _pending.keys():
			ResourceLoader.load_threaded_get(_pending[k])
		_pending.clear()


## One frame of streaming: request, unload, then add finished cells within the budget.
func step() -> void:
	var pts := viewers()
	if pts.is_empty():
		return
	_step_nav(pts)
	var want := wanted(pts, RING)
	var keep := wanted(pts, RING + 1)
	for k in want:
		if hold:
			break
		if not loaded.has(k) and not _pending.has(k):
			var path := cells_dir + "%d_%d.tscn" % [k.x, k.y]
			ResourceLoader.load_threaded_request(path, "PackedScene")
			_pending[k] = path
	for k in loaded.keys():
		if not keep.has(k):
			(loaded[k] as Node).queue_free()
			loaded.erase(k)
	var fresh: Array[Vector2i] = []  # QA: a cell loaded this step is instantiated next step
	var busy_load := hold  # QA-2: an interior's threaded load is in flight
	for k in _pending.keys():
		var st := ResourceLoader.load_threaded_get_status(_pending[k])
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			busy_load = true
		if st == ResourceLoader.THREAD_LOAD_LOADED and not _ready_q.has(k):
			fresh.append(k)
		elif (
			st == ResourceLoader.THREAD_LOAD_FAILED
			or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		):
			push_warning("WorldStreamer: cell %s failed to load" % k)
			_pending.erase(k)
	var t0 := Time.get_ticks_usec()
	# QA-2: instantiating while another threaded load shares its materials left "material is
	# null" / "Parameter m is null" in the dummy renderer: wait until no load is in flight.
	while (
		not busy_load
		and not _ready_q.is_empty()
		and (Time.get_ticks_usec() - t0) < BUDGET_MS * 1000.0
	):
		var k: Vector2i = _ready_q.pop_front()
		var ps := ResourceLoader.load_threaded_get(_pending[k]) as PackedScene
		_pending.erase(k)
		if not keep.has(k) or ps == null:
			continue  # walked away while it loaded
		var n := ps.instantiate()
		add_child(n)
		loaded[k] = n
		break  # at most one cell per frame
	_ready_q.append_array(fresh)


func _step_nav(pts: Array[Vector3]) -> void:
	if _nav_known.is_empty():
		return
	var keep := wanted(pts, RING + 1, _nav_known)
	for k in nav.keys():
		if not keep.has(k):
			(nav[k] as Node).queue_free()
			nav.erase(k)
	for k in wanted(pts, RING, _nav_known):
		if not nav.has(k):
			var r := NavigationRegion3D.new()
			r.name = "Nav_%d_%d" % [k.x, k.y]
			r.navigation_mesh = load(nav_dir + "%d_%d.res" % [k.x, k.y]) as NavigationMesh
			add_child(r)
			nav[k] = r
			return  # at most one nav tile per frame


## True while any cell scene is still loading on a thread.
func loading() -> bool:
	return not _pending.is_empty()


func nav_pending(pts: Array[Vector3]) -> bool:
	for k in wanted(pts, RING, _nav_known):
		if not nav.has(k):
			return true
	return false


## Blocks until every wanted cell is in (loading screen, tests).
func flush(max_frames := 600) -> void:
	for i in max_frames:
		step()
		if _pending.is_empty() and _ready_q.is_empty() and not nav_pending(viewers()):
			return
		OS.delay_msec(1)
