import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  sendPasswordResetEmail,
  signOut as fbSignOut,
  type User,
} from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './firebase';
import type { Permission } from '@/data/types';

export interface AdminProfile {
  uid: string;
  email: string;
  name: string;
  /** Display name of the assigned role, e.g. "Super Admin" — for the nav. */
  role: string;
  roleId: string | null;
  /**
   * Empty when `roleId` names a role that no longer exists (deleted, or the
   * account predates the roles system and was never backfilled). Every guard
   * in the app treats "no permissions" as no access, never as "grant
   * everything" — see RequirePermission in App.tsx.
   */
  permissions: Permission[];
  photoUrl?: string;
}

interface AuthState {
  /** `undefined` while the initial Firebase auth check is still in flight. */
  admin: AdminProfile | null | undefined;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  resetPassword: (email: string) => Promise<void>;
  hasPermission: (permission: Permission) => boolean;
  /** Re-reads admins/{uid} and its role — call after editing your own name. */
  refreshAdmin: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

/**
 * Signing in is not enough to reach the dashboard: the account must also have
 * an `admins/{uid}` document. Mobile users authenticate by phone against the
 * same project, so without this second check any app user could load the
 * console shell (Firestore rules would still refuse them every row, but they
 * should never see the chrome at all).
 *
 * The permission set comes from a second read, `roles/{roleId}` — the same
 * document firestore.rules itself consults, so what the nav shows always
 * matches what the server will actually allow.
 */
async function loadAdmin(user: User): Promise<AdminProfile | null> {
  const snap = await getDoc(doc(db, 'admins', user.uid));
  if (!snap.exists()) return null;

  const data = snap.data();
  const roleId = typeof data.roleId === 'string' ? data.roleId : null;

  let roleName = (data.role as string) || 'Administrator';
  let permissions: Permission[] = [];
  if (roleId) {
    const roleSnap = await getDoc(doc(db, 'roles', roleId));
    if (roleSnap.exists()) {
      const role = roleSnap.data();
      roleName = (role.name as string) || roleName;
      permissions = Array.isArray(role.permissions) ? role.permissions : [];
    }
  }

  return {
    uid: user.uid,
    email: user.email ?? (data.email as string) ?? '',
    name: (data.name as string) || user.displayName || 'Administrator',
    role: roleName,
    roleId,
    permissions,
    photoUrl: (data.photoUrl as string) || user.photoURL || undefined,
  };
}

/** Turns Firebase's error codes into something an operator can act on. */
export function authErrorMessage(error: unknown): string {
  const code =
    typeof error === 'object' && error && 'code' in error
      ? String((error as { code: unknown }).code)
      : '';

  switch (code) {
    case 'auth/invalid-email':
      return 'That email address is not valid.';
    case 'auth/missing-password':
      return 'Enter your password.';
    case 'auth/user-disabled':
      return 'This account has been disabled.';
    case 'auth/invalid-credential':
    case 'auth/wrong-password':
    case 'auth/user-not-found':
      return 'Email or password is incorrect.';
    case 'auth/too-many-requests':
      return 'Too many attempts. Try again in a few minutes.';
    case 'auth/network-request-failed':
      return 'Network error. Check your connection and try again.';
    default:
      return error instanceof Error
        ? error.message
        : 'Something went wrong. Please try again.';
  }
}

export class NotAnAdminError extends Error {
  constructor() {
    super('This account does not have dashboard access.');
    this.name = 'NotAnAdminError';
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [admin, setAdmin] = useState<AdminProfile | null | undefined>(undefined);

  useEffect(() => {
    return onAuthStateChanged(auth, async (user) => {
      if (!user) {
        setAdmin(null);
        return;
      }
      try {
        setAdmin(await loadAdmin(user));
      } catch {
        // A rules rejection or offline read must not strand the app on the
        // splash spinner — fall back to "not signed in" and let them retry.
        setAdmin(null);
      }
    });
  }, []);

  const value = useMemo<AuthState>(
    () => ({
      admin,
      async signIn(email, password) {
        const cred = await signInWithEmailAndPassword(
          auth,
          email.trim(),
          password,
        );
        const profile = await loadAdmin(cred.user);
        if (!profile) {
          await fbSignOut(auth);
          throw new NotAnAdminError();
        }
        setAdmin(profile);
      },
      async signOut() {
        await fbSignOut(auth);
        setAdmin(null);
      },
      async resetPassword(email) {
        await sendPasswordResetEmail(auth, email.trim());
      },
      hasPermission(permission) {
        return admin?.permissions.includes(permission) ?? false;
      },
      async refreshAdmin() {
        if (auth.currentUser) setAdmin(await loadAdmin(auth.currentUser));
      },
    }),
    [admin],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
