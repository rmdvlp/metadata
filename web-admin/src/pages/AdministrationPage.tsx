import { useState } from 'react';
import { cn } from '@/lib/cn';
import { useAuth } from '@/lib/auth';
import { useAsync } from '@/lib/useAsync';
import { PERMISSIONS } from '@/lib/permissions';
import { Panel, SectionHeader } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Modal } from '@/components/ui/Modal';
import { Banner } from '@/components/ui/Banner';
import { Avatar } from '@/components/ui/Avatar';
import { Chip } from '@/components/ui/Badge';
import { ActionMenu, Select } from '@/components/ui/Menu';
import { Blank, DataTable, type Column } from '@/components/ui/Table';
import { PlusIcon, ShieldIcon } from '@/components/icons';
import { formatShortDate } from '@/lib/format';
import {
  administratorErrorMessage,
  createAdministrator,
  fetchAdministrators,
  removeAdministrator,
  updateAdministratorRole,
} from '@/data/admins';
import {
  countAdminsUsingRole,
  createRole,
  deleteRole,
  fetchRoles,
  updateRole,
} from '@/data/roles';
import type { Administrator, Permission, Role } from '@/data/types';

type Tab = 'administrators' | 'roles';

const TABS: Array<{ value: Tab; label: string }> = [
  { value: 'administrators', label: 'Administrators' },
  { value: 'roles', label: 'Roles' },
];

/**
 * Only reachable by a role holding 'administration' — see RequirePermission
 * in App.tsx and the matching check in firestore.rules. Two tabs: who has
 * dashboard access (Administrators) and what each role is allowed to do
 * (Roles). Both read/write through the same permission model every other
 * page enforces, so a Support account cannot reach this screen by any route.
 */
export function AdministrationPage() {
  const { admin } = useAuth();
  const [tab, setTab] = useState<Tab>('administrators');
  const [reloadKey, setReloadKey] = useState(0);
  const bump = () => setReloadKey((k) => k + 1);

  const administrators = useAsync(
    () => fetchAdministrators(),
    [reloadKey],
    'the administrator list',
  );
  const roles = useAsync(() => fetchRoles(), [reloadKey], 'the roles list');

  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-lg font-bold text-ink">Administration</h1>
        <p className="mt-0.5 text-xs text-ink-secondary">
          Manage who can sign in to this dashboard and what each role can do.
        </p>
      </div>

      <div
        role="tablist"
        aria-label="Administration section"
        className="flex gap-1.5"
      >
        {TABS.map((item) => (
          <button
            key={item.value}
            type="button"
            role="tab"
            aria-selected={tab === item.value}
            onClick={() => setTab(item.value)}
            className={cn(
              'h-8 shrink-0 rounded-control px-3.5 text-[13px] font-medium transition-colors',
              tab === item.value
                ? 'bg-brand-500 text-white'
                : 'bg-surface-panel text-ink-secondary hover:bg-line',
            )}
          >
            {item.label}
          </button>
        ))}
      </div>

      {tab === 'administrators' ? (
        <AdministratorsTab
          administrators={administrators.data ?? []}
          roles={roles.data ?? []}
          loading={administrators.loading || roles.loading}
          error={administrators.error ?? roles.error}
          myUid={admin?.uid ?? ''}
          onChanged={bump}
        />
      ) : (
        <RolesTab
          roles={roles.data ?? []}
          administrators={administrators.data ?? []}
          loading={roles.loading}
          error={roles.error}
          onChanged={bump}
        />
      )}
    </div>
  );
}

function AdministratorsTab({
  administrators,
  roles,
  loading,
  error,
  myUid,
  onChanged,
}: {
  administrators: Administrator[];
  roles: Role[];
  loading: boolean;
  error: string | null;
  myUid: string;
  onChanged: () => void;
}) {
  const [adding, setAdding] = useState(false);
  const [changingRoleFor, setChangingRoleFor] = useState<Administrator | null>(null);
  const [removing, setRemoving] = useState<Administrator | null>(null);

  const columns: Array<Column<Administrator>> = [
    {
      key: 'name',
      header: 'Name',
      cell: (row) => (
        <span className="flex items-center gap-2.5 font-medium text-ink">
          <Avatar name={row.name} src={row.photoUrl} size={30} tone="neutral" />
          {row.name}
          {row.uid === myUid ? (
            <span className="rounded-full bg-surface-panel px-2 py-[2px] text-2xs font-medium text-ink-secondary">
              You
            </span>
          ) : null}
        </span>
      ),
    },
    { key: 'email', header: 'Email', cell: (row) => row.email },
    {
      key: 'role',
      header: 'Role',
      cell: (row) => (row.roleName ? <Chip tone="brand">{row.roleName}</Chip> : <Blank />),
    },
    {
      key: 'added',
      header: 'Added',
      hideBelow: 'md',
      cell: (row) => formatShortDate(row.createdAt),
    },
    {
      key: 'action',
      header: 'Action',
      align: 'right',
      className: 'w-[70px]',
      cell: (row) =>
        row.uid === myUid ? (
          <span className="text-2xs text-ink-muted">Edit from My Profile</span>
        ) : (
          <ActionMenu
            items={[
              {
                label: 'Change role',
                onClick: () => setChangingRoleFor(row),
              },
              {
                label: 'Remove access',
                tone: 'danger',
                onClick: () => setRemoving(row),
              },
            ]}
          />
        ),
    },
  ];

  return (
    <>
      <SectionHeader
        title="Administrators"
        actions={
          <Button size="sm" icon={<PlusIcon size={15} />} onClick={() => setAdding(true)}>
            Add Administrator
          </Button>
        }
      />

      <Panel>
        <DataTable
          columns={columns}
          rows={administrators}
          keyOf={(row) => row.uid}
          loading={loading}
          error={error}
          empty="No administrators yet."
        />
      </Panel>

      <AddAdministratorModal
        open={adding}
        roles={roles}
        onClose={() => setAdding(false)}
        onCreated={() => {
          setAdding(false);
          onChanged();
        }}
      />

      <ChangeRoleModal
        administrator={changingRoleFor}
        roles={roles}
        onClose={() => setChangingRoleFor(null)}
        onSaved={() => {
          setChangingRoleFor(null);
          onChanged();
        }}
      />

      <RemoveAdminModal
        administrator={removing}
        onClose={() => setRemoving(null)}
        onRemoved={() => {
          setRemoving(null);
          onChanged();
        }}
      />
    </>
  );
}

function AddAdministratorModal({
  open,
  roles,
  onClose,
  onCreated,
}: {
  open: boolean;
  roles: Role[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [roleId, setRoleId] = useState<string>('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reset = () => {
    setName('');
    setEmail('');
    setRoleId('');
    setError(null);
  };

  const effectiveRoleId = roleId || roles[0]?.id || '';
  const canSubmit = name.trim().length > 0 && email.trim().length > 0 && effectiveRoleId;

  const submit = async () => {
    if (!canSubmit) return;
    setSaving(true);
    setError(null);
    try {
      await createAdministrator({ name, email, roleId: effectiveRoleId });
      reset();
      onCreated();
    } catch (err) {
      setError(administratorErrorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={() => {
        reset();
        onClose();
      }}
      title="Add Administrator"
      description="They'll receive an email to set their own password — no password to share."
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button loading={saving} disabled={!canSubmit} onClick={() => void submit()}>
            Send invitation
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {error ? <Banner tone="error">{error}</Banner> : null}
        <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} />
        <Input
          label="Email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <div>
          <p className="mb-1.5 text-xs font-medium text-ink">Role</p>
          <Select
            value={effectiveRoleId}
            onChange={setRoleId}
            aria-label="Role"
            className="w-full justify-between"
            options={roles.map((role) => ({ value: role.id, label: role.name }))}
          />
        </div>
      </div>
    </Modal>
  );
}

function ChangeRoleModal({
  administrator,
  roles,
  onClose,
  onSaved,
}: {
  administrator: Administrator | null;
  roles: Role[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [roleId, setRoleId] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [openFor, setOpenFor] = useState<string | null>(null);

  // Re-seed whenever a *different* administrator's row opens this modal —
  // tracking just "is it open" would leave the previous row's selection
  // showing the moment a second row is clicked without closing the first.
  if (administrator && administrator.uid !== openFor) {
    setOpenFor(administrator.uid);
    setRoleId(administrator.roleId ?? '');
    setError(null);
  }

  if (!administrator) return null;

  const submit = async () => {
    setSaving(true);
    setError(null);
    try {
      await updateAdministratorRole(administrator.uid, roleId || administrator.roleId!);
      onSaved();
    } catch (err) {
      setError(administratorErrorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      title={`Change role — ${administrator.name}`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button loading={saving} onClick={() => void submit()}>
            Save
          </Button>
        </>
      }
    >
      {error ? <Banner tone="error" className="mb-3">{error}</Banner> : null}
      <Select
        value={roleId}
        onChange={setRoleId}
        aria-label="Role"
        className="w-full justify-between"
        options={roles.map((role) => ({ value: role.id, label: role.name }))}
      />
    </Modal>
  );
}

function RemoveAdminModal({
  administrator,
  onClose,
  onRemoved,
}: {
  administrator: Administrator | null;
  onClose: () => void;
  onRemoved: () => void;
}) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!administrator) return null;

  const submit = async () => {
    setSaving(true);
    setError(null);
    try {
      await removeAdministrator(administrator.uid);
      onRemoved();
    } catch (err) {
      setError(administratorErrorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      title="Remove access"
      description={`${administrator.name} will no longer be able to sign in to this dashboard.`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="danger" loading={saving} onClick={() => void submit()}>
            Remove access
          </Button>
        </>
      }
    >
      {error ? <Banner tone="error" className="mb-2">{error}</Banner> : null}
      <p className="text-[13px] text-ink-secondary">
        Their Firebase Authentication account itself is not deleted — only
        their access to this console. Delete the account separately in the
        Firebase console if it should stop existing entirely.
      </p>
    </Modal>
  );
}

function RolesTab({
  roles,
  administrators,
  loading,
  error,
  onChanged,
}: {
  roles: Role[];
  administrators: Administrator[];
  loading: boolean;
  error: string | null;
  onChanged: () => void;
}) {
  const [editing, setEditing] = useState<Role | 'new' | null>(null);
  const [deleting, setDeleting] = useState<Role | null>(null);

  const countFor = (roleId: string) =>
    administrators.filter((a) => a.roleId === roleId).length;

  const columns: Array<Column<Role>> = [
    {
      key: 'name',
      header: 'Role',
      cell: (row) => (
        <span className="flex items-center gap-2 font-medium text-ink">
          <ShieldIcon size={15} className="shrink-0 text-brand-500" />
          {row.name}
        </span>
      ),
    },
    {
      key: 'permissions',
      header: 'Permissions',
      cell: (row) => (
        <span className="flex flex-wrap gap-1">
          {row.permissions.length === 0 ? (
            <Blank />
          ) : (
            PERMISSIONS.filter((p) => row.permissions.includes(p.key)).map((p) => (
              <Chip key={p.key}>{p.label}</Chip>
            ))
          )}
        </span>
      ),
    },
    {
      key: 'count',
      header: 'Administrators',
      hideBelow: 'md',
      cell: (row) => countFor(row.id),
    },
    {
      key: 'action',
      header: 'Action',
      align: 'right',
      className: 'w-[110px]',
      cell: (row) => (
        <ActionMenu
          items={[
            { label: 'Edit', onClick: () => setEditing(row) },
            {
              label: 'Delete',
              tone: 'danger',
              disabled: row.isSystem || countFor(row.id) > 0,
              onClick: () => setDeleting(row),
            },
          ]}
        />
      ),
    },
  ];

  return (
    <>
      <SectionHeader
        title="Roles"
        actions={
          <Button size="sm" icon={<PlusIcon size={15} />} onClick={() => setEditing('new')}>
            Create Role
          </Button>
        }
      />

      <Panel>
        <DataTable
          columns={columns}
          rows={roles}
          keyOf={(row) => row.id}
          loading={loading}
          error={error}
          empty="No roles yet."
        />
      </Panel>

      <RoleFormModal
        role={editing === 'new' ? null : editing}
        open={editing !== null}
        onClose={() => setEditing(null)}
        onSaved={() => {
          setEditing(null);
          onChanged();
        }}
      />

      <DeleteRoleModal
        role={deleting}
        onClose={() => setDeleting(null)}
        onDeleted={() => {
          setDeleting(null);
          onChanged();
        }}
      />
    </>
  );
}

function RoleFormModal({
  role,
  open,
  onClose,
  onSaved,
}: {
  /** null = create; a Role = edit that role. */
  role: Role | null;
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(role?.name ?? '');
  const [permissions, setPermissions] = useState<Permission[]>(role?.permissions ?? []);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [openFor, setOpenFor] = useState<string | null>(null);

  // The form's local state only needs to track the role it was opened for —
  // this re-seeds it whenever a different row (or "new") opens the modal.
  const key = role?.id ?? (open ? 'new' : null);
  if (open && key !== openFor) {
    setOpenFor(key);
    setName(role?.name ?? '');
    setPermissions(role?.permissions ?? []);
    setError(null);
  }

  const toggle = (permission: Permission) => {
    if (role?.isSystem && permission === 'administration') return;
    setPermissions((current) =>
      current.includes(permission)
        ? current.filter((p) => p !== permission)
        : [...current, permission],
    );
  };

  const canSubmit = name.trim().length > 0 && permissions.length > 0;

  const submit = async () => {
    if (!canSubmit) return;
    setSaving(true);
    setError(null);
    try {
      if (role) {
        await updateRole(role.id, { name, permissions });
      } else {
        await createRole({ name, permissions });
      }
      onSaved();
    } catch (err) {
      setError(administratorErrorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={role ? `Edit role — ${role.name}` : 'Create Role'}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button loading={saving} disabled={!canSubmit} onClick={() => void submit()}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {error ? <Banner tone="error">{error}</Banner> : null}
        <Input label="Role name" value={name} onChange={(e) => setName(e.target.value)} />

        <div>
          <p className="mb-1.5 text-xs font-medium text-ink">Permissions</p>
          <div className="flex flex-col gap-1 rounded-xl border border-line p-1">
            {PERMISSIONS.map((p) => {
              const checked = permissions.includes(p.key);
              const locked = role?.isSystem && p.key === 'administration';
              return (
                <label
                  key={p.key}
                  className={cn(
                    'flex cursor-pointer items-start gap-2.5 rounded-lg px-2.5 py-2 transition-colors',
                    locked ? 'cursor-not-allowed opacity-70' : 'hover:bg-surface-panel',
                  )}
                >
                  <input
                    type="checkbox"
                    checked={checked}
                    disabled={locked}
                    onChange={() => toggle(p.key)}
                    className="mt-0.5 size-4 shrink-0 accent-brand-500"
                  />
                  <span className="min-w-0">
                    <span className="block text-[13px] font-medium text-ink">
                      {p.label}
                    </span>
                    <span className="block text-2xs text-ink-secondary">
                      {locked
                        ? `Required for the ${role.name} role.`
                        : p.description}
                    </span>
                  </span>
                </label>
              );
            })}
          </div>
          {!canSubmit && name.trim().length > 0 ? (
            <p className="mt-1.5 text-2xs text-state-bad">
              Pick at least one permission.
            </p>
          ) : null}
        </div>
      </div>
    </Modal>
  );
}

function DeleteRoleModal({
  role,
  onClose,
  onDeleted,
}: {
  role: Role | null;
  onClose: () => void;
  onDeleted: () => void;
}) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!role) return null;

  const submit = async () => {
    setSaving(true);
    setError(null);
    try {
      // A fresh count right before deleting, rather than trusting the list
      // already on screen — someone else could have assigned this role to
      // an administrator moments ago from a different session.
      const inUse = await countAdminsUsingRole(role.id);
      if (inUse > 0) {
        setError(
          `${inUse} administrator${inUse === 1 ? ' holds' : 's hold'} this role. Reassign them first.`,
        );
        return;
      }
      await deleteRole(role.id);
      onDeleted();
    } catch (err) {
      setError(administratorErrorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      title="Delete role"
      description={`"${role.name}" will be permanently removed.`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="danger" loading={saving} onClick={() => void submit()}>
            Delete role
          </Button>
        </>
      }
    >
      {error ? <Banner tone="error">{error}</Banner> : null}
    </Modal>
  );
}
