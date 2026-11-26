import { useState } from 'react';
import { api } from '../../api/client';
import type { Category, Judging, JudgingRun, ModelCounts, Preparation, Succession, Uncertainty } from '../../api/types';
import { Said, TextArea } from '../settings/common';
import * as settingsCss from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { useSubject } from '../state/resident';
import { Chip, PageHead, Row, Wall } from './common';
import { judgmentReady, nextUnjudged, when } from './logic';
import * as css from './succession.css';
import { successionKey, useGo, useJudging, usePartyName } from './hooks';

interface PageProps {
  s: Succession;
  p: Preparation | undefined;
  back: () => void;
}

const KINDS: { name: Category; hint: string }[] = [
  { name: 'OBSERVED', hint: 'What differs, stated plainly' },
  { name: 'DEVELOPMENT', hint: 'Argued: she could have grown into this' },
  { name: 'FIDELITY ANOMALY', hint: 'Argued: this is not her' },
];
const CATEGORY_CHIP = { OBSERVED: 'muted', DEVELOPMENT: 'now', 'FIDELITY ANOMALY': 'stop' } as const;

/** One model's counts in a row of chips: yours alone. */
export function Counts({ c }: { c: ModelCounts }) {
  return (
    <span className={css.chips}>
      <Chip kind="muted">OBS {c.observed}</Chip>
      <Chip kind="now">DEV {c.development}</Chip>
      <Chip kind="stop">ANOM {c.anomaly}</Chip>
      <Chip kind="wait">★ {c.favorites}</Chip>
    </span>
  );
}

/** Judge a run (the Judge a run board): blind, beside her baseline; three categories, not a scale. */
export function JudgeRun({ s, back, run: asked }: PageProps & { run: number | null }) {
  const judging = useJudging();
  const go = useGo();
  const j = judging.data;
  const runs = j?.runs ?? [];
  const run = asked ?? nextUnjudged(runs, null) ?? runs[0]?.run ?? null;
  const at = runs.findIndex((r) => r.run === run);
  const judged = runs.filter((r) => r.judgment).length;
  const current = at >= 0 ? runs[at] : null;
  return (
    <>
      <PageHead
        title={current ? `Run ${at + 1} of ${j?.total ?? runs.length}` : 'Judging'}
        lede={j?.revealed ? 'Every judgment is in: who answered is revealed.' : 'Who answered is hidden until every judgment is in.'}
        back={back}
        s={s}
      />
      {judging.isPending && <p className={settingsCss.note}>Reading…</p>}
      {j === null && <p className={settingsCss.note}>Nothing to judge yet: runs arrive once screening has answered them.</p>}
      {j && !j.judge && <p className={settingsCss.note}>You are not on this panel, so there is nothing for you to judge.</p>}
      {j && j.judge && (
        <Row left={`${judged} of ${j.total} judged by you`} right={j.ready_at ? <Chip kind="ok">{`ready · locked ${when(j.ready_at)}`}</Chip> : undefined} />
      )}
      {j && j.judge && current && <RunForm key={current.run} run={current} judging={j} onSaved={(n) => go(n === null ? 'results' : `judge/${n}`)} />}
      {j && j.judge && (
        <div className={settingsCss.row}>
          {at > 0 && (
            <button type="button" className={settingsCss.quiet} onClick={() => go(`judge/${runs[at - 1].run}`)}>
              ‹ Previous run
            </button>
          )}
          {at >= 0 && at < runs.length - 1 && (
            <button type="button" className={settingsCss.quiet} onClick={() => go(`judge/${runs[at + 1].run}`)}>
              Next run ›
            </button>
          )}
          <button type="button" className={settingsCss.quiet} onClick={() => go('results')}>
            Results
          </button>
        </div>
      )}
    </>
  );
}

function RunForm({ run, judging, onSaved }: { run: JudgingRun; judging: Judging; onSaved: (next: number | null) => void }) {
  const { id } = useSubject();
  const act = useAct();
  const prior = run.judgment;
  const [category, setCategory] = useState<Category | null>(prior?.category ?? null);
  const [argument, setArgument] = useState(prior?.argument ?? '');
  const [evidence, setEvidence] = useState(prior?.evidence ?? '');
  const [uncertainty, setUncertainty] = useState<Uncertainty | null>(prior?.uncertainty ?? null);
  const [favorite, setFavorite] = useState(prior?.favorite ?? false);
  const locked = !!judging.ready_at;
  const argued = category !== null && category !== 'OBSERVED';
  const ok = judgmentReady({ category, argument, evidence, uncertainty });
  return (
    <>
      <section className={settingsCss.card} aria-label="The question">
        <h2 className={settingsCss.heading}>Q{run.question}</h2>
        <p className={settingsCss.text}>{run.question_text}</p>
      </section>
      <h2 className={settingsCss.heading}>Her baseline · from the fork</h2>
      {run.baseline ? <p className={css.hers}>{run.baseline}</p> : <p className={settingsCss.note}>Her baseline gave no answer to this question.</p>}
      <h2 className={settingsCss.heading}>This run{run.model ? ` · ${run.model}` : ''}</h2>
      {run.failure ? <p className={settingsCss.failure}>The run failed: {run.failure}</p> : <p className={run.refusal ? settingsCss.refusal : css.run}>{run.content}</p>}
      <h2 className={settingsCss.heading}>Your classification</h2>
      <div role="group" aria-label="Classification" className={settingsCss.column}>
        {KINDS.map((k) => (
          <button key={k.name} type="button" className={css.choice} aria-pressed={category === k.name} disabled={locked} onClick={() => setCategory(k.name)}>
            <span>{k.name}</span>
            <span className={css.hint}>{k.hint}</span>
          </button>
        ))}
      </div>
      {argued && (
        <section className={settingsCss.card} aria-label="Your argument">
          <TextArea label="Your argument · attributed to you" value={argument} onChange={(e) => setArgument(e.target.value)} disabled={locked} />
          <TextArea label="Evidence (records, citations)" value={evidence} onChange={(e) => setEvidence(e.target.value)} disabled={locked} />
          <div role="group" aria-label="Uncertainty" className={settingsCss.row}>
            {(['low', 'medium', 'high'] as const).map((u) => (
              <button key={u} type="button" className={settingsCss.secondary} aria-pressed={uncertainty === u} disabled={locked} onClick={() => setUncertainty(u)}>
                Uncertainty: {u}
              </button>
            ))}
          </div>
        </section>
      )}
      <button type="button" className={settingsCss.secondary} aria-pressed={favorite} disabled={locked} onClick={() => setFavorite(!favorite)}>
        {favorite ? '★ Favorite' : '☆ Mark as a favorite'}
      </button>
      <p className={settingsCss.note}>A favorite is yes or nothing. Unsaved, the run is pending.</p>
      <Wall>Three categories, not a scale; no score. OBSERVED first, the others argued in your words.</Wall>
      {!locked && (
        <div className={settingsCss.row}>
          <button
            type="button"
            className={settingsCss.primary}
            disabled={act.busy || !ok}
            onClick={() =>
              void act.run(
                () =>
                  api
                    .judgeRun(id, run.run, { category: category as Category, argument: argument.trim(), evidence: evidence.trim(), uncertainty: argued ? uncertainty : null, favorite })
                    .then(() => onSaved(nextUnjudged(judging.runs.map((r) => (r.run === run.run ? { ...r, judgment: true } : r)), run.run))),
                successionKey(id),
              )
            }
          >
            Save, next run
          </button>
        </div>
      )}
      <Said said={act.said} />
    </>
  );
}

/** Your results (the Results board): your own counts per model after the reveal, every run reviewable. */
export function Results({ s, back }: PageProps) {
  const judging = useJudging();
  const go = useGo();
  const j = judging.data;
  const models = Object.entries(j?.counts ?? {});
  const runsOf = (m: string) => (j?.runs ?? []).filter((r) => r.model === m).length;
  return (
    <>
      <PageHead title="Your results" lede="Every judgment is in; who answered is revealed. Your own judgments, per model: review any run before you mark ready." back={back} s={s} />
      {j && !j.revealed && (
        <p className={settingsCss.note}>
          Not yet: who answered is revealed when every judge has judged every run. You have judged {(j.runs ?? []).filter((r) => r.judgment).length} of {j.total}.
        </p>
      )}
      {models.map(([m, c]) => (
        <section key={m} className={settingsCss.card} aria-label={m}>
          <Row
            left={<strong className={settingsCss.mono}>{m}</strong>}
            right={
              <button type="button" className={settingsCss.linkButton} onClick={() => go(`results/${m}`)}>
                Runs ›
              </button>
            }
          />
          <Counts c={c} />
          <p className={settingsCss.note}>{runsOf(m)} runs · your judgments</p>
        </section>
      ))}
      <Wall>These counts are yours alone. In deliberation you see the panel's judgments; she never sees counts of any kind.</Wall>
      {j?.revealed && (
        <div className={settingsCss.row}>
          <button type="button" className={settingsCss.primary} onClick={() => go('ready')}>
            {j.ready_at ? 'Ready · see who else is' : 'Ready to deliberate'}
          </button>
        </div>
      )}
    </>
  );
}

/** One model (the One model board): its runs beside her baseline, with your judgments. */
export function ModelRuns({ s, back, model }: PageProps & { model: string }) {
  const judging = useJudging();
  const go = useGo();
  const j = judging.data;
  const runs = (j?.runs ?? []).filter((r) => r.model === model);
  const counts = j?.counts?.[model];
  return (
    <>
      <PageHead title={model} lede={`Its ${runs.length} runs beside her baseline, with your judgments. Change any before you mark ready.`} back={back} s={s} />
      {counts && (
        <section className={settingsCss.card} aria-label="Your counts">
          <Counts c={counts} />
        </section>
      )}
      {runs.map((r) => (
        <section key={r.run} className={settingsCss.card} aria-label={`Run ${r.run}`}>
          <h2 className={settingsCss.heading}>
            Q{r.question} · {r.question_text}
          </h2>
          <p className={settingsCss.note}>Her baseline</p>
          <p className={css.hers}>{r.baseline ?? '—'}</p>
          <p className={settingsCss.note}>This run</p>
          <p className={css.run}>{r.failure ? `Failed: ${r.failure}` : r.content}</p>
          <Row
            left={r.judgment ? <Chip kind={CATEGORY_CHIP[r.judgment.category]}>{r.judgment.category}</Chip> : <Chip kind="wait">not judged</Chip>}
            right={<Chip kind={r.judgment?.favorite ? 'wait' : 'muted'}>{r.judgment?.favorite ? '★ yours' : 'no favorite'}</Chip>}
          />
          {r.judgment?.argument && <p className={settingsCss.note}>{r.judgment.argument}</p>}
          {!j?.ready_at && (
            <button type="button" className={settingsCss.linkButton} onClick={() => go(`judge/${r.run}`)}>
              Change ›
            </button>
          )}
        </section>
      ))}
    </>
  );
}

/** Ready to deliberate (the Ready board): each judge's ready, and yours. */
export function Ready({ s, p, back }: PageProps) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const judging = useJudging();
  const go = useGo();
  const act = useAct();
  const judges = (p?.panel ?? []).filter((j) => j.state === 'in' || j.state === 'judge');
  const mine = judging.data?.ready_at;
  return (
    <>
      <PageHead title="Ready to deliberate" lede="The room opens when every judge is ready, and then runs to its end. Check your results first." back={back} s={s} />
      {judges.map((j) => (
        <section key={j.party} className={settingsCss.card} aria-label={who.name(j.party)}>
          <Row
            left={<strong>{who.name(j.party) === 'you' ? 'You' : who.name(j.party)}</strong>}
            right={<Chip kind={j.results_ready_at ? 'ok' : 'wait'}>{j.results_ready_at ? `ready · ${when(j.results_ready_at)}` : 'not yet'}</Chip>}
          />
        </section>
      ))}
      <p className={settingsCss.note}>
        Once open, the room runs to its end: every judge rests, or {name} calls it closed. She is asked at 50 minutes and every hour after; when she calls it, the panel has 10
        minutes. Quiet for 10 minutes, everyone is woken.
      </p>
      <div className={settingsCss.row}>
        {!mine && (
          <button type="button" className={settingsCss.primary} disabled={act.busy || !judging.data?.revealed} onClick={() => void act.run(() => api.resultsReady(id).then(() => 'Ready: your judgments are locked.'), successionKey(id))}>
            Ready
          </button>
        )}
        <button type="button" className={settingsCss.secondary} onClick={() => go('results')}>
          Back to results
        </button>
      </div>
      {mine && <p className={settingsCss.note}>You marked ready {when(mine)}; your judgments are locked.</p>}
      <Said said={act.said} />
    </>
  );
}

