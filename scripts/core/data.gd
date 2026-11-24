class_name FTData
extends RefCounted
## Dati del gioco (mappa, aerei, navi, basi, scenari) letti dai file JSON in res://data.
## La griglia è a esagoni con il lato piatto in alto, colonne verticali, colonne dispari spostate in basso
## di mezzo esagono (come la mappa originale del modulo VASSAL).

static var _loaded := false
static var mappa: Dictionary = {}
static var aerei: Dictionary = {}
static var navi: Dictionary = {}
static var generiche: Dictionary = {}
static var ops: Dictionary = {}
static var ops_tipo: Dictionary = {}
static var basi: Dictionary = {}
static var scenari: Array = []
static var isole: Dictionary = {}
static var grid: PackedStringArray = PackedStringArray()
## Lati d'esagono speciali (chiave «c,r|c,r» con il primo esagono minore): scogliere e terra piena fermano
## le TF, i crinali montuosi fermano gli aerei a bassa quota.
static var lati_scogliera := {}
static var lati_terra := {}
static var lati_montagna := {}
static var isole_mappa: Array = []      # isole: liste di esagoni di terra (parziali e pieni)
static var isola_di := {}               # esagono -> indice dell'isola
static var guardacoste: Array = []      # [{lato, hex, isola}]
static var row0 := -4
static var X0 := 128.0
static var Y0 := 252.0
static var DX := 48.0
static var DY := 56.0
static var COLS := 80
static var ROWS := 51

const DIRS_EVEN := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
const DIRS_ODD := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
## Direzioni: 0 = nord, 1 = nord-est, 2 = sud-est, 3 = sud, 4 = sud-ovest, 5 = nord-ovest (sul gioco: 1-6)

## Esagoni direzionali (rosa dei venti) dei settori I-VIII
static var SETTORE_HEX: Array = [Vector2i(9, 11), Vector2i(29, 11), Vector2i(49, 11), Vector2i(69, 11),
	Vector2i(9, 32), Vector2i(29, 32), Vector2i(49, 32), Vector2i(69, 32)]
## Divisione in settori della mappa corrente: larghezza in colonne, ultima riga dei settori in alto, settori per riga.
static var sett_col_w := 20
static var sett_row := 21
static var sett_ncol := 4
static var mappa_nome := ""
static var mappa_img := "res://assets/map/mappa.webp"
const SETTORE_NOME := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]


static func load_all() -> void:
	if _loaded:
		return
	mappa = _json("res://data/mappa.json")
	aerei = _json("res://data/aerei.json")
	var nv := _json("res://data/navi.json")
	navi = nv.get("navi", {})
	generiche = nv.get("generiche", {})
	ops = nv.get("ops", {})
	ops_tipo = nv.get("ops_tipo", {})
	basi = _json("res://data/basi.json")
	var sc := _json("res://data/scenari.json")
	scenari = sc.get("scenari", [])
	isole = sc.get("isole", {})
	_loaded = true
	load_map("")


## Carica la mappa di uno scenario: "" è il Pacifico meridionale, "midway" e "wake" le mappe degli scenari 6 e 7.
static func load_map(nome: String) -> void:
	if nome == mappa_nome and not grid.is_empty():
		return
	mappa_nome = nome
	var suf := "" if nome == "" else "_" + nome
	mappa = _json("res://data/mappa%s.json" % suf)
	grid = PackedStringArray(mappa.get("grid", []))
	lati_scogliera = {}
	lati_terra = {}
	lati_montagna = {}
	isola_di = {}
	var lt := _json("res://data/lati%s.json" % suf)
	for k in ["scogliere", "terra", "montagne"]:
		var dest: Dictionary = {"scogliere": lati_scogliera, "terra": lati_terra, "montagne": lati_montagna}[k]
		for e in lt.get(k, []):
			var a := Vector2i(int(e[0]), int(e[1]))
			dest[chiave_lato(a, vicino(a, int(e[2])))] = true
	isole_mappa = lt.get("isole", [])
	for i in isole_mappa.size():
		for h in isole_mappa[i]:
			isola_di[Vector2i(int(h[0]), int(h[1]))] = i
	guardacoste = lt.get("guardacoste", [])
	row0 = int(mappa.get("row0", -4))
	X0 = float(mappa.get("x0", 128))
	Y0 = float(mappa.get("y0", 252))
	DX = float(mappa.get("dx", 48))
	DY = float(mappa.get("dy", 56))
	COLS = int(mappa.get("cols", 80))
	ROWS = grid.size()
	mappa_img = str(mappa.get("img", "res://assets/map/mappa.webp"))
	sett_col_w = int(mappa.get("sett_col_w", 20))
	sett_row = int(mappa.get("sett_row", 21))
	sett_ncol = int(mappa.get("sett_ncol", 4))
	SETTORE_HEX = []
	for p in mappa.get("settori_hex", [[9, 11], [29, 11], [49, 11], [69, 11], [9, 32], [29, 32], [49, 32], [69, 32]]):
		SETTORE_HEX.append(Vector2i(int(p[0]), int(p[1])))


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Dati mancanti: " + path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func scenario(id: String) -> Dictionary:
	for s in scenari:
		if s["id"] == id:
			return s
	return {}


# ------------------------------------------------------------ esagoni

static func ter(h: Vector2i) -> String:
	var rr := h.y - row0
	if rr < 0 or rr >= grid.size() or h.x < 0 or h.x >= COLS:
		return " "
	var line: String = grid[rr]
	if h.x >= line.length():
		return " "
	return line[h.x]


## Il mare aperto e gli esagoni costieri si navigano; la terra piena, la pista fuori mappa e il nero no.
static func navigabile(h: Vector2i) -> bool:
	var t := ter(h)
	return t == "." or t == "p"


## Gli aerei volano ovunque sul tavolo; la pista rossa e le basi fuori mappa si raggiungono solo
## attraverso gli esagoni d'ingresso (14.11).
static func volabile(h: Vector2i) -> bool:
	var t := ter(h)
	return t != " " and t != "t" and t != "B"


static func chiave_lato(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var t := a
		a = b
		b = t
	return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]


## Una TF può passare da a all'esagono vicino b? (scogliere e lati di terra piena la fermano: 12.5)
static func passaggio_nave(a: Vector2i, b: Vector2i) -> bool:
	if not navigabile(b):
		return false
	var k := chiave_lato(a, b)
	return not lati_scogliera.has(k) and not lati_terra.has(k)


## Un aereo a bassa quota non attraversa i crinali montuosi.
static func crinale(a: Vector2i, b: Vector2i) -> bool:
	return lati_montagna.has(chiave_lato(a, b))


static func montagna(h: Vector2i) -> bool:
	return ter(h) == "M"


static func centro(h: Vector2i) -> Vector2:
	return Vector2(X0 + h.x * DX, Y0 + h.y * DY + (DY * 0.5 if (h.x & 1) == 1 else 0.0))


static func da_pixel(p: Vector2) -> Vector2i:
	var c := int(round((p.x - X0) / DX))
	var best := Vector2i(c, 0)
	var bd := INF
	for cc in [c - 1, c, c + 1]:
		var off := DY * 0.5 if (cc & 1) == 1 else 0.0
		var r := int(round((p.y - Y0 - off) / DY))
		for rr in [r - 1, r, r + 1]:
			var h := Vector2i(cc, rr)
			var d := centro(h).distance_squared_to(p)
			if d < bd:
				bd = d
				best = h
	return best


static func vicino(h: Vector2i, d: int) -> Vector2i:
	var dirs: Array = DIRS_ODD if (h.x & 1) == 1 else DIRS_EVEN
	return h + dirs[d]


static func vicini(h: Vector2i) -> Array:
	var out := []
	for d in 6:
		out.append(vicino(h, d))
	return out


static func cube(h: Vector2i) -> Vector3i:
	var x := h.x
	var z := h.y - (h.x - (h.x & 1)) / 2
	return Vector3i(x, -x - z, z)


static func dist(a: Vector2i, b: Vector2i) -> int:
	var ca := cube(a)
	var cb := cube(b)
	return maxi(maxi(absi(ca.x - cb.x), absi(ca.y - cb.y)), absi(ca.z - cb.z))


static func dentro(h: Vector2i, r: int) -> Array:
	var out := []
	for c in range(h.x - r - 1, h.x + r + 2):
		for rr in range(h.y - r - 1, h.y + r + 2):
			var q := Vector2i(c, rr)
			if dist(h, q) <= r:
				out.append(q)
	return out


## Settore dell'esagono (0-7 sul Pacifico meridionale: quattro colonne di settori, due righe; 0-3 su Midway e Wake).
static func settore(h: Vector2i) -> int:
	var col := clampi(h.x / sett_col_w, 0, sett_ncol - 1)
	var riga := 0 if h.y <= sett_row else 1
	return riga * sett_ncol + col


static func lettere_colonna(c: int) -> String:
	var L := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var k := c % 26
	var rep := c / 26 + 1
	return L[k].repeat(rep)


## Nome dell'esagono come sulla mappa: lettere della colonna e numero di riga (righe da 1).
static func nome_hex(h: Vector2i) -> String:
	return "%s%d" % [lettere_colonna(h.x), h.y + 1]


## Passo successivo lungo la retta fra due esagoni (linea discreta).
static func linea(a: Vector2i, b: Vector2i) -> Array:
	var n := dist(a, b)
	var out := []
	if n == 0:
		return out
	var ca := Vector3(cube(a))
	var cb := Vector3(cube(b))
	ca += Vector3(1e-6, 2e-6, -3e-6)
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := ca.lerp(cb, t)
		var rx := roundi(p.x)
		var ry := roundi(p.y)
		var rz := roundi(p.z)
		var dx := absf(rx - p.x)
		var dy := absf(ry - p.y)
		var dz := absf(rz - p.z)
		if dx > dy and dx > dz:
			rx = -ry - rz
		elif dy > dz:
			ry = -rx - rz
		else:
			rz = -rx - ry
		var col := rx
		var row := rz + (col - (col & 1)) / 2
		out.append(Vector2i(col, row))
	return out


## Percorso più breve (A*) fra due esagoni. per_nave: solo esagoni navigabili. evita: esagoni da evitare.
## Restituisce la lista degli esagoni dopo la partenza, oppure [] se non c'è strada (entro limite passi).
static func percorso(a: Vector2i, b: Vector2i, per_nave: bool, evita: Dictionary = {}, limite := 4000) -> Array:
	if a == b:
		return []
	if per_nave and not navigabile(b):
		return []
	if not per_nave and not volabile(b):
		return []
	# per gli aerei la retta basta quasi sempre
	if not per_nave and evita.is_empty():
		var l := linea(a, b)
		var ok := true
		for h in l:
			if not volabile(h):
				ok = false
				break
		if ok:
			return l
	var open := {a: 0}
	var came := {}
	var g := {a: 0}
	var steps := 0
	while not open.is_empty() and steps < limite:
		steps += 1
		var cur: Vector2i
		var bf := INF
		for k in open:
			var f: float = open[k]
			if f < bf:
				bf = f
				cur = k
		if cur == b:
			var path := [cur]
			while came.has(cur):
				cur = came[cur]
				path.push_front(cur)
			path.pop_front()
			return path
		open.erase(cur)
		for nb in vicini(cur):
			if per_nave and not passaggio_nave(cur, nb):
				continue
			if not per_nave and not volabile(nb):
				continue
			if evita.has(nb) and nb != b:
				continue
			var ng: int = g[cur] + 1
			if not g.has(nb) or ng < g[nb]:
				g[nb] = ng
				came[nb] = cur
				open[nb] = ng + dist(nb, b)
	return []


# ------------------------------------------------------------ tabelle

## Tabella dei risultati del combattimento (CRT): righe BHT 1-15, colonne per numero di fattori attaccanti.
## -1 = asterisco (un colpo solo con il 6).
const CRT_COL := [2, 4, 6, 8, 10, 12, 15, 20, 25, 30, 35, 40, 45, 9999]
const CRT := [
	[-1, -1, -1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2],
	[-1, -1, 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3],
	[-1, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5],
	[-1, 1, 1, 1, 1, 2, 2, 2, 3, 4, 4, 5, 6, 6],
	[-1, 1, 1, 1, 2, 2, 3, 3, 4, 5, 6, 6, 7, 8],
	[0, 1, 1, 2, 2, 2, 3, 4, 5, 6, 7, 8, 8, 9],
	[0, 1, 1, 2, 2, 3, 3, 4, 5, 7, 8, 9, 10, 11],
	[0, 1, 1, 2, 2, 3, 4, 5, 6, 7, 9, 10, 11, 13],
	[0, 1, 2, 2, 3, 3, 4, 5, 7, 8, 10, 11, 13, 14],
	[0, 1, 2, 2, 3, 4, 5, 6, 7, 9, 11, 12, 14, 16],
	[0, 1, 2, 3, 3, 4, 5, 6, 8, 10, 12, 13, 16, 17],
	[0, 1, 2, 3, 4, 4, 6, 7, 9, 11, 13, 15, 17, 19],
	[0, 1, 2, 3, 4, 5, 6, 7, 9, 11, 13, 15, 18, 21],
	[0, 1, 2, 3, 4, 5, 7, 8, 10, 12, 14, 17, 20, 22],
	[1, 2, 3, 4, 5, 6, 7, 9, 11, 13, 17, 19, 21, 23],
]


static func crt_numero(bht: int, fattori: int) -> int:
	bht = clampi(bht, 1, 15)
	var col := 0
	while col < CRT_COL.size() - 1 and fattori > CRT_COL[col]:
		col += 1
	return CRT[bht - 1][col]


static func is_notte(ora: int) -> bool:
	return ora >= 19 or ora <= 5
