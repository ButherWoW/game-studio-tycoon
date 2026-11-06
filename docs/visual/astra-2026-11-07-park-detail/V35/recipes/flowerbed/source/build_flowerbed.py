"""Native, disjoint ornamental flowers. No overlapping rounded primitive helpers."""
from geometry import *
import subprocess

def build():
 m=model('Flowerbed')
 # Soil is a circle-like sequence of non-overlapping horizontal row strips.
 # Its conservative OBBs remain inside radius1.45, clear of every border stone.
 for i in range(11):
  z=(i-5)*.26; extent=abs(z)+.13
  width=2*math.sqrt(1.45**2-extent**2)
  box(m,'Earth_Row_%02d'%i,(0,.1,z),(width,.2,.259),'694B39',collide=True)
 #16 separate tangential sandstone blocks, irregular tones but symmetric envelope.
 for i in range(16):
  a=i*TAU/16; x,z=1.73*math.sin(a),1.73*math.cos(a)
  box(m,'Border_Stone_%02d'%i,(x,.16,z),(.59,.32,.34),['B9B5A3','C9C3AD','A8AE9D','BEB9A7'][i%4],r=rot(y=i*22.5),mat='Concrete',collide=True)

 def stem(tag,x,z,top):
  box(m,tag+'_Stem',(x,(.21+top)/2,z),(.044,top-.21,.044),'397B41')
 def leaf(tag,x,z,y,side=1,angle=0):
  # Deliberate .02+ clearance from stem; thin leaves remain separate native ellipsoids.
  dx=.20*side
  ball(m,tag+'_Leaf',(x+dx,y,z),(.23,.055,.105),'65A34E')
  box(m,tag+'_Petiole',(x+side*.0535,y,z),(.063,.026,.026),'4E9148')
 def tulip(tag,x,z,h,col):
  stem(tag,x,z,h-.195); leaf(tag+'L',x,z,.51,-1,-12);leaf(tag+'R',x,z,.64,1,12)
  ball(m,tag+'_Cup',(x,h-.115,z),(.33,.14,.24),col)
  for j in range(3):
   ball(m,tag+'_Petal_%d'%j,(x+(j-1)*.115,h+.055,z),(.10,.15+(j%2)*.04,.22),col)
 def daisy(tag,x,z,h):
  stem(tag,x,z,h-.065);leaf(tag,x,z,.48,1,10)
  ball(m,tag+'_GoldenDisc',(x,h,z),(.11,.08,.11),'FFD15B')
  for j in range(6):
   a=j*TAU/6
   ball(m,tag+'_WhiteRay_%d'%j,(x+.17*math.cos(a),h,z+.17*math.sin(a)),(.15,.055,.075),'FFF8E7',r=rot(y=-j*60))
 def poppy(tag,x,z,h):
  stem(tag,x,z,h-.065);leaf(tag+'L',x,z,.46,-1,5);leaf(tag+'R',x,z,.58,1,-5)
  ball(m,tag+'_DarkDisc',(x,h+.025,z),(.10,.07,.10),'433444')
  for j in range(4):
   a=j*TAU/4
   ball(m,tag+'_ScarletPetal_%d'%j,(x+.155*math.cos(a),h,z+.155*math.sin(a)),(.18,.07,.12),'F16C60' if j%2 else 'DC4555',r=rot(y=-j*90))
 def lavender(tag,x,z,h):
  stem(tag,x,z,h-.32);leaf(tag+'L',x,z,.43,-1,-15);leaf(tag+'R',x,z,.55,1,15)
  # Three stacked florets taper upwards, disjoint even in conservative OBB audit.
  for j,(w,col) in enumerate([(.17,'8C73C5'),(.14,'A48BDC'),(.105,'C2A8EC')]):
   ball(m,tag+'_Floret_%d'%j,(x,h-.265+j*.115,z),(w,.10,w),col)

 tulip('Tulip_Rose',-.77,.43,1.14,'E66B9F')
 tulip('Tulip_Amber',.53,-.63,1.27,'F6B957')
 daisy('Daisy_Tall',-.57,-.65,1.06)
 daisy('Daisy_Low',.62,.62,.85)
 poppy('Poppy_Coral',-.02,.15,1.08)
 poppy('Poppy_Scarlet',1.02,-.04,.94)
 lavender('Lavender_West',-1.07,-.12,1.35)
 lavender('Lavender_Back',-.05,-1.05,1.385)
 lavender('Lavender_Front',-.12,1.02,1.22)
 for i,(x,z,w) in enumerate([(-.91,.96,.15),(.98,.89,.17),(.91,-.98,.12),(-1.01,-.98,.13),(.30,.91,.11),(-.36,-.20,.10)]):
  ball(m,'Pebble_%02d'%i,(x,.245,z),(w,.08,w*.77),'AEB2A0')
 for i,(x,z,w) in enumerate([(-.80,-.35,.12),(.45,-1.0,.14),(.82,.28,.10),(-.50,.84,.11)]):
  ball(m,'Turned_Loam_%02d'%i,(x,.23,z),(w,.06,w*.8),['7C5941','5C4234'][i%2])
 return m

if __name__=='__main__':
 m=build();dest=ROOT/'models/Flowerbed.rbxmx';export(m,dest)
 pr=ROOT/'source/convert.project.json';pr.write_text(json.dumps({'name':'Flowerbed','tree':{'$path':str(dest)}}))
 subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(dest.with_suffix('.rbxm'))],check=True);pr.unlink()
 (ROOT/'model-manifest.json').write_text(json.dumps({'model':m,'nativeOnly':True,'flowerSpecies':['tulip','daisy','lavender','poppy'],'front':'+Z'},indent=2)+'\n')
