"""Obsidian Gold furniture: appearance-only variants of accepted classic XML."""
from style_helpers import *
import hashlib,subprocess
SUFFIX='ObsidianGold'
def recolor(p):
 n=p['name'].lower()
 if p['alpha']>=.99:return None
 if any(w in n for w in ['leaf','foliage','soil','grass','weed','petal','stem','water']):return None
 if p['mat']=='Glass':return '8394AE','Glass'
 if p['mat']=='Neon':return 'FFE1AB','Neon'
 if any(w in n for w in ['edge','trim','seam','handle','pull','knob','hinge','bracket','rim','border','footcap','frame','rail']):return 'D5B169','Metal'
 if any(w in n for w in ['seat','cushion','fabric','bean','soft','sofa','backinset','rug']):return '2C2C39',p['mat']
 if p['mat'] in ['Wood','WoodPlanks'] or any(w in n for w in ['top','table','shelfboard','desktop']):return '242635','Marble'
 if any(w in n for w in ['monitor','tower','speaker','server','rack','fan','drawer','base','leg','case','body','panel','cabinet','side','door','post']):return '171823','Metal'
 return 'E9DFC9','SmoothPlastic'

def build():
 rows={}
 for zone,names in ZONES.items():
  for name in names:
   src=ROOT/'baseline/models'/(name+'.rbxmx');tree=ET.parse(src);root=tree.getroot();root.find("./Item[@class='Model']/Properties/string[@name='Name']").text=name+'_'+SUFFIX
   bp=native_parts(root);count=0;preserved=[]
   for e in bp:
    p=parsepart(e)
    if preserve_content(name,p):preserved.append(p['name']);continue
    change=recolor(p)
    if change:
     col,mat=change;pr=e.find('Properties');setcolor(pr,col)
     # Seat material is retained to avoid changing any seat-specific behavior.
     if p['cls']!='Seat':setmaterial(pr,mat)
     count+=1
   for e in root.iter('Item'):
    if e.get('class') in ['PointLight','SpotLight','SurfaceLight']:
     setcolor(e.find('Properties'),'FFE1AB')
     shadow=e.find("Properties/bool[@name='Shadows']")
     if shadow is not None:shadow.text='false'
   dst=ROOT.parent/'models'/(name+'_'+SUFFIX+'.rbxmx');tree.write(dst,encoding='utf-8',xml_declaration=True)
   prj=ROOT/'source/convert.project.json';prj.write_text(json.dumps({'name':name+'_'+SUFFIX,'tree':{'$path':str(dst)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(prj),'-o',str(dst.with_suffix('.rbxm'))],check=True,stdout=subprocess.DEVNULL)
   rows[name+'_'+SUFFIX]={'zone':zone,'classic':name,'parts':len(bp),'appearanceChangedParts':count,'protectedSemanticParts':preserved,'sourceSHA256':hashlib.sha256(src.read_bytes()).hexdigest(),'sha256':hashlib.sha256(dst.read_bytes()).hexdigest()}
 prj.unlink();(ROOT/'manifest.json').write_text(json.dumps({'theme':SUFFIX,'sourceCommit':MANIFEST['sourceCommit'],'models':rows,'appearanceOnly':True,'newParts':0},indent=2)+'\n')
if __name__=='__main__':build()
