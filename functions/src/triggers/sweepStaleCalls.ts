import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions/v2";
import {DocumentReference, Query, QueryDocumentSnapshot, Timestamp} from "firebase-admin/firestore";
import {db, FieldValue} from "../lib/firebase";
import {REGION} from "../lib/options";
import {NEGOTIATING_STATUSES, PRE_ANSWER_STATUSES} from "../lib/callStatus";
import {RawDoc} from "../lib/types";

/** A call nobody answered within this window is a missed call. */
const RING_TIMEOUT_MS = 60_000;

/** Answered but never actually connected within this window -> failed. */
const CONNECT_TIMEOUT_MS = 2 * 60_000;

/** Firestore allows 500 writes per batch; stay under it. */
const BATCH_SIZE = 400;

/** Upper bound per sweep so one bad window cannot blow the timeout. */
const QUERY_LIMIT = 2000;

interface Transition {
  ref: DocumentReference;
  status: "missed" | "failed";
  endReason: string;
}

async function fetchStale(
  statuses: readonly string[],
  cutoff: Timestamp,
  keep: (data: RawDoc) => boolean,
): Promise<QueryDocumentSnapshot[]> {
  try {
    const query: Query = db()
      .collection("calls")
      .where("status", "in", statuses as string[])
      .where("createdAt", "<", cutoff)
      .orderBy("createdAt", "asc")
      .limit(QUERY_LIMIT);
    const snap = await query.get();
    return snap.docs.filter((doc) => keep((doc.data() ?? {}) as RawDoc));
  } catch (err) {
    logger.error("sweepStaleCalls.query_failed", {
      statuses,
      message: err instanceof Error ? err.message : String(err),
      hint: "Requires the composite index calls(status ASC, createdAt ASC).",
    });
    return [];
  }
}

async function commitTransitions(transitions: Transition[]): Promise<number> {
  let written = 0;
  for (let i = 0; i < transitions.length; i += BATCH_SIZE) {
    const chunk = transitions.slice(i, i + BATCH_SIZE);
    const batch = db().batch();
    for (const item of chunk) {
      batch.update(item.ref, {
        status: item.status,
        endReason: item.endReason,
        endedAt: FieldValue.serverTimestamp(),
      });
    }
    try {
      await batch.commit();
      written += chunk.length;
    } catch (err) {
      logger.error("sweepStaleCalls.batch_failed", {
        size: chunk.length,
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }
  return written;
}

/**
 * Safety net for calls whose client died mid-flow. Terminal transitions written
 * here are picked up by onCallStatusChanged, which handles pushes and history.
 */
export const sweepStaleCalls = onSchedule(
  {
    schedule: "every 1 minutes",
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 120,
    retryCount: 0,
  },
  async () => {
    const now = Date.now();
    const ringCutoff = Timestamp.fromMillis(now - RING_TIMEOUT_MS);
    const connectCutoff = Timestamp.fromMillis(now - CONNECT_TIMEOUT_MS);

    const transitions: Transition[] = [];

    // 1) Never answered.
    const unanswered = await fetchStale(PRE_ANSWER_STATUSES, ringCutoff, () => true);
    for (const doc of unanswered) {
      transitions.push({ref: doc.ref, status: "missed", endReason: "timeout"});
    }

    // 2) Answered but media never came up. `connectedAt == null` cannot be
    //    combined with the other filters in a single query, so filter here.
    const stalled = await fetchStale(
      NEGOTIATING_STATUSES,
      connectCutoff,
      (data) => data["connectedAt"] === null || data["connectedAt"] === undefined,
    );
    for (const doc of stalled) {
      transitions.push({ref: doc.ref, status: "failed", endReason: "connect_timeout"});
    }

    if (transitions.length === 0) {
      logger.debug("sweepStaleCalls.nothing_to_do");
      return;
    }

    const written = await commitTransitions(transitions);
    logger.info("sweepStaleCalls.done", {
      unanswered: unanswered.length,
      stalled: stalled.length,
      written,
      sample: transitions.slice(0, 5).map((t) => `${t.ref.id}:${t.status}`),
    });
  },
);
