# Costruisce la mappa unica (Ovest+Est) e la griglia di esagoni con il terreno.
import json
from PIL import Image
W=Image.open('mat/FlatTop_v3/images/Map_West.gif').convert('RGB')
E=Image.open('mat/FlatTop_v3/images/Map_East.gif').convert('RGB')
M=Image.new('RGB',(W.width+E.width,max(W.height,E.height)),(0,0,0)); M.paste(W,(0,0)); M.paste(E,(W.width,0))
M.save('/tmp/fullmap.png')
X0,Y0,DX,DY=128,252,48,56
px=M.load()
def center(c,r): return X0+c*DX, Y0+r*DY+(28 if c%2 else 0)
def cls(p):
    r,g,b=p
    if abs(r-51)<20 and abs(g-204)<25 and b>225: return 'sea'
    if r>180 and g<80 and b<80: return 'red'   # pista aerea fuori mappa (anche testo rosso)
    if r<25 and g<25 and b<25: return 'black'
    if g>150 and r<150 and b<120: return 'green'
    if r<40 and 120<g<190 and b<90: return 'greenhex'
    if abs(r-g)<14 and abs(g-b)<14: return 'gray' if r<115 else 'lgray'
    if b>180 and r<100 and g<160: return 'blue'
    return 'other'
hexes={}
import math
for c in range(0,82):
    for r in range(-5,48):
        x,y=center(c,r)
        if x<0 or y<0 or x>=M.width or y>=M.height: continue
        cnt={}
        tot=0
        for dx in range(-20,21,2):
            for dy in range(-20,21,2):
                if dx*dx+dy*dy>400: continue
                xx,yy=x+dx,y+dy
                if 0<=xx<M.width and 0<=yy<M.height:
                    k=cls(px[xx,yy]); cnt[k]=cnt.get(k,0)+1; tot+=1
        if tot==0: continue
        f={k:v/tot for k,v in cnt.items()}
        sea=f.get('sea',0)+f.get('blue',0)+f.get('red',0)+f.get('lgray',0)+f.get('other',0)
        land=f.get('green',0)+f.get('gray',0)+ (f.get('black',0) if f.get('sea',0)>0.05 or f.get('green',0)>0.1 else 0)
        if f.get('greenhex',0)>0.3: t='offbase'
        elif f.get('red',0)>0.5: t='track'
        elif sea<0.02 and land<0.2: t='void'
        elif land<0.07: t='sea'
        elif land>0.93: t='land'
        else: t='partial'
        mount = f.get('black',0)>0.06 and f.get('green',0)>0.4
        hexes['%d,%d'%(c,r)]={'t':t,'m':1 if mount else 0}
json.dump(hexes,open('/home/claude/flat-top/data/hexes_raw.json','w'))
import collections; print(collections.Counter(h['t'] for h in hexes.values()))
# anteprima
from PIL import ImageDraw
P=M.copy(); d=ImageDraw.Draw(P)
col={'sea':None,'land':(0,120,0),'partial':(255,200,0),'track':(255,0,255),'offbase':(255,255,255),'void':(60,60,60)}
for k,h in hexes.items():
    c,r=map(int,k.split(',')); x,y=center(c,r)
    if col[h['t']]: d.ellipse((x-6,y-6,x+6,y+6),fill=col[h['t']])
    if h['m']: d.rectangle((x-3,y-3,x+3,y+3),fill=(255,0,0))
P.resize((P.width//2,P.height//2)).save('/tmp/hexprev.png')
P.crop((1000,300,2200,1300)).save('/tmp/hexprev2.png')
