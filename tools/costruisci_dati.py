#!/usr/bin/env python3
"""Costruisce i dati di Flat Top (mappa, esagoni, aerei, navi, basi, scenari) dal materiale originale.
Va lanciato dalla radice del progetto con il materiale estratto in ../mat (modulo VASSAL FlatTop_v3)."""
import json, os, sys
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAT = os.environ.get('FT_MAT', os.path.join(ROOT, '..', 'mat'))
D = os.path.join(ROOT, 'data')

# ---------------- mappa ----------------
raw = json.load(open('/home/claude/flat-top/data/hexes_raw.json'))
OFFBASE = {(23, -4), (18, -2), (1, 45), (60, 45)}
cols, rows = 80, 51  # righe da -4 a 46
grid = []
for r in range(-4, 47):
    line = ''
    for c in range(0, 80):
        h = raw.get('%d,%d' % (c, r))
        if (c, r) in OFFBASE: ch = 'B'
        elif h is None: ch = ' '
        else:
            t = h['t']
            ch = {'sea': '.', 'partial': 'p', 'land': 'L', 'track': 't', 'void': ' ', 'offbase': 'B'}[t]
            if t == 'land' and h['m']: ch = 'M'
        line += ch
    grid.append(line)
json.dump({'x0': 128, 'y0': 252, 'dx': 48, 'dy': 56, 'row0': -4, 'cols': 80, 'rows': len(grid), 'grid': grid},
          open(os.path.join(D, 'mappa.json'), 'w'), indent=0)

# ---------------- aerei ----------------
# mf/rf dalla Plane Data Chart (Air Record Sheet); ruoli: I intercettore, I* solo a bassa quota, E scorta, B bombardiere
# bht: aria-aria e tabelle di bombardamento (Air Hit Tables). Chiavi: b=contro basi, s=contro navi;
# hl=livello alta quota, ll=livello bassa quota, dv=picchiata, to=siluro; gp/ap = tipo di bomba
def P(nome, lato, sigla, ruoli, mf, rf, aa, cls, base_hl=(0, 0), base_ll=(0, 0), base_dv=(0, 0), nave_hl=(0, 0), nave_ll=(0, 0), nave_dv=(0, 0), siluro=0):
    return {'nome': nome, 'lato': lato, 'sigla': sigla, 'ruoli': ruoli, 'mf': mf, 'rf': rf, 'aa': aa, 'classe': cls,
            'bht': {'b_hl_gp': base_hl[0], 'b_hl_ap': base_hl[1], 'b_ll_gp': base_ll[0], 'b_ll_ap': base_ll[1],
                    'b_dv_gp': base_dv[0], 'b_dv_ap': base_dv[1], 's_hl_gp': nave_hl[0], 's_hl_ap': nave_hl[1],
                    's_ll_gp': nave_ll[0], 's_ll_ap': nave_ll[1], 's_dv_gp': nave_dv[0], 's_dv_ap': nave_dv[1], 's_to': siluro}}
# classe: CV = imbarcato su portaerei (e anche a terra), L = solo terrestre, FL = idro leggero, FH = idro pesante
AEREI = {
    # Alleati
    'A-20': P('A-20', 'A', '20', 'B', 9, 6, 3, 'L', (5, 2), (8, 3), (0, 0), (0, 1), (2, 5)),
    'Avenger': P('Avenger', 'A', 'A', 'I*B', 7, 8, 3, 'CV', (4, 2), (6, 2), (0, 0), (0, 1), (2, 5), (0, 0), 6),
    'Beaufighter': P('Beaufighter', 'A', 'BF', 'IEB', 9, 6, 6, 'L', (0, 0), (5, 0), (0, 0), (0, 0), (1, 3)),
    'Beaufort': P('Beaufort', 'A', 'BT', 'B', 7, 8, 3, 'L', (4, 2), (6, 2), (0, 0), (0, 1), (2, 6), (0, 0), 7),
    'B-17': P('B-17', 'A', '17', 'B', 8, 12, 8, 'L', (10, 3), (0, 0), (0, 0), (0, 1), (0, 0)),
    'B-25': P('B-25', 'A', '25', 'B', 9, 7, 4, 'L', (8, 3), (11, 5), (0, 0), (0, 1), (3, 7)),
    'B-26': P('B-26', 'A', '26', 'B', 10, 6, 4, 'L', (6, 2), (10, 4), (0, 0), (0, 1), (2, 5), (0, 0), 5),
    'Catalina': P('Catalina', 'A', 'C', 'B', 6, 20, 4, 'FH', (6, 2), (9, 3), (0, 0), (0, 1), (2, 7), (0, 0), 10),
    'Dauntless': P('Dauntless', 'A', 'DT', 'I*B', 9, 6, 3, 'CV', (3, 1), (5, 1), (6, 2), (0, 0), (2, 5), (2, 7)),
    'Devastator': P('Devastator', 'A', 'DV', 'B', 6, 5, 2, 'CV', (3, 1), (5, 2), (0, 0), (0, 0), (1, 5), (0, 0), 6),
    'Hudson': P('Hudson', 'A', 'H', 'B', 7, 10, 3, 'L', (3, 1), (6, 2), (0, 0), (1, 1), (1, 4)),
    'P-38': P('P-38', 'A', '38', 'IEB', 12, 5, 7, 'L', (0, 0), (5, 0), (0, 0), (0, 0), (1, 0)),
    'P-39': P('P-39', 'A', '39', 'IEB', 11, 5, 7, 'L', (0, 0), (5, 0), (0, 0), (0, 0), (1, 0)),
    'P-40': P('P-40', 'A', '40', 'IEB', 11, 5, 7, 'L', (0, 0), (4, 0), (0, 0), (0, 0), (1, 0)),
    'Wildcat': P('Wildcat', 'A', 'W', 'IEB', 8, 6, 9, 'CV', (0, 0), (4, 0), (0, 0), (0, 0), (1, 0)),
    # scenari 6 e 7 (Midway, Wake): valori di combattimento dalla tabella del modulo, movimento stimato
    'Buffalo': P('Buffalo', 'A', 'BU', 'IE', 7, 5, 7, 'CV'),
    'Vindicator': P('Vindicator', 'A', 'VI', 'I*B', 7, 6, 3, 'CV', (3, 1), (5, 1), (6, 2), (0, 0), (1, 5), (3, 6)),
    'B-24': P('B-24', 'A', '24', 'B', 8, 14, 3, 'L', (10, 3), (0, 0), (0, 0), (0, 1), (0, 0)),
    # Giappone
    'Betty': P('Betty', 'J', 'B', 'B', 9, 10, 3, 'L', (4, 2), (6, 2), (0, 0), (0, 1), (2, 5), (0, 0), 9),
    'Dave': P('Dave', 'J', 'D', 'IE', 4, 6, 1, 'FL'),
    'Emily': P('Emily', 'J', 'E', 'B', 9, 24, 6, 'FH', (8, 3), (9, 4), (0, 0), (0, 1), (3, 7), (0, 0), 15),
    'Jake': P('Jake', 'J', 'JK', 'IE', 5, 9, 1, 'FL'),
    'Judy': P('Judy', 'J', 'JD', 'I*B', 11, 6, 3, 'CV', (2, 1), (3, 1), (4, 2), (0, 0), (1, 5), (2, 7)),
    'Kate': P('Kate', 'J', 'K', 'B', 8, 7, 2, 'CV', (4, 2), (6, 2), (0, 0), (0, 1), (2, 6), (0, 0), 10),
    'Mavis': P('Mavis', 'J', 'M', 'B', 8, 23, 5, 'FH', (6, 2), (7, 3), (0, 0), (0, 1), (2, 6), (0, 0), 15),
    'Nell': P('Nell', 'J', 'N', 'B', 8, 8, 3, 'L', (4, 2), (6, 2), (0, 0), (0, 1), (2, 4), (0, 0), 9),
    'Pete': P('Pete', 'J', 'P', 'IE', 4, 6, 1, 'FL'),
    'Rufe': P('Rufe', 'J', 'R', 'IEB', 9, 6, 6, 'FL', (0, 0), (3, 0), (0, 0), (0, 0), (1, 0)),
    'Val': P('Val', 'J', 'V', 'I*B', 9, 7, 2, 'CV', (2, 1), (3, 1), (4, 2), (0, 0), (1, 5), (2, 7)),
    'Zero': P('Zero', 'J', 'Z', 'IEB', 10, 8, 9, 'CV', (0, 0), (3, 0), (0, 0), (0, 0), (1, 0)),
}
json.dump(AEREI, open(os.path.join(D, 'aerei.json'), 'w'), indent=1, ensure_ascii=False)

# ---------------- basi ----------------
INF = 999
def B(nome, lato, hex_, sigla, mc, lf, rf, ph, aaf=0, sf=0, fuori=False, porte=None, ritardo=None):
    b = {'nome': nome, 'lato': lato, 'hex': list(hex_), 'sigla': sigla, 'mc': mc, 'lf': list(lf), 'rf': rf, 'ph': ph, 'aaf': aaf, 'sf': sf, 'fuori': fuori}
    if porte: b['porte'] = porte
    if ritardo: b['ritardo'] = ritardo
    return b
# profili per gruppi di scenari: cs = Coral Sea/Rabaul, es = Eastern Solomons, sc = Santa Cruz/Guadalcanal
BASI = {
    'australia': {'*': B('Australia', 'A', (1, 45), 'A', INF, (INF, INF), 25, 'LS', fuori=True)},
    'nuova_caledonia': {'cs': B('Nuova Caledonia', 'A', (60, 45), 'N', INF, (4, 4), 2, 'S', fuori=True),
                        '*': B('Nuova Caledonia', 'A', (60, 45), 'N', INF, (20, 20), 12, 'LS', fuori=True)},
    'port_moresby': {'*': B('Port Moresby', 'A', (2, 22), 'M', INF, (20, 8), 8, 'L', 10)},
    'espiritu_santo': {'es': B('Espiritu Santo', 'A', (78, 42), 'E', INF, (5, 3), 2, 'LS', 4),
                       '*': B('Espiritu Santo', 'A', (78, 42), 'E', INF, (10, 8), 10, 'LS', 12, 3)},
    'gili_gili': {'es': B('Gili-Gili', 'A', (15, 25), 'G', 10, (6, 2), 5, 'L', 2),
                  '*': B('Gili-Gili', 'A', (15, 25), 'G', INF, (10, 6), 5, 'L', 7)},
    'henderson': {'es': B('Henderson', 'A', (52, 22), 'H', INF, (8, 4), 5, 'L', 5),
                  '*': B('Henderson', 'A', (52, 22), 'H', INF, (12, 6), 8, 'L', 10, 1)},
    'ndeni': {'*': B('Ndeni', 'A', (73, 26), 'ND', 6, (6, 4), 2, 'S', 2)},
    'buka': {'*': B('Buka', 'J', (32, 7), 'BK', 8, (6, 4), 2, 'L', 3)},
    'buna': {'es': B('Buna', 'J', (7, 19), 'BA', INF, (6, 3), 3, 'L', 3),
             '*': B('Buna', 'J', (7, 19), 'BA', INF, (10, 6), 5, 'L', 7)},
    'buin': {'*': B('Buin', 'J', (36, 13), 'BN', INF, (10, 5), 5, 'L', 7)},
    'gasmata': {'*': B('Gasmata', 'J', (15, 10), 'G', INF, (8, 4), 4, 'L', 5)},
    'kavieng': {'*': B('Kavieng', 'J', (18, -2), 'K', INF, (10, 5), 5, 'L', fuori=True)},
    'lae': {'cs': B('Lae', 'J', (2, 13), 'L', INF, (10, 5), 5, 'L', 5),
            '*': B('Lae', 'J', (2, 13), 'L', INF, (12, 5), 6, 'L', 10)},
    'rabaul': {'cs': B('Rabaul', 'J', (23, 3), 'R', INF, (12, 4), 7, 'LS', 9),
               '*': B('Rabaul', 'J', (23, 3), 'R', INF, (20, 9), 12, 'LS', 15, 8)},
    'shortland': {'*': B('Shortland', 'J', (37, 13), 'S', INF, (8, 4), 4, 'S', 5)},
    'truk': {'*': B('Truk', 'J', (23, -4), 'TR', INF, (INF, INF), 20, 'LS', fuori=True)},
    'tulagi': {'*': B('Tulagi', 'J', (53, 21), 'T', 6, (6, 3), 2, 'S', 1)},
    # mappe di Midway e Wake: i numeri sul bordo sono i turni di volo dalle basi fuori mappa
    'midway': {'*': B('Midway', 'A', (29, 15), 'MW', INF, (12, 6), 8, 'LS', 10, 2)},
    'hawaii_m': {'*': B('Hawaii', 'A', (52, 26), 'HW', INF, (INF, INF), 25, 'LS', fuori=True, porte=[[50, r] for r in range(24, 30)], ritardo=7)},
    'johnston': {'*': B('Johnston', 'A', (37, 36), 'JO', INF, (INF, INF), 10, 'S', fuori=True, porte=[[c, 34] for c in (34, 36, 38, 40)], ritardo=5)},
    'marshall': {'*': B('Isole Marshall', 'J', (14, 36), 'MR', INF, (INF, INF), 10, 'S', fuori=True, porte=[[c, 34] for c in (10, 12, 14, 16, 18)], ritardo=10)},
    'wake': {'*': B('Wake', 'A', (13, 19), 'WK', 10, (4, 2), 2, 'L', 3)},
    'hawaii_w': {'*': B('Hawaii', 'A', (52, 16), 'HW', INF, (INF, INF), 25, 'LS', fuori=True, porte=[[50, r] for r in range(14, 20)], ritardo=9)},
    'midway_w': {'*': B('Midway', 'A', (52, 6), 'MW', INF, (INF, INF), 8, 'LS', fuori=True, porte=[[50, r] for r in range(4, 10)], ritardo=2)},
    'kwajalein': {'*': B('Kwajalein', 'J', (12, 36), 'KW', INF, (INF, INF), 10, 'LS', fuori=True, porte=[[c, 34] for c in (10, 12, 14)], ritardo=1)},
}
json.dump(BASI, open(os.path.join(D, 'basi.json'), 'w'), indent=1, ensure_ascii=False)

# ---------------- navi ----------------
src = json.load(open('/tmp/ships_by_scen.json'))
NAVI = {}
for sc in ['10.', '9. ', '8. ', '11.', '5. ', '4.b', '3.b', '2.c', '1. ']:
    for k, v in src.get(sc, {}).items():
        nome, tipo = k.split('|')
        if tipo in ('DD', 'AP', 'APD', 'AO', 'PG', 'SS', 'PT'): continue
        nome = nome.replace('San Fancisco', 'San Francisco')
        rec = {'nome': nome, 'tipo': tipo, 'lato': v['side'], 'art': int(v['gun']) if v['gun'] not in ('*',) else 0,
               'aa': v['aa'], 'mv': v['mv'], 'danno': v['dmg'], 'mun': v['ammo'] if v['ammo'] is not None else NAVI.get(nome, {}).get('mun'),
               'silu': v['torp'] if v['torp'] is not None else NAVI.get(nome, {}).get('silu')}
        old = NAVI.get(nome)
        if old is None or (old.get('mun') is None and rec['mun'] is not None) or sc in ('4.b', '3.b', '2.c', '1. '):
            NAVI[nome] = rec
DEF_MUN = {'BB': 24, 'CA': 12, 'CAV': 12, 'CL': 15, 'CV': 12, 'CVL': 14, 'AV': 12}
for n, v in NAVI.items():
    if v['mun'] is None: v['mun'] = DEF_MUN.get(v['tipo'], 0)
    if v['silu'] is None: v['silu'] = 1 if (v['lato'] == 'J' and v['tipo'] in ('CA', 'CAV')) else (2 if (v['lato'] == 'J' and v['tipo'] == 'CL') else 0)
# correzioni dai regolamenti
NAVI['Shokaku Coral Sea'] = dict(NAVI['Shokaku'], nome='Shokaku', danno=5)
NAVI['Zuikaku Coral Sea'] = dict(NAVI['Zuikaku'], nome='Zuikaku', danno=5)
NAVI['Enterprise Solomons']['nome'] = 'Enterprise'
NAVI['Kamikawa'] = {'nome': 'Kamikawa', 'tipo': 'AV', 'lato': 'J', 'art': 0, 'aa': 1, 'mv': 1, 'danno': 2, 'mun': 0, 'silu': 0}
NAVI['Chitose'] = {'nome': 'Chitose', 'tipo': 'AV', 'lato': 'J', 'art': 1, 'aa': 2, 'mv': 2, 'danno': 3, 'mun': 12, 'silu': 0}
if 'Sendai' not in NAVI: NAVI['Sendai'] = {'nome': 'Sendai', 'tipo': 'CL', 'lato': 'J', 'art': 1, 'aa': 1, 'mv': 2, 'danno': 4, 'mun': 20, 'silu': 2}
if 'Salt Lake City' in NAVI: NAVI['Salt Lake City']['art'] = 5
# navi degli scenari 6 e 7 (pedine del modulo)
NAVI['Akagi'] = {'nome': 'Akagi', 'tipo': 'CV', 'lato': 'J', 'art': 1, 'aa': 4, 'mv': 2, 'danno': 6, 'mun': 12, 'silu': 0}
NAVI['Kaga'] = {'nome': 'Kaga', 'tipo': 'CV', 'lato': 'J', 'art': 1, 'aa': 4, 'mv': 2, 'danno': 6, 'mun': 12, 'silu': 0}
NAVI['Soryu'] = {'nome': 'Soryu', 'tipo': 'CV', 'lato': 'J', 'art': 1, 'aa': 4, 'mv': 2, 'danno': 5, 'mun': 12, 'silu': 0}
NAVI['Hosho'] = {'nome': 'Hosho', 'tipo': 'CVL', 'lato': 'J', 'art': 1, 'aa': 2, 'mv': 1, 'danno': 2, 'mun': 14, 'silu': 0}
NAVI['Nagato'] = dict(NAVI['Mutsu'], nome='Nagato')
NAVI['Chiyoda'] = dict(NAVI['Chitose'], nome='Chiyoda')
NAVI['Nisshin'] = dict(NAVI['Chitose'], nome='Nisshin')
GEN = {
    'DD': {'tipo': 'DD', 'art': 1, 'aa': 1, 'mv': 2, 'danno': 2, 'mun': 1, 'silu': 1},
    'AP': {'tipo': 'AP', 'art': 0, 'aa': 0, 'mv': 1, 'danno': 1, 'mun': 0, 'silu': 0},
    'APD': {'tipo': 'APD', 'art': 1, 'aa': 1, 'mv': 2, 'danno': 2, 'mun': 1, 'silu': 0},
    'AO': {'tipo': 'AO', 'art': 0, 'aa': 1, 'mv': 1, 'danno': 1, 'mun': 0, 'silu': 0},
    'PG': {'tipo': 'PG', 'art': 0, 'aa': 1, 'mv': 1, 'danno': 1, 'mun': 0, 'silu': 0},
}
# operazioni aeree delle navi (Air Operations Chart A): mc, lf normale/minimo, fattore di prontezza (rf), tipo di aerei (CV o FP idro)
OPS = {
    'Enterprise': [33, 11, 3, 9, 'CV'], 'Hornet': [33, 11, 3, 9, 'CV'], 'Lexington': [30, 12, 3, 8, 'CV'],
    'Saratoga': [32, 12, 3, 8, 'CV'], 'Wasp': [28, 10, 3, 7, 'CV'], 'Yorktown': [30, 11, 3, 9, 'CV'],
    'Akagi': [30, 12, 3, 8, 'CV'], 'Kaga': [30, 12, 3, 8, 'CV'], 'Hiryu': [24, 8, 3, 7, 'CV'], 'Soryu': [24, 8, 3, 7, 'CV'],
    'Hiyo': [18, 7, 3, 6, 'CV'], 'Junyo': [18, 7, 3, 6, 'CV'], 'Hosho': [7, 3, 1, 3, 'CV'], 'Ryujo': [16, 5, 2, 4, 'CV'],
    'Shoho': [10, 4, 2, 4, 'CV'], 'Zuiho': [10, 4, 2, 4, 'CV'], 'Shokaku': [28, 10, 3, 8, 'CV'], 'Zuikaku': [28, 10, 3, 8, 'CV'],
    'Chitose': [8, 2, 1, 2, 'FP'], 'Kamikawa': [7, 1, 1, 1, 'FP'], 'Chiyoda': [8, 2, 1, 2, 'FP'], 'Nisshin': [8, 2, 1, 2, 'FP'],
}
OPS_TIPO = {'CAV': [2, 1, 1, 1, 'FP'], 'BB_J': [1, 1, 1, 1, 'FP']}
json.dump({'navi': NAVI, 'generiche': GEN, 'ops': OPS, 'ops_tipo': OPS_TIPO}, open(os.path.join(D, 'navi.json'), 'w'), indent=1, ensure_ascii=False)
print('navi', len(NAVI))

# ---------------- scenari ----------------
G = json.load(open(os.path.join(D, 'mappa.json')))['grid']
def ter(c, r):
    rr = r + 4
    if rr < 0 or rr >= len(G) or c < 0 or c >= 80: return ' '
    return G[rr][c]
def cube(c, r):
    x = c; z = r - (c - (c & 1)) // 2; return x, -x - z, z
def dist(a, b):
    ax, ay, az = cube(*a); bx, by, bz = cube(*b); return max(abs(ax - bx), abs(ay - by), abs(az - bz))
def mare(c, r, ok='.'):
    best = None
    for cc in range(80):
        for rr in range(0, 44):
            if ter(cc, rr) in ok:
                d = dist((c, r), (cc, rr))
                if best is None or d < best[0]: best = (d, (cc, rr))
    return list(best[1])

LT = json.load(open(os.path.join(D, 'lati.json')))
def ISOLA(c, r):
    for comp in LT['isole']:
        if [c, r] in comp: return comp
    raise Exception('isola mancante %d,%d' % (c, r))
# zone di schieramento (vedi FTEngine.zona): settori 1-8, sud/nord/est = entro n esagoni dal bordo della mappa,
# colonne [min,max], vicino/lontano = [esagoni, n], o = unione di più zone
def Z(**k): return k
BOUGAINVILLE = ISOLA(32, 7); DEBOYNE = ISOLA(24, 26); WOODLARK = ISOLA(24, 21); GUADALCANAL = ISOLA(52, 24)
NEW_GEORGIA = ISOLA(42, 18); ONTONG_JAVA = ISOLA(50, 8); GOODENOUGH = ISOLA(17, 24); NDENI = ISOLA(73, 26); STEWART = ISOLA(62, 18)
CW_CORAL = [[41, 14], [48, 17], [40, 16], [42, 18], [52, 24]]

def TF(navi, dove, aerei=None, ancorata=False, entra=None, zona=None, entra_tra=None):
    t = {'navi': navi, 'hex': dove}
    if zona: t['zona'] = zona
    if entra_tra: t['entra_tra'] = entra_tra
    if aerei: t['aerei'] = aerei   # {nome_nave: {tipo: n}}
    if ancorata: t['ancorata'] = True
    if entra is not None: t['entra'] = entra  # turno di entrata (indice)
    return t
def n(k, tipo): return [tipo] * k

SCENARI = []
# 1. Anillos alrededor de Rabaul
SCENARI.append({
    'id': 'rabaul', 'nome': 'Anelli attorno a Rabaul', 'data': '23 febbraio 1942', 'giorno': 0, 'ora': 6, 'turni': 13,
    'mesi': ['23 feb'], 'meteo': 'sparse', 'profilo': 'cs', 'mezza_mappa': 'ovest',
    'descrizione': "Il Lexington tenta un'incursione contro Rabaul. Scenario introduttivo: poche navi e pochi aerei, 13 turni dall'alba al tramonto.",
    'A': {'tf': [TF(['Lexington', 'Minneapolis', 'San Francisco', 'Indianapolis', 'Pensacola'] + n(10, 'DD'), mare(38, 9),
                    {'Lexington': {'Wildcat': 8, 'Dauntless': 12, 'Devastator': 4}}, zona=Z(settori=[2], colonne=[38, 39]))],
          'basi': {'port_moresby': {'P-40': 12, 'Catalina': 4}}, 'radar': ['Lexington', 'port_moresby']},
    'J': {'tf': [], 'basi': {'rabaul': {'Zero': 10, 'Kate': 10, 'Mavis': 4, 'Jake': 1, 'Rufe': 1}, 'kavieng': {'Nell': 12},
                              'gasmata': {}, 'truk': {'Mavis': 4}}, 'radar': []},
    'speciali': {'wildcat7': True, 'tf_unica_A': True, 'cw_ignora_J': [[6, 17]], 'no_decollo_J_turno1': True,
                 'rinforzi_J_avvistamento': {'base': 'truk', 'aerei': {'Zero': 5, 'Betty': 5}}},
    'vittoria': {'tipo': 'rabaul', 'auto': 0, 'min': 20},
    'obiettivi': {'A': {'attacca_base': 'rabaul'}, 'J': {'difendi': 'rabaul'}},
})
CORAL_A_AEREI = {'Lexington': {'Wildcat': 7, 'Dauntless': 13, 'Devastator': 4}, 'Yorktown': {'Wildcat': 7, 'Dauntless': 12, 'Devastator': 4}}
CORAL_J_AEREI = {'Shokaku Coral Sea': {'Zero': 6, 'Val': 7, 'Kate': 6}, 'Zuikaku Coral Sea': {'Zero': 6, 'Val': 7, 'Kate': 5},
                 'Shoho': {'Zero': 4, 'Kate': 6}, 'Kamikawa': {'Dave': 3, 'Pete': 4}}
CORAL_BASI_A = {'nuova_caledonia': {'Catalina': 4}, 'port_moresby': {'Hudson': 2, 'B-26': 12, 'B-25': 5, 'Dauntless': 3, 'P-39': 12, 'P-40': 2},
                'australia': {'B-17': 5, 'Catalina': 1}}
CORAL_BASI_J = {'rabaul': {'Zero': 15, 'Betty': 12}, 'lae': {'Zero': 6}, 'kavieng': {'Nell': 16}, 'tulagi': {'Mavis': 3, 'Rufe': 1}, 'shortland': {'Mavis': 2}, 'truk': {}}
CORAL_SPEC = {'wildcat7': True, 'cw_ignora_J': CW_CORAL, 'sbarco': {'J': {'hex': [[2, 22]], 'nome': 'Port Moresby'}}}
CORAL_VIT = {'tipo': 'coral', 'auto': 100, 'min': 50}
CORAL_OBJ = {'A': {'difendi': 'port_moresby', 'caccia_portaerei': True}, 'J': {'sbarco': 'port_moresby', 'caccia_portaerei': True}}
SCENARI.append({
    'id': 'coral_battaglia', 'nome': 'Mar dei Coralli - La battaglia', 'data': '8 maggio 1942', 'giorno': 4, 'ora': 1, 'turni': 18,
    'meteo': 'fronte', 'profilo': 'cs',
    'descrizione': "Versione breve: l'8 maggio le portaerei si cercano a sud delle Salomone. Il Giappone deve scortare i trasporti verso Port Moresby.",
    'A': {'tf': [TF(['Lexington', 'Minneapolis', 'New Orleans', 'Astoria', 'Chester', 'Portland'] + n(7, 'DD'), mare(34, 33), {'Lexington': CORAL_A_AEREI['Lexington']}, zona=Z(settori=[6], sud=15)),
                 TF(['Yorktown', 'Australia', 'Chicago', 'Hobart'] + n(7, 'DD') + n(2, 'AO'), mare(31, 35), {'Yorktown': CORAL_A_AEREI['Yorktown']}, zona=Z(settori=[6], sud=15))],
          'basi': CORAL_BASI_A, 'radar': ['Lexington', 'Yorktown', 'port_moresby', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(['Shokaku Coral Sea', 'Zuikaku Coral Sea', 'Myoko', 'Haguro'] + n(6, 'DD'), mare(45, 23), {k: CORAL_J_AEREI[k] for k in ('Shokaku Coral Sea', 'Zuikaku Coral Sea')}, zona=Z(vicino=[NEW_GEORGIA, 7])),
                 TF(['Shoho', 'Aoba', 'Kako', 'Kinugasa', 'Furutaka'] + n(4, 'DD') + n(1, 'AO'), mare(41, 22), {'Shoho': CORAL_J_AEREI['Shoho']}, zona=Z(o=[Z(vicino=[NEW_GEORGIA, 7]), Z(vicino=[[[24, 26]], 0])])),
                 TF(['Kamikawa'] + n(2, 'PG'), [24, 26], {'Kamikawa': CORAL_J_AEREI['Kamikawa']}, ancorata=True),
                 TF(['Yubari', 'Tenryu', 'Tatsuta'] + n(5, 'DD') + n(12, 'AP')[:10], mare(28, 21), zona=Z(o=[Z(vicino=[NEW_GEORGIA, 7]), Z(vicino=[[[24, 26]], 0])])),
                 TF(n(2, 'AP') + n(2, 'PG') + n(3, 'AO'), mare(24, 22), zona=Z(o=[Z(vicino=[NEW_GEORGIA, 7]), Z(vicino=[[[24, 26]], 0])]))],
          'basi': CORAL_BASI_J, 'radar': []},
    'speciali': dict(CORAL_SPEC, seaplane_kamikawa=True), 'vittoria': CORAL_VIT, 'obiettivi': CORAL_OBJ,
})
SCENARI.append({
    'id': 'coral_giorni', 'nome': 'Mar dei Coralli - I giorni cruciali', 'data': '7-8 maggio 1942', 'giorno': 3, 'ora': 1, 'turni': 42,
    'meteo': 'fronte', 'profilo': 'cs',
    'descrizione': "Dal 7 maggio all'8 maggio: lo Shoho scorta l'invasione di Port Moresby, le portaerei di Takagi arrivano da est.",
    'A': {'tf': [TF(['Lexington', 'Minneapolis', 'New Orleans', 'Astoria', 'Chester', 'Portland'] + n(7, 'DD'), mare(30, 38), {'Lexington': CORAL_A_AEREI['Lexington']}, zona=Z(settori=[6, 7], sud=12)),
                 TF(['Yorktown', 'Australia', 'Chicago', 'Hobart'] + n(7, 'DD') + n(2, 'AO'), mare(36, 39), {'Yorktown': CORAL_A_AEREI['Yorktown']}, zona=Z(settori=[6, 7], sud=12))],
          'basi': CORAL_BASI_A, 'radar': ['Lexington', 'Yorktown', 'port_moresby', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(['Shokaku Coral Sea', 'Zuikaku Coral Sea', 'Myoko', 'Haguro'] + n(6, 'DD') + n(1, 'AO'), mare(49, 19), {k: CORAL_J_AEREI[k] for k in ('Shokaku Coral Sea', 'Zuikaku Coral Sea')}, zona=Z(vicino=[GUADALCANAL, 6])),
                 TF(['Shoho', 'Aoba', 'Kako', 'Kinugasa', 'Furutaka'] + n(4, 'DD') + n(1, 'AO'), mare(27, 23), {'Shoho': CORAL_J_AEREI['Shoho']}, zona=Z(vicino=[DEBOYNE, 10])),
                 TF(['Kamikawa', 'Yubari', 'Tenryu', 'Tatsuta'] + n(5, 'DD') + n(12, 'AP')[:10] + n(4, 'PG'), mare(26, 21), {'Kamikawa': CORAL_J_AEREI['Kamikawa']}, zona=Z(vicino=[WOODLARK, 6])),
                 TF(n(2, 'AP') + n(2, 'AO'), mare(24, 21), zona=Z(o=[Z(vicino=[GUADALCANAL, 6]), Z(vicino=[DEBOYNE, 10]), Z(vicino=[WOODLARK, 6])]))],
          'basi': CORAL_BASI_J, 'radar': []},
    'speciali': CORAL_SPEC, 'vittoria': CORAL_VIT, 'obiettivi': CORAL_OBJ,
})
SCENARI.append({
    'id': 'coral_campagna', 'nome': 'Mar dei Coralli - La campagna', 'data': '4-8 maggio 1942', 'giorno': 0, 'ora': 6, 'turni': 109,
    'meteo': 'fronte', 'profilo': 'cs',
    'descrizione': "Lo scenario completo: cinque giorni dal 4 maggio. Le navi a Rabaul sono all'ancora fino al 5 maggio alle 18, il convoglio di Tulagi finché non avvista una nave alleata.",
    'A': {'tf': [TF(['Lexington', 'Minneapolis', 'New Orleans', 'Astoria', 'Portland'] + n(7, 'DD') + n(2, 'AO'), mare(30, 41), {'Lexington': CORAL_A_AEREI['Lexington']}, zona=Z(settori=[7], sud=5)),
                 TF(['Yorktown', 'Chester', 'Australia', 'Chicago', 'Hobart'] + n(7, 'DD'), mare(50, 30), {'Yorktown': CORAL_A_AEREI['Yorktown']}, zona=Z(settori=[7], sud=16))],
          'basi': CORAL_BASI_A, 'radar': ['Lexington', 'Yorktown', 'port_moresby', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(n(12, 'AP') + n(4, 'PG') + n(2, 'AO'), [53, 21], ancorata=True),
                 TF(['Shoho', 'Aoba', 'Kako', 'Kinugasa', 'Furutaka'] + n(4, 'DD') + n(1, 'AO'), mare(34, 12), {'Shoho': CORAL_J_AEREI['Shoho']}, zona=Z(vicino=[BOUGAINVILLE, 5])),
                 TF(['Shokaku Coral Sea', 'Zuikaku Coral Sea', 'Myoko', 'Haguro'] + n(6, 'DD') + n(1, 'AO'), mare(26, 6), {k: CORAL_J_AEREI[k] for k in ('Shokaku Coral Sea', 'Zuikaku Coral Sea')}, zona=Z(vicino=[[[23, 3]], 8])),
                 TF(['Yubari', 'Tenryu', 'Tatsuta'] + n(5, 'DD'), mare(30, 10), zona=Z(o=[Z(vicino=[[[53, 21]], 0]), Z(vicino=[BOUGAINVILLE, 5]), Z(vicino=[[[23, 3]], 8])])),
                 TF(['Kamikawa'], [24, 26], {'Kamikawa': CORAL_J_AEREI['Kamikawa']}, ancorata=True)],
          'basi': CORAL_BASI_J, 'radar': []},
    'speciali': dict(CORAL_SPEC, seaplane_kamikawa=True, ancora_fino={'hex': [23, 3], 'turno': 36}, ancora_avvistamento={'hex': [53, 21]}),
    'vittoria': CORAL_VIT, 'obiettivi': CORAL_OBJ,
})
ES_A_AEREI = {'Saratoga': {'Wildcat': 12, 'Dauntless': 13, 'Avenger': 5}, 'Enterprise Solomons': {'Wildcat': 12, 'Dauntless': 12, 'Avenger': 5}, 'Wasp': {'Wildcat': 10, 'Dauntless': 11, 'Avenger': 5}}
ES_J_AEREI = {'Shokaku': {'Zero': 9, 'Val': 9, 'Kate': 9, 'Judy': 1}, 'Zuikaku': {'Zero': 9, 'Val': 8, 'Kate': 8}, 'Ryujo': {'Zero': 7}, 'Chitose': {'Pete': 4, 'Jake': 3}, 'Tone': {'Pete': 1, 'Jake': 1}, 'Chikuma': {'Pete': 1}, 'Hiei': {'Pete': 1}, 'Kirishima': {'Pete': 1}}
ES_BASI_A = {'henderson': {'Wildcat': 4, 'Dauntless': 3, 'P-39': 2}, 'espiritu_santo': {'Catalina': 3, 'B-17': 3, 'Hudson': 2}, 'ndeni': {'Catalina': 2},
             'nuova_caledonia': {}, 'gili_gili': {'P-40': 6, 'P-39': 4}, 'port_moresby': {'P-40': 10, 'P-39': 2, 'B-26': 20, 'B-25': 10, 'Hudson': 1, 'A-20': 3, 'Beaufort': 3, 'Beaufighter': 2},
             'australia': {'B-17': 8, 'Catalina': 1}}
ES_BASI_J = {'rabaul': {'Zero': 14, 'Betty': 8, 'Nell': 3, 'Mavis': 2, 'Emily': 1}, 'buka': {'Zero': 6}, 'buna': {'Val': 2}, 'shortland': {'Rufe': 2}, 'gasmata': {}, 'lae': {}, 'kavieng': {}, 'truk': {}}
ES_SPEC = {'sbarco': {'J': {'hex': [[15, 25]], 'isola': 'guadalcanal', 'nome': 'Gili-Gili o Guadalcanal'}}, 'wasp_notte': True}
ES_VIT = {'tipo': 'standard', 'auto': 200, 'min': 50, 'bonus_sbarco_J': 50}
ES_OBJ = {'A': {'difendi': 'henderson', 'caccia_portaerei': True}, 'J': {'sbarco': 'guadalcanal', 'caccia_portaerei': True}}
def ES_J_FLOTTA(camp):
    resto = Z(o=[Z(settori=[3], nord=3), Z(vicino=[[[23, 3]], 0])]) if camp else Z(settori=[2, 3], lontano=[[[52, 22], [15, 25]], 7])
    return [TF(['Shokaku', 'Zuikaku'] + n(6, 'DD'), mare(46, 3), {k: ES_J_AEREI[k] for k in ('Shokaku', 'Zuikaku')}, zona=resto),
               TF(['Ryujo', 'Tone'] + n(2, 'DD'), mare(42, 6), {'Ryujo': ES_J_AEREI['Ryujo'], 'Tone': ES_J_AEREI['Tone']}, zona=resto),
               TF(['Hiei', 'Kirishima', 'Chikuma', 'Kumano', 'Suzuya', 'Nagara'] + n(6, 'DD'), mare(49, 5), {k: ES_J_AEREI[k] for k in ('Chikuma', 'Hiei', 'Kirishima')}, zona=resto),
               TF(['Mutsu', 'Atago', 'Maya', 'Takao', 'Myoko', 'Haguro', 'Yura', 'Chitose'] + n(7, 'DD'), mare(53, 3), {'Chitose': ES_J_AEREI['Chitose']}, zona=resto),
               TF(['Jintsu'] + n(4, 'APD') + n(1, 'AP') + n(4, 'DD'), mare(49, 11), zona=Z(vicino=[ONTONG_JAVA, 4])),
               TF(['Aoba', 'Kinugasa', 'Furutaka'] + n(2, 'DD'), mare(36, 9), zona=resto),
               TF(['Tenryu', 'Tatsuta'] + n(2, 'AP') + n(1, 'PG') + n(2, 'DD'), [23, 3], ancorata=True),
               TF(n(2, 'AP') + n(2, 'DD'), mare(14, 21), zona=Z(vicino=[GOODENOUGH, 2]) if camp else resto)]
SCENARI.append({
    'id': 'salomone_battaglia', 'nome': 'Salomone orientali - La battaglia', 'data': '24 agosto 1942', 'giorno': 0, 'ora': 1, 'turni': 18,
    'meteo': 'sparse', 'profilo': 'es',
    'descrizione': "Versione breve: il 24 agosto la Kido Butai scende verso Guadalcanal per coprire un convoglio. Le tre portaerei americane la aspettano a est.",
    'A': {'tf': [TF(['Saratoga', 'Minneapolis', 'New Orleans'] + n(6, 'DD'), mare(64, 16), {'Saratoga': ES_A_AEREI['Saratoga']}, zona=Z(settori=[4])),
                 TF(['Enterprise Solomons', 'North Carolina', 'Portland', 'Atlanta'] + n(6, 'DD'), mare(62, 19), {'Enterprise Solomons': ES_A_AEREI['Enterprise Solomons']}, zona=Z(settori=[4])),
                 TF(['Wasp', 'San Juan', 'San Francisco', 'Salt Lake City'] + n(8, 'DD') + n(3, 'AO'), mare(70, 21), {'Wasp': ES_A_AEREI['Wasp']}, zona=Z(settori=[4]))],
          'basi': ES_BASI_A, 'radar': ['*navi_maggiori', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'ndeni', 'nuova_caledonia', 'australia']},
    'J': {'tf': ES_J_FLOTTA(False), 'basi': ES_BASI_J, 'radar': ['rabaul', 'lae']},
    'speciali': ES_SPEC, 'vittoria': ES_VIT, 'obiettivi': ES_OBJ,
})
SCENARI.append({
    'id': 'salomone_campagna', 'nome': 'Salomone orientali - La campagna', 'data': '24-26 agosto 1942', 'giorno': 0, 'ora': 1, 'turni': 66,
    'meteo': 'sparse', 'profilo': 'es',
    'descrizione': "Tre giorni di campagna: il Wasp parte da sud-est, la flotta giapponese scende dal nord e i convogli puntano su Guadalcanal e Gili-Gili.",
    'A': {'tf': [TF(['Saratoga', 'Minneapolis', 'New Orleans'] + n(6, 'DD'), mare(63, 12), {'Saratoga': ES_A_AEREI['Saratoga']}, zona=Z(settori=[4])),
                 TF(['Enterprise Solomons', 'North Carolina', 'Portland', 'Atlanta'] + n(5, 'DD'), mare(61, 15), {'Enterprise Solomons': ES_A_AEREI['Enterprise Solomons']}, zona=Z(settori=[4])),
                 TF(['Wasp', 'San Juan', 'San Francisco', 'Salt Lake City'] + n(8, 'DD') + n(3, 'AO'), mare(74, 32), {'Wasp': ES_A_AEREI['Wasp']}, zona=Z(settori=[8], est=10)),
                 TF(n(1, 'DD'), [15, 25], ancorata=True)],
          'basi': ES_BASI_A, 'radar': ['*navi_maggiori', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'ndeni', 'nuova_caledonia', 'australia']},
    'J': {'tf': ES_J_FLOTTA(True), 'basi': ES_BASI_J, 'radar': ['rabaul', 'lae']},
    'speciali': ES_SPEC, 'vittoria': ES_VIT, 'obiettivi': ES_OBJ,
})
SC_A_AEREI = {'Enterprise': {'Wildcat': 12, 'Dauntless': 12, 'Avenger': 5}, 'Hornet': {'Wildcat': 11, 'Dauntless': 12, 'Avenger': 4}}
SC_J_AEREI = {'Shokaku': {'Zero': 9, 'Val': 2, 'Kate': 9, 'Judy': 1}, 'Zuikaku': {'Zero': 9, 'Val': 9, 'Kate': 8}, 'Junyo': {'Zero': 8, 'Val': 10},
              'Zuiho': {'Zero': 5}, 'Tone': {'Pete': 1, 'Jake': 1}, 'Chikuma': {'Pete': 1, 'Jake': 1}, 'Kongo': {'Pete': 1}, 'Haruna': {'Pete': 1}}
SC_BASI_A = {'henderson': {'Wildcat': 8, 'P-39': 3, 'Dauntless': 6}, 'espiritu_santo': {'Hudson': 3, 'Catalina': 7, 'B-17': 10}, 'nuova_caledonia': {'Catalina': 2},
             'gili_gili': {'P-40': 8, 'P-39': 4}, 'port_moresby': {'P-40': 16, 'B-26': 24, 'B-25': 16, 'Hudson': 2, 'A-20': 4, 'Beaufort': 4, 'Beaufighter': 4},
             'australia': {'B-17': 9, 'Catalina': 2}}
SC_BASI_J = {'rabaul': {'Zero': 15, 'Betty': 11, 'Nell': 9, 'Mavis': 2, 'Emily': 1}, 'buin': {'Zero': 9, 'Val': 15}, 'buka': {'Zero': 6, 'Kate': 2},
             'shortland': {'Rufe': 2, 'Mavis': 2}, 'buna': {'Kate': 4}, 'gasmata': {}, 'lae': {}, 'kavieng': {}, 'truk': {}}
SC_SPEC = {'henderson_ripara2': True}
SC_VIT = {'tipo': 'standard', 'auto': 250, 'min': 200}
SC_OBJ = {'A': {'difendi': 'henderson', 'caccia_portaerei': True}, 'J': {'attacca_base': 'henderson', 'caccia_portaerei': True}}
ZS = Z(vicino=[STEWART, 5])
SC_J_FLOTTA = [TF(['Shokaku', 'Zuikaku', 'Zuiho', 'Kumano'] + n(8, 'DD'), mare(61, 12), {k: SC_J_AEREI[k] for k in ('Shokaku', 'Zuikaku', 'Zuiho')}, zona=ZS),
               TF(['Junyo', 'Isuzu'] + n(6, 'DD'), mare(57, 14), {'Junyo': SC_J_AEREI['Junyo']}, zona=ZS),
               TF(['Kongo', 'Haruna', 'Atago', 'Takao', 'Myoko', 'Maya', 'Tone'] + n(8, 'DD'), mare(62, 15), {k: SC_J_AEREI[k] for k in ('Tone', 'Kongo', 'Haruna')}, zona=ZS),
               TF(['Hiei', 'Kirishima', 'Chikuma', 'Suzuya', 'Chokai', 'Nagara'] + n(6, 'DD'), mare(64, 13), {'Chikuma': SC_J_AEREI['Chikuma']}, zona=ZS),
               TF(['Yura'] + n(2, 'DD'), mare(51, 19), zona=ZS),
               TF(n(8, 'DD'), [37, 13])]
SCENARI.append({
    'id': 'santacruz_battaglia', 'nome': 'Santa Cruz - La battaglia', 'data': '26 ottobre 1942', 'giorno': 1, 'ora': 1, 'turni': 18,
    'meteo': 'sparse', 'profilo': 'sc',
    'descrizione': "Versione breve: il 26 ottobre Hornet ed Enterprise affrontano quattro portaerei giapponesi a nord delle isole Santa Cruz.",
    'A': {'tf': [TF(['Hornet', 'Enterprise', 'South Dakota', 'Portland', 'Northampton', 'Pensacola', 'San Juan', 'San Diego', 'Juneau'] + n(14, 'DD'), mare(70, 24), SC_A_AEREI, zona=Z(vicino=[NDENI, 5])),
                 TF(['Washington', 'San Francisco', 'Helena', 'Atlanta'] + n(6, 'DD'), mare(51, 26), zona=Z(settori=[7], vicino=[GUADALCANAL, 3])),
                 TF(n(2, 'DD') + n(1, 'PG'), mare(51, 21), zona=Z(vicino=[[[52, 22]], 3]))],
          'basi': SC_BASI_A, 'radar': ['*tutte', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'ndeni', 'nuova_caledonia', 'australia']},
    'J': {'tf': SC_J_FLOTTA, 'basi': SC_BASI_J, 'radar': ['rabaul', 'lae', 'shortland', 'gasmata', 'buna']},
    'speciali': SC_SPEC, 'vittoria': SC_VIT, 'obiettivi': SC_OBJ,
})
SCENARI.append({
    'id': 'santacruz_campagna', 'nome': 'Santa Cruz - La campagna', 'data': '25-27 ottobre 1942', 'giorno': 0, 'ora': 1, 'turni': 66,
    'meteo': 'sparse', 'profilo': 'sc',
    'descrizione': "Tre giorni attorno alle Santa Cruz: la flotta giapponese a nord attende la caduta di Henderson, le portaerei americane arrivano da Ndeni.",
    'A': {'tf': [TF(['Hornet', 'Enterprise', 'South Dakota', 'Portland', 'Northampton', 'Pensacola', 'San Juan', 'San Diego', 'Juneau'] + n(14, 'DD'), mare(72, 30), SC_A_AEREI, zona=Z(vicino=[NDENI, 8])),
                 TF(['Washington', 'San Francisco', 'Helena', 'Atlanta'] + n(6, 'DD'), mare(55, 27), zona=Z(settori=[7], vicino=[GUADALCANAL, 6])),
                 TF(n(2, 'DD') + n(2, 'PG'), mare(52, 21), zona=Z(vicino=[[[52, 22]], 1]))],
          'basi': SC_BASI_A, 'radar': ['*tutte', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'ndeni', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(['Shokaku', 'Zuikaku', 'Zuiho', 'Kumano'] + n(8, 'DD'), mare(60, 3), {k: SC_J_AEREI[k] for k in ('Shokaku', 'Zuikaku', 'Zuiho')}, zona=Z(settori=[3], nord=8)),
                 TF(['Junyo', 'Isuzu'] + n(6, 'DD'), mare(54, 3), {'Junyo': SC_J_AEREI['Junyo']}, zona=Z(settori=[3], nord=8)),
                 TF(['Kongo', 'Haruna', 'Atago', 'Takao', 'Myoko', 'Maya', 'Tone'] + n(8, 'DD'), mare(57, 4), {k: SC_J_AEREI[k] for k in ('Tone', 'Kongo', 'Haruna')}, zona=Z(settori=[3], nord=8)),
                 TF(['Hiei', 'Kirishima', 'Chikuma', 'Suzuya', 'Chokai', 'Nagara'] + n(14, 'DD'), mare(64, 4), {'Chikuma': SC_J_AEREI['Chikuma']}, zona=Z(settori=[3], nord=8)),
                 TF(['Yura'] + n(2, 'DD'), mare(50, 20), zona=Z(settori=[3], vicino=[GUADALCANAL, 4]))],
          'basi': SC_BASI_J, 'radar': ['rabaul', 'lae', 'shortland', 'gasmata', 'buna']},
    'speciali': SC_SPEC, 'vittoria': SC_VIT, 'obiettivi': SC_OBJ,
})
SCENARI.append({
    'id': 'guadalcanal', 'nome': 'Guadalcanal', 'data': '12-15 novembre 1942', 'giorno': 0, 'ora': 6, 'turni': 79,
    'meteo': 'sparse', 'profilo': 'sc',
    'descrizione': "La battaglia navale di Guadalcanal: convogli di rinforzi da entrambe le parti, corazzate nella notte e l'Enterprise che arriva da sud il 13.",
    'A': {'tf': [TF(['Portland', 'San Francisco', 'Pensacola', 'Atlanta', 'Juneau', 'Helena'] + n(8, 'DD') + n(7, 'AP') + n(1, 'PG'), [52, 22]),
                 TF(['Enterprise', 'Washington', 'South Dakota', 'Northampton', 'San Diego'] + n(15, 'DD'), mare(70, 43), {'Enterprise': {'Wildcat': 13, 'Dauntless': 10, 'Avenger': 3}}, entra=19, zona=Z(settori=[8], sud=1))],
          'basi': {'henderson': {'Wildcat': 9, 'Dauntless': 12, 'Avenger': 3, 'P-39': 1}, 'espiritu_santo': {'B-17': 12, 'Hudson': 2, 'Catalina': 6}, 'nuova_caledonia': {'Catalina': 2},
                   'gili_gili': {'P-40': 8}, 'port_moresby': {'P-40': 16, 'B-26': 20, 'B-25': 20, 'Hudson': 2, 'A-20': 4, 'Beaufort': 4, 'Beaufighter': 4, 'P-38': 5}, 'australia': {'B-17': 9, 'Catalina': 2}},
          'radar': ['*tutte', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(['Chokai', 'Kinugasa', 'Isuzu', 'Suzuya', 'Maya', 'Tenryu'] + n(17, 'DD') + n(11, 'AP'), [37, 13]),
                 TF(['Junyo', 'Hiyo'] + n(6, 'DD'), mare(50, 4), {'Junyo': {'Zero': 7, 'Val': 6, 'Kate': 3}, 'Hiyo': {'Zero': 7, 'Val': 6, 'Kate': 3}}, zona=Z(vicino=[ONTONG_JAVA, 4])),
                 TF(['Hiei', 'Kirishima', 'Nagara', 'Tone'] + n(8, 'DD'), mare(48, 10), {'Tone': {'Pete': 1, 'Jake': 1}, 'Kirishima': {'Pete': 1}}, zona=Z(vicino=[ONTONG_JAVA, 4])),
                 TF(['Kongo', 'Haruna', 'Atago', 'Takao', 'Sendai'] + n(6, 'DD'), mare(52, 6), {'Kongo': {'Pete': 1}, 'Haruna': {'Jake': 1}}, zona=Z(vicino=[ONTONG_JAVA, 4]))],
          'basi': {'rabaul': {'Zero': 15, 'Betty': 20, 'Nell': 2, 'Mavis': 2, 'Emily': 2}, 'buin': {'Zero': 15, 'Val': 9}, 'buka': {'Kate': 3},
                   'shortland': {'Rufe': 2, 'Mavis': 2}, 'buna': {}, 'gasmata': {}, 'lae': {}, 'kavieng': {}, 'truk': {}},
          'radar': ['shortland', 'rabaul', 'lae', 'gasmata']},
    'speciali': {'henderson_ripara2': True, 'he_hiei_kirishima': True, 'enterprise_rf6': True, 'idro_j_meno1': True,
                 'sbarco': {'A': {'hex': [[52, 22]], 'nome': 'Henderson'}, 'J': {'isola': 'guadalcanal', 'escludi': [[52, 22]], 'nome': 'Guadalcanal (non Henderson)'}}},
    'vittoria': {'tipo': 'guadalcanal', 'auto': 100, 'min': 50, 'bonus_sbarco_max': 50, 'sbarco_vince_J': 100},
    'obiettivi': {'A': {'sbarco': 'henderson', 'difendi': 'henderson', 'caccia_portaerei': True}, 'J': {'sbarco': 'guadalcanal', 'attacca_base': 'henderson', 'caccia_portaerei': True}},
})

# 6. Midway (scenario del modulo VASSAL): mappa propria
MID_ZA = Z(colonne=[0, 10], nord=11)
MID_ZB = Z(colonne=[0, 10], sud=11)
SCENARI.append({
    'id': 'midway', 'nome': 'Midway', 'data': '4-6 giugno 1942', 'giorno': 0, 'ora': 1, 'turni': 72, 'mappa': 'midway',
    'meteo': 'sparse', 'profilo': '*', 'mese': 'giugno', 'anno': 1942, 'giorno_mese': 4,
    'descrizione': "Tre giorni sulla mappa di Midway: quattro portaerei giapponesi e la forza d'invasione contro le tre portaerei americane e l'atollo. Il Giappone deve sbarcare almeno 200 punti a Midway.",
    'A': {'tf': [TF(['Enterprise Solomons', 'Hornet', 'Minneapolis', 'New Orleans', 'Northampton', 'Pensacola', 'Vincennes', 'Atlanta'] + n(11, 'DD'), [36, 12],
                    {'Enterprise Solomons': {'Wildcat': 9, 'Dauntless': 13, 'Devastator': 5}, 'Hornet': {'Wildcat': 9, 'Dauntless': 12, 'Devastator': 5}}, zona=Z(colonne=[20, 50])),
                 TF(['Yorktown', 'Astoria', 'Portland'] + n(6, 'DD'), [38, 13], {'Yorktown': {'Wildcat': 8, 'Dauntless': 12, 'Devastator': 4}}, zona=Z(colonne=[20, 50]))],
          'basi': {'midway': {'Avenger': 2, 'B-17': 3, 'B-26': 1, 'Buffalo': 7, 'Catalina': 8, 'Dauntless': 6, 'Vindicator': 5, 'Wildcat': 2},
                   'hawaii_m': {'B-17': 6, 'B-24': 2}, 'johnston': {'Catalina': 2}},
          'radar': ['Enterprise Solomons', 'Hornet', 'Yorktown', 'midway']},
    'J': {'tf': [TF(['Akagi', 'Kaga', 'Hiryu', 'Soryu', 'Chikuma', 'Tone', 'Haruna', 'Kirishima', 'Nagara'] + n(12, 'DD'), [6, 5],
                    {'Akagi': {'Zero': 7, 'Val': 8, 'Kate': 6}, 'Kaga': {'Zero': 7, 'Val': 8, 'Kate': 7}, 'Hiryu': {'Zero': 6, 'Val': 7, 'Kate': 5},
                     'Soryu': {'Zero': 5, 'Val': 7, 'Kate': 5, 'Judy': 1}, 'Tone': {'Pete': 1, 'Jake': 1}, 'Chikuma': {'Pete': 1, 'Jake': 1}, 'Haruna': {'Pete': 1}}, zona=MID_ZA),
                 TF(['Jintsu'] + n(10, 'DD') + n(15, 'AP') + n(3, 'PG'), [6, 28], zona=MID_ZB),
                 TF(['Zuiho', 'Hiei', 'Kongo', 'Atago', 'Chokai', 'Haguro', 'Myoko', 'Yura'] + n(8, 'DD'), [0, 18], {'Zuiho': {'Kate': 4, 'Zero': 4}}, entra=2, zona=Z(colonne=[0, 0], vicino=[[[0, 19]], 5])),
                 TF(['Chitose', 'Kamikawa', 'Kumano', 'Mikuma', 'Mogami', 'Suzuya'] + n(3, 'DD'), [0, 31], {'Chitose': {'Pete': 6, 'Dave': 2}, 'Kamikawa': {'Pete': 4, 'Dave': 1}}, entra=3, zona=Z(colonne=[0, 0], sud=6)),
                 TF(['Hosho', 'Mutsu', 'Nagato', 'Yamato', 'Chiyoda', 'Nisshin', 'Sendai'] + n(9, 'DD'), [0, 2], {'Hosho': {'Kate': 3}}, entra=11, zona=Z(colonne=[0, 0], nord=5))],
          'basi': {'marshall': {'Mavis': 5}}, 'radar': []},
    'speciali': {'wildcat7': True, 'hosho_solo_kate': True, 'sbarco': {'J': {'hex': [[29, 15]], 'nome': 'Midway'}}, 'conquista': {'base': 'midway', 'lato': 'J', 'punti': 250}},
    'vittoria': {'tipo': 'soglia_sbarco', 'auto': 300, 'lato': 'J', 'soglia': 200, 'luogo': 'Midway'},
    'obiettivi': {'A': {'difendi': 'midway', 'caccia_portaerei': True}, 'J': {'sbarco': 'midway', 'attacca_base': 'midway', 'caccia_portaerei': True}},
})
# 7. Wake (scenario del modulo VASSAL): mappa propria, rinforzi da est e da nord
SCENARI.append({
    'id': 'wake', 'nome': 'Wake', 'data': '21-23 dicembre 1941', 'giorno': 0, 'ora': 1, 'turni': 76, 'mappa': 'wake',
    'meteo': 'sparse', 'profilo': '*', 'mese': 'dicembre', 'anno': 1941, 'giorno_mese': 21,
    'descrizione': "Il soccorso a Wake che non arrivò: tre portaerei americane da est contro Hiryu e Soryu e la seconda forza d'invasione. Conta chi sbarca di più sull'atollo.",
    'A': {'tf': [TF(['Saratoga', 'Astoria', 'Minneapolis', 'San Francisco'] + n(8, 'DD') + n(1, 'APD') + n(1, 'AO'), [50, 14],
                    {'Saratoga': {'Buffalo': 6, 'Wildcat': 4, 'Dauntless': 4, 'Devastator': 4}}, zona=Z(colonne=[50, 50], vicino=[[[50, 14]], 5])),
                 TF(['Lexington', 'Chicago', 'Indianapolis', 'Portland'] + n(8, 'DD') + n(1, 'AO'), [50, 29], {'Lexington': {'Wildcat': 4, 'Dauntless': 4}},
                    entra=4, entra_tra=[4, 11], zona=Z(colonne=[50, 50], sud=11)),
                 TF(['Enterprise', 'New Orleans', 'Northampton', 'Salt Lake City'] + n(9, 'DD'), [50, 14], {'Enterprise': {'Wildcat': 3, 'Dauntless': 4}},
                    entra=17, entra_tra=[17, 23], zona=Z(colonne=[50, 50], vicino=[[[50, 14]], 5]))],
          'basi': {'wake': {'Wildcat': 1}, 'hawaii_w': {'B-17': 2}, 'midway_w': {'Catalina': 2}},
          'radar': ['Saratoga', 'Lexington', 'Enterprise']},
    'J': {'tf': [TF(['Hiryu', 'Soryu', 'Chikuma', 'Tone'] + n(2, 'DD'), [4, 0], {'Hiryu': {'Zero': 6, 'Val': 6, 'Kate': 6}, 'Soryu': {'Zero': 6, 'Val': 6, 'Kate': 6},
                    'Tone': {'Jake': 1}, 'Chikuma': {'Jake': 1}}, entra=0, entra_tra=[0, 4], zona=Z(colonne=[0, 9], nord=1)),
                 TF(['Aoba', 'Furutaka', 'Kako', 'Kinugasa', 'Tatsuta', 'Tenryu', 'Yura'] + n(12, 'DD') + n(2, 'APD') + n(3, 'AP'), [6, 34], entra=26, entra_tra=[26, 32], zona=Z(colonne=[0, 13], sud=1))],
          'basi': {'kwajalein': {'Nell': 17, 'Mavis': 5}}, 'radar': []},
    'speciali': {'wildcat7': True, 'buffalo_solo_terra': True, 'sbarco': {'J': {'hex': [[13, 19]], 'nome': 'Wake'}, 'A': {'hex': [[13, 19]], 'nome': 'Wake'}},
                 'cv_a_ovest': {'navi': ['Hiryu', 'Soryu'], 'colonne': 10, 'punti': 50}},
    'vittoria': {'tipo': 'differenza_sbarco', 'auto': 200, 'lato': 'J', 'scarto': 50, 'luogo': 'Wake'},
    'obiettivi': {'A': {'sbarco': 'wake', 'difendi': 'wake', 'caccia_portaerei': True}, 'J': {'sbarco': 'wake', 'attacca_base': 'wake', 'caccia_portaerei': True}},
})
# isole per lo sbarco: esagoni parziali di Guadalcanal (escluso Henderson nelle regole)
GUAD = []
for c in range(46, 58):
    for r in range(22, 26):
        if ter(c, r) == 'p' and (c, r) != (53, 21): GUAD.append([c, r])
ISOLE = {'guadalcanal': GUAD}
json.dump({'scenari': SCENARI, 'isole': ISOLE}, open(os.path.join(D, 'scenari.json'), 'w'), indent=1, ensure_ascii=False)
print('scenari', len(SCENARI), 'guadalcanal', GUAD)
for s in SCENARI:
    if s.get('mappa'): continue
    for side in 'AJ':
        for t in s[side]['tf']:
            if ter(*t['hex']) not in '.p': print('ATTENZIONE', s['id'], t['hex'], ter(*t['hex']))
