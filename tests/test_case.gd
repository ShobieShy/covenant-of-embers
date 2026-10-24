class_name TestCase
extends RefCounted
## Base class for tests/unit/test_*.gd.

var runner_tree: SceneTree


func check(cond: bool, msg: String = "check failed") -> void:
	if not cond:
		get_meta("errors").append(msg)


func check_near(a: float, b: float, eps: float, msg: String = "") -> void:
	check(absf(a - b) <= eps, "%s expected %f got %f (±%f)" % [msg, b, a, eps])


func fail(msg: String) -> void:
	get_meta("errors").append(msg)
