import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { LibraryDocument } from '../../api/types';
import { ScrollArea } from '../shell/ScrollArea';
import { folderKey, ORDERS, saveOrder, savedOrder, shownDate, sortDocs, type RecordsOrder } from './sort';
import * as css from './records.css';

/**
 * The folder tree (ui-structures.md D): each top-level folder is a kind,
 * marked hers or the witness's and whether it waits on him; its settings
 * open from the gear. The database-backed folders join once their
 * readable copies exist (records-in-repo.md).
 */
export function Tree({
  residentId,
  current,
  onOpen,
  onSettings,
  onAdd,
  onPaste,
}: {
  residentId: string;
  current: string;
  onOpen: (path: string) => void;
  onSettings: (kind: string) => void;
  onAdd?: () => void;
  onPaste?: () => void;
}) {
  const library = useQuery({ queryKey: ['resident', residentId, 'records', 'library'], queryFn: () => api.library(residentId) });
  const kinds = useQuery({ queryKey: ['resident', residentId, 'records', 'kinds'], queryFn: () => api.kinds(residentId) });
  const [open, setOpen] = useState<Record<string, boolean>>({});
  // Last written first, unless this device chose otherwise (the witness, 2026-11-11).
  const [order, setOrder] = useState<RecordsOrder>(savedOrder);

  const byKind = new Map<string, LibraryDocument[]>();
  for (const d of library.data?.documents ?? []) byKind.set(d.kind, [...(byKind.get(d.kind) ?? []), d]);
  const entries = new Map((kinds.data?.kinds ?? []).map((k) => [k.kind, k]));
  const waits = new Set((kinds.data?.proposals ?? []).filter((p) => p.agree === null && p.proposed_by === 'resident').map((p) => p.kind));
  const listed = (library.data?.kinds ?? []).filter((k) => (byKind.get(k.kind)?.length ?? 0) > 0 || entries.get(k.kind)?.own);
  const label = (k: { kind: string; label?: string | null }) => k.label || k.kind;
  // Folders follow the files: under a date order, the folder holding the
  // latest (or earliest) change comes first; by name, alphabetically.
  const shelf =
    order === 'name'
      ? listed.slice().sort((a, b) => label(a).localeCompare(label(b)))
      : listed.slice().sort((a, b) => {
          const ka = folderKey(byKind.get(a.kind) ?? [], order);
          const kb = folderKey(byKind.get(b.kind) ?? [], order);
          return (order === 'updated-oldest' ? ka - kb : kb - ka) || label(a).localeCompare(label(b));
        });

  return (
    <ScrollArea label="Records">
      <div className={css.pad}>
        <div className={css.orderRow}>
          <h2 className={css.heading} style={{ margin: 0 }}>
            FOLDERS · KINDS
          </h2>
          <select
            className={css.order}
            value={order}
            aria-label="Sort"
            onChange={(e) => {
              const next = e.target.value as RecordsOrder;
              setOrder(next);
              saveOrder(next);
            }}
          >
            {ORDERS.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </select>
        </div>
        {onAdd && (
          <button type="button" className={css.folder} onClick={onAdd}>
            <span className={css.folderName}>+ Add a document of yours</span>
          </button>
        )}
        {onPaste && (
          <button type="button" className={css.folder} onClick={onPaste}>
            <span className={css.folderName}>+ Paste a conversation</span>
          </button>
        )}
        {library.isPending && <p className={css.note}>Reading the shelves…</p>}
        {shelf.map((k) => {
          const docs = sortDocs(byKind.get(k.kind) ?? [], order);
          const entry = entries.get(k.kind);
          const isOpen = open[k.kind] ?? docs.some((d) => current === `doc/${d.path}`);
          const hers = entry?.created_by === 'resident';
          return (
            <div key={k.kind}>
              <div style={{ display: 'flex', alignItems: 'center' }}>
                <button
                  type="button"
                  className={css.folder}
                  data-hers={hers}
                  aria-expanded={isOpen}
                  onClick={() => setOpen((o) => ({ ...o, [k.kind]: !isOpen }))}
                >
                  <span aria-hidden>{isOpen ? '▾' : '▸'}</span>
                  <span className={css.folderName}>{k.label || k.kind}</span>
                  {waits.has(k.kind) && <span className={css.badgeWaits}>WAITS</span>}
                  <span className={hers ? css.badgeHers : css.badge}>
                    {hers ? 'HERS · ' : ''}
                    {docs.length}
                  </span>
                </button>
                <button type="button" className={css.settings} aria-label={`${k.label || k.kind} folder settings`} onClick={() => onSettings(k.kind)}>
                  ⚙
                </button>
              </div>
              {isOpen &&
                docs.map((d) => (
                  <button
                    key={d.path}
                    type="button"
                    className={css.file}
                    aria-current={current === `doc/${d.path}` ? 'page' : undefined}
                    onClick={() => onOpen(`doc/${d.path}`)}
                  >
                    <span className={css.fileName}>{d.path.split('/').slice(1).join('/') || d.path}</span>
                    {shownDate(d, order) && <span className={css.fileDate}>{shownDate(d, order)}</span>}
                  </button>
                ))}
            </div>
          );
        })}
        {(library.data?.unadopted.length ?? 0) > 0 && (
          <p className={css.note}>{library.data?.unadopted.length} file(s) not yet on a shelf.</p>
        )}
      </div>
    </ScrollArea>
  );
}
