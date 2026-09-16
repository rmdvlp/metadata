# In-App VoIP Calling — Setup & Operations

App-to-app voice calling over WebRTC, signalled through Firestore and woken by
FCM (Android) / PushKit (iOS). **No cellular call is ever placed** — there is
no `tel:` URL and no SIM involvement anywhere in this feature.

This is separate from the existing *cellular call detection* stack
(`IncomingCallService`, `DialerService`, `CallScreeningServiceImpl`,
`CallObserverPlugin`), which is untouched and still works exactly as before.

---

## 1. Architecture

```
UI (VoipIncomingCallScreen / VoipActiveCallScreen)
        │  watches callSessionProvider, calls callControllerProvider
        ▼
CallController ──► CallService ──────────────► WebRTCService ──► flutter_webrtc
                        │                            (audio only)
                        ├──► CallRemoteDataSource ──► calls/{callId}
                        ├──► SignalingDataSource ───► calls/{callId}/signaling/*
                        └──► VoipPlatformService ───► CallKit / Android call UI

CallCoordinator  ── the single owner of "is a call screen showing?"
        ▲ Firestore incoming stream · FCM data message · native CallKit event
```

Audio never touches Firestore. Firestore carries only SDP offers/answers and
ICE candidates; the voice itself flows peer-to-peer (or via TURN).

### Why the state machine matters

Both devices and the backend write the same `calls/{callId}` document. Every
status change goes through `CallRemoteDataSource.transition`, which runs a
Firestore transaction, re-reads the current status, and consults
`CallStatus.canTransitionTo`. Firestore serialises the transactions, so:

* caller-cancels racing receiver-accepts resolves to exactly one outcome;
* duplicate FCM deliveries and repeated snapshots are no-ops;
* `ended → connected` is structurally impossible.

`test/call_status_test.dart` covers this.

---

## 2. Commands to run

```bash
# Dependencies (already applied to pubspec.yaml)
flutter pub get

# iOS pods — REQUIRED, the Podfile now enables the microphone permission macro
cd ios && LANG=en_US.UTF-8 pod install && cd ..

# Backend
cd functions && npm install && npm run build && cd ..
```

### Deploy

```bash
firebase deploy --only firestore:rules,firestore:indexes --project metadata-64577
firebase deploy --only functions --project metadata-64577
```

Deploy **indexes before functions** — `sweepStaleCalls` queries need them.

> The local `firebase` CLI at `/usr/local/bin/firebase` was found to be a
> corrupt standalone install. Fix with `npm i -g firebase-tools` before
> deploying.

---

## 3. Firebase configuration

### Collections

| Path | Written by | Purpose |
|---|---|---|
| `calls/{callId}` | both clients + functions | call state machine |
| `calls/{callId}/signaling/{offer\|answer}` | caller / receiver | SDP |
| `calls/{callId}/callerCandidates/*` | caller | ICE |
| `calls/{callId}/receiverCandidates/*` | receiver | ICE |
| `users/{uid}/devices/{deviceId}` | client | FCM + PushKit tokens, one per install |
| `phone_index/{normalizedPhone}` | **functions only** | phone → uid lookup |
| `users/{uid}/call_logs/*` | functions | call history (existing collection, reused) |

### Cloud Functions

| Function | Trigger | Job |
|---|---|---|
| `onUserWritten` | `users/{uid}` write | maintains `phone_index` |
| `resolveVoipUsers` | callable | batch phone → app-user lookup |
| `onCallCreated` | `calls/{callId}` create | fans out FCM + PushKit, then `initiating → ringing` |
| `onCallStatusChanged` | `calls/{callId}` update | end pushes + writes call history to both users |
| `sweepStaleCalls` | every 1 min | rescues calls stuck in `ringing` / `connecting` |

### Secrets & params (required for **iOS** calls only)

FCM cannot deliver PushKit pushes, so iOS goes through APNs directly with an
auth key.

1. Apple Developer → Certificates, Identifiers & Profiles → Keys → **+**
2. Enable **Apple Push Notifications service (APNs)**, download the `.p8`
   (one download only), note the **Key ID** and your **Team ID**.

```bash
firebase functions:secrets:set APNS_AUTH_KEY \
  --project metadata-64577 --data-file ./AuthKey_XXXXXXXXXX.p8

gcloud services enable secretmanager.googleapis.com cloudscheduler.googleapis.com \
  --project metadata-64577

cp functions/.env.example functions/.env.metadata-64577
# APNS_KEY_ID=...  APNS_TEAM_ID=...  APNS_BUNDLE_ID=com.example.metadata  APNS_PRODUCTION=false
```

Set `APNS_PRODUCTION=true` for TestFlight/App Store builds. Without APNs
config, Android calling works fine and iOS pushes are skipped with a warning.

### Recommended: TTL on signaling

Clients delete their own signaling documents on teardown, but a device killed
mid-call leaves orphans. Add a Firestore TTL policy on the `createdAt` field of
`callerCandidates`, `receiverCandidates` and `signaling` (e.g. 24 h).

---

## 4. Android configuration

Already applied in this change:

* **Permissions**: `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`,
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `WAKE_LOCK`,
  `BLUETOOTH_CONNECT`.
* **`VoipMessagingService`** — extends the firebase_messaging plugin's own
  `FirebaseMessagingService` and posts the full-screen call notification in
  native code the instant the push lands. The plugin's own service declaration
  is removed via `tools:node="remove"` so FCM has one unambiguous target; its
  separate `FlutterFirebaseMessagingReceiver` is left intact, so all
  Dart-side message delivery is unchanged. **Verified in the merged manifest.**
* **`VoipCallForegroundService`** (`foregroundServiceType="microphone"`) —
  keeps the call alive when the app is backgrounded. Without it Android 11+
  revokes microphone access from a background process mid-call.
* **`VoipCallActionReceiver`** — Answer / Decline straight from the notification.
* `app/build.gradle.kts` gained `com.google.firebase:firebase-messaging`
  (compile-time need of `VoipMessagingService`).

### Known trade-off

Declining from a notification while the app process is **dead** briefly starts
the app, because a broadcast receiver has no Firebase credentials to write the
`rejected` status itself. The alternative — leaving the caller ringing until
the 60-second server sweep — is worse. Declining while the process is alive
does *not* foreground the app.

---

## 5. iOS configuration

Applied in this change:

* `Info.plist`: `NSMicrophoneUsageDescription`, and `UIBackgroundModes` +=
  `voip`, `audio`.
* `VoipCallPlugin.swift` — CallKit (`CXProvider`) + PushKit (`PKPushRegistry`),
  registered from `AppDelegate` and added to `project.pbxproj`.
* `Podfile` `post_install` now defines `PERMISSION_MICROPHONE=1`.
  **This is not optional**: permission_handler defaults every permission macro
  to `0`, so without it `Permission.microphone` never prompts and always
  reports denied.

### Manual Xcode steps (must be done once, in Xcode)

1. **Signing & Capabilities** → **+ Capability** → **Push Notifications**.
2. **+ Capability** → **Background Modes** → tick **Voice over IP** and
   **Audio, AirPlay, and Picture in Picture** (mirrors the Info.plist entries
   so the entitlement is generated).
3. Confirm the bundle id matches `APNS_BUNDLE_ID`.

### Why CallKit/PushKit and not "just a notification"

A terminated iOS app cannot be woken by a normal push in time to ring. Only a
PushKit VoIP push does that, and PushKit is unreachable from Dart. Apple also
**requires** that every VoIP push reports a call to CallKit before the handler
returns — skipping it terminates the app, and repeating that revokes VoIP push
entitlement. Every path in `VoipCallPlugin`, including the "call already
ended" push, therefore reports a call (and immediately ends it if needed).

The plugin also hands the CallKit-activated `AVAudioSession` to
`RTCAudioSession`. **Verified linked in the built binary.** Without this
handoff CallKit and WebRTC fight over the session and calls connect silently.

---

## 6. TURN (production)

STUN-only works for most consumer NATs but fails on symmetric / carrier-grade
NAT. TURN credentials are deliberately **not** compiled into the app — a
long-lived credential in a binary is extractable and gets abused as an open
relay. Supply short-lived, server-issued credentials at runtime:

```dart
ref.read(callServiceProvider).configureTurnServers([
  {
    'urls': ['turn:turn.example.com:3478?transport=udp'],
    'username': ephemeralUsername,   // from your backend, short TTL
    'credential': ephemeralPassword,
  },
]);
```

Call this after sign-in, before the first call. `CallConfig.iceConfiguration`
merges STUN + TURN automatically.

---

## 7. Test plan

### Preconditions
Two devices, two accounts, both signed in, both with a `users/{uid}/devices/*`
document, and each other's phone number saved as a contact.

| # | Scenario | Expected |
|---|---|---|
| 1 | A calls B, B accepts, talk, A ends | Both hear audio; timer starts only at `connected`; both screens close; `completed` in both histories with equal duration |
| 2 | A calls B, B declines | A sees "Call rejected"; `declined` logged |
| 3 | A calls B, nobody answers | After 30 s → "No answer"; status `missed`; server sweep is the backstop |
| 4 | A calls B, A cancels | B's ringing UI disappears; `cancelled` |
| 5 | B in foreground | Firestore listener presents the screen; **no** duplicate native notification |
| 6 | B backgrounded | Full-screen notification over the lock screen; Answer works |
| 7 | B force-killed | Android: FCM → native full-screen notification. iOS: PushKit → CallKit. **Not** a plain banner |
| 8 | Kill Wi-Fi mid-call | Survives a brief blip (12 s ICE grace); a real drop ends the call with `network_lost` |
| 9 | Deny microphone | Typed message + "Open Settings" on permanent denial; no call document ringing the other side |
| 10 | B already on a call | Second caller gets busy; call ends `rejected` / `endReason: busy` |
| 11 | B signed in on 2 devices | Both ring; answering on one stops the other |
| 12 | Duplicate FCM | Exactly one incoming-call screen (`_handledCallIds`) |

### Also verify
- Mute stops the **track** (peer hears silence, device audio unaffected).
- Speaker toggles earpiece ↔ loudspeaker.
- After every call: no red iOS mic indicator, no lingering Android call notification.
- A third user cannot read `calls/{callId}` (rules).
- No audio bytes anywhere in Firestore.

### Automated
```bash
flutter analyze            # clean
flutter test               # 20 tests, includes the state machine suite
cd functions && npm run build && npm run lint
```

---

## 8. Logging

Every stage emits through `CallLogger` (`lib/core/logging/call_logger.dart`),
tagged `[CALL]` and filterable by `callId`:

```
CALL_CREATED → CALL_RINGING → CALL_ACCEPTED → WEBRTC_INITIALIZED
→ OFFER_CREATED → OFFER_RECEIVED → ANSWER_CREATED → ANSWER_RECEIVED
→ ICE_CONNECTED → CALL_CONNECTED → CALL_ENDED
```

A call that rings and is answered but produces no audio will show
`ANSWER_RECEIVED` with no `ICE_CONNECTED` — that is a TURN problem, not a
signaling one.
