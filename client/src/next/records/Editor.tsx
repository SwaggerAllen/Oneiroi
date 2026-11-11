import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { api, RequestFailed, type Lease } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './records.css';

const RENEW_MS = 60_000;

/**
 * The editor, under a lease (seshat#55; decided by the witness): the
 * lease renews while you write, carrying your draft. Idle past the
 * window, it becomes takeable, never revoked; it is taken only when she
 * is waiting on this file, and then your draft is kept, never lost.
 * Tab switches keep the editor mounted, so the lease survives them.
 */
export function Editor({ residentId, path, onDone }: { residentId: string; path: string; onDone: () => void }) {
  const { name } = useSubject();
  const qc = useQueryClient();
  const read = useQuery({ queryKey: ['resident', residentId, 'records', 'doc', path, 'full'], queryFn: () => api.documentRead(residentId, path) });
  const [text, setText] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const [lease, setLease] = useState<Lease | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [taken, setTaken] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const typed = useRef(Date.now());
  const draft = useRef<string | null>(null);

  useEffect(() => {
    if (text === null && read.data) setText(read.data.content);
  }, [read.data, text]);

  // Hold the lease while the editor is open; renew while writing.
  useEffect(() => {
    let live = true;
    api
      .acquireLease(residentId, path)
      .then((l) => live && setLease(l))
      .catch((e: unknown) => live && setSaid(e instanceof Error ? e.message : 'The lease could not be held.'));
    const timer = window.setInterval(() => {
      // Idle writing doesn't renew: the lease goes takeable on its own clock.
      if (Date.now() - typed.current > RENEW_MS * 2) return;
      api
        .renewLease(residentId, path, draft.current ?? undefined)
        .then((l) => live && setLease(l))
        .catch((e: unknown) => {
          if (!live) return;
          if (e instanceof RequestFailed && e.status === 409) setTaken(e.message);
          else setSaid(e instanceof Error ? e.message : 'The lease could not be renewed.');
        });
    }, RENEW_MS);
    return () => {
      live = false;
      window.clearInterval(timer);
      void api.releaseLease(residentId, path).catch(() => undefined);
    };
  }, [residentId, path]);

  const save = () => {
    if (text === null) return;
    setSaving(true);
    api
      .writeDocument(residentId, path, text, note.trim() || undefined)
      .then(() => {
        void qc.invalidateQueries({ queryKey: ['resident', residentId, 'records'] });
        onDone();
      })
      .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not save.'))
      .finally(() => setSaving(false));
  };

  const changed = text !== null && read.data !== undefined && text !== read.data.content;

  return (
    <ScrollArea label={`Editing ${path}`}>
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onDone}>
          ‹ Done
        </button>
        <h1 className={css.title}>Editing</h1>
        <p className={css.meta}>{path}</p>
        <div className={css.bar} role="status">
          {taken
            ? `${name} needed this file, so the lease was taken. Your draft is kept in your own folder; nothing you wrote is lost.`
            : lease?.waiting_at
              ? `${name} is waiting on this file. Save or close when you can.`
              : lease
                ? 'You hold this file while you write; it renews as you type.'
                : 'Taking the lease…'}
        </div>
        <textarea
          id="editor-text"
          className={css.editor}
          value={text ?? ''}
          disabled={text === null || taken !== null}
          onChange={(e) => {
            setText(e.target.value);
            draft.current = e.target.value;
            typed.current = Date.now();
          }}
          aria-label={`${path}, as it will be`}
        />
        <input id="editor-note" className={css.input} value={note} onChange={(e) => setNote(e.target.value)} placeholder="A note on this change (optional)" aria-label="A note on this change" />
        <div className={css.restore}>
          <button type="button" className={css.action} disabled={!changed || saving || taken !== null} onClick={save}>
            Save
          </button>
          <button type="button" className={css.quiet} onClick={onDone}>
            {changed ? 'Discard' : 'Close'}
          </button>
        </div>
        {said && <p className={css.note}>{said}</p>}
      </div>
    </ScrollArea>
  );
}
