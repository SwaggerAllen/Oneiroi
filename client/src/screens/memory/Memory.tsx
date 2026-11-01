import { useState } from 'react';
import type { Bookmark, IndexNow, Tag } from '../../api/types';
import { BookmarkCard } from '../../components/BookmarkCard';
import { EmptyState } from '../../components/EmptyState';
import { Tabs } from '../../components/Tabs';
import { TopBar } from '../../components/TopBar';

export interface MemoryProps {
  residentName: string;
  bookmarks: Bookmark[];
  tags: Tag[];
  // What the index holds now, as the server built and worded it; null
  // until it has answered.
  index: IndexNow | null;
  onPin?: (number: number) => void;
  onUnpin?: (number: number) => void;
  onOpen?: (bookmark: Bookmark) => void;
}

type TabId = 'index' | 'all' | 'pinned' | `tag:${string}`;

// Memory (spec §10): rows with pin or index marker, the line, when, who
// bookmarked, who pinned, the span, tags; tabs In the index (with the
// server's own description as a caption), All, Pinned, and one per tag;
// search. The index tab lists what the server says the index holds now,
// in its order; the client knows nothing of how the index is built.
export function Memory({ residentName, bookmarks, tags, index, onPin, onUnpin, onOpen }: MemoryProps) {
  const [tab, setTab] = useState<TabId>('index');
  const [query, setQuery] = useState('');
  const active = tags.filter((t) => t.state === 'active');
  const byNumber = new Map(bookmarks.map((b) => [b.number, b]));
  const listed = new Set(index?.listed ?? []);
  const inIndex = (index?.listed ?? []).flatMap((n) => {
    const b = byNumber.get(n);
    return b ? [b] : [];
  });
  const pinned = bookmarks.filter((b) => b.pinned_at !== null);
  const tabs: Array<{ id: TabId; label: string; count?: number }> = [
    { id: 'index', label: 'In the index', count: inIndex.length },
    { id: 'all', label: 'All', count: bookmarks.length },
    { id: 'pinned', label: 'Pinned', count: pinned.length },
    ...active.map((t) => ({ id: `tag:${t.slug}` as TabId, label: t.slug })),
  ];
  const byTab =
    tab === 'index' ? inIndex : tab === 'all' ? bookmarks : tab === 'pinned' ? pinned : bookmarks.filter((b) => b.tags.includes(tab.slice(4)));
  const needle = query.trim().toLowerCase();
  const rows = needle
    ? byTab.filter((b) => b.line.toLowerCase().includes(needle) || (b.summary ?? '').toLowerCase().includes(needle))
    : byTab;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Memory" line={`What ${residentName} chose to keep`} />
      <div style={{ padding: 'var(--space-3) var(--space-4) 0', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
        <input
          aria-label="Search bookmarks"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search bookmarks"
          style={{
            minHeight: 'var(--control-h-sm)',
            padding: '0 var(--space-3)',
            borderRadius: 'var(--radius-md)',
            border: '1px solid var(--hairline)',
            background: 'var(--surface-raised)',
            color: 'var(--ink)',
            fontFamily: 'var(--font-sans)',
            fontSize: 15,
          }}
        />
        <Tabs tabs={tabs} current={tab} onChange={setTab} />
        {tab === 'index' && index ? (
          <p style={{ margin: 0, fontSize: 12, lineHeight: '18px', color: 'var(--ink-faint)', overflowWrap: 'anywhere' }}>
            {index.description}
          </p>
        ) : null}
      </div>
      <main style={{ flex: 1, padding: '0 var(--space-4)' }}>
        {rows.length === 0 ? (
          <EmptyState text={bookmarks.length === 0 ? `${residentName} has not bookmarked anything yet.` : 'Nothing here.'} />
        ) : (
          rows.map((b) => (
            <BookmarkCard
              key={b.number}
              bookmark={b}
              residentName={residentName}
              inIndex={listed.has(b.number)}
              onPin={onPin}
              onUnpin={onUnpin}
              onOpen={onOpen}
            />
          ))
        )}
      </main>
    </div>
  );
}
