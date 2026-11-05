"""Conservative candidate check only; does not place anything in the game.
Inputs currentConfigstage4 positions + actualSkyasset bounds and shell XML.
Preserves4studclearance to interiors, full6x6body,4studfrontapron.
"""
from pathlib import Path
import json,re,xml.etree.ElementTree as ET,itertools,hashlib,math
ROOT=Path(__file__).resolve().parents[1]
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--repo',type=Path,default=next((p for p in ROOT.parents if (p/'src/shared/Config/Upgrades.luau').exists()),Path('/private/tmp/game-studio-tycoon-visual-upload-20261104')))
REPO=parser.parse_args().repo
def xmlbounds(path):
 out=[]
 for it in ET.parse(path).getroot().findall('.//Item'):
  if it.attrib['class'] not in ['Part','Seat']:continue
  pr={x.attrib['name']:x for x in it.find('Properties')};cf=pr['CFrame'];p=[float(cf.find(k).text) for k in 'XYZ'];r=[float(cf.find(f'R{i}{j}').text) for i in range(3) for j in range(3)];s=[float(pr['size'].find(k).text) for k in 'XYZ'];e=[sum(abs(r[i*3+j])*s[j]/2 for j in range(3)) for i in range(3)]
  out.append((pr['Name'].text,[[p[i]-e[i] for i in range(3)],[p[i]+e[i] for i in range(3)]]))
 return out
def total(parts):return [[min(b[0][i] for n,b in parts) for i in range(3)],[max(b[1][i] for n,b in parts) for i in range(3)]]
def shift(bb,x,z):return [[v[0]+x,v[1],v[2]+z] for v in bb]
def ov(a,b):return all(min(a[1][i],b[1][i])-max(a[0][i],b[0][i])>1e-5 for i in range(3))
def expanded(bb,d):return [[bb[0][0]-d,bb[0][1],bb[0][2]-d],[bb[1][0]+d,bb[1][1],bb[1][2]+d]]
assetroot=REPO/'assets/models/astra-sky/models';cfg=REPO/'src/shared/Config/Upgrades.luau'
rows=re.findall(r'\{\s*4,\s*(?:nil|"[^"]*"),\s*"([^"]*)",\s*"[^"]*",\s*[\d_]+,\s*"(SkyDesk|SoundStudio|ArtWall)",\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+),',cfg.read_text())
assert len(rows)==13,len(rows)
furniture=[];reserves=[]
for id,n,x,z,yaw in rows:
 assert float(yaw)==0
 b=shift(total(xmlbounds(assetroot/(n+'.rbxmx'))),float(x),float(z));furniture.append((id,b))
 if n=='SkyDesk':reserves.append((id+'_3studApron',[[b[0][0],0,b[1][2]],[b[1][0],5,b[1][2]+3]]))
reserves += [('lift',[[-23,0,21],[-17,7,27]]),('buttonRowConservative',[[-30,0,22.5],[30,5,27.5]]),('boothDoor6studApproach',[[-21.2,0,18.3],[-14.8,6,24.3]]),('frontEntry',[[-12,0,23.5],[12,9,30]])]
legacy=[('playerDesk',[[-15.8,0,-21.75],[-8.2,5.5,-15.8]]),('coffee',[[23.5,0,-27.5],[26.5,6,-20.5]]),('hitShelf',[[-29,0,-20],[-26.2,8,-10]])]
shell=[('shell/'+n,b) for n,b in xmlbounds(assetroot/'Skyscraper.rbxmx') if n not in ['Floor','FloorJoint']]
def check(x,z):
 body=[[x-3,0,z-3],[x+3,5,z+3]];apron=[[x-3,0,z+3],[x+3,5,z+7]];hits=[]
 for n,b in shell+furniture+legacy+reserves:
  if ov(body,b):hits.append('body/'+n)
  if ov(apron,b):hits.append('front4/'+n)
 # Stronger than merely nonintersecting:4stud horizontal clear corridors to allstageinteriors.
 for n,b in furniture+legacy:
  if ov(expanded(body,4),b):hits.append('clearance4/'+n)
 return {'centerXZ':[x,z],'body':body,'frontApron4':apron,'conflicts':hits,'status':'PASS' if not hits else 'FAIL'}
old=check(-23,13);proposed=check(-24,1)
passing=[check(x,z) for x in range(-24,-17) for z in range(-3,8) if check(x,z)['status']=='PASS']
report={'scope':'Candidate only; no code placement. Conservative6x5x6body plus4stud front apron. Actual3templates are smaller5.6x5.2footprint.','configStage4Count':len(rows),'configSHA256':hashlib.sha256(cfg.read_bytes()).hexdigest(),'sourceModels':'Currentmain assets/models/astra-sky/models','assumptions':['floor supporting surface excluded fromshellcollision; final code chooses flooroffset','current11SkyDesk/SoundStudio/ArtWall positions yaw0','legacy playerdesk/coffee/hits preserved using previousSkyvalidation bounds','fullbuttonrowZ22.5..27.5 keptclear acrossentireplot','existingSkybooth6studdoorapproach keptclear','actual runtimeNPC routes andlatermodelvariants needStudioverification'],'rejectedCandidate':old,'recommendedCandidate':proposed,'passingNearLeftWall':[x['centerXZ'] for x in passing],'runtimeTested':False,'worldY':'thirdfloorbase28 plusactualflooroffset','status':'PASS' if proposed['status']=='PASS' else 'NO_RECOMMENDATION'}
(ROOT/'PLACEMENT_CANDIDATE_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
# Standalone QA plan, not a runtime placement file.
from PIL import Image,ImageDraw,ImageFont
im=Image.new('RGB',(1040,1100),'#edf0f7');draw=ImageDraw.Draw(im);font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',15)
scale=14;ox=520;oy=480
pt=lambda x,z:(ox+x*scale,oy+z*scale)
def rect(bb,fill,outline='#283345',width=2):draw.rectangle([pt(bb[0][0],bb[0][2]),pt(bb[1][0],bb[1][2])],fill=fill,outline=outline,width=width)
draw.rectangle([pt(-30,-30),pt(30,30)],fill='#fffdf6',outline='#283345',width=3)
for n,b in furniture+legacy:
 rect(b,'#cbb9e8');draw.text(pt(b[0][0],b[0][2]),n,font=font,fill='#283345')
for n,b in reserves:
 rect(b,None,'#df504d' if n=='lift' else '#95ad9c',2)
rect(proposed['body'],'#3d7bff');rect(proposed['frontApron4'],'#7ee0ad')
draw.text(pt(-27,-2),'V23',font=font,fill='white');draw.text(pt(-27,4),'4 stud',font=font,fill='#174334');draw.text(pt(-23,21),'LIFT',font=font,fill='#d04444')
draw.text((48,20),'V23 candidate: center (-24, 1), yaw 0, floor 3',font=font,fill='#283345')
draw.text((48,930),'Blue: conservative 6x6 footprint; green: 4-stud front approach (+Z).',font=font,fill='#283345')
draw.text((48,960),'Purple: current furniture. Outlines: desk aprons, lift, buttons and door reserves.',font=font,fill='#283345')
draw.text((48,990),'Candidate only. Dev2 final placement; Dev1 verifies actual paths in Studio.',font=font,fill='#283345')
(ROOT/'previews').mkdir(exist_ok=True);im.save(ROOT/'previews'/'Placement_Candidate_QA.png')
print(json.dumps(report,indent=2))
