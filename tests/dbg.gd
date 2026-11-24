extends SceneTree
## Partita IA contro IA con il dettaglio di ogni turno.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scen := args[0] if args.size() > 0 else "rabaul"
	var seed := int(args[1]) if args.size() > 1 else 1
	var eng := FTEngine.new()
	root.add_child(eng)
	eng.setup(scen, seed, {"A": "ia", "J": "ia"})
	eng.log_added.connect(func(e): print("  [T%d %02d00 %s] %s" % [e["t"], e["ora"], e["lato"], e["testo"]]))
	eng.state_changed.connect(func():
		var st = eng.st
		var s := "T%d %s fase=%s  AF=%d " % [st["turno"], eng.data_testo(), st["fase"], st["af"].size()]
		for fid in st["af"]:
			var af = st["af"][fid]
			s += "| %s%d %s %s %s q%s m=%s " % [af["lato"], af["num"], eng.af_desc(fid), FTData.nome_hex(eng.af_hex(fid)), "vol:" + str(af.get("in_volo_di","")), af["quota"], af["missione"].get("tipo","")]
		print(s)
		for side in ["A","J"]:
			var noti = st["noti"][side]
			var t2: String = "   noti " + str(side) + ": "
			for k in noti:
				t2 += "%s@%s c%d; " % [k, FTData.nome_hex(Vector2i(noti[k]["hex"][0], noti[k]["hex"][1])), noti[k]["cond"]]
			print(t2)
		for tid in st["tf"]:
			var tf = st["tf"][tid]
			print("   TF %s%d %s @%s esp=%s %s" % [tf["lato"], tf["num"], eng.tf_desc(tid), FTData.nome_hex(eng.tf_hex(tid)), tf["esposta"], tf["contegno"]])
	)
	await eng.run()
	print("FINE: ", eng.st["risultato"])
	quit()
