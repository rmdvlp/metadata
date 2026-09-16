import { useEffect, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { cn } from '@/lib/cn';
import { CloseIcon } from '../icons';

/**
 * Centred dialog used throughout the console. Portaled to `document.body`
 * rather than rendered where it's called from, for the same reason the
 * dropdown `Popover` is: `position: fixed` centers on the nearest ancestor
 * that establishes a containing block — normally the viewport, but a
 * `transform`, `filter`, or `backdrop-filter` anywhere in the ancestor chain
 * silently changes that. `TopNav`'s header uses `backdrop-blur`
 * (`backdrop-filter`) for its frosted-glass look, so "My Profile" — mounted
 * inside that header — used to center itself on the header's own 56px bar
 * instead of the screen, landing mostly above the visible page on every
 * route. Portaling sidesteps the whole class of bug: wherever a `<Modal>` is
 * mounted, it always centers on the real viewport.
 */
export function Modal({
  open,
  onClose,
  title,
  description,
  children,
  footer,
  className,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  children?: ReactNode;
  footer?: ReactNode;
  className?: string;
}) {
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKeyDown);

    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    panelRef.current?.focus();

    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = previous;
    };
  }, [open, onClose]);

  if (!open) return null;

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-ink/25 p-4 sm:items-center"
      onClick={onClose}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        onClick={(event) => event.stopPropagation()}
        className={cn(
          'w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-pop outline-none',
          className,
        )}
      >
        <div className="flex items-start justify-between gap-4 px-5 pb-3 pt-5">
          <div>
            <h2 className="text-[15px] font-semibold text-ink">{title}</h2>
            {description ? (
              <p className="mt-1 text-xs text-ink-secondary">{description}</p>
            ) : null}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="-mr-1 shrink-0 rounded-full p-1 text-ink-secondary transition-colors hover:bg-surface-panel hover:text-ink"
          >
            <CloseIcon size={16} />
          </button>
        </div>

        {children ? <div className="px-5 pb-4">{children}</div> : null}

        {footer ? (
          <div className="flex justify-end gap-2 border-t border-line bg-surface-panel/60 px-5 py-3.5">
            {footer}
          </div>
        ) : null}
      </div>
    </div>,
    document.body,
  );
}
