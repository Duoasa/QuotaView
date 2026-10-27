"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
if (process.platform !== "win32")
  throw Error("Build the native helper on Windows with .NET Framework 4.8.");
const root = path.resolve(__dirname, ".."),
  out = path.join(root, "dist/helper");
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const compiler = path.join(
  process.env.WINDIR || "C:\\Windows",
  "Microsoft.NET",
  "Framework64",
  "v4.0.30319",
  "csc.exe",
);
const executable = path.join(out, "quotaview-hook.exe");
execFileSync(
  compiler,
  [
    "/nologo",
    "/optimize+",
    "/target:exe",
    "/platform:anycpu",
    "/reference:System.Web.Extensions.dll",
    "/out:" + executable,
    path.join(root, "native/QuotaViewHelper.cs"),
  ],
  { stdio: "inherit" },
);
execFileSync(executable, ["--helper-smoke-test"], { stdio: "inherit" });
const bytes = fs.readFileSync(executable);
if (bytes.length > 1024 * 1024)
  throw Error("Native helper exceeds 1 MiB size budget");
fs.writeFileSync(
  path.join(out, "helper-manifest.json"),
  JSON.stringify(
    {
      runtime: "Windows .NET Framework 4.8",
      bytes: bytes.length,
      sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
    },
    null,
    2,
  ),
);
