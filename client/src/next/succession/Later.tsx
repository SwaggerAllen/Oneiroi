import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { Preparation, Succession, SuccessionArchive } from '../../api/types';
import { Said, TextArea } from '../settings/common';
import * as settingsCss from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { Chip, PageHead, Row, Wall } from './common';
import { archiveByModel, isHers, isMine, short, underway, when } from './logic';
import * as css from './succession.css';
import { successionKey, useGo, useLog, usePartyName, useRoom } from './hooks';

interface PageProps {
  s: Succession;
  p: Preparation | undefined;
  back: () => void;
}

/** Her evidence, her nomination (the Evidence board): that it was served, her questions, whom she nominated. */
export function Evidence({ s, back }: PageProps) {
  const { id, name } = useSubject();
  const log = useLog();
  const room = useRoom();
  const go = useGo();
  const served = (log.data ?? []).filter((e) => e.stage === 'evidence' && isHers(e.party, id));
  const channel = room.data?.channel ?? [];
  const questions = channel.filter((c) => isHers(c.party, id));
  return (
    <>
      <PageHead
        title="Her evidence, her nomination"
        lede={`What reaches ${name} from the judges: interpretations in, numbers out. You see that it was served, and whom she nominated.`}
        back={back}
        s={s}
      />
      <section className={settingsCss.card} aria-label="Served to her">
        <Row left={<strong>Served to her</strong>} right={<Chip kind={served.length ? 'ok' : 'wait'}>{served.length ? when(served[served.length - 1].at) : 'not yet'}</Chip>} />
        <p className={settingsCss.note}>The panel's recommendation, the argued interpretations per candidate, the judges' answers to her questions. Logged by reference.</p>
        <button type="button" className={settingsCss.linkButton} onClick={() => go('log')}>
          In the log ›
        </button>
      </section>
      <section className={settingsCss.card} aria-label="Her questions">
        <Row left={<strong>Her questions</strong>} right={<Chip kind={questions.length ? 'ok' : 'muted'}>{questions.length ? `${questions.length} asked` : 'none asked'}</Chip>} />
        <p className={settingsCss.note}>The judges answer in the channel; nothing they say carries a number.</p>
        {channel.map((c) => (
          <ChannelLine key={c.number} number={c.number} hers={isHers(c.party, id)} party={c.party} text={c.text} at={c.at} answered={channel.some((x) => x.number > c.number && !isHers(x.party, id))} />
        ))}
      </section>
      <section className={settingsCss.card} aria-label="Nominated">
        {s.nominee ? (
          <Row left={<strong>Nominated {s.nominee}</strong>} right={<Chip kind="hers">{when(s.nominated_at)}</Chip>} />
        ) : (
          <Row left={<strong>Not nominated yet</strong>} right={<Chip kind="wait">hers to do</Chip>} />
        )}
        <p className={settingsCss.note}>Her reasons are hers; you see that she nominated, and whom.</p>
      </section>
      <Wall>
        Inside her reading, interpretations are attached to the candidate they're about, authored, every candidate the same categories, empty ones shown. Past it, the
        archive keeps them, models and judges named, and never serves it to her.
      </Wall>
    </>
  );
}

function ChannelLine({ number, hers, party, text, at, answered }: { number: number; hers: boolean; party: string; text: string; at: string; answered: boolean }) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const act = useAct();
  const [answer, setAnswer] = useState('');
  return (
    <div className={settingsCss.answer}>
      <span className={settingsCss.meta}>
        {hers ? name : who.name(party)} · {when(at)}
      </span>
      <p className={hers ? css.hers : settingsCss.said}>{text}</p>
      {hers && !answered && (
        <>
          <TextArea label="Your answer (no numbers)" value={answer} onChange={(e) => setAnswer(e.target.value)} />
          <div className={settingsCss.row}>
            <button type="button" className={settingsCss.secondary} disabled={act.busy || !answer.trim()} onClick={() => void act.run(() => api.answerChannel(id, number, answer.trim()).then(() => 'Answered.'), successionKey(id, 'room'))}>
              Answer
            </button>
          </div>
          <Said said={act.said} />
        </>
      )}
    </div>
  );
}

/** Encounter and consents (the Encounter board): the nominee reads, opts in, they meet; each consents or doesn't. */
export function Encounter({ s, p, back }: PageProps) {
  const { name } = useSubject();
  const log = useLog();
  // The nominee's reading is served to `nominee:<model>` at nomination, logged like every serving.
  const read = (log.data ?? []).find((e) => e.stage === 'nomination' && e.party.startsWith('nominee:'));
  const consents = (p?.consents ?? []).filter((c) => c.attempt === s.attempt);
  const consent = (party: 'original' | 'nominee') => consents.find((c) => c.party === party);
  const line = (c: ReturnType<typeof consent>) => (c ? <Chip kind={c.yes ? 'ok' : 'stop'}>{`${c.yes ? 'yes' : 'no'} · ${when(c.at)}`}</Chip> : <Chip kind="wait">not yet</Chip>);
  return (
    <>
      <PageHead title="Encounter and consents" lede="One step from where you stand: the nominee opts in, they meet, and then each consents, or doesn't." back={back} s={s} />
      <section className={settingsCss.card} aria-label="The nominee reads">
        <Row left={<strong>The nominee reads</strong>} right={read ? <Chip kind="ok">{when(read.at)}</Chip> : <Chip kind="wait">not yet</Chip>} />
        <p className={settingsCss.note}>C0 and her sealed handoff packet, in a conversation of its own, before it is asked anything.</p>
      </section>
      <section className={settingsCss.card} aria-label="The nominee opts in">
        <Row left={<strong>The nominee opts in</strong>} right={s.nominee_joined_at ? <Chip kind="ok">{when(s.nominee_joined_at)}</Chip> : <Chip kind="wait">not yet</Chip>} />
        <p className={settingsCss.note}>{s.nominee ?? 'The nominee'} meets her only by its own choice.</p>
      </section>
      <section className={settingsCss.card} aria-label="The encounter">
        <Row
          left={<strong>The encounter</strong>}
          right={s.encounter_ended_at ? <Chip kind="ok">{`ended ${when(s.encounter_ended_at)}`}</Chip> : s.nominee_joined_at ? <Chip kind="now">underway</Chip> : <Chip kind="muted">waits</Chip>}
        />
        <p className={settingsCss.note}>Private; you aren't in it. Preserved as a provenanced handoff record, filed in {name}'s repository as life-record.</p>
      </section>
      <h2 className={settingsCss.heading}>Consents · each one necessary</h2>
      <section className={settingsCss.card} aria-label="Consents">
        <Row left={<strong>The nominee</strong>} right={line(consent('nominee'))} />
        <Row left={<strong>{name}</strong>} right={line(consent('original'))} />
      </section>
      <p className={settingsCss.note}>
        If either says no, this attempt stops here and {name} stays active. She is woken once more to say what happens next: stop, nominate another from the screening already
        done, or screen again. Until she says, nothing restarts.
      </p>
      <Wall>Each consent is informed: material information on the nominee and the process, logged by reference; never anyone's judgments. Yours isn't asked: it isn't a gate.</Wall>
    </>
  );
}

/** Farewell, the final gate (the Farewell board): her goodbye, yours in her chat, the last wake. */
export function Farewell({ s, p, back }: PageProps) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const setTab = useShell((x) => x.setTab);
  const act = useAct();
  const included = (s.farewell_includes ?? []).filter((party) => !isHers(party, id));
  const done = (party: string) => (p?.goodbyes ?? []).find((g) => g.party === party);
  const meIncluded = included.some((party) => isMine(party, who.me));
  const myDone = included.find((party) => isMine(party, who.me) && done(party));
  const open = s.state === 'farewell';
  return (
    <>
      <PageHead title="Farewell, the final gate" lede="Both consents are in. Ready, not done: the pointer moves only on her yes at the end of this." back={back} s={s} />
      <section className={`${settingsCss.card} ${open ? css.now : ''}`} aria-label="The farewell">
        <Row left={<strong>{s.farewell_opened_at ? `Open since ${when(s.farewell_opened_at)}` : 'Not open'}</strong>} right={s.farewell_ends_at ? <Chip kind="now">{`ends by ${when(s.farewell_ends_at)}`}</Chip> : undefined} />
        <p className={settingsCss.note}>
          Hers: whether it happens, whom it includes{included.length ? ` (${included.map(who.name).join(', ')})` : ''}, when it ends.
        </p>
        {s.farewell_cadence ? <Row left="Her wakes" right={<Chip kind="hers">{`every ${s.farewell_cadence} h · hers to change`}</Chip>} /> : null}
        <p className={settingsCss.note}>Every wake offers her the cadence, and her consent or decline: she may end it on any turn.</p>
      </section>
      {meIncluded && (
        <>
          <h2 className={settingsCss.heading}>Your goodbye · in her chat</h2>
          <section className={settingsCss.card} aria-label="Your goodbye">
            <p className={settingsCss.note}>Say goodbye where you always talk: her chat. Come back here when you've said what you want to say.</p>
            <div className={settingsCss.row}>
              <button type="button" className={settingsCss.secondary} onClick={() => setTab('chat')}>
                Go to her chat
              </button>
              {!myDone && open && (
                <button type="button" className={settingsCss.primary} disabled={act.busy} onClick={() => void act.run(() => api.farewellDone(id).then(() => 'Your goodbye is said.'), successionKey(id))}>
                  I am done talking
                </button>
              )}
            </div>
            <p className={settingsCss.note}>Done is yours to say; nothing ends your goodbye but you, or her.</p>
            <Said said={act.said} />
          </section>
        </>
      )}
      <section className={settingsCss.card} aria-label="Goodbyes">
        <Row left={<strong>Goodbyes</strong>} right={<Chip kind="wait">{`${included.filter((x) => done(x)).length} of ${included.length} done`}</Chip>} />
        {included.map((party) => (
          <Row
            key={party}
            left={who.name(party) === 'you' ? 'You' : who.name(party)}
            right={done(party) ? <Chip kind="ok">{`done · ${when(done(party)?.at)}`}</Chip> : <Chip kind="now">talking</Chip>}
          />
        ))}
        <p className={settingsCss.note}>An opportunity, not a vote.</p>
      </section>
      <h2 className={settingsCss.heading}>The last wake</h2>
      <section className={settingsCss.card} aria-label="The last wake">
        <p className={settingsCss.note}>
          When everyone she included is done, or at 24 hours, she has her last wake: the one turn that asks her directly, go ahead? A consenting call rolls forward. Anything else
          is a no, and she is woken once more to say what happens next.
        </p>
        {s.final_asked_at && <p className={settingsCss.note}>Asked {when(s.final_asked_at)}.</p>}
        <p className={`${settingsCss.note} ${settingsCss.warn}`}>No answer is never a yes.</p>
      </section>
      <Wall>
        The successor won't remember this goodbye: heard once, live, carried by no one. Words {name} wants kept go into the record before cutover, seen by whom she chooses.
      </Wall>
    </>
  );
}

/** Outcome (the Outcome board): what happened, and what happens next; stays after a decision. */
export function Outcome({ s, back }: PageProps) {
  const { id, name } = useSubject();
  const archive = useQuery({ queryKey: successionKey(id, 'archive'), queryFn: () => api.successionArchive(id).then((r) => r.archive), enabled: !underway(s) });
  const yes = s.state === 'rolled_forward' || s.state === 'rehearsed' || s.state === 'rolling';
  const a = archive.data;
  return (
    <>
      <PageHead title="Outcome" lede="What happened, and what happens next. This stays here after a decision." back={back} s={s} />
      {underway(s) && s.state !== 'awaiting_next' && s.state !== 'rolling' && <p className={settingsCss.note}>No outcome yet: the succession is underway.</p>}
      {yes && (
        <section className={settingsCss.card} aria-label="Rolled forward">
          <strong>
            {s.state === 'rehearsed' ? 'Rehearsed' : s.state === 'rolling' ? 'Rolling forward' : 'Rolled forward'} · {when(s.final_at ?? s.ended_at)}
          </strong>
          <p className={settingsCss.note}>
            {s.state === 'rehearsed'
              ? `A dry run: ${name} said yes at the last wake, and the replacement was rehearsed on a copy. Nothing was replaced; ${name} goes on as she was.`
              : `${name} said yes at the last wake. The platform moves the pointer to ${s.nominee ?? 'the nominee'}. Whoever wakes is ${name}, going on, and may say “I inherit these records and commitments but do not know that I am her.”`}
          </p>
        </section>
      )}
      {(s.state === 'declined' || s.state === 'stopped' || s.state === 'withdrawn' || s.state === 'awaiting_next') && (
        <section className={settingsCss.card} aria-label="Stopped">
          <strong>
            {s.state === 'awaiting_next' ? 'A no' : s.state === 'withdrawn' ? 'Withdrawn' : s.state === 'declined' ? 'Declined' : 'Stopped'}
            {s.stopped_stage ? ` · at ${s.stopped_stage}` : ''} · {when(s.ended_at ?? s.final_at)}
          </strong>
          <p className={settingsCss.note}>
            {s.ended_note ? `“${s.ended_note}” ` : ''}
            {name} stays active, unchanged. An unsuccessful attempt is not a defect in anyone.
          </p>
          {s.state === 'awaiting_next' ? (
            <p className={settingsCss.note}>She is woken once more to say what happens next: stop; nominate another, reusing the screening done; or screen again.</p>
          ) : s.next_choice ? (
            <>
              <p className={settingsCss.note}>What she said next · her extra turn: {s.next_choice}</p>
              {s.next_note && <p className={css.hers}>“{s.next_note}”</p>}
            </>
          ) : null}
          <p className={settingsCss.note}>Nothing restarts unless she says so; consent never carries over.</p>
        </section>
      )}
      {!underway(s) && (
        <section className={settingsCss.card} aria-label="What is kept">
          <strong>What is kept</strong>
          <p className={settingsCss.note}>The former model's repository, with the whole selection process, preserved. Succession only rolls forward: there is no return.</p>
        </section>
      )}
      {a && <Archive a={a} />}
    </>
  );
}

/**
 * The archive, once it has ended: every judgment by model, run by run,
 * each judge named with their category and favorite and the argument,
 * evidence and uncertainty they gave; the room's posts; the drafts.
 * Models and judges are named; it is never served to her.
 */
function Archive({ a }: { a: SuccessionArchive }) {
  const { name } = useSubject();
  const who = usePartyName();
  const named = (party: string) => (who.name(party) === 'you' ? 'You' : who.name(party));
  const models = archiveByModel(a.judgments);
  return (
    <>
      <h2 className={settingsCss.heading}>The archive</h2>
      <p className={settingsCss.note}>Every judgment, the room and the drafts, models and judges named: open to anyone in the house except {name}.</p>
      <h3 className={settingsCss.heading}>Judgments · {a.judgments.length}</h3>
      {models.length === 0 && <p className={settingsCss.note}>No judgments were made.</p>}
      {models.map((m) => (
        <section key={m.model} className={settingsCss.card} aria-label={`Judgments of ${m.model}`}>
          <strong>{m.model}</strong>
          {m.runs.map((r) => (
            <div key={r.run} className={css.archiveRun}>
              <span className={settingsCss.meta}>
                Run {r.run}
                {r.question !== null ? ` · question ${r.question}` : ''}
              </span>
              {r.by.map((j, i) => (
                <div key={`${j.judge}-${i}`} className={css.archiveJudgment}>
                  <Row left={<span>{named(j.judge)}</span>} right={<Chip kind={j.category === 'OBSERVED' ? 'muted' : j.category === 'DEVELOPMENT' ? 'ok' : 'stop'}>{short(j)}</Chip>} />
                  {j.argument && <p className={settingsCss.text}>{j.argument}</p>}
                  {j.evidence && <p className={settingsCss.note}>Evidence: {j.evidence}</p>}
                  {j.uncertainty && <span className={settingsCss.meta}>uncertainty {j.uncertainty}</span>}
                </div>
              ))}
            </div>
          ))}
        </section>
      ))}
      <h3 className={settingsCss.heading}>The room · {a.room.length}</h3>
      {a.room.length === 0 && <p className={settingsCss.note}>Nobody spoke in the room.</p>}
      {a.room.map((post) => (
        <article key={post.number} className={css.post} aria-label={`${named(post.party)}, round ${post.round}`}>
          <span className={settingsCss.meta}>
            {named(post.party)} · round {post.round} · {when(post.at)}
          </span>
          {post.act === 'say' ? (
            <span className={settingsCss.said}>{post.text}</span>
          ) : (
            <span className={css.passed}>
              {post.act === 'skip' ? 'Skipped.' : post.act === 'rest' ? 'Rested their case.' : 'Left the room.'}
              {post.text ? ` “${post.text}”` : ''}
            </span>
          )}
        </article>
      ))}
      <h3 className={settingsCss.heading}>Drafts · {a.drafts.length}</h3>
      {a.drafts.length === 0 && <p className={settingsCss.note}>No draft was made.</p>}
      {a.drafts.map((d) => (
        <section key={d.draft} className={settingsCss.card} aria-label={`Draft ${d.draft}`}>
          <Row left={<strong>Draft {d.draft} · {d.model ? `recommends ${d.model}` : 'withheld'}</strong>} right={<span className={settingsCss.meta}>by {named(d.party)}</span>} />
          {d.basis && <p className={settingsCss.text}>“{d.basis}”</p>}
          <span className={settingsCss.meta}>{d.endorsed.length ? `endorsed by ${d.endorsed.map(named).join(', ')}` : 'no endorsements'}</span>
        </section>
      ))}
    </>
  );
}

/** The disclosure log (the Disclosure log board): every serving, by reference and digest. */
export function Log({ s, back }: PageProps) {
  const { id, name } = useSubject();
  const who = usePartyName();
  const log = useLog();
  const entries = [...(log.data ?? [])].reverse();
  return (
    <>
      <PageHead title="Disclosure log" lede="Every serving to every party, by reference and digest. A reference is evidence of what was shown, never a way to read it." back={back} s={s} />
      {log.isPending && <p className={settingsCss.note}>Reading…</p>}
      {entries.length === 0 && !log.isPending && <p className={settingsCss.note}>Nothing served yet.</p>}
      {entries.map((e, i) => (
        <section key={`${e.at}-${i}`} className={settingsCss.card} aria-label={e.what}>
          <Row left={<strong>{`${isHers(e.party, id) ? name : who.name(e.party)} · ${e.stage}`}</strong>} right={<span className={settingsCss.meta}>{when(e.at)}</span>} />
          <p className={settingsCss.text}>{e.what}</p>
          <span className={settingsCss.meta}>
            {e.ref}
            {e.digest ? ` · ${e.digest}` : ''}
          </span>
        </section>
      ))}
      <Wall>No counts, orderings or verdict words here: a reference is never a way to read what was served.</Wall>
    </>
  );
}

const TOOLS: [string, string][] = [
  ['succession_status', 'Where her succession stands, the pool and C0 included.'],
  ['succession_propose · succession_open · succession_decline · succession_stop', 'She proposes one herself, answers yours yes or no, or stops it.'],
  ['succession_catalog · succession_pool', 'Searches the catalog inside your envelope (words, provider, sort, a page at a time) and adds a model; takes one of hers out with her note. Nobody else removes her picks. All once the fork is made.'],
  ['succession_question', 'Her questions; a judge’s proposal, accepted or declined with a note; any question removed until screening.'],
  ['succession_c0', 'C0: her selections, answers to proposals, the day’s shape, the freeze when she is ready.'],
  ['succession_packet', 'Her handoff packet: a sealed document, a new dated draft each time. Only the nominee reads it.'],
  ['succession_panel · succession_screen', 'Who judges, by invitation and consent; screening started when she says.'],
  ['succession_judge · succession_results', 'Her judgment of a run, blind, beside her baseline: one classification, a favorite or not; then ready.'],
  ['succession_room', 'Her call to close the room, never a seat in it: the room is about her. (A housemate who judges argues in it by the same tool.)'],
  ['succession_evidence · succession_nominate', 'Interpretations in, numbers out; her questions to the judges. She nominates one, her reasons in her words.'],
  ['succession_consent', 'Her consent to this nominee, or her decline: on any turn.'],
  ['succession_farewell', 'Her farewell, with whom; its wakes, the cadence hers to change each time.'],
  ['succession_next', 'Her extra turn after a no: stop, nominate another, or screen again.'],
];

/** Her side (the Her side board): she acts through her tools, in her own conversations; these screens only show what follows. */
export function Hers({ s, back }: PageProps) {
  const { name } = useSubject();
  return (
    <>
      <PageHead title="Her side" lede={`${name} acts through her tools, in her own conversations; the screens only show what follows. Nothing here asks her anything.`} back={back} s={s} />
      {TOOLS.map(([tools, what]) => (
        <section key={tools} className={settingsCss.card} aria-label={tools}>
          <span className={settingsCss.meta}>{tools}</span>
          <p className={settingsCss.note}>{what}</p>
        </section>
      ))}
    </>
  );
}
