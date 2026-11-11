import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type SoulEdit } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { NoteAction, PageHead } from './NoteAction';
import { day, proposedTags, REVISION_TARGETS } from './soul';
import * as css from './soul.css';

// What passes between you about her memory (the consent table in
// ui-parity.md): her tag proposals wait on you; your stance revisions
// and your bookmark and identity-file proposals wait on her.

export function Tags({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const tags = useQuery({ queryKey: ['resident', id, 'soul', 'tags'], queryFn: () => api.tags(id) });
  const all = tags.data ?? [];
  const waiting = proposedTags(all);
  const rest = all.filter((t) => !waiting.includes(t));
  return (
    <ScrollArea label="Tags">
      <div className={css.page}>
        <PageHead title="Tags" lead={`The words ${name}'s memory is sorted by. She proposes a new one; it joins the set when you approve it. Either answer reaches her with your note.`} onBack={onBack} />
        {tags.isPending && <p className={css.note}>Reading…</p>}
        <h2 className={css.headingWitness}>WAITING ON YOU · {waiting.length}</h2>
        {waiting.length === 0 && <p className={css.note}>Nothing waits on you.</p>}
        {waiting.map((t) => (
          <div key={t.slug} className={css.cardWaiting}>
            <p className={css.meta}>
              {t.slug} · PROPOSED BY {name.toUpperCase()} {day(t.created_at)}
            </p>
            {t.note && <p className={css.words}>“{t.note}”</p>}
            <div className={css.buttons}>
              <NoteAction label="Approve" primary confirm="Approve with this note" placeholder={`For ${name} to read`} run={(note) => api.decideTag(id, t.slug, 'approve', note)} area={['soul', 'tags']} />
              <NoteAction label="Decline" confirm="Decline with this note" placeholder={`Why, for ${name} to read`} run={(note) => api.decideTag(id, t.slug, 'reject', note)} area={['soul', 'tags']} />
            </div>
          </div>
        ))}
        <h2 className={css.heading}>THE SET</h2>
        <div className={css.vocabulary}>
          {rest.map((t) => (
            <span key={t.slug} className={`${css.word} ${t.state === 'active' ? '' : css.struck}`} title={t.note ?? undefined}>
              {t.slug}
              {t.state === 'active' ? '' : ` · ${t.state === 'rejected' ? 'declined' : t.state}`}
            </span>
          ))}
        </div>
      </div>
    </ScrollArea>
  );
}

export function Revisions({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const revisions = useQuery({ queryKey: ['resident', id, 'soul', 'revisions'], queryFn: () => api.revisions(id) });
  const all = (revisions.data ?? []).slice().sort((a, b) => b.number - a.number);
  return (
    <ScrollArea label="Revisions">
      <div className={css.page}>
        <PageHead
          title="Revisions"
          lead={`Corrections to what ${name} remembers. A fact you correct holds at once; a stance is a proposal she accepts or declines, with a note you read here.`}
          onBack={onBack}
        />
        <Revise />
        {revisions.isPending && <p className={css.note}>Reading…</p>}
        {all.length === 0 && revisions.data && <p className={css.note}>No revisions yet.</p>}
        {all.map((r) => {
          const yours = r.by.kind === 'witness';
          const waiting = r.state === 'proposed';
          return (
            <div key={r.number} className={yours ? (waiting ? css.cardWaiting : css.card) : css.cardHers}>
              <p className={css.meta}>
                #{r.number} · {r.kind.toUpperCase()} ON {r.target_kind.toUpperCase()} {r.target_id} · BY {yours ? 'YOU' : name.toUpperCase()} {day(r.at)} ·{' '}
                {waiting ? `WAITING ON ${name.toUpperCase()}` : r.state.toUpperCase()}
              </p>
              <p className={yours ? css.plain : css.words}>{r.text}</p>
              {r.note && <p className={css.note}>Why: “{r.note}”</p>}
              {r.decision_note && (
                <p className={css.note}>
                  {name}'s answer{r.decided_at ? `, ${day(r.decided_at)}` : ''}: “{r.decision_note}”
                </p>
              )}
            </div>
          );
        })}
      </div>
    </ScrollArea>
  );
}

function Revise() {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const [open, setOpen] = useState(false);
  const [target, setTarget] = useState<string>('bookmark');
  const [targetId, setTargetId] = useState('');
  const [kind, setKind] = useState<'fact' | 'stance'>('stance');
  const [text, setText] = useState('');
  const [note, setNote] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  const revise = useMutation({
    mutationFn: () => api.revise(id, { target_kind: target, target_id: targetId.trim(), kind, text: text.trim(), note: note.trim() }),
    onSuccess: (r) => {
      setSaid(r.state === 'applied' ? `Revision ${r.number} holds.` : `Revision ${r.number} is proposed; ${name} answers.`);
      setOpen(false);
      setText('');
      setNote('');
      setTargetId('');
      return queries.invalidateQueries({ queryKey: ['resident', id, 'soul', 'revisions'] });
    },
  });
  if (!open)
    return (
      <>
        <div className={css.buttons}>
          <button type="button" className={css.small} onClick={() => setOpen(true)}>
            Propose a revision
          </button>
        </div>
        {said && <p className={css.said} role="status">{said}</p>}
      </>
    );
  return (
    <form
      className={css.cardWaiting}
      aria-label="Propose a revision"
      onSubmit={(e) => {
        e.preventDefault();
        revise.mutate();
      }}
    >
      <div className={css.formRow}>
        <label className={css.label}>
          WHAT IT CORRECTS
          <select className={css.select} value={target} onChange={(e) => setTarget(e.target.value)}>
            {REVISION_TARGETS.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </label>
        <label className={css.label}>
          ITS NUMBER OR PATH
          <input className={css.input} value={targetId} onChange={(e) => setTargetId(e.target.value)} />
        </label>
        <label className={css.label}>
          KIND
          <select className={css.select} value={kind} onChange={(e) => setKind(e.target.value as 'fact' | 'stance')}>
            <option value="stance">stance: proposed to her</option>
            <option value="fact">fact: holds at once</option>
          </select>
        </label>
      </div>
      <textarea className={css.noteBox} rows={3} value={text} onChange={(e) => setText(e.target.value)} placeholder="The correction, as it should read" aria-label="The correction" />
      <textarea className={css.noteBox} rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder={`Why, for ${name} to read`} aria-label="Note" />
      <div className={css.buttons}>
        <button type="submit" className={css.primary} disabled={!targetId.trim() || !text.trim() || !note.trim() || revise.isPending}>
          {kind === 'stance' ? `Propose to ${name}` : 'Correct it'}
        </button>
        <button type="button" className={css.secondary} onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
      {revise.error && <p className={css.note}>That didn't go through: {(revise.error as Error).message}</p>}
    </form>
  );
}

/**
 * Your proposals to her (agathos-daimon#43, #44; kumbukumbu#63): open ones
 * waiting on her, which an identity-file edit can be withdrawn from with a
 * note; answered ones with her decision and her note; an accepted
 * bookmark with the line she wrote from yours.
 */
export function Proposals({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const [view, setView] = useState<'open' | 'answered' | 'withdrawn'>('open');
  const edits = useQuery({ queryKey: ['resident', id, 'soul', 'soul-edits', 'all'], queryFn: () => api.soulEdits(id, 'all') });
  const bookmarks = useQuery({ queryKey: ['resident', id, 'soul', 'bookmark-proposals', 'all'], queryFn: () => api.bookmarkProposals(id, 'all') });
  const editsIn = (edits.data ?? []).filter((e) => (view === 'withdrawn' ? !!e.withdrawn : view === 'answered' ? !!e.answer : !e.answer && !e.withdrawn));
  const bookmarksIn = view === 'withdrawn' ? [] : (bookmarks.data ?? []).filter((b) => (view === 'answered' ? !!b.answer : !b.answer));
  const count = (v: typeof view) =>
    (edits.data ?? []).filter((e) => (v === 'withdrawn' ? !!e.withdrawn : v === 'answered' ? !!e.answer : !e.answer && !e.withdrawn)).length +
    (v === 'withdrawn' ? 0 : (bookmarks.data ?? []).filter((b) => (v === 'answered' ? !!b.answer : !b.answer)).length);
  return (
    <ScrollArea label="Your proposals">
      <div className={css.page}>
        <PageHead title="Your proposals" lead={`What you've proposed to ${name}: waiting on her, answered with her note, or withdrawn.`} onBack={onBack} />
        <div className={css.buttons} role="group" aria-label="Which proposals">
          {(['open', 'answered', 'withdrawn'] as const).map((v) => (
            <button key={v} type="button" className={view === v ? css.primary : css.secondary} aria-pressed={view === v} onClick={() => setView(v)}>
              {v === 'open' ? 'Waiting on her' : v === 'answered' ? 'Answered' : 'Withdrawn'} · {count(v)}
            </button>
          ))}
        </div>
        <h2 className={css.heading}>IDENTITY FILES · {editsIn.length}</h2>
        {editsIn.length === 0 && <p className={css.note}>None.</p>}
        {editsIn.map((e) => (
          <EditProposal key={e.ref} e={e} name={name} />
        ))}
        {view !== 'withdrawn' && (
          <>
            <h2 className={css.heading}>BOOKMARKS · {bookmarksIn.length}</h2>
            {bookmarksIn.length === 0 && <p className={css.note}>{view === 'open' ? 'None open. You suggest one from her reply in Chat.' : 'None.'}</p>}
            {bookmarksIn.map((b) => (
              <div key={b.ref} className={b.answer ? css.card : css.cardWaiting}>
                <p className={css.meta}>
                  {day(b.proposed_at)}
                  {b.answer ? ` · ${b.answer.decision === 'accepted' ? 'SHE KEPT IT' : 'SHE DECLINED'} ${day(b.answer.at)}` : ` · WAITING ON ${name.toUpperCase()}`}
                </p>
                <p className={css.plain}>{b.line}</p>
                {b.note && <p className={css.note}>Your note: “{b.note}”</p>}
                {b.answer?.decision === 'declined' && b.answer.note && <p className={css.note}>Her note: “{b.answer.note}”</p>}
                {b.answer?.bookmark &&
                  (b.answer.bookmark.private ? (
                    <p className={css.note}>She kept it as bookmark #{b.answer.bookmark.number}, in a private session; its words are hers.</p>
                  ) : (
                    <p className={css.note}>
                      In her words, #{b.answer.bookmark.number}: “{b.answer.bookmark.line}”
                    </p>
                  ))}
              </div>
            ))}
          </>
        )}
      </div>
    </ScrollArea>
  );
}

function EditProposal({ e, name }: { e: SoulEdit; name: string }) {
  const { id } = useSubject();
  const qc = useQueryClient();
  const [withdrawing, setWithdrawing] = useState(false);
  const [note, setNote] = useState('');
  const withdraw = useMutation({
    mutationFn: () => api.withdrawSoulEdit(id, e.ref, note.trim()),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['resident', id, 'soul'] }),
  });
  const status = e.withdrawn
    ? `WITHDRAWN ${day(e.withdrawn.at)}`
    : e.answer
      ? `${e.answer.decision === 'accepted' ? 'SHE ACCEPTED' : 'SHE DECLINED'} ${day(e.answer.at)}`
      : `WAITING ON ${name.toUpperCase()}`;
  return (
    <div className={e.answer || e.withdrawn ? css.card : css.cardWaiting}>
      <p className={css.meta}>
        {e.file} · {day(e.proposed_at)} · {status}
      </p>
      {e.note && <p className={css.note}>Your note: “{e.note}”</p>}
      {e.answer?.note && <p className={css.note}>Her note: “{e.answer.note}”</p>}
      {e.withdrawn && <p className={css.note}>Why you withdrew it: “{e.withdrawn.note}”</p>}
      <details>
        <summary className={css.meta}>THE FILE AS PROPOSED</summary>
        <pre className={css.pre}>{e.content}</pre>
      </details>
      {!e.answer && !e.withdrawn &&
        (withdrawing ? (
          <div className={css.buttons}>
            <input id={`withdraw-${e.ref}`} className={css.input} value={note} onChange={(ev) => setNote(ev.target.value)} placeholder="Why (she reads it)" aria-label="Why you withdraw it" />
            <button type="button" className={css.secondary} disabled={!note.trim() || withdraw.isPending} onClick={() => withdraw.mutate()}>
              Withdraw it
            </button>
          </div>
        ) : (
          <div className={css.buttons}>
            <button type="button" className={css.small} onClick={() => setWithdrawing(true)}>
              Withdraw
            </button>
          </div>
        ))}
      {withdraw.error && <p className={css.note}>That didn't go through: {(withdraw.error as Error).message}</p>}
    </div>
  );
}
