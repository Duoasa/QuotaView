"use strict";
const { EventEmitter } = require("node:events");
const crypto = require("node:crypto");
const net = require("node:net");
const P = require("./codex-desktop-state.cjs");
const MAX_FRAME = 72 * 1024 * 1024;
const MAX_RETAINED = 128 * 1024 * 1024;
const failure = (code) => Object.assign(new Error(code), { code });

// This follows the EXISTING desktop owner. The independent quota app-server
// remains read-only. IDs from rollouts/hooks never authorize responses here.
class CodexDesktop extends EventEmitter {
  constructor(options = {}) {
    super(); this.options = options;
    this.connector = options.connector || net.connectCodexDesktop;
    this.follows = new Map(); this.pending = new Map(); this.handles = new Map();
    this.enabled = false; this.connected = false; this.epoch = 0; this.clientId = "";
    this.status = "disconnected";
  }
  start() {
    if (this.enabled || this.options.enabled === false || typeof this.connector !== "function") return;
    this.enabled = true; this.connect();
    this.maintenance = setInterval(() => { if (!this.socket) this.connect(); else if (this.connected) this.followAll(); }, 3000);
    this.maintenance.unref?.();
  }
  stop() { this.enabled = false; clearInterval(this.maintenance); this.disconnect(); this.follows.clear(); }
  connect() {
    if (!this.enabled || this.socket) return;
    const epoch = ++this.epoch; this.status = "connecting";
    let socket;
    try { socket = this.connector(); } catch { this.status = "unavailable"; return; }
    this.socket = socket; this.buffer = Buffer.alloc(0);
    socket.on("error", () => this.disconnect());
    socket.on("close", () => { if (this.socket === socket) this.disconnect(); });
    socket.on("data", (b) => { if (this.socket === socket) { try { this.consume(b); } catch { this.disconnect("protocol_incompatible"); } } });
    socket.once("connect", async () => {
      try {
        const reply = await this.request("initialize", 0, { clientType: "quotaview" });
        if (epoch !== this.epoch || !reply.result?.clientId) return;
        this.clientId = reply.result.clientId; this.connected = true; this.status = "connected";
        this.emit("change"); this.followAll();
      } catch { if (epoch === this.epoch) this.disconnect(); }
    });
    this.connectDeadline = setTimeout(() => { if (epoch === this.epoch && !this.connected) this.disconnect(); }, 5000);
  }
  disconnect(status = "disconnected") {
    const socket = this.socket; this.socket = null; this.epoch++;
    clearTimeout(this.connectDeadline); clearTimeout(this.frameDeadline);
    this.connected = false; this.clientId = ""; this.status = status; this.buffer = Buffer.alloc(0);
    for (const waiter of this.pending.values()) { clearTimeout(waiter.timer); waiter.reject(failure(waiter.submission ? "codex_submission_outcome_unknown" : "codex_desktop_disconnected")); }
    this.pending.clear(); this.handles.clear();
    for (const entry of this.follows.values()) { entry.owner = null; entry.state = null; entry.projection = null; entry.handles = []; entry.inFlight = false; this.rejectRefresh(entry); }
    socket?.destroy(); this.emit("change");
  }
  sync(threadIds) {
    const desired = new Set(threadIds.slice(0, 24));
    for (const [id, entry] of this.follows) if (!desired.has(id)) {
      if (this.connected && entry.owner) this.broadcast(id, entry.owner, false);
      this.dropHandles(entry); this.rejectRefresh(entry); this.follows.delete(id);
    }
    for (const id of desired) if (!this.follows.has(id)) this.follows.set(id, { owner:null, state:null, handles:[], inFlight:false });
    if (this.connected) this.followAll();
  }
  followAll() { for (const [id, entry] of this.follows) if (!entry.owner && !entry.inFlight) void this.follow(id, entry); }
  async follow(id, entry, candidate) {
    if (!this.connected || entry.inFlight) return;
    const epoch = this.epoch; entry.inFlight = true;
    try {
      const r = await this.request("thread-owner-discovery", 1, { conversationId:id, hostId:"local" }, candidate);
      if (epoch !== this.epoch || this.follows.get(id) !== entry) return;
      if (typeof r.handledByClientId !== "string" || !r.handledByClientId) throw failure("invalid_owner");
      entry.owner = r.handledByClientId; entry.supportsInput = r.result?.supportsUntrustedAppInput === true;
      this.broadcast(id, entry.owner, true);
    } catch { /* Read-only discovery is retried, never a user decision. */ }
    finally { if (epoch === this.epoch) entry.inFlight = false; }
  }
  broadcast(id, owner, following) {
    this.write({type:"broadcast", method:"thread-stream-following-changed", version:1, sourceClientId:this.clientId,
      targetClientIds:[owner], params:{conversationId:id, hostId:"local", following}});
  }
  request(method, version, params, owner, submission = false) {
    if (!this.socket) return Promise.reject(failure("codex_desktop_disconnected"));
    const id = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(failure(submission ? "codex_submission_outcome_unknown" : "codex_desktop_timeout")); }, 5000);
      this.pending.set(id, {method,owner,submission,timer,resolve,reject});
      try { this.write({type:"request",requestId:id,sourceClientId:this.clientId,version,method,params,...(owner ? {targetClientId:owner} : {})}); }
      catch { clearTimeout(timer); this.pending.delete(id); reject(failure(submission ? "codex_submission_outcome_unknown" : "codex_desktop_disconnected")); }
    });
  }
  write(message) {
    if (!this.socket) throw failure("codex_desktop_disconnected");
    const body = Buffer.from(JSON.stringify(message));
    if (body.length > MAX_FRAME) throw failure("codex_frame_limit");
    const header = Buffer.alloc(4); header.writeUInt32LE(body.length);
    this.socket.write(Buffer.concat([header, body]));
  }
  consume(chunk) {
    if (this.buffer.length + chunk.length > MAX_FRAME + 65536) throw Error("frame_limit");
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length >= 4) {
      const length = this.buffer.readUInt32LE();
      if (!length || length > MAX_FRAME) throw Error("frame_limit");
      if (this.buffer.length < length + 4) break;
      const body = this.buffer.subarray(4, length + 4); this.buffer = this.buffer.subarray(length + 4);
      this.handle(JSON.parse(body.toString("utf8")), length);
    }
    if (!this.buffer.length) { clearTimeout(this.frameDeadline); this.frameDeadline = null; }
    else if (!this.frameDeadline) this.frameDeadline = setTimeout(() => this.disconnect("frame_timeout"), 5000);
  }
  handle(m, bytes) {
    if (m.type === "response") {
      const waiter = this.pending.get(m.requestId); if (!waiter) return;
      this.pending.delete(m.requestId); clearTimeout(waiter.timer);
      if (m.resultType !== "success" || m.method !== waiter.method || (waiter.owner && m.handledByClientId !== waiter.owner))
        waiter.reject(failure(waiter.submission ? "codex_submission_outcome_unknown" : "codex_desktop_request_rejected"));
      else waiter.resolve(m);
      return;
    }
    if (m.type === "client-discovery-request") { this.write({type:"client-discovery-response",requestId:m.requestId,response:{canHandle:false}}); return; }
    if (m.type === "request") { this.write({type:"response",requestId:m.requestId,resultType:"error",error:"no-handler-for-request"}); return; }
    if (m.type !== "broadcast" || !this.connected || (m.targetClientIds && !m.targetClientIds.includes(this.clientId))) return;
    if (m.method === "ipc-connection-reset" || (m.method === "client-status-changed" && m.params?.status === "disconnected" && [...this.follows.values()].some((e) => e.owner === m.params.clientId))) { this.disconnect(); return; }
    const p = m.params, entry = this.follows.get(p?.conversationId);
    if (!entry || p.hostId !== "local") return;
    if (m.method === "thread-stream-following-status-requested") {
      if (entry.owner !== m.sourceClientId) { this.invalidate(entry); entry.owner = null; }
      void this.follow(p.conversationId, entry, m.sourceClientId); return;
    }
    if (m.method !== "thread-stream-state-changed") return;
    if (!entry.owner || m.sourceClientId !== entry.owner) return;
    if (m.version !== 11) { this.disconnect("protocol_incompatible"); return; }
    const c = p.change;
    if (!Number.isSafeInteger(c?.revision) || c.revision < 0) throw Error("invalid_revision");
    if (c.type === "snapshot") {
      if (entry.state && c.revision < entry.revision) return;
      entry.state = c.conversationState; entry.bytes = bytes;
    } else if (c.type === "patches") {
      if (!entry.state || c.baseRevision !== entry.revision || c.revision <= entry.revision) { this.invalidate(entry); this.broadcast(p.conversationId, entry.owner, true); return; }
      try { entry.state = P.applyPatches(entry.state, c.patches); }
      catch { this.invalidate(entry); this.broadcast(p.conversationId, entry.owner, true); return; }
      // Conservative budget: patched trees can only be smaller than the old
      // serialized state plus incoming patch bytes. Periodically renew it.
      entry.bytes += bytes;
      if (entry.bytes > 64 * 1024 * 1024) entry.bytes = Buffer.byteLength(JSON.stringify(entry.state));
    } else throw Error("invalid_change");
    if (entry.bytes > 64 * 1024 * 1024 || [...this.follows.values()].reduce((n,e)=>n+(e.bytes||0),0) > MAX_RETAINED) { this.invalidate(entry); throw Error("state_limit"); }
    entry.revision = c.revision;
    const projection = P.project(entry.state, p.conversationId);
    const previousProjectionKey = entry.projectionKey;
    entry.projectionKey = JSON.stringify([projection.authoritative, projection.turnId, projection.status, projection.title, projection.requests]);
    const old = entry.handles; this.dropHandles(entry); entry.projection = projection;
    for (const raw of projection.requests) {
      const signature = JSON.stringify(raw);
      if (signature.length > 262144) continue;
      const previous = old.find((h) => h.signature === signature && h.turnId === projection.turnId);
      const handle = previous || {id:"codex-desktop:"+crypto.randomUUID(), raw, signature, owner:entry.owner, epoch:this.epoch, threadId:p.conversationId, turnId:projection.turnId, submitted:false};
      entry.handles.push(handle); this.handles.set(handle.id, handle);
    }
    if (c.type === "snapshot" && entry.refresh) { const waiter=entry.refresh; entry.refresh=null; clearTimeout(waiter.timer); waiter.resolve(); }
    if (entry.projectionKey !== previousProjectionKey) this.emit("change");
  }
  dropHandles(entry) { for (const h of entry.handles) this.handles.delete(h.id); entry.handles = []; }
  invalidate(entry) { this.dropHandles(entry); entry.state = null; entry.projection = null; entry.projectionKey = null; entry.bytes = 0; this.rejectRefresh(entry); this.emit("change"); }
  rejectRefresh(entry) { if (entry.refresh) { clearTimeout(entry.refresh.timer); entry.refresh.reject(failure("codex_desktop_disconnected")); entry.refresh = null; } }
  validate(id, expected) {
    const h = this.handles.get(id), entry = h && this.follows.get(h.threadId);
    if (!this.connected || !h || (expected && h !== expected) || h.epoch !== this.epoch || h.owner !== entry?.owner || !entry.supportsInput || entry.projection?.turnId !== h.turnId) throw failure("codex_stale_request");
    if (h.submitted) throw failure("codex_request_already_submitted");
    return h;
  }
  async freshSnapshot(h) {
    const entry = this.follows.get(h.threadId);
    if (entry.refresh) throw failure("codex_request_already_submitting");
    await new Promise((resolve,reject) => {
      const timer=setTimeout(()=>{entry.refresh=null;reject(failure("codex_desktop_timeout"));},5000);
      entry.refresh={resolve,reject,timer};
      try { this.broadcast(h.threadId,h.owner,true); } catch(e) { this.rejectRefresh(entry); }
    });
  }
  async respond(id, decision) {
    const h = this.validate(id); const result = P.response(h.raw, decision);
    if (h.submitting) throw failure("codex_request_already_submitting");
    h.submitting = true;
    try {
      // Revalidate immediately before sending; UI may have been open while the
      // desktop answered, changed owners, changed turns, or updated parameters.
      await this.freshSnapshot(h); this.validate(id, h);
      let params;
      if (h.raw.method === "desktop/tool/requestUserInputAsync") {
        const q = h.raw.params.questions[0], answer = result.answers[q.id].answers[0];
        const text = P.replyOpen + "\n" + JSON.stringify([{questionItemId:q.id,question:q.question,answer}]) + "\n" + P.replyClose;
        const messageId=crypto.randomUUID(), cwd=this.follows.get(h.threadId).state.cwd;
        params={conversationId:h.threadId,clientUserMessageId:messageId,input:[{type:"text",text,text_elements:[]}],attachments:[],restoreMessage:{id:messageId,cwd:cwd||null,context:{prompt:q.question+"\n"+answer,turnTrigger:"send_user_message_async_question",addedFiles:[],fileAttachments:[],imageAttachments:[],commentAttachments:[],ideContext:null,workspaceRoots:cwd?[cwd]:[]}}};
      } else params={conversationId:h.threadId,requestId:h.raw.id,...(Object.hasOwn(result,"decision")?{decision:result.decision}:{response:result})};
      h.submitted = true; this.emit("change");
      const reply=await this.request(P.methods.get(h.raw.method),1,params,h.owner,true);
      if (h.raw.method === "desktop/tool/requestUserInputAsync" ? reply.result?.result?.turnId !== h.turnId : reply.result?.ok !== true) throw failure("codex_submission_outcome_unknown");
      return {accepted:true, pendingSettlement:this.handles.has(id)};
    } finally { h.submitting = false; }
  }
  overlay(task, threadId) {
    const entry=this.follows.get(threadId), p=entry?.projection;
    if (!this.connected || !p?.authoritative) return task;
    const h=entry.handles[0];
    const base=task || {id:"codex:"+threadId,sessionId:threadId,provider:"codex",title:p.title||"Codex",cwd:p.cwd,startedAt:Date.now(),updatedAt:Date.now()};
    const status=p.status === "inProgress" ? (h ? "waiting" : ["working","thinking","compacting"].includes(base.status)?base.status:"working") : p.status === "completed"?"completed":p.status === "failed"?"failed":"interrupted";
    return {...base,status,turnId:p.turnId,title:p.title||base.title,approval:h?{...P.approval(h.raw,h.id,entry.supportsInput && !h.submitted),submitted:h.submitted}:null,
      ...(h?{phase:h.raw.method.includes("requestUserInput")?"等待回答":"等待确认"}:{}),desktopConnected:true};
  }
  getState() { return {connected:this.connected,status:this.status,followed:this.follows.size,owners:[...this.follows.values()].filter(e=>e.owner).length,pending:this.handles.size}; }
}
module.exports={CodexDesktop};
