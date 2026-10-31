"use strict";
const {test}=require('node:test'), assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm');
const {CompletionLedger}=require('../src/core/task-lifecycle.cjs');
const {CodexDesktop}=require('../src/core/codex-desktop.cjs');
const {CodexService,hash}=require('../src/core/codex.cjs');
const shared=require('../shared/task-state.js');
const task=(status,turn='one')=>({id:'codex:session',provider:'codex',turnId:hash(turn),status,verified:true,startedAt:10,updatedAt:20});
function notifications(){
  const notices=[],expansions=[];let tasks=[];
  const source=fs.readFileSync(require.resolve('../src/main.cjs'),'utf8');
  const context={...shared,completionLedger:new CompletionLedger(),oldTaskStates:new Map(),oldAttentionKeys:new Map(),notifyQuota:new Map(),
    snapshot:()=>({tasks,quotas:{}}),settings:{notifications:true,completionNotifications:true,autoExpand:true,autoExpandOnComplete:true},
    Notification:class {static isSupported(){return true;} constructor(n){this.n=n;} show(){notices.push(this.n);}},
    island:{showInactive(){}},word:(en)=>en,setExpanded:(_,reason)=>expansions.push(reason),publish(){},collapseTimer:null,clearTimeout(){}};
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('  function notificationsAndExpansion()'),source.indexOf('  function bindService(')),context);
  return {notices,expansions,context,update:(...next)=>{tasks=next;context.notificationsAndExpansion();}};
}
test('issue 114: initial terminal history and 200 corrections produce no notification or expansion',()=>{
  const n=notifications();
  for(let i=0;i<200;i++)n.update(task(i%2?'completed':'interrupted'));
  assert.equal(n.notices.length,0);assert.equal(n.expansions.length,0);
});
test('one completion per turn despite resync, disappearance, terminal corrections and active replay',()=>{
  const n=notifications();n.update(task('working'));n.update(task('completed'));
  for(let i=0;i<100;i++){n.update();n.update(task('unknown'));n.update(task('working'));n.update(task('interrupted'));n.update(task('completed'));}
  assert.equal(n.notices.length,1);
  assert.equal(n.expansions.filter(x=>['completed','interrupted'].includes(x)).length,1);
  n.update(task('working','two'));n.update(task('interrupted','two'));
  assert.equal(n.notices.length,2);
});
test('notification toggles do not replay history; pending approvals still expand',()=>{
  const n=notifications();n.update(task('working'));n.context.settings.notifications=false;n.update(task('completed'));
  n.context.settings.notifications=true;n.update(task('interrupted'));assert.equal(n.notices.length,0);
  n.update({...task('waiting','two'),approval:{id:'request',kind:'permission'}});
  assert.equal(n.expansions.at(-1),'waiting');
});
test('unverified completion cannot consume the verified completion event',()=>{
  const n=notifications();n.update(task('working'));n.update({...task('completed'),verified:false});n.update(task('completed'));
  assert.equal(n.notices.length,1);
});
test('Desktop settlement survives unavailable snapshots and disconnection with stable turn identity',()=>{
  const d=new CodexDesktop();d.connected=true;
  const e={projection:{authoritative:true,turnId:'one',status:'interrupted'},handles:[]};d.follows.set('session',e);
  const local=task('completed');
  for(let i=0;i<200;i++){
    d.connected=i%2===0;
    const result=d.overlay(local,'session','one');
    assert.equal(result.status,'interrupted');assert.equal(result.turnId,local.turnId);assert.equal(result.approval,null);
  }
  d.connected=true;e.projection=null;assert.equal(d.overlay(local,'session','one').status,'interrupted');
});
test('older Desktop turn cannot overwrite a new local turn; newer timestamp can advance Desktop',()=>{
  const d=new CodexDesktop();d.connected=true;
  const e={projection:{authoritative:true,turnId:'one',status:'completed',startedAt:10},handles:[]};d.follows.set('session',e);
  d.overlay(task('working'),'session','one');
  const next={...task('working','two'),startedAt:30};
  assert.equal(d.overlay(next,'session','two').status,'working');
  e.projection={authoritative:true,turnId:'three',status:'inProgress',startedAt:40};
  assert.equal(d.overlay(next,'session','two').turnId,hash('three'));
  d.connected=false;
  const disconnected=d.overlay(next,'session','two');
  assert.equal(disconnected.turnId,hash('three'));assert.equal(disconnected.status,'unknown');assert.equal(disconnected.approval,null);
});
test('duplicate rollouts resolve to one current task independent of iteration order',()=>{
  const d=new CodexDesktop();
  const old={parser:{threadId:'session',turnId:'one',getTask:()=>task('interrupted')},mtime:999,path:'old'};
  const current={parser:{threadId:'session',turnId:'two',getTask:()=>({...task('completed','two'),startedAt:30})},mtime:40,path:'new'};
  for(const cursors of [[old,current],[current,old]]){
    const service={enabled:true,cursors:new Map(cursors.map((c,i)=>[String(i),c])),clock:()=>50,options:{},desktop:d,state:{}};
    const result=CodexService.prototype.getSnapshot.call(service);
    assert.equal(result.tasks.length,1);assert.equal(result.tasks[0].turnId,hash('two'));assert.equal(result.tasks[0].status,'completed');
  }
});
test('duplicate thread IDs do not crowd out Desktop follow slots',()=>{
  const d=new CodexDesktop();d.sync([...Array(25).fill('one'),'two']);assert.deepEqual([...d.follows.keys()],['one','two']);
});
