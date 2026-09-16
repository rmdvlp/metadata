package com.example.metadata

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Handles Answer / Decline tapped directly on the incoming-call notification.
 *
 * Answer always brings the app to the front — there is nowhere else to
 * conduct a call. Decline tries hard *not* to: if the process is already
 * alive the rejection is relayed straight to Dart and the app stays in the
 * background, which is what a user expects from declining a call.
 *
 * Known trade-off: when the process is not running, declining has to start it
 * so the Dart layer can authenticate to Firestore and write the `rejected`
 * status. A broadcast receiver has no Firebase credentials of its own, so the
 * alternative would be leaving the caller ringing until the backend's
 * 60-second sweep marks the call missed. Starting briefly and resolving the
 * call correctly is the better failure mode; the app is finished immediately
 * afterwards by Dart having nothing to present.
 */
class VoipCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra(VoipCallNotification.EXTRA_CALL_ID) ?: return
        val callerName = intent.getStringExtra(VoipCallNotification.EXTRA_CALLER_NAME) ?: ""
        val callerId = intent.getStringExtra(VoipCallNotification.EXTRA_CALLER_ID) ?: ""

        VoipCallNotification.cancelIncoming(context)

        when (intent.action) {
            VoipCallNotification.ACTION_ANSWER -> {
                VoipBridge.setPendingAction(callId, "answer")
                launchApp(context, callId, callerName, callerId, "answer")
            }

            VoipCallNotification.ACTION_DECLINE -> {
                if (VoipBridge.isAppInForeground) {
                    VoipBridge.sendAction("decline", callId)
                } else {
                    VoipBridge.setPendingAction(callId, "decline")
                    launchApp(context, callId, callerName, callerId, "decline")
                }
            }

            else -> Log.w(TAG, "Unhandled VoIP notification action: ${intent.action}")
        }
    }

    private fun launchApp(
        context: Context,
        callId: String,
        callerName: String,
        callerId: String,
        action: String,
    ) {
        try {
            context.startActivity(
                VoipCallNotification.launchIntent(context, callId, callerName, callerId, action)
            )
        } catch (e: Exception) {
            Log.e(TAG, "Could not launch app for VoIP action $action", e)
        }
    }

    private companion object {
        const val TAG = "VoipCallActionReceiver"
    }
}
