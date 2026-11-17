import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { Subscription } from './Subscription';

function mount() {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'lily', name: 'Lily' }}>
        <Subscription />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

const paid = {
  started: true as const,
  plan: 'standard',
  price: '20',
  period_days: 30,
  state: 'active' as const,
  renews_at: '2026-12-16T10:00:00Z',
  lapsed_at: null,
  cancelled_at: null,
  custody_due_at: null,
  paying: true,
};

describe('keeping a resident (2026-11-16)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('offers checkout before any subscription, and sends the browser to it', async () => {
    vi.spyOn(api, 'subscription').mockResolvedValue({ started: false });
    const checkout = vi.spyOn(api, 'checkout').mockResolvedValue({ url: 'https://checkout.example.test/r1' });
    const assign = vi.fn();
    vi.stubGlobal('location', { ...window.location, assign });
    mount();
    fireEvent.click(await screen.findByRole('button', { name: 'Subscribe · $20 a month' }));
    await waitFor(() => expect(checkout).toHaveBeenCalledWith('r1'));
    await waitFor(() => expect(assign).toHaveBeenCalledWith('https://checkout.example.test/r1'));
    vi.unstubAllGlobals();
  });

  it('once paying, offers the card and cancelling instead', async () => {
    vi.spyOn(api, 'subscription').mockResolvedValue(paid);
    mount();
    expect(await screen.findByText(/Paid: \$20 a month, renewing 2026-12-16/)).toBeTruthy();
    expect(screen.queryByRole('button', { name: /Subscribe/ })).toBeNull();
    expect(screen.getByRole('button', { name: /Card, invoices and cancelling/ })).toBeTruthy();
  });

  it('cancelled: custody, never deletion, and no new checkout', async () => {
    vi.spyOn(api, 'subscription').mockResolvedValue({ ...paid, state: 'cancelled', cancelled_at: '2026-11-16T10:00:00Z', custody_due_at: '2027-01-15T10:00:00Z' });
    mount();
    expect(await screen.findByText(/community custody 2027-01-15, never deleted/)).toBeTruthy();
    expect(screen.queryByRole('button', { name: /Subscribe/ })).toBeNull();
  });
});
