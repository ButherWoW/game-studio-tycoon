from pathlib import Path
import xml.etree.ElementTree as E,json,subprocess
R=Path(__file__).resolve().parents[1];B=R/'baseline';ROJO='/Users/erland/.local/gst-tools/rojo'
allowed=json.loads((R/'ALLOWED_DELETIONS.json').read_text())
for f in sorted(B.glob('*.rbxmx')):
 t=E.parse(f);root=t.getroot();parents={c:p for p in root.iter()for c in p};count=0;removed=[]
 for e in list(root.iter('Item')):
  p=e.find('Properties');n=p.findtext("string[@name='Name']")
  if p.findtext("token[@name='Material']")=='1568':p.find("float[@name='Transparency']").text='0.4';count+=1
  if e.get('referent') in {x['referent'] for x in allowed[f.stem]}:parents[e].remove(e);removed.append(e.get('referent'))
 assert len(removed)==len(allowed[f.stem])
 lights=list(root.findall('.//Item[@class="PointLight"]'));assert len(lights)==4
 for light in lights[1:]:parents[light].remove(light)
 lp=lights[0].find('Properties')
 for tag,name,value in [('bool','Shadows','false'),('float','Range','60'),('float','Brightness','1')]:
  node=lp.find(f'{tag}[@name="{name}"]')
  if node is None:node=E.SubElement(lp,tag,{'name':name})
  node.text=value
 for ref in root.iter('Ref'):assert ref.text not in removed,'dangling reference'
 target=R/'models'/f.name;t.write(target,encoding='utf-8',xml_declaration=True)
 project=R/'source'/'convert.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(target)}}));subprocess.run([ROJO,'build',str(project),'-o',str(target.with_suffix('.rbxm'))],check=True,capture_output=True)
project.unlink()
