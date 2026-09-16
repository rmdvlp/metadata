import {
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from 'react';
import { createPortal } from 'react-dom';
import { cn } from '@/lib/cn';
import { ChevronDownIcon, FilterIcon, MoreIcon } from '../icons';

/**
 * Closes the popover on an outside pointer press or Escape. `extraRef` is the
 * portaled panel (see `Popover` below) — once the panel lives outside
 * `ref`'s subtree in the DOM, a click on one of its own menu items would
 * otherwise register as "outside" and close the menu before the item's own
 * `onClick` runs.
 */
function useDismiss(
  open: boolean,
  close: () => void,
  extraRef?: RefObject<HTMLElement | null>,
) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;

    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as Node;
      if (ref.current?.contains(target) || extraRef?.current?.contains(target)) return;
      close();
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close();
    };

    document.addEventListener('pointerdown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [open, close, extraRef]);

  return ref;
}

/**
 * Every dropdown in the app — Select, ActionMenu, FilterButton — goes through
 * this one component, so it is portaled to `document.body` and positioned in
 * viewport coordinates rather than rendered as a normal `absolute` child.
 * Positioning it in-place would put it inside whatever the caller happens to
 * be inside; `Modal`'s panel is `overflow-hidden` (needed for its rounded
 * corners), which silently clipped every dropdown opened from inside one —
 * the first place that surfaced was the Administration screen's two Role
 * selects, but `EditUserModal`'s plan select had the identical bug already.
 */
export function Popover({
  trigger,
  children,
  align = 'right',
  className,
  panelClassName,
}: {
  trigger: (props: { open: boolean; toggle: () => void; id: string }) => ReactNode;
  children: (props: { close: () => void }) => ReactNode;
  align?: 'left' | 'right';
  className?: string;
  panelClassName?: string;
}) {
  const [open, setOpen] = useState(false);
  const id = useId();
  const panelRef = useRef<HTMLDivElement>(null);
  const ref = useDismiss(open, () => setOpen(false), panelRef);
  const [pos, setPos] = useState<{ top: number; left?: number; right?: number } | null>(
    null,
  );

  // Recomputed on open and kept in sync while open, since the portal escapes
  // the normal flow that would otherwise move it along with the page.
  useLayoutEffect(() => {
    if (!open) return;

    const update = () => {
      const rect = ref.current?.getBoundingClientRect();
      if (!rect) return;
      setPos(
        align === 'right'
          ? { top: rect.bottom + 6, right: window.innerWidth - rect.right }
          : { top: rect.bottom + 6, left: rect.left },
      );
    };

    update();
    window.addEventListener('scroll', update, true);
    window.addEventListener('resize', update);
    return () => {
      window.removeEventListener('scroll', update, true);
      window.removeEventListener('resize', update);
    };
  }, [open, align, ref]);

  return (
    <div ref={ref} className={cn('relative', className)}>
      {trigger({ open, toggle: () => setOpen((v) => !v), id })}
      {open && pos
        ? createPortal(
            <div
              ref={panelRef}
              id={id}
              role="menu"
              style={{ position: 'fixed', top: pos.top, left: pos.left, right: pos.right }}
              className={cn(
                // z-[60] clears Modal's z-50 backdrop, so a dropdown opened
                // from inside a modal still renders above it.
                'z-[60] min-w-[160px] overflow-hidden rounded-xl border border-line bg-white py-1 shadow-pop',
                panelClassName,
              )}
            >
              {children({ close: () => setOpen(false) })}
            </div>,
            document.body,
          )
        : null}
    </div>
  );
}

export function MenuItem({
  children,
  onClick,
  tone = 'default',
  disabled = false,
}: {
  children: ReactNode;
  onClick: () => void;
  tone?: 'default' | 'danger';
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      onClick={onClick}
      className={cn(
        'flex w-full items-center gap-2 px-3 py-2 text-left text-[13px] transition-colors',
        disabled && 'cursor-not-allowed opacity-50',
        tone === 'danger'
          ? 'text-state-bad hover:bg-state-badSoft'
          : 'text-ink hover:bg-surface-panel',
      )}
    >
      {children}
    </button>
  );
}

export interface SelectOption<T extends string> {
  value: T;
  label: string;
}

/** The "This Week" style selector: a bordered pill that opens a short list. */
export function Select<T extends string>({
  value,
  options,
  onChange,
  className,
  leading,
  'aria-label': ariaLabel,
}: {
  value: T;
  options: Array<SelectOption<T>>;
  onChange: (value: T) => void;
  className?: string;
  leading?: ReactNode;
  'aria-label'?: string;
}) {
  const active = options.find((option) => option.value === value);

  return (
    <Popover
      trigger={({ open, toggle, id }) => (
        <button
          type="button"
          onClick={toggle}
          aria-haspopup="menu"
          aria-expanded={open}
          aria-controls={id}
          aria-label={ariaLabel}
          className={cn(
            'inline-flex h-8 items-center gap-2 rounded-control border border-line bg-white px-3 text-xs font-medium text-ink transition-colors hover:border-line-strong',
            className,
          )}
        >
          {leading}
          <span className="truncate">{active?.label ?? value}</span>
          <ChevronDownIcon
            size={14}
            className={cn(
              'shrink-0 text-ink-secondary transition-transform',
              open && 'rotate-180',
            )}
          />
        </button>
      )}
    >
      {({ close }) =>
        options.map((option) => (
          <MenuItem
            key={option.value}
            onClick={() => {
              onChange(option.value);
              close();
            }}
          >
            <span
              className={cn(
                'size-1.5 rounded-full',
                option.value === value ? 'bg-brand-500' : 'bg-transparent',
              )}
            />
            {option.label}
          </MenuItem>
        ))
      }
    </Popover>
  );
}

/** The three-dot Action cell in every table. */
export function ActionMenu({
  items,
}: {
  items: Array<{
    label: string;
    onClick: () => void;
    tone?: 'default' | 'danger';
    disabled?: boolean;
  }>;
}) {
  return (
    <Popover
      className="flex justify-end"
      trigger={({ open, toggle, id }) => (
        <button
          type="button"
          onClick={(event) => {
            // Rows are clickable; opening the menu must not also navigate.
            event.stopPropagation();
            toggle();
          }}
          aria-haspopup="menu"
          aria-expanded={open}
          aria-controls={id}
          aria-label="Row actions"
          className={cn(
            'inline-flex size-7 items-center justify-center rounded-full text-ink-secondary transition-colors hover:bg-surface-panel hover:text-ink',
            open && 'bg-surface-panel text-ink',
          )}
        >
          <MoreIcon size={16} />
        </button>
      )}
    >
      {({ close }) => (
        <div onClick={(event) => event.stopPropagation()}>
          {items.map((item) => (
            <MenuItem
              key={item.label}
              tone={item.tone}
              disabled={item.disabled}
              onClick={() => {
                item.onClick();
                close();
              }}
            >
              {item.label}
            </MenuItem>
          ))}
        </div>
      )}
    </Popover>
  );
}

export interface FilterGroup<T extends string> {
  id: string;
  label: string;
  value: T;
  options: Array<SelectOption<T>>;
  onChange: (value: T) => void;
}

/**
 * The outlined "Filter" button. It shows a dot when any group is off its
 * default so an operator can tell at a glance that the list is narrowed.
 */
export function FilterButton({
  groups,
  active,
  onReset,
}: {
  // Heterogeneous groups (plan, blocked, source…) are erased to string here;
  // each group keeps its own typed onChange at the call site.
  groups: Array<FilterGroup<string>>;
  active: boolean;
  onReset: () => void;
}) {
  return (
    <Popover
      trigger={({ open, toggle, id }) => (
        <button
          type="button"
          onClick={toggle}
          aria-haspopup="menu"
          aria-expanded={open}
          aria-controls={id}
          className={cn(
            'inline-flex h-9 items-center gap-2 rounded-control border px-3.5 text-[13px] font-medium transition-colors',
            active || open
              ? 'border-brand-500 bg-brand-50 text-brand-500'
              : 'border-brand-200 bg-white text-brand-500 hover:bg-brand-50',
          )}
        >
          <FilterIcon size={15} />
          Filter
          {active ? <span className="size-1.5 rounded-full bg-brand-500" /> : null}
        </button>
      )}
      panelClassName="min-w-[210px] p-1"
    >
      {() => (
        <div>
          {groups.map((group) => (
            <div key={group.id} className="px-2 py-1.5">
              <p className="px-1 pb-1 text-2xs font-semibold uppercase tracking-wide text-ink-muted">
                {group.label}
              </p>
              {group.options.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => group.onChange(option.value)}
                  className={cn(
                    'flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-[13px] transition-colors',
                    option.value === group.value
                      ? 'bg-brand-50 font-medium text-brand-600'
                      : 'text-ink hover:bg-surface-panel',
                  )}
                >
                  <span
                    className={cn(
                      'size-1.5 rounded-full',
                      option.value === group.value ? 'bg-brand-500' : 'bg-line-strong',
                    )}
                  />
                  {option.label}
                </button>
              ))}
            </div>
          ))}
          {active ? (
            <div className="border-t border-line px-2 pb-1 pt-1.5">
              <button
                type="button"
                onClick={onReset}
                className="w-full rounded-lg px-2 py-1.5 text-left text-xs font-medium text-ink-secondary transition-colors hover:bg-surface-panel hover:text-ink"
              >
                Clear filters
              </button>
            </div>
          ) : null}
        </div>
      )}
    </Popover>
  );
}
