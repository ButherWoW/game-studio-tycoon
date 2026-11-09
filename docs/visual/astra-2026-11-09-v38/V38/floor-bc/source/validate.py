from pathlib import Path
import json,tempfile,subprocess,xml.etree.ElementTree as E
from convex_support import *
ROOT=Path(__file__).resolve().parents[1]
layout=json.loads((ROOT/'layout-reference.json').read_text())
def value(e):
 try:t=float(e.text.strip())if e.text else ''
 except ValueError:t=(e.text or '').strip()
 return(e.tag,tuple(sorted((k,v)for k,v in e.attrib.items()if k!='referent')),t,tuple(value(c)for c in e))
def norm(r):
 ids={e.get('referent'):str(i)for i,e in enumerate(r.iter('Item'))}
 for e in r.iter('Ref'):
  if e.text in ids:e.text=ids[e.text]
 return[(e.get('class'),sorted([value(p)for p in e.find('Properties')],key=str))for e in r.iter('Item')]
def equal(a,b):
 if isinstance(a,(float,int))and isinstance(b,(float,int)):return abs(a-b)<=1e-6
 if isinstance(a,(tuple,list))and isinstance(b,(tuple,list)):return len(a)==len(b)and all(equal(x,y)for x,y in zip(a,b))
 return a==b
def overlaps(a,b):return min(a[2],b[2])-max(a[0],b[0])>1e-6 and min(a[3],b[3])-max(a[1],b[1])>1e-6
reports=[]
for name,floor,x,y,z,maxx,maxz in [('GameGallery',2,0,3,-28.8,10,.4),('PanoramaCorner',3,22,.025,8,10,6)]:
 f=ROOT/'models'/(name+'.rbxmx');r=E.parse(f).getroot();ps=parse(f);cert,bad=audit(ps);assert not bad
 assert {i.get('class')for i in r.iter('Item')}=={'Model','Part','PointLight'}
 lights=list(r.findall(".//Item[@class='PointLight']"));assert len(lights)==1;assert lights[0].findtext("Properties/bool[@name='Shadows']")=='false'
 for item in r.findall(".//Item[@class='Part']"):assert item.findtext("Properties/bool[@name='Anchored']")=='true'
 lo=np.array([min(support(p,-np.eye(3)[i])[i]for p in ps)for i in range(3)]);hi=np.array([max(support(p,np.eye(3)[i])[i]for p in ps)for i in range(3)])
 assert len(ps)<=100 and hi[0]-lo[0]<=maxx+1e-6 and hi[2]-lo[2]<=maxz+1e-6
 assert abs(lo[1])<1e-6 and abs(lo[0]+hi[0])<1e-6 and abs(lo[2]+hi[2])<1e-6
 model=r.find('Item');ref=model.findtext("Properties/Ref[@name='PrimaryPart']");pr=next(i for i in r.iter('Item')if i.get('referent')==ref).find('Properties')
 def frame(n):
  t=pr.find("CoordinateFrame[@name='"+n+"']")
  return np.array([float(t.findtext(a))for a in 'XYZ']),np.array([[float(t.findtext('R'+str(i)+str(j)))for j in range(3)]for i in range(3)])
 pos,rot=frame('CFrame');off,rr=frame('PivotOffset');assert np.max(np.abs(pos+rot@off))<1e-6
 box=[lo[0]+x,lo[2]+z,hi[0]+x,hi[2]+z]
 targets=layout['floors'][str(floor)]+layout['legacyReservations']+[{'name':'Lift','box':[-23,21,-17,27]},{'name':'Buttons','box':[-29,22,29,29]}]
 conflicts=[t['name']for t in targets if overlaps(box,t['box'])];assert not conflicts,(name,conflicts)
 aprons=[]
 for t in layout['floors'][str(floor)]:
  if t['name'].endswith('Desk'):
   b=t['box'];apron=[b[0],b[3],b[2],b[3]+3];assert not overlaps(box,apron);aprons.append(apron)
 with tempfile.TemporaryDirectory()as temp:
  temp=Path(temp);p=temp/'p.project.json';p.write_text(json.dumps({'name':name,'tree':{'$path':str(f.with_suffix('.rbxm'))}}));out=temp/'out.rbxmx'
  subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(p),'-o',str(out)],check=True,capture_output=True)
  a=norm(E.parse(out).getroot());b=norm(r)
  assert equal(a,b),name
 reports.append({'name':name,'parts':len(ps),'dimensionsXYZ':(hi-lo).tolist(),'worldBoxXZ':box,'pairs':len(cert),'overlaps':bad,'layoutConflicts':conflicts,'deskApronsChecked':len(aprons),'binaryRoundtrip':'PASS','pivot':'PASS','allAnchored':True,'lights':1,'shadows':False,'scripts':0,'runtimeTested':False})
(ROOT/'INDEPENDENT_VALIDATION.json').write_text(json.dumps(reports,indent=2)+'\n');print(json.dumps(reports,indent=2))
