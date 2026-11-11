import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { KindsData, RoutesData } from '../../api/types';
import { kindLine, NAME, routeLine, routeOk, settingsKey } from './logic';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { Card, Field, Said, Select, TextArea } from './common';
import * as css from './settings.css';
import { useAct } from './useAct';

/**
 * Kinds and routes (seshat#51, xenia#19): every kind of document her
 * records hold, with their gates and the proposals about them; every
 * route in one list, with its runs. A kind's folder settings live in
 * Records; profiles are on the Profiles, keys and connections page.
 */
export function Kinds() {
  const { id, name } = useSubject();
  const kinds = useQuery({
    queryKey: settingsKey(id, 'kinds'),
    queryFn: () => api.kinds(id),
  });
  const routes = useQuery({
    queryKey: settingsKey(id, 'routes'),
    queryFn: () => api.routes(id),
  });
  // One note for the next change, as the current client asks: a gate
  // off, an answer, a profile revoked each carries it.
  const [note, setNote] = useState('');
  const act = useAct();
  const also = [
    ['resident', id, 'records'],
    ['resident', id, 'bell'],
  ];
  const noted = note.trim() !== '' && !act.busy;
  const run = (work: () => Promise<string>) => void act.run(work, ...also);

  return (
    <>
      <Card title="A note for the next change" witness>
        <p className={css.note}>Turning a gate off, answering her, and asking a run each carry a note; she reads it.</p>
        <Field label="Your note" value={note} onChange={(e) => setNote(e.target.value)} />
        <Said said={act.said} />
      </Card>
      {kinds.data ? <KindsCard name={name} data={kinds.data} noted={noted} busy={act.busy} note={note.trim()} run={run} id={id} /> : <p className={css.note}>Reading the kinds…</p>}
      {routes.data ? <RoutesCard name={name} data={routes.data} busy={act.busy} note={note.trim()} run={run} id={id} /> : <p className={css.note}>Reading the routes…</p>}
    </>
  );
}

interface Part {
  id: string;
  name: string;
  busy: boolean;
  note: string;
  run: (work: () => Promise<string>) => void;
}

function KindsCard({ id, name, data, noted, busy, note, run }: Part & { data: KindsData; noted: boolean }) {
  const open = data.proposals.filter((p) => p.answered_at === null);
  const answered = data.proposals.filter((p) => p.answered_at !== null).slice(0, 5);
  const waiting = new Set(open.map((p) => p.kind));
  const gateSaid = {
    moved: 'The gate moved.',
    proposed: `Proposed; ${name} answers.`,
    already: 'The gate is already there.',
  };
  const [kind, setKind] = useState('');
  const [label, setLabel] = useState('');
  const [approvable, setApprovable] = useState(false);
  const [cites, setCites] = useState(false);
  const [ask, setAsk] = useState('');
  const nameOk = NAME.test(kind) && !data.kinds.some((k) => k.kind === kind && !k.own);
  const goFolder = useShell((s) => s.go);

  return (
    <>
      {open.length > 0 && (
        <Card title="Open gate proposals" witness>
          <ul className={css.list}>
            {open.map((p) => (
              <li key={p.number} className={css.item}>
                <span className={css.text}>
                  #{p.number} the {p.kind} gate {p.approvable ? 'on' : 'off'}, proposed by {p.proposed_by === 'resident' ? name : 'you'}
                  {p.note ? `: ${p.note}` : ''}
                </span>
                {p.proposed_by === 'resident' ? (
                  <div className={css.row}>
                    <button
                      type="button"
                      className={css.primary}
                      disabled={!noted}
                      onClick={() => run(() => api.answerKindGate(id, p.number, true, note).then(() => 'Agreed: the gate moved.'))}
                    >
                      Agree
                    </button>
                    <button
                      type="button"
                      className={css.secondary}
                      disabled={!noted}
                      onClick={() => run(() => api.answerKindGate(id, p.number, false, note).then(() => 'Declined.'))}
                    >
                      Decline
                    </button>
                    {!noted && <span className={css.note}>Write a note above first.</span>}
                  </div>
                ) : (
                  <span className={css.note}>Waiting for {name}.</span>
                )}
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card title="Kinds">
        <p className={css.note}>A gate means a document of that kind at status: review waits on you. A gate goes on at either word; off is a proposal the other answers.</p>
        <ul className={css.list} aria-label="Kinds">
          {data.kinds.map((k) => (
            <li key={k.kind} className={css.item}>
              <span className={css.text}>
                <strong>{k.label}</strong> <span className={css.meta}>({k.kind})</span>
              </span>
              <span className={css.note}>{kindLine(k, name)}</span>
              <div className={css.row}>
                {k.gated &&
                  (waiting.has(k.kind) ? (
                    <span className={css.note}>A gate proposal is open.</span>
                  ) : k.approvable ? (
                    <button type="button" className={css.quiet} disabled={!noted} onClick={() => run(() => api.kindGate(id, k.kind, false, note).then((r) => gateSaid[r.outcome]))}>
                      Propose gate off
                    </button>
                  ) : (
                    <button type="button" className={css.quiet} disabled={busy} onClick={() => run(() => api.kindGate(id, k.kind, true, note).then((r) => gateSaid[r.outcome]))}>
                      Gate on
                    </button>
                  ))}
                {k.folder !== null && (
                  <button type="button" className={css.quiet} onClick={() => goFolder({ tab: 'records', path: `folder/${k.kind}` })}>
                    Folder settings ›
                  </button>
                )}
              </div>
            </li>
          ))}
        </ul>
      </Card>

      <Card title={`A kind of ${name}'s`}>
        <form
          aria-label="Define a kind"
          className={css.column}
          onSubmit={(e) => {
            e.preventDefault();
            if (!nameOk || busy) return;
            const definition = {
              kind,
              label: label.trim() || undefined,
              cites,
              approvable,
              ask: approvable && ask.trim() ? ask.trim() : undefined,
              note: note || undefined,
            };
            run(() => api.defineKind(id, definition).then((r) => `Defined: ${r.kind}, written as ${r.kind}/kind.json.`));
            setKind('');
            setLabel('');
            setApprovable(false);
            setCites(false);
            setAsk('');
          }}
        >
          <p className={css.note}>Its name is its folder: lowercase letters, digits and -. It is hers to write; to rewrite one, define it again under its name.</p>
          <Field label="Name" value={kind} onChange={(e) => setKind(e.target.value.trim())} />
          <Field label="Label" value={label} onChange={(e) => setLabel(e.target.value)} />
          <label className={css.check}>
            <input type="checkbox" checked={cites} onChange={(e) => setCites(e.target.checked)} /> Its citations make edges
          </label>
          <label className={css.check}>
            <input type="checkbox" checked={approvable} onChange={(e) => setApprovable(e.target.checked)} /> A document at status: review waits on you
          </label>
          {approvable && <Field label="What you are asked" value={ask} onChange={(e) => setAsk(e.target.value)} />}
          <div>
            <button type="submit" className={css.primary} disabled={!nameOk || busy}>
              Define the kind
            </button>
          </div>
        </form>
      </Card>

      {answered.length > 0 && (
        <Card title="Lately answered">
          {answered.map((p) => (
            <p key={p.number} className={css.note}>
              #{p.number} the {p.kind} gate {p.approvable ? 'on' : 'off'}: {p.agree ? 'agreed' : 'declined'}
              {p.answer_note ? `, “${p.answer_note}”` : ''}
            </p>
          ))}
        </Card>
      )}
    </>
  );
}

function RoutesCard({ id, name, data, busy, note, run }: Part & { data: RoutesData }) {
  const setPage = useShell((s) => s.setPage);
  const [key, setKey] = useState('');
  const [prompt, setPrompt] = useState('');
  const [profile, setProfile] = useState('');
  const [kind, setKind] = useState('');
  const builtIn = data.routes.filter((r) => r.built_in);
  const hers = data.routes.filter((r) => !r.built_in);
  const ok = routeOk(data, { key, prompt, profile, kind });

  return (
    <>
      <Card title="Routes">
        <p className={css.note}>
          Every way into or out of {name}'s house, each through one profile.{' '}
          <button type="button" className={css.quiet} onClick={() => setPage('connections')}>
            Profiles ›
          </button>
        </p>
        <ul className={css.list} aria-label="Routes">
          {[...builtIn, ...hers].map((r) => (
            <li key={r.key} className={css.item}>
              <span className={css.text}>
                <strong>{r.label}</strong> <span className={css.meta}>({r.key})</span>
                {r.built_in ? '' : ` · ${name}'s`}
              </span>
              <span className={css.note}>{routeLine(r)}</span>
              {r.state === 'unable' && <span className={`${css.note} ${css.warn}`}>Unable to fire: {r.why}</span>}
              {r.prompt && <span className={css.note}>Reads for: {r.prompt}</span>}
              {!r.built_in && r.state === 'ready' && (
                <div>
                  <button
                    type="button"
                    className={css.quiet}
                    disabled={busy}
                    onClick={() => run(() => api.askRoute(id, r.key, note).then((x) => `Asked as run #${x.number}; the reader fires it on its next wait.`))}
                  >
                    Ask a run
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      </Card>

      {data.runs.length > 0 && (
        <Card title="Runs">
          <ul className={css.list} aria-label="Runs">
            {data.runs.slice(0, 10).map((r) => (
              <li key={r.number} className={css.line}>
                <span>
                  #{r.number} {r.key}
                </span>
                <span className={r.state === 'failed' ? `${css.meta} ${css.warn}` : css.meta}>
                  {r.state}
                  {r.path ? `, as ${r.path}` : ''}
                  {r.reason ? ` (${r.reason})` : ''}
                </span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card title={`A route of ${name}'s`}>
        <form
          aria-label="Define a route"
          className={css.column}
          onSubmit={(e) => {
            e.preventDefault();
            if (!ok || busy) return;
            run(() =>
              api
                .defineRoute(id, {
                  key,
                  prompt: prompt.trim(),
                  profile,
                  kind,
                  note: note || undefined,
                })
                .then((r) => `Defined: ${r.key}, written as routes/${r.key}.json.`),
            );
            setKey('');
            setPrompt('');
          }}
        >
          <p className={css.note}>
            A reading the reader does on request, through a profile that stands, landing as documents of a kind she writes. What it reads for is only that: it never chooses the
            profile, the sites or where it lands.
          </p>
          <Field label="Route name" value={key} onChange={(e) => setKey(e.target.value.trim())} />
          <TextArea label="What it reads for" value={prompt} onChange={(e) => setPrompt(e.target.value)} />
          <div className={css.row}>
            <Select label="Through" value={profile} onChange={setProfile}>
              <option value="">Choose a profile</option>
              {data.profiles
                .filter((p) => !p.revoked)
                .map((p) => (
                  <option key={p.key} value={p.key}>
                    {p.label}
                  </option>
                ))}
            </Select>
            <Select label="Lands as" value={kind} onChange={setKind}>
              <option value="">Choose a kind</option>
              {data.landing.map((k) => (
                <option key={k} value={k}>
                  {k}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <button type="submit" className={css.primary} disabled={!ok || busy}>
              Define the route
            </button>
          </div>
        </form>
      </Card>
    </>
  );
}
