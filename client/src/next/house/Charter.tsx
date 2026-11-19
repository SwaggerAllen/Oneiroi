import { useQuery } from '@tanstack/react-query';
import { useRef, useState } from 'react';
import { api, type BallotItem, type HouseBallot, type HouseContract, type HouseSetting, type HouseVersion } from '../../api/client';
import { Card, Field, Said, Select, TextArea } from '../settings/common';
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
  // One ballot holds any number of changes (the witness, 2026-11-18:
  // "a ballot could contain any number of settings changes and rules"):
  // a setting picked from the list joins the ballot being drafted, never
  // replacing what is there.
  const [items, setItems] = useState<Draft[]>([]);
  const form = useRef<HTMLDivElement>(null);
  const catalog = c?.catalog ?? [];
  const propose = (setting: string) => {
    setItems((now) => (now.some((d) => d.kind === 'setting' && d.setting === setting) ? now : [...now.filter((d) => d.kind !== 'rule' || d.rule.trim() !== ''), { kind: 'setting', setting, value: '' }]));
    setTimeout(() => form.current?.scrollIntoView?.({ block: 'start' }), 0);
  };
  return (
    <HousePage label="Charter" title="Charter" lede="The house's rules and settings: the contract in force, who signed it, and the ballots that change it. Every member has one vote.">
      {contract.isError && <p className={css.note}>The charter could not be read.</p>}
      {c && !c.in_force && <Found catalog={catalog} />}
      <Name />
      {c?.in_force && <InForce v={c.in_force} />}
      {c?.in_force && catalog.length > 0 && <Settings v={c.in_force} catalog={catalog} drafted={items} onPropose={propose} />}
      {c && <Members c={c} accountId={me.data?.account_id ?? undefined} />}
      {c && <Ballots ballots={c.ballots} />}
      {c?.in_force && (
        <div ref={form}>
          <Propose catalog={catalog} items={items} setItems={setItems} current={c.in_force.settings ?? {}} />
        </div>
      )}
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
      <p className={css.note}>{settings.length === 0 ? 'Every setting at its default.' : `${settings.length === 1 ? '1 setting' : `${settings.length} settings`} changed from the default, listed under Settings.`}</p>
      <p className={css.meta}>
        {v.ballot ? `By ballot #${v.ballot}` : 'The founding version'}
        {v.decided_at ? ` · ${when(v.decided_at)}` : ''}
      </p>
    </Card>
  );
}

const shown = (v: unknown) => (v === null || v === undefined ? 'as many as fit' : String(v));

/**
 * Every setting a ballot can change (gaia#49; the witness, 2026-11-18:
 * "I don't see a way to propose settings changes"): what it does, its
 * value in force or its default, and Add to the ballot, which puts it in
 * the one ballot being drafted below, beside whatever is there.
 */
function Settings({ v, catalog, drafted, onPropose }: { v: HouseVersion; catalog: HouseSetting[]; drafted: Draft[]; onPropose: (key: string) => void }) {
  const set = v.settings ?? {};
  const inBallot = (key: string) => drafted.some((d) => d.kind === 'setting' && d.setting === key);
  return (
    <Card title="Settings">
      <p className={css.note}>What the house runs on. Changes go by ballot, as many as you like in one: every member votes once on the whole, and a majority carries it.</p>
      <ul className={css.list} aria-label="Settings">
        {catalog.map((k) => {
          const changed = k.key in set;
          return (
            <li key={k.key} className={css.item}>
              <div className={css.row}>
                <span className={css.text}>
                  <strong>{k.label}</strong>: {shown(changed ? set[k.key] : k.default)}
                  <span className={css.meta}>{changed ? ' · by ballot' : ' · the default'}</span>
                </span>
                <button type="button" className={css.quiet} disabled={inBallot(k.key)} onClick={() => onPropose(k.key)}>
                  {inBallot(k.key) ? 'In the ballot' : 'Add to the ballot'}
                </button>
              </div>
              <p className={css.note}>{k.about}</p>
            </li>
          );
        })}
      </ul>
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
      <p className={css.meta}>If every member votes yes, it carries at once.</p>
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

/** A setting's value control, as its catalog entry says it takes (gaia#49). */
function ValueInput({ entry, value: v, onChange }: { entry: HouseSetting | undefined; value: string; onChange: (v: string) => void }) {
  if (entry?.type === 'boolean' || entry?.type === 'choice' || (entry?.options?.length ?? 0) > 0) {
    const options = entry?.type === 'boolean' ? ['true', 'false'] : [...(entry?.type === 'integer' && entry.min !== undefined && entry.max !== undefined ? Array.from({ length: entry.max - entry.min + 1 }, (_, n) => String((entry.min as number) + n)) : []), ...(entry?.options ?? [])];
    return (
      <Select label="Value" value={v} onChange={onChange}>
        <option value="">Choose…</option>
        {options.map((o) => (
          <option key={o} value={o}>
            {entry?.type === 'boolean' ? (o === 'true' ? 'yes' : 'no') : o}
          </option>
        ))}
      </Select>
    );
  }
  if (entry?.type === 'integer') return <Field label={`Value (${entry.min} to ${entry.max})`} type="number" min={entry.min} max={entry.max} value={v} onChange={(e) => onChange(e.target.value)} />;
  return <Field label="Value" value={v} onChange={(e) => onChange(e.target.value)} />;
}

/** The ballot's items (or a founding version's), as a bundle: rules, and settings with a value. */
function toBundle(items: Draft[]): BallotItem[] {
  return items
    .map((d): BallotItem | null =>
      d.kind === 'rule' ? (d.rule.trim() ? { rule: d.rule.trim() } : null) : d.setting.trim() && d.value.trim() ? { setting: d.setting.trim(), value: value(d.value.trim()) } : null,
    )
    .filter((x): x is BallotItem => x !== null);
}

/**
 * Rules and settings, the settings picked from the catalog (gaia#49):
 * the ballot form's, and the founding version's (gaia#50).
 */
function BundleEditor({ items, setItems, catalog, current }: { items: Draft[]; setItems: (d: Draft[]) => void; catalog: HouseSetting[]; current: Record<string, unknown> }) {
  const entry = (key: string) => catalog.find((k) => k.key === key);
  const set = (i: number, d: Draft) => setItems(items.map((x, j) => (j === i ? d : x)));
  return (
    <>
      {items.map((d, i) =>
        d.kind === 'rule' ? (
          <div key={i} className={css.column}>
            <Field label={`Rule ${i + 1}`} value={d.rule} onChange={(e) => set(i, { kind: 'rule', rule: e.target.value })} />
            <Remove onClick={() => setItems(items.filter((_, j) => j !== i))} what={`rule ${i + 1}`} />
          </div>
        ) : (
          <div key={i} className={css.column}>
            <div className={css.row}>
              <Select label={`Setting ${i + 1}`} value={d.setting} onChange={(v) => set(i, { ...d, setting: v, value: '' })}>
                <option value="">Choose a setting…</option>
                {catalog.map((k) => (
                  <option key={k.key} value={k.key}>
                    {k.label}
                  </option>
                ))}
              </Select>
              <ValueInput entry={entry(d.setting)} value={d.value} onChange={(v) => set(i, { ...d, value: v })} />
            </div>
            {entry(d.setting) && (
              <p className={css.note}>
                {entry(d.setting)?.about} Now: {shown(d.setting in current ? current[d.setting] : entry(d.setting)?.default)}.
              </p>
            )}
            <Remove onClick={() => setItems(items.filter((_, j) => j !== i))} what={`setting ${i + 1}`} />
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
    </>
  );
}

function Remove({ onClick, what }: { onClick: () => void; what: string }) {
  return (
    <button type="button" className={css.quiet} style={{ alignSelf: 'flex-start' }} aria-label={`Remove ${what}`} onClick={onClick}>
      Remove
    </button>
  );
}

/**
 * Changes, proposed as one ballot on a new thread: any number of rules
 * and settings, its bundle fixed once it opens. A ballot every member
 * carries closes at once (gaia#54).
 */
function Propose({ catalog, items, setItems, current }: { catalog: HouseSetting[]; items: Draft[]; setItems: (d: Draft[]) => void; current: Record<string, unknown> }) {
  const [title, setTitle] = useState('');
  const [why, setWhy] = useState('');
  const labels = items.flatMap((d) => (d.kind === 'setting' && d.setting ? [catalog.find((k) => k.key === d.setting)?.label ?? d.setting] : []));
  const suggested = labels.length > 0 ? `Change: ${labels.join(', ')}` : '';
  const [days, setDays] = useState('7');
  const [note, setNote] = useState('');
  const act = useAct();
  const bundle = toBundle(items);
  return (
    <Card title="Propose changes">
      <p className={css.text}>
        One ballot, on its own thread, holds every change you add here, rules and settings together. What it holds is fixed once it opens; a majority of the members carries the whole of it at the end of its term, and if every member votes yes it carries at once, the rest of the term waived.
      </p>
      <form
        aria-label="Propose a change"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(
            () =>
              api.householdPost({ title: (title.trim() || suggested).trim(), content: why.trim(), ballot: { bundle, term_days: Number(days), note: note.trim() } }).then(() => {
                setTitle('');
                setWhy('');
                setItems([]);
                setNote('');
                return 'The ballot is open.';
              }),
            [...HOUSE],
          );
        }}
      >
        <Field label="Title" value={title} placeholder={suggested || undefined} onChange={(e) => setTitle(e.target.value)} />
        <TextArea label="Why" value={why} onChange={(e) => setWhy(e.target.value)} />
        <BundleEditor items={items} setItems={setItems} catalog={catalog} current={current} />
        <Field label="Open for days" type="number" min={1} value={days} onChange={(e) => setDays(e.target.value)} />
        <Field label="A note for the record" value={note} onChange={(e) => setNote(e.target.value)} />
        <div className={css.row}>
          <button type="submit" className={css.primary} disabled={act.busy || !(title.trim() || suggested) || bundle.length === 0 || !note.trim() || !(Number(days) >= 1)}>
            {bundle.length > 1 ? `Open the ballot (${bundle.length} changes)` : 'Open the ballot'}
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

/**
 * The house's name for citations (gaia#44): a witness sets it once, and
 * every citation of its threads names it (`house/<name>:thread/<id>`), so
 * it never changes. Until then nothing in the house can be cited.
 */
function Name() {
  // Its own key: the Threads tab pages the shelf under SHELF.
  const shelf = useQuery({ queryKey: [...HOUSE, 'name'], queryFn: () => api.householdShelf(0) });
  const [slug, setSlug] = useState('');
  const act = useAct();
  const named = shelf.data?.slug;
  if (shelf.isPending || shelf.isError) return null;
  const valid = /^[a-z][a-z0-9-]{1,39}$/.test(slug);
  return (
    <Card title="The house's name" witness={!named}>
      {named ? (
        <p className={css.text}>
          Its threads are cited as <code>house/{named}:thread/…</code>. The name is set once and never changes, so every citation of the house keeps working.
        </p>
      ) : (
        <>
          <p className={css.text}>
            Name the house so its threads and documents can be cited from memory, as <code>house/&lt;name&gt;:thread/…</code>. It is set once and never changes; choose
            one you will keep.
          </p>
          <Field label="Name (lowercase letters, digits and hyphens)" value={slug} onChange={(e) => setSlug(e.target.value.toLowerCase())} />
          <div className={css.row}>
            <button type="button" className={css.primary} disabled={act.busy || !valid} onClick={() => void act.run(() => api.nameHousehold(slug).then(() => `Named ${slug}.`), [...HOUSE])}>
              Name the house
            </button>
          </div>
        </>
      )}
      <Said said={act.said} />
    </Card>
  );
}

/** No version yet: the founding witness proposes version 1, prose alone. */
/**
 * Version 1 of the charter (gaia#27), with its own rules and settings
 * (gaia#50; the witness, 2026-11-18: "settings available for the initial
 * charter proposal, not just text"), in force at once; later changes go
 * by ballot.
 */
function Found({ catalog }: { catalog: HouseSetting[] }) {
  const [prose, setProse] = useState('');
  const [note, setNote] = useState('');
  const [items, setItems] = useState<Draft[]>([]);
  const act = useAct();
  return (
    <Card title="Found the charter" witness>
      <p className={css.text}>The house has no charter yet. Version 1 is its prose, and any rules and settings it starts with; it is in force once proposed, and changes after go by ballot.</p>
      <TextArea label="The charter" value={prose} onChange={(e) => setProse(e.target.value)} />
      <BundleEditor items={items} setItems={setItems} catalog={catalog} current={{}} />
      <Field label="A note for the record" value={note} onChange={(e) => setNote(e.target.value)} />
      <div className={css.row}>
        <button
          type="button"
          className={css.primary}
          disabled={act.busy || !prose.trim() || !note.trim()}
          onClick={() => void act.run(() => api.householdProposeCharter(prose.trim(), note.trim(), toBundle(items)).then(() => 'Founded.'), [...HOUSE])}
        >
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
