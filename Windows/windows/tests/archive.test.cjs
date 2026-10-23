
const {test}=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs"),os=require("node:os"),path=require("node:path");
const {DismissedTasks}=require("../src/core/task-history.cjs");
test("island archive persists without changing the agent and a new turn returns",()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),"qv-archive-"));
 const store=new DismissedTasks(dir),task={id:"one",provider:"codex",status:"working",turnId:"turn1"};
 const before=JSON.stringify(task);store.dismiss(task);
 assert.equal(JSON.stringify(task),before);assert.equal(new DismissedTasks(dir).has(task),true);
 assert.equal(store.has({...task,turnId:"turn2"}),false);
 store.restore();assert.equal(new DismissedTasks(dir).has(task),false);
 fs.unlinkSync(path.join(dir,"dismissed-tasks.json"));fs.rmdirSync(dir);
});

