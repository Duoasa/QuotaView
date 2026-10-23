"use strict";
const fs = require("node:fs"),
  path = require("node:path");
const root = path.resolve(__dirname, "../release"),
  MiB = 1024 * 1024;
function files(directory) {
  return fs
    .readdirSync(directory, { withFileTypes: true })
    .flatMap((e) =>
      e.isDirectory()
        ? files(path.join(directory, e.name))
        : [
            {
              path: path.relative(root, path.join(directory, e.name)),
              bytes: fs.statSync(path.join(directory, e.name)).size,
            },
          ],
    );
}
const all = files(root).filter((f) => f.path !== "size-report.json");
const expanded = all.filter((f) =>
  f.path.startsWith("win-unpacked" + path.sep),
);
const installers = all.filter(
  (f) => !f.path.includes(path.sep) && f.path.endsWith(".exe"),
);
const helper = expanded.find((f) =>
  f.path.endsWith(path.join("helper", "quotaview-hook.exe")),
);
const asar = expanded.find((f) => f.path.endsWith("app.asar"));
const report = {
  expandedBytes: expanded.reduce((s, f) => s + f.bytes, 0),
  helperBytes: helper?.bytes,
  asarBytes: asar?.bytes,
  installers,
  largestFiles: [...expanded].sort((a, b) => b.bytes - a.bytes).slice(0, 12),
  budgetsMiB: { expanded: 400, installer: 220, helper: 1, asar: 32 },
};
fs.writeFileSync(
  path.join(root, "size-report.json"),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
if (
  !helper ||
  !asar ||
  !installers.length ||
  helper.bytes > MiB ||
  asar.bytes > 32 * MiB ||
  report.expandedBytes > 400 * MiB ||
  installers.some((f) => f.bytes > 220 * MiB)
)
  throw Error("Package size budget failed; inspect size-report.json");
