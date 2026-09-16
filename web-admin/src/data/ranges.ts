import type { ChartRange } from './types';

const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_LABELS = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

export interface RangeSpec {
  /** Bucket labels along the x axis, in order. */
  labels: string[];
  /** Inclusive start of the current period. */
  currentStart: Date;
  /** Inclusive start of the period before it — also the query's lower bound. */
  previousStart: Date;
  /** Bucket index for a timestamp, or -1 when it falls outside the period. */
  bucketOf: (date: Date, period: 'current' | 'previous') => number;
}

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/** Most recent Sunday at 00:00, matching the design's Sun→Sat axis. */
function startOfWeek(d: Date): Date {
  const day = startOfDay(d);
  day.setDate(day.getDate() - day.getDay());
  return day;
}

function addDays(d: Date, days: number): Date {
  const next = new Date(d);
  next.setDate(next.getDate() + days);
  return next;
}

function daysInMonth(year: number, month: number): number {
  return new Date(year, month + 1, 0).getDate();
}

export function rangeSpec(range: ChartRange, now = new Date()): RangeSpec {
  if (range === 'week') {
    const currentStart = startOfWeek(now);
    const previousStart = addDays(currentStart, -7);
    return {
      labels: DAY_LABELS,
      currentStart,
      previousStart,
      bucketOf: (date, period) => {
        const base = period === 'current' ? currentStart : previousStart;
        const diff = Math.floor(
          (startOfDay(date).getTime() - base.getTime()) / 86_400_000,
        );
        return diff >= 0 && diff < 7 ? diff : -1;
      },
    };
  }

  if (range === 'month') {
    const currentStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const previousStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const span = daysInMonth(now.getFullYear(), now.getMonth());
    return {
      labels: Array.from({ length: span }, (_, i) => String(i + 1)),
      currentStart,
      previousStart,
      bucketOf: (date, period) => {
        const base = period === 'current' ? currentStart : previousStart;
        if (
          date.getFullYear() !== base.getFullYear() ||
          date.getMonth() !== base.getMonth()
        ) {
          return -1;
        }
        // The previous month may be longer than the current one; those extra
        // days fold into the last bucket rather than being dropped.
        return Math.min(date.getDate() - 1, span - 1);
      },
    };
  }

  const currentStart = new Date(now.getFullYear(), 0, 1);
  const previousStart = new Date(now.getFullYear() - 1, 0, 1);
  return {
    labels: MONTH_LABELS,
    currentStart,
    previousStart,
    bucketOf: (date, period) => {
      const year =
        period === 'current' ? currentStart.getFullYear() : previousStart.getFullYear();
      return date.getFullYear() === year ? date.getMonth() : -1;
    },
  };
}

/** The two 30-day windows the "last month" deltas on the stat tiles compare. */
export function monthOverMonthWindows(now = new Date()) {
  const currentStart = addDays(startOfDay(now), -30);
  return { currentStart, previousStart: addDays(currentStart, -30) };
}

export const RANGE_LABELS: Record<ChartRange, string> = {
  week: 'This Week',
  month: 'This Month',
  year: 'This Year',
};
