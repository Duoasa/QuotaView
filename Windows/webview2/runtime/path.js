import { call } from "./bridge.js";
export const sep = "\\",
  delimiter = ";";
export const join = (...a) => call("path", "join", a),
  resolve = (...a) => call("path", "resolve", a),
  dirname = (p) => call("path", "dirname", [p]),
  basename = (p, suffix) => {
    let n = call("path", "basename", [p]);
    return suffix && n.endsWith(suffix) ? n.slice(0, -suffix.length) : n;
  },
  extname = (p) => call("path", "extname", [p]),
  normalize = (p) => call("path", "normalize", [p]),
  relative = (a, b) => call("path", "relative", [a, b]),
  isAbsolute = (p) => /^(?:[a-z]:[\\/]|\\\\|\/)/i.test(p);
export const parse = (p) => ({
  root: call("path", "root", [p]),
  dir: dirname(p),
  base: basename(p),
  ext: extname(p),
  name: basename(p, extname(p)),
});
const api = {
  sep,
  delimiter,
  join,
  resolve,
  dirname,
  basename,
  extname,
  normalize,
  relative,
  isAbsolute,
  parse,
};
api.win32 = api;
export const win32 = api;
export default api;
