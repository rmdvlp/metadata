# Project: Contact/Caller Identity App (Flutter + Firebase)

GitHub Copilot reads this file as repo-wide context for every suggestion and Copilot Chat conversation in this project.

---

## 1. Overview

A mobile app where users log in by phone number, sync their contacts to Firebase,
and can look up saved details about a contact when that contact calls them
(Truecaller-style lookup). A companion admin panel lets an admin see user
activity, view/delete users, and manage user support queries.

Assume the Firebase project is already connected. Do not scaffold a new Firebase project.

---

## 2. Tech stack

### Mobile (Flutter)

- firebase_auth: phone number + OTP auth
- cloud_firestore: user, contact, and query data
- firebase_messaging: push notifications
- firebase_storage: media and files
- firebase_analytics: events and behavior analytics
- flutter_contacts: read device contacts
- permission_handler: runtime permissions (contacts, location, notifications, phone/overlay on Android)
- geolocator: location capture
- riverpod: state management (stay consistent)
- Android-only: native call-detection approach (see section 6)

### Admin panel (React)

- firebase/auth + firebase/firestore for reads
- Cloud Functions for privileged operations
- User deletion must go through callable Cloud Function using firebase-admin

---

## 3. Firestore data model

Use this schema exactly.

users/{uid}

- phoneNumber: string
- name: string
- profilePhotoUrl: string | null
- createdAt: timestamp
- lastActiveAt: timestamp
- status: "active" | "disabled"
- locationPermissionGranted: boolean
- contactsPermissionGranted: boolean
- lastKnownLocation: geopoint | null
- fcmToken: string | null

users/{uid}/contacts/{contactId}

- name: string
- phoneNumbers: array<string>
- source: "device_sync" | "manual"
- note: string | null
- createdAt: timestamp
- updatedAt: timestamp

users/{uid}/settings/notificationPrefs

- callAlerts: boolean
- marketing: boolean
- queryUpdates: boolean

users/{uid}/queries/{queryId}

- subject: string
- message: string
- status: "open" | "in_progress" | "resolved"
- createdAt: timestamp
- adminReply: string | null
- repliedAt: timestamp | null

Design notes:

- Contacts are private in a user subcollection, not top-level.
- Caller lookup first checks users/{currentUid}/contacts.
- Any cross-user lookup requires explicit product confirmation and privacy disclosure.
- lastActiveAt updates on app foreground/session start.

---

## 4. Mobile app screen spec

1. Splash/auth check: existing session goes to Home.
2. Phone entry: send OTP with firebase_auth.
3. OTP verify: verify credential and check users/{uid}.
4. Name entry (first login): create users/{uid}.
5. Permissions screen: rationale first, then OS prompt.
6. Contacts sync: read with flutter_contacts, batch-write to users/{uid}/contacts.
7. Contact detail/edit: update name/number/note.
8. Add contact: manual create with source="manual".
9. Profile: edit name/photo, phone read-only.
10. Settings: bind toggles to users/{uid}/settings/notificationPrefs.
11. Notifications: persistent in-app list.
12. Incoming call lookup: see section 6.

---

## 5. Admin panel spec

- Dashboard: total users, active users (24h/7d), signup trend.
- User list: search by name/phone, sort by lastActiveAt.
- User detail: profile, contact count, query history.
- Delete user via callable deleteUserAccount Cloud Function:
  1. delete auth user
  2. delete users/{uid} and subcollections recursively
- Query inbox: collection group query on queries, status filters, reply support.

---

## 6. Incoming call detection reality

- Android: native CallScreeningService/platform channel approach; policy-sensitive permissions.
- iOS: no live incoming-call interception by third-party app; use Call Directory Extension for labels.
- Plan: Android live overlay first; iOS uses Call Directory + in-app lookup flow.

---

## 7. Security and privacy guardrails

- Firestore rules enforce per-user access under users/{uid}.
- Admin read/write requires admin custom claim in rules: request.auth.token.admin == true.
- Never attempt client-side deletion of another user's auth account.
- Do not implement silent cross-user lookup without explicit opt-in and disclosure.

---

## 8. Suggested Flutter structure

lib/
main.dart
core/
firebase/
permissions/
features/
auth/
contacts/
profile/
settings/
notifications/
call_lookup/
shared/
widgets/
models/

---

## 9. Future scope

Keep models and architecture extensible. Avoid hardcoded enums or assumptions that block future notification/contact/query expansion.
