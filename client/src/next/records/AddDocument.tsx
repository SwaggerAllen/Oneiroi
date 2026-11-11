import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { humanPath } from '../../screens/library/paths';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './records.css';

/** A document of yours, under human/ (seshat#33): she reads it; you can remove it later. */
export function AddDocument({ residentId, onAdded, onBack }: { residentId: string; onAdded: (path: string) => void; onBack: () => void }) {
  const { name: who } = useSubject();
  const qc = useQueryClient();
  const [name, setName] = useState('');
  const [content, setContent] = useState('');
  const path = humanPath(name);
  const add = useMutation({
    mutationFn: () => api.writeDocument(residentId, path as string, content),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['resident', residentId, 'records'] });
      onAdded(path as string);
    },
  });
  return (
    <ScrollArea label="Add a document of yours">
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ Records
        </button>
        <h1 className={css.title}>A document of yours</h1>
        <p className={css.note}>It goes in human/, which {who} reads and never edits. You can remove it later.</p>
        <input id="add-name" className={css.input} value={name} onChange={(e) => setName(e.target.value)} placeholder="my-substack-post" aria-label="Name" />
        {name.trim() !== '' && <p className={css.meta}>{path ?? 'Letters, digits, dots, dashes and underscores only.'}</p>}
        <textarea id="add-content" className={css.editor} value={content} onChange={(e) => setContent(e.target.value)} aria-label="The document" />
        <div className={css.restore}>
          <button type="button" className={css.action} disabled={!path || !content.trim() || add.isPending} onClick={() => add.mutate()}>
            Add it
          </button>
        </div>
        {add.error && <p className={css.note}>{(add.error as Error).message}</p>}
      </div>
    </ScrollArea>
  );
}
