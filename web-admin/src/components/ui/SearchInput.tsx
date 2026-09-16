import { useEffect, useState } from 'react';
import { cn } from '@/lib/cn';
import { RefreshIcon, SearchIcon } from '../icons';
import { Spinner } from './Spinner';

/**
 * The pill search box from the design. Typing is debounced so each keystroke
 * does not fire a Firestore scan; the trailing control doubles as the
 * in-flight indicator and, once idle, as a reset.
 */
export function SearchInput({
  value,
  onChange,
  placeholder,
  busy = false,
  className,
  debounceMs = 300,
  'aria-label': ariaLabel,
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
  busy?: boolean;
  className?: string;
  debounceMs?: number;
  'aria-label'?: string;
}) {
  const [draft, setDraft] = useState(value);

  // Keep in step when the owner resets the term (tab switch, cleared filter).
  useEffect(() => setDraft(value), [value]);

  useEffect(() => {
    if (draft === value) return;
    const timer = setTimeout(() => onChange(draft), debounceMs);
    return () => clearTimeout(timer);
  }, [draft, value, onChange, debounceMs]);

  return (
    <div
      className={cn(
        'flex h-9 items-center gap-2 rounded-full border border-line bg-surface-panel px-4',
        'transition-colors focus-within:border-brand-200 focus-within:bg-white',
        className,
      )}
    >
      <input
        type="search"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        placeholder={placeholder}
        aria-label={ariaLabel ?? placeholder}
        className="min-w-0 flex-1 bg-transparent text-[13px] text-ink outline-none placeholder:text-ink-muted [&::-webkit-search-cancel-button]:hidden"
      />
      {busy ? (
        <Spinner size={15} className="shrink-0 text-brand-500" />
      ) : draft ? (
        <button
          type="button"
          onClick={() => setDraft('')}
          aria-label="Clear search"
          className="shrink-0 rounded-full p-0.5 text-ink-muted transition-colors hover:text-ink"
        >
          <RefreshIcon size={15} />
        </button>
      ) : (
        <SearchIcon size={16} className="shrink-0 text-ink-muted" />
      )}
    </div>
  );
}
