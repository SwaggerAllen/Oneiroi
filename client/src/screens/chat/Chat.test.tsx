import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Chat.stories';
import { Chat } from './Chat';

const { Empty, Conversation, Refusal, BudgetStop, DrewOnOpen, Streaming, PreviewWhole, PreviewUnderTerm, PreviewClosed, ReadOnly } =
  composeStories(stories);

describe('Chat', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Empty, Conversation, Refusal, BudgetStop, DrewOnOpen, Streaming, PreviewWhole, PreviewUnderTerm, PreviewClosed, ReadOnly]) {
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

  it('names the model the last reply was recorded under, and nothing before a reply', () => {
    const { unmount } = render(<Chat residentName="Lily" messages={[]} onSend={vi.fn()} />);
    expect(screen.getByText('Main conversation')).toBeTruthy();
    unmount();
    const at = '2026-11-01T18:00:00Z';
    const reply = (model: string, ref: string) => ({
      session_key: 's1',
      turn_ref: ref,
      role: 'assistant',
      content: 'hi',
      sent_at: at,
      actor: { kind: 'resident', id: 'r1', model },
      refusal: false,
    });
    render(<Chat residentName="Lily" messages={[reply('acme/old-1', 't1'), reply('acme/new-2', 't2')]} onSend={vi.fn()} />);
    expect(screen.getByText('Main conversation · last reply on acme/new-2')).toBeTruthy();
  });

  it('opens the drew-on inspector over the injections', () => {
    render(<DrewOnOpen />);
    // The reason sits inside the section's fold, under its overview line.
    expect(screen.getByText(/the bookmark index under 1500 tokens/, { selector: 'details p' })).toBeTruthy();
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

  it('opens on the overview with every section closed, one opens alone, and Open all and Close all go down and back', () => {
    render(<PreviewWhole />);
    const list = screen.getByRole('list', { name: 'What the next turn is given' });
    const folds = () => Array.from(list.querySelectorAll('details')) as HTMLDetailsElement[];
    expect(folds()).toHaveLength(5);
    expect(folds().every((d) => !d.open)).toBe(true);
    // The overview line is the label and the size, nothing more.
    expect(folds()[1].querySelector('summary')?.textContent).toMatch(/^index · about \d+ tokens$/);
    fireEvent.click(folds()[1].querySelector('summary') as HTMLElement);
    fireEvent(folds()[1], new Event('toggle'));
    expect(folds().map((d) => d.open)).toEqual([false, true, false, false, false]);
    fireEvent.click(screen.getByRole('button', { name: 'Open all' }));
    expect(folds().every((d) => d.open)).toBe(true);
    fireEvent.click(screen.getByRole('button', { name: 'Close all' }));
    expect(folds().every((d) => !d.open)).toBe(true);
  });

  it('the reply inspector opens on the overview too', () => {
    render(<DrewOnOpen />);
    const list = screen.getByRole('list', { name: 'What this reply drew on' });
    const folds = Array.from(list.querySelectorAll('details')) as HTMLDetailsElement[];
    expect(folds.length).toBeGreaterThan(0);
    expect(folds.every((d) => !d.open)).toBe(true);
  });

  it('asks for the preview with the draft as it stands', () => {
    const onPreview = vi.fn();
    render(<Chat residentName="Lily" messages={[]} onSend={() => undefined} onPreview={onPreview} />);
    fireEvent.change(screen.getByLabelText('Message'), { target: { value: 'the heron' } });
    fireEvent.click(screen.getByRole('button', { name: 'What Lily will see next' }));
    expect(onPreview).toHaveBeenCalledWith('the heron');
  });

  it('reads a conversation the server says is not writable: no composer, no preview, the inspector still opens', () => {
    render(<ReadOnly />);
    expect(screen.queryByLabelText('Message')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Send' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'What Lily will see next' })).toBeNull();
    expect(screen.getByText('Claude Code · Oneiroi · read here, answered there')).toBeTruthy();
    expect(screen.getByRole('note').textContent).toMatch(/You reply to Lily there, not here/);
    expect(screen.getByText('drew on 4 things')).toBeTruthy();
    expect(screen.getByRole('list', { name: 'What this reply drew on' }).querySelectorAll('li')).toHaveLength(2);
  });
});
