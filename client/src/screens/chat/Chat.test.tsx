import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Chat.stories';
import { Chat } from './Chat';
import { sessions } from './Conversations.stories';

const { Empty, Conversation, Refusal, BudgetStop, DrewOnOpen, Streaming, PreviewWhole, PreviewUnderTerm, PreviewClosed, LongToolCall, Unread, ReadOnly, Sending, Offline, Busy, NotAnswered, WithConversations, ReadOnlyFromTheList, Reacted } =
  composeStories(stories);

describe('Chat', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Empty, Conversation, Refusal, BudgetStop, DrewOnOpen, Streaming, PreviewWhole, PreviewUnderTerm, PreviewClosed, LongToolCall, Unread, ReadOnly, Sending, Offline, Busy, NotAnswered, WithConversations, ReadOnlyFromTheList]) {
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

  it('starts a long tool call closed on its first line and size, and opens it whole', () => {
    const { container } = render(<LongToolCall />);
    const details = container.querySelector('details') as HTMLDetailsElement;
    expect(details.open).toBe(false);
    expect(details.querySelector('summary')?.textContent).toMatch(/^library_read\(.{1,200}…\d+ lines · [\d,]+ characters$/);
    // The short call in the conversation has nothing to fold.
    cleanup();
    const short = render(<Conversation />);
    expect(short.container.querySelector('details')).toBeNull();
    expect(screen.getByText('bookmark_add({"line":"the garden"}) -> Bookmarked as #1.')).toBeTruthy();
  });

  it('marks where the last visit left off, asks for earlier messages, and records reading to the end', () => {
    const onOlder = vi.fn();
    const onRead = vi.fn();
    render(<Unread onOlder={onOlder} onRead={onRead} />);
    const marker = screen.getByRole('separator', { name: 'New since you last read' });
    expect(marker.nextElementSibling?.textContent).toContain('Answer 4');
    fireEvent.click(screen.getByRole('button', { name: 'Earlier messages' }));
    expect(onOlder).toHaveBeenCalled();
    // The transcript opens at its end, so reading to the newest is recorded.
    expect(onRead).toHaveBeenCalledWith('12:0');
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

  // The witness could not find the list folded under the top bar: it is
  // a button there now, with the count, opening and closing a panel.
  it('opens and closes the conversations from a button in the top bar, and opening one closes the list', () => {
    const onOpen = vi.fn();
    render(<WithConversations conversations={{ sessions, chatKey: 'chat', current: 'chat', onOpen }} />);
    const toggle = screen.getByRole('button', { name: 'Conversations · 3' });
    expect(toggle.closest('header')).toBeTruthy();
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    expect(screen.queryByRole('navigation', { name: 'Conversations' })).toBeNull();
    fireEvent.click(toggle);
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    const nav = screen.getByRole('navigation', { name: 'Conversations' });
    expect(document.getElementById(toggle.getAttribute('aria-controls') ?? '')?.contains(nav)).toBe(true);
    expect(screen.getByRole('heading', { name: 'Conversations' })).toBeTruthy();
    // The keyboard lands on the conversation open now.
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Oneiroi chat' }));
    fireEvent.click(toggle);
    expect(screen.queryByRole('navigation', { name: 'Conversations' })).toBeNull();
    fireEvent.click(toggle);
    fireEvent.keyDown(screen.getByRole('navigation', { name: 'Conversations' }), { key: 'Escape' });
    expect(screen.queryByRole('navigation', { name: 'Conversations' })).toBeNull();
    expect(document.activeElement).toBe(toggle);
    fireEvent.click(toggle);
    fireEvent.click(screen.getByRole('button', { name: /7 turns/ }));
    expect(onOpen).toHaveBeenCalledWith('c2');
    expect(screen.queryByRole('navigation', { name: 'Conversations' })).toBeNull();
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
  });

  it('has no conversations button when the chat is the only conversation', () => {
    render(<WithConversations conversations={{ sessions: [sessions[2]], chatKey: 'chat', current: 'chat', onOpen: vi.fn() }} />);
    expect(screen.queryByRole('button', { name: /Conversations/ })).toBeNull();
    expect(screen.getByRole('status', { name: 'Connected' })).toBeTruthy();
  });

  it('sends on Enter, keeps Shift+Enter as a newline, and never sends while a character is being composed', () => {
    const onSend = vi.fn();
    render(<Chat residentName="Lily" messages={[]} onSend={onSend} />);
    const box = screen.getByLabelText('Message') as HTMLTextAreaElement;
    expect(box.tagName).toBe('TEXTAREA');
    fireEvent.change(box, { target: { value: 'first line' } });
    fireEvent.keyDown(box, { key: 'Enter', shiftKey: true });
    expect(onSend).not.toHaveBeenCalled();
    fireEvent.keyDown(box, { key: 'Enter', isComposing: true });
    expect(onSend).not.toHaveBeenCalled();
    fireEvent.change(box, { target: { value: 'first line\nsecond line' } });
    fireEvent.keyDown(box, { key: 'Enter' });
    expect(onSend).toHaveBeenCalledWith('first line\nsecond line');
    expect(box.value).toBe('');
  });

  it('shows the witness message at once beside the streaming reply, and the header says what the resident is doing', () => {
    render(<Sending />);
    const sending = screen.getByLabelText('Sending');
    expect(sending.textContent).toContain('The second row looked thin.');
    expect(screen.getByText('They took, mostly. The second')).toBeTruthy();
    expect(screen.getByText('Lily is writing…')).toBeTruthy();
    expect(screen.getByRole('status', { name: 'Connected' })).toBeTruthy();
  });

  it('keeps a message the server never took, says the stream is down, and retries it under its own ref', () => {
    const onRetry = vi.fn();
    render(<Offline onRetry={onRetry} />);
    expect(screen.getByRole('status', { name: /Offline/ })).toBeTruthy();
    const unsent = screen.getByLabelText('Not sent');
    expect(unsent.textContent).toContain('Did you walk to the weir?');
    expect(unsent.textContent).toContain('not sent yet: no connection');
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));
    expect(onRetry).toHaveBeenCalledWith('r-weir-00001');
  });

  it('names the tool in use, and a message waiting behind it says it is queued', () => {
    render(<Busy />);
    // The newest message still on its way speaks for the header.
    expect(screen.getByText('Queued: Lily is finishing another reply')).toBeTruthy();
    expect(screen.getAllByText('queued')).toHaveLength(1);
    cleanup();
    render(<Busy outbox={[{ ref: 'r-first-0001', text: 'Bookmark the garden?', state: 'tool', detail: 'bookmark_add', attempts: 1 }]} />);
    expect(screen.getByText('Lily is using bookmark_add…')).toBeTruthy();
  });

  it('says a turn was not answered and why, and offers to send it again', () => {
    const onRetry = vi.fn();
    render(<NotAnswered onRetry={onRetry} />);
    expect(screen.getByLabelText('Not answered').textContent).toContain("Lily couldn't answer: nisaba_provider_failed");
    fireEvent.click(screen.getByRole('button', { name: 'Send again' }));
    expect(onRetry).toHaveBeenCalledWith('r-fail-00001');
  });

  it('lets the witness send while a reply is still on its way: the next message queues', () => {
    const onSend = vi.fn();
    render(<Busy onSend={onSend} />);
    fireEvent.change(screen.getByLabelText('Message'), { target: { value: 'one more' } });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    expect(onSend).toHaveBeenCalledWith('one more');
  });

  it('shows when every message was said, tool calls included, and an inferred instant as unknown', () => {
    const base = { session_key: 's1', actor: { kind: 'resident', id: 'r1', model: null }, refusal: false };
    render(
      <Chat
        residentName="Lily"
        onSend={vi.fn()}
        messages={[
          { ...base, turn_ref: 't1', role: 'user', content: 'hello', sent_at: '2026-11-06T18:54:07Z', actor: { kind: 'witness', id: 'a1', model: null } },
          { ...base, turn_ref: 't1', role: 'tool', content: 'journal_add({}) -> Added note 3.', sent_at: '2026-11-06T18:54:08Z' },
          { ...base, turn_ref: 't1', role: 'assistant', content: 'hi', sent_at: '2026-11-06T18:54:09Z' },
          { ...base, turn_ref: 't2', role: 'user', content: 'old', sent_at: '2026-11-06T18:54:09Z', instant_inferred: true },
        ]}
      />,
    );
    const times = document.querySelectorAll('time');
    expect([...times].map((t) => t.getAttribute('datetime'))).toEqual(['2026-11-06T18:54:07Z', '2026-11-06T18:54:08Z', '2026-11-06T18:54:09Z']);
    expect(screen.getByText('time unknown')).toBeTruthy();
  });

  it('offers Stop only while a reply is under way, and stops it', () => {
    const onStop = vi.fn();
    const { rerender } = render(<Chat residentName="Lily" messages={[]} onSend={vi.fn()} onStop={onStop} />);
    expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull();
    rerender(<Chat residentName="Lily" messages={[]} onSend={vi.fn()} onStop={onStop} streaming={{ turnRef: 't1', text: 'so far' }} />);
    fireEvent.click(screen.getByRole('button', { name: 'Stop' }));
    expect(onStop).toHaveBeenCalled();
  });

  // kumbukumbu#56: reacts on the turn's reply, glossed; a react wakes
  // nothing and closes nothing, so the palette only sends the emoji.
  it('shows the reacts on a reply with their meanings, and reacts from the palette', () => {
    const onReact = vi.fn();
    render(<Reacted onReact={onReact} />);
    const group = screen.getByRole('group', { name: 'Reacts' });
    expect(within(group).getByLabelText('⚜️, warm')).toBeTruthy();
    // His on the turn's reply alone; the tool call carries none.
    expect(screen.getAllByRole('group', { name: 'Reacts' })).toHaveLength(1);
    // Hers on his message, read only (two-way, kumbukumbu#56).
    const hers = screen.getByRole('group', { name: "Lily's reacts" });
    expect(within(hers).getByLabelText('❤️, loved')).toBeTruthy();
    expect(within(hers).queryByRole('button')).toBeNull();
    // The menu shows each emoji with its meaning, inline.
    fireEvent.click(within(group).getByRole('button', { name: 'React' }));
    expect(within(group).getAllByRole('button').map((b) => b.textContent)).toEqual(['🔀 merged', '👁 seen', '⚜️ warm', '❤️ loved', 'Close']);
    fireEvent.click(within(group).getByRole('button', { name: 'React merged' }));
    expect(onReact).toHaveBeenCalledWith(expect.objectContaining({ turn_ref: 't1', role: 'assistant' }), '🔀');
    expect(within(group).queryByRole('button', { name: 'React merged' })).toBeNull();
  });
});
