import type { ReactNode } from 'react';
import { BrowserRouter, Navigate, Outlet, Route, Routes, useLocation } from 'react-router-dom';
import { AppShell } from './components/layout/AppShell';
import { Spinner } from './components/ui/Spinner';
import { AuthProvider, useAuth } from './lib/auth';
import { configError } from './lib/firebase';
import { landingRoute, permissionLabel } from './lib/permissions';
import { AdministrationPage } from './pages/AdministrationPage';
import { ContactDetailPage } from './pages/ContactDetailPage';
import { DashboardPage } from './pages/DashboardPage';
import { ForgotPasswordPage } from './pages/ForgotPasswordPage';
import { LoginPage } from './pages/LoginPage';
import { SupportPage } from './pages/SupportPage';
import { UserDetailPage } from './pages/UserDetailPage';
import { UsersPage } from './pages/UsersPage';
import type { Permission } from './data/types';

export default function App() {
  if (configError) return <SetupScreen message={configError} />;

  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route element={<GuestOnly />}>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/forgot-password" element={<ForgotPasswordPage />} />
          </Route>

          <Route element={<RequireAdmin />}>
            <Route element={<AppShell />}>
              <Route
                path="/dashboard"
                element={
                  <RequirePermission permission="dashboard">
                    <DashboardPage />
                  </RequirePermission>
                }
              />
              <Route
                path="/users"
                element={
                  <RequirePermission permission="users">
                    <UsersPage />
                  </RequirePermission>
                }
              />
              <Route
                path="/users/:uid"
                element={
                  <RequirePermission permission="users">
                    <UserDetailPage />
                  </RequirePermission>
                }
              />
              <Route
                path="/users/:uid/contacts/:contactId"
                element={
                  <RequirePermission permission="users">
                    <ContactDetailPage />
                  </RequirePermission>
                }
              />
              <Route
                path="/support"
                element={
                  <RequirePermission permission="support">
                    <SupportPage />
                  </RequirePermission>
                }
              />
              <Route
                path="/administration"
                element={
                  <RequirePermission permission="administration">
                    <AdministrationPage />
                  </RequirePermission>
                }
              />
            </Route>
          </Route>

          <Route path="/" element={<RootRedirect />} />
          <Route path="*" element={<RootRedirect />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}

/** Blocks the console until Firebase confirms an admin session. */
function RequireAdmin() {
  const { admin } = useAuth();
  const location = useLocation();

  if (admin === undefined) return <BootSplash />;
  if (admin === null) {
    return (
      <Navigate
        to="/login"
        replace
        state={{ from: location.pathname + location.search }}
      />
    );
  }
  return <Outlet />;
}

/**
 * Gates one route on a permission, not just the nav item that links to it —
 * firestore.rules independently checks the same permission on every read the
 * page makes, but a role can change (or a role can be deleted) while someone
 * is sitting on the page, so the route itself has to re-check on every visit.
 * A role that has since lost the permission is sent to whatever tab it still
 * holds, rather than shown a page that will error on its first read.
 */
function RequirePermission({
  permission,
  children,
}: {
  permission: Permission;
  children: ReactNode;
}) {
  const { admin, hasPermission } = useAuth();
  if (hasPermission(permission)) return <>{children}</>;
  const fallback = landingRoute(admin?.permissions ?? []);
  if (fallback) return <Navigate to={fallback} replace />;
  return <NoAccessScreen />;
}

/** Sends a freshly-signed-in administrator to the first tab their role holds. */
function RootRedirect() {
  const { admin } = useAuth();
  if (admin === undefined) return <BootSplash />;
  if (admin === null) return <Navigate to="/login" replace />;
  const target = landingRoute(admin.permissions);
  return target ? <Navigate to={target} replace /> : <NoAccessScreen />;
}

/** Keeps a signed-in admin off the login screen. */
function GuestOnly() {
  const { admin } = useAuth();
  if (admin === undefined) return <BootSplash />;
  if (admin) {
    const target = landingRoute(admin.permissions) ?? '/dashboard';
    return <Navigate to={target} replace />;
  }
  return <Outlet />;
}

/** A role with zero permissions — not something the UI can create, but a
 * deleted or mis-edited role could leave an account here. Signing out is the
 * only useful action, so that is the only thing offered. */
function NoAccessScreen() {
  const { signOut } = useAuth();
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-3 bg-white px-4 text-center">
      <h1 className="text-base font-bold text-ink">No dashboard access</h1>
      <p className="max-w-sm text-[13px] text-ink-secondary">
        Your account's role does not grant access to any tab
        {' — '}
        ask a Super Admin to check it under {permissionLabel('administration')}.
      </p>
      <button
        type="button"
        onClick={() => void signOut()}
        className="mt-1 text-[13px] font-medium text-brand-500 underline underline-offset-2"
      >
        Sign out
      </button>
    </div>
  );
}

function BootSplash() {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-3 bg-white">
      <img
        src="/logo.svg"
        alt=""
        width={42}
        height={42}
        className="size-[42px] object-contain"
      />
      <Spinner size={20} className="text-brand-500" />
      <span className="sr-only">Checking your session…</span>
    </div>
  );
}

function SetupScreen({ message }: { message: string }) {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-white px-4 py-10">
      <div className="w-full max-w-lg rounded-2xl bg-surface-panel p-6">
        <h1 className="text-base font-bold text-ink">Finish the Firebase setup</h1>
        <p className="mt-2 text-[13px] leading-relaxed text-ink-secondary">
          {message}
        </p>
        <ol className="mt-4 flex flex-col gap-2 text-[13px] leading-relaxed text-ink">
          <li>
            <span className="font-semibold">1.</span> Open the{' '}
            <a
              className="font-medium text-brand-500 underline underline-offset-2"
              href="https://console.firebase.google.com/project/metadata-64577/settings/general"
              target="_blank"
              rel="noreferrer"
            >
              metadata-64577 project settings
            </a>{' '}
            and register a Web app (<code>&lt;/&gt;</code>) if there isn't one.
          </li>
          <li>
            <span className="font-semibold">2.</span> Copy{' '}
            <code>web-admin/.env.example</code> to{' '}
            <code>web-admin/.env.local</code>.
          </li>
          <li>
            <span className="font-semibold">3.</span> Paste the app's{' '}
            <code>apiKey</code> and <code>appId</code> into it, then restart{' '}
            <code>npm run dev</code>.
          </li>
        </ol>
      </div>
    </div>
  );
}
