import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Chat.stories';
import { Chat } from './Chat';

const { Empty, Conversation, Refusal, BudgetStop, DrewOnOpen, Streaming } = composeStories(stories);

describe('Chat', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Empty, Conversation, Refusal, BudgetStop, DrewOnOpen, Streaming]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('shows a refusal in the resident words with no error styling', () => {
    render(<Refusal />);
    const quote = screen.getByText('I would rather not say.');
    expect(quote.tagName).toBe('BLOCKQUOTE');
    expect(screen.queryByText(/error/i)).toBeNull();
  });

  it('sends the draft and clears it; an empty draft cannot be sent', () => {
    const onSend = vi.fn();
    render(<Chat residentName="Lily" messages={[]} onSend={onSend} />);
    const button = screen.getByRole('button', { name: 'Send' }) as HTMLButtonElement;
    expect(button.disabled).toBe(true);
    const input = screen.getByLabelText('Message') as HTMLInputElement;
    fireEvent.change(input, { target: { value: 'hello' } });
    expect(button.disabled).toBe(false);
    fireEvent.click(button);
    expect(onSend).toHaveBeenCalledWith('hello');
    expect(input.value).toBe('');
  });

  it('opens the drew-on inspector over the injections', () => {
    render(<DrewOnOpen />);
    expect(screen.getByText(/the bookmark index under 1500 tokens/, { selector: 'li' })).toBeTruthy();
    expect(screen.getByText('drew on 4 things')).toBeTruthy();
  });
});
