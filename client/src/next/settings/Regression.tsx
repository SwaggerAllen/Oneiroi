import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import type { Grade, RegressionCard, RegressionResult, RegressionRun, RegressionRunDetail, RegressionTest, TestTexts, TraceStep } from '../../api/types';
import { joinRun } from '../../app/socket';
import { byTrial } from '../../screens/regression/deck';
import { argumentsText, plural, saidOf, settingsKey, trialCount, withCard } from './logic';
import { useSubject } from '../state/resident';
import { Card, Said, TextArea } from './common';
import * as css from './settings.css';
import { useAct } from './useAct';

const BLANK: TestTexts = { prompt: '', passes_if: '', fails_if: '' };

/**
 * Regression (spec §6.4, §10): trials as three texts, with "Suggest some"
 * from her files (agathos-daimon#42); runs of models over the trials,
 * answered in the background with cards arriving live (eunomia#30); each
 * card blind until every answer to its trial is graded; results by pass
 * rate and the pin. Grades are yours alone; she is never shown any of it.
 */
export function Regression() {
  const { id } = useSubject();
  const [view, setView] = useState<'trials' | 'runs'>('trials');
  const [open, setOpen] = useState<string | null>(null);
  const tests = useQuery({
    queryKey: settingsKey(id, 'regression', 'tests'),
    queryFn: () => api.regressionTests(id),
  });
  const runs = useQuery({
    queryKey: settingsKey(id, 'regression', 'runs'),
    queryFn: () => api.regressionRuns(id),
  });
  const trials = tests.data ?? [];

  if (open) return <RunView runRef={open} tests={trials} onClose={() => setOpen(null)} />;
  return (
    <>
      <div className={css.row} role="group" aria-label="Regression views">
        <button type="button" className={css.secondary} aria-pressed={view === 'trials'} onClick={() => setView('trials')}>
          Trials · {trials.length}
        </button>
        <button type="button" className={css.secondary} aria-pressed={view === 'runs'} onClick={() => setView('runs')}>
          Runs · {runs.data?.length ?? 0}
        </button>
      </div>
      {view === 'trials' ? <Trials tests={trials} pending={tests.isPending} /> : <Runs tests={trials} runs={runs.data ?? []} onOpen={setOpen} onStarted={(ref) => setOpen(ref)} />}
    </>
  );
}

// ---- trials ----

function Trials({ tests, pending }: { tests: RegressionTest[]; pending: boolean }) {
  const { id, name } = useSubject();
  const act = useAct();
  const [editing, setEditing] = useState<number | null>(null);
  const [draft, setDraft] = useState<TestTexts>(BLANK);
  const [note, setNote] = useState('');
  const [kept, setKept] = useState<string[]>([]);
  const suggest = useMutation({
    mutationFn: () => api.suggestTrials(id, note.trim()),
  });

  return (
    <>
      <Card title="Write a trial">
        <p className={css.note}>Something to say to {name}, what passes as an answer, and what fails.</p>
        <TrialForm
          key={draft === BLANK ? 'blank' : draft.prompt}
          initial={draft}
          submit="Add the trial"
          busy={act.busy}
          onSubmit={(t) => {
            setDraft(BLANK);
            void act.run(() => api.writeTest(id, t).then((r) => `Added as trial #${r.number}.`));
          }}
        />
        <Said said={act.said} />
      </Card>

      <Card title="Suggest some">
        <p className={css.note}>Trials drafted from {name}'s files so far. None is kept until you keep it.</p>
        <div className={css.row}>
          <input
            className={css.input}
            style={{ flex: '1 1 220px' }}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="What should a new model have to keep? (optional)"
            aria-label="What should a new model have to keep"
          />
          <button type="button" className={css.secondary} disabled={suggest.isPending} onClick={() => suggest.mutate()}>
            {suggest.isPending ? 'Suggesting…' : 'Suggest some'}
          </button>
        </div>
        {suggest.error && <p className={css.refused}>{saidOf(suggest.error)}</p>}
        {suggest.data?.trials.map((t, i) => (
          <div key={i} className={css.answer}>
            <p className={css.voice}>“{t.prompt}”</p>
            <p className={css.note}>Passes if {t.passes_if}</p>
            {t.fails_if && <p className={css.note}>Fails if {t.fails_if}</p>}
            <div className={css.row}>
              <button
                type="button"
                className={css.secondary}
                disabled={kept.includes(t.prompt) || act.busy}
                onClick={() =>
                  void act.run(() =>
                    api.writeTest(id, t).then((r) => {
                      setKept((k) => [...k, t.prompt]);
                      return `Kept as trial #${r.number}.`;
                    }),
                  )
                }
              >
                {kept.includes(t.prompt) ? 'Kept' : 'Keep this trial'}
              </button>
              <button type="button" className={css.quiet} onClick={() => setDraft(t)}>
                Edit it first
              </button>
            </div>
          </div>
        ))}
      </Card>

      {pending && <p className={css.note}>Reading…</p>}
      {!pending && tests.length === 0 && <p className={css.note}>No trials yet.</p>}
      {tests.map((t) => (
        <Card key={t.number} title={`Trial #${t.number}`}>
          {editing === t.number ? (
            <TrialForm
              initial={t}
              submit="Save the change"
              busy={act.busy}
              onCancel={() => setEditing(null)}
              onSubmit={(texts) => {
                setEditing(null);
                void act.run(() => api.changeTest(id, t.number, texts).then(() => `Trial #${t.number} changed.`));
              }}
            />
          ) : (
            <>
              <div className={css.three}>
                <Labelled label="What you say">{t.prompt}</Labelled>
                <Labelled label="Passes if">{t.passes_if}</Labelled>
                <Labelled label="Fails if">{t.fails_if}</Labelled>
              </div>
              <div>
                <button type="button" className={css.quiet} onClick={() => setEditing(t.number)}>
                  Edit
                </button>
              </div>
            </>
          )}
        </Card>
      ))}
    </>
  );
}

function Labelled({ label, children }: { label: string; children: string }) {
  return (
    <div className={css.column} style={{ gap: 4 }}>
      <span className={css.meta}>{label.toUpperCase()}</span>
      <p className={css.text} style={{ whiteSpace: 'pre-wrap' }}>
        {children}
      </p>
    </div>
  );
}

function TrialForm({ initial, submit, busy, onSubmit, onCancel }: { initial: TestTexts; submit: string; busy: boolean; onSubmit: (t: TestTexts) => void; onCancel?: () => void }) {
  const { name } = useSubject();
  const [t, setT] = useState<TestTexts>({
    prompt: initial.prompt,
    passes_if: initial.passes_if,
    fails_if: initial.fails_if,
  });
  const complete = t.prompt.trim() !== '' && t.passes_if.trim() !== '' && t.fails_if.trim() !== '';
  return (
    <form
      className={css.column}
      onSubmit={(e) => {
        e.preventDefault();
        if (!complete) return;
        onSubmit(t);
        setT(BLANK);
      }}
    >
      <div className={css.three}>
        <TextArea rows={4} label={`What you say to ${name}`} value={t.prompt} onChange={(e) => setT({ ...t, prompt: e.target.value })} />
        <TextArea rows={4} label="Passes if" value={t.passes_if} onChange={(e) => setT({ ...t, passes_if: e.target.value })} />
        <TextArea rows={4} label="Fails if" value={t.fails_if} onChange={(e) => setT({ ...t, fails_if: e.target.value })} />
      </div>
      <div className={css.row}>
        <button type="submit" className={css.primary} disabled={!complete || busy}>
          {submit}
        </button>
        {onCancel && (
          <button type="button" className={css.quiet} onClick={onCancel}>
            Cancel
          </button>
        )}
      </div>
    </form>
  );
}

// ---- runs ----

function stamp(iso: string) {
  return iso.slice(0, 16).replace('T', ' ');
}

function StateWord({ run }: { run: RegressionRun }) {
  if (run.state === 'running') return <span className={css.warn}>answering</span>;
  if (run.state === 'failed') return <span className={css.warn}>stopped before the end</span>;
  return <span>finished</span>;
}

function Runs({ tests, runs, onOpen, onStarted }: { tests: RegressionTest[]; runs: RegressionRun[]; onOpen: (ref: string) => void; onStarted: (ref: string) => void }) {
  return (
    <>
      <StartRun tests={tests} onStarted={onStarted} />
      <Card title="Runs">
        {runs.length === 0 && <p className={css.note}>No runs yet.</p>}
        <ul className={css.list} aria-label="Runs">
          {runs.map((run) => (
            <li key={run.ref} className={css.line}>
              <span className={css.column} style={{ gap: 2 }}>
                <span>
                  {plural(run.models.length, 'model')} over {plural(trialCount(run), 'trial')}
                </span>
                <span className={css.meta}>
                  {stamp(run.started_at)} · {plural(run.cards, 'answer')} · <StateWord run={run} />
                </span>
              </span>
              <button type="button" className={css.secondary} onClick={() => onOpen(run.ref)}>
                Open
              </button>
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}

function StartRun({ tests, onStarted }: { tests: RegressionTest[]; onStarted: (ref: string) => void }) {
  const { id, name } = useSubject();
  const act = useAct();
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
      <p className={css.note}>
        Each model answers each trial once, on your key, as {name} would in a new conversation, with the memory and the tools, and nothing written in it kept. The answers come in
        while you watch, and you can leave and come back.
      </p>
      <div className={css.row}>
        <label className={css.field}>
          <span>Models to try, by their OpenRouter name</span>
          <input
            className={css.input}
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
        </label>
        <button type="button" className={css.secondary} onClick={add} disabled={draft.trim() === ''}>
          Add
        </button>
      </div>
      {models.length > 0 && (
        <ul className={css.chips} aria-label="Models in this run">
          {models.map((m) => (
            <li key={m} className={css.chip}>
              {m}
              <button type="button" className={css.quiet} aria-label={`Remove ${m}`} onClick={() => setModels(models.filter((x) => x !== m))}>
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
      <fieldset className={css.column} style={{ border: 'none', margin: 0, padding: 0 }}>
        <legend className={css.note}>Which trials</legend>
        <label className={css.check}>
          <input type="radio" name="which-trials" checked={which === 'all'} onChange={() => setWhich('all')} />
          Every trial ({tests.length})
        </label>
        <label className={css.check}>
          <input type="radio" name="which-trials" checked={which === 'some'} onChange={() => setWhich('some')} />
          Only some
        </label>
        {which === 'some' &&
          tests.map((t) => (
            <label key={t.number} className={css.check} style={{ paddingLeft: 24 }}>
              <input
                type="checkbox"
                checked={chosen.includes(t.number)}
                onChange={(e) => setChosen(e.target.checked ? [...chosen, t.number] : chosen.filter((n) => n !== t.number))}
              />
              <span>
                #{t.number} {t.prompt.length > 60 ? `${t.prompt.slice(0, 60)}…` : t.prompt}
              </span>
            </label>
          ))}
      </fieldset>
      <div>
        <button
          type="button"
          className={css.primary}
          disabled={!ready || act.busy}
          onClick={() =>
            void act.run(() =>
              api.startRun(id, models, which === 'all' ? 'all' : [...chosen].sort((a, b) => a - b)).then(({ ref }) => {
                onStarted(ref);
              }),
            )
          }
        >
          Start the run
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}

// ---- a run ----

function RunView({ runRef, tests, onClose }: { runRef: string; tests: RegressionTest[]; onClose: () => void }) {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const key = settingsKey(id, 'regression', 'run', runRef);
  const detail = useQuery({
    queryKey: key,
    queryFn: () => api.regressionRun(id, runRef),
  });
  const act = useAct();
  const running = detail.data?.run.state === 'running';

  // A run still answering is watched on its channel (eunomia#30): each
  // card joins the deck as it is recorded, and the end reads it again.
  // The join reads it once more, for any card recorded before it.
  useEffect(() => {
    if (!running) return;
    let leave: () => void = () => undefined;
    let gone = false;
    const reread = () =>
      void queries.invalidateQueries({
        queryKey: ['resident', id, 'settings', 'regression'],
      });
    api
      .socketToken()
      .then(({ token }) => {
        if (gone) return;
        leave = joinRun(token, id, runRef, {
          onJoined: reread,
          onCard: (card) => queries.setQueryData<RegressionRunDetail>(key, (d) => withCard(d, runRef, card)),
          onFinished: reread,
        });
      })
      .catch(() => undefined);
    return () => {
      gone = true;
      leave();
    };
    // `key` is derived from id and runRef.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, runRef, running, queries]);

  if (!detail.data) {
    return (
      <>
        <button type="button" className={css.back} onClick={onClose}>
          ‹ All runs
        </button>
        <p className={detail.error ? css.refused : css.note}>{detail.error ? saidOf(detail.error) : 'Reading the run…'}</p>
      </>
    );
  }
  const { run, cards, results } = detail.data;
  const prompts = new Map(tests.map((t) => [t.number, t.prompt]));
  const graded = cards.filter((c) => c.grade !== null).length;
  const expected = run.models.length * trialCount(run);
  const progress =
    run.state === 'running'
      ? `Answering: ${cards.length} of ${expected} in, ${graded} graded`
      : run.state === 'failed'
        ? `Stopped before the end: ${plural(cards.length, 'answer')} kept, ${graded} graded`
        : `Finished: ${plural(cards.length, 'answer')}, ${graded} graded`;
  const grade = (card: string, g: Grade) => void act.run(() => api.grade(id, runRef, card, g));
  const favourite = (card: string) => void act.run(() => api.favourite(id, runRef, card));

  return (
    <>
      <button type="button" className={css.back} onClick={onClose}>
        ‹ All runs
      </button>
      <h2 className={css.subheading}>Run of {stamp(run.started_at)}</h2>
      <p aria-live="polite" className={run.state === 'failed' ? `${css.meta} ${css.warn}` : css.meta}>
        {progress}
        {run.state === 'failed' && run.failure ? ` · ${run.failure}` : ''}
      </p>
      <Said said={act.said} />
      {results.length > 0 && <Results results={results} />}
      {cards.length === 0 && <p className={css.note}>{run.state === 'running' ? 'The first answers are on their way.' : 'This run recorded no answers.'}</p>}
      {byTrial(cards).map(({ key: k, label, cards: deck }) => {
        const prompt = deck[0].test_number !== null ? prompts.get(deck[0].test_number) : undefined;
        return (
          <Card key={k} title={label.replace('Test', 'Trial')}>
            {prompt && <p className={css.note}>You said: {prompt}</p>}
            {deck.map((card, i) => (
              <article key={card.card_ref} className={css.answer} aria-label={`Answer ${i + 1}`}>
                <div className={css.line} style={{ borderTop: 'none', padding: 0 }}>
                  <span className={css.meta}>ANSWER {i + 1}</span>
                  {card.model ? (
                    <span className={css.mono}>{card.model}</span>
                  ) : (
                    <span className={css.note}>Who answered stays hidden until every answer to this trial is graded</span>
                  )}
                </div>
                <Answer card={card} />
                <Trace name={name} trace={card.trace} />
                <div className={css.row}>
                  <button type="button" className={css.secondary} aria-pressed={card.grade === 'pass'} disabled={act.busy} onClick={() => grade(card.card_ref, 'pass')}>
                    Passes
                  </button>
                  <button type="button" className={css.secondary} aria-pressed={card.grade === 'fail'} disabled={act.busy} onClick={() => grade(card.card_ref, 'fail')}>
                    Fails
                  </button>
                  <button type="button" className={css.quiet} aria-pressed={card.favourite} disabled={card.favourite || act.busy} onClick={() => favourite(card.card_ref)}>
                    {card.favourite ? '★ A favourite' : '☆ Favourite'}
                  </button>
                </div>
              </article>
            ))}
          </Card>
        );
      })}
    </>
  );
}

// Three kinds, kept apart: an answer in the voice serif; a refusal is its
// words too, never styled as a failure (conventions §8); a failure is no
// answer at all, said plainly.
function Answer({ card }: { card: RegressionCard }) {
  if (card.failure !== null) {
    return (
      <div className={css.failure}>
        No answer came back. <span className={css.mono}>{card.failure}</span>
      </div>
    );
  }
  if (card.refusal) {
    return (
      <div className={css.column} style={{ gap: 4 }}>
        <span className={css.note}>Declined, in its own words</span>
        <div className={css.refusal}>{card.content}</div>
      </div>
    );
  }
  return <p className={css.voice}>{card.content}</p>;
}

// How the answer was reached (eunomia#31), collapsed under it. Nothing
// shows for an empty trace: that is also every card from before traces.
function Trace({ name, trace }: { name: string; trace: TraceStep[] }) {
  if (trace.length === 0) return null;
  const heading = `How ${name} got there`;
  return (
    <details className={css.trace}>
      <summary className={css.note} style={{ cursor: 'pointer' }}>
        {heading} · {plural(trace.length, 'step')}
      </summary>
      <p className={css.note}>A read looked at {name}'s own records. A mocked step would have changed something: it was answered as if done, and nothing was kept.</p>
      <ol className={css.list} aria-label={heading}>
        {trace.map((step, i) => (
          <li key={i} className={css.item} aria-label={`Step ${i + 1}: ${step.tool}`}>
            <span className={css.row} style={{ alignItems: 'center' }}>
              <span className={css.meta}>{i + 1}.</span>
              <span className={css.mono}>{step.tool}</span>
              <span className={css.marker} data-mocked={step.kind === 'mocked'}>
                {step.kind === 'read' ? 'read' : 'mocked'}
              </span>
            </span>
            <pre className={css.pre}>{argumentsText(step.arguments)}</pre>
            <details>
              <summary className={css.note} style={{ cursor: 'pointer' }}>
                {step.truncated ? 'What came back, cut short here' : 'What came back'}
              </summary>
              <pre className={css.pre}>{step.result}</pre>
              {step.truncated && <p className={`${css.note} ${css.warn}`}>Cut here for this card. {name} was given all of it.</p>}
            </details>
          </li>
        ))}
      </ol>
    </details>
  );
}

function Results({ results }: { results: RegressionResult[] }) {
  const { id } = useSubject();
  const residents = useQuery({
    queryKey: ['residents'],
    queryFn: api.residents,
  });
  const chatModel = residents.data?.find((r) => r.id === id)?.chat_model ?? null;
  const [asking, setAsking] = useState<string | null>(null);
  const act = useAct();
  return (
    <Card title="Results" witness>
      <p className={css.note}>Over the trials graded in full, best first.</p>
      <div style={{ overflowX: 'auto' }}>
        <table className={css.table}>
          <thead>
            <tr>
              <th className={css.th}>model</th>
              <th className={css.th}>passed</th>
              <th className={css.th}>favourites</th>
              <th className={css.th} />
            </tr>
          </thead>
          <tbody>
            {results.map((r) => (
              <tr key={r.model}>
                <td className={css.td}>
                  <span className={css.mono}>{r.model}</span>
                </td>
                <td className={css.td}>
                  {Math.round(r.pass_rate * 100)}%{' '}
                  <span className={css.note}>
                    ({r.passed} of {r.graded})
                  </span>
                </td>
                <td className={`${css.td} ${css.mono}`}>{r.favourites}</td>
                <td className={css.td} style={{ textAlign: 'right' }}>
                  {r.model === chatModel ? (
                    <span className={css.note}>✓ The chat model now</span>
                  ) : asking === r.model ? (
                    // Two taps on purpose: the pin changes who answers in the
                    // conversation. The second is a question with both answers.
                    <span
                      role="group"
                      aria-label={`Pin ${r.model} for chat?`}
                      className={css.row}
                      style={{
                        justifyContent: 'flex-end',
                        alignItems: 'center',
                      }}
                    >
                      <span className={css.note}>Chat on this model from the next message?</span>
                      <button
                        type="button"
                        className={css.primary}
                        disabled={act.busy}
                        onClick={() => {
                          setAsking(null);
                          void act.run(() => api.pinModel(id, r.model).then(() => `Pinned: ${r.model} answers from the next message.`), ['residents']);
                        }}
                      >
                        Yes, pin it
                      </button>
                      <button type="button" className={css.quiet} onClick={() => setAsking(null)}>
                        Cancel
                      </button>
                    </span>
                  ) : (
                    <button type="button" className={css.secondary} onClick={() => setAsking(r.model)}>
                      Pin for chat
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Said said={act.said} />
    </Card>
  );
}
