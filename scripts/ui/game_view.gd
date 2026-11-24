extends Control
## Vista di gioco: il tavolo (mappa), la barra del tempo e delle fasi, il pannello degli ordini a destra,
## il diario in basso. Raccoglie gli ordini della persona quando il motore li chiede.
##
## Ordini del turno (simultanei): rotte delle Task Force (si toccano gli esagoni), ancore e contegno,
## preparazione degli aerei (automatica o a mano), pattuglia aerea (CAP), nuove missioni aeree
## (attacco, ricognizione, trasferimento).
## Movimento aereo: le formazioni con una missione volano da sole; si possono cambiare missione,
## quota e rotta di ognuna.

const PILOT := preload("res://scripts/core/pilot.gd")
const MapView := preload("res://scripts/ui/map_view.gd")

signal _risposta(v)

var main
var config: Dictionary = {}
var eng: FTEngine
var map
var dec
var online: FTOnline
var lato_vista := "A"
var modo_partita := "solo"
var umani := {}

var top_data: Label
var top_fase: Label
var top_pv: Label
var top_stato: Label
var fasi_box: HBoxContainer
var luce: Control
var panel_box: VBoxContainer
var panel_scroll: ScrollContainer
var azione_box: VBoxContainer
var log_lbl: RichTextLabel
var toast_box: VBoxContainer
var overlay: Control
var log_grande := false
var log_panel: PanelContainer

var req_corrente: Dictionary = {}
var ord: Dictionary = {}
var sel := {"t": "", "id": ""}
var modo := ""
var lancio: Dictionary = {}
var riservati := {}     # nido -> {chiave: q} aerei già destinati a un lancio in questo turno
var ultimo_lato_hotseat := ""
var finita := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modo_partita = str(config.get("modo", "solo"))
	lato_vista = str(config.get("lato", "A"))
	match modo_partita:
		"solo":
			umani = {lato_vista: true}
		"hotseat":
			umani = {"A": true, "J": true}
		"online":
			umani = {lato_vista: true}
		_:
			umani = {}
	_costruisci()
	eng = FTEngine.new()
	add_child(eng)
	eng.setup(str(config.get("scen", "rabaul")), int(config.get("seed", 1)), {"A": "umano" if umani.get("A", false) else "ia", "J": "umano" if umani.get("J", false) else "ia"})
	for s in FTEngine.LATI:
		eng.ais[s].livello = int(config.get("livello", 2))
	eng.log_added.connect(_on_log)
	eng.state_changed.connect(_aggiorna_tutto)
	eng.event.connect(_on_evento)
	eng.game_over.connect(_on_fine)
	map.eng = eng
	map.lato = lato_vista
	if modo_partita == "online":
		online = FTOnline.new()
		add_child(online)
		var o: Dictionary = config.get("online", {})
		online.setup(main.get_net(), str(o.get("code", "")), int(o.get("seat", 0)), o.get("backlog", []))
		online.view = self
		online.heartbeat_loop()
		dec = online
	else:
		var d := FTDecider.new()
		d.view = self
		d.umani = umani
		dec = d
	eng.decider = dec
	if config.has("replay"):
		eng.replay = config["replay"].duplicate(true)
	for e in eng.st["log"]:
		_on_log(e)
	await get_tree().process_frame
	map.adatta()
	_centra_iniziale()
	_aggiorna_tutto()
	eng.run()


func _centra_iniziale() -> void:
	var hs := []
	for tid in eng.tf_del_lato(lato_vista):
		if not eng.st["tf"][tid].get("fuori", false):
			hs.append(eng.tf_hex(tid))
	if hs.is_empty():
		for nid in eng.nidi_del_lato(lato_vista):
			if eng.st["basi"].has(nid) and not eng.st["basi"][nid]["fuori"]:
				hs.append(eng.nido_hex(nid))
	if not hs.is_empty():
		map.centra_su(hs[0], 0.55)


# ================================================================ costruzione

func _costruisci() -> void:
	var root := UI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# --- barra superiore
	var top := PanelContainer.new()
	var tsb := UI.panel_style(Color(UI.PANEL, 0.98), Color(UI.BRASS, 0.6), 0, 0)
	tsb.border_width_bottom = 2
	tsb.set_content_margin_all(6)
	tsb.content_margin_left = 14
	tsb.content_margin_right = 14
	top.add_theme_stylebox_override("panel", tsb)
	root.add_child(top)
	var th := UI.hbox(14)
	top.add_child(th)
	th.add_child(UI.title("FLAT TOP", 30))
	luce = _Luce.new()
	luce.custom_minimum_size = Vector2(40, 40)
	th.add_child(luce)
	top_data = UI.label("", 24, UI.TEXT, UI.font_ui_b)
	top_data.custom_minimum_size = Vector2(250, 0)
	th.add_child(top_data)
	top_fase = UI.label("", 22, UI.BRASS_L, UI.font_ui_b)
	top_fase.custom_minimum_size = Vector2(250, 0)
	th.add_child(top_fase)
	top_pv = UI.label("", 22, UI.TEXT, UI.font_ui_b)
	top_pv.custom_minimum_size = Vector2(250, 0)
	th.add_child(top_pv)
	th.add_child(UI.spacer())
	top_stato = UI.label("", 19, UI.BRASS_L)
	top_stato.custom_minimum_size = Vector2(200, 0)
	top_stato.clip_text = true
	th.add_child(top_stato)
	th.add_child(UI.button("Adatta", func(): map.adatta(); map.queue_redraw(), 19, 90))
	th.add_child(UI.button("Diario", _toggle_log, 19, 90))
	th.add_child(UI.button("Regole", _mostra_regole, 19, 90))
	if modo_partita != "online":
		th.add_child(UI.button("Salva", _salva, 19, 90))
	th.add_child(UI.button("Menu", _esci, 19, 90))
	# --- fasi
	var fp := PanelContainer.new()
	var fsb := UI.panel_style(Color(UI.BG, 0.92), Color(0, 0, 0, 0), 0, 0)
	fsb.set_content_margin_all(4)
	fp.add_theme_stylebox_override("panel", fsb)
	root.add_child(fp)
	fasi_box = UI.hbox(4)
	fp.add_child(fasi_box)
	# --- centro: mappa + pannello
	var mid := UI.hbox(0)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var map_holder := Control.new()
	map_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_holder.clip_contents = true
	mid.add_child(map_holder)
	map = MapView.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_holder.add_child(map)
	map.hex_tapped.connect(_on_hex)
	# dispacci sopra la mappa
	toast_box = UI.vbox(6)
	toast_box.position = Vector2(20, 14)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_holder.add_child(toast_box)
	# pulsanti della mappa
	var mb := UI.vbox(6)
	mb.position = Vector2(14, 0)
	mb.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	map_holder.add_child(mb)
	var zp := UI.hbox(6)
	zp.add_child(UI.button("+", func(): map._zoom_a(map.size / 2.0, 1.25), 26, 52))
	zp.add_child(UI.button("-", func(): map._zoom_a(map.size / 2.0, 0.8), 26, 52))
	zp.add_child(UI.button("Nord in alto", func(): map.raddrizza(), 19, 120))
	zp.add_child(UI.button("Griglia", func(): map.mostra_griglia = not map.mostra_griglia; map.queue_redraw(), 19, 100))
	mb.add_child(zp)
	mb.position = Vector2(14, -70)
	# pannello destro
	var rp := PanelContainer.new()
	rp.custom_minimum_size = Vector2(560, 0)
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(rp)
	panel_scroll = ScrollContainer.new()
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rv := UI.vbox(8)
	rp.add_child(rv)
	rv.add_child(panel_scroll)
	azione_box = UI.vbox(6)
	rv.add_child(azione_box)
	panel_box = UI.vbox(10)
	panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_box.custom_minimum_size = Vector2(520, 0)
	panel_scroll.add_child(panel_box)
	# --- diario
	log_panel = PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(0, 150)
	var lsb := UI.paper_style()
	lsb.set_content_margin_all(8)
	log_panel.add_theme_stylebox_override("panel", lsb)
	root.add_child(log_panel)
	log_lbl = RichTextLabel.new()
	log_lbl.bbcode_enabled = true
	log_lbl.scroll_following = true
	log_lbl.add_theme_font_override("normal_font", UI.font_type)
	log_lbl.add_theme_font_size_override("normal_font_size", 18)
	log_lbl.add_theme_color_override("default_color", UI.INK)
	log_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_panel.add_child(log_lbl)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)


## Indicatore giorno/notte disegnato (niente simboli dei caratteri).
class _Luce extends Control:
	var notte := false
	func _draw() -> void:
		var c := size / 2.0
		if notte:
			draw_circle(c, 15, Color("#dfe6f5"))
			draw_circle(c + Vector2(7, -5), 13, Color("#16212c"))
		else:
			draw_circle(c, 11, Color("#f5c542"))
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 14, c + Vector2(cos(a), sin(a)) * 19, Color("#f5c542"), 3.0)


# ================================================================ aggiornamento

const FASI := [["meteo", "Meteo"], ["ordini", "Ordini"], ["movimento_tf", "Task Force"], ["iniziativa", "Iniziativa"],
	["aria", "Aerei"], ["combattimento", "Combattimento"], ["riparazioni", "Fine turno"]]


func _aggiorna_tutto() -> void:
	if eng == null:
		return
	var st := eng.st
	top_data.text = eng.data_testo() + "  (turno %d di %d)" % [int(st["turno"]) + 1, int(st["turni"])]
	luce.notte = eng.notte()
	luce.queue_redraw()
	var fase: String = st["fase"]
	var ft := ""
	for f in FASI:
		if fase.begins_with(f[0]):
			ft = f[1]
	if fase.begins_with("aria_"):
		ft = "Aerei: " + FTEngine.NOME_LATO[fase.substr(5)]
	top_fase.text = "Fase: " + ft
	top_pv.text = "Punti  Alleati %d  -  Giappone %d" % [int(st["lati"]["A"]["vp"]), int(st["lati"]["J"]["vp"])]
	for c in fasi_box.get_children():
		c.queue_free()
	for f in FASI:
		var on := fase.begins_with(f[0])
		var l := UI.label(" " + f[1] + " ", 18, UI.INK if on else UI.MUTED, UI.font_ui_b)
		var p := PanelContainer.new()
		var sb := UI.panel_style(UI.BRASS if on else Color(UI.PANEL_L, 0.6), Color(0, 0, 0, 0), 0, 3)
		sb.set_content_margin_all(3)
		p.add_theme_stylebox_override("panel", sb)
		p.add_child(l)
		fasi_box.add_child(p)
	_aggiorna_mappa()
	_pannello()


func _aggiorna_mappa() -> void:
	map.lato = lato_vista
	var rotte := {}
	map.passi_turno = {}
	if req_corrente.get("k", "") == "ordini":
		for tid in ord.get("percorsi", {}):
			rotte[tid] = ord["percorsi"][tid]
			if eng.st["tf"].has(tid):
				map.passi_turno[tid] = eng.tf_mf(tid)
	else:
		for tid in eng.tf_del_lato(lato_vista):
			var tf: Dictionary = eng.st["tf"][tid]
			if tf.has("dest") and not tf.get("fuori", false):
				rotte[tid] = FTData.percorso(eng.tf_hex(tid), FTEngine.vh(tf["dest"]), true)
				map.passi_turno[tid] = eng.tf_mf(tid)
	map.rotte = rotte
	map.rotte_af = {}
	if req_corrente.get("k", "") == "aria":
		for fid in ord:
			if fid.begins_with("F") and ord[fid].has("rotta"):
				map.rotte_af[fid] = ord[fid]["rotta"]
	map.sel_tf = sel["id"] if sel["t"] == "tf" else ""
	map.sel_af = sel["id"] if sel["t"] == "af" else ""
	map.queue_redraw()


func stato_online(t: String) -> void:
	if top_stato != null:
		top_stato.text = t


# ================================================================ diario e dispacci

func _on_log(e: Dictionary) -> void:
	var l: String = e.get("lato", "*")
	if l != "*" and l != lato_vista and modo_partita != "ia":
		return
	if e.get("tipo", "") == "minore" and l != lato_vista:
		return
	var col := "#1f1a12"
	match e.get("tipo", ""):
		"combattimento":
			col = "#7a3410"
		"affondata":
			col = "#9b1a10"
		"minore":
			col = "#5d5540"
	var ora := "%02d00" % int(e.get("ora", 0))
	log_lbl.append_text("[color=%s]%s  %s[/color]\n" % [col, ora, str(e["testo"]).replace("[", "(").replace("]", ")")])


func _toggle_log() -> void:
	log_grande = not log_grande
	log_panel.custom_minimum_size = Vector2(0, 520 if log_grande else 150)


func _on_evento(ev: Dictionary) -> void:
	if ev.has("h"):
		map.effetto(FTEngine.vh(ev["h"]), str(ev.get("k", "")))
	if ev.get("k", "") == "affondata":
		_toast("AFFONDATA: %s" % ev.get("nome", ""), true)
	elif ev.has("testo") and req_corrente.is_empty():
		_toast(str(ev["testo"]), false)


func _toast(t: String, forte: bool) -> void:
	var p := UI.dispatch(t, 560)
	if forte:
		var sb := UI.paper_style()
		sb.bg_color = Color("#f3d5c8")
		p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	while toast_box.get_child_count() > 3:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


# ================================================================ decisioni

## Il decisore chiede gli ordini di un lato alla persona.
func chiedi(s: String, req: Dictionary) -> Dictionary:
	if modo_partita == "hotseat" and s != ultimo_lato_hotseat:
		await _passa_dispositivo(s)
	ultimo_lato_hotseat = s
	lato_vista = s
	map.lato = s
	req_corrente = req.duplicate()
	req_corrente["lato"] = s
	sel = {"t": "", "id": ""}
	modo = ""
	lancio = {}
	riservati = {}
	if req["k"] == "ordini":
		ord = {"lanci": [], "rotte": {}, "cap": {}, "auto": {}, "contegno": {}, "ancora": {}, "mostra": {}, "pedina": {}, "dividi": [], "unisci": [], "prep": [],
			"destinazioni": {}, "percorsi": {}, "_missioni": {}}
		# le TF con una destinazione la riprendono da dove sono arrivate
		for tid in eng.tf_del_lato(s):
			var tf: Dictionary = eng.st["tf"][tid]
			if tf.has("dest") and not tf.get("fuori", false):
				var path := FTData.percorso(eng.tf_hex(tid), FTEngine.vh(tf["dest"]), true)
				if not path.is_empty():
					_imposta_percorso(tid, path)
		for nid in eng.nidi_del_lato(s):
			ord["cap"][nid] = int(eng.st["nidi"][nid].get("cap", 0))
			ord["auto"][nid] = bool(eng.st["nidi"][nid].get("auto", true))
	else:
		ord = {"_missioni": {}}
	stato_online("")
	_aggiorna_tutto()
	var v = await _risposta
	req_corrente = {}
	sel = {"t": "", "id": ""}
	modo = ""
	map.evidenzia = {}
	map.anello = {}
	map.bersaglio = Vector2i(-999, -999)
	_aggiorna_tutto()
	return v if v is Dictionary else {}


func pausa_ia(s: String, req: Dictionary) -> void:
	if modo_partita == "ia":
		await get_tree().create_timer(0.35).timeout
	else:
		await get_tree().process_frame


func _conferma() -> void:
	if req_corrente.is_empty():
		return
	var v := ord.duplicate(true)
	_risposta.emit(v)


func _passa_dispositivo(s: String) -> void:
	map.nascondi_tutto = true
	map.queue_redraw()
	var p := ColorRect.new()
	p.color = Color(0, 0, 0, 0.92)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(p)
	var v := UI.vbox(20)
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.position = Vector2(-300, -120)
	v.custom_minimum_size = Vector2(600, 0)
	p.add_child(v)
	v.add_child(UI.title("Tocca a: " + FTEngine.NOME_LATO[s], 46, UI.lato_col(s)))
	v.add_child(UI.wrap("Passa il dispositivo all'ammiraglio %s. L'altro non guardi lo schermo." % ("alleato" if s == "A" else "giapponese"), 24, UI.TEXT, 600))
	var b := UI.big_button("Sono pronto", func(): pass, 420)
	v.add_child(b)
	await b.pressed
	p.queue_free()
	map.nascondi_tutto = false
	map.queue_redraw()


# ================================================================ pannello

func _clear_panel() -> void:
	for c in azione_box.get_children():
		azione_box.remove_child(c)
		c.queue_free()
	for c in panel_box.get_children():
		panel_box.remove_child(c)
		c.queue_free()


func _pannello() -> void:
	_clear_panel()
	var k: String = req_corrente.get("k", "")
	if finita:
		_pannello_fine()
		return
	if k == "":
		_pannello_attesa()
		return
	if lancio.is_empty():
		var txt := "Ordini pronti: passa al movimento" if k == "ordini" else "Fine del movimento aereo"
		var bb := UI.big_button(txt, _conferma, 500)
		azione_box.add_child(bb)
		var aiuto := "Quando hai dato gli ordini che ti servono (anche nessuno) premi qui: il turno prosegue." if k == "ordini" else "Le formazioni con una missione volano da sole: premi qui per farle muovere e passare al combattimento."
		azione_box.add_child(UI.wrap(aiuto, 17, UI.MUTED, 500))
	if not lancio.is_empty():
		_pannello_lancio()
		return
	if k == "ordini":
		match sel["t"]:
			"tf":
				_pannello_tf(sel["id"])
			"nido":
				_pannello_nido(sel["id"])
			"contatto":
				_pannello_contatto(sel["id"])
			"af":
				_pannello_af(sel["id"])
			_:
				_pannello_ordini()
	elif k == "aria":
		match sel["t"]:
			"af":
				_pannello_af(sel["id"])
			"contatto":
				_pannello_contatto(sel["id"])
			_:
				_pannello_aria()


func _titolo(t: String, sotto := "") -> void:
	panel_box.add_child(UI.title(t, 32))
	if sotto != "":
		panel_box.add_child(UI.wrap(sotto, 19, UI.MUTED, 500))
	panel_box.add_child(UI.hsep())


func _sezione(t: String) -> void:
	panel_box.add_child(UI.label(t, 24, UI.BRASS_L, UI.font_ui_b))


func _riga(icona: Texture2D, testo: String, sotto: String, cb: Callable, col: Color = UI.TEXT) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(500, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	var h := UI.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	b.add_child(h)
	if icona != null:
		var tr := TextureRect.new()
		tr.texture = icona
		tr.custom_minimum_size = Vector2(44, 44)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tr)
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var l1 := UI.label(testo, 21, col, UI.font_ui_b)
	l1.clip_text = true
	l1.custom_minimum_size = Vector2(380, 0)
	l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l1)
	if sotto != "":
		var l2 := UI.label(sotto, 17, UI.MUTED)
		l2.clip_text = true
		l2.custom_minimum_size = Vector2(380, 0)
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l2)
	panel_box.add_child(b)


func _pannello_attesa() -> void:
	var fase: String = eng.st["fase"]
	var t := "Il nemico sta decidendo..."
	if modo_partita == "ia":
		t = "L'IA gioca entrambe le parti. Guarda la battaglia sulla mappa e nel diario."
	_titolo("In attesa", t)
	_contatti_lista()


func _pannello_fine() -> void:
	var r: Dictionary = eng.st["risultato"]
	var v: String = r.get("vincitore", "")
	_titolo("Fine della battaglia")
	if v == "":
		panel_box.add_child(UI.title("Pareggio", 40, UI.BRASS_L))
	else:
		panel_box.add_child(UI.title("Vince " + FTEngine.NOME_LATO[v], 40, UI.lato_col(v)))
	panel_box.add_child(UI.wrap(str(r.get("motivo", "")), 21, UI.TEXT, 500))
	panel_box.add_child(UI.label("Punti vittoria: Alleati %d, Giappone %d" % [int(r.get("vp", {}).get("A", 0)), int(r.get("vp", {}).get("J", 0))], 22))
	panel_box.add_child(UI.hsep())
	_sezione("Navi affondate")
	for nid in eng.st["navi"]:
		var n: Dictionary = eng.st["navi"][nid]
		if n["affondata"]:
			panel_box.add_child(UI.label("%s  %s (%s)" % [n["nome"], n["tipo"], FTEngine.NOME_LATO[n["lato"]]], 19, UI.lato_col(n["lato"])))
	panel_box.add_child(UI.big_button("Torna al menu", _esci, 420))


# ------------------------------------------------------------ ordini: elenco

func _pannello_ordini() -> void:
	var s: String = req_corrente["lato"]
	var sotto := "Tocca una Task Force e poi gli esagoni della sua rotta. Tocca una portaerei o una base per gli aerei. Gli ordini dei due lati valgono insieme."
	if eng.notte():
		sotto += " È notte: gli aerei vedono poco e l'atterraggio è rischioso."
	_titolo("Ordini - " + FTEngine.NOME_LATO[s], sotto)
	_sezione("Task Force")
	for tid in eng.tf_del_lato(s):
		var tf: Dictionary = eng.st["tf"][tid]
		if tf.get("fuori", false):
			_riga(UI.tf_tex(s, int(tf["num"])), "TF %d  (fuori mappa)" % tf["num"], "Entra al turno %d" % (int(tf["entra"]) + 1), func(): pass)
			continue
		var r: Array = ord["rotte"].get(tid, [])
		var info := "%s  -  %s" % [FTData.nome_hex(eng.tf_hex(tid)), eng.tf_desc(tid)]
		var st2 := "movimento %d" % eng.tf_mf(tid)
		if r.size() > 0:
			st2 += ", rotta di %d esagoni" % r.size()
		if tf["ancorata"]:
			st2 += ", all'ancora"
		if tf["esposta"]:
			st2 += ", AVVISTATA"
		_riga(UI.tf_tex(s, int(tf["num"])), "TF %d   %s" % [tf["num"], info], st2, func(): _seleziona("tf", tid))
	_sezione("Portaerei e basi")
	for nid in eng.nidi_del_lato(s):
		var tot := eng.nido_aerei(nid)
		if tot == 0 and not eng.st["basi"].has(nid):
			continue
		var nido: Dictionary = eng.st["nidi"][nid]
		var pronti := 0
		for kk in nido["pronti"]:
			pronti += int(nido["pronti"][kk])
		var icon: Texture2D = UI.tex("res://assets/pedine/%s.png" % ("alliedflag" if s == "A" else "axisflag"))
		if eng.st["navi"].has(nid):
			icon = UI.tf_tex(s, int(eng.st["tf"][eng.st["navi"][nid]["tf"]]["num"]))
		var prep := 0
		var jl := 0
		for kk in nido["prep"]:
			prep += int(nido["prep"][kk])
		for kk in nido["jl"]:
			jl += int(nido["jl"][kk])
		_riga(icon, "%s:  %d aerei" % [eng.nido_nome(nid), tot], "%d pronti, %d in preparazione, %d appena atterrati  -  CAP %d" % [pronti, prep, jl, int(ord["cap"].get(nid, 0))], func(): _seleziona("nido", nid))
	var afs := eng.af_del_lato(s)
	_sezione("Formazioni in volo")
	if afs.is_empty():
		panel_box.add_child(UI.wrap("Nessun aereo in volo. Le nuove missioni partono dalle portaerei e dalle basi.", 18, UI.MUTED, 500))
	for fid in afs:
		var af: Dictionary = eng.st["af"][fid]
		var m: Dictionary = ord["_missioni"].get(fid, af["missione"])
		_riga(UI.af_tex(s, int(af["num"])), "AF %d in %s:  %s" % [af["num"], FTData.nome_hex(eng.af_hex(fid)), eng.af_desc(fid)], _desc_missione(m), func(): _seleziona("af", fid))
	if ord["lanci"].size() > 0:
		_sezione("Missioni ordinate in questo turno")
		var i := 0
		for l in ord["lanci"]:
			var idx := i
			var testo := "%s: %s" % [eng.nido_nome(l["n"]), _desc_gruppi(l["gruppi"])]
			_riga(null, testo, _desc_missione(l["missione"]) + "  (tocca per annullare)", func(): _annulla_lancio(idx))
			i += 1
	_contatti_lista()



func _contatti_lista() -> void:
	var s := lato_vista
	var noti: Dictionary = eng.st["noti"][s]
	var mem: Dictionary = eng.st["memoria"][s]
	var righe := 0
	_sezione("Avvistamenti")
	for k in noti:
		var n: Dictionary = noti[k]
		if int(n.get("cond", 0)) < 1 and n["tipo"] == "af":
			continue
		var hh := FTEngine.vh(n["hex"])
		_riga(UI.tex("res://assets/pedine/%s_%s.png" % [n["tipo"], eng.nemico(s)]), "%s in %s" % ["Navi nemiche" if n["tipo"] == "tf" else "Aerei nemici", FTData.nome_hex(hh)], _desc_contatto(n), func(): _seleziona("contatto", k), UI.lato_col(eng.nemico(s)))
		righe += 1
	for k in mem:
		if noti.has(k):
			continue
		var m: Dictionary = mem[k]
		var eta: int = int(eng.st["turno"]) - int(m["turno"])
		if m["tipo"] != "tf" or eta > 6:
			continue
		var hh2 := FTEngine.vh(m["hex"])
		_riga(UI.tex("res://assets/pedine/tf_%s.png" % eng.nemico(s)), "Navi viste %d ore fa in %s" % [eta, FTData.nome_hex(hh2)], _desc_contatto(m), func(): map.centra_su(hh2); map.queue_redraw(), UI.MUTED)
		righe += 1
	if righe == 0:
		panel_box.add_child(UI.wrap("Nessuna unità nemica avvistata. Manda ricognitori.", 19, UI.MUTED, 500))


func _desc_contatto(n: Dictionary) -> String:
	var c: int = int(n.get("cond", 0))
	var i: Dictionary = n.get("info", {})
	if n["tipo"] == "tf":
		if c >= 3:
			var t := "%d navi: %d portaerei, %d maggiori, %d minori" % [int(i.get("navi", 0)), int(i.get("portaerei", 0)), int(i.get("maggiori", 0)), int(i.get("minori", 0))]
			if i.has("nomi"):
				t += " - " + ", ".join(i["nomi"])
			return t
		if c == 2:
			var p := []
			if i.get("ha_portaerei", false):
				p.append("portaerei")
			if i.get("ha_maggiori", false):
				p.append("navi maggiori")
			if i.get("ha_minori", false):
				p.append("navi minori")
			return "circa %d navi (%s)" % [int(i.get("navi_circa", 0)), ", ".join(p)]
		if c == 1:
			return "navi in vista, composizione sconosciuta"
		return "segnalino sul tavolo"
	if c >= 3:
		return "%d armati, %d scarichi, quota %s" % [int(i.get("armati", 0)), int(i.get("scarichi", 0)), "alta" if i.get("quota", "A") == "A" else "bassa"]
	if c == 2:
		return "circa %d aerei" % int(i.get("aerei_circa", 0))
	return "aerei in vista"


func _desc_gruppi(gr: Array) -> String:
	var p := []
	for g in gr:
		var a: String = g.get("arma", "")
		p.append("%d %s%s" % [int(g["q"]), g["tipo"], (" (" + _nome_arma(a) + ")") if a != "" else ""])
	return ", ".join(p)


static func _nome_arma(a: String) -> String:
	match a:
		"T":
			return "siluri"
		"AP":
			return "bombe AP"
		"GP":
			return "bombe GP"
		"x":
			return "sganciato"
	return ""


func _desc_missione(m: Dictionary) -> String:
	match str(m.get("tipo", "")):
		"attacco":
			if m.has("bersaglio_base"):
				return "Attacco a %s" % eng.st["basi"].get(m["bersaglio_base"], {}).get("nome", "")
			if m.has("hex"):
				return "Attacco verso %s" % FTData.nome_hex(FTEngine.vh(m["hex"]))
			return "Attacco"
		"ricognizione":
			return "Ricognizione verso %s" % FTData.nome_hex(FTEngine.vh(m.get("verso", [0, 0])))
		"cap":
			return "Pattuglia sopra %s" % eng.nido_nome(str(m.get("nido", "")))
		"rientro":
			return "Rientro alla base"
		"trasferimento":
			return "Trasferimento a %s" % eng.nido_nome(str(m.get("nido", "")))
	return "Ordini a mano"


func _seleziona(t: String, id: String) -> void:
	sel = {"t": t, "id": id}
	modo = ""
	map.evidenzia = {}
	map.anello = {}
	map.bersaglio = Vector2i(-999, -999)
	match t:
		"tf":
			modo = "rotta"
			map.centra_su(eng.tf_hex(id))
			_evidenzia_raggio_tf(id)
		"nido":
			var h := eng.nido_hex(id)
			if h.x > -100:
				map.centra_su(h)
				_anello_nido(id)
		"af":
			map.centra_su(eng.af_hex(id))
		"contatto":
			var n: Dictionary = eng.st["noti"][lato_vista].get(id, eng.st["memoria"][lato_vista].get(id, {}))
			if not n.is_empty():
				map.centra_su(FTEngine.vh(n["hex"]))
	_aggiorna_tutto()


func _indietro() -> void:
	sel = {"t": "", "id": ""}
	modo = ""
	lancio = {}
	map.evidenzia = {}
	map.anello = {}
	map.bersaglio = Vector2i(-999, -999)
	_aggiorna_tutto()


# ------------------------------------------------------------ ordini: Task Force

func _evidenzia_raggio_tf(tid: String) -> void:
	var ev := {}
	var start := eng.tf_hex(tid)
	var r: Array = []
	var rimasto := eng.tf_mf(tid)
	if rimasto > 0:
		for h in FTData.dentro(start, rimasto):
			if FTData.navigabile(h) and h != start:
				ev[h] = Color(UI.lato_col(lato_vista), 0.18)
	map.evidenzia = ev


func _pannello_tf(tid: String) -> void:
	if not eng.st["tf"].has(tid):
		_indietro()
		return
	var tf: Dictionary = eng.st["tf"][tid]
	var mf := eng.tf_mf(tid)
	var r: Array = ord["rotte"].get(tid, [])
	var full: Array = ord["percorsi"].get(tid, [])
	var turni_arrivo := 0
	if mf > 0 and full.size() > 0:
		turni_arrivo = int(ceil(float(full.size()) / mf))
	var spieg := "In %s. Le navi fanno %d esagoni all'ora (un turno). Tocca un punto della mappa, anche lontano: la TF ci va da sola nei turni seguenti. I numeri sulla rotta segnano dove sarà alla fine di ogni turno." % [FTData.nome_hex(eng.tf_hex(tid)), mf]
	if turni_arrivo > 0:
		spieg += " Arrivo fra %d turni." % turni_arrivo
	if mf == 0:
		spieg = "In %s. Questa TF non può muovere in questo turno (all'ancora, danneggiata o nella tempesta)." % FTData.nome_hex(eng.tf_hex(tid))
	_titolo("Task Force %d" % tf["num"], spieg)
	var h := UI.hbox(8)
	panel_box.add_child(h)
	h.add_child(UI.button("Indietro", _indietro, 19, 110))
	h.add_child(UI.button("Cancella rotta", func(): _cancella_rotta(tid), 19, 150))
	# ancora
	var anc: bool = bool(ord["ancora"].get(tid, tf["ancorata"]))
	if FTData.ter(eng.tf_hex(tid)) == "p" or tf["ancorata"]:
		h.add_child(UI.button("Salpa" if anc else "Getta l'ancora", func(): ord["ancora"][tid] = not anc; _aggiorna_tutto(), 19, 150))
	# contegno
	_sezione("Contegno")
	var hc := UI.hbox(8)
	panel_box.add_child(hc)
	var cont: String = ord["contegno"].get(tid, tf["contegno"])
	for it in [["evita", "Evita lo scontro"], ["attacca", "Attacca le navi"], ["bombarda", "Bombarda la base"]]:
		var b := UI.button(it[1], func(): ord["contegno"][tid] = it[0]; _aggiorna_tutto(), 18, 150)
		b.toggle_mode = true
		b.button_pressed = cont == it[0]
		hc.add_child(b)
	var vis: bool = bool(ord["mostra"].get(tid, tf.get("in_vista", false)))
	var bv := UI.button("Sul tavolo: può osservare (ma il nemico la vede)" if vis else "Nascosta: non osserva (il nemico non la vede)", func(): ord["mostra"][tid] = not vis; _aggiorna_tutto(), 18, 500)
	panel_box.add_child(bv)
	# unione con altre TF nello stesso esagono
	for t2 in eng.tf_del_lato(lato_vista):
		if t2 != tid and eng.tf_hex(t2) == eng.tf_hex(tid):
			panel_box.add_child(UI.button("Unisci la TF %d a questa" % eng.st["tf"][t2]["num"], func(): ord["unisci"].append([tid, t2]); _aggiorna_tutto(), 18, 500))
	_sezione("Navi")
	for nid in tf["navi"]:
		var n: Dictionary = eng.st["navi"][nid]
		var stat := "artiglieria %d, contraerea %d, movimento %d, danno %d/%d" % [int(n["art"]), int(n["aa"]), int(n["mv"]), int(n["hits"]), int(n["danno"])]
		if n["tipo"] in ["AP", "APD"]:
			stat += ", carico %d/8" % int(n["carico"])
		var col := UI.TEXT if int(n["hits"]) == 0 else UI.BAD
		var cb := Callable()
		if eng.st["nidi"].has(nid) and eng.nido_aerei(nid) + (1 if n["mc"] > 0 else 0) > 0:
			cb = func(): _seleziona("nido", nid)
		else:
			cb = func(): pass
		var nome_n: String = n["nome"]
		if n.get("generica", false):
			nome_n = {"DD": "Cacciatorpediniere", "AP": "Trasporto", "APD": "Trasporto veloce", "AO": "Petroliera", "PG": "Pattugliatore"}.get(n["tipo"], n["tipo"])
		_riga(null, "%s  %s" % [nome_n, n["tipo"]], stat, cb, col)
	if tf["navi"].size() > 1:
		panel_box.add_child(UI.button("Dividi la TF: stacca navi in una nuova TF", func(): _dialogo_dividi(tid), 18, 500))


func _dialogo_dividi(tid: String) -> void:
	var tf: Dictionary = eng.st["tf"][tid]
	_clear_panel()
	_titolo("Dividi la TF %d" % tf["num"], "Scegli le navi che formano la nuova Task Force.")
	var scelte := {}
	for nid in tf["navi"]:
		var n: Dictionary = eng.st["navi"][nid]
		var cb := CheckBox.new()
		cb.text = "%s  %s" % [n["nome"], n["tipo"]]
		cb.add_theme_font_size_override("font_size", 20)
		cb.toggled.connect(func(on): scelte[nid] = on)
		panel_box.add_child(cb)
	var h := UI.hbox(8)
	panel_box.add_child(h)
	h.add_child(UI.button("Annulla", func(): _aggiorna_tutto(), 19, 140))
	h.add_child(UI.button("Dividi", func():
		var navi := []
		for k in scelte:
			if scelte[k]:
				navi.append(k)
		if not navi.is_empty() and navi.size() < tf["navi"].size():
			ord["dividi"].append({"tf": tid, "navi": navi})
			_toast("La divisione avviene all'inizio del movimento.", false)
		_aggiorna_tutto(), 19, 140))


func _imposta_percorso(tid: String, path: Array) -> void:
	var full := []
	for h in path:
		var v: Vector2i = h if h is Vector2i else FTEngine.vh(h)
		full.append([v.x, v.y])
	ord["percorsi"][tid] = full
	ord["rotte"][tid] = full.slice(0, maxi(0, eng.tf_mf(tid)))
	if full.is_empty():
		ord["destinazioni"][tid] = []
	else:
		ord["destinazioni"][tid] = full[-1]


func _cancella_rotta(tid: String) -> void:
	ord["percorsi"].erase(tid)
	ord["rotte"].erase(tid)
	ord["destinazioni"][tid] = []
	_evidenzia_raggio_tf(tid)
	_aggiorna_tutto()


## Tocco sulla mappa con una TF scelta: la rotta arriva fin lì, anche se ci vogliono più turni.
## Nei turni successivi la TF la segue da sola; i numeri sulla rotta segnano la fine di ogni turno.
func _aggiungi_rotta(tid: String, dest: Vector2i) -> void:
	var full: Array = ord["percorsi"].get(tid, []).duplicate()
	for i in full.size():
		if FTEngine.vh(full[i]) == dest:
			_imposta_percorso(tid, full.slice(0, i + 1))
			_evidenzia_raggio_tf(tid)
			_aggiorna_tutto()
			return
	var start := eng.tf_hex(tid)
	if full.size() > 0:
		start = FTEngine.vh(full[-1])
	if dest == start:
		return
	var path := FTData.percorso(start, dest, true)
	if path.is_empty():
		_toast("Le navi non possono arrivare lì (terra o fuori dal mare).", false)
		return
	for h in path:
		full.append([h.x, h.y])
	_imposta_percorso(tid, full)
	_evidenzia_raggio_tf(tid)
	_aggiorna_tutto()


# ------------------------------------------------------------ ordini: portaerei e basi

func _anello_nido(nid: String) -> void:
	var nido: Dictionary = eng.st["nidi"][nid]
	var tipi := []
	for k in nido["pronti"]:
		var parts: PackedStringArray = k.split("|")
		if parts.size() > 1 and parts[1] != "":
			tipi.append(parts[0])
	if tipi.is_empty():
		for k in nido["prep"]:
			if not FTData.aerei[k]["ruoli"].contains("E"):
				tipi.append(k)
	if tipi.is_empty():
		map.anello = {}
		return
	var r := PILOT.raggio(tipi, true)
	map.anello = {"c": eng.nido_hex(nid), "r": r, "col": Color(UI.BRASS_L, 0.85)}


func _pannello_nido(nid: String) -> void:
	if not eng.st["nidi"].has(nid):
		_indietro()
		return
	var nido: Dictionary = eng.st["nidi"][nid]
	var lf := eng.nido_lf(nid)
	var mc := eng.nido_mc(nid)
	var info := "Fattore di lancio %s/%s, prontezza %d, capacità %s." % [
		"illimitato" if int(lf[0]) >= 999 else str(lf[0]), "-" if int(lf[1]) >= 999 else str(lf[1]), eng.nido_rf(nid), "illimitata" if mc >= 999 else str(mc)]
	if eng.st["basi"].has(nid):
		var b: Dictionary = eng.st["basi"][nid]
		info += " Contraerea %d." % int(b["aaf"])
		if int(b["hits"]) > 0:
			info += " Danni: %d colpi." % int(b["hits"])
	_titolo(eng.nido_nome(nid), info + " Il cerchio sulla mappa è il raggio d'attacco dei bombardieri.")
	var h := UI.hbox(8)
	panel_box.add_child(h)
	h.add_child(UI.button("Indietro", _indietro, 19, 110))
	var auto: bool = bool(ord["auto"].get(nid, true))
	var ba := UI.button("Preparazione automatica" if auto else "Preparazione a mano", func(): ord["auto"][nid] = not auto; _aggiorna_tutto(), 19, 260)
	h.add_child(ba)
	# CAP
	var hc := UI.hbox(8)
	panel_box.add_child(hc)
	hc.add_child(UI.label("Pattuglia aerea (CAP):", 21))
	var capv: int = int(ord["cap"].get(nid, 0))
	hc.add_child(UI.button("-", func(): ord["cap"][nid] = maxi(0, capv - 1); _aggiorna_tutto(), 22, 48))
	hc.add_child(UI.label("%d caccia" % capv, 22, UI.BRASS_L, UI.font_ui_b))
	hc.add_child(UI.button("+", func(): ord["cap"][nid] = capv + 1; _aggiorna_tutto(), 22, 48))
	# caselle
	_box_aerei(nid, "pronti", "Pronti al decollo")
	_box_aerei(nid, "prep", "In preparazione")
	_box_aerei(nid, "jl", "Appena atterrati")
	if not nido["disp"].is_empty():
		_box_aerei(nid, "disp", "Dispersi a terra")
	if not auto:
		panel_box.add_child(UI.wrap("Preparazione a mano: tocca un gruppo per spostarlo alla casella successiva (prontezza ancora disponibile: %d)." % (eng.nido_rf(nid) - _rf_ordini(nid)), 18, UI.MUTED, 500))
	panel_box.add_child(UI.hsep())
	_sezione("Nuova missione")
	var hm := UI.hbox(8)
	panel_box.add_child(hm)
	hm.add_child(UI.button("Attacco", func(): _nuovo_lancio(nid, "attacco"), 20, 160))
	hm.add_child(UI.button("Ricognizione", func(): _nuovo_lancio(nid, "ricognizione"), 20, 160))
	hm.add_child(UI.button("Trasferimento", func(): _nuovo_lancio(nid, "trasferimento"), 20, 160))


func _rf_ordini(nid: String) -> int:
	var t := 0
	for m in ord.get("prep", []):
		if m["n"] == nid:
			t += int(m["q"])
	return t


func _box_aerei(nid: String, box: String, titolo: String) -> void:
	var nido: Dictionary = eng.st["nidi"][nid]
	var d: Dictionary = nido[box]
	panel_box.add_child(UI.label(titolo, 21, UI.BRASS_L, UI.font_ui_b))
	if d.is_empty():
		panel_box.add_child(UI.label("  nessuno", 18, UI.MUTED))
		return
	var auto: bool = bool(ord["auto"].get(nid, true))
	for k in d:
		var parts: PackedStringArray = k.split("|")
		var tipo: String = parts[0]
		var arma: String = parts[1] if parts.size() > 1 else ""
		var q: int = int(d[k])
		var ris: int = int(riservati.get(nid, {}).get(k, 0)) if box == "pronti" else 0
		var testo := "%d %s" % [q - ris, tipo]
		if arma != "":
			testo += "  con " + _nome_arma(arma)
		if ris > 0:
			testo += "  (%d già in missione)" % ris
		var ap: Dictionary = FTData.aerei[tipo]
		var sotto := "movimento %d, autonomia %d ore, aria-aria %d" % [int(ap["mf"]), int(ap["rf"]), int(ap["aa"])]
		var cb := func(): pass
		if not auto:
			cb = func(): _sposta_manuale(nid, box, tipo, arma)
		_riga(UI.aereo_tex(tipo), testo, sotto, cb)


func _sposta_manuale(nid: String, box: String, tipo: String, arma: String) -> void:
	var lib := eng.nido_rf(nid) - _rf_ordini(nid)
	if lib <= 0:
		_toast("Prontezza esaurita per questo turno.", false)
		return
	var q: int = mini(lib, int(eng.st["nidi"][nid][box].get(tipo + ("|" + arma if box == "pronti" else ""), 0)))
	if q <= 0:
		return
	match box:
		"jl":
			ord["prep"].append({"n": nid, "da": "jl", "a": "prep", "tipo": tipo, "q": q})
		"prep":
			ord["prep"].append({"n": nid, "da": "prep", "a": "pronti", "tipo": tipo, "q": q, "arma": FTEngine.arma_preferita(tipo, bool(eng.st["nidi"][nid].get("contro_basi", false)))})
		"pronti":
			ord["prep"].append({"n": nid, "da": "pronti", "a": "prep", "tipo": tipo, "q": q, "arma": arma})
	_toast("%d %s: spostamento ordinato (avviene a inizio turno)." % [q, tipo], false)
	_aggiorna_tutto()


# ------------------------------------------------------------ nuovo lancio

func _nuovo_lancio(nid: String, tipo: String) -> void:
	var nido: Dictionary = eng.st["nidi"][nid]
	var q := {}
	for k in nido["pronti"]:
		var parts: PackedStringArray = k.split("|")
		var arma: String = parts[1] if parts.size() > 1 else ""
		var disp: int = int(nido["pronti"][k]) - int(riservati.get(nid, {}).get(k, 0))
		if disp <= 0:
			continue
		var r: String = FTData.aerei[parts[0]]["ruoli"]
		if tipo == "attacco":
			q[k] = disp if (arma != "" or r.contains("E")) else 0
		elif tipo == "ricognizione":
			q[k] = 0
		else:
			q[k] = disp
	if q.is_empty():
		_toast("Nessun aereo pronto al decollo su %s." % eng.nido_nome(nid), false)
		return
	# ricognizione: un solo aereo, preferibilmente un idrovolante
	if tipo == "ricognizione":
		var best := ""
		for k in q:
			var tp: String = k.split("|")[0]
			if best == "" or tp in ["Catalina", "Mavis", "Emily", "Jake", "Pete", "Dave"]:
				best = k
		q[best] = 1
	lancio = {"n": nid, "q": q, "missione": {"tipo": tipo}, "quota": "auto"}
	modo = "bersaglio" if tipo == "attacco" else ("ricognizione" if tipo == "ricognizione" else "trasferimento")
	_anello_lancio()
	_aggiorna_tutto()


func _tipi_lancio() -> Array:
	var tipi := []
	for k in lancio["q"]:
		if int(lancio["q"][k]) > 0:
			tipi.append(k)
	return tipi


func _anello_lancio() -> void:
	var tipi := []
	var armati := false
	for k in _tipi_lancio():
		var parts: PackedStringArray = k.split("|")
		tipi.append(parts[0])
		if parts.size() > 1 and parts[1] != "":
			armati = true
	if tipi.is_empty():
		map.anello = {}
	else:
		var r := PILOT.raggio(tipi, armati)
		if lancio["missione"]["tipo"] != "attacco":
			r = r * 2
		map.anello = {"c": eng.nido_hex(lancio["n"]), "r": r, "col": Color(UI.BRASS_L, 0.9)}
	map.queue_redraw()


func _pannello_lancio() -> void:
	var nid: String = lancio["n"]
	var m: Dictionary = lancio["missione"]
	var tipo: String = m["tipo"]
	var titoli := {"attacco": "Attacco", "ricognizione": "Ricognizione", "trasferimento": "Trasferimento"}
	var aiuto := ""
	match tipo:
		"attacco":
			aiuto = "Tocca sulla mappa (o nell'elenco) il bersaglio: navi avvistate, una base nemica o un esagono. Il cerchio è il raggio d'azione con ritorno."
		"ricognizione":
			aiuto = "Tocca sulla mappa il punto verso cui volare: il ricognitore cerca a ogni turno e poi rientra da solo."
		"trasferimento":
			aiuto = "Tocca la portaerei o la base amica dove trasferire gli aerei."
	_titolo("%s da %s" % [titoli[tipo], eng.nido_nome(nid)], aiuto)
	_sezione("Aerei")
	for k in lancio["q"]:
		var parts: PackedStringArray = k.split("|")
		var tp: String = parts[0]
		var arma: String = parts[1] if parts.size() > 1 else ""
		var disp: int = int(eng.st["nidi"][nid]["pronti"].get(k, 0)) - int(riservati.get(nid, {}).get(k, 0))
		var hh := UI.hbox(8)
		var tr := TextureRect.new()
		tr.texture = UI.aereo_tex(tp)
		tr.custom_minimum_size = Vector2(40, 40)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hh.add_child(tr)
		var l := UI.label("%s%s" % [tp, ("  " + _nome_arma(arma)) if arma != "" else ""], 21)
		l.custom_minimum_size = Vector2(230, 0)
		hh.add_child(l)
		var qv: int = int(lancio["q"][k])
		hh.add_child(UI.button("-", func(): lancio["q"][k] = maxi(0, qv - 1); _anello_lancio(); _aggiorna_tutto(), 22, 48))
		hh.add_child(UI.label("%d / %d" % [qv, disp], 22, UI.BRASS_L, UI.font_ui_b))
		hh.add_child(UI.button("+", func(): lancio["q"][k] = mini(disp, qv + 1); _anello_lancio(); _aggiorna_tutto(), 22, 48))
		panel_box.add_child(hh)
	# stima del decollo
	var tot := 0
	for k in lancio["q"]:
		tot += int(lancio["q"][k])
	var lf := eng.nido_lf(nid)
	var gia := 0
	for l2 in ord["lanci"]:
		if l2["n"] == nid:
			for g in l2["gruppi"]:
				gia += int(g["q"])
	var est := "Decollo: "
	if int(lf[0]) >= 999:
		est += "base fuori mappa, nessun limite."
	elif gia + tot <= int(lf[1]):
		est += "fattore minimo, movimento pieno nel primo turno."
	elif gia + tot <= int(lf[0]):
		est += "fattore normale, metà movimento nel primo turno."
	elif gia + tot <= 2 * int(lf[0]):
		est += "fattore massimo, nel primo turno restano sopra il ponte."
	else:
		est += "TROPPI aerei per un solo turno (massimo %d)." % (2 * int(lf[0]) - gia)
	panel_box.add_child(UI.wrap(est, 19, UI.MUTED, 500))
	# bersaglio
	_sezione("Bersaglio")
	var dest_txt := "da scegliere"
	if m.has("bersaglio_base"):
		dest_txt = "base di " + eng.st["basi"][m["bersaglio_base"]]["nome"]
	elif m.has("bersaglio"):
		dest_txt = "navi avvistate in " + FTData.nome_hex(FTEngine.vh(m["hex"]))
	elif m.has("hex"):
		dest_txt = "esagono " + FTData.nome_hex(FTEngine.vh(m["hex"]))
	elif m.has("verso"):
		dest_txt = "verso " + FTData.nome_hex(FTEngine.vh(m["verso"]))
	elif m.has("nido"):
		dest_txt = eng.nido_nome(m["nido"])
	panel_box.add_child(UI.label(dest_txt, 22, UI.BRASS_L, UI.font_ui_b))
	if tipo == "attacco":
		for k in eng.st["noti"][lato_vista]:
			var n: Dictionary = eng.st["noti"][lato_vista][k]
			if n["tipo"] != "tf":
				continue
			_riga(UI.tex("res://assets/pedine/tf_%s.png" % eng.nemico(lato_vista)), "Navi in %s" % FTData.nome_hex(FTEngine.vh(n["hex"])), _desc_contatto(n), func(): _scegli_bersaglio_contatto(k), UI.lato_col(eng.nemico(lato_vista)))
		var pr := UI.hbox(8)
		panel_box.add_child(pr)
		pr.add_child(UI.label("Priorità:", 20))
		var pv: String = m.get("priorita", "portaerei")
		for it in [["portaerei", "Portaerei"], ["trasporti", "Trasporti"]]:
			var b := UI.button(it[1], func(): m["priorita"] = it[0]; _aggiorna_tutto(), 18, 130)
			b.toggle_mode = true
			b.button_pressed = pv == it[0]
			pr.add_child(b)
	elif tipo == "trasferimento":
		for n2 in eng.nidi_del_lato(lato_vista):
			if n2 == nid:
				continue
			_riga(null, eng.nido_nome(n2), "", func(): m["nido"] = n2; _aggiorna_tutto())
	panel_box.add_child(UI.hsep())
	var h := UI.hbox(8)
	panel_box.add_child(h)
	h.add_child(UI.button("Annulla", func(): lancio = {}; modo = ""; map.anello = {}; map.bersaglio = Vector2i(-999, -999); _seleziona("nido", nid), 20, 150))
	var ok := UI.button("Ordina la missione", _conferma_lancio, 22, 260)
	ok.disabled = tot == 0 or not (m.has("hex") or m.has("verso") or m.has("nido") or m.has("bersaglio_base"))
	h.add_child(ok)


func _scegli_bersaglio_contatto(k: String) -> void:
	var n: Dictionary = eng.st["noti"][lato_vista][k]
	lancio["missione"]["bersaglio"] = k
	lancio["missione"]["hex"] = n["hex"].duplicate()
	lancio["missione"].erase("bersaglio_base")
	map.bersaglio = FTEngine.vh(n["hex"])
	_aggiorna_tutto()


func _conferma_lancio() -> void:
	var nid: String = lancio["n"]
	var m: Dictionary = lancio["missione"].duplicate(true)
	var alti := []
	var bassi := []
	var scorta := []
	for k in lancio["q"]:
		var q: int = int(lancio["q"][k])
		if q <= 0:
			continue
		var parts: PackedStringArray = k.split("|")
		var g := {"tipo": parts[0], "q": q, "arma": parts[1] if parts.size() > 1 else ""}
		if g["arma"] == "T":
			bassi.append(g)
		elif g["arma"] == "" and FTData.aerei[g["tipo"]]["ruoli"].contains("E"):
			scorta.append(g)
		else:
			alti.append(g)
		if not riservati.has(nid):
			riservati[nid] = {}
		riservati[nid][k] = int(riservati[nid].get(k, 0)) + q
	if m["tipo"] == "attacco" and not bassi.is_empty() and not alti.is_empty():
		# due formazioni: picchiatori in alto, aerosiluranti in basso, scorta divisa
		var sa := []
		var sb := []
		for g in scorta:
			var meta: int = int(g["q"]) / 2
			if g["q"] - meta > 0:
				sa.append({"tipo": g["tipo"], "q": g["q"] - meta, "arma": ""})
			if meta > 0:
				sb.append({"tipo": g["tipo"], "q": meta, "arma": ""})
		ord["lanci"].append({"n": nid, "gruppi": alti + sa, "quota": "A", "missione": m.duplicate(true)})
		ord["lanci"].append({"n": nid, "gruppi": bassi + sb, "quota": "B", "missione": m.duplicate(true)})
	else:
		var quota := "B" if not bassi.is_empty() else "A"
		ord["lanci"].append({"n": nid, "gruppi": alti + bassi + scorta, "quota": quota, "missione": m})
	lancio = {}
	modo = ""
	map.anello = {}
	map.bersaglio = Vector2i(-999, -999)
	_toast("Missione ordinata: decolla in questo turno.", false)
	_seleziona("nido", nid)


func _annulla_lancio(idx: int) -> void:
	var l: Dictionary = ord["lanci"][idx]
	for g in l["gruppi"]:
		var k: String = g["tipo"] + "|" + g.get("arma", "")
		if riservati.has(l["n"]):
			riservati[l["n"]][k] = maxi(0, int(riservati[l["n"]].get(k, 0)) - int(g["q"]))
	ord["lanci"].remove_at(idx)
	_aggiorna_tutto()


func _pannello_contatto(k: String) -> void:
	var n: Dictionary = eng.st["noti"][lato_vista].get(k, eng.st["memoria"][lato_vista].get(k, {}))
	if n.is_empty():
		_indietro()
		return
	_titolo("Avvistamento", "%s in %s" % ["Navi nemiche" if n["tipo"] == "tf" else "Aerei nemici", FTData.nome_hex(FTEngine.vh(n["hex"]))])
	panel_box.add_child(UI.wrap(_desc_contatto(n), 21, UI.TEXT, 500))
	panel_box.add_child(UI.wrap("Condizione d'avvistamento %d (1 = solo la presenza, 3 = composizione esatta)." % int(n.get("cond", 0)), 18, UI.MUTED, 500))
	panel_box.add_child(UI.button("Indietro", _indietro, 19, 140))


# ------------------------------------------------------------ movimento aereo

func _pannello_aria() -> void:
	var s: String = req_corrente["lato"]
	_titolo("Movimento aereo - " + FTEngine.NOME_LATO[s], "Le formazioni con una missione volano da sole quando premi Fine movimento. Tocca una formazione per cambiarle missione, quota o rotta.")
	var afs := eng.af_del_lato(s)
	if afs.is_empty():
		panel_box.add_child(UI.wrap("Nessuna formazione in volo.", 20, UI.MUTED, 500))
	for fid in afs:
		var af: Dictionary = eng.st["af"][fid]
		var entro := eng.af_entro(fid)
		var m: Dictionary = ord["_missioni"].get(fid, af["missione"])
		var sotto := "%s - quota %s - atterrare entro le %02d00" % [_desc_missione(m), "alta" if af["quota"] == "A" else "bassa", (int(eng.st["ora"]) + entro - int(eng.st["turno"]) - 1) % 24 + 1]
		var col := UI.TEXT
		if entro <= int(eng.st["turno"]) + 1:
			col = UI.BAD
		_riga(UI.af_tex(s, int(af["num"])), "AF %d in %s:  %s" % [af["num"], FTData.nome_hex(eng.af_hex(fid)), eng.af_desc(fid)], sotto, func(): _seleziona("af", fid), col)
	_contatti_lista()



func _pannello_af(fid: String) -> void:
	if not eng.st["af"].has(fid):
		_indietro()
		return
	var af: Dictionary = eng.st["af"][fid]
	var m: Dictionary = ord["_missioni"].get(fid, af["missione"])
	var entro := eng.af_entro(fid)
	var ore_rimaste := entro - int(eng.st["turno"])
	_titolo("Formazione aerea %d" % af["num"], "%s. In %s, quota %s, movimento %d in questo turno. Autonomia: ancora %d turni compreso questo." % [eng.af_desc(fid), FTData.nome_hex(eng.af_hex(fid)), "alta" if af["quota"] == "A" else "bassa", eng.af_mf(fid), ore_rimaste + 1])
	panel_box.add_child(UI.label("Missione: " + _desc_missione(m), 22, UI.BRASS_L, UI.font_ui_b))
	var h := UI.hbox(8)
	panel_box.add_child(h)
	h.add_child(UI.button("Indietro", _indietro, 19, 110))
	h.add_child(UI.button("Rientra", func(): ord["_missioni"][fid] = {"tipo": "rientro"}; ord.erase(fid); _aggiorna_tutto(), 19, 120))
	h.add_child(UI.button("Attacca...", func(): modo = "bersaglio_af"; _toast("Tocca il bersaglio sulla mappa.", false), 19, 130))
	var h2 := UI.hbox(8)
	panel_box.add_child(h2)
	h2.add_child(UI.button("Ricognizione...", func(): modo = "ricognizione_af"; _toast("Tocca il punto verso cui volare.", false), 19, 170))
	if req_corrente.get("k", "") != "aria":
		panel_box.add_child(UI.wrap("Rotta a mano e atterraggio si scelgono nella fase del movimento aereo.", 17, UI.MUTED, 500))
		_sezione("Composizione")
		for g in af["gruppi"]:
			_riga(UI.aereo_tex(g["tipo"]), "%d %s%s" % [int(g["q"]), g["tipo"], ("  (" + _nome_arma(g["arma"]) + ")") if g["arma"] != "" else ""], "", func(): pass)
		return
	h2.add_child(UI.button("Rotta a mano", func():
		modo = "rotta_af"
		ord[fid] = {"rotta": [], "quota": af["quota"], "cerca": true}
		ord["_missioni"][fid] = {"tipo": "manuale"}
		_toast("Tocca gli esagoni della rotta.", false)
		_aggiorna_tutto(), 19, 150))
	var nidi_qui := eng.nidi_in(eng.af_hex(fid), lato_vista)
	for n2 in nidi_qui:
		h2.add_child(UI.button("Atterra su " + eng.nido_nome(n2), func():
			ord[fid] = {"rotta": [], "quota": "B", "atterra": n2}
			ord["_missioni"][fid] = {"tipo": "manuale"}
			_aggiorna_tutto(), 19, 220))
	if ord.has(fid):
		var o: Dictionary = ord[fid]
		var h3 := UI.hbox(8)
		panel_box.add_child(h3)
		h3.add_child(UI.button("Quota alta" if o.get("quota", "A") == "B" else "Quota bassa", func(): o["quota"] = "A" if o.get("quota", "A") == "B" else "B"; _aggiorna_tutto(), 19, 150))
		h3.add_child(UI.button("Cerca: sì" if o.get("cerca", false) else "Cerca: no", func(): o["cerca"] = not o.get("cerca", false); _aggiorna_tutto(), 19, 130))
		h3.add_child(UI.button("Cancella rotta", func(): o["rotta"] = []; _aggiorna_tutto(), 19, 150))
		panel_box.add_child(UI.wrap("Rotta a mano: %d di %d esagoni." % [o.get("rotta", []).size(), eng.af_mf(fid)], 19, UI.MUTED, 500))
	_sezione("Composizione")
	for g in af["gruppi"]:
		var t := "%d %s" % [int(g["q"]), g["tipo"]]
		if g["arma"] != "":
			t += "  (" + _nome_arma(g["arma"]) + ")"
		_riga(UI.aereo_tex(g["tipo"]), t, "deve atterrare entro il turno %d" % (int(g["entro"]) + 1), func(): pass)


# ================================================================ tocchi sulla mappa

func _on_hex(h: Vector2i) -> void:
	if req_corrente.is_empty():
		map.sel_hex = h
		map.queue_redraw()
		return
	var s := lato_vista
	# scelta del bersaglio / destinazione di un lancio
	if not lancio.is_empty():
		var m: Dictionary = lancio["missione"]
		match m["tipo"]:
			"attacco":
				var k := _contatto_in(h)
				if k != "":
					_scegli_bersaglio_contatto(k)
					return
				var bid := _base_nemica_in(h)
				m.erase("bersaglio")
				if bid != "":
					m["bersaglio_base"] = bid
				else:
					m.erase("bersaglio_base")
				m["hex"] = [h.x, h.y]
				map.bersaglio = h
			"ricognizione":
				m["verso"] = [h.x, h.y]
				map.bersaglio = h
			"trasferimento":
				var ns := eng.nidi_in(h, s)
				if not ns.is_empty():
					m["nido"] = ns[0]
					map.bersaglio = h
		_aggiorna_tutto()
		return
	if req_corrente["k"] == "ordini" and sel["t"] == "tf" and modo == "rotta":
		# tocco sulla TF stessa: niente; altrove: rotta
		if h != eng.tf_hex(sel["id"]):
			_aggiungi_rotta(sel["id"], h)
			return
	if sel["t"] == "af" and modo in ["rotta_af", "bersaglio_af", "ricognizione_af"]:
		var fid: String = sel["id"]
		match modo:
			"rotta_af":
				var o: Dictionary = ord[fid]
				var start := eng.af_hex(fid)
				if o["rotta"].size() > 0:
					start = FTEngine.vh(o["rotta"][-1])
				var path := FTData.percorso(start, h, false)
				for p in path:
					if o["rotta"].size() >= eng.af_mf(fid):
						break
					o["rotta"].append([p.x, p.y])
				_aggiorna_tutto()
				return
			"bersaglio_af":
				var mm := {"tipo": "attacco", "hex": [h.x, h.y]}
				var k2 := _contatto_in(h)
				if k2 != "":
					mm["bersaglio"] = k2
				var b2 := _base_nemica_in(h)
				if b2 != "":
					mm["bersaglio_base"] = b2
				ord["_missioni"][fid] = mm
				ord.erase(fid)
				modo = ""
				map.bersaglio = h
				_aggiorna_tutto()
				return
			"ricognizione_af":
				ord["_missioni"][fid] = {"tipo": "ricognizione", "verso": [h.x, h.y], "andata": 99}
				ord.erase(fid)
				modo = ""
				map.bersaglio = h
				_aggiorna_tutto()
				return
	# selezione
	if req_corrente["k"] == "ordini":
		var tfs := []
		for tid in eng.tf_del_lato(s):
			if not eng.st["tf"][tid].get("fuori", false) and eng.tf_hex(tid) == h:
				tfs.append(tid)
		if not tfs.is_empty():
			var i := tfs.find(sel["id"])
			_seleziona("tf", tfs[(i + 1) % tfs.size()])
			return
		var ns2 := eng.nidi_in(h, s)
		if not ns2.is_empty():
			_seleziona("nido", ns2[0])
			return
	else:
		var afs := []
		for fid2 in eng.af_del_lato(s):
			if eng.af_hex(fid2) == h:
				afs.append(fid2)
		if not afs.is_empty():
			var j := afs.find(sel["id"])
			_seleziona("af", afs[(j + 1) % afs.size()])
			return
	var k3 := _contatto_in(h)
	if k3 != "":
		_seleziona("contatto", k3)
		return
	map.sel_hex = h
	map.queue_redraw()


func _contatto_in(h: Vector2i) -> String:
	for k in eng.st["noti"][lato_vista]:
		var n: Dictionary = eng.st["noti"][lato_vista][k]
		if FTEngine.vh(n["hex"]) == h and n["tipo"] == "tf":
			return k
	for k in eng.st["noti"][lato_vista]:
		var n2: Dictionary = eng.st["noti"][lato_vista][k]
		if FTEngine.vh(n2["hex"]) == h:
			return k
	return ""


func _base_nemica_in(h: Vector2i) -> String:
	for bid in eng.st["basi"]:
		var b: Dictionary = eng.st["basi"][bid]
		if b["lato"] != lato_vista and FTEngine.vh(b["hex"]) == h and not b["fuori"]:
			return bid
	return ""


# ================================================================ varie

func _on_fine(r: Dictionary) -> void:
	finita = true
	if online != null:
		main.get_net().remember_room("")
	_aggiorna_tutto()


func _salva() -> void:
	var cfg := {"scen": eng.st["scen"], "seed": eng.st["seed"], "modo": modo_partita, "lato": str(config.get("lato", "A")), "livello": int(config.get("livello", 2))}
	_toast("Salvo la partita...", false)
	var code: String = await main.get_net().save_game({"cfg": cfg, "decisioni": eng.decisions}, str(config.get("codice", "")))
	if code == "":
		_toast("Salvataggio non riuscito: " + main.get_net().last_error, true)
	else:
		config["codice"] = code
		_toast("Partita salvata. Codice: %s (scrivilo per riprenderla dal menu)." % code, true)


func _esci() -> void:
	eng.stop_requested = true
	if not req_corrente.is_empty():
		_risposta.emit({})
	if online != null:
		online.alive = false
	main.show_menu()


func _mostra_regole() -> void:
	var p := ColorRect.new()
	p.color = Color(0, 0, 0, 0.85)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(p)
	var rv := preload("res://scripts/ui/rules_view.gd").new()
	rv.incorporato = true
	rv.chiudi = func(): p.queue_free()
	p.add_child(rv)
