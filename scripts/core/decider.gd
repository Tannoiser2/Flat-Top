class_name FTDecider
extends RefCounted
## Chi prende le decisioni in una partita sullo stesso dispositivo: le persone (attraverso la vista di
## gioco) e l'IA. In due sullo stesso dispositivo gli ordini simultanei si danno uno alla volta, con lo
## schermo coperto fra un giocatore e l'altro.

var view            # vista di gioco: chiedi(lato, req) -> Dictionary
var umani := {}     # lato -> true se lo comanda una persona


func decide_simul(eng: FTEngine, req: Dictionary) -> Dictionary:
	var out := {}
	for s in FTEngine.LATI:
		if umani.get(s, false) and view != null:
			out[s] = await view.chiedi(s, req)
		else:
			out[s] = eng.ais[s].decide(eng, s, req)
	return out


func decide(eng: FTEngine, s: String, req: Dictionary) -> Dictionary:
	if umani.get(s, false) and view != null:
		return await view.chiedi(s, req)
	if view != null and view.has_method("pausa_ia"):
		await view.pausa_ia(s, req)
	return eng.ais[s].decide(eng, s, req)
