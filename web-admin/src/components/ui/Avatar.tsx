import { useState } from 'react';
import { cn } from '@/lib/cn';
import { initials } from '@/lib/format';

/**
 * Photo with an initials fallback. Avatars come from user-uploaded Storage
 * URLs, so a broken or expired link must degrade rather than show a torn
 * image icon in the middle of a table.
 */
export function Avatar({
  name,
  src,
  size = 32,
  className,
  tone = 'brand',
}: {
  name: string;
  src?: string;
  size?: number;
  className?: string;
  tone?: 'brand' | 'neutral';
}) {
  const [failed, setFailed] = useState(false);
  const showImage = Boolean(src) && !failed;

  return (
    <span
      className={cn(
        'relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full',
        tone === 'brand'
          ? 'bg-brand-500 text-white'
          : 'bg-surface-header text-ink-secondary',
        className,
      )}
      style={{ width: size, height: size }}
    >
      {showImage ? (
        <img
          src={src}
          alt=""
          onError={() => setFailed(true)}
          className="size-full object-cover"
        />
      ) : (
        <span
          className="font-semibold leading-none"
          style={{ fontSize: Math.max(10, Math.round(size * 0.36)) }}
        >
          {initials(name)}
        </span>
      )}
    </span>
  );
}
