export interface Pt {
  x: number;
  y: number;
}

/**
 * Monotone cubic Hermite (Fritsch–Carlson) path through the points.
 *
 * The design draws a soft curve, but a plain Catmull-Rom spline overshoots
 * between a low and a high sample — on a count series that renders dips below
 * zero and invented peaks the data never had. A monotone fit keeps the visual
 * smoothness while guaranteeing the curve stays inside its neighbouring
 * samples.
 */
export function monotonePath(points: Pt[]): string {
  if (points.length === 0) return '';
  if (points.length === 1) return `M ${points[0].x} ${points[0].y}`;
  if (points.length === 2) {
    return `M ${points[0].x} ${points[0].y} L ${points[1].x} ${points[1].y}`;
  }

  const n = points.length;
  const dx: number[] = [];
  const slope: number[] = [];

  for (let i = 0; i < n - 1; i += 1) {
    const h = points[i + 1].x - points[i].x;
    dx.push(h);
    slope.push(h === 0 ? 0 : (points[i + 1].y - points[i].y) / h);
  }

  // Tangents: one-sided at the ends, weighted-harmonic inside, forced flat
  // wherever the data turns — that flat tangent is what kills the overshoot.
  const tangents: number[] = new Array(n).fill(0);
  tangents[0] = slope[0];
  tangents[n - 1] = slope[n - 2];

  for (let i = 1; i < n - 1; i += 1) {
    const previous = slope[i - 1];
    const next = slope[i];
    if (previous * next <= 0) {
      tangents[i] = 0;
    } else {
      const w1 = 2 * dx[i] + dx[i - 1];
      const w2 = dx[i] + 2 * dx[i - 1];
      tangents[i] = (w1 + w2) / (w1 / previous + w2 / next);
    }
  }

  let path = `M ${points[0].x} ${points[0].y}`;
  for (let i = 0; i < n - 1; i += 1) {
    const h = dx[i] / 3;
    const c1x = points[i].x + h;
    const c1y = points[i].y + tangents[i] * h;
    const c2x = points[i + 1].x - h;
    const c2y = points[i + 1].y - tangents[i + 1] * h;
    path += ` C ${c1x} ${c1y}, ${c2x} ${c2y}, ${points[i + 1].x} ${points[i + 1].y}`;
  }
  return path;
}

/** Rounded "nice" axis ticks covering [0, max], always at least two steps. */
export function niceTicks(max: number, count = 4): number[] {
  if (!Number.isFinite(max) || max <= 0) return [0, 1, 2];

  const rawStep = max / count;
  const magnitude = 10 ** Math.floor(Math.log10(rawStep));
  // This axis counts things, so a fractional gridline reads as "0.25
  // encounters" — nonsense. Never step below one whole unit, which is what a
  // quiet period (peak of 1) would otherwise produce.
  const step = Math.max(
    1,
    [1, 2, 2.5, 5, 10].map((m) => m * magnitude).find((s) => s >= rawStep) ??
      10 * magnitude,
  );

  // Round the ceiling up to a whole step so the top gridline always sits at
  // or above the peak — otherwise the curve is drawn off the top of the plot.
  const top = Math.ceil(max / step) * step;
  const ticks: number[] = [];
  for (let value = 0; value <= top + step / 1000; value += step) {
    ticks.push(Math.round(value * 100) / 100);
  }
  return ticks.length >= 2 ? ticks : [0, step];
}
