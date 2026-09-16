/**
 * Shapes mirrored from the Flutter app's models so the dashboard reads the
 * same documents without a translation layer:
 *   users/{uid}                             -> lib/models/user_profile.dart
 *   users/{uid}/contacts/{id}               -> lib/models/contact_model.dart
 *   users/{uid}/contacts/{id}/notes/{id}    -> lib/models/note_entry.dart
 *   support_tickets/{id}                    -> lib/models/support_ticket_model.dart
 *
 * Fields the mobile app does not write yet are marked NEW and always fall
 * back to a safe default, so nothing renders as broken before the app catches
 * up. See web-admin/README.md for the list.
 */

export type PlanTier = 'free' | 'pro';

export interface AppUser {
  uid: string;
  displayName: string;
  phoneNumber: string;
  photoUrl?: string;
  createdAt: Date | null;
  lastActiveAt: Date | null;
  /** NEW — absent on app-written docs, defaults to 'free'. */
  plan: PlanTier;
  /** NEW — set by this dashboard's Block action. */
  isBlocked: boolean;
  /** NEW — free-text admin annotation shown in the Note column. */
  note?: string;
}

/** Location and last-activity for a user row, derived from their contacts. */
export interface AppUserActivity {
  location: string;
  lastUsedAt: Date | null;
}

export type AppUserRow = AppUser & Partial<AppUserActivity>;

export interface ContactLocation {
  lat: number;
  lng: number;
  address?: string;
  placeName?: string;
}

export interface Contact {
  id: string;
  /** Owning user — recovered from the document path on collection-group reads. */
  ownerUid: string;
  fullName: string;
  phoneNumber: string;
  notes?: string;
  photoUrl?: string;
  role?: string;
  source: 'manual' | 'device';
  location: ContactLocation | null;
  eventDate: Date | null;
  createdAt: Date | null;
  updatedAt: Date | null;
  isFavorite: boolean;
  isBlocked: boolean;
  capturesContext: boolean;
}

/**
 * One row of a contact's Timeline, mirroring the Flutter `TimelineEntry` at
 * `users/{uid}/contacts/{contactId}/timeline`.
 */
export interface TimelineEntry {
  id: string;
  /** Short kicker above the title — "FIRST MET", "COFFEE CHAT". */
  label: string;
  title: string;
  subtitle: string;
  date: Date | null;
  createdAt: Date | null;
  role?: string;
  lat: number | null;
  lng: number | null;
}

/** A note at `users/{uid}/contacts/{contactId}/notes`. */
export interface ContactNote {
  id: string;
  text: string;
  createdAt: Date | null;
}

export type TicketStatus = 'pending' | 'waiting' | 'completed';

export interface SupportTicket {
  id: string;
  uid: string;
  name: string;
  email: string;
  subject: string;
  message: string;
  status: TicketStatus;
  createdAt: Date | null;
  /** NEW — human ticket number; falls back to a short ref of the doc id. */
  ticketNo?: string;
}

export interface TicketMessage {
  id: string;
  from: 'user' | 'admin';
  authorName: string;
  authorEmail?: string;
  text: string;
  createdAt: Date | null;
}

export interface StatDelta {
  /** Percent change against the previous period; null when not computable. */
  percent: number | null;
  direction: 'up' | 'down' | 'flat';
}

/**
 * Every figure is independently nullable: one read failing — a missing index,
 * most often — must not take the whole dashboard down with it, so a tile whose
 * own query failed reports null and the rest of the page still renders.
 */
export interface DashboardStats {
  allContacts: number | null;
  encounters: number | null;
  placesVisited: number | null;
  notesAdded: number | null;
  freePlans: number | null;
  proPlans: number | null;
  deltas: Partial<Record<keyof Omit<DashboardStats, 'deltas' | 'issues'>, StatDelta>>;
  /** One de-duplicated operator-readable line per read that failed. */
  issues: string[];
}

export type ChartRange = 'week' | 'month' | 'year';

export interface ChartPoint {
  /** Axis label — "Sun".."Sat" for a week, "1".."31" for a month, months for a year. */
  label: string;
  current: number;
  previous: number;
}

export interface SupportStats {
  todaySubmissions: number;
  pending: number;
  waiting: number;
  completed: number;
}

export interface UserContactStats {
  total: number;
  /** Contacts whose context capture finished — a location was recorded. */
  completed: number;
  /** Saved, but still missing the captured location. */
  pending: number;
}

export interface Page<T> {
  rows: T[];
  /** Total matching rows, when the backend can count them cheaply. */
  total: number | null;
}

/**
 * The four tabs a role can be granted. Enforced twice: the nav only renders
 * the tabs a role holds, and firestore.rules independently checks the same
 * flag on every read/write those tabs make — see `hasPermission()` there.
 */
export type Permission = 'dashboard' | 'users' | 'support' | 'administration';

/** `roles/{id}` — id doubles as a stable key, e.g. `super_admin`. */
export interface Role {
  id: string;
  name: string;
  permissions: Permission[];
  /**
   * True only for the seeded Super Admin role. It can be renamed but never
   * deleted, and its 'administration' permission can never be removed —
   * losing the last role that can reach Administration would lock everyone
   * out of role management with no way back in from the UI.
   */
  isSystem: boolean;
  createdAt: Date | null;
}

/** A row in the Administrators table — the admins/{uid} doc plus its resolved role. */
export interface Administrator {
  uid: string;
  name: string;
  email: string;
  photoUrl?: string;
  roleId: string | null;
  /** Null when roleId points at a role that no longer exists. */
  roleName: string | null;
  createdAt: Date | null;
}
