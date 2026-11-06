from pathlib import Path
import tempfile,json,subprocess,xml.etree.ElementTree as E
R=Path(__file__).resolve().parents[1]
def textval(e):
 t=e.text.strip()if e.text else''
 try:return float(t)
 except ValueError:return t
def equivalent(a,b):
 if isinstance(a,(int,float))and isinstance(b,(int,float)):return abs(a-b)<=1e-6
 if isinstance(a,(tuple,list))and isinstance(b,(tuple,list)):return len(a)==len(b)and all(equivalent(x,y)for x,y in zip(a,b))
 return a==b
def norm(e):return(e.tag,tuple(sorted((k,v)for k,v in e.attrib.items()if k!='referent')),textval(e),tuple(norm(c)for c in e))
def tree(root):
 ids={e.get('referent'):i for i,e in enumerate(root.iter('Item'))}
 for ref in root.iter('Ref'):
  if ref.text in ids:ref.text=str(ids[ref.text])
 return[(e.get('class'),tuple(sorted((norm(p)for p in e.find('Properties')),key=str)))for e in root.iter('Item')]
with tempfile.TemporaryDirectory()as tmp:
 tmp=Path(tmp);p=tmp/'test.project.json';p.write_text(json.dumps({'name':'Pigeon','tree':{'$path':str(R/'models/Pigeon.rbxm')}}));out=tmp/'Pigeon.rbxmx';subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(p),'-o',str(out)],check=True,capture_output=True);assert equivalent(tree(E.parse(out).getroot()),tree(E.parse(R/'models/Pigeon.rbxmx').getroot()))
f=R/'VALIDATION.json';v=json.loads(f.read_text());v['binaryRoundtrip']='PASS';f.write_text(json.dumps(v,indent=2)+'\n');print('binary roundtrip PASS')
