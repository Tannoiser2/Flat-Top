class_name FTEngine
extends Node
## Motore di Flat Top. Tutto lo stato sta in un dizionario (st) fatto solo di tipi semplici, così si salva,
## si confronta e si rigioca. Il motore non decide mai al posto dei giocatori: chiede gli ordini al
## «decisore» (persona, IA o partita online) e li applica nell'ordine delle fasi del regolamento.
##
## Sequenza di un turno (un'ora):
##  1. Meteo (vento e nubi)                    automatico
##  2. Ordini simultanei: operazioni aeree, formazioni aeree, rotte delle Task Force, pedinamenti
##  3. Pedinamento e movimento delle TF        automatico, con avvistamenti esagono per esagono
##  4. Iniziativa                              tiro di dado
##  5. Movimento aereo: prima chi ha l'iniziativa, poi l'altro (con atterraggi, ricerca, intercettazioni)
##  6. Combattimento: aria-aria, contraerea, attacco aereo, superficie, bombardamento costiero
##  7. Riparazioni, sbarchi, punti vittoria, avanzamento dell'orologio

signal log_added(entry: Dictionary)
signal state_changed
signal decision_requested(req: Dictionary)
signal decision_provided(value)
signal game_over(result: Dictionary)
signal event(ev: Dictionary)

const LATI := ["A", "J"]
const NOME_LATO := {"A": "Alleati", "J": "Giappone"}

var st: Dictionary = {}
var rng := RandomNumberGenerator.new()
var decider = null            # oggetto con decide_simul(eng, req) e decide(eng, side, req)
var ais := {}                 # lato -> FTAI
var players := {}             # lato -> "umano" / "ia" / "remoto"
var decisions: Array = []     # registro delle decisioni (per salvataggi e rigiocate)
var replay: Array = []        # decisioni da rigiocare
var running := false
var ai_delay := 0.0
var fast := false             # true nelle simulazioni: niente pause
var stop_requested := false

const COMBAT := preload("res://scripts/core/combat.gd")
const PILOT := preload("res://scripts/core/pilot.gd")


# ================================================================ preparazione

func setup(scen_id: String, seed: int, p_players: Dictionary) -> void:
	FTData.load_all()
	players = p_players
	rng.seed = seed
	var sc := FTData.scenario(scen_id)
	st = {
		"scen": scen_id, "seed": seed, "turno": 0, "turni": int(sc.get("turni", 18)),
		"giorno": int(sc.get("giorno", 0)), "ora": int(sc.get("ora", 6)),
		"navi": {}, "tf": {}, "af": {}, "nidi": {}, "basi": {},
		"nubi": [], "vento": [], "noti": {"A": {}, "J": {}}, "memoria": {"A": {}, "J": {}},
		"lati": {}, "log": [], "fase": "inizio", "iniziativa": "A", "fine": false, "risultato": {},
		"next": {"N": 1, "T": 1, "F": 1}, "speciali": sc.get("speciali", {}), "attaccate": {}, "sbarchi": {"A": 0, "J": 0},
		"avvistate_J": false, "avvistate_A": false, "rinforzi_fatti": false, "eventi": [],
	}
	for s in LATI:
		st["lati"][s] = {"vp": 0, "perdite_oggi": {}, "tf_num": 1, "af_num": 1, "radar_navi": "", "contegno": {}}
	_crea_basi(sc)
	_crea_flotte(sc)
	_meteo_iniziale(sc)
	_osserva_tutto("")
	ais = {}
	for s in LATI:
		ais[s] = FTAI.new(s)
	add_log("*", "Scenario: %s (%s). Durata %d turni." % [sc.get("nome", ""), sc.get("data", ""), st["turni"]])


func _profilo(sc: Dictionary) -> String:
	return str(sc.get("profilo", "*"))


func _crea_basi(sc: Dictionary) -> void:
	var prof := _profilo(sc)
	for s in LATI:
		var side: Dictionary = sc.get(s, {})
		var radar: Array = side.get("radar", [])
		var basi_sc: Dictionary = side.get("basi", {})
		for bid in basi_sc:
			var profili: Dictionary = FTData.basi.get(bid, {})
			var b: Dictionary = profili.get(prof, profili.get("*", {})).duplicate(true)
			if b.is_empty():
				continue
			b["id"] = bid
			b["lato"] = s
			b["hits"] = 0
			b["radar"] = bid in radar
			b["lf0"] = b["lf"].duplicate()
			b["aaf0"] = b["aaf"]
			b["sf0"] = b["sf"]
			st["basi"][bid] = b
			var nido := _nido_vuoto(bid, "base", s)
			for tipo in basi_sc[bid]:
				var q: int = int(basi_sc[bid][tipo])
				if q > 0:
					_add(nido["prep"], tipo, q)
			st["nidi"][bid] = nido
			if s == "A" and str(sc.get("mezza_mappa", "")) == "ovest" and b["hex"][0] >= 40 and not b["fuori"]:
				pass


func _nido_vuoto(id: String, kind: String, lato: String) -> Dictionary:
	return {"id": id, "kind": kind, "lato": lato, "jl": {}, "prep": {}, "pronti": {}, "disp": {},
		"volo": [], "auto": true, "cap": 0, "lf_usato": 0, "lf_pieno": 0, "rf_usato": 0, "rf_zero": false,
		"no_lanci": false}


func _crea_flotte(sc: Dictionary) -> void:
	for s in LATI:
		var side: Dictionary = sc.get(s, {})
		var radar: Array = side.get("radar", [])
		for tdef in side.get("tf", []):
			var tid := _new_id("T")
			var tf := {"id": tid, "lato": s, "num": st["lati"][s]["tf_num"], "hex": tdef["hex"].duplicate(),
				"navi": [], "rotta": [], "esposta": false, "ancorata": bool(tdef.get("ancorata", false)),
				"contegno": "evita", "entra": int(tdef.get("entra", -1)), "mosso": 0, "pedina": "", "sbarco": 0}
			st["lati"][s]["tf_num"] += 1
			var aerei_def: Dictionary = tdef.get("aerei", {})
			for nome in tdef["navi"]:
				var nid := _crea_nave(nome, s, radar)
				var nave: Dictionary = st["navi"][nid]
				nave["tf"] = tid
				if bool(tdef.get("ancorata", false)):
					nave["ancorata"] = true
				tf["navi"].append(nid)
				if aerei_def.has(nome):
					var nido := _nido_vuoto(nid, "nave", s)
					for tipo in aerei_def[nome]:
						var q: int = int(aerei_def[nome][tipo])
						if q > 0:
							# le portaerei iniziano con i caccia pronti e i bombardieri in preparazione
							if _ruoli(tipo).contains("E") or FTData.aerei[tipo]["classe"] == "FL":
								_add(nido["pronti"], tipo + "|", q)
							else:
								_add(nido["prep"], tipo, q)
					st["nidi"][nid] = nido
				elif nave["mc"] > 0:
					st["nidi"][nid] = _nido_vuoto(nid, "nave", s)
			if tf["entra"] > 0:
				tf["fuori"] = true
			st["tf"][tid] = tf


func _crea_nave(nome: String, lato: String, radar: Array) -> String:
	var nid := _new_id("N")
	var base: Dictionary
	var gen := false
	if FTData.navi.has(nome):
		base = FTData.navi[nome].duplicate()
	else:
		base = FTData.generiche.get(nome, {"tipo": nome, "art": 0, "aa": 0, "mv": 1, "danno": 1, "mun": 0, "silu": 0}).duplicate()
		base["nome"] = nome
		gen = true
	var tipo: String = base["tipo"]
	var n := {"id": nid, "nome": base.get("nome", nome), "chiave": nome, "tipo": tipo, "lato": lato,
		"art": int(base["art"]), "aa": int(base["aa"]), "mv": int(base["mv"]), "danno": int(base["danno"]),
		"art0": int(base["art"]), "aa0": int(base["aa"]), "mun": int(base.get("mun", 0)), "silu": int(base.get("silu", 0)),
		"hits": 0, "affondata": false, "ancorata": false, "tf": "", "radar": false, "generica": gen,
		"mc": 0, "lf": [0, 0], "rf": 0, "ph": "", "lento": false, "carico": 8 if tipo in ["AP", "APD"] else 0,
		"stop_turni": 0, "mezza": false}
	# radar
	if "*tutte" in radar or nome in radar:
		n["radar"] = true
	elif "*navi_maggiori" in radar and tipo in ["CV", "CVL", "BB", "CA", "CL"]:
		n["radar"] = true
	# operazioni aeree
	var opkey: String = base.get("nome", nome)
	if FTData.ops.has(opkey):
		var o: Array = FTData.ops[opkey]
		n["mc"] = int(o[0]); n["lf"] = [int(o[1]), int(o[2])]; n["rf"] = int(o[3]); n["ph"] = str(o[4])
	elif tipo == "CAV":
		var o2: Array = FTData.ops_tipo["CAV"]
		n["mc"] = int(o2[0]); n["lf"] = [int(o2[1]), int(o2[2])]; n["rf"] = int(o2[3]); n["ph"] = "FP"
	elif tipo == "BB" and lato == "J":
		var o3: Array = FTData.ops_tipo["BB_J"]
		n["mc"] = int(o3[0]); n["lf"] = [int(o3[1]), int(o3[2])]; n["rf"] = int(o3[3]); n["ph"] = "FP"
	if bool(st["speciali"].get("enterprise_rf6", false)) and opkey == "Enterprise":
		n["rf"] = 6
	if bool(st["speciali"].get("he_hiei_kirishima", false)) and opkey in ["Hiei", "Kirishima"]:
		n["he"] = true
	n["lf0"] = n["lf"].duplicate()
	st["navi"][nid] = n
	return nid


func _new_id(prefix: String) -> String:
	var k: int = st["next"][prefix]
	st["next"][prefix] = k + 1
	return "%s%d" % [prefix, k]


# ================================================================ utilità

func d6() -> int:
	return rng.randi_range(1, 6)


func add_log(lato: String, testo: String, tipo := "") -> void:
	var e := {"t": st.get("turno", 0), "ora": st.get("ora", 0), "lato": lato, "testo": testo, "tipo": tipo}
	st["log"].append(e)
	if st["log"].size() > 1200:
		st["log"] = st["log"].slice(st["log"].size() - 1000)
	log_added.emit(e)


static func _add(d: Dictionary, k: String, q: int) -> void:
	d[k] = int(d.get(k, 0)) + q
	if d[k] <= 0:
		d.erase(k)


static func _ruoli(tipo: String) -> String:
	return str(FTData.aerei.get(tipo, {}).get("ruoli", "B"))


func nemico(s: String) -> String:
	return "J" if s == "A" else "A"


func notte() -> bool:
	return FTData.is_notte(int(st["ora"]))


func ora_testo(ora := -1, giorno := -1) -> String:
	if ora < 0:
		ora = int(st["ora"])
	if giorno < 0:
		giorno = int(st["giorno"])
	return "%02d00" % ora


func data_testo() -> String:
	var sc := FTData.scenario(st["scen"])
	var mesi := {"rabaul": ["23 febbraio"], "coral": ["4 maggio", "5 maggio", "6 maggio", "7 maggio", "8 maggio"],
		"salomone": ["24 agosto", "25 agosto", "26 agosto"], "santacruz": ["25 ottobre", "26 ottobre", "27 ottobre"],
		"guadalcanal": ["12 novembre", "13 novembre", "14 novembre", "15 novembre"]}
	var key: String = str(sc.get("id", "")).split("_")[0]
	var L: Array = mesi.get(key, [])
	var g: int = int(st["giorno"])
	var giorno := str(L[g]) if g < L.size() else "giorno %d" % (g + 1)
	return "%s, ore %s" % [giorno, ora_testo()]


func turni_rimasti() -> int:
	return int(st["turni"]) - int(st["turno"])


## Esagoni con nubi: 1 = nuvoloso, 2+ = tempesta.
var _nubi_m := {}
var _nubi_k := ""

func nubi_map() -> Dictionary:
	if _nubi_k != str(st.get("nubi_ver", 0)) + ":" + str(st.get("scen", "")):
		_ricalcola_nubi()
	return _nubi_m


func _ricalcola_nubi() -> void:
	var m := {}
	for c in st.get("nubi", []):
		var h := Vector2i(int(c["h"][0]), int(c["h"][1]))
		for q in FTData.dentro(h, 2):
			m[q] = int(m.get(q, 0)) + 1
	_nubi_m = m
	_nubi_k = str(st.get("nubi_ver", 0)) + ":" + str(st.get("scen", ""))


func meteo(h: Vector2i) -> int:
	return int(nubi_map().get(h, 0))


func tempesta(h: Vector2i) -> bool:
	return meteo(h) >= 2


static func vh(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func tf_hex(tid: String) -> Vector2i:
	return vh(st["tf"][tid]["hex"])


func af_hex(fid: String) -> Vector2i:
	var af: Dictionary = st["af"][fid]
	if str(af.get("in_volo_di", "")) != "":
		var h := nido_hex(af["in_volo_di"])
		if h.x > -100:
			return h
	return vh(af["hex"])


## Esagono di un nido (portaerei o base). Vector2i(-999,-999) se non c'è (affondata).
func nido_hex(nid: String) -> Vector2i:
	if st["basi"].has(nid):
		return vh(st["basi"][nid]["hex"])
	var n: Dictionary = st["navi"].get(nid, {})
	if n.is_empty() or n["affondata"] or n["tf"] == "":
		return Vector2i(-999, -999)
	return tf_hex(n["tf"])


func nido_nome(nid: String) -> String:
	if st["basi"].has(nid):
		return st["basi"][nid]["nome"]
	return str(st["navi"].get(nid, {}).get("nome", nid))


func nido_lato(nid: String) -> String:
	return str(st["nidi"][nid]["lato"])


## Fattore di lancio attuale [normale, minimo] (ridotto dai danni). Le basi fuori mappa sono illimitate.
func nido_lf(nid: String) -> Array:
	if st["basi"].has(nid):
		var b: Dictionary = st["basi"][nid]
		return [int(b["lf"][0]), int(b["lf"][1])]
	var n: Dictionary = st["navi"][nid]
	var lf: Array = n["lf0"]
	var h: int = n["hits"]
	var rn := 3 if n["tipo"] == "CV" else (2 if n["tipo"] == "CVL" else 1)
	var lfn: int = int(lf[0])
	var lfm: int = int(lf[1])
	# base idrovolanti temporanea: capacità e LF massimo raddoppiati
	if n["tipo"] in ["AV", "CAV"] and n["ancorata"]:
		lfn = lfn * 2 if n["tipo"] == "AV" else lfn
	return [maxi(0, lfn - rn * h), maxi(0, lfm - h)]


func nido_mc(nid: String) -> int:
	if st["basi"].has(nid):
		return int(st["basi"][nid]["mc"])
	var n: Dictionary = st["navi"][nid]
	var mc: int = n["mc"]
	if n["tipo"] in ["AV", "CAV"] and n["ancorata"]:
		mc *= 2
	return mc


func nido_rf(nid: String) -> int:
	var nido: Dictionary = st["nidi"][nid]
	if nido.get("rf_zero", false):
		return 0
	if st["basi"].has(nid):
		return int(st["basi"][nid]["rf"])
	return int(st["navi"][nid]["rf"])


func nido_aerei(nid: String) -> int:
	var nido: Dictionary = st["nidi"][nid]
	var t := 0
	for box in ["jl", "prep", "pronti", "disp"]:
		for k in nido[box]:
			t += int(nido[box][k])
	return t


## Il nido può far decollare o atterrare questo tipo di aereo?
func nido_accetta(nid: String, tipo: String) -> bool:
	var cls: String = FTData.aerei[tipo]["classe"]
	var ph: String
	if st["basi"].has(nid):
		ph = st["basi"][nid]["ph"]
		var sp: Dictionary = st["speciali"]
		if nid == "gili_gili" and st["basi"][nid]["lato"] == "A" and st["scen"].begins_with("salomone"):
			return tipo in ["P-39", "P-40", "Avenger", "Dauntless", "Wildcat"]
		if ph.contains("L") and cls in ["L", "CV"]:
			return true
		if ph.contains("S") and cls in ["FL", "FH"]:
			return true
		return false
	var n: Dictionary = st["navi"][nid]
	if n["affondata"]:
		return false
	ph = n["ph"]
	if ph == "CV":
		return cls == "CV"
	if ph == "FP":
		if cls == "FL":
			# i Pete del Kamikawa solo con la base idro stabilita (nave ancorata)
			if tipo == "Pete" and n["nome"] == "Kamikawa" and bool(st["speciali"].get("seaplane_kamikawa", false)):
				return n["ancorata"]
			return true
		if cls == "FH" and n["tipo"] in ["AV", "CAV"] and n["ancorata"]:
			return true
	return false


# ================================================================ meteo

func _meteo_iniziale(sc: Dictionary) -> void:
	st["vento"] = [2, 2, 2, 2, 2, 2, 2, 2]  # direzione 3 (sud-est), come la freccia stampata
	var mezza := str(sc.get("mezza_mappa", ""))
	for s in 8:
		if mezza == "ovest" and s % 4 >= 2:
			continue
		var dh: Vector2i = FTData.SETTORE_HEX[s]
		if str(sc.get("meteo", "sparse")) == "fronte":
			var roll := d6()
			var dirn := roll - 1
			for off in [-5, 0, 5]:
				# fila da nord-est a sud-ovest
				var h := dh
				var steps := absi(off)
				var d := 1 if off < 0 else 4
				for i in steps:
					h = FTData.vicino(h, d)
				for i in roll:
					h = FTData.vicino(h, dirn)
				st["nubi"].append({"h": [h.x, h.y], "s": s})
		else:
			for k in 4:
				var roll := d6()
				var h := dh
				var dir2 := d6() - 1
				for i in roll:
					h = FTData.vicino(h, dir2)
				st["nubi"].append({"h": [h.x, h.y], "s": s})
	st["nubi_ver"] = int(st.get("nubi_ver", 0)) + 1


func _fase_meteo() -> void:
	var ora: int = st["ora"]
	if ora in [6, 12, 18, 24]:
		for s in 8:
			var r := d6()
			if r == 5:
				st["vento"][s] = (int(st["vento"][s]) + 5) % 6
			elif r == 6:
				st["vento"][s] = (int(st["vento"][s]) + 1) % 6
	if int(st["turno"]) % 2 == 0:
		var nuove := []
		for c in st["nubi"]:
			var s: int = c["s"]
			var h := FTData.vicino(vh(c["h"]), int(st["vento"][s]))
			var ns := FTData.settore(h)
			if ns != s or FTData.ter(h) == " ":
				# la nube passa in un altro settore: si ricolloca (tabella del movimento delle nubi)
				var r := d6()
				var dest := s if r == 1 else (0 if r == 6 else (ns if FTData.ter(h) != " " else s))
				var dh: Vector2i = FTData.SETTORE_HEX[dest]
				var roll := d6()
				var dirn := d6() - 1
				h = dh
				for i in roll:
					h = FTData.vicino(h, dirn)
				s = dest
			nuove.append({"h": [h.x, h.y], "s": s})
		st["nubi"] = nuove
		st["nubi_ver"] = int(st.get("nubi_ver", 0)) + 1
		# formazioni aeree finite in una nuova tempesta: escono subito
		for fid in st["af"]:
			var af: Dictionary = st["af"][fid]
			if str(af.get("in_volo_di", "")) != "":
				continue
			var hh := vh(af["hex"])
			if tempesta(hh):
				for nb in FTData.vicini(hh):
					if not tempesta(nb) and FTData.volabile(nb):
						af["hex"] = [nb.x, nb.y]
						break


# ================================================================ ciclo di gioco

func run() -> void:
	running = true
	while not st["fine"] and not stop_requested:
		await _turno()
		if stop_requested:
			break
		state_changed.emit()
	running = false


func _turno() -> void:
	var t: int = st["turno"]
	var ora: int = st["ora"]
	# ingresso di TF fuori mappa
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		if tf.get("fuori", false) and int(tf["entra"]) <= t:
			tf["fuori"] = false
			add_log(tf["lato"], "La TF %d entra in mappa." % tf["num"])
	if t > 0:
		st["fase"] = "meteo"
		_fase_meteo()
	if ora == 1 and t > 0:
		_rimpiazzi()
	_inizio_turno()
	_rinforzi()
	_osserva_tutto("")
	state_changed.emit()
	# ---- ordini simultanei
	st["fase"] = "ordini"
	state_changed.emit()
	var ordini: Dictionary = await _decide_simul({"k": "ordini", "turno": t})
	if stop_requested:
		return
	for s in LATI:
		_applica_ordini(s, ordini.get(s, {}))
	# ---- pedinamento e movimento delle TF
	st["fase"] = "movimento_tf"
	_movimento_tf(ordini)
	# ---- iniziativa
	st["fase"] = "iniziativa"
	var ra := d6()
	var rj := d6()
	var prima: String = st["iniziativa"]
	if ra > rj:
		prima = "A"
	elif rj > ra:
		prima = "J"
	else:
		prima = nemico(st["iniziativa"])
	st["iniziativa"] = prima
	add_log("*", "Iniziativa: %s (%d contro %d)." % [NOME_LATO[prima], ra if prima == "A" else rj, rj if prima == "A" else ra])
	# ---- movimento aereo
	for s in [prima, nemico(prima)]:
		st["fase"] = "aria_" + s
		st["muove"] = s
		_preparazione_aria(s)
		_osserva_tutto(s)
		state_changed.emit()
		var mosse: Dictionary = await _decide(s, {"k": "aria", "turno": t})
		if stop_requested:
			return
		_movimento_aereo(s, mosse)
	st["muove"] = ""
	# ---- combattimento
	st["fase"] = "combattimento"
	_osserva_tutto("")
	COMBAT.fase_combattimento(self)
	# ---- fine turno
	st["fase"] = "riparazioni"
	_sbarchi()
	_riparazioni()
	_fine_turno()
	_controlla_vittoria()
	if not st["fine"]:
		_avanza_ora()
		if int(st["turno"]) >= int(st["turni"]):
			_fine_partita()


func _avanza_ora() -> void:
	st["turno"] = int(st["turno"]) + 1
	var ora: int = int(st["ora"]) + 1
	if ora > 24:
		ora = 1
		st["giorno"] = int(st["giorno"]) + 1
	st["ora"] = ora


func _inizio_turno() -> void:
	for nid in st["nidi"]:
		var nido: Dictionary = st["nidi"][nid]
		nido["lf_usato"] = 0
		nido["lf_pieno"] = 0
		nido["rf_usato"] = 0
		nido["no_lanci"] = bool(nido.get("no_lanci_prossimo", false))
		nido["no_lanci_prossimo"] = false
		nido["rf_zero"] = bool(nido.get("rf_zero_prossimo", false))
		nido["rf_zero_prossimo"] = false
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		af["cerca_ok"] = false
		af["mosso"] = 0
		af["rf_speso_turno"] = false
		af["mf_turno"] = -1
	for tid in st["tf"]:
		st["tf"][tid]["mosso"] = 0
	st["attaccate"] = {}
	st["combattuti"] = st.get("combattuti_ora", {})
	st["combattuti_ora"] = {}


func _rinforzi() -> void:
	var sp: Dictionary = st["speciali"]
	if sp.has("rinforzi_J_avvistamento") and not st["rinforzi_fatti"] and st.get("avvistata_nave_A_turno", -1) >= 0 \
			and int(st["turno"]) > int(st["avvistata_nave_A_turno"]):
		var r: Dictionary = sp["rinforzi_J_avvistamento"]
		var nido: Dictionary = st["nidi"].get(r["base"], {})
		if not nido.is_empty():
			for tipo in r["aerei"]:
				_add(nido["prep"], tipo, int(r["aerei"][tipo]))
			st["rinforzi_fatti"] = true
			add_log("J", "Rinforzi a %s: %s." % [nido_nome(r["base"]), _desc_aerei(r["aerei"])])


func _rimpiazzi() -> void:
	for s in LATI:
		var perse: Dictionary = st["lati"][s]["perdite_oggi"]
		var tot := 0
		for tipo in perse:
			var q: int = int(perse[tipo]) / 3
			if q <= 0:
				continue
			# il primo nido amico (base) che li accetta
			for nid in st["nidi"]:
				if nido_lato(nid) == s and st["basi"].has(nid) and nido_accetta(nid, tipo):
					_add(st["nidi"][nid]["jl"], tipo, q)
					tot += q
					break
		st["lati"][s]["perdite_oggi"] = {}
		if tot > 0:
			add_log(s, "Rimpiazzi dell'alba: %d fattori aerei." % tot)


static func _desc_aerei(d: Dictionary) -> String:
	var p := []
	for k in d:
		p.append("%d %s" % [int(d[k]), k])
	return ", ".join(p)


# ================================================================ decisioni

func _decide_simul(req: Dictionary) -> Dictionary:
	if replay.size() > 0:
		var v = replay.pop_front()
		decisions.append(v)
		return v
	var out: Dictionary
	if decider != null and decider.has_method("decide_simul"):
		out = await decider.decide_simul(self, req)
	else:
		out = {}
		for s in LATI:
			out[s] = ais[s].decide(self, s, req)
	decisions.append(out)
	return out


func _decide(s: String, req: Dictionary) -> Dictionary:
	if replay.size() > 0:
		var v = replay.pop_front()
		decisions.append(v)
		return v
	var out: Dictionary
	if decider != null and decider.has_method("decide"):
		out = await decider.decide(self, s, req)
	else:
		out = ais[s].decide(self, s, req)
	if out == null:
		out = {}
	decisions.append(out)
	return out


## Chiamata dall'interfaccia quando la persona ha finito gli ordini.
func provide_decision(value) -> void:
	decision_provided.emit(value)


# ================================================================ ordini

## Ordini simultanei di un lato:
##  "prep": [{n, da, a, tipo, q, arma}]  spostamenti fra le caselle (rientrati -> preparazione -> pronti)
##  "auto": {nido: bool}                 preparazione automatica del nido
##  "cap": {nido: n}                     caccia da tenere in pattuglia sopra il nido
##  "lanci": [{n, gruppi:[{tipo,q,arma}], quota, missione}]  nuove formazioni aeree
##  "rotte": {tf: [[c,r], ...]}          rotta di ogni TF per questo turno
##  "ancora": {tf: bool}, "contegno": {tf: "evita"/"attacca"/"bombarda"}, "mostra": {tf: bool}
##  "pedina": {tf/af: chiave nemica}     tentativi di pedinamento
##  "dividi": [{tf, navi:[...]}], "unisci": [[tf1, tf2]]
func _applica_ordini(s: String, o: Dictionary) -> void:
	if o == null:
		o = {}
	var auto: Dictionary = o.get("auto", {})
	for nid in auto:
		if st["nidi"].has(nid) and nido_lato(nid) == s:
			st["nidi"][nid]["auto"] = bool(auto[nid])
	var cb: Dictionary = o.get("contro_basi", {})
	for nid in cb:
		if st["nidi"].has(nid) and nido_lato(nid) == s:
			st["nidi"][nid]["contro_basi"] = bool(cb[nid])
	var cap: Dictionary = o.get("cap", {})
	for nid in cap:
		if st["nidi"].has(nid) and nido_lato(nid) == s:
			st["nidi"][nid]["cap"] = clampi(int(cap[nid]), 0, 40)
	# 8.10.1 preparazione -> pronti (con armamento), poi 8.10.3/8.10.4
	for m in o.get("prep", []):
		_sposta_box(s, m)
	for nid in st["nidi"]:
		var nido: Dictionary = st["nidi"][nid]
		if nido["lato"] == s and nido["auto"]:
			_prep_auto(nid)
	# formazioni aeree (8.10.2)
	for l in o.get("lanci", []):
		_forma_af(s, l)
	# CAP automatica
	for nid in st["nidi"]:
		var nido2: Dictionary = st["nidi"][nid]
		if nido2["lato"] == s and int(nido2.get("cap", 0)) > 0:
			_cap_auto(nid)
	# divisioni e unioni di TF
	for d in o.get("dividi", []):
		_dividi_tf(s, d)
	for u in o.get("unisci", []):
		_unisci_tf(s, u)
	var anc: Dictionary = o.get("ancora", {})
	for tid in anc:
		if st["tf"].has(tid) and st["tf"][tid]["lato"] == s:
			_ancora(tid, bool(anc[tid]))
	var cont: Dictionary = o.get("contegno", {})
	for tid in cont:
		if st["tf"].has(tid) and st["tf"][tid]["lato"] == s:
			st["tf"][tid]["contegno"] = str(cont[tid])
	var most: Dictionary = o.get("mostra", {})
	for tid in most:
		if st["tf"].has(tid) and st["tf"][tid]["lato"] == s:
			st["tf"][tid]["in_vista"] = bool(most[tid])
	var rotte: Dictionary = o.get("rotte", {})
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		if tf["lato"] != s:
			continue
		tf["rotta"] = []
		if rotte.has(tid):
			for h in rotte[tid]:
				tf["rotta"].append([int(h[0]), int(h[1])])
	var ped: Dictionary = o.get("pedina", {})
	st["lati"][s]["pedina"] = ped.duplicate()


func _sposta_box(s: String, m: Dictionary) -> void:
	var nid: String = str(m.get("n", ""))
	if not st["nidi"].has(nid) or nido_lato(nid) != s:
		return
	var nido: Dictionary = st["nidi"][nid]
	var da: String = str(m.get("da", ""))
	var a: String = str(m.get("a", ""))
	var tipo: String = str(m.get("tipo", ""))
	var q: int = int(m.get("q", 0))
	var arma: String = str(m.get("arma", ""))
	if q <= 0 or not FTData.aerei.has(tipo):
		return
	var rf_lib: int = nido_rf(nid) - int(nido["rf_usato"])
	q = mini(q, rf_lib)
	if q <= 0:
		return
	if da == "jl" and a == "prep":
		q = mini(q, int(nido["jl"].get(tipo, 0)))
		_add(nido["jl"], tipo, -q)
		_add(nido["prep"], tipo, q)
	elif da == "prep" and a == "pronti":
		q = mini(q, int(nido["prep"].get(tipo, 0)))
		if not _arma_ok(tipo, arma):
			arma = ""
		_add(nido["prep"], tipo, -q)
		_add(nido["pronti"], tipo + "|" + arma, q)
	elif da == "pronti" and a == "prep":
		var k := tipo + "|" + arma
		q = mini(q, int(nido["pronti"].get(k, 0)))
		_add(nido["pronti"], k, -q)
		_add(nido["prep"], tipo, q)
	elif da == "prep" and a == "disp" and st["basi"].has(nid):
		q = mini(q, int(nido["prep"].get(tipo, 0)))
		_add(nido["prep"], tipo, -q)
		_add(nido["disp"], tipo, q)
	elif da == "disp" and a == "prep":
		q = mini(q, int(nido["disp"].get(tipo, 0)))
		_add(nido["disp"], tipo, -q)
		_add(nido["prep"], tipo, q)
	else:
		return
	nido["rf_usato"] = int(nido["rf_usato"]) + q


## Un tipo di aereo può portare quell'arma? (Air Hit Tables)
static func _arma_ok(tipo: String, arma: String) -> bool:
	if arma == "":
		return true
	var b: Dictionary = FTData.aerei[tipo]["bht"]
	if arma == "T":
		return int(b["s_to"]) > 0
	var k := arma.to_lower()
	for pre in ["b_hl_", "b_ll_", "b_dv_", "s_hl_", "s_ll_", "s_dv_"]:
		if int(b[pre + k]) > 0:
			return true
	return false


## Arma preferita contro le navi: siluro se lo porta, altrimenti AP in picchiata, altrimenti la bomba migliore.
static func arma_preferita(tipo: String, contro_basi := false) -> String:
	var r := _ruoli(tipo)
	if not r.contains("B"):
		return ""
	if r.contains("E"):
		return ""  # i caccia restano scarichi per la scorta
	if FTData.aerei[tipo]["classe"] in ["FH", "FL"]:
		return ""  # gli idrovolanti fanno da esploratori
	var b: Dictionary = FTData.aerei[tipo]["bht"]
	if contro_basi:
		var gp := maxi(int(b["b_hl_gp"]), maxi(int(b["b_ll_gp"]), int(b["b_dv_gp"])))
		var ap := maxi(int(b["b_hl_ap"]), maxi(int(b["b_ll_ap"]), int(b["b_dv_ap"])))
		return "GP" if gp >= ap else "AP"
	if int(b["s_to"]) > 0:
		return "T"
	var gp2 := maxi(int(b["s_hl_gp"]), maxi(int(b["s_ll_gp"]), int(b["s_dv_gp"])))
	var ap2 := maxi(int(b["s_hl_ap"]), maxi(int(b["s_ll_ap"]), int(b["s_dv_ap"])))
	if gp2 == 0 and ap2 == 0:
		return "GP"
	return "AP" if ap2 >= gp2 else "GP"


## Preparazione automatica: prima i bombardieri armati, poi i caccia scarichi, poi i rientrati.
func _prep_auto(nid: String) -> void:
	var nido: Dictionary = st["nidi"][nid]
	var lib: int = nido_rf(nid) - int(nido["rf_usato"])
	if lib <= 0:
		return
	var contro_basi := bool(nido.get("contro_basi", false))
	var ordine := []
	for tipo in nido["prep"].keys():
		var r := _ruoli(tipo)
		var pri := 0 if (r.contains("B") and not r.contains("E")) else (1 if r.contains("E") or r.contains("I") else 2)
		ordine.append([pri, tipo])
	ordine.sort()
	for it in ordine:
		if lib <= 0:
			break
		var tipo: String = it[1]
		var q: int = mini(lib, int(nido["prep"].get(tipo, 0)))
		if q <= 0:
			continue
		var arma := arma_preferita(tipo, contro_basi)
		_add(nido["prep"], tipo, -q)
		_add(nido["pronti"], tipo + "|" + arma, q)
		lib -= q
		nido["rf_usato"] = int(nido["rf_usato"]) + q
	for tipo in nido["jl"].keys():
		if lib <= 0:
			break
		var q2: int = mini(lib, int(nido["jl"].get(tipo, 0)))
		_add(nido["jl"], tipo, -q2)
		_add(nido["prep"], tipo, q2)
		lib -= q2
		nido["rf_usato"] = int(nido["rf_usato"]) + q2


## Formazione di una nuova AF dalla casella «pronti».
func _forma_af(s: String, l: Dictionary) -> String:
	var nid: String = str(l.get("n", ""))
	if not st["nidi"].has(nid) or nido_lato(nid) != s:
		return ""
	var nido: Dictionary = st["nidi"][nid]
	if nido.get("no_lanci", false):
		return ""
	var h := nido_hex(nid)
	if h.x < -100:
		return ""
	if s == "J" and bool(st["speciali"].get("no_decollo_J_turno1", false)) and int(st["turno"]) == 0:
		return ""
	var gruppi := []
	var tot := 0
	for g in l.get("gruppi", []):
		var tipo: String = str(g.get("tipo", ""))
		var arma: String = str(g.get("arma", ""))
		var k := tipo + "|" + arma
		var q: int = mini(int(g.get("q", 0)), int(nido["pronti"].get(k, 0)))
		if q <= 0:
			continue
		if not nido_accetta(nid, tipo):
			continue
		gruppi.append({"tipo": tipo, "q": q, "arma": arma})
		tot += q
	if tot == 0:
		return ""
	# limite del fattore di lancio
	var lf := nido_lf(nid)
	var usato: int = nido["lf_usato"]
	var cap_max: int = 2 * int(lf[0]) if not st["basi"].get(nid, {}).get("fuori", false) else 9999
	if int(lf[0]) >= 999:
		cap_max = 99999
	if usato + tot > cap_max:
		return ""
	var categoria := "max"
	if int(nido["lf_pieno"]) + tot <= int(lf[1]) or int(lf[0]) >= 999:
		categoria = "min"
		nido["lf_pieno"] = int(nido["lf_pieno"]) + tot
	elif usato + tot <= int(lf[0]):
		categoria = "norm"
	nido["lf_usato"] = usato + tot
	for g in gruppi:
		_add(nido["pronti"], g["tipo"] + "|" + g["arma"], -int(g["q"]))
	var fid := _new_id("F")
	var t: int = st["turno"]
	var af := {"id": fid, "lato": s, "num": _num_af(s), "hex": [h.x, h.y], "quota": str(l.get("quota", "A")),
		"gruppi": [], "casa": nid, "missione": l.get("missione", {"tipo": "manuale"}).duplicate(true),
		"esposta": false, "in_volo_di": "", "lanciata": t, "lancio": categoria, "cerca_ok": false,
		"mosso": 0, "fuori": {}, "nuova": true}
	for g in gruppi:
		var rf: int = int(FTData.aerei[g["tipo"]]["rf"])
		if g["arma"] == "" and not (g["tipo"] in ["Catalina", "Mavis", "Emily"]):
			rf += 1
		af["gruppi"].append({"tipo": g["tipo"], "q": int(g["q"]), "arma": g["arma"], "entro": t + rf - 1})
	# le armate non salgono in quota nel turno di decollo
	if _af_armata(af) and af["quota"] == "A":
		af["quota_dopo"] = "A"
		af["quota"] = "B"
	if str(af["missione"].get("tipo", "")) == "cap" and not st["basi"].has(nid):
		af["in_volo_di"] = nid
	st["af"][fid] = af
	# basi fuori mappa: l'AF resta «in volo» finché non arriva al bordo (pista)
	return fid


func _num_af(s: String) -> int:
	var usati := {}
	for fid in st["af"]:
		if st["af"][fid]["lato"] == s:
			usati[int(st["af"][fid]["num"])] = true
	for i in range(1, 99):
		if not usati.has(i):
			return i
	return 99


func _af_armata(af: Dictionary) -> bool:
	for g in af["gruppi"]:
		if g["arma"] != "" and g["arma"] != "x":
			return true
	return false


## Mantiene la pattuglia aerea (CAP) sopra un nido: lancia i caccia pronti che mancano.
func _cap_auto(nid: String) -> void:
	var nido: Dictionary = st["nidi"][nid]
	var vuole: int = int(nido["cap"])
	var h := nido_hex(nid)
	if h.x < -100:
		return
	if bool(nido.get("no_lanci", false)):
		return
	# caccia già in pattuglia sopra il nido
	var in_aria := 0
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if af["lato"] == nido["lato"] and str(af["missione"].get("tipo", "")) == "cap" and str(af["missione"].get("nido", "")) == nid:
			for g in af["gruppi"]:
				# chi deve atterrare entro un turno conta come già sostituito
				if int(g["entro"]) > int(st["turno"]) + 1:
					in_aria += int(g["q"])
	var manca := vuole - in_aria
	if manca <= 0:
		return
	var gruppi := []
	for k in nido["pronti"].keys():
		if manca <= 0:
			break
		var parts: PackedStringArray = k.split("|")
		var tipo: String = parts[0]
		var arma: String = parts[1] if parts.size() > 1 else ""
		if arma != "" or not _ruoli(tipo).contains("I") or _ruoli(tipo).contains("I*"):
			continue
		var q: int = mini(manca, int(nido["pronti"][k]))
		gruppi.append({"tipo": tipo, "q": q, "arma": ""})
		manca -= q
	if gruppi.is_empty():
		return
	_forma_af(nido["lato"], {"n": nid, "gruppi": gruppi, "quota": "A", "missione": {"tipo": "cap", "nido": nid}})


func _dividi_tf(s: String, d: Dictionary) -> void:
	var tid: String = str(d.get("tf", ""))
	if not st["tf"].has(tid) or st["tf"][tid]["lato"] != s:
		return
	var tf: Dictionary = st["tf"][tid]
	var sposta := []
	for nid in d.get("navi", []):
		if nid in tf["navi"]:
			sposta.append(nid)
	if sposta.is_empty() or sposta.size() >= tf["navi"].size():
		return
	var ntid := _new_id("T")
	var nt := {"id": ntid, "lato": s, "num": _num_tf(s), "hex": tf["hex"].duplicate(), "navi": [], "rotta": [],
		"esposta": tf["esposta"], "ancorata": false, "contegno": tf["contegno"], "entra": -1, "mosso": 0, "pedina": "", "sbarco": 0}
	for nid in sposta:
		tf["navi"].erase(nid)
		nt["navi"].append(nid)
		st["navi"][nid]["tf"] = ntid
	st["tf"][ntid] = nt
	add_log(s, "La TF %d si divide: nasce la TF %d." % [tf["num"], nt["num"]])


func _num_tf(s: String) -> int:
	var usati := {}
	for tid in st["tf"]:
		if st["tf"][tid]["lato"] == s:
			usati[int(st["tf"][tid]["num"])] = true
	for i in range(1, 99):
		if not usati.has(i):
			return i
	return 99


func _unisci_tf(s: String, u: Array) -> void:
	if u.size() < 2:
		return
	var a: String = str(u[0])
	var b: String = str(u[1])
	if not (st["tf"].has(a) and st["tf"].has(b)) or a == b:
		return
	if st["tf"][a]["lato"] != s or st["tf"][b]["lato"] != s or tf_hex(a) != tf_hex(b):
		return
	var max_navi := 15 if s == "A" else 10
	if st["tf"][a]["navi"].size() + st["tf"][b]["navi"].size() > max_navi + 10:
		return
	for nid in st["tf"][b]["navi"]:
		st["tf"][a]["navi"].append(nid)
		st["navi"][nid]["tf"] = a
	add_log(s, "La TF %d si unisce alla TF %d." % [st["tf"][b]["num"], st["tf"][a]["num"]])
	st["tf"].erase(b)


func _ancora(tid: String, si: bool) -> void:
	var tf: Dictionary = st["tf"][tid]
	if si and FTData.ter(tf_hex(tid)) != "p":
		return
	if si == bool(tf["ancorata"]):
		return
	tf["ancorata"] = si
	tf["ancora_turno"] = st["turno"]
	for nid in tf["navi"]:
		st["navi"][nid]["ancorata"] = si
	add_log(tf["lato"], "La TF %d %s." % [tf["num"], "getta l'ancora" if si else "salpa le ancore"])


# ================================================================ movimento delle TF

func tf_mf(tid: String) -> int:
	var tf: Dictionary = st["tf"][tid]
	if tf.get("fuori", false):
		return 0
	if tf["ancorata"] or int(tf.get("ancora_turno", -9)) == int(st["turno"]):
		return 0
	if tempesta(tf_hex(tid)):
		return 0
	var m := 99
	for nid in tf["navi"]:
		var n: Dictionary = st["navi"][nid]
		var v: int = n["mv"]
		if int(n.get("stop_turni", 0)) > 0:
			v = 0
		elif n["hits"] >= n["danno"] - 1 and n["danno"] >= 3:
			v = 0  # nave «averiada»: ferma
		elif n["hits"] * 2 >= n["danno"] or n.get("mezza", false):
			if v >= 2:
				v = v / 2
			else:
				v = 1 if int(st["turno"]) % 2 == 0 else 0
		m = mini(m, v)
	return 0 if m == 99 else m


func _movimento_tf(ordini: Dictionary) -> void:
	# pedinamenti (11): chi pedina si muove dopo la TF pedinata
	var pedinate := {}
	for s in LATI:
		var ped: Dictionary = st["lati"][s].get("pedina", {})
		for chi in ped:
			var bers: String = str(ped[chi])
			if not st["tf"].has(bers) or st["tf"][bers]["lato"] == s:
				continue
			var k := "T:" + bers
			var cond: int = int(st["noti"][s].get(bers, {}).get("cond", 0))
			if cond < 2:
				continue
			var roll := d6()
			if notte():
				roll += 3
			if meteo(tf_hex(bers)) == 1:
				roll += 1
			var ok := roll <= 5 and not tempesta(tf_hex(bers))
			pedinate[chi] = {"bers": bers, "ok": ok}
			add_log(s, "Pedinamento della TF nemica: %s." % ("riuscito" if ok else "fallito"))
	# movimento simultaneo passo per passo: tutte le TF fanno un esagono alla volta
	var maxp := 0
	var mf := {}
	for tid in st["tf"]:
		mf[tid] = tf_mf(tid)
		maxp = maxi(maxp, mf[tid])
	for passo in maxp:
		var mosse := false
		for tid in st["tf"].keys():
			var tf: Dictionary = st["tf"][tid]
			if pedinate.has(tid):
				continue
			if passo >= int(mf[tid]):
				continue
			var rotta: Array = tf["rotta"]
			if passo >= rotta.size():
				continue
			var nh := vh(rotta[passo])
			if FTData.dist(nh, tf_hex(tid)) != 1 or not FTData.navigabile(nh):
				tf["rotta"] = rotta.slice(0, passo)
				continue
			tf["hex"] = [nh.x, nh.y]
			tf["mosso"] = int(tf["mosso"]) + 1
			mosse = true
			if tempesta(nh):
				mf[tid] = passo + 1
		if mosse:
			_osserva_tutto("")
	# chi pedina raggiunge la TF pedinata (se ce la fa con il suo movimento)
	for chi in pedinate:
		if not pedinate[chi]["ok"]:
			continue
		var bh := tf_hex(pedinate[chi]["bers"])
		if st["tf"].has(chi):
			var path := FTData.percorso(tf_hex(chi), bh, true)
			var m: int = tf_mf(chi)
			var i := 0
			for h in path:
				if i >= m:
					break
				st["tf"][chi]["hex"] = [h.x, h.y]
				i += 1
		elif st["af"].has(chi):
			var af: Dictionary = st["af"][chi]
			var path2 := FTData.percorso(af_hex(chi), bh, false)
			var m2 := af_mf(chi)
			var j := 0
			for h in path2:
				if j >= m2:
					break
				af["hex"] = [h.x, h.y]
				j += 1
			af["mosso"] = 99  # non si muove nella fase aerea
	_osserva_tutto("")


# ================================================================ movimento aereo

## Fattore di movimento dell'AF in questo turno (il più lento; -1 se vola a bassa quota; ridotto al decollo).
func af_mf(fid: String) -> int:
	var af: Dictionary = st["af"][fid]
	var m := 99
	for g in af["gruppi"]:
		m = mini(m, int(FTData.aerei[g["tipo"]]["mf"]))
	if m == 99:
		return 0
	if af["quota"] == "B":
		m -= 1
	if int(af.get("lanciata", -1)) == int(st["turno"]):
		match str(af.get("lancio", "min")):
			"norm":
				m = (m + 1) / 2
			"max":
				m = 0
	# CAP in volo sopra la portaerei: il movimento della TF si sottrae
	if str(af.get("in_volo_di", "")) != "":
		var n: Dictionary = st["navi"].get(af["in_volo_di"], {})
		if not n.is_empty() and n["tf"] != "":
			m -= int(st["tf"][n["tf"]]["mosso"])
	return maxi(0, m)


func af_fattori(fid: String) -> int:
	var t := 0
	for g in st["af"][fid]["gruppi"]:
		t += int(g["q"])
	return t


## L'ultimo turno in cui l'AF deve atterrare (il gruppo con meno autonomia).
func af_entro(fid: String) -> int:
	var m := 9999
	for g in st["af"][fid]["gruppi"]:
		m = mini(m, int(g["entro"]))
	return m


func _preparazione_aria(s: String) -> void:
	# AF nuove del turno: armate a bassa quota; le missioni automatiche scelgono la rotta
	pass


## Ordini aerei di un lato: {fid: {rotta, quota, cerca, atterra, missione, bombe_via}}.
## Le AF con missione automatica e senza ordini espliciti si muovono da sole (pilota automatico).
func _movimento_aereo(s: String, mosse: Dictionary) -> void:
	if mosse == null:
		mosse = {}
	var nuove_missioni: Dictionary = mosse.get("_missioni", {})
	for fid in nuove_missioni:
		if st["af"].has(fid) and st["af"][fid]["lato"] == s:
			st["af"][fid]["missione"] = nuove_missioni[fid].duplicate(true)
	var ids := []
	for fid in st["af"]:
		if st["af"][fid]["lato"] == s:
			ids.append(fid)
	for fid in ids:
		if not st["af"].has(fid):
			continue
		var af: Dictionary = st["af"][fid]
		if int(af.get("mosso", 0)) >= 99:
			continue
		var o: Dictionary = mosse.get(fid, {})
		if o.is_empty():
			o = PILOT.ordini_af(self, fid)
		_muovi_af(fid, o)
	# atterraggi obbligati e perdite per carburante
	for fid in st["af"].keys():
		var af2: Dictionary = st["af"][fid]
		if af2["lato"] != s:
			continue
		_controlla_carburante(fid)
	for fid in st["af"].keys():
		if st["af"].has(fid):
			st["af"][fid].erase("nuova")
	_osserva_tutto("")


func _muovi_af(fid: String, o: Dictionary) -> void:
	var af: Dictionary = st["af"][fid]
	var s: String = af["lato"]
	if o.has("quota"):
		var q: String = str(o["quota"])
		if q == "A" and _af_armata(af) and int(af.get("lanciata", -1)) == int(st["turno"]):
			q = "B"
		af["quota"] = q
	# la ricerca si dichiara prima di muovere (7.3): solo AF già sul tavolo a inizio turno
	var cerca := bool(o.get("cerca", false))
	af["cerca_ok"] = false
	if cerca and not bool(af.get("nuova", false)) and str(af.get("in_volo_di", "")) == "" and not af.get("fuori_mappa", false):
		var h0 := af_hex(fid)
		if tempesta(h0):
			cerca = false
		else:
			var r := d6()
			if notte():
				r += 3
			if meteo(h0) >= 1 and af["quota"] == "A":
				r += 1
			af["cerca_ok"] = r <= 4
			af["esposta"] = true
			if not af["cerca_ok"]:
				add_log(s, "AF %d: ricerca senza esito in questo turno." % af["num"], "minore")
	if bool(o.get("bombe_via", false)):
		for g in af["gruppi"]:
			if g["arma"] != "":
				g["arma"] = "x"
	var rotta: Array = o.get("rotta", [])
	var mf := af_mf(fid)
	if rotta.size() > 0 and str(af.get("in_volo_di", "")) != "":
		# lascia la pattuglia sopra la portaerei
		af["hex"] = [af_hex(fid).x, af_hex(fid).y]
		af["in_volo_di"] = ""
	var passi := 0
	var bassa_spesa := false
	for h in rotta:
		var nh := vh(h)
		if passi >= mf:
			break
		var cur := af_hex(fid)
		if FTData.dist(cur, nh) != 1 or not FTData.volabile(nh):
			break
		if tempesta(nh) and not (o.get("atterra", "") != "" and nido_hex(str(o.get("atterra", ""))) == nh):
			break
		if FTData.montagna(nh) and af["quota"] == "B":
			break
		af["hex"] = [nh.x, nh.y]
		passi += 1
		if af["quota"] == "B" and not bassa_spesa:
			bassa_spesa = true
		af["mosso"] = passi
		if af["cerca_ok"] or af["esposta"]:
			af["esposta"] = true
		_osserva_movimento(fid)
		if not st["af"].has(fid):
			return
		# intercettazione speciale (14.13.2)
		COMBAT.intercettazione_movimento(self, fid)
		if not st["af"].has(fid) or af_fattori(fid) <= 0:
			return
	# CAP: resta in volo sopra la portaerei
	if str(af["missione"].get("tipo", "")) == "cap" and str(af.get("in_volo_di", "")) == "" and rotta.is_empty():
		var nid: String = str(af["missione"].get("nido", ""))
		if st["navi"].has(nid) and not st["navi"][nid]["affondata"] and nido_hex(nid) == af_hex(fid):
			af["in_volo_di"] = nid
	if o.has("quota_fine"):
		af["quota"] = str(o["quota_fine"])
	# atterraggio a fine movimento
	var dove: String = str(o.get("atterra", ""))
	if dove != "":
		if not _atterra(fid, dove, passi) and st["af"].has(fid):
			# non riesce ad atterrare adesso: resta in volo sopra la portaerei (casella In volo)
			if st["navi"].has(dove) and nido_hex(dove) == af_hex(fid) and nido_lato(dove) == s:
				af["in_volo_di"] = dove
				af["quota"] = "B"


## Prova ad atterrare: il nido deve essere nell'esagono, accettare gli aerei e avere fattore di lancio.
## Con il fattore minimo l'AF può aver usato tutto il movimento, con il normale metà, con il massimo deve
## essere partita dall'esagono (14.8).
func _atterra(fid: String, nid: String, passi: int) -> bool:
	if not st["af"].has(fid) or not st["nidi"].has(nid):
		return false
	var af: Dictionary = st["af"][fid]
	if nido_lato(nid) != af["lato"] or nido_hex(nid) != af_hex(fid):
		return false
	if bool(st["nidi"][nid].get("no_lanci", false)):
		return false
	var lf := nido_lf(nid)
	if int(lf[0]) <= 0 and int(lf[1]) <= 0:
		return false
	for g in af["gruppi"]:
		if not nido_accetta(nid, g["tipo"]):
			return false
	var nido: Dictionary = st["nidi"][nid]
	var tot := af_fattori(fid)
	var illimitato := int(lf[0]) >= 999
	var cap := tot
	if not illimitato:
		var r_min: int = int(lf[1]) - int(nido["lf_pieno"])
		var r_norm: int = int(lf[0]) - int(nido["lf_usato"])
		var r_max: int = 2 * int(lf[0]) - int(nido["lf_usato"])
		if passi == 0:
			cap = maxi(r_max, r_min)
		elif passi <= (af_mf_base(fid) + 1) / 2:
			cap = maxi(r_norm, r_min)
		else:
			cap = r_min
		cap = mini(tot, maxi(0, cap))
		if cap <= 0:
			return false
	var mc := nido_mc(nid)
	var posto := mc - nido_aerei(nid)
	var accettati := 0
	var persi := 0
	var atterrati := 0
	var notturno := notte()
	var temp := tempesta(af_hex(fid))
	var soglia := 5 if st["navi"].has(nid) else 4
	var restano := []
	# atterrano prima i bombardieri, poi i caccia
	var ordine: Array = af["gruppi"].duplicate()
	ordine.sort_custom(func(x, y): return int(_ruoli(x["tipo"]).contains("E")) < int(_ruoli(y["tipo"]).contains("E")))
	for g in ordine:
		var q: int = int(g["q"])
		var libero: int = cap - atterrati
		if libero <= 0:
			restano.append(g)
			continue
		if q > libero:
			var resto: Dictionary = g.duplicate()
			resto["q"] = q - libero
			restano.append(resto)
			q = libero
		atterrati += q
		var armato: bool = g["arma"] != "" and g["arma"] != "x"
		var ok := q
		if notturno or temp or armato:
			ok = 0
			for i in q:
				var r := d6()
				if temp:
					r -= 1
				if armato:
					r -= 1
				if notturno and bool(st["speciali"].get("wasp_notte", false)) and str(st["navi"].get(nid, {}).get("nome", "")) == "Wasp" and g["tipo"] in ["Dauntless", "Avenger"]:
					r += 2
				if r >= soglia:
					ok += 1
			if q - ok > 0:
				persi += q - ok
				_perdita(af["lato"], g["tipo"], q - ok, false)
		if mc < 999 and ok > posto - accettati:
			var eccesso: int = ok - maxi(0, posto - accettati)
			ok -= eccesso
			persi += eccesso
			_perdita(af["lato"], g["tipo"], eccesso, true)
		_add(nido["jl"], g["tipo"], ok)
		accettati += ok
	if not illimitato:
		if atterrati <= int(lf[1]) - int(nido["lf_pieno"]):
			nido["lf_pieno"] = int(nido["lf_pieno"]) + atterrati
		nido["lf_usato"] = int(nido["lf_usato"]) + atterrati
	var txt := "AF %d atterra su %s" % [af["num"], nido_nome(nid)]
	if not restano.is_empty():
		txt = "AF %d: %d fattori atterrano su %s, gli altri aspettano in volo" % [af["num"], atterrati, nido_nome(nid)]
	if persi > 0:
		txt += " (%d fattori persi nell'atterraggio)" % persi
	add_log(af["lato"], txt + ".", "minore" if persi == 0 else "")
	if restano.is_empty():
		st["af"].erase(fid)
		return true
	af["gruppi"] = restano
	return false


func af_mf_base(fid: String) -> int:
	var af: Dictionary = st["af"][fid]
	var m := 99
	for g in af["gruppi"]:
		m = mini(m, int(FTData.aerei[g["tipo"]]["mf"]))
	return 0 if m == 99 else m


## Fine dell'autonomia: chi non è atterrato entro il turno stabilito si perde (10 PV a testa all'avversario).
func _controlla_carburante(fid: String) -> void:
	if not st["af"].has(fid):
		return
	var af: Dictionary = st["af"][fid]
	var t: int = st["turno"]
	var rimasti := []
	var persi := 0
	for g in af["gruppi"]:
		if int(g["entro"]) <= t:
			# ultima occasione: se è sopra un nido amico atterra comunque (miglior tentativo)
			persi += int(g["q"])
			_perdita(af["lato"], g["tipo"], int(g["q"]), true)
		else:
			rimasti.append(g)
	if persi > 0:
		add_log(af["lato"], "AF %d: %d fattori aerei finiscono il carburante e si perdono in mare." % [af["num"], persi])
	af["gruppi"] = rimasti
	if rimasti.is_empty():
		st["af"].erase(fid)


## Registra la perdita di fattori aerei e assegna i punti vittoria all'avversario.
func _perdita(lato: String, tipo: String, q: int, inutile: bool) -> void:
	if q <= 0:
		return
	_add(st["lati"][lato]["perdite_oggi"], tipo, q)
	var pv := q * (10 if inutile else 2)
	st["lati"][nemico(lato)]["vp"] = int(st["lati"][nemico(lato)]["vp"]) + pv


func pv(lato: String, q: int) -> void:
	st["lati"][lato]["vp"] = int(st["lati"][lato]["vp"]) + q


# ================================================================ osservazione

## Chiave usata nelle conoscenze: id della TF o dell'AF nemica.
## noti[lato][id] = {tipo, hex, cond (0 = solo il segnalino sul tavolo), info, turno}
func _osserva_tutto(muove: String) -> void:
	var nuovi := {"A": {}, "J": {}}
	var day := not notte()
	for s in LATI:
		var e := nemico(s)
		var osservatori := _osservatori(s, muove)
		# bersagli: TF e AF nemiche
		for tid in st["tf"]:
			var tf: Dictionary = st["tf"][tid]
			if tf["lato"] != e or tf.get("fuori", false) or tf["navi"].is_empty():
				continue
			var th := tf_hex(tid)
			if tempesta(th):
				continue
			var c := 0
			for ob in osservatori:
				c = maxi(c, _cond(ob, th, "tf", "", day))
				if c >= 3:
					break
			if c > 0:
				nuovi[s][tid] = c
		for fid in st["af"]:
			var af: Dictionary = st["af"][fid]
			if af["lato"] != e or af.get("fuori_mappa", false):
				continue
			var ah := af_hex(fid)
			if tempesta(ah):
				continue
			var c2 := 0
			for ob in osservatori:
				c2 = maxi(c2, _cond(ob, ah, "af", af["quota"], day))
				if c2 >= 3:
					break
			# AF in volo sopra la propria TF: si vede solo se si vede l'esagono da vicino
			if c2 > 0:
				nuovi[s][fid] = c2
	for s in LATI:
		var e2 := nemico(s)
		var noti: Dictionary = st["noti"][s]
		# chi è osservato va sul tavolo
		for k in nuovi[s]:
			if st["tf"].has(k):
				st["tf"][k]["esposta"] = true
				if s == "J" and st["tf"][k]["lato"] == "A":
					if st.get("avvistata_nave_A_turno", -1) < 0:
						st["avvistata_nave_A_turno"] = st["turno"]
			elif st["af"].has(k):
				st["af"][k]["esposta"] = true
		var nn := {}
		for tid in st["tf"]:
			var tf2: Dictionary = st["tf"][tid]
			if tf2["lato"] != e2 or tf2["navi"].is_empty() or tf2.get("fuori", false):
				continue
			var c3: int = int(nuovi[s].get(tid, 0))
			var esp := bool(tf2["esposta"]) or bool(tf2.get("in_vista", false))
			if c3 > 0 or esp:
				var prev: Dictionary = noti.get(tid, {})
				var cmax := c3
				# nel corso del turno la condizione non peggiora
				if not prev.is_empty() and int(prev.get("turno", -1)) == int(st["turno"]) and vh(prev["hex"]) == tf_hex(tid):
					cmax = maxi(cmax, int(prev.get("cond", 0)))
				nn[tid] = {"tipo": "tf", "hex": st["tf"][tid]["hex"].duplicate(), "cond": cmax, "turno": st["turno"], "info": _info_tf(tid, cmax, s)}
		for fid in st["af"]:
			var af2: Dictionary = st["af"][fid]
			if af2["lato"] != e2:
				continue
			var c4: int = int(nuovi[s].get(fid, 0))
			if c4 > 0 or bool(af2["esposta"]):
				var prev2: Dictionary = noti.get(fid, {})
				var cmax2 := c4
				if not prev2.is_empty() and int(prev2.get("turno", -1)) == int(st["turno"]) and vh(prev2["hex"]) == af_hex(fid):
					cmax2 = maxi(cmax2, int(prev2.get("cond", 0)))
				nn[fid] = {"tipo": "af", "hex": [af_hex(fid).x, af_hex(fid).y], "cond": cmax2, "turno": st["turno"], "info": _info_af(fid, cmax2)}
		# memoria: ultimo avvistamento di ogni unità
		for k in nn:
			if int(nn[k]["cond"]) >= 1:
				st["memoria"][s][k] = nn[k].duplicate(true)
		st["noti"][s] = nn


## Unità di un lato che possono osservare: basi, TF sul tavolo, AF sul tavolo.
func _osservatori(s: String, muove: String) -> Array:
	var out := []
	for bid in st["basi"]:
		var b: Dictionary = st["basi"][bid]
		if b["lato"] != s or b["fuori"]:
			continue
		out.append({"k": "base", "h": vh(b["hex"]), "radar": bool(b["radar"]), "quota": ""})
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		if tf["lato"] != s or tf["navi"].is_empty() or tf.get("fuori", false):
			continue
		if not (bool(tf["esposta"]) or bool(tf.get("in_vista", false))):
			continue
		var th := tf_hex(tid)
		if tempesta(th):
			continue
		var radar := false
		for nid in tf["navi"]:
			if st["navi"][nid]["radar"]:
				radar = true
		out.append({"k": "tf", "h": th, "radar": radar, "quota": ""})
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if af["lato"] != s or not bool(af["esposta"]) or af.get("fuori_mappa", false):
			continue
		if muove == s and not bool(af["cerca_ok"]):
			continue
		var ah := af_hex(fid)
		if tempesta(ah):
			continue
		out.append({"k": "af", "h": ah, "radar": false, "quota": af["quota"]})
	return out


## Numero di condizione (0-3) dalla tabella di osservazione.
func _cond(ob: Dictionary, h: Vector2i, bers: String, quota_bers: String, day: bool) -> int:
	var d := FTData.dist(ob["h"], h)
	var nuv := meteo(h) >= 1
	var c := 0
	var k: String = ob["k"]
	if k == "base" or k == "tf":
		if bers == "af":
			if day:
				c = _tab([3, 2, 1] if not nuv else [2, 1], d)
			else:
				c = _tab([1] if not nuv else [], d)
		else:
			if day:
				c = _tab([3, 2, 1], d)
			else:
				c = _tab([1], d)
		if ob["radar"] and bers == "af" and quota_bers == "A":
			c = maxi(c, _tab([3, 2, 1, 1] if (day and not nuv) else [2, 2, 1, 1], d))
	else:
		if bers == "af":
			if day:
				c = _tab([3, 2, 1] if not nuv else [2, 1], d)
			else:
				c = _tab([1] if not nuv else [], d)
		else:
			if ob["quota"] == "A":
				if day:
					c = _tab([3, 2, 1] if not nuv else [2, 1], d)
				else:
					c = _tab([1] if not nuv else [], d)
			else:
				if day:
					c = _tab([3, 1], d)
				else:
					c = _tab([2] if not nuv else [1], d)
	return c


static func _tab(row: Array, d: int) -> int:
	return int(row[d]) if d < row.size() else 0


## Durante il movimento di un'AF: chi muove osserva e viene osservato esagono per esagono.
## Per non rifare tutto a ogni passo si guardano solo le unità entro 3 esagoni.
func _osserva_movimento(fid: String) -> void:
	var af: Dictionary = st["af"][fid]
	var m: String = af["lato"]
	var e := nemico(m)
	var ah := af_hex(fid)
	var day := not notte()
	if tempesta(ah):
		return
	# chi muove osserva (se ha superato la ricerca)
	if bool(af["cerca_ok"]):
		var ob := {"k": "af", "h": ah, "radar": false, "quota": af["quota"]}
		for tid in st["tf"]:
			var tf: Dictionary = st["tf"][tid]
			if tf["lato"] != e or tf["navi"].is_empty() or tf.get("fuori", false):
				continue
			var th := tf_hex(tid)
			if FTData.dist(th, ah) > 3 or tempesta(th):
				continue
			var c := _cond(ob, th, "tf", "", day)
			if c > 0:
				_segna_visto(m, tid, c)
		for f2 in st["af"]:
			var a2: Dictionary = st["af"][f2]
			if a2["lato"] != e:
				continue
			var h2 := af_hex(f2)
			if FTData.dist(h2, ah) > 3 or tempesta(h2):
				continue
			var c2 := _cond(ob, h2, "af", a2["quota"], day)
			if c2 > 0:
				_segna_visto(m, f2, c2)
	# chi non muove osserva l'AF
	var best := 0
	for ob2 in _osservatori(e, m):
		if FTData.dist(ob2["h"], ah) > 3:
			continue
		best = maxi(best, _cond(ob2, ah, "af", af["quota"], day))
	if best > 0:
		_segna_visto(e, fid, best)


func _segna_visto(s: String, k: String, c: int) -> void:
	var noti: Dictionary = st["noti"][s]
	var prev: Dictionary = noti.get(k, {})
	var tipo := "tf" if st["tf"].has(k) else "af"
	var h: Vector2i = tf_hex(k) if tipo == "tf" else af_hex(k)
	if not prev.is_empty() and int(prev.get("turno", -1)) == int(st["turno"]) and vh(prev["hex"]) == h:
		c = maxi(c, int(prev.get("cond", 0)))
	var info := _info_tf(k, c, s) if tipo == "tf" else _info_af(k, c)
	noti[k] = {"tipo": tipo, "hex": [h.x, h.y], "cond": c, "turno": st["turno"], "info": info}
	st["memoria"][s][k] = noti[k].duplicate(true)
	if tipo == "tf":
		st["tf"][k]["esposta"] = true
		if s == "J" and st.get("avvistata_nave_A_turno", -1) < 0:
			st["avvistata_nave_A_turno"] = st["turno"]
	else:
		st["af"][k]["esposta"] = true


## Descrizione di quello che si vede di una TF nemica, secondo la condizione.
func _info_tf(tid: String, cond: int, osservatore: String) -> Dictionary:
	var tf: Dictionary = st["tf"][tid]
	var cv := 0
	var mag := 0
	var mino := 0
	var nomi := []
	for nid in tf["navi"]:
		var n: Dictionary = st["navi"][nid]
		if n["tipo"] in ["CV", "CVL"]:
			cv += 1
		elif n["tipo"] in ["AV", "CAV", "BB", "CA", "CL", "CLA", "BC"]:
			mag += 1
		else:
			mino += 1
		nomi.append(n["nome"] + " " + n["tipo"])
	var tot: int = tf["navi"].size()
	var out := {"cond": cond}
	if cond >= 3:
		out["portaerei"] = cv; out["maggiori"] = mag; out["minori"] = mino; out["navi"] = tot
	elif cond == 2:
		# il giocatore osservato può alterare il numero del 50%: qui lo fa il caso, in modo stabile nel turno
		var h := hash(tid + str(st["turno"]) + osservatore)
		var f := 0.5 + float(absi(h) % 101) / 100.0
		out["navi_circa"] = maxi(1, roundi(tot * f))
		out["ha_portaerei"] = cv > 0; out["ha_maggiori"] = mag > 0; out["ha_minori"] = mino > 0
	if bool(tf.get("svelata", false)):
		out["nomi"] = nomi
	out["ancorata"] = bool(tf["ancorata"]) and cond >= 3
	return out


func _info_af(fid: String, cond: int) -> Dictionary:
	var af: Dictionary = st["af"][fid]
	var arm := 0
	var dis := 0
	for g in af["gruppi"]:
		if g["arma"] != "":
			arm += int(g["q"])
		else:
			dis += int(g["q"])
	var out := {"cond": cond}
	if cond >= 3:
		out["armati"] = arm; out["scarichi"] = dis; out["quota"] = af["quota"]
	elif cond == 2:
		var h := hash(fid + str(st["turno"]))
		var f := 0.5 + float(absi(h) % 101) / 100.0
		out["aerei_circa"] = maxi(1, roundi((arm + dis) * f))
		out["armati_si"] = arm > 0; out["scarichi_si"] = dis > 0
	return out


# ================================================================ fine turno

func _sbarchi() -> void:
	var sp: Dictionary = st["speciali"]
	var sb: Dictionary = sp.get("sbarco", {})
	for s in LATI:
		if not sb.has(s):
			continue
		var regola: Dictionary = sb[s]
		var validi := {}
		for h in regola.get("hex", []):
			validi[vh(h)] = true
		if regola.has("isola"):
			for h in FTData.isole.get(regola["isola"], []):
				validi[vh(h)] = true
		for h in regola.get("escludi", []):
			validi.erase(vh(h))
		for tid in st["tf"]:
			var tf: Dictionary = st["tf"][tid]
			if tf["lato"] != s or not tf["ancorata"] or not validi.has(tf_hex(tid)):
				continue
			# lo scarico inizia il turno dopo l'ancoraggio
			if int(tf.get("ancora_turno", -9)) >= int(st["turno"]):
				continue
			for nid in tf["navi"]:
				var n: Dictionary = st["navi"][nid]
				if n["tipo"] in ["AP", "APD"] and int(n["carico"]) > 0 and not n["affondata"]:
					n["carico"] = int(n["carico"]) - 1
					var q := 3 if n["tipo"] == "AP" else 1
					pv(s, q)
					st["sbarchi"][s] = int(st["sbarchi"][s]) + q
			if true:
				add_log(s, "La TF %d scarica truppe e rifornimenti (%d punti sbarcati in tutto)." % [tf["num"], st["sbarchi"][s]], "minore")
		# Gili-Gili conquistata
		if s == "J" and st["scen"].begins_with("salomone") and int(st["sbarchi"]["J"]) >= 50 and st["basi"].has("gili_gili") and st["basi"]["gili_gili"]["lato"] == "A":
			var b: Dictionary = st["basi"]["gili_gili"]
			b["lato"] = "J"
			b["hits"] = 0
			b["lf"] = b["lf0"].duplicate()
			st["nidi"]["gili_gili"] = _nido_vuoto("gili_gili", "base", "J")
			add_log("*", "Gili-Gili cade in mano giapponese.")
		if sp.get("sbarco", {}).has(s) and regola.has("hex") and str(regola.get("nome", "")) == "Port Moresby" and int(st["sbarchi"][s]) >= 150:
			_vittoria_immediata(s, "Sbarcati 150 punti a Port Moresby.")
		if st["scen"] == "guadalcanal" and s == "J" and int(st["sbarchi"]["J"]) >= 100:
			_vittoria_immediata("J", "Sbarcati 100 punti su Guadalcanal.")


func _riparazioni() -> void:
	for bid in st["basi"]:
		var b: Dictionary = st["basi"][bid]
		if int(b["hits"]) <= 0 or st["attaccate"].has(bid):
			continue
		var r := 1
		if bid == "henderson" and bool(st["speciali"].get("henderson_ripara2", false)) and not notte():
			r = 2
		for i in r:
			if int(b["hits"]) <= 0:
				break
			b["hits"] = int(b["hits"]) - 1
			b["lf"] = [mini(int(b["lf0"][0]), int(b["lf"][0]) + 2), mini(int(b["lf0"][1]), int(b["lf"][1]) + 1)]
			if bid in ["tulagi", "shortland", "ndeni"]:
				b["lf"] = [mini(int(b["lf0"][0]), int(b["lf"][0]) - 1), int(b["lf"][1])]
			b["aaf"] = mini(int(b["aaf0"]), int(b["aaf"]) + 1)
			b["sf"] = mini(int(b["sf0"]), int(b["sf"]) + 1)
	# punti per le basi fuori uso
	for bid in st["basi"]:
		var b2: Dictionary = st["basi"][bid]
		if b2["fuori"]:
			continue
		if int(b2["lf"][0]) <= 0:
			var q := 10 if bid in ["henderson", "rabaul"] else 5
			pv(nemico(b2["lato"]), q)


func _fine_turno() -> void:
	# chi non è più osservato può lasciare il tavolo (7.7)
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		var e := nemico(tf["lato"])
		if not st["noti"][e].has(tid) or int(st["noti"][e][tid].get("cond", 0)) == 0:
			tf["esposta"] = false
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		var e2 := nemico(af["lato"])
		if int(st["noti"][e2].get(fid, {}).get("cond", 0)) == 0:
			af["esposta"] = false
	for nid in st["navi"]:
		var n: Dictionary = st["navi"][nid]
		if int(n.get("stop_turni", 0)) > 0:
			n["stop_turni"] = int(n["stop_turni"]) - 1
	# ordine: le AF armate al decollo salgono in quota dal turno dopo
	for fid in st["af"]:
		var af2: Dictionary = st["af"][fid]
		if af2.has("quota_dopo"):
			af2["quota"] = af2["quota_dopo"]
			af2.erase("quota_dopo")


func _vittoria_immediata(s: String, motivo: String) -> void:
	if st["fine"]:
		return
	st["fine"] = true
	st["risultato"] = {"vincitore": s, "motivo": motivo, "vp": {"A": st["lati"]["A"]["vp"], "J": st["lati"]["J"]["vp"]}}
	add_log("*", "Fine della partita: vince %s. %s" % [NOME_LATO[s], motivo])
	game_over.emit(st["risultato"])


func _controlla_vittoria() -> void:
	if st["fine"]:
		return
	var sc := FTData.scenario(st["scen"])
	var v: Dictionary = sc.get("vittoria", {})
	var va: int = st["lati"]["A"]["vp"]
	var vj: int = st["lati"]["J"]["vp"]
	if v.get("tipo", "") == "rabaul":
		for nid in st["navi"]:
			var n: Dictionary = st["navi"][nid]
			if n["nome"] == "Lexington" and n["affondata"]:
				_vittoria_immediata("J", "Il Lexington è affondato.")
				return
	var auto: int = int(v.get("auto", 0))
	if auto > 0 and int(st["ora"]) == 24 and absi(va - vj) >= auto:
		_vittoria_immediata("A" if va > vj else "J", "Vittoria automatica: %d punti di scarto." % absi(va - vj))


func _fine_partita() -> void:
	if st["fine"]:
		return
	var sc := FTData.scenario(st["scen"])
	var v: Dictionary = sc.get("vittoria", {})
	var va: int = st["lati"]["A"]["vp"]
	var vj: int = st["lati"]["J"]["vp"]
	var minimo: int = int(v.get("min", 50))
	var tipo: String = v.get("tipo", "standard")
	var vinc := ""
	var motivo := ""
	match tipo:
		"rabaul":
			var colpi: int = int(st["basi"].get("rabaul", {}).get("colpi_tot", 0))
			if colpi >= 4 and va >= 20:
				vinc = "A"; motivo = "Rabaul colpita %d volte e %d punti." % [colpi, va]
			elif colpi >= 2 and va >= 20 and va > vj:
				vinc = "A"; motivo = "Rabaul colpita e più punti del Giappone."
			else:
				vinc = "J"; motivo = "L'incursione contro Rabaul non ha raggiunto lo scopo."
		"coral":
			if int(st["sbarchi"]["J"]) < 50:
				va += 50
				st["lati"]["A"]["vp"] = va
				motivo = "Il Giappone non ha sbarcato 50 punti a Port Moresby (+50 agli Alleati). "
		"guadalcanal":
			var sa: int = st["sbarchi"]["A"]
			var sj: int = st["sbarchi"]["J"]
			if sa != sj:
				var chi := "A" if sa > sj else "J"
				pv(chi, 50)
				motivo = "%s sbarca di più (+50). " % NOME_LATO[chi]
				va = st["lati"]["A"]["vp"]
				vj = st["lati"]["J"]["vp"]
		_:
			pass
	if tipo == "standard" or tipo == "coral" or tipo == "guadalcanal":
		if v.has("bonus_sbarco_J") and int(st["sbarchi"]["J"]) >= 50:
			vj += int(v["bonus_sbarco_J"])
			st["lati"]["J"]["vp"] = vj
			motivo += "Il Giappone ha sbarcato almeno 50 punti (+%d). " % int(v["bonus_sbarco_J"])
		if maxi(va, vj) < minimo or va == vj:
			vinc = ""
			motivo += "Nessuno raggiunge i %d punti necessari: pareggio." % minimo if maxi(va, vj) < minimo else "Parità."
		else:
			vinc = "A" if va > vj else "J"
			motivo += "Punti: Alleati %d, Giappone %d." % [va, vj]
	st["fine"] = true
	st["risultato"] = {"vincitore": vinc, "motivo": motivo, "vp": {"A": va, "J": vj}}
	add_log("*", "Fine dello scenario. " + (("Vince %s. " % NOME_LATO[vinc]) if vinc != "" else "") + motivo)
	game_over.emit(st["risultato"])


# ================================================================ viste per l'interfaccia

## Unità visibili a un lato (le proprie tutte, le nemiche secondo le conoscenze).
func tf_del_lato(s: String) -> Array:
	var out := []
	for tid in st["tf"]:
		if st["tf"][tid]["lato"] == s and not st["tf"][tid]["navi"].is_empty():
			out.append(tid)
	return out


func af_del_lato(s: String) -> Array:
	var out := []
	for fid in st["af"]:
		if st["af"][fid]["lato"] == s:
			out.append(fid)
	return out


func nidi_del_lato(s: String) -> Array:
	var out := []
	for nid in st["nidi"]:
		if st["nidi"][nid]["lato"] == s:
			if st["navi"].has(nid) and st["navi"][nid]["affondata"]:
				continue
			out.append(nid)
	return out


## Portaerei e basi (nidi) che stanno in un esagono.
func nidi_in(h: Vector2i, s: String) -> Array:
	var out := []
	for nid in nidi_del_lato(s):
		if nido_hex(nid) == h:
			out.append(nid)
	return out


func tf_desc(tid: String) -> String:
	var tf: Dictionary = st["tf"][tid]
	var cont := {}
	for nid in tf["navi"]:
		var t: String = st["navi"][nid]["tipo"]
		cont[t] = int(cont.get(t, 0)) + 1
	var p := []
	for t in ["CV", "CVL", "AV", "CAV", "BB", "CA", "CL", "DD", "APD", "AP", "AO", "PG"]:
		if cont.has(t):
			p.append("%d %s" % [cont[t], t])
	return ", ".join(p)


func af_desc(fid: String) -> String:
	var p := []
	for g in st["af"][fid]["gruppi"]:
		var a: String = g["arma"]
		var at := ""
		if a == "T":
			at = " siluri"
		elif a == "AP" or a == "GP":
			at = " bombe " + a
		elif a == "x":
			at = " (sganciato)"
		p.append("%d %s%s" % [g["q"], g["tipo"], at])
	return ", ".join(p)


## Dati sintetici per salvataggi: scenario, seme, giocatori, decisioni.
func salvataggio() -> Dictionary:
	return {"scen": st["scen"], "seed": st["seed"], "players": players, "decisioni": decisions.duplicate(true)}
