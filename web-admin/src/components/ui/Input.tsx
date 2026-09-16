import { forwardRef, type InputHTMLAttributes, type ReactNode } from 'react';
import { cn } from '@/lib/cn';

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  /** Rendered inside the field, flush right — the mail and eye affordances. */
  adornment?: ReactNode;
  error?: string;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { label, adornment, error, className, id, ...rest },
  ref,
) {
  const inputId = id ?? rest.name;

  return (
    <div className="w-full">
      {label ? (
        <label
          htmlFor={inputId}
          className="mb-1.5 block text-xs font-medium text-ink"
        >
          {label}
        </label>
      ) : null}
      <div
        className={cn(
          'flex h-12 items-center gap-2 rounded-control border bg-white px-4 transition-colors',
          'focus-within:border-brand-500',
          error ? 'border-state-bad' : 'border-line-strong',
        )}
      >
        <input
          ref={ref}
          id={inputId}
          aria-invalid={error ? true : undefined}
          className={cn(
            'min-w-0 flex-1 bg-transparent text-[13px] text-ink outline-none',
            'placeholder:text-ink-muted',
            className,
          )}
          {...rest}
        />
        {adornment}
      </div>
      {error ? (
        <p role="alert" className="mt-1.5 text-xs text-state-bad">
          {error}
        </p>
      ) : null}
    </div>
  );
});
