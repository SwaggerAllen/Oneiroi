import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Ask } from '../../api/types';
import { Asks } from './Asks';

const ask = (number: number, kind: 'tool' | 'act', subject: string, decision: Ask['decision'] = null): Ask => ({
  number,
  kind,
  subject,
  why: 'because',
  asked_at: '2026-11-05T20:00:00Z',
  decision,
  note: decision ? 'ok' : null,
  answered_at: decision ? '2026-11-05T21:00:00Z' : null,
});

// agathos-daimon#35: acts approved or declined, tools noted, each with a note.
describe('Asks', () => {
  afterEach(cleanup);

  it('approves an act and notes a tool, each only with a note', () => {
    const onAnswer = vi.fn();
    render(<Asks residentName="Lily" asks={[ask(2, 'act', 'publish the Weng piece'), ask(1, 'tool', 'a calendar'), ask(0, 'act', 'old', 'approve')]} onAnswer={onAnswer} />);
    const approve = screen.getByRole('button', { name: 'Approve' }) as HTMLButtonElement;
    expect(approve.disabled).toBe(true);
    const notes = screen.getAllByLabelText('Your note (required)');
    fireEvent.change(notes[0], { target: { value: 'go ahead' } });
    fireEvent.click(approve);
    expect(onAnswer).toHaveBeenCalledWith(2, 'approve', 'go ahead');
    fireEvent.change(notes[1], { target: { value: 'later' } });
    fireEvent.click(screen.getByRole('button', { name: 'Noted' }));
    expect(onAnswer).toHaveBeenCalledWith(1, 'noted', 'later');
    expect(screen.getByRole('list', { name: 'Answered asks' }).textContent).toContain('#0 old: approve, ok');
  });
});
