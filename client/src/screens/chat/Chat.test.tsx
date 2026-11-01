import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Chat.stories';
import { Chat } from './Chat';

const { Empty, Conversation, Refusal, BudgetStop, DrewOnOpen, Streaming, PreviewWhole, PreviewUnderTerm, PreviewClosed } =
  composeStories(stories);

describe('Chat', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Empty, Conversation, Refusal, BudgetStop, DrewOnOpen, Streaming, PreviewWhole, PreviewUnderTerm, PreviewClosed]) {
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

  it('the preview renders the server sections whole, and a notice by its note alone', () => {
    render(<PreviewWhole />);
    const items = screen.getAllByRole('listitem');
    expect(items.map((li) => li.querySelector('strong')?.textContent)).toEqual(['prompt', 'index', 'honcho', 'transcript', 'notice']);
    expect(screen.getByText(/Walks to the weir/)).toBeTruthy();
    expect(items[1].querySelector('pre')?.textContent).toContain('#1 2026-10-26 the garden');
    expect(items[4].querySelector('pre')).toBeNull();
    expect(screen.getByText(/to hear first/)).toBeTruthy();
  });

  it('the preview renders the server sections in order: words where sent, the note where withheld', () => {
    render(<PreviewUnderTerm />);
    const items = screen.getAllByRole('listitem');
    expect(items.map((li) => li.querySelector('strong')?.textContent)).toEqual([
      'prompt',
      'SOUL.md',
      'index',
      'honcho',
      'madeleine',
      'transcript',
    ]);
    expect(screen.getByText(/Curious about herons/)).toBeTruthy();
    expect(screen.getByText(/No screen shows it to you yet/)).toBeTruthy();
    expect(screen.getByText(/a preview does not run it/)).toBeTruthy();
    // A withheld section renders no block of words.
    expect(items[0].querySelector('pre')).toBeNull();
    expect(items[1].querySelector('pre')).not.toBeNull();
    expect(screen.getByRole('button', { name: 'Close the preview' })).toBeTruthy();
  });

  it('asks for the preview with the draft as it stands', () => {
    const onPreview = vi.fn();
    render(<Chat residentName="Lily" messages={[]} onSend={() => undefined} onPreview={onPreview} />);
    fireEvent.change(screen.getByLabelText('Message'), { target: { value: 'the heron' } });
    fireEvent.click(screen.getByRole('button', { name: 'What Lily will see next' }));
    expect(onPreview).toHaveBeenCalledWith('the heron');
  });
});
