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
def glasses():
 m=model('WriterGlasses')
 # Clear open lenses, each frame is a tiled rectangle (no opaque face panel).
 for sign in [-1,1]:
  x=sign*.30
  for yy in [-.20,.20]:box(m,'FrameHorizontal',(x,yy,-.645),(.48,.07,.10),'492D40')
  for xx in [-.205,.205]:box(m,'FrameVertical',(x+xx,0,-.645),(.07,.33,.10),'492D40')
  for yy in [-.13,.13]:box(m,'CornerAccent',(x+sign*.205,yy,-.707),(.07,.05,.024),'DCAD66')
  box(m,'Temple',(sign*.57,0,-.26),(.06,.07,.67),'492D40')
  box(m,'TempleTip',(sign*.57,-.04,.12),(.06,.15,.09),'D49A64')
 box(m,'Bridge',(0,.035,-.645),(.12,.07,.10),'DCAD66')
 return m
def backpack():
 m=model('InternBackpack')
 box(m,'BagBody',(0,0,.84),(1.12,1.18,.38),'287D80')
 # Flat layers meet; contrast stitched seam strips on rear face +Z.
 box(m,'Lid',(0,.68,.84),(1.12,.18,.38),'47A6A2')
 for sign in [-1,1]:
  box(m,'SidePocket',(sign*.65,-.21,.84),(.18,.54,.38),'225E68')
  box(m,'PocketLid',(sign*.65,.10,.84),(.18,.08,.38),'E8BA72')
 # Rear pouch is in front of body along outward +Z.
 box(m,'FrontPouch',(0,-.22,1.15),(.84,.56,.24),'E8BA72')
 box(m,'PouchFlap',(0,.115,1.15),(.84,.11,.24),'F2D5A1')
 box(m,'Zipper',(0,.045,1.28),(.60,.025,.02),'283345')
 box(m,'PullTab',(.26,-.005,1.28),(.06,.075,.02),'B6C6CE')
 # Abstract badge: small square and vertical stripe; no text.
 box(m,'Badge',(0,-.27,1.29),(.23,.23,.04),'F3E8D1')
 box(m,'BadgeMark',(0,-.27,1.32),(.08,.12,.02),'287D80')
 # Carry handle: three disjoint/touching beams.
 for sign in [-1,1]:box(m,'HandleStem',(sign*.23,.87,.84),(.07,.20,.09),'283345')
 box(m,'HandleTop',(0,.995,.84),(.53,.05,.09),'283345')
 # Straps on torso-facing side, parallel tiles avoid interpenetration.
 for sign in [-1,1]:
  box(m,'ShoulderStrap',(sign*.36,0,.605),(.15,1.12,.09),'283345')
  box(m,'StrapBuckle',(sign*.36,-.38,.545),(.19,.16,.03),'B6C6CE')
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
  preview(view,ROOT/'previews'/(skin+'_'+label+'.png'),yaw=angle,elev=15,target=(0,.10,.20),span=2.8,W=700,H=700)
 return {'skin':skin,'partsIncludingHandle':len(allp),'attachment':attachment,'visiblePairChecks':len(cert),'intersections':len(bad),'rigidWelds':len(allp)-1,'runtimeTested':False}
rows=[]
for skin,m,a in [('hoodie_coder',headset('CoderHeadphones','3D7BFF'),'HatAttachment'),('sound_nerd',headset('StudioHeadphones','E8BA72',True),'HatAttachment'),('writer',glasses(),'HatAttachment'),('intern',backpack(),'BodyBackAttachment')]:
 rows.append(export_accessory(m,skin,a))
(ROOT/'VALIDATION.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=2))
