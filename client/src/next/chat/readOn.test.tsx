import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, renderHook, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { Message, Session, Transcript } from '../../api/types';
import type { Live } from '../live/live';
import { useChat } from './useChat';

// kumbukumbu#96 (the witness, 2026-11-21): "I can go to a bookmark but I
// can't read the record after the bookmark." A jump reads a window
// around its anchor; reading on loads the pages after it until the
// window meets the newest, when the chat is live again.

const message = (n: number): Message =>
  ({ role: 'user', content: `said ${n}`, turn_ref: `t-${n}`, sent_at: '2026-11-10T12:00:00Z', cursor: `${n}.0` }) as unknown as Message;

const session = { key: 'k' } as unknown as Session;
const transcript = (ns: number[]): Transcript => ({ session, messages: ns.map(message), drew_on: {} });

describe('reading on past a jump', () => {
  afterEach(() => vi.restoreAllMocks());

  it('loads the pages after the window, then returns to the live chat', async () => {
    vi.spyOn(api, 'mainSession').mockResolvedValue({ key: 'k' } as never);
    vi.spyOn(api, 'transcriptPage').mockResolvedValue({ ...transcript([90, 91]), more: true });
    vi.spyOn(api, 'captureFailures').mockResolvedValue([] as never);
    vi.spyOn(api, 'transcriptAround').mockResolvedValue({
      ...transcript([10, 11, 12]),
      anchor: '11.0',
      more_before: true,
      more_after: true,
    });

    const after = vi
      .spyOn(api, 'transcriptAfter')
      .mockResolvedValueOnce({ ...transcript([13, 14]), more: true })
      .mockResolvedValueOnce({ ...transcript([15]), more: false });

    const live = { session: () => () => undefined } as unknown as Live;
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
    const { result } = renderHook(() => useChat('r', live), { wrapper });

    await waitFor(() => expect(result.current.key).toBe('k'));
    await act(() => result.current.jumpTo('t-11'));
    expect(result.current.windowed?.moreAfter).toBe(true);

    await act(() => result.current.loadNewer());
    expect(after).toHaveBeenLastCalledWith('r', 'k', '12.0', 40);
    expect(result.current.messages.map((m) => m.content)).toEqual(['said 10', 'said 11', 'said 12', 'said 13', 'said 14']);

    await act(() => result.current.loadNewer());
    expect(after).toHaveBeenLastCalledWith('r', 'k', '14.0', 40);
    expect(result.current.messages.map((m) => m.content)).toContain('said 15');
    // Met the newest: no longer a window.
    expect(result.current.windowed).toBeNull();
  });
});
