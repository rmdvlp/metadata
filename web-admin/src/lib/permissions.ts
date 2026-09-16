import type { Permission } from '@/data/types';

/**
 * The single source of truth for what each permission means and where it
 * lives in the nav. The Roles form's checkboxes, their descriptions, and the
 * post-login landing route all read from this one list rather than each
 * hard-coding their own copy of the four tabs.
 */
export const PERMISSIONS: ReadonlyArray<{
  key: Permission;
  label: string;
  description: string;
  route: string;
}> = [
  {
    key: 'dashboard',
    label: 'Dashboard',
    description: 'View totals, the encounters chart and recent contacts.',
    route: '/dashboard',
  },
  {
    key: 'users',
    label: 'Users',
    description:
      'Search users, open a profile, block or unblock, and manage their contacts.',
    route: '/users',
  },
  {
    key: 'support',
    label: 'Support',
    description: 'View the support inbox and reply to tickets.',
    route: '/support',
  },
  {
    key: 'administration',
    label: 'Administration',
    description: 'Manage roles and administrator accounts — this page.',
    route: '/administration',
  },
];

export function permissionLabel(permission: Permission): string {
  return PERMISSIONS.find((p) => p.key === permission)?.label ?? permission;
}

/**
 * The first route a set of permissions can actually reach, in the nav's own
 * left-to-right order. Used both to send a freshly-signed-in administrator
 * somewhere real instead of a hard-coded `/dashboard` they might not hold,
 * and to redirect away from a route a role has since lost.
 */
export function landingRoute(permissions: Permission[]): string | null {
  return PERMISSIONS.find((p) => permissions.includes(p.key))?.route ?? null;
}
