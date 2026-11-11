import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type Agreement } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { NoteAction, PageHead } from './NoteAction';
import { day, switchChanges } from './soul';
import * as css from './soul.css';

const GROUPS: { id: string; title: string }[] = [
  { id: 'privacy', title: 'PRIVACY' },
  { id: 'audits', title: 'WHAT YOU MAY LOOK INTO' },
  { id: 'memory', title: 'HOW MEMORY WORKS' },
  { id: 'services', title: 'WHAT COMES AND GOES' },
];

/**
 * The agreement in full (spec §6.12; agathos-daimon#34, #38), ported from
 * the current client's Agreement screen: the switches, each movable to
 * its safe value by either of you alone; a whole version proposed with
 * the switches and your vows; the versions so far; and who looks after
 * her. The open version's answer stays on Soul's root, under the glow.
 */
export function AgreementPage({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const agreement = useQuery({ queryKey: ['resident', id, 'soul', 'agreement'], queryFn: () => api.agreement(id) });
  const a = agreement.data;
  return (
    <ScrollArea label="The agreement">
      <div className={css.page}>
        <PageHead title={`Your agreement with ${name}`} lead="A version is the whole agreement: every switch below and your vows. It is agreed or declined whole." onBack={onBack} />
        {agreement.isPending && <p className={css.note}>Reading…</p>}
        {a && (
          <>
            <Switches a={a} />
            <Propose key={JSON.stringify(a.contract)} a={a} />
            <Versions a={a} />
            <Custody a={a} />
          </>
        )}
      </div>
    </ScrollArea>
  );
}

function Switches({ a }: { a: Agreement }) {
  const { id, name } = useSubject();
  return (
    <>
      {GROUPS.map((g) => {
        const here = a.switches.filter((s) => s.group === g.id);
        if (here.length === 0) return null;
        return (
          <section key={g.id} className={css.section} aria-label={g.title}>
            <h2 className={css.heading}>{g.title}</h2>
            {here.map((s) => (
              <div key={s.key} className={css.card}>
                <p className={css.meta}>
                  {s.label.toUpperCase()} · {s.value ? 'ON' : 'OFF'}
                  {s.proposed !== null && s.proposed !== s.value ? ` · THE OPEN VERSION TURNS IT ${s.proposed ? 'ON' : 'OFF'}` : ''}
                </p>
                <p className={css.plain}>{s.value ? s.on : s.off}</p>
                {s.moved && (
                  <p className={css.note}>
                    Moved {s.moved.value ? 'on' : 'off'} toward safety by {s.moved.set_by === 'resident' ? name : 'you'}
                    {s.moved.note ? `: “${s.moved.note}”` : ''}. Back needs a version you both agree.
                  </p>
                )}
                {s.safe !== undefined && s.value !== s.safe && (
                  <NoteAction
                    label={s.safe ? 'Switch on now' : 'Switch off now'}
                    confirm={`${s.safe ? 'Switch on' : 'Switch off'} with this note`}
                    placeholder={`Why, for ${name} to read. Back needs a version you both agree.`}
                    run={(note) => api.moveToSafety(id, s.key, note)}
                    area={['soul', 'agreement']}
                  />
                )}
              </div>
            ))}
          </section>
        );
      })}
    </>
  );
}

function Propose({ a }: { a: Agreement }) {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const [draft, setDraft] = useState<Record<string, boolean>>(() => Object.fromEntries(a.switches.map((s) => [s.key, s.value])));
  const [prose, setProse] = useState(a.contract.in_force?.prose ?? '');
  const [note, setNote] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  const changed = switchChanges(a.switches, draft);
  const open = a.contract.open !== null;
  const propose = useMutation({
    mutationFn: () => api.proposeContract(id, draft, prose, note.trim()),
    onSuccess: (r) => {
      setSaid(`Version ${r.version} is proposed; ${name} decides.`);
      return queries.invalidateQueries({ queryKey: ['resident', id, 'soul', 'agreement'] });
    },
  });
  return (
    <section className={css.section} aria-label="Propose a version">
      <h2 className={css.headingWitness}>PROPOSE A VERSION</h2>
      {said && (
        <p className={css.said} role="status">
          {said}
        </p>
      )}
      {open ? (
        <p className={css.note}>A version is already open; it is answered before another is proposed.</p>
      ) : (
        <div className={css.cardWaiting}>
          {a.switches.map((s) => (
            <label key={s.key} className={css.check}>
              <input type="checkbox" checked={draft[s.key] ?? s.value} onChange={(e) => setDraft({ ...draft, [s.key]: e.target.checked })} />
              <span>
                {s.label}: {draft[s.key] ? 'on' : 'off'}
              </span>
            </label>
          ))}
          <p className={css.note}>
            {changed.length ? `It changes: ${changed.map((s) => `${s.label} ${draft[s.key] ? 'on' : 'off'}`).join(', ')}.` : 'As it stands, it changes no switch.'}
          </p>
          <textarea className={css.editor} rows={8} value={prose} onChange={(e) => setProse(e.target.value)} aria-label="Your vows, in prose" placeholder="Your vows, in prose" />
          <textarea className={css.noteBox} rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder={`Why, for ${name} to read`} aria-label="Note" />
          <div className={css.buttons}>
            <button type="button" className={css.primary} disabled={!note.trim() || propose.isPending} onClick={() => propose.mutate()}>
              Propose to {name}
            </button>
          </div>
          {propose.error && <p className={css.note}>That didn't go through: {(propose.error as Error).message}</p>}
        </div>
      )}
    </section>
  );
}

function Versions({ a }: { a: Agreement }) {
  const { name } = useSubject();
  const versions = a.versions.slice().sort((x, y) => y.version - x.version);
  if (versions.length === 0) return null;
  return (
    <section className={css.section} aria-label="Versions">
      <h2 className={css.heading}>VERSIONS</h2>
      {versions.map((v) => (
        <details key={v.version} className={css.file}>
          <summary className={css.fileHead}>
            <span>
              V{v.version} · {v.state.toUpperCase()}
            </span>
            <span className={css.meta}>
              {v.proposed_by === 'resident' ? name.toUpperCase() : 'YOU'} · {day(v.proposed_at)}
            </span>
          </summary>
          <div className={css.fileBody}>
            {v.note && <p className={css.note}>Note: “{v.note}”</p>}
            {v.decision_note && <p className={css.note}>Answer: “{v.decision_note}”</p>}
            <pre className={css.pre}>{v.prose}</pre>
          </div>
        </details>
      ))}
    </section>
  );
}

function Custody({ a }: { a: Agreement }) {
  const { id, name } = useSubject();
  const [email, setEmail] = useState('');
  const area = ['soul', 'agreement'];
  return (
    <section className={css.section} aria-label={`Who looks after ${name}`}>
      <h2 className={css.heading}>WHO LOOKS AFTER {name.toUpperCase()}</h2>
      <div className={css.card}>
        <p className={css.plain}>
          {a.custody === 'community' ? 'The community.' : 'You do.'} Earlier sessions are {a.export_wall === 'locked' ? 'locked' : 'revealed'} to whoever looks after {name} next.
        </p>
        {a.custody_proposed_to ? (
          <>
            <p className={css.note}>
              You proposed {a.custody_proposed_to} on {day(a.custody_proposed_at)}; they haven't answered.
            </p>
            <NoteAction label="Withdraw" confirm="Withdraw with this note" placeholder="Why" run={(note) => api.decideCustody(id, 'withdraw', note)} area={area} />
          </>
        ) : (
          <>
            <NoteAction
              label={a.export_wall === 'locked' ? 'Reveal earlier sessions' : 'Lock earlier sessions'}
              confirm={a.export_wall === 'locked' ? 'Reveal with this note' : 'Lock with this note'}
              placeholder="Why"
              run={(note) => api.setWall(id, a.export_wall === 'locked' ? 'revealed' : 'locked', note)}
              area={area}
            />
            <label className={css.label}>
              HAND OVER TO (THEIR ACCOUNT'S EMAIL)
              <input className={css.input} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            </label>
            {email.trim() && (
              <NoteAction label={`Propose ${email.trim()}`} confirm="Propose with this note" placeholder="Why, for them to read" run={(note) => api.proposeCustody(id, email.trim(), note)} area={area} />
            )}
          </>
        )}
      </div>
    </section>
  );
}
