'use strict';
// Deterministic adapter for the delivered runtime. No downloaded tools or npm install.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),input=path.join(root,'Imports/dot-0.8.3-win.1/runtime/win-unpacked');
const output=path.join(root,'bin/QuotaView.ElectronEffects');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const raw=fs.readFileSync(path.join(input,'resources/app.asar'));
const dataStart=8+raw.readUInt32LE(4),header=JSON.parse(raw.toString('utf8',16,16+raw.readUInt32LE(12)));
const files=new Map();
function visit(node,prefix=''){for(const [name,item]of Object.entries(node.files)){const namePath=prefix+name;if(item.files)visit(item,namePath+'/');else{if(item.unpacked||item.link)throw Error('Unexpected external ASAR entry');files.set(namePath,Buffer.from(raw.subarray(dataStart+Number(item.offset),dataStart+Number(item.offset)+item.size)));}}}
visit(header);
function text(name){if(!files.has(name))throw Error('Missing input '+name);return files.get(name).toString('utf8');}
function patch(value,from,to){const count=value.split(from).length-1;if(count!==1)throw Error('Expected exactly one adapter anchor: '+from.slice(0,90)+'; found '+count);return value.replace(from,to);}
const profileText=fs.readFileSync(path.join(root,'Prototypes/EffectsLab/src/ReleaseProfiles.cs'),'utf8');
const numbers=s=>s.split(',').map(s=>s.trim()).filter(Boolean).map(s=>Number(s.replace(/f$/,'')));
const seed=numbers(profileText.match(/Seed = new float\[\] \{([\s\S]*?)\};/)[1]);
function rows(name){const section=profileText.match(new RegExp(name+' = new float\\[\\]\\[\\] \\{([\\s\\S]*?)\\n        \\};'))[1];return [...section.matchAll(/new float\[\] \{([^}]+)\}/g)].map(m=>numbers(m[1]));}
if(seed.length!==128)throw Error('Unexpected source uniform layout');
const shader=name=>fs.readFileSync(path.join(root,'Prototypes/EffectsLab/shaders',name),'utf8').replace('#version 330 compatibility','#version 300 es\nprecision highp float;\nprecision highp int;');
const assets={seed,orb:rows('Orb'),quantum:rows('Quantum'),orbShader:shader('orb.frag'),quantumShader:shader('quantum.frag'),borderShader:shader('border.frag'),vertex:'#version 300 es\nprecision highp float;\nout vec2 uv;\nvoid main(){vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));gl_Position=vec4(p*2.0-1.0,0,1);uv=vec2(p.x,1.0-p.y);}'};
assets.smoke=require('./src/smoke-profiles.json');
assets.progressShader=fs.readFileSync(path.join(__dirname,'src/progress.frag'),'utf8');
files.set('dist/renderer/shared/task-state.js',fs.readFileSync(path.join(root,'windows/shared/task-state.js')));
const generated='/* Generated from the accepted EffectsLab; MIT (c) 2026 Duoasa. */\n(function(r){const a='+JSON.stringify(assets)+';if(typeof module==="object"&&module.exports)module.exports=a;else r.QVEffectAssets=a;})(globalThis);\n';
fs.writeFileSync(path.join(__dirname,'src/assets.js'),generated);
for(const name of ['assets.js','model.js','runtime.js','effects.css'])files.set('dist/renderer/effects/'+name,fs.readFileSync(path.join(__dirname,'src',name)));
let html=text('dist/renderer/index.html');
html=patch(html,'</head>','<link rel="stylesheet" href="./effects/effects.css"></head>');
html=patch(html,'<script src="./app.js"></script>','<script src="./shared/task-state.js"></script><script src="./effects/assets.js"></script><script src="./effects/model.js"></script><script src="./effects/runtime.js"></script><script src="./app.js"></script>');
files.set('dist/renderer/index.html',Buffer.from(html));
let js=text('dist/renderer/app.js');
const start=js.indexOf('function ho('),end=js.indexOf('function Cr(',start);
if(start<0||end<start||end-start>1200)throw Error('Unexpected orb component boundary');
js=js.slice(0,start)+'function ho({status:t="unknown",small:e=!1,task:a}){let{snapshot:l}=R();return window.QVEffects.renderOrb(b.default,{status:t,small:e,task:a,reduceMotion:!!l.settings.reduceMotion})}'+js.slice(end);
js=patch(js,'f=t.status==="completed"&&t.verified===!1?"unknown":t.status||"unknown"','f=window.QVEffects.displayState(t)');
js=patch(js,'b.default.createElement(ho,{status:f})','b.default.createElement(ho,{status:f,task:t})');
const cssEffect='b.default.createElement("span",{className:"task-effect","aria-hidden":"true"},b.default.createElement("i",null),b.default.createElement("b",null),b.default.createElement("em",null))';
js=patch(js,cssEffect,'n.settings.effect==="quantum"?b.default.createElement(window.QVEffects.Quantum,{react:b.default,task:t,status:f,reduceMotion:!!n.settings.reduceMotion}):'+cssEffect);
js=patch(js,'x[0]?.status||M?.status||"unknown"','window.QVEffects.displayState(x[0]||M)');
js=patch(js,'(0,fm.createRoot)(document.getElementById("root")).render(H.default.createElement(Or,null,H.default.createElement(ay,null)));','(0,fm.createRoot)(document.getElementById("root")).render(H.default.createElement(Or,null,H.default.createElement(ay,null)));window.QVEffects.registerTestReact(H.default,fm.createRoot);');
files.set('dist/renderer/app.js',Buffer.from(js));
let settings=text('src/core/settings.cjs');settings=patch(settings,'effect: "smoke"','effect: "quantum"');files.set('src/core/settings.cjs',Buffer.from(settings));
let main=text('src/main.cjs');
// Native Acrylic fills the rectangular HWND, including transparent rounded margins.
main=patch(main,'settings.material === "glass" ? "acrylic" : "none"','"none"');
main=patch(main,'    nativeTheme.themeSource = settings.theme;','    for (const win of [island, capsule])\n      if (win && !win.isDestroyed()) win.setBackgroundColor("#00000000");\n    nativeTheme.themeSource = settings.theme;');
main=patch(main,'query: { view }','query: { view, effectsSmoke: SMOKE ? "1" : "0" }');
main=patch(main,'const evidence = {','const effects = await island.webContents.executeJavaScript("window.QVEffects.selfTest()");\n        const topAligned = island.getBounds().y === display().bounds.y;\n        if (!topAligned) throw Error("Island is not aligned to screen top");\n        const evidence = {\n          topAligned,\n          windowBackgrounds: [island, capsule].map(win => win.getBackgroundColor()),\n          effects,');
files.set('src/main.cjs',Buffer.from(main));
let platform=text('src/core/platform.cjs');
platform=patch(platform,'const b = display.workArea || display.bounds;','const b = display.bounds || display.workArea;');
platform=patch(platform,'y: Math.round(b.y + 8),','y: Math.round(b.y),');
files.set('src/core/platform.cjs',Buffer.from(platform));
const pkg=JSON.parse(text('package.json'));pkg.version='0.8.3-win.1.effects.2';files.set('package.json',Buffer.from(JSON.stringify(pkg,null,2)));
// Preserve original ASAR file entries and bytes; replace only explicit adapter targets.
const tree={files:{}};let offset=0;
for(const [name,bytes]of files){
  const parts=name.split('/');let node=tree;
  for(const part of parts.slice(0,-1)){if(!node.files[part])node.files[part]={files:{}};node=node.files[part];}
  const blocks=[];for(let i=0;i<bytes.length;i+=4194304)blocks.push(hash(bytes.subarray(i,i+4194304)));
  node.files[parts.at(-1)]={size:bytes.length,offset:String(offset),integrity:{algorithm:'SHA256',hash:hash(bytes),blockSize:4194304,blocks}};
  offset+=bytes.length;
}
const json=Buffer.from(JSON.stringify(tree)),payload=Math.ceil((4+json.length)/4)*4,head=Buffer.alloc(12+payload);
head.writeUInt32LE(4,0);head.writeUInt32LE(payload+4,4);head.writeUInt32LE(payload,8);head.writeUInt32LE(json.length,12);json.copy(head,16);
fs.mkdirSync(output,{recursive:true});fs.cpSync(input,output,{recursive:true,force:false});
const target=path.join(output,'resources/app.asar'),temp=target+'.building';
const fd=fs.openSync(temp,'w');try{fs.writeSync(fd,head);for(const bytes of files.values())fs.writeSync(fd,bytes);}finally{fs.closeSync(fd);}
fs.renameSync(temp,target);
const changed=['dist/renderer/shared/task-state.js','dist/renderer/index.html','dist/renderer/app.js','src/core/settings.cjs','src/core/platform.cjs','src/main.cjs','package.json',...['assets.js','model.js','runtime.js','effects.css'].map(n=>'dist/renderer/effects/'+n)];
const manifest={version:pkg.version,baseAsarSHA256:hash(raw),asarSHA256:hash(fs.readFileSync(target)),baseline:'dot 0.8.3-win.1',effects:'accepted Prototypes/EffectsLab',changes:changed.map(file=>({file,sha256:hash(files.get(file))}))};
fs.writeFileSync(path.join(output,'effects-build-manifest.json'),JSON.stringify(manifest,null,2));
console.log(JSON.stringify({output,version:pkg.version,changed:changed.length,files:files.size}));
