from geometry import *
from render_geometry import preview
from convex_support import parse,audit
import subprocess,hashlib
ROOT=Path(__file__).resolve().parents[1]
for folder in ['models','previews']: (ROOT/folder).mkdir(exist_ok=True)
def headset(name,color,studio=False):
 m=model(name)
 # Segmented U band, shared faces only; open space accommodates the head.
 for j in range(1,11):
  theta=math.radians(7.5+15*j)
  # Deliberately articulated arch with narrow manufacturing joints.
  part(m,'ArcSegment',(math.cos(theta)*.62,math.sin(theta)*.62,0),(.142,.075,.23),color,r=rot(z=math.degrees(theta)+90))
 for side in [-1,1]:
  
  box(m,'Slider',(side*.58,-.06,0),(.08,.12,.23),'B9C4CE')
  # Ear cushions/cups are concentric cylinders on the X axis, touching faces.
  cyl(m,'Cushion',(side*.68,-.17,0),.08,.59,'202638',r=I)
  cyl(m,'Housing',(side*.80,-.17,0),.16,.69,'303C52',r=I)
  cyl(m,'AccentRim',(side*.90,-.17,0),.04,.61,color,r=I)
  cyl(m,'OuterCap',(side*.94,-.17,0),.04,.48,'182030',r=I)
  # Buttons mounted on external cap, with separate centers.
  for y in [-.10,.10]:
   box(m,'Control',(side*.97,-.17+y,0),(.02,.06,.08),'D9E0EB')
  if studio:
   for z in [-.16,-.08,0,.08,.16]:
    box(m,'Grille',(side*.986,-.18,z),(.012,.19,.025),'768397')
 # Top contrasting cushion below horizontal band, not inside it.
 box(m,'TopPad',(0,.515,0),(.36,.07,.22),'202638')
 return m
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
  preview(view,ROOT/'previews'/(skin+'_'+label+'.png'),yaw=angle,elev=15,target=(0,.45,.20) if skin=='wizard_dev' else (0,.10,.20),span=3.4 if skin=='wizard_dev' else 2.8,W=700,H=700)
 return {'skin':skin,'partsIncludingHandle':len(allp),'attachment':attachment,'visiblePairChecks':len(cert),'intersections':len(bad),'rigidWelds':len(allp)-1,'runtimeTested':False}

def neonphones():
 m=headset('NeonCatHeadphones','7955DA')
 for p in m['parts']:
  if p['name'] in ['ArcSegment','AccentRim']:p['mat']='Neon';p['c']=rgb('A579FF')
 # Two triangular ears assembled from mirrored native wedge halves.
 for sign in [-1,1]:
  center=sign*.30
  part(m,'EarLeft',(center-.075,.83,0),(.15,.36,.15),'7955DA',shape='wedge',r=rot(y=90),cls='WedgePart')
  part(m,'EarRight',(center+.075,.83,0),(.15,.36,.15),'FF73C6',shape='wedge',r=rot(y=-90),cls='WedgePart',mat='Neon')
 return m
def visor():
 m=model('CyberVisor')
 box(m,'TintedVisor',(0,.02,-.655),(1.08,.28,.08),'35D7ED',alpha=.35,mat='Glass')
 for y in [-.17,.21]:
  box(m,'FrameRail',(0,y,-.655),(1.20,.10,.10),'23364C')
  box(m,'GlowRail',(0,y,-.716),(1.0,.035,.022),'31E3E6',mat='Neon')
 for sign in [-1,1]:
  box(m,'EndCap',(sign*.595,.02,-.655),(.11,.28,.10),'23364C')
  box(m,'Temple',(sign*.67,.02,-.25),(.04,.09,.71),'23364C')
  box(m,'Processor',(sign*.72,.02,.02),(.06,.24,.20),'7955DA')
  for y in [-.05,.05]:box(m,'ProcessorLed',(sign*.76,y,.02),(.02,.025,.12),'31E3E6',mat='Neon')
 return m
def helmet():
 m=model('SpaceAquariumHelmet')
 ball(m,'GlassDome',(0,.02,0),(1.60,1.60,1.60),'A4D9E9',alpha=.72,mat='Glass')
 cyl(m,'NeckSeal',(0,-.82,0),.08,.96,'303C52')
 cyl(m,'NeckCollar',(0,-.92,0),.12,1.15,'F0F0E9')
 for sign in [-1,1]:
  cyl(m,'SideModule',(sign*.86,.02,0),.12,.42,'F0F0E9',r=I)
  cyl(m,'ModuleGlow',(sign*.94,.02,0),.04,.32,'57DDE9',r=I,mat='Neon')
  cyl(m,'ModuleCap',(sign*.98,.02,0),.04,.22,'303C52',r=I)
 # Top antenna is above transparent dome; no script/light.
 box(m,'AntennaBase',(.24,.855,0),(.12,.07,.12),'F0F0E9')
 box(m,'Antenna',(.24,1.00,0),(.04,.22,.04),'303C52')
 ball(m,'AntennaTip',(.24,1.15,0),(.08,.08,.08),'57DDE9',mat='Neon')
 return m
def wizard():
 m=model('CodeWizardHat')
 cyl(m,'WideBrim',(0,.56,0),.10,1.62,'35335C')
 # Stepped octagonal/conical silhouette built from cylinders, shared faces only.
 for j,(diam,h) in enumerate([(1.12,.20),(.92,.20),(.72,.20),(.52,.20),(.32,.20),(.12,.16)]):
  bottom=.61+j*.20
  cyl(m,'CrownTier',(0,bottom+h/2,0),h,diam,'4D467B')
 # Broad band covers front without intersecting tier.
 box(m,'HatBand',(0,.70,-.58),(.55,.12,.04),'9C77E9',mat='Neon')
 box(m,'StarBadge',(0,.715,-.615),(.13,.13,.03),'F9CF69',r=rot(z=45),mat='Neon')
 # Two gold pin-like symbols on brim, no text.
 for sign in [-1,1]:
  box(m,'BrimCharm',(sign*.64,.63,0),(.10,.04,.10),'F9CF69',r=rot(y=45))
 return m
rows=[]
for skin,m,a in [('neon_streamer',neonphones(),'HatAttachment'),('cyber_dev',visor(),'HatAttachment'),('space_dev',helmet(),'HatAttachment'),('wizard_dev',wizard(),'HatAttachment')]:
 rows.append(export_accessory(m,skin,a))
(ROOT/'VALIDATION.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=2))
