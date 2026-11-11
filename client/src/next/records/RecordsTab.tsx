import { Peek } from '../chat/Peek';
import { documentPath, type Citation } from '../chat/cite';
import { useWide } from '../shell/useWide';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { AddDocument } from './AddDocument';
import { Editor } from './Editor';
import { FolderSettings } from './FolderSettings';
import { History } from './History';
import * as css from './records.css';
import { Tree } from './Tree';
import { Viewer } from './Viewer';

/**
 * The Records tab: its stack's top says what shows (`doc/<path>`,
 * `history/<path>`, `edit/<path>`, `folder/<kind>`, `cite/<kind>/<ref>`,
 * or the tree). On a wide screen
 * the tree stays beside the page; on a phone the page takes the screen
 * and Back pops the stack.
 */
export function RecordsTab({ residentId, path }: { residentId: string; path: string }) {
  const push = useShell((s) => s.push);
  const back = useShell((s) => s.back);
  const go = useShell((s) => s.go);
  const { slug } = useSubject();
  const wide = useWide();

  const openCite = (c: Citation) => {
    const doc = documentPath(c);
    push(doc ? `doc/${doc}` : `cite/${c.kind}/${c.ref}`);
  };
  const tree = <Tree residentId={residentId} current={path} onOpen={push} onSettings={(k) => push(`folder/${k}`)} onAdd={() => push('new')} />;

  // On a wide screen the tree is already beside the page.
  const empty = <div className={css.emptyPage}>Choose a record from the tree.</div>;
  let page = wide ? empty : tree;
  let citation: Citation | null = null;
  if (path.startsWith('doc/')) {
    page = <Viewer residentId={residentId} slug={slug} path={path.slice(4)} onCite={openCite} onOpen={push} onBack={back} onGone={() => go({ tab: 'records', path: '' })} />;
  } else if (path.startsWith('history/')) {
    page = <History residentId={residentId} path={path.slice(8)} onBack={back} />;
  } else if (path === 'new') {
    page = <AddDocument residentId={residentId} onAdded={(p) => push(`doc/${p}`)} onBack={back} />;
  } else if (path.startsWith('edit/')) {
    page = <Editor residentId={residentId} path={path.slice(5)} onDone={back} />;
  } else if (path.startsWith('folder/')) {
    page = <FolderSettings residentId={residentId} kind={path.slice(7)} onBack={back} />;
  } else if (path.startsWith('cite/')) {
    const [kind, ...rest] = path.slice(5).split('/');
    citation = { slug, kind, ref: rest.join('/') };
  }

  return (
    <div className={css.tab}>
      <div className={css.treeColumn}>{tree}</div>
      <div className={css.page}>{page}</div>
      {citation && <Peek residentId={residentId} citation={citation} onClose={back} onOpenFully={openCite} onCite={openCite} />}
    </div>
  );
}
