import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { formatHash } from '../state/routes';
import { useShell } from '../state/store';
import * as css from './firstDay.css';

const WEEK = 7 * 86_400_000;
const key = (id: string) => `oneiroi.first-day.${id}`;
const dismissed = (id: string) => {
  try {
    return localStorage.getItem(key(id)) === 'done';
  } catch {
    return false;
  }
};

/**
 * Your first day (the canvas's EmptyChat board; ui-structures.md D): the
 * three things worth doing in her first days, each ticked from what is
 * actually so — her free time set, an agreement in force, your answer on
 * notifications (the same item the bell carries). Shown for her first
 * week, until all three are done or you close it; closing is this
 * device's.
 */
export function FirstDay({ residentId, residentName }: { residentId: string; residentName: string }) {
  const setOverlay = useShell((s) => s.setOverlay);
  const [closed, setClosed] = useState(() => dismissed(residentId));
  const residents = useQuery({ queryKey: ['residents'], queryFn: api.residents });
  const me = residents.data?.find((r) => r.id === residentId);
  const contact = me?.first_contact_at ? Date.parse(me.first_contact_at) : null;
  const early = contact === null || Date.now() - contact < WEEK;
  const schedule = useQuery({ queryKey: ['resident', residentId, 'time', 'schedule'], queryFn: () => api.schedule(residentId), enabled: early && !closed });
  const agreement = useQuery({ queryKey: ['resident', residentId, 'soul', 'agreement'], queryFn: () => api.agreement(residentId), enabled: early && !closed });
  const push = useQuery({ queryKey: ['me', 'push-config'], queryFn: api.pushConfig, enabled: early && !closed });
  if (closed || !early || !schedule.data || !agreement.data || !push.data) return null;

  const items = [
    { done: schedule.data.free_times.length > 0, label: `Set ${residentName}'s free time`, href: formatHash({ tab: 'time', path: '' }), hint: 'Time › Rhythm' },
    { done: agreement.data.contract.in_force !== null, label: 'Read your agreement together', href: formatHash({ tab: 'soul', path: 'agreement' }) },
    { done: push.data.answered !== null, label: 'Turn on notifications', onClick: () => setOverlay('push') },
  ];
  const count = items.filter((i) => i.done).length;
  if (count === items.length) return null;
  const close = () => {
    try {
      localStorage.setItem(key(residentId), 'done');
    } catch {
      // closed for this visit
    }
    setClosed(true);
  };

  return (
    <aside className={css.panel} aria-label="Your first day">
      <div className={css.top}>
        <span className={css.heading}>
          YOUR FIRST DAY · {count} OF {items.length}
        </span>
        <button type="button" className={css.close} aria-label="Close your first day" onClick={close}>
          ×
        </button>
      </div>
      <ul className={css.list}>
        {items.map((i) => (
          <li key={i.label} className={css.item} data-done={i.done}>
            <span className={css.tick} aria-hidden>
              {i.done ? '✓' : ''}
            </span>
            {i.done ? (
              <span>{i.label}</span>
            ) : i.href ? (
              <a className={css.link} href={i.href}>
                {i.label}
              </a>
            ) : (
              <button type="button" className={css.link} onClick={i.onClick}>
                {i.label}
              </button>
            )}
          </li>
        ))}
      </ul>
    </aside>
  );
}
