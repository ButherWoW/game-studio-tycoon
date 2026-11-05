from build_styles import *
from render_geometry import preview
from PIL import Image,ImageDraw
import hashlib

def functional(e):
 p=e.find('Properties');n=val(p,'string','Name','');return e.get('class')=='Seat' or n.startswith('BlueSeat') or n=='SeatCushion'
def signature(e):
 p=e.find('Properties');return {'class':e.get('class'),'name':val(p,'string','Name'),'frame':readframe(p),'size':readvec(p,'size')}

def validate():
 summary={};allchecks=[]
 for zone,names in ZONES.items():
  for style in STYLES:
   batch=ROOT;report={'sourceCommit':MANIFEST['sourceCommit'],'zone':zone,'style':style,'studioTested':False,'models':{}}
   for name in names:
    base=ET.parse(ROOT/'baseline/models'/f'{name}.rbxmx').getroot();path=batch/'models'/f'{name}_{style}.rbxmx';var=ET.parse(path).getroot();bp=native_parts(base);vp=native_parts(var)
    assert len(vp)<=int(len(bp)*1.2+1e-6),(name,style,len(bp),len(vp))
    assert len(vp)>len(bp),(name,style,'no geometric design change')
    base_solids=[p for p in fromxml(base) if p['alpha']<.99 or protect(p)];new_parts=fromxml(var)[len(bp):]
    from itertools import combinations
    new_base_hits=[(a['name'],b['name']) for a in new_parts for b in base_solids if sat(a,b)]
    new_new_hits=[(a['name'],b['name']) for a,b in combinations(new_parts,2) if sat(a,b)]
    assert not new_base_hits,(name,style,'new/base OBB collisions',new_base_hits)
    assert not new_new_hits,(name,style,'new/new OBB collisions',new_new_hits)
    assert {e.get('class') for e in var.iter('Item')}<={'Model','Part','Seat','PointLight','SpotLight','SurfaceLight'},(name,'classes')
    for a,b in zip(bp,vp):assert signature(a)==signature(b),(name,style,'original geometry moved')
    semantic_count=0
    for a,b in zip(bp,vp):
     pa,pb=parsepart(a),parsepart(b)
     if preserve_content(name,pa):
      assert pa['c']==pb['c'] and pa['mat']==pb['mat'],(name,style,pa['name'],'art/semantic content changed')
      semantic_count+=1
    # Actual functional native classes/properties, not a name-only count.
    fa=[e for e in bp if functional(e)];fv=[e for e in vp if functional(e)];assert [signature(e) for e in fa]==[signature(e) for e in fv]
    for a,b in zip(fa,fv):
     for propname in ['Disabled','CanCollide','CanTouch','CanQuery']:
      assert a.findtext(f"Properties/bool[@name='{propname}']")==b.findtext(f"Properties/bool[@name='{propname}']")
    bm=base.find("./Item[@class='Model']/Properties");vm=var.find("./Item[@class='Model']/Properties");assert bm.findtext("Ref[@name='PrimaryPart']")==vm.findtext("Ref[@name='PrimaryPart']")
    for a,b in zip(bp,vp):
     qa=a.find("Properties/CoordinateFrame[@name='PivotOffset']");qb=b.find("Properties/CoordinateFrame[@name='PivotOffset']");assert (ET.tostring(qa) if qa is not None else None)==(ET.tostring(qb) if qb is not None else None)
    blo,bhi=bounds(fromxml(base));vlo,vhi=bounds(fromxml(var));bd=[bhi[i]-blo[i] for i in range(3)];vd=[vhi[i]-vlo[i] for i in range(3)]
    assert all(abs(bd[i]-vd[i])<=.2+1e-6 for i in range(3)),(name,style,bd,vd)
    assert abs(vlo[1]-blo[1])<1e-6,(name,'base moved')
    lights=[i for i in var.iter('Item') if i.get('class') in ['PointLight','SpotLight','SurfaceLight']];blights=[i for i in base.iter('Item') if i.get('class') in ['PointLight','SpotLight','SurfaceLight']];assert len(lights)==len(blights)
    assert all(l.findtext("Properties/bool[@name='Shadows']")=='false' for l in lights)
    refs=[i.get('referent') for i in var.iter('Item')];assert len(refs)==len(set(refs)),(name,'duplicate refs')
    assert path.with_suffix('.rbxm').read_bytes().startswith(b'<roblox!')
    report['models'][name+'_'+style]={'classicParts':len(bp),'variantParts':len(vp),'addedParts':len(vp)-len(bp),'classicDimensionsXYZ':[round(x,4) for x in bd],'variantDimensionsXYZ':[round(x,4) for x in vd],'functionalParts':len(fa),'preservedArtSemanticParts':semantic_count,'nativeLights':len(lights),'newBaseSAT':{'pairs':len(new_parts)*len(base_solids),'overlaps':len(new_base_hits)},'newNewSAT':{'pairs':len(new_parts)*(len(new_parts)-1)//2,'overlaps':len(new_new_hits)},'satToleranceStuds':.0001,'newPartNames':[p['name'] for p in new_parts],'checks':'PASS'}
   report['checks']=['all original Part class/name/CFrame/size unchanged','native Seat and BlueSeat*/SeatCushion preserved','all original PivotOffsets/PrimaryPart preserved','same shelf-board positions','all original artwork/screen/semantic colors and materials preserved','same monitor/table-top heights','AABB dimension delta<=.2','same lowerY','Part count<=classic+20%','physical design additions present on every model','new/base oriented-bounds SAT zero intersections','new/new oriented-bounds SAT zero intersections','no scripts/mesh/texture','native light count unchanged;Shadows=false','unique referents','Rojo binary builds']
   (batch/'VALIDATION.json').write_text(json.dumps(report,indent=2));summary[batch.name]={'models':len(names),'checks':'PASS'}
 (ROOT/'SUMMARY.json').write_text(json.dumps({'sourceCommit':MANIFEST['sourceCommit'],'batches':summary,'modelCount':len(names),'studioTested':False},indent=2));print('Batch structural checks PASS',flush=True)

def renders():
 cache={}
 for zone,names in ZONES.items():
  for name in names:
   ps=fromxml(ET.parse(ROOT/'baseline/models'/f'{name}.rbxmx').getroot());lo,hi=bounds(ps);dims=[hi[i]-lo[i] for i in range(3)];target=((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,(lo[2]+hi[2])/2);span=max(dims[0],dims[1],dims[2])*1.9
   dest=ROOT/'previews'/f'{name}_Classic.png';preview(ps,dest,yaw=23,elev=22,span=span,target=target,W=700,H=520);cache[name]=(target,span,dest)
  for style in STYLES:
   batch=ROOT;pre=batch/'previews';pre.mkdir(exist_ok=True);sheet=Image.new('RGB',(1400,len(names)*560),'#ece6dd');draw=ImageDraw.Draw(sheet)
   for i,name in enumerate(names):
    target,span,classic=cache[name];ps=fromxml(ET.parse(batch/'models'/f'{name}_{style}.rbxmx').getroot());dest=pre/f'{name}_{style}.png';preview(ps,dest,yaw=23,elev=22,span=span,target=target,W=700,H=520)
    y=i*560;sheet.paste(Image.open(classic),(0,y+30));sheet.paste(Image.open(dest),(700,y+30));draw.text((25,y+10),name+' Classic',fill='#283345');draw.text((725,y+10),name+'_'+style,fill='#283345')
   sheet.save(batch/'Classic_vs_Style.png');print(batch.name,'comparison sheet done',flush=True)

def readmes():
 for zone,names in ZONES.items():
  for style in STYLES:
   batch=ROOT;report=json.loads((batch/'VALIDATION.json').read_text());rows='\n'.join('| '+n+'_'+style+' | '+str(r['classicParts'])+' → '+str(r['variantParts'])+' | '+' × '.join(str(x) for x in r['variantDimensionsXYZ'])+' |' for n,r in [(name,report['models'][name+'_'+style]) for name in names])
   (batch/'README.md').write_text(f'''# V15 {zone} — {style}\n\n{len(names)} native furniture variants with suffix _{style}. Exact accepted classic XML snapshot commit `{MANIFEST['sourceCommit']}` is the baseline; original classics are untouched.\n\n| Model | Classic → variant Parts | Width × height × depth |\n|---|---:|---|\n{rows}\n\nImport one format per model into ServerStorage.Upgrades. Both RBXM and RBXMX are provided. Game style-switch code must select exact suffix names; no gameplay code is included. Pivots, original Part names/classes/sizes/transforms, PcSeat Seat instances, BlueSeat*/SeatCushion, shelf boards, monitor and desktop heights are preserved. NeonSign and PendantLamp retain their original wall/ceiling pivot exceptions. Original artwork, canvas/background panels, screen miniatures, server status colors, hot/cold tap levers and colored control keys retain both classic Color and Material. Only frames, bodies and new trim take the selected style. Each native light remains in its original location with Shadows=false; no new lights.\n\nStyle uses materials and new physical geometry: Neon adds cyan/violet luminous edge rails/status inlays on dark metal; Cozy adds warm wood, textile bindings and soft end pads; Minimal adds pale oak inset panels with rounded white caps. Detail count adapts to each base object's20% budget. Complete-base and new/new OBB SAT resolves placement on exposed surfaces; monitors use top bezel caps above the UI, not screen-covering overlays. Some complex silhouettes use a single safe exterior binding instead of multiple overlapping patches. These are exterior trim Parts beside existing surfaces; they have no solid overlap with the base or each other and are noncolliding.\n\nVALIDATION.json checks all original transforms/functionality, bounds within±0.2stud, exact baseY, unchanged pivot, native class allowlist, lighting and counts. Every new/base and new/new oriented-bounds pair is tested with SAT (0.0001stud numerical tolerance); per-model pair counts and zero-overlap results are recorded. Classic_vs_Style.png compares actual exported geometry with classic in the same camera; individual variant renders are in previews/. Source snapshots and standalone generator/renderer are included in this kit. No scripts, external meshes, textures or brands.\n\nNo Studio/runtime test performed. Verify actual Humanoid seating, style swapping, inherited interactions and lighting/FPS on phone. This kit intentionally preserves any preexisting classic geometry quirks rather than moving working parts to conceal them.\n''')
if __name__=='__main__':
 validate();renders();readmes()
