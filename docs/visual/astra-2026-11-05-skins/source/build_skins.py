"""Original code-native SVG clothing and native Roblox accessory geometry.
UV layout measured from official Roblox R15 classic templates (585x559).
"""
import sys,json,math,copy,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
sys.path.insert(0,'/private/tmp/gst-render-libs')
import numpy as np
from PIL import Image,ImageDraw
from geometry import model,box,ball,cyl,line,rot,export,meshes,flatten,prop,vec,frame,I
ROOT=Path(__file__).resolve().parents[1]
DATA=[
('hoodie_coder','26344E','4678B3','3D7BFF','headphones'),
('pixel_artist','FFB2D5','36466F','FF6EB4','beret'),
('sound_nerd','326A57','27364D','3DC86E','studio'),
('writer','7B4E84','38324F','E7B977','writer'),
('intern','2D7689','3A485C','FFC93C','backpack'),
('bug_hunter','799B61','3D4941','FFD75E','hunter'),
('speedrunner','2566A7','24354C','00D4CE','sports'),
('retro_gamer','8742A4','263D64','FFB845','retro'),
('neon_streamer','302547','27213F','FF6EB4','neon'),
('cyber_dev','1B2C40','172636','00E5FF','cyber'),
('space_dev','DFE7EF','BDCCD9','00CFF0','space'),
('wizard_dev','493169','35264E','CBA0FF','wizard')]
TORSO={'R':(165,74,64,128),'F':(231,74,128,128),'L':(361,74,64,128),'B':(427,74,128,128),'U':(231,8,128,64),'D':(231,204,128,64)}
RIGHT={'L':(19,355,64,128),'B':(85,355,64,128),'R':(151,355,64,128),'F':(217,355,64,128),'U':(217,289,64,64),'D':(217,485,64,64)}
LEFT={'F':(308,355,64,128),'L':(374,355,64,128),'B':(440,355,64,128),'R':(506,355,64,128),'U':(308,289,64,64),'D':(308,485,64,64)}
def shade(c,f):return '#'+''.join(f'{min(255,int(int(c[i:i+2],16)*f)):02x}' for i in (0,2,4))
def rect(x,y,w,h,c,rx=0):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{c}"/>'
def path(d,c,stroke=None,sw=1):return f'<path d="{d}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round"' if stroke else '')+'/>'
def line2(x,y,X,Y,c,sw=2):return f'<path d="M{x} {y}L{X} {Y}" stroke="{c}" stroke-width="{sw}" fill="none"/>'
def star(cx,cy,r,c):
 p=[]
 for i in range(10):
  a=-math.pi/2+i*math.pi/5;R=r if i%2==0 else r*.43;p.append((cx+math.cos(a)*R,cy+math.sin(a)*R))
 return path('M'+' L'.join(f'{x:.2f} {y:.2f}' for x,y in p)+' Z',c)
def panel(w,h,base,accent,kind,face,region,pants):
 s=rect(0,0,w,h,'#'+base)
 if face in ['R','L','B']:s+=rect(0,0,w,h,shade(base,.90 if face!='B' else .82))
 if face in ['U','D']:return s
 # Continuous seam details are placed at matching heights on all wrap faces.
 if pants:
  if region=='torso':return s+rect(0,0,w,14,'#242B3B')+line2(0,15,w,15,'#'+accent,2)
  s+=rect(0,106,w,22,'#242B3B')+rect(0,118,w,6,'#CFD5E2')+line2(4,4,4,104,shade(base,1.2),2)
  if face=='F':
   s+=path(f'M8 13 L{w-8} 13 L{w-12} 36 L12 36 Z',shade(base,.83))+line2(12,38,w-12,38,shade(base,1.18),2)
  if kind in ['neon','cyber','space','sports']:s+=rect(w-11,0,5,103,'#'+accent)
  if kind=='wizard':s+=star(w/2,60,10,'#'+accent)
  return s
 s+=rect(0,h-11,w,11,shade(base,.68))
 if region!='torso':
  if kind=='backpack':
   for x in range(0,w,16):s+=rect(x,0,3,h,'#C5D9D5')
   for y in range(12,h,20):s+=rect(0,y,w,3,'#C5D9D5')
  if kind in ['neon','cyber','sports','space']:s+=rect(0,19,w,6,'#'+accent)+rect(w-10,25,4,75,'#'+accent)
  if kind=='retro':s+=rect(0,23,w,18,'#FFB845')+rect(0,42,w,8,'#3FE0D5')
  return s
 if face=='F':
  # Exposed neckline is truly transparent, rather than a printed skin color.
  s+='' 
  s+=f'<path d="M43 0 Q64 38 85 0 Z" fill="#000" fill-opacity="0"/>'
  if kind in ['headphones','neon']:
   s+=path('M36 0 Q64 45 92 0 L86 14 Q64 48 42 14Z',shade(base,.60))+rect(22,78,84,28,shade(base,.78),8)
   s+=line2(48,25,45,64,'#F0F3F8',3)+line2(80,25,83,64,'#F0F3F8',3)
  elif kind=='beret':
   for x,y,c in [(30,42,'#9650DC'),(49,56,'#3D7BFF'),(67,43,'#FFC93C'),(83,65,'#3DC86E')]:s+=rect(x,y,17,17,c)
  elif kind=='studio':
   for i,hg in enumerate([12,28,39,23,49,32,16]):s+=rect(29+i*10,70-hg/2,5,hg,'#'+accent,2)
  elif kind=='writer':
   s+=path('M26 0 L64 50 L102 0 L89 0 L64 31 L39 0Z','#E7B977')+rect(61,44,6,70,shade(base,.65))
   for y in (60,77,94):s+=rect(62,y,4,4,'#E7B977',2)
  elif kind=='backpack':
   for x in range(0,128,18):s+=rect(x,0,3,128,'#BCD4D7')
   for y in range(12,128,20):s+=rect(0,y,128,3,'#BCD4D7')
   s+=path('M38 0 L64 30 L90 0 L81 0 L64 17 L47 0Z','#DFE5EB')+rect(85,39,22,29,'#E3E9EF',2)+rect(89,44,14,6,'#FFC93C')
  elif kind=='hunter':
   s+=rect(57,0,14,128,'#263F39')
   for x in (12,77):s+=rect(x,39,39,31,'#526F48',3)+rect(x,80,39,29,'#526F48',3)+rect(x,39,39,6,'#AFC08D')
  elif kind=='sports':s+=path('M12 0 L33 0 L77 116 L56 116 Z','#00D4CE')+rect(87,37,23,17,'#F5F8FC',3)
  elif kind=='retro':s+=rect(0,30,128,19,'#FFB845')+rect(0,51,128,9,'#3FE0D5')+rect(62,0,5,117,'#E9D4F4')
  elif kind=='cyber':s+=path('M17 20 L39 20 L56 43 L110 43 L110 49 L53 49 L36 26 L17 26Z','#00E5FF')+rect(21,79,86,6,'#00E5FF')+rect(61,85,6,31,'#00E5FF')
  elif kind=='space':s+=rect(25,32,78,64,'#7B8EA7',7)+rect(34,41,60,29,'#1B3552',4)+rect(39,47,28,5,'#00CFF0')+rect(74,47,10,10,'#FFC93C')+rect(42,81,43,6,'#E5EEF3')
  elif kind=='wizard':
   s+=path('M40 0 L64 40 L88 0 L78 0 L64 24 L50 0Z','#E5C765')
   for x,y,r in [(24,49,10),(96,71,13),(48,93,8)]:s+=star(x,y,r,'#'+accent)
  # neckline mask punched using clip shape in parent SVG
 if face=='B' and kind in ['headphones','neon']:s+=path('M35 0 Q64 58 93 0 L85 0 Q64 39 43 0Z',shade(base,.63))
 if kind in ['neon','cyber']:
  s+=rect(0,18,w,4,'#'+accent)+rect(0,h-17,w,4,'#'+accent)
 return s

def clothing(row,pants,out):
 id,shirt,trouser,accent,kind=row;base=trouser if pants else shirt
 svg=['<svg xmlns="http://www.w3.org/2000/svg" width="585" height="559" viewBox="0 0 585 559">']
 for region,areas in [('torso',TORSO),('right',RIGHT),('left',LEFT)]:
  for face,(x,y,w,h) in areas.items():
   svg+=['<svg x="%d" y="%d" width="%d" height="%d" viewBox="0 0 %d %d">'%(x,y,w,h,w,h)]
   if not pants and region=='torso' and face=='F':
    svg+=['<defs><mask id="neck"><rect width="128" height="128" fill="white"/><path d="M44 0 Q64 29 84 0 Z" fill="black"/></mask></defs><g mask="url(#neck)">',panel(w,h,base,accent,kind,face,region,pants),'</g>']
   else:svg+=[panel(w,h,base,accent,kind,face,region,pants)]
   svg+=['</svg>']
 svg+=['</svg>'];out.write_text(''.join(svg))

def accessories(row):
 id,shirt,trouser,accent,kind=row; groups=[]
 def group(name,attach='HatAttachment',offset=(0,.5,0)):
  m=model(name);box(m,'Handle',(0,0,0),(.12,.12,.12),shirt,alpha=1);m['attachment']=(attach,offset);groups.append(m);return m
 if kind in ['headphones','studio','neon']:
  m=group('Headphones');wide=1.35 if kind=='studio' else 1.23
  for sign in (-1,1):
   box(m,'EarCup',(sign*wide/2,-.12,0),(.23,.58,.5),accent if kind=='neon' else '243148',mat='Neon' if kind=='neon' else 'SmoothPlastic')
   box(m,'EarPad',(sign*(wide/2-.12),-.12,0),(.10,.48,.39),'141A2E')
   box(m,'BandSide',(sign*.56,.3,0),(.13,.55,.24),accent)
  box(m,'HeadBand',(0,.59,0),(1.13,.13,.24),accent)
  if kind=='headphones':
   # Hood behind the head and shoulders; separate from face/headphones.
   box(m,'HoodBack',(0,-.31,.72),(1.18,.71,.24),shirt)
   for sign in (-1,1):box(m,'HoodFold',(sign*.64,-.34,.48),(.18,.54,.36),shirt)
  if kind=='neon':
   for sign in (-1,1):
    line(m,'CatEarA',(sign*.38,.58,0),(sign*.52,.99,0),.11,accent,mat='Neon');line(m,'CatEarB',(sign*.52,.99,0),(sign*.7,.58,0),.11,accent,mat='Neon')
 elif kind=='beret':
  m=group('Beret');ball(m,'BeretCrown',(-.10,.77,.02),(1.65,.48,1.50),'9650DC');cyl(m,'BeretBand',(0,.56,0),.13,1.60,'493169');box(m,'Stem',(-.1,1.08,0),(.10,.17,.1),'493169')
  # Stylus sits clear beside ear, attached to same hat rig.
  line(m,'Stylus',(.69,-.16,.08),(.69,.48,-.19),.07,'FFC93C')
 elif kind=='writer':
  m=group('Glasses','FaceFrontAttachment',(0,0,-.5))
  for sign in (-1,1):
   x=sign*.29
   for yy in (-.14,.14):box(m,'Frame',(x,yy,-.57),(.48,.065,.07),'262438')
   for xx in (-.24,.24):box(m,'Frame',(x+xx,0,-.57),(.065,.28,.07),'262438')
  box(m,'Bridge',(0,0,-.57),(.12,.06,.07),'262438')
  m=group('Scarf','BodyFrontAttachment',(0,0,-.5));box(m,'ScarfCollar',(0,.34,-.12),(1.68,.24,1.12),'E7B977');box(m,'ScarfTail',(.39,-.1,-.72),(.28,.65,.12),'E7B977')
  # Mug worn on a tool loop: decorative, no hand/animation dependency.
  cyl(m,'Mug',(-.7,-.66,-.65),.28,.24,'F2F2F2');box(m,'MugHandle',(-.88,-.66,-.65),(.1,.17,.1),'E7B977')
 elif kind=='backpack':
  m=group('Backpack','BodyBackAttachment',(0,0,.5));box(m,'Bag',(0,0,.76),(1.25,1.35,.5),'D49A48');box(m,'Pocket',(0,-.28,1.07),(.94,.5,.13),'FFC93C');box(m,'TopHandle',(0,.78,.76),(.48,.13,.19),'283345')
  for x in (-.58,.58):box(m,'Strap',(x,0,.46),(.14,1.45,.12),'283345')
 elif kind=='hunter':
  m=group('Headlamp');cyl(m,'Band',(0,.11,0),.14,1.19,'526F48');box(m,'LampHousing',(0,.13,-.59),(.48,.32,.23),'263F39');ball(m,'LampLens',(0,.13,-.75),(.25,.23,.09),'FFD75E',mat='Neon')
  m=group('Magnifier','BodyFrontAttachment',(0,0,-.5));
  for j in range(10):
   a=j*math.tau/10;b=(j+1)*math.tau/10;line(m,'LensRim',(.7+.18*math.cos(a),-.44+.18*math.sin(a),-.67),(.7+.18*math.cos(b),-.44+.18*math.sin(b),-.67),.045,'FFD75E')
  cyl(m,'Lens',(.7,-.44,-.72),.025,.26,'A1DDE5',r=rot(y=90),mat='Glass',alpha=.35);line(m,'LensHandle',(.7,-.67,-.67),(.7,-.98,-.67),.09,'263F39')
 elif kind=='sports':
  m=group('Headband');cyl(m,'Band',(0,.15,0),.16,1.17,'00D4CE');box(m,'Knot',(.52,.13,.28),(.15,.20,.17),'F2F2F2')
  m=group('Stopwatch','BodyFrontAttachment',(0,0,-.5));line(m,'Lanyard',(-.38,.7,-.58),(0,-.15,-.61),.035,'FFC93C');line(m,'Lanyard',(.38,.7,-.58),(0,-.15,-.61),.035,'FFC93C');cyl(m,'Watch',(0,-.34,-.65),.08,.38,'FFC93C',r=rot(y=90));box(m,'WatchFace',(0,-.34,-.71),(.22,.2,.025),'24354C')
 elif kind=='retro':
  m=group('BackwardsCap');ball(m,'Crown',(0,.42,0),(1.32,.65,1.2),'FFB845');box(m,'Brim',(0,.25,.69),(1.11,.10,.55),'8742A4');box(m,'Buckle',(0,.23,-.59),(.36,.14,.08),'3FE0D5')
  m=group('Cartridge','RightGripAttachment',(0,-.1,0));box(m,'Cartridge',(0,-.17,-.57),(.43,.59,.17),'3FE0D5');box(m,'Label',(0,-.09,-.67),(.30,.25,.03),'FFB845')
 elif kind=='cyber':
  m=group('Visor','FaceFrontAttachment',(0,0,-.5));box(m,'VisorShell',(0,.07,-.57),(1.15,.38,.17),'172636');box(m,'GlowLens',(0,.07,-.68),(.99,.22,.07),accent,mat='Neon')
  for sign in (-1,1):box(m,'VisorArm',(sign*.6,.07,-.22),(.1,.17,.64),'00E5FF')
 elif kind=='space':
  m=group('Helmet');ball(m,'Helmet',(0,.23,0),(2.14,2.14,2.05),'9DDDEB',mat='Glass',alpha=.72);cyl(m,'Collar',(0,-.58,0),.17,1.50,'DFE7EF');box(m,'HelmetTop',(0,1.35,0),(.65,.13,.6),'DFE7EF')
  m=group('AirPack','BodyBackAttachment',(0,0,.5));box(m,'Pack',(0,0,.85),(1.2,1.35,.5),'DFE7EF');box(m,'GlowPanel',(0,.10,1.13),(.79,.37,.05),'00E5FF',mat='Neon')
  for sign in (-1,1):cyl(m,'Tank',(sign*.7,0,.82),1.09,.3,'7B8EA7')
 elif kind=='wizard':
  m=group('WizardHat');cyl(m,'Brim',(0,.67,0),.10,1.8,'493169')
  # Stepped native taper, no mesh. Base touches crown.
  for i in range(6):cyl(m,'HatTier',(0,.79+i*.17,0),.17,1.13-i*.16,'493169')
  ball(m,'GlowStar',(0,1.78,0),(.18,.18,.18),'CBA0FF',mat='Neon')
  m=group('Stylus','BodyBackAttachment',(0,0,.5));line(m,'Staff',(.76,-.7,.79),(.76,1.03,.79),.09,'E5C765');ball(m,'Tip',(.76,1.17,.79),(.30,.3,.30),'CBA0FF',mat='Neon')
 return groups

def export_acc(row,groups,out):
 # Build each Accessory with one Handle, standard Attachment, welded massless Parts.
 root=ET.Element('roblox',{'version':'4'});outer=ET.SubElement(root,'Item',{'class':'Model','referent':'RBXROOT'});pr=ET.SubElement(outer,'Properties');prop(pr,'string','Name','skin_'+row[0]+'_acc');prop(pr,'Ref','PrimaryPart','G0P0')
 from geometry import write_part
 for gi,m in enumerate(groups):
  ac=ET.SubElement(outer,'Item',{'class':'Accessory','referent':f'A{gi}'});p=ET.SubElement(ac,'Properties');prop(p,'string','Name',m['name'])
  for pi,part in enumerate(m['parts']):
   p=copy.deepcopy(part);p['collide']=False;node=write_part(p,ac,f'G{gi}P{pi}');props=node.find('Properties')
   props.find("bool[@name='Anchored']").text='false';prop(props,'bool','Massless','true')
   if pi==0:
    at=ET.SubElement(node,'Item',{'class':'Attachment','referent':f'ATT{gi}'});ap=ET.SubElement(at,'Properties');prop(ap,'string','Name',m['attachment'][0]);frame(ap,'CFrame',m['attachment'][1])
   else:
    weld=ET.SubElement(node,'Item',{'class':'WeldConstraint','referent':f'W{gi}_{pi}'});wp=ET.SubElement(weld,'Properties');prop(wp,'string','Name','RigidWeld');prop(wp,'Ref','Part0',f'G{gi}P0');prop(wp,'Ref','Part1',f'G{gi}P{pi}');prop(wp,'bool','Enabled','true')
 ET.ElementTree(root).write(out,encoding='utf-8',xml_declaration=True)

def main():
 import argparse
 ap=argparse.ArgumentParser();ap.add_argument('--batch',type=int,choices=[1,2,3]);args=ap.parse_args()
 for index,row in enumerate(DATA):
  if args.batch and index//4+1!=args.batch:continue
  batch=ROOT/f'batch-{index//4+1}';files=batch/'V12';svgs=batch/'source-svg';files.mkdir(parents=True,exist_ok=True);svgs.mkdir(exist_ok=True)
  for typ in ['shirt','pants']:clothing(row,typ=='pants',svgs/f'skin_{row[0]}_{typ}.svg')
  export_acc(row,accessories(row),files/f'skin_{row[0]}_acc.rbxmx')
 (ROOT/'UV_MAP.json').write_text(json.dumps({'torso':TORSO,'right':RIGHT,'left':LEFT,'official_reference':'https://create.roblox.com/docs/avatar/classic-clothing'},indent=2))
 (ROOT/'manifest.json').write_text(json.dumps(DATA,indent=2))
if __name__=='__main__':main()
