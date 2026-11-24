#!/usr/bin/env python3
"""Ricava dalla mappa: lati d'esagono di scogliera e di montagna, isole, guardacoste (stelle blu = Alleati,
rosse = Giappone). Serve la mappa unita in /tmp/fullmap.png (vedi costruisci_mappa.py)."""
import json, os
import numpy as np
from PIL import Image
from scipy import ndimage
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, 'data')
M = np.array(Image.open('/tmp/fullmap.png').convert('RGB')).astype(int)
R, G, B = M[..., 0], M[..., 1], M[..., 2]
green = (G > 150) & (R < 120) & (B < 160)
reef = (B > 190) & (R < 45) & (G < 140)
black = (R < 40) & (G < 40) & (B < 40)
grid = json.load(open(os.path.join(D, 'mappa.json')))
row0 = grid['row0']; GR = grid['grid']
def ter(c, r):
    rr = r - row0
    if rr < 0 or rr >= len(GR) or c < 0 or c >= 80: return ' '
    return GR[rr][c]
def centro(c, r): return (128 + c * 48, 252 + r * 56 + (28 if c % 2 else 0))
EVEN = [(0, -1), (1, -1), (1, 0), (0, 1), (-1, 0), (-1, -1)]
ODD = [(0, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)]
def vicino(c, r, d):
    dc, dr = (ODD if c % 2 else EVEN)[d]; return c + dc, r + dr
basi = json.load(open(os.path.join(D, 'basi.json')))
base_hex = set()
for k, prof in basi.items():
    for p in prof.values(): base_hex.add(tuple(p['hex']))
def vicino_base(c, r):
    for (bc, br) in base_hex:
        if abs(bc - c) <= 2 and abs(br - r) <= 2: return True
    return False
def campiona(mask, a, b, t0=0.3, t1=0.7, w=3):
    (x0, y0), (x1, y1) = a, b
    tot = hit = 0
    for i in range(41):
        t = t0 + (t1 - t0) * i / 40
        x = int(x0 + (x1 - x0) * t); y = int(y0 + (y1 - y0) * t)
        for dx in range(-w, w + 1):
            for dy in range(-w, w + 1):
                if 0 <= y + dy < mask.shape[0] and 0 <= x + dx < mask.shape[1]:
                    tot += 1; hit += mask[y + dy, x + dx]
    return hit / max(1, tot)
# le stelle blu dei guardacoste non sono scogliere
_lb, _n = ndimage.label((B > 180) & (R < 80) & (G < 120))
for _i, _sl in enumerate(ndimage.find_objects(_lb)):
    _h = _sl[0].stop - _sl[0].start; _w = _sl[1].stop - _sl[1].start
    if 12 <= _h <= 20 and 13 <= _w <= 21:
        reef[max(0, _sl[0].start - 8):_sl[0].stop + 8, max(0, _sl[1].start - 8):_sl[1].stop + 8] = False
scogliere = []; montagne = []; terra = []
for c in range(80):
    for r in range(row0, row0 + len(GR)):
        t = ter(c, r)
        for d in (1, 2, 3):  # ogni lato una volta sola
            c2, r2 = vicino(c, r, d)
            t2 = ter(c2, r2)
            a = centro(c, r); b = centro(c2, r2)
            if t in '.p' and t2 in '.p' and not (vicino_base(c, r) and vicino_base(c2, r2)):
                if campiona(reef, a, b, 0.25, 0.75, 2) > 0.03:
                    scogliere.append([c, r, d])
            if t == 'p' and t2 == 'p' and campiona(green | black | (R + G + B < 200), a, b, 0.4, 0.6, 3) > 0.85:
                terra.append([c, r, d])
            if t in 'pLM' and t2 in 'pLM' and campiona(green, a, b, 0.0, 0.25, 4) > 0.3 and campiona(green, a, b, 0.75, 1.0, 4) > 0.3:
                if campiona(black, a, b, 0.3, 0.7, 2) > 0.10:
                    montagne.append([c, r, d])
# isole: componenti connesse degli esagoni di terra (parziali e pieni)
lab = {}; isole = []
for c in range(80):
    for r in range(row0, row0 + len(GR)):
        if ter(c, r) in 'pLM' and (c, r) not in lab:
            idx = len(isole); stack = [(c, r)]; comp = []
            lab[(c, r)] = idx
            while stack:
                cc, rr = stack.pop(); comp.append([cc, rr])
                for d in range(6):
                    n = vicino(cc, rr, d)
                    if ter(*n) in 'pLM' and n not in lab:
                        lab[n] = idx; stack.append(n)
            isole.append(comp)
# guardacoste
green = (G > 150) & (R < 120) & (B < 160)
cw = []
for lato, mask in (('J', (R > 200) & (G < 60) & (B < 60)), ('A', (B > 180) & (R < 80) & (G < 120))):
    lb, n = ndimage.label(mask)
    for i, sl in enumerate(ndimage.find_objects(lb)):
        h = sl[0].stop - sl[0].start; w = sl[1].stop - sl[1].start
        if not (14 <= h <= 18 and 15 <= w <= 19): continue
        if (lb[sl] == i + 1).sum() < 80: continue
        y0, y1 = max(0, sl[0].start - 6), sl[0].stop + 6; x0, x1 = max(0, sl[1].start - 6), sl[1].stop + 6
        if green[y0:y1, x0:x1].mean() < 0.3: continue
        cx = (sl[1].start + sl[1].stop) / 2; cy = (sl[0].start + sl[0].stop) / 2
        # esagono
        best = None
        for c in range(80):
            for r in range(row0, row0 + len(GR)):
                x, y = centro(c, r); dd = (x - cx) ** 2 + (y - cy) ** 2
                if best is None or dd < best[0]: best = (dd, c, r)
        c, r = best[1], best[2]
        isola = lab.get((c, r))
        if isola is None:
            for d in range(6):
                n = vicino(c, r, d)
                if n in lab: isola = lab[n]; break
        cw.append({'lato': lato, 'hex': [c, r], 'isola': isola})
json.dump({'terra': terra, 'scogliere': scogliere, 'montagne': montagne, 'isole': isole, 'guardacoste': cw},
          open(os.path.join(D, 'lati.json'), 'w'))
print('terra', len(terra), 'scogliere', len(scogliere), 'montagne', len(montagne), 'isole', len(isole), 'guardacoste', len(cw))
for x in cw: print(x['lato'], x['hex'], x['isola'], len(isole[x['isola']]) if x['isola'] is not None else '-')
# anteprima
from PIL import ImageDraw
P = Image.open('/tmp/fullmap.png').convert('RGB'); dr = ImageDraw.Draw(P)
for c, r, d in scogliere:
    a = centro(c, r); b = centro(*vicino(c, r, d)); m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    dr.ellipse((m[0] - 5, m[1] - 5, m[0] + 5, m[1] + 5), fill=(255, 0, 255))
for c, r, d in montagne:
    a = centro(c, r); b = centro(*vicino(c, r, d)); m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    dr.rectangle((m[0] - 4, m[1] - 4, m[0] + 4, m[1] + 4), fill=(255, 140, 0))
for x in cw:
    p = centro(*x['hex']); dr.ellipse((p[0] - 10, p[1] - 10, p[0] + 10, p[1] + 10), outline=(255, 255, 0), width=3)
for c, r, d in terra:
    a = centro(c, r); b = centro(*vicino(c, r, d)); m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    dr.ellipse((m[0] - 6, m[1] - 6, m[0] + 6, m[1] + 6), fill=(255, 0, 0))
P.crop((900, 1300, 2000, 2000)).save('/tmp/lati1.png')
P.crop((2300, 1200, 3500, 1900)).save('/tmp/lati3.png')
P.crop((1700, 700, 2900, 1500)).save('/tmp/lati2.png')
