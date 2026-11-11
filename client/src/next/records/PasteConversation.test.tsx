import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { LibraryDocument, LibraryIndex } from '../../api/types';
import { SubjectContext } from '../state/resident';
import { PasteConversation } from './PasteConversation';

const doc = (d: Partial<LibraryDocument>): LibraryDocument => ({
  path: 'human-correspondence/sam.md',
  kind: 'human-correspondence',
  title: 'Sam and the lease',
  status: null,
  bytes: 10,
  versions: 1,
  written_at: null,
  written_by: 'witness',
  missing_at: null,
  note: null,
  ...d,
});

const shelf = (kinds: string[], documents: LibraryDocument[]): LibraryIndex => ({
  kinds: kinds.map((kind, position) => ({ kind, label: kind, position })),
  documents,
  unadopted: [],
});

function wrap(children: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return (
    <QueryClientProvider client={client}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>{children}</SubjectContext.Provider>
    </QueryClientProvider>
  );
}

const done = { path: 'human-correspondence/sam.md', kind: 'human-correspondence', created: true, changed: true, indexed: true };

describe('Records › Paste a conversation', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('starts a new conversation with whom it is with, and opens it', async () => {
    vi.spyOn(api, 'library').mockResolvedValue(shelf(['human', 'human-correspondence'], []));
    const paste = vi.spyOn(api, 'pasteConversation').mockResolvedValue(done);
    const onAdded = vi.fn();
    render(wrap(<PasteConversation residentId="r1" onAdded={onAdded} onBack={() => undefined} />));

    const save = await screen.findByRole('button', { name: 'Save it' });
    fireEvent.change(screen.getByLabelText('The conversation'), { target: { value: 'Sam: Friday?' } });
    expect((save as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('With whom'), { target: { value: 'Sam' } });
    fireEvent.change(screen.getByLabelText('Title'), { target: { value: 'Sam and the lease' } });
    await waitFor(() => expect((save as HTMLButtonElement).disabled).toBe(false));
    fireEvent.click(save);

    await waitFor(() => expect(onAdded).toHaveBeenCalledWith('human-correspondence/sam.md'));
    expect(paste).toHaveBeenCalledWith('r1', { text: 'Sam: Friday?', with: 'Sam', title: 'Sam and the lease' });
  });

  it('adds to a conversation already there, by its path', async () => {
    vi.spyOn(api, 'library').mockResolvedValue(shelf(['human-correspondence'], [doc({}), doc({ path: 'human/mine.md', kind: 'human', title: 'Mine' })]));
    const paste = vi.spyOn(api, 'pasteConversation').mockResolvedValue({ ...done, created: false });
    render(wrap(<PasteConversation residentId="r1" onAdded={() => undefined} onBack={() => undefined} />));

    await screen.findByRole('option', { name: 'Sam and the lease' });
    expect(screen.queryByRole('option', { name: 'Mine' })).toBeNull();
    fireEvent.change(screen.getByLabelText('Conversation'), { target: { value: 'human-correspondence/sam.md' } });
    expect(screen.queryByLabelText('With whom')).toBeNull();
    fireEvent.change(screen.getByLabelText('The conversation'), { target: { value: 'Sam: Signed.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add to it' }));

    await waitFor(() => expect(paste).toHaveBeenCalledWith('r1', { text: 'Sam: Signed.', path: 'human-correspondence/sam.md' }));
  });

  it('says so, and saves nothing, while she has no such folder', async () => {
    vi.spyOn(api, 'library').mockResolvedValue(shelf(['human'], []));
    render(wrap(<PasteConversation residentId="r1" onAdded={() => undefined} onBack={() => undefined} />));

    expect(await screen.findByText(/Mira has no human-correspondence folder yet/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('With whom'), { target: { value: 'Sam' } });
    fireEvent.change(screen.getByLabelText('The conversation'), { target: { value: 'Hi.' } });
    expect((screen.getByRole('button', { name: 'Save it' }) as HTMLButtonElement).disabled).toBe(true);
  });
});
