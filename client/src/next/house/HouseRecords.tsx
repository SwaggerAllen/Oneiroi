import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, RequestFailed, type HouseDoc as HouseDocument } from '../../api/client';
import { Markdown } from '../chat/Markdown';
import { AddDocument } from '../records/AddDocument';
import * as css from '../records/records.css';
import { Tree } from '../records/Tree';
import { ScrollArea } from '../shell/ScrollArea';
import { useWide } from '../shell/useWide';
import { useShell } from '../state/store';
import { HOUSE, thread as docKey } from './keys';

const FILES = [...HOUSE, 'files'];

/**
 * The house's Records (screen:next-house; the witness, 2026-11-16: "almost
 * identical to the residents records view, just pointed at a different
 * repo"): the same tree and page, over the household's repository
 * (seshat#76). A thread is one file, read whole. What a witness adds
 * goes in the folder named for them, human/<name>/ (seshat#81); the rest
 * is written in the threads and the charter.
 */
export function HouseRecords({ path }: { path: string }) {
  const push = useShell((s) => s.push);
  const back = useShell((s) => s.back);
  const wide = useWide();
  const tree = <Tree residentId="house" current={path} onOpen={push} onAdd={() => push('new')} source={{ key: FILES, load: api.householdFiles }} />;
  const empty = <div className={css.emptyPage}>Choose a record from the tree.</div>;
  const page = path.startsWith('doc/') ? (
    <HouseDoc path={path.slice(4)} onBack={back} />
  ) : path === 'new' ? (
    <AddDocument residentId="house" house onAdded={(p) => push(`doc/${p}`)} onBack={back} />
  ) : wide ? (
    empty
  ) : (
    tree
  );
  return (
    <div className={css.tab}>
      <div className={css.treeColumn}>{tree}</div>
      <div className={css.page}>{page}</div>
    </div>
  );
}

function HouseDoc({ path, onBack }: { path: string; onBack: () => void }) {
  const read = useQuery({
    queryKey: docKey(path),
    queryFn: () => api.householdRead(path),
    retry: (n, e) => n < 2 && !(e instanceof RequestFailed && e.status === 404),
  });
  const folder = path.includes('/') ? path.split('/')[0] : 'the house';
  return (
    <ScrollArea label={path}>
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ {folder}
        </button>
        <div className={css.meta}>{path}</div>
        <h1 className={css.title}>{read.data?.title ?? path.split('/').pop()?.replace(/\.md$/, '')}</h1>
        {read.isPending && <p className={css.note}>Reading…</p>}
        {read.error && <p className={css.note}>This record couldn't be read.</p>}
        {read.data?.sharing && <Sharing path={path} doc={read.data} />}
        {read.data && !read.data.sharing && <Markdown text={strip(read.data.content)} onCite={() => undefined} breaks={path.startsWith('threads/')} />}
      </div>
    </ScrollArea>
  );
}

/**
 * A house document's sharing (seshat#82): whose it is and its mode, and
 * for whoever may edit (its owner, or anyone while it is open) Edit in
 * place; its owner alone turns it open or back.
 */
function Sharing({ path, doc }: { path: string; doc: HouseDocument }) {
  const qc = useQueryClient();
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const [draft, setDraft] = useState<string | null>(null);
  const sharing = doc.sharing!;
  const mine = !!me.data?.account_id && sharing.owner_id === me.data.account_id;
  const editable = mine || sharing.mode === 'open';
  const save = useMutation({
    mutationFn: (edit: { content?: string; mode?: 'owner' | 'open' }) => api.householdEdit(path, edit),
    onSuccess: () => {
      setDraft(null);
      void qc.invalidateQueries({ queryKey: HOUSE });
    },
  });
  const post = useMutation({
    mutationFn: () => api.householdPost({ doc: path, content: '' }),
    onSuccess: () => void qc.invalidateQueries({ queryKey: HOUSE }),
  });
  const who = sharing.owner_id === null ? 'No owner' : mine ? 'Yours' : sharing.owner ?? 'Its owner';
  const mode = sharing.mode === 'open' ? 'open: every member edits it' : 'only its owner edits it; the others reply with feedback';
  return (
    <>
      <p className={css.note}>
        {who} · {mode}
      </p>
      {draft === null ? (
        <>
          <Markdown text={strip(doc.content)} onCite={() => undefined} />
          {editable && (
            <div className={css.restore}>
              <button type="button" className={css.action} onClick={() => setDraft(strip(doc.content))}>
                Edit
              </button>
              {mine && (
                <button type="button" className={css.action} disabled={save.isPending} onClick={() => save.mutate({ mode: sharing.mode === 'open' ? 'owner' : 'open' })}>
                  {sharing.mode === 'open' ? 'Make it yours alone' : 'Open it to every member'}
                </button>
              )}
            </div>
          )}
        </>
      ) : (
        <>
          <textarea className={css.editor} value={draft} onChange={(e) => setDraft(e.target.value)} aria-label="The document" />
          <div className={css.restore}>
            <button type="button" className={css.action} disabled={!draft.trim() || save.isPending} onClick={() => save.mutate({ content: draft })}>
              Save
            </button>
            <button type="button" className={css.action} onClick={() => setDraft(null)}>
              Cancel
            </button>
          </div>
        </>
      )}
      {save.error && <p className={css.note}>{(save.error as Error).message}</p>}
      <p className={css.note}>
        {(doc.discussed ?? []).length === 0
          ? 'No document post on it yet: feedback on it goes in one.'
          : `Discussed in Chat: ${(doc.discussed ?? []).map((t) => `“${t.title}” (${t.replies === 1 ? '1 reply' : `${t.replies} replies`})`).join(', ')}.`}
      </p>
      <div className={css.restore}>
        <button type="button" className={css.action} disabled={post.isPending} onClick={() => post.mutate()}>
          Start a document post on it
        </button>
      </div>
      {post.error && <p className={css.note}>{(post.error as Error).message}</p>}
    </>
  );
}

/** A document's front matter is the record's bookkeeping, not its words. */
function strip(text: string): string {
  return text.startsWith('---\n') ? text.replace(/^---\n[\s\S]*?\n---\n?/, '') : text;
}
