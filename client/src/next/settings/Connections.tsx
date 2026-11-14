import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { Adapter, ReaderSites, ResearchQuestion } from '../../api/types';
import { useSubject } from '../state/resident';
import { Card, Confirm, Field, Said, TextArea } from './common';
import { ADAPTER, day, lines, NAME, ORIGIN, profileLine, settingsKey } from './logic';
import * as css from './settings.css';
import { useAct } from './useAct';

// The roles an adapter's token holds (spec §8, xenia#11), in words.
const ROLES: Array<{ id: string; words: (name: string) => string }> = [
  {
    id: 'brain',
    words: (n) => `speaks as ${n}, with ${n}'s memory (Claude Code)`,
  },
  {
    id: 'reader',
    words: (n) => `reads inboxes and sends approved replies, never as ${n}`,
  },
  { id: 'worker', words: (n) => `does work for ${n}, never as ${n}` },
];

/**
 * Profiles, keys and connections: your model key and GitHub token (the
 * witness's own, gaia#24), what holds a token for her (xenia#11), the
 * profiles routes read through (xenia#19), the reader's sites (xenia#16)
 * and the questions put to its research pass (seshat#38).
 */
export function Connections() {
  return (
    <>
      <ModelKey />
      <GithubToken />
      <OpsTokens />
      <Adapters />
      <Profiles />
      <Reader />
      <Research />
    </>
  );
}

function ModelKey() {
  const { id } = useSubject();
  const ledger = useQuery({
    queryKey: settingsKey(id, 'ledger'),
    queryFn: () => api.ledger(id),
  });
  const [key, setKey] = useState('');
  const act = useAct();
  const present = ledger.data?.key.present ?? false;
  return (
    <Card title="Your OpenRouter key">
      <p className={css.text}>{present ? `Stored since ${day(ledger.data?.key.stored_at)}.` : 'No key stored: nothing can be asked of a model until one is.'}</p>
      <form
        aria-label="Your OpenRouter key"
        className={css.row}
        onSubmit={(e) => {
          e.preventDefault();
          const k = key.trim();
          if (!k) return;
          setKey('');
          void act.run(() => api.storeKey(k).then(() => (present ? 'Rotated.' : 'Stored.')), ['me']);
        }}
      >
        <Field label={present ? 'Rotate the key' : 'Paste the key'} type="password" autoComplete="off" value={key} onChange={(e) => setKey(e.target.value)} />
        <button type="submit" className={css.primary} disabled={key.trim() === '' || act.busy}>
          {present ? 'Rotate' : 'Store'}
        </button>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

// The witness's GitHub read token (gaia#24, the witness, 2026-11-08):
// what her pull request reads send; set, rotated and revoked here.
function GithubToken() {
  const { name } = useSubject();
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const [token, setToken] = useState('');
  const act = useAct();
  const status = me.data?.github ?? { present: false, stored_at: null };
  return (
    <Card title="GitHub">
      <p className={css.text}>
        {status.present
          ? `A read token is stored since ${day(status.stored_at)}; ${name}'s pull request reads use it.`
          : `No token: ${name} reads pull requests anonymously, sixty requests an hour (about twenty pr_meta reads).`}
      </p>
      <p className={css.note}>A fine-grained token with read-only access to the repository is enough. It is stored encrypted and never shown again.</p>
      <form
        aria-label="GitHub token"
        className={css.row}
        onSubmit={(e) => {
          e.preventDefault();
          const t = token.trim();
          if (!t) return;
          setToken('');
          void act.run(() => api.storeGithubToken(t).then(() => (status.present ? 'Replaced.' : 'Stored.')), ['me']);
        }}
      >
        <Field label={status.present ? 'Replace the token' : 'Paste a token'} type="password" autoComplete="off" value={token} onChange={(e) => setToken(e.target.value)} />
        <button type="submit" className={css.primary} disabled={token.trim() === '' || act.busy}>
          {status.present ? 'Replace' : 'Store'}
        </button>
        {status.present && (
          <Confirm label="Revoke" confirm="Revoke the token" disabled={act.busy} onConfirm={() => void act.run(() => api.revokeGithubToken().then(() => 'Revoked.'), ['me'])} />
        )}
      </form>
      <Said said={act.said} />
    </Card>
  );
}

// An ops token (gaia#40, apsu#30; the witness, 2026-11-13): reads the
// platform's ops routes and nothing else, for the agent that helps run it.
// A super admin's alone; nobody else sees the card.
function OpsTokens() {
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const operator = (me.data?.roles ?? []).includes('super_admin');
  const tokens = useQuery({ queryKey: ['me', 'tokens'], queryFn: api.tokens, enabled: operator });
  const [label, setLabel] = useState('');
  const [issued, setIssued] = useState<{ label: string; token: string } | null>(null);
  const act = useAct();
  if (!operator) return null;
  const ops = (tokens.data ?? []).filter((t) => t.scope === 'ops' && !t.revoked_at);
  return (
    <>
      {issued && (
        <Card title={`The ops token “${issued.label}”`} witness>
          <p className={css.text}>Copy it now: it is shown this once. Give it to the agent as an environment variable; never paste it into a chat or a repository.</p>
          <code aria-label="Token" className={css.token}>
            {issued.token}
          </code>
          <div className={css.row}>
            <button type="button" className={css.secondary} onClick={() => void navigator.clipboard?.writeText(issued.token)}>
              Copy
            </button>
            <button type="button" className={css.quiet} onClick={() => setIssued(null)}>
              I've saved it
            </button>
          </div>
        </Card>
      )}
      <Card title="Ops tokens">
        <p className={css.note}>
          A token that reads the platform's ops routes (failures, heartbeats, the slowest calls and their summary) and nothing else: no resident, no words, no
          writes. For the agent that helps you run the platform.
        </p>
        <ul className={css.list} aria-label="Ops tokens">
          {ops.map((t) => (
            <li key={t.hash} className={css.item}>
              <span className={css.text}>
                {t.label} · since {day(t.issued_at)}
              </span>
              <Confirm label="Revoke" confirm={`Revoke ${t.label}`} disabled={act.busy} onConfirm={() => void act.run(() => api.revokeToken(t.hash).then(() => `Revoked ${t.label}.`), ['me', 'tokens'])} />
            </li>
          ))}
        </ul>
        <form
          aria-label="New ops token"
          className={css.row}
          onSubmit={(e) => {
            e.preventDefault();
            const l = label.trim();
            if (!l) return;
            void act.run(
              () =>
                api.issueToken(l, 'ops').then((r) => {
                  setIssued({ label: r.label, token: r.token });
                  setLabel('');
                  return `Made ${r.label}.`;
                }),
              ['me', 'tokens'],
            );
          }}
        >
          <Field label="Label (who holds it)" value={label} onChange={(e) => setLabel(e.target.value)} />
          <button type="submit" className={css.primary} disabled={label.trim() === '' || act.busy}>
            Make a token
          </button>
        </form>
        <Said said={act.said} />
      </Card>
    </>
  );
}

function Adapters() {
  const { id, name } = useSubject();
  const adapters = useQuery({
    queryKey: settingsKey(id, 'adapters'),
    queryFn: () => api.adapters(id),
  });
  const [issued, setIssued] = useState<{
    adapter: string;
    token: string;
  } | null>(null);
  const [adapter, setAdapter] = useState('');
  const [role, setRole] = useState('reader');
  const act = useAct();
  const live = (adapters.data ?? []).filter((a) => !a.revoked_at);
  const gone = (adapters.data ?? []).filter((a) => a.revoked_at);
  const valid = ADAPTER.test(adapter);

  return (
    <>
      {issued && (
        <Card title={`The token for ${issued.adapter}`} witness>
          <p className={css.text}>Copy it now: it is shown this once. Keep it where the runtime reads it (a file only you can read), never in a repository or a chat.</p>
          <code aria-label="Token" className={css.token}>
            {issued.token}
          </code>
          <div className={css.row}>
            <button type="button" className={css.secondary} onClick={() => void navigator.clipboard?.writeText(issued.token)}>
              Copy
            </button>
            <button type="button" className={css.quiet} onClick={() => setIssued(null)}>
              I've saved it
            </button>
          </div>
        </Card>
      )}
      <Card title="Connected">
        <p className={css.note}>The runtimes and hands that hold a token for {name}. Registering a name again replaces its token; revoking stops it at once.</p>
        {adapters.isPending && <p className={css.note}>Reading…</p>}
        {adapters.data && live.length === 0 && <p className={css.note}>Nothing holds a token yet.</p>}
        <ul className={css.list} aria-label="Connected">
          {live.map((a) => (
            <AdapterRow key={a.adapter} adapter={a} name={name} onRevoke={() => void act.run(() => api.revokeAdapter(id, a.adapter).then(() => `Revoked ${a.adapter}.`))} />
          ))}
        </ul>
        <form
          aria-label="Connect something new"
          className={css.column}
          onSubmit={(e) => {
            e.preventDefault();
            if (!valid) return;
            const which = adapter;
            setAdapter('');
            void act.run(() =>
              api.registerAdapter(id, which, role).then((r) => {
                setIssued({ adapter: r.adapter, token: r.token });
              }),
            );
          }}
        >
          <h3 className={css.subheading}>Connect something new</h3>
          <Field label="Name (lowercase, e.g. scrape)" value={adapter} onChange={(e) => setAdapter(e.target.value.toLowerCase())} />
          <fieldset className={css.column} style={{ border: 'none', margin: 0, padding: 0 }}>
            <legend className={css.note}>Role</legend>
            {ROLES.map((r) => (
              <label key={r.id} className={css.check}>
                <input type="radio" name="adapter-role" value={r.id} checked={role === r.id} onChange={() => setRole(r.id)} />
                <span>
                  <strong>{r.id}</strong> <span className={css.note}>{r.words(name)}</span>
                </span>
              </label>
            ))}
          </fieldset>
          <div>
            <button type="submit" className={css.primary} disabled={!valid || act.busy}>
              Issue a token
            </button>
          </div>
        </form>
        <Said said={act.said} />
      </Card>
      {gone.length > 0 && (
        <Card title="Revoked">
          {gone.map((a) => (
            <p key={a.adapter} className={css.note}>
              {a.adapter} ({a.role}) · revoked {day(a.revoked_at)}
            </p>
          ))}
        </Card>
      )}
    </>
  );
}

function AdapterRow({ adapter: a, name, onRevoke }: { adapter: Adapter; name: string; onRevoke: () => void }) {
  const words = ROLES.find((r) => r.id === a.role)?.words(name) ?? a.role;
  return (
    <li className={css.line}>
      <span>
        <strong>{a.adapter}</strong>{' '}
        <span className={css.note}>
          · {a.role}: {words} · since {day(a.registered_at)}
        </span>
      </span>
      <Confirm label="Revoke" confirm={`Revoke ${a.adapter}`} onConfirm={onRevoke} />
    </li>
  );
}

function Profiles() {
  const { id, name } = useSubject();
  const routes = useQuery({
    queryKey: settingsKey(id, 'routes'),
    queryFn: () => api.routes(id),
  });
  const [note, setNote] = useState('');
  const [key, setKey] = useState('');
  const [origin, setOrigin] = useState('');
  const [as, setAs] = useState('');
  const act = useAct();
  const profiles = routes.data?.profiles ?? [];
  const noted = note.trim() !== '' && !act.busy;
  const ok = NAME.test(key) && ORIGIN.test(origin) && !profiles.some((p) => p.seeded && p.key === key);
  const run = (work: () => Promise<string>) => void act.run(work, ['resident', id, 'records']);

  return (
    <Card title="Profiles">
      <p className={css.note}>
        A profile is a browser signed in on one site, on the reader's machine; nothing here holds its password. Every route into or out of {name}'s house reads through one.
      </p>
      <Field label="A note for a revoke or restore" value={note} onChange={(e) => setNote(e.target.value)} />
      <ul className={css.list} aria-label="Profiles">
        {profiles.map((p) => (
          <li key={p.key} className={css.item}>
            <span className={css.text}>
              <strong>{p.label}</strong> <span className={css.meta}>({p.key})</span>
              {p.revoked ? ' · revoked' : ''}
            </span>
            <span className={css.note}>{profileLine(p)}</span>
            <span className={css.note}>{p.routes.length > 0 ? `Routes: ${p.routes.join(', ')}` : 'No route uses it.'}</span>
            <div>
              {p.revoked ? (
                <button
                  type="button"
                  className={css.quiet}
                  disabled={!noted}
                  onClick={() => run(() => api.restoreProfile(id, p.key, note.trim()).then(() => `Restored ${p.key}.`))}
                >
                  Restore
                </button>
              ) : (
                <button
                  type="button"
                  className={css.quiet}
                  disabled={!noted}
                  onClick={() => run(() => api.revokeProfile(id, p.key, note.trim()).then(() => `Revoked ${p.key}; its routes are unable until you restore it.`))}
                >
                  Revoke
                </button>
              )}
            </div>
          </li>
        ))}
      </ul>
      <form
        aria-label="Make a profile"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          if (!ok || act.busy) return;
          const profile = {
            key,
            origin,
            signed_in_as: as.trim() || undefined,
            note: note.trim() || undefined,
          };
          run(() => api.setProfile(id, profile).then(() => `Made ${profile.key}. Sign it in on the reader's machine: reader.sh login ${profile.key}.`));
          setKey('');
          setOrigin('');
          setAs('');
        }}
      >
        <h3 className={css.subheading}>Make a profile</h3>
        <p className={css.note}>A profile reaches exactly one site. Sign it in on the reader's machine with reader.sh login and its name.</p>
        <Field label="Profile name" value={key} onChange={(e) => setKey(e.target.value.trim())} />
        <Field label="Its one site (https://host)" value={origin} onChange={(e) => setOrigin(e.target.value.trim())} />
        <Field label="Signed in as" value={as} onChange={(e) => setAs(e.target.value)} />
        <div>
          <button type="submit" className={css.primary} disabled={!ok || act.busy}>
            Make the profile
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

function Reader() {
  const { id } = useSubject();
  const reader = useQuery({
    queryKey: settingsKey(id, 'reader'),
    queryFn: () => api.reader(id),
  });
  // A fresh form per save (keyed by `set_at`), so it starts again from
  // what the server kept; a refused save keeps the draft.
  return reader.data ? <ReaderForm key={reader.data.set_at ?? 'unset'} reader={reader.data} /> : null;
}

function ReaderForm({ reader }: { reader: ReaderSites }) {
  const { id } = useSubject();
  const [scrape, setScrape] = useState(reader.scrape.join('\n'));
  const [research, setResearch] = useState(reader.research.join('\n'));
  const act = useAct();
  return (
    <Card title="The reader's sites">
      <p className={css.note}>
        Where the reader's browser may go, one origin a line, like https://example.org (no path). {reader.set_at ? `Set ${day(reader.set_at)}.` : 'Never set.'}
      </p>
      <form
        aria-label="The reader's sites"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(() => api.setReader(id, lines(scrape), lines(research)).then(() => 'Saved.'));
        }}
      >
        <TextArea
          mono
          rows={4}
          spellCheck={false}
          label="Reading correspondence: the sites it may open while reading correspondence. * means any site."
          value={scrape}
          onChange={(e) => setScrape(e.target.value)}
        />
        <TextArea
          mono
          rows={4}
          spellCheck={false}
          label="Research: the sites it may open while researching a question. * means any site; an empty list means the reader can't research at all."
          value={research}
          onChange={(e) => setResearch(e.target.value)}
        />
        <div>
          <button type="submit" className={css.primary} disabled={act.busy}>
            Save
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

function Research() {
  const { id, name } = useSubject();
  const research = useQuery({
    queryKey: settingsKey(id, 'research'),
    queryFn: () => api.research(id),
  });
  const [question, setQuestion] = useState('');
  const [urls, setUrls] = useState('');
  const act = useAct();
  const rows: ResearchQuestion[] = research.data ?? [];
  return (
    <Card title="Research">
      {research.data && rows.length === 0 && <p className={css.note}>No question asked yet.</p>}
      <ul className={css.list} aria-label="Research questions">
        {rows.map((r) => (
          <li key={r.number} className={css.item}>
            <span className={css.text}>
              <span className={css.meta}>#{r.number}</span> {r.question}
            </span>
            <span className={r.status === 'failed' ? `${css.note} ${css.warn}` : css.note}>
              {r.status}
              {r.asked_by === 'resident' ? ` · asked by ${name}` : ''} · {day(r.asked_at)}
              {r.status === 'answered' && r.path ? (
                <>
                  {' · in Records at '}
                  <a className={css.link} href={`#/records/doc/${r.path}/task.md`}>
                    {r.path}/task.md
                  </a>
                </>
              ) : null}
              {r.status === 'failed' && r.reason ? ` · ${r.reason}` : ''}
            </span>
          </li>
        ))}
      </ul>
      <form
        aria-label="Ask a question"
        className={css.column}
        onSubmit={(e) => {
          e.preventDefault();
          if (question.trim() === '') return;
          const q = question.trim();
          const u = lines(urls);
          setQuestion('');
          setUrls('');
          void act.run(() => api.askResearch(id, q, u).then((r) => `Asked as #${r.number}.`));
        }}
      >
        <Field label="Question" value={question} onChange={(e) => setQuestion(e.target.value)} />
        <TextArea mono rows={2} spellCheck={false} label="Pages to start from (optional, one a line)" value={urls} onChange={(e) => setUrls(e.target.value)} />
        <div>
          <button type="submit" className={css.primary} disabled={question.trim() === '' || act.busy}>
            Ask
          </button>
        </div>
      </form>
      <Said said={act.said} />
    </Card>
  );
}
