const fs=require('fs'),path=require('path');
let Resvg;try{({Resvg}=require('@resvg/resvg-js'));}catch{({Resvg}=require('/private/tmp/gst-svg-runtime/node_modules/@resvg/resvg-js'));}
const root=path.resolve(__dirname,'..');
for(let b=1;b<=3;b++){
 const src=path.join(root,`batch-${b}`,'source-svg');
 if(!fs.existsSync(src))continue;
 for(const f of fs.readdirSync(src).filter(x=>x.endsWith('.svg'))){
  const png=new Resvg(fs.readFileSync(path.join(src,f)),{font:{loadSystemFonts:false}}).render().asPng();
  fs.writeFileSync(path.join(root,`batch-${b}`,'V13',f.replace('.svg','.png')),png);
 }
}
