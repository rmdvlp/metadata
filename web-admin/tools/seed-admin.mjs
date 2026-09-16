#!/usr/bin/env node
/**
 * Creates (or updates) a dashboard administrator for the Context ID project.
 *
 *   node tools/seed-admin.mjs <email> <password> ["Full Name"]
 *
 * Runs with the Admin SDK, which bypasses Firestore rules — that is the point.
 * `admins/{uid}` is deliberately not client-writable, so nobody can promote
 * themselves through the console; only this script or a Firebase-console edit
 * can grant access.
 *
 * Credentials, in the order the Admin SDK looks for them:
 *   1. GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *      (Firebase console -> Project settings -> Service accounts ->
 *       "Generate new private key". Keep the file out of git — .gitignore
 *       already covers web-admin/serviceAccount.json.)
 *   2. `gcloud auth application-default login`
 *
 * If you would rather not download a key, do it by hand instead:
 *   a. Authentication -> Users -> Add user (email + password).
 *   b. Firestore -> start a collection `admins`, document id = that user's
 *      UID, fields: email (string), name (string), role (string) = "Admin".
 */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const PROJECT_ID = 'metadata-64577';

const [email, password, ...nameParts] = process.argv.slice(2);
const name = nameParts.join(' ').trim() || email?.split('@')[0] || 'Administrator';

if (!email || !password) {
  console.error('Usage: node tools/seed-admin.mjs <email> <password> ["Full Name"]');
  process.exit(1);
}

if (password.length < 6) {
  console.error('Firebase requires a password of at least 6 characters.');
  process.exit(1);
}

let app;
try {
  app = initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
} catch (error) {
  console.error(
    'Could not load Google credentials.\n' +
      'Set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON file, or run\n' +
      '`gcloud auth application-default login`. See the header of this file.\n',
  );
  console.error(error.message);
  process.exit(1);
}

const auth = getAuth(app);
const db = getFirestore(app);

/** Reuses the account if the address already exists, so re-runs are safe. */
async function ensureUser() {
  try {
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid, { password, displayName: name });
    return { uid: existing.uid, created: false };
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    const created = await auth.createUser({
      email,
      password,
      displayName: name,
      emailVerified: true,
    });
    return { uid: created.uid, created: true };
  }
}

try {
  const { uid, created } = await ensureUser();

  await db.collection('admins').doc(uid).set(
    {
      email,
      name,
      role: 'Admin',
      updatedAt: FieldValue.serverTimestamp(),
      ...(created ? { createdAt: FieldValue.serverTimestamp() } : {}),
    },
    { merge: true },
  );

  console.log(`${created ? 'Created' : 'Updated'} admin account`);
  console.log(`  email : ${email}`);
  console.log(`  uid   : ${uid}`);
  console.log(`  doc   : admins/${uid}`);
  console.log('\nMake sure Email/Password is enabled under Authentication -> Sign-in method.');
  process.exit(0);
} catch (error) {
  console.error('Failed to seed the admin account:');
  console.error(`  ${error.code ?? ''} ${error.message}`);
  process.exit(1);
}
