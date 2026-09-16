import {
  collection,
  deleteDoc,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { mapRole } from './mappers';
import type { Permission, Role } from './types';

const ROLES = collection(db, 'roles');

/** Deterministic ids for the three seeded roles — see tools/seed-roles.mjs. */
export const SUPER_ADMIN_ROLE_ID = 'super_admin';

export async function fetchRoles(): Promise<Role[]> {
  const snap = await getDocs(ROLES);
  // Firestore has no native sort-by-"is this the built-in one" — the system
  // role reads first because it is the one every other role is compared
  // against, then the rest alphabetically.
  return snap.docs
    .map(mapRole)
    .sort((a, b) =>
      a.isSystem !== b.isSystem
        ? a.isSystem
          ? -1
          : 1
        : a.name.localeCompare(b.name),
    );
}

export async function fetchRole(roleId: string): Promise<Role | null> {
  const snap = await getDoc(doc(db, 'roles', roleId));
  return snap.exists() ? mapRole(snap) : null;
}

/** How many administrators currently point at this role — gates deletion. */
export async function countAdminsUsingRole(roleId: string): Promise<number> {
  const snap = await getCountFromServer(
    query(collection(db, 'admins'), where('roleId', '==', roleId)),
  );
  return snap.data().count;
}

function randomRoleId(): string {
  // Readable but collision-safe without pulling in a uuid dependency for one
  // call site; the 'role_' prefix keeps it visually distinct from the three
  // fixed seed ids (super_admin / admin / support) in Firestore's console.
  return `role_${crypto.randomUUID().replace(/-/g, '').slice(0, 16)}`;
}

export async function createRole(input: {
  name: string;
  permissions: Permission[];
}): Promise<string> {
  const id = randomRoleId();
  await setDoc(doc(db, 'roles', id), {
    name: input.name.trim(),
    permissions: input.permissions,
    isSystem: false,
    createdAt: serverTimestamp(),
  });
  return id;
}

export async function updateRole(
  roleId: string,
  input: { name: string; permissions: Permission[] },
): Promise<void> {
  await updateDoc(doc(db, 'roles', roleId), {
    name: input.name.trim(),
    permissions: input.permissions,
  });
}

export async function deleteRole(roleId: string): Promise<void> {
  await deleteDoc(doc(db, 'roles', roleId));
}
