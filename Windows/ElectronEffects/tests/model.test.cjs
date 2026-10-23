'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {Model,displayState}=require('../src/model.js');
const advance=(m,seconds,fps=60)=>{for(let i=0;i<seconds*fps;i++)m.advance(1/fps);};
test('continuous interrupted transitions preserve phase and current color',()=>{
 const m=new Model('working',.6);advance(m,1);const p=m.orbUniforms(100,100),phase=m.orbPhase;
 m.setState('thinking');assert.deepEqual(m.orbUniforms(100,100),p);assert.equal(m.orbPhase,phase);
 advance(m,.1);const current=m.orbUniforms(100,100);m.setState('error');assert.deepEqual(m.orbUniforms(100,100),current);
});
test('ordinary progress never creates completion; unknown progress stays unknown',()=>{
 const m=new Model('working',2);advance(m,120);assert.equal(m.progress,.95);assert.ok(m.front<=.95);assert.equal(m.state,'working');
 m.setProgress(null);assert.equal(m.front,0);assert.equal(m.known,false);assert.equal(m.quantumUniforms(200,64)[11],0);
});
test('reduced motion freezes phase, settles completion, and does not replay on re-enable',()=>{
 const m=new Model('working',.6);advance(m,1);m.setReduced(true);const p=m.orbUniforms(100,100),q=m.quantumUniforms(200,64);
 advance(m,3);assert.deepEqual(m.orbUniforms(100,100),p);assert.deepEqual(m.quantumUniforms(200,64),q);
 m.setState('completed');assert.equal(m.quantumUniforms(200,64)[16],0);assert.ok(m.glow>0);
 m.setReduced(false);assert.equal(m.quantumUniforms(200,64)[16],0);
});
test('completion is one-shot; existing completed cards mount settled',()=>{
 const m=new Model('working',.6);m.setState('completed');assert.equal(m.quantumUniforms(200,64)[13],0);
 advance(m,.5);assert.equal(m.quantumUniforms(200,64)[13],1);assert.ok(m.quantumUniforms(200,64)[14]>0);
 advance(m,8);assert.equal(m.quantumUniforms(200,64)[16],0);assert.ok(m.glow>0);
 assert.equal(new Model('completed',.6).quantumUniforms(200,64)[16],0);
 m.setState('working');assert.equal(m.quantumUniforms(200,64)[17],0);
});
test('compaction respects waiting, terminal, and unverified-completion precedence',()=>{
 assert.equal(displayState({status:'working',compacting:true}),'compacting');
 assert.equal(displayState({status:'working',tool:'Compacting context'}),'compacting');
 for(const status of ['waiting','failed','interrupted','completed','unknown'])assert.equal(displayState({status,compacting:true}),status);
 assert.equal(displayState({status:'completed',verified:false,compacting:true}),'unknown');
});
test('phase and displacement remain frame-rate independent and bounded',()=>{
 const a=new Model('working',.5),b=new Model('working',.5);a.setState('compacting');b.setState('compacting');advance(a,2,30);advance(b,2,120);
 for(const name of ['orbPhase','phase','displacement'])assert.ok(Math.abs(a[name]-b[name])<.001,name);
 advance(a,900);assert.ok(a.phase>=0&&a.phase<256);assert.ok(Math.abs(a.displacement)<4096*2.35);
});
test('all nine source profiles retain the sphere geometry and finite uniforms',()=>{
 for(const state of ['thinking','working','compacting','waiting','completed','error','standby','disconnected','unavailable']){
  const m=new Model(state,.6);advance(m,1);const p=m.orbUniforms(100,100);
  assert.equal(p[4],Math.fround(.535));assert.equal(p[15],9);assert.equal(p[19],1);assert.equal(p[21],0);
  assert.ok([...p,...m.quantumUniforms(200,64)].every(Number.isFinite));
 }
});
test('interrupted tasks freeze and malformed time deltas cannot corrupt clocks',()=>{
 const m=new Model('working',.5);m.advance(NaN);m.advance(Infinity);m.advance(-2);assert.equal(m.orbPhase,0);
 m.setState('interrupted');const p=m.orbUniforms(100,100);advance(m,2);assert.deepEqual(m.orbUniforms(100,100),p);
});

test("focused thinking and compaction show animated activity without inventing progress",()=>{
 for(const state of ["thinking","compacting","working","waiting","unknown","interrupted"]){
  const m=new Model(state,null),before=m.quantumUniforms(400,64);advance(m,1);
  const after=m.quantumUniforms(400,64);
  assert.equal(m.known,false);assert.equal(after[2],0);assert.equal(after[11],0);assert.equal(after[54],1);
  if(["thinking","compacting","working","waiting"].includes(state))assert.notDeepEqual(after,before,state);
  if(state==="interrupted")assert.deepEqual(after,before);
  m.setProgress(.5);assert.equal(m.quantumUniforms(400,64)[54],0);
 }
});
