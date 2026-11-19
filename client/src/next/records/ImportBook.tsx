import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './records.css';

const RIGHTS: Record<string, string> = {
  'public-domain': 'Public domain',
  'house-shareable': 'Shareable in the house',
  'purchased-drm-free': 'Bought, DRM-free (yours to give her, not to share)',
};

/**
 * A book for her library (seshat#98; the witness, 2026-11-19: an upload
 * button, the witness's alone): a DRM-free EPUB and the rights note that
 * is true of it. It lands in books/<slug>/, a chapter a document, and she
 * reads it with book_read; a chapter she has not read stays out of her
 * searches until she does.
 */
export function ImportBook({ residentId, onImported, onBack }: { residentId: string; onImported: (path: string) => void; onBack: () => void }) {
  const { name: who } = useSubject();
  const qc = useQueryClient();
  const books = useQuery({ queryKey: ['resident', residentId, 'records', 'books'], queryFn: () => api.books(residentId) });
  const [file, setFile] = useState<File | null>(null);
  const [rights, setRights] = useState('');
  const [caveat, setCaveat] = useState('');

  const send = useMutation({
    mutationFn: () => api.importBook(residentId, file as File, rights, caveat.trim(), file?.name ?? ''),
    onSuccess: (b) => {
      void qc.invalidateQueries({ queryKey: ['resident', residentId, 'records'] });
      onImported(`books/${b.slug}/manifest.md`);
    },
  });

  return (
    <ScrollArea label="Import a book">
      <div className={css.viewer}>
        <button type="button" className={css.back} onClick={onBack}>
          ‹ Records
        </button>
        <h1 className={css.title}>A book for {who}</h1>
        <p className={css.note}>
          A DRM-free EPUB (not a Kindle file). It goes in books/, a chapter a document, and {who} reads it a chapter at a time. Until she reads a chapter, it stays out of her
          searches, so nothing hands her the ending.
        </p>
        <input className={css.inputStacked} type="file" accept=".epub,application/epub+zip" aria-label="The EPUB" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        <select className={css.inputStacked} value={rights} onChange={(e) => setRights(e.target.value)} aria-label="Rights">
          <option value="">Its rights…</option>
          {(books.data?.rights ?? Object.keys(RIGHTS)).map((r) => (
            <option key={r} value={r}>
              {RIGHTS[r] ?? r}
            </option>
          ))}
        </select>
        <input className={css.inputStacked} value={caveat} onChange={(e) => setCaveat(e.target.value)} placeholder="A caveat about its rights (optional)" aria-label="Caveat" />
        <div className={css.restore}>
          <button type="button" className={css.action} disabled={!file || !rights || send.isPending} onClick={() => send.mutate()}>
            {send.isPending ? 'Importing…' : 'Import it'}
          </button>
        </div>
        {send.error && <p className={css.note}>{(send.error as Error).message}</p>}
        {(books.data?.books.length ?? 0) > 0 && (
          <>
            <h2 className={css.note} style={{ fontWeight: 600 }}>
              Her books
            </h2>
            {books.data?.books.map((b) => (
              <p key={b.slug} className={css.note}>
                {b.title}
                {b.author ? `, by ${b.author}` : ''}: read {b.read} of {b.chapters}
                {b.current ? `, her place at ${b.current}` : ', not started'}
              </p>
            ))}
          </>
        )}
      </div>
    </ScrollArea>
  );
}
