package com.example.metadata

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Keeps an in-app call alive while the app is not on screen.
 *
 * Without this, Android is free to freeze the process — and revoke microphone
 * access outright on Android 11+ — as soon as the user switches apps, which
 * would silently kill the call mid-sentence. A `microphone`-typed foreground
 * service with an ongoing notification is the only supported way to hold
 * those resources.
 */
class VoipCallForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callId = intent?.getStringExtra(EXTRA_CALL_ID)
        val peerName = intent?.getStringExtra(EXTRA_PEER_NAME) ?: "In-app call"

        if (callId == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = VoipCallNotification.buildOngoing(this, callId, peerName)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    VoipCallNotification.ONGOING_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(VoipCallNotification.ONGOING_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android 12+ refuses to start a foreground service from the
            // background in some states. The call still works while the app is
            // in the foreground, so this is logged rather than fatal.
            Log.e(TAG, "Could not start call foreground service", e)
            stopSelf()
            return START_NOT_STICKY
        }

        // Not START_STICKY: a call that was killed by the system must not be
        // silently resurrected with no peer on the other end.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    companion object {
        private const val TAG = "VoipCallFgService"
        const val EXTRA_CALL_ID = "callId"
        const val EXTRA_PEER_NAME = "peerName"

        fun start(context: Context, callId: String, peerName: String) {
            val intent = Intent(context, VoipCallForegroundService::class.java).apply {
                putExtra(EXTRA_CALL_ID, callId)
                putExtra(EXTRA_PEER_NAME, peerName)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Could not request call foreground service", e)
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, VoipCallForegroundService::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "Could not stop call foreground service", e)
            }
        }
    }
}
