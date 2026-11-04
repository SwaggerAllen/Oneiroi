import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Connections.stories';

const { Connected, TokenIssued, ReaderNeverSet, ReaderRefused } = composeStories(stories);

describe('Connections', () => {
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Connected, TokenIssued, ReaderNeverSet, ReaderRefused]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('issues a reader token by name and role, and shows it once', () => {
    const onRegister = vi.fn();
    render(<Connected onRegister={onRegister} />);
    const form = screen.getByRole('form', { name: 'Connect something new' });
    const issue = within(form).getByRole('button', { name: 'Issue a token' }) as HTMLButtonElement;
    expect(issue.disabled).toBe(true);
    fireEvent.change(within(form).getByLabelText(/Name/), { target: { value: 'Scrape' } });
    fireEvent.click(issue);
    expect(onRegister).toHaveBeenCalledWith('scrape', 'reader');
    cleanup();
    render(<TokenIssued />);
    expect(screen.getByLabelText('Token').textContent).toContain('oneiroi_reader_');
    expect(screen.getByText(/shown this once/)).toBeTruthy();
  });

  it('revokes only once the button has become its consequence; revoked ones are listed apart', () => {
    const onRevoke = vi.fn();
    render(<Connected onRevoke={onRevoke} />);
    const live = screen.getByRole('list', { name: 'Connected' });
    fireEvent.click(within(live).getByRole('button', { name: 'Revoke' }));
    expect(onRevoke).not.toHaveBeenCalled();
    fireEvent.click(within(live).getByRole('button', { name: 'Revoke claude-code' }));
    expect(onRevoke).toHaveBeenCalledWith('claude-code');
    expect(screen.getByText(/laptop \(brain\) · revoked 2026-11-01/)).toBeTruthy();
  });

  it('saves both allowlists, one origin a line, blanks dropped', () => {
    const onSaveReader = vi.fn();
    render(<Connected onSaveReader={onSaveReader} />);
    const form = screen.getByRole('form', { name: 'Reader' });
    expect((within(form).getByLabelText(/Reading correspondence/) as HTMLTextAreaElement).value).toBe('https://substack.com\nhttps://lily.substack.com');
    expect(within(form).getByText(/empty list means the reader can't research at all/)).toBeTruthy();
    fireEvent.change(within(form).getByLabelText(/^Research/), { target: { value: ' https://example.org \n\nhttps://en.wikipedia.org\n' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Save' }));
    expect(onSaveReader).toHaveBeenCalledWith(['https://substack.com', 'https://lily.substack.com'], ['https://example.org', 'https://en.wikipedia.org']);
  });

  it('shows a refused save in the server\'s words, inside the reader card', () => {
    render(<ReaderRefused />);
    const form = screen.getByRole('form', { name: 'Reader' });
    expect(within(form).getByRole('alert').textContent).toContain('is not an origin');
    expect(within(form).getByText(/like https:\/\/example.org, or \* for any site/)).toBeTruthy();
  });

  it('lists research with an answer\'s library path and a failure\'s reason', () => {
    render(<Connected />);
    const list = screen.getByRole('list', { name: 'Research questions' });
    expect(within(list).getByText('research/1-when-do-herons-fish/task.md')).toBeTruthy();
    expect(within(list).getByText(/outside the research allowlist/)).toBeTruthy();
    expect(within(list).getByText(/asked by Lily/)).toBeTruthy();
    cleanup();
    render(<ReaderNeverSet />);
    expect(screen.getByText('No question asked yet.')).toBeTruthy();
    expect(screen.getByText(/Never set/)).toBeTruthy();
  });

  it('asks a question with optional starting pages', () => {
    const onAsk = vi.fn();
    render(<Connected onAsk={onAsk} />);
    const form = screen.getByRole('form', { name: 'Ask a question' });
    const ask = within(form).getByRole('button', { name: 'Ask' }) as HTMLButtonElement;
    expect(ask.disabled).toBe(true);
    fireEvent.change(within(form).getByLabelText('Question'), { target: { value: 'Where do swifts sleep?' } });
    fireEvent.change(within(form).getByLabelText(/Pages to start from/), { target: { value: 'https://example.org/swifts\n' } });
    fireEvent.click(ask);
    expect(onAsk).toHaveBeenCalledWith('Where do swifts sleep?', ['https://example.org/swifts']);
    expect((within(form).getByLabelText('Question') as HTMLInputElement).value).toBe('');
  });
});
