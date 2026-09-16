package com.example.metadata

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.TelecomManager
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Incoming-call detection bridge (see the plan): a CallScreeningService
 * supplies the ringing number, this activity's phone-state receiver tracks
 * connected/disconnected transitions, and answer/decline act on the real
 * call via TelecomManager — all forwarded to Dart's IncomingCallService
 * through IncomingCallBridge/these two channels.
 */
class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.metadata.calls/methods"
    private val eventChannelName = "com.metadata.calls/events"

    // In-app VoIP runs on its own channel pair. It is a separate feature from
    // the cellular call detection above — that one observes the carrier's
    // calls, this one *is* the call.
    private val voipMethodChannelName = "com.metadata.voip/methods"
    private val voipEventChannelName = "com.metadata.voip/events"

    private var pendingColdStartNumber: String? = null
    private var hasPendingColdStart: Boolean = false
    private var isShowingOverLockScreen = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        IncomingCallBridge.onCallStateForUi = { ringing ->
            if (ringing) enableShowOverLockScreen() else disableShowOverLockScreen()
        }
        // Process-wide and deliberately never unregistered here — see
        // IncomingCallBridge.startPhoneStateWatch for why it cannot be tied to
        // this Activity's lifecycle.
        IncomingCallBridge.startPhoneStateWatch(applicationContext)
    }

    override fun onDestroy() {
        IncomingCallBridge.onCallStateForUi = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        IncomingCallBridge.isAppInForeground = true
        // Lets VoipMessagingService suppress the native full-screen call
        // notification while the Flutter call route is already on screen.
        VoipBridge.isAppInForeground = true

        // Already back in front, so drop any queued re-front attempt and the
        // "tap to return to the call" notification that backs it up.
        CallUiLauncher.cancel(applicationContext)

        // Placing a call hands off to the system in-call screen, so the user
        // coming back here usually means the call just ended. Verify against
        // the real device state and close out any call we still think is
        // running — otherwise a call cancelled from the native dialer would
        // leave the in-app "Calling…" screen stranded.
        IncomingCallBridge.reconcile(applicationContext)
    }

    override fun onPause() {
        super.onPause()
        IncomingCallBridge.isAppInForeground = false
        VoipBridge.isAppInForeground = false
    }

    /**
     * Lets the app's CallingScreen actually be visible over the lock screen
     * when ringing starts while the app is backgrounded/killed — otherwise
     * the Activity could come to front behind a locked screen and never be
     * seen. Always paired with [disableShowOverLockScreen] once the call
     * ends, so this never lingers into ordinary (non-call) app use.
     */
    private fun enableShowOverLockScreen() {
        if (isShowingOverLockScreen) return
        isShowingOverLockScreen = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        keyguardManager.requestDismissKeyguard(this, null)
    }

    private fun disableShowOverLockScreen() {
        if (!isShowingOverLockScreen) return
        isShowingOverLockScreen = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "answerCall" -> result.success(answerRingingCall())
                    "declineCall" -> result.success(declineRingingCall())
                    "armOutgoingCall" -> {
                        val number = call.argument<String>("phoneNumber")
                        if (number != null) IncomingCallBridge.armOutgoingCall(number)
                        result.success(true)
                    }
                    "placeCall" -> {
                        val number = call.argument<String>("phoneNumber")
                        result.success(if (number != null) placeCallDirectly(number) else false)
                    }
                    "releaseCall" -> {
                        IncomingCallBridge.releaseActiveCall(applicationContext)
                        result.success(true)
                    }
                    "requestCallPermissions" -> {
                        CallPermissions.request(this)
                        result.success(true)
                    }
                    "getCallRolesStatus" -> result.success(CallPermissions.status(this))
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    IncomingCallBridge.attach(sink)
                    consumePendingColdStart()
                }

                override fun onCancel(arguments: Any?) {
                    IncomingCallBridge.detach()
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voipMethodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // CallKit equivalents are no-ops here: on Android the
                    // ringing UI is a full-screen-intent notification posted by
                    // VoipMessagingService the moment the push lands, not
                    // something Dart has to ask for.
                    "reportIncomingCall",
                    "reportOutgoingCall",
                    "reportCallConnected",
                    "setMuted" -> result.success(null)

                    "endCall" -> {
                        VoipCallNotification.cancelIncoming(applicationContext)
                        VoipCallForegroundService.stop(applicationContext)
                        result.success(null)
                    }

                    "startCallForegroundService" -> {
                        val callId = call.argument<String>("callId")
                        val peerName = call.argument<String>("peerName") ?: "In-app call"
                        if (callId != null) {
                            VoipCallForegroundService.start(applicationContext, callId, peerName)
                        }
                        result.success(null)
                    }

                    "stopCallForegroundService" -> {
                        VoipCallForegroundService.stop(applicationContext)
                        result.success(null)
                    }

                    // PushKit is iOS-only; Android reaches a terminated app
                    // with a high-priority FCM data message instead.
                    "getVoipToken" -> result.success(null)

                    "consumePendingCallAction" -> result.success(VoipBridge.consumePendingAction())

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, voipEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    VoipBridge.attach(sink)
                }

                override fun onCancel(arguments: Any?) {
                    VoipBridge.detach()
                }
            })

        VoipCallNotification.ensureChannels(applicationContext)
        readColdStartExtras(intent)
        readVoipColdStartExtras(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        readColdStartExtras(intent)
        readVoipColdStartExtras(intent)
        consumePendingColdStart()
    }

    /**
     * Recovers an Answer/Decline tapped on the call notification.
     *
     * The intent extras are authoritative rather than [VoipBridge]'s static
     * state, because the tap may have started the process from scratch — in
     * which case the static was never populated in this process at all.
     */
    private fun readVoipColdStartExtras(intent: Intent?) {
        val callId = intent?.getStringExtra(VoipCallNotification.EXTRA_CALL_ID) ?: return
        val action = intent.getStringExtra(VoipCallNotification.EXTRA_ACTION) ?: return
        VoipBridge.setPendingAction(callId, action)
        // Consumed by Dart via `consumePendingCallAction` once the calling
        // feature has finished initialising.
    }

    /** Populated when launched by tapping NativeCallNotification's full-screen intent. */
    private fun readColdStartExtras(intent: Intent?) {
        val number = intent?.getStringExtra(NativeCallNotification.EXTRA_PHONE_NUMBER) ?: return
        pendingColdStartNumber = number
        hasPendingColdStart = true
    }

    private fun consumePendingColdStart() {
        if (!hasPendingColdStart) return
        hasPendingColdStart = false
        IncomingCallBridge.onRinging(applicationContext, pendingColdStartNumber)
    }

    /**
     * Answers the real ringing call, then puts this app's call screen back on
     * top of the system in-call activity that accepting it brings up.
     *
     * Without the second half, tapping Answer in this app drops the user into
     * the OEM dialer and the in-app call screen — the whole point of which is
     * the encounter details and the live duration — is left behind it.
     */
    private fun answerRingingCall(): Boolean {
        return try {
            val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            telecomManager.acceptRingingCall()
            CallUiLauncher.bringToFront(this, null)
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /**
     * Best-effort only. There is no public API for a non-default-dialer app
     * to reject a call that has already passed CallScreeningServiceImpl's
     * screening window (see the plan). silenceRinger() is the closest
     * available action; on some OEMs/OS versions it may throw, in which
     * case the in-app overlay still dismisses on its own.
     */
    private fun declineRingingCall(): Boolean {
        return try {
            val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            telecomManager.silenceRinger()
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /**
     * Places a call directly via ACTION_CALL instead of ACTION_DIAL, so the
     * user doesn't have to tap a second "Call" button in the native dialer
     * after already tapping ours. Requires the CALL_PHONE runtime
     * permission (requested as part of CallPermissions.request(), the same
     * "Allow Calls" prompt that grants call detection) — returns false if
     * it isn't granted so the Dart side can fall back to opening the
     * native dialer pre-filled instead of silently doing nothing.
     *
     * ACTION_CALL raises the system in-call screen, so — exactly as with
     * answering — the app is brought straight back to the front afterwards.
     * Dialing from this app should not mean watching the OEM dialer for the
     * length of the call.
     */
    private fun placeCallDirectly(phoneNumber: String): Boolean {
        val hasPermission = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.CALL_PHONE,
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return false

        return try {
            startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:$phoneNumber")))
            CallUiLauncher.bringToFront(this, phoneNumber)
            true
        } catch (e: SecurityException) {
            false
        }
    }
}
