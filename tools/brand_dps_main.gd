extends SceneTree
## Prints the BrandDps table (step 143).


func _init() -> void:
	for wand in [false, true]:
		for r: Dictionary in BrandDps.table(wand):
			print(
				(
					"%-16s %s single %6.2f aoe %6.2f base %6.2f ratio %.2f"
					% [r.brand, "wand " if wand else "staff", r.single, r.aoe, r.base, r.ratio]
				)
			)
	quit()
