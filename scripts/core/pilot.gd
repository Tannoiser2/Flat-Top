extends RefCounted
## Pilota automatico delle formazioni aeree: dalla missione (attacco, ricognizione, pattuglia, rientro,
## trasferimento) ricava gli ordini del turno: rotta, quota, ricerca e atterraggio.
## Lo usano sia le persone (missioni assegnate con un tocco) sia l'IA.

## Ordini automatici di un'AF per il turno in corso.
static func ordini_af(eng, fid: String) -> Dictionary:
	var st: Dictionary = eng.st
	var af: Dictionary = st["af"][fid]
	var s: String = af["lato"]
	var miss: Dictionary = af.get("missione", {})
	var tipo: String = str(miss.get("tipo", "manuale"))
	var t: int = st["turno"]
	var entro: int = eng.af_entro(fid)
	var h: Vector2i = eng.af_hex(fid)
	var mf: int = eng.af_mf(fid)
	var casa := _casa(eng, fid)
	var casa_h: Vector2i = eng.nido_hex(casa) if casa != "" else Vector2i(-999, -999)
	# quanto serve per tornare
	var mf_pieno: int = maxi(1, eng.af_mf_base(fid) - 1)
	var turni_ritorno := 99
	if casa_h.x > -100:
		turni_ritorno = int(ceil(float(FTData.dist(h, casa_h)) / mf_pieno))
	var margine := entro - t   # turni ancora disponibili dopo questo
	match tipo:
		"cap":
			var nid: String = str(miss.get("nido", casa))
			var nh: Vector2i = eng.nido_hex(nid)
			if nh.x < -100:
				af["missione"] = {"tipo": "rientro"}
				return ordini_af(eng, fid)
			if entro <= t + 1 or eng.notte():
				# atterra adesso (è sopra il nido)
				if nh == h:
					return {"rotta": [], "quota": "B", "atterra": nid}
				return _verso(eng, fid, nh, "B", false, nid)
			# la pattuglia resta alla quota a cui è stata lanciata (alta contro i picchiatori, bassa contro i siluri)
			if nh != h:
				return _verso(eng, fid, nh, af["quota"], false, "")
			return {"rotta": [], "quota": af["quota"]}
		"attacco":
			if not eng._af_armata(af) or margine < turni_ritorno + 1:
				af["missione"] = {"tipo": "rientro", "da": "attacco"}
				return ordini_af(eng, fid)
			var bers: String = str(miss.get("bersaglio", ""))
			var dest := Vector2i(-999, -999)
			if bers != "":
				var noto: Dictionary = st["noti"][s].get(bers, {})
				if not noto.is_empty() and int(noto.get("cond", 0)) >= 1:
					dest = eng.vh(noto["hex"])
				elif st["memoria"][s].has(bers):
					dest = eng.vh(st["memoria"][s][bers]["hex"])
			if str(miss.get("bersaglio_base", "")) != "":
				var b: Dictionary = st["basi"].get(miss["bersaglio_base"], {})
				if not b.is_empty():
					dest = eng.vh(b["hex"])
			if dest.x < -100 and miss.has("hex"):
				dest = eng.vh(miss["hex"])
			if dest.x < -100:
				af["missione"] = {"tipo": "rientro"}
				return ordini_af(eng, fid)
			# arrivati e niente da vedere: si aspetta un turno cercando, poi si torna
			if dest == h:
				var attese: int = int(miss.get("attese", 0))
				if attese >= 1 and not _bersaglio_qui(eng, fid, h):
					af["missione"] = {"tipo": "rientro"}
					return ordini_af(eng, fid)
				miss["attese"] = attese + 1
				return {"rotta": [], "quota": _quota_attacco(af), "cerca": true}
			# il percorso fino al bersaglio deve lasciare il carburante per tornare
			var dd := FTData.dist(h, dest)
			var andata := 1 + int(ceil(float(maxi(0, dd - mf)) / mf_pieno))
			var ritorno := 99
			if casa_h.x > -100:
				ritorno = int(ceil(float(FTData.dist(dest, casa_h)) / mf_pieno)) + 1
			if andata + ritorno > margine + 1 and int(miss.get("ostinato", 0)) == 0:
				af["missione"] = {"tipo": "rientro"}
				return ordini_af(eng, fid)
			var o := _verso(eng, fid, dest, _quota_attacco(af), true, "")
			return o
		"ricognizione":
			var dir: Vector2i = eng.vh(miss.get("verso", [h.x, h.y]))
			var andata2: int = int(miss.get("andata", maxi(1, (entro - int(af["lanciata"]) + 1) / 2 - 1)))
			if t - int(af["lanciata"]) >= andata2 or margine <= turni_ritorno + 1 or h == dir:
				af["missione"] = {"tipo": "rientro", "da": "ricognizione"}
				return ordini_af(eng, fid)
			var o2 := _verso(eng, fid, dir, "A", true, "")
			return o2
		"trasferimento":
			var dn: String = str(miss.get("nido", ""))
			var dh: Vector2i = eng.nido_hex(dn)
			if dh.x < -100:
				af["missione"] = {"tipo": "rientro"}
				return ordini_af(eng, fid)
			return _verso(eng, fid, dh, "B", false, dn)
		"rientro":
			if casa == "" or casa_h.x < -100:
				casa = _casa_alternativa(eng, fid)
				if casa == "":
					return {"rotta": [], "quota": "B"}
				af["casa"] = casa
				casa_h = eng.nido_hex(casa)
			var o3 := _verso(eng, fid, casa_h, "B", false, casa)
			o3["bombe_via"] = eng.notte() or FTData.dist(h, casa_h) <= mf
			return o3
		"manuale":
			# senza ordini resta dove si trova; all'ultimo turno di autonomia prova a rientrare
			if margine <= turni_ritorno and casa != "":
				af["missione"] = {"tipo": "rientro"}
				return ordini_af(eng, fid)
			if str(af.get("in_volo_di", "")) != "" and entro <= t + 1:
				return {"rotta": [], "quota": "B", "atterra": af["in_volo_di"]}
			return {"rotta": [], "quota": af["quota"]}
	return {}


static func _bersaglio_qui(eng, fid: String, h: Vector2i) -> bool:
	var st: Dictionary = eng.st
	var s: String = st["af"][fid]["lato"]
	for k in st["noti"][s]:
		var n: Dictionary = st["noti"][s][k]
		if n["tipo"] == "tf" and eng.vh(n["hex"]) == h and int(n.get("cond", 0)) >= 1:
			return true
	return false


static func _quota_attacco(af: Dictionary) -> String:
	var silu := false
	var alto := false
	for g in af["gruppi"]:
		if g["arma"] == "T":
			silu = true
		var b: Dictionary = FTData.aerei[g["tipo"]]["bht"]
		if g["arma"] in ["AP", "GP"]:
			var k: String = str(g["arma"]).to_lower()
			if int(b["s_dv_" + k]) > 0 or int(b["s_hl_" + k]) > 0 or int(b["b_hl_" + k]) > 0:
				alto = true
	if silu:
		return "B"
	return "A" if alto else "B"


## Ordini per andare verso un esagono (fino al movimento disponibile); atterra se arriva al nido.
static func _verso(eng, fid: String, dest: Vector2i, quota: String, cerca: bool, atterra: String) -> Dictionary:
	var af: Dictionary = eng.st["af"][fid]
	var h: Vector2i = eng.af_hex(fid)
	# a bassa quota non si scavalcano le montagne: si vola alti finché serve
	var q := quota
	var evita := {}
	for k in eng.nubi_map():
		if int(eng.nubi_map()[k]) >= 2:
			evita[k] = true
	var path := FTData.percorso(h, dest, false, evita)
	if path.is_empty() and h != dest:
		path = FTData.percorso(h, dest, false)
	var mf: int = eng.af_mf(fid)
	if q == "B":
		mf = mini(mf, eng.af_mf_base(fid) - 1)
	var rotta := []
	var prec := h
	for i in mini(mf, path.size()):
		var p: Vector2i = path[i]
		if FTData.montagna(p) or FTData.crinale(prec, p):
			q = "A"
		prec = p
		rotta.append([p.x, p.y])
	var o := {"rotta": rotta, "quota": q, "cerca": cerca}
	if atterra != "":
		var arriva := (path.size() <= mf)
		if arriva:
			o["atterra"] = atterra
			o["quota_fine"] = "B"
	return o


static func _casa(eng, fid: String) -> String:
	var af: Dictionary = eng.st["af"][fid]
	var c: String = str(af.get("casa", ""))
	if c != "" and eng.st["nidi"].has(c) and eng.nido_hex(c).x > -100:
		for g in af["gruppi"]:
			if not eng.nido_accetta(c, g["tipo"]):
				return _casa_alternativa(eng, fid)
		if eng.nido_lato(c) == af["lato"]:
			return c
	return _casa_alternativa(eng, fid)


## Il nido amico più vicino che accetta tutti gli aerei dell'AF.
static func _casa_alternativa(eng, fid: String) -> String:
	var af: Dictionary = eng.st["af"][fid]
	var h: Vector2i = eng.af_hex(fid)
	var best := ""
	var bd := 9999
	for nid in eng.nidi_del_lato(af["lato"]):
		var ok := true
		for g in af["gruppi"]:
			if not eng.nido_accetta(nid, g["tipo"]):
				ok = false
				break
		if not ok:
			continue
		var nh: Vector2i = eng.nido_hex(nid)
		if nh.x < -100:
			continue
		var lf: Array = eng.nido_lf(nid)
		if int(lf[0]) <= 0:
			continue
		var d := FTData.dist(h, nh)
		if d < bd:
			bd = d
			best = nid
	return best


## Raggio d'azione (in esagoni) di una missione d'attacco con andata e ritorno per un gruppo d'aerei.
static func raggio(tipi: Array, armati: bool) -> int:
	var mf := 99
	var rf := 99
	for t in tipi:
		mf = mini(mf, int(FTData.aerei[t]["mf"]))
		var r: int = int(FTData.aerei[t]["rf"])
		if not armati and not (t in ["Catalina", "Mavis", "Emily"]):
			r += 1
		rf = mini(rf, r)
	if mf == 99:
		return 0
	# un turno per il decollo a metà velocità, uno di riserva per l'atterraggio
	var turni: int = maxi(0, rf - 2)
	return (turni * (mf - 1)) / 2
