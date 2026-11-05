"""Original builder R15, classic-clothing SVG and native hardhat."""
from geometry import *
import subprocess,copy
TORSO={'R':(165,74,64,128),'F':(231,74,128,128),'L':(361,74,64,128),'B':(427,74,128,128),'U':(231,8,128,64),'D':(231,204,128,64)}
RIGHT={'L':(19,355,64,128),'B':(85,355,64,128),'R':(151,355,64,128),'F':(217,355,64,128),'U':(217,289,64,64),'D':(217,485,64,64)}
LEFT={'F':(308,355,64,128),'L':(374,355,64,128),'B':(440,355,64,128),'R':(506,355,64,128),'U':(308,289,64,64),'D':(308,485,64,64)}
def rect(x,y,w,h,c):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{c}"/>'
def path(d,c):return f'<path d="{d}" fill="{c}"/>'
def clothing(pants=False):
 out=['<svg xmlns="http://www.w3.org/2000/svg" width="585" height="559" viewBox="0 0 585 559">']
 for region,areas in [('torso',TORSO),('right',RIGHT),('left',LEFT)]:
  for face,(x,y,w,h) in areas.items():
   s=rect(0,0,w,h,'#24344D' if pants else '#314A68')
   if face in ['R','L','B','F']:
    if pants:
     if region=='torso':s+=rect(0,109,w,19,'#182437')
     else:
      s+=rect(0,104,w,24,'#172132')+rect(0,123,w,5,'#4C5868')
      if face in ['R','L']:s+=rect(w/2-2,0,4,104,'#3C4B61')
      if face=='F':s+=rect(5,15,w-10,27,'#33445C')+rect(8,19,w-16,3,'#56657A')
    else:
     if region=='torso':
      s=rect(0,0,w,h,'#F18A32')
      s+=rect(0,77,w,12,'#F9F5C9')+rect(0,81,w,4,'#BCC8CF')
      s+=rect(0,112,w,12,'#F9F5C9')+rect(0,116,w,4,'#BCC8CF')
      if face=='F':
       s+=path('M44 0 H84 L72 33 H56 Z','#314A68')+rect(61,30,6,98,'#98522B')
       for xx in [18,97]:s+=rect(xx,0,12,77,'#F9F5C9')+rect(xx+4,0,4,77,'#BCC8CF')
       for xx in [8,80]:s+=rect(xx,92,38,17,'#D06B28')
      elif face=='B':
       for xx in [18,w-30]:s+=rect(xx,0,12,77,'#F9F5C9')+rect(xx+4,0,4,77,'#BCC8CF')
     else:s+=rect(0,88,w,40,'#D8A576') # bare forearm/hand printed neutral skin; sleeve boundary wraps
   out+=[f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',s,'</svg>']
 out+=['</svg>'];return ''.join(out)

def accessories(row=None):
 m=model('BuilderHat');m['attachment']=('HatAttachment',(0,-.06,0))
 cyl(m,'Handle',(0,0,0),.12,1.5,'FFC93C')
 box(m,'Crown',(0,.27,0),(1.22,.42,1.1),'FFC93C')
 box(m,'Ridge',(0,.53,0),(.16,.10,.8),'FFD970')
 return [m]

def hat_export(out):
 from geometry import write_part
 m=accessories()[0];r=ET.Element('roblox',{'version':'4'});a=ET.SubElement(r,'Item',{'class':'Accessory','referent':'HAT'});pr=ET.SubElement(a,'Properties');prop(pr,'string','Name','BuilderHat')
 for n,p in enumerate(m['parts']):
  node=write_part(copy.deepcopy(p),a,f'H{n}');ps=node.find('Properties');ps.find("bool[@name='Anchored']").text='false';prop(ps,'bool','Massless','true')
  if n==0:
   at=ET.SubElement(node,'Item',{'class':'Attachment','referent':'HATATT'});ap=ET.SubElement(at,'Properties');prop(ap,'string','Name','HatAttachment');frame(ap,'CFrame',(0,-.06,0))
  else:
   wl=ET.SubElement(node,'Item',{'class':'WeldConstraint','referent':f'HW{n}'});wp=ET.SubElement(wl,'Properties');prop(wp,'string','Name','RigidWeld');prop(wp,'Ref','Part0','H0');prop(wp,'Ref','Part1',f'H{n}');prop(wp,'bool','Enabled','true')
 ET.ElementTree(r).write(out,encoding='utf-8',xml_declaration=True)

def rig_export(out):
 from geometry import write_part
 root=ET.Element('roblox',{'version':'4'});m=ET.SubElement(root,'Item',{'class':'Model','referent':'BUILDER'});pr=ET.SubElement(m,'Properties');prop(pr,'string','Name','BuilderNPC');prop(pr,'Ref','PrimaryPart','B_HumanoidRootPart')
 # NPC pivot intentionally root-centred: ConstructionService adds StandHeight to root pivot.
 specs=[('HumanoidRootPart',(0,3,0),(2,2,1),'D8A576',1),('UpperTorso',(0,3.25,0),(2,1.5,1),'F18A32',0),('LowerTorso',(0,2.25,0),(2,.5,1),'24344D',0),('Head',(0,4.6,0),(1.18,1.2,1.05),'D8A576',0)]
 for side,sgn in [('Right',-1),('Left',1)]:
  specs += [(side+'UpperArm',(sgn*1.55,3.56,0),(1,.88,.99),'314A68',0),(side+'LowerArm',(sgn*1.55,2.68,0),(1,.88,.99),'D8A576',0),(side+'Hand',(sgn*1.55,2.12,0),(1,.24,.99),'D8A576',0),(side+'UpperLeg',(sgn*.53,1.55,0),(.99,.9,.99),'24344D',0),(side+'LowerLeg',(sgn*.53,.69,0),(.99,.82,.99),'24344D',0),(side+'Foot',(sgn*.53,.14,-.05),(.99,.28,1.09),'172132',0)]
 nodes={};positions={}
 for name,p,s,c,alpha in specs:
  mm=model('temp');pp=box(mm,name,p,s,c,alpha=alpha);node=write_part(pp,m,'B_'+name);nodes[name]=node;positions[name]=p;ps=node.find('Properties');ps.find("bool[@name='Anchored']").text='true' if name=='HumanoidRootPart' else 'false';prop(ps,'bool','Massless','true')
 def attach(part,name,pos):
  a=ET.SubElement(nodes[part],'Item',{'class':'Attachment','referent':'A_'+name});ap=ET.SubElement(a,'Properties');prop(ap,'string','Name',name);frame(ap,'CFrame',pos)
 attach('Head','HatAttachment',(0,.6,0));attach('Head','FaceFrontAttachment',(0,0,-.525));attach('RightHand','RightGripAttachment',(0,-.12,0));attach('LeftHand','LeftGripAttachment',(0,-.12,0));attach('UpperTorso','BodyFrontAttachment',(0,0,-.5));attach('UpperTorso','BodyBackAttachment',(0,0,.5))
 joints=[('Root','HumanoidRootPart','LowerTorso',(0,2.25,0)),('Waist','LowerTorso','UpperTorso',(0,2.5,0)),('Neck','UpperTorso','Head',(0,4,0))]
 for side,sgn in [('Right',-1),('Left',1)]:joints += [(side+'Shoulder','UpperTorso',side+'UpperArm',(sgn*1.05,3.8,0)),(side+'Elbow',side+'UpperArm',side+'LowerArm',(sgn*1.55,3.12,0)),(side+'Wrist',side+'LowerArm',side+'Hand',(sgn*1.55,2.24,0)),(side+'Hip','LowerTorso',side+'UpperLeg',(sgn*.53,2,0)),(side+'Knee',side+'UpperLeg',side+'LowerLeg',(sgn*.53,1.1,0)),(side+'Ankle',side+'LowerLeg',side+'Foot',(sgn*.53,.28,0))]
 for name,a,b,pivot in joints:
  j=ET.SubElement(nodes[a],'Item',{'class':'Motor6D','referent':'J_'+name});jp=ET.SubElement(j,'Properties');prop(jp,'string','Name',name);prop(jp,'Ref','Part0','B_'+a);prop(jp,'Ref','Part1','B_'+b);frame(jp,'C0',tuple(pivot[i]-positions[a][i] for i in range(3)));frame(jp,'C1',tuple(pivot[i]-positions[b][i] for i in range(3)));frame(jp,'Transform');prop(jp,'bool','Enabled','true')
 # Original face primitives welded to head; no external Decal.
 for n,(x,y,w,h) in enumerate([(-.25,4.66,.08,.16),(.25,4.66,.08,.16),(0,4.38,.31,.055)]):
  mm=model('temp');pp=box(mm,'FaceMark'+str(n),(x,y,-.539),(w,h,.025),'282A35');node=write_part(pp,m,'F'+str(n));ps=node.find('Properties');ps.find("bool[@name='Anchored']").text='false';prop(ps,'bool','Massless','true');wl=ET.SubElement(node,'Item',{'class':'WeldConstraint','referent':'FW'+str(n)});wp=ET.SubElement(wl,'Properties');prop(wp,'string','Name','FaceWeld');prop(wp,'Ref','Part0','B_Head');prop(wp,'Ref','Part1','F'+str(n));prop(wp,'bool','Enabled','true')
 hu=ET.SubElement(m,'Item',{'class':'Humanoid','referent':'HUM'});hp=ET.SubElement(hu,'Properties');prop(hp,'string','Name','Humanoid');prop(hp,'token','RigType',1);prop(hp,'float','HipHeight',2);prop(hp,'bool','RequiresNeck','true');prop(hp,'bool','BreakJointsOnDeath','false');prop(hp,'float','WalkSpeed',0);prop(hp,'float','Health',100);prop(hp,'float','MaxHealth',100)
 for cls,field in [('Shirt','ShirtTemplate'),('Pants','PantsTemplate')]:
  item=ET.SubElement(m,'Item',{'class':cls,'referent':cls.upper()});pp=ET.SubElement(item,'Properties');prop(pp,'string','Name',cls);content=ET.SubElement(pp,'Content',{'name':field});ET.SubElement(content,'null')
 ET.ElementTree(root).write(out,encoding='utf-8',xml_declaration=True)

if __name__=='__main__':
 for n,v in [('shirt',False),('pants',True)]: (ROOT/'source-svg'/f'builder_{n}.svg').write_text(clothing(v))
 hat_export(ROOT/'BuilderHat.rbxmx');rig_export(ROOT/'BuilderNPC.rbxmx')
 (ROOT/'UV_MAP.json').write_text(json.dumps({'torso':TORSO,'right':RIGHT,'left':LEFT},indent=2)+'\n');(ROOT/'hat-manifest.json').write_text(json.dumps(accessories()[0],indent=2)+'\n')
 for n in ['BuilderHat','BuilderNPC']:
  pr=ROOT/'source'/'convert.project.json';pr.write_text(json.dumps({'name':n,'tree':{'$path':str(ROOT/(n+'.rbxmx'))}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(ROOT/(n+'.rbxm'))],check=True)
 pr.unlink()
