import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { humanPath } from '../../screens/library/paths';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './records.css';

/**
 * A document of yours, in the folder named for you, human/<name>/
 * (seshat#33, #81): in a resident's records she reads it and never edits
 * it; in the house every member reads it. The first time, it asks the
 * name you go by (gaia#45), which the folder is named for.
 */
export function AddDocument({
  residentId,
  house = false,
  onAdded,
  onBack,
}: {
  residentId: string;
  /** The household's repository rather than a resident's. */
  house?: boolean;
  onAdded: (path: string) => void;
  onBack: () => void;
}) {
  const { name: who } = useSubject();
  const qc = useQueryClient();
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const [name, setName] = useState('');
  const [content, setContent] = useState('');
  const folder = me.data?.folder ?? null;
  const path = folder ? humanPath(name, folder) : null;
  const add = useMutation({
    mutationFn: () =>
      house ? api.householdPost({ kind: 'human', path: path as string, content }).then(() => undefined) : api.writeDocument(residentId, path as string, content).then(() => undefined),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: house ? ['household', 'files'] : ['resident', residentId, 'records'] });
      onAdded(path as string);
    },
  });
  const where = house ? 'the house, where every member reads it' : `${who}'s records, where she reads it and never edits it`;

  return (
    <ScrollArea label="Add a document of yours">
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ Records
        </button>
        <h1 className={css.title}>A document of yours</h1>
        {me.isPending ? (
          <p className={css.note}>Reading…</p>
        ) : folder === null ? (
          <NameFirst />
        ) : (
          <>
            <p className={css.note}>
              It goes in your folder, human/{folder}/, in {where}. You can remove it later.
            </p>
            <input id="add-name" className={css.input} value={name} onChange={(e) => setName(e.target.value)} placeholder="my-substack-post" aria-label="Name" />
            {name.trim() !== '' && <p className={css.meta}>{path ?? 'Letters, digits, dots, dashes and underscores only.'}</p>}
            <textarea id="add-content" className={css.editor} value={content} onChange={(e) => setContent(e.target.value)} aria-label="The document" />
            <div className={css.restore}>
              <button type="button" className={css.action} disabled={!path || !content.trim() || add.isPending} onClick={() => add.mutate()}>
                Add it
              </button>
            </div>
            {add.error && <p className={css.note}>{(add.error as Error).message}</p>}
          </>
        )}
      </div>
    </ScrollArea>
  );
}

/** The name a witness goes by, asked once before their first document (gaia#45). */
function NameFirst() {
  const qc = useQueryClient();
  const [name, setName] = useState('');
  const save = useMutation({
    mutationFn: () => api.nameWitness(name.trim()),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['me'] }),
  });
  return (
    <>
      <p className={css.note}>
        First, the name you go by. Your documents go in a folder named for it, and the household calls you by it. You can change it in Settings.
      </p>
      <input id="witness-name" className={css.input} value={name} onChange={(e) => setName(e.target.value)} placeholder="Andrew" aria-label="Your name" />
      <div className={css.restore}>
        <button type="button" className={css.action} disabled={!name.trim() || save.isPending} onClick={() => save.mutate()}>
          Use this name
        </button>
      </div>
      {save.error && <p className={css.note}>{(save.error as Error).message}</p>}
    </>
  );
}
