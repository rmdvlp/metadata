import type { SVGProps } from 'react';

/**
 * Iconsax-style outline set matching the design: 24px grid, 1.6 stroke,
 * `currentColor` throughout so an icon inherits its container's text colour.
 * Hand-rolled rather than pulled from a library — it is a couple of dozen
 * glyphs and this keeps the bundle and the licence surface at zero.
 */
type IconProps = SVGProps<SVGSVGElement> & { size?: number };

function Icon({ size = 18, children, ...rest }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.6}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      {...rest}
    >
      {children}
    </svg>
  );
}

export const MailIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="2.5" y="4.5" width="19" height="15" rx="3" />
    <path d="M5.5 8.5l5.3 3.6a2 2 0 0 0 2.4 0l5.3-3.6" />
  </Icon>
);

export const EyeIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" />
    <circle cx="12" cy="12" r="3" />
  </Icon>
);

export const EyeOffIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M9.9 5.9A9.6 9.6 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-2.3 3.2" />
    <path d="M6.5 7.4A16.8 16.8 0 0 0 2.5 12S6 18.5 12 18.5c1.4 0 2.7-.35 3.8-.9" />
    <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" />
    <path d="M3.5 3.5l17 17" />
  </Icon>
);

export const DashboardIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3" y="3" width="7.5" height="7.5" rx="2" />
    <rect x="13.5" y="3" width="7.5" height="7.5" rx="2" />
    <rect x="3" y="13.5" width="7.5" height="7.5" rx="2" />
    <rect x="13.5" y="13.5" width="7.5" height="7.5" rx="2" />
  </Icon>
);

export const UsersIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="9.5" cy="8" r="3.4" />
    <path d="M3 19.2c0-2.9 2.9-4.7 6.5-4.7s6.5 1.8 6.5 4.7" />
    <path d="M16.4 5.2a3.2 3.2 0 0 1 0 6" />
    <path d="M18.2 14.8c1.9.5 3.3 1.7 3.3 3.6" />
  </Icon>
);

/** Single figure — the Name row on the contact detail screen. */
export const PersonIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="8" r="3.6" />
    <path d="M4.8 20c0-3.2 3.2-5.2 7.2-5.2s7.2 2 7.2 5.2" />
  </Icon>
);

export const ClockIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.6" />
    <path d="M12 7.4V12l3 1.8" />
  </Icon>
);

/** Pennant — the Plan row. */
export const FlagIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6.5 3.5v17" />
    <path d="M6.5 5h10.8a.6.6 0 0 1 .5.95l-2.6 3.6a.6.6 0 0 0 0 .7l2.6 3.6a.6.6 0 0 1-.5.95H6.5Z" />
  </Icon>
);

export const SupportIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 14v-2a8 8 0 0 1 16 0v2" />
    <rect x="2.5" y="13" width="4" height="6" rx="2" />
    <rect x="17.5" y="13" width="4" height="6" rx="2" />
    <path d="M19.5 19v.5a2.5 2.5 0 0 1-2.5 2.5h-2.5" />
  </Icon>
);

export const SearchIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="11" cy="11" r="7" />
    <path d="M16.2 16.2 21 21" />
  </Icon>
);

export const RefreshIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M20 12a8 8 0 1 1-2.6-5.9" />
    <path d="M20.5 4v3.4h-3.4" />
  </Icon>
);

export const BellIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 10a6 6 0 0 1 12 0c0 3.3.8 5 1.6 6H4.4C5.2 15 6 13.3 6 10Z" />
    <path d="M9.7 19.2a2.4 2.4 0 0 0 4.6 0" />
  </Icon>
);

export const ChevronDownIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 9.5l6 5.5 6-5.5" />
  </Icon>
);

export const ChevronLeftIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M14.5 5.5 8.5 12l6 6.5" />
  </Icon>
);

export const ChevronRightIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M9.5 5.5 15.5 12l-6 6.5" />
  </Icon>
);

export const ArrowUpIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 19V5" />
    <path d="M6.5 10.5 12 5l5.5 5.5" />
  </Icon>
);

export const ArrowDownIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 5v14" />
    <path d="M17.5 13.5 12 19l-5.5-5.5" />
  </Icon>
);

export const ArrowLeftIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M19 12H5" />
    <path d="M10.5 6.5 5 12l5.5 5.5" />
  </Icon>
);

export const CalendarIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3.2" y="5" width="17.6" height="16" rx="3" />
    <path d="M8 3v4M16 3v4M3.2 10h17.6" />
  </Icon>
);

/** Calendar with dotted days — the Completed stat on the user detail screen. */
export const CalendarDotsIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3.2" y="5" width="17.6" height="16" rx="3.4" />
    <path d="M8 3v4M16 3v4M3.2 10h17.6" />
    <path d="M8.4 14h.01M12 14h.01M15.6 14h.01M8.4 17.4h.01M12 17.4h.01" strokeWidth={2.1} />
  </Icon>
);

/** Calendar with a tick — the Encounters tile in the design. */
export const CalendarTickIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3.2" y="5" width="17.6" height="16" rx="3" />
    <path d="M8 3v4M16 3v4M3.2 10h17.6" />
    <path d="M9.4 15.4l1.9 1.9 3.6-3.6" />
  </Icon>
);

export const PinIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 21.5s7-5.4 7-11a7 7 0 1 0-14 0c0 5.6 7 11 7 11Z" />
    <circle cx="12" cy="10.2" r="2.6" />
  </Icon>
);

/**
 * GPS ring — the Places Visited tile. The design uses a crosshair ring here
 * rather than a map pin; the pin above is kept for the per-contact place rows.
 */
export const GpsIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="7.4" />
    <circle cx="12" cy="12" r="2.7" />
    <path d="M12 2.2v2.4M12 19.4v2.4M2.2 12h2.4M19.4 12h2.4" />
  </Icon>
);

export const NoteIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3.5" y="4" width="17" height="16" rx="3.4" />
    <path d="M7.8 9.6h8.4M7.8 13.2h8.4M7.8 16.6h4.6" />
  </Icon>
);

export const DollarIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M14.6 9.4a2.4 2.4 0 0 0-2.3-1.4h-.4a2.1 2.1 0 0 0-.4 4.2h1.2a2.1 2.1 0 0 1 .3 4.2h-.5a2.4 2.4 0 0 1-2.3-1.5" />
    <path d="M12 6.2v1.8M12 16.2V18" />
  </Icon>
);

export const CrownIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3.5 7.5l3.6 3 3.4-5.5a1.8 1.8 0 0 1 3 0l3.4 5.5 3.6-3-1.7 10a1.8 1.8 0 0 1-1.8 1.5H7a1.8 1.8 0 0 1-1.8-1.5Z" />
  </Icon>
);

export const FilterIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3.5 5.5h17l-6.4 7.4v5.4l-4.2 2v-7.4Z" />
  </Icon>
);

export const MoreIcon = (p: IconProps) => (
  <Icon {...p} strokeWidth={2}>
    <circle cx="12" cy="5.5" r="1.1" fill="currentColor" />
    <circle cx="12" cy="12" r="1.1" fill="currentColor" />
    <circle cx="12" cy="18.5" r="1.1" fill="currentColor" />
  </Icon>
);

export const PhoneIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M7.2 3.5 9 3.9a1.6 1.6 0 0 1 1.2 1.3l.4 2.3a1.6 1.6 0 0 1-.8 1.7l-1.1.6a11 11 0 0 0 5.5 5.5l.6-1.1a1.6 1.6 0 0 1 1.7-.8l2.3.4a1.6 1.6 0 0 1 1.3 1.2l.4 1.8a1.7 1.7 0 0 1-1.6 2A16.4 16.4 0 0 1 3.5 5.1a1.7 1.7 0 0 1 2-1.6Z" />
  </Icon>
);

export const EditIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4.5 19.5h3l10-10a2.1 2.1 0 0 0-3-3l-10 10Z" />
    <path d="M14.5 6.5l3 3" />
  </Icon>
);

export const BlockIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M6.2 6.2l11.6 11.6" />
  </Icon>
);

export const InboxIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3.5" y="4" width="17" height="16" rx="3" />
    <path d="M8.5 11.5 12 15l3.5-3.5" />
    <path d="M12 7.5V15" />
  </Icon>
);

export const HourglassIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M7 3.5h10M7 20.5h10" />
    <path d="M8 3.5v3.2c0 1.8 4 3.6 4 5.3s-4 3.5-4 5.3v3.2" />
    <path d="M16 3.5v3.2c0 1.8-4 3.6-4 5.3s4 3.5 4 5.3v3.2" />
  </Icon>
);

export const CheckCircleIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M8.4 12.3l2.4 2.4 4.8-4.8" />
  </Icon>
);

export const SendIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 11.6 20 4l-7.6 16-1.9-6.5Z" />
    <path d="M10.5 13.5 20 4" />
  </Icon>
);

export const LogOutIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M9.5 4.5H6A2 2 0 0 0 4 6.5v11a2 2 0 0 0 2 2h3.5" />
    <path d="M15 8l4 4-4 4" />
    <path d="M19 12H9" />
  </Icon>
);

export const CloseIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 6l12 12M18 6 6 18" />
  </Icon>
);

export const MenuIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 7h16M4 12h16M4 17h16" />
  </Icon>
);

export const AlertIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 8v5M12 16h.01" />
  </Icon>
);

/** Shield — the Administration nav item, super-admin-only actions. */
export const ShieldIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3.5 5 6.2v5.3c0 4.5 3 7.4 7 9 4-1.6 7-4.5 7-9V6.2Z" />
    <path d="M9 12l2.2 2.2L15.5 9.5" />
  </Icon>
);

export const LockIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="5" y="10.5" width="14" height="9.5" rx="2.2" />
    <path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" />
  </Icon>
);

export const PlusIcon = (p: IconProps) => (
  <Icon {...p} strokeWidth={2}>
    <path d="M12 5v14M5 12h14" />
  </Icon>
);
