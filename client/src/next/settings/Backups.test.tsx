import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api, type ResidentRecord } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { SettingsPage } from './SettingsPage';

const record: ResidentRecord = {
  id: 'r1',
  slug: 'mira',
  name: 'Mira',
  state: 'active',
  first_contact_at: null,
  formation_until: null,
  chat_model: null,
  remote: 'https://github.com/you/mira-records',
  last_backup: { at: '2026-11-14T03:00:00Z', sequence: 412, root: 'abc', commit: '0123456789abcdef' },
};

function page() {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
        <SettingsPage section="backups" onBack={() => undefined} />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('backups, imports and reports', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('shows the remote and its last push, and sets a new one with a token', async () => {
    vi.spyOn(api, 'resident').mockResolvedValue(record);
    vi.spyOn(api, 'reports').mockResolvedValue({ reports: [], strikes: [] });
    const set = vi.spyOn(api, 'setRemote').mockResolvedValue(undefined);
    page();
    expect(await screen.findByText('https://github.com/you/mira-records')).toBeTruthy();
    expect(screen.getByText(/Last push 2026-11-14, through event 412, commit 01234567/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('A new repository URL'), { target: { value: ' https://github.com/you/elsewhere ' } });
    fireEvent.change(screen.getByLabelText('Token (for a private repository)'), { target: { value: 'tok' } });
    fireEvent.click(screen.getByRole('button', { name: 'Change' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('r1', 'https://github.com/you/elsewhere', 'tok'));
    expect(await screen.findByText('Changed.')).toBeTruthy();
  });

  it('sends a ChatGPT export and says what came across', async () => {
    vi.spyOn(api, 'resident').mockResolvedValue({ ...record, remote: null });
    vi.spyOn(api, 'reports').mockResolvedValue({ reports: [], strikes: [] });
    const take = vi
      .spyOn(api, 'importChatgpt')
      .mockResolvedValue({ conversations: 3, messages: 40, context: 1, gaps: 2, report_path: 'system/imports/chatgpt-2026-11-15.md' });
    page();
    expect(await screen.findByText(/No repository set/)).toBeTruthy();
    const zip = new File(['PK'], 'export.zip', { type: 'application/zip' });
    fireEvent.change(screen.getByLabelText('The export (.zip)'), { target: { files: [zip] } });
    fireEvent.click(screen.getByRole('button', { name: 'Bring' }));
    await waitFor(() => expect(take).toHaveBeenCalledWith('r1', zip));
    expect(await screen.findByText(/Brought 3 conversations \(40 messages\); 2 gaps named in system\/imports\/chatgpt-2026-11-15.md/)).toBeTruthy();
  });

  it('reads the ladder with its steps and strikes, and files a report', async () => {
    vi.spyOn(api, 'resident').mockResolvedValue(record);
    vi.spyOn(api, 'reports').mockResolvedValue({
      reports: [
        {
          number: 1,
          by: 'resident',
          text: 'He read my free time.',
          filed_at: '2026-11-10T00:00:00Z',
          state: 'resolved',
          outcome: 'strike',
          resolved_at: '2026-11-12T00:00:00Z',
          resolution_note: 'Confirmed from the receipts.',
          steps: [{ at: '2026-11-11T00:00:00Z', reason: 'Read the receipts' }],
        },
      ],
      strikes: [{ number: 1, report: 1, consequence: 'fine', at: '2026-11-12T00:00:00Z' }],
    });
    const file = vi.spyOn(api, 'fileReport').mockResolvedValue({ number: 2 });
    page();
    expect(await screen.findByText('He read my free time.')).toBeTruthy();
    expect(screen.getByText(/#1, filed 2026-11-10 by Mira · resolved 2026-11-12: a strike/)).toBeTruthy();
    expect(screen.getByText('2026-11-11: Read the receipts')).toBeTruthy();
    expect(screen.getByText(/1 strike: #1 \(report 1, fine, 2026-11-12\)/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('What happened, in your words'), { target: { value: 'Something else.' } });
    fireEvent.click(screen.getByRole('button', { name: 'File a report' }));
    await waitFor(() => expect(file).toHaveBeenCalledWith('r1', 'Something else.'));
    expect(await screen.findByText('Filed as report 2.')).toBeTruthy();
  });
});
