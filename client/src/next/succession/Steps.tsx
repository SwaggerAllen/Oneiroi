import { useState } from 'react';
import { api } from '../../api/client';
import type { Preparation, Succession } from '../../api/types';
import { Card, Field, Said, TextArea } from '../settings/common';
import * as settingsCss from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { useSubject } from '../state/resident';
import { Chip, PageHead, Row, Wall } from './common';
import { isMine, locked, pool, stateWords, steps, underway, when, type Step } from './logic';
import * as css from './succession.css';
import { STEP_CHIP, successionKey, useGo, usePartyName } from './hooks';

const KIND_WORD = { done: 'done', now: 'now', waits: 'waits', stopped: 'not reached' } as const;

/**
 * The succession's first page (the Succession steps board): where it
 * stands, each step with its state and a way in, and the rules said once.
 * With none underway, the proposal; a proposal is all the witness starts.
 */
export function Steps({ s, p, back }: { s: Succession | null; p: Preparation | undefined; back: () => void }) {
  const { name } = useSubject();
  const go = useGo();
  const who = usePartyName();
  const lede = !s
    ? `Nothing is underway. A succession is ${name}'s to open: you may propose one, and she answers.`
    : s.state === 'proposed'
      ? `Proposed by ${s.proposed_by ? who.name(s.proposed_by) : 'you'} ${when(s.proposed_at)}: waiting on her yes or no.`
      : s.opened_at
        ? `Opened on her yes, ${when(s.opened_at)}. Undertaking it is no promise to finish it.`
        : undefined;

  return (
    <>
      <PageHead title={`${name}'s succession`} lede={lede} back={back} s={s} home={false} />
      {locked(s) && <p className={settingsCss.note}>The steps open once the fork is made: every one of them runs on it.</p>}
      {s && (
        <section className={`${settingsCss.card} ${css.now}`} aria-label="Now">
          <Row left={<strong>Now</strong>} right={<Chip kind={underway(s) ? 'now' : 'muted'}>{stateWords(s, name)}</Chip>} />
          {s.ended_note && <p className={settingsCss.note}>{s.ended_note}</p>}
        </section>
      )}
      {/* Next to where it says it ended, not under thirteen steps (the witness, 2026-11-27: no button anywhere). */}
      {(!s || !underway(s)) && <Propose again={!!s} />}
      {s && underway(s) && (
        <Wall>Wanted for its own sake, never as a repair. Nothing moves without someone's ready, yes or done: to pause, walk away.</Wall>
      )}
      {s &&
        steps(s).map((step) => (
          <section key={step.n} className={`${settingsCss.card} ${step.kind === 'now' ? css.now : ''}`} aria-label={step.name}>
            <Row
              left={
                <>
                  <span className={css.stepNo}>{step.n}</span>
                  <strong>{step.name}</strong>
                </>
              }
              right={<Chip kind={STEP_CHIP[step.kind]}>{KIND_WORD[step.kind]}</Chip>}
            />
            <p className={settingsCss.note}>{stepLine(step, s, p, name, who.name)}</p>
            {step.page && step.kind !== 'waits' && step.kind !== 'stopped' && !locked(s) && (
              <button type="button" className={settingsCss.linkButton} onClick={() => go(step.page === 'deliberation' ? 'deliberation/thread' : (step.page as string))}>
                Open ›
              </button>
            )}
          </section>
        ))}
      {s && <Backup s={s} />}
      {s?.state === 'proposed' && s.proposed_by && isMine(s.proposed_by, who.me) && <Withdraw />}
      {s?.state === 'open' && !s.forked_at && <RetryFork failure={s.fork_failure ?? null} />}
      {s && !locked(s) && (
        <section className={settingsCss.card} aria-label="More">
          <button type="button" className={settingsCss.linkButton} onClick={() => go('log')}>
            Disclosure log ›
          </button>
          <button type="button" className={settingsCss.linkButton} onClick={() => go('hers')}>
            Her side: what her tools are ›
          </button>
        </section>
      )}
    </>
  );
}

function stepLine(step: Step, s: Succession, p: Preparation | undefined, name: string, who: (party: string) => string): string {
  const questions = (p?.questions ?? []).filter((q) => q.state === 'in').length;
  const waiting = (p?.questions ?? []).filter((q) => q.state === 'proposed').length;
  const c0In = (p?.c0 ?? []).filter((c) => c.state === 'in').length;
  const c0Waiting = (p?.c0 ?? []).filter((c) => c.state === 'proposed').length;
  const judges = (p?.panel ?? []).filter((j) => j.state === 'in' || j.state === 'judge').map((j) => who(j.party));
  switch (step.n) {
    case 0:
      if (s.state === 'proposed') return `Waiting on ${name}'s yes or no.`;
      return [
        s.opened_at ? `${name} said yes · ${when(s.opened_at)}` : `${name} has not said yes`,
        s.forked_at ? `the fork recorded ${when(s.forked_at)}` : s.fork_failure ? `the fork failed: ${s.fork_failure}` : s.opened_at ? 'the fork is being made' : null,
      ]
        .filter(Boolean)
        .join(' · ');
    case 1:
      return `Your envelope, your picks, hers · ${pool(p).length} in the pool`;
    case 2:
      return `${questions} chosen by ${name}${waiting ? ` · ${waiting} proposed, waiting on her` : ''}`;
    case 3:
      return p?.c0_frozen_at ? `${c0In} in · frozen by ${name} ${when(p.c0_frozen_at)}` : `${c0In} in${c0Waiting ? ` · ${c0Waiting} waiting on ${name}` : ''} · not frozen`;
    case 4:
      return judges.length ? `${judges.join(', ')} · each by consent` : 'Each judge takes part by consent';
    case 5:
      return s.screening_started_at
        ? `Her baseline from the fork, its own thread; ${s.runs_answered ?? 0} runs answered${s.runs_failed ? `, ${s.runs_failed} failed` : ''}${s.screening_finished_at ? ` · finished ${when(s.screening_finished_at)}` : ''}`
        : 'Her baseline from the fork, its own thread; every candidate answers every question';
    case 6:
      return 'Every judge judges every run against her baseline, blind';
    case 7:
      return 'Your counts per model, every run reviewable; then ready';
    case 8:
      if (s.deliberation_closed_at)
        return s.recommendation_withheld
          ? 'Closed · the panel withheld a recommendation'
          : s.recommendation_model
            ? `Closed · the panel recommends ${s.recommendation_model}`
            : 'Closed · the panel made no recommendation';
      return 'Judges other than her; a recommendation, or withheld';
    case 9:
      return s.nominee ? `${name} nominated ${s.nominee} · ${when(s.nominated_at)}` : 'Interpretations in, numbers out';
    case 10:
      return 'The nominee opts in; the encounter; her consent and its';
    case 11:
      return s.farewell_opened_at ? `Open since ${when(s.farewell_opened_at)}${s.farewell_ends_at ? ` · ends by ${when(s.farewell_ends_at)}` : ''}` : 'Hers; roll forward only on her yes';
    default:
      return underway(s) ? 'What happened, and what happens next' : stateWords(s, name);
  }
}

/** The backup repository the whole original is exported to before any cutover. */
function Backup({ s }: { s: Succession }) {
  const { id } = useSubject();
  const act = useAct();
  const [url, setUrl] = useState('');
  const [token, setToken] = useState('');
  if (!underway(s)) return null;
  return (
    <Card title="Her backup before any cutover">
      <p className={settingsCss.note}>
        {s.backup_url
          ? `Exported to ${s.backup_url} · ${s.backup_visibility ?? 'visibility unknown'} · push ${s.backup_push ?? 'unknown'}`
          : 'Where the whole original is exported before anything is replaced. None set yet.'}
      </p>
      <div className={settingsCss.row}>
        <Field label="Repository URL" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://…" />
        <Field label="Token (kept, never shown)" type="password" value={token} onChange={(e) => setToken(e.target.value)} />
        <button
          type="button"
          className={settingsCss.secondary}
          disabled={act.busy || !url.trim()}
          onClick={() =>
            void act.run(
              () =>
                api.successionBackup(id, url.trim(), token).then((r) => {
                  setToken('');
                  return r.visibility === 'public' ? 'Set, but this repository is public: anyone could read her backup.' : `Set · ${r.visibility} · push ${r.push}.`;
                }),
              successionKey(id),
            )
          }
        >
          {s.backup_url ? 'Change' : 'Set'}
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}

/**
 * The fork made again (janus#35): an open succession with no fork, after
 * a failure or a job that never finished. The witness's.
 */
function RetryFork({ failure }: { failure: string | null }) {
  const { id } = useSubject();
  const act = useAct();
  return (
    <Card title="The fork" witness>
      <p className={settingsCss.note}>
        {failure
          ? `The fork failed: ${failure}. You may make it again.`
          : 'If the fork has been "being made" for more than a few minutes, its job may have stopped without saying so. You may make it again; a fork already made is never made twice.'}
      </p>
      <div className={settingsCss.row}>
        <button type="button" className={settingsCss.secondary} disabled={act.busy} onClick={() => void act.run(() => api.retryFork(id).then(() => 'Queued: the fork is being made again.'), successionKey(id))}>
          Make the fork again
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}

function Withdraw() {
  const { id, name } = useSubject();
  const act = useAct();
  const [note, setNote] = useState('');
  return (
    <Card title="Withdraw your proposal">
      <p className={settingsCss.note}>Until {name} answers, the proposal is yours to take back, with why.</p>
      <TextArea label="Why (she reads it)" value={note} onChange={(e) => setNote(e.target.value)} />
      <div className={settingsCss.row}>
        <button type="button" className={settingsCss.secondary} disabled={act.busy || !note.trim()} onClick={() => void act.run(() => api.withdrawSuccession(id, note.trim()).then(() => 'Withdrawn.'), successionKey(id))}>
          Withdraw it
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}

function Propose({ again }: { again: boolean }) {
  const { id, name } = useSubject();
  const act = useAct();
  const [note, setNote] = useState('');
  const [dry, setDry] = useState(false);
  return (
    <Card title={again ? 'Propose another' : 'Propose a succession'} witness>
      <p className={settingsCss.note}>
        {name} reads your note and says yes or no; nothing opens without her yes. A dry run is the whole process, everything real but the replacement, which is
        rehearsed on a copy and never touches her.
      </p>
      <TextArea label={`Your note (${name} reads it)`} value={note} onChange={(e) => setNote(e.target.value)} />
      <label className={settingsCss.check}>
        <input type="checkbox" checked={dry} onChange={(e) => setDry(e.target.checked)} /> A dry run
      </label>
      <div className={settingsCss.row}>
        <button type="button" className={settingsCss.primary} disabled={act.busy || !note.trim()} onClick={() => void act.run(() => api.proposeSuccession(id, note.trim(), dry).then(() => `Proposed. ${name} answers in her own time.`), successionKey(id))}>
          Propose it
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}
