package com.example.metadata

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService

/**
 * Requires the ROLE_CALL_SCREENING role (requested via CallPermissions from
 * the Dart-side permission prompt). Gets the incoming number early, before
 * the call audibly rings, so the app can look the contact up and prep the
 * CallingScreen overlay/notification.
 *
 * Always allows the call through (never rejects here) — this service is
 * used purely for caller-ID/context lookup, not spam blocking. Real
 * answer/decline happens later via TelecomManager from the in-app
 * Accept/Decline buttons, by which point this screening window has already
 * closed — see MainActivity.declineRingingCall() and the plan's documented
 * decline limitation.
 *
 * ## Direction matters
 *
 * From API 29 this callback fires for calls the *user places* too, not just
 * ones they receive. Feeding those into the incoming path made every outgoing
 * call post an "Incoming call" notification, and then land in Recent Call Logs
 * as a missed call — because the screening callback overwrote the direction
 * that `armOutgoingCall` had just set, so the IDLE at the end of the call was
 * read as "an incoming call nobody answered". Outgoing calls therefore go to
 * [IncomingCallBridge.onOutgoingCallDetected], which arms state without
 * announcing a ringing call.
 */
class CallScreeningServiceImpl : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        val phoneNumber = callDetails.handle?.schemeSpecificPart

        if (isOutgoing(callDetails)) {
            IncomingCallBridge.onOutgoingCallDetected(phoneNumber)
        } else {
            IncomingCallBridge.onRinging(applicationContext, phoneNumber)
        }

        respondToCall(
            callDetails,
            CallResponse.Builder()
                .setDisallowCall(false)
                .setRejectCall(false)
                .build(),
        )
    }

    /**
     * `callDirection` only exists from API 29 — which is also the version that
     * started delivering outgoing calls here at all, so on anything older
     * every screened call is by definition incoming.
     */
    private fun isOutgoing(callDetails: Call.Details): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return callDetails.callDirection == Call.Details.DIRECTION_OUTGOING
    }
}
