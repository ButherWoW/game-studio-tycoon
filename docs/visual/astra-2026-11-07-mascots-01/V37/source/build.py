from geometry import *
from render_geometry import preview
from convex_support import parse,audit,support,np
import subprocess,json
ROOT=Path(__file__).resolve().parents[1]
for f in ['models','previews','references']:(ROOT/f).mkdir(exist_ok=True)
def disk(m,n,x,y,z,w,h,depth,c):
 return part(m,n,(x,y,z),(depth,h,w),c,shape='cyl',r=rot(y=90))
def face(m,y,z,spread=.40):
 for sign in [-1,1]:
  x=sign*spread
  disk(m,'EyeWhite',x,y,z+.035,.60,.70,.07,'FFF9EC')
  disk(m,'EyePupil',x,y,z+.09,.39,.53,.04,'14223E')
  disk(m,'BlueIris',x,y-.14,z+.125,.28,.20,.03,'2499DC')
  disk(m,'EyeGleam',x-.055,y+.17,z+.125,.13,.15,.03,'FFFFFF')
  box(m,'Brow',(x,y+.46,z+.025),(.31,.08,.05),'273047')
def mouth(m,y,z,color):
 # A flat upper lip and three decreasing rows make a smiling silhouette,
 # without an overlapping mask or a protruding rectangular face patch.
 for dy,w in [(.07,.43),(0,.35),(-.07,.20)]:
  box(m,'SmileRow',(0,y+dy,z+.02),(w,.07,.04),'542338')
 disk(m,'Tongue',0,y-.04,z+.055,.19,.07,.03,'F47889')
def cat():
 m=model('Mascot_pixel_cat')
 box(m,'Body',(0,1.0,0),(1.20,.80,1.0),'168BDB')
 for x in [-.43,.43]:
  for z in [-.32,.32]:
   box(m,'Leg',(x,.30,z),(.38,.60,.36),'1978C9')
   box(m,'Paw',(x,.12,z+.195),(.38,.24,.03),'46DCE7')
   for dx in [-.09,.09]:box(m,'ToeLine',(x+dx,.10,z+.217),(.025,.13,.014),'147CB4')
 box(m,'Head',(0,2.13,0),(1.85,1.46,1.15),'237ED8')
 # Symmetric stepped pixel ears, all tiers share support faces.
 for sign in [-1,1]:
  for j,(w,h,y)in enumerate([(.48,.20,2.96),(.38,.20,3.16),(.25,.16,3.34)]):
   box(m,'EarTier',(sign*.61,y,0),(w,h,.45),'237ED8')
  box(m,'InnerEar',(sign*.61,3.12,.24),(.24,.30,.03),'F583C3')
 # Muzzle and all facial graphics lie on separate touching planes.
 box(m,'Muzzle',(0,1.67,.590),(1.18,.40,.03),'55DCE2')
 face(m,2.25,.575,.43)
 mouth(m,1.70,.605,'55DCE2')
 box(m,'Nose',(0,2.00,.595),(.18,.08,.04),'152A4A')
 for sign in [-1,1]:
  for yy in [1.66,1.82,1.98]:box(m,'Whisker',(sign*.94,yy,.595),(.48,.035,.04),'153A61')
 box(m,'ForeheadMark',(0,2.72,.59),(.22,.24,.03),'50C6ED')
 for sign in [-1,1]:
  box(m,'TempleMark',(sign*.82,2.64,.59),(.16,.16,.03),'50C6ED')
 box(m,'TailBase',(.85,.90,-.60),(.50,.30,.20),'237ED8')
 box(m,'TailStep1',(1.15,1.25,-.60),(.10,.40,.20),'237ED8')
 box(m,'TailStep2',(1.38,1.50,-.60),(.46,.10,.20),'237ED8')
 box(m,'TailStep3',(1.61,1.80,-.60),(.10,.50,.20),'237ED8')
 box(m,'TailTip',(1.61,2.10,-.60),(.10,.10,.20),'55DCE2')
 return m
def cup():
 m=model('Mascot_coffee_cup')
 cyl(m,'Body',(0,1.45,0),1.75,1.80,'F5E4C4')
 # Boots and short legs; bottom of cup .575, leg top .575.
 for sign in [-1,1]:
  box(m,'Leg',(sign*.48,.4375,0),(.22,.275,.25),'E5D1A8')
  box(m,'Boot',(sign*.48,.15,.16),(.53,.30,.70),'1C9BD5')
  box(m,'BootToe',(sign*.48,.15,.53),(.53,.30,.04),'3DC9EF')
  box(m,'BootShine',(sign*.48,.312,.32),(.28,.024,.22),'A0ECF0')
 # Top surface and gold ring as disjoint annulus sectors; Body supports rim.
 for j in range(20):
  t=TAU*j/20
  box(m,'GoldenRim',(.91*math.sin(t),2.39,.91*math.cos(t)),(.246,.13,.15),'F4BC34',r=rot(y=j*18))
 cyl(m,'Coffee',(0,2.34,0),.03,1.58,'71351C')
 for x,z in [(-.30,.12),(.20,-.20)]:
  ball(m,'Crema',(x,2.365,z),(.40,.02,.15),'C8894F')
 for sign in [-1,1]:
  for j in range(4):
   ball(m,'Steam',(sign*.25+.04*math.sin(j*1.3),2.60+j*.17,-.10),(.07,.16,.07),'E8E0D2',alpha=.25)
 # Face plaque has same ivory as body. It is tangent at center, outside the cup.
 disk(m,'FacePlaque',0,1.48,.94,1.56,1.38,.08,'F5E4C4')
 face(m,1.67,.98,.40)
 mouth(m,1.10,.98,'F5E4C4')
 for sign in [-1,1]:
  disk(m,'Cheek',sign*.67,1.30,1.00,.22,.13,.04,'F08A82')
 # Handle: thick blue rectangular ring, open center, no hidden intersection with Body.
 # Leftmost bridge ends touch the cylinder's extreme right support plane.
 for y in [.99,2.15]:
  box(m,'HandleBridge',(.975,y,0),(.15,.18,.30),'138FD3')
 for j in range(12):
  theta=math.radians(-82.5+j*15)
  part(m,'CurvedHandle',(1.05+.58*math.cos(theta),1.57+.58*math.sin(theta),0),(.117,.18,.30),'138FD3',r=rot(z=math.degrees(theta)+90))
 # Cream fists on each side, separated from cup surface with tangent planes.
 for sign in [-1,1]:
  box(m,'Arm',(sign*1.02,.90,.48),(.24,.20,.25),'EAD5AF')
  box(m,'Fist',(sign*1.27,.90,.48),(.26,.35,.35),'F8E7C7')
  box(m,'FistShine',(sign*1.27,.90,.665),(.16,.19,.02),'FFF8E7')
 return m
rows=[]
for id,m in [('pixel_cat',cat()),('coffee_cup',cup())]:
 # Exact footprint support bounds. Body remains first / PrimaryPart.
 temp=ROOT/'models'/'temp.rbxmx';export(m,temp);ps=parse(temp);lo=[min(support(p,-np.eye(3)[i])[i]for p in ps)for i in range(3)];hi=[max(support(p,np.eye(3)[i])[i]for p in ps)for i in range(3)]
 shift=[(lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2]
 for p in m['parts']:p['p']=tuple(p['p'][i]-shift[i]for i in range(3))
 path=ROOT/'models'/('Mascot_'+id+'.rbxmx');export(m,path);temp.unlink()
 ps=parse(path);cert,bad=audit(ps);assert not bad,(id,bad);assert len(ps)<=100
 project=ROOT/'source/build.project.json';project.write_text(json.dumps({'name':m['name'],'tree':{'$path':str(path)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(path.with_suffix('.rbxm'))],check=True,capture_output=True);project.unlink()
 (ROOT/(id+'_CERTIFICATES.json')).write_text(json.dumps(cert,indent=2)+'\n')
 rows.append({'id':id,'parts':len(ps),'dimensionsXYZ':[hi[i]-lo[i]for i in range(3)],'pairs':len(cert),'overlaps':bad,'PrimaryPart':'Body','pivotXYZ':[0,0,0],'allAnchored':True,'runtimeTested':False})
 for label,yaw in [('Front',0),('ThreeQuarter',35),('Rear',150)]:
  preview(m['parts'],ROOT/'previews'/('Mascot_'+id+'_'+label+'.png'),yaw=yaw,elev=15,target=(0,1.65,0),span=4.8,W=900,H=900)
(ROOT/'VALIDATION.json').write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(rows,indent=2))
