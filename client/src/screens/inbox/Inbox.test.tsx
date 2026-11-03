import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Inbox.stories';
import { letterState } from './letters';

const { Letters, NoLetters, Gate, Writing } = composeStories(stories);

describe('Inbox', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Letters, NoLetters, Gate, Writing]) {
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

  it('lists only replies as what waits on you, and decides nothing without a note', () => {
    const onDecideReply = vi.fn();
    const onMarkSent = vi.fn();
    render(<Gate actions={{ onDecideReply, onMarkSent }} />);
    // One reply drafted, one approved to send; the sent one is not here.
    expect(within(screen.getByRole('list', { name: 'Needs you' })).getAllByRole('listitem')).toHaveLength(2);
    const draft = screen.getByRole('form', { name: 'Decide reply 1' });
    const approve = within(draft).getByRole('button', { name: 'Approve to send' }) as HTMLButtonElement;
    expect(approve.disabled).toBe(true);
    fireEvent.change(within(draft).getByLabelText('Your note to Lily'), { target: { value: 'Send it.' } });
    fireEvent.click(approve);
    expect(onDecideReply).toHaveBeenCalledWith(1, true, 'Send it.');
    fireEvent.click(within(screen.getByRole('form', { name: 'Mark reply 2 sent' })).getByRole('button', { name: 'I sent it' }));
    expect(onMarkSent).toHaveBeenCalledWith(2, null);
  });

  it('shows the correspondence that reached her, a blocked one as a line with no words, and blocks a sender only with a reason', () => {
    const onBlock = vi.fn();
    render(<Gate actions={{ onBlock }} />);
    const items = within(screen.getByRole('list', { name: 'Correspondence' })).getAllByRole('listitem');
    expect(items[1].textContent).toBe('Message #2 · substack · from troll · 2026-11-02 18:00 UTC · blocked, not kept');
    expect(items[2].textContent).toContain('sender not verified');
    // A sender already blocked has no block button.
    expect(within(items[1]).queryByRole('button')).toBeNull();
    fireEvent.click(within(items[2]).getByRole('button', { name: 'Block sender' }));
    const block = within(items[2]).getByRole('button', { name: 'Block grace@example.com' }) as HTMLButtonElement;
    expect(block.disabled).toBe(true);
    fireEvent.change(within(items[2]).getByLabelText('Why'), { target: { value: 'Spam.' } });
    fireEvent.click(block);
    expect(onBlock).toHaveBeenCalledWith(expect.objectContaining({ number: 1 }), 'Spam.');
  });

  it('lifts only the blocks you set; hers have no button', () => {
    const onUnblock = vi.fn();
    render(<Gate actions={{ onUnblock }} />);
    const rows = within(screen.getByRole('list', { name: 'Blocked' })).getAllByRole('listitem');
    expect(rows[1].textContent).toContain('by Lily: Spam.');
    expect(within(rows[1]).queryByRole('button')).toBeNull();
    fireEvent.click(within(rows[0]).getByRole('button', { name: 'Lift' }));
    fireEvent.change(within(rows[0]).getByLabelText('Why lift it'), { target: { value: 'Settled.' } });
    fireEvent.click(within(rows[0]).getByRole('button', { name: 'Unblock troll' }));
    expect(onUnblock).toHaveBeenCalledWith(expect.objectContaining({ identity: 'troll' }), 'Settled.');
  });

  it('writes a letter, to Free time unless told otherwise', () => {
    const onSendLetter = vi.fn();
    render(<Writing onSendLetter={onSendLetter} />);
    const form = screen.getByRole('form', { name: 'Write a letter' });
    expect((within(form).getByLabelText('To') as HTMLSelectElement).value).toBe('Free time');
    fireEvent.change(within(form).getByLabelText('Letter'), { target: { value: 'Read the scrape pass first.' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Send the letter' }));
    expect(onSendLetter).toHaveBeenCalledWith('Free time', 'Read the scrape pass first.');
  });
});
