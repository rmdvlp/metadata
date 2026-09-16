package com.example.metadata

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Requests the runtime permissions + Android role backing call handling:
 * READ_PHONE_STATE/ANSWER_PHONE_CALLS (incoming-call state + answer) and
 * CALL_PHONE (lets outgoing calls be placed directly via ACTION_CALL
 * instead of just opening the dialer pre-filled via ACTION_DIAL, which
 * needs an extra manual tap in the native dialer) — plain runtime
 * permissions — plus ROLE_CALL_SCREENING (a system chooser dialog via
 * RoleManager, API 29+ — see the plan for why this lighter role was chosen
 * over ROLE_DIALER).
 */
object CallPermissions {
    private const val REQUEST_CODE_ROLE = 9001
    private const val REQUEST_CODE_RUNTIME = 9002

    private val runtimePermissions = arrayOf(
        android.Manifest.permission.READ_PHONE_STATE,
        android.Manifest.permission.ANSWER_PHONE_CALLS,
        android.Manifest.permission.CALL_PHONE,
    )

    fun request(activity: Activity) {
        ActivityCompat.requestPermissions(activity, runtimePermissions, REQUEST_CODE_RUNTIME)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = activity.getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (roleManager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
            ) {
                val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING)
                @Suppress("DEPRECATION")
                activity.startActivityForResult(intent, REQUEST_CODE_ROLE)
            }
        }
    }

    fun status(context: Context): Map<String, Boolean> {
        val hasReadPhoneState = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.READ_PHONE_STATE,
        ) == PackageManager.PERMISSION_GRANTED
        val hasAnswerCalls = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ANSWER_PHONE_CALLS,
        ) == PackageManager.PERMISSION_GRANTED
        val hasCallPhone = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.CALL_PHONE,
        ) == PackageManager.PERMISSION_GRANTED

        var hasScreeningRole = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = context.getSystemService(Context.ROLE_SERVICE) as RoleManager
            hasScreeningRole = roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
        }

        return mapOf(
            "readPhoneState" to hasReadPhoneState,
            "answerPhoneCalls" to hasAnswerCalls,
            "callPhone" to hasCallPhone,
            "callScreeningRole" to hasScreeningRole,
        )
    }
}
