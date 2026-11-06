"""Separation certificates for real native convex Parts.
Accept only an explicit analytic support-plane gap >= -tolerance.
No separating certificate means FAIL/unresolved, never an assumed non-overlap.
GJK distance simplex + projected support-gap search finds candidate normals.
"""
from pathlib import Path
import xml.etree.ElementTree as E
import itertools,math,sys
sys.path.insert(0,'/private/tmp/gst-render-libs')
import numpy as np

def parse(path):
 root=E.parse(path).getroot();out=[]
 for e in root.iter('Item'):
  cls=e.get('class')
  if cls not in ['Part','WedgePart','Seat']:continue
  p=e.find('Properties');cf=p.find('CoordinateFrame[@name="CFrame"]');sz=p.find('Vector3[@name="size"]')
  pos=np.array([float(cf.findtext(a))for a in 'XYZ']);R=np.array([[float(cf.findtext(f'R{i}{j}'))for j in range(3)]for i in range(3)]);half=np.array([float(sz.findtext(a))/2 for a in 'XYZ'])
  assert np.max(np.abs(R.T@R-np.eye(3)))<2e-6
  token=p.findtext('token[@name="shape"]','1');shape='wedge'if cls=='WedgePart'else {'0':'ball','1':'box','2':'cyl'}[token]
  out.append({'name':p.findtext('string[@name="Name"]'),'ref':e.get('referent'),'p':pos,'R':R,'h':half,'shape':shape,'alpha':float(p.findtext('float[@name="Transparency"]','0'))})
 return out

def support(o,d):
 v=o['R'].T@np.asarray(d,dtype=float);h=o['h'];shape=o['shape']
 if shape=='ball':
  den=np.linalg.norm(h*v);q=h*h*v/den if den>1e-18 else np.zeros(3)
 elif shape=='cyl':
  q=np.zeros(3);q[0]=h[0] if v[0]>=0 else -h[0];den=np.linalg.norm(h[1:]*v[1:])
  if den>1e-18:q[1:]=h[1:]**2*v[1:]/den
 elif shape=='wedge':
  verts=np.array([[-1,-1,-1],[1,-1,-1],[1,-1,1],[-1,-1,1],[-1,1,1],[1,1,1]],dtype=float)*h
  q=verts[np.argmax(verts@v)]
 else:q=np.where(v>=0,h,-h)
 return o['p']+o['R']@q

def gap(a,b,n):
 n=np.asarray(n,dtype=float);ln=np.linalg.norm(n)
 if ln<1e-16:return -math.inf
 n=n/ln
 return float((support(b,-n)-support(a,n))@n)

def closest_simplex(points):
 best=None
 for count in range(1,min(4,len(points))+1):
  for inds in itertools.combinations(range(len(points)),count):
   P=np.array([points[i]for i in inds]);G=P@P.T
   K=np.block([[G,np.ones((count,1))],[np.ones((1,count)),np.zeros((1,1))]])
   rhs=np.r_[np.zeros(count),1.]
   sol=np.linalg.lstsq(K,rhs,rcond=1e-13)[0][:count]
   if np.min(sol)<-1e-9 or abs(np.sum(sol)-1)>1e-7:continue
   sol=np.maximum(sol,0);sol/=np.sum(sol);q=sol@P;norm=float(q@q)
   if best is None or norm<best[0]:
    used=[points[i]for i,w in zip(inds,sol)if w>1e-10];best=(norm,q,used)
 if best is None:raise RuntimeError('No feasible simplex')
 return best[1],best[2]

def separate(a,b,tol=1e-6):
 axes=[*a['R'].T,*b['R'].T,b['p']-a['p']]
 axes += [np.cross(x,y)for x in a['R'].T for y in b['R'].T]
 bestg=-math.inf;bestn=None
 def test(n,method):
  nonlocal bestg,bestn
  n=np.asarray(n,dtype=float);ln=np.linalg.norm(n)
  if ln<1e-14:return None
  n=n/ln
  if (b['p']-a['p'])@n<0:n=-n
  g=gap(a,b,n)
  if g>bestg:bestg,bestn=g,n
  if g>=-tol:return {'axis':n.tolist(),'gap':g,'method':method}
  return None
 for n in axes:
  ok=test(n,'analytic-support-axis')
  if ok:return ok
 d=b['p']-a['p']
 if np.linalg.norm(d)<1e-12:d=np.array([1.,0,0])
 simplex=[support(a,d)-support(b,-d)];closest=simplex[0]
 for _ in range(96):
  d=-closest;ok=test(d,'GJK-support-plane')
  if ok:return ok
  if np.linalg.norm(d)<1e-13:break
  w=support(a,d)-support(b,-d)
  if any(np.linalg.norm(w-x)<1e-12 for x in simplex):break
  closest,simplex=closest_simplex(simplex+[w])
 # Every accepted result is independently checked as a true analytic support plane.
 seeds=[bestn,b['p']-a['p']]+axes[:6]
 for seed in seeds:
  if seed is None or np.linalg.norm(seed)<1e-12:continue
  n=np.array(seed,dtype=float);n/=np.linalg.norm(n)
  if (b['p']-a['p'])@n<0:n=-n
  for _ in range(120):
   ok=test(n,'optimized-support-plane')
   if ok:return ok
   g=gap(a,b,n);gradient=support(b,-n)-support(a,n);t=gradient-(gradient@n)*n
   if np.linalg.norm(t)<1e-13:break
   improved=False
   for power in range(22):
    cand=n+(2.**(-power))*t;cand/=np.linalg.norm(cand);cg=gap(a,b,cand)
    if cg>g+1e-15:n=cand;improved=True;break
   if not improved:break
 return None

def audit(parts,tol=1e-6):
 results=[];bad=[]
 for a,b in itertools.combinations(parts,2):
  cert=separate(a,b,tol)
  if cert is None:bad.append([a['name'],b['name']])
  else:
   verified=gap(a,b,cert['axis']);assert verified>=-tol
   results.append({'a':a['ref'],'b':b['ref'],**cert})
 return results,bad

if __name__=='__main__':
 import json,collections
 path=Path(sys.argv[1]);parts=[p for p in parse(path)if p['alpha']<.99];certs,bad=audit(parts)
 print(json.dumps({'parts':len(parts),'pairs':len(certs)+len(bad),'separated':len(certs),'unresolvedOrOverlap':bad,'methods':dict(collections.Counter(c['method']for c in certs))},indent=2))
 if bad:sys.exit(1)
