package com.example.metadata

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

/**
 * Keeps the app's own call screen in front once a call starts.
 *
 * Both `TelecomManager.acceptRingingCall()` and `ACTION_CALL` hand control to
 * the phone's system in-call activity, which lands on top of us — the user
 * taps Answer (or Call) in this app and ends up looking at the OEM dialer,
 * with the app's CallingScreen (and its encounter details) buried behind it.
 * Nothing about that hand-off is avoidable for a non-default-dialer app, so
 * the app comes back to the front immediately afterwards instead.
 *
 * Three escalating attempts, because which one works depends on the OS
 * version and how fast the system in-call activity appears:
 *
 *  1. `startActivity` with REORDER_TO_FRONT — the reliable one, because it
 *     runs while this app is still the foreground app (the user just tapped a
 *     button in it), so background-activity-start limits don't apply yet.
 *  2. `AppTask.moveToFront()` retries — wins the race when the system in-call
 *     activity is slower to appear than step 1.
 *  3. A `CATEGORY_CALL` full-screen-intent notification — the documented,
 *     always-permitted way for a call app to put a call screen up from the
 *     background, used only if the app still isn't in front by then.
 *
 * Everything scheduled here is cancelled by [cancel] as soon as the app is
 * back in front or the call ends, so no retry can fire into an unrelated
 * moment later on.
 */
object CallUiLauncher {
    /** 0 covers the still-foreground case; the rest race the in-call screen. */
    private val retryDelaysMs = longArrayOf(0L, 400L, 1000L, 1800L)

    /** After the last retry, fall back to the full-screen-intent notification. */
    private const val FULL_SCREEN_FALLBACK_DELAY_MS = 2600L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pending = mutableListOf<Runnable>()

    fun bringToFront(context: Context, phoneNumber: String?) {
        val appContext = context.applicationContext
        cancelPending()

        for (delay in retryDelaysMs) {
            schedule(delay) { bringToFrontNow(appContext) }
        }
        schedule(FULL_SCREEN_FALLBACK_DELAY_MS) {
            // isAppInForeground is maintained by MainActivity's own
            // onResume/onPause, so this is the app's real visibility — not a
            // guess about whether the launches above were allowed through.
            if (!IncomingCallBridge.isAppInForeground) {
                NativeCallNotification.showOngoingCall(appContext, phoneNumber)
            }
        }
    }

    /**
     * Called when the app is back in front, and when the call ends. Drops any
     * retry still queued and takes down the fallback notification.
     */
    fun cancel(context: Context) {
        cancelPending()
        NativeCallNotification.cancelOngoingCall(context.applicationContext)
    }

    /**
     * Queued runnables are kept so they can be un-posted. The list is bounded
     * at one attempt set: [bringToFront] and [cancel] both clear it first, so
     * a stale entry can never outlive the call it belongs to.
     */
    private fun schedule(delayMs: Long, action: () -> Unit) {
        val runnable = Runnable { action() }
        pending += runnable
        mainHandler.postDelayed(runnable, delayMs)
    }

    private fun cancelPending() {
        pending.forEach { mainHandler.removeCallbacks(it) }
        pending.clear()
    }

    private fun bringToFrontNow(context: Context) {
        if (IncomingCallBridge.isAppInForeground) return

        try {
            context.startActivity(
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
            )
        } catch (e: SecurityException) {
            // Background activity start refused — the notification fallback
            // scheduled alongside this covers it.
        }

        moveOwnTaskToFront(context)
    }

    /**
     * Re-fronts the existing task rather than launching into it, which keeps
     * the Flutter route stack (and therefore the live CallingScreen) exactly
     * as it was. Only ever touches this app's own tasks.
     */
    private fun moveOwnTaskToFront(context: Context) {
        try {
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            activityManager?.appTasks?.firstOrNull()?.moveToFront()
        } catch (e: SecurityException) {
            // No REORDER_TASKS on this OEM build — other attempts still apply.
        } catch (e: IllegalArgumentException) {
            // Task already gone.
        }
    }
}
