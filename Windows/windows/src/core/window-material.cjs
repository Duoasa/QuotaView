"use strict";
// Window regions are in DIP, like Electron bounds and renderer CSS pixels.
function roundedRegion(input, bounds) {
  if (
    !input ||
    !["x", "y", "width", "height", "topRadius", "bottomRadius"].every((k) =>
      Number.isFinite(input[k]),
    )
  )
    throw Error("Invalid window region");
  const x = Math.max(0, Math.round(input.x)),
    y = Math.max(0, Math.round(input.y));
  const width = Math.min(Math.round(input.width), bounds.width - x),
    height = Math.min(Math.round(input.height), bounds.height - y);
  if (width < 1 || height < 1 || height > 4096)
    throw Error("Invalid window region size");
  const top = Math.max(0, Math.min(input.topRadius, width / 2, height / 2)),
    bottom = Math.max(0, Math.min(input.bottomRadius, width / 2, height / 2));
  const rows = [];
  for (let i = 0; i < height; i++) {
    const r = i < top ? top : i >= height - bottom ? bottom : 0;
    const dy =
      i < top
        ? top - i - 0.5
        : i >= height - bottom
          ? i + 0.5 - (height - bottom)
          : 0;
    const inset = r
      ? Math.ceil(r - Math.sqrt(Math.max(0, r * r - dy * dy)))
      : 0;
    if (width - 2 * inset > 0)
      rows.push({
        x: x + inset,
        y: y + i,
        width: width - 2 * inset,
        height: 1,
      });
  }
  return rows;
}
function materialFor({
  platform,
  release,
  enabled,
  transparency = true,
  highContrast = false,
  regionReady = false,
  settings = false,
}) {
  return platform === "win32" &&
    Number(String(release).split(".")[2]) >= 22621 &&
    enabled &&
    transparency &&
    !highContrast &&
    (settings || regionReady)
    ? settings
      ? "mica"
      : "acrylic"
    : "none";
}
module.exports = { roundedRegion, materialFor };
