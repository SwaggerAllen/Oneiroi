import { useState } from 'react';
import type { LibraryDocument, LibraryHit, ShelfKind } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';
import { Tabs } from '../../components/Tabs';
import { TopBar } from '../../components/TopBar';
import { humanPath } from './paths';

export interface LibraryProps {
  residentName: string;
  documents: LibraryDocument[];
  // The kinds in the order they are shown, with their names, as the
  // server's registry gives them (seshat#35).
  shelf?: ShelfKind[];
  // The kind whose list this is ('all' for every document): the route's
  // (#library/<kind>), so each list is its own address. Uncontrolled
  // without it.
  kind?: string;
  onKind?: (kind: string) => void;
  // Opens a document's own page (#doc/<path>).
  onOpen?: (path: string) => void;
  // Adds a document of yours under human/ (seshat#33).
  onAdd?: (name: string, content: string) => void;
  // Removes a scratch or human document; only those are removable.
  onRemove?: (path: string) => void;
  // Moves a document to another path, and so another kind (seshat#39);
  // the server says what may move where.
  onMove?: (from: string, to: string) => void;
  // Searches the words of every document (the library's own index); the
  // passages found, nearest first, or null before any search.
  onSearch?: (query: string) => void;
  hits?: LibraryHit[] | null;
  searching?: boolean;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const row = {
  display: 'flex',
  gap: 'var(--space-2)',
  alignItems: 'flex-end',
  flexWrap: 'wrap',
} as const;
const list = {
  margin: 0,
  padding: 0,
  listStyle: 'none',
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-2)',
} as const;

// The shelf's order and names are the server's (seshat#35): a kind the
// shelf does not name comes last, under its own name. The client knows
// no kind, so a new one, or a resident's own arrangement later, needs no
// change here.
function shelfOf(shelf: ShelfKind[]) {
  const at = new Map(shelf.map((k, i) => [k.kind, { position: i, label: k.label }]));
  return {
    label: (kind: string) => at.get(kind)?.label ?? kind,
    rank: (kind: string) => at.get(kind)?.position ?? shelf.length,
  };
}

// Library (spec §10, screens/library.md): every document the resident's
// library holds, a tab per kind across the top with All first; a find box
// that narrows the tab by title and path as you type, and a search of the
// documents' words through the library's index; keepsakes with why each
// mattered in her words; your own (human/), which you add and remove and
// she reads; scratch, removable when its work is done.
export function Library({ residentName, documents, shelf = [], kind, onKind, onOpen, onAdd, onRemove, onMove, onSearch, hits = null, searching = false }: LibraryProps) {
  const { label, rank } = shelfOf(shelf);
  // Yours is always a tab, so there is somewhere to add the first one.
  const kinds = [...new Set([...documents.map((d) => d.kind), ...(onAdd ? ['human'] : [])])].sort((a, b) => rank(a) - rank(b));
  const [ownTab, setOwnTab] = useState<string>('all');
  const tab = kind ?? ownTab;
  const setTab = onKind ?? setOwnTab;
  const [find, setFind] = useState('');
  const [sort, setSort] = useState<Sort>('updated-desc');
  const needle = find.trim().toLowerCase();
  const inTab = documents.filter((d) => tab === 'all' || d.kind === tab);
  const shown = inTab
    .filter((d) => !needle || (d.title ?? '').toLowerCase().includes(needle) || d.path.toLowerCase().includes(needle))
    .sort(sorter(sort, rank));
  const found = (hits ?? []).filter((h) => tab === 'all' || h.kind === tab);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Library" line={`${documents.length} documents`} />
      <div
        style={{
          padding: 'var(--space-2) var(--space-4) 0',
          borderBottom: '1px solid var(--hairline)',
        }}
      >
        <Tabs
          tabs={[
            { id: 'all', label: 'All', count: documents.length },
            ...kinds.map((k) => ({
              id: k,
              label: label(k),
              count: documents.filter((d) => d.kind === k).length,
            })),
          ]}
          current={tab}
          onChange={setTab}
          wrap
        />
      </div>
      <main
        style={{
          flex: 1,
          padding: 'var(--space-4)',
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--space-4)',
        }}
      >
        <form
          role="search"
          aria-label="Find in the library"
          onSubmit={(e) => {
            e.preventDefault();
            if (onSearch && needle) onSearch(find.trim());
          }}
          style={row}
        >
          <div style={{ flex: 1, minWidth: 0 }}>
            <Field label="Find" value={find} onChange={(e) => setFind(e.target.value)} placeholder="a title, a path, or words to search for" />
          </div>
          {onSearch ? (
            <Button type="submit" disabled={!needle || searching}>
              {searching ? 'Searching…' : 'Search the words'}
            </Button>
          ) : null}
        </form>
        {hits !== null ? (
          <Card title="In the words">
            {found.length === 0 ? (
              <p style={muted}>{searching ? 'Searching…' : 'Nothing found here.'}</p>
            ) : (
              <ul aria-label="In the words" style={list}>
                {found.map((h, i) => (
                  <li
                    key={`${h.path}-${i}`}
                    style={{
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 'var(--space-1)',
                    }}
                  >
                    {onOpen ? (
                      <Button
                        variant="quiet"
                        onClick={() => onOpen(h.path)}
                        style={{
                          alignSelf: 'flex-start',
                          padding: 0,
                          textAlign: 'left',
                        }}
                      >
                        {h.title ?? h.path}
                      </Button>
                    ) : (
                      <span>{h.title ?? h.path}</span>
                    )}
                    <span style={{ fontSize: 13, color: 'var(--ink-muted)' }}>{h.path}</span>
                    <span style={{ fontSize: 14, fontFamily: 'var(--font-serif)' }}>{h.text.length > 220 ? `${h.text.slice(0, 220)}…` : h.text}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        ) : null}
        {documents.length === 0 ? <p style={muted}>Nothing in the library yet.</p> : null}
        {inTab.length > 1 ? (
          <label style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 15 }}>
            Sort by
            <select aria-label="Sort by" value={sort} onChange={(e) => setSort(e.target.value as Sort)} style={{ minHeight: 'var(--control-h)', fontSize: 15 }}>
              {SORTS.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label}
                </option>
              ))}
            </select>
          </label>
        ) : null}
        {shown.length > 0 ? (
          <Card>
            <ul aria-label={tab === 'all' ? 'All documents' : label(tab)} style={{ ...list, gap: 0 }}>
              {shown.map((d, i) => (
                <Doc
                  key={d.path}
                  doc={d}
                  residentName={residentName}
                  kindLabel={tab === 'all' ? label(d.kind) : null}
                  first={i === 0}
                  onOpen={onOpen}
                  onRemove={d.kind === 'scratch' || d.kind === 'human' ? onRemove : undefined}
                  onMove={STAYS.has(d.kind) ? undefined : onMove}
                />
              ))}
            </ul>
          </Card>
        ) : documents.length > 0 && needle ? (
          <p style={muted}>
            No title or path here has “{find.trim()}”.
            {onSearch ? ' Search the words to look inside them.' : ''}
          </p>
        ) : null}
        {onAdd && tab === 'human' ? <AddYours residentName={residentName} onAdd={onAdd} /> : null}
      </main>
    </div>
  );
}

// How a list is ordered (the witness, 2026-11-08, Lily's letter #338):
// by title, or by when a document came in or was last written, either
// way round. Last written, newest first, unless he says otherwise: the
// working library's front page is what was touched lately.
export type Sort = 'updated-desc' | 'updated-asc' | 'created-desc' | 'created-asc' | 'title-asc' | 'title-desc';

const SORTS: { id: Sort; label: string }[] = [
  { id: 'updated-desc', label: 'Updated, newest first' },
  { id: 'updated-asc', label: 'Updated, oldest first' },
  { id: 'created-desc', label: 'Created, newest first' },
  { id: 'created-asc', label: 'Created, oldest first' },
  { id: 'title-asc', label: 'Title, A to Z' },
  { id: 'title-desc', label: 'Title, Z to A' },
];

// A document with no time sorts after every one with one, either way.
function sorter(sort: Sort, rank: (kind: string) => number) {
  const [key, dir] = sort.split('-') as ['updated' | 'created' | 'title', 'asc' | 'desc'];
  const sign = dir === 'asc' ? 1 : -1;
  return (a: LibraryDocument, b: LibraryDocument) => {
    if (key === 'title') return sign * (rank(a.kind) - rank(b.kind) || (a.title ?? a.path).localeCompare(b.title ?? b.path));
    const at = key === 'updated' ? a.written_at : (a.created_at ?? null);
    const bt = key === 'updated' ? b.written_at : (b.created_at ?? null);
    if (!at || !bt) return at ? -1 : bt ? 1 : a.path.localeCompare(b.path);
    return sign * at.localeCompare(bt) || a.path.localeCompare(b.path);
  };
}

// The kinds their systems write, which never move (seshat#39); the
// server refuses them too, and this only spares the button.
const STAYS = new Set(['mail', 'feeds', 'correspondence', 'journal', 'memory', 'originals']);

function Doc({
  doc,
  residentName,
  kindLabel = null,
  first = false,
  onOpen,
  onRemove,
  onMove,
}: {
  doc: LibraryDocument;
  residentName: string;
  kindLabel?: string | null;
  first?: boolean;
  onOpen?: (path: string) => void;
  onRemove?: (path: string) => void;
  onMove?: (from: string, to: string) => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const [moving, setMoving] = useState(false);
  const [to, setTo] = useState(doc.path);
  const name = doc.title ?? doc.path;
  return (
    <li
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-1)',
        fontSize: 15,
        padding: 'var(--space-2) 0',
        borderTop: first ? 'none' : '1px solid var(--hairline)',
      }}
    >
      <span
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          gap: 'var(--space-2)',
        }}
      >
        {onOpen ? (
          <Button variant="quiet" onClick={() => onOpen(doc.path)} style={{ padding: 0, textAlign: 'left' }}>
            {name}
          </Button>
        ) : (
          <span>{name}</span>
        )}
        <span style={{ display: 'flex', gap: 'var(--space-1)', flex: 'none' }}>
          {onMove ? (
            <Button variant="quiet" aria-expanded={moving} onClick={() => setMoving((m) => !m)}>
              {moving ? 'Close' : 'Move'}
            </Button>
          ) : null}
          {onRemove ? (
            <Button variant="quiet" onClick={() => (confirming ? onRemove(doc.path) : setConfirming(true))} onBlur={() => setConfirming(false)}>
              {confirming ? `Remove ${doc.path}` : 'Remove'}
            </Button>
          ) : null}
        </span>
      </span>
      {moving && onMove ? (
        <form
          aria-label={`Move ${doc.path}`}
          onSubmit={(event) => {
            event.preventDefault();
            if (to.trim() && to.trim() !== doc.path) onMove(doc.path, to.trim());
            setMoving(false);
          }}
          style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}
        >
          <Field label="New path (a name alone at the root is a keepsake)" value={to} onChange={(e) => setTo(e.target.value)} />
          <Button variant="primary" type="submit" disabled={to.trim() === '' || to.trim() === doc.path}>
            Move it
          </Button>
        </form>
      ) : null}
      <span style={{ fontSize: 13, color: 'var(--ink-muted)' }}>
        {kindLabel ? `${kindLabel} · ` : ''}
        {doc.path}
        {doc.missing_at ? ' · missing from the repository' : ''}
        {doc.status ? ` · ${doc.status}` : ''}
      </span>
      {doc.kind === 'keepsake' ? (
        <span style={{ fontSize: 14, fontStyle: 'italic' }}>{doc.note ? `${residentName}: “${doc.note}”` : `${residentName} hasn't said why yet.`}</span>
      ) : null}
    </li>
  );
}

// Your own documents (seshat#33): pasted, or read from a text file.
function AddYours({ residentName, onAdd }: { residentName: string; onAdd: (name: string, content: string) => void }) {
  const [name, setName] = useState('');
  const [content, setContent] = useState('');
  const path = humanPath(name);
  return (
    <Card title="Add a document of yours">
      <p style={muted}>For your own writing that belongs nowhere else. {residentName} can read it; only you can change or remove it.</p>
      <form
        aria-label="Add a document of yours"
        onSubmit={(e) => {
          e.preventDefault();
          if (path && content.trim()) {
            onAdd(path, content);
            setName('');
            setContent('');
          }
        }}
        style={{
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--space-2)',
        }}
      >
        <Field label="Name" value={name} onChange={(e) => setName(e.target.value)} placeholder="my-substack-post" />
        <label
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: 'var(--space-1)',
            fontSize: 13,
          }}
        >
          <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Text</span>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={6}
            style={{
              padding: 'var(--space-2) var(--space-3)',
              borderRadius: 'var(--radius-md)',
              border: '1px solid var(--hairline)',
              background: 'var(--surface-raised)',
              color: 'var(--ink)',
              fontFamily: 'var(--font-sans)',
              fontSize: 15,
            }}
          />
        </label>
        <div style={row}>
          <label style={{ fontSize: 13 }}>
            <span style={{ color: 'var(--ink-muted)' }}>Or read a .md or .txt file: </span>
            <input
              type="file"
              accept=".md,.txt,text/markdown,text/plain"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (!file) return;
                void file.text().then((t) => {
                  setContent(t);
                  if (!name) setName(file.name);
                });
              }}
            />
          </label>
          <Button variant="primary" type="submit" disabled={!path || content.trim() === ''}>
            Add {path ?? ''}
          </Button>
        </div>
      </form>
    </Card>
  );
}
