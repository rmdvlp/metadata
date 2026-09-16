/** "21 Apr" — the Last-Use-date column format. */
export function formatShortDate(date: Date | null | undefined): string {
  if (!date) return '—';
  return new Intl.DateTimeFormat('en-GB', {
    day: '2-digit',
    month: 'short',
  }).format(date);
}

/** "02:03 PM" — the Time column format. */
export function formatTime(date: Date | null | undefined): string {
  if (!date) return '—';
  return new Intl.DateTimeFormat('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  }).format(date);
}

/** "May 14, 2026" — the date against a timeline entry. */
export function formatLongDate(date: Date | null | undefined): string {
  if (!date) return '—';
  return new Intl.DateTimeFormat('en-US', {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  }).format(date);
}

/** "2026-07-20" — the date shown against a support ticket. */
export function formatIsoDate(date: Date | null | undefined): string {
  if (!date) return '—';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/**
 * The support tiles show two-digit counts ("03", "02") while the dashboard
 * tiles show plain ones ("234"). `pad` opts into the former.
 */
export function formatCount(value: number, pad = false): string {
  if (!Number.isFinite(value)) return '—';
  if (pad && value < 10) return `0${value}`;
  return new Intl.NumberFormat('en-US').format(value);
}

/** "JS" for the avatar fallbacks and the message-thread bubbles. */
export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

/**
 * Short human-readable handle for a document, shown in the Ticket column.
 * Firestore ids are 20 random chars, which is unreadable in a table — the
 * last four, upper-cased, is enough for an operator to match a row against a
 * console lookup.
 */
export function shortRef(id: string, prefix = '#'): string {
  if (!id) return `${prefix}----`;
  return prefix + id.slice(-4).toUpperCase();
}

/** Percentage change, rounded, guarding the divide-by-zero baseline. */
export function percentChange(current: number, previous: number): number | null {
  if (!Number.isFinite(current) || !Number.isFinite(previous)) return null;
  if (previous === 0) return current === 0 ? 0 : null;
  return Math.round(((current - previous) / previous) * 100);
}

/** "12%" / "03%" — deltas are two-digit padded in the design. */
export function formatDelta(value: number): string {
  const abs = Math.abs(value);
  return `${abs < 10 ? `0${abs}` : abs}%`;
}
