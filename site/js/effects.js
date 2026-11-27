// Page motion, with the Motion library (vendor/motion.min.js, MIT): the hero coming in, the watch
// tilting toward the pointer, and sections appearing as you scroll. Nothing here is needed to use
// the page: without Motion, or with reduced motion asked for, everything is simply shown as it is.

const Motion = window.Motion;
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const root = document.documentElement;

if (!Motion || reducedMotion) {
  root.classList.remove("motion"); // shows anything the stylesheet was keeping hidden for the entrance
} else {
  const { animate, inView, scroll, stagger } = Motion;
  const smooth = [0.22, 1, 0.36, 1];

  // ---- the hero comes in: text first, then the watch drops into place ----
  const text = animate("[data-enter]", { opacity: [0, 1], y: [28, 0] }, { duration: 0.8, ease: smooth, delay: stagger(0.08) });
  const tilt = document.getElementById("tilt");
  const drop = animate(tilt, { opacity: [0, 1], scale: [0.8, 1], rotate: [-14, 0], y: [40, 0] },
    { type: "spring", bounce: 0.35, duration: 1.2, delay: 0.3 });
  // Until then the stylesheet keeps them hidden (the "motion" class), so they don't flash in first.
  Promise.all([text, drop]).then(() => root.classList.remove("motion"));

  // ---- the watch leans toward the pointer, with a glare moving across the glass ----
  const watch = document.getElementById("watch");
  const area = document.getElementById("demo");
  const springy = { type: "spring", stiffness: 140, damping: 16 };
  if (matchMedia("(pointer: fine)").matches) {
    area.addEventListener("pointermove", (e) => {
      const box = watch.getBoundingClientRect();
      const x = (e.clientX - (box.left + box.width / 2)) / box.width;  // -0.5 .. 0.5 over the watch
      const y = (e.clientY - (box.top + box.height / 2)) / box.height;
      const clamp = (v) => Math.max(-1, Math.min(1, v));
      animate(tilt, { rotateY: clamp(x) * 12, rotateX: clamp(-y) * 12 }, springy);
      watch.style.setProperty("--glare-x", 50 + clamp(x) * 40 + "%");
      watch.style.setProperty("--glare-y", 50 + clamp(y) * 40 + "%");
    });
    area.addEventListener("pointerleave", () => {
      animate(tilt, { rotateY: 0, rotateX: 0 }, springy);
      watch.style.setProperty("--glare-x", "30%");
      watch.style.setProperty("--glare-y", "20%");
    });
  }

  // ---- as you scroll down, the watch drifts more slowly than the page ----
  const stage = document.getElementById("stage");
  scroll(animate(stage, { y: [0, 90] }, { ease: "linear" }),
    { target: document.querySelector(".hero"), offset: ["start start", "end start"] });

  // ---- sections appear as they come into view ----
  function reveal(selector, from, options) {
    document.querySelectorAll(selector).forEach((group) => {
      const items = group.matches("[data-reveal-each]") ? [...group.children] : [group];
      animate(items, from, { duration: 0 }); // hidden until seen
      inView(group, () => {
        animate(items, { opacity: 1, y: 0, x: 0, scale: 1 }, options);
      }, { amount: 0.25 });
    });
  }
  reveal(".band:not(.hero) h2", { opacity: 0, y: 30 }, { duration: 0.7, ease: smooth });
  reveal(".shots", { opacity: 0, y: 50, scale: 0.85 }, { type: "spring", bounce: 0.3, duration: 0.9, delay: stagger(0.08) });
  reveal(".points", { opacity: 0, y: 24 }, { duration: 0.6, ease: smooth, delay: stagger(0.07) });
  reveal("#guide h3, #guide table, #guide dl, #guide ol", { opacity: 0, x: -24 }, { duration: 0.6, ease: smooth });
  reveal("#faq details", { opacity: 0, y: 16 }, { duration: 0.5, ease: smooth });
}
