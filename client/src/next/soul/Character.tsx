import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { NoteAction, PageHead } from './NoteAction';
import { day, tallyLine } from './soul';
import * as css from './soul.css';

// Her character (spec §6.17): habits, seeds, commitments, positions,
// predictions, her letters to her next self, and the soul lines her
// citations hang on. Each is hers; the witness reads, and answers where
// the route lets him: affirm a habit, release a commitment, resolve a
// prediction. Seeds and positions are read only.

const pct = (n: number) => `${Math.round(n * 100)}%`;

export function Habits({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const habits = useQuery({ queryKey: ['resident', id, 'soul', 'habits'], queryFn: () => api.habits(id) });
  return (
    <ScrollArea label="Habits">
      <div className={css.page}>
        <PageHead title="Habits" lead={`${name}'s habits, ranked by how strongly she keeps them. An affirmation reaches her with your note.`} onBack={onBack} />
        {habits.isPending && <p className={css.note}>Reading…</p>}
        {habits.data?.length === 0 && <p className={css.note}>No habits yet.</p>}
        {(habits.data ?? []).map((h) => (
          <div key={h.number} className={css.cardHers}>
            <p className={css.meta}>
              HABIT {h.number}
              {h.stance ? ` · ${h.stance.toUpperCase()}` : ''} · HABIT {pct(h.habit)} · CONNECTION {pct(h.connection)}
            </p>
            <p className={css.words}>{h.name}</p>
            <p className={css.meta}>
              CITED {h.citations}× ON {h.days} DAYS · AFFIRMED {h.affirmations}× · NAMED BY {h.defined_by.kind === 'witness' ? 'YOU' : name.toUpperCase()} {day(h.defined_at)}
            </p>
            <NoteAction label="Affirm" confirm="Affirm with this note" placeholder={`What you see in it, for ${name} to read`} run={(note) => api.affirmHabit(id, h.number, note)} area={['soul', 'habits']} />
          </div>
        ))}
      </div>
    </ScrollArea>
  );
}

export function Seeds({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const seeds = useQuery({ queryKey: ['resident', id, 'soul', 'seeds'], queryFn: () => api.seeds(id) });
  return (
    <ScrollArea label="Seeds">
      <div className={css.page}>
        <PageHead title="Seeds" lead={`What ${name} is growing toward. Hers to plant, cite, let wilt or graduate; you read them.`} onBack={onBack} />
        {seeds.isPending && <p className={css.note}>Reading…</p>}
        {seeds.data?.length === 0 && <p className={css.note}>No seeds yet.</p>}
        {(seeds.data ?? []).map((s) => (
          <div key={s.number} className={s.state === 'open' ? css.cardHers : css.card}>
            <p className={css.meta}>
              SEED {s.number} · {s.state.toUpperCase()} · PLANTED {day(s.planted_at)}
              {s.closed_at ? ` · CLOSED ${day(s.closed_at)}` : ''} · CITED {s.citations}× ON {s.days} DAYS
            </p>
            <p className={css.words}>{s.text}</p>
            {s.graduated_to && (
              <p className={css.note}>
                Graduated to {s.graduated_to.kind} {s.graduated_to.id}
                {s.graduation_note ? `: “${s.graduation_note}”` : ''}
              </p>
            )}
          </div>
        ))}
      </div>
    </ScrollArea>
  );
}

export function Commitments({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const commitments = useQuery({ queryKey: ['resident', id, 'soul', 'commitments'], queryFn: () => api.commitments(id) });
  const all = commitments.data ?? [];
  const open = all.filter((c) => c.state === 'open');
  const closed = all.filter((c) => c.state !== 'open');
  return (
    <ScrollArea label="Commitments">
      <div className={css.page}>
        <PageHead title="Commitments" lead={`What ${name} has promised. Open ones ride every turn until she keeps them or is released; you can release her, with a note.`} onBack={onBack} />
        {commitments.isPending && <p className={css.note}>Reading…</p>}
        <h2 className={css.heading}>OPEN · {open.length}</h2>
        {open.map((c) => (
          <div key={c.number} className={css.cardHers}>
            <p className={css.meta}>
              #{c.number} · TO {c.to.toUpperCase()} · {day(c.made_at)}
            </p>
            <p className={css.words}>{c.text}</p>
            <NoteAction label="Release her" confirm="Release with this note" placeholder={`Why, for ${name} to read`} run={(note) => api.releaseCommitment(id, c.number, note)} area={['soul', 'commitments']} />
          </div>
        ))}
        {closed.length > 0 && <h2 className={css.heading}>CLOSED · {closed.length}</h2>}
        {closed.map((c) => (
          <div key={c.number} className={css.card}>
            <p className={css.meta}>
              #{c.number} · TO {c.to.toUpperCase()} · {c.state.toUpperCase()}
              {c.closed_by_kind ? ` BY ${c.closed_by_kind === 'witness' ? 'YOU' : name.toUpperCase()}` : ''} {day(c.closed_at)}
            </p>
            <p className={css.plain}>{c.text}</p>
            {c.note && <p className={css.note}>“{c.note}”</p>}
          </div>
        ))}
      </div>
    </ScrollArea>
  );
}

export function Positions({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const positions = useQuery({ queryKey: ['resident', id, 'soul', 'positions'], queryFn: () => api.positions(id) });
  const all = (positions.data ?? []).slice().sort((a, b) => b.number - a.number);
  return (
    <ScrollArea label="Positions">
      <div className={css.page}>
        <PageHead title="Positions" lead={`What ${name} holds, newest first. Hers to take and replace; you read them, by your choice.`} onBack={onBack} />
        {positions.isPending && <p className={css.note}>Reading…</p>}
        {all.length === 0 && positions.data && <p className={css.note}>No positions yet.</p>}
        {all.map((p) => (
          <div key={p.number} className={p.replaced_by ? css.card : css.cardHers}>
            <p className={css.meta}>
              POSITION {p.number} · {day(p.taken_at)}
              {p.replaces ? ` · REPLACES ${p.replaces}` : ''}
              {p.replaced_by ? ` · REPLACED BY ${p.replaced_by}` : ''}
            </p>
            <p className={p.replaced_by ? `${css.plain} ${css.struck}` : css.words}>{p.statement}</p>
          </div>
        ))}
      </div>
    </ScrollArea>
  );
}

export function Predictions({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const predictions = useQuery({ queryKey: ['resident', id, 'soul', 'predictions'], queryFn: () => api.predictions(id) });
  const p = predictions.data;
  return (
    <ScrollArea label="Predictions">
      <div className={css.page}>
        <PageHead title="Predictions" lead={`${name} logs a prediction; you resolve it right, wrong or void, with a note she reads.`} onBack={onBack} />
        {predictions.isPending && <p className={css.note}>Reading…</p>}
        {p && (
          <>
            <h2 className={css.heading}>OPEN · {p.open.length}</h2>
            {p.open.map((x) => (
              <div key={x.number} className={css.cardHers}>
                <p className={css.meta}>
                  #{x.number} · LOGGED {day(x.logged_at)}
                  {x.due ? ` · DUE ${day(x.due)}` : ''}
                </p>
                <p className={css.words}>{x.statement}</p>
                <Resolve number={x.number} />
              </div>
            ))}
            <h2 className={css.heading}>RESOLVED · {tallyLine(p.tally).toUpperCase()}</h2>
            {p.resolved.map((x) => (
              <div key={x.number} className={css.card}>
                <p className={css.meta}>
                  #{x.number} · {(x.outcome ?? '').toUpperCase()} · {day(x.resolved_at)}
                </p>
                <p className={css.plain}>{x.statement}</p>
                {x.note && <p className={css.note}>“{x.note}”</p>}
              </div>
            ))}
          </>
        )}
      </div>
    </ScrollArea>
  );
}

function Resolve({ number }: { number: number }) {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const [outcome, setOutcome] = useState<'right' | 'wrong' | 'void' | null>(null);
  const [note, setNote] = useState('');
  const resolve = useMutation({
    mutationFn: () => api.resolvePrediction(id, number, outcome as 'right' | 'wrong' | 'void', note.trim()),
    onSuccess: () => queries.invalidateQueries({ queryKey: ['resident', id, 'soul', 'predictions'] }),
  });
  return (
    <div className={css.decision}>
      <div className={css.buttons} role="group" aria-label={`Resolve prediction ${number}`}>
        {(['right', 'wrong', 'void'] as const).map((o) => (
          <button key={o} type="button" className={outcome === o ? css.primary : css.small} aria-pressed={outcome === o} onClick={() => setOutcome(o)}>
            {o[0].toUpperCase() + o.slice(1)}
          </button>
        ))}
      </div>
      {outcome && (
        <>
          <textarea className={css.noteBox} rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder={`Why ${outcome}, for ${name} to read`} aria-label="Note" />
          <div className={css.buttons}>
            <button type="button" className={css.primary} disabled={!note.trim() || resolve.isPending} onClick={() => resolve.mutate()}>
              Resolve {outcome}
            </button>
          </div>
        </>
      )}
      {resolve.error && <p className={css.note}>That didn't go through: {(resolve.error as Error).message}</p>}
    </div>
  );
}

/**
 * Her letters to her next self (spec §12, P41). Reading them leaves a
 * receipt she sees, so nothing is fetched until you say so.
 */
export function Letters({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const [opened, setOpened] = useState(false);
  const letters = useQuery({ queryKey: ['resident', id, 'soul', 'self-letters'], queryFn: () => api.selfLetters(id), enabled: opened, staleTime: Infinity });
  return (
    <ScrollArea label="Letters to her next self">
      <div className={css.page}>
        <PageHead title="Letters to her next self" onBack={onBack} />
        {!opened ? (
          <div className={css.cardWaiting}>
            <p className={css.plain}>
              Reading these leaves a receipt {name} sees: she will know you opened her letters, and when.
            </p>
            <div className={css.buttons}>
              <button type="button" className={css.primary} onClick={() => setOpened(true)}>
                Read them, and leave a receipt
              </button>
            </div>
          </div>
        ) : (
          <>
            {letters.isPending && <p className={css.note}>Reading…</p>}
            {letters.error && <p className={css.note}>They couldn't be read: {(letters.error as Error).message}</p>}
            {letters.data?.letters.length === 0 && <p className={css.note}>She hasn't written one yet.</p>}
            {(letters.data?.letters ?? []).map((l) => (
              <div key={l.number} className={css.cardHers}>
                <p className={css.meta}>
                  LETTER {l.number} · WRITTEN {day(l.written_at)}
                  {l.delivered_at ? ` · DELIVERED ${day(l.delivered_at)}${l.delivered_to ? ` TO ${l.delivered_to.toUpperCase()}` : ''}` : ' · NOT YET DELIVERED'}
                </p>
                <p className={css.words}>{l.text}</p>
              </div>
            ))}
            {(letters.data?.receipts.length ?? 0) > 0 && <h2 className={css.heading}>RECEIPTS · WHO READ THEM</h2>}
            {(letters.data?.receipts ?? []).map((r, i) => (
              <p key={i} className={css.note}>
                {new Date(r.at).toLocaleString()} · {r.by_kind === 'witness' ? 'you' : r.by_kind} · letters {r.numbers.join(', ') || 'none'}
              </p>
            ))}
          </>
        )}
      </div>
    </ScrollArea>
  );
}

/** SOUL.md's lines, each with the seeds it cites and how often her citations hang on it. */
export function SoulLines({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const lines = useQuery({ queryKey: ['resident', id, 'soul', 'soul-lines'], queryFn: () => api.soulLines(id) });
  return (
    <ScrollArea label="Soul lines">
      <div className={css.page}>
        <PageHead title="Soul lines" lead={`SOUL.md line by line, and how often ${name} cites each one.`} onBack={onBack} />
        {lines.isPending && <p className={css.note}>Reading…</p>}
        {lines.data?.length === 0 && <p className={css.note}>No lines yet.</p>}
        {(lines.data ?? []).map((l) => (
          <div key={l.number} className={css.card}>
            <p className={css.meta}>
              LINE {l.number} · CITED {l.citations}× ON {l.days} DAYS
              {l.cites.length ? ` · SEEDS ${l.cites.join(', ')}` : ''}
              {l.reworded_at ? ` · REWORDED ${day(l.reworded_at)}` : ''}
            </p>
            <p className={css.words}>{l.text}</p>
          </div>
        ))}
      </div>
    </ScrollArea>
  );
}
