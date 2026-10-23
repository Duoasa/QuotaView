"use strict";
const { EventEmitter } = require("node:events");
const { spawn } = require("node:child_process");
// Uses the documented Windows user32 API. Only the foreground window rectangle
// and owning PID are read: no title, content, keystrokes, screenshot or process scan.
const FOREGROUND_SCRIPT = `$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class QuotaViewForeground {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
}
'@
while ($true) {
 $previousDpi=[QuotaViewForeground]::SetThreadDpiAwarenessContext([IntPtr](-4))
 $window=[QuotaViewForeground]::GetForegroundWindow()
 $rect=New-Object QuotaViewForeground+RECT
 [uint32]$owner=0
 [void][QuotaViewForeground]::GetWindowThreadProcessId($window,[ref]$owner)
 if ([QuotaViewForeground]::GetWindowRect($window,[ref]$rect)) {
  @{x=$rect.Left;y=$rect.Top;width=($rect.Right-$rect.Left);height=($rect.Bottom-$rect.Top);pid=$owner}|ConvertTo-Json -Compress
 }
 [void][QuotaViewForeground]::SetThreadDpiAwarenessContext($previousDpi)
 Start-Sleep -Milliseconds 1500
}`;
class ForegroundMonitor extends EventEmitter {
  constructor() {
    super();
    this.child = null;
    this.buffer = "";
    this.available = process.platform === "win32";
  }
  start() {
    if (this.child || !this.available) return;
    const command = Buffer.from(FOREGROUND_SCRIPT, "utf16le").toString(
      "base64",
    );
    const child = this.child = spawn(
      "powershell.exe",
      ["-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", command],
      { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] },
    );
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
  const b = display.workArea || display.bounds;
  const w = Math.min(width, b.width);
  return {
    x: Math.round(b.x + (b.width - w) / 2),
    y: Math.round(b.y + 8),
    width: Math.round(w),
    height: Math.min(Math.round(height), b.height - 16),
  };
}
module.exports = { ForegroundMonitor, safeExternal, placeIsland };
