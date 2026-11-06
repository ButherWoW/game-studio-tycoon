"""Patch accepted shell XML snapshots; never move or replace geometry."""
from pathlib import Path
import xml.etree.ElementTree as E
import subprocess,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
ROJO='/Users/erland/.local/gst-tools/rojo'
TARGETS={'WindowGlass','DoorWindow'}

def value(pr,tag,name,text):
 e=pr.find(f'{tag}[@name="{name}"]')
 if e is None:e=E.SubElement(pr,tag,{'name':name})
 e.text=str(text)

def main():
 (ROOT/'models').mkdir(exist_ok=True);changes=[]
 for f in sorted((ROOT/'baseline').glob('*.rbxmx')):
  tree=E.parse(f);r=tree.getroot();parent={c:p for p in r.iter() for c in p};panels=[]
  for part in r.findall('.//Item[@class="Part"]'):
   pr=part.find('Properties');name=pr.findtext('string[@name="Name"]')
   if name in TARGETS:
    panels.append({'name':name,'oldTransparency':float(pr.findtext('float[@name="Transparency"]','0'))});value(pr,'float','Transparency',0);value(pr,'token','Material',272)
  lights=r.findall('.//Item[@class="PointLight"]');assert len(lights)==4
  for light in lights[1:]:parent[light].remove(light)
  lp=lights[0].find('Properties');value(lp,'bool','Shadows','false');value(lp,'float','Range',60);value(lp,'float','Brightness',1)
  assert len(panels)==12
  target=ROOT/'models'/f.name;tree.write(target,encoding='utf-8',xml_declaration=True)
  proj=ROOT/'source'/'convert.project.json';proj.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(target)}}));subprocess.run([ROJO,'build',str(proj),'-o',str(target.with_suffix('.rbxm'))],check=True,capture_output=True);proj.unlink()
  changes.append({'model':f.stem,'panels':panels,'retainedLight':{'count':1,'Shadows':False,'Range':60,'Brightness':1},'geometryChanged':False,'pivotChanged':False})
 (ROOT/'CHANGES.json').write_text(json.dumps(changes,indent=2)+'\n')
if __name__=='__main__':main()
