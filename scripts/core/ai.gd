class_name FTAI
extends RefCounted
## Ammiraglio artificiale. Gioca solo con quello che il suo lato sa: le proprie unità e gli avvistamenti
## (st.noti e st.memoria del suo lato). Non conosce mai la posizione delle unità nemiche nascoste.
##
## Ogni turno:
##  - tiene la pattuglia aerea (CAP) sopra le portaerei e le basi esposte;
##  - manda ricognitori a ventaglio verso le zone da cui può arrivare il nemico;
##  - lancia attacchi coordinati contro le portaerei (o i bersagli di scenario) a portata;
##  - muove le portaerei per restare a distanza d'attacco ma fuori dalla portata nemica,
##    porta i trasporti allo sbarco e manda le navi di superficie ad attaccare di notte.

const PILOT := preload("res://scripts/core/pilot.gd")

var lato := "A"
var livello := 2   # 1 facile, 2 normale, 3 esperto
var piani := {}    # memoria propria fra un turno e l'altro (zone già cercate, punti di partenza)


func _init(s := "A") -> void:
	lato = s


const COMBAT := preload("res://scripts/core/combat.gd")


func decide(eng, s: String, req: Dictionary) -> Dictionary:
	lato = s
	if str(req.get("k", "")) in COMBAT.DECISIONI:
		return COMBAT.ai_decide(eng, s, req)
	match str(req.get("k", "")):
		"schieramento":
			return schieramento(eng, req)
		"ordini":
			return ordini(eng)
		"aria":
			return {}
	return {}


# ================================================================ ordini del turno

## Schieramento segreto: le portaerei il più lontano possibile dalle basi nemiche, le altre TF verso
## l'obiettivo; un po' di caso (stabile con il seme) per non essere prevedibili.
func schieramento(eng, req: Dictionary) -> Dictionary:
	var st: Dictionary = eng.st
	var r: Dictionary = req.get("per", {}).get(lato, req)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(st["seed"]) * 7 + (1 if lato == "A" else 2)
	var basi_nem := []
	for bid in st["basi"]:
		if st["basi"][bid]["lato"] != lato and not st["basi"][bid]["fuori"]:
			basi_nem.append(eng.vh(st["basi"][bid]["hex"]))
	var sc := FTData.scenario(st["scen"])
	var obj: Dictionary = sc.get("obiettivi", {}).get(lato, {})
	var meta := Vector2i(-1, -1)
	for k in ["sbarco", "attacca_base"]:
		var b: String = str(obj.get(k, ""))
		if st["basi"].has(b):
			meta = eng.vh(st["basi"][b]["hex"])
			break
	if meta.x < 0 and str(obj.get("sbarco", "")) == "guadalcanal":
		meta = Vector2i(52, 23)
	var pos := {}
	var out_entra := {}
	var tids: Array = r.get("tf", {}).keys()
	tids.sort()
	for tid in tids:
		var z: Array = r["tf"][tid]["zona"]
		var cv := false
		for nid in st["tf"][tid]["navi"]:
			if st["navi"][nid]["tipo"] in ["CV", "CVL"]:
				cv = true
		var punti := []
		for h in z:
			var v := 0.0
			if cv or meta.x < 0:
				var dm := 99
				for bh in basi_nem:
					dm = mini(dm, FTData.dist(h, bh))
				v = float(mini(dm, 14))
			else:
				v = -float(FTData.dist(h, meta))
			punti.append([v + rng.randf() * 2.0, h])
		punti.sort_custom(func(a, b): return a[0] > b[0])
		var scelta: Vector2i = punti[rng.randi_range(0, mini(punti.size() - 1, maxi(0, punti.size() / 6)))][1]
		pos[tid] = [scelta.x, scelta.y]
		if r["tf"][tid].has("entra_tra"):
			if not out_entra.has(tid):
				out_entra[tid] = int(r["tf"][tid]["entra_tra"][0])
	return {"pos": pos, "entra": out_entra}


func ordini(eng) -> Dictionary:
	var st: Dictionary = eng.st
	var o := {"lanci": [], "rotte": {}, "cap": {}, "contegno": {}, "ancora": {}, "pedina": {}, "auto": {}, "contro_basi": {}}
	var t: int = st["turno"]
	var ora: int = st["ora"]
	var notte: bool = eng.notte()
	var notte_prossima := FTData.is_notte(ora % 24 + 1)
	if not piani.has("partenza"):
		piani["partenza"] = {}
		for tid in eng.tf_del_lato(lato):
			piani["partenza"][tid] = st["tf"][tid]["hex"].duplicate()
	var contatti := _contatti(eng)
	var sc := FTData.scenario(st["scen"])
	var obj: Dictionary = sc.get("obiettivi", {}).get(lato, {})
	# ---- preparazione: sempre automatica; armamento contro basi se l'obiettivo è una base e non ci sono navi
	var navi_nemiche_note := false
	for c in contatti:
		if c["tipo"] == "tf":
			navi_nemiche_note = true
	for nid in eng.nidi_del_lato(lato):
		o["auto"][nid] = true
		o["contro_basi"][nid] = obj.has("attacca_base") and not navi_nemiche_note and st["navi"].has(nid) == false
		if obj.has("attacca_base") and str(obj["attacca_base"]) == "rabaul":
			o["contro_basi"][nid] = not navi_nemiche_note
	# ---- pattuglia aerea
	var minaccia := _minaccia_aerea(eng, contatti)
	for nid in eng.nidi_del_lato(lato):
		var caccia := _caccia_nido(eng, nid)
		var cap := 0
		if not notte and not notte_prossima and caccia > 0:
			if st["navi"].has(nid):
				cap = clampi(int(caccia * (0.5 if minaccia else 0.3)), 2 if caccia >= 2 else caccia, 12)
			elif not st["basi"][nid]["fuori"] and _base_esposta(eng, nid, contatti):
				cap = clampi(int(caccia * 0.4), 0, 8)
		o["cap"][nid] = cap
	# ---- ricognizione
	_ricognizioni(eng, o, contatti)
	# ---- attacchi
	if not notte:
		_attacchi(eng, o, contatti, obj)
	# ---- movimento delle TF
	_movimenti(eng, o, contatti, obj)
	# ---- pedinamenti: le AF che vedono portaerei nemiche le seguono
	for k in st["noti"][lato]:
		var n: Dictionary = st["noti"][lato][k]
		if n["tipo"] == "tf" and int(n.get("cond", 0)) >= 2 and bool(n.get("info", {}).get("ha_portaerei", false) or int(n.get("info", {}).get("portaerei", 0)) > 0):
			for fid in eng.af_del_lato(lato):
				var af: Dictionary = st["af"][fid]
				if str(af["missione"].get("tipo", "")) == "ricognizione" and FTData.dist(eng.af_hex(fid), eng.vh(n["hex"])) <= 2:
					o["pedina"][fid] = k
					break
	return o


## Contatti nemici utili: quelli visti ora e quelli della memoria ancora freschi.
func _contatti(eng) -> Array:
	var st: Dictionary = eng.st
	var out := []
	var t: int = st["turno"]
	var visti := {}
	for k in st["noti"][lato]:
		var n: Dictionary = st["noti"][lato][k]
		if int(n.get("cond", 0)) >= 1 or n["tipo"] == "tf":
			out.append({"k": k, "tipo": n["tipo"], "hex": eng.vh(n["hex"]), "cond": int(n.get("cond", 0)), "eta": 0, "info": n.get("info", {})})
			visti[k] = true
	for k in st["memoria"][lato]:
		if visti.has(k):
			continue
		var m: Dictionary = st["memoria"][lato][k]
		var eta: int = t - int(m.get("turno", -99))
		if eta <= (4 if m["tipo"] == "tf" else 1):
			out.append({"k": k, "tipo": m["tipo"], "hex": eng.vh(m["hex"]), "cond": int(m.get("cond", 0)), "eta": eta, "info": m.get("info", {})})
	return out


static func _ha_cv(c: Dictionary) -> bool:
	var i: Dictionary = c.get("info", {})
	return bool(i.get("ha_portaerei", false)) or int(i.get("portaerei", 0)) > 0


func _minaccia_aerea(eng, contatti: Array) -> bool:
	var st: Dictionary = eng.st
	for c in contatti:
		if c["tipo"] == "af" and c["eta"] <= 1:
			return true
		if c["tipo"] == "tf" and _ha_cv(c) and c["eta"] <= 4:
			return true
	# basi nemiche vicine alle proprie portaerei
	for nid in eng.nidi_del_lato(lato):
		if not st["navi"].has(nid):
			continue
		var h: Vector2i = eng.nido_hex(nid)
		for bid in st["basi"]:
			var b: Dictionary = st["basi"][bid]
			if b["lato"] != lato and not b["fuori"] and FTData.dist(eng.vh(b["hex"]), h) <= 14:
				return true
	return false


func _base_esposta(eng, bid: String, contatti: Array) -> bool:
	var st: Dictionary = eng.st
	var h: Vector2i = eng.vh(st["basi"][bid]["hex"])
	for c in contatti:
		if FTData.dist(c["hex"], h) <= 14:
			return true
	for b2 in st["basi"]:
		var b: Dictionary = st["basi"][b2]
		if b["lato"] != lato and not b["fuori"] and FTData.dist(eng.vh(b["hex"]), h) <= 16:
			return true
	return false


func _caccia_nido(eng, nid: String) -> int:
	var nido: Dictionary = eng.st["nidi"][nid]
	var t := 0
	for box in ["pronti", "prep", "jl"]:
		for k in nido[box]:
			var tipo: String = k.split("|")[0]
			var arma: String = k.split("|")[1] if k.contains("|") else ""
			var r: String = FTData.aerei[tipo]["ruoli"]
			if r.contains("E") and arma == "":
				t += int(nido[box][k])
	return t


# ================================================================ ricognizione

func _ricognizioni(eng, o: Dictionary, contatti: Array) -> void:
	var st: Dictionary = eng.st
	var ora: int = st["ora"]
	# di notte si cerca poco: si preparano le partenze per l'alba
	var giorno_presto := ora >= 4 and ora <= 16
	if not giorno_presto:
		return
	var in_volo := 0
	for fid in eng.af_del_lato(lato):
		if str(st["af"][fid]["missione"].get("tipo", "")) == "ricognizione":
			in_volo += 1
	var voluti := 4 + (2 if livello >= 2 else 0)
	if in_volo >= voluti:
		return
	# direzioni: verso il baricentro nemico (basi nemiche e contatti), a ventaglio
	var bersagli_dir := _direzioni_ricerca(eng, contatti)
	if bersagli_dir.is_empty():
		return
	var usati := {}
	for fid in eng.af_del_lato(lato):
		var af: Dictionary = st["af"][fid]
		if str(af["missione"].get("tipo", "")) == "ricognizione":
			usati[str(af["missione"].get("verso", []))] = true
	var i := 0
	for nid in eng.nidi_del_lato(lato):
		if in_volo >= voluti:
			break
		var nido: Dictionary = st["nidi"][nid]
		var h: Vector2i = eng.nido_hex(nid)
		if h.x < -100:
			continue
		# esploratori: idrovolanti e aerei a lunga autonomia; sulle portaerei un singolo bombardiere scarico
		var scelta := ""
		var arma := ""
		for k in nido["pronti"]:
			var tipo: String = k.split("|")[0]
			var cls: String = FTData.aerei[tipo]["classe"]
			if tipo in ["Catalina", "Mavis", "Emily", "Hudson", "B-17", "Jake", "Pete", "Dave"] or (cls == "CV" and tipo in ["Dauntless", "Kate", "Val", "Avenger"]):
				if scelta == "" or tipo in ["Catalina", "Mavis", "Emily", "Jake", "Pete"]:
					scelta = tipo
					arma = k.split("|")[1] if k.contains("|") else ""
		if scelta == "":
			continue
		# una sola ricognizione per nido per turno; sulle portaerei al massimo due in volo
		var gia := 0
		for fid in eng.af_del_lato(lato):
			var af2: Dictionary = st["af"][fid]
			if str(af2["missione"].get("tipo", "")) == "ricognizione" and af2["casa"] == nid:
				gia += 1
		if gia >= (2 if st["navi"].has(nid) else 3):
			continue
		var dest: Vector2i = bersagli_dir[i % bersagli_dir.size()]
		i += 1
		var tries := 0
		while usati.has(str([dest.x, dest.y])) and tries < bersagli_dir.size():
			dest = bersagli_dir[i % bersagli_dir.size()]
			i += 1
			tries += 1
		usati[str([dest.x, dest.y])] = true
		# ridimensiona la distanza all'autonomia
		var rag := PILOT.raggio([scelta], arma != "") + 2
		var d := FTData.dist(h, dest)
		if d > rag:
			var l := FTData.linea(h, dest)
			if l.size() > rag:
				dest = l[rag - 1]
		o["lanci"].append({"n": nid, "gruppi": [{"tipo": scelta, "q": 1, "arma": arma}], "quota": "A",
			"missione": {"tipo": "ricognizione", "verso": [dest.x, dest.y]}})
		in_volo += 1


func _direzioni_ricerca(eng, contatti: Array) -> Array:
	var st: Dictionary = eng.st
	var punti := []
	for c in contatti:
		if c["tipo"] == "tf":
			punti.append(c["hex"])
	# basi nemiche sul tavolo
	var cen := Vector2.ZERO
	var nb := 0
	for bid in st["basi"]:
		var b: Dictionary = st["basi"][bid]
		if b["lato"] != lato:
			cen += Vector2(eng.vh(b["hex"]))
			nb += 1
	var mio := Vector2.ZERO
	var nm := 0
	for nid in eng.nidi_del_lato(lato):
		var h: Vector2i = eng.nido_hex(nid)
		if h.x > -100 and not (st["basi"].has(nid) and st["basi"][nid]["fuori"]):
			mio += Vector2(h)
			nm += 1
	if nm == 0:
		return punti
	mio /= nm
	if nb > 0:
		cen /= nb
	else:
		cen = mio + Vector2(0, -10 if lato == "A" else 10)
	var dir := (cen - mio).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, -1 if lato == "A" else 1)
	var turno: int = st["turno"]
	# giro d'orizzonte attorno ai propri nidi (il nemico può arrivare da qualunque parte)
	var giro := []
	for j in 6:
		var ang0 := deg_to_rad(float(j * 60 + (turno * 23) % 60))
		var v0 := Vector2(cos(ang0), sin(ang0)) * 12.0
		var p0 := Vector2i(roundi(mio.x + v0.x * 1.15), roundi(mio.y + v0.y))
		p0.x = clampi(p0.x, 0, 79)
		p0.y = clampi(p0.y, 0, 43)
		if FTData.volabile(p0):
			giro.append(p0)
	for k in [-60, -30, 0, 30, 60, -90, 90]:
		var ang := deg_to_rad(float(k) + float((turno * 7) % 20 - 10))
		var v := dir.rotated(ang) * 14.0
		var p := Vector2i(roundi(mio.x + v.x * 1.4), roundi(mio.y + v.y))
		p.x = clampi(p.x, 0, 79)
		p.y = clampi(p.y, 0, 43)
		punti.append(p)
	# alterna: un raggio verso il nemico e uno del giro d'orizzonte
	var out := []
	var n := maxi(punti.size(), giro.size())
	for i in n:
		if i < punti.size():
			out.append(punti[i])
		if i < giro.size():
			out.append(giro[i])
	return out


# ================================================================ attacchi

func _attacchi(eng, o: Dictionary, contatti: Array, obj: Dictionary) -> void:
	var st: Dictionary = eng.st
	var t: int = st["turno"]
	var ora: int = st["ora"]
	# bersagli in ordine di valore
	var bers := []
	for c in contatti:
		if c["tipo"] != "tf" or c["eta"] > 2:
			continue
		var val := 10
		if _ha_cv(c):
			val = 100
		elif bool(c["info"].get("ha_maggiori", false)) or int(c["info"].get("maggiori", 0)) > 0:
			val = 40
		if obj.has("difendi") and c.get("info", {}).get("ha_minori", false):
			val += 10
		val -= c["eta"] * 15
		bers.append({"val": val, "c": c})
	bers.sort_custom(func(a, b): return a["val"] > b["val"])
	var base_obj := ""
	if obj.has("attacca_base"):
		base_obj = str(obj["attacca_base"])
	# attacchi già in volo verso un bersaglio
	var gia := {}
	for fid in eng.af_del_lato(lato):
		var m: Dictionary = st["af"][fid]["missione"]
		if str(m.get("tipo", "")) == "attacco":
			var key := str(m.get("bersaglio", m.get("bersaglio_base", "")))
			gia[key] = int(gia.get(key, 0)) + eng.af_fattori(fid)
	for nid in eng.nidi_del_lato(lato):
		var nido: Dictionary = st["nidi"][nid]
		var h: Vector2i = eng.nido_hex(nid)
		if h.x < -100 or nido.get("no_lanci", false):
			continue
		var armati := {}
		var scorta := {}
		for k in nido["pronti"]:
			var tipo: String = k.split("|")[0]
			var arma: String = k.split("|")[1] if k.contains("|") else ""
			if arma != "":
				armati[k] = int(nido["pronti"][k])
			elif FTData.aerei[tipo]["ruoli"].contains("E"):
				scorta[tipo] = int(scorta.get(tipo, 0)) + int(nido["pronti"][k])
		if armati.is_empty():
			continue
		var tipi := []
		var tot_arm := 0
		for k in armati:
			tipi.append(k.split("|")[0])
			tot_arm += armati[k]
		# serve una forza minima: non si sprecano i bombardieri a gocce
		if tot_arm < (4 if st["navi"].has(nid) else 3):
			continue
		var rag := PILOT.raggio(tipi, true)
		var scelto = null
		for b in bers:
			var d := FTData.dist(h, b["c"]["hex"])
			if d > rag:
				continue
			# non arrivare di notte
			var mfmin := 99
			for tp in tipi:
				mfmin = mini(mfmin, int(FTData.aerei[tp]["mf"]))
			var turni := int(ceil(float(d) / maxi(1, mfmin - 1))) + 1
			var arrivo := (ora + turni - 1) % 24 + 1
			if FTData.is_notte(arrivo) and d > 3:
				continue
			if int(gia.get(b["c"]["k"], 0)) > 40:
				continue
			scelto = {"k": b["c"]["k"], "hex": b["c"]["hex"]}
			break
		if scelto == null and base_obj != "" and st["basi"].has(base_obj) and st["basi"][base_obj]["lato"] != lato:
			var bh: Vector2i = eng.vh(st["basi"][base_obj]["hex"])
			if FTData.dist(h, bh) <= rag and int(gia.get(base_obj, 0)) < 30:
				scelto = {"base": base_obj, "hex": bh}
		if scelto == null:
			continue
		# scorta: i caccia non necessari alla CAP
		var cap_vuole: int = int(o["cap"].get(nid, 0))
		var gruppi_alti := []
		var gruppi_bassi := []
		for k in armati:
			var tipo2: String = k.split("|")[0]
			var arma2: String = k.split("|")[1]
			var g := {"tipo": tipo2, "q": armati[k], "arma": arma2}
			if arma2 == "T":
				gruppi_bassi.append(g)
			else:
				var b2: Dictionary = FTData.aerei[tipo2]["bht"]
				var kk := arma2.to_lower()
				if int(b2.get("s_dv_" + kk, 0)) > 0 or int(b2.get("s_hl_" + kk, 0)) > 0 or int(b2.get("b_hl_" + kk, 0)) > 0:
					gruppi_alti.append(g)
				else:
					gruppi_bassi.append(g)
		var caccia_lib := 0
		for tp in scorta:
			caccia_lib += scorta[tp]
		caccia_lib = maxi(0, caccia_lib - cap_vuole)
		var sc_alti := []
		var sc_bassi := []
		if caccia_lib > 0:
			var n_alti := 0
			var n_bassi := 0
			for g in gruppi_alti:
				n_alti += g["q"]
			for g in gruppi_bassi:
				n_bassi += g["q"]
			var quota_alti := int(round(float(caccia_lib) * n_alti / maxi(1, n_alti + n_bassi)))
			for tp in scorta:
				var q: int = scorta[tp]
				var ra := PILOT.raggio([tp], false)
				if FTData.dist(h, scelto["hex"]) > ra:
					continue
				var qa := mini(q, quota_alti)
				quota_alti -= qa
				var qb := mini(q - qa, caccia_lib - qa)
				if qa > 0:
					sc_alti.append({"tipo": tp, "q": qa, "arma": ""})
				if qb > 0 and not gruppi_bassi.is_empty():
					sc_bassi.append({"tipo": tp, "q": qb, "arma": ""})
				caccia_lib -= qa + qb
				if caccia_lib <= 0:
					break
		var miss := {"tipo": "attacco", "hex": [scelto["hex"].x, scelto["hex"].y]}
		if scelto.has("k"):
			miss["bersaglio"] = scelto["k"]
		else:
			miss["bersaglio_base"] = scelto["base"]
		if not gruppi_alti.is_empty():
			o["lanci"].append({"n": nid, "gruppi": gruppi_alti + sc_alti, "quota": "A", "missione": miss.duplicate()})
		if not gruppi_bassi.is_empty():
			o["lanci"].append({"n": nid, "gruppi": gruppi_bassi + sc_bassi, "quota": "B", "missione": miss.duplicate()})
		var key2 := str(scelto.get("k", scelto.get("base", "")))
		gia[key2] = int(gia.get(key2, 0)) + tot_arm


# ================================================================ movimento delle TF

func _movimenti(eng, o: Dictionary, contatti: Array, obj: Dictionary) -> void:
	var st: Dictionary = eng.st
	var notte: bool = eng.notte()
	var portaerei_nemiche := []
	for c in contatti:
		if c["tipo"] == "tf" and _ha_cv(c) and c["eta"] <= 4:
			portaerei_nemiche.append(c)
	var basi_nemiche := []
	for bid in st["basi"]:
		var b: Dictionary = st["basi"][bid]
		if b["lato"] != lato and not b["fuori"]:
			basi_nemiche.append(eng.vh(b["hex"]))
	# punto di riferimento dello scenario
	var difesa := Vector2i(-999, -999)
	if obj.has("difendi") and st["basi"].has(obj["difendi"]):
		difesa = eng.vh(st["basi"][obj["difendi"]]["hex"])
	var sbarco := []
	var sb: Dictionary = st["speciali"].get("sbarco", {}).get(lato, {})
	for h in sb.get("hex", []):
		sbarco.append(eng.vh(h))
	if sb.has("isola"):
		for h in FTData.isole.get(sb["isola"], []):
			var hh: Vector2i = eng.vh(h)
			var escl := false
			for e in sb.get("escludi", []):
				if eng.vh(e) == hh:
					escl = true
			if not escl:
				sbarco.append(hh)
	var bersaglio_base := Vector2i(-999, -999)
	if obj.has("attacca_base") and st["basi"].has(obj["attacca_base"]):
		bersaglio_base = eng.vh(st["basi"][obj["attacca_base"]]["hex"])
	var cv_tf := []
	for tid in eng.tf_del_lato(lato):
		if st["tf"][tid].get("fuori", false):
			continue
		var tf: Dictionary = st["tf"][tid]
		var h: Vector2i = eng.tf_hex(tid)
		var ha_cv := false
		var ha_tr := false
		var ha_sup := false
		var carichi := 0
		for nid in tf["navi"]:
			var n: Dictionary = st["navi"][nid]
			if n["tipo"] in ["CV", "CVL"] and st["nidi"].has(nid):
				ha_cv = true
			if n["tipo"] in ["AP", "APD"]:
				ha_tr = true
				carichi += int(n["carico"])
			if n["tipo"] in ["BB", "CA", "CL"] and int(n["art"]) > 0:
				ha_sup = true
		var dest := h
		var contegno := "evita"
		if ha_cv:
			cv_tf.append(tid)
			dest = _dest_portaerei(eng, tid, portaerei_nemiche, basi_nemiche, difesa, sbarco, bersaglio_base)
		elif ha_tr and not sbarco.is_empty():
			if carichi > 0:
				var best: Vector2i = sbarco[0]
				var bd := 9999
				for sh in sbarco:
					var d := FTData.dist(h, sh)
					if d < bd and FTData.navigabile(sh):
						bd = d
						best = sh
				dest = best
				if h == best:
					o["ancora"][tid] = true
					continue
			else:
				o["ancora"][tid] = false
				var part = piani["partenza"].get(tid, null)
				dest = eng.vh(part) if part != null else h
		elif ha_sup:
			contegno = "attacca"
			# di notte all'attacco dei trasporti o della base nemica; di giorno lontano dagli aerei
			var preda := Vector2i(-999, -999)
			var pd := 9999
			for c in contatti:
				if c["tipo"] == "tf" and c["eta"] <= 2:
					var d2 := FTData.dist(h, c["hex"])
					if d2 < pd:
						pd = d2
						preda = c["hex"]
			if bersaglio_base.x > -100 and _ha_munizioni(eng, tid):
				dest = bersaglio_base
				contegno = "bombarda"
			elif preda.x > -100 and pd <= 8:
				dest = preda
			elif not cv_tf.is_empty():
				dest = eng.tf_hex(cv_tf[0])
			elif difesa.x > -100:
				dest = _mare_vicino(difesa)
			if not notte and contegno == "bombarda" and FTData.dist(h, dest) <= 4:
				# aspetta la notte fuori portata
				dest = h
		else:
			# navi ausiliarie: restano con le portaerei
			if not cv_tf.is_empty():
				dest = eng.tf_hex(cv_tf[0])
		o["contegno"][tid] = contegno
		if st["tf"][tid]["ancorata"] and not (ha_tr and carichi > 0 and h in sbarco):
			o["ancora"][tid] = false
		if dest != h:
			var path := FTData.percorso(h, _mare_vicino(dest), true)
			var mf: int = eng.tf_mf(tid)
			var rotta := []
			for i in mini(maxi(mf, 2), path.size()):
				rotta.append([path[i].x, path[i].y])
			o["rotte"][tid] = rotta


func _ha_munizioni(eng, tid: String) -> bool:
	for nid in eng.st["tf"][tid]["navi"]:
		var n: Dictionary = eng.st["navi"][nid]
		if n["tipo"] in ["BB", "CA", "CL"] and int(n["mun"]) >= 8:
			return true
	return false


static func _mare_vicino(h: Vector2i) -> Vector2i:
	if FTData.navigabile(h):
		return h
	for r in range(1, 6):
		for q in FTData.dentro(h, r):
			if FTData.navigabile(q) and FTData.ter(q) == ".":
				return q
	return h


## Dove portare una TF di portaerei: a distanza d'attacco dalle portaerei nemiche, fuori dalla loro portata
## di giorno; altrimenti a coprire l'obiettivo dello scenario.
func _dest_portaerei(eng, tid: String, nemiche: Array, basi_nem: Array, difesa: Vector2i, sbarco: Array, bersaglio_base: Vector2i) -> Vector2i:
	var st: Dictionary = eng.st
	var h: Vector2i = eng.tf_hex(tid)
	var raggio := 11
	var notte: bool = eng.notte()
	if not nemiche.is_empty():
		var vicina: Dictionary = nemiche[0]
		var bd := 9999
		for c in nemiche:
			var d := FTData.dist(h, c["hex"])
			if d < bd:
				bd = d
				vicina = c
		var tgt: Vector2i = vicina["hex"]
		if bd > raggio:
			return tgt   # avvicinarsi
		if bd < 6:
			return _lontano(h, tgt, 4)  # troppo vicini: ci si allontana
		# a distanza buona: ci si tiene sul posto (piccole correzioni contro vento)
		return h
	if bersaglio_base.x > -100:
		var db := FTData.dist(h, bersaglio_base)
		if db > raggio - 2:
			return bersaglio_base
		return h
	if difesa.x > -100:
		# copertura: fra la base e il nemico probabile (verso le sue basi)
		var cen := Vector2.ZERO
		for b in basi_nem:
			cen += Vector2(b)
		if not basi_nem.is_empty():
			cen /= basi_nem.size()
			var v := (cen - Vector2(difesa)).normalized() * 6.0
			var p := Vector2i(roundi(difesa.x + v.x * 1.2), roundi(difesa.y + v.y))
			return _mare_vicino(p)
		return _mare_vicino(difesa)
	if not sbarco.is_empty():
		var s0: Vector2i = sbarco[0]
		var dd := FTData.dist(h, s0)
		if dd > 9:
			return s0
		return h
	return h


static func _lontano(h: Vector2i, da: Vector2i, passi: int) -> Vector2i:
	var best := h
	var bd := FTData.dist(h, da)
	var cur := h
	for i in passi:
		var mig := cur
		for nb in FTData.vicini(cur):
			if FTData.navigabile(nb) and FTData.dist(nb, da) > FTData.dist(mig, da):
				mig = nb
		cur = mig
	return cur
