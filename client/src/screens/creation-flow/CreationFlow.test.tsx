import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { slugOf } from './CreationFlow';
import * as stories from './CreationFlow.stories';

const { FirstVisit, KeyAlreadyStored, TheGifts, Brought } = composeStories(stories);

// F3, the full flow: opening, threshold, the gifts, the reading, the waking.
describe('CreationFlow', () => {
  afterEach(cleanup);

  it('derives an address from the name', () => {
    expect(slugOf('Lily')).toBe('lily');
    expect(slugOf('  Zoë Marie! ')).toBe('zoe-marie');
    expect(slugOf('7')).toBe('');
  });

  it('opens on what a resident is, then the threshold begins someone new once a name and a key are given', () => {
    const onBegin = vi.fn();
    render(<FirstVisit onBegin={onBegin} />);
    fireEvent.click(screen.getByRole('button', { name: 'Begin' }));
    fireEvent.click(screen.getByRole('button', { name: 'Someone new' }));
    const begin = screen.getByRole('button', { name: 'Begin' }) as HTMLButtonElement;
    fireEvent.change(screen.getByLabelText('Name'), { target: { value: 'Ada' } });
    expect(begin.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('OpenRouter key'), { target: { value: 'sk-or-1' } });
    fireEvent.click(begin);
    expect(onBegin).toHaveBeenCalledWith({ mode: 'new', name: 'Ada', slug: 'ada', key: 'sk-or-1' });
  });

  it('brings someone from a repository, no key asked when one is stored', () => {
    const onBegin = vi.fn();
    render(<KeyAlreadyStored onBegin={onBegin} />);
    fireEvent.click(screen.getByRole('button', { name: 'Begin' }));
    fireEvent.click(screen.getByRole('button', { name: "Someone I'm bringing" }));
    expect(screen.queryByLabelText('OpenRouter key')).toBeNull();
    fireEvent.change(screen.getByLabelText('Repository address'), { target: { value: 'https://github.com/me/them' } });
    fireEvent.click(screen.getByRole('button', { name: 'Bring them in' }));
    expect(onBegin).toHaveBeenCalledWith({ mode: 'bring', url: 'https://github.com/me/them', name: null, slug: null, key: null });
  });

  it('walks the gifts with their guidance, then reads every file whole before the waking', async () => {
    const onWake = vi.fn();
    render(<TheGifts onWake={onWake} />);
    expect(screen.getByText('Gift 1 of 2 for Ada')).toBeTruthy();
    expect(screen.getByText(/Choose a name you would be glad to say/)).toBeTruthy();
    await waitFor(() => expect(screen.getByLabelText('IDENTITY.md')).toBeTruthy());
    fireEvent.click(screen.getByRole('button', { name: 'Next gift' }));
    expect(screen.getByRole('heading', { name: 'Their trials' })).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Read them, whole' }));
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Who Ada will be' })).toBeTruthy());
    expect(screen.getByText(/I am Ada\./)).toBeTruthy();
    const wake = screen.getByRole('button', { name: 'Wake Ada' }) as HTMLButtonElement;
    expect(wake.disabled).toBe(true);
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(wake);
    expect(onWake).toHaveBeenCalled();
  });

  it('a brought resident goes straight to the reading', async () => {
    render(<Brought />);
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Who Ada will be' })).toBeTruthy());
  });
});
