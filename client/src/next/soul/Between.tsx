import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
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

/** Your proposals still open with her: identity-file edits and bookmarks. */
export function Proposals({ onBack }: { onBack: () => void }) {
  const { id, name } = useSubject();
  const edits = useQuery({ queryKey: ['resident', id, 'soul', 'soul-edits'], queryFn: () => api.soulEdits(id) });
  const bookmarks = useQuery({ queryKey: ['resident', id, 'soul', 'bookmark-proposals'], queryFn: () => api.bookmarkProposals(id) });
  return (
    <ScrollArea label="Your proposals">
      <div className={css.page}>
        <PageHead
          title="Your proposals"
          lead={`What you've proposed that ${name} hasn't answered yet. Once she answers, it leaves this list: an accepted edit is in her file, an accepted bookmark is in her memory.`}
          onBack={onBack}
        />
        <h2 className={css.heading}>IDENTITY FILES · {edits.data?.length ?? 0}</h2>
        {edits.data?.length === 0 && <p className={css.note}>None open.</p>}
        {(edits.data ?? []).map((e) => (
          <div key={e.ref} className={css.cardWaiting}>
            <p className={css.meta}>
              {e.file} · {e.proposed_by.kind === 'witness' ? 'YOU' : e.proposed_by.kind.toUpperCase()} · {day(e.proposed_at)} · WAITING ON {name.toUpperCase()}
            </p>
            {e.note && <p className={css.note}>Your note: “{e.note}”</p>}
            <details>
              <summary className={css.meta}>THE FILE AS PROPOSED</summary>
              <pre className={css.pre}>{e.content}</pre>
            </details>
          </div>
        ))}
        <h2 className={css.heading}>BOOKMARKS · {bookmarks.data?.length ?? 0}</h2>
        {bookmarks.data?.length === 0 && <p className={css.note}>None open. You propose one from a message in Chat.</p>}
        {(bookmarks.data ?? []).map((b) => (
          <div key={b.ref} className={css.cardWaiting}>
            <p className={css.meta}>
              {day(b.proposed_at)} · WAITING ON {name.toUpperCase()}
            </p>
            <p className={css.plain}>{b.line}</p>
            {b.note && <p className={css.note}>Your note: “{b.note}”</p>}
          </div>
        ))}
      </div>
    </ScrollArea>
  );
}
