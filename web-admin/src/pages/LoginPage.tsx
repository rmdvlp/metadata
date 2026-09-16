import { useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { AuthCard } from '@/components/layout/AuthCard';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Banner } from '@/components/ui/Banner';
import { EyeIcon, EyeOffIcon, MailIcon } from '@/components/icons';
import { authErrorMessage, NotAnAdminError, useAuth } from '@/lib/auth';

export function LoginPage() {
  const { signIn } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const onSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError(null);

    if (!email.trim() || !password) {
      setError('Enter your email address and password.');
      return;
    }

    setSubmitting(true);
    try {
      await signIn(email, password);
      // Return them to whatever they were trying to reach before the redirect.
      const from = (location.state as { from?: string } | null)?.from;
      navigate(from ?? '/dashboard', { replace: true });
    } catch (err) {
      setError(
        err instanceof NotAnAdminError ? err.message : authErrorMessage(err),
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AuthCard
      title="Welcome back"
      subtitle="Please Sign in to access for dashboard"
    >
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

        <div>
          <Input
            label="Password"
            name="password"
            type={showPassword ? 'text' : 'password'}
            autoComplete="current-password"
            placeholder="Your Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            adornment={
              <button
                type="button"
                onClick={() => setShowPassword((v) => !v)}
                aria-label={showPassword ? 'Hide password' : 'Show password'}
                className="shrink-0 text-brand-500 transition-opacity hover:opacity-70"
              >
                {showPassword ? <EyeIcon size={18} /> : <EyeOffIcon size={18} />}
              </button>
            }
          />
          <div className="mt-1.5 text-right">
            <Link
              to="/forgot-password"
              className="text-2xs text-ink-secondary transition-colors hover:text-ink"
            >
              Forgot password?
            </Link>
          </div>
        </div>

        <Button type="submit" size="lg" loading={submitting} className="mt-1 w-full">
          Sign in
        </Button>
      </form>
    </AuthCard>
  );
}
