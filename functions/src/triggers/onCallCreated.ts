import {onDocumentCreated} from "firebase-functions/v2/firestore";
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
import {RawDoc, readNullableString, readString, readStringArray} from "../lib/types";

interface ValidationFailure {
  ok: false;
  reason: string;
}

interface ValidationSuccess {
  ok: true;
  callerId: string;
  receiverId: string;
  callerName: string;
  callerPhotoUrl: string;
}

type Validation = ValidationFailure | ValidationSuccess;

function validate(callId: string, data: RawDoc): Validation {
  const docCallId = readString(data, "callId");
  if (docCallId !== callId) {
    return {ok: false, reason: `callId field "${docCallId}" does not match document id`};
  }
  const callerId = readString(data, "callerId");
  const receiverId = readString(data, "receiverId");
  if (!callerId) return {ok: false, reason: "callerId missing"};
  if (!receiverId) return {ok: false, reason: "receiverId missing"};
  if (callerId === receiverId) return {ok: false, reason: "callerId equals receiverId"};

  const participants = readStringArray(data, "participants");
  if (participants.length !== 2 || participants[0] !== callerId || participants[1] !== receiverId) {
    return {ok: false, reason: "participants must be exactly [callerId, receiverId]"};
  }
  if (readString(data, "type") !== "audio") {
    return {ok: false, reason: "type must be \"audio\""};
  }

  return {
    ok: true,
    callerId,
    receiverId,
    callerName: readString(data, "callerName"),
    callerPhotoUrl: readNullableString(data, "callerPhotoUrl") ?? "",
  };
}

/** Moves a still-live call to a terminal failure state. Never throws. */
async function failCall(callId: string, endReason: string): Promise<void> {
  const ref = db().collection("calls").doc(callId);
  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const status = readString((snap.data() ?? {}) as RawDoc, "status");
      if (status !== "initiating" && status !== "ringing") return;
      tx.update(ref, {
        status: "failed",
        endReason,
        endedAt: FieldValue.serverTimestamp(),
      });
    });
    logger.warn("call.failed", {callId, endReason});
  } catch (err) {
    logger.error("call.fail_write_error", {
      callId,
      endReason,
      message: err instanceof Error ? err.message : String(err),
    });
  }
}

/** initiating -> ringing, only if nobody else moved the call meanwhile. */
async function markRinging(callId: string): Promise<boolean> {
  const ref = db().collection("calls").doc(callId);
  try {
    return await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      const status = readString((snap.data() ?? {}) as RawDoc, "status");
      if (status !== "initiating") return false;
      tx.update(ref, {status: "ringing", ringingAt: FieldValue.serverTimestamp()});
      return true;
    });
  } catch (err) {
    logger.error("call.ringing_transition_failed", {
      callId,
      message: err instanceof Error ? err.message : String(err),
    });
    return false;
  }
}

/**
 * Fans an incoming call out to every device the receiver has registered:
 * a high-priority data-only FCM message on Android, a PushKit VoIP push on iOS.
 */
export const onCallCreated = onDocumentCreated(
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
    const snap = event.data;
    if (!snap || !snap.exists) {
      logger.warn("onCallCreated.no_snapshot", {callId});
      return;
    }

    const data = (snap.data() ?? {}) as RawDoc;

    const validation = validate(callId, data);
    if (!validation.ok) {
      logger.error("onCallCreated.invalid_document", {callId, reason: validation.reason});
      await failCall(callId, "invalid_call");
      return;
    }

    const status = readString(data, "status");
    if (status !== "initiating") {
      logger.info("onCallCreated.skipped_non_initiating", {callId, status});
      return;
    }

    const {callerId, receiverId, callerName, callerPhotoUrl} = validation;

    const devices = await getDevices(receiverId);
    if (devices.length === 0) {
      logger.warn("onCallCreated.receiver_has_no_devices", {callId, receiverId});
      await failCall(callId, "receiver_unavailable");
      return;
    }

    const android = androidTokens(devices);
    const voip = iosVoipTokens(devices);

    if (android.length === 0 && voip.length === 0) {
      logger.warn("onCallCreated.receiver_has_no_tokens", {callId, receiverId, devices: devices.length});
      await failCall(callId, "receiver_unavailable");
      return;
    }

    // Every FCM data value must be a string.
    const androidData: Record<string, string> = {
      type: "incoming_call",
      callId,
      callerId,
      callerName,
      callerPhotoUrl,
      callType: "audio",
    };

    const voipPayload: Record<string, string> = {
      callId,
      callerId,
      callerName,
      callerPhotoUrl,
      callType: "audio",
    };

    const [fcm, apns] = await Promise.all([
      sendAndroidDataMessage(android, androidData),
      sendVoipPush(voip, voipPayload),
    ]);

    logger.info("onCallCreated.pushed", {
      callId,
      receiverId,
      androidAttempted: fcm.attempted,
      androidSuccess: fcm.successCount,
      androidFailed: fcm.failureCount,
      voipAttempted: apns.attempted,
      voipSuccess: apns.successCount,
      voipFailed: apns.failureCount,
      voipSkipped: apns.skippedReason ?? null,
    });

    await pruneDeadDevices(devices, fcm.deadTokens, apns.deadVoipTokens);

    const anyDelivered = fcm.successCount > 0 || apns.successCount > 0;
    const apnsSkipped = apns.skippedReason !== undefined;
    // If nothing could be delivered AND we did not merely skip iOS because of
    // missing config, the receiver is genuinely unreachable.
    if (!anyDelivered && !apnsSkipped && android.length + voip.length > 0) {
      logger.warn("onCallCreated.no_device_reachable", {callId, receiverId});
      await failCall(callId, "receiver_unavailable");
      return;
    }

    const moved = await markRinging(callId);
    logger.info("onCallCreated.done", {callId, ringing: moved});
  },
);
