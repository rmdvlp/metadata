import type { ReactNode } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Card } from '@/components/ui/Card';
import { Banner } from '@/components/ui/Banner';
import { Avatar } from '@/components/ui/Avatar';
import { QuarantineBadge } from '@/components/ui/Badge';
import {
  ArrowLeftIcon,
  ClockIcon,
  FlagIcon,
  PersonIcon,
  PhoneIcon,
  RefreshIcon,
} from '@/components/icons';
import { cn } from '@/lib/cn';
import { useAsync } from '@/lib/useAsync';
import { formatLongDate, formatShortDate } from '@/lib/format';
import {
  fetchContact,
  fetchContactNotes,
  fetchContactTimeline,
  fetchUser,
} from '@/data/users';
import type { TimelineEntry } from '@/data/types';

export function ContactDetailPage() {
  const { uid = '', contactId = '' } = useParams();
  const navigate = useNavigate();

  const contact = useAsync(
    () => fetchContact(uid, contactId),
    [uid, contactId],
    'this contact',
  );
  const owner = useAsync(() => fetchUser(uid), [uid], 'the account holder');
  const timeline = useAsync(
    () => fetchContactTimeline(uid, contactId),
    [uid, contactId],
    "this contact's timeline",
  );
  const notes = useAsync(
    () => fetchContactNotes(uid, contactId),
    [uid, contactId],
    "this contact's notes",
  );

  const data = contact.data;
  const back = () => navigate(`/users/${uid}`);

  if (contact.error) {
    return (
      <div className="flex flex-col gap-4">
        <BackLink onClick={back} />
        <Banner tone="error">{contact.error}</Banner>
      </div>
    );
  }

  if (!contact.loading && !data) {
    return (
      <div className="flex flex-col gap-4">
        <BackLink onClick={back} />
        <Banner tone="warn">
          No contact exists at <code>users/{uid}/contacts/{contactId}</code>. It
          may have been deleted from the app.
        </Banner>
      </div>
    );
  }

  // The design's "Note:" panel holds one body of text. A contact carries its
  // own `notes` field and may also have a notes subcollection, so the newest
  // subcollection entry wins and the inline field is the fallback.
  const noteText = notes.data?.[0]?.text ?? data?.notes ?? data?.role ?? '';

  return (
    <div className="flex flex-col gap-5">
      <BackLink onClick={back} />

      <div className="grid grid-cols-1 items-start gap-5 lg:grid-cols-[minmax(0,340px)_minmax(0,1fr)]">
        <div className="flex flex-col gap-5">
          <Card className="px-5 pb-2 pt-6">
            <div className="flex justify-center">
              <div className="relative">
                <Avatar
                  name={data?.fullName ?? '?'}
                  src={data?.photoUrl}
                  size={126}
                  tone="neutral"
                />
                {/* The badge rides the photo only when the contact is actually
                    quarantined; an ordinary contact shows the plain portrait. */}
                {data?.isBlocked ? (
                  <span className="absolute -bottom-1.5 left-1/2 -translate-x-1/2">
                    <QuarantineBadge />
                  </span>
                ) : null}
              </div>
            </div>

            <dl className="mt-7">
              <InfoRow
                label="Name"
                icon={<PersonIcon size={17} />}
                value={data?.fullName}
                loading={contact.loading}
              />
              <InfoRow
                label="Phone Number"
                icon={<PhoneIcon size={17} />}
                value={data?.phoneNumber}
                loading={contact.loading}
              />
              <InfoRow
                label="Last Use Date"
                icon={<ClockIcon size={17} />}
                value={
                  data ? formatShortDate(data.updatedAt ?? data.createdAt) : undefined
                }
                loading={contact.loading}
              />
              <InfoRow
                label="Status"
                icon={<RefreshIcon size={17} />}
                value={data ? (data.isBlocked ? 'Quarantined' : 'Active') : undefined}
                valueClassName={data?.isBlocked ? 'text-state-bad' : undefined}
                loading={contact.loading}
              />
              <InfoRow
                label="Plan"
                icon={<FlagIcon size={17} />}
                value={owner.data ? (owner.data.plan === 'pro' ? 'Pro' : 'Free') : undefined}
                loading={owner.loading}
                last
              />
            </dl>
          </Card>

          <Card className="p-5">
            <p className="text-[13px] text-ink-secondary">Note:</p>
            <div className="mt-3 min-h-[112px] rounded-xl border border-line bg-white p-4">
              {notes.loading || contact.loading ? (
                <div className="h-4 w-2/3 animate-pulse rounded bg-line" />
              ) : noteText ? (
                <p className="whitespace-pre-wrap text-[13px] leading-relaxed text-ink">
                  {noteText}
                </p>
              ) : (
                <p className="text-[13px] text-ink-muted">
                  No note has been written for this contact.
                </p>
              )}
            </div>
            {notes.data && notes.data.length > 1 ? (
              <p className="mt-2 text-2xs text-ink-muted">
                Showing the most recent of {notes.data.length} notes.
              </p>
            ) : null}
          </Card>
        </div>

        <Card className="p-5">
          <h2 className="text-[15px] font-semibold text-ink">Timeline</h2>
          <div className="mt-4 border-t border-line pt-5">
            <Timeline
              entries={timeline.data ?? []}
              loading={timeline.loading}
              error={timeline.error}
            />
          </div>
        </Card>
      </div>
    </div>
  );
}

function Timeline({
  entries,
  loading,
  error,
}: {
  entries: TimelineEntry[];
  loading: boolean;
  error: string | null;
}) {
  if (loading) {
    return (
      <div className="flex flex-col gap-6">
        {[0, 1, 2].map((row) => (
          <div key={row} className="flex gap-4">
            <div className="mt-1 size-2.5 shrink-0 animate-pulse rounded-full bg-line" />
            <div className="flex-1 space-y-2">
              <div className="h-3 w-24 animate-pulse rounded bg-line" />
              <div className="h-4 w-48 animate-pulse rounded bg-line" />
              <div className="h-3 w-32 animate-pulse rounded bg-line" />
            </div>
          </div>
        ))}
      </div>
    );
  }

  if (error) return <Banner tone="error">{error}</Banner>;

  if (entries.length === 0) {
    return (
      <p className="py-6 text-center text-[13px] text-ink-muted">
        No timeline entries have been recorded for this contact.
      </p>
    );
  }

  return (
    <ol className="flex flex-col">
      {entries.map((entry, index) => (
        <li
          key={entry.id}
          className={cn(
            'relative flex gap-4 pl-5',
            // The dashed rail is a left border on every item but the last, so
            // the line stops at the final dot instead of running past it.
            index < entries.length - 1 &&
              'border-l border-dashed border-line-strong pb-6',
          )}
        >
          <span
            aria-hidden="true"
            className="absolute -left-[5px] top-1 size-2.5 rounded-full bg-brand-500 ring-4 ring-surface-panel"
          />
          <div className="min-w-0 flex-1">
            {entry.label ? (
              <p className="text-2xs font-semibold uppercase tracking-wide text-brand-500">
                {entry.label}
              </p>
            ) : null}
            <p className="mt-1 text-[15px] font-semibold text-ink">
              {entry.title || 'Untitled entry'}
            </p>
            {entry.subtitle ? (
              <p className="mt-0.5 text-[13px] text-ink-secondary">
                {entry.subtitle}
              </p>
            ) : null}
          </div>
          <p className="shrink-0 pt-0.5 text-[13px] text-ink-secondary">
            {formatLongDate(entry.date ?? entry.createdAt)}
          </p>
        </li>
      ))}
    </ol>
  );
}

function InfoRow({
  label,
  icon,
  value,
  valueClassName,
  loading,
  last = false,
}: {
  label: string;
  icon: ReactNode;
  value?: string;
  valueClassName?: string;
  loading: boolean;
  last?: boolean;
}) {
  return (
    <div
      className={cn(
        'flex items-center justify-between gap-4 py-4',
        !last && 'border-b border-line-strong',
      )}
    >
      <dt className="shrink-0 text-[13px] text-ink-secondary">{label}</dt>
      <dd className="flex min-w-0 items-center gap-2">
        <span className="shrink-0 text-brand-500">{icon}</span>
        {loading ? (
          <span className="h-4 w-24 animate-pulse rounded bg-line" />
        ) : (
          <span
            title={value}
            className={cn(
              'truncate text-[15px] font-medium text-ink',
              valueClassName,
            )}
          >
            {value || '—'}
          </span>
        )}
      </dd>
    </div>
  );
}

function BackLink({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex items-center gap-3 self-start text-[15px] font-medium text-brand-500"
    >
      <span className="inline-flex size-8 items-center justify-center rounded-full border border-line transition-colors hover:bg-brand-50">
        <ArrowLeftIcon size={16} />
      </span>
      Back to contacts
    </button>
  );
}
