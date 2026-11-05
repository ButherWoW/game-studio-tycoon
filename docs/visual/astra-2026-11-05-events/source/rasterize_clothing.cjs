const fs=require('fs'),path=require('path');
let Resvg;try{({Resvg}=require('@resvg/resvg-js'));}catch{({Resvg}=require('/private/tmp/gst-svg-runtime/node_modules/@resvg/resvg-js'));}
const root=path.resolve(__dirname,'..','contracts-bailiff');
for(const f of fs.readdirSync(path.join(root,'source-svg')).filter(f=>f.endsWith('.svg'))){
 fs.writeFileSync(path.join(root,'V19',f.replace('.svg','.png')),new Resvg(fs.readFileSync(path.join(root,'source-svg',f)),{font:{loadSystemFonts:false}}).render().asPng());
}
