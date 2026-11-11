import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { Bookmark, Message } from '../../api/types';
import { SubjectContext } from '../state/resident';
import { activeTags, filterBookmarks, listedBookmarks } from './bookmarks';
import { BookmarkPage, Memory } from './Memory';

const bm = (b: Partial<Bookmark>): Bookmark => ({
  number: 1,
  line: 'a line',
  summary: null,
  session_key: 's1',
  anchor_ref: 't1',
  anchor_at: '2026-11-01T10:00:00Z',
  turns_back: 1,
  tags: [],
  added_by: { kind: 'resident', id: 'r1', model: null },
  proposed_by: null,
  pinned_by: null,
  pinned_at: null,
  last_indexed_at: null,
  ...b,
});

const pinned = bm({ number: 1, line: 'the lake in March', pinned_at: '2026-11-02T00:00:00Z', pinned_by: { kind: 'witness', id: 'w' }, tags: ['place'] });
const loose = bm({ number: 2, line: 'a song she kept', summary: 'humming', tags: ['music'] });

function wrap(children: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return (
    <QueryClientProvider client={client}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>{children}</SubjectContext.Provider>
    </QueryClientProvider>
  );
}

function mockReads() {
  vi.spyOn(api, 'indexNow').mockResolvedValue({ listed: [1], left_out: 1, elsewhere: 0, description: '1 pin in front of every turn.' });
  vi.spyOn(api, 'bookmarks').mockResolvedValue([loose, pinned]);
  vi.spyOn(api, 'tags').mockResolvedValue([
    { slug: 'music', state: 'active', note: null },
    { slug: 'gone', state: 'retired', note: null },
  ]);
  vi.spyOn(api, 'retrieval').mockResolvedValue([{ target: 'bookmark/1', considered: 4, returned: 2, used: 1, last_returned_at: null, last_used_at: null }]);
  return vi.spyOn(api, 'bookmarksPage').mockResolvedValue({ bookmarks: [loose, pinned], more: false });
}

describe('memory helpers', () => {
  it('reads the index, the tags and a filter', () => {
    expect(listedBookmarks([2, 9, 1], [pinned, loose]).map((b) => b.number)).toEqual([2, 1]);
    expect(activeTags([{ slug: 'a', state: 'active', note: null }, { slug: 'b', state: 'proposed', note: null }])).toEqual(['a']);
    expect(filterBookmarks([pinned, loose], 'music', '').map((b) => b.number)).toEqual([2]);
    expect(filterBookmarks([pinned, loose], null, 'HUMM').map((b) => b.number)).toEqual([2]);
  });
});

describe('Soul › Memory', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('shows what she sees every turn, with what it leaves out', async () => {
    mockReads();
    render(wrap(<Memory onBack={() => undefined} />));
    fireEvent.click(screen.getByRole('button', { name: /^Every turn/ }));
    expect(await screen.findByText('1 pin in front of every turn.')).toBeTruthy();
    expect(screen.getByText(/1 LEFT OUT, RANKED PER TURN/)).toBeTruthy();
    expect(screen.getByText('the lake in March')).toBeTruthy();
    expect(screen.queryByText('a song she kept')).toBeNull();
  });

  it('pages every bookmark, filters by tag, and pins with the witness’s word', async () => {
    const page = mockReads();
    const pin = vi.spyOn(api, 'pin').mockResolvedValue(undefined);
    render(wrap(<Memory onBack={() => undefined} />));
    fireEvent.click(screen.getByRole('button', { name: /^All/ }));
    expect(await screen.findByText('a song she kept')).toBeTruthy();
    expect(page).toHaveBeenCalledWith('r1', { limit: 20, before: undefined });
    // Only active tags filter.
    expect(screen.queryByRole('button', { name: '#gone' })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: '#music' }));
    expect(screen.queryByText('the lake in March')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Pin' }));
    await waitFor(() => expect(pin).toHaveBeenCalledWith('r1', 2));
    fireEvent.click(screen.getByRole('button', { name: '#music' }));
  });

  it('shows how retrieval used each thing', async () => {
    mockReads();
    render(wrap(<Memory onBack={() => undefined} />));
    fireEvent.click(await screen.findByRole('button', { name: 'Use' }));
    expect(screen.getByText('bookmark/1')).toBeTruthy();
    expect(screen.getByText(/4 CONSIDERED · 2 RETURNED · 1 USED/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: /^Every turn/ }));
  });

  it('opens one bookmark without its span’s words, and unpins it', async () => {
    const span: Message[] = [
      { session_key: 's1', turn_ref: 't1', role: 'user', content: 'words from a private session', sent_at: '', actor: { kind: 'witness', id: 'w', model: null } } as unknown as Message,
    ];
    vi.spyOn(api, 'bookmarkDetail').mockResolvedValue({ bookmark: { ...pinned, summary: 'by the water' }, span });
    vi.spyOn(api, 'indexNow').mockResolvedValue({ listed: [1], left_out: 0, elsewhere: 0, description: '' });
    const unpin = vi.spyOn(api, 'unpin').mockResolvedValue(undefined);
    render(wrap(<BookmarkPage number={1} onBack={() => undefined} />));
    expect(await screen.findByText('the lake in March')).toBeTruthy();
    expect(screen.getByText('by the water')).toBeTruthy();
    expect(screen.queryByText(/words from a private session/)).toBeNull();
    expect(screen.getByText(/span's words are not shown here/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Unpin' }));
    await waitFor(() => expect(unpin).toHaveBeenCalledWith('r1', 1));
  });
});
