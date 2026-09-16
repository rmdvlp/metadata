import { Timestamp, type DocumentData } from 'firebase/firestore';
import type {
  AppUser,
  Contact,
  ContactNote,
  Permission,
  PlanTier,
  Role,
  SupportTicket,
  TicketMessage,
  TicketStatus,
  TimelineEntry,
} from './types';

const PERMISSIONS: readonly Permission[] = [
  'dashboard',
  'users',
  'support',
  'administration',
];

/**
 * The subset of a Firestore snapshot the mappers need. Accepting this instead
 * of `QueryDocumentSnapshot` lets `getDoc` and `getDocs` results share one
 * mapper without a cast at each call site.
 */
export interface Snap {
  id: string;
  ref: { path: string };
  data: () => DocumentData | undefined;
}

export function toDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function str(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function optionalStr(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function bool(value: unknown, fallback = false): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function optionalNum(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

/**
 * Mirrors `TimelineEntry.fromFirestore`, with one deliberate difference: the
 * Flutter model falls back to `DateTime.now()` for a missing `date`, which
 * would date an undated entry to whenever the page happened to load. Here it
 * stays null and the row renders without a date.
 */
export function mapTimelineEntry(doc: Snap): TimelineEntry {
  const data = doc.data() ?? {};
  return {
    id: doc.id,
    label: str(data.label),
    title: str(data.title),
    subtitle: str(data.subtitle),
    date: toDate(data.date),
    createdAt: toDate(data.createdAt),
    role: optionalStr(data.role),
    lat: optionalNum(data.lat),
    lng: optionalNum(data.lng),
  };
}

export function mapContactNote(doc: Snap): ContactNote {
  const data = doc.data() ?? {};
  return {
    id: doc.id,
    text: str(data.text),
    createdAt: toDate(data.createdAt),
  };
}

export function mapUser(doc: Snap): AppUser {
  const data = doc.data() ?? {};
  return {
    uid: doc.id,
    displayName: str(data.displayName) || 'Unnamed user',
    phoneNumber: str(data.phoneNumber, '—'),
    photoUrl: optionalStr(data.photoUrl),
    createdAt: toDate(data.createdAt),
    lastActiveAt: toDate(data.lastActiveAt),
    plan: (data.plan === 'pro' ? 'pro' : 'free') as PlanTier,
    isBlocked: bool(data.isBlocked),
    note: optionalStr(data.note),
  };
}

export function mapContact(doc: Snap): Contact {
  const data = doc.data() ?? {};
  const loc = data.location as Record<string, unknown> | null | undefined;

  return {
    id: doc.id,
    // users/{uid}/contacts/{contactId} — segment 1 is the owning uid. On a
    // collection-group read the path is the only place the owner appears.
    ownerUid: doc.ref.path.split('/')[1] ?? '',
    fullName: str(data.fullName) || 'Unnamed contact',
    phoneNumber: str(data.phoneNumber, '—'),
    notes: optionalStr(data.notes),
    photoUrl: optionalStr(data.photoUrl),
    role: optionalStr(data.role),
    source: data.source === 'device' ? 'device' : 'manual',
    location:
      loc && typeof loc.lat === 'number' && typeof loc.lng === 'number'
        ? {
            lat: loc.lat,
            lng: loc.lng,
            address: optionalStr(loc.address),
            placeName: optionalStr(loc.placeName),
          }
        : null,
    eventDate: toDate(data.eventDate),
    createdAt: toDate(data.createdAt),
    updatedAt: toDate(data.updatedAt),
    isFavorite: bool(data.isFavorite),
    isBlocked: bool(data.isBlocked),
    // Docs written before "Save Manually" stopped capturing context have no
    // flag; back then every contact went through capture, hence the true
    // default — same reasoning as ContactModel.fromFirestore.
    capturesContext: bool(data.capturesContext, true),
  };
}

/**
 * The app creates tickets with status 'open' (SupportTicket.toCreateMap), while
 * the dashboard works in the design's three states. 'open' is an unread
 * ticket, which is exactly "pending".
 */
export function normalizeTicketStatus(value: unknown): TicketStatus {
  switch (value) {
    case 'waiting':
      return 'waiting';
    case 'completed':
    case 'resolved':
    case 'closed':
      return 'completed';
    default:
      return 'pending';
  }
}

export function mapTicket(doc: Snap): SupportTicket {
  const data = doc.data() ?? {};
  return {
    id: doc.id,
    uid: str(data.uid),
    name: str(data.name) || 'Unknown sender',
    email: str(data.email, '—'),
    subject: str(data.subject) || 'No subject',
    message: str(data.message),
    status: normalizeTicketStatus(data.status),
    createdAt: toDate(data.createdAt),
    ticketNo: optionalStr(data.ticketNo),
  };
}

/**
 * Filters the stored array down to recognized permission strings, so a role
 * document edited by hand with a typo degrades to "grants less than it looks
 * like" rather than to a value `'x' in permissions` can't safely compare.
 */
export function mapRole(doc: Snap): Role {
  const data = doc.data() ?? {};
  const stored = Array.isArray(data.permissions) ? data.permissions : [];
  return {
    id: doc.id,
    name: str(data.name) || 'Untitled role',
    permissions: PERMISSIONS.filter((permission) => stored.includes(permission)),
    isSystem: bool(data.isSystem),
    createdAt: toDate(data.createdAt),
  };
}

export function mapTicketMessage(doc: Snap): TicketMessage {
  const data = doc.data() ?? {};
  return {
    id: doc.id,
    from: data.from === 'admin' ? 'admin' : 'user',
    authorName: str(data.authorName) || (data.from === 'admin' ? 'Admin' : 'User'),
    authorEmail: optionalStr(data.authorEmail),
    text: str(data.text),
    createdAt: toDate(data.createdAt),
  };
}
