import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

export interface Column<T> {
  key: string;
  header: ReactNode;
  cell: (row: T) => ReactNode;
  /** Extra classes on both the header cell and the body cells. */
  className?: string;
  /** Hide this column below the given breakpoint to protect the layout. */
  hideBelow?: 'sm' | 'md' | 'lg' | 'xl';
  align?: 'left' | 'right' | 'center';
}

const HIDE_BELOW: Record<NonNullable<Column<unknown>['hideBelow']>, string> = {
  sm: 'hidden sm:table-cell',
  md: 'hidden md:table-cell',
  lg: 'hidden lg:table-cell',
  xl: 'hidden xl:table-cell',
};

const ALIGN = {
  left: 'text-left',
  right: 'text-right',
  center: 'text-center',
} as const;

/**
 * The design's table, made responsive in two stages: columns drop out at
 * their breakpoints, and below `md` the whole thing becomes the stacked card
 * list supplied by `mobileCard` (an eight-column table cannot be squeezed
 * into a phone, and a lone horizontal scrollbar hides half the data).
 */
export function DataTable<T>({
  columns,
  rows,
  keyOf,
  loading = false,
  error,
  empty = 'Nothing to show yet.',
  onRowClick,
  mobileCard,
  skeletonRows = 6,
}: {
  columns: Array<Column<T>>;
  rows: T[];
  keyOf: (row: T) => string;
  loading?: boolean;
  error?: string | null;
  empty?: ReactNode;
  onRowClick?: (row: T) => void;
  mobileCard?: (row: T) => ReactNode;
  skeletonRows?: number;
}) {
  if (error) {
    return (
      <div className="px-5 py-10 text-center text-[13px] text-state-bad">{error}</div>
    );
  }

  if (!loading && rows.length === 0) {
    return (
      <div className="px-5 py-12 text-center text-[13px] text-ink-secondary">
        {empty}
      </div>
    );
  }

  return (
    <>
      {mobileCard ? (
        <div className="divide-y divide-line md:hidden">
          {loading
            ? Array.from({ length: skeletonRows }, (_, i) => (
                <div key={i} className="p-4">
                  <div className="h-4 w-1/2 animate-pulse rounded bg-line" />
                  <div className="mt-2 h-3 w-2/3 animate-pulse rounded bg-line" />
                </div>
              ))
            : rows.map((row) => (
                <div
                  key={keyOf(row)}
                  className={cn(
                    'p-4',
                    onRowClick && 'cursor-pointer active:bg-surface-hover',
                  )}
                  onClick={onRowClick ? () => onRowClick(row) : undefined}
                >
                  {mobileCard(row)}
                </div>
              ))}
        </div>
      ) : null}

      <div
        className={cn(
          'scroll-slim overflow-x-auto',
          mobileCard ? 'hidden md:block' : 'block',
        )}
      >
        <table className="w-full min-w-[720px] border-collapse text-left">
          <thead>
            <tr className="bg-surface-header">
              {columns.map((col) => (
                <th
                  key={col.key}
                  scope="col"
                  className={cn(
                    'whitespace-nowrap px-4 py-3 text-xs font-semibold text-ink',
                    ALIGN[col.align ?? 'left'],
                    col.hideBelow && HIDE_BELOW[col.hideBelow],
                    col.className,
                  )}
                >
                  {col.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading
              ? Array.from({ length: skeletonRows }, (_, i) => (
                  <tr key={i} className="border-b border-line last:border-0">
                    {columns.map((col) => (
                      <td
                        key={col.key}
                        className={cn(
                          'px-4 py-3.5',
                          col.hideBelow && HIDE_BELOW[col.hideBelow],
                        )}
                      >
                        <div className="h-3 animate-pulse rounded bg-line" />
                      </td>
                    ))}
                  </tr>
                ))
              : rows.map((row) => (
                  <tr
                    key={keyOf(row)}
                    onClick={onRowClick ? () => onRowClick(row) : undefined}
                    className={cn(
                      'border-b border-line transition-colors last:border-0',
                      onRowClick
                        ? 'cursor-pointer hover:bg-surface-hover'
                        : 'hover:bg-surface-hover/60',
                    )}
                  >
                    {columns.map((col) => (
                      <td
                        key={col.key}
                        className={cn(
                          'px-4 py-3.5 text-[13px] text-ink-secondary',
                          ALIGN[col.align ?? 'left'],
                          col.hideBelow && HIDE_BELOW[col.hideBelow],
                          col.className,
                        )}
                      >
                        {col.cell(row)}
                      </td>
                    ))}
                  </tr>
                ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

/** Muted em dash for a field the mobile app has not written. */
export function Blank() {
  return <span className="text-ink-muted">—</span>;
}

/** Truncating cell — long notes and addresses must not widen the table. */
export function Truncate({
  children,
  title,
  className,
}: {
  children: ReactNode;
  title?: string;
  className?: string;
}) {
  return (
    <span className={cn('block max-w-[240px] truncate', className)} title={title}>
      {children}
    </span>
  );
}
