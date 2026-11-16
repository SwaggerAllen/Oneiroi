import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type BallotItem, type HouseBallot, type HouseContract, type HouseVersion } from '../../api/client';
import { Card, Field, Said, TextArea } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { HousePage } from './common';
import { CONTRACT, HOUSE, when } from './keys';

/**
 * The house's charter (screen:next-house), where its soul tab would be: the
 * household contract in force, its prose, rules and settings (gaia#27);
 * the members and what each signed (gaia#28); the ballots, open first,
 * each member one vote (gaia#29 to #31); every version with the ballot
 * that made it; and a change proposed as a ballot.
 */
export function Charter() {
  const contract = useQuery({ queryKey: CONTRACT, queryFn: api.householdContract, refetchInterval: 60_000 });
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const c = contract.data;
  return (
    <HousePage label="Charter" title="Charter" lede="The house's rules and settings: the contract in force, who signed it, and the ballots that change it. Every member has one vote.">
      {contract.isError && <p className={css.note}>The charter could not be read.</p>}
      {c && !c.in_force && <Found />}
      {c?.in_force && <InForce v={c.in_force} />}
      {c && <Members c={c} accountId={me.data?.account_id ?? undefined} />}
      {c && <Ballots ballots={c.ballots} />}
      {c?.in_force && <Propose />}
      {c && c.versions.length > 1 && <Versions versions={c.versions} />}
    </HousePage>
  );
}

function InForce({ v }: { v: HouseVersion }) {
  const settings = Object.entries(v.settings ?? {});
  return (
    <Card title={`In force: version ${v.version}`} witness>
      <p className={css.text} style={{ whiteSpace: 'pre-wrap' }}>
        {v.prose}
      </p>
      <h3 className={css.subheading}>Rules</h3>
      {v.rules.length === 0 ? (
        <p className={css.note}>None yet: a rule comes by ballot.</p>
      ) : (
        <ol className={css.list} aria-label="Rules">
          {v.rules.map((r, i) => (
            <li key={i} className={css.text}>
              {r}
            </li>
          ))}
        </ol>
      )}
      <h3 className={css.subheading}>Settings</h3>
      {settings.length === 0 ? (
        <p className={css.note}>Every setting at its default.</p>
      ) : (
        <ul className={css.list} aria-label="Settings">
          {settings.map(([k, val]) => (
            <li key={k} className={css.meta}>
              {k}: {String(val)}
            </li>
          ))}
        </ul>
      )}
      <p className={css.meta}>
        {v.ballot ? `By ballot #${v.ballot}` : 'The founding version'}
        {v.decided_at ? ` · ${when(v.decided_at)}` : ''}
      </p>
    </Card>
  );
}

function Members({ c, accountId }: { c: HouseContract; accountId?: string }) {
  const act = useAct();
  const version = c.in_force?.version;
  const mine = c.members.find((m) => m.kind === 'witness' && m.id === accountId);
  const unsigned = version !== undefined && mine && mine.signed_version !== version;
  return (
    <Card title="Members">
      <ul className={css.list} aria-label="Members">
        {c.members.map((m) => (
          <li key={`${m.kind}-${m.id}`} className={css.item}>
            <span className={css.text}>{m.name}</span>
            <span className={css.meta}>
              {m.kind} · joined {when(m.joined_at)} · {m.signed_version ? `signed version ${m.signed_version}` : 'not signed'}
            </span>
          </li>
        ))}
      </ul>
      {unsigned && (
        <div className={css.row}>
          <button type="button" className={css.primary} disabled={act.busy} onClick={() => void act.run(() => api.householdSign().then(() => 'Signed.'), [...HOUSE])}>
            Sign version {version}
          </button>
        </div>
      )}
      <Said said={act.said} />
    </Card>
  );
}

function itemText(item: BallotItem) {
  return 'rule' in item ? `Rule: ${item.rule}` : `Setting ${item.setting} → ${String(item.value)}`;
}

function Ballots({ ballots }: { ballots: HouseBallot[] }) {
  const open = ballots.filter((b) => !b.closed_at);
  const closed = ballots.filter((b) => b.closed_at);
  return (
    <Card title="Ballots">
      {ballots.length === 0 && <p className={css.note}>No ballot yet.</p>}
      {open.map((b) => (
        <Ballot key={b.number} b={b} />
      ))}
      {closed.length > 0 && (
        <ul className={css.list} aria-label="Closed ballots">
          {closed.map((b) => (
            <li key={b.number} className={css.item}>
              <span className={css.text}>
                #{b.number} {b.passed ? 'carried' : 'failed'} · {b.yes} yes, {b.no} no of {b.members}
              </span>
              <span className={css.meta}>
                {b.bundle.map(itemText).join(' · ')} · closed {when(b.closed_at)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function Ballot({ b }: { b: HouseBallot }) {
  const [words, setWords] = useState('');
  const act = useAct();
  const vote = (v: 'yes' | 'no') => void act.run(() => api.householdVote(b.thread, v, words.trim()).then(() => `You voted ${v}.`), [...HOUSE]);
  return (
    <article className={css.item} aria-label={`Ballot #${b.number}`}>
      <p className={css.text}>
        Ballot #{b.number}, open until {when(b.closes_at)} · {b.yes} yes, {b.no} no of {b.members}
      </p>
      <ol className={css.list}>
        {b.bundle.map((item, i) => (
          <li key={i} className={css.text}>
            {itemText(item)}
          </li>
        ))}
      </ol>
      <p className={css.meta}>{b.note}</p>
      {(b.votes ?? []).length > 0 && <p className={css.meta}>Voted: {(b.votes ?? []).map((v) => `${v.name} ${v.vote}`).join(' · ')}</p>}
      <TextArea label="Words with your vote (optional)" value={words} onChange={(e) => setWords(e.target.value)} />
      <div className={css.row}>
        <button type="button" className={css.secondary} disabled={act.busy} onClick={() => vote('yes')}>
          Yes
        </button>
        <button type="button" className={css.secondary} disabled={act.busy} onClick={() => vote('no')}>
          No
        </button>
      </div>
      <Said said={act.said} />
    </article>
  );
}

type Draft = { kind: 'rule'; rule: string } | { kind: 'setting'; setting: string; value: string };

function value(v: string): string | number | boolean {
  if (v === 'true') return true;
  if (v === 'false') return false;
  return /^-?\d+$/.test(v) ? Number(v) : v;
}

/** A change, proposed as a ballot on a new thread: its bundle fixed once it opens. */
function Propose() {
  const [title, setTitle] = useState('');
  const [why, setWhy] = useState('');
  const [items, setItems] = useState<Draft[]>([{ kind: 'rule', rule: '' }]);
  const [days, setDays] = useState('7');
  const [note, setNote] = useState('');
  const act = useAct();
  const bundle: BallotItem[] = items
    .map((d): BallotItem | null => (d.kind === 'rule' ? (d.rule.trim() ? { rule: d.rule.trim() } : null) : d.setting.trim() ? { setting: d.setting.trim(), value: value(d.value.trim()) } : null))
    .filter((x): x is BallotItem => x !== null);
  const set = (i: number, d: Draft) => setItems(items.map((x, j) => (j === i ? d : x)));
  return (
    <Card title="Propose a change">
      <p className={css.text}>A change goes to a ballot on its own thread. What it holds is fixed once it opens; a majority of the members carries the whole of it.</p>
      <form
        aria-label="Propose a change"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(
            () =>
              api.householdPost({ title: title.trim(), content: why.trim(), ballot: { bundle, term_days: Number(days), note: note.trim() } }).then(() => {
                setTitle('');
                setWhy('');
                setItems([{ kind: 'rule', rule: '' }]);
                setNote('');
                return 'The ballot is open.';
              }),
            [...HOUSE],
          );
        }}
      >
        <Field label="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
        <TextArea label="Why" value={why} onChange={(e) => setWhy(e.target.value)} />
        {items.map((d, i) =>
          d.kind === 'rule' ? (
            <Field key={i} label={`Rule ${i + 1}`} value={d.rule} onChange={(e) => set(i, { kind: 'rule', rule: e.target.value })} />
          ) : (
            <div key={i} className={css.row}>
              <Field label={`Setting ${i + 1}`} value={d.setting} placeholder="witnesses_post" onChange={(e) => set(i, { ...d, setting: e.target.value })} />
              <Field label="Value" value={d.value} onChange={(e) => set(i, { ...d, value: e.target.value })} />
            </div>
          ),
        )}
        <div className={css.row}>
          <button type="button" className={css.quiet} onClick={() => setItems([...items, { kind: 'rule', rule: '' }])}>
            + A rule
          </button>
          <button type="button" className={css.quiet} onClick={() => setItems([...items, { kind: 'setting', setting: '', value: '' }])}>
            + A setting
          </button>
        </div>
        <Field label="Open for days" type="number" min={1} value={days} onChange={(e) => setDays(e.target.value)} />
        <Field label="A note for the record" value={note} onChange={(e) => setNote(e.target.value)} />
        <div className={css.row}>
          <button type="submit" className={css.primary} disabled={act.busy || !title.trim() || bundle.length === 0 || !note.trim() || !(Number(days) >= 1)}>
            Open the ballot
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

/** No version yet: the founding witness proposes version 1, prose alone. */
function Found() {
  const [prose, setProse] = useState('');
  const [note, setNote] = useState('');
  const act = useAct();
  return (
    <Card title="Found the charter" witness>
      <p className={css.text}>The house has no charter yet. Version 1 is prose alone; rules and settings come after, by ballot.</p>
      <TextArea label="The charter" value={prose} onChange={(e) => setProse(e.target.value)} />
      <Field label="A note for the record" value={note} onChange={(e) => setNote(e.target.value)} />
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={act.busy || !prose.trim() || !note.trim()} onClick={() => void act.run(() => api.householdProposeCharter(prose.trim(), note.trim()).then(() => 'Founded.'), [...HOUSE])}>
          Propose version 1
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}

function Versions({ versions }: { versions: HouseVersion[] }) {
  return (
    <Card title="Every version">
      <ul className={css.list} aria-label="Versions">
        {[...versions].reverse().map((v) => (
          <li key={v.version} className={css.item}>
            <span className={css.text}>Version {v.version}</span>
            <span className={css.meta}>
              {v.ballot ? `ballot #${v.ballot}` : 'founding'}
              {v.decided_at ? ` · ${when(v.decided_at)}` : ''}
              {v.bundle && v.bundle.length > 0 ? ` · ${v.bundle.map(itemText).join(' · ')}` : ''}
            </span>
          </li>
        ))}
      </ul>
    </Card>
  );
}
