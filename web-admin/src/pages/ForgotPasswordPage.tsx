import { useState } from 'react';
import { Link } from 'react-router-dom';
import { AuthCard } from '@/components/layout/AuthCard';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Banner } from '@/components/ui/Banner';
import { ArrowLeftIcon, MailIcon } from '@/components/icons';
import { authErrorMessage, useAuth } from '@/lib/auth';

export function ForgotPasswordPage() {
  const { resetPassword } = useAuth();
  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const onSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError(null);

    if (!email.trim()) {
      setError('Enter the email address on your admin account.');
      return;
    }

    setSubmitting(true);
    try {
      await resetPassword(email);
      setSent(true);
    } catch (err) {
      // `auth/user-not-found` is deliberately not distinguished here: telling a
      // stranger which addresses exist is an account-enumeration leak.
      const code =
        typeof err === 'object' && err && 'code' in err
          ? String((err as { code: unknown }).code)
          : '';
      if (code === 'auth/user-not-found') setSent(true);
      else setError(authErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AuthCard
      title="Forgot password"
      subtitle="Enter your email and we'll send you a reset link"
    >
      {sent ? (
        <div className="flex flex-col gap-4">
          <Banner tone="info">
            If <span className="font-semibold">{email.trim()}</span> belongs to an
            admin account, a reset link is on its way. The link is valid for one
            hour.
          </Banner>
          <Link to="/login">
            <Button variant="outline" size="lg" className="w-full">
              Back to sign in
            </Button>
          </Link>
        </div>
      ) : (
        <form onSubmit={onSubmit} noValidate className="flex flex-col gap-3.5">
          {error ? <Banner tone="error">{error}</Banner> : null}

          <Input
            label="Email address"
            name="email"
            type="email"
            autoComplete="username"
            placeholder="email@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            adornment={<MailIcon size={18} className="shrink-0 text-brand-500" />}
          />

          <Button type="submit" size="lg" loading={submitting} className="mt-1 w-full">
            Send reset link
          </Button>

          <Link
            to="/login"
            className="mx-auto inline-flex items-center gap-1.5 text-2xs text-ink-secondary transition-colors hover:text-ink"
          >
            <ArrowLeftIcon size={13} />
            Back to sign in
          </Link>
        </form>
      )}
    </AuthCard>
  );
}
