import { useEffect, useState } from 'react';
import { Outlet } from 'react-router-dom';
import { TopNav } from './TopNav';
import { fetchSupportStats } from '@/data/tickets';

/**
 * Chrome shared by every signed-in route. The pending-ticket count lives here
 * rather than in the Support page so the bell shows a badge from any screen.
 */
export function AppShell() {
  const [pendingTickets, setPendingTickets] = useState(0);

  useEffect(() => {
    let cancelled = false;

    const load = () =>
      fetchSupportStats()
        .then((stats) => {
          if (!cancelled) setPendingTickets(stats.pending);
        })
        // A badge is not worth surfacing an error for; the Support page shows
        // the real failure if the read is genuinely broken.
        .catch(() => undefined);

    void load();
    const timer = setInterval(load, 60_000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, []);

  return (
    <div className="min-h-dvh bg-surface-page">
      <TopNav pendingTickets={pendingTickets} />
      <main className="mx-auto max-w-[1400px] px-4 py-6 sm:px-6 sm:py-8">
        <Outlet />
      </main>
    </div>
  );
}
