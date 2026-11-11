import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { useSubject } from '../state/resident';
import * as css from './soul.css';

/**
 * A consent-shaped action: the button opens a note, and the action goes
 * only with the note (every such route takes one, and she reads it).
 * After it lands, the area's queries are read again.
 */
export function NoteAction({
  label,
  confirm,
  placeholder,
  run,
  area,
  primary = false,
  optional = false,
}: {
  label: string;
  confirm: string;
  placeholder: string;
  run: (note: string) => Promise<unknown>;
  /** The query area to read again, under ['resident', id, ...area]. */
  area: string[];
  primary?: boolean;
  /** A note the route does not require. */
  optional?: boolean;
}) {
  const { id } = useSubject();
  const queries = useQueryClient();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState('');
  const act = useMutation({
    mutationFn: () => run(note.trim()),
    onSuccess: () => {
      setOpen(false);
      setNote('');
      return queries.invalidateQueries({ queryKey: ['resident', id, ...area] });
    },
  });
  if (!open)
    return (
      <button type="button" className={primary ? css.primary : css.small} onClick={() => setOpen(true)}>
        {label}
      </button>
    );
  return (
    <div className={css.decision}>
      <textarea className={css.noteBox} value={note} onChange={(e) => setNote(e.target.value)} placeholder={placeholder} aria-label={`Note: ${label}`} rows={2} />
      <div className={css.buttons}>
        <button type="button" className={css.primary} disabled={(!optional && !note.trim()) || act.isPending} onClick={() => act.mutate()}>
          {confirm}
        </button>
        <button type="button" className={css.secondary} onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
      {act.error && <p className={css.note}>That didn't go through: {(act.error as Error).message}</p>}
    </div>
  );
}

/** A page on Soul's stack: back, a title, a line under it. */
export function PageHead({ title, lead, onBack }: { title: string; lead?: string; onBack: () => void }) {
  return (
    <>
      <button type="button" className={css.back} onClick={onBack}>
        ‹ Soul
      </button>
      <h1 className={css.title}>{title}</h1>
      {lead && <p className={css.lead}>{lead}</p>}
    </>
  );
}
