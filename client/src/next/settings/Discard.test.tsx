import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { SettingsPage } from './SettingsPage';

describe('deleting a resident before their first turn (2026-11-16)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('asks for a note, confirms once in place, then deletes and goes back', async () => {
    const discard = vi.spyOn(api, 'discardResident').mockResolvedValue(undefined);
    const back = vi.fn();
    const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queries}>
        <SubjectContext.Provider value={{ id: 'r2', slug: 'fen', name: 'Fen' }}>
          <SettingsPage section="delete" onBack={back} />
        </SubjectContext.Provider>
      </QueryClientProvider>,
    );

    const button = screen.getByRole('button', { name: 'Delete' }) as HTMLButtonElement;
    expect(button.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Why delete them'), { target: { value: 'made twice' } });
    fireEvent.click(button);
    expect(discard).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Delete Fen for good' }));
    await waitFor(() => expect(discard).toHaveBeenCalledWith('r2', 'made twice'));
    await waitFor(() => expect(back).toHaveBeenCalled());
  });
});
