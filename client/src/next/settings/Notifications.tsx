import { useQuery, useQueryClient } from '@tanstack/react-query';
import { api } from '../../api/client';
import { pushState, turnOff, turnOn, type PushState } from '../../app/push';
import { useNotificationsAsk } from '../shell/notifications';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { Card, Said } from './common';
import { answerLine, plural } from './logic';
import * as css from './settings.css';
import { useAct } from './useAct';

/** What this device can do, in words, for every state but on and ready. */
const DEVICE: Partial<Record<PushState, string>> = {
  unsupported: "This browser can't receive notifications.",
  install:
    'On an iPhone, notifications work from the Home Screen app. In Safari, tap Share, then Add to Home Screen, and open Oneiroi from there; this page will offer to turn them on.',
  denied: "Notifications are blocked for Oneiroi in this device's settings.",
};

/**
 * Notifications on this device (gaia#15): on or off here, a test to
 * every device, how many devices are on, and the account's answer
 * (gaia#25). What they are for is the explainer the bell opens.
 */
export function Notifications() {
  const { name } = useSubject();
  const queries = useQueryClient();
  const setOverlay = useShell((s) => s.setOverlay);
  const device = useQuery({
    queryKey: ['me', 'push-state'],
    queryFn: pushState,
    staleTime: 60_000,
  });
  const config = useQuery({
    queryKey: ['me', 'push-config'],
    queryFn: api.pushConfig,
    staleTime: 60_000,
  });
  const ask = useNotificationsAsk();
  const act = useAct();
  const reread = () => {
    void queries.invalidateQueries({ queryKey: ['me', 'push-state'] });
    void queries.invalidateQueries({ queryKey: ['me', 'push-config'] });
    void queries.invalidateQueries({
      queryKey: ['resident'],
      predicate: (q) => q.queryKey.includes('bell'),
    });
  };
  const run = (work: () => Promise<string>) => void act.run(work).finally(reread);
  // The test goes to every device of yours, so it says what each did.
  const test = useAct();
  const sendTest = () =>
    void test.run(async () => {
      const { sent } = await api.testPush();
      return sent.length === 0 ? 'No device of yours is subscribed.' : sent.map((s) => `${s.device}: ${s.result}`).join('; ');
    });
  const state = device.data;
  const enabled = config.data?.enabled ?? false;

  return (
    <>
      <Card title="This device" witness>
        <p className={css.note}>
          You'll be told when {name} writes without being written to (a check-in, a letter, a round) and when something first waits on you. The notification says only that there's
          something new, never what.{' '}
          <button type="button" className={css.quiet} onClick={() => setOverlay('push')}>
            What they're for ›
          </button>
        </p>
        {device.isPending && <p className={css.note}>Checking this device…</p>}
        {state && DEVICE[state] && <p className={css.text}>{DEVICE[state]}</p>}
        {state === 'ready' && !enabled && config.data && <p className={css.text}>Notifications aren't set up on the server yet.</p>}
        {state === 'ready' && enabled && (
          <>
            <p className={css.text}>Off for this device.</p>
            <div>
              <button
                type="button"
                className={css.primary}
                disabled={act.busy}
                onClick={() =>
                  run(async () => {
                    const key = config.data?.public_key;
                    if (!key) throw new Error("Notifications aren't set up on the server yet.");
                    await api.subscribePush(await turnOn(key, name));
                    return 'Notifications are on for this device.';
                  })
                }
              >
                Turn on notifications
              </button>
            </div>
          </>
        )}
        {state === 'on' && (
          <>
            <p className={css.text}>On for this device.</p>
            <div className={css.row}>
              <button
                type="button"
                className={css.quiet}
                disabled={act.busy}
                onClick={() =>
                  run(async () => {
                    const endpoint = await turnOff();
                    if (endpoint) await api.unsubscribePush(endpoint);
                    return 'Notifications are off for this device.';
                  })
                }
              >
                Turn off
              </button>
            </div>
          </>
        )}
        <Said said={act.said} />
      </Card>

      <Card title="Your account">
        {config.data ? (
          <>
            <p className={css.text}>{config.data.devices === 0 ? 'No device of yours is on.' : `${plural(config.data.devices, 'device')} on.`}</p>
            <p className={css.note}>{answerLine(config.data.answered, config.data.answered_at)}</p>
            {(config.data.devices > 0 || state === 'on') && (
              <div>
                <button type="button" className={css.secondary} disabled={test.busy} onClick={sendTest}>
                  Send a test
                </button>
              </div>
            )}
            <Said said={test.said} />
            {ask.ask && (
              <div>
                <button type="button" className={css.quiet} onClick={ask.decline}>
                  No thanks, on every device
                </button>
              </div>
            )}
          </>
        ) : (
          <p className={css.note}>Reading…</p>
        )}
      </Card>
    </>
  );
}
