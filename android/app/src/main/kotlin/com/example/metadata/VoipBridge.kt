package com.example.metadata

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Process-wide relay between the native VoIP pieces (FCM service, call
 * notification, foreground service) and Dart's `VoipPlatformService`.
 *
 * Deliberately separate from [IncomingCallBridge], which relays *cellular*
 * call state. The two features observe different things — one watches the
 * carrier's calls, this one is the call — and sharing a channel would make
 * both harder to reason about.
 *
 * Everything here is static because the pieces that produce these events are
 * created by the system (a broadcast receiver, an FCM service), never by us,
 * and in a process that may have been started purely to deliver a push.
 */
object VoipBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null

    /**
     * Set by [MainActivity]. When the Flutter UI is on screen the incoming
     * call is presented by the Flutter route, so the native full-screen
     * notification must be suppressed — otherwise the user gets a call
     * notification stacked on top of the call screen.
     */
    @Volatile
    var isAppInForeground: Boolean = false

    /**
     * An answer/decline the user performed before Dart existed.
     *
     * Tapping "Answer" on a full-screen call notification while the app is
     * terminated starts the process from scratch; the event has nowhere to go
     * until Flutter attaches. Parking it here (and re-reading it from the
     * launch intent, in case the process was recreated) is what makes
     * answering from a killed app work.
     */
    @Volatile
    private var pendingCallId: String? = null

    @Volatile
    private var pendingAction: String? = null

    fun attach(sink: EventChannel.EventSink) {
        eventSink = sink
    }

    fun detach() {
        eventSink = null
    }

    fun setPendingAction(callId: String, action: String) {
        pendingCallId = callId
        pendingAction = action
    }

    /** Drained exactly once by Dart at start-up. */
    fun consumePendingAction(): Map<String, String>? {
        val callId = pendingCallId ?: return null
        val action = pendingAction ?: return null
        pendingCallId = null
        pendingAction = null
        return mapOf("callId" to callId, "action" to action)
    }

    fun hasPendingAction(): Boolean = pendingCallId != null

    /**
     * Emits to Dart if it is listening, otherwise parks the action so it is
     * not lost. Always hops to the main thread: EventChannel sinks must not
     * be touched from an FCM or broadcast-receiver thread.
     */
    fun send(event: Map<String, Any?>) {
        mainHandler.post {
            val sink = eventSink
            if (sink != null) {
                sink.success(event)
            } else {
                val callId = event["callId"] as? String
                val action = event["event"] as? String
                if (callId != null && (action == "answer" || action == "decline")) {
                    setPendingAction(callId, action)
                }
            }
        }
    }

    fun sendAction(action: String, callId: String) {
        send(mapOf("event" to action, "callId" to callId))
    }

    fun sendIncomingPush(data: Map<String, String>) {
        send(
            mapOf(
                "event" to "incomingPush",
                "callId" to data[VoipCallNotification.EXTRA_CALL_ID],
                "callerId" to data["callerId"],
                "callerName" to data["callerName"],
                "callerPhotoUrl" to data["callerPhotoUrl"],
            )
        )
    }
}
