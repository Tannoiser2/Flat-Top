#!/usr/bin/env python3
"""Mappe degli scenari 6 (Midway) e 7 (Wake): griglia (tutto mare, atolli parziali), esagoni d'ingresso
dalle basi fuori mappa (numeri sul bordo: turni di volo) e immagine webp per il gioco.
Serve il modulo VASSAL estratto in /home/claude/v2/images."""
import json, os
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, 'data')
X0, Y0, DX, DY, COLS, ROWS = 81, 57, 48, 56, 51, 35
def centro(c, r): return (X0 + c * DX, Y0 + r * DY + (DY // 2 if c % 2 else 0))
for nome, img in (('midway', 'Midway_Map.gif'), ('wake', 'Wake_Map.gif')):
    im = Image.open('/home/claude/v2/images/' + img).convert('RGB')
    M = np.array(im).astype(int)
    R, G, B = M[..., 0], M[..., 1], M[..., 2]
    # scogliere blu scuro, terra verde o nera, stella blu: tutto ciò che non è mare né scritta
    atollo = ((B > 150) & (R < 60) & (G < 150)) | ((G > 150) & (R < 140) & (B < 160)) | ((R < 60) & (G < 60) & (B < 60) & (np.arange(M.shape[1])[None, :] > 70) & (np.arange(M.shape[1])[None, :] < 2480) & (np.arange(M.shape[0])[:, None] > 70) & (np.arange(M.shape[0])[:, None] < 1940))
    grid = []
    for r in range(ROWS):
        riga = ''
        for c in range(COLS):
            x, y = centro(c, r)
            if y + 20 > M.shape[0] - 20:
                riga += ' '
                continue
            win = atollo[max(0, y - 22):y + 22, max(0, x - 22):x + 22]
            riga += 'p' if win.sum() > 25 else '.'
        grid.append(riga)
    # le rose dei venti grigie non sono atolli
    ROSE = [(12, 8), (38, 8), (12, 26), (38, 26)]
    def cube(c, r):
        x = c; z = r - (c - (c & 1)) // 2; return x, -x - z, z
    def dist(a, b):
        ax, ay, az = cube(*a); bx, by, bz = cube(*b); return max(abs(ax - bx), abs(ay - by), abs(az - bz))
    for r in range(ROWS):
        for c in range(COLS):
            if grid[r][c] == 'p' and any(dist((c, r), q) <= 2 for q in ROSE):
                grid[r] = grid[r][:c] + '.' + grid[r][c + 1:]
    ps = [(c, r) for r in range(ROWS) for c in range(COLS) if grid[r][c] == 'p']
    print(nome, 'atolli', ps)
    json.dump({'grid': grid, 'row0': 0, 'x0': X0, 'y0': Y0, 'dx': DX, 'dy': DY, 'cols': COLS, 'img': 'res://assets/map/mappa_%s.webp' % nome,
               'w': im.size[0], 'h': im.size[1],
               'settori_hex': [[12, 8], [38, 8], [12, 26], [38, 26]], 'sett_col_w': 25, 'sett_row': 16, 'sett_ncol': 2}, open(os.path.join(D, 'mappa_%s.json' % nome), 'w'))
    isole = [[[c, r]] for (c, r) in ps]
    json.dump({'terra': [], 'scogliere': [], 'montagne': [], 'isole': isole, 'guardacoste': []}, open(os.path.join(D, 'lati_%s.json' % nome), 'w'))
    im.save(os.path.join(ROOT, 'assets/map/mappa_%s.webp' % nome), 'WEBP', quality=80)
