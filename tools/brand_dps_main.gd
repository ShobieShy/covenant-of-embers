extends SceneTree
## Prints the BrandDps table (step 143); step 151: `-- --skills <tree>:<points>` (tree "all" =
## every element tree) prints the element-skill gain table instead.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--skills")
	if i >= 0 and i + 1 < args.size():
		var spec := String(args[i + 1]).split(":")
		var pts := int(spec[1]) if spec.size() > 1 else 20
		for r: Dictionary in BrandDps.skills_table(pts):
			if spec[0] == "all" or spec[0] == r.element:
				print(
					(
						"%-8s %d pts single %6.2f base %6.2f gain %.2f ratio %.2f"
						% [r.element, pts, r.single, r.base, r.gain, r.ratio]
					)
				)
		quit()
		return
	for wand in [false, true]:
		for r: Dictionary in BrandDps.table(wand):
			print(
				(
					"%-16s %s single %6.2f aoe %6.2f base %6.2f ratio %.2f"
					% [r.brand, "wand " if wand else "staff", r.single, r.aoe, r.base, r.ratio]
				)
			)
	quit()
