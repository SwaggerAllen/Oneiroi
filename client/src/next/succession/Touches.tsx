import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import type { CatalogModel } from '../../api/types';
import { Said } from '../settings/common';
import * as settingsCss from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { Chip, DryMark } from './common';
import { isHers, isSuccessionNeed, preparing, stateWords, underway } from './logic';
import * as css from './succession.css';
import { successionKey, usePartyName, useSuccession } from './hooks';

// The succession's three touches on the app (screen:next-succession): no
// new screens for what the app already does. A banner in her chat, the
// pool button on the catalog, and Propose for C0 in Records.

/**
 * Her chat's banner while a succession is underway: its words follow the
 * state, a dry run is marked, and it leads back. When something of the
 * succession waits on you (the bell's first succession entry), its few
 * words show beside the way back, which always opens the overview.
 */
export function SuccessionBanner() {
  const { id, name, kind } = useSubject();
  const setPage = useShell((x) => x.setPage);
  const q = useSuccession(kind !== 'house');
  // The bell's own read, shared: its succession entries come first.
  const bell = useQuery({ queryKey: ['resident', id, 'bell'], queryFn: () => api.needsYou(id), enabled: kind !== 'house' && underway(q.data?.succession) });
  const s = q.data?.succession;
  if (!underway(s)) return null;
  const need = (bell.data ?? []).find(isSuccessionNeed);
  // Always the overview (the witness, 2026-11-26): the witness goes on
  // from there, the whole process in view.
  return (
    <button type="button" className={css.banner} onClick={() => setPage('succession', '')}>
      <span className={css.bannerBody}>
        <span className={css.bannerHead}>
          <span>Succession · {stateWords(s, name)}</span>
          <DryMark s={s} />
        </span>
        <span className={css.bannerFoot}>
          <span className={css.bannerLink}>Back to the succession ›</span>
          {need?.about.words && <span className={css.bannerWords}>{need.about.words}</span>}
        </span>
      </span>
      <span aria-hidden>›</span>
    </button>
  );
}

/** On a catalog entry: in the pool already, or a button that adds it while preparation is open. */
export function PoolButton({ model }: { model: CatalogModel }) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const q = useSuccession();
  const act = useAct();
  const s = q.data?.succession;
  if (!preparing(s)) return null;
  const inPool = (q.data?.preparation?.pool ?? []).find((e) => e.model === model.model && !e.removed_at);
  if (inPool)
    return (
      <div className={settingsCss.row}>
        <span className={settingsCss.note}>In the succession pool</span>
        <Chip kind={isHers(inPool.added_by, id) ? 'hers' : 'now'}>{isHers(inPool.added_by, id) ? `${name}'s pick` : who.name(inPool.added_by) === 'you' ? 'your pick' : `${who.name(inPool.added_by)}'s pick`}</Chip>
        <DryMark s={s} />
      </div>
    );
  return (
    <>
      <div className={settingsCss.row}>
        <button type="button" className={settingsCss.primary} disabled={act.busy} onClick={() => void act.run(() => api.poolAdd(id, model.model).then(() => `Added to ${name}'s succession pool.`), successionKey(id))}>
          Add to the succession pool
        </button>
        <DryMark s={s} />
      </div>
      <Said said={act.said} />
    </>
  );
}

/**
 * Propose for C0, on a record in Records while preparation is open: the
 * whole record by its citation, nothing else (the witness, 11-26).
 */
export function ProposeForC0({ citation }: { citation: string }) {
  const { id, name, kind } = useSubject();
  const q = useSuccession(kind !== 'house');
  const act = useAct();
  const s = q.data?.succession;
  if (!preparing(s) || q.data?.preparation?.c0_frozen_at) return null;
  return (
    <div className={`${settingsCss.card} ${css.now}`} role="group" aria-label="Propose for C0">
      <div className={settingsCss.row}>
        <strong>This record</strong>
        <span className={settingsCss.meta}>{citation}</span>
        <DryMark s={s} />
      </div>
      <div className={settingsCss.row}>
        <button
          type="button"
          className={settingsCss.primary}
          disabled={act.busy}
          onClick={() => void act.run(() => api.proposeC0(id, citation).then((r) => `Proposed as C0 #${r.number}. It reaches ${name} with your name and today's date.`), successionKey(id))}
        >
          Propose for C0
        </button>
      </div>
      <p className={settingsCss.note}>Shown while {name}'s succession is open. The whole record goes to her as a proposal, with your name and today's date.</p>
      <Said said={act.said} />
    </div>
  );
}
