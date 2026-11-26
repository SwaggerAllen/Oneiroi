import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import type { CatalogModel } from '../../api/types';
import { Said } from '../settings/common';
import * as settingsCss from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { Chip, DryMark } from './common';
import { isHers, preparing, stateWords, underway } from './logic';
import * as css from './succession.css';
import { successionKey, usePartyName, useSuccession } from './hooks';

// The succession's three touches on the app (screen:next-succession): no
// new screens for what the app already does. A banner in her chat, the
// pool button on the catalog, and Propose for C0 in Records.

/** Her chat's banner while a succession is underway: its words follow the state, and it leads back. */
export function SuccessionBanner() {
  const { name, kind } = useSubject();
  const setPage = useShell((x) => x.setPage);
  const q = useSuccession(kind !== 'house');
  const s = q.data?.succession;
  if (!underway(s)) return null;
  return (
    <button type="button" className={css.banner} onClick={() => setPage('succession', s.state === 'farewell' ? 'farewell' : '')}>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        <span>
          Succession · {stateWords(s, name)} <DryMark s={s} />
        </span>
        <span className={css.bannerLink}>Back to the succession ›</span>
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
 * whole document, or a stretch of it you select first (its words go as
 * the label; the citation is the document's).
 */
export function ProposeForC0({ citation }: { citation: string }) {
  const { id, name, kind } = useSubject();
  const q = useSuccession(kind !== 'house');
  const act = useAct();
  const [stretch, setStretch] = useState('');
  const s = q.data?.succession;
  const shown = preparing(s) && !q.data?.preparation?.c0_frozen_at;
  // The last stretch selected on the page is kept, so pressing the button
  // (which may clear the selection) still proposes it; Clear lets it go.
  useEffect(() => {
    if (!shown) return;
    const on = () => {
      const sel = document.getSelection();
      const node = sel?.anchorNode;
      const el = node instanceof Element ? node : node?.parentElement;
      // Only a stretch of the record itself: its page carries `data-c0-source`.
      if (!el?.closest('[data-c0-source]')) return;
      const text = (sel?.toString() ?? '').trim().replace(/\s+/g, ' ');
      if (text) setStretch(text.slice(0, 280));
    };
    document.addEventListener('selectionchange', on);
    return () => document.removeEventListener('selectionchange', on);
  }, [shown]);
  if (!shown) return null;
  return (
    <div className={`${settingsCss.card} ${css.now}`} role="group" aria-label="Propose for C0">
      <div className={settingsCss.row}>
        <strong>{stretch ? 'Selected' : 'This record'}</strong>
        {stretch && <span className={settingsCss.note}>“{stretch}”</span>}
        <DryMark s={s} />
      </div>
      <div className={settingsCss.row}>
        <button
          type="button"
          className={settingsCss.primary}
          disabled={act.busy}
          onClick={() => {
            void act.run(
              () =>
                api.proposeC0(id, citation, stretch ? `“${stretch}”` : null).then((r) => {
                  setStretch('');
                  return `Proposed as C0 #${r.number}. It reaches ${name} with your name and today's date.`;
                }),
              successionKey(id),
            );
          }}
        >
          {stretch ? 'Propose the selection for C0' : 'Propose for C0'}
        </button>
        {stretch && (
          <button type="button" className={settingsCss.quiet} onClick={() => setStretch('')}>
            Clear
          </button>
        )}
      </div>
      <p className={settingsCss.note}>Shown while {name}'s succession is open. Goes to her as a proposal with your name and today's date; select a stretch first to propose just that.</p>
      <Said said={act.said} />
    </div>
  );
}
