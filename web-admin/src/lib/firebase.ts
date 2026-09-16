import { initializeApp, type FirebaseApp, type FirebaseOptions } from 'firebase/app';
import { getAuth, connectAuthEmulator, type Auth } from 'firebase/auth';
import {
  getFirestore,
  connectFirestoreEmulator,
  type Firestore,
} from 'firebase/firestore';

/**
 * Same Firebase project as the Context ID mobile app (metadata-64577) — the
 * dashboard reads the very documents the app writes. Only the Web App
 * registration differs, which is why the API key and app id come from
 * `.env.local` rather than being hard-coded like `lib/firebase_options.dart`.
 *
 * A missing value is reported through `configError` instead of thrown: a throw
 * at import time takes down the whole module graph and leaves a blank page,
 * whereas this lets `App` render setup instructions naming the exact vars.
 */
function readConfig(): { config: FirebaseOptions; error: string | null } {
  const env = import.meta.env;
  const entries: Array<[keyof FirebaseOptions, string | undefined, string]> = [
    ['apiKey', env.VITE_FIREBASE_API_KEY, 'VITE_FIREBASE_API_KEY'],
    ['authDomain', env.VITE_FIREBASE_AUTH_DOMAIN, 'VITE_FIREBASE_AUTH_DOMAIN'],
    ['projectId', env.VITE_FIREBASE_PROJECT_ID, 'VITE_FIREBASE_PROJECT_ID'],
    ['storageBucket', env.VITE_FIREBASE_STORAGE_BUCKET, 'VITE_FIREBASE_STORAGE_BUCKET'],
    [
      'messagingSenderId',
      env.VITE_FIREBASE_MESSAGING_SENDER_ID,
      'VITE_FIREBASE_MESSAGING_SENDER_ID',
    ],
    ['appId', env.VITE_FIREBASE_APP_ID, 'VITE_FIREBASE_APP_ID'],
  ];

  const config: FirebaseOptions = {};
  const missing: string[] = [];

  for (const [key, value, envName] of entries) {
    if (!value || value.startsWith('TODO')) missing.push(envName);
    else config[key] = value;
  }

  return {
    config,
    error:
      missing.length > 0
        ? `Missing or unset in web-admin/.env.local: ${missing.join(', ')}`
        : null,
  };
}

const { config, error } = readConfig();

export const configError = error;

// Exposed so a second, throwaway app instance can be spun up with the same
// project — see lib/secondaryAuth.ts. Creating a new administrator's Auth
// account on the *primary* `auth` would sign the current admin out, since the
// client SDK always switches to whichever user it just created.
export const firebaseConfig: FirebaseOptions = config;

// Only constructed once the config is complete. Every consumer sits behind
// the `configError` gate in `App`, so these are never touched when null.
export const firebaseApp: FirebaseApp = error
  ? (null as unknown as FirebaseApp)
  : initializeApp(config);

export const auth: Auth = error ? (null as unknown as Auth) : getAuth(firebaseApp);
export const db: Firestore = error
  ? (null as unknown as Firestore)
  : getFirestore(firebaseApp);

if (!error && import.meta.env.VITE_USE_FIREBASE_EMULATOR === 'true') {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
}
