"""Original flat native-Part cartridge mosaic; no raster resources or scripts."""
from geometry import *
import subprocess
PALETTE={'N':'182741','B':'3D7BFF','C':'70E8EE','G':'FFC93C'}
# Top-down rows run -Z to +Z. Gold edge contacts mark our own cartridge silhouette.
PATTERN=['NNBBBBNN','NBBBBBBN','NBCCCCBN','NBCCCCBN','NBBBBBBN','NBBBBBBN','NBGBBGBN','NNBBBBNN']
def build():
 m=model('SpawnPad')
 box(m,'Base',(0,.1,0),(8,.2,8),'202B48',collide=True)
 # Uniformly flush .32 surface; all inlay cells share the same elevation.
 for z in [-3.9,3.9]:box(m,'NeonFrame',(0,.26,z),(8,.12,.2),'00DDE8',mat='Neon',collide=True)
 for x in [-3.9,3.9]:box(m,'NeonFrame',(x,.26,0),(.2,.12,7.6),'00DDE8',mat='Neon',collide=True)
 width=7.6/len(PATTERN[0]);depth=7.6/len(PATTERN)
 # Merge horizontal runs, reducing native Parts without changing the exact tiling.
 for iz,row in enumerate(PATTERN):
  start=0
  while start<len(row):
   end=start+1
   while end<len(row) and row[end]==row[start]:end+=1
   x=-3.8+(start+end)*width/2;z=-3.8+(iz+.5)*depth
   box(m,'Inlay_'+row[start],(x,.26,z),((end-start)*width,.12,depth),PALETTE[row[start]],collide=True)
   start=end
 return m
ASSETS={'SpawnPad':build()}
def bounds(ps):
 lo=[1e9]*3;hi=[-1e9]*3
 for p in ps:
  ex=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-ex[i]);hi[i]=max(hi[i],p['p'][i]+ex[i])
 return lo,hi
if __name__=='__main__':
 m=ASSETS['SpawnPad'];dest=ROOT/'models/SpawnPad.rbxmx';export(m,dest)
 pr=ROOT/'source/convert.project.json';pr.write_text(json.dumps({'name':'SpawnPad','tree':{'$path':str(dest)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(dest.with_suffix('.rbxm'))],check=True);pr.unlink()
 (ROOT/'model-manifest.json').write_text(json.dumps({'model':m,'palette':PALETTE,'pattern':PATTERN,'topY':.32,'nativeOnly':True},indent=2)+'\n')
