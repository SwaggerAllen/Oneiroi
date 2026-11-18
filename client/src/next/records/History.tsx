import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type DocumentVersion } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { BackBar } from './BackBar';
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
  // Publishing (seshat#85): the draft public to the household, and which
  // are after it. A witness publishes his own name-folder's files; hers
  // are hers to publish, and their state shows here.
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const published = versions.data?.published ?? null;
  const all = versions.data?.versions ?? [];
  const publishedAt = published ? all.findIndex((v) => v.commit === published) : -1;
  const yours = !!me.data?.folder && path.startsWith(`human/${me.data.folder}/`);
  const publish = useMutation({
    mutationFn: (commit: string) => api.publishDraft(residentId, path, commit, note.trim()),
    onSuccess: () => {
      setNote('');
      void qc.invalidateQueries({ queryKey: ['resident', residentId, 'records'] });
    },
  });
  const who = (v: DocumentVersion) => (v.actor === null ? null : v.actor.kind === 'resident' ? name : v.actor.kind === 'witness' ? 'you' : v.actor.kind);

  return (
    <ScrollArea label={`History of ${path}`}>
      <div className={css.viewer}>
        <BackBar onBack={onBack} />
        <h1 className={css.title}>History</h1>
        <p className={css.meta}>{path}</p>
        <p className={css.note}>
          {published
            ? `Published to the household at ${published.slice(0, 12)}${yours ? '' : `, by ${name}`}.`
            : yours
              ? 'Not published: only you and those you share it with read it. Publish a draft to make it the household’s.'
              : `Not published to the household.`}
        </p>
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
                  {published && v.commit === published ? ' · published' : ''}
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
                        Revert to this draft
                      </button>
                    </div>
                  )}
                  {yours && v.commit && (
                    <div className={css.restore}>
                      {publishedAt === -1 || all.indexOf(v) < publishedAt ? (
                        <button type="button" className={css.action} disabled={publish.isPending} onClick={() => publish.mutate(v.commit as string)}>
                          Publish this draft
                        </button>
                      ) : (
                        <button type="button" className={css.action} disabled>
                          Already published
                        </button>
                      )}
                    </div>
                  )}
                  {publish.data && publish.variables === v.commit && (
                    <p className={css.note} role="status">
                      Published.
                    </p>
                  )}
                  {publish.error && publish.variables === v.commit && <p className={css.note}>{(publish.error as Error).message}</p>}
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
