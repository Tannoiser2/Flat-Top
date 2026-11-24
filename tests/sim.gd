extends SceneTree
## Partita automatica IA contro IA: godot --headless --path . -s tests/sim.gd -- <scenario> <seme>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scen := args[0] if args.size() > 0 else "rabaul"
	var seed := int(args[1]) if args.size() > 1 else 1
	var eng := FTEngine.new()
	root.add_child(eng)
	eng.setup(scen, seed, {"A": "ia", "J": "ia"})
	eng.fast = true
	var t0 := Time.get_ticks_msec()
	eng.log_added.connect(func(e): if e.get("tipo", "") != "minore": print("[T%d %02d00 %s] %s" % [e["t"], e["ora"], e["lato"], e["testo"]]))
	await eng.run()
	print("FINE in %d ms: %s" % [Time.get_ticks_msec() - t0, str(eng.st["risultato"])])
	print("PV A=%d J=%d  sbarchi %s" % [eng.st["lati"]["A"]["vp"], eng.st["lati"]["J"]["vp"], str(eng.st["sbarchi"])])
	quit()
