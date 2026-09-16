#!/usr/bin/env node
/**
 * Creates the Firebase Auth account for a dashboard administrator, then
 * prints the UID and a console link for the one document you must add by hand.
 *
 *   node tools/create-admin-user.mjs <email> <password> ["Full Name"]
 *
 * Use this when you do not want to download a service-account key. It needs
 * nothing but the Web app config already in .env.local, because creating your
 * own account is something any client can do.
 *
 * It deliberately CANNOT write admins/{uid} — that document is not
 * client-writable, which is exactly what stops anyone who finds this console
 * from promoting themselves. Adding it is the one step that has to come from
 * someone holding project access.
 *
 * If you do have a service-account key, tools/seed-admin.mjs does both halves
 * in one go.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { initializeApp } from 'firebase/app';
import {
  createUserWithEmailAndPassword,
  getAuth,
  signInWithEmailAndPassword,
  updateProfile,
} from 'firebase/auth';

const [email, password, ...nameParts] = process.argv.slice(2);
const name = nameParts.join(' ').trim() || email?.split('@')[0] || 'Administrator';

if (!email || !password) {
  console.error('Usage: node tools/create-admin-user.mjs <email> <password> ["Full Name"]');
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

let uid;
let created = false;
try {
  const cred = await createUserWithEmailAndPassword(auth, email, password);
  uid = cred.user.uid;
  created = true;
  await updateProfile(cred.user, { displayName: name });
} catch (error) {
  if (error.code !== 'auth/email-already-in-use') {
    console.error(`Could not create the account: ${error.code}`);
    if (error.code === 'auth/operation-not-allowed') {
      console.error('Enable Authentication -> Sign-in method -> Email/Password first.');
    }
    if (error.code === 'auth/weak-password') {
      console.error('Firebase requires at least 6 characters.');
    }
    process.exit(1);
  }
  // Already exists — sign in to recover the UID so a re-run is still useful.
  try {
    const cred = await signInWithEmailAndPassword(auth, email, password);
    uid = cred.user.uid;
  } catch {
    console.error(
      `${email} already has an account, but that password does not match it.\n` +
        'Reset it under Authentication -> Users, or pass the correct one.',
    );
    process.exit(1);
  }
}

const project = env.VITE_FIREBASE_PROJECT_ID;

console.log(`${created ? 'Created' : 'Found existing'} auth account for ${email}`);
console.log(`  uid: ${uid}\n`);
console.log('One step left — add the document that grants dashboard access:');
console.log(`  https://console.firebase.google.com/project/${project}/firestore/data\n`);
console.log('  collection : admins');
console.log(`  document id: ${uid}`);
console.log(`  email      : ${email}     (string)`);
console.log(`  name       : ${name}     (string)`);
console.log('  role       : Admin     (string)\n');
console.log('Then sign in at http://localhost:5173/login');
process.exit(0);
