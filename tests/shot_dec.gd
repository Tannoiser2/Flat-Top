extends SceneTree
## Fotografie delle decisioni: schieramento, combattimenti aerei e di superficie.
## xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s tests/shot_dec.gd -- <cartella> [larghezza] [altezza] [scenario] [lato]

var out := "/tmp/shots_dec"
var visti := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var w := int(args[1]) if args.size() > 1 else 1920
	var h := int(args[2]) if args.size() > 2 else 1080
	var scen := args[3] if args.size() > 3 else "salomone_battaglia"
	var lato := args[4] if args.size() > 4 else "A"
	DirAccess.make_dir_recursive_absolute(out)
	_run(w, h, scen, lato)


func _snap(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("foto ", name)


func _run(w: int, h: int, scen: String, lato: String) -> void:
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	main.start_game({"scen": scen, "seed": 5, "modo": "solo", "lato": lato, "livello": 2})
	await create_timer(1.5).timeout
	var g = main.current
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000 and not g.finita:
		await create_timer(0.05).timeout
		if g.req_corrente.is_empty():
			continue
		var k: String = g.req_corrente["k"]
		if k == "schieramento" and not visti.has(k):
			visti[k] = true
			await _snap("10_schieramento")
			var tids: Array = g.req_corrente["tf"].keys()
			g.sel = {"t": "tf", "id": tids[0]}
			g._aggiorna_tutto()
			await _snap("11_schieramento_tf")
			var z: Array = g.req_corrente["tf"][tids[0]]["zona"]
			g._on_hex(z[z.size() / 2])
			await _snap("12_schieramento_scelto")
			g.ord = g._consiglio()
			g._conferma()
			continue
		if k == "ordini":
			g.ord = g.eng.ais[lato].decide(g.eng, lato, {"k": "ordini"})
			g._conferma()
			continue
		if k == "aria":
			g.ord = {}
			g._conferma()
			continue
		if not visti.has(k):
			visti[k] = true
			await _snap("2%d_%s" % [visti.size(), k])
			g.ord = g._consiglio()
			g._aggiorna_tutto()
			await _snap("2%d_%s_consiglio" % [visti.size(), k])
		else:
			g.ord = g._consiglio()
		g._conferma()
	print("decisioni viste: ", visti.keys(), "  turno ", g.eng.st["turno"])
	quit()
