import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { Card } from '../settings/common';
import * as css from '../settings/settings.css';
import { HousePage } from './common';
import { SHELF, thread as docKey, when } from './keys';

/**
 * The house's records (screen:next-house): its repository's documents
 * (sima-qian#51), BEATS.md and CONTRACT.md, each read whole. The threads
 * are on Chat; the charter's history is on Charter.
 */
export function HouseRecords() {
  const [open, setOpen] = useState<string | null>(null);
  const shelf = useQuery({ queryKey: [...SHELF, 0], queryFn: () => api.householdShelf(0) });
  if (open) return <Doc path={open} onBack={() => setOpen(null)} />;
  const docs = shelf.data?.documents ?? [];
  return (
    <HousePage label="Records" title="Records" lede="The house's repository: its documents, the beats' record and the contract as written, every one a commit under its writer's name.">
      <Card title="The house's own">
        <ul className={css.list} aria-label="The house's files">
          {[
            { path: 'CONTRACT.md', title: 'CONTRACT.md · the charter as written' },
            { path: 'BEATS.md', title: "BEATS.md · the beats' record" },
          ].map((d) => (
            <li key={d.path} className={css.item}>
              <button type="button" className={css.linkButton} onClick={() => setOpen(d.path)}>
                {d.title}
              </button>
            </li>
          ))}
        </ul>
      </Card>
      <Card title="Documents">
        {shelf.isError && <p className={css.note}>The house could not be read.</p>}
        {shelf.data && docs.length === 0 && <p className={css.note}>No documents yet: what the house writes down lands here.</p>}
        <ul className={css.list} aria-label="Documents">
          {docs.map((d) => (
            <li key={d.path} className={css.item}>
              <button type="button" className={css.linkButton} onClick={() => setOpen(d.path)}>
                {d.title}
              </button>
              <p className={css.meta}>
                {d.kind} · {d.path}
                {d.by ? ` · ${d.by}` : ''}
                {d.posted_at ? ` · ${when(d.posted_at)}` : ''}
              </p>
            </li>
          ))}
        </ul>
      </Card>
    </HousePage>
  );
}

function Doc({ path, onBack }: { path: string; onBack: () => void }) {
  const doc = useQuery({ queryKey: docKey(path), queryFn: () => api.householdRead(path) });
  return (
    <HousePage label="Record" title={doc.data?.title ?? path} lede={path}>
      <button type="button" className={css.back} onClick={onBack}>
        ‹ Records
      </button>
      {doc.isError && <p className={css.note}>It could not be read.</p>}
      {doc.data && <pre className={css.pre}>{doc.data.content}</pre>}
    </HousePage>
  );
}
