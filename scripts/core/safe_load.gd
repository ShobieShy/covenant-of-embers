class_name SafeLoad
extends RefCounted
## Threaded scene loads, except under the headless dummy renderer. In Godot 4.7.2 its mesh and
## material RID owners are not thread-safe (fixed upstream later), so a loader thread creating
## meshes while the main thread makes its own corrupts RIDs ('Parameter "m" is null',
## "Attempting to initialize the wrong RID"). Headless loads run synchronously instead; the
## API mirrors ResourceLoader.load_threaded_* so callers stay the same.

static var _done := {}  # path -> Resource (or null when the load failed), headless only


## Drop anything a quit interrupted. A leftover Resource is the ObjectDB leak of one.
static func clear() -> void:
	_done.clear()


static func threaded() -> bool:
	return DisplayServer.get_name() != "headless"


static func request(path: String, hint := "") -> Error:
	if threaded():
		return ResourceLoader.load_threaded_request(path, hint)
	if not _done.has(path):
		_done[path] = ResourceLoader.load(path, hint)
	return OK


static func status(path: String, progress: Array = []) -> ResourceLoader.ThreadLoadStatus:
	if threaded():
		return ResourceLoader.load_threaded_get_status(path, progress)
	if not _done.has(path):
		return ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	if progress.size() > 0:
		progress[0] = 1.0
	elif progress.is_empty():
		progress.append(1.0)
	return (
		ResourceLoader.THREAD_LOAD_LOADED
		if _done[path] != null
		else ResourceLoader.THREAD_LOAD_FAILED
	)


static func take(path: String) -> Resource:
	if threaded():
		return ResourceLoader.load_threaded_get(path)
	var r: Resource = _done.get(path)
	_done.erase(path)
	return r
