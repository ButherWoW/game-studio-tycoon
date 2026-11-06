from geometry import *
from render_geometry import preview
from convex_support import parse,audit
import subprocess,hashlib
ROOT=Path(__file__).resolve().parents[1]
for folder in ['models','previews']: (ROOT/folder).mkdir(exist_ok=True)
def export_accessory(m,skin,attachment):
 root=ET.Element('roblox',{'version':'4'})
 outer=ET.SubElement(root,'Item',{'class':'Model','referent':'ROOT'});pr=ET.SubElement(outer,'Properties');prop(pr,'string','Name','skin_'+skin+'_acc');prop(pr,'Ref','PrimaryPart','HANDLE')
 acc=ET.SubElement(outer,'Item',{'class':'Accessory','referent':'ACCESSORY'});pr=ET.SubElement(acc,'Properties');prop(pr,'string','Name',m['name'])
 h=dict(name='Handle',p=(0,0,0),s=(.05,.05,.05),c=(0,0,0),shape='box',r=I,mat='SmoothPlastic',collide=False,alpha=1,cls='Part')
 allp=[h]+m['parts']
 for i,p in enumerate(allp):
  ident='HANDLE' if i==0 else 'P'+str(i)
  it=write_part(p,acc,ident);pr=it.find('Properties')
  pr.find("bool[@name='Anchored']").text='false';prop(pr,'bool','Massless','true')
  for flag in ['CanCollide','CanTouch','CanQuery','CastShadow']:pr.find("bool[@name='"+flag+"']").text='false'
  if i==0:
   at=ET.SubElement(it,'Item',{'class':'Attachment','referent':'ATT'});ap=ET.SubElement(at,'Properties');prop(ap,'string','Name',attachment)
   frame(ap,'CFrame',(0,.5,0) if attachment=='HatAttachment' else (0,0,.5))
  else:
   w=ET.SubElement(it,'Item',{'class':'WeldConstraint','referent':'W'+str(i)});wp=ET.SubElement(w,'Properties');prop(wp,'string','Name','RigidWeld');prop(wp,'Ref','Part0','HANDLE');prop(wp,'Ref','Part1',ident);prop(wp,'bool','Enabled','true')
 path=ROOT/'models'/('skin_'+skin+'_acc.rbxmx')
 ET.ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)
 project=ROOT/'source'/'build.project.json';project.write_text(json.dumps({'name':'skin_'+skin+'_acc','tree':{'$path':str(path)}}))
 subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(path.with_suffix('.rbxm'))],check=True,capture_output=True)
 project.unlink()
 ps=[p for p in parse(path) if p['alpha']<.99];cert,bad=audit(ps);assert not bad,(skin,bad);assert len(allp)<=40
 # Preview head/torso is reference only, never exported as accessory.
 view=m['parts'].copy();stand=model('Reference')
 if attachment=='HatAttachment':
  ball(stand,'ReferenceHead',(0,0,.02),(1.0,1.0,1.0),'CBBFB5')
 else:box(stand,'ReferenceTorso',(0,0,.10),(1.5,1.5,.92),'A9AEB7')
 view+=stand['parts']
 # Front Roblox -Z; show front eyewear and side cups. Backpacks viewed from +Z.
 yaw=155 if attachment=='HatAttachment' else 25
 for label,angle in [('ThreeQuarter',yaw),('Front',180 if attachment=='HatAttachment' else 0),('Side',90)]:
  preview(view,ROOT/'previews'/(skin+'_'+label+'.png'),yaw=angle,elev=15,target=(0,.10,.20),span=2.8,W=700,H=700)
 return {'skin':skin,'partsIncludingHandle':len(allp),'attachment':attachment,'visiblePairChecks':len(cert),'intersections':len(bad),'rigidWelds':len(allp)-1,'runtimeTested':False}

def beret():
 m=model('ArtistBeret')
 cyl(m,'SoftRim',(0,.565,0),.09,1.23,'303344')
 ball(m,'SoftCrown',(.04,.71,.01),(1.45,.20,1.30),'7A5099')
 cyl(m,'TopStem',(.10,.855,.02),.09,.10,'303344')
 # Three stitched abstract patches, away from the curved crown.
 for x,col in [(-.22,'F5C75F'),(0,'FF8592'),(.22,'69C1C0')]:
  box(m,'PaintPatch',(x,.565,-.633),(.13,.055,.035),col)
 # Stylus rests beside ear, separate from hat.
 box(m,'Stylus',(.64,.22,-.18),(.055,.48,.055),'E8BA72')
 box(m,'StylusTip',(.64,-.05,-.18),(.055,.06,.055),'303344')
 return m
def cap():
 m=model('RetroCap')
 cyl(m,'SweatBand',(0,.565,0),.09,1.24,'F2C75C')
 ball(m,'CapCrown',(0,.735,0),(1.34,.25,1.26),'E05D69')
 # Backward brim faces +Z; the face remains clear.
 box(m,'BackBrim',(0,.49,.62),(1.06,.06,.58),'3D87B7')
 for x in [-.4,0,.4]:
  box(m,'BrimStitch',(x,.526,.80),(.025,.012,.18),'79CAD4')
 cyl(m,'TopButton',(0,.89,0),.06,.12,'F2C75C')
 for x in [-.38,.38]:
  box(m,'RetroPatch',(x,.565,-.625),(.13,.06,.03),'3D87B7')
 return m
def headband(name,color):
 m=model(name)
 for j in range(20):
  theta=math.radians(j*18)
  part(m,'CurvedBandSegment',(.53*math.cos(theta),.25,.53*math.sin(theta)),(.142,.14,.07),color,r=rot(y=-math.degrees(theta)-90))
 return m
def speed():
 m=headband('RunnerHeadband','E85E65')
 box(m,'FrontBadge',(0,.25,-.585),(.30,.12,.03),'F6E2B3')
 for x in [-.08,.08]:
  box(m,'BadgeStripe',(x,.25,-.607),(.035,.08,.014),'273C55')
 # Two compact loose tails extend behind the knot, not through the head.
 box(m,'Knot',(.30,.25,.57),(.20,.16,.07),'F6E2B3')
 box(m,'TailLong',(.25,.02,.57),(.09,.30,.07),'E85E65')
 box(m,'TailShort',(.36,.075,.57),(.09,.19,.07),'E85E65')
 return m
def lamp():
 m=headband('BugHunterHeadlamp','556C55')
 box(m,'LampMount',(0,.25,-.61),(.20,.14,.08),'303344')
 cyl(m,'LampHousing',(0,.25,-.74),.18,.32,'D8AB5C',r=rot(y=90))
 cyl(m,'Lens',(0,.25,-.85),.04,.26,'A7D7E4',r=rot(y=90))
 cyl(m,'LensInset',(0,.25,-.878),.016,.16,'D7EFF2',r=rot(y=90))
 # Compact battery pack on back, no PointLight.
 box(m,'Battery',(0,.25,.65),(.30,.25,.14),'303344')
 for x in [-.12,.12]:
  box(m,'BatteryLatch',(x,.25,.73),(.04,.17,.02),'D8AB5C')
 return m
rows=[]
for skin,m,a in [('pixel_artist',beret(),'HatAttachment'),('retro_gamer',cap(),'HatAttachment'),('speedrunner',speed(),'HatAttachment'),('bug_hunter',lamp(),'HatAttachment')]:
 rows.append(export_accessory(m,skin,a))
(ROOT/'VALIDATION.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=2))
