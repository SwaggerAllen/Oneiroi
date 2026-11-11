import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { PageHead } from './NoteAction';
import * as css from './soul.css';

/**
 * Proposing an edit to one identity file (agathos-daimon; ui-parity #11).
 * After first contact the write is a proposal with a note, which she
 * accepts or declines; she edits her own files directly. Records'
 * editor pattern without the lease: the file is hers, and your words
 * are kept as the proposal rather than written over hers.
 */
export function FileEdit({ file, onDone }: { file: string; onDone: () => void }) {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const files = useQuery({ queryKey: ['resident', id, 'soul', 'files'], queryFn: () => api.files(id) });
  // A file not written yet starts empty.
  const current = files.data ? (files.data.find((f) => f.name === file)?.content ?? '') : undefined;
  const [text, setText] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  // Your words once you type; until then, the file as it stands.
  const value = text ?? current ?? null;
  const propose = useMutation({
    mutationFn: () => api.proposeFile(id, file, value ?? '', note.trim()),
    onSuccess: (r) => {
      setSaid(r?.ref ? `Proposed to ${name}. Until she answers, ${file} stays as it is.` : `${file} is written.`);
      return queries.invalidateQueries({ queryKey: ['resident', id, 'soul'] });
    },
  });
  const changed = value !== null && current !== undefined && value !== current;

  return (
    <ScrollArea label={`Proposing an edit to ${file}`}>
      <div className={css.page}>
        <PageHead title={file} lead={`Your edit goes to ${name} as a proposal with your note. She accepts or declines it; the file changes only if she accepts.`} onBack={onDone} />
        {files.isPending && <p className={css.note}>Reading…</p>}
        {said ? (
          <>
            <p className={css.said} role="status">
              {said}
            </p>
            <div className={css.buttons}>
              <button type="button" className={css.secondary} onClick={onDone}>
                Back to Soul
              </button>
            </div>
          </>
        ) : (
          <>
            <textarea
              className={css.editor}
              rows={20}
              value={value ?? ''}
              disabled={value === null}
              onChange={(e) => setText(e.target.value)}
              aria-label={`${file}, as you propose it`}
            />
            <textarea className={css.noteBox} rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder={`What you changed, and why, for ${name} to read`} aria-label="Note" />
            <div className={css.buttons}>
              <button type="button" className={css.primary} disabled={!changed || !note.trim() || propose.isPending} onClick={() => propose.mutate()}>
                Propose to {name}
              </button>
              <button type="button" className={css.secondary} onClick={onDone}>
                {changed ? 'Discard' : 'Close'}
              </button>
            </div>
            {propose.error && <p className={css.note}>That didn't go through: {(propose.error as Error).message}</p>}
          </>
        )}
      </div>
    </ScrollArea>
  );
}
