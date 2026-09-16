import { describe, expect, it } from 'vitest';
import { landingRoute } from './permissions';

describe('landingRoute', () => {
  it('picks the first tab in nav order, not permission-array order', () => {
    // A Support-only account holds one permission — must land on Support.
    expect(landingRoute(['support'])).toBe('/support');
    // Order in the stored array must not matter: dashboard still wins here.
    expect(landingRoute(['support', 'dashboard'])).toBe('/dashboard');
  });

  it('returns null for a role with no permissions', () => {
    // A role can exist with an empty permission set (e.g. mid-edit); the
    // caller renders a "no access" screen for this rather than looping.
    expect(landingRoute([])).toBeNull();
  });

  it('lands a super admin on the dashboard', () => {
    expect(landingRoute(['dashboard', 'users', 'support', 'administration'])).toBe(
      '/dashboard',
    );
  });
});
