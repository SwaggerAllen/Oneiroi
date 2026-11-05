import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import type { PushState } from '../../app/push';

export interface NotificationsProps {
  residentName: string;
  state: PushState | 'loading';
  // Whether the server has a VAPID key: pushes can be sent at all.
  enabled: boolean;
  busy?: boolean;
  said?: string | null;
  onTurnOn?: () => void;
  onTurnOff?: () => void;
  onTest?: () => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;

// Notifications on this device (gaia#15): told when the resident writes
// without being written to, never what she wrote. On an iPhone, only the
// Home Screen app may ask, so the card says how to get there first.
export function Notifications({ residentName, state, enabled, busy = false, said = null, onTurnOn, onTurnOff, onTest }: NotificationsProps) {
  const what = `You'll be told when ${residentName} writes without being written to: a check-in, a letter, a round. The notification says only that she wrote, never what.`;
  return (
    <Card title="Notifications">
      {state === 'loading' ? <p style={muted}>Checking this device…</p> : null}
      {state === 'unsupported' ? <p style={muted}>This browser can't receive notifications.</p> : null}
      {state === 'install' ? (
        <p style={muted}>
          On an iPhone, notifications work from the Home Screen app. In Safari, tap Share, then Add to Home Screen, and open Oneiroi from
          there; this card will offer to turn them on.
        </p>
      ) : null}
      {state === 'denied' ? <p style={muted}>Notifications are blocked for Oneiroi in this device's settings.</p> : null}
      {state === 'ready' && !enabled ? <p style={muted}>Notifications aren't set up on the server yet.</p> : null}
      {state === 'ready' && enabled ? (
        <>
          <p style={muted}>{what}</p>
          <div>
            <Button variant="primary" onClick={onTurnOn} disabled={busy}>
              Allow notifications
            </Button>
          </div>
        </>
      ) : null}
      {state === 'on' ? (
        <>
          <p style={muted}>On for this device. {what}</p>
          <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
            <Button onClick={onTest} disabled={busy}>
              Send a test
            </Button>
            <Button variant="quiet" onClick={onTurnOff} disabled={busy}>
              Turn off
            </Button>
          </div>
        </>
      ) : null}
      {said ? (
        <p role="status" style={{ ...muted, color: 'var(--ink)' }}>
          {said}
        </p>
      ) : null}
    </Card>
  );
}
