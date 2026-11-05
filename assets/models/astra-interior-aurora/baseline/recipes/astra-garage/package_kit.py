from pathlib import Path
import json, subprocess, xml.etree.ElementTree as E, math
from build_kit import *
ROJO='/Users/erland/.local/gst-tools/rojo'
# Optional matching roof for compact assembled scene; 60-stud version is models/GarageRoof.
export(scaled(ASSETS['GarageRoof'],.75),ROOT/'Garage_Roof_Optional.rbxmx')
report=[]
files=sorted((ROOT/'models').glob('*.rbxmx'))+[ROOT/'Garage_Assembled.rbxmx',ROOT/'Garage_Roof_Optional.rbxmx',ROOT/'Upgrades_Import.rbxmx']
for f in files:
 tree=E.parse(f);items=list(tree.iter('Item'));ids={n.attrib['referent'] for n in items};assert len(ids)==len(items)
 count=0
 for it in items:
  cls=it.attrib['class'];pr=it.find('Properties')
  assert cls in ('Model','Part','Seat','PointLight'),(f,cls)
  if cls=='Model':
   ref=pr.find('Ref[@name="PrimaryPart"]');assert ref is not None and ref.text in ids
  if cls in ('Part','Seat'):
   count+=1;assert pr.find('bool[@name="Anchored"]').text=='true'
   sz=[float(pr.find('Vector3[@name="size"]/'+k).text) for k in 'XYZ'];assert all(.001<=t<=2048 for t in sz)
   cf=pr.find('CoordinateFrame[@name="CFrame"]');r=[float(cf.find(f'R{i}{j}').text) for i in range(3) for j in range(3)]
   for i in range(3):
    for j in range(3):assert abs(sum(r[i*3+k]*r[j*3+k] for k in range(3))-(1 if i==j else 0))<1e-5
  if cls=='Seat':assert pr.find('bool[@name="CanTouch"]').text=='true'
 project=ROOT/'source'/'convert.project.json'
 project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f)}}))
 binary=f.with_suffix('.rbxm')
 run=subprocess.run([ROJO,'build',str(project),'-o',str(binary)],capture_output=True,text=True)
 assert run.returncode==0,(f,run.stderr)
 report.append({'file':str(binary.relative_to(ROOT)),'partsIncludingPivots':count,'bytes':binary.stat().st_size,'rojoReadAndBuild':'passed'})
# A complete place that opens directly; functional scene with spawn and warm lighting.
showcase={'name':'Astra Garage Showcase','tree':{'$className':'DataModel','Workspace':{'$className':'Workspace','Garage':{'$path':'../Garage_Assembled.rbxmx'},'Spawn':{'$className':'SpawnLocation','$properties':{'Anchored':True,'Neutral':True,'Transparency':1,'CanCollide':False,'Size':[4,.1,4],'Position':[0,.3,20]}}},'Lighting':{'$className':'Lighting','$properties':{'Brightness':2,'ClockTime':15,'Ambient':[.48,.43,.39],'OutdoorAmbient':[.57,.6,.66],'EnvironmentDiffuseScale':1,'EnvironmentSpecularScale':.6,'GlobalShadows':True}}}}
project=ROOT/'source'/'showcase.project.json';project.write_text(json.dumps(showcase,indent=2))
r=subprocess.run([ROJO,'build',str(project),'-o',str(ROOT/'Garage_Showcase.rbxl')],capture_output=True,text=True)
assert r.returncode==0,r.stderr
# Canonicalize XML place too, from same known-good project.
r=subprocess.run([ROJO,'build',str(project),'-o',str(ROOT/'Garage_Showcase.rbxlx')],capture_output=True,text=True);assert r.returncode==0,r.stderr
(ROOT/'source'/'convert.project.json').unlink()
(ROOT/'VALIDATION.json').write_text(json.dumps({'status':'passed','tool':'Rojo 7.4.4','checks':['All model XML parsed by Roblox-aware Rojo serializer','All parts anchored; transforms orthonormal; dimensions positive','All model PrimaryPart references resolve','All seats touch-enabled','No scripts or external meshes/textures','Binary RBXM generated for every model','Binary RBXL showcase generated'],'limitation':'Not opened or play-tested in Roblox Studio on this machine. Performance and seating require final Studio check.','files':report},indent=2))
print('Validated and built',len(files),'model files and showcase place')
