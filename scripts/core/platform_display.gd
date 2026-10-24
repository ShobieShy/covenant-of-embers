class_name PlatformDisplay
extends RefCounted
## Per-OS input/display handling (BUILD_PLAN step 86).
##  * Renderer: "auto" (project default: Vulkan, falling back to D3D12 on Windows / OpenGL 3
##    when the GPU has no Vulkan - project.godot fallback_to_* = true), or a forced
##    "vulkan" / "d3d12" (Windows only) / "opengl3" (Compatibility). Godot picks the driver
##    before any script runs, so a choice is written as override.cfg next to the executable
##    (read at the next launch); "auto" removes it. Not written from the editor/tests.
##  * Window mode: windowed / borderless fullscreen / exclusive fullscreen (exclusive gives
##    the lowest latency on Windows; Alt+Tab works in all three).
##  * UI scale: 0 = auto from the monitor (Wayland/macOS report screen_get_scale(); Windows
##    reports 1 there, so DPI / 96 is used), else the chosen factor (0.75..2).
##  * Focus loss (Alt+Tab): Player releases the mouse; a click recaptures it (step 3).
## Gamepads: Godot maps XInput (Windows) and evdev (Linux) pads through the same SDL
## database, so Gamepad.DEFAULTS (SDL JoyButton/JoyAxis, device -1 = any pad) is OS-agnostic.

const RENDERERS: PackedStringArray = ["auto", "vulkan", "d3d12", "opengl3"]
const WINDOW_MODES: PackedStringArray = ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]
const OVERRIDE := "override.cfg"


static func renderers_for(os_name: String) -> PackedStringArray:
	var r := RENDERERS.duplicate()
	if os_name != "Windows":
		r.remove_at(r.find("d3d12"))
	return r


## override.cfg contents for `renderer` ("" for auto / unknown).
static func override_text(renderer: String, os_name := OS.get_name()) -> String:
	if not renderers_for(os_name).has(renderer) or renderer == "auto":
		return ""
	if renderer == "opengl3":
		return '[rendering]\n\nrenderer/rendering_method="gl_compatibility"\ngl_compatibility/driver="opengl3"\n'
	var key := "rendering_device/driver.windows" if os_name == "Windows" else "rendering_device/driver.linuxbsd"
	return '[rendering]\n\nrenderer/rendering_method="forward_plus"\n%s="%s"\n' % [key, renderer]


static func write_override(renderer: String, dir := "") -> Error:
	if dir == "":
		if OS.has_feature("editor") or DisplayServer.get_name() == "headless":
			return OK
		dir = OS.get_executable_path().get_base_dir()
	var path := dir.path_join(OVERRIDE)
	var text := override_text(renderer)
	if text == "":
		if FileAccess.file_exists(path):
			return DirAccess.remove_absolute(path)
		return OK
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	return OK


static func window_mode_of(i: int) -> DisplayServer.WindowMode:
	match i:
		1:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		2:
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	return DisplayServer.WINDOW_MODE_WINDOWED


static func auto_scale(os_name := OS.get_name(), scale := -1.0, dpi := -1) -> float:
	if scale < 0.0:
		scale = DisplayServer.screen_get_scale() if DisplayServer.get_name() != "headless" else 1.0
	if dpi < 0:
		dpi = DisplayServer.screen_get_dpi() if DisplayServer.get_name() != "headless" else 96
	var s := scale
	if os_name == "Windows" and is_equal_approx(scale, 1.0):
		s = dpi / 96.0
	return clampf(snappedf(s, 0.25), 0.75, 2.0)


## Applies window mode + UI scale to `root` (skips the window mode headless).
static func apply(root: Window, window_mode: int, ui_scale: float) -> void:
	if root == null:
		return
	root.content_scale_factor = auto_scale() if ui_scale <= 0.0 else clampf(ui_scale, 0.75, 2.0)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(window_mode_of(window_mode))
