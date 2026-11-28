import { useShell } from '../state/store';
import * as css from './shell.css';

/**
 * A deploy happened while this page was open (apsu#35, the witness,
 * 2026-11-27: pages kept running the code from before it until
 * reloaded). The server named a newer client when the socket rejoined;
 * Reload takes it. Never automatic: a reload would drop what is being
 * typed.
 */
export function UpdateBar() {
  const newBuild = useShell((s) => s.newBuild);
  if (!newBuild) return null;
  return (
    <div className={css.offline} role="status">
      <span style={{ display: 'flex', flexDirection: 'column' }}>
        <span>Oneiroi has been updated</span>
        <span style={{ font: "500 10px 'JetBrains Mono', monospace", opacity: 0.7 }}>THIS PAGE IS RUNNING THE VERSION BEFORE IT</span>
      </span>
      <button type="button" className={css.offlineButton} onClick={() => window.location.reload()}>
        Reload
      </button>
    </div>
  );
}
