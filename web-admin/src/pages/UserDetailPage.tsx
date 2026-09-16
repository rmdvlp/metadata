import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Card, Panel, SectionHeader } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Banner } from '@/components/ui/Banner';
import { Modal } from '@/components/ui/Modal';
import { Avatar } from '@/components/ui/Avatar';
import { ActivityPill, ProBadge, QuarantineBadge } from '@/components/ui/Badge';
import { SearchInput } from '@/components/ui/SearchInput';
import { ActionMenu, FilterButton, Select } from '@/components/ui/Menu';
import { Pagination } from '@/components/ui/Pagination';
import { Blank, DataTable, Truncate, type Column } from '@/components/ui/Table';
import {
  ArrowLeftIcon,
  BlockIcon,
  CalendarDotsIcon,
  EditIcon,
  PhoneIcon,
  PinIcon,
  UsersIcon,
} from '@/components/icons';
import { cn } from '@/lib/cn';
import { useAsync } from '@/lib/useAsync';
import { formatCount, formatShortDate, formatTime } from '@/lib/format';
import {
  fetchUser,
  fetchUserContacts,
  fetchUserContactStats,
  setContactBlocked,
  setUserBlocked,
  updateUser,
} from '@/data/users';
import type { Contact, PlanTier } from '@/data/types';

const PAGE_SIZE = 18;

/** A user counts as active when the app checked in within the last week. */
const ACTIVE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

export function UserDetailPage() {
  const { uid = '' } = useParams();
  const navigate = useNavigate();

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [captured, setCaptured] = useState<'all' | 'captured' | 'manual'>('all');
  const [quarantine, setQuarantine] = useState<'all' | 'only' | 'none'>('all');
  const [editing, setEditing] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const user = useAsync(() => fetchUser(uid), [uid], 'this user');
  const stats = useAsync(
    () => fetchUserContactStats(uid),
    [uid],
    "this user's contact totals",
  );
  const contacts = useAsync(
    () => fetchUserContacts({ uid, page, pageSize: PAGE_SIZE, search }),
    [uid, page, search],
    "this user's contacts",
  );

  useEffect(() => setPage(1), [search, captured, quarantine]);

  const profile = user.data;

  // Provenance and quarantine are cheap client-side predicates over the page
  // that is already loaded, so they need no extra query or index.
  const rows = (contacts.data?.rows ?? []).filter((contact) => {
    if (captured === 'captured' && !contact.capturesContext) return false;
    if (captured === 'manual' && contact.capturesContext) return false;
    if (quarantine === 'only' && !contact.isBlocked) return false;
    if (quarantine === 'none' && contact.isBlocked) return false;
    return true;
  });

  const total = contacts.data?.total ?? 0;
  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const filtersActive = captured !== 'all' || quarantine !== 'all';

  const isActive =
    profile?.lastActiveAt != null &&
    Date.now() - profile.lastActiveAt.getTime() < ACTIVE_WINDOW_MS;

  const onToggleContactBlock = async (contact: Contact) => {
    setActionError(null);
    try {
      await setContactBlocked(uid, contact.id, !contact.isBlocked);
      contacts.reload();
    } catch {
      setActionError(
        `Could not update ${contact.fullName}. Check that this admin account has write access to users/${uid}/contacts.`,
      );
    }
  };

  const columns: Array<Column<Contact>> = [
    {
      key: 'name',
      header: 'Name',
      className: 'font-medium text-ink',
      cell: (row) => (
        <span className="flex items-center gap-2">
          <Truncate title={row.fullName}>{row.fullName}</Truncate>
          {row.isBlocked ? <QuarantineBadge /> : null}
        </span>
      ),
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
              label: 'Copy phone number',
              onClick: () => void navigator.clipboard?.writeText(row.phoneNumber),
            },
            {
              label: row.isBlocked ? 'Release from quarantine' : 'Quarantine contact',
              tone: row.isBlocked ? 'default' : 'danger',
              onClick: () => void onToggleContactBlock(row),
            },
          ]}
        />
      ),
    },
  ];

  if (user.error) {
    return (
      <div className="flex flex-col gap-4">
        <BackButton onClick={() => navigate('/users')} />
        <Banner tone="error">{user.error}</Banner>
      </div>
    );
  }

  if (!user.loading && !profile) {
    return (
      <div className="flex flex-col gap-4">
        <BackButton onClick={() => navigate('/users')} />
        <Banner tone="warn">
          No user document exists at <code>users/{uid}</code>. They may have
          been deleted.
        </Banner>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-5">
      <BackButton onClick={() => navigate(-1)} />

      {actionError ? <Banner tone="error">{actionError}</Banner> : null}

      <Card className="p-4 sm:p-5">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-center">
          <div className="flex min-w-0 flex-1 items-center gap-4">
            <div className="relative shrink-0">
              <Avatar
                name={profile?.displayName ?? '?'}
                src={profile?.photoUrl}
                size={64}
                tone="neutral"
              />
              {profile?.plan === 'pro' ? (
                <ProBadge className="absolute -bottom-1 left-1/2 -translate-x-1/2" />
              ) : null}
            </div>

            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2.5">
                <h1 className="truncate text-base font-semibold text-ink">
                  {user.loading ? 'Loading…' : profile?.displayName}
                </h1>
                {!user.loading ? <ActivityPill active={isActive} /> : null}
                {profile?.isBlocked ? (
                  <span className="rounded-full bg-state-badSoft px-2 py-[3px] text-2xs font-medium text-state-bad">
                    Blocked
                  </span>
                ) : null}
              </div>
              <p className="mt-1.5 flex items-center gap-1.5 text-[13px] text-ink-secondary">
                <PhoneIcon size={15} className="shrink-0 text-brand-500" />
                <span className="truncate font-medium text-ink">
                  {profile?.phoneNumber ?? '—'}
                </span>
              </p>
              <p className="text-2xs text-ink-muted">Phone Number</p>
            </div>
          </div>

          <div className="grid grid-cols-3 rounded-card bg-surface-panel py-3 lg:shrink-0">
            <HeaderStat
              icon={<PinIcon size={22} />}
              value={stats.data?.total ?? null}
              label="All Contacts"
              loading={stats.loading}
            />
            <HeaderStat
              icon={<CalendarDotsIcon size={22} />}
              value={stats.data?.completed ?? null}
              label="Completed"
              loading={stats.loading}
              divided
            />
            <HeaderStat
              icon={<UsersIcon size={22} />}
              value={stats.data?.pending ?? null}
              label="Pending"
              loading={stats.loading}
              divided
            />
          </div>

          <div className="flex shrink-0 gap-2">
            <Button
              variant="outline"
              icon={<EditIcon size={15} />}
              onClick={() => setEditing(true)}
              disabled={!profile}
            >
              Edit
            </Button>
            <Button
              variant="danger"
              icon={<BlockIcon size={15} />}
              onClick={() => setConfirmBlock(true)}
              disabled={!profile}
            >
              {profile?.isBlocked ? 'Unblock' : 'Block'}
            </Button>
          </div>
        </div>

        {stats.error ? (
          <Banner tone="warn" className="mt-4">
            {stats.error}
          </Banner>
        ) : null}
      </Card>

      <SectionHeader
        title="User Contacts"
        actions={
          <>
            <SearchInput
              value={search}
              onChange={setSearch}
              busy={contacts.loading && search.length > 0}
              placeholder="Search name, number, location..."
              className="w-full sm:w-72"
            />
            <FilterButton
              active={filtersActive}
              onReset={() => {
                setCaptured('all');
                setQuarantine('all');
              }}
              groups={[
                {
                  id: 'captured',
                  label: 'Saved via',
                  value: captured,
                  onChange: (value) =>
                    setCaptured(value as 'all' | 'captured' | 'manual'),
                  options: [
                    { value: 'all', label: 'Any method' },
                    { value: 'captured', label: 'Context captured' },
                    { value: 'manual', label: 'Saved manually' },
                  ],
                },
                {
                  id: 'quarantine',
                  label: 'Quarantine',
                  value: quarantine,
                  onChange: (value) =>
                    setQuarantine(value as 'all' | 'only' | 'none'),
                  options: [
                    { value: 'all', label: 'All contacts' },
                    { value: 'only', label: 'Quarantined only' },
                    { value: 'none', label: 'Not quarantined' },
                  ],
                },
              ]}
            />
          </>
        }
      />

      {contacts.data?.capped ? (
        <Banner tone="warn">
          Search scans this user's 500 most recently updated contacts.
        </Banner>
      ) : null}

      <Panel>
        <DataTable
          columns={columns}
          rows={rows}
          keyOf={(row) => row.id}
          loading={contacts.loading}
          error={contacts.error}
          skeletonRows={10}
          empty={
            search || filtersActive
              ? 'No contacts match these filters.'
              : 'This user has not saved any contacts yet.'
          }
          onRowClick={(row) => navigate(`/users/${uid}/contacts/${row.id}`)}
          mobileCard={(row) => (
            <div className="flex items-start gap-3">
              <Avatar name={row.fullName} src={row.photoUrl} size={34} />
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-2 truncate text-[13px] font-medium text-ink">
                  <span className="truncate">{row.fullName}</span>
                  {row.isBlocked ? <QuarantineBadge /> : null}
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

      {profile ? (
        <>
          <EditUserModal
            open={editing}
            user={profile}
            onClose={() => setEditing(false)}
            onSaved={() => {
              setEditing(false);
              user.reload();
            }}
          />
          <Modal
            open={confirmBlock}
            onClose={() => setConfirmBlock(false)}
            title={profile.isBlocked ? 'Unblock this user?' : 'Block this user?'}
            description={
              profile.isBlocked
                ? `${profile.displayName} will be able to use Context ID again.`
                : `${profile.displayName} keeps their data, but is flagged as blocked across the dashboard.`
            }
            footer={
              <>
                <Button variant="ghost" onClick={() => setConfirmBlock(false)}>
                  Cancel
                </Button>
                <Button
                  variant={profile.isBlocked ? 'primary' : 'danger'}
                  onClick={async () => {
                    setActionError(null);
                    try {
                      await setUserBlocked(profile.uid, !profile.isBlocked);
                      setConfirmBlock(false);
                      user.reload();
                    } catch {
                      setConfirmBlock(false);
                      setActionError(
                        'Could not update this user. Your admin account needs write access to /users in firestore.rules.',
                      );
                    }
                  }}
                >
                  {profile.isBlocked ? 'Unblock user' : 'Block user'}
                </Button>
              </>
            }
          />
        </>
      ) : null}
    </div>
  );
}

function BackButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Back"
      className="inline-flex size-8 items-center justify-center rounded-full border border-line text-brand-500 transition-colors hover:bg-brand-50"
    >
      <ArrowLeftIcon size={16} />
    </button>
  );
}

/**
 * Icon to the left, figure over label to its right, separated by a hairline
 * that stops short of the panel edge — the arrangement in the design. The
 * divider is drawn by the cell that follows a neighbour rather than by the
 * container, so the first cell never renders a stray leading rule.
 */
function HeaderStat({
  icon,
  value,
  label,
  loading,
  divided = false,
}: {
  icon: React.ReactNode;
  value: number | null;
  label: string;
  loading: boolean;
  divided?: boolean;
}) {
  return (
    <div
      className={cn(
        'relative flex min-w-0 items-center justify-center gap-2.5 px-2 sm:gap-3 sm:px-4',
        divided &&
          'before:absolute before:left-0 before:top-1/2 before:h-9 before:w-px before:-translate-y-1/2 before:bg-line-strong',
      )}
    >
      {/* No CSS size here on purpose: the `size` prop passed at the call site
          is what decides, so editing it there has the effect you expect. */}
      <span className="shrink-0 text-brand-500">{icon}</span>
      <div className="min-w-0">
        {loading ? (
          <div className="h-6 w-12 animate-pulse rounded bg-line" />
        ) : (
          <p className="text-lg  leading-tight tracking-tight text-ink sm:text-[20px]">
            {value === null ? '—' : formatCount(value)}
          </p>
        )}
        <p className="truncate text-[11px] text-ink-secondary sm:text-xs">{label}</p>
      </div>
    </div>
  );
}

function EditUserModal({
  open,
  user,
  onClose,
  onSaved,
}: {
  open: boolean;
  user: { uid: string; displayName: string; phoneNumber: string; plan: PlanTier; note?: string };
  onClose: () => void;
  onSaved: () => void;
}) {
  const [displayName, setDisplayName] = useState(user.displayName);
  const [phoneNumber, setPhoneNumber] = useState(user.phoneNumber);
  const [plan, setPlan] = useState<PlanTier>(user.plan);
  const [note, setNote] = useState(user.note ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Re-seed the form whenever it reopens on a freshly loaded user.
  useEffect(() => {
    if (!open) return;
    setDisplayName(user.displayName);
    setPhoneNumber(user.phoneNumber);
    setPlan(user.plan);
    setNote(user.note ?? '');
    setError(null);
  }, [open, user]);

  const save = async () => {
    if (!displayName.trim()) {
      setError('A display name is required.');
      return;
    }

    setSaving(true);
    setError(null);
    try {
      await updateUser(user.uid, {
        displayName: displayName.trim(),
        phoneNumber: phoneNumber.trim(),
        plan,
        note: note.trim(),
      });
      onSaved();
    } catch {
      setError(
        'Could not save. Your admin account needs update access to /users in firestore.rules.',
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Edit user"
      description="Changes are written straight to the user's Firestore document."
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button loading={saving} onClick={() => void save()}>
            Save changes
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {error ? <Banner tone="error">{error}</Banner> : null}

        <Input
          label="Display name"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
        />
        <Input
          label="Phone number"
          value={phoneNumber}
          onChange={(e) => setPhoneNumber(e.target.value)}
          placeholder="+1 415 555 0142"
        />

        <div>
          <p className="mb-1.5 text-xs font-medium text-ink">Plan</p>
          <Select
            value={plan}
            onChange={setPlan}
            className="h-12 w-full justify-between"
            aria-label="Plan tier"
            options={[
              { value: 'free', label: 'Free' },
              { value: 'pro', label: 'Pro' },
            ]}
          />
        </div>

        <Input
          label="Admin note"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Shown in the Note column"
        />
      </div>
    </Modal>
  );
}
