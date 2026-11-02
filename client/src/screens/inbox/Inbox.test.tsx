import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Inbox.stories';
import { letterState } from './letters';

const { Letters, NoLetters, Gate } = composeStories(stories);

describe('Inbox', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Letters, NoLetters, Gate]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('reads where each letter stands off the letters themselves', () => {
    const all = Letters.args.letters ?? [];
    const by = (n: number) => letterState(all.find((l) => l.number === n)!, all);
    expect(by(1)).toEqual({ kind: 'answered', by: 2 });
    expect(by(2)).toEqual({ kind: 'closed', readBy: ['Oneiroi chat'] });
    expect(by(3)).toEqual({ kind: 'waiting', on: 'the next free time', clock: true });
    expect(by(4)).toEqual({ kind: 'in_hand', readBy: ['Claude Code · Lily'] });
    expect(by(5)).toMatchObject({ kind: 'waiting', clock: false });
  });

  it('opens on the open letters, newest first, and shows all on the other tab', () => {
    render(<Letters />);
    const list = () => within(screen.getByRole('region', { name: 'Letters' })).getAllByRole('listitem');
    expect(list().map((li) => li.textContent?.match(/^#(\d+)/)?.[1])).toEqual(['5', '4', '3']);
    expect(screen.getByText('read by Claude Code · Lily, not answered yet')).toBeTruthy();
    expect(screen.getByText('waiting for the next free time')).toBeTruthy();
    expect(screen.getByText('With a keepsake: pocket-andrew.md')).toBeTruthy();
    fireEvent.click(screen.getByRole('tab', { name: 'All 5' }));
    expect(list()).toHaveLength(5);
    expect(screen.getByText('answered in #2')).toBeTruthy();
    expect(screen.getByText('read by Oneiroi chat')).toBeTruthy();
  });

  it('says when nothing needs you, and when there are no letters', () => {
    render(<NoLetters />);
    expect(screen.getByText('Nothing waits on you.')).toBeTruthy();
    expect(screen.getByText('No letters yet.')).toBeTruthy();
  });

  it('lists what waits on you, and decides nothing without a note', () => {
    const onDecideMessage = vi.fn();
    render(<Gate actions={{ onDecideMessage }} />);
    const items = within(screen.getByRole('list', { name: 'Needs you' })).getAllByRole('listitem');
    // Two messages waiting, one reply drafted, one approved to send; the approved message and the sent reply are not here.
    expect(items).toHaveLength(4);
    const first = screen.getByRole('form', { name: 'Decide message 1' });
    const through = within(first).getByRole('button', { name: 'Let it through' }) as HTMLButtonElement;
    expect(through.disabled).toBe(true);
    fireEvent.change(within(first).getByLabelText('Your note to Lily'), { target: { value: 'Grace, from the directory.' } });
    fireEvent.click(within(first).getByRole('checkbox'));
    fireEvent.click(through);
    expect(onDecideMessage).toHaveBeenCalledWith(1, true, 'Grace, from the directory.', true);
  });

  it('never offers to trust a sender the adapter did not verify', () => {
    render(<Gate />);
    const second = screen.getByRole('form', { name: 'Decide message 2' });
    expect((within(second).getByRole('checkbox') as HTMLInputElement).disabled).toBe(true);
    expect(within(second).getByText('Only a verified sender can be trusted')).toBeTruthy();
  });

  it('approves a reply with a note, marks an approved one sent, and stops trusting someone only with a reason', () => {
    const onDecideReply = vi.fn();
    const onMarkSent = vi.fn();
    const onDistrust = vi.fn();
    render(<Gate actions={{ onDecideReply, onMarkSent, onDistrust }} />);
    const draft = screen.getByRole('form', { name: 'Decide reply 1' });
    fireEvent.change(within(draft).getByLabelText('Your note to Lily'), { target: { value: 'Send it.' } });
    fireEvent.click(within(draft).getByRole('button', { name: 'Approve to send' }));
    expect(onDecideReply).toHaveBeenCalledWith(1, true, 'Send it.');
    fireEvent.click(within(screen.getByRole('form', { name: 'Mark reply 2 sent' })).getByRole('button', { name: 'I sent it' }));
    expect(onMarkSent).toHaveBeenCalledWith(2, null);
    const trusted = screen.getByRole('list', { name: 'Trusted people' });
    fireEvent.click(within(trusted).getByRole('button', { name: 'Remove' }));
    const stop = within(trusted).getByRole('button', { name: 'Stop trusting max' }) as HTMLButtonElement;
    expect(stop.disabled).toBe(true);
    fireEvent.change(within(trusted).getByLabelText('Why'), { target: { value: 'Asked to stop.' } });
    fireEvent.click(stop);
    expect(onDistrust).toHaveBeenCalledWith(expect.objectContaining({ identity: 'max' }), 'Asked to stop.');
  });
});
