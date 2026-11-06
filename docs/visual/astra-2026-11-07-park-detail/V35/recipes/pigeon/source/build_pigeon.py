from geometry import *
import subprocess
m=model('Pigeon')
ball(m,'Body',(0,.74,-.10),(.84,.96,1.70),'919DAC')
# Ellipsoid tangent support: the short inclined neck sits outside a tangent plane of the breast.
z=.42;y=.74+.48*math.sqrt(1-((z+.10)/.85)**2);q=(0,y,z)
u0=(0,(y-.74)/(.48**2),(z+.10)/(.85**2));l=math.sqrt(sum(v*v for v in u0));u=tuple(v/l for v in u0)
neck_center=add(q,tuple(.13*v for v in u));angle=math.degrees(math.atan2(u[2],u[1]));neck_rot=rot(x=angle)
ball(m,'Neck_GreenIridescence',neck_center,(.30,.26,.30),'477D73',r=neck_rot)
# Neck's forward upper pole and head are separated by the common tangent plane.
top=add(q,tuple(.26*v for v in u));radii=(.25,.23,.27);h=math.sqrt(sum((radii[i]*u[i])**2 for i in range(3)));head=add(top,tuple(radii[i]**2*u[i]/h for i in range(3)))
ball(m,'Head',head,(.50,.46,.54),'738499')
# Purple/cyan lateral neck plumes are tangent to the neck's local side planes.
for side,c in [(-1,'72618C'),(1,'63769B')]:
 off=mv(neck_rot,(side*.158,0,0));ball(m,'Neck_Shimmer_'+str(side),add(neck_center,off),(.016,.18,.045),c,r=neck_rot)
# Small cere and pointed beak face +Z; local Y remains vertical.
front=head[2]+.27
box(m,'Beak_Cere',(0,head[1]-.015,front+.018),(.13,.075,.036),'DCD8CD')
part(m,'Beak',(0,head[1]-.043,front+.112),(.11,.06,.152),'4E525E',cls='WedgePart',r=rot(y=180))
for side in [-1,1]:
 ball(m,'Eye_Amber_'+str(side),(side*.272,head[1]+.025,head[2]),(.044,.095,.095),'DFAB65')
 ball(m,'Eye_Pupil_'+str(side),(side*.302,head[1]+.025,head[2]),(.016,.058,.058),'101724')
 # Actual ellipsoid tangent placement, not floating planar feather layers.
 wingcenter=(side*.455,.74,-.10);wr=(.035,.30,.575)
 ball(m,('Left'if side<0 else 'Right')+'_Wing',wingcenter,(.07,.60,1.15),'8B99AD')
 for j in range(4):
  dy=[-.18,-.06,.06,.18][j];length=[.64,.80,.88,.72][j];fr=(.0125,.0375,length/2)
  dx=side*wr[0]*math.sqrt(1-(dy/wr[1])**2);point=add(wingcenter,(dx,dy,0))
  outward=(dx/wr[0]**2,dy/wr[1]**2,0);den=math.sqrt(sum(v*v for v in outward));outward=tuple(v/den for v in outward)
  supportdist=math.sqrt(sum((fr[i]*outward[i])**2 for i in range(3)));fc=add(point,tuple(fr[i]**2*outward[i]/supportdist for i in range(3)))
  ball(m,'FlightFeather_%s_%s'%(side,j),fc,tuple(2*v for v in fr),['ABB5C3','A1ADBD'][j%2])
  # Two small dark caps on each feather form the two characteristic wing stripes.
  for k,zz in enumerate([-.32,-.08]):
   dz=zz-fc[2];fx=side*fr[0]*math.sqrt(1-(dz/fr[2])**2);fq=add(fc,(fx,0,dz));n=(fx/fr[0]**2,0,dz/fr[2]**2);nl=math.sqrt(sum(v*v for v in n));n=tuple(v/nl for v in n);cr=(.006,.030,.0175);hh=math.sqrt(sum((cr[i]*n[i])**2 for i in range(3)));cc=add(fq,tuple(cr[i]**2*n[i]/hh for i in range(3)))
   ball(m,'WingStripeCap_%s_%s_%s'%(side,j,k),cc,tuple(2*v for v in cr),'354256')
# Six narrow tapered tail vanes; tiny separations give actual feather contours.
for j in range(6):
 x=(j-2.5)*.065;length=.36+.12*(1-abs(j-2.5)/3)
 part(m,'Tail_Feather_%02d'%j,(x,.73,-.95-length/2),(.060,.065,length),'4C5B70',cls='WedgePart')
# Contact points on the lower ellipsoid; each leg projects along the outward normal.
for side,zz in [(-1,.28),(1,-.25)]:
 xx=side*.18;yy=.74-.48*math.sqrt(1-(xx/.42)**2-((zz+.1)/.85)**2);contact=(xx,yy,zz)
 normal=(xx/(.42**2),(yy-.74)/(.48**2),(zz+.1)/(.85**2));mag=math.sqrt(sum(v*v for v in normal));normal=tuple(v/mag for v in normal)
 legLength=(contact[1]-.115)/(-normal[1]);end=add(contact,tuple(legLength*v for v in normal));line(m,'Leg_'+str(side),contact,end,.045,'B47D79')
 footz=end[2]+.02;footx=end[0]
 box(m,'Foot_Palm_'+str(side),(footx,.045,footz),(.17,.09,.12),'C58B82')
 for j in range(3):box(m,'Toe_%s_%s'%(side,j),(footx+(j-1)*.06,.025,footz+.115),(.04,.05,.11),'D59D8D')
# Translate the entire model so pivot is geometric footprint center and ground Y0.
lo=[min(p['p'][i]-sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3))for p in m['parts'])for i in range(3)]
hi=[max(p['p'][i]+sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3))for p in m['parts'])for i in range(3)]
shift=(-(lo[0]+hi[0])/2,-lo[1],-(lo[2]+hi[2])/2)
for p in m['parts']:p['p']=add(p['p'],shift)
assert len(m['parts'])<=60
if __name__=='__main__':
 export(m,ROOT/'models/Pigeon.rbxmx');p=ROOT/'source/convert.project.json';p.write_text(json.dumps({'name':'Pigeon','tree':{'$path':str(ROOT/'models/Pigeon.rbxmx')}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(p),'-o',str(ROOT/'models/Pigeon.rbxm')],check=True,capture_output=True);p.unlink();(ROOT/'MANIFEST.json').write_text(json.dumps(m,indent=2)+'\n');print(len(m['parts']))
