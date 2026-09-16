import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";
import {db, FieldValue} from "../lib/firebase";
import {REGION} from "../lib/options";
import {APNS_SECRETS} from "../lib/params";
import {
  androidTokens,
  getDevices,
  iosVoipTokens,
  pruneDeadDevices,
  sendAndroidDataMessage,
  sendVoipPush,
} from "../lib/devices";
import {CallDirection, CallStatus, isTerminal, resolveDurationSeconds, toCallLogStatus} from "../lib/callStatus";
import {RawDoc, readString} from "../lib/types";

interface HistoryContext {
  callerId: string;
  receiverId: string;
  callerName: string;
  receiverName: string;
  status: CallStatus;
  duration: number;
  startedAt: unknown;
}

function callLogEntry(
  ctx: HistoryContext,
  callId: string,
  direction: CallDirection,
): Record<string, unknown> {
  return {
    // --- existing CallLogEntry schema (lib/models/call_log_model.dart) ---
    contactId: "",
    calleeName: direction === "outgoing" ? ctx.receiverName : ctx.callerName,
    calleePhone: "",
    method: "voip",
    status: toCallLogStatus(ctx.status, direction),
    direction,
    startedAt: ctx.startedAt ?? FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    // --- VoIP extras (ignored by the existing Dart parser) ---
    callId,
    voipStatus: ctx.status,
    duration: ctx.duration,
  };
}

/**
 * Writes both participants' call-history entries and flips `historyWritten` in
 * one transaction, so repeated trigger deliveries cannot double-write.
 *
 * @return true if this invocation was the one that claimed the write.
 */
async function writeHistoryOnce(callId: string, ctx: HistoryContext): Promise<boolean> {
  const callRef = db().collection("calls").doc(callId);
  try {
    return await db().runTransaction(async (tx) => {
      const snap = await tx.get(callRef);
      if (!snap.exists) return false;
      const data = (snap.data() ?? {}) as RawDoc;
      if (data["historyWritten"] === true) return false;

      const callerLog = db().collection("users").doc(ctx.callerId).collection("call_logs").doc();
      const receiverLog = db().collection("users").doc(ctx.receiverId).collection("call_logs").doc();

      tx.set(callerLog, callLogEntry(ctx, callId, "outgoing"));
      tx.set(receiverLog, callLogEntry(ctx, callId, "incoming"));
      tx.update(callRef, {historyWritten: true});
      return true;
    });
  } catch (err) {
    logger.error("callHistory.write_failed", {
      callId,
      message: err instanceof Error ? err.message : String(err),
    });
    return false;
  }
}

/** Notifies one participant's devices that the call is over. */
async function notifyEnded(uid: string, callId: string, status: CallStatus): Promise<void> {
  const devices = await getDevices(uid);
  if (devices.length === 0) return;

  const android = androidTokens(devices);
  const voip = iosVoipTokens(devices);

  const [fcm, apns] = await Promise.all([
    sendAndroidDataMessage(android, {type: "call_ended", callId, status}),
    // iOS MUST report a call to CallKit whenever a VoIP push arrives, so the
    // app reports-and-immediately-ends when it sees ended === "true".
    sendVoipPush(voip, {callId, callType: "audio", ended: "true"}),
  ]);

  logger.info("callEnded.pushed", {
    callId,
    uid,
    status,
    androidSuccess: fcm.successCount,
    androidFailed: fcm.failureCount,
    voipSuccess: apns.successCount,
    voipFailed: apns.failureCount,
    voipSkipped: apns.skippedReason ?? null,
  });

  await pruneDeadDevices(devices, fcm.deadTokens, apns.deadVoipTokens);
}

/**
 * Fires when a call reaches a terminal status: dismisses the ringing UI on both
 * sides and records the call in each participant's history.
 */
export const onCallStatusChanged = onDocumentUpdated(
  {
    document: "calls/{callId}",
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
    retry: false,
    secrets: APNS_SECRETS,
  },
  async (event) => {
    const callId = event.params.callId;
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;
    if (!beforeSnap?.exists || !afterSnap?.exists) return;

    const before = (beforeSnap.data() ?? {}) as RawDoc;
    const after = (afterSnap.data() ?? {}) as RawDoc;

    const beforeStatus = readString(before, "status");
    const afterStatus = readString(after, "status");

    if (beforeStatus === afterStatus) return;
    if (!isTerminal(afterStatus)) return;
    if (isTerminal(beforeStatus)) {
      // Already-terminal -> terminal is never a real transition.
      logger.info("onCallStatusChanged.skipped_terminal_to_terminal", {callId, beforeStatus, afterStatus});
      return;
    }

    const callerId = readString(after, "callerId");
    const receiverId = readString(after, "receiverId");
    if (!callerId || !receiverId) {
      logger.error("onCallStatusChanged.missing_participants", {callId, callerId, receiverId});
      return;
    }

    const ctx: HistoryContext = {
      callerId,
      receiverId,
      callerName: readString(after, "callerName"),
      receiverName: readString(after, "receiverName"),
      status: afterStatus as CallStatus,
      duration: resolveDurationSeconds(after),
      startedAt: after["createdAt"] ?? null,
    };

    // Claim the work first: if another delivery already handled this call we
    // must not re-push or re-log.
    const claimed = await writeHistoryOnce(callId, ctx);
    if (!claimed) {
      logger.info("onCallStatusChanged.already_handled", {callId, afterStatus});
      return;
    }

    const targets = Array.from(new Set([callerId, receiverId]));
    await Promise.all(
      targets.map((uid) =>
        notifyEnded(uid, callId, ctx.status).catch((err) => {
          logger.error("callEnded.notify_failed", {
            callId,
            uid,
            message: err instanceof Error ? err.message : String(err),
          });
        }),
      ),
    );

    logger.info("onCallStatusChanged.done", {callId, beforeStatus, afterStatus, duration: ctx.duration});
  },
);
