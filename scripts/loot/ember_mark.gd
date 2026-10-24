class_name EmberMark
extends RefCounted
## A decoded Ember Mark (BUILD_PLAN step 20; ItemCodes.decode): the rebuilt item, the stack
## count (potions; 1 otherwise), the ItemCodes.Kind, the index-table version, or an error
## message (then item is null). Never push_error()s: a bad code is user input, not a bug.

var item: Resource
var count := 1
var kind := -1
var version := 0
var error := ""

func ok() -> bool:
	return error.is_empty() and item != null
