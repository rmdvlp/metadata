import type { ReactNode } from 'react';

/**
 * The centred sign-in card. Forgot-password reuses it unchanged, per the
 * design note that the reset screen matches login.
 */
export function AuthCard({
  title,
  subtitle,
  children,
  footer,
}: {
  title: string;
  subtitle: string;
  children: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-white px-4 py-10">
      <div className="w-full max-w-[392px] rounded-2xl bg-surface-panel p-6 sm:p-7">
        <div className="flex flex-col items-center text-center">
          <img
            src="/logo.svg"
            alt="Metadata"
            width={52}
            height={52}
            className="size-[52px] object-contain"
          />
          <p className="mt-2.5 text-[13px] text-ink">Metadata</p>
          <h1 className="mt-3 text-xl font-bold text-ink">{title}</h1>
          <p className="mt-1 text-xs text-ink-secondary">{subtitle}</p>
        </div>

        <div className="mt-5">{children}</div>

        <p className="mt-6 text-center text-2xs text-ink-secondary">
          By clicking{' '}
          <a
            href="https://metadata-64577.web.app/privacy"
            target="_blank"
            rel="noreferrer"
            className="font-medium text-brand-500 underline underline-offset-2"
          >
            continue
          </a>
          , you agree to our privacy policy.
        </p>

        {footer}
      </div>
    </div>
  );
}
