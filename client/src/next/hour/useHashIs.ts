import { useEffect, useState } from 'react';

/** Whether the address's hash is `hash` now, following its changes. */
export function useHashIs(hash: string): boolean {
  const [is, setIs] = useState(() => window.location.hash === hash);
  useEffect(() => {
    const change = () => setIs(window.location.hash === hash);
    window.addEventListener('hashchange', change);
    return () => window.removeEventListener('hashchange', change);
  }, [hash]);
  return is;
}
