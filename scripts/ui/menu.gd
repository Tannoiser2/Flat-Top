extends Control
## Menu principale: nuova partita (scenario, parte, livello dell'IA), partita online, ripresa di una
## partita salvata, regolamento.

var main
var box: VBoxContainer
var right: VBoxContainer
var scen_sel := "rabaul"
var modo := "A"        # A, J, hotseat, ia
var livello := 2
var stato_txt: Label
var code_edit: LineEdit
var nome_edit: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scen_sel = str(main.menu_state.get("scen", "rabaul"))
	modo = str(main.menu_state.get("modo", "A"))
	livello = int(main.menu_state.get("livello", 2))
	var root := UI.hbox(30)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.margin(root, 36))
	root.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# colonna sinistra: titolo e voci
	var left := UI.vbox(14)
	left.custom_minimum_size = Vector2(460, 0)
	root.add_child(left)
	left.add_child(UI.title("FLAT TOP", 96))
	left.add_child(UI.label("Battaglie di portaerei nelle Salomone, 1942", 28, UI.BRASS_L, UI.font_ui_b))
	left.add_child(UI.label("dal gioco di Avalon Hill (1977)", 22, UI.MUTED))
	left.add_child(UI.hsep())
	left.add_child(UI.big_button("Nuova partita", _show_nuova))
	left.add_child(UI.big_button("Partita online", _show_online))
	left.add_child(UI.big_button("Riprendi una partita", _show_riprendi))
	left.add_child(UI.big_button("Regolamento", func(): main.show_rules()))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	left.add_child(UI.wrap("Mappa, pedine e tabelle dal modulo VASSAL di Scott Giese e Wim Oudshoorn. Regolamento con le errata ufficiali del 1984.", 17, UI.MUTED, 420))
	# colonna destra: pannello contestuale
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(sc)
	right = UI.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(right)
	_show_nuova()


func _clear_right() -> void:
	for c in right.get_children():
		c.queue_free()


func _salva_stato() -> void:
	main.menu_state["scen"] = scen_sel
	main.menu_state["modo"] = modo
	main.menu_state["livello"] = livello


# ------------------------------------------------------------ nuova partita

func _show_nuova() -> void:
	_clear_right()
	right.add_child(UI.title("Scegli lo scenario", 36))
	_lista_scenari()
	right.add_child(UI.hsep())
	right.add_child(UI.label("Chi comandi", 26, UI.BRASS_L, UI.font_ui_b))
	var h := UI.hbox(10)
	right.add_child(h)
	for it in [["A", "Gli Alleati"], ["J", "Il Giappone"], ["hotseat", "Due giocatori sullo stesso dispositivo"], ["ia", "Guardo l'IA contro l'IA"]]:
		var b := UI.button(it[1], func(): modo = it[0]; _salva_stato(); _show_nuova(), 20, 150)
		b.toggle_mode = true
		b.button_pressed = modo == it[0]
		h.add_child(b)
	right.add_child(UI.label("Ammiraglio artificiale", 26, UI.BRASS_L, UI.font_ui_b))
	var h2 := UI.hbox(10)
	right.add_child(h2)
	for it in [[1, "Prudente"], [2, "Normale"], [3, "Esperto"]]:
		var b2 := UI.button(it[1], func(): livello = it[0]; _salva_stato(); _show_nuova(), 20, 150)
		b2.toggle_mode = true
		b2.button_pressed = livello == it[0]
		h2.add_child(b2)
	right.add_child(UI.hsep())
	var go := UI.big_button("Inizia la battaglia", _avvia, 420)
	right.add_child(go)


func _lista_scenari() -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(g)
	for s in FTData.scenari:
		var sel: bool = s["id"] == scen_sel
		var p := PanelContainer.new()
		var st := UI.panel_style(UI.PANEL_L if not sel else Color("#3c4a28"), UI.BRASS_L if sel else Color(UI.BRASS, 0.4), 3 if sel else 1, 4)
		p.add_theme_stylebox_override("panel", st)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(420, 0)
		var v := UI.vbox(4)
		p.add_child(v)
		v.add_child(UI.label(s["nome"], 25, UI.BRASS_L if sel else UI.TEXT, UI.font_ui_b))
		v.add_child(UI.label("%s  -  %d turni" % [s["data"], int(s["turni"])], 19, UI.MUTED))
		v.add_child(UI.wrap(s.get("descrizione", ""), 18, UI.TEXT, 380))
		p.gui_input.connect(func(ev):
			if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
				scen_sel = s["id"]
				_salva_stato()
				_show_nuova())
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		g.add_child(p)


func _avvia() -> void:
	_salva_stato()
	var cfg := {"scen": scen_sel, "seed": randi() % 1000000 + 1, "livello": livello}
	match modo:
		"A", "J":
			cfg["modo"] = "solo"
			cfg["lato"] = modo
		"hotseat":
			cfg["modo"] = "hotseat"
			cfg["lato"] = "A"
		_:
			cfg["modo"] = "ia"
			cfg["lato"] = "A"
	main.start_game(cfg)


# ------------------------------------------------------------ online

func _show_online() -> void:
	_clear_right()
	right.add_child(UI.title("Partita online", 36))
	right.add_child(UI.wrap("Si gioca in due, ognuno sul suo dispositivo: ogni ammiraglio vede solo quello che avvistano le sue unità. Chi crea la stanza sceglie scenario e parte e comunica il codice all'altro.", 20, UI.TEXT, 600))
	right.add_child(UI.label("Il tuo nome", 22, UI.BRASS_L, UI.font_ui_b))
	nome_edit = LineEdit.new()
	nome_edit.text = str(main.menu_state.get("nome", "Ammiraglio"))
	nome_edit.custom_minimum_size = Vector2(360, 50)
	nome_edit.max_length = 20
	right.add_child(nome_edit)
	right.add_child(UI.hsep())
	right.add_child(UI.label("Crea una stanza", 26, UI.BRASS_L, UI.font_ui_b))
	right.add_child(UI.label("Scenario: %s" % FTData.scenario(scen_sel).get("nome", ""), 21))
	var h := UI.hbox(10)
	right.add_child(h)
	h.add_child(UI.button("Cambia scenario", _show_nuova, 20, 200))
	for it in [["A", "Comando gli Alleati"], ["J", "Comando il Giappone"]]:
		h.add_child(UI.button(it[1], func(): _crea_stanza(it[0]), 20, 220))
	right.add_child(UI.hsep())
	right.add_child(UI.label("Entra in una stanza", 26, UI.BRASS_L, UI.font_ui_b))
	var h2 := UI.hbox(10)
	right.add_child(h2)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "CODICE"
	code_edit.max_length = 4
	code_edit.custom_minimum_size = Vector2(200, 50)
	h2.add_child(code_edit)
	h2.add_child(UI.button("Entra", _entra_stanza, 22, 160))
	stato_txt = UI.wrap("", 20, UI.BRASS_L, 600)
	right.add_child(stato_txt)


func _nome() -> String:
	var n := nome_edit.text.strip_edges() if nome_edit != null else "Ammiraglio"
	if n == "":
		n = "Ammiraglio"
	main.menu_state["nome"] = n
	return n


func _crea_stanza(lato: String) -> void:
	var net: Net = main.get_net()
	stato_txt.text = "Creo la stanza..."
	var seat := 0 if lato == "A" else 1
	var code := await net.create_room(_nome(), [seat, 1 - seat])
	if code == "":
		stato_txt.text = "Non riesco a creare la stanza: " + net.last_error
		return
	var seed := randi() % 1000000 + 1
	await net.db_patch(Net.ROOT + "/" + code, {"cfg": JSON.stringify({"scen": scen_sel, "seed": seed, "host_lato": lato})})
	net.remember_room(code, seat)
	stato_txt.text = "Stanza %s creata. Comunica il codice all'altro ammiraglio: la partita parte quando entra." % code
	# attesa dell'avversario
	while is_inside_tree():
		var room := await net.room(code)
		var seats: Dictionary = Net._as_dict(room.get("seats", {}))
		if seats.has(str(1 - seat)):
			await net.start_room(code, {"scen": scen_sel, "seed": seed})
			main.start_game({"scen": scen_sel, "seed": seed, "modo": "online", "lato": lato, "livello": livello,
				"online": {"code": code, "seat": seat, "role": "host"}})
			return
		await get_tree().create_timer(1.5).timeout


func _entra_stanza() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.length() != 4:
		stato_txt.text = "Il codice è di quattro lettere."
		return
	var net: Net = main.get_net()
	stato_txt.text = "Entro nella stanza %s..." % code
	var seat := await net.join_room(code, _nome())
	if seat < 0:
		stato_txt.text = "Non riesco a entrare: stanza inesistente, piena o già partita. " + net.last_error
		return
	var room: Dictionary = net.last_room
	var cfg = JSON.parse_string(str(room.get("cfg", "{}")))
	if not (cfg is Dictionary):
		stato_txt.text = "Stanza senza configurazione."
		return
	net.remember_room(code, seat)
	var lato := "A" if seat == 0 else "J"
	var backlog := await net.get_acts(code)
	main.start_game({"scen": cfg["scen"], "seed": int(cfg["seed"]), "modo": "online", "lato": lato, "livello": livello,
		"online": {"code": code, "seat": seat, "role": "guest", "backlog": backlog}})


# ------------------------------------------------------------ riprendi

func _show_riprendi() -> void:
	_clear_right()
	right.add_child(UI.title("Riprendi una partita", 36))
	right.add_child(UI.wrap("Le partite si salvano sul server con il pulsante Salva durante il gioco: ricevi un codice di sei lettere. Scrivilo qui per riprendere dallo stesso punto, anche da un altro dispositivo.", 20, UI.TEXT, 600))
	var h := UI.hbox(10)
	right.add_child(h)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "CODICE"
	code_edit.max_length = 6
	code_edit.custom_minimum_size = Vector2(240, 50)
	h.add_child(code_edit)
	h.add_child(UI.button("Carica", _carica, 22, 160))
	stato_txt = UI.wrap("", 20, UI.BRASS_L, 600)
	right.add_child(stato_txt)
	# rientro in una stanza online
	var net: Net = main.get_net()
	var ses := net.load_session()
	if str(ses.get("room", "")) != "":
		right.add_child(UI.hsep())
		right.add_child(UI.label("Partita online in corso: stanza %s" % ses["room"], 22, UI.BRASS_L))
		right.add_child(UI.button("Rientra nella stanza", func():
			code_edit.text = str(ses["room"])
			_show_online()
			code_edit.text = str(ses["room"])
			_entra_stanza(), 22, 260))


func _carica() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.length() != 6:
		stato_txt.text = "Il codice è di sei lettere."
		return
	stato_txt.text = "Carico la partita %s..." % code
	var net: Net = main.get_net()
	var d := await net.load_game(code)
	if d.is_empty():
		stato_txt.text = "Partita non trovata. " + net.last_error
		return
	var cfg: Dictionary = d.get("cfg", {})
	cfg["replay"] = d.get("decisioni", [])
	cfg["codice"] = code
	main.start_game(cfg)
