from build_vip import *
import numpy as np
from pathlib import Path
# Prefer the already accepted repository source model; retain original output fallback.
candidates=[ROOT/'source/reference/Chair.rbxmx',ROOT.parents[2]/'assets/models/astra-garage/models/Chair.rbxmx',ROOT.parent/'roblox-garage-kit/models/Chair.rbxmx']
source=next((p for p in candidates if p.exists()),None)
if source is None:raise RuntimeError('Need accepted astra-garage/models/Chair.rbxmx for overlay fit check')
base=[]
for it in ET.parse(source).getroot().iter('Item'):
 if it.get('class') not in ['Part','Seat']:continue
 pr=it.find('Properties');n=pr.findtext("string[@name='Name']")
 if n=='Pivot':continue
 cf=pr.find("CoordinateFrame[@name='CFrame']");sz=pr.find("Vector3[@name='size']");col=pr.find("Color3[@name='Color']")
 token=pr.findtext("token[@name='shape']") or '1'
 p=dict(name=n,p=tuple(float(cf.findtext(k)) for k in 'XYZ'),s=tuple(float(sz.findtext(k)) for k in 'XYZ'),r=tuple(float(cf.findtext('R'+str(i)+str(j))) for i in range(3) for j in range(3)),c=tuple(round(float(col.findtext(k))*255) for k in 'RGB') if col is not None else (80,90,110),shape={'0':'ball','1':'box','2':'cyl'}[token],alpha=float(pr.findtext("float[@name='Transparency']") or 0),mat='SmoothPlastic',cls=it.get('class'),collide=False)
 base.append(p)
def sat(a,b):
 A=np.asarray(a['r']).reshape(3,3);B=np.asarray(b['r']).reshape(3,3);d=np.array(b['p'])-a['p'];ah=np.array(a['s'])/2;bh=np.array(b['s'])/2
 for axis in list(A.T)+list(B.T)+[np.cross(x,y) for x in A.T for y in B.T]:
  if np.linalg.norm(axis)<1e-8:continue
  ra=sum(abs(axis@A[:,i])*ah[i] for i in range(3));rb=sum(abs(axis@B[:,i])*bh[i] for i in range(3))
  if abs(d@axis)>=ra+rb-1e-4:return False
 return True
bad=[(p['name'],q['name']) for p in ASSETS['VipChair']['parts'] for q in base if sat(p,q)]
print('Overlay overlapping accepted Chair solids:',bad)
assert not bad
# Existing generated sign strips remain in VipService; custom outer ring clears them.
fallback=[]
for xx in (-7.1,7.1):fallback.append(dict(p=(xx,0,0),s=(.2,2.6,.5),r=I,name='codeSide'))
for yy in (-1.2,1.2):fallback.append(dict(p=(0,yy,0),s=(14.4,.2,.5),r=I,name='codeTopBottom'))
assert not [(p['name'],q['name']) for p in ASSETS['VipSignFrame']['parts'] for q in fallback if sat(p,q)]
preview(base+ASSETS['VipChair']['parts'],ROOT/'previews/VipChair_OnAcceptedChair.png',yaw=25,elev=22,span=6.5,target=(0,2,0),W=1300,H=1200)
report=json.loads((ROOT/'MODELS_VALIDATION.json').read_text());report['VipChair']['overlayVsAcceptedChair']='PASS: OBB SAT, no solid overlap';report['VipChair']['referenceChair']=source.name
(ROOT/'MODELS_VALIDATION.json').write_text(json.dumps(report,indent=2))
