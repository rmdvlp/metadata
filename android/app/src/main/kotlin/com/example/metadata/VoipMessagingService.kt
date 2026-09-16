package com.example.metadata

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Turns an incoming-call push into a ringing phone, in native code, before
 * Flutter is involved.
 *
 * Extends the firebase_messaging plugin's own service rather than replacing
 * it so token refresh and every non-call message keep their existing
 * behaviour. The plugin does its real work in a separate broadcast receiver
 * (`FlutterFirebaseMessagingReceiver`), which still runs independently — this
 * subclass only adds the call-specific native path.
 *
 * Why native at all: when the app is terminated, the plugin's path spins up a
 * background Dart isolate to run `firebaseMessagingBackgroundHandler`. That
 * takes long enough that a caller can give up before the phone ever rings.
 * Posting the full-screen notification here happens within milliseconds of
 * the push landing. The Dart background handler explicitly ignores call
 * payloads so the two paths never both fire.
 */
class VoipMessagingService : FlutterFirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        val data = remoteMessage.data
        val type = data["type"] ?: return
        val callId = data["callId"] ?: return

        when (type) {
            "incoming_call" -> handleIncomingCall(callId, data)
            "call_ended" -> handleCallEnded(callId)
            else -> Unit
        }
    }

    private fun handleIncomingCall(callId: String, data: Map<String, String>) {
        val callerName = data["callerName"]?.takeIf { it.isNotBlank() } ?: "Unknown caller"
        val callerId = data["callerId"] ?: ""

        if (VoipBridge.isAppInForeground) {
            // The Flutter incoming-call route is already being presented from
            // the Firestore listener. A second, native call notification on
            // top of it would be a duplicate.
            Log.d(TAG, "App is foreground; leaving call $callId to the Flutter UI")
            VoipBridge.sendIncomingPush(data)
            return
        }

        Log.d(TAG, "Posting full-screen incoming call notification for $callId")
        VoipCallNotification.showIncoming(
            context = applicationContext,
            callId = callId,
            callerName = callerName,
            callerId = callerId,
        )
        VoipBridge.sendIncomingPush(data)
    }

    private fun handleCallEnded(callId: String) {
        Log.d(TAG, "Call $callId ended remotely; clearing native call UI")
        VoipCallNotification.cancelIncoming(applicationContext)
        VoipCallForegroundService.stop(applicationContext)
        VoipBridge.sendAction("end", callId)
    }

    private companion object {
        const val TAG = "VoipMessagingService"
    }
}
