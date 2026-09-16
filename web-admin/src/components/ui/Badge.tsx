import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { CrownIcon } from '../icons';
import type { TicketStatus } from '@/data/types';

/** The blue "Pro" pill beside a paid user's name. */
export function ProBadge({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center gap-0.5 rounded-full bg-brand-500 px-1.5 py-[2px] text-2xs font-semibold text-white',
        className,
      )}
    >
      <CrownIcon size={10} strokeWidth={2} />
      Pro
    </span>
  );
}

/**
 * The "Quarantine" pill beside a blocked contact's name — a pale red fill
 * rather than an outline, matching the design. `title` carries the meaning for
 * anyone who does not read the colour as a warning.
 */
export function QuarantineBadge() {
  return (
    <span
      title="Blocked by the account holder"
      className="inline-flex shrink-0 items-center rounded bg-state-badSoft px-1.5 py-[2px] text-2xs font-medium leading-4 text-state-bad"
    >
      Quarantine
    </span>
  );
}

const TICKET_TONES: Record<TicketStatus, { dot: string; text: string; bg: string; label: string }> = {
  pending: {
    dot: 'bg-state-warn',
    text: 'text-state-warn',
    bg: 'bg-state-warnSoft',
    label: 'Pending',
  },
  waiting: {
    dot: 'bg-brand-500',
    text: 'text-brand-500',
    bg: 'bg-brand-50',
    label: 'Waiting',
  },
  completed: {
    dot: 'bg-state-good',
    text: 'text-state-good',
    bg: 'bg-state-goodSoft',
    label: 'Completed',
  },
};

/**
 * Ticket state. A coloured dot alone would carry the meaning in colour only,
 * so the label always ships with it.
 */
export function StatusPill({
  status,
  className,
}: {
  status: TicketStatus;
  className?: string;
}) {
  const tone = TICKET_TONES[status];
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center gap-1.5 rounded-full px-2 py-[3px] text-2xs font-medium',
        tone.bg,
        tone.text,
        className,
      )}
    >
      <span className={cn('size-1.5 rounded-full', tone.dot)} />
      {tone.label}
    </span>
  );
}

export function ticketStatusLabel(status: TicketStatus): string {
  return TICKET_TONES[status].label;
}

export function ticketStatusDot(status: TicketStatus): string {
  return TICKET_TONES[status].dot;
}

/** Green/grey "Active" marker on the user-detail header. */
export function ActivityPill({ active }: { active: boolean }) {
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center gap-1.5 text-xs font-medium',
        active ? 'text-brand-500' : 'text-ink-muted',
      )}
    >
      <span
        className={cn(
          'size-1.5 rounded-full',
          active ? 'bg-brand-500' : 'bg-ink-muted',
        )}
      />
      {active ? 'Active' : 'Inactive'}
    </span>
  );
}

export function Chip({
  children,
  tone = 'neutral',
}: {
  children: ReactNode;
  tone?: 'neutral' | 'brand';
}) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-[3px] text-2xs font-medium',
        tone === 'brand'
          ? 'bg-brand-100 text-brand-600'
          : 'bg-surface-panel text-ink-secondary',
      )}
    >
      {children}
    </span>
  );
}
