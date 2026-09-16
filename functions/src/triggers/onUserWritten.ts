import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";
import {db, FieldValue} from "../lib/firebase";
import {isValidPhoneIndexId, normalizePhoneForMatching} from "../lib/phone";
import {REGION} from "../lib/options";
import {RawDoc, readNullableString, readString} from "../lib/types";

const PHONE_INDEX = "phone_index";

interface IndexPayload {
  uid: string;
  displayName: string;
  photoUrl: string | null;
}

function payloadOf(uid: string, data: RawDoc): IndexPayload {
  return {
    uid,
    displayName: readString(data, "displayName"),
    photoUrl: readNullableString(data, "photoUrl"),
  };
}

function samePayload(a: IndexPayload, b: IndexPayload): boolean {
  return a.uid === b.uid && a.displayName === b.displayName && a.photoUrl === b.photoUrl;
}

/**
 * Claims (or refreshes) `phone_index/{normalizedPhone}` for this uid.
 * Never steals an entry owned by a different uid.
 */
async function upsertIndex(normalized: string, payload: IndexPayload): Promise<void> {
  const ref = db().collection(PHONE_INDEX).doc(normalized);
  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) {
        const ownerUid = readString((snap.data() ?? {}) as RawDoc, "uid");
        if (ownerUid && ownerUid !== payload.uid) {
          logger.warn("phoneIndex.owned_by_other_uid", {
            normalized,
            ownerUid,
            requestingUid: payload.uid,
          });
          return;
        }
        const current = payloadOf(ownerUid || payload.uid, (snap.data() ?? {}) as RawDoc);
        if (samePayload(current, payload)) return;
      }
      tx.set(
        ref,
        {
          uid: payload.uid,
          displayName: payload.displayName,
          photoUrl: payload.photoUrl,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });
  } catch (err) {
    logger.error("phoneIndex.upsert_failed", {
      normalized,
      uid: payload.uid,
      message: err instanceof Error ? err.message : String(err),
    });
  }
}

/** Deletes a stale index entry, but only if this uid still owns it. */
async function releaseIndex(normalized: string, uid: string): Promise<void> {
  const ref = db().collection(PHONE_INDEX).doc(normalized);
  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const ownerUid = readString((snap.data() ?? {}) as RawDoc, "uid");
      if (ownerUid !== uid) {
        logger.info("phoneIndex.release_skipped_other_owner", {normalized, ownerUid, uid});
        return;
      }
      tx.delete(ref);
    });
  } catch (err) {
    logger.error("phoneIndex.release_failed", {
      normalized,
      uid,
      message: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Keeps `phone_index/{normalizedPhone}` in sync with `users/{uid}`.
 *
 * The index exists so `resolveVoipUsers` can answer "who has this number?"
 * without granting clients read access to other users' documents.
 */
export const onUserWritten = onDocumentWritten(
  {document: "users/{uid}", region: REGION, memory: "256MiB", timeoutSeconds: 60, retry: false},
  async (event) => {
    const uid = event.params.uid;
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;

    const before = beforeSnap?.exists ? ((beforeSnap.data() ?? {}) as RawDoc) : null;
    const after = afterSnap?.exists ? ((afterSnap.data() ?? {}) as RawDoc) : null;

    if (!before && !after) return;

    const beforePhone = before ? normalizePhoneForMatching(readString(before, "phoneNumber")) : "";
    const afterPhone = after ? normalizePhoneForMatching(readString(after, "phoneNumber")) : "";

    const hasBeforeIndex = isValidPhoneIndexId(beforePhone);
    const hasAfterIndex = isValidPhoneIndexId(afterPhone);

    // Case 1: user deleted -> drop the index entry we own.
    if (!after) {
      if (hasBeforeIndex) {
        await releaseIndex(beforePhone, uid);
        logger.info("phoneIndex.user_deleted", {uid, normalized: beforePhone});
      }
      return;
    }

    const nextPayload = payloadOf(uid, after);

    // Case 2: phone number changed (or was removed) -> release the old entry.
    if (hasBeforeIndex && beforePhone !== afterPhone) {
      await releaseIndex(beforePhone, uid);
    }

    if (!hasAfterIndex) {
      if (readString(after, "phoneNumber")) {
        logger.warn("phoneIndex.unindexable_phone", {uid, normalized: afterPhone});
      }
      return;
    }

    // Case 3: nothing indexable changed -> no write. Keeps the trigger from
    // amplifying unrelated user-doc writes (lastActiveAt updates are frequent).
    if (before && beforePhone === afterPhone) {
      const prevPayload = payloadOf(uid, before);
      if (samePayload(prevPayload, nextPayload)) return;
    }

    await upsertIndex(afterPhone, nextPayload);
    logger.info("phoneIndex.upserted", {uid, normalized: afterPhone});
  },
);
