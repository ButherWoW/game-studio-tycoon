from native_xml import *
from render_geometry import preview
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1]
for style in ['', 'Aurora','Sakura','ObsidianGold']:
 sheet=Image.new('RGB',(1800,660),'#e7e7ef');d=ImageDraw.Draw(sheet)
 for i,name in enumerate(['Office','Floor','Skyscraper']):
  stem=name+('_'+style if style else '');parts=fromxml(ET.parse(R/'models'/(stem+'.rbxmx')).getroot())
  # Inspection cutaway deliberately hides glass and roof to show unobstructed windows and interiors.
  ps=[p for p in parts if p['mat']!='Glass' and not ('roof' in p['name'].lower() or 'ceiling' in p['name'].lower())]
  dest=R/'previews'/(stem+'_Inspection.png');preview(ps,dest,yaw=32,elev=27,target=(0,6,0),span=90,W=720,H=650)
  im=Image.open(dest);im.thumbnail((600,570));sheet.paste(im,(i*600,45));d.text((i*600+16,15),stem,fill='black')
 d.text((16,625),'INSPECTION CUTAWAY: Glass panes and roof hidden for visibility. Final Glass transparency = 0.4.',fill='black');sheet.save(R/'previews'/((style or 'Classic')+'_CONTACT_SHEET.png'))
