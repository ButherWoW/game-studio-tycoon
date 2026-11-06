from pathlib import Path
import xml.etree.ElementTree as E
import json
R=Path(__file__).resolve().parents[1]/'models'
reports=[]
def parts(f):
 out=[]
 for e in E.parse(f).iter('Item'):
  if e.get('class')not in['Part','Seat','WedgePart']:continue
  p=e.find('Properties');c=p.find("CoordinateFrame[@name='CFrame']");v=p.find("Vector3[@name='size']")
  xyz=[float(c.findtext(a))for a in'XYZ'];s=[float(v.findtext(a))for a in'XYZ'];r=[[float(c.findtext(f'R{i}{j}'))for j in range(3)]for i in range(3)];h=[sum(abs(r[i][j])*s[j]/2 for j in range(3))for i in range(3)]
  out.append(dict(name=p.findtext("string[@name='Name']"),p=xyz,s=s,lo=[xyz[i]-h[i]for i in range(3)],hi=[xyz[i]+h[i]for i in range(3)],alpha=float(p.findtext("float[@name='Transparency']",'0')),mat=int(p.findtext("token[@name='Material']",'272'))))
 return out
for f in sorted(R.glob('*.rbxmx')):
 ps=parts(f);hits=[]
 for w in [p for p in ps if p['mat']==1568]:
  axis=min(range(3),key=lambda i:w['hi'][i]-w['lo'][i]);uv=[i for i in range(3)if i!=axis]
  for p in ps:
   if p['alpha']>.01:continue
   overlap=[min(p['hi'][i],w['hi'][i])-max(p['lo'][i],w['lo'][i])for i in uv]
   gap=max(0,p['lo'][axis]-w['hi'][axis],w['lo'][axis]-p['hi'][axis])
   if min(overlap)>1e-5 and gap<2:
    hits.append((w['name'],p['name'],p['p'],[round(v,4)for v in overlap],round(gap,3)))
 permitted={'EntranceColumn','EntranceHeader','EntranceLintel','PremiumEntrySoffit','FrontMullion','RearMullion','SideMullion','WindowMullion','WindowTransom','SideTransom','SideNeon','RearNeon'}
 blockers=[h for h in hits if h[1] not in permitted];assert not blockers,(f.stem,blockers)
 reports.append({'model':f.stem,'projectedOverlapAreaThreshold':0,'normalSearchDistanceStuds':2,'opaqueNonFrameDecorBlockers':blockers,'retainedArchitecturalContacts':hits})
 print(f.stem,'zero-threshold PASS')
(R.parent/'ZERO_THRESHOLD_REVIEW.json').write_text(json.dumps({'status':'PASS','method':'Every positive projected AABB overlap within 2 studs normal distance is inspected; only explicit architecture names permitted. No percentage-area threshold. Thin base neon retained as architectural edge trim, not wall art.','models':reports},indent=2)+'\n')
