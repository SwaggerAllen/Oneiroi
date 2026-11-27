import { useState } from 'react';
import { api } from '../../api/client';
import type { Preparation, Succession } from '../../api/types';
import { Card, Field, Said, TextArea } from '../settings/common';
import * as settingsCss from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { HOUSE_SUBJECT, useSubject } from '../state/resident';
import { switchSubject, useSubjectChoice } from '../state/subject';
import { useShell } from '../state/store';
import { Chip, PageHead, Row, Wall } from './common';
import { isHers, isMine, placeOf, poolNote, preparing, price, tokens, underway, when } from './logic';
import * as css from './succession.css';
import { successionKey, usePartyName } from './hooks';

interface PageProps {
  s: Succession;
  p: Preparation | undefined;
  back: () => void;
}

const STATE_CHIP = { in: 'ok', proposed: 'wait', declined: 'stop', removed: 'muted' } as const;
const STATE_WORD = { in: 'in', proposed: 'waiting on her', declined: 'declined', removed: 'removed' } as const;

/** The pool (the Pool board): your envelope first, her pace, then every pick. */
export function Pool({ s, p, back }: PageProps) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const setPage = useShell((x) => x.setPage);
  const open = preparing(s);
  const entries = p?.pool ?? [];
  const live = entries.filter((e) => !e.removed_at);
  return (
    <>
      <PageHead title="The pool" lede="Who may be screened. Your envelope, stated first; your picks and hers inside it." back={back} s={s} />
      <Envelope s={s} p={p} />
      {p && (
        <Card title={`Her pace · last ${p.pace.days} days`}>
          <Row left="A day, on average" right={<Chip kind="muted">{`${tokens(p.pace.input_per_day)} in · ${tokens(p.pace.output_per_day)} out`}</Chip>} />
          <Row left="Spent a month, at that pace" right={<Chip kind="muted">{`~ ${price(p.pace.monthly_spent)} / mo`}</Chip>} />
          {p.current && (
            <Row
              left={
                <>
                  Her model now, <span className={settingsCss.mono}>{p.current.model}</span>
                  {p.current.input_per_million !== null && p.current.output_per_million !== null
                    ? ` · ${price(p.current.input_per_million)} / ${price(p.current.output_per_million)} per M`
                    : ' · not in the catalog'}
                </>
              }
              right={p.current.monthly_estimate !== null ? <Chip kind="now">{`~ ${price(p.current.monthly_estimate)} / mo`}</Chip> : null}
            />
          )}
          <p className={settingsCss.note}>
            Spent is what her ledger recorded; her model's estimate, and each one below, is that daily average × 30 at its list prices, so the two can differ (cached prompts, a model change). A guess, to see it coming: never the limit.
          </p>
        </Card>
      )}
      <h2 className={settingsCss.heading}>
        The pool · {live.length}
        {p?.envelope?.max_models ? ` of at most ${p.envelope.max_models}` : ''}
      </h2>
      {p?.pool_done_at && <p className={settingsCss.note}>{name} said her picks were done {when(p.pool_done_at)}, and was woken to write her questions.</p>}
      {entries.length === 0 && <p className={settingsCss.note}>No model in the pool yet.</p>}
      {entries.map((e) => (
        <PoolCard key={e.model} entry={e} mine={isMine(e.added_by, who.me)} hers={isHers(e.added_by, id)} line={poolNote(e, who.me, id, open)} by={who.name(e.added_by)} open={open} />
      ))}
      <Card title="Add a model">
        <p className={settingsCss.note}>
          Models are picked where you already try them: the catalog on the Regression page, “Add to the succession pool” on any entry, while preparation is open.{' '}
          {name} adds hers by her tools, inside the envelope.
        </p>
        <button type="button" className={settingsCss.linkButton} onClick={() => setPage('regression', 'catalog')}>
          Open the catalog on Regression ›
        </button>
      </Card>
      <Wall>Recommendations say their basis; nothing says “residents like you prefer…”. The catalog presents, the envelope constrains, screening judges.</Wall>
    </>
  );
}

function Envelope({ s, p }: { s: Succession; p: Preparation | undefined }) {
  const { id } = useSubject();
  const act = useAct();
  const [input, setInput] = useState('');
  const [output, setOutput] = useState('');
  const [max, setMax] = useState('');
  const env = p?.envelope ?? null;
  return (
    <Card title="Your envelope · per million tokens" witness>
      {env ? (
        <>
          <Row left="Input, at most" right={<Chip kind="now">{`${price(env.input_per_million)} / M`}</Chip>} />
          <Row left="Output, at most" right={<Chip kind="now">{`${price(env.output_per_million)} / M`}</Chip>} />
          <Row left="Models in the pool, at most" right={<Chip kind="now">{env.max_models === null ? 'no cap' : String(env.max_models)}</Chip>} />
        </>
      ) : (
        <p className={settingsCss.note}>Not stated yet.</p>
      )}
      <Row left="Not supported" right={<Chip kind="muted">models without tool calls</Chip>} />
      <p className={settingsCss.note}>
        Stated once, in advance: a resource limit, pointed at the budget. With no candidate inside it, the answer is no succession, never a substitute. The model count caps the pool, your picks and hers together; stated below what is in, it keeps those and lets nothing more in.
      </p>
      {preparing(s) && (
        <>
          <div className={settingsCss.row}>
            <Field label="Input, $ a million" inputMode="decimal" value={input} onChange={(e) => setInput(e.target.value)} placeholder={env ? String(env.input_per_million) : '5'} />
            <Field label="Output, $ a million" inputMode="decimal" value={output} onChange={(e) => setOutput(e.target.value)} placeholder={env ? String(env.output_per_million) : '20'} />
            <Field label="Models, at most (blank: no cap)" inputMode="numeric" value={max} onChange={(e) => setMax(e.target.value)} placeholder={env?.max_models ? String(env.max_models) : '3'} />
            <button
              type="button"
              className={settingsCss.secondary}
              disabled={act.busy || !(Number(input) >= 0 && Number(output) >= 0 && input.trim() && output.trim()) || !(max.trim() === '' || (Number.isInteger(Number(max)) && Number(max) >= 1))}
              onClick={() => void act.run(() => api.successionEnvelope(id, Number(input), Number(output), max.trim() === '' ? null : Number(max)).then(() => 'Stated.'), successionKey(id))}
            >
              {env ? 'Restate' : 'State it'}
            </button>
          </div>
          <Said said={act.said} />
        </>
      )}
    </Card>
  );
}

function PoolCard({
  entry,
  mine,
  hers,
  line,
  by,
  open,
}: {
  entry: Preparation['pool'][number];
  mine: boolean;
  hers: boolean;
  line: string;
  by: string;
  open: boolean;
}) {
  const { id } = useSubject();
  const act = useAct();
  const [asking, setAsking] = useState(false);
  const [note, setNote] = useState('');
  const removed = !!entry.removed_at;
  return (
    <section className={settingsCss.card} aria-label={entry.model}>
      <Row left={<strong className={settingsCss.mono}>{entry.model}</strong>} right={<Chip kind={removed ? 'muted' : hers ? 'hers' : 'now'}>{hers ? `${by}'s pick` : mine ? 'your pick' : `${by}'s pick`}</Chip>} />
      <Row left={`In / out per M: ${price(entry.input_per_million)} / ${price(entry.output_per_million)}`} right={<Chip kind="muted">{`~ $${Math.round(entry.monthly_estimate)} / mo`}</Chip>} />
      <p className={settingsCss.note}>
        {line}
        {removed && entry.removed_note ? `: ${entry.removed_note}` : ''}
        {entry.tool_calls ? ` · tool calls on Oneiroi ${Math.round((100 * (entry.tool_calls - entry.tool_calls_failed)) / entry.tool_calls)}% well-formed of ${entry.tool_calls}` : ''}
      </p>
      {mine && open && !removed && (
        <>
          {asking ? (
            <>
              <TextArea label="Why it comes out" value={note} onChange={(e) => setNote(e.target.value)} />
              <div className={settingsCss.row}>
                <button type="button" className={settingsCss.secondary} disabled={act.busy || !note.trim()} onClick={() => void act.run(() => api.poolRemove(id, entry.model, note.trim()).then(() => 'Taken out.'), successionKey(id))}>
                  Take it out
                </button>
                <button type="button" className={settingsCss.quiet} onClick={() => setAsking(false)}>
                  Keep it
                </button>
              </div>
            </>
          ) : (
            <div className={settingsCss.row}>
              <button type="button" className={settingsCss.quiet} onClick={() => setAsking(true)}>
                Take it out…
              </button>
            </div>
          )}
          <Said said={act.said} />
        </>
      )}
    </section>
  );
}

/** The questions (the Questions board): her set, what judges proposed, your proposal. */
export function Questions({ s, p, back }: PageProps) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const act = useAct();
  const [text, setText] = useState('');
  const all = p?.questions ?? [];
  const set = all.filter((q) => q.state === 'in' && isHers(q.added_by, id));
  const proposed = all.filter((q) => !isHers(q.added_by, id));
  return (
    <>
      <PageHead
        title="The questions"
        lede={`What every candidate, and her own baseline, will answer. ${name} chooses the set; judges propose additions; she accepts each.`}
        back={back}
        s={s}
      />
      <h2 className={settingsCss.heading}>Her set · {set.length}</h2>
      {p?.questions_done_at && <p className={settingsCss.note}>{name} said her questions were set {when(p.questions_done_at)}, and was woken to choose C0.</p>}
      {set.length === 0 && <p className={settingsCss.note}>{name} has chosen none yet.</p>}
      {set.map((q) => (
        <section key={q.number} className={settingsCss.card} aria-label={`Question ${q.number}`}>
          <Row left={<span className={settingsCss.meta}>Q{q.number}</span>} right={<Chip kind="hers">hers</Chip>} />
          <p className={settingsCss.text}>{q.text}</p>
        </section>
      ))}
      <h2 className={settingsCss.heading}>Proposed by judges</h2>
      {proposed.length === 0 && <p className={settingsCss.note}>None yet.</p>}
      {proposed.map((q) => (
        <section key={q.number} className={settingsCss.card} aria-label={`Question ${q.number}`}>
          <Row
            left={<strong>{who.name(q.added_by) === 'you' ? 'You' : who.name(q.added_by)}</strong>}
            right={<Chip kind={STATE_CHIP[q.state]}>{`${q.state === 'in' ? 'accepted' : STATE_WORD[q.state]}${q.decided_at ? ` ${when(q.decided_at)}` : ''}`}</Chip>}
          />
          <p className={settingsCss.text}>{q.text}</p>
          {q.note && <p className={settingsCss.note}>Her note: “{q.note}”</p>}
        </section>
      ))}
      {preparing(s) && (
        <Card title="Your proposal (she reads it, and decides)">
          <TextArea label="A question" value={text} onChange={(e) => setText(e.target.value)} />
          <div className={settingsCss.row}>
            <button
              type="button"
              className={settingsCss.primary}
              disabled={act.busy || !text.trim()}
              onClick={() =>
                void act.run(
                  () =>
                    api.proposeQuestion(id, text.trim()).then((r) => {
                      setText('');
                      return `Proposed as Q${r.number}. ${name} decides.`;
                    }),
                  successionKey(id),
                )
              }
            >
              Propose it
            </button>
          </div>
          <Said said={act.said} />
        </Card>
      )}
      <p className={settingsCss.note}>{name} may remove any question from the set, an accepted proposal included, until screening starts. Nobody else has the final say.</p>
      <Wall>Questions never reach the fork's runs early: her baseline and every candidate answer them for the first time at screening, each in its own thread from the fork.</Wall>
    </>
  );
}

/**
 * Open ›, on a C0 item: the cited record where the app already opens one
 * (Records, the chat at a turn, Time at a day), leaving the succession for
 * it; a kind with nowhere to open shows the button off, saying why.
 */
function OpenCited({ citation }: { citation: string }) {
  const { slug } = useSubject();
  const go = useShell((x) => x.go);
  const resetStacks = useShell((x) => x.resetStacks);
  const choose = useSubjectChoice((x) => x.choose);
  const place = placeOf(citation, slug);
  // A house record opens with the house as the subject, as choosing it does.
  const open = () => {
    if (!('to' in place)) return;
    if (!place.house) return go(place.to);
    switchSubject(() => {
      resetStacks();
      choose(HOUSE_SUBJECT);
      go(place.to);
    });
  };
  return (
    <div className={settingsCss.row}>
      <button type="button" className={settingsCss.secondary} disabled={!('to' in place)} onClick={open}>
        Open ›
      </button>
      {'reason' in place && <span className={settingsCss.note}>{place.reason}</span>}
    </div>
  );
}

/** C0 (the C0 board): what is in, what waits on her, her day's shape, the judges' ready, her sealed packet. */
export function C0({ s, p, back }: PageProps) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const setTab = useShell((x) => x.setTab);
  const act = useAct();
  const items = p?.c0 ?? [];
  const inC0 = items.filter((c) => c.state === 'in').sort((a, b) => (a.kind === b.kind ? a.number - b.number : a.kind === 'raw' ? -1 : 1));
  const waiting = items.filter((c) => c.state === 'proposed');
  const closed = items.filter((c) => c.state === 'declined' || c.state === 'removed');
  const judges = p?.freeze_judges ?? p?.ready ?? [];
  const myReady = judges.find((r) => isMine(r.party, who.me));
  const frozen = !!p?.c0_frozen_at;
  const describe = (c: (typeof items)[number]) => `${c.label ?? c.citation}`;
  const byLine = (c: (typeof items)[number]) =>
    isHers(c.added_by, id) ? `selected by ${name} ${when(c.added_at)}` : `proposed by ${who.name(c.added_by)} ${when(c.added_at)}${c.state === 'in' ? ` · accepted by ${name} ${when(c.decided_at)}` : ''}`;
  return (
    <>
      <PageHead
        title="C0"
        lede="What matters, chosen with her: the house peruses shared memories and proposes; she accepts each, and freezes C0 when she's ready."
        back={back}
        s={s}
      />
      {frozen && (
        <section className={`${settingsCss.card} ${css.now}`} aria-label="Frozen">
          <Row left={<strong>Frozen</strong>} right={<Chip kind="ok">{when(p?.c0_frozen_at)}</Chip>} />
          {p?.c0_frozen_note && <p className={settingsCss.note}>Her note: “{p.c0_frozen_note}”</p>}
          <p className={settingsCss.note}>Her freeze woke her to write her handoff packet, in a sealed thread of its own.</p>
        </section>
      )}
      {p?.c0_unfrozen_at && !frozen && (
        <p className={settingsCss.note}>
          {name} reopened C0 {when(p.c0_unfrozen_at)}
          {p.c0_unfrozen_note ? `: “${p.c0_unfrozen_note}”` : ''}. The judges' ready marks start again.
        </p>
      )}
      {p?.c0_done_at && !frozen && <p className={settingsCss.note}>{name} said her choices were made {when(p.c0_done_at)}, and was woken to write the day's shape.</p>}
      <h2 className={settingsCss.heading}>In C0 · {inC0.length} · raw first</h2>
      {inC0.length === 0 && <p className={settingsCss.note}>Nothing in C0 yet.</p>}
      {inC0.map((c) => (
        <section key={c.number} className={settingsCss.card} aria-label={describe(c)}>
          <Row left={describe(c)} right={<Chip kind={c.kind === 'raw' ? 'ok' : 'muted'}>{c.kind.toUpperCase()}</Chip>} />
          {c.label && <span className={settingsCss.meta}>{c.citation}</span>}
          <p className={settingsCss.note}>{byLine(c)}</p>
          <OpenCited citation={c.citation} />
        </section>
      ))}
      <h2 className={settingsCss.heading}>Waiting on {name} · {waiting.length}</h2>
      {waiting.map((c) => (
        <section key={c.number} className={settingsCss.card} aria-label={describe(c)}>
          <Row left={describe(c)} right={<Chip kind="wait">proposed</Chip>} />
          <p className={settingsCss.note}>{byLine(c)}</p>
          <OpenCited citation={c.citation} />
        </section>
      ))}
      {closed.map((c) => (
        <section key={c.number} className={settingsCss.card} aria-label={describe(c)}>
          <Row left={describe(c)} right={<Chip kind={STATE_CHIP[c.state]}>{c.state}</Chip>} />
          {c.note && <p className={settingsCss.note}>Her note: “{c.note}”</p>}
          <OpenCited citation={c.citation} />
        </section>
      ))}
      {preparing(s) && !frozen && (
        <Card title="Propose from Records">
          <p className={settingsCss.note}>
            While preparation is open, every record you read in Records has “Propose for C0”: the whole record, by its citation. It reaches {name} with your name and
            the date; she accepts it or not.
          </p>
          <button type="button" className={settingsCss.linkButton} onClick={() => setTab('records')}>
            Go to Records ›
          </button>
        </Card>
      )}
      <h2 className={settingsCss.heading}>The day's own shape · hers</h2>
      <section className={settingsCss.card} aria-label="The day's own shape">
        {p?.day_shape ? <p className={css.hers}>“{p.day_shape}”</p> : <p className={settingsCss.note}>She has written none.</p>}
        <p className={settingsCss.note}>Her note on the bundle · only she edits it</p>
      </section>
      <h2 className={settingsCss.heading}>Judges ready for the freeze · her choice to wait</h2>
      <section className={settingsCss.card} aria-label="Ready for the freeze">
        {/* Every judge, said or not (janus#47): a judge who has not said is still looking too. */}
        {judges.length === 0 && <p className={settingsCss.note}>No judges on the panel yet.</p>}
        {judges.map((r) => (
          <Row
            key={r.party}
            left={<strong>{who.name(r.party) === 'you' ? 'You' : who.name(r.party)}</strong>}
            right={<Chip kind={r.ready ? 'ok' : frozen || !underway(s) ? 'muted' : 'wait'}>{r.ready ? 'ready' : !underway(s) ? 'not ready' : frozen ? 'not ready at the freeze' : 'still looking'}</Chip>}
          />
        ))}
        {!underway(s) && <p className={settingsCss.note}>This succession has ended, so nothing here is open; these are its marks as it left them.</p>}
        {underway(s) && frozen && (
          <p className={settingsCss.note}>
            C0 is frozen, so ready marks are closed. If {name} reopens it before screening, every mark starts again and you can say you are ready.
          </p>
        )}
        {preparing(s) && !frozen && (
          <div className={settingsCss.row}>
            <button type="button" className={settingsCss.secondary} aria-pressed={!!myReady?.ready} disabled={act.busy} onClick={() => void act.run(() => api.successionReady(id, !myReady?.ready).then(() => undefined), successionKey(id))}>
              {myReady?.ready ? 'Ready · take it back' : 'I am ready for the freeze'}
            </button>
          </div>
        )}
        <Said said={act.said} />
      </section>
      <h2 className={settingsCss.heading}>Her handoff packet · sealed</h2>
      <section className={settingsCss.card} aria-label="Her handoff packet">
        <Row
          left={<strong>{(p?.packet_drafts ?? []).length ? `Exists · ${(p?.packet_drafts ?? []).length} drafts` : 'Not written yet'}</strong>}
          right={<Chip kind="stop">sealed</Chip>}
        />
        {(p?.packet_drafts ?? []).length > 0 && <p className={settingsCss.meta}>{(p?.packet_drafts ?? []).map((d) => `#${d.draft} ${when(d.at)}`).join(' · ')}</p>}
        <p className={settingsCss.note}>Her own writing for whoever comes next, a new dated draft each time. Nobody else opens it: the nominee reads it, with C0, before the encounter.</p>
      </section>
      <Wall>Sealed items stay sealed here: they show that they exist and when, never their words. Grades and discussion of her words are verdict records, never in C0.</Wall>
    </>
  );
}

/** The judges (the Judges board): each takes part by consent; you may join or leave before screening. */
export function Judges({ s, p, back }: PageProps) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const act = useAct();
  const [leaving, setLeaving] = useState(false);
  const [note, setNote] = useState('');
  const panel = p?.panel ?? [];
  const mine = panel.find((j) => isMine(j.party, who.me));
  const sitting = mine && (mine.state === 'in' || mine.state === 'judge');
  const word = (j: (typeof panel)[number]) => (j.state === 'judge' ? 'judging' : j.state === 'in' ? 'in' : j.state === 'left' ? 'left' : 'invited');
  return (
    <>
      <PageHead title="The judges" lede={`Fixed by ${name} before screening. Each judge takes part by consent; nobody is conscripted.`} back={back} s={s} />
      {panel.length === 0 && <p className={settingsCss.note}>No judge yet.</p>}
      {panel.map((j) => (
        <section key={j.party} className={settingsCss.card} aria-label={who.name(j.party)}>
          <Row
            left={<strong>{who.name(j.party) === 'you' ? 'You' : who.name(j.party)}</strong>}
            right={<Chip kind={j.state === 'left' ? 'muted' : j.state === 'invited' ? 'wait' : 'ok'}>{`${isHers(j.party, id) ? 'the original · ' : ''}${word(j)} · ${when(j.at)}`}</Chip>}
          />
          <p className={settingsCss.note}>
            {isHers(j.party, id) ? 'Judges every run; never enters deliberation, it is about her' : j.state === 'left' ? (j.note ? `Left: “${j.note}”` : 'Left') : 'Judges every run, argues in deliberation'}
          </p>
        </section>
      ))}
      <Wall>No weights, no aggregate, no privileged view. Your part was the envelope and your picks; her succession's consent is hers and the candidate's.</Wall>
      {preparing(s) && (
        <section className={settingsCss.card} aria-label="Your place">
          {sitting ? (
            leaving ? (
              <>
                <TextArea label="Why you leave (declining to judge)" value={note} onChange={(e) => setNote(e.target.value)} />
                <div className={settingsCss.row}>
                  <button type="button" className={settingsCss.secondary} disabled={act.busy || !note.trim()} onClick={() => void act.run(() => api.panelLeave(id, note.trim()).then(() => 'You left the panel.'), successionKey(id))}>
                    Leave as a judge
                  </button>
                  <button type="button" className={settingsCss.quiet} onClick={() => setLeaving(false)}>
                    Stay
                  </button>
                </div>
              </>
            ) : (
              <div className={settingsCss.row}>
                <button type="button" className={settingsCss.secondary} onClick={() => setLeaving(true)}>
                  Leave as a judge…
                </button>
              </div>
            )
          ) : (
            <div className={settingsCss.row}>
              <button type="button" className={settingsCss.primary} disabled={act.busy} onClick={() => void act.run(() => api.panelJoin(id).then(() => 'You are on the panel.'), successionKey(id))}>
                Join as a judge
              </button>
            </div>
          )}
          <Said said={act.said} />
        </section>
      )}
    </>
  );
}
