import { useEffect, useState } from 'react';
import { NavLink, useLocation, useNavigate } from 'react-router-dom';
import { cn } from '@/lib/cn';
import { useAuth } from '@/lib/auth';
import { Avatar } from '../ui/Avatar';
import { SearchInput } from '../ui/SearchInput';
import { MenuItem, Popover } from '../ui/Menu';
import { ProfileModal } from '../ProfileModal';
import {
  BellIcon,
  CloseIcon,
  DashboardIcon,
  LogOutIcon,
  MenuIcon,
  PersonIcon,
  ShieldIcon,
  SupportIcon,
  UsersIcon,
} from '../icons';
import type { Permission } from '@/data/types';

const NAV: ReadonlyArray<{
  to: string;
  label: string;
  Icon: typeof DashboardIcon;
  permission: Permission;
}> = [
  { to: '/dashboard', label: 'Dashboard', Icon: DashboardIcon, permission: 'dashboard' },
  { to: '/users', label: 'Users', Icon: UsersIcon, permission: 'users' },
  { to: '/support', label: 'Support', Icon: SupportIcon, permission: 'support' },
  // Rendered for every role in the array above; only a role holding
  // 'administration' actually sees this item — see the filter below.
  { to: '/administration', label: 'Administration', Icon: ShieldIcon, permission: 'administration' },
];

export function TopNav({ pendingTickets }: { pendingTickets: number }) {
  const { admin, signOut, hasPermission } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);

  // A tab a role does not hold is not just visually de-emphasised — it is
  // absent from the nav entirely, matching the Support role's "only sees the
  // Support tab" requirement. RequirePermission in App.tsx enforces the same
  // rule at the route level for anyone who navigates there directly.
  const visibleNav = NAV.filter((item) => hasPermission(item.permission));

  // A route change means the user got where they were going — collapse the
  // mobile sheet rather than leaving it covering the page they asked for.
  useEffect(() => setMobileOpen(false), [location.pathname]);

  /** The header search is the fast path into the user directory. */
  const runSearch = (term: string) => {
    const trimmed = term.trim();
    navigate(trimmed ? `/users?q=${encodeURIComponent(trimmed)}` : '/users');
  };

  return (
    <header className="sticky top-0 z-40 border-b border-line bg-white/95 backdrop-blur">
      <div className="mx-auto flex h-14 max-w-[1400px] items-center gap-3 px-4 sm:px-6">
        <button
          type="button"
          onClick={() => setMobileOpen((v) => !v)}
          aria-label={mobileOpen ? 'Close menu' : 'Open menu'}
          aria-expanded={mobileOpen}
          className="-ml-1 shrink-0 rounded-lg p-1.5 text-ink-secondary transition-colors hover:bg-surface-panel md:hidden"
        >
          {mobileOpen ? <CloseIcon size={20} /> : <MenuIcon size={20} />}
        </button>

        <NavLink to="/dashboard" className="flex shrink-0 items-center gap-2">
          <img
            src="/logo.svg"
            alt=""
            width={26}
            height={26}
            className="size-[26px] object-contain"
          />
          <span className="whitespace-nowrap text-[15px] font-semibold text-ink">
            Metadata
          </span>
        </NavLink>

        <div className="mx-1 hidden h-6 w-px bg-line md:block" />

        <nav className="hidden items-center gap-1 md:flex" aria-label="Main">
          {visibleNav.map(({ to, label, Icon }) => (
            <NavLink key={to} to={to} className="shrink-0">
              {({ isActive }) => (
                <span
                  className={cn(
                    'inline-flex h-9 items-center gap-2 rounded-control px-3 text-[13px] font-medium transition-colors',
                    isActive
                      ? 'bg-brand-100 text-brand-500'
                      : 'text-ink-secondary hover:bg-surface-panel hover:text-ink',
                  )}
                >
                  <Icon size={17} />
                  {label}
                </span>
              )}
            </NavLink>
          ))}
        </nav>

        <div className="ml-auto flex min-w-0 items-center gap-2 sm:gap-3">
          <SearchInput
            value=""
            onChange={runSearch}
            debounceMs={0}
            placeholder="Search contacts, places..."
            aria-label="Search users, contacts and places"
            className="hidden w-56 lg:flex xl:w-72"
          />

          {hasPermission('support') ? (
            <NavLink
              to="/support"
              aria-label={
                pendingTickets > 0
                  ? `Support inbox, ${pendingTickets} pending`
                  : 'Support inbox'
              }
              className="relative shrink-0 rounded-lg p-1.5 text-ink-secondary transition-colors hover:bg-surface-panel hover:text-ink"
            >
              <BellIcon size={19} />
              {pendingTickets > 0 ? (
                <>
                  <span className="absolute right-1 top-1 size-2 rounded-full bg-state-bad ring-2 ring-white" />
                  <span className="sr-only">{pendingTickets} pending tickets</span>
                </>
              ) : null}
            </NavLink>
          ) : null}

          <Popover
            trigger={({ open, toggle, id }) => (
              <button
                type="button"
                onClick={toggle}
                aria-haspopup="menu"
                aria-expanded={open}
                aria-controls={id}
                aria-label="Account menu"
                className="flex shrink-0 items-center gap-2 rounded-full py-1 pl-1 pr-1 transition-colors hover:bg-surface-panel sm:pr-2"
              >
                <Avatar
                  name={admin?.name ?? '?'}
                  src={admin?.photoUrl}
                  size={30}
                  tone="neutral"
                />
                <span className="hidden min-w-0 text-left sm:block">
                  <span className="block truncate text-xs font-semibold text-ink">
                    {admin?.name}
                  </span>
                  <span className="block truncate text-2xs capitalize text-ink-secondary">
                    {admin?.role}
                  </span>
                </span>
              </button>
            )}
          >
            {({ close }) => (
              <>
                <div className="border-b border-line px-3 pb-2 pt-1">
                  <p className="truncate text-xs font-semibold text-ink">
                    {admin?.name}
                  </p>
                  <p className="truncate text-2xs text-ink-secondary">
                    {admin?.email}
                  </p>
                </div>
                <MenuItem
                  onClick={() => {
                    close();
                    setProfileOpen(true);
                  }}
                >
                  <PersonIcon size={15} />
                  My Profile
                </MenuItem>
                <MenuItem
                  tone="danger"
                  onClick={() => {
                    close();
                    void signOut();
                  }}
                >
                  <LogOutIcon size={15} />
                  Sign out
                </MenuItem>
              </>
            )}
          </Popover>
        </div>
      </div>

      <ProfileModal open={profileOpen} onClose={() => setProfileOpen(false)} />

      {mobileOpen ? (
        <div className="border-t border-line bg-white px-4 pb-3 pt-2 md:hidden">
          <nav className="flex flex-col gap-0.5" aria-label="Main">
            {visibleNav.map(({ to, label, Icon }) => (
              <NavLink key={to} to={to}>
                {({ isActive }) => (
                  <span
                    className={cn(
                      'flex h-10 items-center gap-2.5 rounded-control px-3 text-[13px] font-medium transition-colors',
                      isActive
                        ? 'bg-brand-100 text-brand-500'
                        : 'text-ink-secondary hover:bg-surface-panel',
                    )}
                  >
                    <Icon size={18} />
                    {label}
                  </span>
                )}
              </NavLink>
            ))}
          </nav>
          <SearchInput
            value=""
            onChange={runSearch}
            debounceMs={0}
            placeholder="Search contacts, places..."
            aria-label="Search users, contacts and places"
            className="mt-2 lg:hidden"
          />
        </div>
      ) : null}
    </header>
  );
}
