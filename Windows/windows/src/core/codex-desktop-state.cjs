"use strict";

// Desktop follower protocol v11. Only public confirmation content leaves this
// module; transcript/state trees stay in the backend and are never persisted.
const { object } = require("./codex-rollout.cjs");
const validID = (v) => (typeof v === "string" && v.length > 0) || Number.isSafeInteger(v);
const methods = new Map([
  ["item/commandExecution/requestApproval", "thread-follower-command-approval-decision"],
  ["item/fileChange/requestApproval", "thread-follower-file-approval-decision"],
  ["item/permissions/requestApproval", "thread-follower-permissions-request-approval-response"],
  ["item/tool/requestUserInput", "thread-follower-submit-user-input"],
  ["desktop/tool/requestUserInputAsync", "thread-follower-steer-turn"],
  ["mcpServer/elicitation/request", "thread-follower-submit-mcp-server-elicitation-response"],
]);
const replyOpen = "<send_user_message_question_reply>", replyClose = "</send_user_message_question_reply>";

function currentTurn(state) {
  const live = Array.isArray(state.turns) ? state.turns.filter(object) : [];
  if (state.turnHistory?.kind !== "canonical") return live.at(-1) || null;
  const history = state.turnHistory.history, islands = history?.islands;
  const last = islands?.at(-1), entities = history?.entitiesByKey;
  if (last?.newerBoundary?.status !== "exhausted" || !Array.isArray(last.entries) || !object(entities)) return null;
  const turns = last.entries.map((e) => entities[e.value]);
  if (turns.some((t) => !t?.turnId)) return null;
  const canonical = turns.at(-1);
  if (!canonical) return live.at(-1) || null;
  const ids = new Set(islands.flatMap((i) => (i.entries || []).map((e) => entities[e.value]?.turnId)));
  let suffix = [];
  for (const turn of live) {
    if (ids.has(turn.turnId)) suffix = [];
    else if (turn.turnId || turn.turnStartedAtMs || turn.status !== "completed" || turn.error || turn.items?.length) suffix.push(turn);
  }
  if (suffix.length) return suffix.at(-1)?.turnId ? suffix.at(-1) : null;
  const overlay = live.findLast((t) => t.turnId === canonical.turnId);
  if (!overlay) return canonical;
  const result = { ...canonical, ...overlay };
  if (canonical.status !== "inProgress" && overlay.status === "inProgress" && (canonical.itemsPagination || overlay.itemsPagination)) result.status = canonical.status;
  const incoming = new Map((overlay.items || []).map((i) => [i.id, i]));
  const oldIDs = new Set((canonical.items || []).map((i) => i.id));
  result.items = (canonical.items || []).map((i) => incoming.get(i.id) || i).concat((overlay.items || []).filter((i) => !oldIDs.has(i.id)));
  return result;
}

function asyncRequests(turn, threadId) {
  const found = new Map();
  for (const item of turn.items || []) {
    if (item.type === "agentMessage" && item.id && Array.isArray(item.questions)) {
      item.questions.forEach((q, index) => {
        if (typeof q.title !== "string" || !q.title.trim() || (q.options && (!Array.isArray(q.options) || q.options.some((s) => typeof s !== "string")))) return;
        const id = JSON.stringify(["request_user_input_async", item.id, index]);
        if (found.has(id)) throw Error("duplicate_async_question");
        found.set(id, { id, method: "desktop/tool/requestUserInputAsync", params: { threadId, turnId: turn.turnId, itemId: item.id,
          questions: [{ id, question: q.title, options: (q.options || []).map((label) => ({ label })), isOther: true }] } });
      });
    }
    if (item.type !== "userMessage" && !(item.type === "steeringUserMessage" && item.status === "accepted")) continue;
    const input = item.type === "userMessage" ? item.content : item.input;
    if (!Array.isArray(input) || input.length !== 1 || input[0].type !== "text") continue;
    const text = input[0].text?.trim();
    if (!text?.startsWith(replyOpen) || !text.endsWith(replyClose)) continue;
    try {
      const replies = JSON.parse(text.slice(replyOpen.length, -replyClose.length));
      for (const reply of Array.isArray(replies) ? replies : [replies]) {
        if (typeof reply.answer === "string" && found.get(reply.questionItemId)?.params.questions[0].question === reply.question) found.delete(reply.questionItemId);
      }
    } catch {}
  }
  return [...found.values()];
}

function project(state, threadId) {
  if (!object(state) || state.id !== threadId || !Array.isArray(state.requests) || state.requests.length > 256) throw Error("invalid_desktop_state");
  const turn = currentTurn(state);
  if (!turn?.turnId || !["inProgress", "completed", "interrupted", "failed"].includes(turn.status)) return { authoritative: false, requests: [] };
  const requests = [], seen = new Set();
  if (turn.status === "inProgress") {
    for (const raw of state.requests) {
      if (raw.completed === true || !methods.has(raw.method)) continue;
      if (!validID(raw.id) || !object(raw.params) || raw.params.threadId !== threadId) throw Error("invalid_desktop_request");
      if (raw.params.turnId !== turn.turnId && !(raw.method === "mcpServer/elicitation/request" && raw.params.turnId == null)) continue;
      const key = JSON.stringify(raw.id);
      if (seen.has(key)) throw Error("duplicate_desktop_request");
      seen.add(key);
      if (raw.method === "item/fileChange/requestApproval") {
        const item = (turn.items || []).find((i) => i.type === "fileChange" && i.id === raw.params.itemId);
        requests.push({...raw, fileChanges:item?.changes?.map(({path,kind,diff})=>({path,kind,diff})) || []});
      } else requests.push(raw);
    }
    requests.push(...asyncRequests(turn, threadId));
  }
  if (requests.length > 256) throw Error("too_many_desktop_requests");
  return { authoritative: true, turnId: turn.turnId, status: turn.status, requests, title: state.title, cwd: state.cwd };
}

function approval(raw, id, canRespond) {
  const p = raw.params, questions = Array.isArray(p.questions) ? p.questions : [];
  const isQuestion = raw.method.endsWith("requestUserInput") || raw.method.endsWith("requestUserInputAsync");
  let choices = ["accept", "decline"];
  if (Array.isArray(p.availableDecisions)) choices = choices.filter((s) => p.availableDecisions.includes(s));
  // URL elicitation requires the provider's external consent flow. Only an
  // empty form is a yes/no confirmation; richer schemas stay in Codex.
  const mcp = raw.method === "mcpServer/elicitation/request";
  const emptyForm = mcp && p.mode === "form" && p.requestedSchema?.type === "object" && Object.keys(p.requestedSchema.properties || {}).length === 0 && !(p.requestedSchema.required?.length);
  if (mcp && !emptyForm) canRespond = false;
  if (raw.method.includes("fileChange") && !raw.fileChanges?.length) choices = choices.filter((s) => s !== "accept");
  if (raw.method.includes("commandExecution") && !p.command && !p.networkApprovalContext && !p.additionalPermissions) choices = choices.filter((s) => s !== "accept");
  return { id, canRespond: canRespond && (!isQuestion || (questions.length > 0 && questions.every((q) => typeof q.id === "string" && typeof q.question === "string" && !q.isSecret))),
    kind: isQuestion ? "question" : raw.method.includes("commandExecution") ? "command" : "permission",
    title: isQuestion ? questions[0]?.question : mcp ? (p.message || "服务请求需要确认") : raw.method.includes("fileChange") ? "文件修改需要确认" : "操作需要确认",
    reason: p.reason || p.description || "", command: p.command || null, cwd: p.cwd || null,
    scope: raw.fileChanges?.length ? JSON.stringify(raw.fileChanges,null,2) : p.permissions ? JSON.stringify(p.permissions, null, 2) : p.networkApprovalContext || p.additionalPermissions ? JSON.stringify({network:p.networkApprovalContext,permissions:p.additionalPermissions},null,2) : p.grantRoot || p.url || null,
    questions: questions.map((q) => ({ id:q.id, question:q.question, options:q.options || [], multiSelect:q.multiSelect === true, isOther:q.isOther !== false })),
    decisions: choices, source:"codex-desktop", method: raw.method };
}

function answerResponse(raw, decision) {
  if (!object(decision) || Object.keys(decision).length !== 1 || !object(decision.answers)) throw Error("invalid_question_response");
  const questions = raw.params.questions;
  if (!Array.isArray(questions) || !questions.length || Object.keys(decision.answers).length !== questions.length) throw Error("invalid_question_response");
  const answers = {};
  for (const q of questions) {
    let value = decision.answers[q.id];
    value = typeof value === "string" ? [value] : value?.answers;
    if (q.isSecret || !Array.isArray(value) || !value.length || value.length > 32 || value.some((s) => typeof s !== "string" || !s.trim() || s.length > 65536) || (!q.multiSelect && value.length !== 1)) throw Error("invalid_question_response");
    if (q.isOther === false && value.some((s) => !(q.options || []).some((o) => (typeof o === "string" ? o : o.label) === s))) throw Error("invalid_question_option");
    answers[q.id] = { answers: value };
  }
  return { answers };
}

function response(raw, decision) {
  if (raw.method.includes("requestUserInput")) return answerResponse(raw, decision);
  if (!["accept", "decline"].includes(decision)) throw Error("invalid_approval_decision");
  const displayed = approval(raw, "validation", true);
  if (!displayed.canRespond || !displayed.decisions.includes(decision)) throw Error("unavailable_approval_decision");
  if (Array.isArray(raw.params.availableDecisions) && !raw.params.availableDecisions.includes(decision)) throw Error("unavailable_approval_decision");
  if (raw.method === "mcpServer/elicitation/request") return decision === "accept" ? {action:"accept",content:{}} : {action:"decline"};
  if (raw.method === "item/permissions/requestApproval") return { permissions: decision === "accept" ? structuredClone(raw.params.permissions) : {}, scope: "turn" };
  return { decision };
}

// Immer patches use path arrays, not JSON pointer strings. Refuse prototype
// segments, out-of-range indices and missing parents; recover with a snapshot.
function applyPatches(state, patches) {
  if (!Array.isArray(patches) || patches.length > 2048) throw Error("invalid_patches");
  for (const { op, path, value } of patches) {
    if (!["add", "remove", "replace"].includes(op) || !Array.isArray(path) || path.length > 128 || path.some((s) => !["string", "number"].includes(typeof s) || ["__proto__", "constructor", "prototype"].includes(s))) throw Error("invalid_patch");
    if (!path.length) { if (op === "remove" || !object(value)) throw Error("invalid_root_patch"); state = value; continue; }
    let parent = state;
    for (const key of path.slice(0, -1)) { if (!parent || !Object.hasOwn(parent, key)) throw Error("missing_patch_parent"); parent = parent[key]; }
    const key = path.at(-1);
    if (!parent || typeof parent !== "object") throw Error("invalid_patch_parent");
    if (Array.isArray(parent)) {
      if (key === "length" && op === "replace" && Number.isSafeInteger(value) && value >= 0 && value <= parent.length) { parent.length = value; continue; }
      if (!Number.isSafeInteger(key) || key < 0 || key > parent.length || (op !== "add" && key === parent.length)) throw Error("invalid_patch_index");
      if (op === "remove") parent.splice(key, 1);
      else if (op === "add") parent.splice(key, 0, value);
      else parent[key] = value;
    } else {
      if (op !== "add" && !Object.hasOwn(parent, key)) throw Error("missing_patch_key");
      if (op === "remove") delete parent[key]; else parent[key] = value;
    }
  }
  return state;
}
module.exports = { project, currentTurn, approval, response, methods, applyPatches, replyOpen, replyClose };
