extends SceneTree
## Andamento dei punti turno per turno: godot --headless --path . -s tests/vp.gd -- <scenario> <seme>
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var eng := FTEngine.new()
	root.add_child(eng)
	eng.setup(args[0], int(args[1]), {"A": "ia", "J": "ia"})
	eng.fast = true
	eng.state_changed.connect(_s.bind(eng))
	eng.log_added.connect(func(e): if e.get("tipo", "") in ["affondata"] or str(e["testo"]).contains("Bombardamento") or str(e["testo"]).contains("cade"): print("   ", e["testo"]))
	await eng.run()
	print(eng.st["risultato"])
	quit()

func _s(eng) -> void:
	if eng.st["fase"] != "ordini": return
	var s := ""
	for bid in eng.st["basi"]:
		var b = eng.st["basi"][bid]
		if int(b["lf"][0]) <= 0 and not b["fuori"]: s += bid + " "
	print("T%d %s A%d J%d sbarchi %s perse A %s J %s ko: %s" % [eng.st["turno"], eng.ora_testo(), eng.st["lati"]["A"]["vp"], eng.st["lati"]["J"]["vp"], str(eng.st["sbarchi"]), str(eng.st["lati"]["A"]["perdite_oggi"].values().reduce(func(a,b): return a+b, 0)), str(eng.st["lati"]["J"]["perdite_oggi"].values().reduce(func(a,b): return a+b, 0)), s])
