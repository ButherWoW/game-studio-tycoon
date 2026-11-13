from pathlib import Path
import json,subprocess,os,xml.etree.ElementTree as ET
import numpy as np
from convex_support import parse
ROOT=Path(__file__).resolve().parents[1]
project=ROOT/'source/roundtrip.project.json'
project.write_text(json.dumps({'name':'Fountain','tree':{'$path':'../models/Fountain.rbxm'}}))
subprocess.run([os.environ.get('ROJO','/Users/erland/.local/gst-tools/rojo'),'build',str(project),'-o',str(ROOT/'source/Fountain.roundtrip.rbxmx')],check=True)
a=parse(ROOT/'models/Fountain.rbxmx');b=parse(ROOT/'source/Fountain.roundtrip.rbxmx')
assert len(a)==len(b)
for p,q in zip(a,b):
    assert p['name']==q['name'] and p['shape']==q['shape']
    for k in ('p','R','h'):assert np.max(np.abs(p[k]-q[k]))<2e-6,(p['name'],k)
def pivot(path):
    root=ET.parse(path).getroot();m=next(e for e in root.iter('Item') if e.get('class')=='Model');ref=m.findtext('Properties/Ref[@name="PrimaryPart"]')
    part=next(e for e in m.iter('Item') if e.get('referent')==ref);props=part.find('Properties')
    def cf(name):
        f=props.find('CoordinateFrame[@name="'+name+'"]');pos=np.array([float(f.findtext(x)) for x in 'XYZ']);R=np.array([[float(f.findtext(f'R{i}{j}')) for j in range(3)]for i in range(3)]);return pos,R
    p,R=cf('CFrame');o,S=cf('PivotOffset');return p+R@o,R@S
for path in (ROOT/'models/Fountain.rbxmx',ROOT/'source/Fountain.roundtrip.rbxmx'):
    p,R=pivot(path);assert np.linalg.norm(p)<1e-6 and np.linalg.norm(R-np.eye(3))<1e-6
report={'partTransformsMatch':len(a),'maxTolerance':2e-6,'pivot':[0,0,0],'pivotRotation':'identity','scriptFree':True,'studioTested':False}
(ROOT/'ROUNDTRIP_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
