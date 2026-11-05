import sys,xml.etree.ElementTree as ET
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from check_overlay import sat,ASSETS,ROOT
import json
report={}
from pathlib import Path
for style in ['neon','cozy','minimal']:
 name=f'Chair_{style.title()}.rbxmx'
 candidates=list((ROOT.parents[2]/'assets/models').glob('*/models/'+name)) if (ROOT.parents[2]/'assets/models').exists() else []
 candidates+=[ROOT.parent/'roblox-furniture-styles-v15'/f'garage-{style}'/'models'/name]
 p=next((p for p in candidates if p.exists()),None)
 if p is None:raise RuntimeError('Need accepted V15 Chair model '+name)
 parts=[]
 for it in ET.parse(p).getroot().iter('Item'):
  if it.get('class') not in ['Part','Seat']:continue
  pr=it.find('Properties');cf=pr.find("CoordinateFrame[@name='CFrame']");sz=pr.find("Vector3[@name='size']")
  if cf is None:continue
  parts.append(dict(name=pr.findtext("string[@name='Name']"),p=tuple(float(cf.findtext(k)) for k in 'XYZ'),s=tuple(float(sz.findtext(k)) for k in 'XYZ'),r=tuple(float(cf.findtext('R'+str(i)+str(j))) for i in range(3) for j in range(3))))
 pairs=[(a['name'],b['name']) for a in ASSETS['VipChair']['parts'] for b in parts if sat(a,b)]
 assert not pairs,pairs
 report[style]={'pairsTested':len(ASSETS['VipChair']['parts'])*len(parts),'overlaps':0,'checks':'PASS'}
 print(style,pairs)

(ROOT/'STYLE_COMPATIBILITY.json').write_text(json.dumps(report,indent=2))
