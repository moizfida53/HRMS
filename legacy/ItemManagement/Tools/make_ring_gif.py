#!/usr/bin/env python3
"""
Spin only the gold ring of a circular logo; keep the center (text) static.
Reusable for any circular logo with a warm/gold ring (auto-detected).
Usage: python3 make_ring_gif.py <input_image> <output_gif> [out_width]
"""
import sys, os, numpy as np
from PIL import Image

SRC   = sys.argv[1] if len(sys.argv) > 1 else 'Pistachio_B2.png'
OUT   = sys.argv[2] if len(sys.argv) > 2 else 'pistachio-logo.gif'
OUT_W = int(sys.argv[3]) if len(sys.argv) > 3 else 224   # display size (px)
N, COLORS, DUR = 30, 64, 60

im = Image.open(SRC).convert('RGB')
a = np.asarray(im).astype(float); h, w, _ = a.shape
R, G, B = a[:,:,0], a[:,:,1], a[:,:,2]

# detect the warm/gold ring -> circle geometry
gold = (R>170)&(R<245)&(G>120)&(G<200)&(B>60)&(B<160)&(R-B>50)&(R-G>15)&(G-B>15)
ys, xs = np.where(gold)
cx, cy = (xs.min()+xs.max())/2.0, (ys.min()+ys.max())/2.0
R_out = ((xs.max()-xs.min())/2.0 + (ys.max()-ys.min())/2.0)/2.0
YY, XX = np.mgrid[0:h, 0:w]
rr = np.sqrt((XX-cx)**2 + (YY-cy)**2)
r_in_g, r_out_g = np.percentile(rr[gold],2), np.percentile(rr[gold],98)
print(f'center=({cx:.1f},{cy:.1f}) R={R_out:.1f} band={r_in_g:.1f}..{r_out_g:.1f}')

Rmask = R_out + 2.0
alpha = np.clip((Rmask - rr)/1.5 + 0.5, 0, 1) * 255.0
ang = np.arctan2(YY-cy, XX-cx)
band = np.clip(1 - np.abs(rr-(r_in_g+r_out_g)/2)/((r_out_g-r_in_g)/2 + 1.5), 0, 1)**0.6
wrap = lambda x:(x+np.pi)%(2*np.pi)-np.pi
LIGHT, SHADE = np.array([255,244,210]), np.array([150,110,60])

m = 10
x0,y0 = max(0,int(cx-Rmask-m)), max(0,int(cy-Rmask-m))
x1,y1 = min(w,int(cx+Rmask+m)), min(h,int(cy+Rmask+m))
scale = OUT_W/(x1-x0)

frames=[]
for f in range(N):
    th = 2*np.pi*f/N
    hi = np.exp(-(wrap(ang-th)/0.55)**2) + 0.45*np.exp(-(wrap(ang-(th+np.pi))/0.55)**2)
    sh = np.exp(-(wrap(ang-(th+np.pi/2))/0.6)**2) + np.exp(-(wrap(ang-(th-np.pi/2))/0.6)**2)
    hi = np.clip(hi,0,1)*band*0.9; sh = np.clip(sh,0,1)*band*0.30
    fr = a.copy()
    for c in range(3):
        fr[:,:,c] = fr[:,:,c]*(1-hi)+LIGHT[c]*hi
        fr[:,:,c] = fr[:,:,c]*(1-sh)+SHADE[c]*sh
    img = Image.fromarray(np.dstack([np.clip(fr,0,255),alpha]).astype(np.uint8),'RGBA').crop((x0,y0,x1,y1))
    img = img.resize((OUT_W, int((y1-y0)*scale)), Image.LANCZOS)
    frames.append(img)
print('frame size', frames[0].size)

Image.alpha_composite(Image.new('RGBA',frames[0].size,(201,161,120,255)), frames[N//2]).convert('RGB').save('preview_on_tan.png')

def to_p(img):
    rgb = img.convert('RGB').quantize(colors=COLORS, method=Image.MEDIANCUT)
    arr = np.asarray(rgb).copy(); arr[np.asarray(img.split()[3])<128] = COLORS
    p = Image.fromarray(arr,'P'); p.putpalette(rgb.getpalette()+[0,0,0]*(COLORS+1-len(rgb.getpalette())//3))
    p.info['transparency']=COLORS; return p

pf=[to_p(fr) for fr in frames]
pf[0].save(OUT, save_all=True, append_images=pf[1:], loop=0, duration=DUR,
           disposal=2, transparency=COLORS, optimize=True)
print('saved', OUT, round(os.path.getsize(OUT)/1024,1),'KB', 'frames', N)
