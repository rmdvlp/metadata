import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { ArrowDownIcon, ArrowUpIcon } from '../icons';
import { formatCount, formatDelta } from '@/lib/format';
import type { StatDelta } from '@/data/types';

/**
 * A stat tile is a hero number, not a chart — the label names it, the figure
 * carries it, and the delta gives it direction. The arrow is paired with a
 * sign-bearing word so the trend never rests on green-vs-red alone.
 */
export function StatCard({
  label,
  value,
  icon,
  delta,
  loading = false,
  padValue = false,
  tone = 'panel',
  footnote,
}: {
  label: string;
  value: number | null;
  icon: ReactNode;
  delta?: StatDelta;
  loading?: boolean;
  padValue?: boolean;
  tone?: 'panel' | 'bordered';
  footnote?: string;
}) {
  return (
    <div
      className={cn(
        'flex flex-col justify-between rounded-card p-4',
        tone === 'panel'
          ? 'bg-surface-panel'
          : 'border border-line bg-white shadow-card',
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-medium text-ink-secondary">{label}</p>
        <span className="shrink-0 text-brand-500">{icon}</span>
      </div>

      {loading ? (
        <div className="mt-3 h-8 w-20 animate-pulse rounded bg-line" />
      ) : (
        <p className="mt-2 text-[26px] font-bold leading-none tracking-tight text-ink">
          {value === null ? '—' : formatCount(value, padValue)}
        </p>
      )}

      {delta && !loading ? <DeltaLine delta={delta} /> : null}
      {footnote && !loading ? (
        <p className="mt-2 text-2xs text-ink-muted">{footnote}</p>
      ) : null}
    </div>
  );
}

function DeltaLine({ delta }: { delta: StatDelta }) {
  if (delta.percent === null) {
    return <p className="mt-2 text-2xs text-ink-muted">no prior month to compare</p>;
  }

  const up = delta.direction === 'up';
  const flat = delta.direction === 'flat';

  return (
    <p className="mt-2 flex items-center gap-1 text-2xs">
      {flat ? null : (
        <span className={up ? 'text-state-good' : 'text-state-bad'}>
          {up ? <ArrowUpIcon size={13} /> : <ArrowDownIcon size={13} />}
        </span>
      )}
      <span
        className={cn(
          'font-semibold',
          flat ? 'text-ink-secondary' : up ? 'text-state-good' : 'text-state-bad',
        )}
      >
        {flat ? 'No change' : formatDelta(delta.percent)}
      </span>
      <span className="text-ink-secondary">last month</span>
    </p>
  );
}
