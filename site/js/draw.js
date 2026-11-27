// Drawing helpers for a 390 x 390 round watch screen, like the app's Draw module (source/Styles.mc).
// Angles are in degrees, counter-clockwise from 3 o'clock, as on the watch.

export const SIZE = 390, CX = 195, CY = 195;

export const COLOR = {
  focus: 0xFF5544, short: 0x44DD88, long: 0x44AAFF, goal: 0xFFB000,
  dim: 0x8A8A8A, white: 0xFFFFFF, light: 0xCCCCCC
};

// The fonts are declared with @font-face in index.html.
export const FONT = {
  xtiny: "25px NotoW", small: "31px NotoW", medium: "40px NotoW",
  row: "34px NotoW", rowSub: "26px NotoW",
  emberTimer: "84px EmberT", arc: "19px ArcW",
  drainTimer: "104px Bebas", drainLabel: "30px Bebas"
};

let ctx;
let capHeight = {}; // per font, to centre text on its capital letters
export function setContext(c) { ctx = c; capHeight = {}; }
export const context = () => ctx;
export function fontsChanged() { capHeight = {}; }

export const hex = (c) => "#" + c.toString(16).padStart(6, "0");
// Each channel times f (0..1): a darker shade.
export const shade = (c, f) =>
  (Math.floor(((c >> 16) & 255) * f) << 16) | (Math.floor(((c >> 8) & 255) * f) << 8) | Math.floor((c & 255) * f);

const rad = (deg) => deg * Math.PI / 180;
export const pointX = (r, deg) => CX + r * Math.cos(rad(deg));
export const pointY = (r, deg) => CY - r * Math.sin(rad(deg));

export function text(x, y, font, s, color, align = "center") {
  ctx.font = font;
  ctx.fillStyle = hex(color);
  ctx.textAlign = align;
  if (capHeight[font] === undefined) capHeight[font] = ctx.measureText("H").actualBoundingBoxAscent;
  ctx.fillText(s, x, y + capHeight[font] / 2);
}

export function textWidth(font, s) {
  ctx.font = font;
  return ctx.measureText(s).width;
}

// A clockwise arc of `sweep` degrees starting at `start`.
export function arc(r, start, sweep, pen, color) {
  if (sweep <= 0.3) return;
  ctx.beginPath();
  ctx.lineWidth = pen;
  ctx.strokeStyle = hex(color);
  if (sweep >= 359.9) ctx.arc(CX, CY, r, 0, Math.PI * 2);
  else ctx.arc(CX, CY, r, rad(-start), rad(-start + sweep));
  ctx.stroke();
}

export const ring = (r, pen, color) => arc(r, 90, 360, pen, color);

export function dot(x, y, r, color) {
  ctx.beginPath();
  ctx.fillStyle = hex(color);
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
}

export function circleOutline(x, y, r, pen, color) {
  ctx.beginPath();
  ctx.lineWidth = pen;
  ctx.strokeStyle = hex(color);
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.stroke();
}

// Text curved along the top of the circle (reading clockwise) or the bottom.
export function arcText(r, s, color, top) {
  ctx.font = FONT.arc;
  ctx.fillStyle = hex(color);
  ctx.textAlign = "center";
  const chars = [...s];
  const widths = chars.map((ch) => ctx.measureText(ch).width);
  const total = widths.reduce((a, b) => a + b, 0);
  let done = 0;
  chars.forEach((ch, i) => {
    const offset = (done + widths[i] / 2 - total / 2) / r;
    const angle = top ? -Math.PI / 2 + offset : Math.PI / 2 - offset;
    ctx.save();
    ctx.translate(CX + r * Math.cos(angle), CY + r * Math.sin(angle));
    ctx.rotate(top ? angle + Math.PI / 2 : angle - Math.PI / 2);
    ctx.fillText(ch, 0, 7);
    ctx.restore();
    done += widths[i];
  });
}

// Shortens `s` with `dots` until it fits in `width` pixels.
export function fit(font, s, width, dots = "…") {
  if (textWidth(font, s) <= width) return s;
  let n = s.length - 1;
  while (n > 1 && textWidth(font, s.slice(0, n) + dots) > width) n--;
  return s.slice(0, n) + dots;
}

// `s` on at most two lines of the given widths. Balanced when it fits; otherwise the second line
// ends with "…" (Draw.wrap in the app).
export function wrap(s, width1, width2, font = FONT.xtiny) {
  if (textWidth(font, s) <= width1) return [s];
  let greedy = 0, balanced = 0, best = 0;
  for (let i = 1; i < s.length - 1; i++) {
    if (s[i] !== " ") continue;
    const a = textWidth(font, s.slice(0, i)) / width1;
    if (a > 1) break;
    greedy = i;
    const b = textWidth(font, s.slice(i + 1)) / width2;
    const worst = Math.max(a, b);
    if (b <= 1 && (!balanced || worst < best)) { balanced = i; best = worst; }
  }
  const cut = balanced || greedy;
  return cut ? [s.slice(0, cut), fit(font, s.slice(cut + 1), width2)] : [fit(font, s, width1)];
}

// Width of the circle of radius r at height y, minus a margin.
export function chord(y, r) {
  const dy = Math.abs(y - CY);
  return dy < r ? 2 * Math.sqrt(r * r - dy * dy) - 12 : 0;
}
