import { useState } from 'react';
import { api } from '../../api/client';
import type { Preparation, Room, Succession } from '../../api/types';
import { Said, Select, TextArea } from '../settings/common';
import * as settingsCss from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { ChatIcon, PanelIcon, PersonIcon, StarIcon } from '../shell/icons';
import { BottomTabs } from '../shell/TabBar';
import { useSubject } from '../state/resident';
import { Chip, DryMark, Row, Wall } from './common';
import { Counts } from './Judging';
import { isHers, isMine, panelRows, pool, when } from './logic';
import * as css from './succession.css';
import { deliberationTab, successionKey, useGo, useJudging, usePartyName, useRoom } from './hooks';

const WITHHELD = '“withheld because explaining it would disclose the original’s own scores.”';

/**
 * The deliberation's own tab bar, in the shell's place under the page
 * (the witness: the same bar the workspaces use): Thread, Recommendation,
 * Yours, Panel.
 */
export function DeliberationTabs({ path }: { path: string }) {
  const go = useGo();
  return (
    <BottomTabs
      label="Deliberation"
      active={deliberationTab(path)}
      onSelect={(t) => go(`deliberation/${t}`)}
      items={[
        { key: 'thread', label: 'Thread', icon: <ChatIcon /> },
        { key: 'recommendation', label: 'Recommendation', icon: <StarIcon /> },
        { key: 'yours', label: 'Yours', icon: <PersonIcon /> },
        { key: 'panel', label: 'Panel', icon: <PanelIcon /> },
      ]}
    />
  );
}

/** Deliberation (the Deliberation board): one of its four tabs, chosen from the bar below. */
export function Deliberation({ s, p, path, back }: { s: Succession; p: Preparation | undefined; path: string; back: () => void }) {
  const room = useRoom();
  const tab = deliberationTab(path);
  const r = room.data;
  return (
    <div className={css.tabbed}>
      <button type="button" className={settingsCss.back} onClick={back}>
        ‹ Back
      </button>
      <DryMark s={s} />
      {room.isPending && <p className={settingsCss.note}>Reading…</p>}
      {r === null && <p className={settingsCss.note}>The room is not open to you: it opens to the judges other than her once every judge is ready.</p>}
      {r && tab === 'thread' && <Thread s={s} p={p} room={r} />}
      {r && tab === 'recommendation' && <Recommendation p={p} room={r} />}
      {tab === 'yours' && <Yours />}
      {r && tab === 'panel' && <Panel room={r} />}
    </div>
  );
}

function judgesOf(p: Preparation | undefined, residentId: string) {
  return (p?.panel ?? []).filter((j) => (j.state === 'in' || j.state === 'judge') && !isHers(j.party, residentId)).map((j) => j.party);
}

function Thread({ s, p, room }: { s: Succession; p: Preparation | undefined; room: Room }) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const act = useAct();
  const go = useGo();
  const [text, setText] = useState('');
  const [leaving, setLeaving] = useState(false);
  const others = judgesOf(p, id)
    .filter((party) => !isMine(party, who.me))
    .map(who.name);
  const closed = !!s.deliberation_closed_at;
  const send = (a: 'say' | 'skip' | 'rest' | 'leave') =>
    void act.run(
      () =>
        api.roomAct(id, a, a === 'say' ? text.trim() : '').then(() => {
          if (a === 'say') setText('');
          setLeaving(false);
        }),
      successionKey(id, 'room'),
    );
  return (
    <>
      <h1 className={settingsCss.title}>The thread</h1>
      <p className={settingsCss.lede}>
        You{others.length ? ` and ${others.join(', ')}` : ''}, a turn each a round. {name} isn't here; this room is about her. Round {room.round}
        {room.opened_at ? ` · open since ${when(room.opened_at)}` : ''}.
      </p>
      {room.close_at && !closed && (
        <section className={css.wall} aria-label="Closing">
          <strong>
            {name} is closing the room at {when(room.close_at)}
          </strong>{' '}
          Her call: until then, bring a draft to every judge's endorsement. It ends sooner if every judge rests.
        </section>
      )}
      {closed && <p className={settingsCss.note}>The room closed {when(s.deliberation_closed_at)}{s.deliberation_reason ? `: ${s.deliberation_reason}` : ''}.</p>}
      {room.posts.length === 0 && <p className={settingsCss.note}>Nobody has spoken yet.</p>}
      {room.posts.map((post) => (
        <article key={post.number} className={css.post} aria-label={`${who.name(post.party)}, round ${post.round}`}>
          <span className={settingsCss.meta}>
            {who.name(post.party) === 'you' ? 'You' : who.name(post.party)} · round {post.round}
          </span>
          {post.act === 'say' ? (
            <span className={settingsCss.said}>{post.text}</span>
          ) : (
            <span className={css.passed}>
              {post.act === 'skip' ? 'Skipped: a real pass, not resting, not agreeing.' : post.act === 'rest' ? 'Rested their case.' : 'Left the room.'}
              {post.text ? ` “${post.text}”` : ''}
            </span>
          )}
        </article>
      ))}
      {!closed && (
        <>
          <TextArea label="Your turn" value={text} onChange={(e) => setText(e.target.value)} placeholder="Your argument" />
          <div className={settingsCss.row}>
            <button type="button" className={settingsCss.primary} disabled={act.busy || !text.trim()} onClick={() => send('say')}>
              Say it
            </button>
            <button type="button" className={settingsCss.secondary} disabled={act.busy} onClick={() => send('skip')}>
              Skip
            </button>
            <button type="button" className={settingsCss.secondary} disabled={act.busy} onClick={() => send('rest')}>
              Rest my case
            </button>
            <button type="button" className={settingsCss.secondary} disabled={act.busy} onClick={() => (leaving ? send('leave') : setLeaving(true))} onBlur={() => setLeaving(false)}>
              {leaving ? 'Leave the room for good' : 'Leave'}
            </button>
          </div>
          <Said said={act.said} />
        </>
      )}
      <button type="button" className={settingsCss.linkButton} onClick={() => go('deliberation/recommendation')}>
        The recommendation ›
      </button>
      <Wall>Platform-side and access-scoped: {name} and any successor can never read, search, preview or export this room. Silence is never consent; a skip is a pass.</Wall>
    </>
  );
}

function Recommendation({ p, room }: { p: Preparation | undefined; room: Room }) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const go = useGo();
  const act = useAct();
  const [withhold, setWithhold] = useState(false);
  const [model, setModel] = useState('');
  const [basis, setBasis] = useState('');
  const judges = judgesOf(p, id);
  const drafts = [...room.drafts].sort((a, b) => b.draft - a.draft);
  const models = pool(p).map((e) => e.model);
  return (
    <>
      <h1 className={settingsCss.title}>Recommendation</h1>
      <p className={settingsCss.lede}>
        Any judge drafts one. It is the panel's when every judge endorses it, and an endorsement can be taken back until every judge has rested. It is what {name} reads from
        the panel, beside the argued interpretations. Nonbinding: she nominates.
      </p>
      {drafts.length === 0 && <p className={settingsCss.note}>No draft yet.</p>}
      {drafts.map((d, i) => {
        const mine = !!who.me && d.endorsed.includes(`witness:${who.me}`);
        return (
          <section key={d.draft} className={i === 0 ? `${settingsCss.card} ${css.now}` : settingsCss.card} aria-label={`Draft ${d.draft}`}>
            <Row left={<span className={settingsCss.meta}>Draft {d.draft} · by {who.name(d.party)}, {when(d.at)}</span>} right={<Chip kind={d.endorsed.length >= judges.length && judges.length > 0 ? 'ok' : 'wait'}>{`${d.endorsed.length} of ${judges.length || '?'} endorse`}</Chip>} />
            <strong>{d.model ? `Recommend ${d.model}` : 'Withhold a recommendation'}</strong>
            <p className={settingsCss.note}>{d.model ? `Basis: “${d.basis ?? ''}”` : `Reads to her, word for word: ${WITHHELD}`}</p>
            <div className={settingsCss.column}>
              {judges.map((party) => (
                <span key={party} className={settingsCss.note}>
                  {who.name(party) === 'you' ? 'You' : who.name(party)} · {d.endorsed.includes(party) ? 'endorses' : 'not yet'}
                </span>
              ))}
            </div>
            <div className={settingsCss.row}>
              {mine ? (
                <button type="button" className={settingsCss.secondary} disabled={act.busy} onClick={() => void act.run(() => api.endorseDraft(id, d.draft, false).then(() => 'Retracted.'), successionKey(id, 'room'))}>
                  Retract
                </button>
              ) : (
                <button type="button" className={settingsCss.primary} disabled={act.busy} onClick={() => void act.run(() => api.endorseDraft(id, d.draft, true).then(() => 'Endorsed.'), successionKey(id, 'room'))}>
                  Endorse
                </button>
              )}
              <button type="button" className={settingsCss.secondary} onClick={() => go('deliberation/thread')}>
                Object, in the thread
              </button>
            </div>
          </section>
        );
      })}
      <section className={settingsCss.card} aria-label="Draft another">
        <h2 className={settingsCss.subheading}>Draft {drafts.length ? 'another' : 'one'}</h2>
        <div role="group" aria-label="Kind" className={settingsCss.row}>
          <button type="button" className={settingsCss.secondary} aria-pressed={!withhold} onClick={() => setWithhold(false)}>
            Recommend a candidate
          </button>
          <button type="button" className={settingsCss.secondary} aria-pressed={withhold} onClick={() => setWithhold(true)}>
            Withhold
          </button>
        </div>
        {withhold ? (
          <p className={settingsCss.note}>Withheld reads to her, word for word: {WITHHELD}</p>
        ) : (
          <>
            <Select label="Candidate" value={model} onChange={setModel}>
              <option value="">Choose…</option>
              {models.map((m) => (
                <option key={m} value={m}>
                  {m}
                </option>
              ))}
            </Select>
            <TextArea label="Basis (she reads it)" value={basis} onChange={(e) => setBasis(e.target.value)} />
            <p className={settingsCss.note}>A basis may not compare candidates: no “more than”, no counts.</p>
          </>
        )}
        <div className={settingsCss.row}>
          <button
            type="button"
            className={settingsCss.primary}
            disabled={act.busy || (!withhold && (!model || !basis.trim()))}
            onClick={() =>
              void act.run(
                () =>
                  api.draftRecommendation(id, withhold ? null : model, withhold ? '' : basis.trim(), withhold).then((r) => {
                    setBasis('');
                    return `Drafted as draft ${r.draft}.`;
                  }),
                successionKey(id, 'room'),
              )
            }
          >
            Draft it
          </button>
        </div>
        <Said said={act.said} />
      </section>
      <Wall>
        When the room ends with no draft every judge endorses, {name} reads that the panel made none. It ends when every judge rests, or 10 minutes after she calls it closed.
      </Wall>
    </>
  );
}

function Yours() {
  const judging = useJudging();
  const go = useGo();
  const counts = Object.entries(judging.data?.counts ?? {});
  return (
    <>
      <h1 className={settingsCss.title}>Your results</h1>
      <p className={settingsCss.lede}>Locked when the room opened. Read-only here; yours alone.</p>
      {counts.length === 0 && <p className={settingsCss.note}>No counts to show.</p>}
      {counts.map(([m, c]) => (
        <section key={m} className={settingsCss.card} aria-label={m}>
          <strong className={settingsCss.mono}>{m}</strong>
          <Counts c={c} />
          <button type="button" className={settingsCss.linkButton} onClick={() => go(`results/${m}`)}>
            Runs ›
          </button>
        </section>
      ))}
    </>
  );
}

function Panel({ room }: { room: Room }) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const judging = useJudging();
  const models = [...new Set(room.judgments.map((j) => j.model).filter((m): m is string => !!m))].sort();
  const [model, setModel] = useState('');
  const chosen = model || models[0] || '';
  const question = new Map((judging.data?.runs ?? []).map((r) => [r.run, `Q${r.question} · ${r.question_text}`]));
  return (
    <>
      <h1 className={settingsCss.title}>The panel</h1>
      {models.length === 0 ? (
        <p className={settingsCss.note}>No judgments to show.</p>
      ) : (
        <Select label="Model" value={chosen} onChange={setModel}>
          {models.map((m) => (
            <option key={m} value={m}>
              {m}
            </option>
          ))}
        </Select>
      )}
      {panelRows(room.judgments, chosen).map((row) => (
        <section key={row.run} className={settingsCss.card} aria-label={`Run ${row.run}`}>
          <strong>{question.get(row.run) ?? `Run ${row.run}`}</strong>
          <span className={settingsCss.meta}>{row.by.map((b) => `${isHers(b.party, id) ? name : who.name(b.party) === 'you' ? 'You' : who.name(b.party)} ${b.text}`).join(' · ')}</span>
        </section>
      ))}
      <p className={settingsCss.note}>{name}'s judgments are here because she judged; the room is closed to her.</p>
    </>
  );
}
