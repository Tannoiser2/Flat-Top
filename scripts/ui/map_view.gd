extends Control
## Il tavolo: la mappa delle Salomone con le pedine. Si sposta trascinando (un dito o il mouse), si
## ingrandisce con la rotella o pizzicando con due dita, si ruota con due dita. Un tocco su un esagono
## avvisa la vista di gioco (hex_tapped).
## Mostra solo quello che il lato «lato» sa: le proprie unità e gli avvistamenti del nemico.

signal hex_tapped(h: Vector2i)

var eng: FTEngine
var lato := "A"
var tex: Texture2D
var zoom := 0.45
var rot := 0.0
var offset := Vector2.ZERO        # posizione sullo schermo del punto (0,0) della mappa
var sel_hex := Vector2i(-999, -999)
var sel_tf := ""
var sel_af := ""
var rotte := {}                    # id TF -> [esagoni] (rotte pianificate)
var rotte_af := {}                 # id AF -> [esagoni]
var evidenzia := {}                # esagono -> colore
var anello := {}                   # {"c": Vector2i, "r": int, "col": Color}
var bersaglio := Vector2i(-999, -999)
var effetti := []                  # [{h, t, k}]
var mostra_griglia := true
var nascondi_tutto := false        # schermo coperto (passaggio del dispositivo)

var _touches := {}
var _drag_from := Vector2.ZERO
var _dragging := false
var _press_pos := Vector2.ZERO
var _pinch_d := 0.0
var _pinch_a := 0.0
var _mouse_down := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	tex = UI.tex("res://assets/map/mappa.webp")
	set_process(true)


func centra_su(h: Vector2i, z := -1.0) -> void:
	if z > 0:
		zoom = z
	var p := FTData.centro(h)
	offset = size / 2.0 - _xf_basis().basis_xform(p)


func adatta() -> void:
	if tex == null or size.x <= 0:
		return
	rot = 0.0
	zoom = minf(size.x / tex.get_width(), size.y / tex.get_height())
	offset = (size - Vector2(tex.get_width(), tex.get_height()) * zoom) / 2.0


func _xf_basis() -> Transform2D:
	return Transform2D(rot, Vector2(zoom, zoom), 0.0, Vector2.ZERO)


func _xf() -> Transform2D:
	var t := _xf_basis()
	t.origin = offset
	return t


func schermo_a_mappa(p: Vector2) -> Vector2:
	return _xf().affine_inverse() * p


func mappa_a_schermo(p: Vector2) -> Vector2:
	return _xf() * p


func _process(delta: float) -> void:
	if effetti.is_empty():
		return
	var tenuti := []
	for e in effetti:
		e["t"] = float(e["t"]) + delta
		if e["t"] < 2.2:
			tenuti.append(e)
	effetti = tenuti
	queue_redraw()


func effetto(h: Vector2i, k: String) -> void:
	effetti.append({"h": h, "t": 0.0, "k": k})


# ------------------------------------------------------------ input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
			if _touches.size() == 1:
				_press_pos = ev.position
				_dragging = false
			elif _touches.size() == 2:
				_inizio_pinch()
		else:
			if _touches.size() == 1 and not _dragging and ev.position.distance_to(_press_pos) < 14.0:
				_tap(ev.position)
			_touches.erase(ev.index)
			if _touches.size() == 2:
				_inizio_pinch()
		accept_event()
	elif ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if _touches.size() == 1:
			if ev.position.distance_to(_press_pos) > 10.0:
				_dragging = true
			offset += ev.relative
			queue_redraw()
		elif _touches.size() >= 2:
			_pinch()
		accept_event()
	elif ev is InputEventMouseButton:
		if ev.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_zoom_a(ev.position, 1.15)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_zoom_a(ev.position, 1.0 / 1.15)
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if ev.pressed:
				_mouse_down = true
				_press_pos = ev.position
				_dragging = false
			else:
				_mouse_down = false
				if not _dragging and ev.button_index == MOUSE_BUTTON_LEFT and ev.position.distance_to(_press_pos) < 8.0:
					_tap(ev.position)
		accept_event()
	elif ev is InputEventMouseMotion:
		if ev.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if _mouse_down:
			if ev.position.distance_to(_press_pos) > 6.0:
				_dragging = true
			if _dragging:
				offset += ev.relative
				queue_redraw()
	elif ev is InputEventMagnifyGesture:
		_zoom_a(ev.position, ev.factor)
	elif ev is InputEventPanGesture:
		offset -= ev.delta * 12.0
		queue_redraw()


func _inizio_pinch() -> void:
	var k: Array = _touches.keys()
	var a: Vector2 = _touches[k[0]]
	var b: Vector2 = _touches[k[1]]
	_pinch_d = a.distance_to(b)
	_pinch_a = (b - a).angle()
	_drag_from = (a + b) / 2.0
	_dragging = true


func _pinch() -> void:
	var k: Array = _touches.keys()
	var a: Vector2 = _touches[k[0]]
	var b: Vector2 = _touches[k[1]]
	var d := a.distance_to(b)
	var ang := (b - a).angle()
	var mid := (a + b) / 2.0
	if _pinch_d > 1.0:
		var f := d / _pinch_d
		_zoom_a(_drag_from, f)
		var dr := wrapf(ang - _pinch_a, -PI, PI)
		_ruota_a(_drag_from, dr)
	offset += mid - _drag_from
	_pinch_d = d
	_pinch_a = ang
	_drag_from = mid
	queue_redraw()


func _zoom_a(p: Vector2, f: float) -> void:
	var mp := schermo_a_mappa(p)
	zoom = clampf(zoom * f, 0.12, 2.5)
	offset = p - _xf_basis().basis_xform(mp)
	queue_redraw()


func _ruota_a(p: Vector2, da: float) -> void:
	var mp := schermo_a_mappa(p)
	rot += da
	offset = p - _xf_basis().basis_xform(mp)


func raddrizza() -> void:
	var c := schermo_a_mappa(size / 2.0)
	rot = 0.0
	offset = size / 2.0 - _xf_basis().basis_xform(c)
	queue_redraw()


func _tap(p: Vector2) -> void:
	var mp := schermo_a_mappa(p)
	var h := FTData.da_pixel(mp)
	hex_tapped.emit(h)


# ------------------------------------------------------------ disegno

func _hex_poly(h: Vector2i, scale := 1.0) -> PackedVector2Array:
	var c := FTData.centro(h)
	var r := FTData.DY / sqrt(3.0) * scale
	var pts := PackedVector2Array()
	for i in 7:
		var a := deg_to_rad(60.0 * i)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#05080c"))
	if nascondi_tutto:
		return
	draw_set_transform_matrix(_xf())
	if tex != null:
		draw_texture(tex, Vector2.ZERO)
	if eng == null:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var vis := _hex_visibili()
	# griglia
	if mostra_griglia and zoom > 0.28:
		var col := Color(0, 0, 0, 0.16)
		for h in vis:
			if FTData.ter(h) != " ":
				draw_polyline(_hex_poly(h), col, 1.0 / zoom * 0.8)
	# nubi e tempeste
	var nm := eng.nubi_map()
	for h in vis:
		var n: int = int(nm.get(h, 0))
		if n == 1:
			draw_colored_polygon(_hex_poly(h, 0.98), Color(1, 1, 1, 0.16))
		elif n >= 2:
			draw_colored_polygon(_hex_poly(h, 0.98), Color(0.12, 0.14, 0.2, 0.42))
	for c in eng.st["nubi"]:
		var ch := FTEngine.vh(c["h"])
		var cp := FTData.centro(ch)
		var ct := UI.tex("res://assets/pedine/cloud.png")
		if ct != null and zoom > 0.2:
			draw_texture_rect(ct, Rect2(cp - Vector2(22, 22), Vector2(44, 44)), false, Color(1, 1, 1, 0.75))
	# notte
	if eng.notte():
		draw_rect(Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height())), Color(0.02, 0.05, 0.18, 0.32))
	# evidenziazioni
	for h in evidenzia:
		draw_colored_polygon(_hex_poly(h, 0.92), evidenzia[h])
	if not anello.is_empty():
		_anello(anello["c"], int(anello["r"]), anello.get("col", Color(UI.BRASS_L, 0.8)))
	# basi
	for bid in eng.st["basi"]:
		_disegna_base(bid)
	# rotte pianificate
	for tid in rotte:
		_rotta(tid, rotte[tid], Color(UI.lato_col(lato), 0.95), true)
	for fid in rotte_af:
		_rotta(fid, rotte_af[fid], Color(0.75, 0.95, 1.0, 0.95), false)
	# unità
	_disegna_unita(vis)
	# selezione
	if sel_hex.x > -100:
		draw_polyline(_hex_poly(sel_hex, 1.02), UI.BRASS_L, 4.0 / maxf(zoom, 0.3))
	if bersaglio.x > -100:
		var bc := FTData.centro(bersaglio)
		draw_arc(bc, 30, 0, TAU, 32, UI.BAD, 4.0)
		draw_line(bc + Vector2(-40, 0), bc + Vector2(-18, 0), UI.BAD, 3.0)
		draw_line(bc + Vector2(40, 0), bc + Vector2(18, 0), UI.BAD, 3.0)
		draw_line(bc + Vector2(0, -40), bc + Vector2(0, -18), UI.BAD, 3.0)
		draw_line(bc + Vector2(0, 40), bc + Vector2(0, 18), UI.BAD, 3.0)
	# effetti dei combattimenti
	for e in effetti:
		var ec := FTData.centro(e["h"])
		var t: float = e["t"]
		var a := 1.0 - t / 2.2
		var col2 := Color(1.0, 0.55, 0.1, a) if e["k"] != "affondata" else Color(1.0, 0.2, 0.1, a)
		draw_circle(ec, 10.0 + t * 30.0, Color(col2, a * 0.35))
		draw_arc(ec, 12.0 + t * 40.0, 0, TAU, 40, col2, 4.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _hex_visibili() -> Array:
	var inv := _xf().affine_inverse()
	var pts := [inv * Vector2.ZERO, inv * Vector2(size.x, 0), inv * size, inv * Vector2(0, size.y)]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var c0 := maxi(0, int((mn.x - FTData.X0) / FTData.DX) - 1)
	var c1 := mini(FTData.COLS - 1, int((mx.x - FTData.X0) / FTData.DX) + 1)
	var r0 := maxi(FTData.row0, int((mn.y - FTData.Y0) / FTData.DY) - 1)
	var r1 := mini(FTData.row0 + FTData.ROWS - 1, int((mx.y - FTData.Y0) / FTData.DY) + 1)
	var out := []
	for c in range(c0, c1 + 1):
		for r in range(r0, r1 + 1):
			out.append(Vector2i(c, r))
	return out


func _anello(c: Vector2i, r: int, col: Color) -> void:
	# contorno degli esagoni a distanza r (cerchio d'azione)
	var cp := FTData.centro(c)
	var rad := r * FTData.DY
	draw_arc(cp, rad, 0, TAU, 96, col, 3.0 / maxf(zoom, 0.25))
	draw_arc(cp, rad, 0, TAU, 96, Color(col, 0.15), 14.0 / maxf(zoom, 0.25))


func _rotta(id: String, path: Array, col: Color, nave: bool) -> void:
	var start := Vector2i(-999, -999)
	if nave and eng.st["tf"].has(id):
		start = eng.tf_hex(id)
	elif not nave and eng.st["af"].has(id):
		start = eng.af_hex(id)
	if start.x < -100 or path.is_empty():
		return
	var prev := FTData.centro(start)
	var w := 5.0 if nave else 3.5
	for i in path.size():
		var h: Vector2i = path[i] if path[i] is Vector2i else FTEngine.vh(path[i])
		var p := FTData.centro(h)
		# tratteggio
		var seg := p - prev
		var n := int(seg.length() / 10.0)
		for k in n:
			if k % 2 == 0:
				draw_line(prev + seg * (float(k) / n), prev + seg * (float(k + 1) / n), col, w)
		draw_circle(p, 6.0, col)
		prev = p
	# freccia finale
	if path.size() >= 1:
		var last: Vector2i = path[-1] if path[-1] is Vector2i else FTEngine.vh(path[-1])
		var lp := FTData.centro(last)
		var pp := FTData.centro(start) if path.size() == 1 else FTData.centro(path[-2] if path[-2] is Vector2i else FTEngine.vh(path[-2]))
		var d := (lp - pp).normalized()
		var nn := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([lp + d * 14, lp - d * 8 + nn * 10, lp - d * 8 - nn * 10]), col)


func _disegna_base(bid: String) -> void:
	var b: Dictionary = eng.st["basi"][bid]
	var h := FTEngine.vh(b["hex"])
	var c := FTData.centro(h)
	var col := UI.lato_col(b["lato"])
	var flag := UI.tex("res://assets/pedine/%s.png" % ("alliedflag" if b["lato"] == "A" else "axisflag"))
	var r := Rect2(c + Vector2(-34, -40), Vector2(30, 30))
	if flag != null:
		draw_texture_rect(flag, r, false)
	else:
		draw_rect(r, col)
	draw_rect(r, Color(0, 0, 0, 0.8), false, 2.0)
	if zoom > 0.3:
		var f := UI.font_ui_b
		var txt: String = b["nome"]
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var tp := c + Vector2(-tw / 2.0, 44)
		draw_rect(Rect2(tp + Vector2(-4, -16), Vector2(tw + 8, 22)), Color(0, 0, 0, 0.55))
		draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
	if int(b["hits"]) > 0:
		draw_circle(c + Vector2(22, -26), 13, UI.BAD)
		draw_string(UI.font_ui_b, c + Vector2(15, -19), str(b["hits"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


func _disegna_unita(vis: Array) -> void:
	var st: Dictionary = eng.st
	var per_hex := {}   # esagono -> lista di [tipo, id, lato, info]
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		if tf["navi"].is_empty() or tf.get("fuori", false):
			continue
		if tf["lato"] == lato:
			_aggiungi(per_hex, eng.tf_hex(tid), ["tf", tid, lato, {}])
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if af["lato"] == lato:
			_aggiungi(per_hex, eng.af_hex(fid), ["af", fid, lato, {}])
	# nemici: avvistamenti in corso e memoria recente
	var nem := eng.nemico(lato)
	var noti: Dictionary = st["noti"][lato]
	for k in noti:
		var n: Dictionary = noti[k]
		_aggiungi(per_hex, FTEngine.vh(n["hex"]), [n["tipo"], k, nem, n])
	for k in st["memoria"][lato]:
		if noti.has(k):
			continue
		var m: Dictionary = st["memoria"][lato][k]
		var eta: int = int(st["turno"]) - int(m["turno"])
		if eta <= 3 and m["tipo"] == "tf":
			var m2 := m.duplicate()
			m2["vecchio"] = eta
			_aggiungi(per_hex, FTEngine.vh(m["hex"]), ["tf", k, nem, m2])
	for h in per_hex:
		var lst: Array = per_hex[h]
		var c := FTData.centro(h)
		var i := 0
		for it in lst:
			var passo := maxf(12.0, 13.0 / maxf(zoom, 0.05))
			var off := Vector2(-passo + i * passo, -passo * 0.5 + i * passo * 0.8)
			if i >= 4:
				off = Vector2(-passo + (i - 4) * passo + 6, -passo * 0.5 + (i - 4) * passo * 0.8 + 4)
			_pedina(c + off, it)
			i += 1


func _aggiungi(d: Dictionary, h: Vector2i, it: Array) -> void:
	if not d.has(h):
		d[h] = []
	d[h].append(it)


func _pedina(p: Vector2, it: Array) -> void:
	var tipo: String = it[0]
	var id: String = it[1]
	var l: String = it[2]
	var info: Dictionary = it[3]
	var st: Dictionary = eng.st
	var size_p := maxf(38.0, 40.0 / maxf(zoom, 0.05))
	var r := Rect2(p - Vector2(size_p, size_p) / 2.0, Vector2(size_p, size_p))
	var t: Texture2D
	var alpha := 1.0
	if l == lato:
		if tipo == "tf":
			t = UI.tf_tex(l, int(st["tf"][id]["num"]))
		else:
			t = UI.af_tex(l, int(st["af"][id]["num"]))
	else:
		t = UI.tex("res://assets/pedine/%s_%s.png" % [tipo, l])
		if info.has("vecchio"):
			alpha = 0.45
	if t != null:
		draw_texture_rect(t, r, false, Color(1, 1, 1, alpha))
	else:
		draw_rect(r, Color(UI.lato_col(l), alpha))
	var bordo := Color(0, 0, 0, 0.85 * alpha)
	var bw := 2.0
	if (tipo == "tf" and id == sel_tf) or (tipo == "af" and id == sel_af):
		bordo = UI.BRASS_L
		bw = 4.0
	draw_rect(r, bordo, false, bw)
	if l == lato:
		# unità nascoste al nemico: angolo tratteggiato
		var esp: bool = st["tf"][id]["esposta"] if tipo == "tf" else st["af"][id]["esposta"]
		if esp:
			draw_rect(Rect2(r.position + Vector2(r.size.x - 12, -4), Vector2(14, 10)), UI.BAD)
		if tipo == "af":
			var q: String = st["af"][id]["quota"]
			draw_rect(Rect2(r.position + Vector2(-6, r.size.y - 12), Vector2(16, 14)), Color(0, 0, 0, 0.75))
			draw_string(UI.font_ui_b, r.position + Vector2(-3, r.size.y), "A" if q == "A" else "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	else:
		# condizione dell'avvistamento
		var txt := ""
		var cond: int = int(info.get("cond", 0))
		var inf: Dictionary = info.get("info", {})
		if info.has("vecchio"):
			txt = "-%dh" % int(info["vecchio"])
		elif cond == 0:
			txt = "?"
		elif tipo == "tf":
			if cond >= 3:
				txt = "%d" % int(inf.get("navi", 0))
				if int(inf.get("portaerei", 0)) > 0:
					txt = "CV %s" % txt
			elif cond == 2:
				txt = "~%d" % int(inf.get("navi_circa", 0))
				if bool(inf.get("ha_portaerei", false)):
					txt = "CV " + txt
			else:
				txt = "navi"
		else:
			if cond >= 3:
				txt = "%d" % (int(inf.get("armati", 0)) + int(inf.get("scarichi", 0)))
			elif cond == 2:
				txt = "~%d" % int(inf.get("aerei_circa", 0))
			else:
				txt = "aerei"
		var f := UI.font_ui_b
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var tp := r.position + Vector2(r.size.x / 2.0 - tw / 2.0, r.size.y + 15)
		draw_rect(Rect2(tp + Vector2(-3, -14), Vector2(tw + 6, 18)), Color(0, 0, 0, 0.7 * alpha))
		draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UI.lato_col(l), alpha))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
