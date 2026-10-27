"use strict";
const { EventEmitter } = require("node:events");
const { spawn } = require("node:child_process");
// Uses the documented Windows user32 API. Only the foreground window rectangle
// and owning PID are read: no title, content, keystrokes, screenshot or process scan.
class ForegroundMonitor extends EventEmitter {
  constructor() {
    super();
    this.child = null;
    this.buffer = "";
    this.available = process.platform === "win32";
  }
  start() {
    if (this.child || !this.available) return;
    if (!this.executable) {
      this.available = false;
      this.emit("unavailable");
      return;
    }
    const child = (this.child = spawn(
      this.executable,
      ["--foreground-monitor"],
      { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] },
    ));
    this.child.stdout.setEncoding("utf8");
    this.child.stdout.on("data", (data) => {
      if (this.child !== child) return;
      this.buffer = (this.buffer + data).slice(-16384);
      let i;
      while ((i = this.buffer.indexOf("\n")) >= 0) {
        const line = this.buffer.slice(0, i);
        this.buffer = this.buffer.slice(i + 1);
        try {
          const r = JSON.parse(line);
          if (
            ["x", "y", "width", "height", "pid"].every((k) =>
              Number.isFinite(r[k]),
            ) &&
            r.width > 0 &&
            r.height > 0 &&
            r.pid !== process.pid
          )
            this.emit("rect", r);
        } catch {}
      }
    });
    this.child.on("error", () => {
      if (this.child !== child) return;
      this.available = false;
      this.child = null;
      this.emit("unavailable");
    });
    this.child.on("exit", () => {
      if (this.child !== child) return;
      this.child = null;
      this.available = false;
      this.emit("unavailable");
    });
    this.child.stderr.on("data", () => {});
  }
  stop() {
    const child = this.child;
    this.child = null;
    child?.kill();
    this.buffer = "";
  }
}
function safeExternal(value) {
  if (typeof value !== "string" || value.length > 8192)
    throw Error("Invalid URL");
  const u = new URL(value);
  if (!["https:", "http:"].includes(u.protocol) || u.username || u.password)
    throw Error("Only public HTTP(S) links can be opened");
  return u.href;
}
function placeIsland(display, width, height) {
  const b = display.bounds || display.workArea;
  const w = Math.min(width, b.width);
  return {
    x: Math.round(b.x + (b.width - w) / 2),
    y: Math.round(b.y),
    width: Math.round(w),
    height: Math.min(Math.round(height), b.height - 16),
  };
}
module.exports = { ForegroundMonitor, safeExternal, placeIsland };
