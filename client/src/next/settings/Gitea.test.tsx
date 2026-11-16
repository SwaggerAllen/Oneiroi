import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { SettingsPage } from './SettingsPage';

function page() {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'lily', name: 'Lily' }}>
        <SettingsPage section="backups" onBack={() => undefined} />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('your repositories on Gitea (2026-11-16)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('names the server, the user and the repositories, and sets a password', async () => {
    vi.spyOn(api, 'gitea').mockResolvedValue({ url: 'https://git.example.test', login: 'w-abc', repositories: ['h-1/house', 'h-1/lily'] });
    const set = vi.spyOn(api, 'setGiteaPassword').mockResolvedValue(undefined);
    page();
    expect(await screen.findByRole('link', { name: 'h-1/lily' })).toBeTruthy();
    expect(screen.getByText('w-abc')).toBeTruthy();
    const form = screen.getByRole('form', { name: 'Set your Gitea password' });
    const field = within(form).getByLabelText('A password for Gitea (twelve characters or more)');
    fireEvent.change(field, { target: { value: 'short' } });
    expect((within(form).getByRole('button', { name: 'Set' }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(field, { target: { value: 'a long password!' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Set' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('a long password!'));
  });

  it('says so before the server is set up', async () => {
    vi.spyOn(api, 'gitea').mockResolvedValue(null);
    page();
    expect(await screen.findByText("The repositories' server is not set up on this platform yet.")).toBeTruthy();
  });
});
