package com.example.metadata

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * Native (non-Dart) fallback for the incoming-call notification, used only
 * when no Flutter EventSink is attached (app backgrounded/killed — see
 * IncomingCallBridge). Posts to the same "incoming_call_channel" channel
 * that lib/core/firebase/local_notifications_service.dart creates on app
 * init; safe to assume it already exists here because reaching this
 * feature at all requires the user to have opened the app once to grant
 * call permissions (which creates the channel).
 */
object NativeCallNotification {
    private const val CHANNEL_ID = "incoming_call_channel"
    private const val NOTIFICATION_ID = 990011

    /**
     * Separate id from the ringing notification: the two can legitimately
     * overlap for a moment (ringing is cancelled from Dart once the call is
     * answered, the ongoing one is posted from the connected transition), and
     * sharing an id would make whichever cancel lands last take down both.
     */
    private const val ONGOING_NOTIFICATION_ID = 990012

    const val EXTRA_PHONE_NUMBER = "za.co.contextidentity.metadata.EXTRA_INCOMING_CALL_NUMBER"

    fun show(context: Context, phoneNumber: String?) {
        val pendingIntent = callScreenIntent(context, phoneNumber)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("Incoming call")
            .setContentText(phoneNumber ?: "Unknown number")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager(context).notify(NOTIFICATION_ID, notification)
    }

    /**
     * Puts the app's in-call screen back in front of the system in-call UI
     * once a call is live — the last resort in [CallUiLauncher]'s escalation,
     * used when a plain activity start was refused because the app is no
     * longer the foreground app.
     *
     * A full-screen intent is what makes this work from the background at all;
     * CATEGORY_CALL is what makes it a legitimate use of one.
     */
    fun showOngoingCall(context: Context, phoneNumber: String?) {
        val pendingIntent = callScreenIntent(context, phoneNumber)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("Call in progress")
            .setContentText("Tap to return to the call")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager(context).notify(ONGOING_NOTIFICATION_ID, notification)
    }

    fun cancel(context: Context) {
        notificationManager(context).cancel(NOTIFICATION_ID)
    }

    fun cancelOngoingCall(context: Context) {
        notificationManager(context).cancel(ONGOING_NOTIFICATION_ID)
    }

    /**
     * Reuses the existing task/route stack rather than restarting the app, so
     * tapping through lands on the live call screen the service already
     * pushed instead of a fresh Home.
     */
    private fun callScreenIntent(context: Context, phoneNumber: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            putExtra(EXTRA_PHONE_NUMBER, phoneNumber)
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
