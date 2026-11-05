"""V13: original SVG face/clothing artwork and hollow native-Part hair assemblies.
Head-local target: center0, size1.18x1.20x1.05, HatAttachment(0,.5,0).
"""
import math,json,copy,sys,xml.etree.ElementTree as ET
from pathlib import Path
from geometry import *
ROOT=Path(__file__).resolve().parents[1]
TORSO={'R':(165,74,64,128),'F':(231,74,128,128),'L':(361,74,64,128),'B':(427,74,128,128),'U':(231,8,128,64),'D':(231,204,128,64)}
RIGHT={'L':(19,355,64,128),'B':(85,355,64,128),'R':(151,355,64,128),'F':(217,355,64,128),'U':(217,289,64,64),'D':(217,485,64,64)}
LEFT={'F':(308,355,64,128),'L':(374,355,64,128),'B':(440,355,64,128),'R':(506,355,64,128),'U':(308,289,64,64),'D':(308,485,64,64)}
SPEC={'gameplay':'3D7BFF','graphics':'FF6EB4','sound':'3DC86E','story':'9650DC','all':'FFC93C'}
# id, specialization, gender, hair color, trouser color, skin color, face character
DATA=[('mila','gameplay','female','65452F','32476D','F3C8A6','bright'),('tim','graphics','male','6D3F27','42415C','EBC19D','cheeky'),('zoe','sound','female','30263B','344A43','B87955','delighted'),('ilya','story','male','88522D','3C3A52','F1C99C','dreamy'),('oleg','gameplay','male','483A32','34404F','DCA87D','calm'),('sara','graphics','female','242B43','3F5873','DCA078','confident'),('max','sound','male','4F3C36','273B38','E9BD98','sleepy'),('nika','story','female','B47036','494057','F0C3A4','warm'),('den','gameplay','male','313440','3F4956','B98361','focused'),('aya','graphics','female','542C4D','373C58','A96D50','proud'),('leo','sound','male','2D3B35','293B39','E7B585','cool'),('vera','story','female','747287','494357','D8B29D','wise'),('robo','all','other','596A7D','516172','A5B6CA','robot'),('ghost','all','other','6BBFE0','72BDD1','9AD9EA','ghost'),('legend','all','other','594059','443850','E8C49E','legend')]
def rect(x,y,w,h,c,rx=0):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{c}"/>'
def path(d,c='none',stroke=None,sw=2):return f'<path d="{d}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"' if stroke else '')+'/>'
def ellipse(x,y,rx,ry,c):return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}"/>'
def line2(x,y,X,Y,c,sw=2):return path(f'M{x} {y}L{X} {Y}',stroke=c,sw=sw)
def shade(c,f):return '#'+''.join(f'{min(255,int(int(c[i:i+2],16)*f)):02x}' for i in (0,2,4))
def star(x,y,r,c):
 pts=[]
 for i in range(10):
  a=-math.pi/2+i*math.pi/5;rr=r if i%2==0 else r*.45;pts.append((x+rr*math.cos(a),y+rr*math.sin(a)))
 return path('M'+'L'.join(f'{a:.2f},{b:.2f}' for a,b in pts)+'Z',c)
def face(row,index):
 id,spec,gender,hair,pants,skin,emotion=row;ink='#263345';s='';eyeY=111+(index%3-1)*4
 if id in ('robo','ghost'):
  c='#74F2F2' if id=='robo' else '#DAFFFF'
  for x in (82,174):s+=rect(x-14,94,28,33,c,9)
  if id=='robo':s+=path('M80 154 Q128 198 176 154',stroke=c,sw=12)
  else:s+=path('M99 158 Q128 177 157 158',stroke=c,sw=8)
  return '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256">'+s+'</svg>'
 # Every employee has distinct eye shape, eyebrow rhythm, and mouth.
 if emotion in ('bright','delighted','warm'):
  for x in (82,174):s+=ellipse(x,eyeY,19,25,'#FFFFFF')+ellipse(x+(index%3-1)*3,eyeY+2,10,16,ink)+ellipse(x-3,eyeY-7,4,6,'#FFFFFF')
 elif emotion in ('dreamy','sleepy'):
  for x in (82,174):s+=path(f'M{x-16} {eyeY} Q{x} {eyeY+28} {x+16} {eyeY} Z',ink)+line2(x-18,eyeY,x+18,eyeY-3,ink,6)
 elif emotion=='cheeky':
  s+=path('M65 113 Q82 95 101 112',stroke=ink,sw=9)+ellipse(174,110,13,21,ink)+ellipse(170,104,4,6,'white')
 elif emotion in ('focused','cool'):
  for x in (82,174):s+=rect(x-12,105,24,22,ink,5)
 else:
  for x in (82,174):s+=ellipse(x,eyeY,12+(index%2)*2,18,ink)+ellipse(x-3,eyeY-6,3,5,'#FFFFFF')
 for sign in (-1,1):
  x=128+sign*46;tilt=(index%4-1.5)*3*sign
  s+=path(f'M{x-20} {78+tilt} Q{x} {68-index%3*3} {x+20} {78-tilt}',stroke='#'+hair,sw=7)
 if emotion=='delighted':s+=ellipse(128,167,30,28,ink)+path('M105 180 Q128 162 151 180 Q128 198 105 180','#ED8190')
 elif emotion=='sleepy':s+=path('M107 165 Q128 169 150 158',stroke=ink,sw=6)
 elif emotion=='cheeky':s+=path('M99 167 Q128 190 163 155',stroke=ink,sw=7)
 elif emotion=='focused':s+=path('M108 168 Q128 162 151 165',stroke=ink,sw=6)
 elif emotion=='legend':s+=path('M95 156 Q128 190 163 156 L159 171 Q128 191 101 172 Z',ink)+path('M102 159 Q128 177 156 159 L154 166 Q128 181 104 166Z','#FFFFFF')
 else:s+=path(f'M{100-index%4*2} 160 Q128 {187-index%5*3} {156+index%3*2} 159',stroke=ink,sw=7)
 if gender=='female':
  for sign in (-1,1):s+=line2(128+sign*61,100,128+sign*69,91,ink,5)
  for x in (57,199):s+=ellipse(x,147,12,6,'#EA9A91')
 if id=='oleg':
  s+=path('M67 164 Q74 217 128 226 Q184 217 189 164 L173 172 Q155 205 128 204 Q98 205 82 172Z','#483A32')
  s+=path('M101 163 Q128 146 155 163',stroke='#483A32',sw=9)
 return '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256">'+s+'</svg>'
def panel(row,pants,region,face,w,h):
 id,spec,gender,hair,trouser,skin,emotion=row;base=trouser if pants else SPEC[spec]
 if id=='ghost':base='72BDD1' if pants else '95D9E7'
 if id=='robo':base='677C90' if pants else 'C8D5DC'
 c='#'+base;s=rect(0,0,w,h,c if face in ('F','U') else shade(base,.88))
 if face in ('U','D'):return s
 if pants:
  if region=='torso':return s+rect(0,110,w,18,'#313C4B')
  s+=rect(0,110,w,18,'#27303D')+rect(0,123,w,5,'#ADB8C2')
  if face=='F':s+=path(f'M9 16 L{w-9} 16 L{w-12} 33 L12 33Z',shade(base,.8))+line2(9,67,w-9,67,shade(base,1.2),2)
  if id in ('sara','aya'):s+=line2(w-6,1,w-6,108,'#FF9ACB',3)
  if id=='robo':s+=rect(4,46,w-8,14,'#3B4C60')+rect(8,49,w-16,6,'#FFC93C')
  if id=='ghost':s+=path(f'M0 105 L12 98 L25 108 L40 99 L{w} 106 L{w} 127 L0 127Z','#B9F1F7')
  if id=='legend':s+=rect(2,0,5,110,'#FFC93C')+rect(w-7,0,5,110,'#FFC93C')
  return s
 s+=rect(0,h-9,w,9,shade(base,.72))
 if region!='torso':
  if id=='oleg':
   for x in range(4,w,18):s+=rect(x,0,3,h,'#A9CBFF')
   for y in range(8,h,20):s+=rect(0,y,w,3,'#A9CBFF')
  if id=='max' and face=='L':
   s+=ellipse(w*.45,67,6,4,'#123D32')+line2(w*.45+5,67,w*.45+5,43,'#123D32',3)+line2(w*.45+5,43,w*.45+18,47,'#123D32',3)
  if id in ('leo','den'):s+=rect(0,16,w,11,shade(base,.48))
  if id=='legend':s+=rect(0,12,w,8,'#E8B642')+rect(0,97,w,10,'#E8B642')
  if id=='robo':s+=rect(0,49,w,16,'#677C90')+rect(0,54,w,5,'#FFC93C')
  return s
 if face!='F':
  if id=='ghost':s+=path('M31 15 L64 44 L97 15 L87 53 L41 53Z','#B9F1F7')
  return s
 if id=='mila':
  s+=path('M34 0 Q64 39 94 0 L85 0 Q64 23 43 0Z','#2452A4')+rect(27,87,74,23,'#2A62C4',7)
  # Curly-brace pictogram drawn as geometry, not font or lettering.
  s+=path('M51 47 Q42 47 45 57 Q47 63 39 66 Q47 69 45 75 Q42 84 51 84',stroke='#CDE6FF',sw=4)+path('M77 47 Q86 47 83 57 Q81 63 89 66 Q81 69 83 75 Q86 84 77 84',stroke='#CDE6FF',sw=4)
 elif id=='tim':
  for x,y,c in [(28,36,'#FFF1A6'),(46,59,'#A46BDA'),(65,39,'#79DBD2'),(81,66,'#FFCF7E'),(39,82,'#BE4F91')]:s+=rect(x,y,16,16,c)
 elif id=='zoe':
  for x,y,r in [(34,58,8),(64,76,11),(93,48,6)]:s+=ellipse(x,y,r,r,'#B8F2C4')
  s+=path('M31 100 Q64 78 97 100',stroke='#237443',sw=6)
 elif id=='ilya':
  s+=rect(76,63,30,33,'#C7A6EB',3)+rect(80,56,22,30,'#F1DFB6',2)+line2(84,65,98,65,'#9F82B8',2)
 elif id=='oleg':
  for x in range(3,128,18):s+=rect(x,0,3,128,'#A9CBFF')
  for y in range(8,128,20):s+=rect(0,y,128,3,'#A9CBFF')
  s+=rect(61,0,6,118,'#2B5796')
  for y in (36,56,76,96):s+=ellipse(64,y,2,2,'#EBF3FF')
 elif id=='sara':
  s+=rect(23,53,82,66,'#3F5873')+rect(27,0,12,65,'#3F5873')+rect(89,0,12,65,'#3F5873')+rect(44,66,40,26,'#6686A4',3)
  for x in (33,95):s+=ellipse(x,47,4,4,'#FFC93C')
 elif id=='max':s+=rect(0,0,128,15,'#2B9656')+rect(50,15,28,7,'#2B9656')+path('M31 88 Q64 74 97 88',stroke='#71DE95',sw=4)
 elif id=='nika':
  s+=path('M0 0 L39 0 L59 120 L0 120Z','#7541AE')+path('M128 0 L89 0 L69 120 L128 120Z','#7541AE')
  for y in (43,64,85,106):s+=ellipse(64,y,3,3,'#EBC584')
 elif id=='den':
  s+=path('M0 0 L27 0 L46 30 L46 118 L0 118Z','#293E62')+path('M128 0 L101 0 L82 30 L82 118 L128 118Z','#293E62')+rect(90,41,20,28,'#F3E8BB',2)+rect(94,47,12,5,'#3D7BFF')
 elif id=='aya':
  s+=path('M0 0 L30 0 L48 42 L36 49 L48 120 L0 120Z','#B84485')+path('M128 0 L98 0 L80 42 L92 49 L80 120 L128 120Z','#B84485')+rect(13,67,21,4,'#F7C8E3')
 elif id=='leo':
  s+=path('M0 0 L22 0 L43 32 L32 47 L43 119 L0 119Z','#203F34')+path('M128 0 L106 0 L85 32 L96 47 L85 119 L128 119Z','#203F34')+line2(79,40,61,118,'#B8C6BA',3)
 elif id=='vera':
  for y in range(19,114,15):s+=path(f'M10 {y} Q20 {y-9} 30 {y} T50 {y} T70 {y} T90 {y} T118 {y}',stroke='#B081E1',sw=3)
 elif id=='robo':
  s+=rect(25,28,78,69,'#6E8498',7)+rect(36,40,56,26,'#243D51',3)+rect(42,47,20,11,'#7EEEE7')+rect(73,48,10,10,'#FFC93C')+rect(42,78,44,7,'#E0E7EC')
 elif id=='ghost':
  s+=path('M30 0 Q64 57 98 0 L87 0 Q64 32 41 0Z','#5AA7C7')+path('M18 112 Q31 92 45 112 Q59 91 73 112 Q89 90 111 112',stroke='#CCFAFF',sw=6)
 elif id=='legend':
  s+=path('M22 0 L64 47 L106 0 L94 0 L64 31 L34 0Z','#8B634E')+rect(18,86,92,18,'#77533D')+rect(52,83,24,24,'#EFC76B')+star(64,61,16,'#FFF3B3')
 return s

def clothing(row,pants,out):
 s=['<svg xmlns="http://www.w3.org/2000/svg" width="585" height="559" viewBox="0 0 585 559">']
 for region,areas in [('torso',TORSO),('right',RIGHT),('left',LEFT)]:
  for face,(x,y,w,h) in areas.items():
   s.append(f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 {w} {h}">')
   if region=='torso' and face=='F' and not pants and row[0] not in ('robo','ghost','max'):
    s.append('<defs><mask id="neck"><rect width="128" height="128" fill="white"/><path d="M45 0 Q64 27 83 0 Z" fill="black"/></mask></defs><g mask="url(#neck)">'+panel(row,pants,region,face,w,h)+'</g>')
   else:s.append(panel(row,pants,region,face,w,h))
   s.append('</svg>')
 s.append('</svg>');out.write_text(''.join(s))

def hair(row):
 id,spec,gender,col,pants,skin,emotion=row;m=model('hair_'+id);box(m,'Handle',(0,0,0),(.08,.08,.08),col,alpha=1);m['attachment']=('HatAttachment',(0,.5,0))
 def top():
  box(m,'Crown',(0,.72,0),(1.3,.20,1.17),col)
 def side(length=.9):
  for x in (-.70,.70):box(m,'SideLocks',(x,.65-length/2,.08),(.18,length,1.12),col)
  box(m,'BackLocks',(0,.65-length/2,.65),(1.25,length,.18),col)
 def fringe():
  for x,y in [(-.42,.51),(-.14,.55),(.14,.51),(.42,.56)]:box(m,'Fringe',(x,y,-.62),(.30,.28,.14),col)
 def glasses():
  for x in (-.29,.29):
   for y in (-.13,.15):box(m,'GlassesFrame',(x,y,-.604),(.47,.05,.055),'293344')
   for dx in (-.235,.235):box(m,'GlassesFrame',(x+dx,.01,-.604),(.05,.28,.055),'293344')
  box(m,'GlassesBridge',(0,.01,-.604),(.12,.05,.055),'293344')
 if id=='robo':
  for x in (-.76,.76):box(m,'MonitorSide',(x,0,0),(.20,1.55,1.43),'516478')
  for y in (-.74,.74):box(m,'MonitorTopBottom',(0,y,0),(1.33,.16,1.43),'718598')
  box(m,'MonitorBack',(0,0,.70),(1.33,1.34,.14),'516478')
  box(m,'FaceScreen',(0,0,-.70),(1.33,1.34,.14),'183C4B')
  for x in (-.239,.239):box(m,'NeonEye',(x,.094,-.784),(.145,.173,.025),'74F2F2',mat='Neon')
  # Emissive smile follows the exact face SVG quadratic stroke, not a PointLight.
  nodes=[]
  for i in range(7):
   t=i/6;px=80+96*t;py=154+88*t*(1-t);nodes.append(((px/256-.5)*1.33,(.5-py/256)*1.34,-.784))
  for a,b in zip(nodes,nodes[1:]):line(m,'NeonSmile',a,b,.062,'74F2F2',mat='Neon')
  line(m,'Antenna',(.55,.85,.2),(.55,1.12,.2),.06,'FFC93C');ball(m,'AntennaTip',(.55,1.19,.2),(.18,.18,.18),'FFC93C')
  return m
 if id=='ghost':
  box(m,'HoodTop',(0,.76,.05),(1.5,.26,1.44),'6BBFE0',alpha=.25)
  for x in (-.75,.75):box(m,'HoodSide',(x,-.1,.05),(.22,1.5,1.44),'6BBFE0',alpha=.25)
  box(m,'HoodBack',(0,-.1,.78),(1.3,1.5,.18),'6BBFE0',alpha=.25)
  for x in (-.212,.212):box(m,'GlowEye',(x,.084,-.57),(.129,.155,.035),'DFFFFF',mat='Neon')
  return m
 top()
 if id=='mila':
  fringe();box(m,'PonyTie',(0,.68,.75),(.5,.3,.4),'3D7BFF')
  for x,y,z,s in [(0,.54,1.0,(.6,.7,.5)),(0,-.03,1.04,(.48,.65,.4)),(0,-.49,.98,(.34,.38,.3))]:ball(m,'Ponytail',(x,y,z),s,col)
  glasses()
 elif id=='tim':
  fringe()
  for x,z in [(-.5,.1),(-.3,-.3),(.25,-.25),(.48,.1)]:ball(m,'ShaggyTuft',(x,.86,z),(.4,.44,.43),col)
  ball(m,'SoftBeret',(-.10,1.17,.08),(1.58,.48,1.38),'576F91');box(m,'BeretStem',(-.1,1.47,.08),(.1,.16,.1),'344965')
 elif id=='zoe':
  fringe();side(.55)
  for x in (-.83,.83):ball(m,'HairBun',(x,.98,.15),(.5,.55,.55),col)
  # One small decorative neck-headphone accessory: no lights.
  for x in (-.70,.70):box(m,'NeckHeadphone',(x,-.98,-.62),(.27,.37,.3),'1F6850')
  box(m,'NeckBand',(0,-.86,.68),(1.48,.15,.15),'1F6850')
 elif id=='ilya':
  for i,(x,z) in enumerate([(-.45,-.35),(0,-.4),(.45,-.35),(-.5,.2),(0,.2),(.5,.2)]):ball(m,'Curl',(x,.84+(i%2)*.1,z),(.42,.42,.42),col)
  # Scarf lies in front of torso, outside head; head-rig decorative tail only.
  box(m,'Scarf',(0,-.82,-.65),(1.53,.22,.18),'D9B16D');box(m,'ScarfTail',(.46,-1.2,-.65),(.24,.63,.18),'D9B16D')
 elif id=='oleg':
  for x in (-.5,.5):box(m,'Temple',(x,.44,-.62),(.22,.35,.14),col)
 elif id=='sara':
  side(1.35);fringe();box(m,'BrightStreak',(.80,.05,-.32),(.06,1.14,.25),'FF6EB4')
 elif id=='max':
  box(m,'TurtleneckCollar',(0,-.71,0),(1.25,.18,1.12),'2B9656')
  for i in range(5):box(m,'SweptLock',(-.5+i*.25,.87+i*.025,.15),(.23,.15,.92),col)
 elif id=='nika':
  side(1.9);fringe();box(m,'Clip',(.81,.3,-.42),(.08,.42,.12),'E9C87E');line(m,'Feather',(.83,.28,-.43),(.92,.7,-.43),.09,'E9C87E')
 elif id=='den':
  for x in (-.45,-.15,.15,.45):
   for z in (-.3,.12,.42):box(m,'CrewSpike',(x,.87,z),(.22,.30,.22),col)
 elif id=='aya':
  fringe();box(m,'PonyRibbon',(0,.89,.62),(.5,.18,.35),'FF6EB4');ball(m,'HighPony',(0,1.23,.72),(.60,.65,.55),col)
  for y,z in [(1.05,1.08),(.58,1.16),(.12,1.13)]:ball(m,'PonySegment',(0,y,z),(.4,.6,.38),col)
  line(m,'Brush',(.70,.72,.55),(.85,1.36,.55),.08,'C8A27A');box(m,'BrushBristle',(.87,1.49,.55),(.18,.28,.16),'E8C983')
 elif id=='leo':
  for i in range(5):box(m,'Mohawk',(0,.89+i*.055,-.40+i*.20),(.28,.32+i*.11,.19),'254C35')
  for sign in (-1,1):
   box(m,'StudioCup',(sign*.85,.02,0),(.30,.63,.6),'263E38');box(m,'StudioPad',(sign*.66,.02,0),(.08,.53,.44),'151F23')
  line(m,'StudioSide',(-.85,.02,0),(-.85,.77,.72),.12,'213E31');line(m,'StudioSide',(.85,.02,0),(.85,.77,.72),.12,'213E31')
  box(m,'StudioBand',(0,.77,.72),(1.8,.14,.25),'213E31')
 elif id=='vera':
  fringe();side(.4);box(m,'HairKnot',(0,.78,.65),(.5,.3,.2),col);ball(m,'HairBun',(0,.93,.90),(.72,.7,.55),col);line(m,'Pencil',(-.43,1.03,.90),(.5,1.28,.90),.07,'FFC93C');glasses()
 elif id=='legend':
  fringe();box(m,'CrownBand',(0,.98,0),(1.52,.16,1.4),'B17E2B')
  # Crown walls, hollow center, pixel-shaped merlons.
  for z in (-.68,.68):
   for i,x in enumerate((-.60,-.30,0,.30,.60)):box(m,'CrownPixel',(x,1.15+(i%2)*.14,z),(.24,.38+(i%2)*.28,.16),'FFC93C')
  for x in (-.68,.68):box(m,'CrownSide',(x,1.13,0),(.16,.30,1.12),'FFC93C')
  ball(m,'FrontGem',(0,1.15,-.79),(.22,.22,.12),'79DFDE',mat='Neon')
 return m

def cape():
 m=model('look_legend_cape');box(m,'Handle',(0,0,0),(.08,.08,.08),'443850',alpha=1);m['attachment']=('BodyBackAttachment',(0,0,.5))
 box(m,'CapeBack',(0,-.55,.76),(1.85,2.8,.22),'7B3554');box(m,'GoldHem',(0,-1.94,.77),(1.85,.12,.25),'FFC93C')
 for x in (-.82,.82):box(m,'GoldEdge',(x,-.55,.9),(.12,2.65,.05),'FFC93C')
 return m

def export_accessory(m,out):
 root=ET.Element('roblox',{'version':'4'});ac=ET.SubElement(root,'Item',{'class':'Accessory','referent':'ACC'});p=ET.SubElement(ac,'Properties');prop(p,'string','Name',m['name'])
 for i,src in enumerate(m['parts']):
  pp=copy.deepcopy(src);pp['collide']=False;node=write_part(pp,ac,'P'+str(i));props=node.find('Properties');props.find('bool[@name="Anchored"]').text='false';prop(props,'bool','Massless','true')
  if i==0:
   at=ET.SubElement(node,'Item',{'class':'Attachment','referent':'ATT'});ap=ET.SubElement(at,'Properties');prop(ap,'string','Name',m['attachment'][0]);frame(ap,'CFrame',m['attachment'][1])
  else:
   w=ET.SubElement(node,'Item',{'class':'WeldConstraint','referent':'W'+str(i)});wp=ET.SubElement(w,'Properties');prop(wp,'string','Name','RigidWeld');prop(wp,'Ref','Part0','P0');prop(wp,'Ref','Part1','P'+str(i));prop(wp,'bool','Enabled','true')
 ET.ElementTree(root).write(out,encoding='utf-8',xml_declaration=True)

def main():
 for i,row in enumerate(DATA):
  folder=ROOT/f'batch-{i//5+1}';out=folder/'V13';src=folder/'source-svg';out.mkdir(parents=True,exist_ok=True);src.mkdir(exist_ok=True)
  (src/f'face_{row[0]}.svg').write_text(face(row,i))
  for pants in (False,True):clothing(row,pants,src/(f'look_{row[0]}_'+('pants' if pants else 'shirt')+'.svg'))
  export_accessory(hair(row),out/f'hair_{row[0]}.rbxmx')
  if row[0]=='legend':export_accessory(cape(),out/'look_legend_cape.rbxmx')
 frames={}
 for row in DATA:
  mm=hair(row);frames[row[0]]={'attachment':mm['attachment'],'coordinateSpace':'head-local','parts':mm['parts']}
 frames['legend_cape']={'attachment':cape()['attachment'],'coordinateSpace':'torso-local','parts':cape()['parts']}
 (ROOT/'CFRAMES.json').write_text(json.dumps(frames,indent=2))
 (ROOT/'UV_MAP.json').write_text(json.dumps({'torso':TORSO,'right':RIGHT,'left':LEFT,'official_template':'https://create.roblox.com/docs/avatar/classic-clothing'},indent=2))
 (ROOT/'manifest.json').write_text(json.dumps({'sourceSpecRevision':'fe8c7a7','employees':[dict(zip(['id','specialization','gender','hairColor','pantsColor','bodyColor','expression'],r)) for r in DATA],'targetHead':{'size':[1.18,1.20,1.05],'HatAttachment':[0,.5,0]},'runtimeOverrides':{'robo':{'faceTarget':'hair_robo.Handle assembly FaceScreen, front normal -Z','bodyColor':'A5B6CA'},'ghost':{'bodyColor':'9AD9EA','bodyTransparency':.35,'faceTarget':'Head front; native GlowEye geometry also present'},'legend':{'extraAccessory':'look_legend_cape.rbxmx','attachment':'BodyBackAttachment'}},'studioTested':False},indent=2))
if __name__=='__main__':main()
