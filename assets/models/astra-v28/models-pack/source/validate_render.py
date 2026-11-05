from build_v28 import *
from render_geometry import preview
from PIL import Image,ImageDraw,ImageFont
report=json.loads((ROOT/'INDEPENDENT_VALIDATION.json').read_text());assert report['status']=='PASS'
for name,m in ASSETS.items():
 dims=report['models'][name]['dimensionsXYZ'];preview(flatten(m),ROOT/'previews'/(name+'.png'),yaw=22,elev=25,target=(0,dims[1]/2,0),span=max(dims)*1.45,W=1100,H=1000)
 if name=='Billboard':preview(flatten(m),ROOT/'previews/Billboard_Front.png',yaw=0,elev=0,target=(0,4.5,0),span=19,W=1500,H=1000)
 if name.startswith('Hall'):
  top=next(p for p in m['parts'] if p['name']=='Top');assert top['s'][0]>=3 and top['s'][2]>=3
  assert all(p['p'][1]+sum(abs(p['r'][3+j])*p['s'][j]/2 for j in range(3))<=dims[1]+1e-6 for p in m['parts'])
report['functionalChecks']={'pedestalFreeTop':'4x4 smooth tops, central3x3 unobstructed','plate':'NamedPlate nativePart each, face+Z=Back','screen':'NamedScreen nativePart, face+Z=Back; current BillboardService matches','joystick':'Ownoriginalstatue,2studheight','runtimeTested':False};(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
s=Image.new('RGB',(1800,1160),'#ece6dd');d=ImageDraw.Draw(s);font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',22)
for n,name in enumerate(ASSETS):
 im=Image.open(ROOT/'previews'/(name+'.png'));im.thumbnail((580,510));x=n%3*600;y=n//3*580;s.paste(im,(x+(600-im.width)//2,y));d.text((x+15,y+525),name+' / '+str(report['models'][name]['parts'])+'Parts',font=font,fill='#202b48')
s.save(ROOT/'previews/V28_Models_ContactSheet.png')
