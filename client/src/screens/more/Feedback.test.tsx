import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { Feedback } from './Feedback';
import { Reports } from './Reports';

// gaia#20: a person reports to the platform team; the operator triages.
describe('Feedback and Reports', () => {
  afterEach(cleanup);

  it('says where it goes, files a problem in the reporter words, and lists their own with status', async () => {
    const onFile = vi.fn(() => Promise.resolve());
    render(<Feedback mine={[{ number: 3, kind: 'feature_request', surface: 'Schedule', body: 'x', trace_id: null, author_kind: 'witness', status: 'in_work', note: 'looking', filed_at: '2026-11-06T18:00:00Z' }]} onFile={onFile} />);
    expect(screen.getByText(/the operator's triage list and Lily/)).toBeTruthy();
    const send = screen.getByRole('button', { name: 'Send to the platform team' }) as HTMLButtonElement;
    expect(send.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('In your words'), { target: { value: 'The card froze.' } });
    fireEvent.change(screen.getByLabelText('Where (a screen, a moment)'), { target: { value: 'Schedule' } });
    fireEvent.click(send);
    expect(onFile).toHaveBeenCalledWith({ kind: 'bug', surface: 'Schedule', body: 'The card froze.', trace_id: null });
    await waitFor(() => expect(screen.getByRole('status').textContent).toBe('Sent to the platform team.'));
    expect(screen.getByRole('list', { name: 'Your reports' }).textContent).toContain('being worked on, "looking"');
  });

  it('shows a report with what the platform logged for its trace id, and moves it with a note', () => {
    const onMove = vi.fn();
    render(
      <Reports
        reports={[{ number: 1, kind: 'bug', surface: 'Schedule', body: 'The card froze.', trace_id: 't-1', author_kind: 'witness', status: 'new', note: null, filed_at: '2026-11-06T18:00:00Z' }]}
        open={{ number: 1, kind: 'bug', surface: 'Schedule', body: 'The card froze.', trace_id: 't-1', author_kind: 'witness', status: 'new', note: null, filed_at: '2026-11-06T18:00:00Z', failures: [{ at: '2026-11-06T18:00:00Z', level: 'error', component: 'sunna', error_kind: 'sunna_x', error_site: 'sunna_y', message: 'boom' }] }}
        onMove={onMove}
      />,
    );
    expect(screen.getByRole('list', { name: 'What the platform logged' }).textContent).toContain('sunna_y: boom');
    fireEvent.change(screen.getByLabelText('A note the reporter reads (required)'), { target: { value: 'fixed' } });
    fireEvent.click(screen.getByRole('button', { name: 'Mark resolved' }));
    expect(onMove).toHaveBeenCalledWith(1, 'resolved', 'fixed');
  });
});
