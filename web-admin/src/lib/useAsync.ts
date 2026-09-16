import { useCallback, useEffect, useState } from 'react';
import { firestoreErrorMessage } from './firestoreError';

export interface AsyncState<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  reload: () => void;
}

/**
 * Runs a Firestore read and tracks its lifecycle. Results that arrive after
 * the inputs changed (or the component unmounted) are discarded, so a slow
 * page-1 read cannot overwrite the page-2 rows the operator is looking at.
 */
export function useAsync<T>(
  run: () => Promise<T>,
  deps: unknown[],
  label = 'this data',
): AsyncState<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);

  // `run` is a fresh closure each render; the caller's deps are the real key.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const runRef = useCallback(run, deps);

  useEffect(() => {
    let stale = false;
    setLoading(true);
    setError(null);

    runRef()
      .then((result) => {
        if (!stale) setData(result);
      })
      .catch((err) => {
        if (!stale) setError(firestoreErrorMessage(err, label));
      })
      .finally(() => {
        if (!stale) setLoading(false);
      });

    return () => {
      stale = true;
    };
  }, [runRef, nonce, label]);

  return {
    data,
    loading,
    error,
    reload: useCallback(() => setNonce((n) => n + 1), []),
  };
}
