import {
  collection,
  collectionGroup,
  getCountFromServer,
  getDocs,
  limit,
  orderBy,
  query,
  Timestamp,
  where,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { mapContact, mapUser, toDate } from './mappers';
import { monthOverMonthWindows, rangeSpec } from './ranges';
import { percentChange } from '@/lib/format';
import { firestoreErrorMessage } from '@/lib/firestoreError';
import type {
  ChartPoint,
  ChartRange,
  DashboardStats,
  StatDelta,
} from './types';

/**
 * Ceiling on the windowed contact scan behind the chart and the contact
 * deltas. One query serves both, so the cap is generous; when it is hit the
 * caller is told and the UI marks the figures as partial rather than quietly
 * under-reporting.
 */
const WINDOW_SCAN_LIMIT = 5000;

function delta(current: number, previous: number): StatDelta {
  const percent = percentChange(current, previous);
  return {
    percent,
    direction: percent === null || percent === 0 ? 'flat' : percent > 0 ? 'up' : 'down',
  };
}

async function countOf(q: ReturnType<typeof query>): Promise<number> {
  const snap = await getCountFromServer(q);
  return snap.data().count;
}

/**
 * Runs one read and absorbs its failure into `issues` instead of rejecting.
 * These reads are independent, so the dashboard should lose only the figures
 * whose own query broke — collapsing the entire page because a single
 * collection-group index is missing tells the operator nothing they can act on
 * and hides the five numbers that were fetched perfectly well.
 */
async function attempt<T>(
  what: string,
  run: () => Promise<T>,
  issues: string[],
): Promise<T | null> {
  try {
    return await run();
  } catch (error) {
    issues.push(firestoreErrorMessage(error, what));
    return null;
  }
}

/**
 * The six tiles above the chart. Totals come from Firestore's count aggregate
 * (billed per 1000 index entries, so a handful of reads however large the
 * collection gets); the "last month" deltas come from two 30-day windows.
 */
export async function fetchDashboardStats(): Promise<DashboardStats> {
  const contacts = collectionGroup(db, 'contacts');
  const notes = collectionGroup(db, 'notes');
  const users = collection(db, 'users');
  const { currentStart, previousStart } = monthOverMonthWindows();
  const currentTs = Timestamp.fromDate(currentStart);
  const previousTs = Timestamp.fromDate(previousStart);

  // `attempt` never rejects, so these still run in parallel but one missing
  // index can no longer sink the other nine reads.
  const issues: string[] = [];
  const [
    allContacts,
    encounters,
    placesVisited,
    notesAdded,
    totalUsers,
    proPlans,
    notesCurrent,
    notesPrevious,
    windowRows,
    userRows,
  ] = await Promise.all([
    attempt('the contact total', () => countOf(contacts), issues),
    attempt(
      'the encounters total',
      () => countOf(query(contacts, where('capturesContext', '==', true))),
      issues,
    ),
    attempt(
      'the places-visited total',
      () => countOf(query(contacts, where('location', '!=', null))),
      issues,
    ),
    attempt('the notes total', () => countOf(notes), issues),
    attempt('the user total', () => countOf(users), issues),
    attempt(
      'the Pro plan total',
      () => countOf(query(users, where('plan', '==', 'pro'))),
      issues,
    ),
    attempt(
      'this month’s notes',
      () => countOf(query(notes, where('createdAt', '>=', currentTs))),
      issues,
    ),
    attempt(
      'last month’s notes',
      () =>
        countOf(
          query(
            notes,
            where('createdAt', '>=', previousTs),
            where('createdAt', '<', currentTs),
          ),
        ),
      issues,
    ),
    // One scan covers the three contact deltas. Splitting them into six count
    // aggregates would each need a composite index on the collection group,
    // and `location != null` combined with a createdAt range would need a
    // multi-inequality index on top of that.
    attempt(
      'the monthly contact comparison',
      () =>
        getDocs(
          query(
            contacts,
            where('createdAt', '>=', previousTs),
            orderBy('createdAt', 'desc'),
            limit(WINDOW_SCAN_LIMIT),
          ),
        ),
      issues,
    ),
    attempt(
      'the monthly plan comparison',
      () =>
        getDocs(
          query(
            users,
            where('createdAt', '>=', previousTs),
            orderBy('createdAt', 'desc'),
            limit(WINDOW_SCAN_LIMIT),
          ),
        ),
      issues,
    ),
  ]);

  const scanned = windowRows ? windowRows.docs.map(mapContact) : null;
  const inCurrent = (at: Date | null) => at !== null && at >= currentStart;
  const inPrevious = (at: Date | null) =>
    at !== null && at >= previousStart && at < currentStart;

  const contactsCurrent = scanned?.filter((c) => inCurrent(c.createdAt));
  const contactsPrevious = scanned?.filter((c) => inPrevious(c.createdAt));
  const newUsers = userRows ? userRows.docs.map(mapUser) : null;

  // A delta is only meaningful if its scan came back; otherwise the tile shows
  // its total with no trend line rather than a fabricated 0%.
  const contactDeltas =
    contactsCurrent && contactsPrevious
      ? {
          allContacts: delta(contactsCurrent.length, contactsPrevious.length),
          encounters: delta(
            contactsCurrent.filter((c) => c.capturesContext).length,
            contactsPrevious.filter((c) => c.capturesContext).length,
          ),
          placesVisited: delta(
            contactsCurrent.filter((c) => c.location !== null).length,
            contactsPrevious.filter((c) => c.location !== null).length,
          ),
        }
      : {};

  const planDeltas = newUsers
    ? {
        proPlans: delta(
          newUsers.filter((u) => u.plan === 'pro' && inCurrent(u.createdAt)).length,
          newUsers.filter((u) => u.plan === 'pro' && inPrevious(u.createdAt)).length,
        ),
        freePlans: delta(
          newUsers.filter((u) => u.plan === 'free' && inCurrent(u.createdAt)).length,
          newUsers.filter((u) => u.plan === 'free' && inPrevious(u.createdAt)).length,
        ),
      }
    : {};

  return {
    allContacts,
    encounters,
    placesVisited,
    notesAdded,
    freePlans:
      totalUsers === null || proPlans === null
        ? null
        : Math.max(0, totalUsers - proPlans),
    proPlans,
    deltas: {
      ...contactDeltas,
      ...planDeltas,
      ...(notesCurrent !== null && notesPrevious !== null
        ? { notesAdded: delta(notesCurrent, notesPrevious) }
        : {}),
    },
    // The same missing index fails several reads at once; the operator needs
    // to be told about it once, not six times.
    issues: [...new Set(issues)],
  };
}

/**
 * Encounters per bucket for the selected range, alongside the same buckets of
 * the preceding period so the chart can show the comparison line the design
 * draws behind the blue one.
 */
export async function fetchEncounterSeries(
  range: ChartRange,
): Promise<{ points: ChartPoint[]; capped: boolean; issue: string | null }> {
  const spec = rangeSpec(range);

  // Buckets exist before the read does, so an empty period and a failed read
  // both draw a real chart — axis, gridlines, labels, a flat line at zero —
  // instead of an error where the chart should be.
  const points: ChartPoint[] = spec.labels.map((label) => ({
    label,
    current: 0,
    previous: 0,
  }));

  let snap;
  try {
    snap = await getDocs(
      query(
        collectionGroup(db, 'contacts'),
        where('createdAt', '>=', Timestamp.fromDate(spec.previousStart)),
        orderBy('createdAt', 'desc'),
        limit(WINDOW_SCAN_LIMIT),
      ),
    );
  } catch (error) {
    return {
      points,
      capped: false,
      issue: firestoreErrorMessage(error, 'the encounters chart'),
    };
  }

  for (const doc of snap.docs) {
    const createdAt = toDate(doc.data().createdAt);
    if (!createdAt) continue;

    const period = createdAt >= spec.currentStart ? 'current' : 'previous';
    const bucket = spec.bucketOf(createdAt, period);
    if (bucket < 0) continue;

    points[bucket][period] += 1;
  }

  return { points, capped: snap.size === WINDOW_SCAN_LIMIT, issue: null };
}
