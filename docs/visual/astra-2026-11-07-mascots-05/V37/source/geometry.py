import math, json, copy, xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TAU=2*math.pi
I=(1,0,0,0,1,0,0,0,1)
serial=0
MAT={'SmoothPlastic':272,'Neon':288,'Wood':512,'WoodPlanks':528,'Metal':1088,'Concrete':816,'Glass':1568}
C={'wood':'C8A27A','top':'C8A27A','edge':'DEC1A0','darkwood':'886643','blue':'3D7BFF','fabric':'3874C6','seam':'285590','gold':'FFC93C','warm':'FFD9A0','dark':'283345','metal':'657083','silver':'B0B7C3','white':'F2F2F2','green':'4CAF50','leaf':'8AC461','cyan':'79D5ED','concrete':'DADDDD','pink':'FF6EB4','purple':'9650DC'}
def rgb(c):
 c=C.get(c,c).lstrip('#');return tuple(int(c[i:i+2],16) for i in (0,2,4))

def add(a,b):return tuple(x+y for x,y in zip(a,b))

def mul(a,b):return tuple(sum(a[i*3+k]*b[k*3+j] for k in range(3)) for i in range(3) for j in range(3))

def mv(a,v):return tuple(sum(a[i*3+k]*v[k] for k in range(3)) for i in range(3))

def rot(x=0,y=0,z=0):
 x,y,z=map(math.radians,(x,y,z));cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
 return mul(mul((cy,0,sy,0,1,0,-sy,0,cy),(1,0,0,0,cx,-sx,0,sx,cx)),(cz,-sz,0,sz,cz,0,0,0,1))

def model(n):return {'name':n,'parts':[],'children':[],'pos':(0,0,0),'r':I}

def part(m,n,p,s,c='dark',shape='box',r=I,mat='SmoothPlastic',collide=False,alpha=0,cls='Part',light=None):
 d=dict(name=n,p=tuple(p),s=tuple(s),c=rgb(c),shape=shape,r=r,mat=mat,collide=collide,alpha=alpha,cls=cls)
 if light:d['light']=light
 m['parts'].append(d);return d

def box(m,n,p,s,c='dark',**kw):return part(m,n,p,s,c,**kw)

def cyl(m,n,p,h,d,c='dark',r=None,**kw):return part(m,n,p,(h,d,d),c,'cyl',r or rot(z=90),**kw)

def ball(m,n,p,s,c='dark',**kw):return part(m,n,p,s,c,'ball',**kw)

def rounded(m,n,p,s,c='dark',rad=.07,**kw):
 # Exact rounded cuboid as 3 slabs, 12 edge cylinders and 8 corner spheres.
 rad=min(rad,min(s)/2-.001)
 if rad<.015:return box(m,n,p,s,c,**kw)
 R=kw.pop('r',I);inner=[v-2*rad for v in s];lit=[kw.pop('light',None)]
 # One PointLight per rounded object: on the first slab only (23 lights per desk lamp hit mobile)
 def emit(nm,off,sz,sh='box',rr=I):
  extra={'light':lit.pop()} if lit and lit[0] else {}
  if lit and not lit[0]:lit.pop()
  return part(m,n+nm,add(p,mv(R,off)),sz,c,sh,mul(R,rr),**kw,**extra)
 for a in range(3):
  sz=inner.copy();sz[a]=s[a];emit('_core'+str(a),(0,0,0),sz)
 for axis in range(3):
  axes=[a for a in range(3) if a!=axis]
  rr=I if axis==0 else rot(z=90) if axis==1 else rot(y=90)
  for a in (-1,1):
   for b in (-1,1):
    off=[0,0,0];off[axes[0]]=a*inner[axes[0]]/2;off[axes[1]]=b*inner[axes[1]]/2
    emit('_edge',off,(inner[axis],2*rad,2*rad),'cyl',rr)
 for x in (-1,1):
  for y in (-1,1):
   for z in (-1,1):emit('_corner',(x*inner[0]/2,y*inner[1]/2,z*inner[2]/2),(2*rad,)*3,'ball')

def line(m,n,a,b,d,c='dark',**kw):
 v=tuple(b[i]-a[i] for i in range(3));length=math.sqrt(sum(t*t for t in v));u=tuple(t/length for t in v)
 ref=(0,1,0) if abs(u[1])<.9 else (0,0,1)
 cross=lambda a,b:(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
 w=cross(u,ref);wn=math.sqrt(sum(t*t for t in w));w=tuple(t/wn for t in w);v2=cross(w,u)
 r=tuple((u,v2,w)[j][i] for i in range(3) for j in range(3))
 return cyl(m,n,tuple((a[i]+b[i])/2 for i in range(3)),length,d,c,r=r,**kw)

def put(parent,child,p=(0,0,0),yaw=0,name=None):
 c=copy.deepcopy(child);c['pos']=p;c['r']=rot(y=yaw)
 if name:c['name']=name
 parent['children'].append(c);return c

def prop(props,typ,name,value):
 e=ET.SubElement(props,typ,{'name':name});e.text=str(value);return e

def vec(props,name,v):
 e=ET.SubElement(props,'Vector3',{'name':name})
 for n,t in zip('XYZ',v):ET.SubElement(e,n).text=f'{t:.12g}'

def frame(props,name,p=(0,0,0),r=I):
 e=ET.SubElement(props,'CoordinateFrame',{'name':name})
 for n,v in zip(['X','Y','Z']+[f'R{i}{j}' for i in range(3) for j in range(3)],list(p)+list(r)):ET.SubElement(e,n).text=f'{v:.12g}'

def refid():
 global serial;serial+=1;return 'RBX'+str(serial)

def write_model(m,parent,worldp=(0,0,0),worldr=I):
 pos=add(worldp,mv(worldr,m['pos']));rr=mul(worldr,m['r'])
 rootid=refid();item=ET.SubElement(parent,'Item',{'class':'Model','referent':refid()});props=ET.SubElement(item,'Properties')
 prop(props,'string','Name',m['name'])
 if m['parts']:prop(props,'Ref','PrimaryPart',rootid)
 # Use an existing native Part + PivotOffset instead of another invisible Part for every tree.
 for index,p in enumerate(m['parts']):
  p=copy.deepcopy(p);p['p']=add(pos,mv(rr,p['p']));p['r']=mul(rr,p['r'])
  if index==0:
   inv=tuple(p['r'][j*3+i] for i in range(3) for j in range(3))
   p['pivotOffset']=(mv(inv,tuple(pos[i]-p['p'][i] for i in range(3))),mul(inv,rr))
  write_part(p,item,rootid if index==0 else None)
 for child in m['children']:write_model(child,item,pos,rr)
 return item

def write_part(p,parent,referent=None):
 it=ET.SubElement(parent,'Item',{'class':p['cls'],'referent':referent or refid()});pr=ET.SubElement(it,'Properties')
 prop(pr,'string','Name',p['name']);vec(pr,'size',p['s']);frame(pr,'CFrame',p['p'],p['r'])
 if p.get('pivotOffset'):frame(pr,'PivotOffset',*p['pivotOffset'])
 else:frame(pr,'PivotOffset')
 prop(pr,'Color3uint8','Color3uint8',(p['c'][0]<<16)|(p['c'][1]<<8)|p['c'][2])
 for n,v in [('Anchored',True),('CanCollide',p['collide']),('CanTouch',p['cls']=='Seat'),('CanQuery',p['collide'] or p['cls']=='Seat'),('CastShadow',p['mat']!='Neon' and p['alpha']<.5)]:prop(pr,'bool',n,str(v).lower())
 prop(pr,'float','Transparency',p['alpha']);prop(pr,'token','Material',MAT[p['mat']]);prop(pr,'token','TopSurface',0);prop(pr,'token','BottomSurface',0)
 if p['cls']=='Part':prop(pr,'token','shape',{'box':1,'ball':0,'cyl':2}[p['shape']])
 if p['cls']=='Seat':prop(pr,'bool','Disabled','false')
 if p.get('light'):
  ra,br,co=p['light'];li=ET.SubElement(it,'Item',{'class':'PointLight','referent':refid()});lp=ET.SubElement(li,'Properties');prop(lp,'string','Name','WarmLight');prop(lp,'float','Range',ra);prop(lp,'float','Brightness',br);prop(lp,'bool','Shadows','true' if ra>=30 else 'false')
  e=ET.SubElement(lp,'Color3',{'name':'Color'})
  for k,v in zip('RGB',rgb(co)):ET.SubElement(e,k).text=str(v/255)
 return it

def export(m,path,place=False):
 global serial;serial=0
 root=ET.Element('roblox',{'version':'4','xmlns:xmime':'http://www.w3.org/2005/05/xmlmime','xmlns:xsi':'http://www.w3.org/2001/XMLSchema-instance'})
 ET.SubElement(root,'External').text='null';ET.SubElement(root,'External').text='nil'
 target=root
 if place:
  ws=ET.SubElement(root,'Item',{'class':'Workspace','referent':refid()});pr=ET.SubElement(ws,'Properties');prop(pr,'string','Name','Workspace');target=ws
  lighting=ET.SubElement(root,'Item',{'class':'Lighting','referent':refid()});lp=ET.SubElement(lighting,'Properties');prop(lp,'string','Name','Lighting');prop(lp,'float','Brightness',2);prop(lp,'float','ClockTime',15)
  for name,col in [('Ambient','AFA4A1'),('OutdoorAmbient','B0B7CA')]:
   e=ET.SubElement(lp,'Color3',{'name':name})
   for k,v in zip('RGB',rgb(col)):ET.SubElement(e,k).text=str(v/255)
 write_model(m,target)
 ET.ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)

def flatten(m,wp=(0,0,0),wr=I):
 pos=add(wp,mv(wr,m['pos']));r=mul(wr,m['r']);out=[]
 for p in m['parts']:
  p=copy.deepcopy(p);p['p']=add(pos,mv(r,p['p']));p['r']=mul(r,p['r']);out.append(p)
 for child in m['children']:out.extend(flatten(child,pos,r))
 return out

def meshes(p):
 sx,sy,sz=[v/2 for v in p['s']]
 if p['shape']=='box':
  vs=[(x*sx,y*sy,z*sz) for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
  fs=[(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2)]
 elif p['shape']=='wedge':
  vs=[(-sx,-sy,-sz),(sx,-sy,-sz),(sx,-sy,sz),(-sx,-sy,sz),(-sx,sy,sz),(sx,sy,sz)]
  fs=[(0,3,2,1),(0,1,5,4),(0,4,3),(1,2,5),(3,4,5,2)]
 elif p['shape']=='cyl':
  N=28;vs=[(x*sx,math.cos(i*TAU/N)*sy,math.sin(i*TAU/N)*sz) for x in (-1,1) for i in range(N)];fs=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
 else:
  N=28;K=18;vs=[(sx*math.sin(j*math.pi/K)*math.cos(i*TAU/N),sy*math.cos(j*math.pi/K),sz*math.sin(j*math.pi/K)*math.sin(i*TAU/N)) for j in range(K+1) for i in range(N)]
  fs=[(j*N+i,j*N+(i+1)%N,(j+1)*N+(i+1)%N,(j+1)*N+i) for j in range(K) for i in range(N)]
 return [add(p['p'],mv(p['r'],v)) for v in vs],fs
