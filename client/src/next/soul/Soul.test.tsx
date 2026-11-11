import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { Letters } from './Character';
import { FileEdit } from './FileEdit';
import { NoteAction } from './NoteAction';

function wrap(children: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return (
    <QueryClientProvider client={client}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>{children}</SubjectContext.Provider>
    </QueryClientProvider>
  );
}

describe('Soul pages', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('a consent-shaped action goes only with a note', async () => {
    const run = vi.fn(() => Promise.resolve());
    render(wrap(<NoteAction label="Affirm" confirm="Affirm with this note" placeholder="why" run={run} area={['soul']} />));
    fireEvent.click(screen.getByRole('button', { name: 'Affirm' }));
    const go = screen.getByRole('button', { name: 'Affirm with this note' }) as HTMLButtonElement;
    expect(go.disabled).toBe(true);
    fireEvent.change(screen.getByRole('textbox'), { target: { value: '  kept it all week ' } });
    expect(go.disabled).toBe(false);
    fireEvent.click(go);
    await waitFor(() => expect(run).toHaveBeenCalledWith('kept it all week'));
  });

  it('reads her letters only after saying a receipt is left', async () => {
    const read = vi.spyOn(api, 'selfLetters').mockResolvedValue({
      letters: [{ number: 1, text: 'Dear next me', model: null, written_at: '2026-11-01T00:00:00Z', delivered_at: null, delivered_to: null }],
      receipts: [],
    });
    render(wrap(<Letters onBack={() => undefined} />));
    expect(screen.getByText(/leaves a receipt Mira sees/)).toBeTruthy();
    expect(read).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: /Read them/ }));
    expect(await screen.findByText('Dear next me')).toBeTruthy();
    expect(read).toHaveBeenCalledTimes(1);
  });

  it('proposes an identity-file edit with a note, and says it waits on her', async () => {
    vi.spyOn(api, 'files').mockResolvedValue([{ name: 'SOUL.md', content: 'I am.' }]);
    const propose = vi.spyOn(api, 'proposeFile').mockResolvedValue({ ref: 'se-1' });
    render(wrap(<FileEdit file="SOUL.md" onDone={() => undefined} />));
    const text = (await screen.findByDisplayValue('I am.')) as HTMLTextAreaElement;
    const send = screen.getByRole('button', { name: 'Propose to Mira' }) as HTMLButtonElement;
    fireEvent.change(text, { target: { value: 'I am, still.' } });
    expect(send.disabled).toBe(true);
    fireEvent.change(screen.getByRole('textbox', { name: 'Note' }), { target: { value: 'a comma' } });
    fireEvent.click(send);
    expect(await screen.findByText(/Proposed to Mira/)).toBeTruthy();
    expect(propose).toHaveBeenCalledWith('r1', 'SOUL.md', 'I am, still.', 'a comma');
  });
});
