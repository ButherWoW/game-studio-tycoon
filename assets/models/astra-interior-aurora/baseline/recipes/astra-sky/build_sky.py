"""Original V7 third-floor models. Native geometry, no runtime scripts/assets."""
from geometry import *
import subprocess
NIGHT='141A2E';VIOLET='7C4DFF';ICE='00E5FF';TRIM='404968'

def desk():
 m=model('SkyDesk')
 # Four-stud width is deliberate: Config first row spacing8 leaves circulation4.
 box(m,'GlassDesktop',(0,2.88,-.8),(4,.24,2),'9AD4E5',mat='Glass',alpha=.25,collide=True)
 for x in [-1.72,1.72]:
  box(m,'Trestle',(x,1.38,-.8),(.12,2.76,1.55),TRIM,collide=True)
  box(m,'Foot',(x,.08,-.8),(.28,.16,1.85),'silver',collide=True)
 box(m,'RearCrossbar',(0,2.62,-1.6),(3.4,.15,.15),TRIM)
 box(m,'NeonEdge',(0,2.9,.22),(3.8,.07,.035),ICE,mat='Neon')
 box(m,'MonitorFoot',(0,3.06,-1.05),(.78,.12,.45),'silver')
 box(m,'MonitorStem',(0,3.49,-1.22),(.13,.74,.12),TRIM)
 box(m,'WideMonitor',(0,4.1,-1.22),(3.25,1.35,.19),NIGHT)
 box(m,'Screen',(0,4.1,-1.115),(3.03,1.13,.02),'203151',mat='Neon')
 # Original abstract 3D/editor scene, no text or external content.
 box(m,'Timeline',(0,3.64,-1.098),(2.9,.14,.012),VIOLET,mat='Neon')
 for i,h in enumerate([.26,.41,.58,.32,.48]):box(m,'TimelineBar',(-1.15+i*.26,3.83+h/2,-1.086),(.13,h,.012),ICE,mat='Neon')
 for x,y,c in [(.55,4.25,'pink'),(.95,4.35,'gold'),(.77,3.99,'blue')]:box(m,'EditorTile',(x,y,-1.08),(.28,.28,.015),c,r=rot(z=15))
 box(m,'Keyboard',(0,3.055,-.1),(1.9,.11,.47),TRIM)
 for i in range(3):
  for j in range(8):box(m,'Key',(-.77+j*.22,3.125,-.25+i*.15),(.17,.03,.09),'silver')
 ball(m,'Mouse',(1.36,3.119,-.1),(.3,.18,.44),'white')
 box(m,'MouseMat',(1.36,3.016,-.1),(.55,.025,.63),VIOLET)
 # Compact premium tower stands clear of display, on left end.
 box(m,'MiniTower',(-1.35,.7,-.95),(.55,1.4,1),NIGHT)
 for y in [.4,.96]:
  cyl(m,'Fan',(-1.35,y,-.435),.025,.25,ICE,r=rot(y=90),mat='Neon')
  cyl(m,'FanHub',(-1.35,y,-.415),.02,.1,TRIM,r=rot(y=90))
 # Human-scale tucked chair: no Seat, StaffService positions employees.
 cyl(m,'ChairPost',(0,.77,1.05),1.34,.13,'silver')
 for i in range(5):
  t=i*TAU/5;end=(math.sin(t)*.64,.12,1.05+math.cos(t)*.64)
  line(m,'ChairSpoke',(0,.23,1.05),end,.09,TRIM)
  ball(m,'Caster',(end[0],.09,end[2]),(.17,.18,.17),NIGHT)
 ball(m,'SeatCushion',(0,1.5,1.05),(1.57,.31,1.3),NIGHT,collide=True)
 box(m,'ChairBack',(0,2.27,1.65),(1.53,1.42,.2),NIGHT,collide=True)
 box(m,'BackInset',(0,2.28,1.76),(1.24,1.06,.025),VIOLET)
 for x in [-.8,.8]:
  box(m,'ArmStem',(x,1.64,1.05),(.08,.53,.09),'silver')
  box(m,'ArmPad',(x,1.95,1.02),(.15,.12,.65),NIGHT)
 return m

def sound():
 m=model('SoundStudio')
 # 10.8x8.6 glass booth: six-stud open doorway centered on +Z.
 for x in [-5.28,5.28]:
  box(m,'SideGlass',(x,3.5,0),(.08,6.8,8.3),'91B5CA',mat='Glass',alpha=.76,collide=True)
  for z in [-4.18,4.18]:box(m,'CornerPost',(x,3.6,z),(.24,7.2,.24),TRIM,collide=True)
  for y in [.1,7.1]:box(m,'SideRail',(x,y,0),(.24,.2,8.6),TRIM)
 box(m,'BackGlass',(0,3.5,-4.18),(10.32,6.8,.08),'91B5CA',mat='Glass',alpha=.76,collide=True)
 for y in [.1,7.1]:box(m,'BackRail',(0,y,-4.18),(10.8,.2,.24),TRIM)
 for x in [-4.28,4.28]:
  box(m,'FrontGlass',(x,3.5,4.18),(1.76,6.8,.08),'91B5CA',mat='Glass',alpha=.76,collide=True)
  box(m,'DoorPost',(-3.3 if x<0 else 3.3,3.6,4.18),(.2,7.2,.24),TRIM,collide=True)
 box(m,'DoorLintel',(0,7.1,4.18),(10.8,.2,.24),TRIM)
 # Flat sound-absorbing panels on rear inside glass; each bounded and separated.
 for x in [-3.5,-1.2,1.2,3.5]:
  box(m,'AcousticPanel',(x,4.7,-3.99),(1.65,3.05,.22),NIGHT)
  for j in range(3):box(m,'AcousticRib',(x-.5+j*.5,4.7,-3.85),(.13,2.72,.055),VIOLET)
 # Mixer console, tactile colored faders, desk front +Z.
 box(m,'MixingDesk',(0,2.7,-1.72),(5.5,.3,1.8),TRIM,collide=True)
 for x in [-2.25,2.25]:box(m,'ConsoleLeg',(x,1.275,-1.72),(.17,2.55,1.4),'silver',collide=True)
 box(m,'ConsoleSurface',(0,2.87,-1.72),(4.5,.035,1.42),NIGHT)
 for i in range(9):
  x=-1.9+i*.46
  box(m,'FaderTrack',(x,2.9,-1.48),(.055,.025,.73),'silver')
  box(m,'FaderCap',(x,2.94,-1.65+(i%3)*.18),(.2,.07,.12),ICE if i%2==0 else 'gold')
  cyl(m,'MixKnob',(x,2.97,-2.15),.12,.13,VIOLET)
 # Pair of monitor speakers on rear cabinet, with cones facing operator.
 for x in [-3.9,3.9]:
  box(m,'SpeakerStand',(x,1.15,-2.7),(.4,2.3,.5),'silver',collide=True)
  box(m,'SpeakerFoot',(x,.08,-2.7),(1.3,.16,1.2),TRIM,collide=True)
  box(m,'Speaker',(x,3,-2.7),(1.3,1.4,1.1),NIGHT)
  for y,d in [(2.8,.67),(3.38,.29)]:
   cyl(m,'SpeakerCone',(x,y,-2.13),.04,d,'metal',r=rot(y=90))
   cyl(m,'SpeakerDustcap',(x,y,-2.1),.025,d*.38,ICE,r=rot(y=90))
 # Recording corner to right, leaving center route free from entry.
 cyl(m,'MicFoot',(3.75,.06,1.6),.12,.86,TRIM,collide=True)
 cyl(m,'MicStand',(3.75,1.86,1.6),3.6,.075,'silver')
 line(m,'MicBoom',(3.75,3.4,1.6),(2.95,3.68,1.6),.065,'silver')
 cyl(m,'Microphone',(2.89,3.65,1.6),.55,.22,'metal',r=rot(z=70))
 for yy in [3.51,3.64,3.77]:cyl(m,'MicGrille',(2.89,yy,1.6),.03,.23,TRIM)
 box(m,'PopFilter',(2.6,3.62,1.7),(.04,.48,.48),NIGHT)
 # A compact stool in front of mixer, separated from desk edge.
 cyl(m,'StoolStem',(0,.74,.25),1.3,.15,'silver')
 cyl(m,'StoolFoot',(0,.08,.25),.16,.95,TRIM)
 cyl(m,'StoolSeat',(0,1.5,.25),.22,1.3,VIOLET,collide=True)
 box(m,'StudioLight',(0,6.95,0),(4.5,.05,.13),ICE,mat='Neon',light=(9,.25,ICE))
 return m

def art():
 m=model('ArtWall')
 # Free-standing 13.6-wide thin gallery at exact Config center, facing +Z.
 for x in [-6.3,6.3]:box(m,'GalleryPost',(x,3.9,-.22),(.16,7.8,.28),TRIM,collide=True)
 for x in [-6.3,6.3]:box(m,'GalleryFoot',(x,.05,0),(.9,.1,.9),TRIM,collide=True)
 for x,c in [(-4.4,VIOLET),(0,ICE),(4.4,'pink')]:
  box(m,'ArtFrame',(x,4.65,0),(4,5.3,.24),TRIM,collide=True)
  box(m,'Canvas',(x,4.65,.14),(3.7,5,.025),NIGHT)
  # Three original geometric compositions, physical native parts.
  if x<0:
   for dx,yy,w in [(-.85,3.7,1.1),(0,4.5,1.4),(.7,5.4,1.0)]:box(m,'FloatingTile',(x+dx,yy,.17),(w,w,.025),c,r=rot(z=15))
   ball(m,'Moon',(x+.8,6.25,.175),(.75,.75,.03),'gold')
  elif x==0:
   for j in range(5):line(m,'Wave',(x-1.3+j*.55,3.0,.18),(x-1.3+j*.55,5.3+math.sin(j)*.7,.18),.14,c)
   ball(m,'Orbit',(x+.7,6.25,.18),(.6,.6,.035),'pink')
  else:
   for j in range(4):box(m,'PixelMountain',(x-.95+j*.62,3.25+j*.52,.17),(.62,1.1+j*.35,.025),c)
   box(m,'Horizon',(x,6.2,.18),(2.9,.08,.03),'gold')
  box(m,'FrameGlow',(x,7.33,0),(3.9,.05,.12),c,mat='Neon')
 return m

def shell():
 m=model('Skyscraper')
 box(m,'Floor',(0,.01,0),(58,.02,58),NIGHT,collide=True)
 # A subtle large-scale floor grid; shallow native strips, not textures.
 for x in range(-24,25,8):box(m,'FloorJoint',(x,.022,0),(.015,.004,57.7),'252D46')
 for z in range(-24,25,8):box(m,'FloorJoint',(0,.022,z),(57.7,.004,.015),'252D46')
 # Panoramic glazing around perimeter. All walls finish at Y13.
 for x in [-29.75,29.75]:
  for y,h in [(.55,1.1),(12.5,1)]:box(m,'SideWallBand',(x,y,0),(.5,h,59.5),NIGHT,collide=True)
  box(m,'PanoramicSide',(x,6.5,0),(.08,10.8,59.5),'6A8CA5',mat='Glass',alpha=.78,collide=True)
  for z in [-24,-12,0,12,24]:box(m,'WindowMullion',(x,6.5,z),(.5,10.8,.14),TRIM)
  box(m,'SideNeon',(x+(.29 if x<0 else -.29),1.2,0),(.05,.07,59.2),VIOLET,mat='Neon')
 for y,h in [(.55,1.1),(12.5,1)]:box(m,'RearWallBand',(0,y,-29.75),(59.5,h,.5),NIGHT,collide=True)
 box(m,'PanoramicRear',(0,6.5,-29.75),(59.5,10.8,.08),'6A8CA5',mat='Glass',alpha=.78,collide=True)
 for x in [-24,-12,0,12,24]:box(m,'RearMullion',(x,6.5,-29.75),(.14,10.8,.5),TRIM)
 box(m,'RearNeon',(0,1.2,-29.46),(59.2,.07,.05),ICE,mat='Neon')
 # +Z aperture exactly24x9; code supplies glazing.
 box(m,'EntranceLintel',(0,11,29.75),(60,4,.5),NIGHT,collide=True)
 for x in [-21,21]:
  box(m,'FrontBand',(x,.55,29.75),(18,1.1,.5),NIGHT,collide=True)
  box(m,'FrontGlazing',(x,5.05,29.75),(18,7.9,.08),'6A8CA5',mat='Glass',alpha=.78,collide=True)
  for dx in [-8.9,0,8.9]:box(m,'FrontMullion',(x+dx,5,29.75),(.14,8,.5),TRIM)
 # Only this top-floor shell owns a roof. Continuous roof13..14 covers full60x60.
 box(m,'Roof',(0,13.5,0),(60,1,60),NIGHT,collide=True)
 for x in [-12,12]:
  for z in [-15,8]:
   box(m,'LampCase',(x,12.76,z),(5,.25,1.15),TRIM)
   box(m,'LampDiffuser',(x,12.615,z),(4.7,.04,.93),'C3D1FF',mat='Neon',light=(22,.45,'B8D5FF'))
 return m

ASSETS={m['name']:m for m in [shell(),desk(),sound(),art()]}
# Exact footprint center, without a helper Part.
for p in ASSETS['SkyDesk']['parts']:p['p']=(p['p'][0],p['p'][1],p['p'][2]+.0125)
DESKS=[(-3,-20),(5,-20),(13,-20),(21,-20),(-18,-8),(-9,-8),(0,-8),(9,-8),(18,-8),(-6,4),(6,4)]
LAYOUT=[('Skyscraper',(0,0,0),0)]+[('SkyDesk',(x,0,z),0) for x,z in DESKS]+[('SoundStudio',(-18,0,14),0),('ArtWall',(15,0,16),0)]
FULL=model('AstraSky_ConfigLayout')
for i,(name,pos,yaw) in enumerate(LAYOUT):put(FULL,ASSETS[name],pos,yaw,name+('_'+str(i) if name=='SkyDesk' else ''))
if __name__=='__main__':
 for n,m in ASSETS.items():export(m,ROOT/'models'/f'{n}.rbxmx')
 export(FULL,ROOT/'Sky_Assembled.rbxmx')
 templates=model('Upgrades')
 for m in ASSETS.values():put(templates,m)
 export(templates,ROOT/'Sky_Upgrades_Import.rbxmx')
 for f in list((ROOT/'models').glob('*.rbxmx'))+[ROOT/'Sky_Assembled.rbxmx',ROOT/'Sky_Upgrades_Import.rbxmx']:
  project=ROOT/'source'/'convert.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(f.with_suffix('.rbxm'))],check=True)
 project.unlink()
 (ROOT/'layout.json').write_text(json.dumps({'source':'origin/main src/shared/Config/Upgrades.luau stage4','localBaseY':0,'gameFloorY':28,'entry':{'x':[-12,12],'height':9,'z':29.75},'elevator':{'min':[-23,0,21],'max':[-17,7,27]},'placements':[{'model':n,'position':p,'yaw':y} for n,p,y in LAYOUT]},indent=2))
