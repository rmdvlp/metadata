import { describe, expect, it } from 'vitest';
import { pageItems } from './Pagination';

describe('pageItems', () => {
  it('lists every page when they all fit', () => {
    expect(pageItems(1, 1)).toEqual([1]);
    expect(pageItems(3, 7)).toEqual([1, 2, 3, 4, 5, 6, 7]);
  });

  it('matches the design at the start: 1 2 3 … 100', () => {
    expect(pageItems(2, 100)).toEqual([1, 2, 3, -1, 100]);
  });

  it('windows around the middle with a gap on both sides', () => {
    expect(pageItems(50, 100)).toEqual([1, -1, 49, 50, 51, -1, 100]);
  });

  it('windows at the end without a trailing gap', () => {
    expect(pageItems(100, 100)).toEqual([1, -1, 98, 99, 100]);
  });

  it('never emits an out-of-range or duplicate page', () => {
    for (const total of [8, 20, 100]) {
      for (let page = 1; page <= total; page += 1) {
        const items = pageItems(page, total).filter((p) => p !== -1);
        expect(items).toEqual([...new Set(items)].sort((a, b) => a - b));
        expect(Math.min(...items)).toBeGreaterThanOrEqual(1);
        expect(Math.max(...items)).toBeLessThanOrEqual(total);
        expect(items).toContain(page);
      }
    }
  });

  it('never puts an ellipsis where a single page would do', () => {
    const items = pageItems(4, 100);
    const gapIndex = items.indexOf(-1);
    expect(items[gapIndex + 1] - items[gapIndex - 1]).toBeGreaterThan(2);
  });
});
