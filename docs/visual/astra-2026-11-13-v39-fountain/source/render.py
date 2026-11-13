from build import M,ROOT
from geometry import flatten
from render_geometry import preview
for name,yaw,elev in [('Front',0,18),('ThreeQuarter',35,28),('Top',25,65)]:
    preview(flatten(M),ROOT/'previews'/('Fountain_'+name+'.png'),yaw=yaw,elev=elev,target=(0,1.8,0),span=13,W=1100,H=850)
