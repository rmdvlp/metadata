import { describe, expect, it } from 'vitest';
import { monotonePath, niceTicks, type Pt } from './curve';

/** Samples the cubic segments of a path so we can assert what it draws. */
function pathYRange(path: string): { min: number; max: number } {
  const numbers = [...path.matchAll(/-?\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));
  // Coordinates alternate x, y from the leading "M x y" onwards.
  const ys = numbers.filter((_, index) => index % 2 === 1);
  return { min: Math.min(...ys), max: Math.max(...ys) };
}

describe('monotonePath', () => {
  it('handles degenerate inputs', () => {
    expect(monotonePath([])).toBe('');
    expect(monotonePath([{ x: 1, y: 2 }])).toBe('M 1 2');
    expect(monotonePath([{ x: 0, y: 0 }, { x: 1, y: 1 }])).toBe('M 0 0 L 1 1');
  });

  it('never overshoots past the data, which is the whole point of monotone', () => {
    // A spike: a Catmull-Rom spline dips below the baseline on either side of
    // this, drawing negative counts the data never had.
    const points: Pt[] = [
      { x: 0, y: 100 },
      { x: 10, y: 100 },
      { x: 20, y: 0 },
      { x: 30, y: 100 },
      { x: 40, y: 100 },
    ];

    const { min, max } = pathYRange(monotonePath(points));
    expect(min).toBeGreaterThanOrEqual(0);
    expect(max).toBeLessThanOrEqual(100);
  });

  it('flattens the tangent at a turning point', () => {
    const path = monotonePath([
      { x: 0, y: 10 },
      { x: 10, y: 0 },
      { x: 20, y: 10 },
    ]);
    // The control points either side of the peak share its y value when the
    // tangent there is zero.
    expect(path).toContain('C');
    const { min } = pathYRange(path);
    expect(min).toBe(0);
  });

  it('emits one cubic segment per gap', () => {
    const path = monotonePath([
      { x: 0, y: 1 },
      { x: 1, y: 2 },
      { x: 2, y: 3 },
      { x: 3, y: 4 },
    ]);
    expect(path.match(/C/g)).toHaveLength(3);
  });
});

describe('niceTicks', () => {
  it('starts at zero and covers the peak', () => {
    for (const peak of [1, 3, 7, 42, 153, 1999, 87_431]) {
      const ticks = niceTicks(peak);
      expect(ticks[0]).toBe(0);
      expect(ticks[ticks.length - 1]).toBeGreaterThanOrEqual(peak);
      expect(ticks.length).toBeGreaterThanOrEqual(2);
    }
  });

  it('uses an even step throughout', () => {
    const ticks = niceTicks(153);
    const steps = ticks.slice(1).map((tick, i) => tick - ticks[i]);
    for (const step of steps) expect(step).toBeCloseTo(steps[0], 6);
  });

  it('degrades safely on an empty series', () => {
    expect(niceTicks(0)).toEqual([0, 1, 2]);
    expect(niceTicks(Number.NaN)).toEqual([0, 1, 2]);
  });

  it('never labels a fraction of a countable thing', () => {
    // A quiet week floors the peak at 1, which used to yield 0/0.25/0.5/0.75/1.
    for (const peak of [1, 2, 3, 4]) {
      for (const tick of niceTicks(peak)) {
        expect(Number.isInteger(tick)).toBe(true);
      }
    }
  });
});
