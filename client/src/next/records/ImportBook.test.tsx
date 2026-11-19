import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { ImportBook } from './ImportBook';

function wrap(children: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return (
    <QueryClientProvider client={client}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'scarlett', name: 'Scarlett' }}>{children}</SubjectContext.Provider>
    </QueryClientProvider>
  );
}

describe('importing a book (seshat#98)', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('needs the file and its rights note, sends both, and opens the manifest; her books listed with her place', async () => {
    vi.spyOn(api, 'books').mockResolvedValue({
      books: [{ slug: 'persuasion', title: 'Persuasion', author: 'Jane Austen', rights: 'public-domain', caveat: null, chapters: 24, read: 3, current: '003', read_at: null, imported_at: '2026-11-19T12:00:00Z' }],
      rights: ['public-domain', 'house-shareable', 'purchased-drm-free'],
    });
    const sent = vi.spyOn(api, 'importBook').mockResolvedValue({ slug: 'the-long-field', title: 'The Long Field', author: 'Ada Wren', chapters: 3 });
    const opened = vi.fn();
    render(wrap(<ImportBook residentId="r1" onImported={opened} onBack={() => undefined} />));

    expect(await screen.findByText(/Persuasion, by Jane Austen: read 3 of 24, her place at 003/)).toBeTruthy();
    const button = screen.getByRole('button', { name: 'Import it' });
    expect((button as HTMLButtonElement).disabled).toBe(true);

    const epub = new File(['zip'], 'field.epub', { type: 'application/epub+zip' });
    fireEvent.change(screen.getByLabelText('The EPUB'), { target: { files: [epub] } });
    expect((button as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Rights'), { target: { value: 'public-domain' } });
    fireEvent.click(button);

    await waitFor(() => expect(sent).toHaveBeenCalledWith('r1', epub, 'public-domain', '', 'field.epub'));
    await waitFor(() => expect(opened).toHaveBeenCalledWith('books/the-long-field/manifest.md'));
  });
});
