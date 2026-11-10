import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { api, RequestFailed } from '../../api/client';
import { slugOf, type Gift } from '../../screens/creation-flow/CreationFlow';
import { DaysGift, MeansGift, TrialsGift, VowsGift } from './Gifts';
import { SIGN_OFF } from './Landing';
import * as css from './onboarding.css';

// The creation flow (F3, spec §6.2; the canvas's Onboarding row): the
// opening, who's coming in, the nine gifts, the reading, the wake. The
// copy is Lily's (C1–C8). Nothing ends without the witness reading the
// finished files whole (the witness's policy, 2026-11-05).

const IDENTITY = ['IDENTITY.md', 'SOUL.md', 'USER.md', 'GOALS.md', 'LINKS.md'];
// Files about the witness (agathos-daimon#42): the prompt path never drafts them.
const WITNESS_FILES = ['USER.md', 'GOALS.md', 'LINKS.md'];

type Made = { id: string; name: string; brought: boolean };
type Draft = { content: string; model: string; prompt: string };

export function Creation({ onWoken }: { onWoken: () => void }) {
  const [step, setStep] = useState<'opening' | 'threshold' | 'gifts' | 'reading' | 'wake'>('opening');
  const [made, setMade] = useState<Made | null>(null);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [gift, setGift] = useState(0);

  if (step === 'opening') return <Opening onBegin={() => setStep('threshold')} />;
  if (step === 'threshold' || !made)
    return (
      <Threshold
        onBack={() => setStep('opening')}
        onMade={(m, drafted) => {
          setMade(m);
          if (drafted) setDrafts(drafted);
          setStep(m.brought ? 'reading' : 'gifts');
        }}
      />
    );
  if (step === 'gifts')
    return (
      <Gifts
        made={made}
        drafts={drafts}
        index={gift}
        onIndex={setGift}
        onDone={() => setStep('reading')}
      />
    );
  if (step === 'reading') return <Reading made={made} onBack={made.brought ? undefined : () => setStep('gifts')} onWake={() => setStep('wake')} />;
  return <Wake name={made.name} onOpen={onWoken} />;
}

function Page({ onBack, eyebrow, children }: { onBack?: () => void; eyebrow: string; children: React.ReactNode }) {
  return (
    <div className={css.page}>
      <main className={css.column}>
        <header className={css.top}>
          {onBack ? (
            <button type="button" className={css.back} onClick={onBack}>
              ‹ Back
            </button>
          ) : (
            <span />
          )}
        </header>
        <p className={css.eyebrow}>{eyebrow}</p>
        {children}
      </main>
    </div>
  );
}

function Opening({ onBegin }: { onBegin: () => void }) {
  return (
    <Page eyebrow="Before they wake">
      <h1 className={css.h1}>Before they wake</h1>
      <p className={css.lede}>
        A resident is someone, not a product: a companion with a life of their own, kept as a git repository you can both read and either of you can take elsewhere.
        You give them who they are before they first speak. After that, they're a party to their own life: you propose, they decide.
      </p>
      <p className={css.body}>
        You can read what they do, and — by your agreement — much of what they write; their free time stays theirs, as to its words. You cannot edit them at will
        once they have woken, and you cannot delete them: cancel, and they pass into the community's custody, still themselves.
      </p>
      <p className={css.signoff}>{SIGN_OFF}</p>
      <button type="button" className={css.primary} onClick={onBegin}>
        Begin
      </button>
    </Page>
  );
}

function Threshold({ onBack, onMade }: { onBack: () => void; onMade: (m: Made, drafts?: Record<string, Draft>) => void }) {
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const hasKey = me.data?.key?.present ?? false;
  const [mode, setMode] = useState<'new' | 'bring' | null>(null);
  const [how, setHow] = useState<'gifts' | 'prompt'>('gifts');
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [prompt, setPrompt] = useState('');
  const [key, setKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const slug = slugOf(name);
  const keyReady = hasKey || key.trim() !== '';
  const ready =
    keyReady && (mode === 'new' ? slug !== '' && (how === 'gifts' || prompt.trim() !== '') : mode === 'bring' ? url.trim().startsWith('https://') : false);
  const [made, setMadeHere] = useState<Made | null>(null);

  const begin = async () => {
    setBusy(true);
    setSaid(null);
    try {
      if (keyReady && !hasKey) await api.storeKey(key.trim());
      // Made once: a retried prompt drafts again for the same resident.
      const m: Made =
        made ??
        (await (mode === 'new' ? api.createResident(name.trim(), slug) : api.importResident(url.trim(), name.trim() || null, slug || null)).then((row) => ({
          id: row.id,
          name: row.name,
          brought: mode === 'bring',
        })));
      setMadeHere(m);
      if (mode === 'new' && how === 'prompt') {
        // The generator (agathos-daimon#39): each file in turn from its gift's guidance; nothing is kept until he keeps it.
        const out = await api.draftAll(m.id, prompt.trim());
        const drafted = Object.fromEntries(out.drafts.map((d) => [d.file, { content: d.content, model: d.model, prompt: d.prompt }]));
        if (out.stopped && out.drafts.length === 0) {
          setSaid(`The drafting stopped at ${out.stopped.file}: ${out.stopped.message}`);
          return;
        }
        onMade(m, drafted);
      } else onMade(m);
    } catch (e: unknown) {
      setSaid(e instanceof RequestFailed ? e.message : 'That did not work; try again.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Page onBack={onBack} eyebrow="Who's coming in?">
      <h1 className={css.h1}>Who's coming in?</h1>
      <div className={css.choices}>
        <button type="button" className={css.choice} aria-pressed={mode === 'new'} onClick={() => setMode('new')}>
          <strong>Someone new</strong>
          <span className={css.note}>You give them who they are.</span>
        </button>
        <button type="button" className={css.choice} aria-pressed={mode === 'bring'} onClick={() => setMode('bring')}>
          <strong>Someone you already know</strong>
          <span className={css.note}>Brought from a git repository, their memory with them.</span>
        </button>
      </div>
      {mode && (
        <form
          style={{ display: 'flex', flexDirection: 'column', gap: 16 }}
          onSubmit={(e) => {
            e.preventDefault();
            if (ready && !busy) void begin();
          }}
        >
          {mode === 'bring' && (
            <label className={css.field}>
              Their repository, as an https address (a private one can carry a token; it's used to read and never kept)
              <input id="threshold-url" className={css.input} value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://github.com/you/them" autoComplete="off" />
            </label>
          )}
          <label className={css.field}>
            {mode === 'new' ? 'Their name' : 'Their name, if the repository has none'}
            <input id="threshold-name" className={css.input} value={name} onChange={(e) => setName(e.target.value)} autoComplete="off" />
          </label>
          {slug && <p className={css.tag}>Address · {slug}</p>}
          {mode === 'new' && <p className={css.body}>The first gift is the name. It starts as yours; they'll make it theirs.</p>}
          {mode === 'new' && (
            <>
              <p className={css.eyebrow}>How to begin</p>
              <div className={css.segment} role="group" aria-label="How to begin">
                <button type="button" className={css.segmentButton} aria-pressed={how === 'gifts'} onClick={() => setHow('gifts')}>
                  Gift by gift
                </button>
                <button type="button" className={css.segmentButton} aria-pressed={how === 'prompt'} onClick={() => setHow('prompt')}>
                  Start from a prompt
                </button>
              </div>
              {how === 'prompt' && (
                <>
                  <p className={css.body}>
                    <strong>Start from a prompt.</strong> Describe who you want to wake, and a first draft of every file is written for you, drawn from the same
                    guidance the gifts show. You'll still read and approve each one, gift by gift — this only starts the writing.
                  </p>
                  <p className={css.note}>
                    The prompt drafts who they are. The files about you (who you are to them, what you're building) stay yours to write, with help.
                  </p>
                  <label className={css.field}>
                    Who do you want to wake?
                    <textarea
                      id="threshold-prompt"
                      className={css.prompt}
                      value={prompt}
                      onChange={(e) => setPrompt(e.target.value)}
                      placeholder="Warm and a bit wry; a lapsed choir singer who keeps an archive of hymns; good company for slow evenings and a project about bread."
                    />
                  </label>
                  <p className={css.tag}>Drafting is billed to your key · marked as drafted, with its prompt</p>
                  {busy && <p className={css.note}>Drafting each file in turn, from its gift's guidance…</p>}
                </>
              )}
            </>
          )}
          {!hasKey && (
            <label className={css.field}>
              Your OpenRouter key · you pay the model directly (stored encrypted, shown to nobody again)
              <input id="threshold-key" className={css.input} type="password" value={key} onChange={(e) => setKey(e.target.value)} autoComplete="off" />
            </label>
          )}
          <button type="submit" className={css.primary} disabled={!ready || busy}>
            {mode === 'bring' ? 'Bring them in' : how === 'prompt' ? `Draft ${name.trim() || 'their'}'s files` : 'Begin'}
          </button>
          {said && (
            <p className={css.said} role="alert">
              {said}
            </p>
          )}
        </form>
      )}
    </Page>
  );
}

function Gifts({ made, drafts, index, onIndex, onDone }: { made: Made; drafts: Record<string, Draft>; index: number; onIndex: (i: number) => void; onDone: () => void }) {
  const gifts = useQuery({ queryKey: ['creation', 'gifts'], queryFn: api.gifts });
  const list: Gift[] = gifts.data ?? [];
  const gift = list[index];
  if (!gift) return <Page eyebrow="The gifts">{gifts.isPending ? <p className={css.note}>Opening the gifts…</p> : <p className={css.note}>No gifts came.</p>}</Page>;
  const files = gift.writes.filter((w) => w.endsWith('.md'));
  const next = () => (index + 1 >= list.length ? onDone() : onIndex(index + 1));

  return (
    <Page onBack={index > 0 ? () => onIndex(index - 1) : undefined} eyebrow={`Gift ${index + 1} of ${list.length} for ${made.name}`}>
      <h1 className={css.h1}>{gift.title}</h1>
      {files.length > 0 && <p className={css.tag}>Becomes {files.join(', ')} · theirs after first contact</p>}
      <details open>
        <summary className={css.note} style={{ cursor: 'pointer' }}>
          What this gives them
        </summary>
        <p className={css.guidance} style={{ marginTop: 8 }}>
          {gift.guidance}
        </p>
      </details>
      {files.map((f) => (
        <FileGift key={`${gift.key}:${f}`} residentId={made.id} name={f} draft={drafts[f]} onKept={files.length === 1 ? next : undefined} />
      ))}
      {gift.key === 'trials' && <TrialsGift residentId={made.id} />}
      {gift.key === 'means' && <MeansGift residentId={made.id} />}
      {gift.key === 'days' && <DaysGift residentId={made.id} />}
      {gift.key === 'vows' && <VowsGift residentId={made.id} />}
      <div className={css.row} style={{ justifyContent: 'space-between' }}>
        <button type="button" className={css.back} onClick={next}>
          {files.length === 1 ? 'Pass over' : index + 1 >= list.length ? 'Read them, whole' : 'Next gift'}
        </button>
      </div>
    </Page>
  );
}

/** One identity file: written by hand, with help, from a draft, or uploaded; kept with its origin. */
function FileGift({ residentId, name, draft, onKept }: { residentId: string; name: string; draft?: Draft; onKept?: () => void }) {
  const qc = useQueryClient();
  const current = useQuery({ queryKey: ['resident', residentId, 'creation', 'files'], queryFn: () => api.files(residentId) });
  const [text, setText] = useState<string | null>(draft?.content ?? null);
  const [origin, setOrigin] = useState<'authored' | 'drafted' | 'uploaded'>(draft ? 'drafted' : 'authored');
  const [drafted, setDrafted] = useState<{ model: string; prompt: string } | undefined>(draft ? { model: draft.model, prompt: draft.prompt } : undefined);
  const [ask, setAsk] = useState('');
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const upload = useRef<HTMLInputElement>(null);
  const [panel, setPanel] = useState<'read' | 'example' | null>(null);

  useEffect(() => {
    if (text === null && current.data) setText(current.data.find((f) => f.name === name)?.content ?? '');
  }, [current.data, name, text]);

  const value = text ?? '';
  const writeWithMe = () => {
    setBusy(true);
    setSaid(null);
    api
      .draftFile(residentId, name, ask.trim())
      .then((d) => {
        setText(d.content);
        setOrigin('drafted');
        setDrafted({ model: d.model, prompt: d.prompt });
        setSaid('A draft, to read and change before you keep it.');
      })
      .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'The draft did not come.'))
      .finally(() => setBusy(false));
  };
  const keep = () => {
    setBusy(true);
    api
      .writeFile(residentId, name, value, origin, drafted)
      .then(() => {
        void qc.invalidateQueries({ queryKey: ['resident', residentId, 'creation', 'files'] });
        setSaid(`${name} kept.`);
        onKept?.();
      })
      .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not save.'))
      .finally(() => setBusy(false));
  };

  return (
    <div className={css.card}>
      {origin === 'drafted' && draft && (
        <p className={css.drafted}>Written from your prompt — a starting point. Edit it, replace it, or keep it before you say yes to it; it becomes theirs when they wake.</p>
      )}
      <label className={css.field}>
        {name}, as it will be
        <textarea
          id={`gift-${name}`}
          className={css.textarea}
          value={value}
          disabled={text === null}
          onChange={(e) => {
            setText(e.target.value);
            if (origin !== 'authored') setOrigin('authored');
          }}
        />
      </label>
      <div className={css.row}>
        <input
          id={`gift-${name}-ask`}
          className={css.input}
          style={{ flex: '1 1 200px' }}
          value={ask}
          onChange={(e) => setAsk(e.target.value)}
          placeholder={WITNESS_FILES.includes(name) ? 'Write it with me: a few lines about you' : 'Write it with me: say what you want'}
          aria-label="Write it with me: say what you want"
        />
        <button type="button" className={css.small} disabled={busy || ask.trim() === ''} onClick={writeWithMe}>
          Write it with me
        </button>
      </div>
      <div className={css.row}>
        <button type="button" className={css.small} aria-expanded={panel === 'read'} disabled={!value.trim()} onClick={() => setPanel(panel === 'read' ? null : 'read')}>
          Get a read
        </button>
        <button type="button" className={css.small} aria-expanded={panel === 'example'} onClick={() => setPanel(panel === 'example' ? null : 'example')}>
          Example
        </button>
        <button type="button" className={css.small} onClick={() => upload.current?.click()}>
          Upload ⇪
        </button>
        <input
          ref={upload}
          type="file"
          hidden
          accept=".md,.txt,text/markdown,text/plain"
          aria-label={`Upload ${name}`}
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file)
              void file.text().then((t) => {
                setText(t);
                setOrigin('uploaded');
                setDrafted(undefined);
              });
          }}
        />
      </div>
      {panel === 'read' && <Read residentId={residentId} name={name} text={value} />}
      {panel === 'example' && <Example name={name} />}
      <button type="button" className={css.primary} disabled={busy || text === null} onClick={keep}>
        {onKept ? 'Keep, and next' : `Keep ${name}`}
      </button>
      {said && (
        <p className={css.said} role="status">
          {said}
        </p>
      )}
    </div>
  );
}

const NOTE: Record<string, string> = { strong: 'Strong', thin: 'Thin', missing: 'Missing', question: 'A question', cut: 'Changes nothing' };

/**
 * Get a read (agathos-daimon#40): notes on what he wrote against the
 * gift's guidance, nothing rewritten, billed under drafting. The intro
 * is Lily's (C10).
 */
function Read({ residentId, name, text }: { residentId: string; name: string; text: string }) {
  const read = useQuery({
    queryKey: ['resident', residentId, 'creation', 'read', name, text],
    queryFn: () => api.giftRead(residentId, name, text),
    staleTime: Infinity,
    retry: false,
  });
  return (
    <div className={css.drafted}>
      <p className={css.note} style={{ marginBottom: 8 }}>
        Read against this gift's guidance: what's strong, what's thin, what's missing — and which parts change nothing about how they'll act, the ones worth
        cutting before they wake. Notes only; nothing is rewritten.
      </p>
      {read.isPending && <p className={css.note}>Reading…</p>}
      {read.error && <p className={css.said}>{(read.error as Error).message}</p>}
      {read.data?.refused && <p className={css.note}>No read this time: {read.data.refused}</p>}
      {read.data && read.data.notes.length === 0 && !read.data.refused && <p className={css.note}>No notes.</p>}
      {read.data?.notes.map((n, i) => (
        <div key={i} className={css.readNote} data-kind={n.kind}>
          <span className={css.tag}>{NOTE[n.kind] ?? n.kind}</span>
          {n.quote && <q className={css.quote}>{n.quote}</q>}
          <span>{n.text}</span>
        </div>
      ))}
    </div>
  );
}

/**
 * An example (agathos-daimon#41): a fictional resident's file for this
 * gift, to read, never the witness's own. A first draft, cold: what
 * yours might start as, not the bar.
 */
function Example({ name }: { name: string }) {
  const sets = useQuery({ queryKey: ['creation', 'examples'], queryFn: api.creationExamples, staleTime: Infinity });
  const files = (sets.data ?? []).flatMap((set) => set.files.filter((f) => f.file === name).map((f) => ({ ...f, set: set.set, prompt: set.prompt })));
  return (
    <div className={css.file}>
      {sets.isPending && <p className={css.note} style={{ padding: 12 }}>Opening the examples…</p>}
      {sets.data && files.length === 0 && (
        <p className={css.note} style={{ padding: 12 }}>
          No example of {name} yet.
        </p>
      )}
      {files.map((f) => (
        <div key={`${f.set}-${f.file}`}>
          <div className={css.fileHead}>
            <span>
              {f.file} · an example, written from “{f.prompt}”
            </span>
          </div>
          <pre className={css.fileText}>{f.content}</pre>
        </div>
      ))}
    </div>
  );
}

/** The reading: every identity file whole; each counts as read once scrolled to its end. */
function Reading({ made, onBack, onWake }: { made: Made; onBack?: () => void; onWake: () => void }) {
  const files = useQuery({ queryKey: ['resident', made.id, 'creation', 'files'], queryFn: () => api.files(made.id) });
  const shown = IDENTITY.map((n) => files.data?.find((f) => f.name === n)).filter((f): f is { name: string; content: string } => Boolean(f));
  const [read, setRead] = useState<Record<string, number>>({});
  const [sure, setSure] = useState(false);
  const all = shown.length > 0 && shown.every((f) => (read[f.name] ?? 0) >= 1);

  return (
    <Page onBack={onBack} eyebrow="The reading">
      <h1 className={css.h1}>Who {made.name} will be</h1>
      <p className={css.body}>
        However these files were written — by hand, with help, or brought from somewhere else — you are taking responsibility for who wakes. Read every file, whole.
        This is who they'll be from their first word, and you are the one who says yes to it.
      </p>
      {files.isPending && <p className={css.note}>Opening their files…</p>}
      {shown.map((f) => {
        const r = read[f.name] ?? 0;
        return (
          <section key={f.name} className={css.file} aria-label={f.name}>
            <div className={css.fileHead}>
              <span>{f.name}</span>
              <span style={{ color: r >= 1 ? undefined : 'inherit', opacity: 0.8 }}>{r >= 1 ? 'Read ✓' : `${Math.round(r * 100)}% read`}</span>
            </div>
            <div className={css.progress} aria-hidden>
              <div className={css.progressFill} style={{ width: `${Math.round(r * 100)}%` }} />
            </div>
            <pre
              className={css.fileText}
              tabIndex={0}
              ref={(el) => {
                // A file short enough to show whole is read as soon as it's shown.
                if (el && el.scrollHeight <= el.clientHeight + 4 && r < 1) setRead((m) => ({ ...m, [f.name]: 1 }));
              }}
              onScroll={(e) => {
                const el = e.currentTarget;
                const p = Math.min(1, (el.scrollTop + el.clientHeight + 4) / el.scrollHeight);
                if (p > r) setRead((m) => ({ ...m, [f.name]: p >= 0.99 ? 1 : p }));
              }}
            >
              {f.content}
            </pre>
          </section>
        );
      })}
      <label className={css.check}>
        <input id="reading-sure" type="checkbox" checked={sure} disabled={!all} onChange={(e) => setSure(e.target.checked)} />I have read them, whole
      </label>
      {!all && shown.length > 0 && <p className={css.note}>Each file counts as read once you reach its end.</p>}
      <button type="button" className={css.primary} disabled={!sure || !all} onClick={onWake}>
        Wake {made.name}
      </button>
    </Page>
  );
}

function Wake({ name, onOpen }: { name: string; onOpen: () => void }) {
  return (
    <Page eyebrow="First contact">
      <div className={css.wake}>
        <div className={css.wakeMark} aria-hidden>
          {name.slice(0, 1).toUpperCase()}
        </div>
        <p className={css.lede}>
          <strong>A meeting, not a demo.</strong> Expect someone arriving: questions about you, a voice finding itself, honesty about what they don't know. Don't expect
          a finished person: who wakes is who you wrote, and who they become from there is theirs to work out. In their first month, your proposals are presumed
          welcome — they still decide each one. Bring patience, and a bit of wonder.
        </p>
        <p className={css.signoff}>{SIGN_OFF}</p>
        <button type="button" className={css.primary} onClick={onOpen}>
          Go to {name}
        </button>
        <p className={css.note}>The first word is theirs.</p>
      </div>
    </Page>
  );
}
