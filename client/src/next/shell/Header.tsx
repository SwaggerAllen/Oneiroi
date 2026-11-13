import { useShell } from '../state/store';
import { BellIcon, ChevronIcon, GearIcon, SearchIcon } from './icons';
import { presenceLine, useNow } from './presence';
import * as css from './shell.css';

export interface HeaderProps {
  name: string;
  waiting: number;
  /** A turn failed (brain#89): the dot goes red. */
  failing?: boolean;
  onSubject?: () => void;
  onBell?: () => void;
  onSettings?: () => void;
}

export function Header({ name, waiting, failing = false, onSubject, onBell, onSettings }: HeaderProps) {
  const presence = useShell((s) => s.presence);
  const connection = useShell((s) => s.connection);
  const setSearchOpen = useShell((s) => s.setSearchOpen);
  const working = presence.state !== 'idle';
  const now = useNow(working);
  const line = presenceLine(presence, connection === 'connected', now);

  return (
    <header className={css.header}>
      <button type="button" className={css.subject} onClick={onSubject} aria-label={`${name}, choose a subject`}>
        <span className={css.avatar} data-working={working}>
          {name.slice(0, 1)}
          <span
            className={`${css.dotBase} ${css.connectionDot[connection]}`}
            role="img"
            aria-label={connection === 'connected' ? 'Connected' : connection === 'connecting' ? 'Reconnecting' : 'Offline'}
          />
        </span>
        <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 1 }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span className={css.name}>{name}</span>
            <ChevronIcon />
          </span>
          <span className={css.presence} data-working={working} aria-live="polite">
            {line}
          </span>
        </span>
      </button>
      <div style={{ display: 'flex' }}>
        <button type="button" className={css.iconButton} aria-label="Search everything" onClick={() => setSearchOpen(true)}>
          <SearchIcon />
        </button>
        <button
          type="button"
          className={css.iconButton}
          aria-label={waiting ? `Waiting on you, ${waiting}${failing ? ', something failed' : ''}` : 'Nothing waiting on you'}
          onClick={onBell}
        >
          <BellIcon />
          {waiting > 0 && <span className={failing ? css.badgeFailing : css.badge}>{waiting}</span>}
        </button>
        <button type="button" className={css.iconButton} aria-label="Settings" onClick={onSettings}>
          <GearIcon />
        </button>
      </div>
    </header>
  );
}
