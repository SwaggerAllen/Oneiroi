import { useQuery } from '@tanstack/react-query';
import { api, RequestFailed } from '../../api/client';
import { Markdown } from '../chat/Markdown';
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
 * (seshat#76). A thread is one file, read whole. Reading only: what is
 * written here is written in the threads and the charter.
 */
export function HouseRecords({ path }: { path: string }) {
  const push = useShell((s) => s.push);
  const back = useShell((s) => s.back);
  const wide = useWide();
  const tree = <Tree residentId="house" current={path} onOpen={push} source={{ key: FILES, load: api.householdFiles }} />;
  const empty = <div className={css.emptyPage}>Choose a record from the tree.</div>;
  const page = path.startsWith('doc/') ? <HouseDoc path={path.slice(4)} onBack={back} /> : wide ? empty : tree;
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
        {read.data && <Markdown text={strip(read.data.content)} onCite={() => undefined} breaks={path.startsWith('threads/')} />}
      </div>
    </ScrollArea>
  );
}

/** A document's front matter is the record's bookkeeping, not its words. */
function strip(text: string): string {
  return text.startsWith('---\n') ? text.replace(/^---\n[\s\S]*?\n---\n?/, '') : text;
}
