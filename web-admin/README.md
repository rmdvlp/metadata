# Context ID — Admin Web Dashboard

Responsive admin console for the Context ID mobile app, on the **same Firebase
project** (`metadata-64577`). It reads the documents the Flutter app writes:
no separate backend, no data copy.

React 18 · TypeScript · Vite 6 · Tailwind 3 · Firebase JS SDK 11

| Screen | Route | Reads |
|---|---|---|
| Sign in | `/login` | Firebase Auth (email + password) + `admins/{uid}` |
| Forgot password | `/forgot-password` | Firebase Auth reset email |
| Dashboard | `/dashboard` | count aggregates over `contacts` / `notes` / `users` |
| Users | `/users` | `users` (paged, filtered) |
| User detail | `/users/:uid` | `users/{uid}` + `users/{uid}/contacts` |
| Support | `/support` | `support_tickets` + `support_tickets/{id}/messages` (live) |

---

## 1. Run it

```bash
cd web-admin
npm install
cp .env.example .env.local     # then fill in the two TODO values
npm run dev                    # opens http://localhost:5173 in your browser
```

`npm run dev` opens the browser itself. If `.env.local` is missing or
incomplete the app renders setup instructions instead of a blank page.

**Node 18.18+ is required** (Vite 6). This repo's default is 18.19.1, which
works; 20 or 22 also work.

### Getting the two TODO values

> **Already done for `metadata-64577`.** The Web app "Context ID Admin"
> (`1:823490823169:web:2036b08b8ec832fe10ac00`) is registered and
> `.env.local` is filled in. This section is for a fresh clone or a
> different project.

The mobile app's `lib/firebase_options.dart` has Android and iOS credentials
only — a browser needs a **Web** app registration.

Either:

```bash
npx firebase-tools apps:create web "Context ID Admin" --project metadata-64577
npx firebase-tools apps:sdkconfig web <the-new-app-id> --project metadata-64577
```

…or in the [Firebase console](https://console.firebase.google.com/project/metadata-64577/settings/general):
**Project settings → Your apps → Add app → Web (`</>`)**, then copy `apiKey`
and `appId` out of the config snippet.

These values are not secrets — a Vite client ships everything it holds. Access
is enforced by `firestore.rules` and the `admins/{uid}` document, not by hiding
the config.

## 2. Deploy the rules

The dashboard reads across all users, which the previous rules forbade.

> **Already deployed to `metadata-64577`.** Re-run this after any further
> edit to the rules.

```bash
cd ..
firebase deploy --only firestore:rules,firestore:indexes
```

Without this every screen shows a permission error naming this step.
What changed in `firestore.rules`:

- an `isAdmin()` predicate — true when `admins/{request.auth.uid}` exists;
- admin `read` on `/users/**` and `/support_tickets/**`, admin `update` on
  user documents and ticket status;
- collection-group rules for `contacts` and `notes` (a `collectionGroup()`
  query is matched against `/{path=**}/contacts/{id}`, *not* against the
  nested blocks, so the dashboard's cross-user totals need their own rule);
- an append-only `support_tickets/{id}/messages` subcollection;
- **a bug fix unrelated to the dashboard:** `users/{uid}/contacts/{id}/notes`
  had no rule at all, so it fell through to the closing `deny` — the mobile
  app's multi-note writes were being rejected. It now mirrors `timeline`.

`firestore.indexes.json` gains two kinds of entry.

**Three composite indexes**, used only by the Users screen's plan/status
filters.

**Four single-field overrides** — these are the ones that matter, and the
reason a fresh project throws `failed-precondition` on the dashboard until they
are deployed:

| Collection group | Field | Scope added |
| --- | --- | --- |
| `contacts` | `createdAt` | `COLLECTION_GROUP` ASC + DESC |
| `contacts` | `capturesContext` | `COLLECTION_GROUP` ASC |
| `contacts` | `location` | `COLLECTION_GROUP` ASC |
| `notes` | `createdAt` | `COLLECTION_GROUP` ASC + DESC |

Firestore indexes every field automatically, but **only at `COLLECTION`
scope**. The dashboard reads across all users with `collectionGroup()`, and a
collection-group query is served exclusively by a `COLLECTION_GROUP`-scope
index, which has to be requested by hand. That is a *single-field* index
exemption, not a composite one — which is why the console link in the error
message says `create_exemption`.

One trap when editing that block: declaring an override **replaces** automatic
indexing for that field. Each entry above therefore restates the two
`COLLECTION`-scope orders as well, because dropping them would silently break
the mobile app's own per-user `orderBy('createdAt')` queries. If you add a
field, restate its `COLLECTION` orders too.

Deploy with `firebase deploy --only firestore:indexes`. Builds run in the
background — the queries keep failing for a minute or two afterwards, which is
normal and not a misconfiguration.

## 3. Create the first administrator

Signing in is not enough: the account also needs an `admins/{uid}` document
whose `roleId` points at a real `roles/{id}` document — see [Roles &
Administration](#4-roles--administration) for what that means. Every
administrator **after** the first one is added from the **Administration**
tab in the dashboard itself; these scripts exist only to bootstrap the very
first account, before there is anyone signed in yet to click "Add
Administrator".

Email/Password sign-in is already enabled on this project, so pick whichever
route suits you, then run `npm run seed:roles -- <email> <password>` once
(below) to create the three built-in roles and grant that account Super
Admin.

**Without a service-account key** — creates the Auth account and prints the
UID for the one document you add in the console:

```bash
npm run create:admin-user -- admin@example.com 'a-strong-password' 'Smith John'
```

You'll still need to add the printed `admins/{uid}` document by hand (see the
script's own output), then run `seed:roles` below.

**With a service-account key** — does both halves at once:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
npm run seed:admin -- admin@example.com 'a-strong-password' 'Smith John'
```

A signed-in account whose `admins/{uid}` document does not exist, or exists
but names a role no one can find, is signed straight back out ("This account
does not have dashboard access." / a "No dashboard access" screen) — so a
mobile user who somehow reaches the console never sees the chrome, and a role
mix-up never renders half a page.

---

## 4. Roles & Administration

Three built-in roles, seeded once by `npm run seed:roles` (see above) and
editable — indeed replaceable — from the **Administration** tab afterwards:

| Role | Tabs it can reach |
| --- | --- |
| **Super Admin** | Dashboard, Users, Support, **Administration** |
| **Admin** | Dashboard, Users, Support |
| **Support** | Support only |

**Administration is the one tab a role's permissions have to include by
name** — an Admin has every operational tab Super Admin has, but never sees
Administration itself, by design. Everything else is a plain permission a
role either holds or doesn't; a Super Admin can create further roles with any
combination (e.g. a "Viewer" role holding only Dashboard).

**This is enforced twice, not once.** The nav in `TopNav.tsx` and the route
guards in `App.tsx` hide what a role can't reach, but that alone is a UI
nicety a browser's dev tools can see straight through. `firestore.rules`
independently checks the same permission on every read and write those tabs
make (`hasPermission('users')`, `hasPermission('support')`, …) — a
Support-only account querying Firestore directly gets `permission-denied` on
`users`/`contacts`, not just a blank nav item. See the block above
`match /admins/{uid}` in `firestore.rules` for the two functions this runs on:
`hasPermission()` and the self-closing `rolesNotYetSeeded()` bootstrap that
made the very first seeding possible with zero manual Firestore edits.

**A few rules that hold everywhere in this system:**

- **Self-profile editing is universal.** Every role can edit its own name and
  send itself a password-reset email from **My Profile** (top-right menu).
  None of them — including Super Admin — can change their *own* role through
  that path; `firestore.rules` refuses a self-update that touches `roleId`.
  Changing someone's role is only ever done to *another* account, from
  Administration → Administrators → Change role.
- **Adding an administrator never signs you out.** Creating the new person's
  sign-in credentials happens on a disposable secondary `FirebaseApp`
  instance (`lib/secondaryAuth.ts`) so the super admin doing the inviting
  keeps their own session. The new administrator gets a password-reset email
  and picks their own password — no temporary password is ever shown,
  stored, or sent.
- **"Remove access" does not delete the Firebase Authentication account.**
  It deletes the `admins/{uid}` document, which is all a client-only console
  can do without the Admin SDK. The person's login credentials still exist;
  if that account should stop existing entirely, delete it under
  **Authentication → Users** in the Firebase console as a separate step.
- **A role in use can't be deleted.** The Roles tab shows how many
  administrators hold each role and disables Delete while that count is
  above zero (re-checked live, right before the delete, in case someone
  else assigned it seconds earlier from another session) — and the Super
  Admin role can never be deleted or stripped of its Administration
  permission at all, since that would be the one mistake with no way back in
  from the UI.

---

## Data mapping

Every screen reads live Firestore. Where the design shows a field the mobile
app does not write yet, the value is **derived** or falls back to `—`; nothing
is mocked.

### Derived, not stored

| Design label | How it is computed |
|---|---|
| Encounters | contacts with `capturesContext == true` |
| Places Visited | contacts with a non-null `location` |
| Notes Added | documents in the `notes` collection group |
| Ticket / `#3245` | last 4 characters of the document id (`shortRef`) |
| Users → Location / Last Use | that user's most recently updated contact |
| Detail → Completed | contacts that finished capture (have a `location`) |
| Detail → Pending | contacts saved without a location |
| Detail → Active | `lastActiveAt` within the last 7 days |
| `TK-1031` | `ticketNo` if present, else `TK-` + last 4 of the doc id |
| Chart comparison line | the same buckets one period earlier |

### Fields this dashboard introduces

These are written by the console and read back by it. The Flutter app ignores
them, so nothing breaks in either direction — but until the app writes them,
`plan` reads as `free` and the Note column is empty.

| Path | Field | Purpose |
|---|---|---|
| `users/{uid}` | `plan: 'free' \| 'pro'` | Free/Pro Plans tiles, Pro badge, plan filter |
| `users/{uid}` | `isBlocked: boolean` | Block button, Blocked badge |
| `users/{uid}` | `note: string` | the Note column |
| `support_tickets/{id}` | `status: 'pending' \| 'waiting' \| 'completed'` | inbox tabs |
| `support_tickets/{id}/messages/{id}` | `from`, `authorName`, `authorEmail`, `text`, `createdAt` | the reply thread |

The app creates tickets with `status: 'open'`; the dashboard treats `open` and
`pending` as the same unworked state, so no migration is needed.

`users/{uid}/contacts/{id}.isBlocked` already exists in the app — the design's
red **Quarantine** badge renders exactly that flag.

### Query costs

- **Totals** use `getCountFromServer`, billed per 1,000 index entries — a
  handful of reads however large the collections grow.
- **Chart and stat deltas** share one windowed collection-group scan, capped
  at 5,000 documents. Past that the UI says the figures are partial rather
  than silently under-reporting.
- **Pagination** is `limit(page × pageSize)` with the last page sliced off,
  because Firestore has no offset. One round trip per page; page *N* reads
  *N × 18* documents. Fine at hundreds-to-low-thousands of users — revisit if
  the directory reaches six figures.
- **Search** scans the 500 most recent rows and filters in the browser, since
  Firestore cannot do substring matching and the design's box searches name,
  number *and* location at once. The UI warns when the cap is hit.

## Layout / responsiveness

One breakpoint ladder, no separate mobile build:

| Width | Behaviour |
|---|---|
| `< 768px` | hamburger nav; tables become stacked cards; support shows list **or** thread |
| `768–1023px` | inline nav; tables with `Location`/`Time`/`Note` dropped; support still stacks |
| `1024–1279px` | header search appears; support splits into directory + thread |
| `≥ 1280px` | stat grid and chart sit side by side; every table column visible |

The chart measures its own container with a `ResizeObserver` and redraws in
real pixels, so strokes never distort.

## Notes on the design

Three labels in the Figma read as typos and were corrected; say the word and
they go back:

| Figma | Here |
|---|---|
| "Encounter Our Time" | "Encounters Over Time" |
| "Resent Contacts" | "Recent Contacts" |
| "Replay" (send button) | "Reply" |

Two deliberate additions, both accessibility-driven:

- **A legend on the chart.** The design draws a second, grey comparison curve
  with nothing naming it. Two series identified by colour alone is not
  readable for a colourblind viewer, so a two-item legend and a "View as
  table" disclosure were added.
- **A visible focus ring.** The design shows none; keyboard users need one.
  It appears on `:focus-visible` only, so it never shows on a mouse click.

The y-axis is a real linear scale with rounded ticks. The Figma's axis
(`1k+, 500, 150, 100, 50, 10`) is not linearly spaced, which would misplace
every point on the curve.

## Layout of the source

```
src/
├── App.tsx                  routes + the admin gate
├── lib/
│   ├── firebase.ts          SDK init; reports config gaps via `configError`
│   ├── auth.tsx             AuthProvider, the admins/{uid} check
│   ├── useAsync.ts          read lifecycle, discards stale results
│   ├── firestoreError.ts    rules/index failures -> actionable text
│   └── format.ts            dates, counts, initials, short refs
├── data/                    every Firestore query lives here
│   ├── types.ts             shapes mirrored from the Flutter models
│   ├── mappers.ts           snapshot -> typed object
│   ├── ranges.ts            week/month/year bucketing
│   ├── dashboard.ts  users.ts  tickets.ts
├── components/
│   ├── icons.tsx            hand-rolled outline set, no icon dependency
│   ├── ui/                  Button, Input, DataTable, Pagination, Modal, …
│   ├── layout/              AppShell, TopNav, AuthCard
│   └── charts/              EncountersChart + monotone curve maths
└── pages/                   one file per screen
```

`data/` is the only layer that talks to Firestore. Pages never import
`firebase/firestore` directly.

## Scripts

| Command | Does |
|---|---|
| `npm run dev` | dev server, opens the browser |
| `npm run build` | typecheck + production bundle into `dist/` |
| `npm run preview` | serve the built bundle |
| `npm run typecheck` | types only |
| `npm run test` | run the unit tests (curve maths, bucketing, mappers, pager, permissions) |
| `npm run create:admin-user` | create an admin's Auth account, no key needed |
| `npm run seed:admin` | create the account **and** its `admins/{uid}` doc (needs a key) |
| `npm run seed:roles` | one-time: create the 3 built-in roles, grant one account Super Admin |
