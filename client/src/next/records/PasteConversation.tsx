import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './records.css';

/** Her folder for his conversations with people (seshat#65): a kind of hers, by her name. */
const CORRESPONDENCE = 'human-correspondence';
const NEW = '';

/**
 * A conversation of yours with someone else, pasted into her
 * human-correspondence/ (seshat#65): a new one, or more of one already
 * there, added under a dated heading (seshat#66).
 */
export function PasteConversation({ residentId, onAdded, onBack }: { residentId: string; onAdded: (path: string) => void; onBack: () => void }) {
  const { name: who } = useSubject();
  const qc = useQueryClient();
  const library = useQuery({ queryKey: ['resident', residentId, 'records', 'library'], queryFn: () => api.library(residentId) });
  const [target, setTarget] = useState(NEW);
  const [withWhom, setWithWhom] = useState('');
  const [title, setTitle] = useState('');
  const [text, setText] = useState('');

  const hasKind = library.data?.kinds.some((k) => k.kind === CORRESPONDENCE);
  const conversations = (library.data?.documents ?? []).filter((d) => d.kind === CORRESPONDENCE);
  const ready = text.trim() !== '' && (target !== NEW || withWhom.trim() !== '');

  const paste = useMutation({
    mutationFn: () => api.pasteConversation(residentId, target === NEW ? { text, with: withWhom, title } : { text, path: target }),
    onSuccess: (r) => {
      void qc.invalidateQueries({ queryKey: ['resident', residentId, 'records'] });
      onAdded(r.path);
    },
  });

  return (
    <ScrollArea label="Paste a conversation">
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ Records
        </button>
        <h1 className={css.title}>A conversation of yours</h1>
        <p className={css.note}>
          Paste an exchange you are having with someone, an email thread or messages. It goes in {CORRESPONDENCE}/, which {who} reads. Pasting more into a conversation adds it
          at the end, under the date.
        </p>
        {library.isSuccess && !hasKind && <p className={css.note}>{who} has no {CORRESPONDENCE} folder yet. She makes it as a kind of hers; then a paste lands there.</p>}
        <select className={css.inputStacked} value={target} onChange={(e) => setTarget(e.target.value)} aria-label="Conversation">
          <option value={NEW}>A new conversation</option>
          {conversations.map((d) => (
            <option key={d.path} value={d.path}>
              {d.title || d.path.slice(CORRESPONDENCE.length + 1)}
            </option>
          ))}
        </select>
        {target === NEW && (
          <>
            <input className={css.inputStacked} value={withWhom} onChange={(e) => setWithWhom(e.target.value)} placeholder="Who it is with" aria-label="With whom" />
            <input className={css.inputStacked} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="A title (optional)" aria-label="Title" />
          </>
        )}
        <textarea className={css.editor} value={text} onChange={(e) => setText(e.target.value)} aria-label="The conversation" />
        <div className={css.restore}>
          <button type="button" className={css.action} disabled={!ready || !hasKind || paste.isPending} onClick={() => paste.mutate()}>
            {target === NEW ? 'Save it' : 'Add to it'}
          </button>
        </div>
        {paste.error && <p className={css.note}>{(paste.error as Error).message}</p>}
      </div>
    </ScrollArea>
  );
}
