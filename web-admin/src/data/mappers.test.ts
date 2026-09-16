import { describe, expect, it } from 'vitest';
import { Timestamp } from 'firebase/firestore';
import {
  mapContact,
  mapTicket,
  mapTicketMessage,
  mapUser,
  normalizeTicketStatus,
  toDate,
  type Snap,
} from './mappers';

function snap(id: string, data: Record<string, unknown>, path?: string): Snap {
  return { id, ref: { path: path ?? `users/u1/contacts/${id}` }, data: () => data };
}

describe('toDate', () => {
  it('unwraps a Firestore Timestamp', () => {
    const now = new Date(2026, 4, 1, 12, 0);
    expect(toDate(Timestamp.fromDate(now))?.getTime()).toBe(now.getTime());
  });

  it('returns null for anything else, including serverTimestamp placeholders', () => {
    expect(toDate(null)).toBeNull();
    expect(toDate(undefined)).toBeNull();
    expect(toDate('2026-05-01')).toBeNull();
    expect(toDate({ _methodName: 'serverTimestamp' })).toBeNull();
  });
});

describe('mapUser', () => {
  it('defaults the fields the mobile app does not write', () => {
    const user = mapUser(snap('u1', { phoneNumber: '+1 415 555 0142' }, 'users/u1'));
    expect(user.plan).toBe('free');
    expect(user.isBlocked).toBe(false);
    expect(user.note).toBeUndefined();
    expect(user.displayName).toBe('Unnamed user');
  });

  it('reads a pro plan and a block flag when present', () => {
    const user = mapUser(
      snap('u2', { displayName: 'Jay Smith', plan: 'pro', isBlocked: true }, 'users/u2'),
    );
    expect(user.plan).toBe('pro');
    expect(user.isBlocked).toBe(true);
  });

  it('treats an unknown plan value as free rather than trusting it', () => {
    expect(mapUser(snap('u3', { plan: 'enterprise' }, 'users/u3')).plan).toBe('free');
  });

  it('survives a document with no data at all', () => {
    const empty: Snap = { id: 'u4', ref: { path: 'users/u4' }, data: () => undefined };
    expect(mapUser(empty).uid).toBe('u4');
    expect(mapUser(empty).phoneNumber).toBe('—');
  });
});

describe('mapContact', () => {
  it('recovers the owning uid from the document path', () => {
    const contact = mapContact(snap('c1', {}, 'users/abc123/contacts/c1'));
    expect(contact.ownerUid).toBe('abc123');
  });

  it('defaults capturesContext to true, matching ContactModel.fromFirestore', () => {
    // Documents written before "Save Manually" stopped capturing context have
    // no flag; back then everything went through capture.
    expect(mapContact(snap('c2', {})).capturesContext).toBe(true);
    expect(mapContact(snap('c3', { capturesContext: false })).capturesContext).toBe(false);
  });

  it('only builds a location when both coordinates are numbers', () => {
    expect(mapContact(snap('c4', { location: null })).location).toBeNull();
    expect(mapContact(snap('c5', { location: { lat: 1 } })).location).toBeNull();
    expect(
      mapContact(snap('c6', { location: { lat: 1.5, lng: 2.5, placeName: 'Blue bottle coffee' } }))
        .location,
    ).toEqual({ lat: 1.5, lng: 2.5, address: undefined, placeName: 'Blue bottle coffee' });
  });

  it('normalises an unexpected source to manual', () => {
    expect(mapContact(snap('c7', { source: 'device' })).source).toBe('device');
    expect(mapContact(snap('c8', { source: 'imported' })).source).toBe('manual');
  });
});

describe('normalizeTicketStatus', () => {
  it("folds the app's 'open' into pending", () => {
    // SupportTicket.toCreateMap defaults to 'open'; the dashboard's unworked
    // state is 'pending'. They are the same thing, so no migration is needed.
    expect(normalizeTicketStatus('open')).toBe('pending');
    expect(normalizeTicketStatus(undefined)).toBe('pending');
    expect(normalizeTicketStatus('anything-else')).toBe('pending');
  });

  it('accepts every spelling of done', () => {
    expect(normalizeTicketStatus('completed')).toBe('completed');
    expect(normalizeTicketStatus('resolved')).toBe('completed');
    expect(normalizeTicketStatus('closed')).toBe('completed');
  });

  it('passes waiting through', () => {
    expect(normalizeTicketStatus('waiting')).toBe('waiting');
  });
});

describe('mapTicket / mapTicketMessage', () => {
  it('fills sensible placeholders for a sparse ticket', () => {
    const ticket = mapTicket(snap('t1', {}, 'support_tickets/t1'));
    expect(ticket.name).toBe('Unknown sender');
    expect(ticket.subject).toBe('No subject');
    expect(ticket.email).toBe('—');
    expect(ticket.status).toBe('pending');
  });

  it('defaults an unknown author side to the user, never to admin', () => {
    // Erring towards 'user' means a malformed document can never render as an
    // official reply in the thread.
    expect(mapTicketMessage(snap('m1', { from: 'bogus' })).from).toBe('user');
    expect(mapTicketMessage(snap('m2', { from: 'admin' })).from).toBe('admin');
  });
});
