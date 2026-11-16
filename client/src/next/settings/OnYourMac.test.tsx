import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { OnYourMac } from './OnYourMac';

function card(slug: string, id: string) {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id, slug, name: 'Wren' }}>
        <OnYourMac />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('on your Mac (dioscuri#8)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('makes the writing room its token and gives the one command, her slug and id in it and never the token', async () => {
    vi.spyOn(api, 'adapters').mockResolvedValue([]);
    const register = vi.spyOn(api, 'registerAdapter').mockResolvedValue({ adapter: 'writing-room', role: 'brain', token: 'tok-123' });
    card('wren', 'r9');
    const room = await screen.findByRole('region', { name: 'Writing room' });
    fireEvent.click(within(room).getByRole('button', { name: 'Set up the writing room' }));
    await waitFor(() => expect(register).toHaveBeenCalledWith('r9', 'writing-room', 'brain'));
    expect(within(room).getByLabelText('Writing room token').textContent).toBe('tok-123');
    const command = within(room).getByLabelText('Writing room command').textContent ?? '';
    expect(command).toBe(`bash <(curl -fsSL ${window.location.origin}/setup.sh) writer --slug wren --resident r9`);
    expect(command).not.toContain('tok-123');
  });

  it("the reader's command carries her handle; one already set up says so and offers to set it up again", async () => {
    vi.spyOn(api, 'adapters').mockResolvedValue([{ adapter: 'scrape', role: 'reader', registered_at: '2026-11-04T10:00:00Z', revoked_at: null }]);
    const register = vi.spyOn(api, 'registerAdapter').mockResolvedValue({ adapter: 'scrape', role: 'reader', token: 'tok-r' });
    card('wren', 'r9');
    const reader = await screen.findByRole('region', { name: 'Reader' });
    expect(await within(reader).findByText(/Set up since/)).toBeTruthy();
    fireEvent.change(within(reader).getByLabelText("Wren's Substack handle (optional)"), { target: { value: 'wrenwrites' } });
    fireEvent.click(within(reader).getByRole('button', { name: 'Set up the reader again' }));
    await waitFor(() => expect(register).toHaveBeenCalledWith('r9', 'scrape', 'reader'));
    expect(within(reader).getByLabelText('Reader command').textContent).toContain("reader --slug wren --resident r9 --substack 'wrenwrites'");
  });
});
