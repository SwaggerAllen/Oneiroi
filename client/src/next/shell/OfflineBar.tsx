import { useEffect, useState } from 'react';
import { status } from '../theme/contract.css';
import { useShell } from '../state/store';
import * as css from './shell.css';

// A blip shorter than this never shows the bar.
const GRACE_MS = 2000;

/**
 * Offline, said plainly (client-state.md): what you see is what you had,
 * and Reconnect tries now instead of waiting out the backoff.
 */
export function OfflineBar({ onReconnect }: { onReconnect: () => void }) {
  const connection = useShell((s) => s.connection);
  const since = useShell((s) => s.offlineSince);
  // Which outage has outlasted the grace period: set only from the timer,
  // so a reconnect inside the grace never shows the bar.
  const [shownFor, setShownFor] = useState<number | null>(null);

  useEffect(() => {
    if (connection === 'connected' || since === null) return;
    const wait = Math.max(0, since + GRACE_MS - Date.now());
    const id = setTimeout(() => setShownFor(since), wait);
    return () => clearTimeout(id);
  }, [connection, since]);

  const show = connection !== 'connected' && since !== null && shownFor === since;
  if (!show || since === null) return null;
  const at = new Date(since);
  const hhmm = `${String(at.getHours()).padStart(2, '0')}:${String(at.getMinutes()).padStart(2, '0')}`;

  return (
    <div className={css.offline} role="status">
      <span style={{ width: 8, height: 8, borderRadius: 4, background: status.warn, flex: 'none' }} />
      <span style={{ display: 'flex', flexDirection: 'column' }}>
        <span>{connection === 'connecting' ? 'Reconnecting…' : 'Offline'}</span>
        <span style={{ font: "500 10px 'JetBrains Mono', monospace", opacity: 0.7 }}>
          SHOWING WHAT YOU HAD AT {hhmm}
        </span>
      </span>
      <button type="button" className={css.offlineButton} onClick={onReconnect}>
        Reconnect
      </button>
    </div>
  );
}
