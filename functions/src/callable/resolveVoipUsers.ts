import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions/v2";
import {db} from "../lib/firebase";
import {isValidPhoneIndexId, normalizePhoneForMatching} from "../lib/phone";
import {REGION} from "../lib/options";
import {RawDoc, readNullableString, readString} from "../lib/types";

const MAX_PHONE_NUMBERS = 200;
/** Firestore getAll() accepts a large but finite argument list. */
const GET_ALL_CHUNK = 100;

export interface ResolvedUser {
  uid: string;
  displayName: string;
  photoUrl: string | null;
}

export interface ResolveVoipUsersResponse {
  matches: Record<string, ResolvedUser>;
}

/**
 * Resolves phone numbers to VoIP-capable users.
 *
 * Clients have no read access to `phone_index` or to other users' documents,
 * so this callable is the only supported lookup path. Keys in the response are
 * the ORIGINAL strings the client sent, so it can map results back directly.
 */
export const resolveVoipUsers = onCall<{phoneNumbers?: unknown}, Promise<ResolveVoipUsersResponse>>(
  {region: REGION, memory: "256MiB", timeoutSeconds: 60, cors: true},
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const raw = request.data?.phoneNumbers;
    if (!Array.isArray(raw)) {
      throw new HttpsError("invalid-argument", "phoneNumbers must be an array of strings.");
    }
    if (raw.length > MAX_PHONE_NUMBERS) {
      throw new HttpsError(
        "invalid-argument",
        `phoneNumbers may contain at most ${MAX_PHONE_NUMBERS} entries (received ${raw.length}).`,
      );
    }

    // original string -> normalized id (many originals can share one id)
    const originalToNormalized = new Map<string, string>();
    for (const entry of raw) {
      if (typeof entry !== "string") continue;
      const normalized = normalizePhoneForMatching(entry);
      if (!isValidPhoneIndexId(normalized)) continue;
      originalToNormalized.set(entry, normalized);
    }

    const uniqueNormalized = Array.from(new Set(originalToNormalized.values()));
    if (uniqueNormalized.length === 0) {
      return {matches: {}};
    }

    const resolved = new Map<string, ResolvedUser>();
    const collection = db().collection("phone_index");

    try {
      for (let i = 0; i < uniqueNormalized.length; i += GET_ALL_CHUNK) {
        const chunk = uniqueNormalized.slice(i, i + GET_ALL_CHUNK);
        const refs = chunk.map((id) => collection.doc(id));
        const snapshots = await db().getAll(...refs);
        for (const snap of snapshots) {
          if (!snap.exists) continue;
          const data = (snap.data() ?? {}) as RawDoc;
          const uid = readString(data, "uid");
          if (!uid || uid === callerUid) continue; // never resolve to yourself
          resolved.set(snap.id, {
            uid,
            displayName: readString(data, "displayName"),
            photoUrl: readNullableString(data, "photoUrl"),
          });
        }
      }
    } catch (err) {
      logger.error("resolveVoipUsers.lookup_failed", {
        callerUid,
        requested: uniqueNormalized.length,
        message: err instanceof Error ? err.message : String(err),
      });
      throw new HttpsError("internal", "Unable to resolve contacts right now.");
    }

    const matches: Record<string, ResolvedUser> = {};
    for (const [original, normalized] of originalToNormalized.entries()) {
      const match = resolved.get(normalized);
      if (match) matches[original] = match;
    }

    logger.info("resolveVoipUsers.done", {
      callerUid,
      requested: raw.length,
      normalized: uniqueNormalized.length,
      matched: Object.keys(matches).length,
    });

    return {matches};
  },
);
