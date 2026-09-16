import { deleteApp, initializeApp } from 'firebase/app';
import { getAuth, updateProfile } from 'firebase/auth';
import { firebaseConfig } from './firebase';

/**
 * Creates a new administrator's Auth account without disturbing the session
 * of the super admin doing the creating.
 *
 * The Firebase client SDK has no "create a user but stay signed in as
 * myself" call — `createUserWithEmailAndPassword` always switches the app's
 * current user to the one it just created. The standard workaround is a
 * second, temporary `FirebaseApp` instance pointed at the same project: it
 * gets its own isolated Auth state, so creating a user there never touches
 * the primary `auth` the rest of the console is signed in on.
 *
 * Returns the new user's uid. The temporary app is always torn down, even on
 * failure, so a run of these never accumulates named app instances.
 */
export async function createAuthAccount(input: {
  email: string;
  password: string;
  name: string;
}): Promise<string> {
  const { createUserWithEmailAndPassword } = await import('firebase/auth');
  const secondaryApp = initializeApp(firebaseConfig, `secondary-${Date.now()}`);
  try {
    const secondaryAuth = getAuth(secondaryApp);
    const cred = await createUserWithEmailAndPassword(
      secondaryAuth,
      input.email,
      input.password,
    );
    await updateProfile(cred.user, { displayName: input.name });
    return cred.user.uid;
  } finally {
    await deleteApp(secondaryApp);
  }
}
