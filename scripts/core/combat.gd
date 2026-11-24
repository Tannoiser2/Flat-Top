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
	# anche gli esagoni entro 2 da una portaerei/base con AF nemiche osservate (intercettazione)
	hexes.sort_custom(func(a, b): return a.x * 1000 + a.y < b.x * 1000 + b.y)
	for h in hexes:
		if eng.tempesta(h):
			continue
		battaglia(eng, h)
	# intercettazioni entro due esagoni da portaerei o basi (16.1.2)
	_intercettazioni_vicine(eng)


static func battaglia(eng, h: Vector2i) -> void:
	var st: Dictionary = eng.st
	var con_navi_basi := _ha_nave_o_base(eng, h)
	if con_navi_basi:
		for s in ["A", "J"]:
			aria_aria(eng, h, s, true)
	for s in ["A", "J"]:
		attacco_aereo(eng, h, s)
	superficie(eng, h)
	for s in ["A", "J"]:
		bombardamento(eng, h, s)


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
		if nh.x > -100 and FTData.dist(nh, h) <= 2:
			return true
	return false


static func _intercettazioni_vicine(eng) -> void:
	var st: Dictionary = eng.st
	var fatti := {}
	for fid in st["af"].keys():
		if not st["af"].has(fid):
			continue
		var af: Dictionary = st["af"][fid]
		var h: Vector2i = eng.af_hex(fid)
		if fatti.has(h) or _ha_nave_o_base(eng, h):
			continue
		var s: String = af["lato"]
		var e: String = eng.nemico(s)
		# il lato s ha intercettori qui ed è entro 2 esagoni da una sua portaerei o base
		if not _vicino_nido(eng, h, s):
			continue
		var nemici := false
		for f2 in st["af"]:
			if st["af"][f2]["lato"] == e and eng.af_hex(f2) == h and int(st["noti"][s].get(f2, {}).get("cond", 0)) >= 1:
				nemici = true
				break
		if not nemici:
			continue
		fatti[h] = true
		aria_aria(eng, h, s, false)


# ================================================================ aria-aria

## Classificazione degli aerei di un lato in un esagono e a una quota.
## Restituisce {intercettori:[{fid, gi}], scorte:[...], bombardieri:[...]} (fid = AF, gi = indice del gruppo).
static func _classifica(eng, h: Vector2i, s: String, quota: String, ha_bomb_lato: bool) -> Dictionary:
	var st: Dictionary = eng.st
	var out := {"int": [], "sco": [], "bom": []}
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if af["lato"] != s or eng.af_hex(fid) != h or af["quota"] != quota:
			continue
		var bomber_af := false
		for g in af["gruppi"]:
			var r: String = FTData.aerei[g["tipo"]]["ruoli"]
			if g["arma"] != "" or not r.contains("I"):
				bomber_af = true
		for gi in af["gruppi"].size():
			var g2: Dictionary = af["gruppi"][gi]
			var r2: String = FTData.aerei[g2["tipo"]]["ruoli"]
			var armato: bool = g2["arma"] != ""
			if bomber_af:
				if not armato and r2.contains("E"):
					out["sco"].append({"fid": fid, "gi": gi})
				else:
					out["bom"].append({"fid": fid, "gi": gi})
			else:
				var puo := r2.contains("I") and (not r2.contains("I*") or quota == "B")
				if puo:
					if ha_bomb_lato:
						if r2.contains("E"):
							out["sco"].append({"fid": fid, "gi": gi})
					else:
						out["int"].append({"fid": fid, "gi": gi})
				else:
					out["bom"].append({"fid": fid, "gi": gi})
	return out


static func _tot(eng, lst: Array) -> int:
	var t := 0
	for it in lst:
		t += int(eng.st["af"][it["fid"]]["gruppi"][it["gi"]]["q"])
	return t


static func _lato_ha_bombardieri(eng, h: Vector2i, s: String) -> bool:
	var st: Dictionary = eng.st
	for fid in st["af"]:
		var af: Dictionary = st["af"][fid]
		if af["lato"] == s and eng.af_hex(fid) == h:
			for g in af["gruppi"]:
				if g["arma"] != "" and g["arma"] != "x":
					return true
	return false


## Il lato «att» usa i suoi intercettori contro gli aerei nemici dell'esagono (16).
## sicuro = true nell'esagono con navi o basi (niente tabella di intercettazione).
static func aria_aria(eng, h: Vector2i, att: String, sicuro: bool) -> void:
	var st: Dictionary = eng.st
	var dif: String = eng.nemico(att)
	var ha_bomb_att := _lato_ha_bombardieri(eng, h, att)
	if ha_bomb_att:
		return  # i suoi caccia scortano i propri bombardieri (14.17)
	for quota in ["A", "B"]:
		var A := _classifica(eng, h, att, quota, false)
		var D := _classifica(eng, h, dif, quota, _lato_ha_bombardieri(eng, h, dif))
		# solo aerei nemici osservati
		var D_sco := []
		var D_bom := []
		for it in D["sco"] + D["int"]:
			if int(st["noti"][att].get(it["fid"], {}).get("cond", 0)) >= 1:
				D_sco.append(it)
		for it in D["bom"]:
			if int(st["noti"][att].get(it["fid"], {}).get("cond", 0)) >= 1:
				D_bom.append(it)
		var I: Array = A["int"]
		var ni := _tot(eng, I)
		if ni <= 0 or (_tot(eng, D_sco) + _tot(eng, D_bom)) <= 0:
			continue
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
		var notte: bool = eng.notte()
		var nuv: bool = eng.meteo(h) >= 1
		var nsco := _tot(eng, D_sco)
		var nbom := _tot(eng, D_bom)
		# divisione degli intercettori: metà contro le scorte (se ci sono), il resto contro i bombardieri
		var I_sco := []
		var I_bom := []
		if nsco > 0 and nbom > 0:
			var meta := 0
			for it in I:
				var q: int = st["af"][it["fid"]]["gruppi"][it["gi"]]["q"]
				if meta * 2 < ni:
					I_sco.append(it)
					meta += q
				else:
					I_bom.append(it)
			if I_bom.is_empty() and I_sco.size() > 1:
				I_bom.append(I_sco.pop_back())
		elif nsco > 0:
			I_sco = I.duplicate()
		else:
			I_bom = I.duplicate()
		var rep := []
		_spendi_rf(eng, I)
		# intercettori contro scorte
		if not I_sco.is_empty() and nsco > 0:
			_spendi_rf(eng, D_sco)
			var p1 := _duello(eng, I_sco, D_sco, nuv, notte)
			var p2 := _duello(eng, D_sco, I_sco, nuv, notte)
			_applica_perdite(eng, p1, dif)
			_applica_perdite(eng, p2, att)
			rep.append("intercettori contro scorte: %d abbattuti contro %d" % [_somma(p1), _somma(p2)])
			var si := _tot(eng, _vivi(eng, I_sco))
			var ss := _tot(eng, _vivi(eng, D_sco))
			if ss > 0 and ss >= 2 * si:
				I_bom = []
				rep.append("le scorte respingono l'attacco")
			elif si >= 2 * maxi(1, ss) or ss == 0:
				I_bom = I_bom + I_sco
		I_bom = _vivi(eng, I_bom)
		D_bom = _vivi(eng, D_bom)
		if not I_bom.is_empty() and not D_bom.is_empty():
			var p3 := _duello(eng, I_bom, D_bom, nuv, notte)
			var p4 := _duello(eng, D_bom, I_bom, nuv, notte)
			_applica_perdite(eng, p3, dif)
			_applica_perdite(eng, p4, att)
			rep.append("intercettori contro bombardieri: %d abbattuti contro %d" % [_somma(p3), _somma(p4)])
		st["combattuti_ora"][att + str(h)] = true
		st["combattuti_ora"][dif + str(h)] = true
		if not rep.is_empty():
			var txt := "Combattimento aereo in %s (%s quota): %s." % [FTData.nome_hex(h), "alta" if quota == "A" else "bassa", "; ".join(rep)]
			eng.add_log("*", txt, "combattimento")
			eng.event.emit({"k": "aria", "h": [h.x, h.y], "testo": txt})
		_pulisci_af(eng)


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
		if a2["lato"] == e and eng.af_hex(f2) == h and bool(a2["esposta"]) and a2["quota"] == af["quota"]:
			for g in a2["gruppi"]:
				if g["arma"] == "" and FTData.aerei[g["tipo"]]["ruoli"].contains("I"):
					ci_sono = true
	if not ci_sono or int(st["noti"][e].get(fid, {}).get("cond", 0)) < 1:
		return
	if not st.has("_intercettati"):
		st["_intercettati"] = {}
	st["_intercettati"][key] = true
	aria_aria(eng, h, e, false)


# ================================================================ contraerea e attacco aereo

static func attacco_aereo(eng, h: Vector2i, att: String) -> void:
	var st: Dictionary = eng.st
	var dif: String = eng.nemico(att)
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
	var notte: bool = eng.notte()
	var nuv: bool = eng.meteo(h) >= 1
	for fid in st["af"].keys():
		if not st["af"].has(fid):
			continue
		var af: Dictionary = st["af"][fid]
		if af["lato"] != att or eng.af_hex(fid) != h:
			continue
		var armati := []
		for gi in af["gruppi"].size():
			var g: Dictionary = af["gruppi"][gi]
			if g["arma"] != "" and g["arma"] != "x" and int(g["q"]) > 0:
				armati.append(gi)
		if armati.is_empty():
			continue
		var miss: Dictionary = af.get("missione", {})
		var vuole_base := str(miss.get("bersaglio_base", "")) == base and base != ""
		if str(miss.get("tipo", "")) == "manuale" and str(miss.get("bersaglio_base", "")) == "" and str(miss.get("bersaglio", "")) == "" and not tfs.is_empty():
			vuole_base = false
		if tfs.is_empty():
			vuole_base = base != ""
		if not vuole_base and tfs.is_empty():
			continue
		# assegnazione dei bersagli
		var assegna := []   # [gi, "nave"/"base", id, metodo]
		if vuole_base:
			for gi in armati:
				assegna.append([gi, "base", base, _metodo(af, af["gruppi"][gi], true)])
		else:
			var navi := []
			var pref: String = str(miss.get("bersaglio", ""))
			for tid in tfs:
				for nid in st["tf"][tid]["navi"]:
					var n: Dictionary = st["navi"][nid]
					if n["affondata"]:
						continue
					var pri := priorita_nave(n["tipo"])
					if str(miss.get("priorita", "")) == "trasporti" and n["tipo"] in ["AP", "APD"]:
						pri = -1
					if tid == pref:
						pri -= 10
					navi.append([pri, -int(n["danno"]) + int(n["hits"]), nid])
			navi.sort()
			if navi.is_empty():
				continue
			# concentra sul primo bersaglio finché i colpi attesi non bastano ad affondarlo, poi passa al successivo
			var idx := 0
			var attesi := 0.0
			var ord := armati.duplicate()
			ord.sort_custom(func(a, b): return int(af["gruppi"][a]["q"]) > int(af["gruppi"][b]["q"]))
			for gi in ord:
				var nid: String = navi[idx][2]
				var n2: Dictionary = st["navi"][nid]
				var g3: Dictionary = af["gruppi"][gi]
				var met := _metodo(af, g3, false)
				assegna.append([gi, "nave", nid, met])
				var bh := _bht_attacco(eng, g3, met, false, n2, nuv, notte)
				attesi += maxf(0.3, float(FTData.crt_numero(bh, int(g3["q"]))))
				if attesi >= float(int(n2["danno"]) - int(n2["hits"])) * 1.3 and idx < navi.size() - 1:
					idx += 1
					attesi = 0.0
		# contraerea: un tiro per ogni gruppo (tipo d'aereo) dell'AF
		var aaf_tot := 0
		if vuole_base:
			aaf_tot = maxi(0, int(st["basi"][base]["aaf"]))
			for tid in st["tf"]:
				if st["tf"][tid]["lato"] == dif and eng.tf_hex(tid) == h:
					for nid in st["tf"][tid]["navi"]:
						if st["navi"][nid]["ancorata"]:
							aaf_tot += int(st["navi"][nid]["aa"])
		else:
			var tf_colpite := {}
			for a in assegna:
				tf_colpite[st["navi"][a[2]]["tf"]] = true
			for tid in tf_colpite:
				for nid in st["tf"][tid]["navi"]:
					if not st["navi"][nid]["affondata"]:
						aaf_tot += int(st["navi"][nid]["aa"])
			if base != "" and int(st["basi"][base]["aaf"]) > 0:
				for tid in tf_colpite:
					if st["tf"][tid]["ancorata"]:
						aaf_tot += int(st["basi"][base]["aaf"])
						break
		var tot_att := 0
		for a in assegna:
			tot_att += int(af["gruppi"][a[0]]["q"])
		var abb_tot := 0
		for a in assegna:
			var g4: Dictionary = af["gruppi"][a[0]]
			var quota_aa: String = "B" if a[3] in ["dv", "to", "ll"] else "A"
			var parte: int = aaf_tot if assegna.size() == 1 else maxi(1, roundi(float(aaf_tot) * int(g4["q"]) / maxi(1, tot_att)))
			if parte <= 0:
				continue
			var bht := 4
			if quota_aa == "A":
				bht -= 2
			if nuv:
				bht -= 1
			if notte:
				bht -= 2
			var colpi := tiro(eng, maxi(1, bht), parte)
			colpi = mini(colpi, int(g4["q"]))
			if colpi > 0:
				g4["q"] = int(g4["q"]) - colpi
				eng._perdita(att, g4["tipo"], colpi, false)
				abb_tot += colpi
		# attacco
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
				colpi_base(eng, a[2], colpi2, a[3] in ["dv", "ll"] and not notte, att)
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
				var esito := colpi_nave(eng, a[2], colpi3, a[3] in ["dv", "ll"] and not notte, att)
				rep.append("%d %s %s su %s %s: %s" % [q, g5["tipo"], _nome_metodo(a[3]), n3["nome"], n3["tipo"], esito])
		if sopravvissuti and not vuole_base:
			for tid in tfs:
				st["tf"][tid]["svelata"] = true
		if vuole_base:
			st["attaccate"][base] = true
		var txt := "Attacco aereo in %s (AF %d): contraerea %d abbattuti. %s." % [FTData.nome_hex(h), af["num"], abb_tot, "; ".join(rep) if not rep.is_empty() else "Nessun aereo arriva sul bersaglio"]
		eng.add_log("*", txt, "combattimento")
		eng.event.emit({"k": "attacco", "h": [h.x, h.y], "testo": txt, "lato": att})
		_pulisci_af(eng)


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


## Metodo di attacco: siluro se armato di siluri, picchiata se può e vola alto, altrimenti livello alla quota dell'AF.
static func _metodo(af: Dictionary, g: Dictionary, contro_base: bool) -> String:
	if g["arma"] == "T" and not contro_base:
		return "to"
	var b: Dictionary = FTData.aerei[g["tipo"]]["bht"]
	var k: String = str(g["arma"]).to_lower()
	if k == "t":
		k = "gp"
	var pre := "b_" if contro_base else "s_"
	if af["quota"] == "A" and int(b.get(pre + "dv_" + k, 0)) > 0:
		return "dv"
	if af["quota"] == "A" and int(b.get(pre + "hl_" + k, 0)) > 0:
		return "hl"
	if int(b.get(pre + "ll_" + k, 0)) > 0:
		return "ll"
	if int(b.get(pre + "hl_" + k, 0)) > 0:
		return "hl"
	return "ll"


static func _bht_attacco(eng, g: Dictionary, metodo: String, contro_base: bool, nave: Dictionary, nuv: bool, notte: bool) -> int:
	var b: Dictionary = FTData.aerei[g["tipo"]]["bht"]
	var k: String = str(g["arma"]).to_lower()
	if k == "x" or k == "":
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
	if st["nidi"].has(nid):
		_distruggi_aerei(eng, nid, nuovi, sceglie_att, false)
	if int(n["hits"]) >= int(n["danno"]):
		n["affondata"] = true
		# punti: valore pieno, tolti quelli già dati per i danni
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
	# aerei a bordo persi per sempre (niente rimpiazzi)
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
		# le AF in volo sopra di lei restano in aria e cercano un'altra casa
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


static func _distruggi_aerei(eng, nid: String, colpi: int, sceglie_att: bool, base_disp: bool) -> void:
	var st: Dictionary = eng.st
	var nido: Dictionary = st["nidi"][nid]
	var lato: String = nido["lato"]
	var resta := colpi
	for box in ["pronti", "jl", "prep"]:
		while resta > 0 and not nido[box].is_empty():
			var keys: Array = nido[box].keys()
			# l'attaccante sceglie i più preziosi (bombardieri), il difensore i meno preziosi
			keys.sort_custom(func(a, b): return _val_aereo(a) > _val_aereo(b) if sceglie_att else _val_aereo(a) < _val_aereo(b))
			var k: String = keys[0]
			var q: int = mini(resta, int(nido[box][k]))
			FTEngine._add(nido[box], k, -q)
			eng._perdita(lato, k.split("|")[0], q, false)
			resta -= q
	if base_disp:
		while resta >= 2 and not nido["disp"].is_empty():
			var k2: String = nido["disp"].keys()[0]
			FTEngine._add(nido["disp"], k2, -1)
			eng._perdita(lato, k2, 1, false)
			resta -= 2


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
		_distruggi_aerei(eng, bid, colpi, sceglie_att, true)
	st["attaccate"][bid] = true


# ================================================================ combattimento di superficie

static func superficie(eng, h: Vector2i) -> void:
	var st: Dictionary = eng.st
	var tfs := {"A": [], "J": []}
	var vuole := false
	for tid in st["tf"]:
		var tf: Dictionary = st["tf"][tid]
		if tf["navi"].is_empty() or tf.get("fuori", false) or eng.tf_hex(tid) != h:
			continue
		var e: String = eng.nemico(tf["lato"])
		tfs[tf["lato"]].append(tid)
	if tfs["A"].is_empty() or tfs["J"].is_empty():
		return
	# serve che entrambi sappiano dell'altro e che qualcuno voglia combattere
	var visti := {"A": false, "J": false}
	for s in ["A", "J"]:
		for tid in tfs[eng.nemico(s)]:
			if int(st["noti"][s].get(tid, {}).get("cond", 0)) >= 1:
				visti[s] = true
	if not (visti["A"] and visti["J"]):
		return
	for s in ["A", "J"]:
		for tid in tfs[s]:
			if str(st["tf"][tid].get("contegno", "evita")) in ["attacca", "bombarda"]:
				vuole = true
	if not vuole:
		return
	var notte: bool = eng.notte()
	var pos := {}  # nid -> "art" / "silu" / "schermo"
	var forza := {"A": 0, "J": 0}
	for s in ["A", "J"]:
		for tid in tfs[s]:
			for nid in st["tf"][tid]["navi"]:
				var n: Dictionary = st["navi"][nid]
				var p := "art"
				if n["tipo"] in ["CV", "CVL", "AP", "AO", "PG", "AV"] or n["ancorata"] or (int(n["danno"]) >= 3 and int(n["hits"]) >= int(n["danno"]) - 1):
					p = "schermo"
				elif int(n["silu"]) > 0 and (notte or n["tipo"] == "DD") and not n.get("silu_usati", false):
					p = "silu"
				elif int(n["art"]) <= 0 or (int(n["mun"]) <= 0 and not n["tipo"] in ["DD", "APD"]):
					p = "schermo"
				pos[nid] = p
				if p == "art":
					forza[s] += _art(n)
	# dadi segreti: chi è più forte sceglie 6, chi è più debole 1
	var da: int = 6 if forza["A"] >= forza["J"] else 1
	var dj: int = 6 if forza["J"] >= forza["A"] else 1
	var bht: int = da + dj
	var rep := []
	# artiglieria simultanea
	var danni := {}
	for s in ["A", "J"]:
		var e: String = eng.nemico(s)
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
		_spara(eng, tfs[e], pos, tot, tot_bb, bht, danni, ["art", "silu"])
		rep.append("%s %d fattori d'artiglieria" % [FTEngine.NOME_LATO[s], tot])
	_applica_danni_sup(eng, danni, rep)
	# siluri
	var danni2 := {}
	var silu_ok := bht >= (7 if notte else 10)
	for s in ["A", "J"]:
		var e2: String = eng.nemico(s)
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
			var tb := 15 if s == "J" else 10
			_spara(eng, tfs[e2], pos, ts, ts, tb, danni2, ["art", "silu"], true)
			rep.append("%s lancia %d fattori di siluri" % [FTEngine.NOME_LATO[s], ts])
	_applica_danni_sup(eng, danni2, rep)
	# attacco di penetrazione (3:1)
	var resto := {"A": 0, "J": 0}
	for s in ["A", "J"]:
		for tid in tfs[s]:
			if not st["tf"].has(tid):
				continue
			for nid in st["tf"][tid]["navi"]:
				if pos.get(nid, "") in ["art", "silu"] and not st["navi"][nid]["affondata"]:
					resto[s] += _art(st["navi"][nid])
	for s in ["A", "J"]:
		var e3: String = eng.nemico(s)
		if resto[s] > 0 and resto[s] >= 3 * maxi(1, resto[e3]):
			var danni3 := {}
			_spara(eng, tfs[e3], pos, resto[s], resto[s], bht, danni3, ["schermo"])
			var schermo := 0
			for tid in tfs[e3]:
				if not st["tf"].has(tid):
					continue
				for nid in st["tf"][tid]["navi"]:
					if pos.get(nid, "") == "schermo":
						schermo += _art(st["navi"][nid])
			if schermo > 0:
				_spara(eng, tfs[s], pos, schermo, schermo, bht, danni3, ["art", "silu"])
			rep.append("%s sfonda lo schermo nemico" % FTEngine.NOME_LATO[s])
			_applica_danni_sup(eng, danni3, rep)
			break
	for s in ["A", "J"]:
		for tid in tfs[s]:
			if st["tf"].has(tid):
				st["tf"][tid]["svelata"] = true
	var txt := "Combattimento di superficie in %s (BHT %d): %s." % [FTData.nome_hex(h), bht, "; ".join(rep)]
	eng.add_log("*", txt, "combattimento")
	eng.event.emit({"k": "superficie", "h": [h.x, h.y], "testo": txt})


static func _art(n: Dictionary) -> int:
	if n.get("he", false):
		return mini(int(n["art"]), 8)
	return int(n["art"])


## Distribuisce fattori d'artiglieria (o siluri) sulle navi nemiche nelle posizioni indicate.
static func _spara(eng, tfs_nem: Array, pos: Dictionary, tot: int, tot_bb: int, bht: int, danni: Dictionary, posizioni: Array, siluri := false) -> void:
	var st: Dictionary = eng.st
	var bers := []
	for tid in tfs_nem:
		if not st["tf"].has(tid):
			continue
		for nid in st["tf"][tid]["navi"]:
			var n: Dictionary = st["navi"][nid]
			if n["affondata"] or not pos.get(nid, "") in posizioni:
				continue
			bers.append([priorita_nave(n["tipo"]), -_art(n), nid])
	if bers.is_empty() or tot <= 0:
		return
	bers.sort()
	var resto := tot
	var resto_bb := tot_bb
	for b in bers:
		if resto <= 0:
			break
		var n2: Dictionary = st["navi"][b[2]]
		var serve: int = maxi(2, (int(n2["danno"]) - int(n2["hits"])) * 2)
		var f := mini(resto, serve)
		if n2["tipo"] in ["BB", "BC"] and not siluri:
			f = mini(f, resto_bb)
			resto_bb -= f
		if f <= 0:
			continue
		resto -= f
		var bh := bht
		if n2["ancorata"]:
			bh += 1
		if int(n2["danno"]) >= 3 and int(n2["hits"]) >= int(n2["danno"]) - 1:
			bh += 1
		var c := tiro(eng, bh, f)
		danni[b[2]] = int(danni.get(b[2], 0)) + c


static func _applica_danni_sup(eng, danni: Dictionary, rep: Array) -> void:
	var st: Dictionary = eng.st
	for nid in danni:
		var n: Dictionary = st["navi"][nid]
		if n["affondata"] or int(danni[nid]) <= 0:
			continue
		var esito := colpi_nave(eng, nid, int(danni[nid]), false, eng.nemico(n["lato"]))
		rep.append("%s %s: %s" % [n["nome"], n["tipo"], esito])


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
			var art: int = int(n["art"])
			if n.get("he", false):
				art = 16
			f += art
			n["mun"] = int(n["mun"]) - 8
			navi.append(nid)
	if f <= 0:
		return
	var colpi := tiro(eng, 8, f)
	colpi_base(eng, base, colpi, false, s)
	var txt := "Bombardamento navale di %s: %d colpi." % [st["basi"][base]["nome"], colpi]
	# la base risponde con il suo fattore di superficie
	var sf: int = int(st["basi"][base]["sf"])
	if sf > 0 and not navi.is_empty():
		var c2 := tiro(eng, 8, sf)
		if c2 > 0:
			var esito := colpi_nave(eng, navi[0], c2, false, st["basi"][base]["lato"])
			txt += " Le batterie costiere colpiscono %s: %s." % [st["navi"][navi[0]]["nome"], esito]
	eng.add_log("*", txt, "combattimento")
	eng.event.emit({"k": "bombardamento", "h": [h.x, h.y], "testo": txt})
