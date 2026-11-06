"""Known separated/tangent/penetrating fixtures for the analytic support validator."""
from convex_support import *
def fixture(p,h,shape='ball',R=None):
 return {'name':'fixture','ref':'fixture','p':np.array(p,dtype=float),'h':np.array(h),'R':np.eye(3)if R is None else R,'shape':shape}
a=fixture([0,0,0],[1,1,1])
assert separate(a,fixture([2.1,0,0],[1,1,1]))is not None
assert separate(a,fixture([2,0,0],[1,1,1]))is not None
assert separate(a,fixture([1.9,0,0],[1,1,1]))is None
angle=.4;R=np.array([[1,0,0],[0,math.cos(angle),-math.sin(angle)],[0,math.sin(angle),math.cos(angle)]])
a=fixture([0,0,0],[.42,.48,.85])
for v in [[.23,.85,.47],[-.6,.3,.7],[.5,.8,-.2],[0,1,.2]]:
 n=np.array(v,dtype=float);n/=np.linalg.norm(n);b=fixture([0,0,0],[.15,.13,.15],R=R)
 b['p']=support(a,n)-support(b,-n)
 assert separate(a,b)is not None,('missed tangent',v)
 b['p']-=.01*n
 assert separate(a,b)is None,('false clearance',v)
a=fixture([0,0,0],[1,1,1],shape='box')
assert separate(a,fixture([1.9,0,0],[1,1,1],shape='box'))is None
assert separate(a,fixture([2,0,0],[1,1,1],shape='box'))is not None
print('PASS: separated/tangent accepted, penetrating spheres/boxes/rotated ellipsoids rejected')
