import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { Ledger } from '../../api/types';
import { SubjectContext } from '../state/resident';
import type { SettingsSection } from '../state/routes';
import { SettingsPage } from './SettingsPage';

function page(section: SettingsSection, onBack = () => undefined) {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
        <SettingsPage section={section} onBack={onBack} />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('settings pages', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('changes a budget line from the line itself', async () => {
    const ledger: Ledger = {
      key: { present: true, stored_at: '2026-11-01T00:00:00Z' },
      purposes: ['chat', 'work'],
      budgets: [{ purpose: 'work', period: 'week', cap: '3.00', spent: '1.10', exceeded: false }],
      spend: { since: '2026-11-01T00:00:00Z', by_purpose: [], by_model: [], by_actor: [] },
    };
    vi.spyOn(api, 'ledger').mockResolvedValue(ledger);
    const set = vi.spyOn(api, 'setBudget').mockResolvedValue(undefined);
    page('ledger');

    expect(await screen.findByText('$1.10 of $3.00 a week')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Change the work line' }));
    fireEvent.change(screen.getByLabelText('Cap in dollars (blank for no limit)'), { target: { value: '4' } });
    fireEvent.click(screen.getByRole('button', { name: 'Set the line' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('r1', 'work', '4', 'week'));
    expect(await screen.findByText('work: $4 a week.')).toBeTruthy();
  });
});
