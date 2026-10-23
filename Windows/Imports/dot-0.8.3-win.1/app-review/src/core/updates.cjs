"use strict";
const REPOSITORY = "Duoasa/quotaview-windows";
const RELEASE_PAGE = `https://github.com/${REPOSITORY}/releases`;
function windowsVersion(value) {
  const m = String(value).match(/^v?(\d+)\.(\d+)\.(\d+)-win\.(\d+)$/);
  return m ? m.slice(1).map(Number) : null;
}
function compareVersions(a, b) {
  const x = windowsVersion(a),
    y = windowsVersion(b);
  if (!x || !y) return null;
  for (let i = 0; i < x.length; i++)
    if (x[i] !== y[i]) return x[i] > y[i] ? 1 : -1;
  return 0;
}
function selectRelease(rows, current) {
  if (!Array.isArray(rows)) throw Error("Unexpected release response");
  const valid = rows
    .filter(
      (r) =>
        r &&
        !r.draft &&
        windowsVersion(r.tag_name) &&
        typeof r.html_url === "string" &&
        r.html_url === RELEASE_PAGE + "/tag/" + r.tag_name,
    )
    .sort((a, b) => compareVersions(b.tag_name, a.tag_name));
  if (!valid.length)
    return {
      checking: false,
      available: false,
      url: RELEASE_PAGE,
      message: "No Windows preview release has been published yet.",
    };
  const r = valid[0];
  return {
    checking: false,
    available: compareVersions(r.tag_name, current) === 1,
    version: r.tag_name.replace(/^v/, ""),
    url: r.html_url,
    publishedAt: r.published_at,
    prerelease: !!r.prerelease,
  };
}
module.exports = {
  REPOSITORY,
  RELEASE_PAGE,
  windowsVersion,
  compareVersions,
  selectRelease,
};
