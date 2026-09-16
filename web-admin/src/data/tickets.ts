import {
  addDoc,
  collection,
  doc,
  getCountFromServer,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  Timestamp,
  updateDoc,
  where,
  type QueryConstraint,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { mapTicket, mapTicketMessage } from './mappers';
import type {
  SupportStats,
  SupportTicket,
  TicketMessage,
  TicketStatus,
} from './types';

export const TICKET_STATUSES: TicketStatus[] = ['pending', 'waiting', 'completed'];

const TICKETS_LIMIT = 200;

function ticketsRef() {
  return collection(db, 'support_tickets');
}

async function countTickets(...constraints: QueryConstraint[]): Promise<number> {
  const snap = await getCountFromServer(query(ticketsRef(), ...constraints));
  return snap.data().count;
}

/**
 * The four tiles above the inbox. "Today Submissions" counts tickets opened
 * since local midnight, which is what an operator working a shift means by
 * "today".
 */
export async function fetchSupportStats(): Promise<SupportStats> {
  const now = new Date();
  const midnight = Timestamp.fromDate(
    new Date(now.getFullYear(), now.getMonth(), now.getDate()),
  );

  const [today, pending, waiting, completed] = await Promise.all([
    countTickets(where('createdAt', '>=', midnight)),
    // New tickets from the mobile app carry status 'open'; this dashboard
    // writes 'pending'. Both are the same unworked state.
    countTickets(where('status', 'in', ['pending', 'open'])),
    countTickets(where('status', '==', 'waiting')),
    countTickets(where('status', 'in', ['completed', 'resolved', 'closed'])),
  ]);

  return { todaySubmissions: today, pending, waiting, completed };
}

/**
 * Live inbox. Tickets stream rather than poll so a submission from the mobile
 * app lands in the directory while an operator is looking at it.
 *
 * Status filtering happens in the browser: the app writes 'open' for new
 * tickets while this dashboard writes 'pending', and one `in` filter covering
 * every legacy spelling per tab would need a composite index for each. The
 * inbox is capped at the most recent `TICKETS_LIMIT`, which is well past what
 * a directory pane can show.
 */
export function watchTickets(
  onChange: (tickets: SupportTicket[]) => void,
  onError: (error: Error) => void,
): () => void {
  return onSnapshot(
    query(ticketsRef(), orderBy('createdAt', 'desc'), limit(TICKETS_LIMIT)),
    (snap) => onChange(snap.docs.map(mapTicket)),
    onError,
  );
}

/** Live message thread for one ticket, oldest first. */
export function watchTicketMessages(
  ticketId: string,
  onChange: (messages: TicketMessage[]) => void,
  onError: (error: Error) => void,
): () => void {
  return onSnapshot(
    query(
      collection(db, 'support_tickets', ticketId, 'messages'),
      orderBy('createdAt', 'asc'),
    ),
    (snap) => onChange(snap.docs.map(mapTicketMessage)),
    onError,
  );
}

export async function sendTicketReply(options: {
  ticketId: string;
  text: string;
  authorName: string;
  authorEmail: string;
}): Promise<void> {
  const { ticketId, text, authorName, authorEmail } = options;
  await addDoc(collection(db, 'support_tickets', ticketId, 'messages'), {
    from: 'admin',
    authorName,
    authorEmail,
    text: text.trim(),
    createdAt: serverTimestamp(),
  });
}

export async function setTicketStatus(
  ticketId: string,
  status: TicketStatus,
): Promise<void> {
  await updateDoc(doc(db, 'support_tickets', ticketId), {
    status,
    statusUpdatedAt: serverTimestamp(),
  });
}

/** One-off read used by tests and by deep links into a ticket. */
export async function fetchTickets(): Promise<SupportTicket[]> {
  const snap = await getDocs(
    query(ticketsRef(), orderBy('createdAt', 'desc'), limit(TICKETS_LIMIT)),
  );
  return snap.docs.map(mapTicket);
}
