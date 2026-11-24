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
def B(nome, lato, hex_, sigla, mc, lf, rf, ph, aaf=0, sf=0, fuori=False):
    return {'nome': nome, 'lato': lato, 'hex': list(hex_), 'sigla': sigla, 'mc': mc, 'lf': list(lf), 'rf': rf, 'ph': ph, 'aaf': aaf, 'sf': sf, 'fuori': fuori}
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
    'Chitose': [8, 2, 1, 2, 'FP'], 'Kamikawa': [7, 1, 1, 1, 'FP'],
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

def TF(navi, dove, aerei=None, ancorata=False, entra=None):
    t = {'navi': navi, 'hex': dove}
    if aerei: t['aerei'] = aerei   # {nome_nave: {tipo: n}}
    if ancorata: t['ancorata'] = True
    if entra: t['entra'] = entra  # turno di entrata (indice)
    return t
def n(k, tipo): return [tipo] * k

SCENARI = []
# 1. Anillos alrededor de Rabaul
SCENARI.append({
    'id': 'rabaul', 'nome': 'Anelli attorno a Rabaul', 'data': '23 febbraio 1942', 'giorno': 0, 'ora': 6, 'turni': 13,
    'mesi': ['23 feb'], 'meteo': 'sparse', 'profilo': 'cs', 'mezza_mappa': 'ovest',
    'descrizione': "Il Lexington tenta un'incursione contro Rabaul. Scenario introduttivo: poche navi e pochi aerei, 13 turni dall'alba al tramonto.",
    'A': {'tf': [TF(['Lexington', 'Minneapolis', 'San Francisco', 'Indianapolis', 'Pensacola'] + n(10, 'DD'), mare(38, 9),
                    {'Lexington': {'Wildcat': 8, 'Dauntless': 12, 'Devastator': 4}})],
          'basi': {'port_moresby': {'P-40': 12, 'Catalina': 4}}, 'radar': ['Lexington', 'port_moresby']},
    'J': {'tf': [], 'basi': {'rabaul': {'Zero': 10, 'Kate': 10, 'Mavis': 4, 'Jake': 1, 'Rufe': 1}, 'kavieng': {'Nell': 12},
                              'gasmata': {}, 'truk': {'Mavis': 4}}, 'radar': []},
    'speciali': {'wildcat7': True, 'tf_unica_A': True, 'no_decollo_J_turno1': True,
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
CORAL_SPEC = {'wildcat7': True, 'sbarco': {'J': {'hex': [[2, 22]], 'nome': 'Port Moresby'}}}
CORAL_VIT = {'tipo': 'coral', 'auto': 100, 'min': 50}
CORAL_OBJ = {'A': {'difendi': 'port_moresby', 'caccia_portaerei': True}, 'J': {'sbarco': 'port_moresby', 'caccia_portaerei': True}}
SCENARI.append({
    'id': 'coral_battaglia', 'nome': 'Mar dei Coralli - La battaglia', 'data': '8 maggio 1942', 'giorno': 4, 'ora': 1, 'turni': 18,
    'meteo': 'fronte', 'profilo': 'cs',
    'descrizione': "Versione breve: l'8 maggio le portaerei si cercano a sud delle Salomone. Il Giappone deve scortare i trasporti verso Port Moresby.",
    'A': {'tf': [TF(['Lexington', 'Minneapolis', 'New Orleans', 'Astoria', 'Chester', 'Portland'] + n(7, 'DD'), mare(34, 33), {'Lexington': CORAL_A_AEREI['Lexington']}),
                 TF(['Yorktown', 'Australia', 'Chicago', 'Hobart'] + n(7, 'DD') + n(2, 'AO'), mare(31, 35), {'Yorktown': CORAL_A_AEREI['Yorktown']})],
          'basi': CORAL_BASI_A, 'radar': ['Lexington', 'Yorktown', 'port_moresby', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(['Shokaku Coral Sea', 'Zuikaku Coral Sea', 'Myoko', 'Haguro'] + n(6, 'DD'), mare(45, 23), {k: CORAL_J_AEREI[k] for k in ('Shokaku Coral Sea', 'Zuikaku Coral Sea')}),
                 TF(['Shoho', 'Aoba', 'Kako', 'Kinugasa', 'Furutaka'] + n(4, 'DD') + n(1, 'AO'), mare(41, 22), {'Shoho': CORAL_J_AEREI['Shoho']}),
                 TF(['Kamikawa'] + n(2, 'PG'), [24, 26], {'Kamikawa': CORAL_J_AEREI['Kamikawa']}, ancorata=True),
                 TF(['Yubari', 'Tenryu', 'Tatsuta'] + n(5, 'DD') + n(12, 'AP')[:10], mare(28, 21)),
                 TF(n(2, 'AP') + n(2, 'PG') + n(3, 'AO'), mare(24, 22))],
          'basi': CORAL_BASI_J, 'radar': []},
    'speciali': dict(CORAL_SPEC, seaplane_kamikawa=True), 'vittoria': CORAL_VIT, 'obiettivi': CORAL_OBJ,
})
SCENARI.append({
    'id': 'coral_giorni', 'nome': 'Mar dei Coralli - I giorni cruciali', 'data': '7-8 maggio 1942', 'giorno': 3, 'ora': 1, 'turni': 42,
    'meteo': 'fronte', 'profilo': 'cs',
    'descrizione': "Dal 7 maggio all'8 maggio: lo Shoho scorta l'invasione di Port Moresby, le portaerei di Takagi arrivano da est.",
    'A': {'tf': [TF(['Lexington', 'Minneapolis', 'New Orleans', 'Astoria', 'Chester', 'Portland'] + n(7, 'DD'), mare(30, 38), {'Lexington': CORAL_A_AEREI['Lexington']}),
                 TF(['Yorktown', 'Australia', 'Chicago', 'Hobart'] + n(7, 'DD') + n(2, 'AO'), mare(36, 39), {'Yorktown': CORAL_A_AEREI['Yorktown']})],
          'basi': CORAL_BASI_A, 'radar': ['Lexington', 'Yorktown', 'port_moresby', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(['Shokaku Coral Sea', 'Zuikaku Coral Sea', 'Myoko', 'Haguro'] + n(6, 'DD') + n(1, 'AO'), mare(49, 19), {k: CORAL_J_AEREI[k] for k in ('Shokaku Coral Sea', 'Zuikaku Coral Sea')}),
                 TF(['Shoho', 'Aoba', 'Kako', 'Kinugasa', 'Furutaka'] + n(4, 'DD') + n(1, 'AO'), mare(27, 23), {'Shoho': CORAL_J_AEREI['Shoho']}),
                 TF(['Kamikawa', 'Yubari', 'Tenryu', 'Tatsuta'] + n(5, 'DD') + n(12, 'AP')[:10] + n(4, 'PG'), mare(26, 21), {'Kamikawa': CORAL_J_AEREI['Kamikawa']}),
                 TF(n(2, 'AP') + n(2, 'AO'), mare(24, 21))],
          'basi': CORAL_BASI_J, 'radar': []},
    'speciali': CORAL_SPEC, 'vittoria': CORAL_VIT, 'obiettivi': CORAL_OBJ,
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
ES_J_FLOTTA = [TF(['Shokaku', 'Zuikaku'] + n(6, 'DD'), mare(46, 3), {k: ES_J_AEREI[k] for k in ('Shokaku', 'Zuikaku')}),
               TF(['Ryujo', 'Tone'] + n(2, 'DD'), mare(42, 6), {'Ryujo': ES_J_AEREI['Ryujo'], 'Tone': ES_J_AEREI['Tone']}),
               TF(['Hiei', 'Kirishima', 'Chikuma', 'Kumano', 'Suzuya', 'Nagara'] + n(6, 'DD'), mare(49, 5), {k: ES_J_AEREI[k] for k in ('Chikuma', 'Hiei', 'Kirishima')}),
               TF(['Mutsu', 'Atago', 'Maya', 'Takao', 'Myoko', 'Haguro', 'Yura', 'Chitose'] + n(7, 'DD'), mare(53, 3), {'Chitose': ES_J_AEREI['Chitose']}),
               TF(['Jintsu'] + n(4, 'APD') + n(1, 'AP') + n(4, 'DD'), mare(49, 11)),
               TF(['Aoba', 'Kinugasa', 'Furutaka'] + n(2, 'DD'), mare(36, 9)),
               TF(['Tenryu', 'Tatsuta'] + n(2, 'AP') + n(1, 'PG') + n(2, 'DD'), [23, 3], ancorata=True),
               TF(n(2, 'AP') + n(2, 'DD'), mare(14, 21))]
SCENARI.append({
    'id': 'salomone_battaglia', 'nome': 'Salomone orientali - La battaglia', 'data': '24 agosto 1942', 'giorno': 0, 'ora': 1, 'turni': 18,
    'meteo': 'sparse', 'profilo': 'es',
    'descrizione': "Versione breve: il 24 agosto la Kido Butai scende verso Guadalcanal per coprire un convoglio. Le tre portaerei americane la aspettano a est.",
    'A': {'tf': [TF(['Saratoga', 'Minneapolis', 'New Orleans'] + n(6, 'DD'), mare(64, 16), {'Saratoga': ES_A_AEREI['Saratoga']}),
                 TF(['Enterprise Solomons', 'North Carolina', 'Portland', 'Atlanta'] + n(6, 'DD'), mare(62, 19), {'Enterprise Solomons': ES_A_AEREI['Enterprise Solomons']}),
                 TF(['Wasp', 'San Juan', 'San Francisco', 'Salt Lake City'] + n(8, 'DD') + n(3, 'AO'), mare(70, 21), {'Wasp': ES_A_AEREI['Wasp']})],
          'basi': ES_BASI_A, 'radar': ['*navi_maggiori', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'ndeni', 'nuova_caledonia', 'australia']},
    'J': {'tf': ES_J_FLOTTA, 'basi': ES_BASI_J, 'radar': ['rabaul', 'lae']},
    'speciali': ES_SPEC, 'vittoria': ES_VIT, 'obiettivi': ES_OBJ,
})
SCENARI.append({
    'id': 'salomone_campagna', 'nome': 'Salomone orientali - La campagna', 'data': '24-26 agosto 1942', 'giorno': 0, 'ora': 1, 'turni': 66,
    'meteo': 'sparse', 'profilo': 'es',
    'descrizione': "Tre giorni di campagna: il Wasp parte da sud-est, la flotta giapponese scende dal nord e i convogli puntano su Guadalcanal e Gili-Gili.",
    'A': {'tf': [TF(['Saratoga', 'Minneapolis', 'New Orleans'] + n(6, 'DD'), mare(63, 12), {'Saratoga': ES_A_AEREI['Saratoga']}),
                 TF(['Enterprise Solomons', 'North Carolina', 'Portland', 'Atlanta'] + n(5, 'DD'), mare(61, 15), {'Enterprise Solomons': ES_A_AEREI['Enterprise Solomons']}),
                 TF(['Wasp', 'San Juan', 'San Francisco', 'Salt Lake City'] + n(8, 'DD') + n(3, 'AO'), mare(74, 32), {'Wasp': ES_A_AEREI['Wasp']}),
                 TF(n(1, 'DD'), [15, 25], ancorata=True)],
          'basi': ES_BASI_A, 'radar': ['*navi_maggiori', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'ndeni', 'nuova_caledonia', 'australia']},
    'J': {'tf': ES_J_FLOTTA, 'basi': ES_BASI_J, 'radar': ['rabaul', 'lae']},
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
SC_J_FLOTTA = [TF(['Shokaku', 'Zuikaku', 'Zuiho', 'Kumano'] + n(8, 'DD'), mare(61, 12), {k: SC_J_AEREI[k] for k in ('Shokaku', 'Zuikaku', 'Zuiho')}),
               TF(['Junyo', 'Isuzu'] + n(6, 'DD'), mare(57, 14), {'Junyo': SC_J_AEREI['Junyo']}),
               TF(['Kongo', 'Haruna', 'Atago', 'Takao', 'Myoko', 'Maya', 'Tone'] + n(8, 'DD'), mare(62, 15), {k: SC_J_AEREI[k] for k in ('Tone', 'Kongo', 'Haruna')}),
               TF(['Hiei', 'Kirishima', 'Chikuma', 'Suzuya', 'Chokai', 'Nagara'] + n(6, 'DD'), mare(64, 13), {'Chikuma': SC_J_AEREI['Chikuma']}),
               TF(['Yura'] + n(2, 'DD'), mare(51, 19)),
               TF(n(8, 'DD'), [37, 13])]
SCENARI.append({
    'id': 'santacruz_battaglia', 'nome': 'Santa Cruz - La battaglia', 'data': '26 ottobre 1942', 'giorno': 1, 'ora': 1, 'turni': 18,
    'meteo': 'sparse', 'profilo': 'sc',
    'descrizione': "Versione breve: il 26 ottobre Hornet ed Enterprise affrontano quattro portaerei giapponesi a nord delle isole Santa Cruz.",
    'A': {'tf': [TF(['Hornet', 'Enterprise', 'South Dakota', 'Portland', 'Northampton', 'Pensacola', 'San Juan', 'San Diego', 'Juneau'] + n(14, 'DD'), mare(70, 24), SC_A_AEREI),
                 TF(['Washington', 'San Francisco', 'Helena', 'Atlanta'] + n(6, 'DD'), mare(51, 26)),
                 TF(n(2, 'DD') + n(1, 'PG'), mare(51, 21))],
          'basi': SC_BASI_A, 'radar': ['*tutte', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'ndeni', 'nuova_caledonia', 'australia']},
    'J': {'tf': SC_J_FLOTTA, 'basi': SC_BASI_J, 'radar': ['rabaul', 'lae', 'shortland', 'gasmata', 'buna']},
    'speciali': SC_SPEC, 'vittoria': SC_VIT, 'obiettivi': SC_OBJ,
})
SCENARI.append({
    'id': 'santacruz_campagna', 'nome': 'Santa Cruz - La campagna', 'data': '25-27 ottobre 1942', 'giorno': 0, 'ora': 1, 'turni': 66,
    'meteo': 'sparse', 'profilo': 'sc',
    'descrizione': "Tre giorni attorno alle Santa Cruz: la flotta giapponese a nord attende la caduta di Henderson, le portaerei americane arrivano da Ndeni.",
    'A': {'tf': [TF(['Hornet', 'Enterprise', 'South Dakota', 'Portland', 'Northampton', 'Pensacola', 'San Juan', 'San Diego', 'Juneau'] + n(14, 'DD'), mare(72, 30), SC_A_AEREI),
                 TF(['Washington', 'San Francisco', 'Helena', 'Atlanta'] + n(6, 'DD'), mare(55, 27)),
                 TF(n(2, 'DD') + n(2, 'PG'), mare(52, 21))],
          'basi': SC_BASI_A, 'radar': ['*tutte', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'ndeni', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(['Shokaku', 'Zuikaku', 'Zuiho', 'Kumano'] + n(8, 'DD'), mare(60, 3), {k: SC_J_AEREI[k] for k in ('Shokaku', 'Zuikaku', 'Zuiho')}),
                 TF(['Junyo', 'Isuzu'] + n(6, 'DD'), mare(54, 3), {'Junyo': SC_J_AEREI['Junyo']}),
                 TF(['Kongo', 'Haruna', 'Atago', 'Takao', 'Myoko', 'Maya', 'Tone'] + n(8, 'DD'), mare(57, 4), {k: SC_J_AEREI[k] for k in ('Tone', 'Kongo', 'Haruna')}),
                 TF(['Hiei', 'Kirishima', 'Chikuma', 'Suzuya', 'Chokai', 'Nagara'] + n(14, 'DD'), mare(64, 4), {'Chikuma': SC_J_AEREI['Chikuma']}),
                 TF(['Yura'] + n(2, 'DD'), mare(50, 20))],
          'basi': SC_BASI_J, 'radar': ['rabaul', 'lae', 'shortland', 'gasmata', 'buna']},
    'speciali': SC_SPEC, 'vittoria': SC_VIT, 'obiettivi': SC_OBJ,
})
SCENARI.append({
    'id': 'guadalcanal', 'nome': 'Guadalcanal', 'data': '12-15 novembre 1942', 'giorno': 0, 'ora': 6, 'turni': 79,
    'meteo': 'sparse', 'profilo': 'sc',
    'descrizione': "La battaglia navale di Guadalcanal: convogli di rinforzi da entrambe le parti, corazzate nella notte e l'Enterprise che arriva da sud il 13.",
    'A': {'tf': [TF(['Portland', 'San Francisco', 'Pensacola', 'Atlanta', 'Juneau', 'Helena'] + n(8, 'DD') + n(7, 'AP') + n(1, 'PG'), [52, 22]),
                 TF(['Enterprise', 'Washington', 'South Dakota', 'Northampton', 'San Diego'] + n(15, 'DD'), mare(70, 43), {'Enterprise': {'Wildcat': 13, 'Dauntless': 10, 'Avenger': 3}}, entra=19)],
          'basi': {'henderson': {'Wildcat': 9, 'Dauntless': 12, 'Avenger': 3, 'P-39': 1}, 'espiritu_santo': {'B-17': 12, 'Hudson': 2, 'Catalina': 6}, 'nuova_caledonia': {'Catalina': 2},
                   'gili_gili': {'P-40': 8}, 'port_moresby': {'P-40': 16, 'B-26': 20, 'B-25': 20, 'Hudson': 2, 'A-20': 4, 'Beaufort': 4, 'Beaufighter': 4, 'P-38': 5}, 'australia': {'B-17': 9, 'Catalina': 2}},
          'radar': ['*tutte', 'henderson', 'espiritu_santo', 'gili_gili', 'port_moresby', 'nuova_caledonia', 'australia']},
    'J': {'tf': [TF(['Chokai', 'Kinugasa', 'Isuzu', 'Suzuya', 'Maya', 'Tenryu'] + n(17, 'DD') + n(11, 'AP'), [37, 13]),
                 TF(['Junyo', 'Hiyo'] + n(6, 'DD'), mare(50, 4), {'Junyo': {'Zero': 7, 'Val': 6, 'Kate': 3}, 'Hiyo': {'Zero': 7, 'Val': 6, 'Kate': 3}}),
                 TF(['Hiei', 'Kirishima', 'Nagara', 'Tone'] + n(8, 'DD'), mare(48, 10), {'Tone': {'Pete': 1, 'Jake': 1}, 'Kirishima': {'Pete': 1}}),
                 TF(['Kongo', 'Haruna', 'Atago', 'Takao', 'Sendai'] + n(6, 'DD'), mare(52, 6), {'Kongo': {'Pete': 1}, 'Haruna': {'Jake': 1}})],
          'basi': {'rabaul': {'Zero': 15, 'Betty': 20, 'Nell': 2, 'Mavis': 2, 'Emily': 2}, 'buin': {'Zero': 15, 'Val': 9}, 'buka': {'Kate': 3},
                   'shortland': {'Rufe': 2, 'Mavis': 2}, 'buna': {}, 'gasmata': {}, 'lae': {}, 'kavieng': {}, 'truk': {}},
          'radar': ['shortland', 'rabaul', 'lae', 'gasmata']},
    'speciali': {'henderson_ripara2': True, 'he_hiei_kirishima': True, 'enterprise_rf6': True, 'idro_j_meno1': True,
                 'sbarco': {'A': {'hex': [[52, 22]], 'nome': 'Henderson'}, 'J': {'isola': 'guadalcanal', 'escludi': [[52, 22]], 'nome': 'Guadalcanal (non Henderson)'}}},
    'vittoria': {'tipo': 'guadalcanal', 'auto': 100, 'min': 50, 'bonus_sbarco_max': 50, 'sbarco_vince_J': 100},
    'obiettivi': {'A': {'sbarco': 'henderson', 'difendi': 'henderson', 'caccia_portaerei': True}, 'J': {'sbarco': 'guadalcanal', 'attacca_base': 'henderson', 'caccia_portaerei': True}},
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
    for side in 'AJ':
        for t in s[side]['tf']:
            if ter(*t['hex']) not in '.p': print('ATTENZIONE', s['id'], t['hex'], ter(*t['hex']))
