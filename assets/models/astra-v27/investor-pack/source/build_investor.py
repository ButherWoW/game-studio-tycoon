"""Original SVG classic-clothing panels and native InvestorCase. No ImageGen."""
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
   base='#29354E' if not pants else '#253048'
   if face in ['R','L']:base='#253048' if not pants else '#212C40'
   if face=='B':base='#253149' if not pants else '#202A3D'
   s=rect(0,0,w,h,base)
   if face in ['F','B','R','L']:
    if pants:
     if region=='torso':s+=rect(0,113,w,15,'#182137')+rect(0,111,w,2,'#586682')
     else:
      s+=rect(0,106,w,22,'#192238')+rect(0,124,w,4,'#C4CAD4')
      if face=='F':s+=rect(w/2-1,6,2,96,'#44516C')
    else:
     if region=='torso':
      s+=rect(0,119,w,9,'#202B41')
      if face=='F':
       s+=path('M33 0 H95 L82 69 H46 Z','#F7F7EE')
       s+=path('M32 0 L46 0 L61 65 L42 86 L22 28 L36 25 Z','#485471')
       s+=path('M96 0 L82 0 L67 65 L86 86 L106 28 L92 25 Z','#485471')
       s+=path('M46 0 L64 13 L55 25 L36 0 Z','#FFFFFF')+path('M82 0 L64 13 L73 25 L92 0 Z','#FFFFFF')
       s+=path('M44 17 L61 24 L44 31 Z','#FFC93C')+path('M84 17 L67 24 L84 31 Z','#FFC93C')+rect(61,21,6,7,'#D89C2B')
       s+=rect(17,54,20,3,'#FFC93C')+rect(61,83,6,6,'#FFC93C')+rect(61,103,6,6,'#FFC93C')
      if face=='B':s+=rect(w/2-1,10,2,108,'#3C4862')
     else:
      s+=rect(0,109,w,12,'#F7F7EE')+rect(0,121,w,7,'#202B41')
      if face=='F':s+=rect(w-13,112,5,5,'#FFC93C')
   out+=[f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',s,'</svg>']
 out+=['</svg>'];return ''.join(out)

def accessories(row=None):
 m=model('InvestorCase');m['attachment']=('RightGripAttachment',(.5,0,0))
 box(m,'Handle',(0,0,-.27),(.8,.12,.08),'315BD3')
 for x in [-.35,.35]:box(m,'HandleSupport',(x,-.14,-.27),(.10,.16,.08),'315BD3')
 box(m,'CaseBase',(0,-.9,0),(1.44,.12,.62),'202B48')
 for x in [-.67,.67]:box(m,'CaseSide',(x,-.53,0),(.1,.62,.62),'315BD3')
 for z in [-.25,.25]:box(m,'CaseWall',(0,-.53,z),(1.24,.62,.12),'315BD3')
 # Decorative latch mounts on front face, touching rather than sinking into wall.
 for x in [-.42,.42]:box(m,'GoldLatch',(x,-.39,-.33),(.17,.16,.04),'FFC93C')
 # Tall cylindrical coin stacks rest on the bottom; rings sit above upper rim.
 for x in [-.29,.29]:
  cyl(m,'CoinStack',(x,-.51,0),.66,.32,'EAB437')
  cyl(m,'CoinTop',(x,-.16,0),.04,.34,'FFC93C')
 return [m]

def export_accessory(out):
 from geometry import write_part
 m=accessories()[0];root=ET.Element('roblox',{'version':'4'});ac=ET.SubElement(root,'Item',{'class':'Accessory','referent':'AC'});pr=ET.SubElement(ac,'Properties');prop(pr,'string','Name','InvestorCase')
 for n,p in enumerate(m['parts']):
  node=write_part(copy.deepcopy(p),ac,f'P{n}');ps=node.find('Properties');ps.find("bool[@name='Anchored']").text='false';prop(ps,'bool','Massless','true')
  if n==0:
   at=ET.SubElement(node,'Item',{'class':'Attachment','referent':'ATT'});ap=ET.SubElement(at,'Properties');prop(ap,'string','Name',m['attachment'][0]);frame(ap,'CFrame',m['attachment'][1])
  else:
   wl=ET.SubElement(node,'Item',{'class':'WeldConstraint','referent':f'W{n}'});wp=ET.SubElement(wl,'Properties');prop(wp,'string','Name','RigidWeld');prop(wp,'Ref','Part0','P0');prop(wp,'Ref','Part1',f'P{n}');prop(wp,'bool','Enabled','true')
 ET.ElementTree(root).write(out,encoding='utf-8',xml_declaration=True)

if __name__=='__main__':
 for name,pants in [('shirt',False),('pants',True)]: (ROOT/'source-svg'/f'investor_{name}.svg').write_text(clothing(pants))
 export_accessory(ROOT/'InvestorCase.rbxmx')
 (ROOT/'UV_MAP.json').write_text(json.dumps({'torso':TORSO,'right':RIGHT,'left':LEFT,'reference':'https://create.roblox.com/docs/avatar/classic-clothing'},indent=2)+'\n')
 (ROOT/'accessory-manifest.json').write_text(json.dumps(accessories()[0],indent=2)+'\n')
 pr=ROOT/'source'/'convert.project.json';pr.write_text(json.dumps({'name':'InvestorCase','tree':{'$path':str(ROOT/'InvestorCase.rbxmx')}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(ROOT/'InvestorCase.rbxm')],check=True);pr.unlink()
