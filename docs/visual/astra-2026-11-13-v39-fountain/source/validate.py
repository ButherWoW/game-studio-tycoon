from pathlib import Path
import json,itertools,xml.etree.ElementTree as ET
import numpy as np
from convex_support import parse,separate,gap,support

ROOT=Path(__file__).resolve().parents[1]
path=ROOT/'models/Fountain.rbxmx';parts=parse(path);visible=[p for p in parts if p['alpha']<.99]
root=ET.parse(path).getroot();classes={e.get('class') for e in root.iter('Item')}
assert classes <= {'Model','Part','WedgePart'}
assert all(e.findtext('Properties/bool[@name="Anchored"]')=='true' for e in root.iter('Item') if e.get('class')!='Model')
bad=[];count=0;mingap=1e9
for a,b in itertools.combinations(visible,2):
    cert=separate(a,b,tol=3e-6)
    if cert is None:bad.append([a['name'],b['name']])
    else:
        assert gap(a,b,cert['axis'])>=-3e-6
        mingap=min(mingap,cert['gap'])
    count+=1
lo=[min(support(p,-np.eye(3)[i])[i] for p in visible) for i in range(3)]
hi=[max(support(p,np.eye(3)[i])[i] for p in visible) for i in range(3)]
report={'parts':len(parts),'visibleParts':len(visible),'pairChecks':count,'unresolvedPairs':bad,'minCertifiedGap':mingap,'bounds':[lo,hi],'classes':sorted(classes),'studioTested':False,'physicsFPS':None}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report),flush=True)
assert not bad
assert abs(lo[1])<1e-6
