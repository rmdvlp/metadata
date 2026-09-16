import { useState } from 'react';
import { Modal } from './ui/Modal';
import { Input } from './ui/Input';
import { Button } from './ui/Button';
import { Banner } from './ui/Banner';
import { Avatar } from './ui/Avatar';
import { LockIcon, MailIcon, ShieldIcon } from './icons';
import { useAuth } from '@/lib/auth';
import { administratorErrorMessage, updateOwnName } from '@/data/admins';

/**
 * Self-service profile editing, open to every role — a Support account edits
 * their own name here exactly like a Super Admin does. The role field is
 * read-only by design: firestore.rules refuses a self-update that touches
 * `roleId`, so a save that tried to change it would fail server-side anyway.
 */
export function ProfileModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { admin, resetPassword, refreshAdmin } = useAuth();
  const [name, setName] = useState(admin?.name ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<number | null>(null);
  const [resetState, setResetState] = useState<'idle' | 'sending' | 'sent' | 'error'>(
    'idle',
  );

  if (!admin) return null;

  const dirty = name.trim() !== admin.name && name.trim().length > 0;

  const handleSave = async () => {
    if (!dirty) return;
    setSaving(true);
    setError(null);
    try {
      await updateOwnName(admin.uid, name);
      await refreshAdmin();
      setSavedAt(Date.now());
    } catch (err) {
      setError(administratorErrorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  const handleReset = async () => {
    setResetState('sending');
    try {
      await resetPassword(admin.email);
      setResetState('sent');
    } catch {
      setResetState('error');
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="My Profile"
      description="Visible only to you."
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Close
          </Button>
          <Button loading={saving} disabled={!dirty} onClick={() => void handleSave()}>
            Save changes
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="flex items-center gap-3">
          <Avatar name={admin.name} src={admin.photoUrl} size={48} tone="neutral" />
          <div className="min-w-0">
            <p className="truncate text-[13px] font-semibold text-ink">{admin.name}</p>
            <p className="truncate text-2xs text-ink-secondary">{admin.email}</p>
          </div>
        </div>

        {error ? <Banner tone="error">{error}</Banner> : null}
        {savedAt ? <Banner tone="info">Profile updated.</Banner> : null}

        <Input
          label="Name"
          value={name}
          onChange={(e) => {
            setName(e.target.value);
            setSavedAt(null);
          }}
        />

        <div>
          <p className="mb-1.5 text-xs font-medium text-ink">Email</p>
          <div className="flex h-12 items-center gap-2 rounded-control border border-line-strong bg-surface-panel px-4 text-[13px] text-ink-secondary">
            <MailIcon size={16} className="shrink-0 text-ink-muted" />
            <span className="truncate">{admin.email}</span>
          </div>
        </div>

        <div>
          <p className="mb-1.5 text-xs font-medium text-ink">Role</p>
          <div className="flex h-12 items-center gap-2 rounded-control border border-line-strong bg-surface-panel px-4 text-[13px] text-ink-secondary">
            <ShieldIcon size={16} className="shrink-0 text-ink-muted" />
            <span className="truncate">{admin.role}</span>
            <span className="ml-auto shrink-0 text-2xs text-ink-muted">
              Ask a Super Admin to change this
            </span>
          </div>
        </div>

        <div className="rounded-xl border border-line p-3.5">
          <p className="flex items-center gap-1.5 text-[13px] font-medium text-ink">
            <LockIcon size={15} className="text-ink-secondary" />
            Password
          </p>
          <p className="mt-1 text-xs text-ink-secondary">
            We'll email you a link to set a new one.
          </p>
          {resetState === 'sent' ? (
            <p className="mt-2 text-xs font-medium text-state-good">
              Reset link sent to {admin.email}.
            </p>
          ) : resetState === 'error' ? (
            <p className="mt-2 text-xs font-medium text-state-bad">
              Could not send the email. Try again shortly.
            </p>
          ) : (
            <Button
              variant="outline"
              size="sm"
              className="mt-2.5"
              loading={resetState === 'sending'}
              onClick={() => void handleReset()}
            >
              Send reset email
            </Button>
          )}
        </div>
      </div>
    </Modal>
  );
}
