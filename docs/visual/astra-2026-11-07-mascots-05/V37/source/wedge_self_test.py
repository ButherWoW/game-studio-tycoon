from convex_support import *
from copy import deepcopy
a={'name':'lower','ref':'a','p':np.zeros(3),'R':np.eye(3),'h':np.array([.10,.50,.50]),'shape':'wedge','alpha':0}
b={'name':'upper','ref':'b','p':np.zeros(3),'R':np.diag([1.,-1.,-1.]),'h':np.array([.10,.50,.50]),'shape':'wedge','alpha':0}
n=np.array([0.,1.,-1.]);n/=np.linalg.norm(n)
cert=separate(a,b);assert cert is not None and gap(a,b,cert['axis'])>=-1e-6
outside=deepcopy(b);outside['p']+=n*.02;assert separate(a,outside) is not None
inside=deepcopy(b);inside['p']-=n*.02;assert separate(a,inside) is None
print('PASS: coincident-center complementary wedges touch along a slope; separated accepted, penetrating rejected.')
