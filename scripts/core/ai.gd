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
			return aria(eng)
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
			# mai partire dentro una tempesta: la TF resterebbe ferma
			if eng.tempesta(h):
				v -= 100.0
			punti.append([v + rng.randf() * 2.0, h])
		punti.sort_custom(func(a, b): return a[0] > b[0])
		var scelta: Vector2i = punti[rng.randi_range(0, mini(punti.size() - 1, maxi(0, punti.size() / 6)))][1]
		pos[tid] = [scelta.x, scelta.y]
		if r["tf"][tid].has("entra_tra"):
			if not out_entra.has(tid):
				out_entra[tid] = int(r["tf"][tid]["entra_tra"][0])
	return {"pos": pos, "entra": out_entra}


## Movimento aereo: le formazioni d'attacco dirette allo stesso bersaglio che si trovano nello stesso
## esagono e alla stessa quota si uniscono (la contraerea spara contro ogni formazione: meglio una grossa).
func aria(eng) -> Dictionary:
	var st: Dictionary = eng.st
	var unisci := []
	var usate := {}
	var ids: Array = eng.af_del_lato(lato)
	ids.sort()
	for i in ids.size():
		var a: String = ids[i]
		if usate.has(a) or st["af"][a].get("fuori_mappa", false):
			continue
		var ma: Dictionary = st["af"][a]["missione"]
		if str(ma.get("tipo", "")) != "attacco":
			continue
		for j in range(i + 1, ids.size()):
			var b: String = ids[j]
			if usate.has(b) or st["af"][b].get("fuori_mappa", false):
				continue
			var mb: Dictionary = st["af"][b]["missione"]
			if str(mb.get("tipo", "")) != "attacco" or eng.af_hex(a) != eng.af_hex(b) or st["af"][a]["quota"] != st["af"][b]["quota"]:
				continue
			if str(ma.get("bersaglio", ma.get("bersaglio_base", ""))) != str(mb.get("bersaglio", mb.get("bersaglio_base", ""))):
				continue
			unisci.append([a, b])
			usate[b] = true
	return {"_unisci_af": unisci}


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
		o["auto"][nid] = false
		o["contro_basi"][nid] = obj.has("attacca_base") and not navi_nemiche_note and st["navi"].has(nid) == false
		if obj.has("attacca_base") and str(obj["attacca_base"]) == "rabaul":
			o["contro_basi"][nid] = not navi_nemiche_note
	o["prep"] = []
	# ---- pattuglia aerea
	var minaccia := _minaccia_aerea(eng, contatti)
	for nid in eng.nidi_del_lato(lato):
		var caccia := _caccia_nido(eng, nid)
		var cap := 0
		if not notte and not notte_prossima and caccia > 0:
			if st["navi"].has(nid):
				var esposto: bool = minaccia or _sotto_aerei(eng, eng.nido_hex(nid))
				cap = clampi(int(caccia * ((0.75 if lato == "A" else 0.5) if esposto else 0.3)), 2 if caccia >= 2 else caccia, 14)
			elif not st["basi"][nid]["fuori"] and _base_esposta(eng, nid, contatti):
				cap = clampi(int(caccia * 0.4), 0, 8)
		o["cap"][nid] = cap
	# ---- preparazione degli aerei: i bombardieri si armano solo quando c'è qualcosa da colpire (gli aerei
	# pronti sul ponte raddoppiano i colpi nemici), i caccia salgono per la pattuglia e la scorta
	_preparazione(eng, o, contatti, obj)
	# quota della pattuglia: contro un nemico che attacca soprattutto con i siluri si sta bassi
	var q_cap := _quota_cap(eng)
	o["cap_quota"] = {}
	for nid in eng.nidi_del_lato(lato):
		o["cap_quota"][nid] = q_cap
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


## L'esagono è nel raggio d'attacco (12 esagoni) di una base nemica con bombardieri?
func _sotto_aerei(eng, h: Vector2i) -> bool:
	var st: Dictionary = eng.st
	for bid in st["basi"]:
		var b: Dictionary = st["basi"][bid]
		if b["lato"] == lato or b["fuori"] or not st["nidi"].has(bid):
			continue
		if FTData.dist(eng.vh(b["hex"]), h) > 12 or int(eng.nido_lf(bid)[0]) <= 0:
			continue
		var bomb := 0
		for box in ["prep", "pronti", "jl"]:
			for k in st["nidi"][bid][box]:
				if FTData.aerei[str(k).split("|")[0]]["ruoli"].contains("B") and not FTData.aerei[str(k).split("|")[0]]["ruoli"].contains("E"):
					bomb += int(st["nidi"][bid][box][k])
		if bomb >= 3:
			return true
	return false


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


func _preparazione(eng, o: Dictionary, contatti: Array, obj: Dictionary) -> void:
	var st: Dictionary = eng.st
	var notte_presto := FTData.is_notte(int(st["ora"]) % 24 + 1) and FTData.is_notte((int(st["ora"]) + 2) % 24 + 1)
	for nid in eng.nidi_del_lato(lato):
		var nido: Dictionary = st["nidi"][nid]
		var h: Vector2i = eng.nido_hex(nid)
		if h.x < -100:
			continue
		var lib: int = eng.nido_rf(nid) - int(nido["rf_usato"])
		if lib <= 0:
			continue
		var contro_basi: bool = bool(o["contro_basi"].get(nid, false))
		# basi sul tavolo: di notte gli aerei si disperdono (contro i bombardamenti navali ne perde uno ogni due
		# colpi invece di uno per colpo) e all'alba tornano in preparazione
		if st["basi"].has(nid) and not st["basi"][nid]["fuori"]:
			var sera: bool = eng.notte() or int(st["ora"]) >= 18
			if sera:
				for tp in nido["pronti"].keys():
					if lib <= 0:
						break
					var qp: int = mini(lib, int(nido["pronti"][tp]))
					if qp > 0 and not _cap_in_uso(eng, nid):
						o["prep"].append({"n": nid, "da": "pronti", "a": "prep", "tipo": str(tp).split("|")[0], "q": qp, "arma": str(tp).split("|")[1] if str(tp).contains("|") else ""})
						lib -= qp
				for tp in nido["prep"].keys():
					if lib <= 0:
						break
					var qd: int = mini(lib, int(nido["prep"][tp]))
					if qd > 0:
						o["prep"].append({"n": nid, "da": "prep", "a": "disp", "tipo": tp, "q": qd})
						lib -= qd
				for tp in nido["jl"].keys():
					if lib <= 0:
						break
					var qj: int = mini(lib, int(nido["jl"][tp]))
					if qj > 0:
						o["prep"].append({"n": nid, "da": "jl", "a": "prep", "tipo": tp, "q": qj})
						lib -= qj
				continue
			elif int(st["ora"]) >= 4:
				for tp in nido["disp"].keys():
					if lib <= 0:
						break
					var qr: int = mini(lib, int(nido["disp"][tp]))
					if qr > 0:
						o["prep"].append({"n": nid, "da": "disp", "a": "prep", "tipo": tp, "q": qr})
						lib -= qr
		# bombardieri a bordo e loro raggio
		var tipi_b := []
		for box in ["prep", "jl", "pronti"]:
			for k in nido[box]:
				var tp: String = str(k).split("|")[0]
				var r: String = FTData.aerei[tp]["ruoli"]
				if r.contains("B") and not r.contains("E") and FTEngine.arma_preferita(tp) != "" and not tp in tipi_b:
					tipi_b.append(tp)
		var armare := false
		# contro un nemico che attacca soprattutto con i siluri, gli aerei in preparazione raddoppiano i suoi
		# colpi: meglio averli già pronti (21.6)
		if _quota_cap(eng) == "B" and not tipi_b.is_empty():
			armare = true
		if not tipi_b.is_empty() and not notte_presto:
			var rag := 6
			for tpb in tipi_b:
				rag = maxi(rag, PILOT.raggio([tpb], true) + 6)
			for c in contatti:
				if c["tipo"] == "tf" and c["eta"] <= 3 and FTData.dist(h, c["hex"]) <= rag:
					armare = true
			if obj.has("attacca_base") and st["basi"].has(str(obj["attacca_base"])) and st["basi"][str(obj["attacca_base"])]["lato"] != lato:
				if FTData.dist(h, eng.vh(st["basi"][str(obj["attacca_base"])]["hex"])) <= rag:
					armare = true
			# basi lontane dal fronte (fuori mappa): armano sempre, non rischiano attacchi
			if st["basi"].has(nid) and st["basi"][nid]["fuori"]:
				armare = true
		# caccia da tenere pronti: pattuglia voluta più una scorta se si prepara un attacco
		var caccia_pronti := 0
		for k in nido["pronti"]:
			if str(k).ends_with("|") and FTData.aerei[str(k).split("|")[0]]["ruoli"].contains("E"):
				caccia_pronti += int(nido["pronti"][k])
		var caccia_voluti: int = int(o["cap"].get(nid, 0)) + (6 if armare else 2)
		var ordine := []
		for tp in nido["prep"].keys():
			var r2: String = FTData.aerei[tp]["ruoli"]
			var bomb: bool = r2.contains("B") and not r2.contains("E") and FTEngine.arma_preferita(tp) != ""
			if bomb and armare:
				ordine.append([0, tp, FTEngine.arma_preferita(tp, contro_basi)])
			elif not bomb and (r2.contains("E") or r2.contains("I")):
				ordine.append([1, tp, ""])
			elif not bomb:
				# esploratori (idrovolanti, bombardieri pesanti usati per cercare): pronti scarichi
				ordine.append([2, tp, ""])
		ordine.sort()
		for it in ordine:
			if lib <= 0:
				break
			var q: int = mini(lib, int(nido["prep"][it[1]]))
			if it[0] == 1:
				q = mini(q, maxi(0, caccia_voluti - caccia_pronti))
				caccia_pronti += q
			elif it[0] == 2:
				q = mini(q, 2)
			if q <= 0:
				continue
			o["prep"].append({"n": nid, "da": "prep", "a": "pronti", "tipo": it[1], "q": q, "arma": it[2]})
			lib -= q
		for tp in nido["jl"].keys():
			if lib <= 0:
				break
			var q2: int = mini(lib, int(nido["jl"][tp]))
			if q2 > 0:
				o["prep"].append({"n": nid, "da": "jl", "a": "prep", "tipo": tp, "q": q2})
				lib -= q2


func _cap_in_uso(_eng, _nid: String) -> bool:
	return false


func _quota_cap(eng) -> String:
	if piani.has("quota_cap"):
		return piani["quota_cap"]
	var st: Dictionary = eng.st
	var silu := 0
	var alti := 0
	for nid in st["nidi"]:
		var nido: Dictionary = st["nidi"][nid]
		if nido["lato"] == lato:
			continue
		for box in ["jl", "prep", "pronti", "disp"]:
			for k in nido[box]:
				var tp: String = str(k).split("|")[0]
				var b: Dictionary = FTData.aerei[tp]["bht"]
				var r: String = FTData.aerei[tp]["ruoli"]
				if not r.contains("B") or r.contains("E"):
					continue
				if int(b.get("s_to", 0)) > 0:
					silu += int(nido[box][k])
				elif int(b.get("s_dv_ap", 0)) > 0 or int(b.get("s_hl_ap", 0)) > 0:
					alti += int(nido[box][k])
	var q := "misto"
	if silu > alti * 2:
		q = "B"
	elif alti > silu * 2:
		q = "A"
	piani["quota_cap"] = q
	return q


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


# ================================================================ corridoio dei convogli

## Se il nemico deve sbarcare vicino a una base che difendiamo, i convogli arrivano lungo le rotte fra le
## sue basi e la nostra (lo Slot, a Guadalcanal): esagoni di quei corridoi entro 22 dalla base difesa.
func _corridoio(eng) -> Array:
	if piani.has("corridoio"):
		return piani["corridoio"]
	var st: Dictionary = eng.st
	var out := []
	var sc_obj: Dictionary = FTData.scenario(st["scen"]).get("obiettivi", {})
	var obj: Dictionary = sc_obj.get(lato, {})
	if sc_obj.get(eng.nemico(lato), {}).has("sbarco") and obj.has("difendi") and st["basi"].has(str(obj["difendi"])):
		var d: Vector2i = eng.vh(st["basi"][str(obj["difendi"])]["hex"])
		var vis := {}
		for bid in st["basi"]:
			var b: Dictionary = st["basi"][bid]
			if b["lato"] == lato or b["fuori"]:
				continue
			var bh: Vector2i = eng.vh(b["hex"])
			if FTData.dist(bh, d) > 30:
				continue
			for h in FTData.linea(d, bh):
				if FTData.dist(h, d) <= 22 and not vis.has(h):
					vis[h] = true
					out.append(h)
	piani["corridoio"] = out
	return out


## Il contatto è una TF nemica nel corridoio dei convogli? (anche vista solo con la condizione 1)
func _sospetto_convoglio(eng, c: Dictionary) -> bool:
	if c["tipo"] != "tf" or _ha_cv(c):
		return false
	for h in _corridoio(eng):
		if FTData.dist(h, c["hex"]) <= 2:
			var i: Dictionary = c.get("info", {})
			# con la condizione 3 si sa se ci sono trasporti: le flotte di sole navi da guerra non contano
			if int(i.get("cond", 0)) >= 3 and int(i.get("minori", 0)) == 0:
				return false
			return true
	return false


# ================================================================ ricognizione

func _ricognizioni(eng, o: Dictionary, contatti: Array) -> void:
	var st: Dictionary = eng.st
	var ora: int = st["ora"]
	# di notte si cerca poco: si preparano le partenze per l'alba
	# ricerca all'alba (i ricognitori partono prima della luce) e nel primo pomeriggio; di notte quasi mai
	var giorno_presto := (ora >= 4 and ora <= 8) or (ora >= 12 and ora <= 14)
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
	# pattuglia del corridoio dei convogli: punti a 5, 10, 15 e 20 esagoni dalla base difesa
	var cor := _corridoio(eng)
	if not cor.is_empty():
		var sc_obj2: Dictionary = FTData.scenario(st["scen"]).get("obiettivi", {})
		var d0: Vector2i = eng.vh(st["basi"][str(sc_obj2[lato]["difendi"])]["hex"])
		var pat := []
		for h in cor:
			var dd := FTData.dist(h, d0)
			if dd in [5, 10, 15, 20]:
				pat.append(h)
		bersagli_dir = pat + bersagli_dir
		voluti += 2
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
	var sc_obj: Dictionary = FTData.scenario(st["scen"]).get("obiettivi", {})
	var nemico_sbarca: bool = sc_obj.get(eng.nemico(lato), {}).has("sbarco")
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
		if nemico_sbarca and _sospetto_convoglio(eng, c):
			val += 60
		if obj.has("difendi") and (c.get("info", {}).get("ha_minori", false) or int(c.get("info", {}).get("minori", 0)) > 0):
			val += 10
			# un convoglio che punta sulla base da difendere vale più di tutto il resto
			if nemico_sbarca and st["basi"].has(str(obj["difendi"])) and FTData.dist(c["hex"], eng.vh(st["basi"][str(obj["difendi"])]["hex"])) <= 25 and not _ha_cv(c):
				val += 70
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
		# attacchi grossi e concentrati: si aspetta che sia armata la maggior parte dei bombardieri
		var tot_bomb := tot_arm
		for box in ["prep", "jl"]:
			for k2 in nido[box]:
				var r3: String = FTData.aerei[str(k2).split("|")[0]]["ruoli"]
				if r3.contains("B") and not r3.contains("E") and FTEngine.arma_preferita(str(k2).split("|")[0]) != "":
					tot_bomb += int(nido[box][k2])
		var soglia: int = clampi(ceili(tot_bomb * 0.7), 4, 10) if st["navi"].has(nid) else clampi(ceili(tot_bomb * 0.6), 5, 12)
		if tot_arm < mini(soglia, tot_bomb):
			continue
		if tot_arm < (4 if st["navi"].has(nid) else 5):
			continue
		# raggio: quello del tipo che arriva più lontano; chi non ci arriva resta a bordo
		var rag := 0
		for tp0 in tipi:
			rag = maxi(rag, PILOT.raggio([tp0], true))
		var scelto = null
		# le basi che difendono dallo sbarco tengono i bombardieri per il convoglio
		var riserva := false
		if nemico_sbarca and st["basi"].has(nid) and obj.has("difendi"):
			for b0 in bers:
				if _sospetto_convoglio(eng, b0["c"]):
					riserva = true
		for b in bers:
			if riserva and not _sospetto_convoglio(eng, b["c"]) and FTData.dist(b["c"]["hex"], eng.vh(st["basi"][str(obj["difendi"])]["hex"])) > 3:
				continue
			var d := FTData.dist(h, b["c"]["hex"])
			if d > rag:
				continue
			# non arrivare di notte
			var mfmin := 99
			for tp in tipi:
				if PILOT.raggio([tp], true) >= d:
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
		var dist_b := FTData.dist(h, scelto["hex"])
		var arm2 := {}
		var tot2 := 0
		for k in armati:
			if PILOT.raggio([str(k).split("|")[0]], true) >= dist_b:
				arm2[k] = armati[k]
				tot2 += int(armati[k])
		if tot2 < (4 if st["navi"].has(nid) else 5) or tot2 * 2 < tot_arm:
			continue
		armati = arm2
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
			if nemico_sbarca:
				miss["priorita"] = "trasporti"
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
			# Wake: alla fine le portaerei giapponesi devono essere vicine al bordo ovest
			var ovest: Dictionary = st["speciali"].get("cv_a_ovest", {})
			if not ovest.is_empty() and lato == "J" and h.x >= int(ovest["colonne"]) - 2:
				if int(st["turni"]) - int(st["turno"]) <= (h.x - int(ovest["colonne"]) + 2) / maxi(1, eng.tf_mf(tid)) + 8:
					dest = _mare_vicino(Vector2i(int(ovest["colonne"]) - 4, h.y))
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
				# il convoglio aspetta al largo finché la base nemica che copre lo sbarco ha aerei e le portaerei
				# nemiche sono nei paraggi (salvo il tempo che stringe o il punteggio che preme)
				if h != best and FTData.dist(h, best) > 3:
					var minacciato := _sotto_aerei(eng, best)
					for c in contatti:
						if c["tipo"] == "tf" and _ha_cv(c) and c["eta"] <= 6 and FTData.dist(c["hex"], best) <= 12:
							minacciato = true
					var vit: Dictionary = FTData.scenario(st["scen"]).get("vittoria", {})
					var deficit: int = int(st["lati"][eng.nemico(lato)]["vp"]) - int(st["lati"][lato]["vp"])
					var fretta: bool = int(st["turno"]) >= int(st["turni"]) * 0.35 or deficit >= int(vit.get("auto", 200)) / 2
					if minacciato and not fretta:
						dest = h if FTData.dist(h, best) >= 11 else _lontano(h, best, 2)
				# di giorno il convoglio non entra nel raggio degli aerei delle basi nemiche: aspetta il
				# tramonto e corre di notte verso lo sbarco
				var pross := FTData.percorso(h, best, true)
				if not pross.is_empty() and h != best:
					var avanti: Vector2i = pross[mini(pross.size() - 1, maxi(0, eng.tf_mf(tid) - 1))]
					var buio := FTData.is_notte((int(st["ora"]) + 1) % 24 + 1) or int(st["ora"]) >= 17
					if not buio and _sotto_aerei(eng, avanti) and not _sotto_aerei(eng, h):
						dest = h
				if h == best:
					# prima di gettare l'ancora le navi da guerra si staccano: all'ancora finirebbero tutte
					# nello schermo e non potrebbero difendere i trasporti
					if ha_sup:
						var scorta := []
						for nid in tf["navi"]:
							if not st["navi"][nid]["tipo"] in ["AP", "APD", "AO", "PG"] and st["navi"][nid]["tipo"] != "CV" and st["navi"][nid]["tipo"] != "CVL":
								scorta.append(nid)
						if not scorta.is_empty() and scorta.size() < tf["navi"].size():
							if not o.has("dividi"):
								o["dividi"] = []
							o["dividi"].append({"tf": tid, "navi": scorta})
					o["ancora"][tid] = true
					continue
			else:
				o["ancora"][tid] = false
				var part = piani["partenza"].get(tid, null)
				dest = eng.vh(part) if part != null else h
		elif ha_sup:
			contegno = "attacca"
			var notte_vicina: bool = notte or FTData.is_notte((int(st["ora"]) + 1) % 24 + 1)
			var nemico_sbarca2: bool = not _corridoio(eng).is_empty()
			# di notte all'attacco dei trasporti o della base nemica; di giorno lontano dagli aerei
			var preda := Vector2i(-999, -999)
			var pd := 9999
			for c in contatti:
				if c["tipo"] == "tf" and c["eta"] <= 2:
					var d2 := FTData.dist(h, c["hex"])
					# di notte la caccia ai convogli viene prima di tutto; contro chi deve sbarcare, di giorno
					# non si va incontro alle flotte da guerra nemiche
					var sosp := _sospetto_convoglio(eng, c)
					if nemico_sbarca2 and not (sosp and notte_vicina):
						continue
					if sosp and notte_vicina:
						d2 -= 6
					if d2 < pd:
						pd = d2
						preda = c["hex"]
			var miei_magg := 0
			for nid2 in tf["navi"]:
				if st["navi"][nid2]["tipo"] in ["BB", "CA", "CAV", "BC"] and int(st["navi"][nid2]["art"]) > 0:
					miei_magg += 1
			var minaccia := Vector2i(-999, -999)
			for c in contatti:
				if c["tipo"] == "tf" and c["eta"] <= 1 and FTData.dist(h, c["hex"]) <= 2:
					var magg: int = int(c["info"].get("maggiori", 2 if c["info"].get("ha_maggiori", false) else 0))
					if magg > miei_magg:
						minaccia = c["hex"]
			if minaccia.x > -100:
				# troppo forti: ci si allontana verso la propria base e si evita il combattimento
				contegno = "evita"
				var via := h
				var bd2 := -1
				for nb in FTData.dentro(h, 2):
					if FTData.navigabile(nb):
						var d3 := FTData.dist(nb, minaccia) * 3 - (FTData.dist(nb, difesa) if difesa.x > -100 else 0)
						if d3 > bd2:
							bd2 = d3
							via = nb
				dest = via
				preda = Vector2i(-999, -999)
			# guardia notturna alla base da difendere contro i bombardamenti navali e gli sbarchi
			var guardia := false
			var ritira := false
			var nem_obj: Dictionary = FTData.scenario(st["scen"]).get("obiettivi", {}).get(eng.nemico(lato), {})
			if difesa.x > -100 and (str(nem_obj.get("attacca_base", "")) == str(obj.get("difendi", "")) or nem_obj.has("sbarco")) and _ha_munizioni(eng, tid):
				guardia = notte_vicina and (preda.x < -100 or pd > 3)
				# di guardia solo se non ci sono in giro flotte da guerra nemiche più forti
				for c in contatti:
					if c["tipo"] == "tf" and c["eta"] <= 4 and FTData.dist(c["hex"], difesa) <= 12:
						var magg2: int = int(c["info"].get("maggiori", 0))
						if magg2 > miei_magg or (magg2 == 0 and c["info"].get("ha_maggiori", false) and miei_magg < 3):
							guardia = false
							if FTData.dist(h, difesa) < 6 and minaccia.x < -100:
								ritira = true
								contegno = "evita"
								dest = _lontano(h, c["hex"], 3)
			if minaccia.x > -100 or ritira:
				pass
			elif guardia:
				dest = difesa if FTData.navigabile(difesa) else _mare_vicino(difesa)
				contegno = "attacca"
			elif bersaglio_base.x > -100 and _ha_munizioni(eng, tid):
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
