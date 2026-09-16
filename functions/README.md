# Metadata Cloud Functions

TypeScript backend for the VoIP calling feature. Firebase project: **`metadata-64577`**.

- Runtime: **Node 20**
- SDKs: **firebase-functions v6 (`firebase-functions/v2`)**, **firebase-admin v13**
- Codebase: `default`, source `functions/`

## Functions

| Name | Type | Trigger | Purpose |
| --- | --- | --- | --- |
| `onUserWritten` | Firestore | `onDocumentWritten("users/{uid}")` | Maintains `phone_index/{normalizedPhone}` |
| `resolveVoipUsers` | Callable | `onCall` (auth required) | Phone numbers → VoIP users, without exposing other users' docs |
| `onCallCreated` | Firestore | `onDocumentCreated("calls/{callId}")` | Fans the call out to the receiver's devices, then `initiating → ringing` |
| `onCallStatusChanged` | Firestore | `onDocumentUpdated("calls/{callId}")` | Terminal status → end-call pushes + call history for both parties |
| `sweepStaleCalls` | Scheduler | `onSchedule("every 1 minutes")` | Times out abandoned calls |

### Layout

```
functions/
  src/
    index.ts                       # exports + setGlobalOptions
    lib/
      firebase.ts                  # lazy admin init, db(), messaging()
      phone.ts                     # normalizePhoneForMatching (mirrors lib/utils/phone_number.dart)
      callStatus.ts                # status constants, terminal check, transition map, log-status mapping
      devices.ts                   # device reads, FCM multicast, VoIP fan-out, dead-token pruning
      apns.ts                      # direct APNs HTTP/2 + ES256 JWT PushKit client
      params.ts                    # defineSecret / defineString / defineBoolean
      options.ts                   # shared REGION + runtime options
      types.ts                     # CallDoc shape and safe field readers
    triggers/                      # onUserWritten, onCallCreated, onCallStatusChanged, sweepStaleCalls
    callable/                      # resolveVoipUsers
```

## Why a hand-rolled APNs client?

FCM cannot deliver **PushKit** pushes — it only sends standard APNs alert and background push
types, and iOS refuses to wake a VoIP app for those. `src/lib/apns.ts` therefore talks to APNs
directly over the Node `http2` builtin:

- `apns-push-type: voip`, `apns-priority: 10`, `apns-expiration: now + 60s`
- topic `<APNS_BUNDLE_ID>.voip`
- `authorization: bearer <ES256 JWT>`, signed with the `.p8` key, cached for 50 minutes
  (Apple requires a refresh at least hourly and no more than once per 20 minutes)
- HTTP/2 session is cached per instance and re-opened on `error` / `close` / `goaway`

If APNs config is missing, iOS pushes are **skipped with a warning** — Android delivery and the
call state machine keep working.

## Configuration

### 1. Obtain an APNs auth key (`.p8`)

1. Sign in at <https://developer.apple.com/account> as an **Account Holder** or **Admin**.
2. Go to **Certificates, Identifiers & Profiles → Keys → +** (Create a key).
3. Name it (e.g. `Metadata VoIP APNs`), tick **Apple Push Notifications service (APNs)**, Continue → Register.
4. **Download** `AuthKey_XXXXXXXXXX.p8`. Apple lets you download it exactly once — store it in a
   password manager. Never commit it.
5. Note the **Key ID** (the 10 characters in the filename) and your **Team ID**
   (Apple Developer → Membership details).
6. Ensure the App ID `com.example.metadata` has the **Push Notifications** capability, and the
   Xcode target enables **Push Notifications** + **Background Modes → Voice over IP**.

> The same key works for sandbox and production. `APNS_PRODUCTION` selects the host:
> `false` → `api.sandbox.push.apple.com` (debug builds), `true` → `api.push.apple.com`
> (TestFlight / App Store builds).

### 2. Store the private key as a secret

> **Do this before the first `firebase deploy --only functions`.** `onCallCreated` and
> `onCallStatusChanged` declare `secrets: [APNS_AUTH_KEY]`, so the secret must exist in Secret
> Manager or the deploy fails (interactive deploys offer to create it; CI deploys just error).
> If you are not ready to wire up iOS yet, set it to any placeholder that contains a PEM body, or
> temporarily remove `secrets: APNS_SECRETS` from the two trigger option objects.

```bash
cd "/Users/riasatali/Personal Project/metadata"

# From the downloaded file (recommended):
firebase functions:secrets:set APNS_AUTH_KEY --project metadata-64577 --data-file ./AuthKey_XXXXXXXXXX.p8

# Or pipe it in:
cat ./AuthKey_XXXXXXXXXX.p8 | firebase functions:secrets:set APNS_AUTH_KEY --project metadata-64577

# Or run interactively and paste the whole file including the BEGIN/END lines:
firebase functions:secrets:set APNS_AUTH_KEY --project metadata-64577
```

Verify / manage:

```bash
firebase functions:secrets:access APNS_AUTH_KEY --project metadata-64577
firebase functions:secrets:describe APNS_AUTH_KEY --project metadata-64577
firebase functions:secrets:prune --project metadata-64577      # delete unused versions
```

The value must include the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines;
`resolveApnsConfig()` rejects anything else and falls back to skipping iOS pushes.

Secret Manager requires the **Blaze** plan and the Secret Manager API enabled:

```bash
gcloud services enable secretmanager.googleapis.com --project metadata-64577
```

### 3. Set the non-secret params

Create `functions/.env.metadata-64577` (copy `functions/.env.example`):

```dotenv
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=YYYYYYYYYY
APNS_BUNDLE_ID=com.example.metadata
APNS_PRODUCTION=false
```

```bash
cp functions/.env.example functions/.env.metadata-64577
$EDITOR functions/.env.metadata-64577
```

`.env.metadata-64577` is applied only when deploying to `metadata-64577`; `functions/.env` applies
to every project. Both are non-secret and safe to commit. Anything matching `*.local` is gitignored.

All four params have defaults, so deploying without them never prompts — it just logs
`apns.not_configured` and skips iOS.

### 4. Enable the scheduler

`sweepStaleCalls` needs Cloud Scheduler (Blaze plan):

```bash
gcloud services enable cloudscheduler.googleapis.com --project metadata-64577
```

## Deploy

```bash
cd "/Users/riasatali/Personal Project/metadata"

# Everything in this backend
firebase deploy --only functions,firestore:rules,firestore:indexes --project metadata-64577

# Functions only (runs the lint + build predeploy hooks)
firebase deploy --only functions --project metadata-64577

# A single function
firebase deploy --only functions:onCallCreated --project metadata-64577

# Rules / indexes only
firebase deploy --only firestore:rules --project metadata-64577
firebase deploy --only firestore:indexes --project metadata-64577
```

The `firestore:indexes` deploy is **required before `sweepStaleCalls` can work** — it needs the
composite index `calls(status ASC, createdAt ASC)`.

## Local development

```bash
cd functions
nvm use 20
npm install
npm run lint
npm run build         # or: npm run typecheck
npm run serve         # functions emulator
firebase functions:log --project metadata-64577
```

Node 20 is required (`engines.node`). Deploys from a different local Node major will warn.

## Data contracts

### `users/{uid}/devices/{deviceId}`

```
{ token, voipToken?, platform: 'ios' | 'android', appVersion, deviceModel?, updatedAt }
```

Android devices need `token`; iOS devices need `voipToken` (and may also carry `token`).
Dead FCM tokens delete the device doc; APNs-rejected VoIP tokens only clear the `voipToken` field.

### `calls/{callId}`

Statuses: `initiating, ringing, accepted, connecting, connected, rejected, cancelled, missed,
ended, failed`. Terminal: `rejected, cancelled, missed, ended, failed`.

Signaling lives under `calls/{callId}/signaling/{offer|answer}`,
`calls/{callId}/callerCandidates/*`, `calls/{callId}/receiverCandidates/*`.

### `phone_index/{normalizedPhone}`

`{ uid, displayName, photoUrl, updatedAt }` — server-maintained only, `allow read, write: if false`.
The id is the phone number with all non-digits stripped, keeping the **last 10** digits when more
than 10 remain. This must stay identical to `lib/utils/phone_number.dart`.

### Push payloads

Incoming call, Android (data-only, `priority: high`, `ttl: 60000`, all values strings):

```json
{"type":"incoming_call","callId":"...","callerId":"...","callerName":"...","callerPhotoUrl":"...","callType":"audio"}
```

Incoming call, iOS PushKit:

```json
{"callId":"...","callerId":"...","callerName":"...","callerPhotoUrl":"...","callType":"audio"}
```

Call ended, Android: `{"type":"call_ended","callId":"...","status":"ended"}`

Call ended, iOS PushKit: `{"callId":"...","callType":"audio","ended":"true"}` — iOS **must** report
a call to CallKit for every VoIP push, so on `ended === "true"` the app reports the call and ends it
immediately.

## Troubleshooting

| Log event | Meaning |
| --- | --- |
| `apns.not_configured` | One of the APNs params/secret is empty; iOS pushes skipped |
| `apns.jwt_sign_failed` | The `.p8` contents are malformed or truncated |
| `apns.connect_failed` | Cannot reach APNs (check egress / host selection) |
| `apns.send_failed` reason `BadDeviceToken` | Sandbox vs production mismatch → check `APNS_PRODUCTION` |
| `apns.send_failed` reason `TopicDisallowed` | `APNS_BUNDLE_ID` wrong, or the App ID lacks push capability |
| `sweepStaleCalls.query_failed` | The `calls(status, createdAt)` composite index is missing |
| `phoneIndex.owned_by_other_uid` | Two accounts claim the same number; the first owner keeps the index |
