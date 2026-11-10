import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import { Markdown } from '../chat/Markdown';
import { targetsFor, type Citation } from '../chat/cite';
import { ScrollArea } from '../shell/ScrollArea';
import * as css from './records.css';

/**
 * A record, read (ui-structures.md D): markdown with her citations as
 * links that open the cited record in this tab's stack, what it cites,
 * and what cites it. History and editing under a lease join with S4.
 */
export function Viewer({
  residentId,
  slug,
  path,
  onCite,
  onOpen,
  onBack,
}: {
  residentId: string;
  slug: string;
  path: string;
  onCite: (c: Citation) => void;
  onOpen: (path: string) => void;
  onBack: () => void;
}) {
  const read = useQuery({
    queryKey: ['resident', residentId, 'records', 'doc', path, 'full'],
    queryFn: () => api.documentRead(residentId, path),
  });
  const targets = targetsFor(slug, path);
  const citedBy = useQuery({
    queryKey: ['resident', residentId, 'records', 'cited-by', path],
    queryFn: () => Promise.all(targets.map((t) => api.citedBy(residentId, t))).then((rows) => rows.flat()),
  });

  const doc = read.data?.document;
  const folder = path.split('/')[0];
  const fromPaths = [...new Set((citedBy.data ?? []).map((r) => r.from_path))];

  return (
    <ScrollArea label={path}>
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ {folder}
        </button>
        <div className={css.meta}>
          {targets[targets.length - 1]}
          {doc ? ` · v${doc.versions}` : ''}
          {doc?.written_at ? ` · ${new Date(doc.written_at).toLocaleString()}` : ''}
          {doc?.written_by ? ` · by ${doc.written_by}` : ''}
        </div>
        <h1 className={css.title}>{doc?.title ?? path.split('/').pop()?.replace(/\.md$/, '')}</h1>
        <div className={css.bar}>
          History and editing under a lease arrive with the documents work (S4).
        </div>
        {read.isPending && <p className={css.note}>Reading…</p>}
        {read.error && <p className={css.note}>This record couldn't be read.</p>}
        {read.data && <Markdown text={read.data.content} onCite={onCite} />}

        {(read.data?.references.length ?? 0) > 0 && (
          <div className={css.links}>
            <span className={css.linksLabel}>CITES</span>
            {read.data?.references.map((r, i) => (
              <button
                key={`${r.target}-${i}`}
                type="button"
                className={css.chip}
                data-broken={!r.resolved}
                title={r.resolved ? (r.label ?? r.target) : (r.reason ?? 'unresolved')}
                onClick={() => onCite({ slug: r.target.split(':')[0], kind: r.kind, ref: r.ref })}
              >
                {r.kind}/{r.ref}
              </button>
            ))}
          </div>
        )}
        {fromPaths.length > 0 && (
          <div className={css.links}>
            <span className={css.linksLabel}>CITED BY</span>
            {fromPaths.map((from) => (
              <button key={from} type="button" className={css.chip} onClick={() => onOpen(`doc/${from}`)}>
                {from}
              </button>
            ))}
          </div>
        )}
      </div>
    </ScrollArea>
  );
}
