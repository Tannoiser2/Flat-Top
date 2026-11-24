extends SceneTree
## Fotografie dell'interfaccia (serve un display, anche virtuale: xvfb-run).
## xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s tests/shot.gd -- <cartella> [larghezza] [altezza] [scenario]

var out := "/tmp/shots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var w := int(args[1]) if args.size() > 1 else 1920
	var h := int(args[2]) if args.size() > 2 else 1080
	var scen := args[3] if args.size() > 3 else "coral_battaglia"
	DirAccess.make_dir_recursive_absolute(out)
	_run(w, h, scen)


func _snap(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("foto ", name)


func _run(w: int, h: int, scen: String) -> void:
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	await _snap("01_menu")
	main.current._show_online()
	await _snap("02_online")
	main.show_rules()
	await create_timer(0.3).timeout
	await _snap("03_regole")
	main.start_game({"scen": scen, "seed": 77, "modo": "solo", "lato": "A", "livello": 2})
	await create_timer(1.5).timeout
	var g = main.current
	await _snap("04_ordini")
	# seleziona la prima TF e traccia una rotta
	var tids = g.eng.tf_del_lato("A")
	g._seleziona("tf", tids[0])
	var h0: Vector2i = g.eng.tf_hex(tids[0])
	g._on_hex(h0 + Vector2i(-2, -2))
	await _snap("05_tf_rotta")
	# portaerei
	var nidi = g.eng.nidi_del_lato("A")
	var cv = ""
	for n in nidi:
		if g.eng.st["navi"].has(n):
			cv = n
			break
	g._seleziona("nido", cv)
	await _snap("06_portaerei")
	g._nuovo_lancio(cv, "ricognizione")
	g._on_hex(h0 + Vector2i(0, -8))
	await _snap("07_lancio")
	g._conferma_lancio()
	g._indietro()
	g._conferma()
	# turni successivi: la persona conferma ordini vuoti
	for t in 10:
		await create_timer(0.4).timeout
		if not g.req_corrente.is_empty():
			if t == 1:
				await _snap("08_aria")
				var afs = g.eng.af_del_lato("A")
				if not afs.is_empty():
					g._seleziona("af", afs[0])
					await _snap("09_af")
					g._indietro()
			g._conferma()
	await create_timer(0.5).timeout
	await _snap("10_dopo")
	g._toggle_log()
	await _snap("11_diario")
	quit()
