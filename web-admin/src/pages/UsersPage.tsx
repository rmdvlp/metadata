import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Panel, SectionHeader } from '@/components/ui/Card';
import { Banner } from '@/components/ui/Banner';
import { SearchInput } from '@/components/ui/SearchInput';
import { ActionMenu, FilterButton } from '@/components/ui/Menu';
import { Pagination } from '@/components/ui/Pagination';
import { Blank, DataTable, Truncate, type Column } from '@/components/ui/Table';
import { Avatar } from '@/components/ui/Avatar';
import { ProBadge } from '@/components/ui/Badge';
import { useAsync } from '@/lib/useAsync';
import { formatShortDate, formatTime, shortRef } from '@/lib/format';
import {
  fetchUserActivity,
  fetchUsers,
  setUserBlocked,
} from '@/data/users';
import type { AppUserActivity, AppUser, PlanTier } from '@/data/types';

const PAGE_SIZE = 18;

export function UsersPage() {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();

  // The header search deep-links here with ?q=, so the URL owns the term.
  const search = params.get('q') ?? '';
  const [page, setPage] = useState(1);
  const [plan, setPlan] = useState<PlanTier | 'all'>('all');
  const [blocked, setBlocked] = useState<'all' | 'blocked' | 'active'>('all');
  const [activity, setActivity] = useState<Record<string, AppUserActivity>>({});
  const [actionError, setActionError] = useState<string | null>(null);

  const filtersActive = plan !== 'all' || blocked !== 'all';

  const users = useAsync(
    () =>
      fetchUsers({
        page,
        pageSize: PAGE_SIZE,
        search,
        plan,
        blocked: blocked === 'all' ? 'all' : blocked === 'blocked',
      }),
    [page, search, plan, blocked],
    'the user directory',
  );

  const rows = users.data?.rows ?? [];
  const total = users.data?.total ?? 0;
  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE));

  // Reset to page 1 whenever the result set changes shape under us.
  useEffect(() => setPage(1), [search, plan, blocked]);

  // Location and last-use are not on the user doc — fill them in after the
  // table has painted so rows never wait on a per-row read.
  const uidKey = rows.map((row) => row.uid).join(',');
  useEffect(() => {
    if (rows.length === 0) return;
    let stale = false;

    void fetchUserActivity(rows.map((row) => row.uid)).then((result) => {
      if (!stale) setActivity((prev) => ({ ...prev, ...result }));
    });

    return () => {
      stale = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [uidKey]);

  const onToggleBlock = async (user: AppUser) => {
    setActionError(null);
    try {
      await setUserBlocked(user.uid, !user.isBlocked);
      users.reload();
    } catch {
      setActionError(
        `Could not ${user.isBlocked ? 'unblock' : 'block'} ${user.displayName}. Your admin account needs write access in firestore.rules.`,
      );
    }
  };

  const columns: Array<Column<AppUser>> = useMemo(
    () => [
      {
        key: 'ticket',
        header: 'Ticket',
        className: 'w-[86px] font-medium text-ink',
        cell: (row) => shortRef(row.uid),
      },
      {
        key: 'name',
        header: 'Name',
        className: 'font-medium text-ink',
        cell: (row) => (
          <span className="flex items-center gap-2">
            <Truncate title={row.displayName}>{row.displayName}</Truncate>
            {row.plan === 'pro' ? <ProBadge /> : null}
            {row.isBlocked ? (
              <span className="shrink-0 text-2xs font-medium text-state-bad">
                Blocked
              </span>
            ) : null}
          </span>
        ),
      },
      { key: 'phone', header: 'Phone Number', cell: (row) => row.phoneNumber },
      {
        key: 'location',
        header: 'Location',
        hideBelow: 'lg',
        cell: (row) => {
          const place = activity[row.uid]?.location;
          return place && place !== '—' ? (
            <Truncate title={place}>{place}</Truncate>
          ) : (
            <Blank />
          );
        },
      },
      {
        key: 'date',
        header: 'Last Use date',
        hideBelow: 'lg',
        cell: (row) =>
          formatShortDate(activity[row.uid]?.lastUsedAt ?? row.lastActiveAt),
      },
      {
        key: 'time',
        header: 'Time',
        hideBelow: 'xl',
        cell: (row) =>
          formatTime(activity[row.uid]?.lastUsedAt ?? row.lastActiveAt),
      },
      {
        key: 'note',
        header: 'Note',
        hideBelow: 'xl',
        cell: (row) =>
          row.note ? <Truncate title={row.note}>{row.note}</Truncate> : <Blank />,
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
                label: 'View details',
                onClick: () => navigate(`/users/${row.uid}`),
              },
              {
                label: 'Copy phone number',
                onClick: () => void navigator.clipboard?.writeText(row.phoneNumber),
              },
              {
                label: row.isBlocked ? 'Unblock user' : 'Block user',
                tone: row.isBlocked ? 'default' : 'danger',
                onClick: () => void onToggleBlock(row),
              },
            ]}
          />
        ),
      },
    ],
    // `activity` fills in after the first paint, so the cells must re-render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [activity, navigate],
  );

  return (
    <div className="flex flex-col gap-4">
      <SectionHeader
        title="All Users"
        subtitle={
          users.loading
            ? undefined
            : `${total.toLocaleString()} ${total === 1 ? 'user' : 'users'}${search ? ` matching “${search}”` : ''}`
        }
        actions={
          <>
            <SearchInput
              value={search}
              onChange={(term) => {
                const next = new URLSearchParams(params);
                if (term.trim()) next.set('q', term.trim());
                else next.delete('q');
                setParams(next, { replace: true });
              }}
              busy={users.loading && search.length > 0}
              placeholder="Search name, number, location..."
              className="w-full sm:w-72"
            />
            <FilterButton
              active={filtersActive}
              onReset={() => {
                setPlan('all');
                setBlocked('all');
              }}
              groups={[
                {
                  id: 'plan',
                  label: 'Plan',
                  value: plan,
                  onChange: (value) => setPlan(value as PlanTier | 'all'),
                  options: [
                    { value: 'all', label: 'All plans' },
                    { value: 'free', label: 'Free' },
                    { value: 'pro', label: 'Pro' },
                  ],
                },
                {
                  id: 'status',
                  label: 'Status',
                  value: blocked,
                  onChange: (value) =>
                    setBlocked(value as 'all' | 'blocked' | 'active'),
                  options: [
                    { value: 'all', label: 'All users' },
                    { value: 'active', label: 'Active only' },
                    { value: 'blocked', label: 'Blocked only' },
                  ],
                },
              ]}
            />
          </>
        }
      />

      {actionError ? <Banner tone="error">{actionError}</Banner> : null}
      {users.data?.capped ? (
        <Banner tone="warn">
          Search scans the 500 most recently created users. Narrow the term, or
          filter by plan, to be sure you are seeing everyone.
        </Banner>
      ) : null}

      <Panel>
        <DataTable
          columns={columns}
          rows={rows}
          keyOf={(row) => row.uid}
          loading={users.loading}
          error={users.error}
          skeletonRows={10}
          empty={
            search
              ? `No users match “${search}”.`
              : 'No users have signed up yet.'
          }
          onRowClick={(row) => navigate(`/users/${row.uid}`)}
          mobileCard={(row) => (
            <div className="flex items-start gap-3">
              <Avatar name={row.displayName} src={row.photoUrl} size={34} />
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-2 truncate text-[13px] font-medium text-ink">
                  <span className="truncate">{row.displayName}</span>
                  {row.plan === 'pro' ? <ProBadge /> : null}
                </p>
                <p className="truncate text-xs text-ink-secondary">
                  {row.phoneNumber}
                </p>
                <p className="mt-1 truncate text-2xs text-ink-muted">
                  {activity[row.uid]?.location ?? '—'}
                  {' · '}
                  {formatShortDate(
                    activity[row.uid]?.lastUsedAt ?? row.lastActiveAt,
                  )}
                </p>
              </div>
            </div>
          )}
        />
      </Panel>

      <Pagination
        page={page}
        pageCount={pageCount}
        onChange={setPage}
        className="pb-2 pt-1"
      />
    </div>
  );
}
