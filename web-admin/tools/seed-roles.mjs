#!/usr/bin/env node
/**
 * One-time migration: creates the three built-in roles (Super Admin, Admin,
 * Support) and backfills the caller's own admins/{uid} document with
 * roleId: 'super_admin'.
 *
 *   node tools/seed-roles.mjs <email> <password>
 *
 * Run this once, signed in as the administrator who already has dashboard
 * access, before anyone opens the Administration tab. It uses the client
 * SDK — no service-account key needed — the same way
 * tools/create-admin-user.mjs does.
 *
 * WHY IT WORKS WITHOUT A KEY: firestore.rules has a self-closing bootstrap —
 * any signed-in administrator may write to roles/* and backfill their own
 * roleId ONLY until roles/super_admin exists. The moment it does, that
 * window closes forever and every write after this script has to go through
 * the normal 'administration' permission check, same as everyone else's.
 *
 * ORDER MATTERS. roles/super_admin must be written LAST — it is the doc
 * whose existence closes the bootstrap window, so anything that still needs
 * that window open (the other two roles, the roleId backfill) has to happen
 * before it.
 *
 * Safe to re-run: if roles/super_admin already exists, it exits immediately
 * without writing anything.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
import {
  doc,
  getDoc,
  getFirestore,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const [email, password] = process.argv.slice(2);
if (!email || !password) {
  console.error('Usage: node tools/seed-roles.mjs <email> <password>');
  process.exit(1);
}

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
let env;
try {
  env = Object.fromEntries(
    readFileSync(join(root, '.env.local'), 'utf8')
      .split('\n')
      .filter((line) => line.startsWith('VITE_'))
      .map((line) => {
        const index = line.indexOf('=');
        return [line.slice(0, index).trim(), line.slice(index + 1).trim()];
      }),
  );
} catch {
  console.error('Could not read web-admin/.env.local — copy .env.example and fill it in first.');
  process.exit(1);
}

const app = initializeApp({
  apiKey: env.VITE_FIREBASE_API_KEY,
  authDomain: env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: env.VITE_FIREBASE_APP_ID,
});
const auth = getAuth(app);
const db = getFirestore(app);

const cred = await signInWithEmailAndPassword(auth, email, password);
console.log(`Signed in as ${email} (uid: ${cred.user.uid})`);

const superAdminRef = doc(db, 'roles', 'super_admin');
if ((await getDoc(superAdminRef)).exists()) {
  console.log('\nroles/super_admin already exists — roles are already seeded.');
  console.log('Use the Administration tab in the dashboard to manage roles from here.');
  process.exit(0);
}

try {
  // 1 & 2 — the two roles that do NOT close the bootstrap window.
  await setDoc(doc(db, 'roles', 'admin'), {
    name: 'Admin',
    permissions: ['dashboard', 'users', 'support'],
    isSystem: false,
    createdAt: serverTimestamp(),
  });
  console.log('Created roles/admin');

  await setDoc(doc(db, 'roles', 'support'), {
    name: 'Support',
    permissions: ['support'],
    isSystem: false,
    createdAt: serverTimestamp(),
  });
  console.log('Created roles/support');

  // 3 — backfill this account's own roleId while the window is still open.
  await updateDoc(doc(db, 'admins', cred.user.uid), { roleId: 'super_admin' });
  console.log(`Set roleId: 'super_admin' on admins/${cred.user.uid}`);

  // 4 — LAST. This is the write that closes the bootstrap window for good.
  await setDoc(superAdminRef, {
    name: 'Super Admin',
    permissions: ['dashboard', 'users', 'support', 'administration'],
    isSystem: true,
    createdAt: serverTimestamp(),
  });
  console.log('Created roles/super_admin — bootstrap window is now closed.');
} catch (error) {
  console.error('\nSeeding failed partway through:', error.code || error.message);
  console.error(
    'This is safe to re-run — each step above only writes a document that\n' +
      "doesn't exist yet, and re-running skips anything already in place\n" +
      '(except it will try to `setDoc` roles/admin and roles/support again,\n' +
      'which overwrites them with the same values — harmless).',
  );
  process.exit(1);
}

console.log(`\nDone. ${email} now has the Super Admin role.`);
console.log('Sign in to the dashboard and open Administration to manage roles and administrators.');
process.exit(0);
