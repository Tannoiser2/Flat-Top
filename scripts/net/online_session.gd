class_name FTOnline
extends Node
## Partita online in due, in lockstep: entrambi i dispositivi fanno girare lo stesso motore con lo
## stesso seme e applicano le stesse decisioni nello stesso ordine. Sul database viaggiano solo gli
## ordini (acts/0, acts/1, ...). Per gli ordini simultanei ognuno scrive nel suo posto: Alleati nel
## primo numero libero, Giappone nel successivo; poi si aspetta quello dell'altro.
## Ogni dispositivo mostra solo quello che sa il suo lato.

var net: Net
var view
var code := ""
var seat := 0
var lato := "A"
var n := 0
var backlog: Array = []
var alive := true


func setup(p_net: Net, p_code: String, p_seat: int, p_backlog: Array) -> void:
	net = p_net
	code = p_code
	seat = p_seat
	lato = "A" if seat == 0 else "J"
	backlog = p_backlog


func _exit_tree() -> void:
	alive = false


func _val(a: Dictionary) -> Dictionary:
	var v = str_to_var(str(a.get("v", "{}")))
	return v if v is Dictionary else {}


func decide_simul(eng: FTEngine, req: Dictionary) -> Dictionary:
	var base := n
	n += 2
	var out := {}
	var mia := base + (0 if lato == "A" else 1)
	var sua := base + (1 if lato == "A" else 0)
	if sua < backlog.size() and mia < backlog.size():
		out[lato] = _val(backlog[mia])
		out[eng.nemico(lato)] = _val(backlog[sua])
		return out
	if mia < backlog.size():
		out[lato] = _val(backlog[mia])
	else:
		out[lato] = await view.chiedi(lato, req)
		await _pubblica(mia, out[lato])
	if sua < backlog.size():
		out[eng.nemico(lato)] = _val(backlog[sua])
	else:
		out[eng.nemico(lato)] = await _aspetta(sua)
	return out


func decide(eng: FTEngine, s: String, req: Dictionary) -> Dictionary:
	var k := n
	n += 1
	if k < backlog.size():
		return _val(backlog[k])
	if s == lato:
		var v: Dictionary = await view.chiedi(s, req)
		await _pubblica(k, v)
		return v
	return await _aspetta(k)


func _pubblica(k: int, v: Dictionary) -> void:
	var a := {"s": seat, "k": "o", "v": var_to_str(v)}
	while alive:
		if await net.post_act(code, k, a):
			return
		var ex := await net.get_act(code, k)
		if not ex.is_empty() and not ex.has("_err"):
			return
		if view != null:
			view.stato_online("Rete non raggiungibile, riprovo... (%s)" % net.last_error)
		await get_tree().create_timer(2.0).timeout


func _aspetta(k: int) -> Dictionary:
	if view != null:
		view.stato_online("In attesa degli ordini dell'altro ammiraglio...")
	var t0 := Time.get_ticks_msec()
	while alive:
		var a := await net.get_act(code, k)
		if not a.is_empty() and not a.has("_err"):
			if view != null:
				view.stato_online("")
			return _val(a)
		if view != null and Time.get_ticks_msec() - t0 > 90000:
			view.stato_online("L'altro ammiraglio ci sta pensando da un po'...")
		await get_tree().create_timer(1.5).timeout
	return {}


func heartbeat_loop() -> void:
	while alive:
		net.heartbeat(code, seat)
		await get_tree().create_timer(6.0).timeout
