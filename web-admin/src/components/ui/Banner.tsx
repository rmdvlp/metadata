import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { AlertIcon } from '../icons';

/** Inline notice for a rules rejection, a capped result set, or a write error. */
export function Banner({
  tone = 'warn',
  children,
  className,
}: {
  tone?: 'warn' | 'error' | 'info';
  children: ReactNode;
  className?: string;
}) {
  const tones = {
    warn: 'bg-state-warnSoft text-[#8a5200]',
    error: 'bg-state-badSoft text-[#9c2318]',
    info: 'bg-brand-50 text-brand-700',
  } as const;

  return (
    <div
      role={tone === 'error' ? 'alert' : 'status'}
      className={cn(
        'flex items-start gap-2 rounded-control px-3 py-2.5 text-xs',
        tones[tone],
        className,
      )}
    >
      <AlertIcon size={15} className="mt-px shrink-0" />
      <span className="min-w-0">{children}</span>
    </div>
  );
}
