import { useState } from 'react';
import type { Adapter, ApiError, ReaderSites, ResearchQuestion } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { ErrorNotice } from '../../components/ErrorNotice';
import { Field } from '../../components/Field';
import { TopBar } from '../../components/TopBar';

export interface ConnectionsProps {
  residentName: string;
  adapters: Adapter[];
  // The token just issued, shown once and never again.
  issued?: { adapter: string; token: string } | null;
  onRegister?: (adapter: string, role: string) => void;
  onRevoke?: (adapter: string) => void;
  onDismissToken?: () => void;
  // The reader's two allowlists (xenia #16), and what the server said
  // when a save was refused (an entry not an origin, a list too long).
  reader?: ReaderSites | null;
  readerError?: ApiError | null;
  onSaveReader?: (scrape: string[], research: string[]) => void;
  // The questions put to the reader's research pass (seshat #38), newest first.
  research?: ResearchQuestion[] | null;
  onAsk?: (question: string, urls: string[]) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const area = { padding: 'var(--space-2) var(--space-3)', borderRadius: 'var(--radius-md)', border: '1px solid var(--hairline)', background: 'var(--surface-raised)', color: 'var(--ink)', fontFamily: 'var(--font-mono)', fontSize: 14 } as const;
const row = { display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' } as const;

// The roles an adapter's token holds (spec §8, xenia #11), in words.
const roles: Array<{ id: string; words: (name: string) => string }> = [
  { id: 'brain', words: (n) => `speaks as ${n}, with ${n}'s memory (Claude Code)` },
  { id: 'reader', words: (n) => `reads inboxes and sends approved replies, never as ${n}` },
  { id: 'worker', words: (n) => `does work for ${n}, never as ${n}` },
];

// Connections (spec §10's "agreement and custody", the adapters part):
// the runtimes and hands that hold a token for the resident. A token is
// shown once, when it is issued; registering a name again replaces its
// token; revoking stops it at once.
export function Connections({
  residentName,
  adapters,
  issued = null,
  onRegister,
  onRevoke,
  onDismissToken,
  reader = null,
  readerError = null,
  onSaveReader,
  research = null,
  onAsk,
}: ConnectionsProps) {
  const [name, setName] = useState('');
  const [role, setRole] = useState('reader');
  const live = adapters.filter((a) => !a.revoked_at);
  const gone = adapters.filter((a) => a.revoked_at);
  const valid = /^[a-z0-9][a-z0-9_-]{0,31}$/.test(name);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Connections" line={`What holds a token for ${residentName}`} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        {issued ? (
          <Card title={`The token for ${issued.adapter}`}>
            <p style={{ margin: 0, fontSize: 15 }}>
              Copy it now: it is shown this once. Keep it where the runtime reads it (a file only you can read), never in a repository or a chat.
            </p>
            <code
              aria-label="Token"
              style={{ display: 'block', padding: 'var(--space-2)', background: 'var(--surface-sunken)', borderRadius: 'var(--radius-sm)', fontFamily: 'var(--font-mono)', fontSize: 13, overflowWrap: 'anywhere' }}
            >
              {issued.token}
            </code>
            <div style={row}>
              <Button onClick={() => void navigator.clipboard?.writeText(issued.token)}>Copy</Button>
              {onDismissToken ? (
                <Button variant="quiet" onClick={onDismissToken}>
                  I've saved it
                </Button>
              ) : null}
            </div>
          </Card>
        ) : null}
        <Card title="Connected">
          {live.length === 0 ? (
            <p style={muted}>Nothing holds a token yet.</p>
          ) : (
            <ul aria-label="Connected" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {live.map((a) => (
                <AdapterRow key={a.adapter} residentName={residentName} adapter={a} onRevoke={onRevoke} />
              ))}
            </ul>
          )}
        </Card>
        {onRegister ? (
          <Card title="Connect something new">
            <form
              aria-label="Connect something new"
              onSubmit={(e) => {
                e.preventDefault();
                if (valid) onRegister(name, role);
                setName('');
              }}
              style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
            >
              <Field label="Name (lowercase, e.g. scrape)" value={name} onChange={(e) => setName(e.target.value.toLowerCase())} />
              <fieldset style={{ border: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
                <legend style={{ fontSize: 13, color: 'var(--ink-muted)', fontWeight: 500 }}>Role</legend>
                {roles.map((r) => (
                  <label key={r.id} style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 15 }}>
                    <input type="radio" name="role" value={r.id} checked={role === r.id} onChange={() => setRole(r.id)} />
                    <span>
                      <strong style={{ fontWeight: 600 }}>{r.id}</strong> <span style={{ color: 'var(--ink-muted)' }}>{r.words(residentName)}</span>
                    </span>
                  </label>
                ))}
              </fieldset>
              <div>
                <Button variant="primary" type="submit" disabled={!valid}>
                  Issue a token
                </Button>
              </div>
            </form>
          </Card>
        ) : null}
        {reader ? <ReaderCard key={reader.set_at ?? 'unset'} reader={reader} error={readerError} onSave={onSaveReader} /> : null}
        {research ? <ResearchCard residentName={residentName} research={research} onAsk={onAsk} /> : null}
        {gone.length > 0 ? (
          <Card title="Revoked">
            <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 14, color: 'var(--ink-muted)' }}>
              {gone.map((a) => (
                <li key={a.adapter}>
                  {a.adapter} ({a.role}) · revoked {a.revoked_at?.slice(0, 10)}
                </li>
              ))}
            </ul>
          </Card>
        ) : null}
      </main>
    </div>
  );
}

function AdapterRow({ residentName, adapter: a, onRevoke }: { residentName: string; adapter: Adapter; onRevoke?: (adapter: string) => void }) {
  const [confirming, setConfirming] = useState(false);
  const words = roles.find((r) => r.id === a.role)?.words(residentName) ?? a.role;
  return (
    <li style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 'var(--space-2)', fontSize: 15 }}>
      <span>
        <strong style={{ fontWeight: 600 }}>{a.adapter}</strong> <span style={{ color: 'var(--ink-muted)' }}>· {a.role}: {words} · since {a.registered_at.slice(0, 10)}</span>
      </span>
      {onRevoke ? (
        <Button variant="quiet" onClick={() => (confirming ? onRevoke(a.adapter) : setConfirming(true))} onBlur={() => setConfirming(false)}>
          {confirming ? `Revoke ${a.adapter}` : 'Revoke'}
        </Button>
      ) : null}
    </li>
  );
}

// One entry a line, blanks and surrounding space dropped.
const lines = (text: string) =>
  text
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '');

// The reader's two allowlists (xenia #16), edited one origin a line and
// saved together. A fresh card per save (keyed by `set_at`), so it
// starts again from what the server kept; a refused save keeps the draft.
function ReaderCard({ reader, error, onSave }: { reader: ReaderSites; error: ApiError | null; onSave?: (scrape: string[], research: string[]) => void }) {
  const [scrape, setScrape] = useState(reader.scrape.join('\n'));
  const [research, setResearch] = useState(reader.research.join('\n'));
  return (
    <Card title="Reader">
      <p style={muted}>
        Where the reader's browser may go, one origin a line, like https://example.org (no path). {reader.set_at ? `Set ${reader.set_at.slice(0, 10)}.` : 'Never set.'}
      </p>
      <form
        aria-label="Reader"
        onSubmit={(e) => {
          e.preventDefault();
          onSave?.(lines(scrape), lines(research));
        }}
        style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}
      >
        <SiteList label="Reading correspondence" value={scrape} onChange={setScrape} disabled={!onSave}>
          The sites it may open while reading correspondence. * means any site.
        </SiteList>
        <SiteList label="Research" value={research} onChange={setResearch} disabled={!onSave}>
          The sites it may open while researching a question. * means any site; an empty list means the reader can't research at all.
        </SiteList>
        {error ? <ErrorNotice error={error} /> : null}
        {onSave ? (
          <div>
            <Button variant="primary" type="submit">
              Save
            </Button>
          </div>
        ) : null}
      </form>
    </Card>
  );
}

function SiteList({ label, value, onChange, disabled, children }: { label: string; value: string; onChange: (v: string) => void; disabled: boolean; children: string }) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
      <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>{label}</span>
      <textarea value={value} onChange={(e) => onChange(e.target.value)} rows={4} disabled={disabled} spellCheck={false} style={area} />
      <span style={{ color: 'var(--ink-muted)' }}>{children}</span>
    </label>
  );
}

// The research questions (seshat #38): what was asked and how it
// settled; an answered one's notes are in the Library at the path shown.
function ResearchCard({ residentName, research, onAsk }: { residentName: string; research: ResearchQuestion[]; onAsk?: (question: string, urls: string[]) => void }) {
  const [question, setQuestion] = useState('');
  const [urls, setUrls] = useState('');
  return (
    <Card title="Research">
      {research.length === 0 ? (
        <p style={muted}>No question asked yet.</p>
      ) : (
        <ul aria-label="Research questions" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
          {research.map((r) => (
            <li key={r.number} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
              <span>
                <span style={{ color: 'var(--ink-muted)' }}>#{r.number}</span> {r.question}
              </span>
              <span style={{ fontSize: 13, color: r.status === 'failed' ? 'var(--danger)' : 'var(--ink-muted)' }}>
                {r.status}
                {r.asked_by === 'resident' ? ` · asked by ${residentName}` : ''} · {r.asked_at.slice(0, 10)}
                {r.status === 'answered' && r.path ? (
                  <>
                    {' · in the Library at '}
                    <code style={{ fontFamily: 'var(--font-mono)', fontSize: 12 }}>{r.path}/task.md</code>
                  </>
                ) : null}
                {r.status === 'failed' && r.reason ? ` · ${r.reason}` : ''}
              </span>
            </li>
          ))}
        </ul>
      )}
      {onAsk ? (
        <form
          aria-label="Ask a question"
          onSubmit={(e) => {
            e.preventDefault();
            if (question.trim() === '') return;
            onAsk(question.trim(), lines(urls));
            setQuestion('');
            setUrls('');
          }}
          style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
        >
          <Field label="Question" value={question} onChange={(e) => setQuestion(e.target.value)} />
          <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
            <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Pages to start from (optional, one a line)</span>
            <textarea value={urls} onChange={(e) => setUrls(e.target.value)} rows={2} spellCheck={false} style={area} />
          </label>
          <div>
            <Button variant="primary" type="submit" disabled={question.trim() === ''}>
              Ask
            </Button>
          </div>
        </form>
      ) : null}
    </Card>
  );
}
