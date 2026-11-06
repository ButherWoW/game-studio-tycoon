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
def beetle():
 m=model('Mascot_bug_beetle')
 ball(m,'Body',(0,1.40,-.30),(1.90,1.20,1.90),'2386DF')
 ball(m,'Underside',(0,.75,-.30),(1.60,.10,1.70),'6AD9A7')
 ball(m,'MintFace',(0,1.45,.92),(1.90,1.70,.34),'8CEABB')
 # Six stout joint-like legs with feet, not extra eye dots.
 for sign in [-1,1]:
  for t in [-.35,0,.35]:
   n=np.array([sign*.6,-1,t]);h=np.array([.8,.05,.85])
   anchor=np.array([0,.75,-.3])+h*h*n/np.linalg.norm(h*n)
   end=anchor+n*((anchor[1]-.26)/(-n[1]))
   line(m,'Leg',tuple(anchor),tuple(end),.18,'7BE4AF')
   box(m,'Foot',(end[0],.10,end[2]),(.30,.20,.32),'45A68F')
 # Large glasses: layered discs keep every visible volume separate.
 for sign in [-1,1]:
  x=sign*.43
  disk(m,'GlassesRim',x,1.70,1.15,.76,.85,.06,'24365B')
  disk(m,'EyeWhite',x,1.70,1.20,.61,.70,.04,'FAF8EB')
  disk(m,'EyePupil',x,1.70,1.24,.43,.54,.04,'1A2447')
  disk(m,'EyeGleam',x-.06,1.85,1.275,.13,.15,.03,'FFFFFF')
  disk(m,'SmallGleam',x+.07,1.57,1.275,.07,.07,.03,'FFFFFF')
  box(m,'GlassesTemple',(sign*.94,1.70,1.15),(.26,.10,.06),'24365B')
 box(m,'GlassesBridge',(0,1.70,1.15),(.10,.10,.06),'24365B')
 mouth(m,1.08,1.105,'8CEABB')
 for sign in [-1,1]:
  disk(m,'Cheek',sign*.64,1.16,1.12,.19,.10,.03,'9EF2C6')
  line(m,'Antenna',(sign*.40,2.28,.92),(sign*.57,2.68,.92),.09,'6AD9A7')
  ball(m,'AntennaTip',(sign*.60,2.84,.92),(.31,.23,.28),'9CF0C8')
 # Broad blue shell highlights lie above the ellipsoid, not embedded.

 return m
def dog():
 m=model('Mascot_floppy_dog')
 box(m,'Body',(0,.925,0),(1.20,.85,.85),'2386DF')
 for x in [-.42,.42]:
  for z in [-.25,.25]:
   box(m,'Leg',(x,.25,z),(.36,.50,.32),'2386DF')
   box(m,'Paw',(x,.12,z+.18),(.36,.24,.04),'F3E1BE')
 box(m,'Head',(0,2.10,0),(2.0,1.50,1.0),'277FDC')
 for sign in [-1,1]:
  ball(m,'FloppyEar',(sign*1.21,2.12,0),(.42,1.05,.60),'393653')
  box(m,'HeadMark',(sign*.82,2.77,.515),(.17,.12,.03),'4BC3EA')
 disk(m,'Muzzle',0,1.62,.54,1.55,.50,.08,'F3E1BE')
 face(m,2.25,.50,.44)
 disk(m,'Nose',0,1.89,.615,.24,.13,.07,'20253D')
 mouth(m,1.56,.58,'F3E1BE')
 # Floppy-disk shutter sits high on the forehead, like the icon.
 box(m,'Shutter',(0,3.02,.54),(1.04,.50,.08),'C5CBD9',mat='Metal')
 box(m,'ShutterTab',(.30,3.02,.60),(.20,.30,.04),'343B61')
 box(m,'ShutterShine',(-.30,3.06,.595),(.12,.26,.03),'F1F4F5')
 box(m,'ChestLabel',(0,.94,.445),(.76,.42,.04),'F3E1BE')
 for y in [.84,.98,1.12]:
  box(m,'ChestStripe',(0,y,.475),(.52,.035,.02),'C6AF90')
 box(m,'Tail',(0,1.05,-.65),(.20,.20,.45),'2386DF')
 ball(m,'TailTip',(0,1.19,-.935),(.23,.35,.12),'F3E1BE')
 return m
rows=[]
for id,m in [('bug_beetle',beetle()),('floppy_dog',dog())]:
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
