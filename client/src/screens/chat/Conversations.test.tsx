import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Conversations.stories';
import { Conversations } from './Conversations';

const { ChatOpen, ClaudeCodeOpen, OnlyTheChat } = composeStories(stories);

describe('Conversations', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [ChatOpen, ClaudeCodeOpen, OnlyTheChat]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('groups the other conversations under the server names, in its order, each a row of its own', () => {
    render(<ChatOpen />);
    const nav = screen.getByRole('navigation', { name: 'Conversations' });
    expect(Array.from(nav.querySelectorAll('h2')).map((h) => h.textContent)).toEqual(['Claude Code · Oneiroi', 'Claude Code · catapult']);
    const oneiroi = screen.getByRole('region', { name: 'Claude Code · Oneiroi' });
    const rows = Array.from(oneiroi.querySelectorAll('li')).map((li) => li.textContent);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatch(/· 7 turns$/);
    expect(rows[1]).toMatch(/· 1 turn$/);
    expect(screen.getByRole('button', { name: 'Oneiroi chat' }).getAttribute('aria-current')).toBe('true');
  });

  it('opens a conversation by its key, and shows nothing when the chat is the only one', () => {
    const onOpen = vi.fn();
    const { unmount } = render(<Conversations sessions={stories.sessions} chatKey="chat" current="chat" onOpen={onOpen} />);
    fireEvent.click(screen.getByRole('button', { name: /2 turns/ }));
    expect(onOpen).toHaveBeenCalledWith('c3');
    unmount();
    const { container } = render(<OnlyTheChat />);
    expect(container.textContent).toBe('');
  });

  it('marks the conversation open and unfolds the list while one is', () => {
    render(<ClaudeCodeOpen />);
    expect(screen.getByRole('button', { name: /7 turns/ }).getAttribute('aria-current')).toBe('true');
    expect((screen.getByText(/Other conversations/).closest('details') as HTMLDetailsElement).open).toBe(true);
  });
});
