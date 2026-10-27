const fs = require("fs"),
  path = require("path"),
  { build } = require("esbuild");
(async () => {
  const root = path.resolve(__dirname, ".."),
    repo = path.dirname(root),
    out = path.join(root, "build");
  fs.mkdirSync(out, { recursive: true });
  const { version } = require('../../version.json');
  if (!/^\d+\.\d+\.\d+-win\.\d+$/.test(version)) throw Error('Invalid Windows version');
  fs.writeFileSync(path.join(out, 'BuildIdentity.g.cs'), `namespace QuotaView; internal static class BuildIdentity { internal const string Version = "${version}"; }\n`);
  const [marketing, number] = version.split('-win.');
  fs.writeFileSync(path.join(out, 'Version.props'), `<Project><PropertyGroup><Version>${marketing}</Version><FileVersion>${marketing}.${number}</FileVersion><InformationalVersion>${version}</InformationalVersion></PropertyGroup></Project>\n`);
  const nativeShim = {
    name: "dotnet-platform",
    setup(build) {
      build.onResolve({ filter: /helper-runtime\.cjs$/ }, () => ({
        path: "helper-runtime",
        namespace: "helper-native",
      }));
      build.onLoad({ filter: /.*/, namespace: "helper-native" }, () => ({
        contents: `exports.materializeHelper=()=>globalThis.process.execPath;`,
        loader: "js",
      }));
      build.onResolve({ filter: /^(node:|electron$)/ }, (args) => ({
        path: args.path.replace(/^node:/, ""),
        namespace: "native",
      }));
      build.onLoad({ filter: /.*/, namespace: "native" }, (args) => {
        const name = args.path,
          runtime = path.join(root, "runtime");
        if (["fs", "fs/promises", "path", "electron"].includes(name))
          return {
            contents:
              name === "fs/promises"
                ? `import {promises} from './fs.js';module.exports=promises;`
                : `module.exports=require('./${name}.js')${name === "fs" ? ".default" : ""};`,
            resolveDir: runtime,
            loader: "js",
          };
        if (["events", "buffer", "string_decoder"].includes(name))
          return {
            contents: `module.exports=require('${name}');`,
            resolveDir: root,
            loader: "js",
          };
        if (["os", "crypto", "url", "util"].includes(name))
          return {
            contents: `module.exports=require('./misc.js').${name};`,
            resolveDir: runtime,
            loader: "js",
          };
        if (["net", "tls", "http", "child_process"].includes(name))
          return {
            contents: `module.exports=require('./io.js').${name};`,
            resolveDir: runtime,
            loader: "js",
          };
        throw Error("Unported native dependency: " + name);
      });
      build.onResolve({ filter: /^yaml$/ }, () => ({
        path: path.join(
          path.dirname(require.resolve("yaml/package.json")),
          "browser/index.js",
        ),
      }));
      build.onResolve({ filter: /^@iarna\/toml$/ }, () => ({
        path: "toml",
        namespace: "toml-sync",
      }));
      build.onLoad({ filter: /.*/, namespace: "toml-sync" }, () => ({
        contents: `exports.parse=require('@iarna/toml/parse-string.js');exports.stringify=require('@iarna/toml/stringify.js');`,
        resolveDir: root,
        loader: "js",
      }));
      build.onLoad({ filter: /windows[\\/]src[\\/].*\.cjs$/ }, (args) => {
        const rel = path
          .relative(path.join(repo, "windows"), path.dirname(args.path))
          .replace(/\\/g, "/");
        return {
          contents:
            `const __dirname=globalThis.process.appRoot+${JSON.stringify("/" + rel)};\n` +
            fs.readFileSync(args.path, "utf8"),
          loader: "js",
        };
      });
    },
  };
  await build({
    stdin: {
      contents: `import './runtime/bridge.js';if(process.argv.includes('--adapter-test'))require('./tests/runtime.cjs');else require('../windows/src/main.cjs');`,
      resolveDir: root,
    },
    outfile: path.join(out, "backend.js"),
    bundle: true,
    format: "iife",
    platform: "browser",
    target: "es2022",
    plugins: [nativeShim],
    legalComments: "linked",
  });
  await build({
    entryPoints: [path.join(repo, "windows/renderer/app.js")],
    outfile: path.join(out, "dist/renderer/app.js"),
    bundle: true,
    format: "iife",
    platform: "browser",
    target: "es2022",
    legalComments: "linked",
  });
  for (const dir of ["assets", "shared"])
    fs.cpSync(
      path.join(repo, "windows", dir),
      path.join(out, dir === "assets" ? "dist/assets" : "dist/renderer/shared"),
      { recursive: true },
    );
  for (const n of ["app.css", "native-ui.css", "index.html"])
    fs.copyFileSync(
      path.join(repo, "windows/renderer", n),
      path.join(out, "dist/renderer", n),
    );
  fs.mkdirSync(path.join(out, "dist/renderer/effects"), { recursive: true });
  for (const n of ["model.js", "runtime.js", "effects.css"])
    fs.copyFileSync(
      path.join(repo, "ElectronEffects/src", n),
      path.join(out, "dist/renderer/effects", n),
    );
  const assets = {
    ...require(path.join(repo, "ElectronEffects/src/assets.js")),
  };
  fs.writeFileSync(
    path.join(out, "dist/renderer/effects/assets.js"),
    "window.QVEffectAssets=" + JSON.stringify(assets) + ";",
  );
  fs.mkdirSync(path.join(out, "src/core"), { recursive: true });
  fs.copyFileSync(
    path.join(repo, "windows/src/core/dsh-plugin.mjs"),
    path.join(out, "src/core/dsh-plugin.mjs"),
  );
  fs.writeFileSync(
    path.join(out, "backend.html"),
    '<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'self\'"><script src="backend.js"></script>',
  );
  fs.copyFileSync(
    path.join(root, "runtime/renderer-bridge.js"),
    path.join(out, "renderer-bridge.js"),
  );
  fs.writeFileSync(
    path.join(out, "package.json"),
    JSON.stringify({ version }),
  );
  const notices = path.join(out, "dist/assets/licenses");
  fs.mkdirSync(notices, { recursive: true });
  for (const packageName of [
    "buffer",
    "events",
    "string_decoder",
    "@iarna/toml",
    "yaml",
    "base64-js",
    "ieee754",
    "safe-buffer",
  ]) {
    const folder = path.dirname(
      require.resolve(packageName + "/package.json", {
        paths: [
          root,
          fs.realpathSync(path.join(root, "node_modules/buffer")),
          fs.realpathSync(path.join(root, "node_modules/string_decoder")),
        ],
      }),
    );
    for (const name of fs
      .readdirSync(folder)
      .filter((name) => /^licen[sc]e|^notice/i.test(name)))
      if (fs.statSync(path.join(folder, name)).isFile())
        fs.copyFileSync(
          path.join(folder, name),
          path.join(notices, packageName.replace("/", "-") + "-" + name),
        );
  }
  fs.copyFileSync(
    path.join(repo, "LICENSE"),
    path.join(out, "dist/assets/LICENSE-QuotaView.txt"),
  );
  console.log("Built WebView2 application: no Electron or Node runtime.");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
