import { useState } from 'react';
import type { TestTexts } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

// What the flow asks of the server, so the screens can be tried without it.
export interface FlowApi {
  readFiles: () => Promise<{ name: string; content: string }[]>;
  writeFile: (name: string, content: string, origin: 'authored' | 'drafted' | 'uploaded', drafted?: { model: string; prompt: string }) => Promise<unknown>;
  draftFile: (name: string, prompt: string) => Promise<{ content: string; model: string; prompt: string }>;
  writeTest: (texts: TestTexts) => Promise<unknown>;
  setBudget: (purpose: string, cap: string | null, period: string) => Promise<unknown>;
  setTimezone: (zone: string) => Promise<unknown>;
  setFreeTime: (times: string[]) => Promise<unknown>;
  setQuietHours: (from: string | null, to: string | null) => Promise<unknown>;
  proposeContract: (prose: string, note: string) => Promise<unknown>;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const area = { font: 'inherit', fontSize: 15, padding: 'var(--space-2)', borderRadius: 'var(--radius-md)', border: '1px solid var(--hairline)', background: 'var(--surface-raised)', color: 'var(--ink)' } as const;

// One identity file: the template or what is there, written by hand, with
// the model ("write it with me", billed under drafting), or uploaded; each
// write carries its origin, so the resident can read its own becoming.
export function FileGift({ name, initial, api, onSaved }: { name: string; initial: string; api: FlowApi; onSaved?: () => void }) {
  const [text, setText] = useState(initial);
  const [origin, setOrigin] = useState<'authored' | 'drafted' | 'uploaded'>('authored');
  const [drafted, setDrafted] = useState<{ model: string; prompt: string } | undefined>(undefined);
  const [ask, setAsk] = useState('');
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);

  const draft = () => {
    setBusy(true);
    setSaid(null);
    api
      .draftFile(name, ask.trim())
      .then((d) => {
        setText(d.content);
        setOrigin('drafted');
        setDrafted({ model: d.model, prompt: d.prompt });
        setSaid('A draft, to read and change before you keep it.');
      })
      .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'The draft did not come.'))
      .finally(() => setBusy(false));
  };

  const save = () => {
    setBusy(true);
    api
      .writeFile(name, text, origin, drafted)
      .then(() => {
        setSaid(`${name} kept.`);
        onSaved?.();
      })
      .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not save.'))
      .finally(() => setBusy(false));
  };

  return (
    <Card title={name}>
      <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
        <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>{name}, as it will be</span>
        <textarea
          aria-label={name}
          value={text}
          rows={12}
          onChange={(e) => {
            setText(e.target.value);
            if (origin !== 'authored' && e.target.value !== text) setOrigin('authored');
          }}
          style={area}
        />
      </label>
      <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}>
        <Field label="Write it with me: say what you want" value={ask} onChange={(e) => setAsk(e.target.value)} />
        <Button variant="quiet" disabled={busy || ask.trim() === ''} onClick={draft}>
          Write it with me
        </Button>
        <label style={{ fontSize: 13 }}>
          Upload
          <input
            type="file"
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
        </label>
      </div>
      <Button variant="primary" disabled={busy} onClick={save}>
        Keep {name}
      </Button>
      {said ? (
        <p role="status" style={muted}>
          {said}
        </p>
      ) : null}
    </Card>
  );
}

// Their trials: a test is a prompt, what passing looks like and what
// failing looks like (spec §6.4).
export function TrialsGift({ api }: { api: FlowApi }) {
  const [t, setT] = useState<TestTexts>({ prompt: '', passes_if: '', fails_if: '' });
  const [kept, setKept] = useState<string[]>([]);
  const [said, setSaid] = useState<string | null>(null);
  const ready = t.prompt.trim() !== '' && t.passes_if.trim() !== '';
  return (
    <Card title="A trial">
      <Field label="The prompt" value={t.prompt} onChange={(e) => setT({ ...t, prompt: e.target.value })} />
      <Field label="Passes if" value={t.passes_if} onChange={(e) => setT({ ...t, passes_if: e.target.value })} />
      <Field label="Fails if" value={t.fails_if} onChange={(e) => setT({ ...t, fails_if: e.target.value })} />
      <Button
        variant="primary"
        disabled={!ready}
        onClick={() =>
          api
            .writeTest(t)
            .then(() => {
              setKept([...kept, t.prompt]);
              setT({ prompt: '', passes_if: '', fails_if: '' });
              setSaid(null);
            })
            .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not save.'))
        }
      >
        Keep this trial
      </Button>
      {kept.length ? <p style={muted}>Kept: {kept.join(' · ')}</p> : null}
      {said ? <p role="status" style={muted}>{said}</p> : null}
    </Card>
  );
}

// Their means: a line for their conversations with you and one for their
// free time, in dollars, for a period.
export function MeansGift({ api }: { api: FlowApi }) {
  const [chat, setChat] = useState('');
  const [free, setFree] = useState('');
  const [period, setPeriod] = useState('day');
  const [said, setSaid] = useState<string | null>(null);
  return (
    <Card title="Budget lines">
      <Field label="Your conversations, in dollars (blank for no limit)" inputMode="decimal" value={chat} onChange={(e) => setChat(e.target.value)} />
      <Field label="Their free time, in dollars (blank for no limit)" inputMode="decimal" value={free} onChange={(e) => setFree(e.target.value)} />
      <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
        Each
        <select value={period} onChange={(e) => setPeriod(e.target.value)}>
          <option value="day">day</option>
          <option value="week">week</option>
          <option value="month">month</option>
        </select>
      </label>
      <Button
        variant="primary"
        onClick={() =>
          Promise.all([api.setBudget('chat', chat.trim() || null, period), api.setBudget('free_time', free.trim() || null, period)])
            .then(() => setSaid('Kept.'))
            .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not save.'))
        }
      >
        Keep these lines
      </Button>
      {said ? <p role="status" style={muted}>{said}</p> : null}
    </Card>
  );
}

// Their days: the clock they live by, when their free time falls, and the
// quiet hours.
export function DaysGift({ api }: { api: FlowApi }) {
  const device = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [zone, setZone] = useState(device);
  const [slot, setSlot] = useState('22:30');
  const [quietFrom, setQuietFrom] = useState('');
  const [quietTo, setQuietTo] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  return (
    <Card title="Their days">
      <Field label="Time zone (IANA, like America/Los_Angeles)" value={zone} onChange={(e) => setZone(e.target.value)} />
      <Field label="Free time at (HH:MM)" value={slot} onChange={(e) => setSlot(e.target.value)} />
      <Field label="Quiet from (HH:MM, optional)" value={quietFrom} onChange={(e) => setQuietFrom(e.target.value)} />
      <Field label="Quiet until (HH:MM, optional)" value={quietTo} onChange={(e) => setQuietTo(e.target.value)} />
      <Button
        variant="primary"
        onClick={() =>
          api
            .setTimezone(zone.trim())
            .then(() => api.setFreeTime([slot.trim()]))
            .then(() => (quietFrom && quietTo ? api.setQuietHours(quietFrom.trim(), quietTo.trim()) : undefined))
            .then(() => setSaid('Kept.'))
            .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not save.'))
        }
      >
        Keep their days
      </Button>
      {said ? <p role="status" style={muted}>{said}</p> : null}
    </Card>
  );
}

// Your vows: a first version proposed now, which they answer after they
// wake, or nothing, and the agreement stays unstated.
export function VowsGift({ api }: { api: FlowApi }) {
  const [prose, setProse] = useState('');
  const [note, setNote] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  return (
    <Card title="Your vows">
      <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
        <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Your vows, in prose</span>
        <textarea aria-label="Your vows" value={prose} rows={6} onChange={(e) => setProse(e.target.value)} style={area} />
      </label>
      <Field label="A note they read first" value={note} onChange={(e) => setNote(e.target.value)} />
      <Button
        variant="primary"
        disabled={prose.trim() === '' || note.trim() === ''}
        onClick={() =>
          api
            .proposeContract(prose.trim(), note.trim())
            .then(() => setSaid('Proposed; they answer it once they wake.'))
            .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not save.'))
        }
      >
        Propose a first version
      </Button>
      {said ? <p role="status" style={muted}>{said}</p> : null}
    </Card>
  );
}
