package com.example.metadata

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Builds the two notifications an in-app call needs on Android.
 *
 * The incoming one uses a full-screen intent, which is what lets a ringing
 * call take over the screen (and appear over the lock screen) while the app
 * is backgrounded or terminated. It is posted from [VoipMessagingService] the
 * instant the push arrives, in native code, rather than from a Dart
 * background isolate — starting an isolate takes long enough that a ringing
 * phone would visibly lag or miss short-lived calls entirely.
 */
object VoipCallNotification {
    const val EXTRA_CALL_ID = "callId"
    const val EXTRA_CALLER_NAME = "callerName"
    const val EXTRA_CALLER_ID = "callerId"
    const val EXTRA_ACTION = "voipAction"

    const val ACTION_ANSWER = "za.co.contextidentity.metadata.VOIP_ANSWER"
    const val ACTION_DECLINE = "za.co.contextidentity.metadata.VOIP_DECLINE"

    private const val INCOMING_CHANNEL_ID = "voip_incoming_call_channel"
    private const val ONGOING_CHANNEL_ID = "voip_ongoing_call_channel"

    const val INCOMING_NOTIFICATION_ID = 990021
    const val ONGOING_NOTIFICATION_ID = 990022

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        val incoming = NotificationChannel(
            INCOMING_CHANNEL_ID,
            "In-app Calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Ringing for calls placed to you inside Metadata."
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1000, 1000)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        // Low importance on purpose: this one is the silent "call in progress"
        // badge that keeps the foreground service alive, not an alert.
        val ongoing = NotificationChannel(
            ONGOING_CHANNEL_ID,
            "Ongoing Call",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while an in-app call is connected."
            setShowBadge(false)
        }

        manager.createNotificationChannel(incoming)
        manager.createNotificationChannel(ongoing)
    }

    fun showIncoming(context: Context, callId: String, callerName: String, callerId: String) {
        ensureChannels(context)

        val fullScreenIntent = PendingIntent.getActivity(
            context,
            callId.hashCode(),
            launchIntent(context, callId, callerName, callerId, action = null),
            pendingIntentFlags(),
        )

        val notification = NotificationCompat.Builder(context, INCOMING_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle("Incoming call")
            .setContentText(callerName)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            // The pair that makes a ringing call take over the screen instead
            // of appearing as a heads-up banner.
            .setFullScreenIntent(fullScreenIntent, true)
            .setContentIntent(fullScreenIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Decline",
                actionIntent(context, ACTION_DECLINE, callId, callerName, callerId),
            )
            .addAction(
                android.R.drawable.sym_action_call,
                "Answer",
                actionIntent(context, ACTION_ANSWER, callId, callerName, callerId),
            )
            .build()

        NotificationManagerCompat.from(context)
            .notify(INCOMING_NOTIFICATION_ID, notification)
    }

    fun buildOngoing(context: Context, callId: String, peerName: String): Notification {
        ensureChannels(context)
        val contentIntent = PendingIntent.getActivity(
            context,
            callId.hashCode() + 1,
            launchIntent(context, callId, peerName, callerId = "", action = null),
            pendingIntentFlags(),
        )
        return NotificationCompat.Builder(context, ONGOING_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle("Call in progress")
            .setContentText(peerName)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(contentIntent)
            .build()
    }

    fun cancelIncoming(context: Context) {
        NotificationManagerCompat.from(context).cancel(INCOMING_NOTIFICATION_ID)
    }

    /**
     * Launches the app for this call. Carries the call id (and, for the
     * notification actions, what the user chose) as intent extras rather than
     * relying only on [VoipBridge]'s static state, because the process may be
     * created fresh to handle the tap.
     */
    fun launchIntent(
        context: Context,
        callId: String,
        callerName: String,
        callerId: String,
        action: String?,
    ): Intent {
        return Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CALLER_NAME, callerName)
            putExtra(EXTRA_CALLER_ID, callerId)
            if (action != null) putExtra(EXTRA_ACTION, action)
        }
    }

    private fun actionIntent(
        context: Context,
        action: String,
        callId: String,
        callerName: String,
        callerId: String,
    ): PendingIntent {
        val intent = Intent(context, VoipCallActionReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CALLER_NAME, callerName)
            putExtra(EXTRA_CALLER_ID, callerId)
        }
        return PendingIntent.getBroadcast(
            context,
            (action + callId).hashCode(),
            intent,
            pendingIntentFlags(),
        )
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }
}
