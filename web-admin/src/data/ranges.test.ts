import { describe, expect, it } from 'vitest';
import { monthOverMonthWindows, rangeSpec } from './ranges';

// Thursday 3 September 2026, 14:30 local.
const NOW = new Date(2026, 8, 3, 14, 30);

describe('rangeSpec("week")', () => {
  const spec = rangeSpec('week', NOW);

  it('runs Sunday to Saturday, matching the design axis', () => {
    expect(spec.labels).toEqual(['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']);
    expect(spec.currentStart.getDay()).toBe(0);
    expect(spec.currentStart.getDate()).toBe(30); // Sun 30 Aug 2026
    expect(spec.previousStart.getDate()).toBe(23);
  });

  it('buckets a timestamp onto its weekday', () => {
    expect(spec.bucketOf(new Date(2026, 7, 30, 9, 0), 'current')).toBe(0);
    expect(spec.bucketOf(NOW, 'current')).toBe(4); // Thursday
    expect(spec.bucketOf(new Date(2026, 7, 24), 'previous')).toBe(1);
  });

  it('rejects a timestamp from the wrong period', () => {
    // Last week's Monday is not in this week's buckets.
    expect(spec.bucketOf(new Date(2026, 7, 24), 'current')).toBe(-1);
    expect(spec.bucketOf(NOW, 'previous')).toBe(-1);
  });
});

describe('rangeSpec("month")', () => {
  const spec = rangeSpec('month', NOW);

  it('has one bucket per day of the current month', () => {
    expect(spec.labels).toHaveLength(30); // September
    expect(spec.currentStart.getMonth()).toBe(8);
    expect(spec.previousStart.getMonth()).toBe(7);
  });

  it('folds a longer previous month into the last bucket rather than dropping it', () => {
    // August has 31 days; September's axis only has 30 buckets.
    expect(spec.bucketOf(new Date(2026, 7, 31), 'previous')).toBe(29);
    expect(spec.bucketOf(new Date(2026, 7, 15), 'previous')).toBe(14);
  });

  it('buckets by day-of-month in the current period', () => {
    expect(spec.bucketOf(new Date(2026, 8, 1), 'current')).toBe(0);
    expect(spec.bucketOf(NOW, 'current')).toBe(2);
    expect(spec.bucketOf(new Date(2026, 9, 1), 'current')).toBe(-1);
  });
});

describe('rangeSpec("year")', () => {
  const spec = rangeSpec('year', NOW);

  it('buckets by calendar month against the same months last year', () => {
    expect(spec.labels).toHaveLength(12);
    expect(spec.bucketOf(new Date(2026, 0, 9), 'current')).toBe(0);
    expect(spec.bucketOf(NOW, 'current')).toBe(8);
    expect(spec.bucketOf(new Date(2025, 8, 3), 'previous')).toBe(8);
    expect(spec.bucketOf(new Date(2025, 8, 3), 'current')).toBe(-1);
  });
});

describe('monthOverMonthWindows', () => {
  it('gives two adjacent 30-day windows ending today', () => {
    const { currentStart, previousStart } = monthOverMonthWindows(NOW);
    const days = (a: Date, b: Date) => Math.round((a.getTime() - b.getTime()) / 86_400_000);
    expect(days(currentStart, previousStart)).toBe(30);
    expect(days(new Date(2026, 8, 3), currentStart)).toBe(30);
    // Windows start at midnight so a tile's figure does not shift hour to hour.
    expect(currentStart.getHours()).toBe(0);
  });
});
