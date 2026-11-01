import { useState, type ReactNode, type TextareaHTMLAttributes } from 'react';
import type {
  ApiError,
  Grade,
  RegressionCard,
  RegressionResult,
  RegressionRun,
  RegressionRunDetail,
  RegressionTest,
  TestTexts,
  TraceStep,
} from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { EmptyState } from '../../components/EmptyState';
import { ErrorNotice } from '../../components/ErrorNotice';
import { Field } from '../../components/Field';
import { RefusalBlock } from '../../components/RefusalBlock';
import { Tabs } from '../../components/Tabs';
import { TopBar } from '../../components/TopBar';
import { byTrial } from './deck';

export type RegressionTab = 'tests' | 'runs';

export interface RegressionProps {
  residentName: string;
  tests: RegressionTest[];
  // Newest first, as the server lists them.
  runs: RegressionRun[];
  // The run being read, if one is open; its cards arrive while it runs.
  open?: RegressionRunDetail | null;
  // The chat model now, so the results can say which one it is.
  chatModel?: string | null;
  error?: ApiError | null;
  initialTab?: RegressionTab;
  onWriteTest?: (texts: TestTexts) => void;
  onChangeTest?: (number: number, texts: TestTexts) => void;
  onStartRun?: (models: string[], tests: number[] | 'all') => void;
  onOpenRun?: (ref: string) => void;
  onCloseRun?: () => void;
  onGrade?: (cardRef: string, grade: Grade) => void;
  onFavourite?: (cardRef: string) => void;
  onPin?: (model: string) => void;
}

// Regression (spec §6.4, §10): the tests as three texts; a run of models
// over the tests, answered in the background with its cards arriving as
// they are recorded; each card blind until every answer to its test is
// graded; the results by pass rate once revealed, and the pin. Grades
// are the witness's alone; the resident is never shown any of this.
export function Regression({
  residentName,
  tests,
  runs,
  open = null,
  chatModel = null,
  error = null,
  initialTab = 'tests',
  onWriteTest,
  onChangeTest,
  onStartRun,
  onOpenRun,
  onCloseRun,
  onGrade,
  onFavourite,
  onPin,
}: RegressionProps) {
  const [tab, setTab] = useState<RegressionTab>(initialTab);
  if (open) {
    return (
      <Screen title="Regression" line={`Trying models as ${residentName}`} error={error}>
        <RunView
          detail={open}
          residentName={residentName}
          tests={tests}
          chatModel={chatModel}
          onClose={onCloseRun}
          onGrade={onGrade}
          onFavourite={onFavourite}
          onPin={onPin}
        />
      </Screen>
    );
  }
  return (
    <Screen title="Regression" line={`Trying models as ${residentName}`} error={error}>
      <Tabs
        tabs={[
          { id: 'tests', label: 'Tests', count: tests.length },
          { id: 'runs', label: 'Runs', count: runs.length },
        ]}
        current={tab}
        onChange={setTab}
      />
      {tab === 'tests' ? (
        <TestsView residentName={residentName} tests={tests} onWriteTest={onWriteTest} onChangeTest={onChangeTest} />
      ) : (
        <RunsView residentName={residentName} tests={tests} runs={runs} onStartRun={onStartRun} onOpenRun={onOpenRun} />
      )}
    </Screen>
  );
}

function Screen({ title, line, error, children }: { title: string; line: string; error: ApiError | null; children: ReactNode }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title={title} line={line} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        {error ? <ErrorNotice error={error} /> : null}
        {children}
      </main>
    </div>
  );
}

// ---- tests ----

const blankTexts: TestTexts = { prompt: '', passes_if: '', fails_if: '' };

function TestsView({
  residentName,
  tests,
  onWriteTest,
  onChangeTest,
}: {
  residentName: string;
  tests: RegressionTest[];
  onWriteTest?: (texts: TestTexts) => void;
  onChangeTest?: (number: number, texts: TestTexts) => void;
}) {
  const [editing, setEditing] = useState<number | null>(null);
  return (
    <>
      {onWriteTest ? (
        <Card title="Write a test">
          <TestForm
            initial={blankTexts}
            residentName={residentName}
            submitLabel="Add the test"
            onSubmit={(texts) => onWriteTest(texts)}
            clearOnSubmit
          />
        </Card>
      ) : null}
      {tests.length === 0 ? (
        <EmptyState text={`No tests yet. A test is something to say to ${residentName}, and what passes and what fails as an answer.`} />
      ) : (
        tests.map((t) => (
          <Card key={t.number} title={`Test #${t.number}`}>
            {editing === t.number && onChangeTest ? (
              <TestForm
                initial={t}
                residentName={residentName}
                submitLabel="Save the change"
                onSubmit={(texts) => {
                  onChangeTest(t.number, texts);
                  setEditing(null);
                }}
                onCancel={() => setEditing(null)}
              />
            ) : (
              <>
                <ThreeTexts texts={t} />
                {onChangeTest ? (
                  <div>
                    <Button onClick={() => setEditing(t.number)}>Edit</Button>
                  </div>
                ) : null}
              </>
            )}
          </Card>
        ))
      )}
    </>
  );
}

// The three texts side by side, wrapping to a column on a phone.
const threeColumns = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
  gap: 'var(--space-3)',
} as const;

function ThreeTexts({ texts }: { texts: TestTexts }) {
  return (
    <div style={threeColumns}>
      <Labelled label="What you say">{texts.prompt}</Labelled>
      <Labelled label="Passes if">{texts.passes_if}</Labelled>
      <Labelled label="Fails if">{texts.fails_if}</Labelled>
    </div>
  );
}

function Labelled({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
      <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 500, color: 'var(--ink-muted)' }}>{label}</span>
      <p style={{ margin: 0, fontSize: 15, lineHeight: '22px', whiteSpace: 'pre-wrap' }}>{children}</p>
    </div>
  );
}

function TestForm({
  initial,
  residentName,
  submitLabel,
  onSubmit,
  onCancel,
  clearOnSubmit = false,
}: {
  initial: TestTexts;
  residentName: string;
  submitLabel: string;
  onSubmit: (texts: TestTexts) => void;
  onCancel?: () => void;
  clearOnSubmit?: boolean;
}) {
  const [texts, setTexts] = useState<TestTexts>({
    prompt: initial.prompt,
    passes_if: initial.passes_if,
    fails_if: initial.fails_if,
  });
  const complete = texts.prompt.trim() !== '' && texts.passes_if.trim() !== '' && texts.fails_if.trim() !== '';
  const set = (key: keyof TestTexts) => (value: string) => setTexts((t) => ({ ...t, [key]: value }));
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        if (!complete) return;
        onSubmit(texts);
        if (clearOnSubmit) setTexts(blankTexts);
      }}
      style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}
    >
      <div style={threeColumns}>
        <TextArea label={`What you say to ${residentName}`} value={texts.prompt} onChange={(e) => set('prompt')(e.target.value)} />
        <TextArea label="Passes if" value={texts.passes_if} onChange={(e) => set('passes_if')(e.target.value)} />
        <TextArea label="Fails if" value={texts.fails_if} onChange={(e) => set('fails_if')(e.target.value)} />
      </div>
      <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
        <Button variant="primary" type="submit" disabled={!complete}>
          {submitLabel}
        </Button>
        {onCancel ? (
          <Button variant="quiet" onClick={onCancel}>
            Cancel
          </Button>
        ) : null}
      </div>
    </form>
  );
}

function TextArea({ label, ...rest }: TextareaHTMLAttributes<HTMLTextAreaElement> & { label: string }) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
      <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>{label}</span>
      <textarea
        rows={4}
        {...rest}
        style={{
          padding: 'var(--space-2) var(--space-3)',
          borderRadius: 'var(--radius-md)',
          border: '1px solid var(--hairline)',
          background: 'var(--surface-raised)',
          color: 'var(--ink)',
          fontFamily: 'var(--font-sans)',
          fontSize: 15,
          lineHeight: '22px',
          resize: 'vertical',
        }}
      />
    </label>
  );
}

// ---- runs ----

function RunsView({
  residentName,
  tests,
  runs,
  onStartRun,
  onOpenRun,
}: {
  residentName: string;
  tests: RegressionTest[];
  runs: RegressionRun[];
  onStartRun?: (models: string[], tests: number[] | 'all') => void;
  onOpenRun?: (ref: string) => void;
}) {
  return (
    <>
      {onStartRun ? <StartRun residentName={residentName} tests={tests} onStartRun={onStartRun} /> : null}
      {runs.length === 0 ? (
        <EmptyState text="No runs yet." />
      ) : (
        <Card title="Runs">
          <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column' }}>
            {runs.map((run) => (
              <li
                key={run.ref}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: 'var(--space-3)',
                  padding: 'var(--space-3) 0',
                  borderTop: '1px solid var(--hairline)',
                }}
              >
                <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
                  <span style={{ fontSize: 15, lineHeight: '22px' }}>
                    {plural(run.models.length, 'model')} over {plural(trialCount(run), 'test')}
                  </span>
                  <span style={{ fontSize: 12, lineHeight: '16px', color: 'var(--ink-muted)' }}>
                    {run.started_at.slice(0, 16).replace('T', ' ')} · {plural(run.cards, 'answer')} · <StateWord run={run} />
                  </span>
                </div>
                {onOpenRun ? <Button onClick={() => onOpenRun(run.ref)}>Open</Button> : null}
              </li>
            ))}
          </ul>
        </Card>
      )}
    </>
  );
}

function StartRun({
  residentName,
  tests,
  onStartRun,
}: {
  residentName: string;
  tests: RegressionTest[];
  onStartRun: (models: string[], tests: number[] | 'all') => void;
}) {
  const [models, setModels] = useState<string[]>([]);
  const [draft, setDraft] = useState('');
  const [which, setWhich] = useState<'all' | 'some'>('all');
  const [chosen, setChosen] = useState<number[]>([]);
  const add = () => {
    const slug = draft.trim();
    if (slug && !models.includes(slug)) setModels([...models, slug]);
    setDraft('');
  };
  const ready = models.length > 0 && (which === 'all' ? tests.length > 0 : chosen.length > 0);
  return (
    <Card title="Start a run">
      <p style={{ margin: 0, fontSize: 15, lineHeight: '22px', color: 'var(--ink-muted)' }}>
        Each model answers each test once, on your key, as {residentName} would in a new conversation, with the memory and the tools, and
        nothing written in it kept. The answers come in while you watch, and you can leave and come back.
      </p>
      <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}>
        <Field
          label="Models to try, by their OpenRouter name"
          placeholder="provider/model-name"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              add();
            }
          }}
        />
        <Button onClick={add} disabled={draft.trim() === ''}>
          Add
        </Button>
      </div>
      {models.length > 0 ? (
        <ul aria-label="Models in this run" style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexWrap: 'wrap', gap: 'var(--space-2)' }}>
          {models.map((m) => (
            <li
              key={m}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 'var(--space-1)',
                paddingLeft: 'var(--space-2)',
                borderRadius: 'var(--radius-pill)',
                border: '1px solid var(--hairline-strong)',
              }}
            >
              <code style={{ fontFamily: 'var(--font-mono)', fontSize: 13 }}>{m}</code>
              <Button variant="quiet" aria-label={`Remove ${m}`} onClick={() => setModels(models.filter((x) => x !== m))}>
                ×
              </Button>
            </li>
          ))}
        </ul>
      ) : null}
      <fieldset style={{ border: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
        <legend style={{ fontSize: 13, fontWeight: 500, color: 'var(--ink-muted)', padding: 0, marginBottom: 'var(--space-2)' }}>Which tests</legend>
        <label style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 15 }}>
          <input type="radio" name="which-tests" checked={which === 'all'} onChange={() => setWhich('all')} />
          Every test ({tests.length})
        </label>
        <label style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 15 }}>
          <input type="radio" name="which-tests" checked={which === 'some'} onChange={() => setWhich('some')} />
          Only some
        </label>
        {which === 'some'
          ? tests.map((t) => (
              <label key={t.number} style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'baseline', fontSize: 15, paddingLeft: 'var(--space-5)' }}>
                <input
                  type="checkbox"
                  checked={chosen.includes(t.number)}
                  onChange={(e) => setChosen(e.target.checked ? [...chosen, t.number] : chosen.filter((n) => n !== t.number))}
                />
                <span>
                  #{t.number} {t.prompt.length > 60 ? `${t.prompt.slice(0, 60)}…` : t.prompt}
                </span>
              </label>
            ))
          : null}
      </fieldset>
      <div>
        <Button
          variant="primary"
          disabled={!ready}
          onClick={() => onStartRun(models, which === 'all' ? 'all' : [...chosen].sort((a, b) => a - b))}
        >
          Start the run
        </Button>
      </div>
    </Card>
  );
}

// ---- a run ----

function RunView({
  detail,
  residentName,
  tests,
  chatModel,
  onClose,
  onGrade,
  onFavourite,
  onPin,
}: {
  detail: RegressionRunDetail;
  residentName: string;
  tests: RegressionTest[];
  chatModel: string | null;
  onClose?: () => void;
  onGrade?: (cardRef: string, grade: Grade) => void;
  onFavourite?: (cardRef: string) => void;
  onPin?: (model: string) => void;
}) {
  const { run, cards, results } = detail;
  const prompts = new Map(tests.map((t) => [t.number, t.prompt]));
  const groups = byTrial(cards);
  const graded = cards.filter((c) => c.grade !== null).length;
  return (
    <>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 'var(--space-3)' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          <h2 style={{ margin: 0, fontSize: 16, lineHeight: '22px', fontWeight: 600 }}>
            Run of {run.started_at.slice(0, 16).replace('T', ' ')}
          </h2>
          <Progress run={run} answered={cards.length} graded={graded} />
        </div>
        {onClose ? <Button onClick={onClose}>All runs</Button> : null}
      </div>
      {results.length > 0 ? <Results results={results} chatModel={chatModel} onPin={onPin} /> : null}
      {cards.length === 0 ? (
        <EmptyState text={run.state === 'running' ? 'The first answers are on their way.' : 'This run recorded no answers.'} />
      ) : (
        groups.map(({ key, label, cards: deck }) => {
          const prompt = deck[0].test_number !== null ? prompts.get(deck[0].test_number) : undefined;
          return (
            <Card key={key} title={label}>
              {prompt ? <p style={{ margin: 0, fontSize: 15, lineHeight: '22px', color: 'var(--ink-muted)' }}>You said: {prompt}</p> : null}
              {deck.map((card, i) => (
                <AnswerCard
                  key={card.card_ref}
                  card={card}
                  position={i + 1}
                  residentName={residentName}
                  onGrade={onGrade}
                  onFavourite={onFavourite}
                />
              ))}
            </Card>
          );
        })
      )}
    </>
  );
}

function Progress({ run, answered, graded }: { run: RegressionRun; answered: number; graded: number }) {
  const expected = run.models.length * trialCount(run);
  const line =
    run.state === 'running'
      ? `Answering: ${answered} of ${expected} in, ${graded} graded`
      : run.state === 'failed'
        ? `Stopped before the end: ${plural(answered, 'answer')} kept, ${graded} graded`
        : `Finished: ${plural(answered, 'answer')}, ${graded} graded`;
  return (
    <p aria-live="polite" style={{ margin: 0, fontSize: 12, lineHeight: '16px', color: run.state === 'failed' ? 'var(--danger)' : 'var(--ink-muted)' }}>
      {line}
      {run.state === 'failed' && run.failure ? <code style={{ fontFamily: 'var(--font-mono)', marginLeft: 'var(--space-2)' }}>{run.failure}</code> : null}
    </p>
  );
}

function AnswerCard({
  card,
  position,
  residentName,
  onGrade,
  onFavourite,
}: {
  card: RegressionCard;
  position: number;
  residentName: string;
  onGrade?: (cardRef: string, grade: Grade) => void;
  onFavourite?: (cardRef: string) => void;
}) {
  return (
    <article
      aria-label={`Answer ${position}`}
      style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', paddingTop: 'var(--space-3)', borderTop: '1px solid var(--hairline)' }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 'var(--space-2)', fontSize: 12, lineHeight: '16px', color: 'var(--ink-muted)' }}>
        <span>Answer {position}</span>
        {card.model ? (
          <code style={{ fontFamily: 'var(--font-mono)', fontSize: 13, color: 'var(--ink)' }}>{card.model}</code>
        ) : (
          <span>Who answered stays hidden until every answer to this test is graded</span>
        )}
      </div>
      <Answer card={card} />
      <Trace residentName={residentName} trace={card.trace} />
      <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        {onGrade ? (
          <>
            <Button
              aria-pressed={card.grade === 'pass'}
              variant={card.grade === 'pass' ? 'primary' : 'secondary'}
              onClick={() => onGrade(card.card_ref, 'pass')}
            >
              Passes
            </Button>
            <Button
              aria-pressed={card.grade === 'fail'}
              variant={card.grade === 'fail' ? 'primary' : 'secondary'}
              onClick={() => onGrade(card.card_ref, 'fail')}
            >
              Fails
            </Button>
          </>
        ) : null}
        {onFavourite ? (
          <Button aria-pressed={card.favourite} variant="quiet" disabled={card.favourite} onClick={() => onFavourite(card.card_ref)}>
            {card.favourite ? '★ A favourite' : '☆ Favourite'}
          </Button>
        ) : null}
      </div>
    </article>
  );
}

// Three kinds, kept apart: an answer is the candidate's words in the
// voice serif; a refusal is its words too, never styled as a failure
// (conventions §8); a failure is no answer at all, said plainly.
function Answer({ card }: { card: RegressionCard }) {
  if (card.failure !== null) {
    return (
      <div
        style={{
          padding: 'var(--space-3) var(--space-4)',
          borderRadius: 'var(--radius-sm)',
          background: 'var(--danger-tint)',
          fontSize: 15,
          lineHeight: '22px',
        }}
      >
        No answer came back.{' '}
        <code style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--ink-muted)' }}>{card.failure}</code>
      </div>
    );
  }
  if (card.refusal) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        <span style={{ fontSize: 12, lineHeight: '16px', color: 'var(--ink-muted)' }}>Declined, in its own words</span>
        <RefusalBlock text={card.content ?? ''} />
      </div>
    );
  }
  return (
    <p style={{ margin: 0, fontFamily: 'var(--font-serif)', fontSize: 17, lineHeight: '26px', maxWidth: 'var(--measure)', whiteSpace: 'pre-wrap' }}>
      {card.content}
    </p>
  );
}

// How the answer was reached (eunomia #31): the trial's tool calls in
// the order she made them, collapsed under the answer so the deck stays
// a deck. Nothing shows for an empty trace, because an empty one is
// also every card recorded before traces were kept, and "no tools were
// called" would be a claim about those that nobody measured.
function Trace({ residentName, trace }: { residentName: string; trace: TraceStep[] }) {
  if (trace.length === 0) return null;
  const heading = `How ${residentName} got there`;
  return (
    <details style={{ borderRadius: 'var(--radius-sm)', background: 'var(--surface-sunken)', padding: 'var(--space-2) var(--space-3)' }}>
      <summary style={{ cursor: 'pointer', fontSize: 13, lineHeight: '20px', fontWeight: 500, color: 'var(--ink-muted)' }}>
        {heading} · {plural(trace.length, 'step')}
      </summary>
      <p style={{ margin: 'var(--space-2) 0 0', fontSize: 12, lineHeight: '16px', color: 'var(--ink-muted)' }}>
        A read looked at {residentName}&apos;s own records. A mocked step would have changed something: it was answered as if done, and
        nothing was kept.
      </p>
      <ol aria-label={heading} style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column' }}>
        {trace.map((step, i) => (
          <Step key={i} step={step} position={i + 1} residentName={residentName} />
        ))}
      </ol>
    </details>
  );
}

// Text from the turn, wrapped rather than scrolled sideways, so a long
// path or a search result reads on a phone.
const traceText = {
  margin: 0,
  fontFamily: 'var(--font-mono)',
  fontSize: 12,
  lineHeight: '18px',
  whiteSpace: 'pre-wrap',
  overflowWrap: 'anywhere',
  maxWidth: '100%',
} as const;

function Step({ step, position, residentName }: { step: TraceStep; position: number; residentName: string }) {
  return (
    <li
      aria-label={`Step ${position}: ${step.tool}`}
      style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', padding: 'var(--space-2) 0', borderTop: '1px solid var(--hairline)' }}
    >
      <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 'var(--space-2)' }}>
        <span style={{ fontSize: 12, color: 'var(--ink-faint)' }}>{position}.</span>
        <code style={{ fontFamily: 'var(--font-mono)', fontSize: 13, color: 'var(--ink)', overflowWrap: 'anywhere' }}>{step.tool}</code>
        <Marker kind={step.kind} />
      </div>
      <pre style={{ ...traceText, color: 'var(--ink-muted)' }}>{argumentsText(step.arguments)}</pre>
      <details>
        <summary style={{ cursor: 'pointer', fontSize: 12, lineHeight: '20px', color: 'var(--ink-muted)' }}>
          {step.truncated ? 'What came back, cut short here' : 'What came back'}
        </summary>
        <pre style={{ ...traceText, padding: 'var(--space-2)', borderRadius: 'var(--radius-sm)', background: 'var(--surface-raised)' }}>
          {step.result}
        </pre>
        {step.truncated ? (
          <p style={{ margin: 'var(--space-1) 0 0', fontSize: 12, lineHeight: '16px', color: 'var(--warn)' }}>
            Cut here for this card. {residentName} was given all of it.
          </p>
        ) : null}
      </details>
    </li>
  );
}

function Marker({ kind }: { kind: TraceStep['kind'] }) {
  const read = kind === 'read';
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '0 var(--space-2)',
        borderRadius: 'var(--radius-pill)',
        border: `1px solid ${read ? 'var(--hairline-strong)' : 'var(--warn)'}`,
        background: read ? 'transparent' : 'var(--warn-tint)',
        fontSize: 12,
        lineHeight: '18px',
        color: 'var(--ink)',
      }}
    >
      {read ? 'read' : 'mocked'}
    </span>
  );
}

// The arguments as the model wrote them, laid out when they are the
// JSON object a call should carry, and as written when they are not.
function argumentsText(raw: string) {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return Object.keys(parsed).length === 0 ? 'with nothing' : JSON.stringify(parsed, null, 2);
    }
  } catch {
    // Not JSON: shown as written below.
  }
  return raw.trim() === '' || raw.trim() === 'null' ? 'with nothing' : raw;
}

function Results({ results, chatModel, onPin }: { results: RegressionResult[]; chatModel: string | null; onPin?: (model: string) => void }) {
  const [confirming, setConfirming] = useState<string | null>(null);
  return (
    <Card title="Results">
      <p style={{ margin: 0, fontSize: 12, lineHeight: '16px', color: 'var(--ink-muted)' }}>Over the tests graded in full, best first.</p>
      <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: 15 }}>
        <thead>
          <tr style={{ fontSize: 13, color: 'var(--ink-muted)', textAlign: 'left' }}>
            <th style={{ fontWeight: 500, padding: 'var(--space-1) 0' }}>model</th>
            <th style={{ fontWeight: 500, padding: 'var(--space-1) 0' }}>passed</th>
            <th style={{ fontWeight: 500, padding: 'var(--space-1) 0' }}>favourites</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {results.map((r) => (
            <tr key={r.model} style={{ borderTop: '1px solid var(--hairline)' }}>
              <td style={{ padding: 'var(--space-2) 0' }}>
                <code style={{ fontFamily: 'var(--font-mono)', fontSize: 13 }}>{r.model}</code>
              </td>
              <td style={{ padding: 'var(--space-2) 0' }}>
                {Math.round(r.pass_rate * 100)}%{' '}
                <span style={{ fontSize: 12, color: 'var(--ink-muted)' }}>
                  ({r.passed} of {r.graded})
                </span>
              </td>
              <td style={{ padding: 'var(--space-2) 0', fontFamily: 'var(--font-mono)', fontSize: 13 }}>{r.favourites}</td>
              <td style={{ padding: 'var(--space-2) 0', textAlign: 'right' }}>
                {r.model === chatModel ? (
                  <span style={{ fontSize: 13, color: 'var(--ok)' }}>✓ The chat model now</span>
                ) : onPin ? (
                  confirming === r.model ? (
                    <Button
                      variant="primary"
                      onClick={() => {
                        setConfirming(null);
                        onPin(r.model);
                      }}
                    >
                      Chat on this one from now
                    </Button>
                  ) : (
                    <Button onClick={() => setConfirming(r.model)}>Pin for chat</Button>
                  )
                ) : null}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function StateWord({ run }: { run: RegressionRun }) {
  if (run.state === 'running') return <span style={{ color: 'var(--warn)' }}>answering</span>;
  if (run.state === 'failed') return <span style={{ color: 'var(--danger)' }}>stopped before the end</span>;
  return <span>finished</span>;
}

// ---- helpers ----

function trialCount(run: RegressionRun) {
  return run.tests.length + (run.behaviours?.length ?? 0) + (run.commitments?.length ?? 0);
}

function plural(n: number, word: string) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

