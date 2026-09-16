/**
 * Firestore's raw errors are unhelpful to whoever is standing in front of the
 * screen. The two that actually happen during setup — rules not deployed yet,
 * and a collection-group index missing — get an instruction instead of a code.
 */
export function firestoreErrorMessage(error: unknown, what = 'this data'): string {
  const code =
    typeof error === 'object' && error && 'code' in error
      ? String((error as { code: unknown }).code)
      : '';
  const message = error instanceof Error ? error.message : '';

  if (code === 'permission-denied' || code === 'firestore/permission-denied') {
    return `Not allowed to read ${what}. Deploy the updated rules with \`firebase deploy --only firestore:rules\`, and check this account has an admins/{uid} document.`;
  }

  if (code === 'failed-precondition' && message.includes('index')) {
    const link = message.match(/https:\/\/\S+/)?.[0];
    return link
      ? `Firestore needs an index for this query. Create it here: ${link}`
      : 'Firestore needs a composite index for this query — run `firebase deploy --only firestore:indexes`.';
  }

  if (code === 'unavailable') {
    return 'Cannot reach Firestore. Check your connection and try again.';
  }

  if (code === 'resource-exhausted') {
    return 'Firestore quota exceeded for this project. Try again later.';
  }

  return message || `Could not load ${what}.`;
}
