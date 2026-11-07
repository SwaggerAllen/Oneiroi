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
    expect(screen.getByText('No replies wait on you.')).toBeTruthy();
    expect(screen.getByText('No letters yet.')).toBeTruthy();
  });

  it('lists everything waiting on you oldest first, marks the long-waiting, and decides nothing itself', () => {
    render(<Gate />);
    const card = screen.getByRole('list', { name: 'Waiting on you' });
    const rows = within(card).getAllByRole('listitem').map((li) => li.textContent);
    expect(rows).toEqual([
      'Lily asks: Post the essay on Noteswaiting 36 hours',
      'Approve or decline Lily’s reply #1 to max on substackwaiting 3 hours',
      'Send reply #2 to max on substack, approvedwaiting 2 hours',
      'Work item #7 blocked on the address to draft from: Re-stage the Jack letterwaiting 2 hours · on the Schedule screen',
    ]);
    // A list to read: the decisions are made where each thing is.
    expect(within(card).queryByRole('button')).toBeNull();
    expect(within(card).getByRole('link', { name: /reply #1/ }).getAttribute('href')).toBe('#reply-1');
  });

  it('marks what the server marks as long, and does nothing else about it', () => {
    const entries = Gate.args.needsYou ?? [];
    render(<Gate now={Date.parse('2026-11-04T00:00:00Z')} needsYou={[{ ...entries[0], long: true }, ...entries.slice(1)]} />);
    const rows = within(screen.getByRole('list', { name: 'Waiting on you' })).getAllByRole('listitem');
    expect(rows[0].textContent).toContain('waiting 2 days, a long time');
    expect(rows[1].textContent).not.toContain('a long time');
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

  it('shows the correspondence by thread with her replies in it, the newest open, and blocks a sender only with a reason', () => {
    const onBlock = vi.fn();
    render(<Gate actions={{ onBlock }} />);
    const list = screen.getByRole('list', { name: 'Correspondence' });
    const threads = within(list).getAllByRole('listitem', { name: /^Thread with/ });
    // Newest activity first; Max's thread holds his two and her three live replies, not the superseded one.
    expect(threads.map((t) => t.getAttribute('aria-label'))).toEqual(['Thread with Max', 'Thread with troll', 'Thread with Grace']);
    expect(threads[0].textContent).toContain('2 from them, 3 from Lily');
    expect(threads[0].textContent).toContain('Earlier in this thread (4)');
    expect(threads[0].textContent).toContain('from Lily (lily) to max');
    expect(threads[0].textContent).not.toContain('An older go.');
    expect(threads[1].textContent).toContain('Message #2 · substack · from troll · 2026-11-02 18:00 UTC · blocked, not kept');
    // A sender already blocked has no block button.
    expect(within(threads[1]).queryByRole('button')).toBeNull();
    const grace = threads[2];
    expect(grace.textContent).toContain('sender not verified');
    fireEvent.click(within(grace).getByRole('button', { name: 'Block sender' }));
    const block = within(grace).getByRole('button', { name: 'Block grace@example.com' }) as HTMLButtonElement;
    expect(block.disabled).toBe(true);
    fireEvent.change(within(grace).getByLabelText('Why'), { target: { value: 'Spam.' } });
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
