from pathlib import Path
import json,sys
from copy import deepcopy
from convex_support import *
ROOT=Path(__file__).resolve().parents[1]
REPO=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/private/tmp/game-studio-tycoon-visual-upload-20261104')
placements={'GameGallery':{'floor':2,'localTranslation':[0,3,-28.8],'zone':[-5,3,-29,5,8,-28.6]},'PanoramaCorner':{'floor':3,'localTranslation':[22,.025,8],'zone':[17,0,5,27,5,11]}}
report=[]
for name,entry in placements.items():
 ps=parse(ROOT/'models'/(name+'.rbxmx'));offset=np.array(entry['localTranslation'])
 for p in ps:p['p']+=offset
 lo=[min(support(q,-np.eye(3)[i])[i]for q in ps)for i in range(3)];hi=[max(support(q,np.eye(3)[i])[i]for q in ps)for i in range(3)]
 zone=entry['zone'];assert all(lo[i]>=zone[i]-1e-6 and hi[i]<=zone[i+3]+1e-6 for i in range(3))
 # Lift 6x6, its southern approach and front purchase band: no new footprints enter.
 reserved=[[-23,21,-17,27],[-23,15,-17,21],[-29,22,29,29]]
 assert not any(min(hi[0],b[2])>max(lo[0],b[0])+1e-6 and min(hi[2],b[3])>max(lo[2],b[1])+1e-6 for b in reserved)
 shell=parse(ROOT/'source'/(('Floor' if entry['floor']==2 else 'Skyscraper')+'_baseline.rbxmx'))
 # Exact support-plane certificates for every new-part / existing-shell pair.
 cert,bad=audit(ps+shell);newrefs={p['ref'] for p in ps};crossbad=[]
 # audit reports names only. Check each pair independently to avoid confusing same referents.
 for a in ps:
  for b in shell:
   _,badpair=audit([a,b])
   if badpair:crossbad.append([a['name'],b['name']])
 assert not crossbad,(name,crossbad)
 report.append({'name':name,**entry,'boundsAfterTranslation':[lo,hi],'liftAndApproachClear':True,'existingShellCrossIntersections':crossbad,'StudioTested':False})
(ROOT/'LAYOUT_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
