import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type DocumentVersion } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './records.css';

const ACT: Record<DocumentVersion['act'], string> = {
  written: 'written',
  adopted: 'adopted',
  moved: 'moved here',
  archived: 'archived',
  tombstone: 'removed',
  committed: 'committed',
};

/**
 * A record's history (seshat#54): every version newest first, with who
 * made it, when, and their note; one opens as a diff against the file
 * now, and can be restored. A restore is a direct write unless the write
 * would need a proposal, when it is filed as one (decided).
 */
export function History({ residentId, path, onBack }: { residentId: string; path: string; onBack: () => void }) {
  const { name } = useSubject();
  const qc = useQueryClient();
  const versions = useQuery({ queryKey: ['resident', residentId, 'records', 'versions', path], queryFn: () => api.versions(residentId, path) });
  const [open, setOpen] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const current = versions.data?.current ?? null;
  const opened = versions.data?.versions.find((v) => v.version === open);
  const diff = useQuery({
    queryKey: ['resident', residentId, 'records', 'diff', path, open],
    queryFn: () => api.diff(residentId, path, open as string),
    // A version's words come from the repository's commits; one written and
    // overwritten between two commits is listed but not held (seshat#54).
    enabled: open !== null && open !== current && opened?.restorable === true,
    retry: false,
  });
  const restore = useMutation({
    mutationFn: (v: string) => api.restore(residentId, path, v, note.trim()),
    onSuccess: () => {
      setNote('');
      void qc.invalidateQueries({ queryKey: ['resident', residentId, 'records'] });
    },
  });
  const who = (v: DocumentVersion) => (v.actor === null ? null : v.actor.kind === 'resident' ? name : v.actor.kind === 'witness' ? 'you' : v.actor.kind);

  return (
    <ScrollArea label={`History of ${path}`}>
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ {path.split('/').pop()}
        </button>
        <h1 className={css.title}>History</h1>
        <p className={css.meta}>{path}</p>
        {versions.isPending && <p className={css.note}>Reading the history…</p>}
        {versions.error && <p className={css.note}>{(versions.error as Error).message}</p>}
        <ol className={css.versions}>
          {versions.data?.versions.map((v, i) => (
            <li key={`${v.version}-${i}`} className={css.version} data-open={open === v.version}>
              <button type="button" className={css.versionHead} onClick={() => setOpen(open === v.version ? null : v.version)} aria-expanded={open === v.version}>
                <span>
                  {ACT[v.act]}
                  {who(v) ? ` by ${who(v)}` : ''}
                  {v.current ? ' · now' : ''}
                </span>
                <span className={css.meta}>{v.at ? new Date(v.at).toLocaleString() : v.committed_at ? new Date(v.committed_at).toLocaleString() : ''}</span>
              </button>
              {v.note && <p className={css.note}>{v.note}</p>}
              {open === v.version && (
                <div className={css.versionBody}>
                  {v.version === current ? (
                    <p className={css.note}>This is the file as it is now.</p>
                  ) : !v.restorable ? (
                    <p className={css.note}>
                      Its words weren't kept: it was overwritten before the repository's next commit, so only who wrote it, when and why remain.
                    </p>
                  ) : diff.error ? (
                    <p className={css.note}>{(diff.error as Error).message}</p>
                  ) : diff.isPending ? (
                    <p className={css.note}>Comparing…</p>
                  ) : diff.data ? (
                    <>
                      <p className={css.meta}>
                        From this version to now: +{diff.data.added} −{diff.data.removed}
                      </p>
                      <pre className={css.diff}>
                        {diff.data.runs.map((r, k) =>
                          r.lines.map((line, j) => (
                            <span key={`${k}-${j}`} className={css.diffLine} data-op={r.op}>
                              {r.op === 'ins' ? '+ ' : r.op === 'del' ? '− ' : '  '}
                              {line}
                              {'\n'}
                            </span>
                          )),
                        )}
                      </pre>
                    </>
                  ) : null}
                  {v.restorable && v.version !== current && (
                    <div className={css.restore}>
                      <input
                        id="restore-note"
                        className={css.input}
                        value={note}
                        onChange={(e) => setNote(e.target.value)}
                        placeholder="Why restore it (optional)"
                        aria-label="Why restore it"
                      />
                      <button type="button" className={css.action} disabled={restore.isPending} onClick={() => restore.mutate(v.version)}>
                        Restore this version
                      </button>
                    </div>
                  )}
                  {restore.data && restore.variables === v.version && (
                    <p className={css.note} role="status">
                      {restore.data.proposed ? `Proposed to ${name}: this file is hers to accept.` : 'Restored.'}
                    </p>
                  )}
                  {restore.error && restore.variables === v.version && <p className={css.note}>{(restore.error as Error).message}</p>}
                </div>
              )}
            </li>
          ))}
        </ol>
      </div>
    </ScrollArea>
  );
}
