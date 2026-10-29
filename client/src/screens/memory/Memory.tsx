import { useState } from 'react';
import type { Bookmark, Tag } from '../../api/types';
import { BookmarkCard } from '../../components/BookmarkCard';
import { EmptyState } from '../../components/EmptyState';
import { Tabs } from '../../components/Tabs';
import { TopBar } from '../../components/TopBar';

export interface MemoryProps {
  residentName: string;
  bookmarks: Bookmark[];
  tags: Tag[];
  indexBudget: number;
  onPin?: (number: number) => void;
  onUnpin?: (number: number) => void;
  onOpen?: (bookmark: Bookmark) => void;
}

type TabId = 'index' | 'all' | 'pinned' | `tag:${string}`;

// Memory (spec §10): rows with pin or index marker, the line, when, who
// bookmarked, who pinned, the span, tags; tabs In the index (with the
// budget as a caption), All, Pinned, and one per tag; search.
export function Memory({ residentName, bookmarks, tags, indexBudget, onPin, onUnpin, onOpen }: MemoryProps) {
  const [tab, setTab] = useState<TabId>('index');
  const [query, setQuery] = useState('');
  const active = tags.filter((t) => t.state === 'active');
  const inIndex = bookmarks.filter((b) => b.last_indexed_at !== null);
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
        {tab === 'index' ? (
          <p style={{ margin: 0, fontSize: 12, color: 'var(--ink-faint)' }}>
            Injected every turn under {indexBudget} tokens, a bound; pins take at most half.
          </p>
        ) : null}
      </div>
      <main style={{ flex: 1, padding: '0 var(--space-4)' }}>
        {rows.length === 0 ? (
          <EmptyState text={bookmarks.length === 0 ? `${residentName} has not bookmarked anything yet.` : 'Nothing here.'} />
        ) : (
          rows.map((b) => (
            <BookmarkCard key={b.number} bookmark={b} residentName={residentName} onPin={onPin} onUnpin={onUnpin} onOpen={onOpen} />
          ))
        )}
      </main>
    </div>
  );
}
