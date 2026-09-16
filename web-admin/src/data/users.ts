import {
  collection,
  collectionGroup,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  updateDoc,
  where,
  type Query,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import {
  mapContact,
  mapContactNote,
  mapTimelineEntry,
  mapUser,
  type Snap,
} from './mappers';
import type {
  AppUser,
  AppUserActivity,
  Contact,
  ContactNote,
  Page,
  PlanTier,
  TimelineEntry,
  UserContactStats,
} from './types';

/** Ceiling on a single contact's timeline/notes read — both are small. */
const SUBCOLLECTION_LIMIT = 200;

/**
 * Sort key for a nullable date. The caller picks what a missing date is worth
 * so undated rows land at the end of an ascending *and* a descending sort.
 */
function at(date: Date | null, whenMissing = Number.MAX_SAFE_INTEGER): number {
  return date ? date.getTime() : whenMissing;
}

/**
 * Firestore has no offset operator, so a jump to page N is served by one
 * `limit(N * pageSize)` read whose last page is sliced off. That reads
 * N * pageSize documents for page N — fine for an admin console over
 * hundreds-to-low-thousands of users, and it keeps the design's numbered
 * pager honest (a cursor-only pager could offer next/prev but not "page 47").
 */
async function pageOf<T>(
  build: (take: number) => Query,
  map: (doc: Snap) => T,
  page: number,
  pageSize: number,
): Promise<T[]> {
  const snap = await getDocs(build(page * pageSize));
  return snap.docs.slice((page - 1) * pageSize).map(map);
}

/** Rows scanned when a search term is active — see `fetchUsers`. */
const SEARCH_SCAN_LIMIT = 500;

function matches(haystacks: Array<string | undefined>, needle: string): boolean {
  const term = needle.trim().toLowerCase();
  if (!term) return true;
  return haystacks.some((h) => (h ?? '').toLowerCase().includes(term));
}

/**
 * Firestore cannot do substring search, and the design's box searches name,
 * number *and* location at once. So a search scans up to
 * `SEARCH_SCAN_LIMIT` recent users and filters in the browser, which gives
 * true "contains" matching over all three fields. Beyond that ceiling the
 * result is capped rather than wrong, and the UI says so.
 */
export async function fetchUsers(options: {
  page: number;
  pageSize: number;
  search?: string;
  plan?: PlanTier | 'all';
  blocked?: boolean | 'all';
}): Promise<Page<AppUser> & { capped: boolean }> {
  const { page, pageSize, search = '', plan = 'all', blocked = 'all' } = options;
  const usersRef = collection(db, 'users');
  const filters = [
    ...(plan !== 'all' ? [where('plan', '==', plan)] : []),
    ...(blocked !== 'all' ? [where('isBlocked', '==', blocked)] : []),
  ];
  const isFiltered = search.trim().length > 0;

  if (isFiltered) {
    const snap = await getDocs(
      query(usersRef, ...filters, orderBy('createdAt', 'desc'), limit(SEARCH_SCAN_LIMIT)),
    );
    const all = snap.docs
      .map(mapUser)
      .filter((u) => matches([u.displayName, u.phoneNumber, u.note], search));
    return {
      rows: all.slice((page - 1) * pageSize, page * pageSize),
      total: all.length,
      capped: snap.size === SEARCH_SCAN_LIMIT,
    };
  }

  const [rows, count] = await Promise.all([
    pageOf(
      (take) => query(usersRef, ...filters, orderBy('createdAt', 'desc'), limit(take)),
      mapUser,
      page,
      pageSize,
    ),
    getCountFromServer(query(usersRef, ...filters)),
  ]);

  return { rows, total: count.data().count, capped: false };
}

/**
 * Location and last-use are not on the user document — they live on the
 * contacts the user captured. One tiny read per row fills the two columns the
 * design shows; it runs after the table has already painted so the rows never
 * wait on it.
 */
export async function fetchUserActivity(
  uids: string[],
): Promise<Record<string, AppUserActivity>> {
  const entries = await Promise.all(
    uids.map(async (uid) => {
      try {
        const snap = await getDocs(
          query(
            collection(db, 'users', uid, 'contacts'),
            orderBy('updatedAt', 'desc'),
            limit(1),
          ),
        );
        const latest = snap.docs[0] ? mapContact(snap.docs[0]) : null;
        return [
          uid,
          {
            location:
              latest?.location?.placeName ?? latest?.location?.address ?? '—',
            lastUsedAt: latest?.updatedAt ?? null,
          },
        ] as const;
      } catch {
        return [uid, { location: '—', lastUsedAt: null }] as const;
      }
    }),
  );

  return Object.fromEntries(entries);
}

export async function fetchUser(uid: string): Promise<AppUser | null> {
  const snap = await getDoc(doc(db, 'users', uid));
  if (!snap.exists()) return null;
  return mapUser(snap);
}

export async function fetchContact(
  uid: string,
  contactId: string,
): Promise<Contact | null> {
  const snap = await getDoc(doc(db, 'users', uid, 'contacts', contactId));
  if (!snap.exists()) return null;
  return mapContact(snap);
}

/**
 * A contact's timeline and notes. Both are read unordered and sorted here:
 * `date` and `createdAt` are optional in the documents the app writes, and an
 * `orderBy` would silently drop every entry missing the field it sorts on.
 * These subcollections hold a handful of rows each, so the cost is nil.
 */
export async function fetchContactTimeline(
  uid: string,
  contactId: string,
): Promise<TimelineEntry[]> {
  const snap = await getDocs(
    query(
      collection(db, 'users', uid, 'contacts', contactId, 'timeline'),
      limit(SUBCOLLECTION_LIMIT),
    ),
  );
  return snap.docs
    .map(mapTimelineEntry)
    .sort((a, b) => at(a.date ?? a.createdAt) - at(b.date ?? b.createdAt));
}

export async function fetchContactNotes(
  uid: string,
  contactId: string,
): Promise<ContactNote[]> {
  const snap = await getDocs(
    query(
      collection(db, 'users', uid, 'contacts', contactId, 'notes'),
      limit(SUBCOLLECTION_LIMIT),
    ),
  );
  return snap.docs
    .map(mapContactNote)
    .sort((a, b) => at(b.createdAt, 0) - at(a.createdAt, 0));
}

/**
 * The three figures on the user-detail header. "Completed" counts contacts
 * that finished context capture (a location was recorded); the rest are still
 * pending — which is what the mobile app's Pending Sync screen surfaces.
 */
export async function fetchUserContactStats(uid: string): Promise<UserContactStats> {
  const contactsRef = collection(db, 'users', uid, 'contacts');
  const [total, completed] = await Promise.all([
    getCountFromServer(contactsRef),
    getCountFromServer(query(contactsRef, where('location', '!=', null))),
  ]);

  const totalCount = total.data().count;
  const completedCount = completed.data().count;
  return {
    total: totalCount,
    completed: completedCount,
    pending: Math.max(0, totalCount - completedCount),
  };
}

export async function fetchUserContacts(options: {
  uid: string;
  page: number;
  pageSize: number;
  search?: string;
}): Promise<Page<Contact> & { capped: boolean }> {
  const { uid, page, pageSize, search = '' } = options;
  const contactsRef = collection(db, 'users', uid, 'contacts');

  if (search.trim()) {
    const snap = await getDocs(
      query(contactsRef, orderBy('updatedAt', 'desc'), limit(SEARCH_SCAN_LIMIT)),
    );
    const all = snap.docs
      .map(mapContact)
      .filter((c) =>
        matches(
          [
            c.fullName,
            c.phoneNumber,
            c.location?.placeName,
            c.location?.address,
            c.role,
            c.notes,
          ],
          search,
        ),
      );
    return {
      rows: all.slice((page - 1) * pageSize, page * pageSize),
      total: all.length,
      capped: snap.size === SEARCH_SCAN_LIMIT,
    };
  }

  const [rows, count] = await Promise.all([
    pageOf(
      (take) => query(contactsRef, orderBy('updatedAt', 'desc'), limit(take)),
      mapContact,
      page,
      pageSize,
    ),
    getCountFromServer(contactsRef),
  ]);

  return { rows, total: count.data().count, capped: false };
}

/** Most recently created contacts across every user — the dashboard table. */
export async function fetchRecentContacts(take = 8): Promise<Contact[]> {
  const snap = await getDocs(
    query(collectionGroup(db, 'contacts'), orderBy('createdAt', 'desc'), limit(take)),
  );
  return snap.docs.map(mapContact);
}

export async function setUserBlocked(uid: string, isBlocked: boolean): Promise<void> {
  await updateDoc(doc(db, 'users', uid), { isBlocked });
}

export async function updateUser(
  uid: string,
  patch: { displayName?: string; phoneNumber?: string; plan?: PlanTier; note?: string },
): Promise<void> {
  await updateDoc(doc(db, 'users', uid), patch);
}

export async function setContactBlocked(
  uid: string,
  contactId: string,
  isBlocked: boolean,
): Promise<void> {
  await updateDoc(doc(db, 'users', uid, 'contacts', contactId), { isBlocked });
}
