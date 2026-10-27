class_name WorldStreamer
extends Node3D
## OW3 (OPEN_WORLD_PLAN section 3): streams the 128 m world cells (res://world/cells/,
## tools/build_cells.gd) around every viewer (local players, co-op avatars,
## stream_viewers). Cells within RING of a viewer's cell are requested with
## ResourceLoader.load_threaded_request; finished loads are added at most one per frame and
## only while the frame's add budget (BUDGET_MS) lasts. A cell leaves once no viewer is
## within RING + 1 (hysteresis ring), so walking along a cell line never thrashes.

const CELL := 128.0
const RING := 2  ## 5 x 5 cells loaded around each viewer
const BUDGET_MS := 2.0
const DIR := "res://world/cells/"

var cells_dir := DIR
var loaded := {}  ## Vector2i -> Node3D in the tree
var _pending := {}  ## Vector2i -> path being loaded on a thread
var _ready_q: Array[Vector2i] = []
var _known := {}  ## Vector2i -> true for cells that exist on disk
var viewer_override: Array[Vector3] = []  ## tests / tools


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _ready() -> void:
	scan()


func scan() -> void:
	_known.clear()
	if not DirAccess.dir_exists_absolute(cells_dir):
		return
	for f in DirAccess.get_files_at(cells_dir):
		if f.ends_with(".tscn"):
			var p := f.get_basename().split("_")
			if p.size() == 2:
				_known[Vector2i(int(p[0]), int(p[1]))] = true


func viewers() -> Array[Vector3]:
	if not viewer_override.is_empty():
		return viewer_override
	var out: Array[Vector3] = []
	if not is_inside_tree():
		return out
	for g in [Player.GROUP, &"coop_avatars", &"stream_viewers"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and (n as Node3D).is_inside_tree():
				out.append((n as Node3D).global_position)
	return out


## Cells within `ring` of any viewer (Chebyshev distance in cells), existing on disk only.
func wanted(pts: Array[Vector3], ring: int) -> Dictionary:
	var out := {}
	for v in pts:
		var c := cell_of(Vector2(v.x, v.z))
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var k := c + Vector2i(dx, dz)
				if _known.has(k):
					out[k] = true
	return out


func _process(_delta: float) -> void:
	step()


## One frame of streaming: request, unload, then add finished cells within the budget.
func step() -> void:
	var pts := viewers()
	if pts.is_empty():
		return
	var want := wanted(pts, RING)
	var keep := wanted(pts, RING + 1)
	for k in want:
		if not loaded.has(k) and not _pending.has(k):
			var path := cells_dir + "%d_%d.tscn" % [k.x, k.y]
			ResourceLoader.load_threaded_request(path, "PackedScene")
			_pending[k] = path
	for k in loaded.keys():
		if not keep.has(k):
			(loaded[k] as Node).queue_free()
			loaded.erase(k)
	for k in _pending.keys():
		var st := ResourceLoader.load_threaded_get_status(_pending[k])
		if st == ResourceLoader.THREAD_LOAD_LOADED and not _ready_q.has(k):
			_ready_q.append(k)
		elif (
			st == ResourceLoader.THREAD_LOAD_FAILED
			or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		):
			push_warning("WorldStreamer: cell %s failed to load" % k)
			_pending.erase(k)
	var t0 := Time.get_ticks_usec()
	while not _ready_q.is_empty() and (Time.get_ticks_usec() - t0) < BUDGET_MS * 1000.0:
		var k: Vector2i = _ready_q.pop_front()
		var ps := ResourceLoader.load_threaded_get(_pending[k]) as PackedScene
		_pending.erase(k)
		if not keep.has(k) or ps == null:
			continue  # walked away while it loaded
		var n := ps.instantiate()
		add_child(n)
		loaded[k] = n
		break  # at most one cell per frame


## Blocks until every wanted cell is in (loading screen, tests).
func flush(max_frames := 600) -> void:
	for i in max_frames:
		step()
		if _pending.is_empty() and _ready_q.is_empty():
			return
		OS.delay_msec(1)
