"use strict";
// Opt-in, isolated approval project. Requests use the real .NET hook and service;
// the command text is display-only and is never passed to a shell.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const { IntegrationService } = require("../src/core/integrations.cjs");
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const check = (value, message) => {
  if (!value) throw Error(message);
};
async function until(read, message) {
  for (let n = 0; n < 160; n++) {
    const value = await read();
    if (value) return value;
    await wait(50);
  }
  throw Error(message);
}
async function create({ root, executable, settings }) {
  const project = path.join(root, "Approval Demo");
  const home = path.join(root, "home");
  const claudeHome = path.join(home, ".claude");
  fs.mkdirSync(project, { recursive: true });
  fs.mkdirSync(claudeHome, { recursive: true });
  fs.writeFileSync(
    path.join(project, "sample.txt"),
    "QuotaView isolated approval fixture.\n",
  );
  fs.writeFileSync(
    path.join(project, "README.md"),
    "# 模拟审批项目\n\n仅用于验证 QuotaView 审批界面和 Hook 回执。卡片中的命令不会执行。允许、拒绝或取消后，结果写入 receipts.json。此目录使用独立的 Claude 配置，不连接真实会话。\n",
  );
  settings.claudeHome = claudeHome;
  const service = new IntegrationService({
    dataDir: path.join(root, "data"),
    home,
    env: {},
    settings,
    executable,
    packaged: true,
    decisionTimeoutMs: 1800000,
  });
  const codexFixture = await require("./codex-approval-fixture.cjs").create({
    root,
    executable,
  });
  settings.providers.codex = true;
  const children = new Set(),
    receipts = [];
  let stopped = false;
  function hook(payload) {
    const child = spawn(
      executable,
      ["--quotaview-hook", "--configuration", service.routePath("claude")],
      {
        windowsHide: true,
        stdio: ["pipe", "pipe", "pipe"],
      },
    );
    children.add(child);
    const result = new Promise((resolve, reject) => {
      let output = "",
        error = "";
      child.stdout.setEncoding("utf8").on("data", (value) => {
        output += value;
      });
      child.stderr.setEncoding("utf8").on("data", (value) => {
        error += value;
      });
      child.on("error", reject);
      child.on("close", (code) => {
        children.delete(child);
        code
          ? reject(Error("Mock hook failed: " + code + " " + error))
          : resolve(output);
      });
      child.stdin.on("error", () => {});
      child.stdin.end(JSON.stringify(payload));
    });
    result.catch(() => {});
    return { child, result };
  }
  await service.start();
  await service.configure("claude", true, {
    home: claudeHome,
    interactiveApprovals: true,
  });
  async function request(label, { question = false } = {}) {
    const session = crypto.randomUUID(),
      title = "[模拟审批] " + label;
    const base = {
      session_id: session,
      prompt_id: session,
      cwd: project,
      session_title: title,
      model: "模拟客户端",
    };
    await hook({ ...base, hook_event_name: "UserPromptSubmit" }).result;
    const tool = question ? "AskUserQuestion" : "PowerShell";
    const input = question
      ? {
          questions: [
            {
              question: "模拟项目采用哪种测试方案？",
              header: "测试方案",
              multiSelect: false,
              options: [
                { label: "快速检查", description: "只验证模拟审批往返。" },
                { label: "完整检查", description: "验证所有模拟审批结果。" },
              ],
            },
          ],
        }
      : {
          command: "Get-Content -LiteralPath './sample.txt'",
          description: "本地模拟审批：只验证按钮与回执，命令不会执行。",
        };
    const pending = hook({
      ...base,
      hook_event_name: "PermissionRequest",
      tool_name: tool,
      tool_input: input,
      tool_use_id: session,
    });
    const task = await until(
      () =>
        service
          .getSnapshot()
          .tasks.find((t) => t.title === title && t.approval?.canRespond),
      "Approval did not reach the service",
    );
    return { ...pending, base, task, label };
  }
  async function finish(request, { remove = false } = {}) {
    const output = await request.result;
    const decision = output
      ? JSON.parse(output).hookSpecificOutput?.decision
      : null;
    receipts.push({
      title: request.task.title,
      decision,
      commandExecuted: false,
      at: new Date().toISOString(),
    });
    fs.writeFileSync(
      path.join(project, "receipts.json"),
      JSON.stringify(receipts, null, 2),
    );
    if (!stopped) {
      await hook({
        ...request.base,
        hook_event_name: "Stop",
        last_assistant_message:
          "模拟审批已结束。回执：" +
          JSON.stringify(decision) +
          "。未执行卡片中的命令。",
      }).result;
      if (remove)
        await hook({ ...request.base, hook_event_name: "SessionEnd" }).result;
    }
    return decision;
  }
  function stop() {
    stopped = true;
    for (const child of children) child.kill();
    void service.stop();
    void codexFixture.stop();
  }
  return { service, project, request, finish, stop, codexFixture };
}
async function evaluate(island, code) {
  return island.webContents.executeJavaScript("(async()=>{" + code + "})()");
}
async function openCard(island, task) {
  await until(
    () =>
      evaluate(
        island,
        "return !!document.querySelector('[data-task-id=" +
          JSON.stringify(task.id) +
          "]');",
      ),
    "Approval card did not render",
  );
  await evaluate(
    island,
    "const c=document.querySelector('[data-task-id=" +
      JSON.stringify(task.id) +
      "]');if(c.getAttribute('aria-expanded')!=='true')c.click();return true;",
  );
  await until(
    () =>
      evaluate(island, "return !!document.querySelector('.approval-panel');"),
    "Approval details did not open",
  );
}
async function assertAutoCard(island, task) {
  await until(() => evaluate(island,
    "const card=document.querySelector('[data-task-id=" + JSON.stringify(task.id) + "]');return card?.getAttribute('aria-expanded')==='true' && !!card.parentElement.querySelector('.approval-panel');"),
    "Pending request did not automatically open its own detail");
}
async function verify({ island, scenario, folder }) {
  const results = [];
  async function test(name, fn) {
    try {
      await fn();
      results.push({ name, ok: true });
    } catch (error) {
      results.push({ name, ok: false, error: String(error.message) });
      throw error;
    }
  }
  try {
    for (const [label, button, behavior, interrupt] of [
      ["允许一次", "允许这一次", "allow", false],
      ["拒绝请求", "拒绝", "deny", false],
      ["取消请求", "取消请求", "deny", true],
    ])
      await test(label + "经界面与原生 Hook 返回", async () => {
        const request = await scenario.request(label);
        await assertAutoCard(island, request.task);
        await evaluate(
          island,
          "const b=[...document.querySelectorAll('.approval-actions button')].find(b=>b.textContent===" +
            JSON.stringify(button) +
            ");if(!b||b.disabled)throw Error('Approval action unavailable');b.click();return true;",
        );
        const decision = await scenario.finish(request, { remove: true });
        check(
          decision?.behavior === behavior &&
            !!decision?.interrupt === interrupt,
          "Wrong native decision",
        );
        const replay = await evaluate(
          island,
          "try{await window.quotaView.respond({id:" +
            JSON.stringify(request.task.approval.id) +
            ",decision:'accept'});return false;}catch{return true;}",
        );
        check(replay, "Consumed approval accepted a second response");
      });
    await test("问题选择校验与答案回传", async () => {
      const request = await scenario.request("选择测试方案", {
        question: true,
      });
      await assertAutoCard(island, request.task);
      check(
        await evaluate(
          island,
          "return document.querySelector('.approval-actions button')?.disabled===true;",
        ),
        "Unanswered question can submit",
      );
      await evaluate(
        island,
        "document.querySelector('.question-option').click();return true;",
      );
      await until(
        () =>
          evaluate(
            island,
            "return document.querySelector('.approval-actions button')?.disabled===false;",
          ),
        "Selected answer not enabled",
      );
      await evaluate(
        island,
        "document.querySelector('.approval-actions button').click();return true;",
      );
      const decision = await scenario.finish(request, { remove: true });
      check(
        decision?.behavior === "allow" &&
          decision?.updatedInput?.answers?.["模拟项目采用哪种测试方案？"] ===
            "快速检查",
        "Question answer lost",
      );
    });
    await test("关闭请求后拒绝过期审批", async () => {
      const request = await scenario.request("过期请求");
      await assertAutoCard(island, request.task);
      scenario.service.releasePending(
        request.task.approval.id,
        "模拟请求已结束",
      );
      await scenario.finish(request, { remove: true });
      const rejected = await evaluate(
        island,
        "try{await window.quotaView.respond({id:" +
          JSON.stringify(request.task.approval.id) +
          ",decision:'accept'});return false;}catch{return true;}",
      );
      check(rejected, "Expired approval was accepted");
    });
    await test("Codex 原生审批事件自动展开，工具结束后清除待确认", async () => {
      await evaluate(
        island,
        "await window.quotaView.resize({expanded:false,pinned:false});return true;",
      );
      await wait(350);
      await scenario.codexFixture.hook("PermissionRequest", {
        tool_use_id: "display-fixture",
      });
      await until(
        () =>
          evaluate(
            island,
            "return window.quotaView.snapshot().then(s=>s.ui.expanded&&s.tasks.some(t=>t.provider==='codex'&&t.status==='waiting'));",
          ),
        "Codex approval did not auto-expand island",
      );
      const task = scenario.codexFixture.service.getSnapshot().tasks[0];
      await assertAutoCard(island, task);
      check(
        await evaluate(
          island,
          "return !document.querySelector('.approval-actions');",
        ),
        "Codex observation exposes approval actions",
      );
      if (island.capture && folder) {
        fs.mkdirSync(path.join(folder, "codex-approval"), {recursive:true});
        await wait(350);
        await island.capture(path.join(folder, "codex-approval"));
      }
      await scenario.codexFixture.hook("PostToolUse", {
        tool_use_id: "display-fixture",
      });
      await until(
        () =>
          evaluate(
            island,
            "return window.quotaView.snapshot().then(s=>s.tasks.filter(t=>t.provider==='codex').every(t=>t.status!=='waiting'&&!t.approval));",
          ),
        "Codex approval did not settle",
      );
    });
  } catch {
    /* Report all completed steps and the failing step. */
  }
  const report = {
    ok: results.every((r) => r.ok),
    tests: results,
    project: scenario.project,
    actualCommandExecution: false,
  };
  if (folder) {
    fs.mkdirSync(folder, { recursive: true });
    fs.writeFileSync(
      path.join(folder, "approval-report.json"),
      JSON.stringify(report, null, 2),
    );
  }
  return report;
}
async function present({ island, scenario, root }) {
  const requests = [];
  for (const [label, options] of [
    ["读取 sample.txt · 可尝试允许 / 拒绝 / 取消", {}],
    ["第二次文件读取 · 可比较另一种决定", {}],
    ["选择测试方案 · 可尝试问题审批", { question: true }],
  ]) {
    const request = await scenario.request(label, options);
    requests.push(request);
    scenario
      .finish(request)
      .catch((e) => console.error("Approval demo: " + e.message));
  }
  await openCard(island, requests[0].task);
  fs.writeFileSync(
    path.join(root, "ready.json"),
    JSON.stringify(
      { project: scenario.project, pending: requests.length, simulated: true },
      null,
      2,
    ),
  );
  if (island.capture) await island.capture(root);
}
module.exports = { create, verify, present };
