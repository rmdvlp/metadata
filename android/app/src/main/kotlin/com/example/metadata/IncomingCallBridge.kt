package com.example.metadata

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
import io.flutter.plugin.common.EventChannel

/**
 * In-process bridge between native call-state sources
 * (CallScreeningServiceImpl, the phone-state BroadcastReceiver this object
 * registers) and the Dart side's EventChannel listener.
 *
 * Having an EventSink attached only means the Dart isolate is alive — it
 * does NOT mean MainActivity is currently visible (the app could be
 * backgrounded with the engine still running). So whether to also show the
 * native full-screen notification is decided by [isAppInForeground], not by
 * EventSink presence: foreground already has the in-app screen visible via
 * the Dart-side push, backgrounded/killed needs the notification to bring
 * the app back in front of (alongside) the phone's native call screen.
 *
 * ## One event per real transition
 *
 * Everything downstream of here — the in-app call screen, the Recent Call
 * Logs row, the bell notification — treats an event as "something new
 * happened", so a repeated event is not harmless: it is a duplicate call log
 * row. Repeats are genuinely common, because
 * `ACTION_PHONE_STATE_CHANGED` can be delivered more than once for a single
 * transition (dual-SIM handsets especially), and telecom can screen the same
 * call twice. Every entry point below is therefore idempotent for the current
 * call, keyed off [lastEmittedState]/[connectedAtMs] rather than trusting the
 * platform to call each one once.
 */
object IncomingCallBridge {
    private const val STATE_RINGING = "ringing"
    private const val STATE_CONNECTED = "connected"
    private const val STATE_DISCONNECTED = "disconnected"

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Only one call is ever active at a time on a phone, so a single slice
    // of "what's the current call" state covers both directions.
    private var activeNumber: String? = null
    private var activeIsOutgoing: Boolean = false

    /**
     * When the current call was first observed/armed. Doubles as "is a call
     * being tracked at all" — every arming path sets it, and [reset] is the
     * only thing that clears it.
     */
    private var activeSinceMs: Long = 0L

    /**
     * When the current call actually went off-hook, or 0 if it never did.
     * Both the duration reported to Dart and the "was this ever connected"
     * distinction come from this one field.
     */
    private var connectedAtMs: Long = 0L

    /** Last state actually delivered to Dart, so a repeat can be dropped. */
    private var lastEmittedState: String? = null

    /** How long to let a freshly-armed call settle before believing "idle". */
    private const val RECONCILE_GRACE_MS = 3000L

    private var pendingReconcile: Runnable? = null

    private var phoneStateReceiver: BroadcastReceiver? = null

    /** Set by MainActivity.onResume/onPause. */
    var isAppInForeground: Boolean = false

    /**
     * Lets MainActivity opt in/out of showing over the lock screen while a
     * call is ringing, without IncomingCallBridge holding an Activity
     * reference itself. Set/cleared by MainActivity's own lifecycle.
     */
    var onCallStateForUi: ((ringing: Boolean) -> Unit)? = null

    fun attach(sink: EventChannel.EventSink) {
        eventSink = sink
    }

    fun detach() {
        eventSink = null
    }

    /**
     * Starts watching OFFHOOK/IDLE for the life of the process.
     *
     * Registered here against the application context rather than in
     * MainActivity, for two reasons:
     *
     *  * Placing a call opens the system in-call screen, which stops our
     *    Activity — an onStart/onStop registration would be torn down for the
     *    entire call and miss both the OFFHOOK that means "connected" and the
     *    IDLE that means "hung up". The visible symptom was the in-app
     *    "Calling…" screen never going away after the call was cancelled from
     *    the native dialer.
     *  * MainActivity can exist more than once (the call notification launches
     *    it with FLAG_ACTIVITY_NEW_TASK, and the activity has no task
     *    affinity), and a per-Activity registration then means two receivers
     *    and two of every transition.
     *
     * Note that these broadcasts are only delivered at all when
     * READ_PHONE_STATE has been granted; [reconcile] covers the case where it
     * has not.
     */
    fun startPhoneStateWatch(context: Context) {
        if (phoneStateReceiver != null) return
        val appContext = context.applicationContext
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.getStringExtra(TelephonyManager.EXTRA_STATE)) {
                    TelephonyManager.EXTRA_STATE_OFFHOOK -> onConnected(appContext)
                    TelephonyManager.EXTRA_STATE_IDLE -> onDisconnected(appContext)
                }
            }
        }
        val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            appContext.registerReceiver(receiver, filter)
        }
        phoneStateReceiver = receiver
    }

    fun onRinging(context: Context, phoneNumber: String?) {
        // Telecom screens the same call twice on some handsets. Re-announcing
        // it would give Dart a second call session for one real call, and with
        // it a second Recent Call Logs row. The cold-start path (tapping the
        // notification for a call whose screening event went nowhere because no
        // EventSink was attached) is unaffected: nothing was emitted then, so
        // lastEmittedState is still null and this passes through. The number is
        // part of the check so a genuinely new caller is never suppressed by a
        // previous call this object somehow never saw the end of.
        if (lastEmittedState == STATE_RINGING && phoneNumber == activeNumber) return

        activeNumber = phoneNumber
        activeIsOutgoing = false
        activeSinceMs = System.currentTimeMillis()
        connectedAtMs = 0L
        onCallStateForUi?.invoke(true)
        emit(STATE_RINGING, phoneNumber, isOutgoing = false)
        if (!isAppInForeground) {
            NativeCallNotification.show(context, phoneNumber)
        }
    }

    /**
     * Called right before Dart hands off to the native dialer for a call
     * placed from within the app, so the next OFFHOOK/IDLE phone-state
     * transition (which carries no number/direction of its own) can be
     * correctly attributed to this outgoing call rather than dropped.
     */
    fun armOutgoingCall(phoneNumber: String) {
        activeNumber = phoneNumber
        activeIsOutgoing = true
        activeSinceMs = System.currentTimeMillis()
        connectedAtMs = 0L
        lastEmittedState = null
    }

    /**
     * An outgoing call seen by the screening service.
     *
     * From API 29 a CallScreeningService is handed outgoing calls as well as
     * incoming ones. Treating those as "ringing" is what made a call the user
     * placed show up as an incoming-call notification, and then — because the
     * direction was overwritten before the IDLE that followed — as a *missed*
     * call in Recent Call Logs. So an outgoing screening callback only ever
     * arms direction/number here; it never announces a ringing call.
     *
     * Does not disturb an already-armed outgoing call: [armOutgoingCall] ran
     * first for calls placed from inside the app and holds the number Dart is
     * showing a screen for.
     */
    fun onOutgoingCallDetected(phoneNumber: String?) {
        if (activeIsOutgoing && activeSinceMs != 0L) return
        activeNumber = phoneNumber
        activeIsOutgoing = true
        activeSinceMs = System.currentTimeMillis()
        connectedAtMs = 0L
        lastEmittedState = null
    }

    fun onConnected(context: Context) {
        if (activeSinceMs == 0L) return
        // Guarding on connectedAtMs rather than lastEmittedState so a repeated
        // OFFHOOK is dropped even when no EventSink was attached for the first
        // one (nothing is recorded as emitted in that case).
        if (connectedAtMs != 0L) return
        connectedAtMs = System.currentTimeMillis()

        emit(STATE_CONNECTED, activeNumber, activeIsOutgoing)
        // The system in-call screen has just taken over the display. Put this
        // app's call screen — the one with the encounter details and the live
        // duration — back in front of it.
        CallUiLauncher.bringToFront(context, activeNumber)
    }

    fun onDisconnected(context: Context) {
        if (activeSinceMs == 0L) return
        cancelPendingReconcile()
        emit(
            STATE_DISCONNECTED,
            activeNumber,
            activeIsOutgoing,
            durationSeconds = elapsedTalkSeconds(),
        )
        NativeCallNotification.cancel(context)
        CallUiLauncher.cancel(context)
        onCallStateForUi?.invoke(false)
        reset()
    }

    /**
     * Drops the current call without announcing anything to Dart — used when
     * Dart decides the call is none of its business after all (a blocked
     * contact). Without this the call would stay armed, and the OFFHOOK from
     * the user answering it on the handset would still drag the app to the
     * front.
     */
    fun releaseActiveCall(context: Context) {
        if (activeSinceMs == 0L) return
        cancelPendingReconcile()
        NativeCallNotification.cancel(context)
        CallUiLauncher.cancel(context)
        onCallStateForUi?.invoke(false)
        reset()
    }

    /** Conversation length so far, in whole seconds; 0 if never connected. */
    private fun elapsedTalkSeconds(): Int {
        if (connectedAtMs == 0L) return 0
        val elapsedMs = System.currentTimeMillis() - connectedAtMs
        return if (elapsedMs <= 0L) 0 else (elapsedMs / 1000L).toInt()
    }

    private fun reset() {
        activeNumber = null
        activeIsOutgoing = false
        activeSinceMs = 0L
        connectedAtMs = 0L
        lastEmittedState = null
    }

    /**
     * Backstop for a call that ended while nobody was listening.
     *
     * Called when MainActivity comes back to the foreground. The primary
     * mechanism is the phone-state broadcast receiver, but it can miss a
     * transition in two real situations:
     *
     *  * the process was killed while the native in-call screen was up, so
     *    the receiver did not exist when the call ended;
     *  * READ_PHONE_STATE was never granted, in which case Android does not
     *    deliver ACTION_PHONE_STATE_CHANGED to us at all.
     *
     * Without this, cancelling from the native dialer leaves the in-app
     * "Calling…" screen stuck on screen forever.
     *
     * Deliberately checks the audio mode first: unlike TelephonyManager it
     * needs no permission, so this still works for a user who declined the
     * call permission prompt.
     */
    fun reconcile(context: Context) {
        val appContext = context.applicationContext
        if (activeSinceMs == 0L) return

        val elapsed = System.currentTimeMillis() - activeSinceMs
        if (elapsed < RECONCILE_GRACE_MS) {
            // Too soon to trust "idle" — the dialer may not have moved the
            // radio off-hook yet. Re-check once the grace period is over
            // rather than dropping the check entirely.
            scheduleReconcile(appContext, RECONCILE_GRACE_MS - elapsed)
            return
        }

        if (isCallActive(appContext)) return
        onDisconnected(appContext)
    }

    private fun scheduleReconcile(context: Context, delayMs: Long) {
        cancelPendingReconcile()
        val runnable = Runnable {
            pendingReconcile = null
            reconcile(context)
        }
        pendingReconcile = runnable
        mainHandler.postDelayed(runnable, delayMs)
    }

    private fun cancelPendingReconcile() {
        pendingReconcile?.let { mainHandler.removeCallbacks(it) }
        pendingReconcile = null
    }

    /**
     * Whether the phone is on a call right now.
     *
     * Audio mode is the permission-free signal and is checked first;
     * telephony state is consulted only as confirmation, and only when the
     * runtime permission backing it has actually been granted (it throws on
     * API 31+ otherwise).
     */
    fun isCallActive(context: Context): Boolean {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val mode = audioManager?.mode
        if (mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION) {
            return true
        }

        return try {
            val telephonyManager =
                context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            @Suppress("DEPRECATION")
            val state = telephonyManager?.callState
            state != null && state != TelephonyManager.CALL_STATE_IDLE
        } catch (e: SecurityException) {
            // READ_PHONE_STATE not granted — the audio-mode check above is
            // the only signal available, and it already said "not in a call".
            false
        }
    }

    private fun emit(
        state: String,
        phoneNumber: String?,
        isOutgoing: Boolean,
        durationSeconds: Int = 0,
    ) {
        eventSink ?: return
        if (lastEmittedState == state) return
        lastEmittedState = state
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "state" to state,
                    "phoneNumber" to phoneNumber,
                    "isOutgoing" to isOutgoing,
                    "durationSeconds" to durationSeconds,
                    "timestampMs" to System.currentTimeMillis(),
                )
            )
        }
    }
}
