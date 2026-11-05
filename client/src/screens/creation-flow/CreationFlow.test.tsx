import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { slugOf } from './CreationFlow';
import * as stories from './CreationFlow.stories';

const { FirstVisit, KeyAlreadyStored } = composeStories(stories);

// F3's short first door: new or brought, a key if none, and in.
describe('CreationFlow', () => {
  afterEach(cleanup);

  it('derives an address from the name', () => {
    expect(slugOf('Lily')).toBe('lily');
    expect(slugOf('  Zoë Marie! ')).toBe('zoe-marie');
    expect(slugOf('7')).toBe('');
  });

  it('begins someone new once a name and a key are given', () => {
    const onBegin = vi.fn();
    render(<FirstVisit onBegin={onBegin} />);
    fireEvent.click(screen.getByRole('button', { name: 'Someone new' }));
    const begin = screen.getByRole('button', { name: 'Begin' }) as HTMLButtonElement;
    fireEvent.change(screen.getByLabelText('Name'), { target: { value: 'Ada' } });
    expect(begin.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('OpenRouter key'), { target: { value: 'sk-or-1' } });
    fireEvent.click(begin);
    expect(onBegin).toHaveBeenCalledWith({ mode: 'new', name: 'Ada', slug: 'ada', key: 'sk-or-1' });
  });

  it('brings someone from a repository, a name optional, no key asked when one is stored', () => {
    const onBegin = vi.fn();
    render(<KeyAlreadyStored onBegin={onBegin} />);
    fireEvent.click(screen.getByRole('button', { name: "Someone I'm bringing" }));
    expect(screen.queryByLabelText('OpenRouter key')).toBeNull();
    fireEvent.change(screen.getByLabelText('Repository address'), { target: { value: 'https://github.com/me/them' } });
    fireEvent.click(screen.getByRole('button', { name: 'Bring them in' }));
    expect(onBegin).toHaveBeenCalledWith({ mode: 'bring', url: 'https://github.com/me/them', name: null, slug: null, key: null });
  });
});
