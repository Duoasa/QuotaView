"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict");
const { RolloutParser, CodexService } = require("../src/core/codex.cjs");
const { selectPayload } = require("../src/core/codex-hook.cjs");
function fixture() {
  let now = 1700000000000;
  const parser = new RolloutParser(
    { id: "session", source: "appServer" },
    { clock: () => now },
  );
  const feed = (payload) =>
    parser.feed(
      JSON.stringify({
        type: "event_msg",
        timestamp: new Date(now).toISOString(),
        payload,
      }),
      { live: true },
    );
  feed({ type: "task_started", turn_id: "turn" });
  const hook = (event, extra = {}) =>
    parser.observeHook({
      event,
      sessionId: "session",
      turnId: "turn",
      toolName: "Bash",
      observedAt: ++now,
      ...extra,
    });
  return { parser, hook, feed, advance: (ms) => (now += ms) };
}
test("Codex permission hooks show read-only waiting and matching completion clears it", () => {
  const { parser, hook } = fixture();
  hook("PermissionRequest", { toolUseId: "command-1" });
  assert.equal(parser.getTask().status, "waiting");
  assert.equal(parser.getTask().approval.canRespond, false);
  hook("PreCompact");
  assert.equal(parser.getTask().status, "waiting");
  hook("PostToolUse", { toolUseId: "other" });
  assert.equal(parser.getTask().status, "waiting");
  hook("PostToolUse", { toolUseId: "command-1" });
  assert.notEqual(parser.getTask().status, "waiting");
  assert.equal(parser.getTask().approval, undefined);
});
test("Codex name-only approval resolves only an unambiguous matching tool", () => {
  const { parser, hook } = fixture();
  hook("PermissionRequest");
  hook("PostToolUse", { toolName: "apply_patch" });
  assert.equal(parser.getTask().status, "waiting");
  hook("PostToolUse");
  assert.equal(parser.getTask().approval, undefined);
  hook("PermissionRequest");
  hook("PermissionRequest");
  hook("PostToolUse");
  assert.equal(parser.getTask().status, "waiting");
  hook("Stop");
  assert.equal(parser.getTask().approval, undefined);
});
test("Codex hook identity, stale observation, completed and new turns do not invent waiting", () => {
  const { parser, hook, feed, advance } = fixture();
  for (const extra of [
    { sessionId: "other" },
    { turnId: "other" },
    { turnId: null },
    { observedAt: 1 },
  ])
    assert.equal(hook("PermissionRequest", extra), false);
  hook("PermissionRequest");
  advance(300001);
  assert.equal(parser.getTask().status, "unknown");
  assert.equal(parser.getTask().approval, undefined);
  feed({ type: "task_started", turn_id: "next" });
  assert.equal(parser.getTask().approval, undefined);
  feed({ type: "task_complete", turn_id: "next" });
  assert.equal(hook("PermissionRequest", { turnId: "next" }), false);
});
test("Codex permission event is not overwritten by another event in the same debounce batch", async (t) => {
  const { parser } = fixture();
  const service = new CodexService({
    home: process.cwd(),
    clock: parser.clock,
  });
  service.enabled = true;
  service.hooks.enabled = true;
  service.cursors.set("fixture", { parser });
  service.refreshActivity = async () => {};
  t.after(() => service.stop());
  service.observeHook({
    event: "PermissionRequest",
    sessionId: "session",
    turnId: "turn",
    toolName: "Bash",
    observedAt: 1700000000001,
  });
  service.observeHook({
    event: "PreCompact",
    sessionId: "session",
    turnId: "turn",
    observedAt: 1700000000002,
  });
  await new Promise((r) => setTimeout(r, 90));
  assert.equal(service.getSnapshot().tasks[0].status, "waiting");
  await assert.rejects(
    service.respond({ decision: "accept" }),
    /must be answered in Codex/,
  );
});
test("Codex hook forwards identity metadata only", () => {
  const value = selectPayload({
    hook_event_name: "PermissionRequest",
    session_id: "s",
    turn_id: "t",
    tool_name: "Bash",
    tool_use_id: "i",
    tool_input: { command: "private" },
    prompt: "secret",
  });
  assert.deepEqual(value, {
    event: "PermissionRequest",
    sessionId: "s",
    turnId: "t",
    toolName: "Bash",
    toolUseId: "i",
  });
  assert.equal(
    selectPayload({
      hook_event_name: "PermissionRequest",
      session_id: "s",
      tool_name: "bad\nname",
    }),
    null,
  );
});
