from native_xml import *
from render_geometry import preview
ps=fromxml(ET.parse(ROOT/'models/Pigeon.rbxmx').getroot())
for name,yaw,elev in [('ThreeQuarter',35,18),('Profile',90,12),('Front',0,10)]:preview(ps,ROOT/'previews'/('Pigeon_'+name+'.png'),yaw=yaw,elev=elev,target=(0,.9,-.15),span=3.5,W=1000,H=1000)
