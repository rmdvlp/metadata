import { useEffect, useMemo, useRef, useState } from 'react';
import { Panel } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Banner } from '@/components/ui/Banner';
import { StatCard } from '@/components/ui/StatCard';
import { SearchInput } from '@/components/ui/SearchInput';
import { Select } from '@/components/ui/Menu';
import { Avatar } from '@/components/ui/Avatar';
import { StatusPill, ticketStatusDot, ticketStatusLabel } from '@/components/ui/Badge';
import {
  ArrowLeftIcon,
  CheckCircleIcon,
  HourglassIcon,
  InboxIcon,
  SendIcon,
} from '@/components/icons';
import { cn } from '@/lib/cn';
import { useAuth } from '@/lib/auth';
import { useAsync } from '@/lib/useAsync';
import { firestoreErrorMessage } from '@/lib/firestoreError';
import { formatIsoDate, formatTime, initials, shortRef } from '@/lib/format';
import {
  fetchSupportStats,
  sendTicketReply,
  setTicketStatus,
  watchTicketMessages,
  watchTickets,
} from '@/data/tickets';
import type { SupportTicket, TicketMessage, TicketStatus } from '@/data/types';

type Tab = 'all' | TicketStatus;

const TABS: Array<{ value: Tab; label: string }> = [
  { value: 'all', label: 'All' },
  { value: 'pending', label: 'Pending' },
  { value: 'waiting', label: 'Waiting' },
  { value: 'completed', label: 'Completed' },
];

/** Human ticket reference: the app's own number if it wrote one, else TK-XXXX. */
function ticketRef(ticket: SupportTicket): string {
  return ticket.ticketNo ?? shortRef(ticket.id, 'TK-');
}

export function SupportPage() {
  const { admin } = useAuth();

  const [tickets, setTickets] = useState<SupportTicket[] | null>(null);
  const [ticketsError, setTicketsError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('all');
  const [search, setSearch] = useState('');
  const [threadOpenOnMobile, setThreadOpenOnMobile] = useState(false);

  const stats = useAsync(() => fetchSupportStats(), [], 'the support totals');

  // Live inbox: a ticket submitted from the app appears without a refresh.
  useEffect(() => {
    return watchTickets(
      (next) => {
        setTickets(next);
        setTicketsError(null);
      },
      (error) => setTicketsError(firestoreErrorMessage(error, 'support tickets')),
    );
  }, []);

  const visible = useMemo(() => {
    const term = search.trim().toLowerCase();
    return (tickets ?? []).filter((ticket) => {
      if (tab !== 'all' && ticket.status !== tab) return false;
      if (!term) return true;
      return [ticket.subject, ticket.name, ticket.email, ticketRef(ticket)].some(
        (field) => field.toLowerCase().includes(term),
      );
    });
  }, [tickets, tab, search]);

  // Keep a selection at all times so the right pane is never blank on desktop,
  // and drop one that a filter has just hidden.
  useEffect(() => {
    if (visible.length === 0) {
      setSelectedId(null);
      return;
    }
    if (!selectedId || !visible.some((ticket) => ticket.id === selectedId)) {
      setSelectedId(visible[0].id);
    }
  }, [visible, selectedId]);

  const selected = visible.find((ticket) => ticket.id === selectedId) ?? null;
  const pendingCount = (tickets ?? []).filter((t) => t.status === 'pending').length;

  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-lg font-bold text-ink">Support Center Inbox</h1>
        <p className="mt-0.5 text-xs text-ink-secondary">
          Manage, review and resolve queries submitted by users through the
          Context ID application interface.
        </p>
      </div>

      {stats.error ? <Banner tone="error">{stats.error}</Banner> : null}

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          tone="bordered"
          label="Today Submissions"
          value={stats.data?.todaySubmissions ?? null}
          loading={stats.loading}
          icon={<InboxIcon size={18} />}
        />
        <StatCard
          tone="bordered"
          label="Pending Tickets"
          value={stats.data?.pending ?? null}
          loading={stats.loading}
          padValue
          icon={<HourglassIcon size={18} className="text-state-warn" />}
        />
        <StatCard
          tone="bordered"
          label="Waiting"
          value={stats.data?.waiting ?? null}
          loading={stats.loading}
          padValue
          icon={<CheckCircleIcon size={18} />}
        />
        <StatCard
          tone="bordered"
          label="Completed / Resolved"
          value={stats.data?.completed ?? null}
          loading={stats.loading}
          icon={<CheckCircleIcon size={18} className="text-state-good" />}
        />
      </div>

      {ticketsError ? <Banner tone="error">{ticketsError}</Banner> : null}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[340px_minmax(0,1fr)] xl:grid-cols-[380px_minmax(0,1fr)]">
        <Panel
          className={cn(
            'flex flex-col',
            // On a phone the two panes share the viewport, so only one shows.
            threadOpenOnMobile ? 'hidden lg:flex' : 'flex',
          )}
        >
          <div className="flex items-center justify-between gap-3 px-4 pb-3 pt-4">
            <h2 className="text-[14px] font-semibold text-ink">Tickets Directory</h2>
            <span className="shrink-0 text-2xs text-ink-secondary">
              {pendingCount} {pendingCount === 1 ? 'Ticket' : 'Tickets'} Pending
            </span>
          </div>

          <div className="px-4 pb-3">
            <SearchInput
              value={search}
              onChange={setSearch}
              placeholder="Search subject or sender..."
              className="w-full"
            />
          </div>

          <div
            role="tablist"
            aria-label="Filter tickets by status"
            className="flex gap-1.5 px-4 pb-3"
          >
            {TABS.map((item) => (
              <button
                key={item.value}
                type="button"
                role="tab"
                aria-selected={tab === item.value}
                onClick={() => setTab(item.value)}
                className={cn(
                  'h-7 shrink-0 rounded-control px-3 text-xs font-medium transition-colors',
                  tab === item.value
                    ? 'bg-brand-500 text-white'
                    : 'text-ink-secondary hover:bg-surface-panel hover:text-ink',
                )}
              >
                {item.label}
              </button>
            ))}
          </div>

          <div className="scroll-slim max-h-[520px] flex-1 overflow-y-auto border-t border-line">
            {tickets === null ? (
              <div className="divide-y divide-line">
                {Array.from({ length: 5 }, (_, i) => (
                  <div key={i} className="p-4">
                    <div className="h-3 w-24 animate-pulse rounded bg-line" />
                    <div className="mt-2 h-3.5 w-2/3 animate-pulse rounded bg-line" />
                  </div>
                ))}
              </div>
            ) : visible.length === 0 ? (
              <p className="px-4 py-12 text-center text-[13px] text-ink-secondary">
                {search || tab !== 'all'
                  ? 'No tickets match this filter.'
                  : 'No tickets have been submitted yet.'}
              </p>
            ) : (
              <ul className="divide-y divide-line">
                {visible.map((ticket) => (
                  <li key={ticket.id}>
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedId(ticket.id);
                        setThreadOpenOnMobile(true);
                      }}
                      aria-current={ticket.id === selectedId ? 'true' : undefined}
                      className={cn(
                        'w-full px-4 py-3 text-left transition-colors',
                        ticket.id === selectedId
                          ? 'bg-brand-50'
                          : 'hover:bg-surface-hover',
                      )}
                    >
                      <div className="flex items-center gap-2">
                        <span className="text-2xs font-medium text-ink-secondary">
                          {ticketRef(ticket)}
                        </span>
                        <StatusPill status={ticket.status} />
                        <span className="ml-auto shrink-0 text-2xs text-ink-muted">
                          {formatIsoDate(ticket.createdAt)}
                        </span>
                      </div>
                      <p className="mt-1.5 truncate text-[13px] font-medium text-ink">
                        {ticket.subject}
                      </p>
                      <div className="mt-0.5 flex items-baseline gap-2">
                        <span className="truncate text-2xs text-ink-secondary">
                          {ticket.name}
                        </span>
                        <span className="ml-auto shrink-0 truncate text-2xs text-ink-muted">
                          {ticket.email}
                        </span>
                      </div>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </Panel>

        <Panel
          className={cn(
            'flex min-h-[480px] flex-col',
            threadOpenOnMobile ? 'flex' : 'hidden lg:flex',
          )}
        >
          {selected ? (
            <TicketThread
              key={selected.id}
              ticket={selected}
              adminName={admin?.name ?? 'Admin'}
              adminEmail={admin?.email ?? ''}
              onBack={() => setThreadOpenOnMobile(false)}
            />
          ) : (
            <p className="m-auto px-6 text-center text-[13px] text-ink-secondary">
              Select a ticket to read the conversation.
            </p>
          )}
        </Panel>
      </div>
    </div>
  );
}

function TicketThread({
  ticket,
  adminName,
  adminEmail,
  onBack,
}: {
  ticket: SupportTicket;
  adminName: string;
  adminEmail: string;
  onBack: () => void;
}) {
  const [messages, setMessages] = useState<TicketMessage[] | null>(null);
  const [threadError, setThreadError] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [status, setStatus] = useState<TicketStatus>(ticket.status);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => setStatus(ticket.status), [ticket.status]);

  useEffect(() => {
    return watchTicketMessages(
      ticket.id,
      (next) => {
        setMessages(next);
        setThreadError(null);
      },
      (error) => setThreadError(firestoreErrorMessage(error, 'this conversation')),
    );
  }, [ticket.id]);

  // Keep the newest reply in view as the thread grows.
  useEffect(() => {
    const element = scrollRef.current;
    if (element) element.scrollTop = element.scrollHeight;
  }, [messages]);

  /**
   * The ticket document holds the user's original message, and the `messages`
   * subcollection holds everything after it. Prepending it here means the
   * thread reads in order without the mobile app having to change how it
   * submits.
   */
  const thread: TicketMessage[] = [
    {
      id: '__original__',
      from: 'user',
      authorName: ticket.name,
      authorEmail: ticket.email,
      text: ticket.message,
      createdAt: ticket.createdAt,
    },
    ...(messages ?? []),
  ];

  const send = async () => {
    const text = draft.trim();
    if (!text) return;

    setSending(true);
    setActionError(null);
    try {
      await sendTicketReply({
        ticketId: ticket.id,
        text,
        authorName: adminName,
        authorEmail: adminEmail,
      });
      setDraft('');
      // A replied-to ticket is no longer unworked — it is waiting on the user.
      if (status === 'pending') {
        await setTicketStatus(ticket.id, 'waiting');
        setStatus('waiting');
      }
    } catch (error) {
      setActionError(firestoreErrorMessage(error, 'this reply'));
    } finally {
      setSending(false);
    }
  };

  const changeStatus = async (next: TicketStatus) => {
    const previous = status;
    setStatus(next);
    setActionError(null);
    try {
      await setTicketStatus(ticket.id, next);
    } catch (error) {
      setStatus(previous);
      setActionError(firestoreErrorMessage(error, 'this ticket'));
    }
  };

  return (
    <>
      <div className="flex items-center gap-2.5 border-b border-line px-4 py-3.5">
        <button
          type="button"
          onClick={onBack}
          aria-label="Back to tickets"
          className="-ml-1 shrink-0 rounded-full p-1 text-ink-secondary transition-colors hover:bg-surface-panel lg:hidden"
        >
          <ArrowLeftIcon size={16} />
        </button>

        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-2xs font-medium text-ink-secondary">
              {ticketRef(ticket)}
            </span>
            <StatusPill status={status} />
          </div>
          <h2 className="mt-1 truncate text-[14px] font-semibold text-ink">
            {ticket.subject}
          </h2>
        </div>

        <Select
          value={status}
          onChange={(value) => void changeStatus(value)}
          aria-label="Ticket status"
          className="ml-auto shrink-0"
          leading={
            <span className={cn('size-1.5 rounded-full', ticketStatusDot(status))} />
          }
          options={[
            { value: 'pending', label: ticketStatusLabel('pending') },
            { value: 'waiting', label: ticketStatusLabel('waiting') },
            { value: 'completed', label: ticketStatusLabel('completed') },
          ]}
        />
      </div>

      {threadError ? (
        <Banner tone="error" className="m-4">
          {threadError}
        </Banner>
      ) : null}
      {actionError ? (
        <Banner tone="error" className="mx-4 mt-4">
          {actionError}
        </Banner>
      ) : null}

      <div
        ref={scrollRef}
        className="scroll-slim flex max-h-[440px] min-h-[240px] flex-1 flex-col gap-4 overflow-y-auto p-4"
      >
        {messages === null ? (
          <div className="space-y-3">
            <div className="h-16 w-3/4 animate-pulse rounded-xl bg-surface-panel" />
            <div className="ml-auto h-12 w-2/3 animate-pulse rounded-xl bg-surface-panel" />
          </div>
        ) : (
          thread.map((message) =>
            message.from === 'admin' ? (
              <AdminMessage key={message.id} message={message} />
            ) : (
              <UserMessage key={message.id} message={message} />
            ),
          )
        )}
      </div>

      <form
        onSubmit={(event) => {
          event.preventDefault();
          void send();
        }}
        className="flex items-center gap-2 border-t border-line p-3"
      >
        <input
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          placeholder="Type reply..."
          aria-label={`Reply to ${ticket.name}`}
          className="h-10 min-w-0 flex-1 rounded-control border border-line bg-white px-3.5 text-[13px] text-ink outline-none transition-colors placeholder:text-ink-muted focus:border-brand-500"
        />
        <Button
          type="submit"
          loading={sending}
          disabled={!draft.trim()}
          icon={<SendIcon size={15} />}
        >
          Reply
        </Button>
      </form>
    </>
  );
}

function UserMessage({ message }: { message: TicketMessage }) {
  return (
    <div className="flex max-w-[85%] gap-2.5">
      <span className="mt-0.5 inline-flex size-8 shrink-0 items-center justify-center rounded-full bg-surface-header text-xs font-semibold text-ink-secondary">
        {initials(message.authorName)}
      </span>
      <div className="min-w-0">
        <div className="flex flex-wrap items-baseline gap-x-2">
          <span className="text-xs font-semibold text-ink">
            {message.authorName}
          </span>
          {message.authorEmail ? (
            <span className="text-2xs text-ink-secondary">
              ({message.authorEmail})
            </span>
          ) : null}
          <span className="text-2xs text-ink-muted">
            {formatIsoDate(message.createdAt)}
          </span>
        </div>
        <p className="mt-1.5 whitespace-pre-wrap rounded-xl rounded-tl-sm bg-surface-panel px-3.5 py-2.5 text-[13px] leading-relaxed text-ink">
          {message.text || <span className="text-ink-muted">(empty message)</span>}
        </p>
      </div>
    </div>
  );
}

function AdminMessage({ message }: { message: TicketMessage }) {
  return (
    <div className="flex max-w-[85%] gap-2.5 self-end">
      <div className="min-w-0 text-right">
        <div className="flex flex-wrap items-baseline justify-end gap-x-2">
          <span className="text-xs font-semibold text-ink">
            {message.authorName} (Admin)
          </span>
          <span className="text-2xs text-ink-muted">
            {formatIsoDate(message.createdAt)}
            {message.createdAt ? ` · ${formatTime(message.createdAt)}` : ''}
          </span>
        </div>
        <p className="mt-1.5 whitespace-pre-wrap rounded-xl rounded-tr-sm bg-brand-500 px-3.5 py-2.5 text-left text-[13px] leading-relaxed text-white">
          {message.text}
        </p>
      </div>
      <Avatar name={message.authorName} size={32} className="mt-0.5" />
    </div>
  );
}
