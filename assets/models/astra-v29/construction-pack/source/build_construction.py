from geometry import *
import subprocess
ORANGE='F59B32';WHITE='F1EEE3';PIPE='687E94';DARK='253247';GOLD='FFC93C';BLUE='3D7BFF'
def scaffold():
 m=model('Construction_Scaffold')
 for x in [-5.16,5.16]:
  for z in [-1.01,1.01]:box(m,'VerticalPole',(x,7.5,z),(.18,15,.18),PIPE,mat='Metal')
 for y in [5,10]:box(m,'Deck',(0,y,0),(10.14,.16,1.84),ORANGE)
 for y in [6.15,11.15]:
  for z in [-1.01,1.01]:box(m,'GuardRail',(0,y,z),(10.14,.14,.14),PIPE,mat='Metal')
 for y in [.3,12.0]:line(m,'Brace',(-4.95,y,-1.01),(4.95,y+2.5,-1.01),.1,PIPE,mat='Metal')
 return m

def fence():
 m=model('Construction_Fence');box(m,'OrangePanel',(0,1.7,0),(8,3.4,.2),ORANGE)
 # White applique panels share only the front contact plane with the orange board.
 for x in [-2.65,0,2.65]:box(m,'WhiteStripe',(x,1.7,.15),(.55,3.1,.1),WHITE)
 return m

def sign():
 m=model('Construction_Sign')
 for x in [-2.8,2.8]:box(m,'Post',(x,.55,.08),(.24,1.1,.32),PIPE,mat='Metal')
 box(m,'Screen',(0,3.4,-.04),(7.4,4.2,.18),DARK)
 # Frame:5.5overallheight,7.5width; all rails butt jointed.
 for x in [-3.725,3.725]:box(m,'SideFrame',(x,3.4,-.04),(.05,4.2,.3),ORANGE)
 for y in [1.25,5.55]:box(m,'Frame',(0,y,-.04),(7.5,.1,.3),ORANGE)
 # Correct targetheight5.5 by lowering frame/body .1; posts remain grounded.
 for p in m['parts']:
  if p['name']!='Post':p['p']=(p['p'][0],p['p'][1]-.1,p['p'][2])
 return m

def crane():
 m=model('Construction_Crane');box(m,'Foundation',(0,.5,0),(6,1,6),DARK,mat='Concrete')
 for x in [-.9,.9]:
  for z in [-.9,.9]:box(m,'MastPole',(x,28,z),(.22,54,.22),GOLD,mat='Metal')
 # Braces stay between poles; horizontal collars and diagonal braces are in separate height bands.
 for k in range(8):
  y=1.6+k*6.5
  for z in [-.9,.9]:line(m,'MastBrace',(-.72,y,z),(.72,y+4.9,z),.1,ORANGE,mat='Metal')
 for y in [7,20,33,46]:
  for z in [-.9,.9]:box(m,'MastTie',(0,y,z),(1.58,.16,.16),ORANGE,mat='Metal')
 for x in [-.65,.65]:
  box(m,'JibForward',(x,55.5,-21.5),(.22,1,45),GOLD,mat='Metal')
  box(m,'JibCounter',(x,55.5,4.5),(.22,1,7),GOLD,mat='Metal')
 for z in [-42,-34,-26,-18,-10,-2,3,7]:box(m,'JibTie',(0,55.5,z),(1.08,.2,.2),ORANGE,mat='Metal')
 box(m,'Counterweight',(0,54.5,7),(3.4,1,2.4),DARK,mat='Concrete')
 box(m,'CabBase',(2.2,52.08,0),(2.2,.16,2.4),BLUE)
 for x in [1.16,3.24]:box(m,'CabGlassSide',(x,53.06,0),(.12,1.8,2.4),'79D5ED',mat='Glass',alpha=.45)
 for z in [-1.14,1.14]:box(m,'CabGlassEnd',(2.2,53.06,z),(1.96,1.8,.12),'79D5ED',mat='Glass',alpha=.45)
 box(m,'CabRoof',(2.2,54.04,0),(2.2,.16,2.4),BLUE)
 box(m,'Trolley',(0,54.8,-32),(1.6,.4,.8),DARK)
 box(m,'Cable',(0,50.3,-32),(.08,8.6,.08),PIPE,mat='Metal')
 box(m,'HookStem',(0,45.8,-32),(.14,.4,.14),GOLD)
 box(m,'Load',(0,44.6,-32),(2.8,2,2.8),ORANGE)
 return m
ASSETS={m['name']:m for m in [scaffold(),fence(),crane(),sign()]}
def bounds(ps):
 lo=[1e9]*3;hi=[-1e9]*3
 for p in ps:
  h=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-h[i]);hi[i]=max(hi[i],p['p'][i]+h[i])
 return lo,hi
if __name__=='__main__':
 for n,m in ASSETS.items():
  f=ROOT/'models'/(n+'.rbxmx');export(m,f);pr=ROOT/'source'/'convert.project.json';pr.write_text(json.dumps({'name':n,'tree':{'$path':str(f)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(f.with_suffix('.rbxm'))],check=True)
 pr.unlink();(ROOT/'model-manifest.json').write_text(json.dumps(ASSETS,indent=2)+'\n')
