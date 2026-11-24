extends RefCounted
## Combattimenti di Flat Top: aria-aria, contraerea, attacco aereo, superficie e bombardamento costiero.
## Funzioni statiche che lavorano sullo stato del motore (eng.st) e usano i suoi dadi.

const CACCIA_ARMATI_MENO6 := ["Wildcat", "P-38", "P-39", "P-40", "Beaufighter", "Zero", "Rufe"]

## Punti vittoria delle navi: [affondata, per punto di danno]
static func valore_nave(n: Dictionary) -> Array:
	var t: String = n["tipo"]
	var lato: String = n["lato"]
	var nome: String = n["nome"]
	match t:
		"CV":
			if lato == "A":
				return [150, 20]
			if nome in ["Shokaku", "Zuikaku"]:
				return [140, 20]
			if nome in ["Junyo", "Hiyo"]:
				return [120, 20]
			return [150, 20]
		"CVL":
			return [100, 20]
		"BB", "BC":
			if lato == "A":
				return [75, 5]
			if nome == "Mutsu":
				return [65, 5]
			return [60, 5]
		"AV", "CAV":
			return [50, 4]
		"CA":
			return [40, 4]
		"CL", "CLA":
			return [30, 3]
		"AP":
			return [maxi(2, 24 - 3 * (8 - int(n.get("carico", 8)))), 3]
		"APD":
			return [4 if int(n.get("carico", 8)) > 0 else 1, 1]
		"AO":
			return [20, 0]
		"DD":
			return [8, 0]
		"PG", "PT":
			return [4, 0]
	return [4, 0]


static func priorita_nave(t: String) -> int:
	match t:
		"CV":
			return 0
		"CVL":
			return 1
		"BB", "BC":
			return 2
		"AV", "CAV", "CA":
			return 3
		"CL", "CLA":
			return 4
		"AP", "APD":
			return 5
		"AO":
			return 6
		"DD":
			return 7
	return 8


# ================================================================ decisioni

## Tipi di decisione che nascono nei combattimenti (per l'IA e per l'interfaccia).
const DECISIONI := ["intercetta", "bersagli", "contraerea", "ponte", "sup_ingaggio", "sup_schiera", "sup_fuoco", "sup_siluri", "sup_penetra", "sup_schermo"]


static func _attiva(af: Dictionary) -> bool:
	return not af.get("fuori_mappa", false)


## Chiede la stessa cosa ai due lati: se uno dei due non ha niente da decidere risponde l'IA per lui.
## req_lati: lato -> richiesta (vuota = niente da decidere).
static func _simul(eng, k: String, req_lati: Dictionary) -> Dictionary:
	var out := {}
	var veri := []
	for s in ["A", "J"]:
		var r: Dictionary = req_lati.get(s, {})
		if r.is_empty() or bool(r.get("banale", false)):
			continue
		veri.append(s)
	if veri.size() == 2:
		var req := {"k": k, "per": req_lati}
		out = await eng._decide_simul(req)
	elif veri.size() == 1:
		var s1: String = veri[0]
		var rq: Dictionary = req_lati[s1].duplicate()
		rq["k"] = k
		out[s1] = await eng._decide(s1, rq)
	for s in ["A", "J"]:
		if not out.has(s) or out[s] == null:
			var r2: Dictionary = req_lati.get(s, {}).duplicate()
			r2["k"] = k
			out[s] = ai_decide(eng, s, r2) if not req_lati.get(s, {}).is_empty() else {}
	return out


## Il consiglio dell'IA per ogni decisione di combattimento (anche il tasto «Suggerisci»).
static func ai_decide(eng, s: String, req: Dictionary) -> Dictionary:
	var r: Dictionary = req
	if req.has("per"):
		r = req["per"].get(s, {})
	match str(req.get("k", "")):
		"intercetta":
			return ai_intercetta(eng, s, r)
		"bersagli":
			return ai_bersagli(eng, s, r)
		"contraerea":
			return ai_contraerea(eng, s, r)
		"ponte":
			return ai_ponte(eng, s, r)
		"sup_ingaggio":
			return ai_sup_ingaggio(eng, s, r)
		"sup_schiera":
			return ai_sup_schiera(eng, s, r)
		"sup_fuoco", "sup_siluri", "sup_schermo":
			return {"fuoco": ai_alloca(eng, r)}
		"sup_penetra":
			return {"penetra": true, "fuoco": ai_alloca(eng, r)}
	return {}


# ================================================================ fase di combattimento

static func fase_combattimento(eng) -> void:
	var st: Dictionary = eng.st
	# esagoni con unità di entrambi i lati
	var occ := {}
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		if tf["navi"].is_empty() or tf.get("fuori", false):
			continue
		var h: Vector2i = eng.tf_hex(tid)
		if not occ.has(h):
			occ[h] = {"A": false, "J": false}
		occ[h][tf["lato"]] = true
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if not _attiva(af):
			continue
		var h2: Vector2i = eng.af_hex(fid)
		if not occ.has(h2):
			occ[h2] = {"A": false, "J": false}
		occ[h2][af["lato"]] = true
	for bid in st["basi"]:
		var b: Dictionary = st["basi"][bid]
		if b["fuori"]:
			continue
		var h3 := Vector2i(int(b["hex"][0]), int(b["hex"][1]))
		if not occ.has(h3):
			occ[h3] = {"A": false, "J": false}
		occ[h3][b["lato"]] = true
	var hexes := []
	for h in occ:
		if occ[h]["A"] and occ[h]["J"]:
			hexes.append(h)
	hexes.sort_custom(func(a, b): return a.x * 1000 + a.y < b.x * 1000 + b.y)
	for h in hexes:
		if eng.tempesta(h):
			continue
		await battaglia(eng, h)
		if eng.stop_requested:
			return
	# intercettazioni entro due esagoni da portaerei o basi (16.1.2)
	await _intercettazioni_vicine(eng)


static func battaglia(eng, h: Vector2i) -> void:
	var con_navi_basi := _ha_nave_o_base(eng, h)
	if con_navi_basi:
		for s in [eng.st["iniziativa"], eng.nemico(eng.st["iniziativa"])]:
			await aria_aria(eng, h, s, true)
	for s in [eng.st["iniziativa"], eng.nemico(eng.st["iniziativa"])]:
		await attacco_aereo(eng, h, s)
	await superficie(eng, h)
	for s in ["A", "J"]:
		await bombardamento(eng, h, s)


static func _ha_nave_o_base(eng, h: Vector2i) -> bool:
	var st: Dictionary = eng.st
	for tid in st["tf"]:
		if not st["tf"][tid]["navi"].is_empty() and not st["tf"][tid].get("fuori", false) and eng.tf_hex(tid) == h:
			return true
	for bid in st["basi"]:
		if not st["basi"][bid]["fuori"] and eng.vh(st["basi"][bid]["hex"]) == h:
			return true
	return false


static func _vicino_nido(eng, h: Vector2i, s: String) -> bool:
	for nid in eng.nidi_del_lato(s):
		var nh: Vector2i = eng.nido_hex(nid)
		if nh.x > -100 and not eng.base_fuori(nid) and FTData.dist(nh, h) <= 2:
			return true
	return false


static func _intercettazioni_vicine(eng) -> void:
	var st: Dictionary = eng.st
	var fatti := {}
	for fid in st["af"].keys():
		if not st["af"].has(fid):
			continue
		var af: Dictionary = st["af"][fid]
		if not _attiva(af):
			continue
		var h: Vector2i = eng.af_hex(fid)
		if fatti.has(h) or _ha_nave_o_base(eng, h):
			continue
		var s: String = af["lato"]
		var e: String = eng.nemico(s)
		if not _vicino_nido(eng, h, s):
			continue
		var nemici := false
		for f2 in st["af"]:
			if st["af"][f2]["lato"] == e and _attiva(st["af"][f2]) and eng.af_hex(f2) == h and int(st["noti"][s].get(f2, {}).get("cond", 0)) >= 1:
				nemici = true
				break
		if not nemici:
			continue
		fatti[h] = true
		await aria_aria(eng, h, s, false)


# ================================================================ aria-aria

## Gruppi aerei di un lato in un esagono e a una quota: {sco: caccia scarichi, bom: armati e altri}.
static func _classifica(eng, h: Vector2i, s: String, quota: String) -> Dictionary:
	var st: Dictionary = eng.st
	var out := {"sco": [], "bom": []}
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if af["lato"] != s or not _attiva(af) or eng.af_hex(fid) != h or af["quota"] != quota:
			continue
		for gi in af["gruppi"].size():
			var g: Dictionary = af["gruppi"][gi]
			var r: String = FTData.aerei[g["tipo"]]["ruoli"]
			if g["arma"] == "" and (r.contains("I") or r.contains("E")):
				out["sco"].append({"fid": fid, "gi": gi})
			else:
				out["bom"].append({"fid": fid, "gi": gi})
	return out


## Caccia di un lato che possono intercettare in un esagono e a una quota.
static func _candidati(eng, h: Vector2i, s: String, quota: String) -> Array:
	var st: Dictionary = eng.st
	var out := []
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if af["lato"] != s or not _attiva(af) or eng.af_hex(fid) != h or af["quota"] != quota:
			continue
		for gi in af["gruppi"].size():
			var g: Dictionary = af["gruppi"][gi]
			var r: String = FTData.aerei[g["tipo"]]["ruoli"]
			if g["arma"] == "" and r.contains("I") and (not r.contains("I*") or quota == "B") and int(g["q"]) > 0:
				out.append({"fid": fid, "gi": gi})
	return out


static func _tot(eng, lst: Array) -> int:
	var t := 0
	for it in lst:
		if eng.st["af"].has(it["fid"]) and it["gi"] < eng.st["af"][it["fid"]]["gruppi"].size():
			t += int(eng.st["af"][it["fid"]]["gruppi"][it["gi"]]["q"])
	return t


static func _lato_ha_bombardieri(eng, h: Vector2i, s: String) -> bool:
	var st: Dictionary = eng.st
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if af["lato"] == s and _attiva(af) and eng.af_hex(fid) == h:
			for g in af["gruppi"]:
				if g["arma"] != "" and g["arma"] != "x":
					return true
	return false


static func _desc_gruppi(eng, lst: Array, mostra_tipo: bool) -> Array:
	var out := []
	for it in lst:
		var af: Dictionary = eng.st["af"][it["fid"]]
		var g: Dictionary = af["gruppi"][it["gi"]]
		out.append({"id": it["fid"] + ":" + str(it["gi"]), "af": int(af["num"]), "tipo": g["tipo"] if mostra_tipo else "",
			"q": int(g["q"]), "armato": g["arma"] != "" and g["arma"] != "x"})
	return out


## Il lato «att» decide come usare i suoi caccia contro gli aerei nemici dell'esagono (16, 14.17).
## sicuro = true nell'esagono con navi o basi (niente tabella di intercettazione).
static func aria_aria(eng, h: Vector2i, att: String, sicuro: bool) -> void:
	var st: Dictionary = eng.st
	var dif: String = eng.nemico(att)
	for quota in ["A", "B"]:
		var I := _candidati(eng, h, att, quota)
		if I.is_empty():
			continue
		var D := _classifica(eng, h, dif, quota)
		var D_sco := []
		var D_bom := []
		for it in D["sco"]:
			var g0: Dictionary = st["af"][it["fid"]]["gruppi"][it["gi"]]
			if int(st["noti"][att].get(it["fid"], {}).get("cond", 0)) >= 1 and int(g0.get("int_turno", -1)) != int(st["turno"]):
				D_sco.append(it)
		for it in D["bom"]:
			if int(st["noti"][att].get(it["fid"], {}).get("cond", 0)) >= 1:
				D_bom.append(it)
		if _tot(eng, D_sco) + _tot(eng, D_bom) <= 0:
			continue
		var ni := _tot(eng, I)
		if not sicuro:
			var nd := _tot(eng, D_sco) + _tot(eng, D_bom)
			var serve := 5
			if ni <= 5 and nd >= 6:
				serve = 4
			elif ni >= 6 and nd <= 5:
				serve = 4
			elif ni >= 6 and nd >= 6:
				serve = 3
			var r: int = eng.d6()
			if st.get("combattuti", {}).has(att + str(h)):
				r += 1
			if r < serve:
				eng.add_log(att, "Tentativo di intercettazione in %s fallito." % FTData.nome_hex(h), "minore")
				continue
		# decisione: chi attacca le scorte, chi i bombardieri, chi resta di scorta
		var req := {"k": "intercetta", "h": [h.x, h.y], "quota": quota, "sicuro": sicuro,
			"miei": _desc_gruppi(eng, I, true), "sco": _desc_gruppi(eng, D_sco, true), "bom": _desc_gruppi(eng, D_bom, true),
			"miei_bombardieri": _lato_ha_bombardieri(eng, h, att), "difendo": _difende(eng, h, att)}
		var risp: Dictionary = await eng._decide(att, req)
		if eng.stop_requested:
			return
		var ass: Dictionary = risp.get("assegna", {})
		if ass.is_empty():
			ass = ai_intercetta(eng, att, req).get("assegna", {})
		var I_sco := []
		var I_bom := []
		for it in I:
			var k: String = it["fid"] + ":" + str(it["gi"])
			match str(ass.get(k, "no")):
				"sco":
					if not D_sco.is_empty():
						I_sco.append(it)
					else:
						I_bom.append(it)
				"bom":
					if not D_bom.is_empty():
						I_bom.append(it)
					else:
						I_sco.append(it)
		if I_sco.is_empty() and I_bom.is_empty():
			eng.add_log(att, "In %s i caccia restano di scorta e non intercettano." % FTData.nome_hex(h), "minore")
			continue
		for it in I_sco + I_bom:
			st["af"][it["fid"]]["gruppi"][it["gi"]]["int_turno"] = st["turno"]
		var notte: bool = eng.notte()
		var nuv: bool = eng.meteo(h) >= 1
		var rep := []
		_spendi_rf(eng, I_sco + I_bom)
		if not I_sco.is_empty() and not D_sco.is_empty():
			_spendi_rf(eng, D_sco)
			var p1 := _duello(eng, I_sco, D_sco, nuv, notte)
			var p2 := _duello(eng, D_sco, I_sco, nuv, notte)
			_applica_perdite(eng, p1, dif)
			_applica_perdite(eng, p2, att)
			rep.append("caccia contro scorte: %d abbattuti contro %d" % [_somma(p1), _somma(p2)])
			var si := _tot(eng, _vivi(eng, I_sco))
			var ss := _tot(eng, _vivi(eng, D_sco))
			if ss > 0 and ss >= 2 * si and not I_bom.is_empty():
				I_bom = []
				rep.append("le scorte respingono l'attacco ai bombardieri")
			elif si >= 2 * maxi(1, ss) or ss == 0:
				I_bom = I_bom + I_sco
		I_bom = _vivi(eng, I_bom)
		D_bom = _vivi(eng, D_bom)
		if not I_bom.is_empty() and not D_bom.is_empty():
			var p3 := _duello(eng, I_bom, D_bom, nuv, notte)
			var p4 := _duello(eng, D_bom, I_bom, nuv, notte)
			_applica_perdite(eng, p3, dif)
			_applica_perdite(eng, p4, att)
			rep.append("caccia contro bombardieri: %d abbattuti contro %d" % [_somma(p3), _somma(p4)])
		st["combattuti_ora"][att + str(h)] = true
		st["combattuti_ora"][dif + str(h)] = true
		if not rep.is_empty():
			var txt := "Combattimento aereo in %s (%s quota): %s." % [FTData.nome_hex(h), "alta" if quota == "A" else "bassa", "; ".join(rep)]
			eng.add_log("*", txt, "combattimento")
			eng.event.emit({"k": "aria", "h": [h.x, h.y], "testo": txt})
		_pulisci_af(eng)


## Il lato ha navi o basi nell'esagono (i caccia proteggono, non scortano).
static func _difende(eng, h: Vector2i, s: String) -> bool:
	var st: Dictionary = eng.st
	for tid in st["tf"]:
		if st["tf"][tid]["lato"] == s and not st["tf"][tid]["navi"].is_empty() and not st["tf"][tid].get("fuori", false) and eng.tf_hex(tid) == h:
			return true
	for bid in st["basi"]:
		if st["basi"][bid]["lato"] == s and not st["basi"][bid]["fuori"] and eng.vh(st["basi"][bid]["hex"]) == h:
			return true
	return false


static func ai_intercetta(eng, s: String, req: Dictionary) -> Dictionary:
	var miei: Array = req.get("miei", [])
	var nsco := 0
	var nbom := 0
	for g in req.get("sco", []):
		nsco += int(g["q"])
	for g in req.get("bom", []):
		nbom += int(g["q"])
	var ass := {}
	# con i propri bombardieri in aria e niente da difendere, i caccia restano di scorta
	if bool(req.get("miei_bombardieri", false)) and not bool(req.get("difendo", false)):
		for g in miei:
			ass[g["id"]] = "no"
		return {"assegna": ass}
	var tot := 0
	for g in miei:
		tot += int(g["q"])
	var verso_sco := 0
	var ord := miei.duplicate()
	ord.sort_custom(func(a, b): return int(a["q"]) > int(b["q"]))
	for g in ord:
		if nsco > 0 and nbom > 0:
			if verso_sco * 2 < tot and ord.size() > 1:
				ass[g["id"]] = "sco"
				verso_sco += int(g["q"])
			else:
				ass[g["id"]] = "bom"
		elif nsco > 0:
			ass[g["id"]] = "sco"
		else:
			ass[g["id"]] = "bom"
	# se tutti sono finiti sulle scorte, almeno uno va sui bombardieri
	if nbom > 0 and not ass.values().has("bom") and ord.size() > 0:
		ass[ord[ord.size() - 1]["id"]] = "bom"
	return {"assegna": ass}


static func _somma(p: Dictionary) -> int:
	var t := 0
	for k in p:
		t += int(p[k])
	return t


static func _vivi(eng, lst: Array) -> Array:
	var out := []
	for it in lst:
		if eng.st["af"].has(it["fid"]) and it["gi"] < eng.st["af"][it["fid"]]["gruppi"].size() and int(eng.st["af"][it["fid"]]["gruppi"][it["gi"]]["q"]) > 0:
			out.append(it)
	return out

## I gruppi di «chi» sparano contro i gruppi di «bersagli»: ogni tipo d'aereo tira una volta sul CRT.
## Restituisce le perdite: chiave "fid:gi" -> fattori abbattuti.
static func _duello(eng, chi: Array, bersagli: Array, nuv: bool, notte: bool) -> Dictionary:
	var st: Dictionary = eng.st
	var perdite := {}
	if bersagli.is_empty():
		return perdite
	# raggruppa per tipo chi spara
	var per_tipo := {}
	for it in chi:
		var g: Dictionary = st["af"][it["fid"]]["gruppi"][it["gi"]]
		per_tipo[g["tipo"]] = int(per_tipo.get(g["tipo"], 0)) + int(g["q"])
	# bersaglio: il gruppo più numeroso (ancora vivo)
	for tipo in per_tipo:
		var q: int = per_tipo[tipo]
		if q <= 0:
			continue
		var bht := aa_bht(eng, tipo)
		if nuv:
			bht -= 1
		if notte:
			bht -= 2
		var colpi := tiro(eng, maxi(1, bht), q)
		if colpi <= 0:
			continue
		var best = null
		var bq := -1
		for b in bersagli:
			var g2: Dictionary = st["af"][b["fid"]]["gruppi"][b["gi"]]
			var rest: int = int(g2["q"]) - int(perdite.get(b["fid"] + ":" + str(b["gi"]), 0))
			if rest > bq:
				bq = rest
				best = b
		if best == null or bq <= 0:
			continue
		var k: String = best["fid"] + ":" + str(best["gi"])
		perdite[k] = mini(int(perdite.get(k, 0)) + colpi, int(st["af"][best["fid"]]["gruppi"][best["gi"]]["q"]))
	return perdite


static func aa_bht(eng, tipo: String) -> int:
	var b: int = int(FTData.aerei[tipo]["aa"])
	if tipo == "Wildcat" and bool(eng.st["speciali"].get("wildcat7", false)):
		b = 7
	if bool(eng.st["speciali"].get("idro_j_meno1", false)) and FTData.aerei[tipo]["classe"] in ["FL", "FH"] and FTData.aerei[tipo]["lato"] == "J":
		b -= 1
	return b


static func _applica_perdite(eng, perdite: Dictionary, lato: String) -> void:
	var st: Dictionary = eng.st
	for k in perdite:
		var parts: PackedStringArray = k.split(":")
		var fid := parts[0]
		var gi := int(parts[1])
		if not st["af"].has(fid):
			continue
		var g: Dictionary = st["af"][fid]["gruppi"][gi]
		var q: int = mini(int(perdite[k]), int(g["q"]))
		g["q"] = int(g["q"]) - q
		eng._perdita(lato, g["tipo"], q, false)


static func _pulisci_af(eng) -> void:
	var st: Dictionary = eng.st
	for fid in st["af"].keys():
		var af: Dictionary = st["af"][fid]
		var gl := []
		for g in af["gruppi"]:
			if int(g["q"]) > 0:
				gl.append(g)
		af["gruppi"] = gl
		if gl.is_empty():
			st["af"].erase(fid)


static func _spendi_rf(eng, lst: Array) -> void:
	var st: Dictionary = eng.st
	var fatti := {}
	for it in lst:
		var af: Dictionary = st["af"][it["fid"]]
		var k: String = it["fid"] + ":" + str(it["gi"])
		if fatti.has(k):
			continue
		fatti[k] = true
		var g: Dictionary = af["gruppi"][it["gi"]]
		if int(g.get("rf_turno", -1)) == int(st["turno"]):
			continue
		g["rf_turno"] = st["turno"]
		g["entro"] = int(g["entro"]) - 1


## Tiro sul CRT: numero risultato ±2 secondo il dado (20.3).
static func tiro(eng, bht: int, fattori: int) -> int:
	if fattori <= 0:
		return 0
	var n := FTData.crt_numero(bht, fattori)
	var r: int = eng.d6()
	if n < 0:
		return 1 if r == 6 else 0
	var mod := 0
	match r:
		1:
			mod = -2
		2:
			mod = -1
		5:
			mod = 1
		6:
			mod = 2
	return maxi(0, n + mod)



## Intercettazione durante il movimento (14.13.2): l'AF che muove entra in un esagono con AF nemiche
## sul tavolo che hanno intercettori alla stessa quota.
static func intercettazione_movimento(eng, fid: String) -> void:
	var st: Dictionary = eng.st
	var af: Dictionary = st["af"][fid]
	var m: String = af["lato"]
	var e: String = eng.nemico(m)
	var h: Vector2i = eng.af_hex(fid)
	if eng.tempesta(h):
		return
	if not (_ha_nave_o_base(eng, h) or _vicino_nido(eng, h, e)):
		return
	var key := "int_" + e + str(h) + str(st["turno"])
	if st.get("_intercettati", {}).has(key):
		return
	var ci_sono := false
	for f2 in st["af"]:
		var a2: Dictionary = st["af"][f2]
		if a2["lato"] == e and _attiva(a2) and eng.af_hex(f2) == h and bool(a2["esposta"]) and a2["quota"] == af["quota"]:
			for g in a2["gruppi"]:
				if g["arma"] == "" and FTData.aerei[g["tipo"]]["ruoli"].contains("I"):
					ci_sono = true
	if not ci_sono or int(st["noti"][e].get(fid, {}).get("cond", 0)) < 1:
		return
	if not st.has("_intercettati"):
		st["_intercettati"] = {}
	st["_intercettati"][key] = true
	await aria_aria(eng, h, e, false)


# ================================================================ contraerea e attacco aereo

## Metodi d'attacco possibili per un gruppo: contro navi o contro basi, secondo la quota dell'AF.
static func metodi(g: Dictionary, quota: String, contro_base: bool) -> Array:
	var b: Dictionary = FTData.aerei[g["tipo"]]["bht"]
	var k: String = str(g["arma"]).to_lower()
	var out := []
	if k == "t":
		if not contro_base and int(b.get("s_to", 0)) > 0:
			out.append("to")
		k = "gp"
	var pre := "b_" if contro_base else "s_"
	if quota == "A":
		for m in ["dv", "hl"]:
			if int(b.get(pre + m + "_" + k, 0)) > 0:
				out.append(m)
	if int(b.get(pre + "ll_" + k, 0)) > 0:
		out.append("ll")
	if out.is_empty() and int(b.get(pre + "hl_" + k, 0)) > 0:
		out.append("hl")
	if out.is_empty():
		out.append("ll")
	return out


static func attacco_aereo(eng, h: Vector2i, att: String) -> void:
	var st: Dictionary = eng.st
	var dif: String = eng.nemico(att)
	var notte: bool = eng.notte()
	var nuv: bool = eng.meteo(h) >= 1
	for fid in st["af"].keys():
		if not st["af"].has(fid):
			continue
		var af: Dictionary = st["af"][fid]
		if af["lato"] != att or not _attiva(af) or eng.af_hex(fid) != h:
			continue
		var armati := []
		for gi in af["gruppi"].size():
			var g: Dictionary = af["gruppi"][gi]
			if g["arma"] != "" and g["arma"] != "x" and int(g["q"]) > 0:
				armati.append(gi)
		if armati.is_empty():
			continue
		# bersagli osservati nell'esagono
		var tfs := []
		for tid in st["tf"]:
			var tf: Dictionary = st["tf"][tid]
			if tf["lato"] == dif and not tf["navi"].is_empty() and not tf.get("fuori", false) and eng.tf_hex(tid) == h:
				if int(st["noti"][att].get(tid, {}).get("cond", 0)) >= 1:
					tfs.append(tid)
		var base := ""
		for bid in st["basi"]:
			var b: Dictionary = st["basi"][bid]
			if b["lato"] == dif and not b["fuori"] and eng.vh(b["hex"]) == h:
				base = bid
		if tfs.is_empty() and base == "":
			return
		# ---- decisione dell'attaccante: bersaglio e metodo di ogni gruppo armato
		var navi := []
		for tid in tfs:
			for nid in st["tf"][tid]["navi"]:
				var n: Dictionary = st["navi"][nid]
				if n["affondata"]:
					continue
				navi.append({"id": nid, "tipo": n["tipo"], "nome": n["nome"] if bool(st["tf"][tid].get("svelata", false)) else "",
					"tf": int(st["tf"][tid]["num"]), "hits": int(n["hits"]), "danno": int(n["danno"]), "ancorata": bool(n["ancorata"]),
					"portaerei_carica": st["nidi"].has(nid) and not st["nidi"][nid]["pronti"].is_empty()})
		var gruppi := []
		for gi in armati:
			var g2: Dictionary = af["gruppi"][gi]
			gruppi.append({"gi": gi, "tipo": g2["tipo"], "q": int(g2["q"]), "arma": g2["arma"],
				"metodi_nave": metodi(g2, af["quota"], false), "metodi_base": metodi(g2, af["quota"], true)})
		var req := {"k": "bersagli", "h": [h.x, h.y], "fid": fid, "af": int(af["num"]), "quota": af["quota"],
			"gruppi": gruppi, "navi": navi, "base": base, "base_nome": st["basi"][base]["nome"] if base != "" else "",
			"missione": af.get("missione", {}).duplicate(true)}
		var risp: Dictionary = await eng._decide(att, req)
		if eng.stop_requested:
			return
		var assegna := _valida_bersagli(eng, req, risp)
		if assegna.is_empty():
			continue
		var vuole_base := false
		for a in assegna:
			if a[1] == "base":
				vuole_base = true
		# ---- contraerea: il difensore divide il suo fattore fra i gruppi attaccanti
		var aaf_tot := 0
		var tf_colpite := {}
		for a in assegna:
			if a[1] == "nave":
				tf_colpite[st["navi"][a[2]]["tf"]] = true
		for tid in tf_colpite:
			for nid in st["tf"][tid]["navi"]:
				if not st["navi"][nid]["affondata"]:
					aaf_tot += int(st["navi"][nid]["aa"])
		if base != "" and int(st["basi"][base]["aaf"]) > 0:
			var tocca_base := vuole_base
			for tid in tf_colpite:
				if st["tf"][tid]["ancorata"]:
					tocca_base = true
			if tocca_base:
				aaf_tot += maxi(0, int(st["basi"][base]["aaf"]))
			if vuole_base:
				for tid in st["tf"]:
					if st["tf"][tid]["lato"] == dif and eng.tf_hex(tid) == h and not tf_colpite.has(tid):
						for nid in st["tf"][tid]["navi"]:
							if st["navi"][nid]["ancorata"]:
								aaf_tot += int(st["navi"][nid]["aa"])
		var parti := {}
		if aaf_tot > 0:
			var g_aa := []
			for a in assegna:
				var ga: Dictionary = af["gruppi"][a[0]]
				g_aa.append({"gi": a[0], "tipo": ga["tipo"], "q": int(ga["q"]), "metodo": a[3],
					"bersaglio": st["basi"][a[2]]["nome"] if a[1] == "base" else st["navi"][a[2]]["nome"] + " " + st["navi"][a[2]]["tipo"]})
			var req_aa := {"k": "contraerea", "h": [h.x, h.y], "af": int(af["num"]), "aaf": aaf_tot, "gruppi": g_aa}
			if g_aa.size() == 1:
				parti[str(g_aa[0]["gi"])] = aaf_tot
			else:
				var r_aa: Dictionary = await eng._decide(dif, req_aa)
				if eng.stop_requested:
					return
				parti = _valida_aa(eng, req_aa, r_aa)
		var abb_tot := 0
		for a in assegna:
			var g4: Dictionary = af["gruppi"][a[0]]
			var parte: int = int(parti.get(str(a[0]), 0))
			if parte <= 0:
				continue
			var bht := 4
			if not a[3] in ["dv", "to", "ll"]:
				bht -= 2
			if nuv:
				bht -= 1
			if notte:
				bht -= 2
			var colpi := mini(tiro(eng, maxi(1, bht), parte), int(g4["q"]))
			if colpi > 0:
				g4["q"] = int(g4["q"]) - colpi
				eng._perdita(att, g4["tipo"], colpi, false)
				abb_tot += colpi
		# ---- attacco
		var rep := []
		var sopravvissuti := false
		for a in assegna:
			var g5: Dictionary = af["gruppi"][a[0]]
			var q: int = g5["q"]
			g5["arma"] = "x"
			if q <= 0:
				continue
			sopravvissuti = true
			if a[3] in ["dv", "to", "ll"] and int(g5.get("rf_att", -1)) != int(st["turno"]):
				g5["rf_att"] = st["turno"]
				g5["entro"] = int(g5["entro"]) - 1
			if a[1] == "base":
				var bht2 := _bht_attacco(eng, g5, a[3], true, {}, nuv, notte)
				var colpi2 := tiro(eng, bht2, q)
				var nido: Dictionary = st["nidi"].get(a[2], {})
				if colpi2 > 0 and a[3] != "to" and not nido.is_empty() and (not nido["pronti"].is_empty() or not nido["jl"].is_empty()):
					colpi2 *= 2
				await colpi_base(eng, a[2], colpi2, a[3] in ["dv", "ll"] and not notte, att)
				rep.append("%d %s su %s: %d colpi" % [q, g5["tipo"], st["basi"][a[2]]["nome"], colpi2])
			else:
				var n3: Dictionary = st["navi"][a[2]]
				if n3["affondata"]:
					continue
				var bht3 := _bht_attacco(eng, g5, a[3], false, n3, nuv, notte)
				var colpi3 := tiro(eng, bht3, q)
				if colpi3 > 0 and st["nidi"].has(a[2]):
					var nd: Dictionary = st["nidi"][a[2]]
					if a[3] == "to":
						if not nd["prep"].is_empty():
							colpi3 *= 2
					elif not nd["pronti"].is_empty() or not nd["jl"].is_empty():
						colpi3 *= 2
				var esito: String = await colpi_nave(eng, a[2], colpi3, a[3] in ["dv", "ll"] and not notte, att)
				rep.append("%d %s %s su %s %s: %s" % [q, g5["tipo"], _nome_metodo(a[3]), n3["nome"], n3["tipo"], esito])
			if eng.stop_requested:
				return
		for tid in tf_colpite:
			if st["tf"].has(tid):
				st["tf"][tid]["attaccata"] = true
				if sopravvissuti:
					st["tf"][tid]["svelata"] = true
		if vuole_base:
			st["attaccate"][base] = true
		var txt := "Attacco aereo in %s (AF %d): contraerea %d abbattuti. %s." % [FTData.nome_hex(h), af["num"], abb_tot, "; ".join(rep) if not rep.is_empty() else "Nessun aereo arriva sul bersaglio"]
		eng.add_log("*", txt, "combattimento")
		eng.event.emit({"k": "attacco", "h": [h.x, h.y], "testo": txt, "lato": att})
		_pulisci_af(eng)


## Controlla la scelta dei bersagli: [gi, "nave"/"base", id, metodo]. I gruppi senza scelta valida
## prendono quella dell'IA; «no» lascia il gruppo armato (non attacca in questo esagono).
static func _valida_bersagli(eng, req: Dictionary, risp: Dictionary) -> Array:
	var st: Dictionary = eng.st
	var ai_ass: Array = ai_bersagli(eng, "", req).get("assegna", [])
	var scelta := {}
	for a in risp.get("assegna", []):
		if a is Array and a.size() >= 4:
			scelta[int(a[0])] = a
	var out := []
	for g in req["gruppi"]:
		var gi: int = int(g["gi"])
		var a = scelta.get(gi, null)
		var ok := false
		if a != null:
			if str(a[1]) == "no":
				continue
			if str(a[1]) == "base" and str(a[2]) == str(req["base"]) and req["base"] != "" and str(a[3]) in g["metodi_base"]:
				ok = true
			elif str(a[1]) == "nave" and str(a[3]) in g["metodi_nave"]:
				for n in req["navi"]:
					if n["id"] == str(a[2]) and not st["navi"][n["id"]]["affondata"]:
						ok = true
		if ok:
			out.append([gi, str(a[1]), str(a[2]), str(a[3])])
		else:
			for b in ai_ass:
				if int(b[0]) == gi:
					out.append(b)
	return out


static func ai_bersagli(eng, _s: String, req: Dictionary) -> Dictionary:
	var st: Dictionary = eng.st
	var miss: Dictionary = req.get("missione", {})
	var base: String = str(req.get("base", ""))
	var vuole_base := base != "" and str(miss.get("bersaglio_base", "")) == base
	if req["navi"].is_empty():
		vuole_base = base != ""
	var out := []
	if vuole_base:
		for g in req["gruppi"]:
			out.append([int(g["gi"]), "base", base, g["metodi_base"][0]])
		return {"assegna": out}
	var navi := []
	var pref: String = str(miss.get("bersaglio", ""))
	for n in req["navi"]:
		var nn: Dictionary = st["navi"][n["id"]]
		var pri := priorita_nave(nn["tipo"])
		if nn["tf"] == pref:
			pri -= 10
		if str(miss.get("priorita", "")) == "trasporti" and nn["tipo"] in ["AP", "APD"] and int(nn.get("carico", 0)) > 0:
			pri = -20
		navi.append([pri, -int(nn["danno"]) + int(nn["hits"]), n["id"]])
	navi.sort()
	if navi.is_empty():
		return {"assegna": out}
	# concentra sul primo bersaglio finché i colpi attesi non bastano ad affondarlo, poi passa al successivo
	var idx := 0
	var attesi := 0.0
	var ord: Array = req["gruppi"].duplicate()
	ord.sort_custom(func(a, b): return int(a["q"]) > int(b["q"]))
	var notte: bool = eng.notte()
	var nuv: bool = eng.meteo(Vector2i(int(req["h"][0]), int(req["h"][1]))) >= 1
	for g in ord:
		var nid: String = navi[idx][2]
		var n2: Dictionary = st["navi"][nid]
		var met: String = _miglior_metodo(eng, g, n2, nuv, notte)
		out.append([int(g["gi"]), "nave", nid, met])
		var gd := {"tipo": g["tipo"], "arma": g["arma"], "q": g["q"]}
		var bh := _bht_attacco(eng, gd, met, false, n2, nuv, notte)
		attesi += maxf(0.3, float(FTData.crt_numero(bh, int(g["q"]))))
		if attesi >= float(int(n2["danno"]) - int(n2["hits"])) * 1.3 and idx < navi.size() - 1:
			idx += 1
			attesi = 0.0
	return {"assegna": out}


static func _miglior_metodo(eng, g: Dictionary, nave: Dictionary, nuv: bool, notte: bool) -> String:
	var best: String = g["metodi_nave"][0]
	var bv := -1
	for m in g["metodi_nave"]:
		var v := _bht_attacco(eng, {"tipo": g["tipo"], "arma": g["arma"]}, m, false, nave, nuv, notte)
		if v > bv:
			bv = v
			best = m
	return best


static func _valida_aa(eng, req: Dictionary, risp: Dictionary) -> Dictionary:
	var parti: Dictionary = risp.get("parti", {})
	var tot := 0
	var out := {}
	for g in req["gruppi"]:
		var k := str(g["gi"])
		var v := maxi(0, int(parti.get(k, 0)))
		v = mini(v, int(req["aaf"]) - tot)
		out[k] = v
		tot += v
	if tot == 0 and int(req["aaf"]) > 0:
		return ai_contraerea(eng, "", req)["parti"]
	return out


static func ai_contraerea(_eng, _s: String, req: Dictionary) -> Dictionary:
	var tot_att := 0
	for g in req["gruppi"]:
		tot_att += int(g["q"])
	var out := {}
	var resto: int = int(req["aaf"])
	var gs: Array = req["gruppi"]
	for i in gs.size():
		var g: Dictionary = gs[i]
		var v: int = resto if i == gs.size() - 1 else mini(resto, roundi(float(int(req["aaf"])) * int(g["q"]) / maxi(1, tot_att)))
		out[str(g["gi"])] = v
		resto -= v
	return {"parti": out}


static func _nome_metodo(m: String) -> String:
	match m:
		"dv":
			return "in picchiata"
		"to":
			return "con siluri"
		"ll":
			return "a bassa quota"
		"hl":
			return "da alta quota"
	return ""


static func _bht_attacco(eng, g: Dictionary, metodo: String, contro_base: bool, nave: Dictionary, nuv: bool, notte: bool) -> int:
	var b: Dictionary = FTData.aerei[g["tipo"]]["bht"]
	var k: String = str(g["arma"]).to_lower()
	if k == "x" or k == "" or k == "t":
		k = "gp"
	var v := 0
	if metodo == "to":
		v = int(b["s_to"])
	else:
		v = int(b.get(("b_" if contro_base else "s_") + metodo + "_" + k, 0))
	if v <= 0:
		return 0
	if not nave.is_empty():
		if int(nave["hits"]) >= int(nave["danno"]) - 1 and int(nave["danno"]) >= 3:
			v += 2
		if nave["ancorata"]:
			v += 2
	if nuv:
		v -= 2
	if notte:
		var wasp: bool = bool(eng.st["speciali"].get("wasp_notte", false)) and g["tipo"] in ["Dauntless", "Avenger"] and bool(g.get("wasp", false))
		v -= 2 if wasp else 4
	if bool(eng.st["speciali"].get("idro_j_meno1", false)) and FTData.aerei[g["tipo"]]["classe"] in ["FL", "FH"] and FTData.aerei[g["tipo"]]["lato"] == "J":
		v -= 1
	return clampi(v, 1, 15)


## Applica i colpi a una nave. Restituisce una descrizione breve.
static func colpi_nave(eng, nid: String, colpi: int, sceglie_att: bool, att: String) -> String:
	var st: Dictionary = eng.st
	var n: Dictionary = st["navi"][nid]
	if colpi <= 0:
		return "mancata"
	var prima: int = n["hits"]
	var nuovi: int = mini(colpi, int(n["danno"]) - prima)
	n["hits"] = prima + nuovi
	n["art"] = maxi(0, int(n["art"]) - nuovi)
	n["aa"] = maxi(0, int(n["aa"]) - nuovi)
	var val := valore_nave(n)
	# aerei distrutti a bordo (21.2.4 e 21.7)
	if st["nidi"].has(nid) and int(n["hits"]) < int(n["danno"]):
		await _distruggi_aerei(eng, nid, nuovi, sceglie_att, false, att)
	if int(n["hits"]) >= int(n["danno"]):
		n["affondata"] = true
		eng.pv(att, int(val[0]) - prima * int(val[1]))
		_affonda(eng, nid)
		return "%d colpi, AFFONDATA" % colpi
	eng.pv(att, nuovi * int(val[1]))
	var t := "%d colpi" % colpi
	if int(n["danno"]) >= 3 and int(n["hits"]) >= int(n["danno"]) - 1:
		t += ", immobilizzata"
	elif int(n["hits"]) * 2 >= int(n["danno"]):
		t += ", velocità dimezzata"
	return t


static func _affonda(eng, nid: String) -> void:
	var st: Dictionary = eng.st
	var n: Dictionary = st["navi"][nid]
	if st["nidi"].has(nid):
		var nido: Dictionary = st["nidi"][nid]
		var persi := 0
		for box in ["jl", "prep", "pronti", "disp"]:
			for k in nido[box]:
				persi += int(nido[box][k])
		eng.pv(eng.nemico(n["lato"]), persi * 2)
		nido["jl"] = {}
		nido["prep"] = {}
		nido["pronti"] = {}
		for fid in st["af"]:
			if str(st["af"][fid].get("in_volo_di", "")) == nid:
				var h: Vector2i = eng.af_hex(fid)
				st["af"][fid]["in_volo_di"] = ""
				st["af"][fid]["hex"] = [h.x, h.y]
	var tid: String = n["tf"]
	if st["tf"].has(tid):
		st["tf"][tid]["navi"].erase(nid)
		if st["tf"][tid]["navi"].is_empty():
			st["tf"].erase(tid)
	n["tf"] = ""
	eng.add_log("*", "%s (%s) affondata." % [n["nome"], n["tipo"]], "affondata")
	eng.event.emit({"k": "affondata", "nome": n["nome"], "lato": n["lato"]})


## Aerei distrutti nelle caselle di una portaerei o di una base colpita. Sceglie l'attaccante (picchiata e
## bassa quota di giorno) o il difensore; prima le caselle Pronti, Appena atterrati e Preparazione,
## sulle basi poi un fattore della casella Disponibili ogni due colpi.
static func _distruggi_aerei(eng, nid: String, colpi: int, sceglie_att: bool, base_disp: bool, att: String) -> void:
	var st: Dictionary = eng.st
	var nido: Dictionary = st["nidi"][nid]
	var lato: String = nido["lato"]
	var esposti := 0
	var chiavi := 0
	for box in ["pronti", "jl", "prep"]:
		for k in nido[box]:
			esposti += int(nido[box][k])
			chiavi += 1
	var da_disp := 0
	var disp_tot := 0
	for k in nido["disp"]:
		disp_tot += int(nido["disp"][k])
	if base_disp:
		da_disp = mini(maxi(0, colpi - esposti) / 2, disp_tot)
	var da_esposti := mini(colpi, esposti)
	if da_esposti + da_disp <= 0:
		return
	var chi: String = att if sceglie_att else lato
	var req := {"k": "ponte", "nido": nid, "nome": eng.nido_nome(nid), "proprio": chi == lato, "colpi": colpi,
		"da_esposti": da_esposti, "da_disp": da_disp,
		"caselle": {"pronti": nido["pronti"].duplicate(), "jl": nido["jl"].duplicate(), "prep": nido["prep"].duplicate(), "disp": nido["disp"].duplicate()}}
	var risp: Dictionary
	# se non c'è scelta (un solo tipo o tutto distrutto) non si chiede
	if (da_esposti == esposti or chiavi <= 1) and (da_disp == 0 or da_disp == disp_tot or nido["disp"].size() <= 1):
		risp = ai_ponte(eng, chi, req)
	else:
		risp = await eng._decide(chi, req)
	var scelta := _valida_ponte(eng, chi, req, risp)
	for bk in scelta:
		var parts: PackedStringArray = str(bk).split("/")
		var q: int = int(scelta[bk])
		if q <= 0:
			continue
		FTEngine._add(nido[parts[0]], parts[1], -q)
		eng._perdita(lato, parts[1].split("|")[0], q, false)


static func _valida_ponte(eng, chi: String, req: Dictionary, risp: Dictionary) -> Dictionary:
	var d: Dictionary = risp.get("distrutti", {})
	var cas: Dictionary = req["caselle"]
	var out := {}
	var es := 0
	var di := 0
	for bk in d:
		var parts: PackedStringArray = str(bk).split("/")
		if parts.size() != 2 or not cas.has(parts[0]):
			continue
		var avail: int = int(cas[parts[0]].get(parts[1], 0))
		var q: int = clampi(int(d[bk]), 0, avail)
		if parts[0] == "disp":
			q = mini(q, int(req["da_disp"]) - di)
			di += q
		else:
			q = mini(q, int(req["da_esposti"]) - es)
			es += q
		if q > 0:
			out[bk] = q
	if es < int(req["da_esposti"]) or di < int(req["da_disp"]):
		# completa con la scelta automatica
		var resto := req.duplicate(true)
		for bk in out:
			var p2: PackedStringArray = str(bk).split("/")
			resto["caselle"][p2[0]][p2[1]] = int(resto["caselle"][p2[0]][p2[1]]) - int(out[bk])
		resto["da_esposti"] = int(req["da_esposti"]) - es
		resto["da_disp"] = int(req["da_disp"]) - di
		var agg: Dictionary = ai_ponte(eng, chi, resto)["distrutti"]
		for bk2 in agg:
			out[bk2] = int(out.get(bk2, 0)) + int(agg[bk2])
	return out


static func ai_ponte(_eng, _s: String, req: Dictionary) -> Dictionary:
	var cas: Dictionary = req["caselle"]
	var out := {}
	var resta: int = int(req["da_esposti"])
	# chi attacca sceglie i più preziosi, chi difende i meno preziosi
	var prezioso: bool = not bool(req.get("proprio", false))
	for box in ["pronti", "jl", "prep"]:
		var keys: Array = []
		for k in cas[box]:
			if int(cas[box][k]) > 0:
				keys.append(k)
		keys.sort_custom(func(a, b): return _val_aereo(a) > _val_aereo(b) if prezioso else _val_aereo(a) < _val_aereo(b))
		for k in keys:
			if resta <= 0:
				break
			var q: int = mini(resta, int(cas[box][k]))
			out[box + "/" + k] = q
			resta -= q
	var rd: int = int(req["da_disp"])
	var kd: Array = []
	for k in cas["disp"]:
		if int(cas["disp"][k]) > 0:
			kd.append(k)
	kd.sort_custom(func(a, b): return _val_aereo(a) > _val_aereo(b) if prezioso else _val_aereo(a) < _val_aereo(b))
	for k in kd:
		if rd <= 0:
			break
		var q2: int = mini(rd, int(cas["disp"][k]))
		out["disp/" + k] = q2
		rd -= q2
	return {"distrutti": out}


static func _val_aereo(k: String) -> int:
	var tipo: String = k.split("|")[0]
	var b: Dictionary = FTData.aerei.get(tipo, {}).get("bht", {})
	var v := 0
	for x in b:
		v = maxi(v, int(b[x]))
	return v


## Colpi su una base (21.3).
static func colpi_base(eng, bid: String, colpi: int, sceglie_att: bool, att: String) -> void:
	if colpi <= 0:
		return
	var st: Dictionary = eng.st
	var b: Dictionary = st["basi"][bid]
	b["hits"] = int(b["hits"]) + colpi
	b["colpi_tot"] = int(b.get("colpi_tot", 0)) + colpi
	var solo_idro: bool = b["ph"] == "S"
	b["lf"] = [int(b["lf"][0]) - (1 if solo_idro else 2) * colpi, int(b["lf"][1]) - colpi]
	b["aaf"] = int(b["aaf"]) - colpi
	b["sf"] = int(b["sf"]) - colpi
	eng.pv(att, colpi)
	if st["nidi"].has(bid):
		await _distruggi_aerei(eng, bid, colpi, sceglie_att, true, att)
	st["attaccate"][bid] = true


# ================================================================ combattimento di superficie

static func _desc_nave(st: Dictionary, nid: String, nome: bool) -> Dictionary:
	var n: Dictionary = st["navi"][nid]
	return {"id": nid, "nome": n["nome"] if nome else "", "tipo": n["tipo"], "art": _art(n), "silu": int(n["silu"]),
		"mun": int(n["mun"]), "hits": int(n["hits"]), "danno": int(n["danno"]), "ancorata": bool(n["ancorata"]),
		"silu_usati": bool(n.get("silu_usati", false)), "tf": int(st["tf"][n["tf"]]["num"]) if st["tf"].has(n["tf"]) else 0}


## Posizioni ammesse per una nave (19.3): le ancorate e le gravemente danneggiate stanno in schermo.
static func posizioni_ok(n: Dictionary) -> Array:
	if n["ancorata"] or (int(n["danno"]) >= 3 and int(n["hits"]) >= int(n["danno"]) - 1):
		return ["schermo"]
	var out := []
	if _art(n) > 0:
		out.append("art")
	if int(n["silu"]) > 0 and not n.get("silu_usati", false):
		out.append("silu")
	out.append("schermo")
	return out


static func superficie(eng, h: Vector2i) -> void:
	var st: Dictionary = eng.st
	var tfs := {"A": [], "J": []}
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		if tf["navi"].is_empty() or tf.get("fuori", false) or eng.tf_hex(tid) != h:
			continue
		tfs[tf["lato"]].append(tid)
	if tfs["A"].is_empty() or tfs["J"].is_empty():
		return
	for s in ["A", "J"]:
		var visto := false
		for tid in tfs[eng.nemico(s)]:
			if int(st["noti"][s].get(tid, {}).get("cond", 0)) >= 1:
				visto = true
		if not visto:
			return
	var notte: bool = eng.notte()
	# ---- 1. chi inizia il combattimento (19.1): basta che uno lo voglia
	var rq1 := {}
	for s in ["A", "J"]:
		var forza := 0
		var forza_n := 0
		var contegni := []
		for tid in tfs[s]:
			contegni.append(str(st["tf"][tid].get("contegno", "evita")))
			for nid in st["tf"][tid]["navi"]:
				var nf: Dictionary = st["navi"][nid]
				# conta solo chi ha ancora munizioni
				if (not nf.get("mun_usata", false)) if nf["tipo"] in ["DD", "APD"] else int(nf["mun"]) > 0:
					forza += _art(nf)
		for tid in tfs[eng.nemico(s)]:
			for nid in st["tf"][tid]["navi"]:
				forza_n += _art(st["navi"][nid])
		rq1[s] = {"h": [h.x, h.y], "forza": forza, "forza_nemica_circa": forza_n, "contegni": contegni, "banale": forza <= 0}
	var r1: Dictionary = await _simul(eng, "sup_ingaggio", rq1)
	if eng.stop_requested:
		return
	var chi_inizia := []
	for s in ["A", "J"]:
		if bool(r1.get(s, {}).get("ingaggia", false)) and int(rq1[s]["forza"]) > 0:
			chi_inizia.append(s)
	if chi_inizia.is_empty():
		return
	eng.add_log("*", "Combattimento di superficie in %s, voluto da %s." % [FTData.nome_hex(h), " e ".join(chi_inizia.map(func(x): return FTEngine.NOME_LATO[x]))], "combattimento")
	# ---- 2. posizioni segrete e dado segreto (19.2-19.4)
	var rq2 := {}
	for s in ["A", "J"]:
		var mie := []
		var nem := []
		for tid in tfs[s]:
			for nid in st["tf"][tid]["navi"]:
				var d := _desc_nave(st, nid, true)
				d["pos_ok"] = posizioni_ok(st["navi"][nid])
				mie.append(d)
		for tid in tfs[eng.nemico(s)]:
			for nid in st["tf"][tid]["navi"]:
				nem.append(_desc_nave(st, nid, false))
		rq2[s] = {"h": [h.x, h.y], "mie": mie, "nemiche": nem, "notte": notte}
	var r2: Dictionary = await _simul(eng, "sup_schiera", rq2)
	if eng.stop_requested:
		return
	var pos := {}
	var dadi := {}
	for s in ["A", "J"]:
		var ps: Dictionary = r2.get(s, {}).get("pos", {})
		for d in rq2[s]["mie"]:
			var p: String = str(ps.get(d["id"], ""))
			if not p in d["pos_ok"]:
				p = "schermo" if not "art" in d["pos_ok"] else "art"
			pos[d["id"]] = p
		dadi[s] = clampi(int(r2.get(s, {}).get("dado", 1)), 1, 6)
	var bht: int = dadi["A"] + dadi["J"]
	# chi combatte in linea o con i siluri non può bombardare la costa in questo turno (19.9)
	for nid in pos:
		if pos[nid] in ["art", "silu"]:
			st["navi"][nid]["sup_turno"] = int(st["turno"])
	var rep := ["dadi %d e %d, BHT %d" % [dadi["A"], dadi["J"], bht]]
	for s in ["A", "J"]:
		for tid in tfs[s]:
			st["tf"][tid]["svelata"] = true
			st["tf"][tid]["attaccata"] = true
	# ---- 3. artiglieria simultanea (19.5)
	var rq3 := {}
	for s in ["A", "J"]:
		var tot := 0
		var tot_bb := 0
		for tid in tfs[s]:
			for nid in st["tf"][tid]["navi"]:
				if pos.get(nid, "") != "art":
					continue
				var n2: Dictionary = st["navi"][nid]
				var f := _art(n2)
				if n2["tipo"] in ["DD", "APD"]:
					if n2.get("mun_usata", false):
						continue
					n2["mun_usata"] = true
				else:
					if int(n2["mun"]) <= 0:
						continue
					if int(n2["mun"]) < bht:
						f = (f + 1) / 2
						n2["mun"] = 0
					else:
						n2["mun"] = int(n2["mun"]) - bht
				tot += f
				if n2["tipo"] in ["BB", "BC", "CA", "CAV"]:
					tot_bb += f
		rq3[s] = _req_fuoco(eng, tfs[eng.nemico(s)], pos, ["art", "silu"], tot, tot_bb, bht, h)
	var r3: Dictionary = await _simul(eng, "sup_fuoco", rq3)
	if eng.stop_requested:
		return
	var danni := {}
	for s in ["A", "J"]:
		_risolvi_fuoco(eng, rq3[s], r3.get(s, {}).get("fuoco", {}), bht, danni, false)
		rep.append("%s %d fattori d'artiglieria" % [FTEngine.NOME_LATO[s], int(rq3[s]["tot"])])
	await _applica_danni_sup(eng, danni, rep)
	# ---- 4. siluri (19.6)
	var silu_ok := bht >= (7 if notte else 10)
	var rq4 := {}
	for s in ["A", "J"]:
		var ts := 0
		for tid in tfs[s]:
			if not st["tf"].has(tid):
				continue
			for nid in st["tf"][tid]["navi"]:
				var n3: Dictionary = st["navi"][nid]
				if pos.get(nid, "") == "silu" and not n3["affondata"] and not n3.get("silu_usati", false):
					ts += int(n3["silu"])
					n3["silu_usati"] = true
		if ts > 0 and silu_ok:
			rq4[s] = _req_fuoco(eng, tfs[eng.nemico(s)], pos, ["art", "silu"], ts, ts, 15 if s == "J" else 10, h)
		elif ts > 0:
			rep.append("%s lancia i siluri senza effetto (BHT troppo basso)" % FTEngine.NOME_LATO[s])
	if not rq4.is_empty():
		var r4: Dictionary = await _simul(eng, "sup_siluri", rq4)
		if eng.stop_requested:
			return
		var danni2 := {}
		for s in rq4:
			_risolvi_fuoco(eng, rq4[s], r4.get(s, {}).get("fuoco", {}), int(rq4[s]["bht"]), danni2, true)
			rep.append("%s lancia %d fattori di siluri" % [FTEngine.NOME_LATO[s], int(rq4[s]["tot"])])
		await _applica_danni_sup(eng, danni2, rep)
	# ---- 5. attacco di penetrazione (19.7)
	var resto := {"A": 0, "J": 0}
	for s in ["A", "J"]:
		for tid in tfs[s]:
			if not st["tf"].has(tid):
				continue
			for nid in st["tf"][tid]["navi"]:
				var nr: Dictionary = st["navi"][nid]
				# contano solo le navi che hanno ancora munizioni (19.7, 19.8)
				var carica: bool = (not nr.get("mun_usata", false)) if nr["tipo"] in ["DD", "APD"] else int(nr["mun"]) > 0
				if pos.get(nid, "") in ["art", "silu"] and not nr["affondata"] and carica:
					resto[s] += _art(nr)
	for s in ["A", "J"]:
		var e3: String = eng.nemico(s)
		if resto[s] <= 0 or resto[s] < 3 * maxi(1, resto[e3]):
			continue
		var rq5 := _req_fuoco(eng, tfs[e3], pos, ["schermo"], resto[s], resto[s], bht, h)
		if (rq5["bersagli"] as Array).is_empty():
			break
		rq5["k"] = "sup_penetra"
		var r5: Dictionary = await eng._decide(s, rq5)
		if eng.stop_requested:
			return
		if not bool(r5.get("penetra", false)):
			rep.append("%s rinuncia all'attacco di penetrazione" % FTEngine.NOME_LATO[s])
			break
		var danni3 := {}
		_risolvi_fuoco(eng, rq5, r5.get("fuoco", {}), bht, danni3, false)
		var schermo := 0
		for tid in tfs[e3]:
			if not st["tf"].has(tid):
				continue
			for nid in st["tf"][tid]["navi"]:
				if pos.get(nid, "") == "schermo":
					schermo += _art(st["navi"][nid])
		if schermo > 0:
			var rq6 := _req_fuoco(eng, tfs[s], pos, ["art", "silu"], schermo, schermo, bht, h)
			rq6["k"] = "sup_schermo"
			var r6: Dictionary = await eng._decide(e3, rq6)
			if eng.stop_requested:
				return
			_risolvi_fuoco(eng, rq6, r6.get("fuoco", {}), bht, danni3, false)
		rep.append("%s sfonda lo schermo nemico" % FTEngine.NOME_LATO[s])
		await _applica_danni_sup(eng, danni3, rep)
		break
	var txt := "Combattimento di superficie in %s: %s." % [FTData.nome_hex(h), "; ".join(rep)]
	eng.add_log("*", txt, "combattimento")
	eng.event.emit({"k": "superficie", "h": [h.x, h.y], "testo": txt})


static func _art(n: Dictionary) -> int:
	if n.get("he", false):
		return mini(int(n["art"]), 8)
	return int(n["art"])


## Richiesta di assegnazione del fuoco: fattori totali (e quelli che possono colpire le corazzate) e le
## navi nemiche bersagliabili.
static func _req_fuoco(eng, tfs_nem: Array, pos: Dictionary, posizioni: Array, tot: int, tot_bb: int, bht: int, h: Vector2i) -> Dictionary:
	var st: Dictionary = eng.st
	var bers := []
	for tid in tfs_nem:
		if not st["tf"].has(tid):
			continue
		for nid in st["tf"][tid]["navi"]:
			var n: Dictionary = st["navi"][nid]
			if n["affondata"] or not pos.get(nid, "") in posizioni:
				continue
			var d := _desc_nave(st, nid, true)
			d["pos"] = pos[nid]
			bers.append(d)
	return {"h": [h.x, h.y], "tot": tot, "tot_bb": tot_bb, "bht": bht, "bersagli": bers, "banale": tot <= 0 or bers.is_empty()}


static func ai_alloca(eng, req: Dictionary) -> Dictionary:
	var st: Dictionary = eng.st
	var bers := []
	for d in req.get("bersagli", []):
		var n: Dictionary = st["navi"][d["id"]]
		bers.append([priorita_nave(n["tipo"]), -_art(n), d["id"]])
	bers.sort()
	var out := {}
	var resto: int = int(req.get("tot", 0))
	var resto_bb: int = int(req.get("tot_bb", 0))
	for b in bers:
		if resto <= 0:
			break
		var n2: Dictionary = st["navi"][b[2]]
		var serve: int = maxi(2, (int(n2["danno"]) - int(n2["hits"])) * 2)
		var f := mini(resto, serve)
		if n2["tipo"] in ["BB", "BC"]:
			f = mini(f, resto_bb)
			resto_bb -= f
		if f <= 0:
			continue
		resto -= f
		out[b[2]] = f
	# l'avanzo va sul primo bersaglio
	if resto > 0 and not bers.is_empty():
		for b in bers:
			var n3: Dictionary = st["navi"][b[2]]
			if n3["tipo"] in ["BB", "BC"] and resto_bb <= 0:
				continue
			out[b[2]] = int(out.get(b[2], 0)) + resto
			break
	return out


## Applica un'assegnazione di fuoco (controllata: totale e limite contro le corazzate).
static func _risolvi_fuoco(eng, req: Dictionary, fuoco: Dictionary, bht: int, danni: Dictionary, siluri: bool) -> void:
	var st: Dictionary = eng.st
	if int(req.get("tot", 0)) <= 0 or (req.get("bersagli", []) as Array).is_empty():
		return
	var ok_id := {}
	for d in req["bersagli"]:
		ok_id[d["id"]] = true
	var resto: int = int(req["tot"])
	var resto_bb: int = int(req["tot_bb"])
	var usato := {}
	for nid in fuoco:
		if not ok_id.has(nid):
			continue
		var f := clampi(int(fuoco[nid]), 0, resto)
		var n: Dictionary = st["navi"][nid]
		if n["tipo"] in ["BB", "BC"] and not siluri:
			f = mini(f, resto_bb)
			resto_bb -= f
		resto -= f
		if f > 0:
			usato[nid] = f
	if usato.is_empty():
		usato = ai_alloca(eng, req)
	for nid in usato:
		var n2: Dictionary = st["navi"][nid]
		var bh := bht
		if n2["ancorata"]:
			bh += 1
		if int(n2["danno"]) >= 3 and int(n2["hits"]) >= int(n2["danno"]) - 1:
			bh += 1
		var c := tiro(eng, bh, int(usato[nid]))
		danni[nid] = int(danni.get(nid, 0)) + c


static func _applica_danni_sup(eng, danni: Dictionary, rep: Array) -> void:
	var st: Dictionary = eng.st
	for nid in danni:
		var n: Dictionary = st["navi"][nid]
		if n["affondata"] or int(danni[nid]) <= 0:
			continue
		var esito: String = await colpi_nave(eng, nid, int(danni[nid]), false, eng.nemico(n["lato"]))
		rep.append("%s %s: %s" % [n["nome"], n["tipo"], esito])


static func ai_sup_ingaggio(_eng, _s: String, req: Dictionary) -> Dictionary:
	var vuole := false
	var f: int = int(req.get("forza", 0))
	var fn: int = int(req.get("forza_nemica_circa", 0))
	for c in req.get("contegni", []):
		if str(c) in ["attacca", "bombarda"] and f * 5 >= fn * 4:
			vuole = true
	if f >= 2 * maxi(1, fn) and f >= 10:
		vuole = true
	return {"ingaggia": vuole}


static func ai_sup_schiera(_eng, _s: String, req: Dictionary) -> Dictionary:
	var notte: bool = bool(req.get("notte", false))
	var pos := {}
	var forza := 0
	var forza_n := 0
	for d in req["mie"]:
		var p := "art"
		var ok: Array = d["pos_ok"]
		if d["tipo"] in ["CV", "CVL", "AP", "AO", "PG", "AV"] or not "art" in ok:
			p = "schermo"
		elif "silu" in ok and (notte or d["tipo"] == "DD"):
			p = "silu"
		elif int(d["art"]) <= 0 or (int(d["mun"]) <= 0 and not d["tipo"] in ["DD", "APD"]):
			p = "schermo"
		if not p in ok:
			p = ok[0]
		pos[d["id"]] = p
		if p == "art":
			forza += int(d["art"])
	for d2 in req["nemiche"]:
		if not d2["tipo"] in ["CV", "CVL", "AP", "AO", "PG", "AV"]:
			forza_n += int(d2["art"])
	return {"pos": pos, "dado": 6 if forza >= forza_n else 1}


## Bombardamento costiero (19.9): TF con contegno «bombarda» nell'esagono di una base nemica.
static func bombardamento(eng, h: Vector2i, s: String) -> void:
	var st: Dictionary = eng.st
	var base := ""
	for bid in st["basi"]:
		var b: Dictionary = st["basi"][bid]
		if b["lato"] != s and not b["fuori"] and eng.vh(b["hex"]) == h:
			base = bid
	if base == "":
		return
	var f := 0
	var navi := []
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		if tf["lato"] != s or eng.tf_hex(tid) != h or str(tf.get("contegno", "")) != "bombarda":
			continue
		for nid in tf["navi"]:
			var n: Dictionary = st["navi"][nid]
			if n["affondata"] or not n["tipo"] in ["BB", "CAV", "CA", "CL"] or int(n["mun"]) < 8:
				continue
			if int(n.get("sup_turno", -1)) == int(st["turno"]):
				continue
			var art: int = int(n["art"])
			if n.get("he", false):
				art = 16
			f += art
			n["mun"] = int(n["mun"]) - 8
			navi.append(nid)
	if f <= 0:
		return
	var colpi := tiro(eng, 8, f)
	await colpi_base(eng, base, colpi, false, s)
	var txt := "Bombardamento navale di %s: %d colpi." % [st["basi"][base]["nome"], colpi]
	var sf: int = int(st["basi"][base]["sf"])
	if sf > 0 and not navi.is_empty():
		var c2 := tiro(eng, 8, sf)
		if c2 > 0:
			var esito: String = await colpi_nave(eng, navi[0], c2, false, st["basi"][base]["lato"])
			txt += " Le batterie costiere colpiscono %s: %s." % [st["navi"][navi[0]]["nome"], esito]
	eng.add_log("*", txt, "combattimento")
	eng.event.emit({"k": "bombardamento", "h": [h.x, h.y], "testo": txt})
