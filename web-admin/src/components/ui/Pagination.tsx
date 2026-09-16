import { cn } from '@/lib/cn';
import { ChevronLeftIcon, ChevronRightIcon } from '../icons';

/**
 * Builds the page list from the design: first page, a window around the
 * current one, the last page, with a single ellipsis on either side.
 * `-1` marks an ellipsis slot.
 */
export function pageItems(current: number, total: number): number[] {
  if (total <= 7) {
    return Array.from({ length: total }, (_, i) => i + 1);
  }

  const items = new Set<number>([1, total, current]);
  if (current - 1 > 1) items.add(current - 1);
  if (current + 1 < total) items.add(current + 1);
  // Keep three leading numbers when we are at the start, as the design shows.
  if (current <= 3) {
    items.add(2);
    items.add(3);
  }
  if (current >= total - 2) {
    items.add(total - 1);
    items.add(total - 2);
  }

  const sorted = [...items].filter((p) => p >= 1 && p <= total).sort((a, b) => a - b);
  const withGaps: number[] = [];
  sorted.forEach((page, index) => {
    if (index > 0) {
      const skipped = page - sorted[index - 1] - 1;
      // An ellipsis standing in for a single page is worse than the page
      // itself: same width, one fewer destination.
      if (skipped === 1) withGaps.push(page - 1);
      else if (skipped > 1) withGaps.push(-1);
    }
    withGaps.push(page);
  });
  return withGaps;
}

export function Pagination({
  page,
  pageCount,
  onChange,
  className,
}: {
  page: number;
  pageCount: number;
  onChange: (page: number) => void;
  className?: string;
}) {
  if (pageCount <= 1) return null;

  const items = pageItems(page, pageCount);

  return (
    <nav
      aria-label="Pagination"
      className={cn('flex items-center justify-center gap-1.5', className)}
    >
      <PagerButton
        label="Previous page"
        disabled={page <= 1}
        onClick={() => onChange(page - 1)}
      >
        <ChevronLeftIcon size={16} />
      </PagerButton>

      {items.map((item, index) =>
        item === -1 ? (
          <span
            key={`gap-${index}`}
            aria-hidden="true"
            className="px-1 text-xs text-ink-muted"
          >
            •••
          </span>
        ) : (
          <button
            key={item}
            type="button"
            onClick={() => onChange(item)}
            aria-current={item === page ? 'page' : undefined}
            aria-label={`Page ${item}`}
            className={cn(
              'inline-flex size-7 items-center justify-center rounded-full text-xs font-medium transition-colors',
              item === page
                ? 'bg-brand-500 text-white'
                : 'text-ink-secondary hover:bg-surface-panel hover:text-ink',
            )}
          >
            {item}
          </button>
        ),
      )}

      <PagerButton
        label="Next page"
        disabled={page >= pageCount}
        onClick={() => onChange(page + 1)}
      >
        <ChevronRightIcon size={16} />
      </PagerButton>
    </nav>
  );
}

function PagerButton({
  label,
  disabled,
  onClick,
  children,
}: {
  label: string;
  disabled: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        'inline-flex size-7 items-center justify-center rounded-full border border-line text-ink-secondary transition-colors',
        disabled
          ? 'cursor-not-allowed opacity-40'
          : 'hover:border-brand-200 hover:bg-brand-50 hover:text-brand-500',
      )}
    >
      {children}
    </button>
  );
}
