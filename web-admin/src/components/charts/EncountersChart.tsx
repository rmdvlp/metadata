import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { cn } from '@/lib/cn';
import { monotonePath, niceTicks, type Pt } from './curve';
import type { ChartPoint } from '@/data/types';

const PAD = { top: 14, right: 12, bottom: 26, left: 34 };
const MIN_HEIGHT = 170;

/**
 * Encounters per bucket, current period against the one before it.
 *
 * Two series, so identity never rests on colour alone: the legend is always
 * present, the tooltip names each line, and a table view carries the same
 * numbers for anyone the chart does not serve.
 */
export function EncountersChart({
  points,
  loading = false,
  previousLabel,
  currentLabel = 'This period',
}: {
  points: ChartPoint[];
  loading?: boolean;
  previousLabel: string;
  currentLabel?: string;
}) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(560);
  const [height, setHeight] = useState(210);
  const [hover, setHover] = useState<number | null>(null);
  const [showTable, setShowTable] = useState(false);

  useEffect(() => {
    const element = wrapRef.current;
    if (!element) return;

    const observer = new ResizeObserver(([entry]) => {
      const w = entry.contentRect.width;
      setWidth(w);
      // Shorter on a phone, taller on a wide card — keeps the curve readable
      // without letting it become a band across the screen.
      setHeight(Math.max(MIN_HEIGHT, Math.min(240, Math.round(w * 0.42))));
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const geometry = useMemo(() => {
    const innerW = Math.max(1, width - PAD.left - PAD.right);
    const innerH = Math.max(1, height - PAD.top - PAD.bottom);
    const peak = Math.max(
      1,
      ...points.map((p) => Math.max(p.current, p.previous)),
    );
    const ticks = niceTicks(peak);
    const top = ticks[ticks.length - 1] || 1;

    const xAt = (index: number) =>
      PAD.left +
      (points.length <= 1 ? innerW / 2 : (innerW * index) / (points.length - 1));
    const yAt = (value: number) => PAD.top + innerH - (value / top) * innerH;

    const current: Pt[] = points.map((p, i) => ({ x: xAt(i), y: yAt(p.current) }));
    const previous: Pt[] = points.map((p, i) => ({ x: xAt(i), y: yAt(p.previous) }));
    const baseline = PAD.top + innerH;

    const line = monotonePath(current);
    const area =
      current.length > 0
        ? `${line} L ${current[current.length - 1].x} ${baseline} L ${current[0].x} ${baseline} Z`
        : '';

    return {
      innerW,
      innerH,
      ticks,
      top,
      xAt,
      yAt,
      current,
      previous,
      baseline,
      line,
      area,
      previousLine: monotonePath(previous),
    };
  }, [points, width, height]);

  /** Nearest bucket to the pointer — a wider hit area than the 8px dot. */
  const pick = useCallback(
    (clientX: number) => {
      const box = wrapRef.current?.getBoundingClientRect();
      if (!box || points.length === 0) return;

      const x = clientX - box.left;
      let best = 0;
      let bestDistance = Infinity;
      points.forEach((_, index) => {
        const distance = Math.abs(geometry.xAt(index) - x);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = index;
        }
      });
      setHover(best);
    },
    [geometry, points],
  );

  const onKeyDown = (event: React.KeyboardEvent) => {
    if (points.length === 0) return;
    if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
      event.preventDefault();
      const step = event.key === 'ArrowRight' ? 1 : -1;
      setHover((prev) => {
        const next = (prev ?? 0) + step;
        return Math.max(0, Math.min(points.length - 1, next));
      });
    }
    if (event.key === 'Escape') setHover(null);
  };

  const total = points.reduce((sum, p) => sum + p.current, 0);
  const active = hover !== null ? points[hover] : null;

  if (loading) {
    return (
      <div className="mt-3 h-[210px] animate-pulse rounded-xl bg-white/70" />
    );
  }

  return (
    <div className="mt-2">
      <Legend previousLabel={previousLabel} currentLabel={currentLabel} />

      <div ref={wrapRef} className="relative mt-1 w-full select-none">
        <svg
          width={width}
          height={height}
          role="img"
          tabIndex={0}
          aria-label={`Encounters by ${points.length} buckets. ${total} in ${currentLabel.toLowerCase()}, compared with ${previousLabel.toLowerCase()}. Use arrow keys to read each value.`}
          onMouseMove={(event) => pick(event.clientX)}
          onMouseLeave={() => setHover(null)}
          onTouchStart={(event) => pick(event.touches[0].clientX)}
          onTouchMove={(event) => pick(event.touches[0].clientX)}
          onKeyDown={onKeyDown}
          onBlur={() => setHover(null)}
          className="block rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-brand-500/40"
        >
          <defs>
            <linearGradient id="encounter-fill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#0A6CFF" stopOpacity="0.20" />
              <stop offset="100%" stopColor="#0A6CFF" stopOpacity="0" />
            </linearGradient>
          </defs>

          {/* Recessive grid: hairlines behind the data, never competing. */}
          {geometry.ticks.map((tick) => {
            const y = geometry.yAt(tick);
            return (
              <g key={tick}>
                <line
                  x1={PAD.left}
                  x2={width - PAD.right}
                  y1={y}
                  y2={y}
                  stroke="#EDF0F3"
                  strokeWidth={1}
                />
                <text
                  x={PAD.left - 8}
                  y={y + 3}
                  textAnchor="end"
                  className="fill-ink-muted text-[9px]"
                >
                  {compact(tick)}
                </text>
              </g>
            );
          })}

          <path d={geometry.area} fill="url(#encounter-fill)" />

          {/* Comparison period: dashed and grey so it reads as background. */}
          <path
            d={geometry.previousLine}
            fill="none"
            stroke="#C6CED6"
            strokeWidth={2}
            strokeDasharray="4 4"
            strokeLinecap="round"
          />

          <path
            d={geometry.line}
            fill="none"
            stroke="#0A6CFF"
            strokeWidth={2}
            strokeLinecap="round"
          />

          {hover !== null ? (
            <g>
              <line
                x1={geometry.xAt(hover)}
                x2={geometry.xAt(hover)}
                y1={PAD.top}
                y2={geometry.baseline}
                stroke="#C6CED6"
                strokeWidth={1}
                strokeDasharray="3 3"
              />
              <circle
                cx={geometry.xAt(hover)}
                cy={geometry.yAt(points[hover].previous)}
                r={4}
                fill="#fff"
                stroke="#C6CED6"
                strokeWidth={2}
              />
              <circle
                cx={geometry.xAt(hover)}
                cy={geometry.yAt(points[hover].current)}
                r={5}
                fill="#fff"
                stroke="#0A6CFF"
                strokeWidth={2.5}
              />
            </g>
          ) : null}

          {points.map((point, index) => (
            <text
              key={point.label}
              x={geometry.xAt(index)}
              y={height - 8}
              textAnchor="middle"
              className={cn(
                'text-[9px]',
                hover === index ? 'fill-ink font-semibold' : 'fill-ink-muted',
              )}
            >
              {/* A month's 31 labels will not fit — show every fifth. */}
              {points.length > 14 && index % 5 !== 0 && index !== points.length - 1
                ? ''
                : point.label}
            </text>
          ))}
        </svg>

        {active && hover !== null ? (
          <div
            role="status"
            className="pointer-events-none absolute z-10 -translate-x-1/2 -translate-y-full rounded-lg border border-line bg-white px-2.5 py-1.5 shadow-pop"
            style={{
              left: clamp(geometry.xAt(hover), 60, Math.max(60, width - 60)),
              top: Math.max(30, geometry.yAt(active.current) - 10),
            }}
          >
            <p className="text-2xs font-medium text-ink-secondary">{active.label}</p>
            <p className="flex items-center gap-1.5 text-xs font-semibold text-ink">
              <span className="size-1.5 rounded-full bg-brand-500" />
              {active.current}
            </p>
            <p className="flex items-center gap-1.5 text-2xs text-ink-secondary">
              <span className="size-1.5 rounded-full bg-[#C6CED6]" />
              {active.previous}
            </p>
          </div>
        ) : null}
      </div>

      {/* A flat line along the baseline is a real answer — say so, so it is
          not mistaken for a chart that failed to draw. */}
      {total === 0 && points.reduce((sum, p) => sum + p.previous, 0) === 0 ? (
        <p className="mt-1 text-2xs text-ink-muted">
          No encounters recorded in this period.
        </p>
      ) : null}

      <button
        type="button"
        onClick={() => setShowTable((v) => !v)}
        aria-expanded={showTable}
        className="mt-1 text-2xs font-medium text-ink-secondary underline decoration-line-strong underline-offset-2 transition-colors hover:text-ink"
      >
        {showTable ? 'Hide data' : 'View as table'}
      </button>

      {showTable ? (
        <div className="scroll-slim mt-2 max-h-40 overflow-auto rounded-lg border border-line">
          <table className="w-full text-left text-2xs">
            <thead className="sticky top-0 bg-surface-header">
              <tr>
                <th scope="col" className="px-2.5 py-1.5 font-semibold text-ink">
                  Bucket
                </th>
                <th scope="col" className="px-2.5 py-1.5 font-semibold text-ink">
                  {currentLabel}
                </th>
                <th scope="col" className="px-2.5 py-1.5 font-semibold text-ink">
                  {previousLabel}
                </th>
              </tr>
            </thead>
            <tbody>
              {points.map((point) => (
                <tr key={point.label} className="border-t border-line">
                  <td className="px-2.5 py-1 text-ink">{point.label}</td>
                  <td className="px-2.5 py-1 text-ink-secondary">{point.current}</td>
                  <td className="px-2.5 py-1 text-ink-secondary">{point.previous}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}

function Legend({
  currentLabel,
  previousLabel,
}: {
  currentLabel: string;
  previousLabel: string;
}) {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-2xs text-ink-secondary">
      <span className="inline-flex items-center gap-1.5">
        <span className="h-0.5 w-3.5 rounded-full bg-brand-500" />
        {currentLabel}
      </span>
      <span className="inline-flex items-center gap-1.5">
        <span
          className="h-0.5 w-3.5 rounded-full"
          style={{
            backgroundImage:
              'repeating-linear-gradient(to right, #C6CED6 0 4px, transparent 4px 7px)',
          }}
        />
        {previousLabel}
      </span>
    </div>
  );
}

function compact(value: number): string {
  if (value >= 1000) return `${Math.round(value / 100) / 10}k`;
  return String(value);
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
