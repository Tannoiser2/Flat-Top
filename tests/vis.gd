extends SceneTree
## Quanti turni ogni lato conosce la posizione delle portaerei nemiche: -s tests/vis.gd -- <scenario> <seme>
var vis := {"A": 0, "J": 0}
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var eng := FTEngine.new()
	root.add_child(eng)
	eng.setup(args[0], int(args[1]), {"A": "ia", "J": "ia"})
	eng.fast = true
	eng.state_changed.connect(_s.bind(eng))
	await eng.run()
	print("portaerei nemiche note: ", vis, " su ", eng.st["turno"], " turni; vince ", eng.st["risultato"].get("vincitore", ""))
	quit()

func _s(eng) -> void:
	if eng.st["fase"] != "ordini": return
	for s in ["A", "J"]:
		for c in eng.ais[s]._contatti(eng):
			if c["tipo"] == "tf" and eng.ais[s]._ha_cv(c) and c["eta"] <= 1:
				vis[s] += 1
				break
