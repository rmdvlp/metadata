import {
  collection,
  deleteDoc,
  doc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';
import { sendPasswordResetEmail } from 'firebase/auth';
import { auth, db } from '@/lib/firebase';
import { createAuthAccount } from '@/lib/secondaryAuth';
import { toDate } from './mappers';
import { fetchRoles } from './roles';
import type { Administrator } from './types';

export async function fetchAdministrators(): Promise<Administrator[]> {
  const [adminsSnap, roles] = await Promise.all([
    getDocs(collection(db, 'admins')),
    fetchRoles(),
  ]);
  const roleNameOf = new Map(roles.map((role) => [role.id, role.name]));

  return adminsSnap.docs
    .map((snap): Administrator => {
      const data = snap.data();
      const roleId = typeof data.roleId === 'string' ? data.roleId : null;
      return {
        uid: snap.id,
        name: (data.name as string) || 'Administrator',
        email: (data.email as string) || '—',
        photoUrl: (data.photoUrl as string) || undefined,
        roleId,
        roleName: roleId ? (roleNameOf.get(roleId) ?? null) : null,
        createdAt: toDate(data.createdAt),
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** Maps Auth/Firestore failures onto what an operator should actually do next. */
export function administratorErrorMessage(error: unknown): string {
  const code =
    typeof error === 'object' && error && 'code' in error
      ? String((error as { code: unknown }).code)
      : '';

  if (code === 'auth/email-already-in-use') {
    return (
      'An account with this email already exists. If it belongs to someone ' +
      "who should have dashboard access, recover their uid with " +
      '`npm run create:admin-user -- <email> <password>` and assign them a ' +
      'role from the console, since the web app cannot read another ' +
      "account's uid without its password."
    );
  }
  if (code === 'auth/invalid-email') return 'That email address is not valid.';
  if (code === 'auth/weak-password') {
    return 'Firebase could not set a password for this account — try again.';
  }
  if (code === 'permission-denied') {
    return 'Not allowed. Only an administrator with the Administration permission can do this.';
  }
  return error instanceof Error ? error.message : 'Something went wrong. Please try again.';
}

/**
 * Creates the new administrator's sign-in credentials on an isolated
 * secondary app (so the current admin's session is untouched), writes their
 * `admins/{uid}` document, then emails them a link to set their own
 * password — the throwaway password used to satisfy Auth's create call is
 * never shown or stored anywhere.
 */
export async function createAdministrator(input: {
  name: string;
  email: string;
  roleId: string;
}): Promise<void> {
  const email = input.email.trim();
  const name = input.name.trim();
  const throwawayPassword = `${crypto.randomUUID()}${crypto.randomUUID()}`;

  const uid = await createAuthAccount({ email, password: throwawayPassword, name });

  await setDoc(doc(db, 'admins', uid), {
    name,
    email,
    roleId: input.roleId,
    createdAt: serverTimestamp(),
  });

  await sendPasswordResetEmail(auth, email);
}

export async function updateAdministratorRole(
  uid: string,
  roleId: string,
): Promise<void> {
  await updateDoc(doc(db, 'admins', uid), { roleId });
}

/**
 * Revokes dashboard access. This removes the admins/{uid} document only —
 * the underlying Firebase Authentication account still exists, since
 * deleting an Auth user requires the Admin SDK, which this client-only
 * console does not have. Delete it separately in the Firebase console if the
 * account should stop existing entirely.
 */
export async function removeAdministrator(uid: string): Promise<void> {
  await deleteDoc(doc(db, 'admins', uid));
}

/** Every signed-in administrator may edit their own name — never their role. */
export async function updateOwnName(uid: string, name: string): Promise<void> {
  await updateDoc(doc(db, 'admins', uid), { name: name.trim() });
}
