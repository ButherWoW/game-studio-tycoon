"""Render actual exported geometry with the linked original basecolor maps."""
import sys,json,importlib.util
from pathlib import Path
sys.path.insert(0,'/private/tmp/gst-realism-libs')
import numpy as np,trimesh
from PIL import Image
P=Path(__file__).resolve().parent
g=json.loads((P/'Flowerbed.gltf').read_text())
for item in g['images']:
 path=P/item['uri'];assert path.is_file() and path.stat().st_size>0,path
 with Image.open(path) as im:assert im.size==(2048,2048),(path,im.size)
scene=trimesh.load(P/'Flowerbed.gltf',force='scene',process=False)
assert len(scene.geometry)==7
assert sum(len(m.faces) for m in scene.geometry.values())==json.loads((P/'validation.json').read_text())['triangles']
records=[]
for name,m in scene.geometry.items():
 uv=np.asarray(m.visual.uv);assert uv.shape==(len(m.vertices),2) and np.isfinite(uv).all()
 assert np.isfinite(m.vertices).all() and m.faces.min()>=0 and m.faces.max()<len(m.vertices)
 records.append(dict(mesh=name,triangles=len(m.faces),uv_finite=True,degenerate_triangles=int((m.area_faces<1e-12).sum())))
 # Bake the glTF tint into preview-only image data; the exported texture remains original.
 mat=m.visual.material;factor=np.array(mat.baseColorFactor[:3])/255
 tex=mat.baseColorTexture
 if tex is None:tex=Image.new('RGB',(2,2),(255,255,255))
 mat.baseColorTexture=Image.fromarray((np.asarray(tex.convert('RGB'))*factor).astype('uint8'))
 uv=uv.copy();out=(uv<0)|(uv>1);uv[out]%=1;m.visual.uv=uv
spec=importlib.util.spec_from_file_location('park_renderer',P.parent/'rocks-bush'/'build_assets.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.preview(list(scene.geometry.values()),P/'Flowerbed_textured_preview.png')
r=json.loads((P/'validation.json').read_text());r.update(texture_files_verified=True,texture_dimensions=[2048,2048],gltf_reimport_triangles_match=True,parts=records)
(P/'validation.json').write_text(json.dumps(r,indent=2));print(json.dumps(r))
