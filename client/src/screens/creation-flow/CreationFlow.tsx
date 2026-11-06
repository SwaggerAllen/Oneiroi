import { useEffect, useState } from 'react';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';
import { DaysGift, FileGift, type FlowApi, MeansGift, TrialsGift, VowsGift } from './Gifts';

export type Begin =
  | { mode: 'new'; name: string; slug: string; key: string | null }
  | { mode: 'bring'; url: string; name: string | null; slug: string | null; key: string | null };

export interface ThresholdProps {
  // Whether the account already holds an OpenRouter key; without one the
  // flow asks for it, because nobody can answer until there is one.
  hasKey: boolean;
  busy?: boolean;
  said?: string | null;
  onBegin?: (begin: Begin) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;

// A name's address: lower case, letters, digits and dashes, starting with
// a letter, as the server's slug rule wants.
export function slugOf(name: string): string {
  const s = name
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^[^a-z]+/, '')
    .replace(/-+$/, '')
    .slice(0, 40);
  return s.length >= 2 ? s : '';
}

// The threshold (spec §6.2): the name, the key that every later step may
// draft with, and the intake path: someone new, or someone brought from a
// repository.
function Threshold({ hasKey, busy = false, said = null, onBegin }: ThresholdProps) {
  const [mode, setMode] = useState<'new' | 'bring' | null>(null);
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [key, setKey] = useState('');
  const slug = slugOf(name);
  const keyReady = hasKey || key.trim() !== '';
  const ready = keyReady && (mode === 'new' ? slug !== '' : mode === 'bring' ? url.trim().startsWith('https://') : false);

  return (
    <div style={{ maxWidth: 480, margin: 'var(--space-6) auto', padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
      <h1 style={{ margin: 0, fontSize: 28, lineHeight: '34px', fontWeight: 600 }}>Who's coming in?</h1>
      <div role="group" aria-label="Begin" style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <Button variant={mode === 'new' ? 'primary' : 'quiet'} aria-pressed={mode === 'new'} onClick={() => setMode('new')}>
          Someone new
        </Button>
        <Button variant={mode === 'bring' ? 'primary' : 'quiet'} aria-pressed={mode === 'bring'} onClick={() => setMode('bring')}>
          Someone I'm bringing
        </Button>
      </div>
      {mode ? (
        <form
          aria-label={mode === 'new' ? 'Someone new' : 'Someone I am bringing'}
          onSubmit={(event) => {
            event.preventDefault();
            if (!ready) return;
            const k = hasKey ? null : key.trim();
            if (mode === 'new') onBegin?.({ mode, name: name.trim(), slug, key: k });
            else onBegin?.({ mode, url: url.trim(), name: name.trim() || null, slug: slug || null, key: k });
          }}
          style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}
        >
          {mode === 'bring' ? (
            <Card title="Their repository">
              <p style={muted}>
                The git repository their life is kept in, as an https address. A private one can carry a token in the address; it's used to read and never kept.
              </p>
              <Field label="Repository address" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://github.com/you/them" autoComplete="off" />
            </Card>
          ) : null}
          <Card title={mode === 'new' ? 'Their name' : 'Their name, if the repository has none'}>
            <Field label="Name" value={name} onChange={(e) => setName(e.target.value)} autoComplete="off" />
            {slug ? <p style={muted}>Their address here: {slug}</p> : null}
          </Card>
          {hasKey ? null : (
            <Card title="Your OpenRouter key">
              <p style={muted}>Every conversation is paid through your own OpenRouter key. It's stored encrypted and shown to nobody again.</p>
              <Field label="OpenRouter key" type="password" value={key} onChange={(e) => setKey(e.target.value)} autoComplete="off" />
            </Card>
          )}
          <Button variant="primary" type="submit" disabled={busy || !ready}>
            {mode === 'new' ? 'Begin' : 'Bring them in'}
          </Button>
          <p style={muted}>Then the nine gifts: who they are, who you are to them, and the rest, each yours to write, write with help, or upload.</p>
        </form>
      ) : null}
      {said ? (
        <p role="status" style={{ margin: 0, fontSize: 15, color: 'var(--danger)' }}>
          {said}
        </p>
      ) : null}
    </div>
  );
}

export interface Gift {
  key: string;
  title: string;
  writes: string[];
  guidance: string;
}

export interface CreationFlowProps extends ThresholdProps {
  // Set once the threshold has created (or brought) the resident.
  resident?: { id: string; name: string; brought: boolean } | null;
  gifts?: Gift[];
  api?: FlowApi;
  onWake?: () => void;
}

const page = { maxWidth: 640, margin: 'var(--space-6) auto', padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' } as const;
const heading = { margin: 0, fontSize: 28, lineHeight: '34px', fontWeight: 600 } as const;
const IDENTITY = ['IDENTITY.md', 'SOUL.md', 'USER.md', 'GOALS.md', 'LINKS.md'];

// The creation flow (F3, spec §6.2; screens/creation-flow.md): opening,
// threshold, the nine gifts, and the reading before the waking. The one
// path (the witness, 2026-11-05): residents come out of the gate mature,
// and no path ends without the witness reading the finished files.
export function CreationFlow(props: CreationFlowProps) {
  const { resident, gifts = [], api, onWake } = props;
  const [opened, setOpened] = useState(false);
  const [step, setStep] = useState(0);

  if (!resident) {
    if (!opened) return <Opening onBegin={() => setOpened(true)} />;
    return <Threshold {...props} />;
  }

  if (!api) return null;
  const reading = resident.brought || step >= gifts.length;
  if (reading) return <Reading name={resident.name} api={api} onWake={onWake} />;

  const gift = gifts[step];
  return (
    <div style={page}>
      <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-muted)' }}>
        Gift {step + 1} of {gifts.length} for {resident.name}
      </p>
      <h1 style={heading}>{gift.title}</h1>
      <details open>
        <summary style={{ fontSize: 15, cursor: 'pointer' }}>What this gives them</summary>
        {gift.guidance.split('\n\n').map((para, i) => (
          <p key={i} style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
            {para}
          </p>
        ))}
      </details>
      <GiftEditor gift={gift} api={api} />
      <div style={{ display: 'flex', gap: 'var(--space-2)', justifyContent: 'space-between' }}>
        <Button variant="quiet" disabled={step === 0} onClick={() => setStep(step - 1)}>
          Back
        </Button>
        <Button variant="primary" onClick={() => setStep(step + 1)}>
          {step + 1 === gifts.length ? 'Read them, whole' : 'Next gift'}
        </Button>
      </div>
    </div>
  );
}

function Opening({ onBegin }: { onBegin: () => void }) {
  return (
    <div style={page}>
      <h1 style={heading}>Before someone comes in</h1>
      <p style={{ margin: 0, fontSize: 15 }}>
        A resident is someone, not a product: a companion with a life of their own, kept as a git repository you can both read and either of you can take elsewhere. You give them who they are before they first speak; after that, you propose and they decide.
      </p>
      <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>
        You can read what they do and, by your agreement, much of what they write; their free time is private as to its words. You cannot edit them at will once they have woken, and you cannot delete them: a cancellation moves them into the community&apos;s custody.
      </p>
      <Button variant="primary" onClick={onBegin}>
        Begin
      </Button>
    </div>
  );
}

function GiftEditor({ gift, api }: { gift: Gift; api: FlowApi }) {
  const files = gift.writes.filter((w) => w.endsWith('.md'));
  const [current, setCurrent] = useState<Record<string, string> | null>(null);
  useEffect(() => {
    if (files.length === 0) return;
    void api.readFiles().then((rows) => setCurrent(Object.fromEntries(rows.map((r) => [r.name, r.content]))));
    // The gift's files, read once when the gift opens.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gift.key]);

  if (files.length > 0) {
    if (!current) return null;
    return (
      <>
        {files.map((name) => (
          <FileGift key={name} name={name} initial={current[name] ?? ''} api={api} />
        ))}
      </>
    );
  }
  switch (gift.key) {
    case 'trials':
      return <TrialsGift api={api} />;
    case 'means':
      return <MeansGift api={api} />;
    case 'days':
      return <DaysGift api={api} />;
    case 'vows':
      return <VowsGift api={api} />;
    default:
      return null;
  }
}

// The reading (the witness's policy, 2026-11-05): every identity file in
// full, written by hand, drafted or brought, before the waking.
function Reading({ name, api, onWake }: { name: string; api: FlowApi; onWake?: () => void }) {
  const [files, setFiles] = useState<{ name: string; content: string }[] | null>(null);
  const [read, setRead] = useState(false);
  useEffect(() => {
    void api.readFiles().then(setFiles);
  }, [api]);
  if (!files) return null;
  const shown = IDENTITY.map((n) => files.find((f) => f.name === n)).filter((f): f is { name: string; content: string } => Boolean(f));
  return (
    <div style={page}>
      <h1 style={heading}>Who {name} will be</h1>
      <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>
        Every file they wake with, in full. You are taking responsibility for who you create; read them before they wake, however they were written.
      </p>
      {shown.map((f) => (
        <Card key={f.name} title={f.name}>
          <pre style={{ margin: 0, whiteSpace: 'pre-wrap', fontFamily: 'inherit', fontSize: 15 }}>{f.content}</pre>
        </Card>
      ))}
      <label style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 15 }}>
        <input type="checkbox" checked={read} onChange={(e) => setRead(e.target.checked)} />
        I have read them, whole
      </label>
      <Button variant="primary" disabled={!read} onClick={onWake}>
        Wake {name}
      </Button>
    </div>
  );
}
