// Clip the native backdrop to the actual UI, including the transparent margins.
export function trackWindowRegion(view) {
  if (view === "settings" || !window.quotaView?.region) return () => {};
  let last = "",
    queued = 0;
  const update = () => {
    queued = 0;
    const el = document.querySelector(
      view === "capsule"
        ? ".standalone-capsule .quota-capsule"
        : ".island-shell",
    );
    if (!el) return;
    const r = el.getBoundingClientRect(),
      s = getComputedStyle(el);
    const value = {
      x: r.x,
      y: r.y,
      width: r.width,
      height: r.height,
      topRadius: parseFloat(s.borderTopLeftRadius) || 0,
      bottomRadius: parseFloat(s.borderBottomLeftRadius) || 0,
    };
    // A content measurement can arrive before the native window grows. Its
    // region is then clipped to the old bounds. Re-send after the WebView
    // viewport catches up, even when the element geometry is unchanged.
    const key = JSON.stringify([
      value,
      innerWidth,
      innerHeight,
      devicePixelRatio,
    ]);
    if (key === last) return;
    last = key;
    window.quotaView.region(value).catch(() => {
      last = "";
    });
  };
  const schedule = () => {
    if (!queued) queued = requestAnimationFrame(update);
  };
  const resize = new ResizeObserver(schedule),
    mutation = new MutationObserver(schedule);
  resize.observe(document.documentElement);
  mutation.observe(document.getElementById("root"), {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["class", "style"],
  });
  window.addEventListener("resize", schedule);
  document.addEventListener("transitionend", schedule);
  schedule();
  return () => {
    cancelAnimationFrame(queued);
    resize.disconnect();
    mutation.disconnect();
    window.removeEventListener("resize", schedule);
    document.removeEventListener("transitionend", schedule);
  };
}
