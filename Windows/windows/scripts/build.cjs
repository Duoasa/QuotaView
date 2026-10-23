const fs = require("node:fs");
const path = require("node:path");
const { buildSync } = require("esbuild");
const root = path.resolve(__dirname, "..");
const output = path.join(root, "dist");
fs.mkdirSync(path.join(output, "renderer/effects"), { recursive: true });
fs.rmSync(path.join(output, "assets"), { recursive: true, force: true });
fs.cpSync(path.join(root, "assets"), path.join(output, "assets"), {
  recursive: true,
});
fs.cpSync(path.join(root, "shared"), path.join(output, "renderer/shared"), {
  recursive: true,
});
for (const name of ["index.html", "app.css", "native-ui.css"])
  fs.copyFileSync(
    path.join(root, "renderer", name),
    path.join(output, "renderer", name),
  );
buildSync({
  entryPoints: [path.join(root, "renderer/app.js")],
  outfile: path.join(output, "renderer/app.js"),
  bundle: true,
  format: "iife",
  platform: "browser",
  target: "chrome145",
  minify: true,
  legalComments: "linked",
});
for (const name of ["model.js", "runtime.js", "effects.css"])
  fs.copyFileSync(
    path.join(root, "../ElectronEffects/src", name),
    path.join(output, "renderer/effects", name),
  );
const assets = {
  ...require("../../ElectronEffects/src/assets.js"),
  smoke: require("../../ElectronEffects/src/smoke-profiles.json"),
  progressShader: fs.readFileSync(
    path.join(root, "../ElectronEffects/src/progress.frag"),
    "utf8",
  ),
};
fs.writeFileSync(
  path.join(output, "renderer/effects/assets.js"),
  "/* QuotaView shaders, MIT. */\nwindow.QVEffectAssets=" +
    JSON.stringify(assets) +
    ";\n",
);
console.log("Built renderer, effects and assets from tracked project files.");
