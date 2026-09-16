import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Panel, SectionHeader } from '@/components/ui/Card';
import { StatCard } from '@/components/ui/StatCard';
import { Banner } from '@/components/ui/Banner';
import { ActionMenu, Select } from '@/components/ui/Menu';
import { Blank, DataTable, Truncate, type Column } from '@/components/ui/Table';
import { EncountersChart } from '@/components/charts/EncountersChart';
import { Avatar } from '@/components/ui/Avatar';
import {
  CalendarTickIcon,
  CrownIcon,
  DollarIcon,
  GpsIcon,
  NoteIcon,
  UsersIcon,
} from '@/components/icons';
import { useAuth } from '@/lib/auth';
import { useAsync } from '@/lib/useAsync';
import { formatShortDate, formatTime, shortRef } from '@/lib/format';
import { fetchDashboardStats, fetchEncounterSeries } from '@/data/dashboard';
import { fetchRecentContacts } from '@/data/users';
import { RANGE_LABELS } from '@/data/ranges';
import type { ChartRange, Contact } from '@/data/types';

const PREVIOUS_LABEL: Record<ChartRange, string> = {
  week: 'Last week',
  month: 'Last month',
  year: 'Last year',
};

export function DashboardPage() {
  const { admin } = useAuth();
  const navigate = useNavigate();
  const [range, setRange] = useState<ChartRange>('week');

  const stats = useAsync(() => fetchDashboardStats(), [], 'the dashboard totals');
  const series = useAsync(
    () => fetchEncounterSeries(range),
    [range],
    'the encounters chart',
  );
  const recent = useAsync(() => fetchRecentContacts(8), [], 'recent contacts');

  const value = <K extends 'allContacts' | 'encounters' | 'placesVisited' | 'notesAdded' | 'freePlans' | 'proPlans'>(
    key: K,
  ) => (stats.data ? stats.data[key] : null);

  // The same missing collection-group index fails several reads at once, which
  // is why this used to print the identical message three times over. One line
  // per distinct problem, and the tiles and chart still render around it.
  const issues = [
    ...(stats.error ? [stats.error] : []),
    ...(stats.data?.issues ?? []),
    ...(series.error ? [series.error] : []),
    ...(series.data?.issue ? [series.data.issue] : []),
  ].filter((message, index, all) => all.indexOf(message) === index);

  const columns: Array<Column<Contact>> = [
    {
      key: 'ticket',
      header: 'Ticket',
      className: 'w-[86px] font-medium text-ink',
      cell: (row) => shortRef(row.id),
    },
    {
      key: 'name',
      header: 'Name',
      className: 'font-medium text-ink',
      cell: (row) => <Truncate title={row.fullName}>{row.fullName}</Truncate>,
    },
    { key: 'phone', header: 'Phone Number', cell: (row) => row.phoneNumber },
    {
      key: 'location',
      header: 'Location',
      hideBelow: 'lg',
      cell: (row) =>
        row.location ? (
          <Truncate title={row.location.address ?? row.location.placeName}>
            {row.location.placeName ?? row.location.address ?? '—'}
          </Truncate>
        ) : (
          <Blank />
        ),
    },
    {
      key: 'date',
      header: 'Last Use date',
      hideBelow: 'lg',
      cell: (row) => formatShortDate(row.updatedAt ?? row.createdAt),
    },
    {
      key: 'time',
      header: 'Time',
      hideBelow: 'xl',
      cell: (row) => formatTime(row.updatedAt ?? row.createdAt),
    },
    {
      key: 'note',
      header: 'Note',
      hideBelow: 'xl',
      cell: (row) =>
        row.role || row.notes ? (
          <Truncate title={row.role ?? row.notes}>{row.role ?? row.notes}</Truncate>
        ) : (
          <Blank />
        ),
    },
    {
      key: 'action',
      header: 'Action',
      align: 'right',
      className: 'w-[70px]',
      cell: (row) => (
        <ActionMenu
          items={[
            {
              label: 'Open owner',
              onClick: () => navigate(`/users/${row.ownerUid}`),
              disabled: !row.ownerUid,
            },
            {
              label: 'Copy phone number',
              onClick: () => void navigator.clipboard?.writeText(row.phoneNumber),
            },
          ]}
        />
      ),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-lg font-bold text-ink">
          Hi, {admin?.name ?? 'there'} <span aria-hidden="true">👋</span>
        </h1>
        <p className="mt-0.5 text-xs text-ink-secondary">
          Here's your connection overview.
        </p>
      </div>

      {issues.length > 0 ? (
        <Banner tone="warn">
          <p className="font-medium">
            {issues.length === 1
              ? 'One figure could not be loaded.'
              : `${issues.length} figures could not be loaded.`}{' '}
            Everything else below is live.
          </p>
          <ul className="mt-1 list-disc space-y-1 pl-4">
            {issues.map((message) => (
              <li key={message} className="break-words">
                {message}
              </li>
            ))}
          </ul>
        </Banner>
      ) : null}

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <StatCard
            label="All Contacts"
            value={value('allContacts')}
            loading={stats.loading}
            delta={stats.data?.deltas.allContacts}
            icon={<UsersIcon size={18} />}
          />
          <StatCard
            label="Encounters"
            value={value('encounters')}
            loading={stats.loading}
            delta={stats.data?.deltas.encounters}
            icon={<CalendarTickIcon size={18} />}
          />
          <StatCard
            label="Places Visited"
            value={value('placesVisited')}
            loading={stats.loading}
            delta={stats.data?.deltas.placesVisited}
            icon={<GpsIcon size={18} />}
          />
          <StatCard
            label="Notes Added"
            value={value('notesAdded')}
            loading={stats.loading}
            delta={stats.data?.deltas.notesAdded}
            icon={<NoteIcon size={18} />}
          />
          <StatCard
            label="Free Plans"
            value={value('freePlans')}
            loading={stats.loading}
            delta={stats.data?.deltas.freePlans}
            icon={<DollarIcon size={18} />}
          />
          <StatCard
            label="Pro Plans"
            value={value('proPlans')}
            loading={stats.loading}
            delta={stats.data?.deltas.proPlans}
            icon={<CrownIcon size={18} />}
          />
        </div>

        <Card className="p-4">
          <SectionHeader
            title="Encounters Over Time"
            actions={
              <Select
                value={range}
                onChange={setRange}
                aria-label="Chart date range"
                options={[
                  { value: 'week', label: RANGE_LABELS.week },
                  { value: 'month', label: RANGE_LABELS.month },
                  { value: 'year', label: RANGE_LABELS.year },
                ]}
              />
            }
          />

          {/* Drawn unconditionally. A read that failed still yields zeroed
              buckets, so the operator sees the axis and the range they picked
              rather than an error card where the chart belongs — the reason
              why is in the banner at the top of the page. */}
          <EncountersChart
            points={series.data?.points ?? []}
            loading={series.loading}
            currentLabel={RANGE_LABELS[range]}
            previousLabel={PREVIOUS_LABEL[range]}
          />
          {series.data?.capped ? (
            <Banner tone="warn" className="mt-2">
              Showing the most recent 5,000 encounters in this window; older ones
              in the same period are not counted.
            </Banner>
          ) : null}
        </Card>
      </div>

      <div>
        <SectionHeader
          title="Recent Contacts"
          className="mb-3"
          actions={
            <a
              href="/users"
              onClick={(event) => {
                event.preventDefault();
                navigate('/users');
              }}
              className="text-xs font-medium text-brand-500 hover:underline"
            >
              View all users
            </a>
          }
        />
        <Panel>
          <DataTable
            columns={columns}
            rows={recent.data ?? []}
            keyOf={(row) => `${row.ownerUid}/${row.id}`}
            loading={recent.loading}
            error={recent.error}
            empty="No contacts have been captured yet."
            onRowClick={(row) =>
              row.ownerUid ? navigate(`/users/${row.ownerUid}`) : undefined
            }
            mobileCard={(row) => (
              <div className="flex items-start gap-3">
                <Avatar name={row.fullName} src={row.photoUrl} size={34} />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[13px] font-medium text-ink">
                    {row.fullName}
                  </p>
                  <p className="truncate text-xs text-ink-secondary">
                    {row.phoneNumber}
                  </p>
                  <p className="mt-1 truncate text-2xs text-ink-muted">
                    {row.location?.placeName ?? row.location?.address ?? 'No place captured'}
                    {' · '}
                    {formatShortDate(row.updatedAt ?? row.createdAt)}
                  </p>
                </div>
                <span className="shrink-0 text-2xs text-ink-muted">
                  {shortRef(row.id)}
                </span>
              </div>
            )}
          />
        </Panel>
      </div>
    </div>
  );
}
